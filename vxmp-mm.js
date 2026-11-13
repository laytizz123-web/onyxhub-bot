"use strict";

/*
  KAZUKI MM: single-file Discord bot, Litecoin middleman (escrow) inside tickets.

  SETUP (Windows, in a new empty folder that contains only this file):
    npm init -y
    npm install discord.js dotenv bitcoinjs-lib@6 bip32@4 bip39@3 tiny-secp256k1@2
    node vxmp-mm.js new-seed          -> prints MM_SEED=... (back the 12 words up OFFLINE)
    create a file named .env next to this one:
        DISCORD_TOKEN=...   CLIENT_ID=...   GUILD_ID=...   MM_SEED=...
        optional: MM_STAFF_ROLE_ID  MM_CATEGORY_ID  MM_LOG_CHANNEL_ID  MM_CONFIRMATIONS  MM_MIN_LTC
    node vxmp-mm.js                   -> starts the bot; type /panel in the channel you want
*/

require("dotenv").config({ override: true, quiet: true }); // the .env wins over variables already set on the PC

/* =====================================================
   PART 1: LITECOIN ESCROW ENGINE
===================================================== */
/*
  LITECOIN MIDDLEMAN (escrow) for Discord
  ---------------------------------------
  Node 18+ / discord.js v14 / bitcoinjs-lib v6.

  Flow (everything happens inside a ticket opened with the button of a panel; the person first picks French or English,
  then the range of the amount of the deal (0-25, 25-50...), and the whole ticket stays in that language):
    1. The person who opened the ticket adds the person he trades with (@mention or ID)
    2. Each person picks a role: LTC sender or LTC receiver
    3. The sender enters the amount, the receiver confirms it
    4. The bot gives a deposit address (one per deal, derived from MM_SEED)
       and watches the blockchain until the payment has enough confirmations
    5. The receiver delivers the item/service
    6. The sender clicks "Release" once he got it
    7. The receiver gives his LTC address, the bot sends the funds (minus the network fee)

  Staff can freeze a deal (dispute), force a release, or refund the sender.

  Setup (.env):
    MM_SEED=twelve word mnemonic ...       required, run `node middleman.js new-seed` to make one
    MM_CONFIRMATIONS=2                     confirmations needed (default 2)
    MM_MIN_LTC=0.0001                      smallest deal accepted (about 0.005 USD)
    MM_QR=off                              hide the QR code of the deposit address (default: shown)
    MM_PAYPAL_EMAIL=you@example.com        optional: first PayPal account. Accounts are managed in Discord with /paypal
                                           (add, change, remove, set present / absent), up to 4
    MM_PAYPAL_CURRENCY=USD                 USD or EUR (the currency of your PayPal account)
    MM_PAYPAL_MIN=1                        smallest PayPal deal, in that currency
    MM_PAYPAL_NOTE=text                    extra line shown to the payer (for example "Send as Friends & Family")
    MM_TIERS=0-25,25-50,50-100,100-250,250-500,500-1000,1000-2500,2500+
                                           the FIRST list of amount ranges offered before a ticket opens (min-max, or min+
                                           for "and more"). Afterwards the ranges live in Discord: /tiers lets an
                                           administrator add, edit, remove them and give each one a staff role.
                                           The amount typed in the ticket must fit its range. "off" starts without ranges
    MM_TIER_CURRENCY=USD                   USD or EUR, the currency of those ranges
    TOOLS=off                              switch the multitools off (levels, moderation, welcome, roles, fun, logs, security)
    TOOLS_LANG=fr                          fr (default) or en: language of the multitools
    (multitools need "Message Content Intent" and "Server Members Intent" switched on in the Developer Portal, Bot tab)
    MM_STAFF_ROLE_ID=...                   sees and handles EVERY ticket (a range role only sees the tickets of its range)
    MM_CATEGORY_ID=...                     category where the deal channels are created (optional)
    LTC_API_URL=https://litecoinspace.org/api    Esplora-compatible API (default)
    LTC_EXPLORER_TX_URL=https://litecoinspace.org/tx/
    MM_POLL_SECONDS=30  MM_MIN_FEE_RATE=2

  SECURITY: MM_SEED controls every deposit address. Keep it out of git, keep the host private, and do
  not leave large amounts on it: it is a hot wallet. Back the seed up offline.
*/
const middleman = (() => {

  const fs = require("fs");
  const path = require("path");
  const bitcoin = require("bitcoinjs-lib");
  const ecc = require("tiny-secp256k1");
  const { BIP32Factory } = require("bip32");
  const bip39 = require("bip39");
  const {
    ActionRowBuilder,
    ButtonBuilder,
    ButtonStyle,
    EmbedBuilder,
    MessageFlags,
    ModalBuilder,
    PermissionFlagsBits,
    RoleSelectMenuBuilder,
    UserSelectMenuBuilder,
    StringSelectMenuBuilder,
    TextInputBuilder,
    TextInputStyle,
  } = require("discord.js");

  bitcoin.initEccLib(ecc);
  const bip32 = BIP32Factory(ecc);

  /* =====================================================
     CONFIG
  ===================================================== */

  const LITECOIN = {
    messagePrefix: "\x19Litecoin Signed Message:\n",
    bech32: "ltc",
    bip32: { public: 0x019da462, private: 0x019d9cfe },
    pubKeyHash: 0x30,
    scriptHash: 0x32,
    wif: 0xb0,
  };

  const SAT_PER_LTC = 100000000;
  const DUST_SAT = 1000;
  const MAX_FEE_SHARE = 0.1; // refuse to send when the fee would eat more than 10% of the funds

  function ltcToSat(text) {
    const clean = String(text ?? "").trim().replace(",", ".");
    if (!/^\d{1,8}(\.\d{1,8})?$/.test(clean)) return null;
    const [whole, frac = ""] = clean.split(".");
    return Number(whole) * SAT_PER_LTC + Number(frac.padEnd(8, "0"));
  }

  function satToLtc(sat) {
    return (sat / SAT_PER_LTC).toFixed(8).replace(/0+$/, "").replace(/\.$/, ".0");
  }

  /* MM_SEED may have been pasted on several lines in the .env: join the lines that follow it. */
  function readSeed() {
    const fromEnv = process.env.MM_SEED || "";
    try {
      const lines = fs.readFileSync(path.join(process.cwd(), ".env"), "utf8").replace(/^\uFEFF/, "").split(/\r?\n/);
      const i = lines.findIndex((l) => /^\s*MM_SEED\s*=/.test(l));
      if (i < 0) return fromEnv;
      let text = lines[i].replace(/^\s*MM_SEED\s*=/, "");
      for (let j = i + 1; j < lines.length; j++) {
        const line = lines[j];
        if (!line.trim() || /^\s*#/.test(line) || /^\s*[A-Za-z_][A-Za-z0-9_]*\s*=/.test(line)) break;
        text += " " + line;
      }
      return text;
    } catch {
      return fromEnv;
    }
  }

  /* "0-25,25-50,500+"  ->  [{ min, max }]   (max is null for "and more"). "off" gives no ranges at all. */
  function parseTiers(text) {
    const raw = String(text ?? "0-25,25-50,50-100,100-250,250-500,500-1000,1000-2500,2500+").trim();
    if (/^(off|none|no|false)$/i.test(raw)) return [];
    const out = [];
    for (const part of raw.split(",")) {
      const m = part.trim().match(/^(\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?)|(\+))$/);
      if (!m) continue;
      const min = Number(m[1]);
      const max = m[3] ? null : Number(m[2]);
      if (max !== null && max <= min) continue;
      out.push({ min, max });
    }
    if (!out.length && text !== undefined) return parseTiers(undefined); // nothing valid: back to the defaults
    return out.slice(0, 25);
  }

  const cfg = {
    seed: readSeed().replace(/["'`]/g, " ").replace(/\s+/g, " ").trim().toLowerCase(),
    apiUrl: (process.env.LTC_API_URL || "https://litecoinspace.org/api").replace(/\/+$/, ""),
    explorerTx: process.env.LTC_EXPLORER_TX_URL || "https://litecoinspace.org/tx/",
    confirmations: Math.max(1, Number(process.env.MM_CONFIRMATIONS) || 2),
    pollMs: Math.max(10, Number(process.env.MM_POLL_SECONDS) || 30) * 1000,
    minFeeRate: Math.max(1, Number(process.env.MM_MIN_FEE_RATE) || 2),
    minSat: ltcToSat(process.env.MM_MIN_LTC || "0.0001") || 10000,
    categoryId: process.env.MM_CATEGORY_ID || "",
    qr: String(process.env.MM_QR || "on").toLowerCase() !== "off", // QR code of the deposit address (image made by api.qrserver.com)
    paypalEmail: (process.env.MM_PAYPAL_EMAIL || "").trim(),
    paypalCurrency: String(process.env.MM_PAYPAL_CURRENCY || "USD").trim().toUpperCase() === "EUR" ? "EUR" : "USD",
    paypalMinCents: Math.round((Number(process.env.MM_PAYPAL_MIN) || 1) * 100),
    paypalNote: (process.env.MM_PAYPAL_NOTE || "").trim(),
    tiersEnv: process.env.MM_TIERS,
    tierCurrency: String(process.env.MM_TIER_CURRENCY || "USD").trim().toUpperCase() === "EUR" ? "EUR" : "USD",
  };

  const DATA_FILE = path.join(process.env.DATA_DIR || __dirname, "middleman.json");

  /* =====================================================
     WALLET (HD, BIP84, coin type 2 = Litecoin)
  ===================================================== */

  let root = null;

  function initWallet() {
    if (!bip39.validateMnemonic(cfg.seed)) {
      const words = cfg.seed ? cfg.seed.split(" ").length : 0;
      throw new Error(`MM_SEED is not valid (${words} word(s) found, it must be the 12 words from "new-seed", on one line, spelled exactly).`);
    }
    root = bip32.fromSeed(bip39.mnemonicToSeedSync(cfg.seed), LITECOIN);
  }

  function deriveNode(index) {
    return root.derivePath(`m/84'/2'/0'/0/${index}`);
  }

  function addressOf(index) {
    const node = deriveNode(index);
    return bitcoin.payments.p2wpkh({ pubkey: node.publicKey, network: LITECOIN }).address;
  }

  function isValidLtcAddress(address) {
    try {
      bitcoin.address.toOutputScript(String(address).trim(), LITECOIN);
      return true;
    } catch {
      return false;
    }
  }

  /* =====================================================
     BLOCKCHAIN API (Esplora compatible)
  ===================================================== */

  async function api(pathname, options = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const res = await fetch(cfg.apiUrl + pathname, { ...options, signal: controller.signal });
      const text = await res.text();
      if (!res.ok) throw new Error(`Blockchain API ${res.status}: ${text.slice(0, 200)}`);
      return text;
    } finally {
      clearTimeout(timer);
    }
  }

  const apiJson = async (pathname) => JSON.parse(await api(pathname));

  /* ---------- amounts typed as money: "0.01$", "$5", "5 usd", "5€", "5 eur" (or plain LTC: "0.25", "0.25 ltc") ---------- */

  async function fetchJson(url) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);
    try {
      const res = await fetch(url, { signal: controller.signal, headers: { Accept: "application/json" } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }

  let priceCache = { at: 0, usd: 0, eur: 0 };

  /* Current LTC price in USD and EUR (cached 60 s). Two public sources, no key needed. */
  async function getLtcPrice() {
    if (priceCache.usd && Date.now() - priceCache.at < 60000) return priceCache;
    const sources = [
      async () => {
        const [usd, eur] = await Promise.all(
          ["USD", "EUR"].map(async (c) => Number((await fetchJson(`https://api.coinbase.com/v2/prices/LTC-${c}/spot`)).data.amount))
        );
        return { usd, eur };
      },
      async () => {
        const j = await fetchJson("https://api.coingecko.com/api/v3/simple/price?ids=litecoin&vs_currencies=usd,eur");
        return { usd: Number(j.litecoin.usd), eur: Number(j.litecoin.eur) };
      },
    ];
    let lastError = null;
    for (const source of sources) {
      try {
        const price = await source();
        const ok = (n) => Number.isFinite(n) && n > 1 && n < 100000; // sanity check
        if (ok(price.usd) && ok(price.eur)) {
          priceCache = { at: Date.now(), ...price };
          return priceCache;
        }
        lastError = new Error("implausible price");
      } catch (error) {
        lastError = error;
      }
    }
    throw new Error(`Could not get the LTC price (${lastError?.message || "unknown error"}).`);
  }

  /* "0.25" / "0.25 ltc" -> LTC; "0.01$" "$0.01" "0.01 usd" -> dollars; "0.01€" "0.01 eur" -> euros. */
  function parseAmountInput(text) {
    const raw = String(text || "").trim().toLowerCase().replace(",", ".");
    const number = raw.match(/\d+(?:\.\d+)?/)?.[0];
    if (!number) return null;
    const rest = raw.replace(number, "").replace(/\s+/g, "");
    if (/^(\$|usd|dollars?)?$/.test(rest) && /[$]|usd|dollar/.test(rest)) return { kind: "USD", value: number };
    if (/^(€|eur|euros?)$/.test(rest)) return { kind: "EUR", value: number };
    if (/^(ltc)?$/.test(rest)) return { kind: "LTC", value: number, bare: rest === "" };
    return null;
  }

  /* Returns { sat, quote } where quote describes the conversion (null for plain LTC), or { error }. */
  async function resolveAmount(text, deal) {
    const parsed = parseAmountInput(text);
    if (!parsed) return { error: tr(deal, "Invalid amount. Examples: `0.25` (LTC), `5$` (dollars), `5€` (euros).", "Montant invalide. Exemples : `0.25` (LTC), `5$` (dollars), `5€` (euros).") };

    if (parsed.kind === "LTC") {
      const sat = ltcToSat(parsed.value);
      if (!sat) return { error: tr(deal, "Invalid amount. Use at most 8 decimals, for example `0.25`.", "Montant invalide. Utilise 8 décimales au maximum, par exemple `0.25`.") };
      const prices = await getLtcPrice().catch(() => null);
      return { sat, quote: prices ? { fiat: (sat / SAT_PER_LTC) * prices.usd, currency: "USD", price: prices.usd, indicative: true } : null };
    }

    const fiat = Number(parsed.value);
    if (!(fiat > 0) || fiat > 1000000) return { error: tr(deal, "Invalid amount.", "Montant invalide.") };
    let prices;
    try {
      prices = await getLtcPrice();
    } catch (error) {
      if (isFr(deal)) return { error: "Impossible d'obtenir le cours du LTC pour l'instant. Réessaie dans un instant." };
      throw error;
    }
    const price = parsed.kind === "USD" ? prices.usd : prices.eur;
    return { sat: Math.round((fiat / price) * SAT_PER_LTC), quote: { fiat, currency: parsed.kind, price } };
  }

  const fmtMoney = (n) => (n >= 1 ? n.toFixed(2) : n >= 0.0001 ? Number(n.toFixed(4)).toString() : Number(n.toPrecision(2)).toString());
  const quoteText = (q) =>
    !q ? "" : q.indicative
      ? `≈ ${fmtMoney(q.fiat)} ${q.currency} (1 LTC = ${q.price} ${q.currency})`
      : `≈ ${q.fiat} ${q.currency} (1 LTC = ${q.price} ${q.currency})`;

  async function getTipHeight() {
    const height = parseInt(await api("/blocks/tip/height"), 10);
    if (!Number.isFinite(height)) throw new Error("Blockchain API returned an invalid block height.");
    return height;
  }

  async function getUtxos(address) {
    const utxos = await apiJson(`/address/${address}/utxo`);
    if (!Array.isArray(utxos)) throw new Error("Blockchain API returned an invalid UTXO list.");
    return utxos.map((u) => ({
      txid: String(u.txid),
      vout: Number(u.vout),
      value: Number(u.value),
      confirmed: Boolean(u.status?.confirmed),
      height: Number(u.status?.block_height) || 0,
    }));
  }

  async function getFeeRate() {
    try {
      const fees = await apiJson("/v1/fees/recommended");
      const rate = Number(fees.halfHourFee || fees.fastestFee || fees.hourFee);
      if (Number.isFinite(rate) && rate > 0) return Math.max(rate, cfg.minFeeRate);
    } catch {
      // fall back to the configured minimum
    }
    return cfg.minFeeRate;
  }

  async function broadcast(hex) {
    const txid = (await api("/tx", { method: "POST", body: hex, headers: { "Content-Type": "text/plain" } })).trim();
    if (!/^[0-9a-f]{64}$/i.test(txid)) throw new Error(`Unexpected broadcast answer: ${txid.slice(0, 120)}`);
    return txid;
  }

  function confirmationsOf(utxo, tip) {
    return utxo.confirmed && utxo.height ? Math.max(0, tip - utxo.height + 1) : 0;
  }

  /* =====================================================
     TRANSACTION BUILDING
  ===================================================== */

  /* Sweep every given UTXO of one derived address to `toAddress` (the fee comes out of the amount). */
  function buildSweepTx({ index, utxos, toAddress, feeRate }) {
    if (!utxos.length) throw new Error("No funds to send.");
    const node = deriveNode(index);
    const own = bitcoin.payments.p2wpkh({ pubkey: node.publicKey, network: LITECOIN });
    const total = utxos.reduce((sum, u) => sum + u.value, 0);

    const vsize = Math.ceil(10.5 + 68 * utxos.length + 34); // 34 = biggest standard output
    const fee = Math.ceil(vsize * feeRate);
    const outValue = total - fee;

    if (fee > total * MAX_FEE_SHARE) throw new Error(`Network fee too high (${fee} sat on ${total} sat). Try again later.`);
    if (outValue < DUST_SAT) throw new Error("The amount is too small to be sent after the network fee.");

    const psbt = new bitcoin.Psbt({ network: LITECOIN });
    for (const u of utxos) {
      psbt.addInput({ hash: u.txid, index: u.vout, witnessUtxo: { script: own.output, value: u.value } });
    }
    psbt.addOutput({ script: bitcoin.address.toOutputScript(toAddress, LITECOIN), value: outValue });
    psbt.signAllInputs(node);
    if (!psbt.validateSignaturesOfAllInputs((pubkey, hash, sig) => ecc.verify(hash, pubkey, sig))) {
      throw new Error("Signature check failed.");
    }
    psbt.finalizeAllInputs();
    const tx = psbt.extractTransaction();
    return { hex: tx.toHex(), txid: tx.getId(), fee, outValue, total };
  }

  /* =====================================================
     STORAGE
  ===================================================== */

  let store = { nextIndex: 0, nextDeal: 1, walletCheck: "", deals: {}, paypal: [], nextPaypal: 1, tiers: [], nextTier: 1, tiersReady: false, access: [], stats: {} };

  function loadStore() {
    try {
      store = { ...store, ...JSON.parse(fs.readFileSync(DATA_FILE, "utf8")) };
    } catch (error) {
      if (error.code !== "ENOENT") throw new Error(`Could not read ${DATA_FILE}: ${error.message}`);
    }
    const check = addressOf(0);
    if (store.walletCheck && store.walletCheck !== check) {
      throw new Error("MM_SEED does not match the wallet used by the saved deals (middleman.json). Refusing to start.");
    }
    store.walletCheck = check;
    saveStore();
  }

  function saveStore() {
    const tmp = `${DATA_FILE}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(store, null, 2));
    fs.renameSync(tmp, DATA_FILE);
  }

  const locks = new Map();
  function withLock(key, fn) {
    const previous = locks.get(key) || Promise.resolve();
    const next = previous.catch(() => {}).then(fn);
    locks.set(key, next);
    next.finally(() => locks.get(key) === next && locks.delete(key)).catch(() => {});
    return next;
  }

  /* =====================================================
     DISCORD
  ===================================================== */

  let client = null;
  let options = { staffRoleId: "", ownerRoleId: "", logChannelId: "" };
  let enabled = false;
  let timer = null;

  const COLORS = { info: 0x5865f2, wait: 0xfaa61a, ok: 0x2ecc71, bad: 0xed4245, grey: 0x747f8d };
  const ephemeral = MessageFlags.Ephemeral;

  const STATE_TEXT = {
    partner: "Add the person you trade with",
    roles: "Both people choose a role",
    amount: "The sender enters the amount",
    amount_confirm: "The receiver confirms the amount",
    awaiting_payment: "Waiting for the LTC payment",
    confirming: "Payment detected, waiting for confirmations",
    funded: "Funds secured: deliver, then the sender releases",
    released: "Released: the receiver enters his LTC address",
    paying: "Sending the funds...",
    done: "Completed",
    refunded: "Refunded to the sender",
    cancelled: "Cancelled",
  };
  const FINAL = new Set(["done", "refunded", "cancelled"]);

  /* ---------- language: every ticket is entirely in English or in French ---------- */
  const isFr = (deal) => deal?.lang === "fr";
  /* PayPal deals never talk about Litecoin: the LTC wording of shared texts becomes payer / seller. */
  const noLtc = (text, fr) =>
    (fr
      ? text.replace(/l'expéditeur des LTC/g, "le payeur").replace(/le destinataire des LTC/g, "le vendeur").replace(/destinataire des LTC/g, "vendeur").replace(/expéditeur des LTC/g, "payeur")
      : text.replace(/the LTC sender/g, "the payer").replace(/the LTC receiver/g, "the seller").replace(/LTC sender/g, "payer").replace(/LTC receiver/g, "seller"));
  const tr = (deal, en, fr) => {
    const text = isFr(deal) ? fr : en;
    return deal?.method === "paypal" && typeof text === "string" ? noLtc(text, isFr(deal)) : text;
  };
  const frozenLine = (deal) => tr(deal, "🧊  **FROZEN**: a dispute is open, staff will decide.", "🧊  **GELÉ** : un litige est ouvert, le staff va décider.");

  const mention = (id) => (id ? `<@${id}>` : "—");
  const txLink = (txid) => `[${txid.slice(0, 12)}…](${cfg.explorerTx}${txid})`;
  const isParticipant = (deal, id) => id === deal.userA || id === deal.userB;

  /* ---------- PayPal (manual mode): the bot guides the steps, staff checks PayPal and sends the money ---------- */
  const isPaypal = (deal) => deal.method === "paypal";
  const CUR = { USD: "$", EUR: "€" };
  const fmtFiat = (cents, currency) => `${CUR[currency] || ""}${(cents / 100).toFixed(2)} ${currency}`;
  const words = (deal) =>
    isPaypal(deal)
      ? { sender: tr(deal, "Payer", "Payeur"), receiver: tr(deal, "Seller", "Vendeur") }
      : { sender: tr(deal, "Sender", "Expéditeur"), receiver: tr(deal, "Receiver", "Destinataire") };
  const makeRef = (deal) => `MM${deal.n}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
  const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  /* "5", "5.50", "5$", "$5", "5 usd", "5€", "5 eur"  ->  { cents } in the PayPal currency, or { error } */
  function parseFiatCents(text, deal, chosen) {
    const want = chosen === "EUR" || chosen === "USD" ? chosen : cfg.paypalCurrency;
    let raw = String(text || "").trim().toLowerCase().replace(",", ".").replace(/\s+/g, "");
    let currency = want;
    if (/\$|usd|dollars?/.test(raw)) {
      currency = "USD";
      raw = raw.replace(/\$|usd|dollars?/g, "");
    } else if (/€|eur|euros?/.test(raw)) {
      currency = "EUR";
      raw = raw.replace(/€|eur|euros?/g, "");
    }
    const example = `\`5${CUR[want]}\``;
    if (!/^\d+(\.\d{1,2})?$/.test(raw)) return { error: tr(deal, `Invalid amount. Example: ${example}.`, `Montant invalide. Exemple : ${example}.`) };
    if (currency !== want) {
      return { error: tr(deal, `You chose ${want}. Type for example ${example}, or press the amount button again to choose the other currency.`, `Tu as choisi ${want}. Écris par exemple ${example}, ou rappuie sur le bouton du montant pour choisir l'autre devise.`) };
    }
    const cents = Math.round(Number(raw) * 100);
    if (!(cents > 0) || cents > 100000000) return { error: tr(deal, "Invalid amount.", "Montant invalide.") };
    return { cents, currency };
  }

  const amountText = (deal) =>
    isPaypal(deal)
      ? deal.amountCents ? `**${fmtFiat(deal.amountCents, deal.currency)}**` : tr(deal, "*not set yet*", "*pas encore fixé*")
      : deal.amountSat ? `**${satToLtc(deal.amountSat)} LTC**${deal.quote ? `\n${quoteText(deal.quote)}` : ""}` : tr(deal, "*not set yet*", "*pas encore fixé*");

  function isStaff(member) {
    if (!member) return false;
    return (
      member.permissions?.has(PermissionFlagsBits.Administrator) ||
      (options.staffRoleId && member.roles?.cache?.has(options.staffRoleId)) ||
      (options.ownerRoleId && member.roles?.cache?.has(options.ownerRoleId))
    );
  }

  /* Staff of ONE deal: general staff / administrators, or the holder of the role of the deal's amount range. */
  const ltcAccess = () => (store.access = Array.isArray(store.access) ? store.access : []);
  /* LTC tickets are private: only administrators and the roles given with /access count as staff there.
     PayPal tickets keep the general staff role and the role of the range. */
  const staffFor = (deal, member) => {
    if (deal && !isPaypal(deal)) {
      return Boolean(
        member?.permissions?.has(PermissionFlagsBits.Administrator) ||
          (options.ownerRoleId && member?.roles?.cache?.has(options.ownerRoleId)) ||
          ltcAccess().some((id) => member?.roles?.cache?.has(id))
      );
    }
    return isStaff(member) || Boolean(dealTierRole(deal) && member?.roles?.cache?.has(dealTierRole(deal)));
  };

  function button(id, label, style = ButtonStyle.Secondary, emoji) {
    const b = new ButtonBuilder().setCustomId(`mm:${id}`).setLabel(label).setStyle(style);
    if (emoji) b.setEmoji(emoji);
    return b;
  }

  /* ---------- look & feel ---------- */

  const STEPS = ["Partner", "Roles", "Amount", "Payment", "Delivery", "Payout"];
  const STEPS_FR = ["Partenaire", "Rôles", "Montant", "Paiement", "Livraison", "Versement"];
  const STEP_OF = { partner: 0, roles: 1, amount: 2, amount_confirm: 2, choose_pp: 3, awaiting_payment: 3, confirming: 3, funded: 4, released: 5, payout_pending: 5, paying: 5, done: 6 };
  const STATE_COLOR = {
    partner: 0x5865f2, roles: 0x5865f2, amount: 0x5865f2, amount_confirm: 0x5865f2, choose_pp: 0x0070ba,
    awaiting_payment: 0xfaa61a, confirming: 0xf57c00, funded: 0x2ecc71, released: 0x1abc9c, payout_pending: 0x1abc9c, paying: 0x1abc9c,
    done: 0x2ecc71, refunded: 0x747f8d, cancelled: 0x747f8d,
  };

  /* "▰▰▰▰▰▱  Step 5 of 6 · Delivery" */
  const stepper = (deal) => {
    const current = STEP_OF[deal.state];
    if (current === undefined) return "";
    if (current >= STEPS.length) return `${bar(STEPS.length, STEPS.length, STEPS.length)}  **${tr(deal, "Complete", "Terminé")}**`;
    const name = tr(deal, STEPS, STEPS_FR)[current];
    return `${bar(current + 1, STEPS.length, STEPS.length)}  ${tr(deal, `Step ${current + 1} of ${STEPS.length}`, `Étape ${current + 1} sur ${STEPS.length}`)}  ·  **${name}**`;
  };

  const bar = (done, total, width = 10) => {
    const filled = Math.max(0, Math.min(width, Math.round((width * done) / Math.max(1, total))));
    return "▰".repeat(filled) + "▱".repeat(width - filled);
  };

  const unix = (ms) => Math.floor(ms / 1000);

  const qrUrl = (deal) =>
    `https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=10&format=png&data=${encodeURIComponent(
      `litecoin:${deal.address}?amount=${(deal.amountSat / SAT_PER_LTC).toFixed(8)}`
    )}`;

  /* What is going on and who has to do what, as a heading plus a quoted block. */
  function stateText(deal) {
    const pp = isPaypal(deal);
    const T = (en, fr) => tr(deal, en, fr);
    const sender = mention(deal.senderId);
    const receiver = mention(deal.receiverId);
    const block = (title, lines = []) => [`### ${title}`, ...lines.map((l) => `> ${l}`)].join("\n");
    switch (deal.state) {
      case "partner":
        return block(T("➕  Add your partner", "➕  Ajoute ton partenaire"), [T("Click the button below and send their **@mention or user ID**.", "Clique sur le bouton ci-dessous et envoie son **@mention ou son ID**.")]);
      case "roles":
        return pp
          ? block(T("🎭  Pick your roles", "🎭  Choisissez vos rôles"), [T("📤 The **payer** sends the money.", "📤 Le **payeur** envoie l'argent."), T("📥 The **seller** gets paid when the deal is done.", "📥 Le **vendeur** est payé quand le deal est terminé.")])
          : block(T("🎭  Pick your roles", "🎭  Choisissez vos rôles"), [T("📤 The **sender** pays the LTC.", "📤 L'**expéditeur** paie les LTC."), T("📥 The **receiver** gets it when the deal is done.", "📥 Le **destinataire** les reçoit quand le deal est terminé.")]);
      case "amount":
        return pp
          ? block(T("💰  Set the amount", "💰  Fixe le montant"), [
              T(`${sender} press the button, **choose $ or €**, then type the amount.`, `${sender} appuie sur le bouton, **choisis $ ou €**, puis écris le montant.`),
            ])
          : block(T("💰  Set the amount", "💰  Fixe le montant"), [
              T(`${sender} type it in money (\`5$\`, \`5€\`) or in LTC (\`0.25 ltc\`).`, `${sender} écris-le en argent (\`5$\`, \`5€\`) ou en LTC (\`0.25 ltc\`).`),
              T("With a plain number, I ask which one you mean.", "Avec un nombre seul, je te demande ce que tu veux dire."),
            ]);
      case "amount_confirm":
        return block(pp ? T("🤝  Waiting for the seller", "🤝  En attente du vendeur") : T("🤝  Waiting for the receiver", "🤝  En attente du destinataire"), [
          T(`${receiver} accept or decline on the **amount card** below.`, `${receiver} accepte ou refuse sur la **carte du montant** ci-dessous.`),
          pp ? T("🔒 Once confirmed, the amount is locked.", "🔒 Une fois confirmé, le montant est verrouillé.") : T("🔒 Once confirmed, the LTC figure is locked.", "🔒 Une fois confirmé, le montant en LTC est verrouillé."),
        ]);
      case "choose_pp":
        return block(T("💙  A staff member gives their PayPal", "💙  Un staff donne son PayPal"), [
          T(`${staffPing(deal)} press **PayPal** and enter the PayPal email that receives this payment.`, `${staffPing(deal)} appuyez sur **PayPal** et entrez l'email PayPal qui reçoit ce paiement.`),
          T("The two people of the deal cannot do this. The payer sees the PayPal right after.", "Les deux personnes du deal ne peuvent pas le faire. Le payeur voit le PayPal juste après."),
        ]);
      case "awaiting_payment":
        return pp
          ? block(T("💳  Waiting for the PayPal payment", "💳  En attente du paiement PayPal"), [
              T(`${sender} pay as shown in the **payment card** below.`, `${sender} paie comme indiqué sur la **carte de paiement** ci-dessous.`),
              deal.paidClaimed
                ? T("Staff is checking PayPal, this updates when it is verified.", "Le staff vérifie PayPal, ça se met à jour dès que c'est validé.")
                : T("Then click **I've paid**, staff checks PayPal.", "Clique ensuite sur **J'ai payé**, le staff vérifie PayPal."),
            ])
          : block(T("💳  Waiting for the payment", "💳  En attente du paiement"), [
              T(`${sender} send the exact amount shown in the **payment card** below.`, `${sender} envoie le montant exact indiqué sur la **carte de paiement** ci-dessous.`),
              T("The bot spots it by itself, nothing to click.", "Le bot le détecte tout seul, rien à cliquer."),
            ]);
      case "confirming":
        return block(T("⏳  Payment spotted", "⏳  Paiement détecté"), [T("The network is confirming it.", "Le réseau le confirme."), T("This card updates by itself.", "Cette carte se met à jour toute seule.")]);
      case "funded":
        return block(pp ? T("🔒  Payment verified", "🔒  Paiement vérifié") : T("🔒  Funds secured", "🔒  Fonds sécurisés"), [
          T(`📥 ${receiver} deliver what was agreed.`, `📥 ${receiver} livre ce qui a été convenu.`),
          T(`📤 ${sender} click **Release** only once you really received it.`, `📤 ${sender} clique sur **Libérer** seulement quand tu as vraiment tout reçu.`),
        ]);
      case "released":
        return block(T("🔓  Funds released", "🔓  Fonds libérés"), [
          T(`📥 ${receiver} click **${pp ? "Enter my PayPal email" : "Enter my LTC address"}** to get paid.`, `📥 ${receiver} clique sur **${pp ? "Entrer mon email PayPal" : "Entrer mon adresse LTC"}** pour être payé.`),
        ]);
      case "payout_pending":
        return block(T("🏦  Staff is sending the money", "🏦  Le staff envoie l'argent"), [
          T(`Staff sends **${fmtFiat(deal.amountCents, deal.currency)}** to \`${deal.payoutPaypal}\`.`, `Le staff envoie **${fmtFiat(deal.amountCents, deal.currency)}** à \`${deal.payoutPaypal}\`.`),
          T("This card updates when it is done.", "Cette carte se met à jour quand c'est fait."),
        ]);
      case "paying": return block(T("📤  Sending the funds…", "📤  Envoi des fonds…"));
      case "done": return block(T("🎉  Deal complete", "🎉  Deal terminé"), [T("Thank you both 💜", "Merci à vous deux 💜")]);
      case "refunded":
        return block(T("↩️  Refunded", "↩️  Remboursé"), [
          pp ? T("The payment went back to the payer.", "Le paiement est retourné au payeur.") : T("The funds went back to the sender.", "Les fonds sont retournés à l'expéditeur."),
        ]);
      case "cancelled":
        return block(
          T("✖️  Cancelled", "✖️  Annulé"),
          deal.address
            ? [T("Do **not** send any LTC to the deposit address anymore.", "N'envoie **plus** de LTC à l'adresse de dépôt.")]
            : deal.ref
              ? [T("Do **not** send any money anymore.", "N'envoie **plus** d'argent.")]
              : [T("Nothing was paid.", "Rien n'a été payé.")]
        );
      default: return "";
    }
  }

  /* A step card: one message per step, several panels (embeds) in it:
       1. header  : progress + what to do now
       2. details : sender, receiver, amount (from the roles step on)
       3. result  : payout or refund transaction (when finished)
     Each new step posts a new card; the previous one folds into one line (see advance()).
     The payment (address, QR, live confirmations) is its own message, see paymentEmbed(). */
  function dealEmbeds(deal) {
    const T = (en, fr) => tr(deal, en, fr);
    const panels = [];
    const color = deal.frozen ? COLORS.bad : STATE_COLOR[deal.state] || COLORS.info;

    // 1. header
    panels.push(
      new EmbedBuilder()
        .setColor(color)
        .setTitle(isPaypal(deal) ? `💙  PayPal Middleman  ·  Deal #${deal.n}` : `💱  Litecoin Middleman  ·  Deal #${deal.n}`)
        .setDescription(
          [
            deal.frozen ? frozenLine(deal) : null,
            deal.notice || null,
            stepper(deal) || null,
            stateText(deal) || null,
          ].filter(Boolean).join("\n​\n")
        )
    );

    // 2. details (from the roles step on)
    const amountLine = amountText(deal);
    if (deal.state !== "partner") panels.push(
      new EmbedBuilder()
        .setColor(0x4f545c)
        .setTitle(T("📋  Deal details", "📋  Détails du deal"))
        .addFields(
          { name: `📤  ${words(deal).sender}`, value: deal.senderId ? mention(deal.senderId) : T("*waiting…*", "*en attente…*"), inline: true },
          { name: `📥  ${words(deal).receiver}`, value: deal.receiverId ? mention(deal.receiverId) : T("*waiting…*", "*en attente…*"), inline: true },
          { name: T("💰  Amount", "💰  Montant"), value: amountLine, inline: true },
          ...(deal.tier ? [{ name: T("🎚️  Range", "🎚️  Tranche"), value: deal.tier.label, inline: true }] : [])
        )
    );

    // 3. result
    if (deal.payoutTxid || deal.refundTxid) {
      const refund = Boolean(deal.refundTxid);
      panels.push(
        new EmbedBuilder()
          .setColor(refund ? COLORS.grey : COLORS.ok)
          .setTitle(refund ? T("↩️  Refund", "↩️  Remboursement") : T("🏦  Payout", "🏦  Versement"))
          .setDescription(
            [
              `${txLink(refund ? deal.refundTxid : deal.payoutTxid)}`,
              `\`${refund ? deal.refundAddress : deal.payoutAddress}\``,
              T(`🧾 Network fee: ${satToLtc(deal.feeSat)} LTC (deducted from the amount sent)`, `🧾 Frais réseau : ${satToLtc(deal.feeSat)} LTC (déduits du montant envoyé)`),
            ].join("\n")
          )
      );
    }

    // 3b. PayPal result: staff sent the money (or refunded it)
    if (isPaypal(deal) && (deal.state === "done" || deal.state === "refunded")) {
      const refund = deal.state === "refunded";
      panels.push(
        new EmbedBuilder()
          .setColor(refund ? COLORS.grey : COLORS.ok)
          .setTitle(refund ? T("↩️  Refund", "↩️  Remboursement") : T("🏦  Payout", "🏦  Versement"))
          .setDescription(
            [
              refund
                ? T("Refunded to the payer by staff.", "Remboursé au payeur par le staff.")
                : T(`**${fmtFiat(deal.amountCents, deal.currency)}** sent to \`${deal.payoutPaypal}\` by staff.`, `**${fmtFiat(deal.amountCents, deal.currency)}** envoyés à \`${deal.payoutPaypal}\` par le staff.`),
              deal.resultNote ? `🧾 ${deal.resultNote}` : null,
            ].filter(Boolean).join("\n")
          )
      );
    }

    panels[panels.length - 1]
      .setFooter({
        text: isPaypal(deal)
          ? T("Kazuki MM  ·  every PayPal payment is checked and sent by staff", "Kazuki MM  ·  chaque paiement PayPal est vérifié et envoyé par le staff")
          : T("Kazuki MM  ·  funds are held by the bot until release", "Kazuki MM  ·  les fonds sont gardés par le bot jusqu'à la libération"),
      })
      .setTimestamp();
    return panels;
  }

  /* The payment card is a message of its own, edited in place while the payment goes through:
     instructions -> payment spotted (confirmations 1/2, 2/2) -> payment confirmed. */
  function paypalPaymentEmbed(deal) {
    const T = (en, fr) => tr(deal, en, fr);
    const embed = new EmbedBuilder().setTimestamp();
    if (deal.state === "cancelled") {
      return embed.setColor(COLORS.grey).setTitle(T("✖️  Payment cancelled", "✖️  Paiement annulé")).setDescription(T("The deal was cancelled. Do **not** send any money anymore.", "Le deal a été annulé. N'envoie **plus** d'argent."));
    }
    if (deal.state === "refunded") {
      return embed.setColor(COLORS.grey).setTitle(T("↩️  Payment refunded", "↩️  Paiement remboursé")).setDescription(T("The payment went back to the payer.", "Le paiement est retourné au payeur."));
    }
    if (deal.state !== "awaiting_payment") {
      return embed
        .setColor(COLORS.ok)
        .setTitle(T("✅  Payment verified", "✅  Paiement vérifié"))
        .setDescription([
          T(`**${fmtFiat(deal.amountCents, deal.currency)}** received and checked by staff.`, `**${fmtFiat(deal.amountCents, deal.currency)}** reçus et vérifiés par le staff.`),
          "​",
          T("Staff holds the payment until the deal is done.", "Le staff garde le paiement jusqu'à la fin du deal."),
        ].join("\n"));
    }
    return embed
      .setColor(deal.paidClaimed ? 0xf57c00 : 0xfaa61a)
      .setTitle(deal.paidClaimed ? T("⏳  Waiting for staff to verify", "⏳  En attente de la vérification du staff") : T("💙  PayPal payment instructions", "💙  Instructions de paiement PayPal"))
      .setDescription(
        [
          deal.frozen ? `${frozenLine(deal)}\n​` : null,
          T(`📤 ${mention(deal.senderId)} send exactly`, `📤 ${mention(deal.senderId)} envoie exactement`),
          `\`\`\`${fmtFiat(deal.amountCents, deal.currency)}\`\`\``,
          T(`to this PayPal account (**${deal.ppLabel}**)`, `sur ce compte PayPal (**${deal.ppLabel}**)`),
          `\`\`\`${deal.ppEmail}\`\`\``,
          T("and write this **reference** in the PayPal note", "et écris cette **référence** dans la note PayPal"),
          `\`\`\`${deal.ref}\`\`\``,
          cfg.paypalNote ? `ℹ️ ${cfg.paypalNote}` : null,
          T("🔒 The amount is **locked**.", "🔒 Le montant est **verrouillé**."),
          "​",
          T("### ⏱️  Status", "### ⏱️  Statut"),
          deal.paidClaimed
            ? T("🔔 The payer says it is sent. Staff is checking PayPal.", "🔔 Le payeur dit l'avoir envoyé. Le staff vérifie PayPal.")
            : T("⏳ Waiting for your payment. Once it is sent, click **I've paid**.", "⏳ En attente de ton paiement. Une fois envoyé, clique sur **J'ai payé**."),
        ].filter(Boolean).join("\n")
      );
  }

  function paymentEmbed(deal) {
    if (isPaypal(deal)) return paypalPaymentEmbed(deal);
    const T = (en, fr) => tr(deal, en, fr);
    const need = cfg.confirmations;
    const live = deal.state === "awaiting_payment" || deal.state === "confirming";
    const embed = new EmbedBuilder().setTimestamp();

    if (deal.state === "cancelled") {
      return embed.setColor(COLORS.grey).setTitle(T("✖️  Payment cancelled", "✖️  Paiement annulé")).setDescription(T("The deal was cancelled. Do **not** send any LTC to this address anymore.", "Le deal a été annulé. N'envoie **plus** de LTC à cette adresse."));
    }
    if (deal.state === "refunded") {
      return embed.setColor(COLORS.grey).setTitle(T("↩️  Payment refunded", "↩️  Paiement remboursé")).setDescription(T("The funds went back to the sender.", "Les fonds sont retournés à l'expéditeur."));
    }

    if (live) {
      const confirming = deal.state === "confirming";
      const checked = deal.lastCheck ? T(`🔄 Last check <t:${unix(deal.lastCheck)}:R>`, `🔄 Dernière vérification <t:${unix(deal.lastCheck)}:R>`) : null;
      embed
        .setColor(confirming ? 0xf57c00 : 0xfaa61a)
        .setTitle(confirming ? T("⏳  Payment spotted", "⏳  Paiement détecté") : T("💳  Payment instructions", "💳  Instructions de paiement"))
        .setDescription(
          [
            deal.frozen ? `${frozenLine(deal)}\n​` : null,
            T(`📤 ${mention(deal.senderId)} send exactly`, `📤 ${mention(deal.senderId)} envoie exactement`),
            `\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\``,
            T("to this address", "à cette adresse"),
            `\`\`\`${deal.address}\`\`\``,
            T("🔒 The amount is **locked**, it will not change even if the price moves.", "🔒 Le montant est **verrouillé**, il ne changera pas même si le cours bouge."),
            "​",
            "### ⏱️  Confirmations",
            confirming
              ? T(
                  `${bar(deal.confirmations, need)}  **${Math.min(deal.confirmations, need)}/${need}**  ·  seen **${satToLtc(deal.seenSat)} LTC**`,
                  `${bar(deal.confirmations, need)}  **${Math.min(deal.confirmations, need)}/${need}**  ·  vus **${satToLtc(deal.seenSat)} LTC**`
                )
              : T(
                  `${bar(0, need)}  waiting for the payment\nNeeds ${need} confirmation(s) after sending (about ${Math.round(need * 2.5)} min)`,
                  `${bar(0, need)}  en attente du paiement\nIl faut ${need} confirmation(s) après l'envoi (environ ${Math.round(need * 2.5)} min)`
                ),
            checked,
          ].filter(Boolean).join("\n")
        );
      if (cfg.qr && deal.address) embed.setThumbnail(qrUrl(deal));
      return embed;
    }

    // funded, and everything after it
    const txs = (deal.paymentTxids || []).map(txLink).join("   ");
    return embed
      .setColor(COLORS.ok)
      .setTitle(T("✅  Payment confirmed", "✅  Paiement confirmé"))
      .setDescription(
        [
          T(`**${satToLtc(deal.receivedSat || deal.amountSat)} LTC** received and confirmed.`, `**${satToLtc(deal.receivedSat || deal.amountSat)} LTC** reçus et confirmés.`),
          `${bar(need, need)}  **${need}/${need}** confirmations`,
          txs ? `🔗 ${txs}` : null,
          "​",
          T("The bot holds the funds until the deal is done.", "Le bot garde les fonds jusqu'à la fin du deal."),
        ].filter(Boolean).join("\n")
      );
  }

  const paymentComponents = (deal) => (deal.state === "awaiting_payment" || deal.state === "confirming" ? dealComponents(deal) : []);

  async function postPaymentCard(deal) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const message = await channel
      .send({ content: mention(deal.senderId), embeds: [paymentEmbed(deal)], components: paymentComponents(deal), allowedMentions: { users: [deal.senderId] } })
      .catch(() => null);
    deal.payMsgId = message?.id || "";
    saveStore();
  }

  /* Edits the payment card in place (an edit does not ping, the short notices below do). */
  async function refreshPaymentCard(deal) {
    if (!deal.payMsgId || !["awaiting_payment", "confirming", "funded", "cancelled", "refunded"].includes(deal.state)) return;
    deal.lastRefresh = Date.now();
    const channel = await getChannel(deal);
    const message = await channel?.messages.fetch(deal.payMsgId).catch(() => null);
    await message?.edit({ embeds: [paymentEmbed(deal)], components: paymentComponents(deal) }).catch(() => {});
  }

  function dealComponents(deal) {
    const T = (en, fr) => tr(deal, en, fr);
    const rows = [];
    const s = deal.state;
    const main = [];

    if (s === "partner") main.push(button("partner", T("Add the other person", "Ajouter l'autre personne"), ButtonStyle.Primary, "➕"));
    const pp = isPaypal(deal);
    if (s === "roles") {
      main.push(
        button("role:sender", pp ? T("I pay", "Je paie") : T("I send the LTC", "J'envoie les LTC"), ButtonStyle.Primary, "📤"),
        button("role:receiver", pp ? T("I get paid", "Je suis payé") : T("I receive the LTC", "Je reçois les LTC"), ButtonStyle.Success, "📥")
      );
    }
    if (s === "amount") main.push(button("amount", T("Set the amount", "Fixer le montant"), ButtonStyle.Primary, "💰"));
    if (s === "choose_pp") {
      main.push(button("staffpp", "PayPal", ButtonStyle.Primary, "💙"));
    }
    if (s === "funded") main.push(button("release", T("Release the funds", "Libérer les fonds"), ButtonStyle.Success, "🔓"));
    if (s === "released") main.push(button("payout", pp ? T("Enter my PayPal email", "Entrer mon email PayPal") : T("Enter my LTC address", "Entrer mon adresse LTC"), ButtonStyle.Success, "🏦"));
    if (s === "awaiting_payment" || s === "confirming") main.push(button("copy", T("Copy details", "Copier les infos"), ButtonStyle.Secondary, "📋"));
    if (pp && s === "awaiting_payment" && !deal.paidClaimed) main.push(button("paid", T("I've paid", "J'ai payé"), ButtonStyle.Success, "💸"));
    if (["partner", "roles", "amount", "amount_confirm", "choose_pp", "awaiting_payment"].includes(s) && !(pp && deal.paidClaimed)) main.push(button("cancel", T("Cancel", "Annuler"), ButtonStyle.Danger, "✖️"));
    if (["awaiting_payment", "confirming", "funded", "released", "payout_pending"].includes(s) && !deal.frozen) main.push(button("dispute", T("Call staff", "Appeler le staff"), ButtonStyle.Danger, "🚨"));

    if (staffComponents(deal).length) main.push(button("staff", T("Staff tools", "Outils staff"), ButtonStyle.Secondary, "🛠️"));
    if (main.length) rows.push(new ActionRowBuilder().addComponents(main));
    return rows;
  }

  /* Buttons shown only inside the private "Staff tools" panel. */
  function staffComponents(deal) {
    const T = (en, fr) => tr(deal, en, fr);
    const s = deal.state;
    const staff = [];
    if (deal.frozen) staff.push(button("unfreeze", T("Unfreeze", "Dégeler"), ButtonStyle.Secondary, "🧊"));
    if (isPaypal(deal)) {
      if (s === "awaiting_payment") {
        staff.push(button("mark_paid", T("Payment received", "Paiement reçu"), ButtonStyle.Success, "✅"));
      }
      if (s === "funded") staff.push(button("force_release", T("Force release", "Forcer la libération"), ButtonStyle.Primary, "⚖️"));
      if (s === "payout_pending") staff.push(button("payout_sent", T("Payout sent", "Versement envoyé"), ButtonStyle.Success, "🏦"));
      if (["funded", "released", "payout_pending"].includes(s)) staff.push(button("refund", T("Refund payer", "Rembourser le payeur"), ButtonStyle.Danger, "↩️"));
    } else {
      if (s === "funded") staff.push(button("force_release", T("Force release", "Forcer la libération"), ButtonStyle.Primary, "⚖️"));
      if (s === "confirming" || s === "funded" || s === "released") staff.push(button("refund", T("Refund sender", "Rembourser l'expéditeur"), ButtonStyle.Danger, "↩️"));
    }
    if (FINAL.has(s)) staff.push(button("close", T("Close channel", "Fermer le salon"), ButtonStyle.Secondary, "🗑️"));
    return staff.length ? [new ActionRowBuilder().addComponents(staff)] : [];
  }

  const render = (deal) => ({ embeds: dealEmbeds(deal), components: dealComponents(deal) });

  async function getChannel(deal) {
    return client.channels.fetch(deal.channelId).catch(() => null);
  }

  /* Acknowledges a click on a deal card (or on the private staff panel) and refreshes the live cards. */
  async function ack(interaction, deal, refresh = true) {
    const onCard = interaction.message?.id && [deal.messageId, deal.payMsgId].includes(interaction.message.id);
    if (onCard) await interaction.deferUpdate();
    else await interaction.update({ content: tr(deal, "✅ Done.", "✅ Fait."), components: [] });
    if (refresh) await refreshMain(deal);
  }

  /* Re-draws the active step card (if any) and the payment card (if any). */
  async function refreshMain(deal) {
    deal.lastRefresh = Date.now();
    const channel = await getChannel(deal);
    if (!channel) return;
    if (deal.messageId) {
      try {
        const message = await channel.messages.fetch(deal.messageId);
        await message.edit(render(deal));
      } catch {
        const message = await channel.send(render(deal)).catch(() => null);
        if (message) {
          deal.messageId = message.id;
          saveStore();
        }
      }
    }
    await refreshPaymentCard(deal).catch(() => {});
  }

  /* ---------- step cards: every step is a NEW card at the bottom, the previous one folds into one line ---------- */

  const foldedEmbed = (text) => new EmbedBuilder().setColor(0x4f545c).setDescription(text);

  /* Folds the active step card into a one-line summary (buttons removed). */
  async function foldStepCard(deal, text) {
    if (!deal.messageId) return;
    const channel = await getChannel(deal);
    const message = await channel?.messages.fetch(deal.messageId).catch(() => null);
    await message?.edit({ content: "", embeds: [foldedEmbed(text)], components: [] }).catch(() => {});
    deal.messageId = "";
  }

  /* Posts the card of the current state at the bottom of the ticket (pings make it a notification too). */
  async function postStepCard(deal, ping = []) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const users = ping.filter((id) => /^\d{15,25}$/.test(String(id)));
    const roles = ping.filter((x) => /^<@&\d+>$/.test(String(x))).map((x) => String(x).slice(3, -1));
    const others = ping.filter((x) => x && !/^\d{15,25}$/.test(String(x)));
    const content = [...users.map((id) => mention(id)), ...others].join(" ");
    const message = await channel
      .send({ content: content || undefined, ...render(deal), allowedMentions: { users, roles } })
      .catch(() => null);
    deal.messageId = message?.id || "";
    saveStore();
  }

  /* Next step: fold the previous card, then post the new one. */
  async function advance(deal, { summary, ping = [], notice = "" } = {}) {
    await foldStepCard(deal, summary || tr(deal, "✅  **Done**", "✅  **Fait**"));
    deal.notice = notice;
    await postStepCard(deal, ping);
  }

  /* A short coloured card (with pings) posted under the main deal card. */
  async function notify(deal, { title, body, color = COLORS.info, ping = [], thumbnail, components }) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const embed = new EmbedBuilder().setColor(color).setTitle(title).setDescription(body).setTimestamp();
    if (thumbnail) embed.setThumbnail(thumbnail);
    const mentions = ping.filter(Boolean).map((id) => (/^\d{15,25}$/.test(String(id)) ? mention(id) : id));
    await channel
      .send({ content: mentions.join(" ") || undefined, embeds: [embed], components, allowedMentions: { parse: ["users", "roles"] } })
      .catch(() => {});
  }

  /* ---------- the amount card: it carries its own Confirm / Decline buttons ---------- */

  const AMOUNT_CARD = (deal) => ({
    pending: { title: tr(deal, "💰  Amount to confirm", "💰  Montant à confirmer"), color: COLORS.wait },
    confirmed: { title: tr(deal, "✅  Amount confirmed", "✅  Montant confirmé"), color: COLORS.ok },
    declined: { title: tr(deal, "❌  Amount declined", "❌  Montant refusé"), color: COLORS.grey },
    superseded: { title: tr(deal, "↪️  Amount replaced", "↪️  Montant remplacé"), color: COLORS.grey },
  });

  function amountCard(deal, status = "pending", by = null) {
    const T = (en, fr) => tr(deal, en, fr);
    const info = AMOUNT_CARD(deal)[status];
    const pp = isPaypal(deal);
    const lines = [
      T(`${mention(deal.senderId)} set the amount to`, `${mention(deal.senderId)} a fixé le montant à`),
      pp ? `\`\`\`${fmtFiat(deal.amountCents, deal.currency)}\`\`\`` : `\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\``,
      !pp && deal.quote ? quoteText(deal.quote) : "",
      "",
    ];
    if (status === "pending") {
      lines.push(
        T(`📥 ${mention(deal.receiverId)} do you accept this amount?`, `📥 ${mention(deal.receiverId)} acceptes-tu ce montant ?`),
        pp ? T("🔒 Once you confirm, the amount is locked.", "🔒 Une fois confirmé, le montant est verrouillé.") : T("🔒 Once you confirm, the LTC figure is locked.", "🔒 Une fois confirmé, le montant en LTC est verrouillé.")
      );
    }
    if (status === "confirmed") lines.push(T(`Confirmed by ${mention(by)}. The amount is locked.`, `Confirmé par ${mention(by)}. Le montant est verrouillé.`));
    if (status === "declined") lines.push(T(`Declined by ${mention(by)}.`, `Refusé par ${mention(by)}.`));
    if (status === "superseded") lines.push(T("A new amount was proposed, or the deal was cancelled.", "Un nouveau montant a été proposé, ou le deal a été annulé."));
    return new EmbedBuilder().setColor(info.color).setTitle(info.title).setDescription(lines.join("\n")).setTimestamp();
  }

  const amountButtons = (deal) => [
    new ActionRowBuilder().addComponents(
      button("confirm_amount", tr(deal, "Confirm", "Confirmer"), ButtonStyle.Success, "✅"),
      button("decline_amount", tr(deal, "Decline", "Refuser"), ButtonStyle.Danger, "❌")
    ),
  ];

  async function postAmountCard(deal) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const message = await channel
      .send({ content: mention(deal.receiverId), embeds: [amountCard(deal)], components: amountButtons(deal), allowedMentions: { users: [deal.receiverId] } })
      .catch(() => null);
    deal.amountMsgId = message?.id || "";
    saveStore();
  }

  /* Closes the pending amount card (buttons removed) when it is replaced or the deal is cancelled. */
  async function closeAmountCard(deal, status) {
    if (!deal.amountMsgId) return;
    const channel = await getChannel(deal);
    const message = await channel?.messages.fetch(deal.amountMsgId).catch(() => null);
    await message?.edit({ embeds: [amountCard(deal, status)], components: [] }).catch(() => {});
    deal.amountMsgId = "";
  }

  /* Validates an amount typed by the sender, stores it and posts the Confirm / Decline card. */
  async function setDealAmount(deal, text, chosenCurrency) {
    const T = (en, fr) => tr(deal, en, fr);
    if (!["amount", "amount_confirm"].includes(deal.state)) return { error: T("The amount can no longer be changed.", "Le montant ne peut plus être modifié.") };

    if (isPaypal(deal)) {
      const parsed = parseFiatCents(text, deal, chosenCurrency);
      if (parsed.error) return { error: parsed.error };
      if (parsed.cents < cfg.paypalMinCents) return { error: T(`Minimum deal: ${fmtFiat(cfg.paypalMinCents, parsed.currency)}.`, `Deal minimum : ${fmtFiat(cfg.paypalMinCents, parsed.currency)}.`) };
      const tierError = await checkTier(deal, { cents: parsed.cents, currency: parsed.currency });
      if (tierError) return { error: tierError };
      await closeAmountCard(deal, "superseded");
      deal.amountCents = parsed.cents;
      deal.currency = parsed.currency;
      deal.state = "amount_confirm";
      saveStore();
      await foldStepCard(deal, T(`💰  **Amount proposed**  ·  ${fmtFiat(deal.amountCents, deal.currency)}`, `💰  **Montant proposé**  ·  ${fmtFiat(deal.amountCents, deal.currency)}`));
      await postAmountCard(deal);
      return {};
    }

    const result = await resolveAmount(text, deal).catch((error) => ({ error: error?.message || String(error) }));
    if (result.error) return { error: result.error };
    if (result.sat < cfg.minSat) {
      return { error: T(`That is only ${satToLtc(result.sat)} LTC. Minimum deal: ${satToLtc(cfg.minSat)} LTC.`, `Ça ne fait que ${satToLtc(result.sat)} LTC. Deal minimum : ${satToLtc(cfg.minSat)} LTC.`) };
    }
    const tierError = await checkTier(deal, { sat: result.sat, quote: result.quote });
    if (tierError) return { error: tierError };
    await closeAmountCard(deal, "superseded"); // a previous, still pending card is replaced
    deal.amountSat = result.sat;
    deal.quote = result.quote;
    deal.state = "amount_confirm";
    saveStore();
    await foldStepCard(deal, T(`💰  **Amount proposed**  ·  ${satToLtc(deal.amountSat)} LTC`, `💰  **Montant proposé**  ·  ${satToLtc(deal.amountSat)} LTC`));
    await postAmountCard(deal);
    return {};
  }

  async function logLine(text) {
    if (!options.logChannelId) return;
    const channel = await client.channels.fetch(options.logChannelId).catch(() => null);
    if (channel?.isTextBased()) await channel.send({ content: text, allowedMentions: { parse: [] } }).catch(() => {});
  }

  /* The role to ping: the role of the range of the deal when it has one, otherwise the general staff role. */
  const staffPing = (deal) => {
    if (deal && !isPaypal(deal)) return ltcAccess().length ? ltcAccess().map((id) => `<@&${id}>`).join(" ") : "An administrator";
    const id = dealTierRole(deal) || options.staffRoleId;
    return id ? `<@&${id}>` : "Staff";
  };
  const reply = (interaction, content) => interaction.reply({ content, flags: ephemeral });

  /* ---------- amount ranges ("tiers"): the person picks one before the ticket opens ---------- */

  const tierLabel = (t) => `${CUR[cfg.tierCurrency]}${t.min}${t.max === null ? "+" : ` – ${CUR[cfg.tierCurrency]}${t.max}`}`;
  const tierSlug = (t) => (t.max === null ? `${t.min}plus` : `${t.min}-${t.max}`).replace(/\./g, "_");

  /* Before the first start the ranges come from MM_TIERS; then they live in the store and are managed with /tiers. */
  const seedTiers = () => parseTiers(cfg.tiersEnv).map((t, i) => ({ id: `t${i + 1}`, min: t.min, max: t.max, roleId: "" }));

  function ensureTiers() {
    if (store.tiersReady) return;
    store.tiers = seedTiers();
    store.nextTier = store.tiers.length + 1;
    store.tiersReady = true;
    saveStore();
  }

  function tierList() {
    const list = store.tiersReady ? store.tiers : seedTiers();
    return [...list].sort((a, b) => a.min - b.min || (a.max ?? Infinity) - (b.max ?? Infinity));
  }
  const tierById = (id) => tierList().find((t) => t.id === id);
  const tierRoleId = (id) => tierById(id)?.roleId || "";
  /* The role that handles a deal (live: a change made in /tiers applies at once). */
  const dealTierRole = (deal) => (deal?.tier ? tierRoleId(deal.tier.id) : "");

  const tierOf = (id) => {
    const t = tierById(id);
    return t ? { id: t.id, min: t.min, max: t.max, slug: tierSlug(t), currency: cfg.tierCurrency, label: tierLabel(t) } : undefined;
  };

  /* The choices of the menu, in the language of the person. */
  function tierOptions(lang) {
    const fr = lang === "fr";
    const sym = CUR[cfg.tierCurrency];
    return tierList().map((t) => ({
      value: t.id,
      label: tierLabel(t),
      slug: tierSlug(t),
      description:
        t.max === null
          ? (fr ? `Deals au-dessus de ${sym}${t.min}` : `Deals above ${sym}${t.min}`)
          : t.min === 0
            ? (fr ? `Deals jusqu'à ${sym}${t.max}` : `Deals up to ${sym}${t.max}`)
            : (fr ? `Deals de ${sym}${t.min} à ${sym}${t.max}` : `Deals from ${sym}${t.min} to ${sym}${t.max}`),
    }));
  }

  /* The typed amount in the currency of the ranges, or null when it cannot be told (no price available). */
  async function tierValue(deal, input) {
    const to = cfg.tierCurrency;
    const prices = () => getLtcPrice().catch(() => null);
    const convert = async (amount, from) => {
      if (from === to) return amount;
      const p = await prices();
      return p ? amount * (from === "USD" ? p.eur / p.usd : p.usd / p.eur) : null;
    };
    if (isPaypal(deal)) return convert(input.cents / 100, input.currency || cfg.paypalCurrency);
    if (input.quote && !input.quote.indicative) return convert(input.quote.fiat, input.quote.currency); // typed in dollars or euros
    const p = await prices();                                                                        // typed in LTC
    return p ? (input.sat / SAT_PER_LTC) * (to === "EUR" ? p.eur : p.usd) : null;
  }

  /* An error text when the amount does not fit the range chosen for the ticket, otherwise null. */
  async function checkTier(deal, input) {
    const tier = deal.tier;
    if (!tier) return null;
    const value = await tierValue(deal, input);
    if (value == null) return null; // cannot compare without a price: do not block
    if (value >= tier.min - 0.005 && (tier.max === null || value <= tier.max + 0.005)) return null;
    const shown = `${CUR[tier.currency]}${value.toFixed(2)}`;
    return tr(
      deal,
      `This ticket is for deals of ${tier.label}. Your amount is about ${shown}. Open a ticket in the right range, or type another amount.`,
      `Ce ticket est pour les deals de ${tier.label}. Ton montant fait environ ${shown}. Ouvre un ticket dans la bonne tranche, ou écris un autre montant.`
    );
  }

  /* ---------- /tiers: the amount ranges and the staff role of each one, managed from Discord ---------- */

  const MAX_TIERS = 25;
  const trButton = (id, label, style = ButtonStyle.Secondary, emoji) => {
    const b = new ButtonBuilder().setCustomId(`tr:${id}`).setLabel(label).setStyle(style);
    if (emoji) b.setEmoji(emoji);
    return b;
  };
  const tierActiveDeals = (t) => Object.values(store.deals).filter((d) => d.tier?.id === t.id && !FINAL.has(d.state));

  function tiersView(selectedId) {
    const list = tierList();
    const selected = list.find((t) => t.id === selectedId);
    const embed = new EmbedBuilder()
      .setColor(0x5865f2)
      .setTitle("🎚️  Amount ranges")
      .setDescription(
        list.length
          ? list.map((t) => `**${tierLabel(t)}**  ·  ${t.roleId ? `<@&${t.roleId}>` : "*no role: general staff only*"}  ·  ${tierActiveDeals(t).length} open ticket(s)`).join("\n")
          : "*No range: tickets open without asking for one.*"
      )
      .setFooter({ text: "A member with the role of a range only sees and handles the tickets of that range  ·  the general staff role sees them all" });
    const rows = [];
    if (list.length) {
      rows.push(
        new ActionRowBuilder().addComponents(
          new StringSelectMenuBuilder()
            .setCustomId("tr:pick")
            .setPlaceholder("Choose a range to set its role, edit or remove it")
            .addOptions(list.slice(0, MAX_TIERS).map((t) => ({ label: tierLabel(t), description: t.roleId ? "Has a staff role" : "No staff role", value: t.id, default: t.id === selectedId })))
        )
      );
    }
    if (selected) {
      const role = new RoleSelectMenuBuilder().setCustomId(`tr:role:${selected.id}`).setPlaceholder(`Staff role for ${tierLabel(selected)}`).setMinValues(1).setMaxValues(1);
      if (selected.roleId) role.setDefaultRoles([selected.roleId]);
      rows.push(new ActionRowBuilder().addComponents(role));
      rows.push(
        new ActionRowBuilder().addComponents(
          trButton(`edit:${selected.id}`, "Edit range", ButtonStyle.Secondary, "✏️"),
          trButton(`clear:${selected.id}`, "Clear role", ButtonStyle.Secondary, "🧹").setDisabled(!selected.roleId),
          trButton(`remove:${selected.id}`, "Remove", ButtonStyle.Danger, "🗑️")
        )
      );
    }
    rows.push(
      new ActionRowBuilder().addComponents(
        trButton("add", "Add a range", ButtonStyle.Primary, "➕").setDisabled(list.length >= MAX_TIERS),
        trButton("reset", "Back to defaults", ButtonStyle.Secondary, "🔄")
      )
    );
    return { embeds: [embed], components: rows };
  }

  function tiersModal(customId, title, tier) {
    const input = (id, label, required, value) => {
      const field = new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(TextInputStyle.Short).setRequired(required).setMaxLength(12);
      if (value !== undefined && value !== "") field.setValue(String(value));
      return new ActionRowBuilder().addComponents(field);
    };
    return new ModalBuilder().setCustomId(customId).setTitle(title).addComponents(
      input("from", `From (in ${cfg.tierCurrency})`, true, tier ? tier.min : ""),
      input("to", "To (empty = and more)", false, tier && tier.max !== null ? tier.max : "")
    );
  }

  /* When the role of a range changes, the tickets that are still open follow (the bot edits their permissions). */
  async function syncTierAccess(tierId, oldRoleId, newRoleId) {
    if (oldRoleId === newRoleId) return 0;
    let touched = 0;
    for (const deal of Object.values(store.deals)) {
      if (deal.tier?.id !== tierId || FINAL.has(deal.state)) continue;
      const channel = await client.channels.fetch(deal.channelId).catch(() => null);
      if (!channel?.permissionOverwrites) continue;
      try {
        if (oldRoleId && oldRoleId !== options.staffRoleId) await channel.permissionOverwrites.delete(oldRoleId);
        if (newRoleId) await channel.permissionOverwrites.edit(newRoleId, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true });
        touched++;
      } catch (error) {
        console.error(`⚠️ Could not update the access of ticket #${deal.n}:`, error?.message || error);
      }
    }
    return touched;
  }

  async function handleTiersModal(interaction, parts) {
    const kind = parts[2]; // add | edit
    const id = parts[3];
    const number = (text) => {
      const v = Number(String(text).trim().replace(",", "."));
      return Number.isFinite(v) && v >= 0 ? Math.round(v * 100) / 100 : null;
    };
    const from = number(interaction.fields.getTextInputValue("from"));
    const toRaw = interaction.fields.getTextInputValue("to").trim();
    const andMore = toRaw === "" || toRaw === "+";
    const to = andMore ? null : number(toRaw);
    if (from === null) return reply(interaction, "❌ \"From\" must be a number, for example `25`.");
    if (!andMore && to === null) return reply(interaction, "❌ \"To\" must be a number, or empty for \"and more\".");
    if (to !== null && to <= from) return reply(interaction, "❌ \"To\" must be bigger than \"From\".");

    ensureTiers();
    if (kind === "edit" && !store.tiers.some((t) => t.id === id)) return reply(interaction, "❌ This range no longer exists.");
    const others = store.tiers.filter((t) => t.id !== id);
    const clash = others.find((t) => from < (t.max ?? Infinity) && (to ?? Infinity) > t.min);
    if (clash) return reply(interaction, `❌ This range overlaps **${tierLabel(clash)}**. Change that one first.`);

    let tier;
    if (kind === "add") {
      if (store.tiers.length >= MAX_TIERS) return reply(interaction, `❌ You can have at most ${MAX_TIERS} ranges.`);
      tier = { id: `t${store.nextTier++}`, min: from, max: to, roleId: "" };
      store.tiers.push(tier);
    } else {
      tier = store.tiers.find((t) => t.id === id);
      if (!tier) return reply(interaction, "❌ This range no longer exists.");
      tier.min = from;
      tier.max = to;
    }
    saveStore();

    const view = tiersView(tier.id);
    if (interaction.isFromMessage?.()) await interaction.update(view);
    else await interaction.reply({ ...view, flags: ephemeral });
    return logLine(`🎚️ Range ${kind === "add" ? "added" : "changed"}: **${tierLabel(tier)}** (by <@${interaction.user.id}>).`);
  }

  /* ---------- /access: which roles can see and handle the (private) Litecoin tickets ---------- */
  const OPEN_PERMS = { ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true };

  function accessView(note = "") {
    const list = ltcAccess();
    const embed = new EmbedBuilder()
      .setColor(0x5865f2)
      .setTitle("🔐  Litecoin ticket access")
      .setDescription(
        [
          "A Litecoin ticket is **private**: only the person who opened it and the person they add can see it.",
          "Pick below the roles that may also see and handle **every** Litecoin ticket (for example your owners). Administrators always can.",
          "",
          list.length ? `**Roles with access:** ${list.map((id) => `<@&${id}>`).join(" ")}` : "**Roles with access:** none (only administrators)",
          note,
        ].filter((x) => x !== "").join("\n")
      );
    const menu = new RoleSelectMenuBuilder().setCustomId("ac:roles").setPlaceholder("Roles that can see every Litecoin ticket").setMinValues(0).setMaxValues(10);
    if (list.length) menu.setDefaultRoles(list.slice(0, 10));
    return { embeds: [embed], components: [new ActionRowBuilder().addComponents(menu)] };
  }

  async function syncAccess(oldIds, newIds) {
    let touched = 0;
    for (const deal of Object.values(store.deals)) {
      if (isPaypal(deal) || FINAL.has(deal.state)) continue;
      const channel = await client.channels.fetch(deal.channelId).catch(() => null);
      if (!channel?.permissionOverwrites) continue;
      try {
        for (const id of oldIds) if (!newIds.includes(id) && id !== options.staffRoleId) await channel.permissionOverwrites.delete(id);
        for (const id of newIds) await channel.permissionOverwrites.edit(id, OPEN_PERMS);
        touched++;
      } catch (error) {
        console.error(`⚠️ Could not update the access of ticket #${deal.n}:`, error?.message || error);
      }
    }
    return touched;
  }

  async function handleAccessAdmin(interaction) {
    if (!isAdmin(interaction.member)) return reply(interaction, "❌ Only administrators can change who sees the Litecoin tickets.");
    if (interaction.isChatInputCommand?.()) return interaction.reply({ ...accessView(), flags: ephemeral });
    if (interaction.customId !== "ac:roles") return;
    const old = [...ltcAccess()];
    const next = [...new Set(interaction.values || [])].filter((id) => id !== interaction.guild?.id);
    store.access = next;
    saveStore();
    const touched = await syncAccess(old, next);
    await interaction.update(accessView(touched ? `✅ Saved. ${touched} open ticket(s) updated.` : "✅ Saved."));
    return logLine(`🔐 Litecoin ticket access set to ${next.length ? next.map((id) => `<@&${id}>`).join(" ") : "administrators only"} (by <@${interaction.user.id}>).`);
  }

  async function handleTiersAdmin(interaction) {
    if (!isAdmin(interaction.member)) return reply(interaction, "❌ Only administrators can change the amount ranges.");
    ensureTiers();
    if (interaction.isChatInputCommand?.()) return interaction.reply({ ...tiersView(""), flags: ephemeral });

    const parts = String(interaction.customId || "").split(":"); // tr:action[:id]  |  tr:m:add  |  tr:m:edit:id
    if (interaction.isModalSubmit?.()) return handleTiersModal(interaction, parts);

    const [, action, id] = parts;
    const tier = store.tiers.find((t) => t.id === id);
    const gone = () => reply(interaction, "❌ This range no longer exists.");

    const setRole = async (roleId) => {
      const old = tier.roleId;
      tier.roleId = roleId;
      saveStore();
      await interaction.update(tiersView(tier.id));
      const touched = await syncTierAccess(tier.id, old, roleId);
      if (touched) await interaction.followUp({ content: `✅ The access of ${touched} open ticket(s) was updated.`, flags: ephemeral });
      return logLine(`🎚️ Range **${tierLabel(tier)}**: ${roleId ? `role set to <@&${roleId}>` : "role cleared"} (by <@${interaction.user.id}>).`);
    };

    switch (action) {
      case "pick":
        return interaction.update(tiersView(interaction.values?.[0] || ""));

      case "role":
        if (!tier) return gone();
        return setRole(interaction.values?.[0] || "");

      case "clear":
        if (!tier) return gone();
        return setRole("");

      case "add":
        if (store.tiers.length >= MAX_TIERS) return reply(interaction, `❌ You can have at most ${MAX_TIERS} ranges.`);
        return interaction.showModal(tiersModal("tr:m:add", "Add a range"));

      case "edit":
        if (!tier) return gone();
        return interaction.showModal(tiersModal(`tr:m:edit:${id}`, "Edit this range", tier));

      case "remove": {
        if (!tier) return gone();
        const running = tierActiveDeals(tier).length;
        return interaction.update({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.bad)
              .setTitle("🗑️  Remove this range?")
              .setDescription(`**${tierLabel(tier)}**${tier.roleId ? `  ·  <@&${tier.roleId}>` : ""}${running ? `\n\n${running} open ticket(s) keep this range, but its role loses access to them.` : ""}`),
          ],
          components: [new ActionRowBuilder().addComponents(trButton(`rm_yes:${id}`, "Yes, remove", ButtonStyle.Danger), trButton(`rm_no:${id}`, "Cancel"))],
        });
      }

      case "rm_yes": {
        if (!tier) return gone();
        const old = tier.roleId;
        store.tiers = store.tiers.filter((t) => t.id !== id);
        saveStore();
        await interaction.update(tiersView(""));
        await syncTierAccess(id, old, "");
        return logLine(`🗑️ Range **${tierLabel(tier)}** removed by <@${interaction.user.id}>.`);
      }

      case "rm_no":
        return interaction.update(tiersView(id || ""));

      case "reset":
        return interaction.update({
          embeds: [
            new EmbedBuilder().setColor(COLORS.bad).setTitle("🔄  Back to the default ranges?").setDescription("All ranges are replaced by the default ones (**MM_TIERS** of your .env, or 0-25 … 2500+). **The roles you set are cleared.**"),
          ],
          components: [new ActionRowBuilder().addComponents(trButton("reset_yes", "Yes, reset", ButtonStyle.Danger), trButton("rm_no", "Cancel"))],
        });

      case "reset_yes": {
        const previous = store.tiers;
        const fresh = parseTiers(cfg.tiersEnv);
        store.tiers = fresh.map((t) => ({ id: `t${store.nextTier++}`, min: t.min, max: t.max, roleId: "" }));
        saveStore();
        await interaction.update(tiersView(""));
        for (const t of previous) if (t.roleId) await syncTierAccess(t.id, t.roleId, "");
        return logLine(`🔄 Ranges reset to the defaults by <@${interaction.user.id}>.`);
      }
    }
  }

  /* ---------- PayPal accounts, managed from Discord with /paypal ---------- */

  const MAX_PAYPAL = 4;
  const ppList = () => (store.paypal = Array.isArray(store.paypal) ? store.paypal : []);
  const ppActiveDeals = (account) => Object.values(store.deals).filter((d) => isPaypal(d) && d.ppId === account.id && !FINAL.has(d.state));
  const ppWaiting = (account) => ppActiveDeals(account).filter((d) => d.state === "awaiting_payment" && !d.paidClaimed);
  const isAdmin = (member) =>
    Boolean(member?.permissions?.has(PermissionFlagsBits.Administrator) || (options.ownerRoleId && member?.roles?.cache?.has(options.ownerRoleId)));

  /* configured: at least one account exists. available: at least one is present (not marked absent). */
  function paypalStatus() {
    return { configured: true, available: true };
  }

  /* The present account with the fewest deals in progress (never the one in `excludeId`). */
  function pickPaypal(excludeId) {
    const present = ppList().filter((a) => !a.away && a.id !== excludeId);
    present.sort((a, b) => ppActiveDeals(a).length - ppActiveDeals(b).length);
    return present[0] || null;
  }

  /* Deals waiting for a staff choice show the accounts that are present right now. */
  async function refreshChooseCards() {
    for (const deal of Object.values(store.deals)) {
      if (deal.state === "choose_pp") await refreshMain(deal).catch(() => {});
    }
  }

  /* The deal keeps a copy, so changing or removing an account never moves a deal that is already running. */
  function assignPaypal(deal, account) {
    deal.ppId = account.id;
    deal.ppEmail = account.email;
    deal.ppLabel = account.label;
    deal.ppHolder = account.holderId || "";
  }

  const ppButton = (id, label, style = ButtonStyle.Secondary, emoji) => {
    const b = new ButtonBuilder().setCustomId(`pp:${id}`).setLabel(label).setStyle(style);
    if (emoji) b.setEmoji(emoji);
    return b;
  };

  function paypalManagerView(admin) {
    const list = ppList();
    const embed = new EmbedBuilder()
      .setColor(0x0070ba)
      .setTitle("💙  PayPal accounts")
      .setDescription(
        list.length
          ? list.map((a) => `${a.away ? "🔴" : "🟢"}  **${a.label}**  ·  \`${a.email}\`${a.holderId ? `  ·  <@${a.holderId}>` : ""}\n${ppActiveDeals(a).length} deal(s) in progress`).join("\n\n")
          : "*No PayPal account yet.*\nAn administrator adds one with the button below."
      )
      .setFooter({ text: "A PayPal ticket needs at least one 🟢 present account  ·  each deal gets the least busy present one" });
    const rows = list.map((a) =>
      new ActionRowBuilder().addComponents(
        ppButton(`toggle:${a.id}`, `${a.away ? "🔴" : "🟢"} ${a.label}`.slice(0, 80), a.away ? ButtonStyle.Secondary : ButtonStyle.Success),
        ppButton(`edit:${a.id}`, "Edit", ButtonStyle.Secondary, "✏️").setDisabled(!admin),
        ppButton(`remove:${a.id}`, "Remove", ButtonStyle.Danger, "🗑️").setDisabled(!admin)
      )
    );
    rows.push(new ActionRowBuilder().addComponents(ppButton("add", "Add a PayPal account", ButtonStyle.Primary, "➕").setDisabled(!admin || list.length >= MAX_PAYPAL)));
    return { embeds: [embed], components: rows };
  }

  function ppModal(customId, title, account) {
    const input = (id, label, required, max, value) => {
      const field = new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(TextInputStyle.Short).setRequired(required).setMaxLength(max);
      if (value) field.setValue(value);
      return new ActionRowBuilder().addComponents(field);
    };
    return new ModalBuilder().setCustomId(customId).setTitle(title).addComponents(
      input("label", "Name (who owns it)", true, 20, account?.label),
      input("email", "PayPal email", true, 100, account?.email),
      input("holder", "Owner on Discord (@mention or ID, optional)", false, 60, account?.holderId)
    );
  }

  async function handlePaypalModal(interaction, parts, admin) {
    if (!admin) return reply(interaction, "❌ Only administrators can change the PayPal accounts.");
    const kind = parts[2]; // add | edit
    const label = interaction.fields.getTextInputValue("label").trim();
    const email = interaction.fields.getTextInputValue("email").trim();
    const holderRaw = interaction.fields.getTextInputValue("holder").trim();
    if (!label) return reply(interaction, "❌ Give the account a name.");
    if (!EMAIL.test(email)) return reply(interaction, "❌ That is not a valid email address.");
    const holderId = holderRaw ? holderRaw.match(/\d{15,25}/)?.[0] || "" : "";
    if (holderRaw && !holderId) return reply(interaction, "❌ Send the owner as an @mention or a numeric ID, or leave it empty.");

    const list = ppList();
    const duplicate = list.find((a) => a.email.toLowerCase() === email.toLowerCase() && a.id !== parts[3]);
    if (duplicate) return reply(interaction, `❌ **${duplicate.label}** already uses this email.`);

    if (kind === "add") {
      if (list.length >= MAX_PAYPAL) return reply(interaction, `❌ You can have at most ${MAX_PAYPAL} PayPal accounts.`);
      list.push({ id: `a${store.nextPaypal++}`, label, email, holderId, away: false });
    } else {
      const account = list.find((a) => a.id === parts[3]);
      if (!account) return reply(interaction, "❌ This account no longer exists.");
      Object.assign(account, { label, email, holderId });
    }
    saveStore();

    const view = paypalManagerView(true);
    if (interaction.isFromMessage?.()) await interaction.update(view);
    else await interaction.reply({ ...view, flags: ephemeral });
    await refreshChooseCards();
    return logLine(`💙 PayPal account ${kind === "add" ? "added" : "changed"}: **${label}** (by <@${interaction.user.id}>).`);
  }

  /* /paypal and its buttons (pp:...). Staff can open it and set accounts present / absent, administrators change the list. */
  async function handlePaypalAdmin(interaction) {
    if (!isStaff(interaction.member)) return reply(interaction, "❌ Staff only.");
    const admin = isAdmin(interaction.member);
    if (interaction.isChatInputCommand?.()) return interaction.reply({ ...paypalManagerView(admin), flags: ephemeral });

    const parts = String(interaction.customId || "").split(":"); // pp:action[:id]  |  pp:m:add  |  pp:m:edit:id
    if (interaction.isModalSubmit?.()) return handlePaypalModal(interaction, parts, admin);

    const [, action, id] = parts;
    const account = ppList().find((a) => a.id === id);
    const needAdmin = () => !admin && (reply(interaction, "❌ Only administrators can change the PayPal accounts."), true);
    const view = () => paypalManagerView(admin);

    switch (action) {
      case "add":
        if (needAdmin()) return;
        if (ppList().length >= MAX_PAYPAL) return reply(interaction, `❌ You can have at most ${MAX_PAYPAL} PayPal accounts.`);
        return interaction.showModal(ppModal("pp:m:add", "Add a PayPal account"));

      case "edit":
        if (needAdmin()) return;
        if (!account) return reply(interaction, "❌ This account no longer exists.");
        return interaction.showModal(ppModal(`pp:m:edit:${id}`, "Edit this PayPal account", account));

      case "toggle": {
        if (!account) return reply(interaction, "❌ This account no longer exists.");
        account.away = !account.away;
        saveStore();
        await interaction.update(view());
        if (account.away) {
          const waiting = ppWaiting(account).length;
          if (waiting) {
            await interaction.followUp({
              content: `⚠️ ${waiting} deal(s) are waiting for a payment on **${account.label}**. In each ticket, use **Staff tools → Switch PayPal account**.`,
              flags: ephemeral,
            });
          }
        }
        await refreshChooseCards();
        return logLine(`${account.away ? "🔴" : "🟢"} PayPal **${account.label}** set ${account.away ? "absent" : "present"} by <@${interaction.user.id}>.`);
      }

      case "remove": {
        if (needAdmin()) return;
        if (!account) return reply(interaction, "❌ This account no longer exists.");
        const running = ppActiveDeals(account).length;
        return interaction.update({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.bad)
              .setTitle("🗑️  Remove this PayPal account?")
              .setDescription(`**${account.label}**  ·  \`${account.email}\`${running ? `\n\n${running} deal(s) in progress keep using it until they end.` : ""}`),
          ],
          components: [new ActionRowBuilder().addComponents(ppButton(`rm_yes:${id}`, "Yes, remove", ButtonStyle.Danger), ppButton("rm_no", "Cancel"))],
        });
      }

      case "rm_yes": {
        if (needAdmin()) return;
        store.paypal = ppList().filter((a) => a.id !== id);
        saveStore();
        await interaction.update(view());
        await refreshChooseCards();
        return logLine(`🗑️ PayPal account **${account?.label || id}** removed by <@${interaction.user.id}>.`);
      }

      case "rm_no":
        return interaction.update(view());
    }
  }

  /* ---------- blockchain watcher ---------- */

  async function checkDeal(deal) {
    const utxos = await getUtxos(deal.address);
    if (!utxos.length) return;
    const tip = await getTipHeight();

    deal.paymentTxids = [...new Set(utxos.map((u) => u.txid))];
    const seenSat = utxos.reduce((sum, u) => sum + u.value, 0);
    const confirmedUtxos = utxos.filter((u) => confirmationsOf(u, tip) >= cfg.confirmations);
    const confirmedSat = confirmedUtxos.reduce((sum, u) => sum + u.value, 0);
    const minConf = Math.min(...utxos.map((u) => confirmationsOf(u, tip)));

    const before = `${deal.state}|${deal.seenSat}|${deal.confirmations}`;
    deal.seenSat = seenSat;
    deal.confirmations = minConf;

    if (confirmedSat >= deal.amountSat) {
      deal.state = "funded";
      deal.receivedSat = confirmedSat;
      saveStore();
      await refreshPaymentCard(deal);
      await advance(deal, { ping: [deal.receiverId, deal.senderId] });
      await logLine(`💰 Deal #${deal.n} funded: ${satToLtc(confirmedSat)} LTC (<#${deal.channelId}>).`);
      return;
    }

    if (deal.state === "awaiting_payment") {
      deal.state = "confirming";
      saveStore();
      await refreshMain(deal);
      await notify(deal, {
        title: tr(deal, "👀  Payment spotted", "👀  Paiement détecté"),
        body: tr(
          deal,
          `**${satToLtc(seenSat)} LTC** seen on the deposit address.\nThe confirmations are tracked live in the **payment card** above.`,
          `**${satToLtc(seenSat)} LTC** vus sur l'adresse de dépôt.\nLes confirmations sont suivies en direct sur la **carte de paiement** au-dessus.`
        ),
        color: 0xf57c00,
        ping: [deal.senderId, deal.receiverId],
      });
      return;
    }

    if (`${deal.state}|${deal.seenSat}|${deal.confirmations}` !== before) {
      saveStore();
      await refreshMain(deal);
    }

    if (confirmedSat > 0 && confirmedSat === seenSat && !deal.shortWarned) {
      deal.shortWarned = true;
      saveStore();
      await notify(deal, {
        title: tr(deal, "⚠️  Payment too small", "⚠️  Paiement trop faible"),
        body: tr(
          deal,
          `The confirmed payment is **${satToLtc(confirmedSat)} LTC** but the deal is **${satToLtc(deal.amountSat)} LTC**.\n\n📤 ${mention(deal.senderId)} send the missing **${satToLtc(deal.amountSat - confirmedSat)} LTC** to the same address,\nor ${staffPing(deal)} can refund it.`,
          `Le paiement confirmé est de **${satToLtc(confirmedSat)} LTC** mais le deal est de **${satToLtc(deal.amountSat)} LTC**.\n\n📤 ${mention(deal.senderId)} envoie les **${satToLtc(deal.amountSat - confirmedSat)} LTC** manquants à la même adresse,\nou ${staffPing(deal)} peut rembourser.`
        ),
        color: COLORS.bad,
        ping: [deal.senderId],
      });
    }
  }

  let ticking = false;
  async function watcherTick() {
    if (ticking) return;
    ticking = true;
    try {
      for (const deal of Object.values(store.deals)) {
        if (isPaypal(deal) || (deal.state !== "awaiting_payment" && deal.state !== "confirming")) continue;
        deal.lastCheck = Date.now();
        await withLock(deal.channelId, () => checkDeal(deal)).catch((error) =>
          console.error(`⚠️ Middleman: check failed for deal #${deal.n}:`, error?.message || error)
        );
        // refresh the card now and then so "Last check" stays alive (about once a minute)
        if (["awaiting_payment", "confirming"].includes(deal.state) && Date.now() - (deal.lastRefresh || 0) > 55000) {
          await refreshPaymentCard(deal).catch(() => {});
        }
      }
    } finally {
      ticking = false;
    }
  }

  /* ---------- sending funds (payout or refund) ---------- */

  async function sweep(deal, toAddress) {
    const tip = await getTipHeight();
    const utxos = (await getUtxos(deal.address)).filter((u) => confirmationsOf(u, tip) >= cfg.confirmations);
    const feeRate = await getFeeRate();
    const tx = buildSweepTx({ index: deal.index, utxos, toAddress, feeRate });
    const txid = await broadcast(tx.hex);
    return { ...tx, txid };
  }

  /* ---------- interactions ---------- */

  /* Called by index.js right after a "middleman" ticket channel was created. */
  async function openDeal(channel, user, method = "ltc", lang = "en", tierId = "") {
    const L = { lang: lang === "fr" ? "fr" : "en" };
    if (!enabled) {
      await channel.send(tr(L, "❌ The middleman is not configured yet (MM_SEED is missing). Staff has been notified in this ticket.", "❌ Le middleman n'est pas encore configuré (MM_SEED manque). Le staff est prévenu dans ce ticket."));
      return false;
    }
    if (method === "paypal" && !paypalStatus().available) {
      await channel.send(
        paypalStatus().configured
          ? tr(L, "❌ No PayPal account is available right now (everyone is absent). Staff has been notified in this ticket.", "❌ Aucun compte PayPal n'est disponible pour le moment (tout le monde est absent). Le staff est prévenu dans ce ticket.")
          : tr(L, "❌ PayPal is not set up yet: an administrator adds an account with `/paypal`. Staff has been notified in this ticket.", "❌ PayPal n'est pas encore configuré : un administrateur ajoute un compte avec `/paypal`. Le staff est prévenu dans ce ticket.")
      );
      return false;
    }

    const n = store.nextDeal++;
    const deal = {
      n,
      channelId: channel.id,
      messageId: "",
      userA: user.id,
      userB: null,
      lang: L.lang,
      tier: tierOf(tierId),
      method: method === "paypal" ? "paypal" : "ltc",
      amountCents: 0,
      currency: "",
      senderId: null,
      receiverId: null,
      amountSat: 0,
      state: "partner",
      frozen: false,
      index: null,
      address: "",
      seenSat: 0,
      confirmations: 0,
      receivedSat: 0,
      createdAt: Date.now(),
    };
    store.deals[channel.id] = deal;

    const message = await channel.send({
      content: mention(deal.userA),
      ...render(deal),
      allowedMentions: { users: [deal.userA] },
    });
    deal.messageId = message.id;
    saveStore();

    await logLine(`🆕 Middleman deal #${n} opened by <@${deal.userA}> (<#${channel.id}>)${deal.tier ? `, range ${deal.tier.label}` : ""}.`);
    return true;
  }

  /* Counts a finished deal for the panel statistics (kept even after the ticket is closed). */
  function recordStat(deal, outcome) {
    store.stats = store.stats && typeof store.stats === "object" ? store.stats : {};
    const key = isPaypal(deal) ? "paypal" : "ltc";
    const m = (store.stats[key] = { done: 0, refunded: 0, sat: 0, usd: 0, eur: 0, ...(store.stats[key] || {}) });
    if (outcome === "refunded") {
      m.refunded++;
      return;
    }
    m.done++;
    if (isPaypal(deal)) m[deal.currency === "EUR" ? "eur" : "usd"] += deal.amountCents || 0;
    else m.sat += deal.amountSat || 0;
  }

  /* Live numbers for a panel: deals done, in progress, and the volume handled. */
  function panelStats(method) {
    const key = method === "paypal" ? "paypal" : "ltc";
    const m = { done: 0, refunded: 0, sat: 0, usd: 0, eur: 0, ...((store.stats || {})[key] || {}) };
    const active = Object.values(store.deals).filter((d) => isPaypal(d) === (key === "paypal") && !FINAL.has(d.state)).length;
    const volume = key === "paypal" ? [m.usd ? `$${(m.usd / 100).toFixed(2)}` : "", m.eur ? `€${(m.eur / 100).toFixed(2)}` : ""].filter(Boolean).join(" + ") || "$0.00" : `${satToLtc(m.sat)} LTC`;
    return { done: m.done, refunded: m.refunded, active, volume };
  }

  /* Rules shown on the panel buttons (how much, how many confirmations). */
  function panelInfo() {
    return {
      confirmations: cfg.confirmations,
      minLtc: satToLtc(cfg.minSat),
      paypalMin: fmtFiat(cfg.paypalMinCents, cfg.paypalCurrency),
      paypalNote: cfg.paypalNote,
    };
  }

  /* Forget a finished deal when its ticket is closed. */
  function forget(channelId) {
    if (store.deals[channelId] && !blocksClose(channelId)) {
      delete store.deals[channelId];
      saveStore();
    }
  }

  /* True while a deal still holds (or may hold) funds: the ticket must not be closed then. */
  function blocksClose(channelId) {
    const deal = store.deals[channelId];
    if (!deal) return false;
    if (["confirming", "funded", "released", "payout_pending", "paying"].includes(deal.state)) return true;
    return deal.state === "awaiting_payment" && (deal.seenSat > 0 || Boolean(deal.paidClaimed));
  }

  /* Error texts that come from the Litecoin code, in the language of the ticket. */
  function errText(deal, message) {
    const m = String(message || "");
    if (!isFr(deal)) return m;
    if (/Network fee too high/.test(m)) return "Frais réseau trop élevés. Réessaie plus tard.";
    if (/too small to be sent/.test(m)) return "Le montant est trop petit pour être envoyé après les frais réseau.";
    if (/No funds to send/.test(m)) return "Aucun fonds à envoyer.";
    return m;
  }

  async function handleButton(interaction, deal, action, arg, extra) {
    const T = (en, fr) => tr(deal, en, fr);
    const user = interaction.user;
    const staff = staffFor(deal, interaction.member);
    const participant = isParticipant(deal, user.id);

    const needParticipant = () => !participant && !staff && (reply(interaction, T("❌ You are not part of this deal.", "❌ Tu ne fais pas partie de ce deal.")), true);
    const needStaff = () => !staff && (reply(interaction, T("❌ Staff only.", "❌ Réservé au staff.")), true);
    const frozenBlock = () => deal.frozen && (reply(interaction, T("🧊 This deal is frozen. Wait for staff.", "🧊 Ce deal est gelé. Attends le staff.")), true);

    switch (action) {
      case "partner": {
        if (user.id !== deal.userA) return reply(interaction, T("❌ Only the person who opened the ticket can add the other person.", "❌ Seule la personne qui a ouvert le ticket peut ajouter l'autre personne."));
        if (deal.state !== "partner") return reply(interaction, T("❌ The other person was already added.", "❌ L'autre personne a déjà été ajoutée."));
        return interaction.reply({
          flags: ephemeral,
          content: T("👤 **Who do you trade with?** Pick the person in the list.", "👤 **Avec qui échanges-tu ?** Choisis la personne dans la liste."),
          components: [new ActionRowBuilder().addComponents(new UserSelectMenuBuilder().setCustomId("mm:pickpartner").setPlaceholder(T("Search a member", "Cherche un membre")).setMinValues(1).setMaxValues(1))],
        });
      }

      case "role": {
        if (!participant) return reply(interaction, T("❌ You are not part of this deal.", "❌ Tu ne fais pas partie de ce deal."));
        if (deal.state !== "roles") return reply(interaction, T("❌ Roles are already set.", "❌ Les rôles sont déjà choisis."));
        const other = arg === "sender" ? "receiver" : "sender";
        if (deal[`${arg}Id`] && deal[`${arg}Id`] !== user.id) {
          return reply(interaction, T(`❌ The ${arg} role is already taken by the other person.`, `❌ Le rôle ${words(deal)[arg].toLowerCase()} est déjà pris par l'autre personne.`));
        }
        if (deal[`${other}Id`] === user.id) deal[`${other}Id`] = null;
        deal[`${arg}Id`] = user.id;
        const ready = Boolean(deal.senderId && deal.receiverId);
        if (ready) deal.state = "amount";
        saveStore();
        if (!ready) return interaction.update(render(deal)); // still choosing: this card updates in place
        await interaction.deferUpdate();
        return advance(deal, { summary: T(`✅  **Roles**  ·  📤 ${mention(deal.senderId)}  ·  📥 ${mention(deal.receiverId)}`, `✅  **Rôles**  ·  📤 ${mention(deal.senderId)}  ·  📥 ${mention(deal.receiverId)}`), ping: [deal.senderId] });
      }

      case "amount": {
        if (!["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, T("❌ The amount can no longer be changed.", "❌ Le montant ne peut plus être modifié."));
        if (user.id !== deal.senderId) return reply(interaction, T("❌ Only the LTC sender sets the amount.", "❌ Seul l'expéditeur des LTC fixe le montant."));
        if (isPaypal(deal) && arg !== "USD" && arg !== "EUR") {
          return interaction.reply({
            flags: ephemeral,
            content: T("💱 **Which currency?**", "💱 **Quelle devise ?**"),
            components: [new ActionRowBuilder().addComponents(button("amount:USD", T("Dollars ($)", "Dollars ($)"), ButtonStyle.Primary, "💵"), button("amount:EUR", T("Euros (€)", "Euros (€)"), ButtonStyle.Primary, "💶"))],
          });
        }
        const cur = isPaypal(deal) ? arg : "";
        const modal = new ModalBuilder().setCustomId(isPaypal(deal) ? `mm:m:amount:${cur}` : "mm:m:amount").setTitle(T("Amount to send", "Montant à envoyer"))
          .addComponents(new ActionRowBuilder().addComponents(
            isPaypal(deal)
              ? new TextInputBuilder().setCustomId("value").setLabel(T(`Amount in ${cur}`, `Montant en ${cur}`)).setPlaceholder(`5${CUR[cur]}`).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(24)
              : new TextInputBuilder().setCustomId("value").setLabel(T("Amount: 5$ / 5€ / 0.25 LTC", "Montant : 5$ / 5€ / 0.25 LTC")).setPlaceholder(T("0.01   (I will ask: dollars or LTC?)", "0.01   (je demanderai : dollars ou LTC ?)")).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(24)
          ));
        return interaction.showModal(modal);
      }

      case "confirm_amount": {
        if (deal.state !== "amount_confirm") return reply(interaction, T("❌ Nothing to confirm right now.", "❌ Rien à confirmer pour le moment."));
        if (user.id !== deal.receiverId) return reply(interaction, T("❌ Only the LTC receiver confirms the amount.", "❌ Seul le destinataire des LTC confirme le montant."));
        if (isPaypal(deal)) {
          deal.ref = deal.ref || makeRef(deal);
        } else if (!deal.address) {
          deal.index = store.nextIndex++;
          deal.address = addressOf(deal.index);
        }
        deal.state = isPaypal(deal) ? "choose_pp" : "awaiting_payment";
        saveStore();
        if (deal.messageId && interaction.message?.id === deal.messageId) {
          await interaction.deferUpdate(); // an old card carried the button: fold it
          await foldStepCard(deal, T("✅  **Amount confirmed**", "✅  **Montant confirmé**"));
        } else {
          deal.amountMsgId = "";
          await interaction.update({ embeds: [amountCard(deal, "confirmed", user.id)], components: [] });
        }
        if (isPaypal(deal)) return advance(deal, { ping: [staffPing(deal)] }); // a staff member now gives their PayPal
        return postPaymentCard(deal);
      }

      case "staffpp": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "choose_pp") return reply(interaction, T("❌ Nothing to do right now.", "❌ Rien à faire pour le moment."));
        if (isParticipant(deal, user.id)) return reply(interaction, T("❌ The two people of the deal cannot give the PayPal. A staff member does.", "❌ Les deux personnes du deal ne peuvent pas donner le PayPal. C'est un staff."));
        return interaction.showModal(
          new ModalBuilder().setCustomId("mm:m:staffpp").setTitle(T("Your PayPal", "Ton PayPal")).addComponents(
            new ActionRowBuilder().addComponents(
              new TextInputBuilder().setCustomId("value").setLabel(T("PayPal email that receives the payment", "Email PayPal qui reçoit le paiement")).setStyle(TextInputStyle.Short).setRequired(true).setMinLength(5).setMaxLength(100)
            )
          )
        );
      }

      case "release": {
        if (user.id !== deal.senderId) return reply(interaction, T("❌ Only the LTC sender can release the funds.", "❌ Seul l'expéditeur des LTC peut libérer les fonds."));
        if (deal.state !== "funded") return reply(interaction, T("❌ The funds are not ready to be released.", "❌ Les fonds ne sont pas prêts à être libérés."));
        if (frozenBlock()) return;
        return interaction.reply({
          flags: ephemeral,
          content: T("⚠️ Release the funds **only if you received what was agreed**. This cannot be undone.", "⚠️ Libère les fonds **seulement si tu as bien reçu ce qui était convenu**. C'est irréversible."),
          components: [new ActionRowBuilder().addComponents(button("release_yes", T("Yes, I received it", "Oui, j'ai tout reçu"), ButtonStyle.Success), button("release_no", T("No", "Non"), ButtonStyle.Secondary))],
        });
      }

      case "pick": {
        if (user.id !== deal.senderId) return reply(interaction, T("❌ Only the LTC sender sets the amount.", "❌ Seul l'expéditeur des LTC fixe le montant."));
        if (!["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, T("❌ The amount can no longer be changed.", "❌ Le montant ne peut plus être modifié."));
        if ((arg !== "usd" && arg !== "ltc") || !parseAmountInput(extra)?.bare) return reply(interaction, T("❌ Invalid choice.", "❌ Choix invalide."));
        await interaction.update({ content: T("⏳ Setting the amount…", "⏳ Enregistrement du montant…"), components: [] });
        const outcome = await withLock(deal.channelId, () => setDealAmount(deal, arg === "usd" ? `${extra}$` : `${extra} ltc`));
        return interaction.editReply({
          content: outcome.error ? `❌ ${outcome.error}` : T("✅ Sent to the receiver for confirmation.", "✅ Envoyé au destinataire pour confirmation."),
          components: [],
        });
      }

      case "copy": {
        if (user.id !== deal.senderId && !staff) return reply(interaction, T("❌ Only the sender needs the payment details.", "❌ Seul l'expéditeur a besoin des infos de paiement."));
        if (!["awaiting_payment", "confirming"].includes(deal.state)) return reply(interaction, T("❌ There is nothing to pay right now.", "❌ Il n'y a rien à payer pour le moment."));
        if (isPaypal(deal)) {
          await interaction.reply({ content: deal.ppEmail, flags: ephemeral });
          await interaction.followUp({ content: (deal.amountCents / 100).toFixed(2), flags: ephemeral });
          await interaction.followUp({ content: deal.ref, flags: ephemeral });
          return interaction.followUp({
            content: T(
              `📋 **Tap and hold** a message above, then **Copy Text**.\n1️⃣ the **PayPal email**   2️⃣ the **amount** (${deal.currency})   3️⃣ the **reference** to write in the PayPal note`,
              `📋 **Appuie longuement** sur un message ci-dessus, puis **Copier le texte**.\n1️⃣ l'**email PayPal**   2️⃣ le **montant** (${deal.currency})   3️⃣ la **référence** à écrire dans la note PayPal`
            ),
            flags: ephemeral,
          });
        }
        // one value per message so "Copy Text" on mobile copies exactly that value
        await interaction.reply({ content: deal.address, flags: ephemeral });
        await interaction.followUp({ content: satToLtc(deal.amountSat), flags: ephemeral });
        return interaction.followUp({
          content: T(
            "📋 **Tap and hold** a message above, then **Copy Text**.\n1️⃣ the **address**   2️⃣ the **amount** in LTC\nSend exactly that amount to that address.",
            "📋 **Appuie longuement** sur un message ci-dessus, puis **Copier le texte**.\n1️⃣ l'**adresse**   2️⃣ le **montant** en LTC\nEnvoie exactement ce montant à cette adresse."
          ),
          flags: ephemeral,
        });
      }

      case "decline_amount": {
        if (deal.state !== "amount_confirm") return reply(interaction, T("❌ Nothing to decline right now.", "❌ Rien à refuser pour le moment."));
        if (user.id !== deal.receiverId) return reply(interaction, T("❌ Only the LTC receiver can decline the amount.", "❌ Seul le destinataire des LTC peut refuser le montant."));
        const declined = { ...deal };
        deal.state = "amount";
        deal.amountSat = 0;
        deal.quote = null;
        deal.amountMsgId = "";
        saveStore();
        await interaction.update({ embeds: [amountCard(declined, "declined", user.id)], components: [] });
        return advance(deal, { ping: [deal.senderId], notice: T(`❌  ${mention(user.id)} declined the previous amount.`, `❌  ${mention(user.id)} a refusé le montant précédent.`) });
      }

      case "paid": {
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, T("❌ Nothing to confirm right now.", "❌ Rien à confirmer pour le moment."));
        if (user.id !== deal.senderId) return reply(interaction, T("❌ Only the payer can say the payment was sent.", "❌ Seul le payeur peut dire que le paiement est envoyé."));
        if (frozenBlock()) return;
        if (deal.paidClaimed) return reply(interaction, T("Staff was already notified.", "Le staff a déjà été prévenu."));
        deal.paidClaimed = true;
        saveStore();
        await ack(interaction, deal);
        await notify(deal, {
          title: T("💸  Payment sent?", "💸  Paiement envoyé ?"),
          body: T(
            `${mention(user.id)} says the PayPal payment is sent.\n\n${staffPing(deal)} check PayPal for **${fmtFiat(deal.amountCents, deal.currency)}** with the reference \`${deal.ref}\`, then open **Staff tools → Payment received**.`,
            `${mention(user.id)} dit que le paiement PayPal est envoyé.\n\n${staffPing(deal)} vérifiez PayPal : **${fmtFiat(deal.amountCents, deal.currency)}** avec la référence \`${deal.ref}\`, puis ouvrez **Outils staff → Paiement reçu**.`
          ),
          color: 0xf57c00,
          ping: [staffPing(deal), deal.ppHolder],
        });
        return logLine(`💸 Deal #${deal.n}: payer says PayPal ${fmtFiat(deal.amountCents, deal.currency)} sent, ref ${deal.ref} (<#${deal.channelId}>).`);
      }

      case "mark_paid": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, T("❌ Nothing to confirm right now.", "❌ Rien à confirmer pour le moment."));
        deal.state = "funded";
        saveStore();
        await ack(interaction, deal, false);
        await refreshPaymentCard(deal);
        await advance(deal, { ping: [deal.receiverId, deal.senderId] });
        return logLine(`💙 Deal #${deal.n}: PayPal payment verified by <@${user.id}> (${fmtFiat(deal.amountCents, deal.currency)}).`);
      }

      case "ppick": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "choose_pp") return reply(interaction, T("❌ Nothing to choose right now.", "❌ Rien à choisir pour le moment."));
        const account = ppList().find((a) => a.id === arg);
        if (!account || account.away) {
          await reply(interaction, T("❌ This PayPal account is no longer available. The list was refreshed.", "❌ Ce compte PayPal n'est plus disponible. La liste a été actualisée."));
          return refreshMain(deal);
        }
        assignPaypal(deal, account);
        deal.state = "awaiting_payment";
        saveStore();
        await interaction.deferUpdate();
        await foldStepCard(deal, T(`✅  **PayPal account**  ·  **${account.label}** chosen by ${mention(user.id)}`, `✅  **Compte PayPal**  ·  **${account.label}** choisi par ${mention(user.id)}`));
        await postPaymentCard(deal);
        return logLine(`💙 Deal #${deal.n}: PayPal account ${account.label} chosen by <@${user.id}>.`);
      }

      case "switch_pp": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, T("❌ Nothing to change right now.", "❌ Rien à changer pour le moment."));
        if (deal.paidClaimed) return reply(interaction, T("❌ The payer says it is already paid: check PayPal first.", "❌ Le payeur dit avoir déjà payé : vérifie d'abord PayPal."));
        const others = ppList().filter((a) => !a.away && a.id !== deal.ppId).slice(0, 4);
        if (!others.length) return reply(interaction, T("❌ No other PayPal account is available.", "❌ Aucun autre compte PayPal n'est disponible."));
        return interaction.reply({
          content: T("🔁 Which PayPal account should this deal use instead?", "🔁 Quel compte PayPal ce deal doit-il utiliser à la place ?"),
          components: [new ActionRowBuilder().addComponents(others.map((a) => button(`ppswitch:${a.id}`, a.label.slice(0, 80), ButtonStyle.Primary, "💙")))],
          flags: ephemeral,
        });
      }

      case "ppswitch": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return interaction.update({ content: T("❌ Nothing to change right now.", "❌ Rien à changer pour le moment."), components: [] });
        if (deal.paidClaimed) return interaction.update({ content: T("❌ The payer says it is already paid: check PayPal first.", "❌ Le payeur dit avoir déjà payé : vérifie d'abord PayPal."), components: [] });
        const account = ppList().find((a) => a.id === arg);
        if (!account || account.away || account.id === deal.ppId) return interaction.update({ content: T("❌ This PayPal account is not available.", "❌ Ce compte PayPal n'est pas disponible."), components: [] });
        assignPaypal(deal, account);
        saveStore();
        await interaction.update({ content: T(`✅ This deal now uses **${account.label}**.`, `✅ Ce deal utilise maintenant **${account.label}**.`), components: [] });
        await refreshPaymentCard(deal);
        return notify(deal, {
          title: T("🔁  PayPal account changed", "🔁  Compte PayPal changé"),
          body: T(
            `Please pay to the **new** account shown in the payment card: **${account.label}**.\nDo not use the previous one.`,
            `Paie sur le **nouveau** compte indiqué sur la carte de paiement : **${account.label}**.\nN'utilise pas l'ancien.`
          ),
          color: 0xf57c00,
          ping: [deal.senderId],
        });
      }

      case "payout_sent": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "payout_pending") return reply(interaction, T("❌ Nothing to confirm right now.", "❌ Rien à confirmer pour le moment."));
        return interaction.showModal(noteModal("mm:m:payout_sent", T("Payout sent", "Versement envoyé"), T("PayPal transaction ID (optional)", "ID de transaction PayPal (facultatif)")));
      }

      case "release_no":
        return interaction.update({ content: T("Cancelled, nothing was released.", "Annulé, rien n'a été libéré."), components: [] });

      case "release_yes": {
        if (user.id !== deal.senderId) return reply(interaction, T("❌ Only the LTC sender can release the funds.", "❌ Seul l'expéditeur des LTC peut libérer les fonds."));
        if (deal.state !== "funded" || deal.frozen) return interaction.update({ content: T("❌ Not possible right now.", "❌ Impossible pour le moment."), components: [] });
        deal.state = "released";
        saveStore();
        await interaction.update({ content: T("✅ Released.", "✅ Libéré."), components: [] });
        return advance(deal, {
          summary: T(`✅  **Delivery confirmed**  ·  ${mention(deal.senderId)} released the funds`, `✅  **Livraison confirmée**  ·  ${mention(deal.senderId)} a libéré les fonds`),
          ping: [deal.receiverId],
        });
      }

      case "payout": {
        if (user.id !== deal.receiverId) return reply(interaction, T("❌ Only the LTC receiver can enter the payout address.", "❌ Seul le destinataire des LTC peut entrer l'adresse de versement."));
        if (deal.state !== "released") return reply(interaction, T("❌ The funds were not released yet.", "❌ Les fonds n'ont pas encore été libérés."));
        if (frozenBlock()) return;
        return interaction.showModal(
          isPaypal(deal) ? emailModal(deal) : addressModal("mm:m:payout", T("Where should we send the LTC?", "Où envoyer les LTC ?"), T("Your Litecoin address", "Ton adresse Litecoin"))
        );
      }

      case "dispute": {
        if (needParticipant()) return;
        if (deal.frozen) return reply(interaction, T("Already frozen.", "Déjà gelé."));
        deal.frozen = true;
        saveStore();
        await ack(interaction, deal);
        await notify(deal, {
          title: T("🚨  Staff called", "🚨  Staff appelé"),
          body: T(
            `${mention(user.id)} called staff on deal #${deal.n}.\nThe deal is **frozen** until staff decides.`,
            `${mention(user.id)} a appelé le staff sur le deal #${deal.n}.\nLe deal est **gelé** jusqu'à la décision du staff.`
          ),
          color: COLORS.bad,
          ping: [staffPing(deal)],
        });
        return logLine(`🚨 Deal #${deal.n} frozen by <@${user.id}> (<#${deal.channelId}>).`);
      }

      case "staff": {
        if (needStaff()) return;
        const rows = staffComponents(deal);
        if (!rows.length) return reply(interaction, T("Nothing to do for staff right now.", "Rien à faire pour le staff pour le moment."));
        return interaction.reply({ content: T(`🛠️ **Staff tools** · deal #${deal.n}`, `🛠️ **Outils staff** · deal #${deal.n}`), components: rows, flags: ephemeral });
      }

      case "unfreeze": {
        if (needStaff()) return;
        deal.frozen = false;
        saveStore();
        await ack(interaction, deal);
        return notify(deal, {
          title: T("🧊  Deal unfrozen", "🧊  Deal dégelé"),
          body: T(`Unfrozen by ${mention(user.id)}. The deal can continue.`, `Dégelé par ${mention(user.id)}. Le deal peut continuer.`),
          color: COLORS.info,
        });
      }

      case "force_release": {
        if (needStaff()) return;
        if (deal.state !== "funded") return reply(interaction, T("❌ Funds are not in a releasable state.", "❌ Les fonds ne sont pas dans un état libérable."));
        deal.state = "released";
        deal.frozen = false;
        saveStore();
        await ack(interaction, deal, false);
        await advance(deal, { summary: T(`⚖️  **Released by staff**  ·  ${mention(user.id)}`, `⚖️  **Libéré par le staff**  ·  ${mention(user.id)}`), ping: [deal.receiverId] });
        return logLine(`⚖️ Deal #${deal.n} force-released by <@${user.id}>.`);
      }

      case "refund": {
        if (needStaff()) return;
        if (isPaypal(deal)) {
          if (!["funded", "released", "payout_pending"].includes(deal.state)) return reply(interaction, T("❌ Nothing to refund.", "❌ Rien à rembourser."));
          return interaction.showModal(noteModal("mm:m:refund_pp", T("Refund the payer", "Rembourser le payeur"), T("PayPal refund transaction ID (optional)", "ID du remboursement PayPal (facultatif)")));
        }
        if (!["confirming", "funded", "released"].includes(deal.state)) return reply(interaction, T("❌ Nothing to refund.", "❌ Rien à rembourser."));
        return interaction.showModal(addressModal("mm:m:refund", T("Refund address of the sender", "Adresse de remboursement de l'expéditeur"), T("Sender's Litecoin address", "Adresse Litecoin de l'expéditeur")));
      }

      case "cancel": {
        if (needParticipant()) return;
        if (!["partner", "roles", "amount", "amount_confirm", "choose_pp", "awaiting_payment"].includes(deal.state) || (isPaypal(deal) && deal.paidClaimed)) {
          return reply(interaction, T("❌ This deal can no longer be cancelled here. Call staff.", "❌ Ce deal ne peut plus être annulé ici. Appelle le staff."));
        }
        await closeAmountCard(deal, "superseded");
        deal.state = "cancelled";
        saveStore();
        await ack(interaction, deal, false);
        await refreshPaymentCard(deal);
        return advance(deal, { summary: T(`✖️  **Cancelled**  ·  by ${mention(user.id)}`, `✖️  **Annulé**  ·  par ${mention(user.id)}`) });
      }

      case "close": {
        if (needStaff()) return;
        if (!FINAL.has(deal.state)) return reply(interaction, T("❌ The deal is not finished.", "❌ Le deal n'est pas terminé."));
        await interaction.deferUpdate().catch(() => {}); // acknowledged with no message: the channel is gone right away
        delete store.deals[deal.channelId];
        saveStore();
        return interaction.channel?.delete().catch((error) => console.error("⚠️ Could not delete the ticket:", error?.message || error));
      }
    }
  }

  const emailModal = (deal) =>
    new ModalBuilder().setCustomId("mm:m:payout").setTitle(tr(deal, "Where should staff pay you?", "Où le staff doit-il te payer ?")).addComponents(
      new ActionRowBuilder().addComponents(
        new TextInputBuilder().setCustomId("value").setLabel(tr(deal, "Your PayPal email", "Ton email PayPal")).setStyle(TextInputStyle.Short).setRequired(true).setMinLength(5).setMaxLength(100)
      )
    );

  const noteModal = (id, title, label) =>
    new ModalBuilder().setCustomId(id).setTitle(title).addComponents(
      new ActionRowBuilder().addComponents(
        new TextInputBuilder().setCustomId("value").setLabel(label).setStyle(TextInputStyle.Short).setRequired(false).setMaxLength(100)
      )
    );

  function addressModal(id, title, label) {
    return new ModalBuilder().setCustomId(id).setTitle(title).addComponents(
      new ActionRowBuilder().addComponents(
        new TextInputBuilder().setCustomId("value").setLabel(label).setStyle(TextInputStyle.Short).setRequired(true).setMinLength(20).setMaxLength(110)
      )
    );
  }

  /* The person is picked in a user menu (an @mention typed in a text box is not recognised by Discord). */
  async function handlePartnerPick(interaction, deal) {
    const T = (en, fr) => tr(deal, en, fr);
    const user = interaction.user;
    if (user.id !== deal.userA || deal.state !== "partner") return interaction.update({ content: T("❌ Not possible right now.", "❌ Impossible pour le moment."), components: [] });
    const id = interaction.values?.[0];
    if (!id) return;
    if (id === user.id) return interaction.update({ content: T("❌ You cannot trade with yourself. Pick someone else.", "❌ Tu ne peux pas échanger avec toi-même. Choisis quelqu'un d'autre."), components: interaction.message?.components || [] });
    const member = await interaction.guild.members.fetch(id).catch(() => null);
    if (!member || member.user.bot) {
      return interaction.update({ content: T("❌ I could not find that person in this server (bots are not allowed).", "❌ Je ne trouve pas cette personne sur ce serveur (les bots ne sont pas autorisés)."), components: interaction.message?.components || [] });
    }
    await interaction.channel.permissionOverwrites.edit(id, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true });
    deal.userB = id;
    deal.state = "roles";
    saveStore();
    await interaction.update({ content: T(`✅ Added ${mention(id)}.`, `✅ ${mention(id)} ajouté.`), components: [] });
    return advance(deal, { summary: T(`✅  **Partner added**  ·  ${mention(id)}`, `✅  **Partenaire ajouté**  ·  ${mention(id)}`), ping: [deal.userA, id] });
  }

  async function handleModal(interaction, deal, kind, arg) {
    const T = (en, fr) => tr(deal, en, fr);
    const user = interaction.user;
    const value = interaction.fields.getTextInputValue("value").trim();

    if (kind === "partner") {
      if (user.id !== deal.userA || deal.state !== "partner") return reply(interaction, T("❌ Not possible right now.", "❌ Impossible pour le moment."));
      const id = value.match(/\d{15,25}/)?.[0];
      if (!id) return reply(interaction, T("❌ Send an @mention or the numeric user ID.", "❌ Envoie une @mention ou l'ID numérique de l'utilisateur."));
      if (id === user.id) return reply(interaction, T("❌ You cannot trade with yourself.", "❌ Tu ne peux pas échanger avec toi-même."));
      const member = await interaction.guild.members.fetch(id).catch(() => null);
      if (!member || member.user.bot) {
        return reply(interaction, T("❌ I could not find that person in this server (bots are not allowed).", "❌ Je ne trouve pas cette personne sur ce serveur (les bots ne sont pas autorisés)."));
      }
      await interaction.channel.permissionOverwrites.edit(id, {
        ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true,
      });
      deal.userB = id;
      deal.state = "roles";
      saveStore();
      await interaction.deferUpdate();
      return advance(deal, { summary: T(`✅  **Partner added**  ·  ${mention(id)}`, `✅  **Partenaire ajouté**  ·  ${mention(id)}`), ping: [deal.userA, id] });
    }

    if (kind === "amount") {
      if (user.id !== deal.senderId || !["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, T("❌ Not possible right now.", "❌ Impossible pour le moment."));
      const parsed = isPaypal(deal) ? null : parseAmountInput(value);
      if (!isPaypal(deal) && !parsed) {
        return reply(interaction, T("❌ Invalid amount. Examples: `5$` (dollars), `5€` (euros), `0.25 ltc`.", "❌ Montant invalide. Exemples : `5$` (dollars), `5€` (euros), `0.25 ltc`."));
      }

      if (parsed?.bare) {
        // "0.01" alone is ambiguous: show both readings side by side and let the sender pick
        await interaction.deferReply({ flags: ephemeral });
        const prices = await getLtcPrice().catch(() => null);
        const asLtc = ltcToSat(parsed.value);
        const dollarSat = prices ? Math.round((Number(parsed.value) / prices.usd) * SAT_PER_LTC) : 0;
        const dollarLabel = prices ? `$${parsed.value}  =  ${satToLtc(dollarSat)} LTC` : `$${parsed.value} ${T("(price unavailable)", "(cours indisponible)")}`;
        const ltcLabel = asLtc
          ? `${parsed.value} LTC${prices ? `  (≈ $${fmtMoney((asLtc / SAT_PER_LTC) * prices.usd)})` : ""}`
          : T("invalid LTC amount", "montant LTC invalide");
        return interaction.editReply({
          content: T(
            `**${parsed.value}** what do you mean?\nPick one, the receiver then confirms it.`,
            `**${parsed.value}** qu'est-ce que tu veux dire ?\nChoisis, le destinataire confirmera ensuite.`
          ),
          components: [
            new ActionRowBuilder().addComponents(
              button(`pick:usd:${parsed.value}`, dollarLabel.slice(0, 80), ButtonStyle.Primary, "💵").setDisabled(!prices || dollarSat < 1),
              button(`pick:ltc:${parsed.value}`, ltcLabel.slice(0, 80), ButtonStyle.Secondary, "🪙").setDisabled(!asLtc)
            ),
          ],
        });
      }

      await interaction.deferUpdate(); // the price lookup can take a moment
      const outcome = await withLock(deal.channelId, () => setDealAmount(deal, value, arg));
      if (outcome.error) return interaction.followUp({ content: `❌ ${outcome.error}`, flags: ephemeral });
      return;
    }

    if (isPaypal(deal) && kind === "staffpp") {
      if (!staffFor(deal, interaction.member) || isParticipant(deal, user.id)) return reply(interaction, T("❌ Staff only.", "❌ Réservé au staff."));
      if (deal.state !== "choose_pp") return reply(interaction, T("❌ This is not possible in the current state of the deal.", "❌ Impossible dans l'état actuel du deal."));
      if (!EMAIL.test(value)) return reply(interaction, T("❌ That is not a valid PayPal email address.", "❌ Ce n'est pas une adresse email PayPal valide."));
      deal.ppId = "";
      deal.ppEmail = value;
      deal.ppLabel = interaction.member?.displayName || user.username || "Staff";
      deal.ppHolder = user.id;
      deal.state = "awaiting_payment";
      saveStore();
      await reply(interaction, T("✅ Your PayPal is set. The payer sees it now.", "✅ Ton PayPal est enregistré. Le payeur le voit maintenant."));
      await foldStepCard(deal, T(`✅  **PayPal**  ·  given by ${mention(user.id)}`, `✅  **PayPal**  ·  donné par ${mention(user.id)}`));
      await postPaymentCard(deal);
      return logLine(`💙 Deal #${deal.n}: PayPal given by <@${user.id}> (<#${deal.channelId}>).`);
    }

    if (isPaypal(deal) && kind === "payout") {
      if (user.id !== deal.receiverId) return reply(interaction, T("❌ Not allowed.", "❌ Non autorisé."));
      if (deal.state !== "released" || deal.frozen) return reply(interaction, T("❌ This is not possible in the current state of the deal.", "❌ Impossible dans l'état actuel du deal."));
      if (!EMAIL.test(value)) return reply(interaction, T("❌ That is not a valid PayPal email address.", "❌ Ce n'est pas une adresse email PayPal valide."));
      deal.payoutPaypal = value;
      deal.state = "payout_pending";
      saveStore();
      await reply(interaction, T("✅ Sent to staff. They pay you and mark the deal as done.", "✅ Envoyé au staff. Il te paie puis marque le deal comme terminé."));
      await advance(deal, { summary: T("🏦  **PayPal email received**", "🏦  **Email PayPal reçu**"), ping: [staffPing(deal), deal.senderId] });
      return logLine(`🏦 Deal #${deal.n}: pay ${fmtFiat(deal.amountCents, deal.currency)} to ${value} (<#${deal.channelId}>).`);
    }

    if (isPaypal(deal) && kind === "payout_sent") {
      if (!staffFor(deal, interaction.member)) return reply(interaction, T("❌ Staff only.", "❌ Réservé au staff."));
      if (deal.state !== "payout_pending") return reply(interaction, T("❌ This is not possible in the current state of the deal.", "❌ Impossible dans l'état actuel du deal."));
      deal.resultNote = value;
      deal.state = "done";
      recordStat(deal, "done");
      saveStore();
      await reply(interaction, T("✅ Deal marked as done.", "✅ Deal marqué comme terminé."));
      await advance(deal, { summary: T(`🏦  **Payout sent by staff**  ·  ${mention(user.id)}`, `🏦  **Versement envoyé par le staff**  ·  ${mention(user.id)}`), ping: [deal.receiverId, deal.senderId] });
      return logLine(`✅ Deal #${deal.n}: PayPal payout sent by <@${user.id}>.`);
    }

    if (isPaypal(deal) && kind === "refund_pp") {
      if (!staffFor(deal, interaction.member)) return reply(interaction, T("❌ Staff only.", "❌ Réservé au staff."));
      if (!["funded", "released", "payout_pending"].includes(deal.state)) return reply(interaction, T("❌ Nothing to refund.", "❌ Rien à rembourser."));
      deal.resultNote = value;
      deal.state = "refunded";
      recordStat(deal, "refunded");
      saveStore();
      await reply(interaction, T("✅ Deal marked as refunded.", "✅ Deal marqué comme remboursé."));
      await refreshPaymentCard(deal);
      await advance(deal, { summary: T(`↩️  **Refunded by staff**  ·  ${mention(user.id)}`, `↩️  **Remboursé par le staff**  ·  ${mention(user.id)}`), ping: [deal.senderId] });
      return logLine(`↩️ Deal #${deal.n}: PayPal payment refunded by <@${user.id}>.`);
    }

    // payout / refund: both send the whole balance of the deal address
    const isRefund = kind === "refund";
    if (isRefund ? !staffFor(deal, interaction.member) : user.id !== deal.receiverId) return reply(interaction, T("❌ Not allowed.", "❌ Non autorisé."));
    if (!isValidLtcAddress(value)) return reply(interaction, T("❌ That is not a valid Litecoin address.", "❌ Ce n'est pas une adresse Litecoin valide."));
    if (value === deal.address) return reply(interaction, T("❌ You cannot send the funds back to the deposit address.", "❌ Tu ne peux pas renvoyer les fonds vers l'adresse de dépôt."));

    await interaction.deferReply({ flags: ephemeral });

    const result = await withLock(deal.channelId, async () => {
      const allowed = isRefund ? ["confirming", "funded", "released"] : ["released"];
      if (!allowed.includes(deal.state) || (!isRefund && deal.frozen)) {
        return { error: T("This is not possible in the current state of the deal.", "Impossible dans l'état actuel du deal.") };
      }
      const previous = deal.state;
      deal.state = "paying"; // saved first so a restart never pays twice
      saveStore();
      try {
        const sent = await sweep(deal, value);
        if (isRefund) {
          deal.state = "refunded";
          deal.refundAddress = value;
          deal.refundTxid = sent.txid;
        } else {
          deal.state = "done";
          deal.payoutAddress = value;
          deal.payoutTxid = sent.txid;
        }
        deal.feeSat = sent.fee;
        deal.sentSat = sent.outValue;
        recordStat(deal, isRefund ? "refunded" : "done");
        saveStore();
        return { sent };
      } catch (error) {
        deal.state = previous;
        saveStore();
        return { error: errText(deal, error?.message || String(error)) };
      }
    });

    if (result.error) {
      console.error(`⚠️ Middleman: ${isRefund ? "refund" : "payout"} failed for deal #${deal.n}:`, result.error);
      return interaction.editReply(T(`❌ Could not send the funds: ${result.error}\nNothing was lost, you can try again.`, `❌ Impossible d'envoyer les fonds : ${result.error}\nRien n'est perdu, tu peux réessayer.`));
    }

    const { sent } = result;
    await interaction.editReply(T("✅ Funds sent.", "✅ Fonds envoyés."));
    await refreshPaymentCard(deal);
    await advance(deal, {
      summary: isRefund
        ? T(`↩️  **Refunded by staff**  ·  ${satToLtc(sent.outValue)} LTC`, `↩️  **Remboursé par le staff**  ·  ${satToLtc(sent.outValue)} LTC`)
        : T(`🏦  **Payout address received**  ·  ${satToLtc(sent.outValue)} LTC sent`, `🏦  **Adresse de versement reçue**  ·  ${satToLtc(sent.outValue)} LTC envoyés`),
      ping: isRefund ? [deal.senderId] : [deal.receiverId, deal.senderId],
    });
    return logLine(`${isRefund ? "↩️ Refund" : "✅ Payout"} deal #${deal.n}: ${satToLtc(sent.outValue)} LTC, tx ${sent.txid}`);
  }

  /* Returns true when the interaction belongs to the middleman, so index.js stops there. */
  async function handleInteraction(interaction) {
    const id = interaction.customId;
    const isPayPalCommand = Boolean(interaction.isChatInputCommand?.()) && interaction.commandName === "paypal";
    if (isPayPalCommand || (typeof id === "string" && id.startsWith("pp:"))) {
      try {
        if (!enabled) await reply(interaction, "❌ The middleman is not configured yet (MM_SEED is missing).");
        else await handlePaypalAdmin(interaction);
      } catch (error) {
        console.error("⚠️ PayPal accounts error:", error?.message || error);
        const message = "❌ Something went wrong. Check the bot console.";
        if (interaction.deferred || interaction.replied) await interaction.followUp({ content: message, flags: ephemeral }).catch(() => {});
        else await interaction.reply({ content: message, flags: ephemeral }).catch(() => {});
      }
      return true;
    }
    const isAccessCommand = Boolean(interaction.isChatInputCommand?.()) && interaction.commandName === "access";
    if (isAccessCommand || (typeof id === "string" && id.startsWith("ac:"))) {
      try {
        if (!enabled) await reply(interaction, "❌ The middleman is not configured yet (MM_SEED is missing).");
        else await handleAccessAdmin(interaction);
      } catch (error) {
        console.error("⚠️ Access error:", error?.message || error);
        const message = "❌ Something went wrong. Check the bot console.";
        if (interaction.deferred || interaction.replied) await interaction.followUp({ content: message, flags: ephemeral }).catch(() => {});
        else await interaction.reply({ content: message, flags: ephemeral }).catch(() => {});
      }
      return true;
    }
    const isTiersCommand = Boolean(interaction.isChatInputCommand?.()) && interaction.commandName === "tiers";
    if (isTiersCommand || (typeof id === "string" && id.startsWith("tr:"))) {
      try {
        if (!enabled) await reply(interaction, "❌ The middleman is not configured yet (MM_SEED is missing).");
        else await handleTiersAdmin(interaction);
      } catch (error) {
        console.error("⚠️ Amount ranges error:", error?.message || error);
        const message = "❌ Something went wrong. Check the bot console.";
        if (interaction.deferred || interaction.replied) await interaction.followUp({ content: message, flags: ephemeral }).catch(() => {});
        else await interaction.reply({ content: message, flags: ephemeral }).catch(() => {});
      }
      return true;
    }
    if (typeof id !== "string" || !id.startsWith("mm:")) return false;

    // the language of the ticket also tells how to answer when the deal itself is gone
    const L = { lang: /:fr$/.test(interaction.channel?.topic || "") ? "fr" : "en" };
    try {
      if (!enabled) {
        await reply(interaction, tr(L, "❌ The middleman is not configured yet (MM_SEED is missing).", "❌ Le middleman n'est pas encore configuré (MM_SEED manque)."));
        return true;
      }

      const deal = store.deals[interaction.channelId];
      if (!deal) {
        await reply(interaction, tr(L, "❌ This deal no longer exists.", "❌ Ce deal n'existe plus."));
        return true;
      }
      L.lang = deal.lang === "fr" ? "fr" : "en";

      const parts = id.split(":"); // mm:action[:arg]  |  mm:m:kind
      if (interaction.isModalSubmit()) await handleModal(interaction, deal, parts[2], parts[3]);
      else if (interaction.isUserSelectMenu?.() && parts[1] === "pickpartner") await handlePartnerPick(interaction, deal);
      else if (interaction.isButton()) await handleButton(interaction, deal, parts[1], parts[2], parts[3]);
    } catch (error) {
      console.error("⚠️ Middleman error:", error?.message || error);
      const message = tr(L, "❌ Something went wrong. Check the bot console.", "❌ Une erreur est survenue. Regarde la console du bot.");
      if (interaction.deferred || interaction.replied) await interaction.followUp({ content: message, flags: ephemeral }).catch(() => {});
      else await interaction.reply({ content: message, flags: ephemeral }).catch(() => {});
    }
    return true;
  }

  function init(discordClient, opts = {}) {
    client = discordClient;
    options = { ...options, ...opts };
    if (!cfg.seed) {
      console.log("ℹ️ Middleman disabled (set MM_SEED to enable it).");
      return;
    }
    try {
      initWallet();
      loadStore();
    } catch (error) {
      console.error("❌ Middleman disabled:", error.message);
      return;
    }

    // A restart in the middle of a payout leaves the deal in "paying": staff must check it on the explorer.
    for (const deal of Object.values(store.deals)) {
      if (deal.state === "paying") {
        deal.frozen = true;
        deal.state = "released";
        saveStore();
        console.error(`⚠️ Middleman: deal #${deal.n} was interrupted while sending. Check ${deal.address} on the explorer before retrying.`);
      }
    }

    // MM_PAYPAL_EMAIL in the .env becomes the first account, once; after that /paypal is the only place to manage them
    if (!Array.isArray(store.paypal)) store.paypal = [];
    if (!store.paypal.length && EMAIL.test(cfg.paypalEmail)) {
      store.paypal.push({ id: `a${store.nextPaypal || 1}`, label: "Main", email: cfg.paypalEmail, holderId: "", away: false });
      store.nextPaypal = (store.nextPaypal || 1) + 1;
      saveStore();
    }

    ensureTiers();

    enabled = true;
    timer = setInterval(() => watcherTick().catch((e) => console.error("Middleman watcher error:", e?.message || e)), cfg.pollMs);
    console.log(`💱 Middleman enabled (${cfg.confirmations} confirmation(s), polling every ${cfg.pollMs / 1000}s).`);
  }

  /* node vxmp-mm.js new-seed          -> prints a fresh seed
     node vxmp-mm.js new-seed --save   -> writes it straight into .env (nothing to copy)  */
  function newSeed(save, force) {
    const existing = cfg.seed;
    const mnemonic = bip39.generateMnemonic();
    cfg.seed = mnemonic;
    initWallet();

    if (!save) {
      console.log("\nMM_SEED=" + mnemonic);
      console.log("First deposit address:", addressOf(0));
      console.log("\nPut the MM_SEED line in your .env, and back the words up OFFLINE. Anyone with them controls the funds.\n");
      return;
    }

    if (bip39.validateMnemonic(existing) && !force) {
      console.log("\n⚠️ A valid MM_SEED is already in your .env, so I did not touch it (its funds would be lost).");
      console.log("Back it up, then run: node vxmp-mm.js new-seed --save --force\n");
      return;
    }

    const file = path.join(process.cwd(), ".env");
    let text = "";
    try {
      text = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
    } catch {
      // no .env yet: it will be created
    }
    const out = [];
    let skipping = false;
    for (const line of text.split(/\r?\n/)) {
      if (/^\s*MM_SEED\s*=/.test(line)) { skipping = true; continue; }
      if (skipping && line.trim() && !/^\s*#/.test(line) && !/^\s*[A-Za-z_][A-Za-z0-9_]*\s*=/.test(line)) continue;
      skipping = false;
      out.push(line);
    }
    while (out.length && !out[out.length - 1].trim()) out.pop();
    out.push("MM_SEED=" + mnemonic);
    fs.writeFileSync(file, out.join("\n") + "\n");

    console.log("\n✅ New seed saved in .env (not shown here).");
    console.log("First deposit address:", addressOf(0));
    console.log('Back it up: run "notepad .env", write the 12 words on paper, close it. Anyone with them controls the funds.\n');
  }

  /* Is this member staff for the ticket of that channel? (general staff, or the role of its amount range) */
  const isStaffFor = (channelId, member) => (store.deals[channelId] ? staffFor(store.deals[channelId], member) : isStaff(member));

  return { init, openDeal, blocksClose, forget, handleInteraction, newSeed, paypalStatus, tierOptions, tierRole: tierRoleId, isStaffFor, accessRoles: ltcAccess, panelStats, panelInfo };
})();

/* =====================================================
   IMAGES: smooth picture cards drawn by the bot itself (no library to install).
   Text uses the Outfit font (c) 2021 The Outfit Project Authors, SIL Open Font License 1.1,
   embedded below as a small subset (Latin letters, digits and common signs).
===================================================== */

const gfx = (() => {
  const zlib = require("zlib");

  /* ---------- PNG writer ---------- */
  const CRC = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c >>> 0;
    }
    return table;
  })();
  const crc32 = (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };

  /* ---------- PNG reader (for avatars): 8/16 bit, grey / RGB / palette / alpha, not interlaced ---------- */
  function decodePng(buf) {
    try {
      buf = Buffer.from(buf);
      if (buf.length < 33 || buf.readUInt32BE(0) !== 0x89504e47) return null;
      let pos = 8;
      let ihdr = null;
      let plte = null;
      let trns = null;
      const idat = [];
      while (pos + 8 <= buf.length) {
        const len = buf.readUInt32BE(pos);
        const type = buf.toString("ascii", pos + 4, pos + 8);
        const data = buf.subarray(pos + 8, pos + 8 + len);
        if (type === "IHDR") ihdr = { w: data.readUInt32BE(0), h: data.readUInt32BE(4), depth: data[8], color: data[9], interlace: data[12] };
        else if (type === "PLTE") plte = data;
        else if (type === "tRNS") trns = data;
        else if (type === "IDAT") idat.push(data);
        else if (type === "IEND") break;
        pos += 12 + len;
      }
      if (!ihdr || ihdr.interlace || !idat.length || ihdr.w * ihdr.h > 4096 * 4096) return null;
      const { w, h, depth, color } = ihdr;
      const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[color];
      if (!channels || ![1, 2, 4, 8, 16].includes(depth)) return null;
      const bitsPerPixel = channels * depth;
      const bpp = Math.max(1, bitsPerPixel >> 3);
      const stride = Math.ceil((w * bitsPerPixel) / 8);
      const raw = zlib.inflateSync(Buffer.concat(idat));
      const img = Buffer.alloc(stride * h);
      for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)];
        const src = y * (stride + 1) + 1;
        const dst = y * stride;
        for (let x = 0; x < stride; x++) {
          const a = x >= bpp ? img[dst + x - bpp] : 0;
          const b = y > 0 ? img[dst - stride + x] : 0;
          const c = x >= bpp && y > 0 ? img[dst - stride + x - bpp] : 0;
          let v = raw[src + x];
          if (f === 1) v += a;
          else if (f === 2) v += b;
          else if (f === 3) v += (a + b) >> 1;
          else if (f === 4) {
            const pa = Math.abs(b - c);
            const pb = Math.abs(a - c);
            const pc = Math.abs(a + b - 2 * c);
            v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          }
          img[dst + x] = v & 255;
        }
      }
      const out = new Uint8Array(w * h * 4);
      const sample = (row, index) => {
        // value `index` (in samples) of a row, scaled to 0..255 for depths below 8
        if (depth === 8) return img[row + index];
        if (depth === 16) return img[row + index * 2];
        const perByte = 8 / depth;
        const byte = img[row + Math.floor(index / perByte)];
        const shift = 8 - depth * ((index % perByte) + 1);
        return (byte >> shift) & ((1 << depth) - 1);
      };
      for (let y = 0; y < h; y++) {
        const row = y * stride;
        for (let x = 0; x < w; x++) {
          const o = (y * w + x) * 4;
          let r, g, b, a = 255;
          if (color === 3) {
            const i = sample(row, x);
            r = plte[i * 3]; g = plte[i * 3 + 1]; b = plte[i * 3 + 2];
            if (trns && i < trns.length) a = trns[i];
          } else if (color === 0) {
            const v = sample(row, x);
            r = g = b = depth < 8 ? Math.round((v * 255) / ((1 << depth) - 1)) : v;
          } else if (color === 4) {
            r = g = b = sample(row, x * 2);
            a = sample(row, x * 2 + 1);
          } else {
            r = sample(row, x * channels); g = sample(row, x * channels + 1); b = sample(row, x * channels + 2);
            if (color === 6) a = sample(row, x * channels + 3);
          }
          out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a;
        }
      }
      return { w, h, data: out };
    } catch {
      return null;
    }
  }

  /* ---------- colours ---------- */
  const hex = (h) => {
    if (Array.isArray(h)) return h;
    let s = String(h).replace("#", "");
    if (s.length === 3) s = s.split("").map((c) => c + c).join("");
    return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
  };
  const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
  const smooth = (a, b, v) => {
    const t = clamp01((v - a) / (b - a));
    return t * t * (3 - 2 * t);
  };
  const mixc = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  /* A paint is a colour or a function (x, y) -> [r, g, b]. */
  const lin = (x0, y0, x1, y1, stops) => {
    const s = stops.map(([t, c]) => [t, hex(c)]);
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len2 = dx * dx + dy * dy || 1;
    return (x, y) => {
      const t = clamp01(((x - x0) * dx + (y - y0) * dy) / len2);
      for (let i = 1; i < s.length; i++) if (t <= s[i][0]) return mixc(s[i - 1][1], s[i][1], (t - s[i - 1][0]) / (s[i][0] - s[i - 1][0] || 1));
      return s[s.length - 1][1];
    };
  };
  const radial = (cx, cy, r, stops) => {
    const s = stops.map(([t, c]) => [t, hex(c)]);
    return (x, y) => {
      const t = clamp01(Math.hypot(x - cx, y - cy) / r);
      for (let i = 1; i < s.length; i++) if (t <= s[i][0]) return mixc(s[i - 1][1], s[i][1], (t - s[i - 1][0]) / (s[i][0] - s[i - 1][0] || 1));
      return s[s.length - 1][1];
    };
  };
  const rngOf = (seed) => {
    let h = 1779033703 ^ String(seed).length;
    for (const ch of String(seed)) {
      h = Math.imul(h ^ ch.charCodeAt(0), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    let a = h >>> 0;
    return () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };

  /* ---------- fonts: a small TrueType reader and an exact-coverage rasteriser ---------- */
  const B64 = {
    bold: "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",
    regular: "AAEAAAAHAEAAAgAwY21hcMkPayMAADo4AAAB9GdseWYHbnL9AAAAfAAANFBoZWFkKctaLwAANpQAAAA2aGhlYRGJDI8AADoUAAAAJGhtdHijcyS6AAA2zAAAA0hsb2NhBrr59QAANOwAAAGmbWF4cADqAQMAADTMAAAAIAACAB8AAAKaArYABwALAABzATMBIwMzAzc1IRUfARxEARtm6SPrIwFtArb9SgJL/bWdUlL//wAfAAACmgPHBiYAAQAAAAcAxwDPANv//wAfAAACmgO/BiYAAQAAAAcAyACJANv//wAfAAACmgN5BiYAAQAAAAcAxQCDANv//wAfAAACmgO/BiYAAQAAAAcAxgC8ANv//wAfAAACmgOABiYAAQAAAAcAyQC8AH///wAfAAACmgN7BiYAAQAAAAcAygB4ANsABgAfAAADoAK2AAUACQANABEAFQAZAABzATMVIwM3NSEVFzUhFSERMxEDNSEVATUhFR8BHP/E8ycBaRwBcf5PXiABUv6wAWsCtlb9oPVSUvVWVgK2/UoBOlJSASZWVgAAAgBSAAACQgK2ACQAKAAAczUzMjY1NCYmIyM1MzI2NTQmIyM1MzIWFhUUBgc3FhYVFAYGIyERMxGR0jxEHjkm1ccyOz4zw8VEWy89OwhDSzZlSf70XlJHMiI3IFI1MjI1UjFQMDhUGB4YYUI3WDUCtv1KAAABAC//9gKPAsAAIQAARSIuAjU0PgIzMhYXByYmIyIOAhUUHgIzMjY3FwYGAY1LgF80NF9/S1J8MEEhXz03XEQlJURcN0FgIUEwgQo3YoJKS4JhNzgwQSUqJ0hiOjpiSCcrJUAyOP//AC//LwKPAsAGJgAKAAAABwDMAOgAAAACAFIAAAK0ArYAFwAbAABzNTMyNjY1NCYmIyM1MzIeAhUUDgIjIREzEZDBTXRBQnRMwMJMgV81NV6BS/79XlZDdk1MdkJWNF5+S0p/XjQCtv1KAAADABYAAALDArYAAwAbAB8AAFMhFSETNTMyNjY1NCYmIyM1MzIeAhUUDgIjIREzERYBdP6MicFNdEFCdEzAwkyBXzU1XoFL/v1eAYdP/shWQ3ZNTHZCVjRefktKf140Arb9SgAABABSAAACIAK2AAMABwALAA8AAHMRMxEjNSEVATUhFQE1IRVSXh4Bjv5yAW3+kwGJArb9SlZWATpSUgEmVlYA//8AUgAAAiADxwYmAA4AAAAHAMcArwDb//8AUgAAAiADvwYmAA4AAAAHAMgAaADb//8AUgAAAiADeQYmAA4AAAAHAMUAYwDb//8AUgAAAiADvwYmAA4AAAAHAMYAmwDbAAMAUgAAAg0CtgADAAcACwAAcxEzEQM1IRUBNSEVUl4eAWr+lgF7Arb9SgExVlYBL1ZWAAABAC//9gLZAsAAJQAARSIuAjU0PgIzMhYXByYmIyIGBhUUFhYzMjY2NRchNSEVFAYGAYxJf182NmCBTFOML0EhbEBMdUFCcEhJazo5/tQBVFWXCjdigktLgWI2QDxBMDNEeE5PeEQ4bU8pVg55o1IAAwBSAAACcAK2AAMABwALAABzETMRIREzEQE1IRVSXgFiXv4iAZcCtv1KArb9SgE8VlYAAAEAUgAAALACtgADAABzETMRUl4Ctv1K//8AHQAAAOUDxwYmABYAAAAHAMf/9QDb////1gAAASwDvwYmABYAAAAHAMj/rgDb////5QAAAR4DeQYmABYAAAAHAMX/qQDb//8ACQAAANIDvwYmABYAAAAHAMb/4QDbAAEAHv/2AaUCtgARAABXIiYnNxYWMzI2NjURMxEUBgbSPFsdQhM5IyM2H143XwovKD0cHh47KwHi/iNFZjgAAgBSAAACfAK2AAYACgAAYQEBMwE1ASERMxEB//6iAVd6/o4BfP3WXgFqAUz+nDT+egK2/UoAAgBSAAACBgK2AAMABwAAcxEzESM1IRVSXh4BdAK2/UpWVgAAAQBSAAAC9QK2AA8AAHMRMwEjATMRIxEXAyMDNxFSQgEmLQEmQl4W6ELoFQK2/h0B4/1KAhEG/oMBfQb97wADAFIAAAJ0ArYABAAIAA0AAHMRMxcRIQE3AQcnETMRUkIcAYL+VgwBqw0cXgK2bf23Ajl9/ch+ZwJP/UoA//8AUgAAAnQDewYmAB8AAAAHAMoAgADbAAIAL//2AusCwAATACUAAEUiLgI1ND4CMzIeAhUUDgInMjY2NTQuAiMiBgYVFB4CAY5KgGA1NV9/Skp/YDY2X39LS3FCJkRcOEpxQSVDXQo3Y4JKS4FiNjZigktKgmI3WkV5TjphSCdEeE46Y0coAP//AC//9gLrA8cGJgAhAAAABwDHAQAA2///AC//9gLrA78GJgAhAAAABwDIALoA2///AC//9gLrA3kGJgAhAAAABwDFALQA2///AC//9gLrA78GJgAhAAAABwDGAO0A2wADAC7/9gLqAsAAAwAXACkAAEEXAScFIi4CNTQ+AjMyHgIVFA4CJzI2NjU0LgIjIgYGFRQeAgKqPv2IPgFcSoBgNjZff0pKf2A1NV9/S0pyQSVEXDhKckEmQ10Ctj79iD5IN2OCSkuBYjY2YoJLSoJiN1pFeU46YUgnRHhOOmNHKAD//wAv//YC6wN7BiYAIQAAAAcAygCpANsAAgBSAAACNAK2ABUAGQAAUzUzMjY2NTQmJiMjNTMyFhYVFAYGIwERMxGRvSc9IyM9J73DQGU7O2VA/v5eAQ5SIDooKDogUjRfQUBfNf7yArb9SgAAAgBSAAACNAK2ABUAGQAAdzUzMjY2NTQmJiMjNTMyFhYVFAYGIwURMxGRvSc9IyM9J73DQGU7O2VA/v5ej1MfOigoOx9SNF9BQF81jwK2/UoAAAMAL//PAxcCwAATABcAKQAARSIuAjU0PgIzMh4CFRQOAgUBNwElMjY2NTQuAiMiBgYVFB4CAY9KgGA2Nl9/Skp/YDU1X38BA/67PQFE/nZKckElRFw4SnJBJkNdCjdjgkpLgWI2NmKCS0qCYjcnAUU9/rtERXlOOmFIJ0R4TjpjRygAAAMAUgAAAlkCtgATABcAGwAAUzUzMjY1NCYjIzUzMhYWFRQGBiMDETMRIQM3AZG8PUJBPb3AQmI1NWJC/14BMvxZARoBLk8+NTJCUjNYOTtYMf7SArb9SgE3H/6qAAABACD/9gH+AsAAKgAARSImJzcWFjMyNjU0LgU1NDY2MzIWFwcmJiMiBhUUHgUVFAYBE1J0LUAhVj8+SyQ9SEg8JTljPkRsIkAfRy44QiU8SUg8JX8KPDlALi82LycwHxkdK0Y1O1MtNStAJCQxLCMrHhkeLkk3XGgAAAIAHgAAAlMCtgADAAcAAGERMxEBNSEVAQpe/rYCNQKi/V4CYFZWAAABAEr/9gJiArYAFQAARSImJjURMxEUFhYzMjY2NREzERQGBgFWTXlGXi5PMTNNLV9GeApFeU0Btf5NN1AsLFA2AbT+Sk14Rf//AEr/9gJiA8cGJgAuAAAABwDHAMkA2///AEr/9gJiA78GJgAuAAAABwDIAIIA2///AEr/9gJiA3kGJgAuAAAABwDFAH0A2///AEr/9gJiA78GJgAuAAAABwDGALUA2wABAB8AAAKRArYABwAAYQEzEyMTMwEBNf7qZuUl52X+6AK2/bUCS/1KAAABACAAAAO0ArYADwAAYQMzEyMTMxMjEzMDIwMzAwED4160G7FEsRq0XeJDshqxArb9ygI2/coCNv1KAjX9ywAAAwAeAAAClQK2AAcACwAPAABhAyMBMxMzASEBFwMBJxMzAifaEf7ucNgRARL9iQENQOMBAT/WagE+AXj+1f51AXE4/scBTzgBLwACAB0AAAJ9ArYABwALAABBATMTIxMzAQMRMxEBLv7vbdwx3Wv+7UxeARoBnP6vAVH+ZP7mAVj+qAD//wAdAAACfQPHBiYANgAAAAcAxwDAANsAAwAnAAACHQK2AAMACAANAAB3ATMBBzU3IRUBNSEVBycBiG7+eG5QAZ/+JgHhUUECNf3LQUEVVgJgVkAWAAADACT/9gIFAeUAEAAfACYAAEUiJiY1NDY2MzIWFhcVDgInMjY1NCYmIyIGBhUUFhYXNTcnNTMRAQxBaj09aUI2VTQDAzNVKENSJUQtLUUnJ0a8ERFbCkFwRkZwQi1PNI8zUC1VW0cxSSkqSS8wSSpLgHRzdP4lAP//ACT/9gIFAuwGJgA5AAAABwDHAJkAAP//ACT/9gIFAuQGJgA5AAAABgDIUgD//wAk//YCBQKeBiYAOQAAAAYAxU0A//8AJP/2AgUC5AYmADkAAAAHAMYAhQAA//8AJP/2AgUDAQYmADkAAAAHAMkAhgAA//8AJP/2AgUCoAYmADkAAAAGAMpCAP//ACT/9gOFAeUEJwBGAY0AAAAGADkAAAADAEL/9gIiAsoAEAAXACcAAEUiJiYnNT4CMzIWFhUUBgYlETMRBxcVNzI2NjU0JiYjIgYGFRQWFgE8Nlc0AwM1VzVBaTw8af7FWhERkS1EKChELC1EJiVFCi1QM480Ty1CcEZGcEEKAsr+nXN0gEsqSTAvSikpSjAvSSoAAQAj//YB0gHlAB0AAEUiJiY1NDY2MzIWFwcmJiMiBgYVFBYWMzI2NxcGBgEbRnFBQXFGN14iPBY/Ji1GKChGLSY/FzshXwpCcUVGcEEpJzwaGylILy9IKhsaPCYq//8AI/8vAdIB5QYmAEIAAAAGAMx6AAADACT/9gIFAsoAEAAgACcAAEUiJiY1NDY2MzIWFhcVDgInMjY2NTQmJiMiBgYVFBYWBSM1NycRMwELQmg9PWhCNVY1AwM0VictQyYnQy0tRCcnRQEYWxERWwpBcEZGcEItTzSPM1AtVSpJLzFIKipJLzBJKkuAdHMBYwAAAwAo//YCDQK2ABUAJQApAABFIiYmNTQ2NjMyFhYXJwMzExYVFAYGJzI2NjU0JiYjIgYGFRQWFgMnJRcBG0RtQjxkPSMxIQwi0W7MQEBuRCpDJiZDKilEKChDfxoBTRkKQW5CQ2U6EB0VEgEd/uVbXEJsQFgoRisrRSgoRSsrRSkBokF7QQABACP/9gH4AeUAJQAARSImJjU0NjYzMhYWFRQGByE1IQc0JiYjIgYGFRQWFjMyNjcXBgYBHkdyQkFvRUJlOQID/m8BYSEiPiwuRiYoSjAoQxg6ImMKQXBHRnBBPGpDChcPSx0wQyUoSDEySykcHDsoKv//ACP/9gH4AuwGJgBGAAAABwDHAIoAAP//ACP/9gH4AuQGJgBGAAAABgDIRAD//wAj//YB+AKeBiYARgAAAAYAxT4A//8AI//2AfgC5AYmAEYAAAAHAMYAdwAAAAIAEQAAAbkC1AAQABQAAHMRNDY2MzIWFwcmJiMiBhURAzUhFYYuUTYpPBk7DSAXKy/PAWYCIjVPLhwbOg4PMiz93gGJUlIAAAMAI/8vAgEB5QATACQANAAARSImJzcWFjMyNjU1Nyc1MxEUBgYnIiYmNTQ2NjMyFhYXFQ4CJzI2NjU0JiYjIgYGFRQWFgEHSXEiOh1QN0lVEBBaP3FKQWc8PGdBOFYzAgMzViUsQyQlQi0tRCcnRdE2MTslJ01Bdmtqff44RGY62T5tRERrPyxPNX40TyxVJkUuLkUnJ0UtLUYnAAIAQgAAAewCygASABYAAGERNCYjIgYGFSc0NjYzMhYWFREhETMRAZJENiQ4ICUwVjY2UzD+VloBFTZGIDgkFTZUMTBWOP7ZAsr9NgACADcAAACpAq0AAwAPAABzETMRAyImNTQ2MzIWFRQGQ1otGSAgGRkgIAHb/iUCOiEZGCEhGBkhAAEAQgAAAJwB2wADAABzETMRQloB2/4l//8ACgAAANMC7AYmAE8AAAAGAMfiAP///8QAAAEaAuQGJgBPAAAABgDInAD////SAAABDAKeBiYATwAAAAYAxZYA////9wAAAMAC5AYmAE8AAAAGAMbPAAAC/4D/LwCxAq0AEAAcAABXIiYnNxYWMzI2NREzERQGBhMiJjU0NjMyFhUUBgYuPxk6DiEXHixaLEhIGCAgGBkgINEeHDsRECUlAg798zRGJQMLIRkYISEYGSEAAAIAQgAAAeYCygAGAAoAAGEnNzMDNxMhETMRAXLe3G31BPr+XFrz6P8ANP7xAsr9NgAAAQBCAAAAnALKAAMAAHMRMxFCWgLK/TYAAwBCAAADHwHlAAMAFgApAABzETMRMxE0JiMiBgYVJzQ2NjMyFhYVETMRNCYjIgYGFSc+AjMyFhYVEUJa50ExITQgJS9SMzJRL+dBMCE1IDMDNVQyNFIxAdv+JQEfNT0cMiMSNlAtLFA3/s4BHzU9HDIjEjdPLSxQOP7PAAIAQgAAAewB5QASABYAAGERNCYjIgYGFSc0NjYzMhYWFREhETMRAZJENiQ4ICUwVjY2UzD+VloBFTZGIDgkFTZUMTZXMf7ZAdv+Jf//AEIAAAHsAqAGJgBYAAAABgDKLwAAAgAj//YCEwHlAA8AHwAARSImJjU0NjYzMhYWFRQGBicyNjY1NCYmIyIGBhUUFhYBG0ZwQkJwRkVxQkJxRS1GKClFLS1GKChGCkJxRkVvQkFwRUZxQlcqSS8uSCkpSC4vSSoA//8AI//2AhMC7AYmAFoAAAAHAMcAjwAA//8AI//2AhMC5AYmAFoAAAAGAMhIAP//ACP/9gITAp4GJgBaAAAABgDFQwD//wAj//YCEwLkBiYAWgAAAAcAxgB7AAAAAwAV/+cCIgH0AAMAEwAjAABXJwEXASImJjU0NjYzMhYWFRQGBicyNjY1NCYmIyIGBhUUFhZQOwHSO/75RnBCQnBGRXFCQnFFLUYoKUUtLUYoKEYZOwHSO/49QnFGRW9CQXBFRnFCVypJLy5IKSlILi9JKv//ACP/9gITAqAGJgBaAAAABgDKOAAAAwBC/zkCIgHlABAAFwAnAABFIiYmJzU+AjMyFhYVFAYGBREzFQcXERMyNjY1NCYmIyIGBhUUFhYBPDZXNAMDNVc1QWk8PGn+xVoREZEtRCgoRCwtRCYlRQotUDOPNE8tQnBGRnBBvQKifXN0/sIBEipJMC9KKSlKMC9JKgAAAwBC/zkCIgLKABAAFwAnAABFIiYmJzU+AjMyFhYVFAYGBREzEQcXERMyNjY1NCYmIyIGBhUUFhYBPDZXNAMDNVc1QWk8PGn+xVoREZEtRScnRSwtRCYlRQotUDOPNE8tQnBGRnBBvQOR/pRzdP7CARIqSTAvSikpSjAvSSoAAwAk/zkCBQHlABAAHwAmAABFIiYmNTQ2NjMyFhYXFQ4CJzI2NTQmJiMiBgYVFBYWExE3JzUzEQENQmo9PWpBN1UzAwMzVShDUiVDLS1FKChFvRAQWgpBcEZGcEItTzSPM1AtVVtHMUkpKkkvMEkq/u4BPnRzff1eAAACAEIAAAGUAeUAAwARAABzETMRESc0NjMyFhcHJiYjIgZCWiJUTyQ6GTsPJBgyQAHb/iUBDw9bbBkdPRAOQAAAAQAY//YBiAHlACkAAFciJiYnNxYWMzI2NTQuBDU0NjYzMhYXByYmIyIGFRQeBBUUBtkoRzwWOhpEKiouJTpBOiUqSzU4Vxw6FDslJykkO0A6JV8KFScbOiAfHRoaHRMTHjQrKz8iJyc6GhwbGBgaEhMgNixDTgAAAQBC//YCHALUADQAAEUiJic3FhYzMjY2NTQmJiMjNTMyNjY1NCYmIyIGFREjETQ2NjMyFhYVFAYHNx4CFRQOAgFDLkAZNg4pHSI0HSI7JjwjIDAaHDMjNURaNl4/PlsyRzwHN1MuIDpPChgYRA4RHzklJTojTx42IiAyHj80/fQCDDhbNTRWNUBZDyMFNVc5LUw4HwAAAgAWAAABWgKiAAMABwAAcxEzEQM1IRWLWs8BRAKi/V4BiVJSAAABADb/9gHNAdsAFAAARSImJjURMxEUFhYzMjY1ETMRFAYGAQI7XTRaGzQjNTxaNFsKNV4+ART+8Cc5HkM7ARD+7D5eNQD//wA2//YBzQLsBiYAaAAAAAcAxwB2AAD//wA2//YBzQLkBiYAaAAAAAYAyC8A//8ANv/2Ac0CngYmAGgAAAAGAMUqAP//ADb/9gHNAuQGJgBoAAAABgDGYgAAAQALAAAB9AHbAAcAAHMDMxMjEzMD5dpkrzqwYNoB2/5vAZH+JQABAA4AAALgAdsADwAAcwMzEyMTMxMjEzMDIwMzA8q8XogehzSHHoheuzWJIYoB2/6OAXL+jgFy/iUBZ/6ZAAMAEQAAAecB2wAHAAsADwAAYS8CMxcXEyETFwc3JzczAXqUEbtthxHI/irEM42rNINp0BD7uQ7+7AEIQsbhQLoAAAIAEP85AfIB2wAHAAsAAFcDMxMjEzMDBxMXB97OZJkgoWTevowyWgQB3/6JAXf+IcMBH1zD//8AEP85AfIC7AYmAHAAAAAHAMcAdAAA//8AEP85AfICngYmAHAAAAAGAMUoAAADABwAAAGgAdsAAwAIAA0AAHcBMwEHNTchFQE1IRUHHAEaav7malABLv6TAXNTMQF5/ocxMSFSAYlSMSEAAAMAEgGQAT4CvAAOABoAIQAAUyImJjU0NjYzMhYXFQYGJzI2NTQmIyIGFRQWFzU3JzUzEZ8oQCUlQCguPgQEPSIjKysjIy0tbgsLRwGQKEMrK0QnNSlwJzdCLyYlLzAkJTA8TUdFR/7gAAACABIBjwFGArwADwAbAABTIiYmNTQ2NjMyFhYVFAYGJzI2NTQmIyIGFRQWrCtHKClFLCxFKShGLCQtLiMkLS4BjyhFKitDKCdEKypFKEMvJSUuLyQlLwAAAgAv//YCYQLAAA8AHwAARSImJjU0NjYzMhYWFRQGBicyNjY1NCYmIyIGBhUUFhYBSk6BTEuATU+AS0t/TzdTMDBUNzZULy9UClihbW2gV1egbm2hV1k9eFhYdz09d1hYeD0AAAIAHwAAAQoCtgADAAcAAHMRMxEDNTMVrV3r4QK2/UoCYlRUAAIAIQAAAfMCwAAYAB0AAHcBPgI1NCYjIgYHJzY2MzIWFhUUBgYPAjU3IRUhAQAnLBNENjVQH0IpdExAXzQVNS/PelABgjkBDig7Mhs1PDM1N0RFMlo8K0RHMdU8ORtUAAMAHv/2Ae0CtgAdACIAJwAAVyImJzcWFjMyNjY1NCYmIyIGBzc2NjMyFhYVFAYGAzU3NwcnNSEVB/dEbyZAF1AxLkMnJ0YwEiQRKBMsFjhZNT9ulstw0dUBplIKMzFAIykjQCorPyIFBTYJCjRePkJlOQFnOecB7dFUOBwAAAMAIQAAAjUCtgADAAgADAAAdxMzAQc1NyEVBxEzESH9av7+ZSgB7MFd7wHH/jk6OhpUtQHL/jUAAwAc//YB9AK2AB4AIwAnAABXIiYnNxYWMzI2NjU0JiYjIgYHNz4CMzIWFhUUBgYDJxMzAycnIRX4R28mQBdRMi9HKShDKClDHgERLDglSGQ1QXLJMx9WIyATAW0KMzFAIykkQS0uQCEUGDwVGg48Zj9CaDsBTTMBQP639VRUAAACACj/9gINArYAFQAlAABFIiYmNTQ3EzMDBz4CMzIWFhUUBgYnMjY2NTQmJiMiBgYVFBYWARpFbUBAzG3RIgwiMiI9Yz1Bb0MqQycnQyoqQycnQwpAbEJcWwEb/uMSFR0QOmVDQm5BWClFKytFKChFKytGKAAAAgAfAAAB7QK2AAMACAAAcwEXAwM1IRUHjAEEXf7QAc4pAn8D/YQCYlQ6GgADACv/9gH8AsEAIQAxAD0AAEUiJiY1NDY2NxcuAjU0NjYzMhYWFRQGBgc3HgIVFAYGJzI2NjU0JiYjIgYGFRQWFhMyNjU0JiMiBhUUFgETRWk6JEYvAyg4HTRbOjtaNB03KAIwRSU6aUYqPyUlPyopQCUlQCkyQEAyMUBACjRcOi9ONwwbCzFDJjZSLy9SNiZDMQsbDDdOLzpcNFUhOiYlOiEhOiUmOiEBSj4xMD09MDE+AAACACcAAAIMAsAAFQAlAABzEzcOAiMiJiY1NDY2MzIWFhUUBwMTMjY2NTQmJiMiBgYVFBYWk9EiDCIxIzxlPEJuQ0RuQEDMGipDJydDKipDKChEAR0SFB4QOmdBQ21BQGtDXFv+5QE3KUUqLEUoKEUsK0QpAAYAIv/yAmgCyAADAAcACwAPACUAKgAAQRcDJwEnExcBETMRAzUzFRM3NjY1NCYjIgYHJzY2MzIWFRQGDwI1NzMVARYnzk0BUifOTf4qUZWQh4oUDRsXFCARNhZDKTlCGh9gYkO/AS4k/uhKAU8lARhL/tkBYP6gAR1DQ/2yixQZDhUZFxkwJCE8NB8yHl0qLRZDAAAHACL/8gJ6AsgAAwAHAAsADwATABgAHAAAQRcDJwEnExcBETMRAzUzFRM3MwcHNTchFQc1MxUBFifOTQFSJ85N/ipRlZB/cVdzVRcBBnNQAS4k/uhKAU8lARhL/tkBYP6gAR1DQ/366+ssLBhESdXVAAAIACz/8gJ5AsgAAwAHACEAJgArAC8ANAA4AABBFwMnAScTFwEiJic3FhYzMjY1NCYjIgYHNzY2MzIWFRQGJzU3FwcnNTMVBxM3MwcHNTchFQc1MxUBESe/TQFoJ8BM/jQlPhY0CiYUGyIkHgkVCCQVFgcqOE1rWVdai+U9UXFXc1UXAQVzUAEyIf7hSgFMIAEgS/7TGhc0DxEcGBkcAwIsBgQ5LzVCqS1lAWVOQywX/frr6ywsGERJ1dUAAAIAHwFWALQCtgADAAcAAFMRMxEDNTMVZFCVkAFWAWD+oAEdQ0MAAgAiAVYBJwK8ABUAGgAAUzc2NjU0JiMiBgcnNjYzMhYVFAYPAjU3MxUkihQNGxYUIRE2F0IpOUIZIF9jRL8Bg4sUGQ4VGRcZMCQhPDQfMh5dKi0WQwADAB4BUAEiArYAGQAeACMAAFMiJic3FhYzMjY1NCYjIgYHNzY2MzIWFRQGJzU3FwcnNTMVB5YlPhU0CiYUGiIkHQoVByMWFQgqN0xrWFdaiuQ8AVAaFzQPERwYGRwDAiwGBDkvNUKpLWUBZU5DLBcAAQBQ//YA0gB5AAsAAFciJjU0NjMyFhUUBpEcJSUcHCUlCicbHCUlHBsnAAABAEf/dgDTAHkAEgAAVzc3BgYjIiY1NDYzMhYVFAYHB0c+IAUPCxUjJh0aKAkNQm53CAsOIxodJycdCx8YfQAAAgBG//YAyAGxAAsAFwAAVyImNTQ2MzIWFRQGAyImNTQ2MzIWFRQGhxwlJRwcJSUcHCUlHBwlJQonGh0lJR0aJwE4JhsdJSUdGyYAAAIAQv92AM4BsQASAB4AAFc3NwYGIyImNTQ2MzIWFRQGBwcTIiY1NDYzMhYVFAZCPh8FDwoVIyccGigJDUMSHCQkHBwlJW53CAsOIxocKCcdCx8YfQG4JhsdJSUdGyYA//8AUP/2Ap4AeQQnAIgA5gAAACcAiAHMAAAABgCIAAAAAgA///YAwALKAAMADwAAdwMzAwciJjU0NjMyFhUUBl0NYA0kHCQkHB0kJNwB7v4S5iYcHCUlHBwmAAIARP85AMUB5QADAA8AAFcTMxMDIiY1NDYzMhYVFAZVDUYNMB0kJB0cJCTHAcb+OgIpJhsdJSUdGyYAAAIAKP/2AcgC1AAbACcAAHcnNzI2NjU0JiYjIgYHJzY2MzIWFhUUBgYHNwcHIiY1NDYzMhYVFAbbARsjNR4dNSQwRhVCHW1HPV40L1U6JwgoHCUlHBwlJdy+AR40ICEyHDAsNztCMVc5NFU3CCiX5iYcHCUlHBwmAAIAM/8vAc8B5QAaACYAAFciJiY1NDY2Nwc3MxUjBgYVFBYWMzI2NxcGBgMiJjU0NjMyFhUUBv47XDQvVjgmCE4aNUEdMyIxRRVCHWxMHSQkHRwkJNEyVzk2UzYJKW+WAT4zIDMdMSs3OkMCMyYcHCUlHBwmAP//AAABKgCCAa4EBwCI/7ABNAABAEMBCwEGAc8ADwAAUyImJjU0NjYzMhYWFRQGBqUdLBkZLB0dKxkZKwELGi0bGywbGywbGy0aAAEAMQFWAbYC2AAOAABTJwcnNyc3FzcXBxcHJxfkCIUmlHo7YzhMV6ANmyoBVp9WSzhhO3mTJoQIUimaAAQAMAAAAk8CtgADAAcACwAPAABhEzMDJTUhFQUTMwMDNSEVAUxqTWr+lwIA/kZqTWp0AgACtv1K1klJ1gK2/UoBpUlJAAABAA7/2AF4At0AAwAAVwEzAQ4BFlT+6ygDBfz7AAABAA7/2AF4At0AAwAARQEzAQEk/upVARUoAwX8+wABAEIA1AGLASkAAwAAdzUhFUIBSdRVVQABAEIA2AHjASUAAwAAdzUhFUIBodhNTQABAEIA2QMMASMAAwAAdzUhFUICytlKSgABABT/hAHl/9IAAwAAVzUhFRQB0XxOTgABAC7/jAERAuIADwAAVy4CNTQ2NjcXBgYVFBYX3TdOKipONzRHTU1HdC6HoFZWoIcuLz7EennEPwAAAQAe/4wBAQLiAA8AAFcnNjY1NCYnNx4CFRQGBlI0R0xMRzQ3TioqTnQvP8R5esQ+Ly6HoFZWoIcAAAEAHv+gAR8CygAnAABXIiY3NzYmIyM1MzI2JycmNjMzFSMiBhcXFgYGBzUeAgcHBhYzMxXtTUwIDAQWHBwcHBYEDAhMTTIqLSUFCgQOKycnKw4ECgQkLSpgWFZ8JiRFJSV5V1dHLjVuJzckCyAIJDcncTUtSAABACT/oAElAsoAJwAAVyM1MzI2JycmNjY3FS4CNzc2JiMjNTMyFgcHBhYzMxUjIgYXFxYGVjIqLSQECgMNKycnKw0DCgUlLSoyTU0JDAQWHBwcHBYEDAhMYEgtNXEnNyQIIAskNyduNS5HV1d5JSVFJCZ8VlgAAwBP/6ABLgLKAAMABwALAABXETMRIzUzFQM1MxVPTCe6urpgAyr81khIAuNHRwAAAwAk/6ABAwLKAAMABwALAABXETMRIzUzFQM1MxW3TN+6urpgAyr81khIAuNHRwAAAgAzAdABdwLTABIAJQAAUwcHNjYzMhYVFAYjIiY1NDY3NxcHBzY2MzIWFRQGIyImNTQ2Nze/Ph8FDwoVIycbGygKDEPrPh8FDwoVIycbGygKDEMCt3cICw4iGxspKBwMHxh8HHcICw4iGxspKBwMHxh8AAACADoBvQF+AsAAEgAlAABTNzcGBiMiJjU0NjMyFhUUBgcHJzc3BgYjIiY1NDYzMhYVFAYHB/I+IAUPCxUjJxwaKAkNQuw+IAUPCxUjJxwaKAkNQgHZdwgLDiMaHCgoHAsfGXwcdwgLDiMaHCgoHAsfGXwAAAEAMwHQAL8C0wASAABTBwc2NjMyFhUUBiMiJjU0Njc3vz4fBQ8KFSMnGxsoCgxDArd3CAsOIhsbKSgcDB8YfAABADoBvQDGAsAAEgAAUzc3BgYjIiY1NDYzMhYVFAYHBzo+IAUPCxUjJxwaKAkNQgHZdwgLDiMaHCgoHAsfGXwAAgAlAFIBpgGPAAUACwAAdyc3MwcXMyc3MwcXkm1tXHFxXW1tW3FxUp6fn56en5+eAAACACQAUgGlAY8ABQALAAB3NyczFwchNyczFwfdcXFbbW3+7HJyXG1tUp6fn56en5+eAAIARQHWAUwCygADAAcAAFMnMwcjJzMH/RVkFtwVYxUB1vT09PQAAQBFAdYAqALKAAMAAFMnMwdaFWMVAdb09AAFADX/pgK6AjQAKAA3AEMARwBOAABFIi4CNTQ+AjMyFhYVFAYHJz4CNTQmJiMiBgYVFBYWMzI2NxcGBiciJiY1NDY2MzIWFRUUBicyNjU0JiMiBhUUFhc1MxUjNTcnNTMRAXpEd1gyM1p5RVyNURETTQ4RCDlrS0xzPz1wSDVUIDIsblEnPycnPycwPTwtJCsrJCEtLJK61goKQVoxWHdGRndZMlSSXytFHgQUKTIgT287QHNPTnI/HR0zJie0J0IpKUMnLy1tLDA/LyUmLi8lJS84OztKRkNF/ugAAgA6//YChwLBABcALgAAYQEmJjU0NjYzMhYWFwcmJiMiBhUUFhcBBSImJjU0NjcXBgYVFBYWMzI2NxcOAgIZ/rQnJjJYOSpFNRJBFzcnLTweHgFx/plFaDlEQSsoLiRBKjVKEzsUQU8BZCpMLjVTMRssHDsgJzYrJDIh/m4KNl89P2YeOBRFMCc4HywiRRsrGQADADj/nAKRArYAFQAZAB0AAEEjIiYmNTQ2NjMhFSEiBgYVFBYWMzMTIxEzEyMRMwF6YUBmOztmQAF4/o0nPSMjPSdcIU9Pn09PAQ40X0FAXzVSIDooKDog/jwDGvzmAxoAAAIAP/+HAccCwAAjAEcAAGU3MjY1NC4ENTQ2NjMyFhcHJiYjIgYVFB4EFRQGBgMiJic3FhYzMjY1NC4ENTQ2NjMHIgYVFB4EFRQGBgEIAi83KUBJQCksUzk8YB47F0MpLDEpQElAKTJWRjxgHjsXQygtMClASEEoMVc2Ai82KUBIQSgsUotDKCIhJhYXIz00MEgoLyw7ICInIB8jGBgkPTIuQyT+/DAsOyEiKB8fJBgXJD0zLkIkQycjISYWFyM9MzFHKQADAD//9gMCAr8AEwAxAEEAAEUiLgI1ND4CMzIeAhUUDgInIiYmNTQ2NjMyFhcHJiYjIgYGFRQWFjMyNjcXBgYHMjY2NTQmJiMiBgYVFBYWAaFNgl80NF6BTk2DXjQ0XoFGOFw1NV04K0wcNRIvHSE2Hx82IR4wEDUbTTVcjE9PjFxcjE5PjAo3YoJLTIFhNTZggkxLgmI2njVaOThaNCAfNhQUHzcjJDgeFRM2HyF1VJBZWI9UU49ZWZBUAAUARQENAfQCwAAPABMAFwAnADkAAEEiJiY1NDY2MzIWFhUUBgYnNTMVMyczFwcyNjY1NCYmIyIGBhUUFhY3NTMyNjU0JiMjNTMyFhUUBiMBHD9hNzZhP0BhODhgiCNfUyhWZjdULy9UNzZTLy9TAz8SFBQSP0AgKCggAQ06ZD09Yjk6Yj09Yzpr5eVnZ04yVjY1VDIyVDU2VjKxHhMPDxQfJB0dJAACACkBiwFhAsAADwAbAABTIiYmNTQ2NjMyFhYVFAYGJzI2NTQmIyIGFRQWxS1HKChHLS5GKChGLiMsLCIjLS0BiyhGKy1GKSlGLStGKEcxIiQvLyQiMQAAAQBi/34AtAL8AAMAAFcRMxFiUoIDfvyCAAACAGL/fgC0AvwAAwAHAABTETMRAxEzEWJSUlIBiQFz/o399QFz/o0AAgAxAAoB4QKsAB0AIQAAZSImJjU0NjYzMhYXByYmIyIGBhUUFhYzMjY3FwYGBxEzEQEqRnFCQnFGNl8hOxc/JS5GKChGLiVAFjwiX2BCZEFxRkZvQiomPBobKkcvL0kqGxs8JylaAqL9XgAABgA1AHcB/gJAAA8AEwAjACcAKwAvAABlIiYmNTQ2NjMyFhYVFAYGByc3FzcyNjY1NCYmIyIGBhUUFhYXJzcXASc3FxcnNxcBGjldNjZcOjldNjZc7zBYL14hMh0dMiEhMxwcM9dZL1j+j1gwV+ovWS6TNVs5OFo1NFs4OVs1HC5ZLxcfNCMiNB4fNCEiNR9vWC9ZARRXMFgvL1gwAAACADn/nAILAxoAKgAuAABFIiYnNxYWMzI2NTQuBTU0NjYzMhYXByYmIyIGFRQeBRUUBgcRMxEBIkxxLD8gVDk9SyQ8SEc8JDliPT9oIj8fRCk6QiU9R0k8JX55Qgo8OT8tNDgyJzAfGR0rRjU7Uy01Kz8kKDIwIyseGR4uSTdcaFoDfvyCAAMAGf/2AqICwAAfACMAJwAARSIuAjU0PgIzMhYXByYmIyIGBhUUFhYzMjY3FwYGATUhBwU1IQcBrEt7WjAwWXxLTnMwQSFYO0hrOjttSjtYIUEweP4fAdwY/jwBsxgKN2KCSkuCYTc4MEEnKkV5T056RSsnQDI4AZhKSq9LSwAAAwBCAAACMQLAABEAFQAZAAB3ETQ2NjMyFhcHJiYjIgYGFREHNSEVATUhFaE4YjxHWhk+FjkuIjYfvQHh/h8BgAMB4EZjNDgnPiEmHjgo/hcDVlYBKUtLAAUAOQAAAkwCtgAHAAsADwATABcAAEEDMxMjEzMDAxEzEQMXIzUVNSEVJzczFQEj6m22MbZr7ExejRuyAemtI4oBEwGj/pwBZP5d/u0BSf63AdhKSvlLS69KSgAAAgA7AHAB4wItAAMABwAAUzUhFQMzESM7Aaj9U1MBJlFRAQf+QwACAEAAfwHfAh4AAwAHAAB3JwEXAwE3AXs7AWQ7Q/6qOwFWfzsBZDv+owFWO/6qAAADADsAcQHjAi0AAwAPABsAAFM1IRUnIiY1NDYzMhYVFAYDIiY1NDYzMhYVFAY7AajUGCAgGBkgIBkYICAYGSAgASZRUZMiGBkhIRkYIv64IRkYISEYGSEAAgA7ALMB4wHqAAMABwAAUzUhFQU1IRU7Aaj+WAGoAZlRUeZRUQABADsAcQHjAi4ABwAAUzUFFQU1JRU7Aaj+WAFfAdNbvkG+WpUiAAEAOwBxAeMCLgAHAABlJTUlFQU1BQHj/lgBqP6hAV9xvkG+W5UilQADADsAaQHjAjUAAwAHAAsAAFM1IRUnMxEjBzUhFTsBqP1TU6sBqAFnUVHO/raCUVEAAAEANgEWAekBmQAXAABBIi4CIyIGByc2NjMyHgIzMjY3FwYGAWYcKiYlGBopETMZQSsdKyYkFhkpETMZQQEWDhIOFBQzJSUNEw4VEzMkJgAAAgA7ALEB4wGpAAMABwAAUzUhFSczFSM7AahTU1MBWFFRQegAAQA1AckBkALKAAcAAEEnMwcjEzMTAURzJHRMjzyQAcnPzwEB/v8AAAIAYv9FAfkB2wADABQAAFcRMxE3IiY1NxQWMzI2NREzERQGBmJagFNaLUEwMEJaMFW7Apb9arFpUhU9PDs/ART+4TlaMwAFADL/9gJjAsAAAwATAB8ALwA7AABzATMBBSImJjU0NjYzMhYWFRQGBicyNjU0JiMiBhUUFgMiJiY1NDY2MzIWFhUUBgYnMjY1NCYjIgYVFBY+Ab1b/kMBPCdAJiZAJydBJiZAKB4mJx0dJib6JkAmJUAnKEAmJj8pHiYnHR0lJQK2/UoKJj8oJz8mJj8nKD8mRycfHicnHh8nAWomQCcoPiYmPignQCZHJx8fJiYfHycAAgAlAFsCcgJJAAMACQAAQRUhNRM3JzMXBwIL/hre9/d49/cBfVZW/t739/f3AAIAPAIrAXYCngALABcAAFMiJjU0NjMyFhUUBjMiJjU0NjMyFhUUBnUZICAZGSAgrxkgIBkZICACKyEZGCEhGBkhIRkYISEYGSEAAQAoAhsA8QLkAAMAAFMnNxfIoEeCAhuDRqEAAAEAKAIiAPEC7AADAABTJzcXUSmCRwIiKaFHAAABACgCIQF+AuQABwAAUyc3MxcHJxdRKYhGiCihPQIhKJubKIYBAAIAKAIUARcDAQAPABsAAFMiJiY1NDY2MzIWFhUUBgYnMjY1NCYjIgYVFBahIzcfHzcjIjUfHzUiFR4eFRgdHQIUIDUhIjYfHzYhIjYfQR8XFx4fFhcfAAABACgCJAGgAqAAFQAAQSImJiMiBgcnNjYzMhYWMzI2NxcGBgEsIC0oGRkeDjEZNiYhLigXGR4NMRo1AiQYFhISMB4kFhgTEjAeJQAAAQAoAj8BkAKJAAMAAFMhFSEoAWj+mAKJSgABAAz/LwECAA0AFwAAVyImJzcWFjMyNjU0JiMjNzMHJzYWFRQGgSM4GikMIxceHBwcLB9EFyE9SUbRExExDA4SDg4UYUgbAjMnJzL//wA8AisBdgKeBAYAxQAA//8AKAIbAPEC5AQGAMYAAP//ACgCIgDxAuwEBgDHAAD//wAoAj8BkAKJBAYAywAA//8ADP8vAQIADQQGAMwAAAABAAAA0gC0AA4ATQAGAAEAAAAAAAAAAAAAAAAAAwABAAAAAAAaACYAMgA+AEoAVgBiAJIAzAD/AQsBNQFnAYcBkwGfAasBtwHRAgkCIwIvAjsCRwJTAl8CfgKZAqsCygLpAvUDLQM5A0UDUQNdA54DqgPUA/0EPwRuBKsEvwTjBO8E+wUHBRMFKAVIBW0FigWWBbUF8QX9BggGEwYfBisGNgZCBoAGrwa6BvgHOwd0B4AHiweWB6IHxggUCDoIVghiCG0IeAiDCI4IvAjVCOEJHwlFCVAJggmOCZkJpAmwCeoJ9Qo0CnMKsArQCwwLVwtqC40LmQukC68LugvNC+wMDQwoDDQMPwxeDJMMvwzxDQMNMw1yDY4Nzg4JDh8OeQ6zDv0PNg+UD6cP0hAKEAoQChAgEEAQZhCWEKYQwxDhER0RWBFhEX0RmxG+Ec0R3BHoEfQSABIMEikSRhKBErwS1BLsEyYTYBOAE6ATuRPSE+UT8hRgFKkU2hU8FZoV7RYZFiYWOhZwFr8XAhdCF24XnBevF8cX8xgGGBkYLRhGGG4YgBiUGLcZEBknGUwZWhloGXsZpxnNGdoaABoIGhAaGBogGigAAAABAAAAARmaZepsul8PPPUAAwPoAAAAANzb5f4AAAAA4DoXKv+A/q4OHgPcAAAABgACAAAAAAAAAq4AUQK4AB8CuAAfArgAHwK4AB8CuAAfArgAHwK4AB8DzQAfAm8AUgKwAC8CsAAvAuQAUgLzABYCTgBSAk4AUgJOAFICTgBSAk4AUgI2AFIDBQAvAsIAUgECAFIBAgAdAQL/1gEC/+UBAgAJAe8AHgKaAFICKABSA0cAUgLGAFICxgBSAxoALwMaAC8DGgAvAxoALwMaAC8DGgAuAxoALwJeAFICXgBSAzEALwJ2AFICKwAgAnEAHgKrAEoCqwBKAqsASgKrAEoCqwBKArAAHwPVACACswAeApkAHQKZAB0CRwAnAkYAJAJGACQCRgAkAkYAJAJGACQCRgAkAkYAJAOlACQCRgBCAekAIwHpACMCRgAkAjQAKAIYACMCGAAjAhgAIwIYACMCGAAjAY8AEQJDACMCJABCAOAANwDeAEIA3gAKAN7/xADe/9IA3v/3AOb/gAHyAEIA3gBCA1cAQgIkAEICJABCAjYAIwI2ACMCNgAjAjYAIwI2ACMCNgAVAjYAIwJGAEICRgBCAkcAJAGjAEIBqwAYAj0AQgFwABYCBAA2AgQANgIEADYCBAA2AgQANgH/AAsC7gAOAfgAEQICABACAgAQAgIAEAG/ABwBYgASAVgAEgKQAC8BWwAfAh0AIQIaAB4CVgAhAh0AHAI0ACgCDQAfAiYAKwI0ACcCngAiAqQAIgKeACwBBQAfAVAAIgFPAB4A0AAAANAAAAEiAFABEwBHAQ8ARgENAEIC7gBQAQUAPwELAEQB+QAoAekAMwCCAAABSgBDAeoAMQKAADABhgAOAYYADgHNAEICJQBCA1QAQgH5ABQBLwAuAS4AHgFDAB4BQwAkAVIATwFSACQBsAAzAbEAOgD4ADMA+QA6AcoAJQHKACQBkABFAO0ARQLuADUCkwA6AsIAOAIFAD8DQQA/AjgARQGKACkBFgBiARYAYgIJADECNAA1AkwAOQLVABkCawBCAoUAOQIeADsCHgBAAh4AOwIeADsCHgA7Ah4AOwIeADsCHgA2Ah4AOwHFADUCQwBiApQAMgKSACUAAAA8AAAAKAAAACgAAAAoAAAAKAAAACgAAAAoAAAADAGyADwBGQAoARkAKAG4ACgBDwAMAAEAAAPo/vwAAA5g/4D+YA4eAAEAAAAAAAAAAAAAAAAAAADSAAAAAgAAAAMAAAAUAAMAAQAAABQABAHgAAAAGgAQAAMACgAvADkAfgCsAP8gFCAZIB0gIiAmIKwhkv//AAAAIAAwADoAoACuIBMgGCAcICIgJiCsIZL//wAAAEYAAAAAAADgheCL4IXgcOBm4AnfMgABABoAAAA2AL4A1gAAAAAAAAAAAAAAAAAAAAAAhgCNAKcAlAC0AMMAqgCoAJsAnACTALgAiQCXAIgAlQCKAIsAvQC7ALwAjwCpAAEACQAKAAwADgATABQAFQAWABsAHAAdAB4AHwAhACgAKgArACwALQAuADMANAA1ADYAOACfAJYAoADBAJoAzgA5AEEAQgBEAEYASwBMAE0ATgBUAFUAVgBXAFgAWgBhAGMAZABlAGcAaABtAG4AbwBwAHMAnQCwAJ4AvwCHAI4AsgC2ALMAtwCxAKwAzQCtAHQApQDAAK4A0ACvAL4AhACFAM8AwgCrAJEA0QCDAHUApgCBAIAAggCQAAUAAgADAAcABAAGAAgACwASAA8AEAARABoAFwAYABkADQAgACUAIgAjACcAJAC5ACYAMgAvADAAMQA3ACkAZgA9ADoAOwA/ADwAPgBAAEMASgBHAEgASQBTAFAAUQBSAEUAWQBeAFsAXABgAF0AugBfAGwAaQBqAGsAcQBiAHI=",
  };
  function loadFont(b64) {
    const buf = Buffer.from(b64, "base64");
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    const tables = {};
    for (let i = 0; i < dv.getUint16(4); i++) {
      const o = 12 + i * 16;
      tables[buf.toString("ascii", o, o + 4)] = dv.getUint32(o + 8);
    }
    const upem = dv.getUint16(tables.head + 18);
    const locFormat = dv.getInt16(tables.head + 50);
    const numGlyphs = dv.getUint16(tables.maxp + 4);
    const numHM = dv.getUint16(tables.hhea + 34);
    const advance = (g) => dv.getUint16(tables.hmtx + Math.min(g, numHM - 1) * 4);
    const loca = (g) => (locFormat ? dv.getUint32(tables.loca + g * 4) : dv.getUint16(tables.loca + g * 2) * 2);
    // cmap, format 4 (Unicode BMP)
    let cmap = 0;
    for (let i = 0; i < dv.getUint16(tables.cmap + 2); i++) {
      const rec = tables.cmap + 4 + i * 8;
      const off = tables.cmap + dv.getUint32(rec + 4);
      if (dv.getUint16(off) === 4 && !cmap) cmap = off;
    }
    const segX2 = dv.getUint16(cmap + 6);
    const endP = cmap + 14;
    const startP = endP + segX2 + 2;
    const deltaP = startP + segX2;
    const rangeP = deltaP + segX2;
    const gidOf = (code) => {
      for (let i = 0; i < segX2; i += 2) {
        if (dv.getUint16(endP + i) < code) continue;
        const start = dv.getUint16(startP + i);
        if (start > code) return 0;
        const delta = dv.getInt16(deltaP + i);
        const range = dv.getUint16(rangeP + i);
        if (!range) return (code + delta) & 0xffff;
        const g = dv.getUint16(rangeP + i + range + 2 * (code - start));
        return g ? (g + delta) & 0xffff : 0;
      }
      return 0;
    };
    const cache = new Map();
    /* The outline of a glyph: a list of contours, each a list of { x, y, on } in font units. */
    function outline(gid, depth = 0) {
      if (cache.has(gid) && depth === 0) return cache.get(gid);
      const start = loca(gid);
      const end = loca(gid + 1);
      let contours = [];
      if (end > start && depth < 6) {
        let p = tables.glyf + start;
        const n = dv.getInt16(p);
        p += 10;
        if (n >= 0) {
          const ends = [];
          for (let i = 0; i < n; i++) ends.push(dv.getUint16(p + i * 2));
          p += n * 2;
          p += 2 + dv.getUint16(p);
          const count = n ? ends[n - 1] + 1 : 0;
          const flags = [];
          while (flags.length < count) {
            const f = dv.getUint8(p++);
            flags.push(f);
            if (f & 8) for (let r = dv.getUint8(p++); r > 0; r--) flags.push(f);
          }
          const xs = [];
          let v = 0;
          for (const f of flags) {
            if (f & 2) { const d = dv.getUint8(p++); v += f & 16 ? d : -d; } else if (!(f & 16)) { v += dv.getInt16(p); p += 2; }
            xs.push(v);
          }
          const ys = [];
          v = 0;
          for (const f of flags) {
            if (f & 4) { const d = dv.getUint8(p++); v += f & 32 ? d : -d; } else if (!(f & 32)) { v += dv.getInt16(p); p += 2; }
            ys.push(v);
          }
          let a = 0;
          for (const e of ends) {
            const pts = [];
            for (let i = a; i <= e; i++) pts.push({ x: xs[i], y: ys[i], on: Boolean(flags[i] & 1) });
            contours.push(pts);
            a = e + 1;
          }
        } else {
          for (;;) {
            const flags = dv.getUint16(p);
            const sub = dv.getUint16(p + 2);
            p += 4;
            let dx = 0;
            let dy = 0;
            if (flags & 1) { dx = flags & 2 ? dv.getInt16(p) : dv.getUint16(p); dy = flags & 2 ? dv.getInt16(p + 2) : dv.getUint16(p + 2); p += 4; } else { dx = flags & 2 ? dv.getInt8(p) : dv.getUint8(p); dy = flags & 2 ? dv.getInt8(p + 1) : dv.getUint8(p + 1); p += 2; }
            let a = 1, b = 0, c = 0, d = 1;
            const f2 = (o) => dv.getInt16(o) / 16384;
            if (flags & 8) { a = d = f2(p); p += 2; } else if (flags & 0x40) { a = f2(p); d = f2(p + 2); p += 4; } else if (flags & 0x80) { a = f2(p); b = f2(p + 2); c = f2(p + 4); d = f2(p + 6); p += 8; }
            for (const contour of outline(sub, depth + 1)) contours.push(contour.map((pt) => ({ x: pt.x * a + pt.y * c + dx, y: pt.x * b + pt.y * d + dy, on: pt.on })));
            if (!(flags & 0x20)) break;
          }
        }
      }
      if (depth === 0) cache.set(gid, contours);
      return contours;
    }
    return { upem, gidOf, advance, outline, numGlyphs };
  }
  let FONTS = null;
  const fonts = () => FONTS || (FONTS = { bold: loadFont(B64.bold), regular: loadFont(B64.regular) });

  /* A contour as a polygon in pixels (quadratic curves flattened). */
  function flatten(contour, scale, ox, oy) {
    const n = contour.length;
    if (n < 2) return [];
    const full = [];
    for (let i = 0; i < n; i++) {
      const cur = contour[i];
      const nxt = contour[(i + 1) % n];
      full.push(cur);
      if (!cur.on && !nxt.on) full.push({ x: (cur.x + nxt.x) / 2, y: (cur.y + nxt.y) / 2, on: true });
    }
    const first = full.findIndex((p) => p.on);
    if (first < 0) return [];
    const pts = [...full.slice(first), ...full.slice(0, first)];
    const m = pts.length;
    const tx = (p) => [ox + p.x * scale, oy - p.y * scale];
    const out = [tx(pts[0])];
    let i = 0;
    while (i < m) {
      const b = pts[(i + 1) % m];
      if (b.on) {
        out.push(tx(b));
        i += 1;
      } else {
        const a = tx(pts[i]);
        const q = tx(b);
        const c = tx(pts[(i + 2) % m]);
        for (let k = 1; k <= 8; k++) {
          const t = k / 8;
          const u = 1 - t;
          out.push([u * u * a[0] + 2 * u * t * q[0] + t * t * c[0], u * u * a[1] + 2 * u * t * q[1] + t * t * c[1]]);
        }
        i += 2;
      }
    }
    return out;
  }

  /* Exact area coverage of polygons (non-zero fill) in a w x h grid. */
  function coverage(polys, w, h) {
    const a = new Float32Array(w * h + w + 4);
    const line = (p0, p1) => {
      if (p0[1] === p1[1]) return;
      let dir = 1;
      let [x0, y0] = p0;
      let [x1, y1] = p1;
      if (y0 > y1) { dir = -1; [x0, y0, x1, y1] = [x1, y1, x0, y0]; }
      const dxdy = (x1 - x0) / (y1 - y0);
      let x = x0;
      if (y0 < 0) x -= y0 * dxdy;
      const yStart = Math.max(0, Math.floor(y0));
      const yEnd = Math.min(h, Math.ceil(y1));
      for (let y = yStart; y < yEnd; y++) {
        const base = y * w;
        const dy = Math.min(y + 1, y1) - Math.max(y, y0);
        const xnext = x + dxdy * dy;
        const d = dy * dir;
        let xa = x < xnext ? x : xnext;
        let xb = x < xnext ? xnext : x;
        xa = Math.max(0, Math.min(w, xa));
        xb = Math.max(0, Math.min(w, xb));
        const xaf = Math.floor(xa);
        const xai = xaf;
        const xbc = Math.ceil(xb);
        if (xbc <= xai + 1) {
          const xmf = 0.5 * (xa + xb) - xaf;
          a[base + xai] += d - d * xmf;
          a[base + xai + 1] += d * xmf;
        } else {
          const s = 1 / (xb - xa);
          const x0f = xa - xaf;
          const a0 = 0.5 * s * (1 - x0f) * (1 - x0f);
          const x1f = xb - xbc + 1;
          const am = 0.5 * s * x1f * x1f;
          a[base + xai] += d * a0;
          if (xbc === xai + 2) a[base + xai + 1] += d * (1 - a0 - am);
          else {
            const a1 = s * (1.5 - x0f);
            a[base + xai + 1] += d * (a1 - a0);
            for (let xi = xai + 2; xi < xbc - 1; xi++) a[base + xi] += d * s;
            const a2 = a1 + (xbc - xai - 3) * s;
            a[base + xbc - 1] += d * (1 - a2 - am);
          }
          a[base + xbc] += d * am;
        }
        x = xnext;
      }
    };
    for (const poly of polys) {
      for (let i = 0; i < poly.length; i++) line(poly[i], poly[(i + 1) % poly.length]);
    }
    const cov = new Float32Array(w * h);
    for (let y = 0; y < h; y++) {
      let acc = 0;
      for (let x = 0; x < w; x++) {
        acc += a[y * w + x];
        const v = Math.abs(acc);
        cov[y * w + x] = v > 1 ? 1 : v;
      }
    }
    return cov;
  }

  /* The text as a coverage mask. Origin: pen at (pad, baseline). */
  function textMask(font, str, size, spacing, pad) {
    const scale = size / font.upem;
    const items = [];
    let pen = 0;
    for (const ch of String(str)) {
      const code = ch.codePointAt(0);
      let gid = font.gidOf(code);
      if (!gid && ch !== " " && ch !== " ") continue; // not in the font: skipped
      if (ch === " ") gid = font.gidOf(32);
      items.push({ gid, x: pen });
      pen += font.advance(gid) * scale + spacing;
    }
    const width = Math.max(0, pen - spacing);
    const asc = Math.ceil(size * 1.05) + pad;
    const desc = Math.ceil(size * 0.4) + pad;
    const w = Math.ceil(width) + pad * 2 + 2;
    const h = asc + desc;
    const mask = new Float32Array(w * h);
    for (const it of items) {
      const polys = font.outline(it.gid).map((c) => flatten(c, scale, pad + it.x, asc)).filter((p) => p.length > 2);
      if (!polys.length) continue;
      let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
      for (const poly of polys) for (const [x, y] of poly) { if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
      const bx = Math.max(0, Math.floor(minx) - 1);
      const by = Math.max(0, Math.floor(miny) - 1);
      const bw = Math.min(w, Math.ceil(maxx) + 1) - bx;
      const bh = Math.min(h, Math.ceil(maxy) + 1) - by;
      if (bw <= 0 || bh <= 0) continue;
      const cov = coverage(polys.map((poly) => poly.map(([x, y]) => [x - bx, y - by])), bw, bh);
      for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
        const v = cov[y * bw + x];
        if (v > 0) { const i = (by + y) * w + bx + x; mask[i] = Math.min(1, mask[i] + v); }
      }
    }
    return { mask, w, h, width, baseline: asc, pad, scale };
  }

  /* Three box blurs make a soft, gaussian-like blur of a mask. */
  function blurMask(src, w, h, radius) {
    let a = Float32Array.from(src);
    let b = new Float32Array(src.length);
    const r = Math.max(1, Math.round(radius / 2));
    for (let pass = 0; pass < 3; pass++) {
      for (let y = 0; y < h; y++) {
        let sum = 0;
        for (let x = -r; x <= r; x++) sum += a[y * w + Math.max(0, Math.min(w - 1, x))];
        for (let x = 0; x < w; x++) {
          b[y * w + x] = sum / (2 * r + 1);
          sum += a[y * w + Math.min(w - 1, x + r + 1)] - a[y * w + Math.max(0, x - r)];
        }
      }
      for (let x = 0; x < w; x++) {
        let sum = 0;
        for (let y = -r; y <= r; y++) sum += b[Math.max(0, Math.min(h - 1, y)) * w + x];
        for (let y = 0; y < h; y++) {
          a[y * w + x] = sum / (2 * r + 1);
          sum += b[Math.min(h - 1, y + r + 1) * w + x] - b[Math.max(0, y - r) * w + x];
        }
      }
    }
    return a;
  }

  const CAP = 0.7; // cap height of the font, in em

  /* ---------- the canvas ---------- */
  class Canvas {
    constructor(w, h, bg1 = "#101226", bg2 = null) {
      this.w = w;
      this.h = h;
      this.px = new Float32Array(w * h * 3);
      const paint = bg2 ? lin(0, 0, 0, h, [[0, bg1], [1, bg2]]) : null;
      const c = hex(bg1);
      for (let y = 0; y < h; y++) {
        const col = paint ? paint(0, y) : c;
        for (let x = 0; x < w; x++) {
          const i = (y * w + x) * 3;
          this.px[i] = col[0]; this.px[i + 1] = col[1]; this.px[i + 2] = col[2];
        }
      }
    }
    clone() {
      const c = Object.create(Canvas.prototype);
      c.w = this.w;
      c.h = this.h;
      c.px = Float32Array.from(this.px);
      return c;
    }
    blend(x, y, c, a) {
      if (a <= 0 || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
      const i = (y * this.w + x) * 3;
      const p = this.px;
      p[i] += (c[0] - p[i]) * a;
      p[i + 1] += (c[1] - p[i + 1]) * a;
      p[i + 2] += (c[2] - p[i + 2]) * a;
    }
    /* Fills where sdf(x, y) <= 0 with a soft edge. */
    shape(sdf, x0, y0, x1, y1, paint, alpha = 1) {
      const fixed = typeof paint === "function" ? null : hex(paint);
      for (let y = Math.max(0, Math.floor(y0)); y < Math.min(this.h, Math.ceil(y1)); y++) {
        for (let x = Math.max(0, Math.floor(x0)); x < Math.min(this.w, Math.ceil(x1)); x++) {
          const cover = clamp01(0.5 - sdf(x + 0.5, y + 0.5));
          if (cover > 0) this.blend(x, y, fixed || paint(x + 0.5, y + 0.5), cover * alpha);
        }
      }
    }
    /* A soft glow or shadow around a shape: 1 inside, fading to 0 over `blur` pixels outside. */
    soft(sdf, x0, y0, x1, y1, blur, color, alpha = 1) {
      const col = hex(color);
      for (let y = Math.max(0, Math.floor(y0 - blur)); y < Math.min(this.h, Math.ceil(y1 + blur)); y++) {
        for (let x = Math.max(0, Math.floor(x0 - blur)); x < Math.min(this.w, Math.ceil(x1 + blur)); x++) {
          const d = sdf(x + 0.5, y + 0.5);
          const v = d <= 0 ? 1 : 1 - smooth(0, blur, d);
          if (v > 0) this.blend(x, y, col, v * v * alpha);
        }
      }
    }
    round(x, y, w, h, r, paint, alpha = 1) {
      r = Math.min(r, w / 2, h / 2);
      this.shape(roundSdf(x, y, w, h, r), x - 1, y - 1, x + w + 1, y + h + 1, paint, alpha);
    }
    roundShadow(x, y, w, h, r, blur, color, alpha, dy = 0) {
      r = Math.min(r, w / 2, h / 2);
      this.soft(roundSdf(x, y + dy, w, h, r), x, y + dy, x + w, y + h + dy, blur, color, alpha);
    }
    circle(cx, cy, r, paint, alpha = 1) {
      this.shape((px, py) => Math.hypot(px - cx, py - cy) - r, cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, paint, alpha);
    }
    ring(cx, cy, r, thickness, paint, alpha = 1) {
      this.shape((px, py) => Math.abs(Math.hypot(px - cx, py - cy) - r) - thickness / 2, cx - r - thickness, cy - r - thickness, cx + r + thickness, cy + r + thickness, paint, alpha);
    }
    ellipse(cx, cy, rx, ry, paint, alpha = 1) {
      this.shape((px, py) => (Math.hypot((px - cx) / rx, (py - cy) / ry) - 1) * Math.min(rx, ry), cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1, paint, alpha);
    }
    /* A soft blob (shadow or highlight): full in the middle, fading smoothly to nothing. */
    ellipseSoft(cx, cy, rx, ry, blur, color, alpha) {
      const col = hex(color);
      const rx2 = rx + blur;
      const ry2 = ry + blur;
      const from = Math.min(0.9, Math.max(rx, ry) > 0 ? Math.min(rx / rx2, ry / ry2) * 0.5 : 0);
      for (let y = Math.max(0, Math.floor(cy - ry2)); y < Math.min(this.h, Math.ceil(cy + ry2)); y++) {
        for (let x = Math.max(0, Math.floor(cx - rx2)); x < Math.min(this.w, Math.ceil(cx + rx2)); x++) {
          const t = Math.hypot((x + 0.5 - cx) / rx2, (y + 0.5 - cy) / ry2);
          const v = 1 - smooth(from, 1, t);
          if (v > 0) this.blend(x, y, col, v * v * alpha);
        }
      }
    }
    glow(cx, cy, r, color, alpha = 0.5) {
      const col = hex(color);
      for (let y = Math.max(0, Math.floor(cy - r)); y < Math.min(this.h, Math.ceil(cy + r)); y++) {
        for (let x = Math.max(0, Math.floor(cx - r)); x < Math.min(this.w, Math.ceil(cx + r)); x++) {
          const t = 1 - Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r;
          if (t > 0) this.blend(x, y, col, t * t * (3 - 2 * t) * alpha);
        }
      }
    }
    segment(x0, y0, x1, y1, width, paint, alpha = 1) {
      const dx = x1 - x0;
      const dy = y1 - y0;
      const len2 = dx * dx + dy * dy || 1;
      this.shape((px, py) => {
        const t = clamp01(((px - x0) * dx + (py - y0) * dy) / len2);
        return Math.hypot(px - (x0 + dx * t), py - (y0 + dy * t)) - width / 2;
      }, Math.min(x0, x1) - width, Math.min(y0, y1) - width, Math.max(x0, x1) + width, Math.max(y0, y1) + width, paint, alpha);
    }
    /* Polygons (lists of [x, y]) filled with a paint. */
    polygons(polys, paint, alpha = 1) {
      let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
      for (const poly of polys) for (const [x, y] of poly) { if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
      const bx = Math.max(0, Math.floor(minx) - 1);
      const by = Math.max(0, Math.floor(miny) - 1);
      const bw = Math.min(this.w, Math.ceil(maxx) + 1) - bx;
      const bh = Math.min(this.h, Math.ceil(maxy) + 1) - by;
      if (bw <= 0 || bh <= 0) return;
      const cov = coverage(polys.map((poly) => poly.map(([x, y]) => [x - bx, y - by])), bw, bh);
      const fixed = typeof paint === "function" ? null : hex(paint);
      for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
        const v = cov[y * bw + x];
        if (v > 0) this.blend(bx + x, by + y, fixed || paint(bx + x + 0.5, by + y + 0.5), v * alpha);
      }
    }
    /* A four-pointed sparkle. */
    sparkle(cx, cy, r, color, alpha = 0.8) {
      this.glow(cx, cy, r * 2.4, color, alpha * 0.35);
      const pts = [];
      for (let k = 0; k < 8; k++) {
        const ang = (Math.PI / 4) * k - Math.PI / 2;
        const rr = k % 2 === 0 ? r : r * 0.22;
        pts.push([cx + Math.cos(ang) * rr, cy + Math.sin(ang) * rr]);
      }
      this.polygons([pts], color, alpha);
    }
    /* A rotated rectangle (confetti). */
    confetti(cx, cy, w, h, angle, color, alpha = 1) {
      const c = Math.cos(angle);
      const s = Math.sin(angle);
      const pts = [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]].map(([x, y]) => [cx + x * c - y * s, cy + x * s + y * c]);
      this.polygons([pts], color, alpha);
    }
    /* A picture (decoded avatar) as a circle. */
    avatar(img, cx, cy, d) {
      const r = d / 2;
      for (let y = Math.max(0, Math.floor(cy - r) - 1); y < Math.min(this.h, Math.ceil(cy + r) + 1); y++) {
        for (let x = Math.max(0, Math.floor(cx - r) - 1); x < Math.min(this.w, Math.ceil(cx + r) + 1); x++) {
          const cover = clamp01(0.5 - (Math.hypot(x + 0.5 - cx, y + 0.5 - cy) - r));
          if (cover <= 0) continue;
          const u = ((x + 0.5 - (cx - r)) / d) * img.w - 0.5;
          const v = ((y + 0.5 - (cy - r)) / d) * img.h - 0.5;
          const x0 = Math.max(0, Math.min(img.w - 1, Math.floor(u)));
          const y0 = Math.max(0, Math.min(img.h - 1, Math.floor(v)));
          const x1 = Math.min(img.w - 1, x0 + 1);
          const y1 = Math.min(img.h - 1, y0 + 1);
          const fx = clamp01(u - x0);
          const fy = clamp01(v - y0);
          const at = (px, py, k) => img.data[(py * img.w + px) * 4 + k];
          const ch = (k) => (at(x0, y0, k) * (1 - fx) + at(x1, y0, k) * fx) * (1 - fy) + (at(x0, y1, k) * (1 - fx) + at(x1, y1, k) * fx) * fy;
          this.blend(x, y, [ch(0), ch(1), ch(2)], cover * (ch(3) / 255));
        }
      }
    }
    /* A picture with transparency (a logo), centred at (cx, cy) and fitted in a square of `size` pixels. */
    image(img, cx, cy, size, alpha = 1) {
      const x0 = cx - size / 2;
      const y0 = cy - size / 2;
      for (let y = Math.max(0, Math.floor(y0)); y < Math.min(this.h, Math.ceil(y0 + size)); y++) {
        for (let x = Math.max(0, Math.floor(x0)); x < Math.min(this.w, Math.ceil(x0 + size)); x++) {
          const u = ((x + 0.5 - x0) / size) * img.w - 0.5;
          const v = ((y + 0.5 - y0) / size) * img.h - 0.5;
          const ix = Math.max(0, Math.min(img.w - 1, Math.floor(u)));
          const iy = Math.max(0, Math.min(img.h - 1, Math.floor(v)));
          const jx = Math.min(img.w - 1, ix + 1);
          const jy = Math.min(img.h - 1, iy + 1);
          const fx = clamp01(u - ix);
          const fy = clamp01(v - iy);
          let r = 0, g = 0, b = 0, a = 0;
          for (const [px, py, wgt] of [[ix, iy, (1 - fx) * (1 - fy)], [jx, iy, fx * (1 - fy)], [ix, jy, (1 - fx) * fy], [jx, jy, fx * fy]]) {
            const o = (py * img.w + px) * 4;
            const pa = (img.data[o + 3] / 255) * wgt; // averaged with their transparency, so edges have no dark fringe
            r += img.data[o] * pa; g += img.data[o + 1] * pa; b += img.data[o + 2] * pa; a += pa;
          }
          if (a > 0.002) this.blend(x, y, [r / a, g / a, b / a], a * alpha);
        }
      }
    }
    measure(str, size, font = "bold", spacing = 0) {
      return textMask(fonts()[font === "regular" ? "regular" : "bold"], str, size, spacing, 0).width;
    }
    /* Text. y is the vertical middle of the capital letters (valign "middle"), their top ("top") or the baseline. Returns the width. */
    text(str, x, y, size, o = {}) {
      const font = fonts()[o.font === "regular" ? "regular" : "bold"];
      const blurPad = Math.ceil(Math.max(o.glow?.blur || 0, (o.shadow?.blur || 0) + Math.max(Math.abs(o.shadow?.dx || 0), Math.abs(o.shadow?.dy || 0)))) + 3;
      const m = textMask(font, str, size, o.spacing || 0, blurPad);
      const left = o.align === "center" ? x - m.width / 2 : o.align === "right" ? x - m.width : x;
      const base = o.valign === "baseline" ? y : o.valign === "top" ? y + CAP * size : y + (CAP * size) / 2;
      const ox = Math.round(left - m.pad);
      const oy = Math.round(base - m.baseline);
      const stamp = (mask, color, alpha, dx = 0, dy = 0) => {
        const col = hex(color);
        for (let j = 0; j < m.h; j++) for (let i = 0; i < m.w; i++) {
          const v = mask[j * m.w + i];
          if (v > 0.002) this.blend(ox + i + dx, oy + j + dy, col, v * alpha);
        }
      };
      if (o.glow) stamp(blurMask(m.mask, m.w, m.h, o.glow.blur), o.glow.color || "#ffffff", o.glow.alpha ?? 0.7);
      if (o.shadow) stamp(blurMask(m.mask, m.w, m.h, o.shadow.blur ?? 4), o.shadow.color || "#000000", o.shadow.alpha ?? 0.5, Math.round(o.shadow.dx || 0), Math.round(o.shadow.dy ?? 3));
      const top = base - CAP * size;
      const paint = o.paint ? o.paint(top, base) : o.gradient ? lin(0, top, 0, base, o.gradient) : null;
      const fixed = paint ? null : hex(o.color || "#ffffff");
      const opacity = o.alpha ?? 1;
      for (let j = 0; j < m.h; j++) for (let i = 0; i < m.w; i++) {
        const v = m.mask[j * m.w + i];
        if (v > 0.002) this.blend(ox + i, oy + j, fixed || paint(ox + i, oy + j), v * opacity);
      }
      return m.width;
    }
    /* A rounded glass panel with a soft shadow and a bright edge. */
    glass(x, y, w, h, r, alpha = 0.1) {
      this.roundShadow(x, y, w, h, r, 26, "#000000", 0.3, 10);
      this.round(x, y, w, h, r, "#ffffff", alpha);
      this.shape((px, py) => Math.abs(roundSdf(x, y, w, h, r)(px, py) + 1) - 0.9, x - 2, y - 2, x + w + 2, y + h + 2, lin(x, y, x + w, y + h, [[0, "#ffffff"], [1, "#9aa4ff"]]), 0.28);
    }
    /* A pill with a paint and a text in the middle. */
    pill(x, y, w, h, paint, str, size, o = {}) {
      this.roundShadow(x, y, w, h, h / 2, 12, o.glow || "#000000", o.glow ? 0.45 : 0.25, 3);
      this.round(x, y, w, h, h / 2, paint);
      this.round(x, y, w, h / 2, h / 2, "#ffffff", 0.14);
      if (str) this.text(str, x + w / 2, y + h / 2, size, { align: "center", spacing: o.spacing || 0, color: o.color || "#ffffff", shadow: { dx: 0, dy: 1, blur: 2, alpha: 0.35 } });
    }
    /* A progress bar with a glow. */
    bar(x, y, w, h, fraction, stops = [[0, "#2effa8"], [1, "#19c7ff"]]) {
      this.round(x, y, w, h, h / 2, "#000000", 0.38);
      const fw = Math.max(h, w * clamp01(fraction));
      if (fraction > 0) {
        this.roundShadow(x, y, fw, h, h / 2, 14, stops[stops.length - 1][1], 0.45, 0);
        this.round(x, y, fw, h, h / 2, lin(x, 0, x + w, 0, stops));
        this.round(x + 2, y + 2, Math.max(0, fw - 4), h / 2 - 1, (h - 4) / 4, "#ffffff", 0.28);
      }
    }
    png() {
      const raw = Buffer.alloc((this.w * 4 + 1) * this.h);
      let seed = 12345;
      for (let y = 0; y < this.h; y++) {
        const row = y * (this.w * 4 + 1);
        raw[row] = 0;
        for (let x = 0; x < this.w; x++) {
          const i = (y * this.w + x) * 3;
          const o = row + 1 + x * 4;
          seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
          const noise = (seed / 4294967296 - 0.5) * 1.2; // a little dither keeps gradients smooth
          raw[o] = Math.max(0, Math.min(255, Math.round(this.px[i] + noise)));
          raw[o + 1] = Math.max(0, Math.min(255, Math.round(this.px[i + 1] + noise)));
          raw[o + 2] = Math.max(0, Math.min(255, Math.round(this.px[i + 2] + noise)));
          raw[o + 3] = 255;
        }
      }
      const ihdr = Buffer.alloc(13);
      ihdr.writeUInt32BE(this.w, 0);
      ihdr.writeUInt32BE(this.h, 4);
      ihdr[8] = 8;
      ihdr[9] = 6;
      return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 6 })), chunk("IEND", Buffer.alloc(0))]);
    }
  }
  function roundSdf(x, y, w, h, r) {
    return (px, py) => {
      const dx = Math.abs(px - (x + w / 2)) - (w / 2 - r);
      const dy = Math.abs(py - (y + h / 2)) - (h / 2 - r);
      return Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) + Math.min(Math.max(dx, dy), 0) - r;
    };
  }

  /* ---------- animated GIF ---------- */
  /* 255 colours that fit the given RGB samples best (median cut). */
  function medianCut(samples, count) {
    const total = samples.length / 3;
    const boxes = [Array.from({ length: total }, (_, i) => i)];
    const range = (box) => {
      const lo = [255, 255, 255];
      const hi = [0, 0, 0];
      for (const i of box) for (let k = 0; k < 3; k++) { const v = samples[i * 3 + k]; if (v < lo[k]) lo[k] = v; if (v > hi[k]) hi[k] = v; }
      const spans = [hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]];
      const channel = spans.indexOf(Math.max(...spans));
      return { channel, span: spans[channel] };
    };
    const info = boxes.map(range);
    while (boxes.length < count) {
      let pick = -1;
      let best = 0;
      for (let b = 0; b < boxes.length; b++) {
        const score = boxes[b].length > 1 ? info[b].span * Math.sqrt(boxes[b].length) : 0;
        if (score > best) { best = score; pick = b; }
      }
      if (pick < 0) break;
      const box = boxes[pick];
      const ch = info[pick].channel;
      box.sort((a, b) => samples[a * 3 + ch] - samples[b * 3 + ch]);
      const mid = box.length >> 1;
      const left = box.slice(0, mid);
      const right = box.slice(mid);
      boxes[pick] = left;
      info[pick] = range(left);
      boxes.push(right);
      info.push(range(right));
    }
    return boxes.map((box) => {
      let r = 0, g = 0, b = 0;
      for (const i of box) { r += samples[i * 3]; g += samples[i * 3 + 1]; b += samples[i * 3 + 2]; }
      const n = box.length || 1;
      return [Math.round(r / n), Math.round(g / n), Math.round(b / n)];
    });
  }

  /* GIF's own compression (LZW), the encoder of the classic gif.js. Returns the data sub-blocks. */
  function lzw(indices, minCode) {
    const clear = 1 << minCode;
    const eof = clear + 1;
    const bytes = [];
    let acc = 0;
    let bits = 0;
    let nbits = minCode + 1;
    let maxcode = (1 << nbits) - 1;
    let free = clear + 2;
    let clearFlag = false;
    const write = (code) => {
      acc |= code << bits;
      bits += nbits;
      while (bits >= 8) { bytes.push(acc & 255); acc >>>= 8; bits -= 8; }
    };
    const output = (code) => {
      write(code);
      if (free > maxcode || clearFlag) {
        if (clearFlag) { nbits = minCode + 1; maxcode = (1 << nbits) - 1; clearFlag = false; } else { nbits++; maxcode = nbits === 12 ? 4096 : (1 << nbits) - 1; }
      }
    };
    const dict = new Map();
    output(clear);
    let cur = indices[0];
    for (let i = 1; i < indices.length; i++) {
      const k = indices[i];
      const key = cur * 256 + k;
      const found = dict.get(key);
      if (found !== undefined) { cur = found; continue; }
      output(cur);
      cur = k;
      if (free < 4096) dict.set(key, free++);
      else { dict.clear(); free = clear + 2; clearFlag = true; output(clear); }
    }
    output(cur);
    output(eof);
    if (bits > 0) bytes.push(acc & 255);
    const out = [];
    for (let i = 0; i < bytes.length; i += 255) {
      const part = bytes.slice(i, i + 255);
      out.push(part.length, ...part);
    }
    out.push(0);
    return Buffer.from(out);
  }

  const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  /* Canvases -> one animated GIF (loops forever). Pixels that do not change from a frame to the next are left transparent. */
  function encodeGif(canvases, delayCs = 5) {
    const w = canvases[0].w;
    const h = canvases[0].h;
    // palette from a handful of frames
    const sample = [];
    const picks = [0, 0.25, 0.5, 0.75, 1].map((k) => Math.min(canvases.length - 1, Math.round(k * (canvases.length - 1)))).filter((v, i, a) => a.indexOf(v) === i);
    const stride = Math.max(1, Math.ceil((w * h * picks.length) / 30000)); // about 30 000 samples: enough for a good palette, quick to sort
    for (const f of picks) for (let i = 0; i < w * h; i += stride) sample.push(canvases[f].px[i * 3], canvases[f].px[i * 3 + 1], canvases[f].px[i * 3 + 2]);
    const palette = medianCut(Uint8Array.from(sample.map((v) => Math.max(0, Math.min(255, Math.round(v))))), 255);
    while (palette.length < 255) palette.push([0, 0, 0]);
    const TRANSPARENT = 255;
    const lut = new Int16Array(32768).fill(-1);
    const nearest = (r, g, b) => {
      const key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      if (lut[key] >= 0) return lut[key];
      const rr = (r & 0xf8) + 4, gg = (g & 0xf8) + 4, bb = (b & 0xf8) + 4;
      let best = 0;
      let bd = Infinity;
      for (let i = 0; i < 255; i++) {
        const d = (palette[i][0] - rr) ** 2 + (palette[i][1] - gg) ** 2 + (palette[i][2] - bb) ** 2;
        if (d < bd) { bd = d; best = i; }
      }
      lut[key] = best;
      return best;
    };
    const quantize = (c) => {
      const idx = new Uint8Array(w * h);
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 3;
        const dv = (BAYER[(y & 3) * 4 + (x & 3)] - 7.5) * 1.6;
        idx[y * w + x] = nearest(Math.max(0, Math.min(255, Math.round(c.px[i] + dv))), Math.max(0, Math.min(255, Math.round(c.px[i + 1] + dv))), Math.max(0, Math.min(255, Math.round(c.px[i + 2] + dv))));
      }
      return idx;
    };
    const head = Buffer.alloc(13);
    head.write("GIF89a", 0, "ascii");
    head.writeUInt16LE(w, 6);
    head.writeUInt16LE(h, 8);
    head[10] = 0xf7; // global colour table, 256 entries
    const table = Buffer.alloc(768);
    palette.forEach((c, i) => { table[i * 3] = c[0]; table[i * 3 + 1] = c[1]; table[i * 3 + 2] = c[2]; });
    const parts = [head, table, Buffer.from([0x21, 0xff, 0x0b, ...Buffer.from("NETSCAPE2.0", "ascii"), 3, 1, 0, 0, 0])];
    let prev = null;
    for (const canvas of canvases) {
      const idx = quantize(canvas);
      let x0 = 0, y0 = 0, x1 = w, y1 = h;
      let data = idx;
      let transparent = 0;
      if (prev) {
        let minx = w, miny = h, maxx = -1, maxy = -1;
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (idx[y * w + x] !== prev[y * w + x]) { if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
        if (maxx < 0) { minx = 0; miny = 0; maxx = 0; maxy = 0; }
        x0 = minx; y0 = miny; x1 = maxx + 1; y1 = maxy + 1;
        data = new Uint8Array((x1 - x0) * (y1 - y0));
        for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) data[(y - y0) * (x1 - x0) + (x - x0)] = idx[y * w + x] === prev[y * w + x] ? TRANSPARENT : idx[y * w + x];
        transparent = 1;
      }
      const gce = Buffer.from([0x21, 0xf9, 0x04, (1 << 2) | transparent, delayCs & 255, delayCs >> 8, TRANSPARENT, 0]);
      const desc = Buffer.alloc(10);
      desc[0] = 0x2c;
      desc.writeUInt16LE(x0, 1);
      desc.writeUInt16LE(y0, 3);
      desc.writeUInt16LE(x1 - x0, 5);
      desc.writeUInt16LE(y1 - y0, 7);
      parts.push(gce, desc, Buffer.from([8]), lzw(data, 8));
      prev = idx;
    }
    parts.push(Buffer.from([0x3b]));
    return Buffer.concat(parts);
  }

  /* ---------- logos of the payment methods (small PNGs with transparency) ---------- */
  const LOGO_B64 = {
    ltc: "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",
    paypal: "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",
  };
  const logoCache = new Map();
  const logo = (kind) => {
    if (!Object.prototype.hasOwnProperty.call(LOGO_B64, kind)) return null;
    if (!logoCache.has(kind)) logoCache.set(kind, decodePng(Buffer.from(LOGO_B64[kind], "base64")));
    return logoCache.get(kind);
  };

  /* ---------- shared look ---------- */
  const PALETTES = [
    ["#170f3d", "#3a1c78", "#7c4dff", "#ff4fd8", "#3ad1ff"], // purple
    ["#06204a", "#0b4a8f", "#19c7ff", "#6a5bff", "#00e0b0"], // ocean
    ["#2a0f3d", "#7a1f5c", "#ff6a3d", "#ffc94d", "#ff3d81"], // sunset
    ["#062b2b", "#0b5d4b", "#2effa8", "#2bb5ff", "#a6ff4d"], // emerald
    ["#1d1038", "#5a1f7a", "#ff5ccf", "#7a6bff", "#ffd34d"], // candy
  ];
  const pickPalette = (seed) => PALETTES[Math.floor(rngOf(seed + "pal")() * PALETTES.length)];
  const GOLD = [[0, "#fff3b0"], [0.5, "#ffc93c"], [1, "#ff8a1f"]];

  /* A colourful background: a gradient, soft glows, sparkles. */
  function aurora(c, seed, pal, sparkles = 14) {
    const r = rngOf(seed);
    const paint = lin(0, 0, c.w * 0.4, c.h, [[0, pal[0]], [1, pal[1]]]);
    for (let y = 0; y < c.h; y++) for (let x = 0; x < c.w; x++) {
      const col = paint(x, y);
      const i = (y * c.w + x) * 3;
      c.px[i] = col[0]; c.px[i + 1] = col[1]; c.px[i + 2] = col[2];
    }
    c.glow(c.w * (0.1 + r() * 0.3), c.h * (0.1 + r() * 0.6), c.w * 0.6, pal[2], 0.55);
    c.glow(c.w * (0.6 + r() * 0.35), c.h * (0.2 + r() * 0.7), c.w * 0.55, pal[3], 0.5);
    c.glow(c.w * (0.3 + r() * 0.4), c.h * (0.7 + r() * 0.4), c.w * 0.45, pal[4], 0.3);
    for (let k = 0; k < 7; k++) c.ring(r() * c.w, r() * c.h, 20 + r() * 70, 2, "#ffffff", 0.05 + r() * 0.05);
    for (let k = 0; k < sparkles; k++) c.sparkle(r() * c.w, r() * c.h, 3 + r() * 7, "#ffffff", 0.2 + r() * 0.5);
  }
  const fitSize = (c, str, maxWidth, maxSize, font = "bold", spacing = 0) => {
    let s = maxSize;
    while (s > 10 && c.measure(str, s, font, spacing) > maxWidth) s -= 2;
    return s;
  };
  const cutText = (c, str, maxWidth, size, font = "bold") => {
    let s = String(str ?? "");
    if (c.measure(s, size, font) <= maxWidth) return s;
    while (s.length > 1 && c.measure(`${s}…`, size, font) > maxWidth) s = s.slice(0, -1);
    return `${s}…`;
  };
  const initial = (name) => (String(name || "?").normalize("NFD").replace(/[^\p{L}\p{N}]/gu, "")[0] || "?").toUpperCase();

  /* The avatar of a member in a circle with a coloured ring (or a coloured disc with an initial). */
  function portrait(c, cx, cy, d, name, img, ringStops, glowColor) {
    c.glow(cx, cy, d * 0.95, glowColor, 0.55);
    c.circle(cx + 2, cy + 6, d / 2 + 4, "#000000", 0.35);
    c.ring(cx, cy, d / 2 + 5, 8, lin(cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2, ringStops));
    if (img) {
      c.avatar(img, cx, cy, d);
    } else {
      c.circle(cx, cy, d / 2, lin(cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2, [[0, "#7c8cff"], [1, "#d96bff"]]));
      c.text(initial(name), cx, cy, d * 0.5, { align: "center", shadow: { dy: 3, blur: 5, alpha: 0.4 } });
    }
  }

  /* ---------- cards ---------- */
  function rank({ name, level, into, need, rank: place, xp, label, avatar }) {
    const c = new Canvas(860, 280);
    const pal = pickPalette(name);
    aurora(c, name, pal);
    c.glass(24, 24, 812, 232, 34);
    portrait(c, 126, 140, 148, name, avatar, [[0, pal[3]], [1, pal[4]]], pal[2]);
    c.text(cutText(c, name, 410, 46), 224, 70, 46, { shadow: { dy: 3, blur: 6, alpha: 0.5 } });
    c.pill(224, 102, 158, 40, lin(224, 0, 382, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), `${label.rank} #${place}`, 22, { spacing: 2, glow: "#7c4dff" });
    c.text(`${xp} XP`, 398, 122, 24, { font: "regular", color: "#ffffff", alpha: 0.8 });
    c.text(label.level, 812, 56, 22, { align: "right", spacing: 6, font: "regular", color: "#ffffff", alpha: 0.75 });
    c.text(String(level), 812, 112, fitSize(c, String(level), 150, 92), { align: "right", gradient: GOLD, glow: { blur: 14, color: "#ffb02e", alpha: 0.5 }, shadow: { dy: 4, blur: 6, alpha: 0.45 } });
    c.bar(224, 168, 588, 34, into / need);
    c.text(`${into} / ${need} XP`, 224, 228, 22, { font: "regular", alpha: 0.9 });
    c.text(`${Math.round((into / need) * 100)}%`, 812, 228, 22, { align: "right", font: "regular", alpha: 0.9 });
    return c.png();
  }

  function leaderboard(rows, label) {
    const rowH = 90;
    const h = 150 + rows.length * rowH + 24;
    const c = new Canvas(900, h);
    aurora(c, "leaderboard", PALETTES[0], 20);
    c.text(label.title, 450, 64, fitSize(c, label.title, 700, 66), { align: "center", spacing: 4, gradient: [[0, "#ffffff"], [1, "#ffd9a0"]], glow: { blur: 16, color: "#ffb02e", alpha: 0.5 }, shadow: { dy: 4, blur: 8, alpha: 0.5 } });
    c.round(380, 104, 140, 4, lin(380, 0, 520, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]));
    const medal = [[[0, "#fff3b0"], [1, "#e69b1a"]], [[0, "#f4f6fb"], [1, "#9aa5bd"]], [[0, "#ffd0a0"], [1, "#b8651b"]]];
    rows.forEach((r, n) => {
      const y = 130 + n * rowH;
      c.glass(30, y, 840, rowH - 14, 38, n === 0 ? 0.15 : 0.09);
      if (n < 3) c.round(30, y, 840, rowH - 14, 38, medal[n][1][1], 0.12);
      const cy = y + (rowH - 14) / 2;
      c.circle(82, cy, 27, lin(55, cy - 27, 109, cy + 27, n < 3 ? medal[n] : [[0, "#6b7390"], [1, "#464c68"]]));
      c.text(String(n + 1), 82, cy, 28, { align: "center", color: n < 3 ? "#3a2a05" : "#ffffff" });
      if (r.avatar) {
        c.ring(158, cy, 30, 4, lin(128, cy - 30, 188, cy + 30, n < 3 ? medal[n] : [[0, "#7c8cff"], [1, "#d96bff"]]));
        c.avatar(r.avatar, 158, cy, 52);
      } else {
        c.circle(158, cy, 28, lin(130, cy - 28, 186, cy + 28, [[0, "#7c8cff"], [1, "#d96bff"]]));
        c.text(initial(r.name), 158, cy, 28, { align: "center" });
      }
      c.text(cutText(c, r.name, 330, 30), 206, cy - 12, 30, { shadow: { dy: 2, blur: 4, alpha: 0.4 } });
      c.bar(206, cy + 12, 330, 12, r.into / r.need);
      c.text(label.level, 836, cy - 18, 18, { align: "right", spacing: 4, font: "regular", alpha: 0.75 });
      c.text(String(r.level), 836, cy + 11, fitSize(c, String(r.level), 110, 42), { align: "right", gradient: GOLD, glow: { blur: 8, color: "#ffb02e", alpha: 0.4 } });
      c.text(r.sub ?? `${r.xp} XP`, 700, cy + 4, 22, { align: "right", font: "regular", alpha: 0.85 });
    });
    return c.png();
  }

  function levelUp({ name, level, from, label, avatar }) {
    const c = new Canvas(760, 300);
    const pal = ["#2b1604", "#7a3a0c", "#ffd34d", "#ff8a3d", "#fff0a0"];
    aurora(c, `${name}${level}`, pal, 10);
    const r = rngOf(`${name}${level}confetti`);
    const colors = ["#ffd34d", "#ff5ccf", "#5cd5ff", "#7cffb0", "#ffffff", "#ff8a3d"];
    for (let k = 0; k < 46; k++) c.confetti(r() * 760, r() * 300, 8 + r() * 10, 4 + r() * 5, r() * Math.PI, colors[Math.floor(r() * colors.length)], 0.55 + r() * 0.4);
    c.glass(20, 20, 720, 260, 34, 0.1);
    portrait(c, 140, 150, 156, name, avatar, GOLD, "#ffb02e");
    c.text(label.up, 236, 78, fitSize(c, label.up, 480, 66), { gradient: GOLD, glow: { blur: 16, color: "#ffb02e", alpha: 0.6 }, shadow: { dy: 4, blur: 8, alpha: 0.55 } });
    c.text(cutText(c, name, 470, 34), 236, 140, 34, { shadow: { dy: 2, blur: 5, alpha: 0.5 } });
    if (typeof from === "number") {
      c.text(String(from), 236, 214, 52, { font: "regular", alpha: 0.55 });
      const fx = 236 + c.measure(String(from), 52, "regular") + 16;
      c.text("→", fx, 214, 44, { color: "#ffd34d" });
      c.text(`${label.level} ${level}`, fx + 56, 214, 66, { gradient: GOLD, glow: { blur: 12, color: "#ffb02e", alpha: 0.55 }, shadow: { dy: 4, blur: 6, alpha: 0.5 } });
    } else c.text(`${label.level} ${level}`, 236, 214, 66, { gradient: GOLD, glow: { blur: 12, color: "#ffb02e", alpha: 0.55 } });
    return c.png();
  }

  function coin(face, letter, caption) {
    const c = new Canvas(320, 340);
    aurora(c, "coin", PALETTES[0], 10);
    c.ellipseSoft(160, 288, 96, 14, 14, "#000000", 0.5);
    c.glow(160, 150, 160, "#ffb02e", 0.35);
    c.circle(160, 150, 122, lin(60, 40, 260, 260, [[0, "#fff3b0"], [0.45, "#f0b429"], [1, "#9a5d08"]]));
    c.circle(160, 150, 106, lin(60, 40, 260, 260, [[0, "#c47a0c"], [1, "#fff0a0"]]));
    c.circle(160, 150, 100, radial(130, 110, 150, [[0, "#ffe680"], [0.6, "#f0b429"], [1, "#c8860e"]]));
    c.ring(160, 150, 82, 3, "#a86a0a", 0.5);
    c.text(letter, 160, 150, 128, { align: "center", color: "#ffeaa0", shadow: { dx: -2, dy: -2, blur: 1, color: "#fff7cc", alpha: 0.7 } });
    c.text(letter, 160, 150, 128, { align: "center", gradient: [[0, "#b8730a"], [1, "#7a4505"]], shadow: { dx: 2, dy: 3, blur: 2, color: "#5a3200", alpha: 0.5 } });
    c.ellipseSoft(112, 92, 52, 20, 18, "#ffffff", 0.35);
    c.sparkle(262, 66, 11, "#ffffff", 0.9);
    c.sparkle(54, 214, 8, "#ffe9a0", 0.9);
    c.sparkle(274, 226, 6, "#ffffff", 0.7);
    if (caption) c.pill(110, 296, 100, 34, lin(110, 0, 210, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), caption, 20, { spacing: 3, glow: "#7c4dff" });
    return c.png();
  }

  function dice(faces, value) {
    const c = new Canvas(320, 340);
    aurora(c, `dice${value}`, PALETTES[1], 10);
    c.ellipseSoft(160, 290, 98, 14, 14, "#000000", 0.5);
    c.roundShadow(52, 48, 216, 216, 48, 24, "#000000", 0.35, 14);
    c.round(52, 48, 216, 216, 48, lin(52, 48, 268, 264, [[0, "#ffffff"], [1, "#cfd6ee"]]));
    c.round(58, 54, 204, 204, 42, lin(58, 54, 262, 258, [[0, "#f6f8ff"], [1, "#e6eaf8"]]));
    c.round(66, 58, 188, 60, 30, "#ffffff", 0.55);
    const pips = { 1: [[0, 0]], 2: [[-1, -1], [1, 1]], 3: [[-1, -1], [0, 0], [1, 1]], 4: [[-1, -1], [1, -1], [-1, 1], [1, 1]], 5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]], 6: [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]] };
    if (faces <= 6) {
      for (const [dx, dy] of pips[value]) {
        const x = 160 + dx * 56;
        const y = 156 + dy * 56;
        c.circle(x + 1, y + 3, 20, "#000000", 0.18);
        c.circle(x, y, 20, radial(x - 6, y - 7, 30, [[0, "#4a4f8f"], [1, "#12132e"]]));
        c.circle(x - 6, y - 7, 5, "#ffffff", 0.45);
      }
    } else {
      c.text(String(value), 160, 156, fitSize(c, String(value), 150, 118), { align: "center", gradient: [[0, "#4a4f8f"], [1, "#12132e"]], shadow: { dy: 3, blur: 3, alpha: 0.25 } });
    }
    c.pill(116, 298, 88, 34, lin(116, 0, 204, 0, [[0, "#19c7ff"], [1, "#7c4dff"]]), `d${faces}`, 22, { spacing: 2, glow: "#19c7ff" });
    return c.png();
  }

  function eightBall() {
    const c = new Canvas(320, 320);
    aurora(c, "8ball", PALETTES[0], 12);
    c.ellipseSoft(160, 286, 96, 13, 14, "#000000", 0.5);
    c.glow(160, 150, 170, "#7c4dff", 0.45);
    c.circle(160, 148, 124, radial(120, 96, 200, [[0, "#5b5f99"], [0.35, "#15172e"], [1, "#04040c"]]));
    c.circle(160, 128, 58, lin(110, 70, 210, 190, [[0, "#ffffff"], [1, "#c9cee8"]]));
    c.text("8", 160, 128, 92, { align: "center", gradient: [[0, "#2a2d5e"], [1, "#0b0b1f"]], shadow: { dy: 2, blur: 2, alpha: 0.2 } });
    c.ellipseSoft(106, 78, 46, 22, 20, "#ffffff", 0.45);
    c.sparkle(262, 52, 10, "#ffffff", 0.9);
    c.sparkle(52, 236, 7, "#c9b6ff", 0.9);
    return c.png();
  }

  function quizCard(lines, label, opts = {}) {
    const c = new Canvas(720, 320);
    aurora(c, lines.join("|"), PALETTES[0], 16);
    c.glass(20, 20, 680, 280, 36, 0.09);
    c.pill(44, 40, 118, 42, lin(44, 0, 162, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), label, 24, { spacing: 4, glow: "#7c4dff" });
    c.pill(584, 40, 92, 42, lin(584, 0, 676, 0, [[0, "#19c7ff"], [1, "#7c4dff"]]), opts.timer || "30 s", 22, { spacing: 1, glow: "#19c7ff" });
    const spacing = opts.spacing || 0;
    const size = Math.min(...lines.map((l) => fitSize(c, l, 600, 104, "bold", spacing)));
    const total = lines.length * CAP * size + (lines.length - 1) * 30;
    let y = 190 - total / 2 + (CAP * size) / 2 + 14;
    for (const l of lines) {
      c.text(l, 360, y, size, { align: "center", spacing, gradient: [[0, "#ffffff"], [1, "#d9d2ff"]], glow: { blur: 14, color: "#9b7bff", alpha: 0.6 }, shadow: { dy: 4, blur: 8, alpha: 0.5 } });
      y += CAP * size + 30;
    }
    c.round(300, 276, 120, 4, lin(300, 0, 420, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]));
    return c.png();
  }

  /* The shield with a check mark: the sign of the panels. */
  function shield(c, cx, cy, size, stops) {
    const q = (p0, p1, p2) => Array.from({ length: 9 }, (_, k) => {
      const t = k / 8;
      const u = 1 - t;
      return [u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]];
    });
    const s = size / 2;
    const P = (x, y) => [cx + x * s, cy + y * s];
    const poly = [P(0, -1), P(0.9, -0.66), P(0.9, 0.06), ...q(P(0.9, 0.06), P(0.9, 0.64), P(0, 1)), ...q(P(0, 1), P(-0.9, 0.64), P(-0.9, 0.06)), P(-0.9, -0.66)];
    c.glow(cx, cy, size * 1.1, stops[stops.length - 1][1], 0.5);
    c.polygons([poly.map(([x, y]) => [x + 3, y + 7])], "#000000", 0.35);
    c.polygons([poly], lin(cx - s, cy - s, cx + s, cy + s, stops));
    c.polygons([[P(0, -0.86), P(0.76, -0.58), P(0.76, 0.04), P(0, 0.04)]], "#ffffff", 0.16);
    c.segment(...P(-0.36, 0.02), ...P(-0.1, 0.32), size * 0.13, "#ffffff");
    c.segment(...P(-0.1, 0.32), ...P(0.4, -0.3), size * 0.13, "#ffffff");
  }

  function banner(title, subtitle, colorA, colorB, mark) {
    const c = new Canvas(900, 176);
    aurora(c, `${title}${subtitle}`, [colorA, colorB, "#7c4dff", "#19c7ff", "#ff4fd8"], 12);
    c.glass(18, 18, 864, 140, 32, 0.08);
    const picture = mark ? logo(mark) : null;
    if (picture) {
      // the logo of the payment method on a white disc, so it stands out on any colour
      c.glow(100, 88, 92, "#ffffff", 0.3);
      c.circle(103, 95, 50, "#000000", 0.32);
      c.circle(100, 88, 50, "#ffffff");
      c.image(picture, 100, 88, mark === "ltc" ? 88 : 64);
    } else if (mark === "swap") {
      // two arrows going opposite ways on a white disc: a trade
      c.glow(100, 88, 92, "#ffffff", 0.3);
      c.circle(103, 95, 50, "#000000", 0.32);
      c.circle(100, 88, 50, "#ffffff");
      const arrow = (dir, y, color) => {
        c.segment(100 - dir * 24, y, 100 + dir * 14, y, 8, color);
        c.polygons([[[100 + dir * 30, y], [100 + dir * 12, y - 14], [100 + dir * 12, y + 14]]], color);
      };
      arrow(1, 74, "#19c7a0");
      arrow(-1, 102, "#7c4dff");
    } else shield(c, 100, 88, 92, [[0, "#ffffff"], [0.5, "#bfa8ff"], [1, "#6c4dff"]]);
    c.text(title, 170, 64, fitSize(c, title, 680, 82), { gradient: [[0, "#ffffff"], [1, "#d9ccff"]], glow: { blur: 14, color: "#9b7bff", alpha: 0.6 }, shadow: { dy: 4, blur: 7, alpha: 0.55 } });
    const w = Math.min(600, c.measure(subtitle, 22, "bold", 4) + 44);
    c.round(170, 102, w, 40, 20, "#000000", 0.28);
    c.shape((px, py) => Math.abs(roundSdf(170, 102, w, 40, 20)(px, py) + 1) - 0.9, 168, 100, 170 + w + 2, 144, lin(170, 102, 170 + w, 142, [[0, "#ffffff"], [1, "#9aa4ff"]]), 0.35);
    c.text(subtitle, 170 + w / 2, 122, 22, { align: "center", spacing: 4, gradient: [[0, "#fff3b0"], [1, "#ffc93c"]] });
    return c.png();
  }

  /* The welcome picture: a background, a foreground (glass, avatar, texts) and the moving parts. */
  function welcomeScene({ name, server, count, avatar, label }) {
    const W = 720;
    const H = 240;
    const pal = pickPalette(name);
    const bg = new Canvas(W, H);
    aurora(bg, `welcome${name}`, pal, 8);

    // The foreground is drawn on black and on white, which gives its exact transparency: it can then be laid over every frame.
    const drawForeground = (c) => {
      c.glass(18, 18, W - 36, H - 36, 34, 0.1);
      c.circle(120, 128, 76, "#000000", 0.3);
      if (avatar) c.avatar(avatar, 118, 120, 140);
      else {
        c.circle(118, 120, 70, lin(48, 50, 188, 190, [[0, "#7c8cff"], [1, "#d96bff"]]));
        c.text(initial(name), 118, 120, 70, { align: "center", shadow: { dy: 3, blur: 5, alpha: 0.4 } });
      }
      c.text(cutText(c, name, 460, 38), 222, 112, 38, { shadow: { dy: 3, blur: 6, alpha: 0.5 } });
      c.text(cutText(c, `${label.to} ${server}`, 460, 24, "regular"), 222, 148, 24, { font: "regular", alpha: 0.85 });
      const pillText = `${label.member} #${count}`;
      c.pill(222, 172, c.measure(pillText, 20, "bold", 2) + 40, 36, lin(222, 0, 460, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), pillText, 20, { spacing: 2, glow: "#7c4dff" });
    };
    const onBlack = new Canvas(W, H, "#000000");
    const onWhite = new Canvas(W, H, "#ffffff");
    drawForeground(onBlack);
    drawForeground(onWhite);
    const overlay = { rgb: new Float32Array(W * H * 3), a: new Float32Array(W * H) };
    for (let i = 0; i < W * H; i++) {
      let alpha = 0;
      for (let k = 0; k < 3; k++) alpha += 1 - (onWhite.px[i * 3 + k] - onBlack.px[i * 3 + k]) / 255;
      alpha = clamp01(alpha / 3);
      overlay.a[i] = alpha;
      for (let k = 0; k < 3; k++) overlay.rgb[i * 3 + k] = alpha > 0.003 ? Math.min(255, onBlack.px[i * 3 + k] / alpha) : 0;
    }
    const rnd = rngOf(`confetti${name}`);
    const confetti = Array.from({ length: 36 }, () => ({ x: rnd() * W, y: rnd() * H, w: 8 + rnd() * 9, h: 4 + rnd() * 4, speed: 1 + Math.floor(rnd() * 2), a: rnd() * Math.PI, spin: (rnd() < 0.5 ? -1 : 1) * (1 + Math.floor(rnd() * 2)), color: ["#ffd34d", "#ff5ccf", "#5cd5ff", "#7cffb0", "#ffffff", "#ff8a3d"][Math.floor(rnd() * 6)], sway: rnd() * 6 }));
    const twinkle = Array.from({ length: 9 }, () => ({ x: 230 + rnd() * 470, y: 26 + rnd() * 190, r: 3 + rnd() * 5, phase: rnd() }));

    /* The picture at time t in [0, 1): everything moves in a loop. */
    const render = (t) => {
      const c = bg.clone();
      const pulse = 0.5 + 0.5 * Math.sin(2 * Math.PI * t);
      c.glow(118, 120, 118 + 16 * pulse, pal[2], 0.45 + 0.25 * pulse);
      for (const k of confetti) {
        const y = ((k.y + t * H * k.speed) % (H + 40)) - 20;
        const x = k.x + Math.sin(2 * Math.PI * t * k.speed + k.sway) * 10;
        c.confetti(x, y, k.w, k.h, k.a + 2 * Math.PI * t * k.spin, k.color, 0.9);
      }
      for (let i = 0; i < W * H; i++) { // the foreground over it
        const al = overlay.a[i];
        if (al > 0.003) {
          const j = i * 3;
          c.px[j] += (overlay.rgb[j] - c.px[j]) * al;
          c.px[j + 1] += (overlay.rgb[j + 1] - c.px[j + 1]) * al;
          c.px[j + 2] += (overlay.rgb[j + 2] - c.px[j + 2]) * al;
        }
      }
      c.ring(118, 120, 77 + 2 * pulse, 7 + 3 * pulse, lin(40, 40, 200, 200, [[0, pal[3]], [1, pal[4]]])); // over the avatar's shadow: it shines
      // moving shine across the title
      const bandX = 214 + (t * 1.6 - 0.3) * 470;
      c.text(label.welcome, 222, 64, fitSize(c, label.welcome, 460, 60), {
        spacing: 3,
        paint: (top, base) => {
          const g = lin(0, top, 0, base, [[0, "#ffffff"], [1, "#ffd9a0"]]);
          return (x, y) => mixc(g(x, y), [255, 255, 255], Math.max(0, 1 - Math.abs(x - bandX - (y - top) * 0.7) / 60) * 0.9);
        },
        glow: { blur: 14, color: "#ffb02e", alpha: 0.5 },
        shadow: { dy: 4, blur: 8, alpha: 0.5 },
      });
      const orbit = 2 * Math.PI * t - Math.PI / 2;
      c.sparkle(118 + Math.cos(orbit) * 92, 120 + Math.sin(orbit) * 92, 9, "#ffffff", 0.95);
      for (const k of twinkle) c.sparkle(k.x, k.y, k.r * (0.35 + 0.65 * Math.abs(Math.sin(Math.PI * (t * 2 + k.phase)))), "#ffffff", 0.85);
      return c;
    };
    return { render, w: W, h: H };
  }
  const welcome = (opts) => welcomeScene(opts).render(0.3).png();
  const FRAMES = 24;
  const welcomeAnimated = (opts) => {
    const scene = welcomeScene(opts);
    return encodeGif(Array.from({ length: FRAMES }, (_, f) => scene.render(f / FRAMES)), 5);
  };

  /* A picture drawn on black and on white gives its exact transparency, so it can be laid over every frame. */
  function overlayOf(W, H, draw) {
    const onBlack = new Canvas(W, H, "#000000");
    const onWhite = new Canvas(W, H, "#ffffff");
    draw(onBlack);
    draw(onWhite);
    const overlay = { rgb: new Float32Array(W * H * 3), a: new Float32Array(W * H), W, H };
    for (let i = 0; i < W * H; i++) {
      let alpha = 0;
      for (let k = 0; k < 3; k++) alpha += 1 - (onWhite.px[i * 3 + k] - onBlack.px[i * 3 + k]) / 255;
      alpha = clamp01(alpha / 3);
      overlay.a[i] = alpha;
      for (let k = 0; k < 3; k++) overlay.rgb[i * 3 + k] = alpha > 0.003 ? Math.min(255, onBlack.px[i * 3 + k] / alpha) : 0;
    }
    return overlay;
  }
  function layOver(c, overlay) {
    for (let i = 0; i < overlay.W * overlay.H; i++) {
      const al = overlay.a[i];
      if (al > 0.003) {
        const j = i * 3;
        c.px[j] += (overlay.rgb[j] - c.px[j]) * al;
        c.px[j + 1] += (overlay.rgb[j + 1] - c.px[j + 1]) * al;
        c.px[j + 2] += (overlay.rgb[j + 2] - c.px[j + 2]) * al;
      }
    }
  }
  /* A bouncing gift box. t in [0, 1) loops. */
  function giftBox(c, cx, cy, S, t) {
    const phase = Math.abs(Math.sin(2 * Math.PI * t));
    const y0 = cy - phase * S * 0.16;
    c.ellipseSoft(cx, cy + S * 0.62, S * 0.46 * (1 - phase * 0.3), S * 0.06, 10, "#000000", 0.38);
    c.glow(cx, y0 + S * 0.2, S * 0.95, "#ffb02e", 0.25 + 0.15 * phase);
    c.round(cx - 0.43 * S, y0 - 0.02 * S, 0.86 * S, 0.54 * S, 0.07 * S, lin(cx - S / 2, y0, cx + S / 2, y0 + 0.5 * S, [[0, "#ff6b95"], [1, "#d02060"]]));
    c.round(cx - 0.4 * S, y0, 0.18 * S, 0.5 * S, 0.05 * S, "#ffffff", 0.16);
    c.round(cx - 0.49 * S, y0 - 0.2 * S, 0.98 * S, 0.24 * S, 0.06 * S, lin(cx, y0 - 0.2 * S, cx, y0 + 0.04 * S, [[0, "#ff9ab6"], [1, "#e63a73"]]));
    c.round(cx - 0.07 * S, y0 - 0.2 * S, 0.14 * S, 0.74 * S, 2, lin(cx - 0.07 * S, 0, cx + 0.07 * S, 0, [[0, "#fff3b0"], [1, "#ffb02e"]]));
    for (const dir of [-1, 1]) {
      c.ellipse(cx + dir * 0.16 * S, y0 - 0.27 * S, 0.15 * S, 0.095 * S, lin(cx, y0 - 0.4 * S, cx, y0 - 0.15 * S, [[0, "#fff3b0"], [1, "#ffb02e"]]));
      c.ellipse(cx + dir * 0.16 * S, y0 - 0.27 * S, 0.08 * S, 0.045 * S, "#c2740a", 0.55);
    }
    c.circle(cx, y0 - 0.22 * S, 0.065 * S, lin(cx, y0 - 0.3 * S, cx, y0 - 0.15 * S, [[0, "#ffe27a"], [1, "#e0971a"]]));
  }
  /* The "GIVEAWAY" banner: a gift that bounces, confetti, sparkles, a shine over the title. */
  function giveawayScene({ prize, winners, host, label }) {
    const W = 720;
    const H = 240;
    const pal = ["#2a1250", "#6a2a8a", "#ffb02e", "#ff5ccf", "#7a6bff"];
    const bg = new Canvas(W, H);
    aurora(bg, `giveaway${prize}`, pal, 8);
    const overlay = overlayOf(W, H, (c) => {
      c.glass(18, 18, W - 36, H - 36, 34, 0.1);
      c.text(cutText(c, prize, 450, 46), 232, 128, fitSize(c, cutText(c, prize, 450, 46), 450, 46), { shadow: { dy: 3, blur: 6, alpha: 0.5 } });
      const pill = `${winners} ${winners > 1 ? label.winnersMany : label.winnersOne}`;
      c.pill(232, 164, c.measure(pill, 20, "bold", 2) + 40, 36, lin(232, 0, 470, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), pill, 20, { spacing: 2, glow: "#7c4dff" });
      if (host) c.text(cutText(c, `${label.by} ${host}`, 300, 20, "regular"), 700 - 22, 182, 20, { align: "right", font: "regular", alpha: 0.8 });
    });
    const rnd = rngOf(`gwconfetti${prize}`);
    const confetti = Array.from({ length: 34 }, () => ({ x: rnd() * W, y: rnd() * H, w: 8 + rnd() * 9, h: 4 + rnd() * 4, speed: 1 + Math.floor(rnd() * 2), a: rnd() * Math.PI, spin: (rnd() < 0.5 ? -1 : 1) * (1 + Math.floor(rnd() * 2)), color: ["#ffd34d", "#ff5ccf", "#5cd5ff", "#7cffb0", "#ffffff", "#ff8a3d"][Math.floor(rnd() * 6)], sway: rnd() * 6 }));
    const twinkle = Array.from({ length: 8 }, () => ({ x: 230 + rnd() * 470, y: 26 + rnd() * 190, r: 3 + rnd() * 5, phase: rnd() }));
    const render = (t) => {
      const c = bg.clone();
      for (const k of confetti) c.confetti(k.x + Math.sin(2 * Math.PI * t * k.speed + k.sway) * 10, ((k.y + t * H * k.speed) % (H + 40)) - 20, k.w, k.h, k.a + 2 * Math.PI * t * k.spin, k.color, 0.9);
      layOver(c, overlay);
      giftBox(c, 118, 112, 112, t);
      const bandX = 224 + (t * 1.6 - 0.3) * 470;
      c.text(label.title, 232, 70, fitSize(c, label.title, 450, 54, "bold", 4), {
        spacing: 4,
        paint: (top, base) => {
          const g = lin(0, top, 0, base, [[0, "#fff3b0"], [1, "#ffb02e"]]);
          return (x, y) => mixc(g(x, y), [255, 255, 255], Math.max(0, 1 - Math.abs(x - bandX - (y - top) * 0.7) / 55) * 0.9);
        },
        glow: { blur: 14, color: "#ffb02e", alpha: 0.5 },
        shadow: { dy: 4, blur: 8, alpha: 0.5 },
      });
      const orbit = 2 * Math.PI * t;
      c.sparkle(118 + Math.cos(orbit) * 84, 112 + Math.sin(orbit) * 70, 8, "#ffffff", 0.9);
      for (const k of twinkle) c.sparkle(k.x, k.y, k.r * (0.35 + 0.65 * Math.abs(Math.sin(Math.PI * (t * 2 + k.phase)))), "#ffffff", 0.85);
      return c;
    };
    return { render };
  }
  const giveawayAnimated = (opts) => {
    const scene = giveawayScene(opts);
    return encodeGif(Array.from({ length: 24 }, (_, f) => scene.render(f / 24)), 5);
  };
  /* The card of the end: a crown over the first winner, the names, how many entered. */
  function giveawayEnd({ prize, winners, count, label }) {
    const c = new Canvas(720, 240);
    aurora(c, `gwend${prize}`, ["#2b1604", "#7a3a0c", "#ffd34d", "#ff8a3d", "#fff0a0"], 12);
    const r = rngOf(`gwendconfetti${prize}`);
    for (let k = 0; k < 40; k++) c.confetti(r() * 720, r() * 240, 8 + r() * 10, 4 + r() * 5, r() * Math.PI, ["#ffd34d", "#ff5ccf", "#5cd5ff", "#7cffb0", "#ffffff", "#ff8a3d"][Math.floor(r() * 6)], 0.55 + r() * 0.4);
    c.glass(18, 18, 684, 204, 34, 0.1);
    const first = winners[0];
    if (first) {
      portrait(c, 124, 132, 112, first.name, first.avatar, GOLD, "#ffb02e");
      const crown = [[-36, 24], [-36, -6], [-18, 12], [0, -20], [18, 12], [36, -6], [36, 24]].map(([x, y]) => [124 + x, 56 + y]);
      c.polygons([crown.map(([x, y]) => [x + 2, y + 5])], "#000000", 0.3);
      c.polygons([crown], lin(88, 36, 160, 80, [[0, "#fff3b0"], [0.5, "#ffc93c"], [1, "#e08a1a"]]));
      for (const [x, y] of [[-36, -6], [0, -20], [36, -6]]) c.circle(124 + x, 56 + y, 4.5, "#ffffff", 0.95);
    }
    const title = winners.length > 1 ? label.winnersMany : winners.length === 1 ? label.winnersOne : label.noWinner;
    c.text(title, 226, 56, fitSize(c, title, 450, 48, "bold", 4), { spacing: 4, gradient: GOLD, glow: { blur: 14, color: "#ffb02e", alpha: 0.55 }, shadow: { dy: 4, blur: 8, alpha: 0.55 } });
    const shownNames = winners.length > 3 ? winners.slice(0, 2) : winners.slice(0, 3);
    shownNames.forEach((w, n) => c.text(cutText(c, w.name, 440, 28), 226, 98 + n * 32, 28, { shadow: { dy: 2, blur: 4, alpha: 0.5 } }));
    if (winners.length > 3) c.text(`+ ${winners.length - 2}`, 226, 98 + 2 * 32, 24, { font: "regular", alpha: 0.85 });
    if (!winners.length) c.text(cutText(c, prize, 440, 30), 226, 110, 30, { font: "regular", alpha: 0.9 });
    const pillText = `${count} ${label.entries}`;
    c.pill(226, 192, c.measure(pillText, 18, "bold", 2) + 36, 30, lin(226, 0, 440, 0, [[0, "#7c4dff"], [1, "#ff4fd8"]]), pillText, 18, { spacing: 2, glow: "#7c4dff" });
    if (winners.length) c.text(cutText(c, prize, 250, 20, "regular"), 700 - 22, 207, 20, { align: "right", font: "regular", alpha: 0.85 });
    return c.png();
  }

  return { Canvas, decodePng, encodeGif, logo, giveawayAnimated, giveawayEnd, banner, rank, leaderboard, levelUp, coin, dice, eightBall, quizCard, welcome, welcomeAnimated, shield, measure: (s, size, font) => new Canvas(1, 1).measure(s, size, font), ascii: (s) => String(s ?? "") };
})();

/* =====================================================
   PART 3: MULTITOOLS (levels, moderation, welcome, roles, fun, logs, security)
   Separate from the middleman: its own file (tools.json), switched off with TOOLS=off.
===================================================== */

const tools = (() => {
  const fs = require("fs");
  const path = require("path");
  const {
    ActionRowBuilder,
    AttachmentBuilder,
    ButtonBuilder,
    ButtonStyle,
    ChannelType,
    EmbedBuilder,
    Events,
    MessageFlags,
    ModalBuilder,
    PermissionFlagsBits: P,
    SlashCommandBuilder,
    TextInputBuilder,
    TextInputStyle,
    UserSelectMenuBuilder,
  } = require("discord.js");

  const ON = !/^(off|no|false|0)$/i.test(String(process.env.TOOLS || "on").trim());
  const FR = String(process.env.TOOLS_LANG || "fr").trim().toLowerCase() !== "en";
  const t = (fr, en) => (FR ? fr : en);
  const ephemeral = MessageFlags.Ephemeral;
  const FILE = path.join(process.env.DATA_DIR || __dirname, "tools.json");

  /* ---------- storage ---------- */
  const defaults = () => ({
    xp: {},
    warns: {},
    polls: {},
    giveaways: {},
    locks: {},
    claims: {},
    crosstrades: {},
    crossStats: { opened: 0, done: 0 },
    vouches: {},
    vouchN: 0,
    voc: { hubs: [], rooms: {} },
    setup: { items: [], voiceItems: [], levelRoles: [], autoWelcome: false },
    cfg: {
      levels: { on: true, rewards: [], announce: true, ignored: [], channelId: "", quizXp: 50, stack: false, xpChannelId: "", xpStep: 100, voiceOn: true, voiceXp: 8, voiceMinPeople: 2 },
      welcome: { channelId: "", message: "", leave: "", leaveChannelId: "", autorole: "" },
      logs: { channelId: "" },
      suggest: { channelId: "" },
      vouch: { channelId: "", cooldownH: 24, panelChannelId: "", panelMsgId: "", stickyMsgId: "" },
      autoquiz: { on: false, channelId: "", minutes: 30, nextAt: 0 },
      apps: {
        staffRoleId: "",
        mmRoleId: "",
        categoryId: "",
        claim: { xp: 5000, reward: "Garama" },
        access: { trade: { channelId: "1570218139113758740", roleId: "1570262105309847642", label: "Trade OG" }, shop: { channelId: "1570218143903912007", roleId: "1570262023546339429", label: "Shop OG" } },
      },
      security: { antiSpam: false, antiLink: "off", antiRaid: false },
    },
  });
  let db = defaults();
  let saveTimer = null;
  /* Reads tools.json. A file written by an older version gets every missing setting filled with its default. */
  function load() {
    let raw = {};
    try {
      raw = JSON.parse(fs.readFileSync(FILE, "utf8")) || {};
    } catch {
      /* first start (or unreadable file): defaults */
    }
    const base = defaults();
    const next = { ...base, ...raw };
    next.cfg = { ...(raw.cfg || {}) };
    for (const key of Object.keys(base.cfg)) next.cfg[key] = { ...base.cfg[key], ...(raw.cfg?.[key] || {}) };
    next.setup = { ...base.setup, ...(raw.setup || {}) };
    next.cfg.apps.claim = { ...base.cfg.apps.claim, ...(raw.cfg?.apps?.claim || {}) };
    next.cfg.apps.access = { trade: { ...base.cfg.apps.access.trade, ...(raw.cfg?.apps?.access?.trade || {}) }, shop: { ...base.cfg.apps.access.shop, ...(raw.cfg?.apps?.access?.shop || {}) } };
    next.voc = { ...base.voc, ...(raw.voc || {}) };
    next.crossStats = { ...base.crossStats, ...(raw.crossStats || {}) };
    if (!Array.isArray(next.voc.hubs)) next.voc.hubs = [];
    if (!next.voc.rooms || typeof next.voc.rooms !== "object") next.voc.rooms = {};
    for (const key of ["xp", "warns", "polls", "giveaways", "locks", "claims", "crosstrades", "vouches"]) if (!next[key] || typeof next[key] !== "object") next[key] = {};
    for (const [group, keys] of [[next.setup, ["items", "voiceItems", "levelRoles"]], [next.cfg.levels, ["rewards", "ignored"]]]) for (const k of keys) if (!Array.isArray(group[k])) group[k] = [];
    for (const [k, v] of Object.entries(next.vouches)) if (!Array.isArray(v)) delete next.vouches[k];
    if (!Number.isFinite(next.vouchN)) next.vouchN = 0;
    db = next;
  }
  function save(now = false) {
    const write = () => {
      saveTimer = null;
      try {
        fs.writeFileSync(`${FILE}.tmp`, JSON.stringify(db));
        fs.renameSync(`${FILE}.tmp`, FILE);
      } catch (error) {
        console.error("⚠️ Tools: could not save tools.json:", error?.message || error);
      }
    };
    if (now) {
      if (saveTimer) clearTimeout(saveTimer);
      return write();
    }
    if (!saveTimer) saveTimer = setTimeout(write, 2000);
  }

  let client = null;
  const reply = (i, content) => i.reply({ content, flags: ephemeral });
  const ok = (text) => `✅ ${text}`;
  const no = (text) => `❌ ${text}`;
  const embed = (color = 0x5865f2) => new EmbedBuilder().setColor(color);

  /* ---------- levels ---------- */
  const need = (level) => 5 * level * level + 50 * level + 100; // xp to go from `level` to `level + 1`
  function levelOf(xp) {
    let level = 0;
    let rest = Math.max(0, xp | 0);
    while (rest >= need(level)) {
      rest -= need(level);
      level++;
    }
    return { level, into: rest, need: need(level) };
  }
  const bar = (part, whole, size = 12) => {
    const filled = Math.max(0, Math.min(size, Math.round((part / whole) * size)));
    return "▰".repeat(filled) + "▱".repeat(size - filled);
  };
  const rankOf = (userId) => {
    const sorted = Object.entries(db.xp).sort((a, b) => b[1] - a[1]);
    const index = sorted.findIndex(([id]) => id === userId);
    return index < 0 ? sorted.length + 1 : index + 1;
  };

  const cooldown = new Map();
  async function giveRewards(member, level) {
    const cfg = db.cfg.levels;
    const eligible = cfg.rewards.filter((r) => r.level <= level);
    if (!eligible.length || !member?.roles) return;
    const keep = cfg.stack ? eligible.map((r) => r.roleId) : [eligible[eligible.length - 1].roleId];
    for (const roleId of keep) {
      if (member.roles.cache.has(roleId)) continue;
      await member.roles.add(roleId, "level reward").catch(() => {});
    }
    if (!cfg.stack) {
      for (const r of cfg.rewards) {
        if (!keep.includes(r.roleId) && member.roles.cache.has(r.roleId)) await member.roles.remove(r.roleId, "higher level role").catch(() => {});
      }
    }
  }

  /* The ladder of level roles the bot can create: [level, name, colour]. Always in English. */
  const LADDER = [
    [1, "🌱 Newcomer", 0x95a5a6],
    [5, "⭐ Rookie", 0x3498db],
    [10, "🔥 Active", 0x1abc9c],
    [15, "💠 Regular", 0x2ecc71],
    [20, "⚔️ Veteran", 0x9b59b6],
    [30, "💎 Elite", 0xe91e63],
    [40, "👑 Master", 0xe67e22],
    [50, "🏆 Legend", 0xf1c40f],
  ];

  /* Creates the level roles, remembers them, and connects them to the levels. Returns how many. */
  async function createLevelRoles(guild) {
    if (db.setup.levelRoles.length) return 0;
    let made = 0;
    for (const [level, name, color] of LADDER) {
      const role = await guild.roles.create({ name, color, hoist: false, mentionable: false, reason: "level roles" });
      db.setup.levelRoles.push(role.id);
      db.cfg.levels.rewards = db.cfg.levels.rewards.filter((r) => r.level !== level);
      db.cfg.levels.rewards.push({ level, roleId: role.id });
      made++;
    }
    db.cfg.levels.rewards.sort((a, b) => a.level - b.level);
    save(true);
    return made;
  }

  /* The roles already exist: give them the current names and colours of the ladder. Returns how many changed. */
  async function refreshLevelRoles(guild) {
    let changed = 0;
    for (const [level, name, color] of LADDER) {
      const reward = db.cfg.levels.rewards.find((r) => r.level === level && db.setup.levelRoles.includes(r.roleId));
      if (!reward) continue;
      const role = await Promise.resolve(guild.roles.fetch?.(reward.roleId)).catch(() => null);
      if (!role || (role.name === name && role.color === color)) continue;
      try {
        await role.edit({ name, color, reason: "level roles updated" });
        changed++;
      } catch {
        /* the role keeps its name */
      }
    }
    return changed;
  }

  /* Deletes only the roles the bot created, and the rewards that pointed to them. Returns how many. */
  async function removeLevelRoles(guild) {
    let removed = 0;
    const ids = new Set(db.setup.levelRoles);
    for (const id of [...db.setup.levelRoles]) {
      const role = await Promise.resolve(guild.roles.fetch?.(id)).catch(() => null);
      if (role) {
        try {
          await role.delete("level roles removed");
          removed++;
        } catch {
          /* the role stays in Discord, forget it anyway */
        }
      }
    }
    db.cfg.levels.rewards = db.cfg.levels.rewards.filter((r) => !ids.has(r.roleId));
    db.setup.levelRoles = [];
    save(true);
    return removed;
  }

  const cardLabel = () => ({ level: t("NIVEAU", "LEVEL"), rank: t("RANG", "RANK"), title: t("CLASSEMENT", "LEADERBOARD"), up: t("NIVEAU SUPÉRIEUR !", "LEVEL UP!"), welcome: t("BIENVENUE", "WELCOME"), to: t("sur", "to"), member: t("MEMBRE", "MEMBER") });

  /* The welcome picture of a member: an animated GIF, or a still PNG when animating is not wanted or fails. */
  async function welcomeCard(member, animated = true) {
    const opts = { name: member.displayName || member.user?.username || "?", server: member.guild?.name || "", count: member.guild?.memberCount ?? 0, avatar: await loadAvatar(member), label: cardLabel() };
    if (animated) {
      try {
        await new Promise((resolve) => setImmediate(resolve)); // let other events through first: the animation takes about a second
        return picture("welcome.gif", gfx.welcomeAnimated(opts));
      } catch (error) {
        console.error("⚠️ Animated welcome failed, using a still picture:", error?.message || error);
      }
    }
    return picture("welcome.png", gfx.welcome(opts));
  }

  /* The profile picture of a member as a decoded image (null when it cannot be loaded: the card then shows an initial). */
  const avatarCache = new Map();
  async function loadAvatar(who, size = 128) {
    try {
      const url = who?.displayAvatarURL?.({ extension: "png", size, forceStatic: true });
      if (!url || !/^https?:\/\//.test(url) || typeof fetch !== "function") return null;
      if (avatarCache.has(url)) return avatarCache.get(url);
      const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
      if (!res.ok) return null;
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length > 3_000_000) return null;
      const img = gfx.decodePng(buf);
      if (avatarCache.size >= 200) avatarCache.delete(avatarCache.keys().next().value);
      avatarCache.set(url, img);
      return img;
    } catch {
      return null;
    }
  }
  const picture = (name, buffer) => ({ file: new AttachmentBuilder(buffer, { name }), url: `attachment://${name}` });

  async function announceLevel(member, level, fallbackChannel, from) {
    const cfg = db.cfg.levels;
    let channel = fallbackChannel;
    if (cfg.channelId) {
      const chosen = await Promise.resolve(member.guild?.channels?.fetch?.(cfg.channelId)).catch(() => null);
      if (chosen?.isTextBased?.()) channel = chosen;
    }
    if (!channel?.send) return;
    const name = member.displayName || member.user?.username || "?";
    const card = picture("levelup.png", gfx.levelUp({ name, level, from, label: cardLabel(), avatar: await loadAvatar(member.user || member) }));
    await channel
      .send({
        content: t(`🎉 <@${member.id}> passe **niveau ${level}** !`, `🎉 <@${member.id}> reached **level ${level}**!`),
        embeds: [embed(0x57f287).setImage(card.url)],
        files: [card.file],
        allowedMentions: { users: [member.id] },
      })
      .catch(() => {});
  }

  /* Adds xp to a member (messages and quiz), gives the reward roles and announces a new level. */
  /* Every `xpStep` xp (100 by default) a message is posted in the XP channel. One message even if several steps were passed at once. */
  async function announceXp(member, xpBefore, xpAfter) {
    const cfg = db.cfg.levels;
    const step = Math.max(1, Number(cfg.xpStep) || 100);
    if (!cfg.xpChannelId || Math.floor(xpAfter / step) <= Math.floor(xpBefore / step)) return;
    const channel = await Promise.resolve(member.guild?.channels?.fetch?.(cfg.xpChannelId)).catch(() => null);
    if (!channel?.isTextBased?.() || !channel.send) return;
    const milestone = Math.floor(xpAfter / step) * step;
    const l = levelOf(xpAfter);
    const e = embed(0xf1c40f)
      .setTitle(`⭐  ${milestone} XP`)
      .setDescription(`<@${member.id}> ${t("a atteint", "reached")} **${milestone} XP** !\n${t("Niveau", "Level")} **${l.level}**  ·  ${bar(l.into, l.need)}  ·  ${l.into} / ${l.need} XP`)
      .setThumbnail(member.displayAvatarURL?.() || member.user?.displayAvatarURL?.() || null);
    await channel.send({ embeds: [e], allowedMentions: { users: [member.id] } }).catch(() => {});
  }

  async function addXp(member, amount, fallbackChannel) {
    const xpBefore = db.xp[member.id] || 0;
    const before = levelOf(xpBefore).level;
    db.xp[member.id] = xpBefore + amount;
    const after = levelOf(db.xp[member.id]).level;
    save();
    await announceXp(member, xpBefore, db.xp[member.id]);
    await giveRewards(member, after);
    if (after > before && db.cfg.levels.announce) await announceLevel(member, after, fallbackChannel, before);
  }

  /* Voice activity: every minute, each person in a voice channel with enough other people (and not deafened) earns xp. */
  let lastVoiceXp = 0;
  async function tickVoiceXp() {
    const cfg = db.cfg.levels;
    if (!ON || !cfg.on || !cfg.voiceOn || !(cfg.voiceXp > 0) || !client?.guilds?.cache) return;
    const now = Date.now();
    if (now - lastVoiceXp < 55_000) return;
    lastVoiceXp = now;
    for (const guild of client.guilds.cache.values()) {
      for (const channel of guild.channels.cache.values()) {
        if (channel.type !== ChannelType.GuildVoice && channel.type !== ChannelType.GuildStageVoice) continue;
        if (channel.id === guild.afkChannelId || cfg.ignored.includes(channel.id)) continue;
        const people = [...(channel.members?.values?.() || [])].filter((m) => !m.user?.bot);
        if (people.length < Math.max(1, cfg.voiceMinPeople)) continue; // alone in a channel earns nothing
        for (const m of people) {
          if (m.voice?.selfDeaf || m.voice?.serverDeaf) continue; // deafened: not really there
          await addXp(m, cfg.voiceXp, null).catch((e) => console.error("⚠️ voice xp:", e?.message || e));
        }
      }
    }
  }

  async function onXp(message) {
    const cfg = db.cfg.levels;
    if (!cfg.on || message.author.bot || !message.guild || !message.member) return;
    if (cfg.ignored.includes(message.channelId)) return;
    const now = Date.now();
    if (now - (cooldown.get(message.author.id) || 0) < 60_000) return;
    cooldown.set(message.author.id, now);
    await addXp(message.member, 15 + Math.floor(Math.random() * 11), message.channel);
  }

  /* ---------- logs ---------- */
  async function log(guild, text, color = 0x747f8d) {
    const id = db.cfg.logs.channelId;
    if (!id) return;
    const channel = await Promise.resolve((guild?.channels || client?.channels)?.fetch?.(id)).catch(() => null);
    if (channel?.isTextBased?.()) await channel.send({ embeds: [embed(color).setDescription(String(text).slice(0, 3900)).setTimestamp()], allowedMentions: { parse: [] } }).catch(() => {});
  }

  /* ---------- helpers ---------- */
  const need_perm = (i, flag) => {
    if (i.memberPermissions?.has?.(flag) || i.member?.permissions?.has?.(flag)) return false;
    reply(i, no(t("Tu n'as pas la permission pour ça.", "You do not have the permission for that.")));
    return true;
  };
  const canAct = (i, target) => {
    // the target must be below the moderator and below the bot
    const me = i.guild?.members?.me;
    if (!target) return null;
    if (target.id === i.user.id) return t("Tu ne peux pas faire ça sur toi-même.", "You cannot do that to yourself.");
    if (target.id === i.guild?.ownerId) return t("Impossible sur le propriétaire du serveur.", "Not possible on the server owner.");
    if (me && target.roles?.highest && me.roles.highest.comparePositionTo(target.roles.highest) <= 0) return t("Mon rôle est trop bas pour cette personne.", "My role is too low for this person.");
    if (i.guild?.ownerId !== i.user.id && i.member?.roles?.highest && target.roles?.highest && i.member.roles.highest.comparePositionTo(target.roles.highest) <= 0) return t("Cette personne est au-dessus de toi.", "This person is above you.");
    return null;
  };
  function parseDuration(text) {
    const m = String(text || "").trim().toLowerCase().match(/^(\d+)\s*(s|sec|m|min|h|j|d)?$/);
    if (!m) return 0;
    const n = Number(m[1]);
    const unit = m[2] || "m";
    const mult = { s: 1000, sec: 1000, m: 60_000, min: 60_000, h: 3_600_000, j: 86_400_000, d: 86_400_000 }[unit];
    return n * mult;
  }
  const fmtDuration = (ms) => {
    const s = Math.round(ms / 1000);
    if (s < 60) return `${s}s`;
    if (s < 3600) return `${Math.round(s / 60)} min`;
    if (s < 86400) return `${Math.round(s / 3600)} h`;
    return `${Math.round(s / 86400)} ${t("j", "d")}`;
  };

  /* ---------- slash commands ---------- */
  const cmd = (name, description) => new SlashCommandBuilder().setName(name).setDescription(description.slice(0, 100));
  const userOpt = (b, required = true, name = "membre", description = "Le membre") => b.addUserOption((o) => o.setName(name).setDescription(description).setRequired(required));
  const strOpt = (b, name, description, required = false, max = 500) => b.addStringOption((o) => o.setName(name).setDescription(description).setRequired(required).setMaxLength(max));

  function commands() {
    if (!ON) return [];
    const D = (flag, b) => b.setDefaultMemberPermissions(flag);
    const list = [
      // levels
      userOpt(cmd("rank", t("Affiche ton niveau et ton XP", "Show your level and XP")), false),
      cmd("leaderboard", t("Classement des niveaux du serveur", "Server level leaderboard")),
      D(
        P.ManageGuild,
        cmd("levels", t("Réglages des niveaux", "Level settings"))
          .addSubcommand((s) => s.setName("toggle").setDescription(t("Activer ou couper les niveaux", "Turn levels on or off")))
          .addSubcommand((s) => s.setName("announce").setDescription(t("Activer ou couper l'annonce de niveau", "Turn level-up messages on or off")))
          .addSubcommand((s) =>
            s
              .setName("reward-add")
              .setDescription(t("Donner un rôle à un niveau", "Give a role at a level"))
              .addIntegerOption((o) => o.setName("niveau").setDescription("Niveau").setMinValue(1).setMaxValue(200).setRequired(true))
              .addRoleOption((o) => o.setName("role").setDescription("Rôle").setRequired(true))
          )
          .addSubcommand((s) => s.setName("reward-remove").setDescription(t("Retirer la récompense d'un niveau", "Remove the reward of a level")).addIntegerOption((o) => o.setName("niveau").setDescription("Niveau").setRequired(true)))
          .addSubcommand((s) => s.setName("rewards").setDescription(t("Voir les récompenses", "List the rewards")))
          .addSubcommand((s) => s.setName("roles-create").setDescription(t("Créer les rôles de niveau (Nouveau, Sigma, Roi...)", "Create the level roles (Newbie, Sigma, King...)")))
          .addSubcommand((s) => s.setName("roles-delete").setDescription(t("Supprimer les rôles de niveau créés par le bot", "Delete the level roles the bot created")))
          .addSubcommand((s) => s.setName("stack").setDescription(t("Garder tous les rôles de niveau, ou seulement le plus haut", "Keep every level role, or only the highest")))
          .addSubcommand((s) => s.setName("ignore").setDescription(t("Ne pas gagner d'XP dans ce salon (ou l'inverse)", "No XP in this channel (toggle)")))
          .addSubcommand((s) =>
            s
              .setName("channel")
              .setDescription(t("Salon où les passages de niveau s'affichent", "Channel where level-ups are shown"))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = là où la personne écrit)", "The channel (empty = where the person writes)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
          )
          .addSubcommand((s) =>
            s
              .setName("xpchannel")
              .setDescription(t("Salon où un message est posté à chaque palier d'XP (100 par défaut)", "Channel where a message is posted at every XP step (100 by default)"))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = couper)", "The channel (empty = off)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
          )
          .addSubcommand((s) => s.setName("xpstep").setDescription(t("Tous les combien d'XP un message est posté (100 par défaut)", "How many XP between two messages (100 by default)")).addIntegerOption((o) => o.setName("montant").setDescription("10-10000").setMinValue(10).setMaxValue(10000).setRequired(true)))
          .addSubcommand((s) =>
            s
              .setName("voice")
              .setDescription(t("XP gagnés en vocal (reste actif avec d'autres membres)", "XP earned in voice (stay active with other members)"))
              .addBooleanOption((o) => o.setName("actif").setDescription(t("Activer ou couper l'XP en vocal", "Turn voice XP on or off")))
              .addIntegerOption((o) => o.setName("xp").setDescription(t("XP par minute (0-100)", "XP per minute (0-100)")).setMinValue(0).setMaxValue(100))
              .addIntegerOption((o) => o.setName("personnes").setDescription(t("Minimum de personnes dans le vocal (bots exclus)", "Minimum people in the voice channel (bots excluded)")).setMinValue(1).setMaxValue(10))
          )
          .addSubcommand((s) => s.setName("quiz-xp").setDescription(t("XP gagnés avec une bonne réponse au quiz", "XP won with a right quiz answer")).addIntegerOption((o) => o.setName("montant").setDescription("1-500").setMinValue(1).setMaxValue(500).setRequired(true)))
      ),
      D(
        P.ManageGuild,
        cmd("xp", t("Modifier l'XP d'un membre", "Change a member's XP"))
          .addSubcommand((s) => userOpt(s.setName("add").setDescription(t("Ajouter de l'XP", "Add XP")), true).addIntegerOption((o) => o.setName("montant").setDescription("XP").setMinValue(1).setRequired(true)))
          .addSubcommand((s) => userOpt(s.setName("remove").setDescription(t("Retirer de l'XP", "Remove XP")), true).addIntegerOption((o) => o.setName("montant").setDescription("XP").setMinValue(1).setRequired(true)))
          .addSubcommand((s) => userOpt(s.setName("reset").setDescription(t("Remettre à zéro", "Reset to zero")), true))
      ),
      // moderation
      D(P.BanMembers, strOpt(userOpt(cmd("ban", t("Bannir un membre", "Ban a member"))), "raison", t("Raison", "Reason"))),
      D(P.BanMembers, strOpt(cmd("unban", t("Débannir (ID de l'utilisateur)", "Unban (user ID)")), "id", "ID", true, 30)),
      D(P.KickMembers, strOpt(userOpt(cmd("kick", t("Expulser un membre", "Kick a member"))), "raison", t("Raison", "Reason"))),
      D(
        P.ModerateMembers,
        strOpt(userOpt(cmd("timeout", t("Mettre un membre en sourdine", "Time a member out"))).addStringOption((o) => o.setName("duree").setDescription("10m, 2h, 1j").setRequired(true)), "raison", t("Raison", "Reason"))
      ),
      D(P.ModerateMembers, userOpt(cmd("untimeout", t("Retirer la sourdine", "Remove the timeout")))),
      D(P.ModerateMembers, strOpt(userOpt(cmd("warn", t("Avertir un membre", "Warn a member"))), "raison", t("Raison", "Reason"), true)),
      D(P.ModerateMembers, userOpt(cmd("warnings", t("Voir les avertissements d'un membre", "See a member's warnings")))),
      D(P.ModerateMembers, userOpt(cmd("clearwarns", t("Effacer les avertissements d'un membre", "Clear a member's warnings")))),
      D(
        P.ManageChannels,
        cmd("lock", t("Verrouiller un salon : plus personne ne peut écrire", "Lock a channel: nobody can write"))
          .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = celui-ci)", "The channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
          .addStringOption((o) => o.setName("duree").setDescription(t("Se rouvre tout seul après : 10m, 2h, 1j", "Opens again after: 10m, 2h, 1d")).setMaxLength(10))
          .addStringOption((o) => o.setName("raison").setDescription(t("Raison", "Reason")).setMaxLength(200))
      ),
      D(P.ManageChannels, cmd("unlock", t("Déverrouiller un salon", "Unlock a channel")).addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = celui-ci)", "The channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))),
      D(P.ManageMessages, userOpt(cmd("clear", t("Supprimer des messages", "Delete messages")).addIntegerOption((o) => o.setName("nombre").setDescription("1-100").setMinValue(1).setMaxValue(100).setRequired(true)), false, "membre", t("Seulement ce membre", "Only this member"))),
      // welcome and roles
      D(
        P.ManageGuild,
        cmd("welcome", t("Messages de bienvenue et rôle automatique", "Welcome messages and auto role"))
          .addSubcommand((s) => s.setName("channel").setDescription(t("Salon de bienvenue (celui-ci)", "Welcome channel (this one)")))
          .addSubcommand((s) => s.setName("message").setDescription(t("Texte de bienvenue : {user} {server} {count}", "Welcome text: {user} {server} {count}")).addStringOption((o) => o.setName("texte").setDescription("{user} {server} {count}").setRequired(true).setMaxLength(1000)))
          .addSubcommand((s) =>
            s
              .setName("leave")
              .setDescription(t("Au revoir : salon séparé de bienvenue + texte {user} {server}", "Goodbye: channel separate from welcome + text {user} {server}"))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Salon des au revoir (vide = celui-ci)", "Goodbye channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
              .addStringOption((o) => o.setName("texte").setDescription("{user} {server}").setMaxLength(1000))
          )
          .addSubcommand((s) => s.setName("autorole").setDescription(t("Rôle donné aux nouveaux", "Role given to new members")).addRoleOption((o) => o.setName("role").setDescription("Rôle (vide = aucun)")))
          .addSubcommand((s) => s.setName("off").setDescription(t("Tout couper", "Turn everything off")))
          .addSubcommand((s) => s.setName("test").setDescription(t("Tester le message", "Test the message")))
      ),
      D(
        P.ManageRoles,
        (() => {
          let b = cmd("rolepanel", t("Poster un panneau de rôles à boutons", "Post a button role panel")).addStringOption((o) => o.setName("titre").setDescription("Titre").setRequired(true).setMaxLength(100));
          b = b.addRoleOption((o) => o.setName("role1").setDescription("Rôle 1").setRequired(true));
          for (let n = 2; n <= 5; n++) b = b.addRoleOption((o) => o.setName(`role${n}`).setDescription(`Rôle ${n}`));
          return b;
        })()
      ),
      // fun and utilities
      (() => {
        let b = cmd("poll", t("Créer un sondage", "Create a poll")).addStringOption((o) => o.setName("question").setDescription("Question").setRequired(true).setMaxLength(200));
        for (let n = 1; n <= 5; n++) b = b.addStringOption((o) => o.setName(`choix${n}`).setDescription(`Choix ${n}`).setRequired(n <= 2).setMaxLength(60));
        return b;
      })(),
      D(
        P.ManageGuild,
        cmd("giveaway", t("Concours", "Giveaways"))
          .addSubcommand((s) =>
            s
              .setName("start")
              .setDescription(t("Lancer un concours", "Start a giveaway"))
              .addStringOption((o) => o.setName("lot").setDescription(t("Le lot", "The prize")).setRequired(true).setMaxLength(100))
              .addStringOption((o) => o.setName("duree").setDescription("10m, 2h, 1j").setRequired(true))
              .addIntegerOption((o) => o.setName("gagnants").setDescription("1-10").setMinValue(1).setMaxValue(10))
          )
          .addSubcommand((s) => s.setName("end").setDescription(t("Terminer maintenant", "End now")).addStringOption((o) => o.setName("message_id").setDescription(t("ID du message du concours", "Giveaway message ID")).setRequired(true)))
          .addSubcommand((s) => s.setName("reroll").setDescription(t("Retirer au sort", "Draw again")).addStringOption((o) => o.setName("message_id").setDescription(t("ID du message du concours", "Giveaway message ID")).setRequired(true)))
      ),
      D(
        P.ManageGuild,
        cmd("vouchadmin", t("Gérer les vouches : salon, retirer, reset (staff)", "Manage vouches: channel, remove, reset (staff)"))
          .addSubcommand((s) => s.setName("salon").setDescription(t("Salon où les vouches sont postés (admin)", "Channel where vouches are posted (admin)")).addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = celui-ci)", "The channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement)))
          .addSubcommand((s) =>
            s
              .setName("panel")
              .setDescription(t("Poster le classement des vouches (mis à jour en direct)", "Post the vouch ranking (live updates)"))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = celui-ci)", "The channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
          )
          .addSubcommand((s) => s.setName("retirer").setDescription(t("Retirer un vouch (staff)", "Remove a vouch (staff)")).addIntegerOption((o) => o.setName("numero").setDescription(t("Le numéro du vouch (#)", "The vouch number (#)")).setRequired(true).setMinValue(1)))
          .addSubcommand((s) => s.setName("reset").setDescription(t("Effacer tous les vouches d'un membre (staff)", "Clear all of a member's vouches (staff)")).addUserOption((o) => o.setName("membre").setDescription(t("Le membre", "The member")).setRequired(true)))
      ),
      strOpt(cmd("suggest", t("Proposer une idée", "Suggest an idea")), "idee", t("Ton idée", "Your idea"), true, 900),
      cmd("vouch", t("Laisser un vouch (avis) à quelqu'un après un trade", "Leave a vouch (review) for someone after a trade"))
        .addUserOption((o) => o.setName("membre").setDescription(t("La personne que tu vouch", "The person you vouch for")).setRequired(true))
        .addIntegerOption((o) => o.setName("note").setDescription(t("Ta note de 1 à 5 étoiles", "Your rating, 1 to 5 stars")).setRequired(true).addChoices(...[5, 4, 3, 2, 1].map((n) => ({ name: `${"⭐".repeat(n)} (${n}/5)`, value: n }))))
        .addStringOption((o) => o.setName("objet").setDescription(t("Ce qui a été trade, ou le service (ex : Garama, Middleman, Shop…)", "What was traded, or the service (e.g. Garama, Middleman, Shop…)")).setRequired(true).setMinLength(2).setMaxLength(100))
        .addStringOption((o) => o.setName("commentaire").setDescription(t("Ce qui s'est passé (ex : rapide et fiable)", "What happened (e.g. fast and reliable)")).setRequired(true).setMinLength(3).setMaxLength(500)),

      D(P.ManageGuild, cmd("suggestions", t("Salon des suggestions (celui-ci)", "Suggestions channel (this one)"))),
      strOpt(cmd("8ball", t("Boule magique, ou sans question : un quiz à image qui rapporte de l'XP", "Magic 8-ball, or with no question: a picture quiz that wins XP")), "question", t("Ta question (vide = lancer un quiz)", "Your question (empty = start a quiz)"), false, 200),
      D(
        P.ManageGuild,
        cmd("autoquiz", t("Un quiz automatique toutes les X minutes", "An automatic quiz every X minutes"))
          .addSubcommand((s) =>
            s
              .setName("start")
              .setDescription(t("Lancer le quiz automatique (30 min par défaut)", "Start the automatic quiz (30 min by default)"))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon (vide = celui-ci)", "The channel (empty = this one)")).addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement))
              .addIntegerOption((o) => o.setName("minutes").setDescription(t("Toutes les X minutes (5-1440)", "Every X minutes (5-1440)")).setMinValue(5).setMaxValue(1440))
          )
          .addSubcommand((s) => s.setName("stop").setDescription(t("Arrêter le quiz automatique", "Stop the automatic quiz")))
          .addSubcommand((s) => s.setName("status").setDescription(t("Voir l'état", "See the status")))
      ),
      cmd("quiz", t("Quiz à image : la première bonne réponse gagne de l'XP", "Picture quiz: the first right answer wins XP")).addStringOption((o) =>
        o.setName("type").setDescription(t("Type de question", "Question type")).addChoices({ name: t("Drapeau", "Flag"), value: "flag" }, { name: t("Calcul", "Math"), value: "math" }, { name: t("Mot mélangé", "Scrambled word"), value: "word" })
      ),
      cmd("coinflip", t("Pile ou face", "Flip a coin")),
      cmd("dice", t("Lance un dé (1-100 faces)", "Roll a die")).addIntegerOption((o) => o.setName("faces").setDescription("6").setMinValue(2).setMaxValue(100)),
      userOpt(cmd("avatar", t("Affiche l'avatar", "Show the avatar")), false),
      userOpt(cmd("userinfo", t("Infos sur un membre", "Member info")), false),
      cmd("serverinfo", t("Infos sur le serveur", "Server info")),
      cmd("ping", t("Latence du bot", "Bot latency")),
      cmd("help", t("Liste des commandes", "Command list")),
      // application tickets
      D(
        P.ManageGuild,
        cmd("ticketpanel", t("Poster un panneau de tickets (candidature middleman, ou accès aux salons OG)", "Post a ticket panel (middleman application, or OG channel access)")).addStringOption((o) =>
          o.setName("type").setDescription(t("Quel panneau", "Which panel")).setRequired(true).addChoices({ name: t("Devenir middleman", "Become a middleman"), value: "middleman" }, { name: t("Accès aux salons OG (Trade OG / Shop OG)", "OG channel access (Trade OG / Shop OG)"), value: "access" }, { name: t("Réclamer le brainrot Garama (5000 XP)", "Claim the Garama brainrot (5000 XP)"), value: "claim" }, { name: t("Cross-trade : échange objet contre objet", "Cross-trade: item for item"), value: "crosstrade" })
        )
      ),
      D(
        P.ManageGuild,
        cmd("apps", t("Réglages des tickets de candidature et d'accès", "Settings of the application and access tickets"))
          .addSubcommand((s) => s.setName("staff").setDescription(t("Le rôle qui voit et traite ces tickets", "The role that sees and handles these tickets")).addRoleOption((o) => o.setName("role").setDescription(t("Le rôle (vide = aucun)", "The role (empty = none)"))))
          .addSubcommand((s) => s.setName("mmrole").setDescription(t("Le rôle donné quand une candidature middleman est acceptée", "The role given when a middleman application is accepted")).addRoleOption((o) => o.setName("role").setDescription(t("Le rôle (vide = aucun)", "The role (empty = none)"))))
          .addSubcommand((s) => s.setName("category").setDescription(t("La catégorie où ces tickets sont créés", "The category where these tickets are created")).addChannelOption((o) => o.setName("categorie").setDescription(t("La catégorie (vide = aucune)", "The category (empty = none)")).addChannelTypes(ChannelType.GuildCategory)))
          .addSubcommand((s) =>
            s
              .setName("access")
              .setDescription(t("Changer le rôle donné (et le salon affiché) pour une demande d'accès", "Change the role given (and the channel shown) for an access request"))
              .addStringOption((o) => o.setName("type").setDescription(t("Quelle demande", "Which request")).setRequired(true).addChoices({ name: "Trade OG", value: "trade" }, { name: "Shop OG", value: "shop" }))
              .addRoleOption((o) => o.setName("role").setDescription(t("Le rôle donné quand c'est accepté", "The role given when accepted")))
              .addChannelOption((o) => o.setName("salon").setDescription(t("Le salon que ce rôle ouvre (affiché dans le ticket)", "The channel this role opens (shown in the ticket)")))
          )
          .addSubcommand((s) =>
            s
              .setName("revoke")
              .setDescription(t("Retirer l'accès d'un membre à un salon OG", "Take a member's access to an OG channel away"))
              .addUserOption((o) => o.setName("membre").setDescription(t("Le membre", "The member")).setRequired(true))
              .addStringOption((o) => o.setName("type").setDescription(t("Quel salon", "Which channel")).setRequired(true).addChoices({ name: "Trade OG", value: "trade" }, { name: "Shop OG", value: "shop" }))
          )
          .addSubcommand((s) =>
            s
              .setName("claim")
              .setDescription(t("Réglages de la réclamation (XP nécessaires et récompense)", "Claim settings (XP needed and reward)"))
              .addIntegerOption((o) => o.setName("xp").setDescription(t("XP nécessaires", "XP needed")).setMinValue(1).setMaxValue(10000000))
              .addStringOption((o) => o.setName("recompense").setDescription(t("Nom de la récompense", "Name of the reward")).setMaxLength(40))
          )
          .addSubcommand((s) => s.setName("claimreset").setDescription(t("Permettre à un membre de réclamer à nouveau", "Let a member claim again")).addUserOption((o) => o.setName("membre").setDescription(t("Le membre", "The member")).setRequired(true)))
          .addSubcommand((s) => s.setName("status").setDescription(t("Voir les réglages", "See the settings")))
      ),
      // voice channels
      D(
        P.ManageChannels,
        cmd("vocadmin", t("Créer des salons vocaux (staff)", "Create voice channels (staff)"))
        .addSubcommand((s) =>
            s
              .setName("create")
              .setDescription(t("Créer un salon vocal", "Create a voice channel"))
              .addStringOption((o) => o.setName("nom").setDescription(t("Nom du vocal", "Voice channel name")).setRequired(true).setMaxLength(80))
              .addIntegerOption((o) => o.setName("limite").setDescription(t("Nombre de places (0 = illimité)", "Number of seats (0 = unlimited)")).setMinValue(0).setMaxValue(99))
              .addBooleanOption((o) => o.setName("prive").setDescription(t("Privé : personne ne peut le rejoindre sans invitation", "Private: nobody can join without an invite")))
              .addIntegerOption((o) => o.setName("nombre").setDescription(t("Combien en créer d'un coup (numérotés, 1-25)", "How many to create at once (numbered, 1-25)")).setMinValue(1).setMaxValue(25))
          )
          .addSubcommand((s) => s.setName("hub").setDescription(t("Créer le salon « ➕ Créer ton vocal » (chacun obtient son vocal)", "Create the \"➕ Create your voice\" channel (everyone gets their own)")))
      ),
      // channels made by the bot
      D(
        P.Administrator,
        cmd("setup", t("Créer ou supprimer les salons automatiquement", "Create or delete the channels automatically"))
          .addSubcommand((s) =>
            s
              .setName("create")
              .setDescription(t("Créer les salons (catégories, règles, général, logs...)", "Create the channels (categories, rules, general, logs...)"))
              .addStringOption((o) => o.setName("modele").setDescription(t("Modèle", "Template")).addChoices({ name: "Steal a Brainrot (trades, shops, middleman)", value: "brainrot" }, { name: t("Complet", "Full"), value: "full" }, { name: t("Minimal", "Minimal"), value: "minimal" }))
          )
          .addSubcommand((s) => s.setName("delete").setDescription(t("Supprimer les salons créés par le bot", "Delete the channels the bot created")))
          .addSubcommand((s) =>
            s
              .setName("voc-create")
              .setDescription(t("Créer plein de salons vocaux d'un coup (catégories, trade, gaming, chill...)", "Create lots of voice channels at once (categories, trade, gaming, chill...)"))
              .addStringOption((o) => o.setName("modele").setDescription(t("Modèle", "Template")).addChoices({ name: t("Serveur complet : trade, gaming, support, détente, staff (34 vocaux)", "Full server: trade, gaming, support, chill, staff (34 voice channels)"), value: "brainrot" }, { name: t("Complet (17 vocaux)", "Full (17 voice channels)"), value: "full" }, { name: t("Minimal (4 vocaux)", "Minimal (4 voice channels)"), value: "minimal" }))
          )
          .addSubcommand((s) => s.setName("voc-delete").setDescription(t("Supprimer les vocaux créés par le bot", "Delete the voice channels the bot created")))
          .addSubcommand((s) => s.setName("status").setDescription(t("Voir les salons créés par le bot", "See the channels the bot created")))
      ),
      // logs and security
      D(
        P.ManageGuild,
        cmd("logs", t("Salon des logs (messages, arrivées, bans)", "Logs channel (messages, joins, bans)"))
          .addSubcommand((s) => s.setName("here").setDescription(t("Utiliser ce salon", "Use this channel")))
          .addSubcommand((s) => s.setName("off").setDescription(t("Couper les logs", "Turn logs off")))
      ),
      D(
        P.ManageGuild,
        cmd("security", t("Anti-spam, anti-liens, anti-raid", "Anti-spam, anti-links, anti-raid"))
          .addSubcommand((s) => s.setName("status").setDescription(t("Voir les réglages", "See the settings")))
          .addSubcommand((s) => s.setName("antispam").setDescription(t("Anti-spam (5 messages en 5 s = sourdine 5 min)", "Anti-spam (5 messages in 5 s = 5 min timeout)")).addBooleanOption((o) => o.setName("actif").setDescription("on/off").setRequired(true)))
          .addSubcommand((s) =>
            s
              .setName("antilink")
              .setDescription(t("Anti-liens", "Anti-links"))
              .addStringOption((o) => o.setName("mode").setDescription("off / invites / all").setRequired(true).addChoices({ name: t("Désactivé", "Off"), value: "off" }, { name: t("Invitations Discord", "Discord invites"), value: "invites" }, { name: t("Tous les liens", "All links"), value: "all" }))
          )
          .addSubcommand((s) => s.setName("antiraid").setDescription(t("Anti-raid (5 arrivées en 10 s)", "Anti-raid (5 joins in 10 s)")).addBooleanOption((o) => o.setName("actif").setDescription("on/off").setRequired(true)))
      ),
    ];
    return list.map((b) => b.toJSON());
  }
  const NAMES = new Set(["rank", "leaderboard", "levels", "xp", "ban", "unban", "kick", "timeout", "untimeout", "warn", "warnings", "clearwarns", "clear", "welcome", "rolepanel", "poll", "giveaway", "suggest", "suggestions", "8ball", "coinflip", "dice", "avatar", "userinfo", "serverinfo", "ping", "help", "logs", "security", "setup", "quiz", "autoquiz", "lock", "unlock", "ticketpanel", "apps", "vouch", "vouchadmin", "vocadmin"]);

  /* ---------- command handlers ---------- */
  const H = {};

  H.rank = async (i) => {
    const user = i.options.getUser("membre") || i.user;
    const xp = db.xp[user.id] || 0;
    const l = levelOf(xp);
    await i.deferReply();
    const member = await i.guild.members.fetch(user.id).catch(() => null);
    const name = member?.displayName || user.username;
    const card = picture("rank.png", gfx.rank({ name, level: l.level, into: l.into, need: l.need, rank: rankOf(user.id), xp, label: cardLabel(), avatar: await loadAvatar(member || user) }));
    const e = embed().setAuthor({ name: user.username, iconURL: user.displayAvatarURL?.() }).setTitle(t(`Niveau ${l.level}`, `Level ${l.level}`)).setImage(card.url);
    return i.editReply({ embeds: [e], files: [card.file] });
  };

  H.leaderboard = async (i) => {
    const top = Object.entries(db.xp).sort((a, b) => b[1] - a[1]).slice(0, 10);
    if (!top.length) return reply(i, t("Personne n'a encore d'XP.", "Nobody has XP yet."));
    await i.deferReply();
    const rows = await Promise.all(
      top.map(async ([id, xp]) => {
        const m = await i.guild.members.fetch(id).catch(() => null);
        const l = levelOf(xp);
        return { name: m?.displayName || m?.user?.username || t("Ancien membre", "Former member"), level: l.level, into: l.into, need: l.need, xp, avatar: m ? await loadAvatar(m, 64) : null };
      })
    );
    const card = picture("leaderboard.png", gfx.leaderboard(rows, cardLabel()));
    return i.editReply({ embeds: [embed(0xf1c40f).setTitle(t("🏆 Classement", "🏆 Leaderboard")).setImage(card.url)], files: [card.file] });
  };

  H.levels = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const cfg = db.cfg.levels;
    const sub = i.options.getSubcommand();
    if (sub === "toggle") {
      cfg.on = !cfg.on;
      save();
      return reply(i, ok(cfg.on ? t("Niveaux activés.", "Levels on.") : t("Niveaux coupés.", "Levels off.")));
    }
    if (sub === "announce") {
      cfg.announce = !cfg.announce;
      save();
      return reply(i, ok(cfg.announce ? t("Annonce de niveau activée.", "Level-up messages on.") : t("Annonce de niveau coupée.", "Level-up messages off.")));
    }
    if (sub === "reward-add") {
      const level = i.options.getInteger("niveau");
      const role = i.options.getRole("role");
      cfg.rewards = cfg.rewards.filter((r) => r.level !== level);
      cfg.rewards.push({ level, roleId: role.id });
      cfg.rewards.sort((a, b) => a.level - b.level);
      save();
      return reply(i, ok(t(`Le rôle ${role} sera donné au niveau ${level}.`, `${role} will be given at level ${level}.`)));
    }
    if (sub === "reward-remove") {
      const level = i.options.getInteger("niveau");
      const before = cfg.rewards.length;
      cfg.rewards = cfg.rewards.filter((r) => r.level !== level);
      save();
      return reply(i, before === cfg.rewards.length ? no(t("Aucune récompense à ce niveau.", "No reward at that level.")) : ok(t("Récompense retirée.", "Reward removed.")));
    }
    if (sub === "rewards") {
      const text = cfg.rewards.length ? cfg.rewards.map((r) => `${t("Niveau", "Level")} **${r.level}** → <@&${r.roleId}>`).join("\n") : t("Aucune récompense. Ajoute-en avec `/levels reward-add`.", "No rewards. Add one with `/levels reward-add`.");
      return i.reply({ embeds: [embed().setTitle(t("🎁 Récompenses de niveau", "🎁 Level rewards")).setDescription(text)], flags: ephemeral, allowedMentions: { parse: [] } });
    }
    if (sub === "channel") {
      const channel = i.options.getChannel("salon");
      cfg.channelId = channel?.id || "";
      save();
      return reply(i, ok(channel ? t(`Les passages de niveau s'afficheront dans ${channel}.`, `Level-ups will be shown in ${channel}.`) : t("Les passages de niveau s'afficheront là où la personne écrit.", "Level-ups will be shown where the person writes.")));
    }
    if (sub === "xpchannel") {
      const channel = i.options.getChannel("salon");
      cfg.xpChannelId = channel?.id || "";
      save();
      return reply(i, ok(channel ? t(`Un message sera posté dans ${channel} à chaque palier de ${cfg.xpStep} XP.`, `A message will be posted in ${channel} at every ${cfg.xpStep} XP.`) : t("Messages de palier d'XP coupés.", "XP step messages turned off.")));
    }
    if (sub === "xpstep") {
      cfg.xpStep = i.options.getInteger("montant");
      save();
      return reply(i, ok(t(`Un message sera posté tous les ${cfg.xpStep} XP${cfg.xpChannelId ? "" : " (choisis aussi un salon avec `/levels xpchannel`)"}.`, `A message will be posted every ${cfg.xpStep} XP${cfg.xpChannelId ? "" : " (also pick a channel with `/levels xpchannel`)"}.`)));
    }
    if (sub === "voice") {
      const on = i.options.getBoolean("actif");
      const rate = i.options.getInteger("xp");
      const people = i.options.getInteger("personnes");
      if (on !== null && on !== undefined) cfg.voiceOn = on;
      if (rate !== null && rate !== undefined) cfg.voiceXp = rate;
      if (people !== null && people !== undefined) cfg.voiceMinPeople = people;
      save();
      return reply(i, cfg.voiceOn && cfg.voiceXp > 0
        ? ok(t(`XP en vocal : **${cfg.voiceXp} XP par minute**, avec au moins **${cfg.voiceMinPeople} personne${cfg.voiceMinPeople > 1 ? "s" : ""}** dans le vocal (sourdine « casque » = rien, salon AFK = rien).`, `Voice XP: **${cfg.voiceXp} XP per minute**, with at least **${cfg.voiceMinPeople} ${cfg.voiceMinPeople > 1 ? "people" : "person"}** in the voice channel (deafened = nothing, AFK channel = nothing).`))
        : ok(t("XP en vocal coupé.", "Voice XP turned off.")));
    }
    if (sub === "quiz-xp") {
      cfg.quizXp = i.options.getInteger("montant");
      save();
      return reply(i, ok(t(`Une bonne réponse au quiz rapporte ${cfg.quizXp} XP.`, `A right quiz answer wins ${cfg.quizXp} XP.`)));
    }
    if (sub === "roles-create") {
      if (need_perm(i, P.ManageRoles)) return;
      if (db.setup.levelRoles.length) {
        await i.deferReply({ flags: ephemeral });
        const n = await refreshLevelRoles(i.guild);
        return i.editReply(ok(t(`${n} rôle(s) de niveau mis à jour (noms et couleurs).`, `${n} level role(s) updated (names and colours).`)));
      }
      await i.deferReply({ flags: ephemeral });
      try {
        const n = await createLevelRoles(i.guild);
        return i.editReply(ok(t(`${n} rôles créés et branchés : ${db.cfg.levels.rewards.filter((r) => db.setup.levelRoles.includes(r.roleId)).map((r) => `niveau ${r.level} → <@&${r.roleId}>`).join(", ")}.\nIls sont donnés automatiquement, et le plus haut remplace le précédent.`, `${n} roles created and connected: ${db.cfg.levels.rewards.filter((r) => db.setup.levelRoles.includes(r.roleId)).map((r) => `level ${r.level} → <@&${r.roleId}>`).join(", ")}.\nThey are given automatically, and the highest replaces the previous one.`)));
      } catch (error) {
        save(true);
        console.error("⚠️ Level roles error:", error?.message || error);
        return i.editReply(no(t("Je n'ai pas pu tout créer (il me faut la permission « Gérer les rôles »). `/levels roles-delete` supprime ce qui a été créé.", "I could not create everything (I need the Manage Roles permission). `/levels roles-delete` removes what was created.")));
      }
    }
    if (sub === "roles-delete") {
      if (need_perm(i, P.ManageRoles)) return;
      if (!db.setup.levelRoles.length) return reply(i, no(t("Le bot n'a créé aucun rôle de niveau.", "The bot created no level roles.")));
      await i.deferReply({ flags: ephemeral });
      const n = await removeLevelRoles(i.guild);
      return i.editReply(ok(t(`${n} rôle(s) de niveau supprimé(s).`, `${n} level role(s) deleted.`)));
    }
    if (sub === "stack") {
      cfg.stack = !cfg.stack;
      save();
      return reply(i, ok(cfg.stack ? t("Tous les rôles de niveau sont gardés.", "Every level role is kept.") : t("Seul le rôle de niveau le plus haut est gardé.", "Only the highest level role is kept.")));
    }
    if (sub === "ignore") {
      const has = cfg.ignored.includes(i.channelId);
      cfg.ignored = has ? cfg.ignored.filter((c) => c !== i.channelId) : [...cfg.ignored, i.channelId];
      save();
      return reply(i, ok(has ? t("Ce salon donne de l'XP.", "This channel gives XP.") : t("Ce salon ne donne plus d'XP.", "This channel no longer gives XP.")));
    }
  };

  H.xp = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const sub = i.options.getSubcommand();
    const user = i.options.getUser("membre");
    if (sub === "reset") delete db.xp[user.id];
    else {
      const amount = i.options.getInteger("montant");
      db.xp[user.id] = Math.max(0, (db.xp[user.id] || 0) + (sub === "add" ? amount : -amount));
    }
    save();
    const member = await i.guild.members.fetch(user.id).catch(() => null);
    if (member) await giveRewards(member, levelOf(db.xp[user.id] || 0).level);
    return reply(i, ok(`${user.username}: ${db.xp[user.id] || 0} XP (${t("niveau", "level")} ${levelOf(db.xp[user.id] || 0).level})`));
  };

  /* moderation */
  const reasonOf = (i) => i.options.getString("raison") || t("Aucune raison", "No reason");
  const targetMember = async (i) => i.options.getMember?.("membre") || (await i.guild.members.fetch(i.options.getUser("membre").id).catch(() => null));

  H.ban = async (i) => {
    if (need_perm(i, P.BanMembers)) return;
    const user = i.options.getUser("membre");
    const member = await targetMember(i);
    const problem = canAct(i, member);
    if (problem) return reply(i, no(problem));
    const reason = reasonOf(i);
    try {
      await i.guild.members.ban(user.id, { reason: `${i.user.username}: ${reason}` });
    } catch {
      return reply(i, no(t("Je n'ai pas pu bannir cette personne.", "I could not ban this person.")));
    }
    await log(i.guild, `🔨 **Ban** ${user} (${user.id})\n${t("Par", "By")} ${i.user}  ·  ${reason}`, 0xed4245);
    return i.reply({ content: ok(t(`${user.username} est banni. (${reason})`, `${user.username} is banned. (${reason})`)) });
  };
  H.unban = async (i) => {
    if (need_perm(i, P.BanMembers)) return;
    const id = i.options.getString("id").trim();
    try {
      await i.guild.bans.remove(id, `${i.user.username}`);
    } catch {
      return reply(i, no(t("Cet utilisateur n'est pas banni.", "This user is not banned.")));
    }
    await log(i.guild, `♻️ **Unban** <@${id}>  ·  ${t("par", "by")} ${i.user}`, 0x2ecc71);
    return reply(i, ok(t("Débanni.", "Unbanned.")));
  };
  H.kick = async (i) => {
    if (need_perm(i, P.KickMembers)) return;
    const member = await targetMember(i);
    if (!member) return reply(i, no(t("Membre introuvable.", "Member not found.")));
    const problem = canAct(i, member);
    if (problem) return reply(i, no(problem));
    const reason = reasonOf(i);
    try {
      await member.kick(`${i.user.username}: ${reason}`);
    } catch {
      return reply(i, no(t("Je n'ai pas pu expulser cette personne.", "I could not kick this person.")));
    }
    await log(i.guild, `👢 **Kick** ${member.user}  ·  ${t("par", "by")} ${i.user}  ·  ${reason}`, 0xe67e22);
    return i.reply({ content: ok(t(`${member.user.username} est expulsé. (${reason})`, `${member.user.username} was kicked. (${reason})`)) });
  };
  H.timeout = async (i) => {
    if (need_perm(i, P.ModerateMembers)) return;
    const member = await targetMember(i);
    if (!member) return reply(i, no(t("Membre introuvable.", "Member not found.")));
    const problem = canAct(i, member);
    if (problem) return reply(i, no(problem));
    const ms = parseDuration(i.options.getString("duree"));
    if (!ms || ms > 28 * 86_400_000) return reply(i, no(t("Durée invalide (ex : 10m, 2h, 1j ; maximum 28 jours).", "Invalid duration (e.g. 10m, 2h, 1d; 28 days max).")));
    const reason = reasonOf(i);
    try {
      await member.timeout(ms, `${i.user.username}: ${reason}`);
    } catch {
      return reply(i, no(t("Je n'ai pas pu mettre cette personne en sourdine.", "I could not time this person out.")));
    }
    await log(i.guild, `🔇 **Timeout** ${member.user} ${fmtDuration(ms)}  ·  ${t("par", "by")} ${i.user}  ·  ${reason}`, 0xe67e22);
    return i.reply({ content: ok(t(`${member.user.username} est en sourdine pendant ${fmtDuration(ms)}.`, `${member.user.username} is timed out for ${fmtDuration(ms)}.`)) });
  };
  H.untimeout = async (i) => {
    if (need_perm(i, P.ModerateMembers)) return;
    const member = await targetMember(i);
    if (!member) return reply(i, no(t("Membre introuvable.", "Member not found.")));
    await member.timeout(null).catch(() => {});
    return reply(i, ok(t("Sourdine retirée.", "Timeout removed.")));
  };
  H.warn = async (i) => {
    if (need_perm(i, P.ModerateMembers)) return;
    const user = i.options.getUser("membre");
    if (user.bot) return reply(i, no(t("Impossible sur un bot.", "Not possible on a bot.")));
    const reason = i.options.getString("raison");
    (db.warns[user.id] = db.warns[user.id] || []).push({ by: i.user.id, reason, at: Date.now() });
    save();
    await log(i.guild, `⚠️ **Warn** ${user}  ·  ${t("par", "by")} ${i.user}  ·  ${reason}  (${db.warns[user.id].length})`, 0xf1c40f);
    user.send?.(t(`⚠️ Tu as reçu un avertissement sur **${i.guild.name}** : ${reason}`, `⚠️ You got a warning on **${i.guild.name}**: ${reason}`))?.catch?.(() => {});
    return i.reply({ content: ok(t(`${user.username} est averti (${db.warns[user.id].length} au total). ${reason}`, `${user.username} was warned (${db.warns[user.id].length} total). ${reason}`)) });
  };
  H.warnings = async (i) => {
    if (need_perm(i, P.ModerateMembers)) return;
    const user = i.options.getUser("membre");
    const list = db.warns[user.id] || [];
    if (!list.length) return reply(i, t(`${user.username} n'a aucun avertissement.`, `${user.username} has no warnings.`));
    const lines = list.slice(-15).map((w, n) => `**${n + 1}.** <t:${Math.floor(w.at / 1000)}:d>  ·  ${w.reason}  ·  <@${w.by}>`);
    return i.reply({ embeds: [embed(0xf1c40f).setTitle(`⚠️ ${user.username}  ·  ${list.length}`).setDescription(lines.join("\n"))], flags: ephemeral, allowedMentions: { parse: [] } });
  };
  H.clearwarns = async (i) => {
    if (need_perm(i, P.ModerateMembers)) return;
    const user = i.options.getUser("membre");
    delete db.warns[user.id];
    save();
    return reply(i, ok(t("Avertissements effacés.", "Warnings cleared.")));
  };
  /* ---------- voice channels: /voc, and "join to create" rooms ---------- */
  const VOICE = ChannelType.GuildVoice;
  const roomCooldown = new Map();
  async function createRoom(guild, member, hub) {
    const name = `🔊│${member.displayName || member.user?.username || "vocal"}`.slice(0, 100);
    const room = await guild.channels.create({
      name,
      type: VOICE,
      parent: hub.parentId || undefined,
      permissionOverwrites: [{ id: member.id, allow: [P.ViewChannel, P.Connect, P.Speak, P.ManageChannels, P.MoveMembers] }],
      reason: "voice room",
    });
    db.voc.rooms[room.id] = { owner: member.id, at: Date.now() };
    save();
    return room;
  }
  async function onVoice(oldState, newState) {
    const guild = newState.guild || oldState.guild;
    const member = newState.member || oldState.member;
    if (!guild || !member || member.user?.bot) return;
    if (newState.channelId && newState.channelId !== oldState.channelId && db.voc.hubs.includes(newState.channelId)) {
      const now = Date.now();
      if (now - (roomCooldown.get(member.id) || 0) < 8000) return; // no flood of rooms
      roomCooldown.set(member.id, now);
      const hub = newState.channel || (await guild.channels.fetch(newState.channelId).catch(() => null));
      if (!hub) return;
      let room = null;
      try {
        room = await createRoom(guild, member, hub);
        await member.voice.setChannel(room, "voice room");
        await Promise.resolve(room.send?.({ content: `<@${member.id}>`, ...roomPanel(room, member.id), allowedMentions: { users: [member.id] } })).catch(() => {});
      } catch (error) {
        console.error("⚠️ Voice room error:", error?.message || error);
        if (room) {
          delete db.voc.rooms[room.id];
          await room.delete("voice room failed").catch(() => {});
          save();
        }
      }
    }
    if (oldState.channelId && oldState.channelId !== newState.channelId && db.voc.rooms[oldState.channelId]) {
      const room = oldState.channel || (await guild.channels.fetch(oldState.channelId).catch(() => null));
      if (room && room.members?.size === 0) {
        delete db.voc.rooms[room.id];
        save();
        await room.delete("empty voice room").catch(() => {});
      }
    }
  }
  /* Forgets rooms and hubs that no longer exist and removes rooms that stayed empty. */
  async function tickVoc() {
    for (const [id, room] of Object.entries(db.voc.rooms)) {
      const channel = await Promise.resolve(client?.channels?.fetch?.(id)).catch(() => null);
      if (!channel) {
        delete db.voc.rooms[id];
        save();
      } else if (channel.members?.size === 0 && Date.now() - room.at > 30_000) {
        delete db.voc.rooms[id];
        save();
        await channel.delete("empty voice room").catch(() => {});
      }
    }
    for (const id of [...db.voc.hubs]) {
      const channel = await Promise.resolve(client?.channels?.fetch?.(id)).catch(() => null);
      if (!channel) {
        db.voc.hubs = db.voc.hubs.filter((h) => h !== id);
        save();
      }
    }
  }
  /* The voice room of the member, when it is one of the bot's rooms and they own it (or manage channels). */
  /* The control panel posted in the chat of a voice room: only its owner (or staff) can use it. */
  function roomPanel(room, ownerId) {
    const r = db.voc.rooms[room.id] || {};
    const state = [r.locked ? t("🔒 Fermé", "🔒 Closed") : t("🔓 Ouvert", "🔓 Open"), r.hidden ? t("🙈 Caché", "🙈 Hidden") : t("👁️ Visible", "👁️ Visible"), room.userLimit ? `👥 ${room.userLimit} ${t("places", "seats")}` : t("👥 Illimité", "👥 Unlimited")].join("  ·  ");
    const e = embed(0x5865f2)
      .setTitle(t("🎛️  Ton vocal", "🎛️  Your voice room"))
      .setDescription(t(`Propriétaire : <@${ownerId}>\nGère ton vocal avec les boutons ci-dessous.\n\n${state}`, `Owner: <@${ownerId}>\nManage your voice room with the buttons below.\n\n${state}`))
      .setFooter({ text: t("Le vocal est supprimé quand il est vide.", "The room is deleted when it is empty.") });
    const b = (id, label, emoji, style = ButtonStyle.Secondary) => new ButtonBuilder().setCustomId(`tl:vr:${id}`).setLabel(label).setEmoji(emoji).setStyle(style);
    return {
      embeds: [e],
      components: [
        new ActionRowBuilder().addComponents(
          b("rename", t("Renommer", "Rename"), "✏️"),
          b("limit", t("Places", "Seats"), "👥"),
          r.locked ? b("unlock", t("Ouvrir", "Open"), "🔓", ButtonStyle.Success) : b("lock", t("Fermer", "Close"), "🔒", ButtonStyle.Danger),
          r.hidden ? b("show", t("Afficher", "Show"), "👁️", ButtonStyle.Success) : b("hide", t("Cacher", "Hide"), "🙈"),
          b("claim", t("Récupérer", "Claim"), "👑", ButtonStyle.Primary)
        ),
      ],
      allowedMentions: { parse: [] },
    };
  }
  async function roomButton(i, action) {
    const room = db.voc.rooms[i.channelId];
    if (!room) return reply(i, no(t("Ce n'est pas un vocal créé avec « ➕ Créer ton vocal ».", "This is not a room made with \"➕ Create your voice\".")));
    const channel = i.channel;
    const staff = Boolean(i.member?.permissions?.has?.(P.ManageChannels));
    if (action === "claim") {
      if (room.owner === i.user.id) return reply(i, no(t("C'est déjà ton vocal.", "It is already your room.")));
      const ownerHere = channel?.members?.has?.(room.owner);
      if (ownerHere && !staff) return reply(i, no(t("Le propriétaire est encore dans le vocal.", "The owner is still in the room.")));
      if (i.member?.voice?.channelId !== channel.id && !staff) return reply(i, no(t("Rejoins le vocal pour le récupérer.", "Join the room to claim it.")));
      await channel.permissionOverwrites.edit(i.user.id, { ViewChannel: true, Connect: true, Speak: true, ManageChannels: true, MoveMembers: true }).catch(() => {});
      await channel.permissionOverwrites.delete?.(room.owner).catch(() => {});
      room.owner = i.user.id;
      save();
      return i.update(roomPanel(channel, room.owner));
    }
    if (room.owner !== i.user.id && !staff) return reply(i, no(t("Seul le propriétaire du vocal peut faire ça.", "Only the owner of the room can do that.")));
    if (action === "rename" || action === "limit") {
      const modal = new ModalBuilder().setCustomId(`tl:vrm:${action}`).setTitle(action === "rename" ? t("Renommer le vocal", "Rename the room") : t("Nombre de places", "Number of seats"));
      const input = action === "rename"
        ? new TextInputBuilder().setCustomId("v").setLabel(t("Nouveau nom", "New name")).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(80).setValue(String(channel.name || "").replace(/^🔊│/, "").slice(0, 80))
        : new TextInputBuilder().setCustomId("v").setLabel(t("Places (0 = illimité, max 99)", "Seats (0 = unlimited, max 99)")).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(2).setValue(String(channel.userLimit || 0));
      modal.addComponents(new ActionRowBuilder().addComponents(input));
      return i.showModal(modal);
    }
    const everyone = i.guild.roles.everyone.id;
    try {
      if (action === "lock" || action === "unlock") {
        await channel.permissionOverwrites.edit(everyone, { Connect: action === "lock" ? false : null });
        room.locked = action === "lock";
      }
      if (action === "hide" || action === "show") {
        await channel.permissionOverwrites.edit(everyone, { ViewChannel: action === "hide" ? false : null });
        room.hidden = action === "hide";
      }
    } catch {
      return reply(i, no(t("Je n'ai pas pu modifier ce vocal.", "I could not change this voice room.")));
    }
    save();
    return i.update(roomPanel(channel, room.owner));
  }
  async function roomModal(i, action) {
    const room = db.voc.rooms[i.channelId];
    if (!room) return reply(i, no(t("Ce vocal n'existe plus.", "This room no longer exists.")));
    if (room.owner !== i.user.id && !i.member?.permissions?.has?.(P.ManageChannels)) return reply(i, no(t("Seul le propriétaire du vocal peut faire ça.", "Only the owner of the room can do that.")));
    const value = String(i.fields.getTextInputValue("v") || "").trim();
    try {
      if (action === "rename") {
        if (!value) return reply(i, no(t("Écris un nom.", "Write a name.")));
        await i.channel.setName(`🔊│${value}`.slice(0, 100));
      } else {
        const n = Number(value);
        if (!Number.isInteger(n) || n < 0 || n > 99) return reply(i, no(t("Écris un nombre entre 0 et 99.", "Write a number from 0 to 99.")));
        await i.channel.setUserLimit(n);
      }
    } catch {
      return reply(i, no(t("Je n'ai pas pu modifier ce vocal (Discord limite les renommages à 2 toutes les 10 minutes).", "I could not change this room (Discord allows 2 renames every 10 minutes).")));
    }
    if (i.isFromMessage?.()) return i.update(roomPanel(i.channel, room.owner));
    return reply(i, ok(t("C'est fait.", "Done.")));
  }
  H.vocadmin = (i) => H.voc(i);
  H.voc = async (i) => {
    const sub = i.options.getSubcommand();
    if (sub === "create" || sub === "hub") {
      if (need_perm(i, P.ManageChannels)) return;
      const parent = i.channel?.parentId || undefined;
      try {
        if (sub === "hub") {
          const hub = await i.guild.channels.create({ name: t("➕│Créer ton vocal", "➕│Create your voice"), type: VOICE, parent, reason: "voice hub" });
          db.voc.hubs.push(hub.id);
          save(true);
          return reply(i, ok(t(`<#${hub.id}> est prêt : en le rejoignant, chacun obtient son propre vocal (supprimé quand il est vide).`, `<#${hub.id}> is ready: joining it gives everyone their own voice room (deleted when empty).`)));
        }
        const priv = i.options.getBoolean("prive");
        const count = i.options.getInteger("nombre") || 1;
        if (count > 1) await i.deferReply({ flags: ephemeral });
        const made = [];
        try {
          for (let n = 1; n <= count; n++) {
            const base = i.options.getString("nom");
            const channel = await i.guild.channels.create({
              name: `🔊│${count > 1 ? `${base} ${n}` : base}`.slice(0, 100),
              type: VOICE,
              parent,
              userLimit: i.options.getInteger("limite") || 0,
              permissionOverwrites: priv ? [{ id: i.guild.roles.everyone.id, deny: [P.Connect] }, { id: i.user.id, allow: [P.Connect, P.ViewChannel] }] : [],
              reason: `voc create: ${i.user.username}`,
            });
            made.push(channel);
          }
        } catch (error) {
          console.error("⚠️ Voc error:", error?.message || error);
          const text = made.length
            ? t(`Je n'en ai créé que ${made.length} sur ${count} : ${made.map((c) => `<#${c.id}>`).join(" ")} (il me faut « Gérer les salons »).`, `I only created ${made.length} of ${count}: ${made.map((c) => `<#${c.id}>`).join(" ")} (I need Manage Channels).`)
            : t("Je n'ai pas pu le créer (il me faut « Gérer les salons »).", "I could not create it (I need Manage Channels).");
          return count > 1 ? i.editReply(no(text)) : reply(i, no(text));
        }
        const list = made.map((c) => `<#${c.id}>`).join(" ");
        const doneText = ok(count > 1 ? t(`${count} vocaux créés : ${list}${priv ? " (privés)" : ""}.`, `${count} voice channels created: ${list}${priv ? " (private)" : ""}.`) : t(`Vocal créé : ${list}${priv ? " (privé)" : ""}.`, `Voice channel created: ${list}${priv ? " (private)" : ""}.`));
        return count > 1 ? i.editReply(doneText) : reply(i, doneText);
      } catch (error) {
        console.error("⚠️ Voc error:", error?.message || error);
        return reply(i, no(t("Je n'ai pas pu le créer (il me faut « Gérer les salons »).", "I could not create it (I need Manage Channels).")));
      }
    }
  };

  /* ---------- lock / unlock a channel ---------- */
  const SEND = P.SendMessages;
  async function lockChannel(guild, channel, by, reason, ms) {
    const everyone = guild.roles.everyone;
    const current = channel.permissionOverwrites.cache?.get?.(everyone.id);
    const prev = current?.allow?.has?.(SEND) ? true : current?.deny?.has?.(SEND) ? false : null;
    await channel.permissionOverwrites.edit(everyone.id, { SendMessages: false, SendMessagesInThreads: false, AddReactions: false }, { reason: `lock: ${by}` });
    db.locks[channel.id] = { prev, until: ms ? Date.now() + ms : 0 };
    save(true);
  }
  async function unlockChannel(guild, channel, why) {
    const lock = db.locks[channel.id];
    await channel.permissionOverwrites.edit(guild.roles.everyone.id, { SendMessages: lock?.prev ?? null, SendMessagesInThreads: null, AddReactions: null }, { reason: `unlock: ${why}` });
    delete db.locks[channel.id];
    save(true);
  }
  H.lock = async (i) => {
    if (need_perm(i, P.ManageChannels)) return;
    const channel = i.options.getChannel("salon") || i.channel;
    if (String(channel.topic || "").startsWith("mm-ticket:")) return reply(i, no(t("Impossible sur un ticket middleman : utilise « Appeler le staff » dans le ticket.", "Not possible on a middleman ticket: use \"Call staff\" in the ticket.")));
    if (db.locks[channel.id]) return reply(i, no(t("Ce salon est déjà verrouillé. `/unlock` pour le rouvrir.", "This channel is already locked. `/unlock` to open it.")));
    const raw = i.options.getString("duree");
    const ms = raw ? parseDuration(raw) : 0;
    if (raw && (!ms || ms > 30 * 86_400_000)) return reply(i, no(t("Durée invalide (ex : 10m, 2h, 1j).", "Invalid duration (e.g. 10m, 2h, 1d).")));
    const reason = i.options.getString("raison") || t("Aucune raison", "No reason");
    try {
      await lockChannel(i.guild, channel, i.user.username, reason, ms);
    } catch {
      return reply(i, no(t("Je n'ai pas pu verrouiller (il me faut « Gérer les salons »).", "I could not lock it (I need Manage Channels).")));
    }
    await channel.send?.({ embeds: [embed(0xed4245).setTitle(t("🔒 Salon verrouillé", "🔒 Channel locked")).setDescription(`${reason}${ms ? `\n${t("Réouverture", "Opens again")} <t:${Math.floor((Date.now() + ms) / 1000)}:R>` : ""}`)] }).catch(() => {});
    await log(i.guild, `🔒 **Lock** <#${channel.id}>  ·  ${t("par", "by")} ${i.user}  ·  ${reason}${ms ? `  ·  ${fmtDuration(ms)}` : ""}`, 0xed4245);
    return reply(i, ok(t(`<#${channel.id}> est verrouillé${ms ? ` pendant ${fmtDuration(ms)}` : ""}.`, `<#${channel.id}> is locked${ms ? ` for ${fmtDuration(ms)}` : ""}.`)));
  };
  H.unlock = async (i) => {
    if (need_perm(i, P.ManageChannels)) return;
    const channel = i.options.getChannel("salon") || i.channel;
    if (!db.locks[channel.id]) return reply(i, no(t("Ce salon n'a pas été verrouillé par le bot.", "This channel was not locked by the bot.")));
    try {
      await unlockChannel(i.guild, channel, i.user.username);
    } catch {
      return reply(i, no(t("Je n'ai pas pu déverrouiller (il me faut « Gérer les salons »).", "I could not unlock it (I need Manage Channels).")));
    }
    await channel.send?.({ embeds: [embed(0x57f287).setTitle(t("🔓 Salon déverrouillé", "🔓 Channel unlocked"))] }).catch(() => {});
    await log(i.guild, `🔓 **Unlock** <#${channel.id}>  ·  ${t("par", "by")} ${i.user}`, 0x2ecc71);
    return reply(i, ok(t(`<#${channel.id}> est déverrouillé.`, `<#${channel.id}> is unlocked.`)));
  };
  /* Locks with a duration open again by themselves. */
  async function tickLocks() {
    const now = Date.now();
    for (const [id, lock] of Object.entries(db.locks)) {
      if (!lock.until || lock.until > now) continue;
      const channel = await Promise.resolve(client?.channels?.fetch?.(id)).catch(() => null);
      if (!channel?.guild) {
        delete db.locks[id]; // the channel is gone
        save();
        continue;
      }
      try {
        await unlockChannel(channel.guild, channel, "timer");
        await channel.send?.({ embeds: [embed(0x57f287).setTitle(t("🔓 Salon déverrouillé", "🔓 Channel unlocked"))] }).catch(() => {});
      } catch (error) {
        console.error("⚠️ Auto unlock failed:", error?.message || error);
        lock.until = now + 5 * 60_000; // try again in 5 minutes
      }
    }
  }

  H.clear = async (i) => {
    if (need_perm(i, P.ManageMessages)) return;
    const n = i.options.getInteger("nombre");
    const user = i.options.getUser("membre");
    await i.deferReply({ flags: ephemeral });
    try {
      let count;
      if (user) {
        const messages = await i.channel.messages.fetch({ limit: 100 });
        const mine = [...messages.filter((m) => m.author.id === user.id).values()].slice(0, n);
        count = (await i.channel.bulkDelete(mine, true)).size;
      } else {
        count = (await i.channel.bulkDelete(n, true)).size;
      }
      await log(i.guild, `🧹 **Clear** ${count} ${t("messages dans", "messages in")} <#${i.channelId}>  ·  ${t("par", "by")} ${i.user}`);
      return i.editReply(ok(t(`${count} message(s) supprimé(s). (les messages de plus de 14 jours ne peuvent pas l'être)`, `${count} message(s) deleted. (messages older than 14 days cannot be)`)));
    } catch {
      return i.editReply(no(t("Je n'ai pas pu supprimer (permission « Gérer les messages » manquante ?).", "I could not delete (missing Manage Messages?).")));
    }
  };

  /* welcome */
  const fill = (text, member) => String(text).replace(/\{user\}/g, `<@${member.id}>`).replace(/\{server\}/g, member.guild?.name || "").replace(/\{count\}/g, String(member.guild?.memberCount ?? ""));
  H.welcome = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const w = db.cfg.welcome;
    const sub = i.options.getSubcommand();
    if (sub === "channel") {
      w.channelId = i.channelId;
      if (!w.message) w.message = t("Bienvenue {user} sur **{server}** ! Nous sommes {count}.", "Welcome {user} to **{server}**! We are {count}.");
      save();
      return reply(i, ok(t("Les messages de bienvenue arriveront ici.", "Welcome messages will go here.")));
    }
    if (sub === "message") {
      w.message = i.options.getString("texte");
      db.setup.autoWelcome = false;
      save();
      return reply(i, ok(t("Message de bienvenue enregistré.", "Welcome message saved.")));
    }
    if (sub === "leave") {
      const text = i.options.getString("texte");
      const channel = i.options.getChannel?.("salon");
      if (text) w.leave = text;
      if (!w.leave) w.leave = t("{user} a quitté {server}.", "{user} left {server}.");
      w.leaveChannelId = channel?.id || i.channelId;
      save();
      return reply(i, ok(t(`Les au revoir arriveront dans <#${w.leaveChannelId}>, séparés de la bienvenue.`, `Goodbyes will go to <#${w.leaveChannelId}>, separate from the welcome.`)));
    }
    if (sub === "autorole") {
      const role = i.options.getRole("role");
      w.autorole = role?.id || "";
      save();
      return reply(i, ok(role ? t(`Les nouveaux recevront ${role}.`, `New members will get ${role}.`) : t("Plus de rôle automatique.", "No more auto role.")));
    }
    if (sub === "off") {
      db.cfg.welcome = { channelId: "", message: "", leave: "", leaveChannelId: "", autorole: "" };
      save();
      return reply(i, ok(t("Bienvenue coupé.", "Welcome turned off.")));
    }
    if (sub === "test") {
      if (!w.message) return reply(i, no(t("Aucun message. Utilise `/welcome channel`.", "No message. Use `/welcome channel`.")));
      await i.deferReply({ flags: ephemeral });
      const card = await welcomeCard(i.member, true);
      return i.editReply({ content: fill(w.message, i.member), embeds: [embed(0xff8a3d).setImage(card.url)], files: [card.file] });
    }
  };
  const recentJoins = [];
  async function onJoin(member) {
    const w = db.cfg.welcome;
    const joinedAt = Date.now();
    while (recentJoins.length && joinedAt - recentJoins[0] > 10_000) recentJoins.shift();
    recentJoins.push(joinedAt);
    const sec = db.cfg.security;
    if (sec.antiRaid) {
      const now = Date.now();
      joins.push(now);
      while (joins.length && now - joins[0] > 10_000) joins.shift();
      if (joins.length >= 5) {
        if (!raidUntil || now > raidUntil) await log(member.guild, t("🚨 **Raid probable** : 5 arrivées en 10 secondes. Les nouveaux sont mis en sourdine 10 min pendant 2 minutes.", "🚨 **Likely raid**: 5 joins in 10 seconds. New members are timed out 10 min for 2 minutes."), 0xed4245);
        raidUntil = now + 120_000;
      }
      if (raidUntil && now < raidUntil) await member.timeout(600_000, "anti-raid").catch(() => {});
    }
    if (w.autorole) await member.roles.add(w.autorole, "auto role").catch(() => {});
    if (w.channelId && w.message) {
      const channel = await member.guild.channels.fetch(w.channelId).catch(() => null);
      if (channel?.isTextBased?.()) {
        const body = { content: fill(w.message, member), allowedMentions: { users: [member.id] } };
        try {
          const card = await welcomeCard(member, recentJoins.length < 3); // many joins at once (a raid): a still picture, the server stays responsive
          body.embeds = [embed(0xff8a3d).setImage(card.url)];
          body.files = [card.file];
        } catch (error) {
          console.error("⚠️ Welcome picture failed:", error?.message || error);
        }
        await channel.send(body).catch(() => {});
      }
    }
    await log(member.guild, `📥 ${member.user} ${t("a rejoint", "joined")}  ·  ${t("compte créé", "account created")} <t:${Math.floor(member.user.createdTimestamp / 1000)}:R>`, 0x2ecc71);
  }
  async function onLeave(member) {
    const w = db.cfg.welcome;
    const target = w.leaveChannelId || w.channelId;
    if (target && w.leave) {
      const channel = await member.guild.channels.fetch(target).catch(() => null);
      if (channel?.isTextBased?.()) await channel.send({ content: fill(w.leave, member), allowedMentions: { parse: [] } }).catch(() => {});
    }
    await log(member.guild, `📤 ${member.user ? `${member.user.username}` : member.id} ${t("a quitté", "left")}`, 0xe67e22);
  }
  const joins = [];
  let raidUntil = 0;

  /* role panel */
  H.rolepanel = async (i) => {
    if (need_perm(i, P.ManageRoles)) return;
    const roles = [];
    for (let n = 1; n <= 5; n++) {
      const r = i.options.getRole(`role${n}`);
      if (r && !roles.some((x) => x.id === r.id)) roles.push(r);
    }
    const me = i.guild.members.me;
    const bad = roles.find((r) => r.managed || r.id === i.guild.id || (me && me.roles.highest.comparePositionTo(r) <= 0));
    if (bad) return reply(i, no(t(`Je ne peux pas donner ${bad} (rôle géré ou au-dessus du mien).`, `I cannot give ${bad} (managed or above mine).`)));
    const row = new ActionRowBuilder().addComponents(roles.map((r) => new ButtonBuilder().setCustomId(`tl:rr:${r.id}`).setLabel(r.name.slice(0, 80)).setStyle(ButtonStyle.Secondary)));
    await i.channel.send({ embeds: [embed().setTitle(i.options.getString("titre")).setDescription(t("Appuie sur un bouton pour prendre ou retirer un rôle.", "Press a button to take or drop a role."))], components: [row] });
    return reply(i, ok(t("Panneau posté.", "Panel posted.")));
  };
  async function roleButton(i, roleId) {
    const role = i.guild.roles.cache.get(roleId);
    if (!role) return reply(i, no(t("Ce rôle n'existe plus.", "This role no longer exists.")));
    const has = i.member.roles.cache.has(roleId);
    try {
      if (has) await i.member.roles.remove(roleId, "role panel");
      else await i.member.roles.add(roleId, "role panel");
    } catch {
      return reply(i, no(t("Je n'ai pas pu changer ce rôle (mon rôle est trop bas ?).", "I could not change this role (my role too low?).")));
    }
    return reply(i, has ? ok(t(`Rôle ${role.name} retiré.`, `Role ${role.name} removed.`)) : ok(t(`Rôle ${role.name} ajouté.`, `Role ${role.name} added.`)));
  }

  /* polls */
  const pollEmbed = (poll) => {
    const total = Object.keys(poll.votes).length;
    const lines = poll.options.map((o, n) => {
      const c = Object.values(poll.votes).filter((v) => v === n).length;
      return `**${n + 1}. ${o}**\n${bar(c, Math.max(1, total), 10)} ${c} (${total ? Math.round((c / total) * 100) : 0}%)`;
    });
    return embed(0x3498db).setTitle(`📊 ${poll.question}`).setDescription(lines.join("\n\n")).setFooter({ text: t(`${total} vote(s)`, `${total} vote(s)`) });
  };
  H.poll = async (i) => {
    const options = [];
    for (let n = 1; n <= 5; n++) {
      const o = i.options.getString(`choix${n}`);
      if (o) options.push(o);
    }
    const poll = { question: i.options.getString("question"), options, votes: {} };
    const row = new ActionRowBuilder().addComponents(options.map((o, n) => new ButtonBuilder().setCustomId(`tl:poll:${n}`).setLabel(`${n + 1}. ${o}`.slice(0, 80)).setStyle(ButtonStyle.Primary)));
    await i.reply({ embeds: [pollEmbed(poll)], components: [row] });
    const message = await i.fetchReply();
    db.polls[message.id] = poll;
    save();
  };
  async function pollVote(i, index) {
    const poll = db.polls[i.message.id];
    if (!poll || !poll.options[index]) return reply(i, no(t("Ce sondage n'existe plus.", "This poll no longer exists.")));
    if (poll.votes[i.user.id] === index) delete poll.votes[i.user.id];
    else poll.votes[i.user.id] = index;
    save();
    return i.update({ embeds: [pollEmbed(poll)] });
  }

  /* giveaways */
  const gwWord = () => ({ title: "GIVEAWAY", winnersOne: t("GAGNANT", "WINNER"), winnersMany: t("GAGNANTS", "WINNERS"), noWinner: t("PAS DE GAGNANT", "NO WINNER"), entries: t("PARTICIPANTS", "ENTRIES"), by: t("par", "by") });
  /* The giveaway message: a live countdown, the host, the number of entries (changes with every click). */
  const gwEmbed = (g, ended = false, winners = [], withImage = true) => {
    const end = Math.floor(g.endsAt / 1000);
    const e = embed(ended ? 0x747f8d : 0xf1c40f).setTitle(`🎉  ${g.prize}`);
    if (!ended) {
      e.setDescription(t("Appuie sur **🎉 Participer** pour tenter ta chance !", "Press **🎉 Join** to try your luck!"))
        .addFields(
          { name: `⏰  ${t("Fin", "Ends")}`, value: `<t:${end}:R>\n<t:${end}:f>`, inline: true },
          { name: `🏆  ${t("Gagnants", "Winners")}`, value: `**${g.winners}**`, inline: true },
          { name: `👥  ${t("Participants", "Entries")}`, value: `**${g.entries.length}**`, inline: true },
          ...(g.host ? [{ name: `👑  ${t("Organisé par", "Hosted by")}`, value: `<@${g.host}>`, inline: true }] : [])
        )
        .setTimestamp(g.endsAt)
        .setFooter({ text: t("Se termine", "Ends") });
      if (withImage) e.setImage("attachment://giveaway.gif");
    } else {
      e.setDescription(winners.length ? t(`🏆  **${winners.length > 1 ? "Gagnants" : "Gagnant"} :** ${winners.map((w) => `<@${w}>`).join(", ")}`, `🏆  **${winners.length > 1 ? "Winners" : "Winner"}:** ${winners.map((w) => `<@${w}>`).join(", ")}`) : t("Personne n'a participé.", "Nobody joined."))
        .addFields({ name: `👥  ${t("Participants", "Entries")}`, value: `**${g.entries.length}**`, inline: true }, ...(g.host ? [{ name: `👑  ${t("Organisé par", "Hosted by")}`, value: `<@${g.host}>`, inline: true }] : []))
        .setFooter({ text: t("Terminé", "Ended") })
        .setTimestamp(g.endsAt);
      if (withImage) e.setImage("attachment://giveaway-end.png");
    }
    return e;
  };
  const gwRow = (g, ended = false) =>
    new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId("tl:gw").setLabel(ended ? t("Terminé", "Ended") : `${t("Participer", "Join")} (${g.entries.length})`).setEmoji("🎉").setStyle(ended ? ButtonStyle.Secondary : ButtonStyle.Success).setDisabled(ended),
      new ButtonBuilder().setCustomId("tl:gwlist").setLabel(t("Participants", "Entries")).setEmoji("👥").setStyle(ButtonStyle.Secondary)
    );
  const draw = (g) => {
    const pool = [...g.entries];
    const out = [];
    while (pool.length && out.length < g.winners) out.push(pool.splice(Math.floor(Math.random() * pool.length), 1)[0]);
    return out;
  };
  async function endGiveaway(messageId, announce = true) {
    const g = db.giveaways[messageId];
    if (!g) return false;
    const channel = await client.channels.fetch(g.channelId).catch(() => null);
    const winners = draw(g);
    g.ended = true;
    g.lastWinners = winners;
    save();
    const message = await channel?.messages?.fetch?.(messageId).catch(() => null);
    if (message) {
      let card = null;
      try {
        const named = await Promise.all(
          winners.slice(0, 3).map(async (id, n) => {
            const m = await channel.guild?.members?.fetch?.(id).catch(() => null);
            return { name: m?.displayName || m?.user?.username || t("Membre", "Member"), avatar: n === 0 && m ? await loadAvatar(m) : null };
          })
        );
        card = picture("giveaway-end.png", gfx.giveawayEnd({ prize: g.prize, winners: winners.map((id, n) => named[n] || { name: "…", avatar: null }), count: g.entries.length, label: gwWord() }));
      } catch (error) {
        console.error("⚠️ Giveaway card failed:", error?.message || error);
      }
      // the animated banner is replaced by the card of the end, and the button is switched off
      await message.edit({ embeds: [gwEmbed(g, true, winners, Boolean(card))], components: [gwRow(g, true)], ...(card ? { files: [card.file], attachments: [] } : { attachments: [] }) }).catch(() => {});
    }
    if (announce && channel?.isTextBased?.()) {
      await channel.send({ content: winners.length ? t(`🎉 Bravo ${winners.map((w) => `<@${w}>`).join(", ")} ! Vous gagnez **${g.prize}** !`, `🎉 Congrats ${winners.map((w) => `<@${w}>`).join(", ")}! You win **${g.prize}**!`) : t(`Concours **${g.prize}** terminé : aucun participant.`, `Giveaway **${g.prize}** ended: nobody joined.`), allowedMentions: { users: winners } }).catch(() => {});
    }
    return true;
  }
  H.giveaway = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const sub = i.options.getSubcommand();
    if (sub === "start") {
      const ms = parseDuration(i.options.getString("duree"));
      if (!ms || ms < 10_000 || ms > 30 * 86_400_000) return reply(i, no(t("Durée invalide (ex : 10m, 2h, 1j).", "Invalid duration (e.g. 10m, 2h, 1d).")));
      const g = { channelId: i.channelId, prize: i.options.getString("lot"), winners: i.options.getInteger("gagnants") || 1, endsAt: Date.now() + ms, entries: [], ended: false, host: i.user.id };
      await i.deferReply(); // the animated banner takes about a second to draw
      let card = null;
      try {
        card = picture("giveaway.gif", gfx.giveawayAnimated({ prize: g.prize, winners: g.winners, host: i.member?.displayName || i.user.username, label: gwWord() }));
      } catch (error) {
        console.error("⚠️ Giveaway banner failed:", error?.message || error);
      }
      await i.editReply({ embeds: [gwEmbed(g, false, [], Boolean(card))], components: [gwRow(g)], ...(card ? { files: [card.file] } : {}) });
      const message = await i.fetchReply();
      db.giveaways[message.id] = g;
      save();
      return;
    }
    const id = i.options.getString("message_id").trim();
    const g = db.giveaways[id];
    if (!g) return reply(i, no(t("Concours introuvable.", "Giveaway not found.")));
    if (sub === "end") {
      if (g.ended) return reply(i, no(t("Déjà terminé. Utilise `/giveaway reroll`.", "Already ended. Use `/giveaway reroll`.")));
      await endGiveaway(id);
      return reply(i, ok(t("Concours terminé.", "Giveaway ended.")));
    }
    if (sub === "reroll") {
      if (!g.ended) return reply(i, no(t("Le concours n'est pas terminé.", "The giveaway has not ended.")));
      const winners = draw(g);
      g.lastWinners = winners;
      save();
      return i.reply({ content: winners.length ? t(`🎉 Nouveau tirage : ${winners.map((w) => `<@${w}>`).join(", ")} gagne **${g.prize}** !`, `🎉 New draw: ${winners.map((w) => `<@${w}>`).join(", ")} wins **${g.prize}**!`) : no(t("Personne n'a participé.", "Nobody joined.")), allowedMentions: { users: winners } });
    }
  };
  async function giveawayJoin(i) {
    const g = db.giveaways[i.message.id];
    if (!g || g.ended) return reply(i, no(t("Ce concours est terminé.", "This giveaway has ended.")));
    if (g.entries.includes(i.user.id)) {
      g.entries = g.entries.filter((u) => u !== i.user.id);
      save();
      await i.update({ embeds: [gwEmbed(g)], components: [gwRow(g)] });
      return;
    }
    g.entries.push(i.user.id);
    save();
    return i.update({ embeds: [gwEmbed(g)], components: [gwRow(g)] });
  }
  /* "Entries": who is in, privately. */
  async function giveawayList(i) {
    const g = db.giveaways[i.message?.id];
    if (!g) return reply(i, no(t("Ce concours n'existe plus.", "This giveaway no longer exists.")));
    const shown = g.entries.slice(0, 40).map((id) => `<@${id}>`).join(" ");
    const more = g.entries.length > 40 ? `\n${t(`… et ${g.entries.length - 40} autres`, `… and ${g.entries.length - 40} more`)}` : "";
    return i.reply({
      flags: ephemeral,
      allowedMentions: { parse: [] },
      embeds: [embed(0xf1c40f).setTitle(`👥  ${t("Participants", "Entries")}  ·  ${g.entries.length}`).setDescription(g.entries.length ? `${shown}${more}` : t("Personne pour le moment. Sois le premier !", "Nobody yet. Be the first!"))],
    });
  }
  async function tickGiveaways() {
    const now = Date.now();
    for (const [id, g] of Object.entries(db.giveaways)) {
      if (!g.ended && g.endsAt <= now) await endGiveaway(id).catch((e) => console.error("⚠️ giveaway:", e?.message || e));
    }
    // forget old finished ones (30 days)
    for (const [id, g] of Object.entries(db.giveaways)) if (g.ended && now - g.endsAt > 30 * 86_400_000) delete db.giveaways[id];
  }

  /* suggestions */
  H.suggestions = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    db.cfg.suggest.channelId = i.channelId;
    save();
    return reply(i, ok(t("Les suggestions arriveront ici.", "Suggestions will go here.")));
  };
  H.suggest = async (i) => {
    const id = db.cfg.suggest.channelId;
    if (!id) return reply(i, no(t("Aucun salon de suggestions. Un admin doit utiliser `/suggestions` dans le salon voulu.", "No suggestions channel. An admin must use `/suggestions` in the right channel.")));
    const channel = await i.guild.channels.fetch(id).catch(() => null);
    if (!channel?.isTextBased?.()) return reply(i, no(t("Le salon des suggestions n'existe plus.", "The suggestions channel no longer exists.")));
    const m = await channel.send({ embeds: [embed(0x9b59b6).setAuthor({ name: i.user.username, iconURL: i.user.displayAvatarURL?.() }).setTitle(t("💡 Suggestion", "💡 Suggestion")).setDescription(i.options.getString("idee"))] });
    await m.react("👍").catch(() => {});
    await m.react("👎").catch(() => {});
    return reply(i, ok(t("Suggestion envoyée !", "Suggestion sent!")));
  };

  /* ---------- vouches: a review with stars for the person you traded with ---------- */
  const stars = (n) => "★".repeat(n) + "☆".repeat(5 - n);
  const vouchStats = (id) => {
    const list = db.vouches[id] || [];
    const avg = list.length ? list.reduce((a, v) => a + v.stars, 0) / list.length : 0;
    return { list, count: list.length, avg };
  };
  const vouchChannelId = () => db.cfg.vouch.channelId || db.setup.items.find((x) => x.key === "vouches")?.id || "";
  H.vouch = async (i) => {
    const target = i.options.getUser("membre");
    const note = i.options.getInteger("note");
    const text = String(i.options.getString("commentaire") || "").trim().slice(0, 500);
    const item = String(i.options.getString("objet") || "").trim().slice(0, 100);
    if (!target) return reply(i, no(t("Choisis la personne à vouch.", "Pick the person to vouch for.")));
    if (target.id === i.user.id) return reply(i, no(t("Tu ne peux pas te vouch toi-même.", "You cannot vouch for yourself.")));
    if (target.bot) return reply(i, no(t("On ne vouch pas un bot.", "You cannot vouch for a bot.")));
    if (!(note >= 1 && note <= 5)) return reply(i, no(t("La note va de 1 à 5.", "The rating goes from 1 to 5.")));
    if (text.length < 3) return reply(i, no(t("Écris un vrai commentaire (3 caractères minimum).", "Write a real comment (3 characters minimum).")));
    if (item.length < 2) return reply(i, no(t("Écris l'objet trade ou le service (ex : Garama, Middleman).", "Write the traded item or the service (e.g. Garama, Middleman).")));
    const wait = Math.max(0, Number(db.cfg.vouch.cooldownH) || 0) * 3_600_000;
    const last = (db.vouches[target.id] || []).filter((v) => v.from === i.user.id).at(-1);
    if (last && wait && Date.now() - last.at < wait) {
      return reply(i, no(t(`Tu as déjà vouch <@${target.id}> récemment. Tu pourras recommencer <t:${Math.floor((last.at + wait) / 1000)}:R>.`, `You already vouched for <@${target.id}> recently. You can do it again <t:${Math.floor((last.at + wait) / 1000)}:R>.`)));
    }
    const channelId = vouchChannelId();
    const channel = channelId ? await Promise.resolve(i.guild.channels.fetch(channelId)).catch(() => null) : i.channel;
    if (!channel?.isTextBased?.() || !channel.send) return reply(i, no(t("Le salon des vouches n'existe plus. Un admin doit faire `/vouchadmin salon`.", "The vouch channel no longer exists. An admin must use `/vouchadmin salon`.")));
    const n = (db.vouchN || 0) + 1;
    const v = { n, from: i.user.id, stars: note, text, item, at: Date.now(), channelId: channel.id, msgId: "" };
    const after = vouchStats(target.id);
    const count = after.count + 1;
    const avg = (after.avg * after.count + note) / count;
    const e = embed(note >= 4 ? 0xf1c40f : note === 3 ? 0xe67e22 : 0xed4245)
      .setAuthor({ name: `${i.member?.displayName || i.user.username}`, iconURL: i.user.displayAvatarURL?.() || undefined })
      .setTitle(`⭐  Vouch #${n}`)
      .setDescription(`<@${i.user.id}> ➜ <@${target.id}>\n\n**${stars(note)}**  ${note}/5\n\n> ${text.replace(/\n/g, "\n> ")}`)
      .setThumbnail(target.displayAvatarURL?.() || null)
      .addFields({ name: t("📦 Objet / service", "📦 Item / service"), value: `**${item}**`, inline: true }, { name: t("📊 Total", "📊 Total"), inline: true, value: t(`**${count}** vouch(es) · moyenne **${avg.toFixed(1)}/5**`, `**${count}** vouch(es) · average **${avg.toFixed(1)}/5**`) })
      .setFooter({ text: t("Kazuki MM · /vouch pour laisser le tien", "Kazuki MM · /vouch to leave yours") });
    let message;
    try {
      message = await channel.send({ content: `<@${target.id}>`, embeds: [e], allowedMentions: { users: [target.id] } });
    } catch (error) {
      console.error("⚠️ Vouch could not be posted:", error?.message || error);
      return reply(i, no(t(`Je ne peux pas écrire dans <#${channel.id}>.`, `I cannot write in <#${channel.id}>.`)));
    }
    v.msgId = message?.id || "";
    db.vouchN = n;
    (db.vouches[target.id] ||= []).push(v);
    save(true);
    queueVouchPanel();
    if (channel.id === vouchChannelId()) await postSticky(channel).catch(() => {});
    await log(i.guild, `⭐ **Vouch #${n}**  ·  <@${i.user.id}> ➜ <@${target.id}>  ·  ${note}/5`, 0xf1c40f);
    return reply(i, ok(channel.id === i.channelId ? t(`Vouch #${n} envoyé pour <@${target.id}> !`, `Vouch #${n} sent for <@${target.id}>!`) : t(`Vouch #${n} envoyé pour <@${target.id}> dans <#${channel.id}> !`, `Vouch #${n} sent for <@${target.id}> in <#${channel.id}>!`)));
  };
  /* ---------- the vouch ranking panel: never reset, kept up to date in the background ---------- */
  /* Everyone ranked by all the vouches they ever got (then by average). */
  function vouchRanking() {
    return Object.entries(db.vouches)
      .map(([id, list]) => ({ id, count: list.length, avg: list.length ? list.reduce((a, v) => a + v.stars, 0) / list.length : 0 }))
      .filter((r) => r.count)
      .sort((a, b) => b.count - a.count || b.avg - a.avg);
  }
  async function vouchPanelBody(guild) {
    const rows = vouchRanking().slice(0, 10);
    const medal = ["🥇", "🥈", "🥉"];
    const members = await Promise.all(rows.map((r) => Promise.resolve(guild?.members?.fetch?.(r.id)).catch(() => null)));
    let file;
    if (rows.length) {
      const cards = await Promise.all(rows.map(async (r, k) => ({ name: members[k]?.displayName || members[k]?.user?.username || t("Ancien membre", "Former member"), level: r.count, into: Math.round(r.avg * 100), need: 500, xp: 0, sub: `${r.avg.toFixed(1)}/5`, avatar: members[k] ? await loadAvatar(members[k], 64).catch(() => null) : null })));
      file = new AttachmentBuilder(gfx.leaderboard(cards, { title: "TOP VOUCHES", level: "VOUCHES" }), { name: "vouches.png" });
    } else file = new AttachmentBuilder(gfx.banner("KAZUKI MM", "TOP VOUCHES", "#5a3a05", "#f1c40f"), { name: "vouches.png" });
    const list = rows.length ? rows.map((r, k) => `${medal[k] || `**${k + 1}.**`} <@${r.id}> · **${r.count}** vouch(es) · ${r.avg.toFixed(1)}/5`).join("\n") : t("*Personne pour le moment : sois le premier à recevoir un vouch !*", "*Nobody yet: be the first to get a vouch!*");
    const e = embed(0xf1c40f)
      .setTitle(t("🏆  Top vouches", "🏆  Top vouches"))
      .setDescription(`${list}\n\n⭐ ${t("Pour vouch quelqu'un, utilise", "To vouch for someone, use")} \`/vouch\``)
      .setImage("attachment://vouches.png");
    return { embeds: [e], files: [file], components: [], allowedMentions: { parse: [] } };
  }
  /* What the panel shows: when it changes, the panel is redrawn. */
  const panelSignature = (guild) => JSON.stringify(vouchRanking().slice(0, 10).map((r) => [r.id, r.count, r.avg.toFixed(1), guild?.members?.cache?.get?.(r.id)?.displayName || ""]));
  let panelShown = "";
  let panelBusy = false;
  async function refreshVouchPanel(force = false) {
    const cfg = db.cfg.vouch;
    if (!cfg.panelChannelId || !cfg.panelMsgId || panelBusy) return false;
    panelBusy = true;
    try {
      const channel = await Promise.resolve(client?.channels?.fetch?.(cfg.panelChannelId)).catch(() => null);
      const sig = panelSignature(channel?.guild);
      if (!force && sig === panelShown) return false; // nothing changed: nothing to do
      const message = channel ? await Promise.resolve(channel.messages?.fetch?.(cfg.panelMsgId)).catch(() => null) : null;
      if (!message) {
        cfg.panelMsgId = ""; // the panel was deleted: stop updating it
        save();
        return false;
      }
      await message.edit({ ...(await vouchPanelBody(channel.guild)), attachments: [] });
      panelShown = sig;
      return true;
    } finally {
      panelBusy = false;
    }
  }
  const queueVouchPanel = () => {
    panelShown = ""; // the next check (within a second) redraws it
  };

  /* ---------- the vouch channel: a reminder always at the bottom, and plain messages are turned into a hint ---------- */
  const STICKY_WAIT = 1500;
  const stickyTimers = new Map();
  /* A discreet reminder: one small grey line, no ping, no notification. */
  const stickyBody = () => ({
    content: t("-# ⭐ Pour laisser un vouch, utilise **`/vouch`** · membre · note · objet · commentaire", "-# ⭐ To leave a vouch, use **`/vouch`** · member · rating · item · comment"),
    flags: MessageFlags.SuppressNotifications,
    allowedMentions: { parse: [] },
  });
  /* The reminder is moved to the bottom (old one deleted, new one posted). */
  let stickyChain = Promise.resolve();
  function postSticky(channel) {
    stickyChain = stickyChain.then(() => moveSticky(channel)).catch(() => {});
    return stickyChain;
  }
  async function moveSticky(channel) {
    const cfg = db.cfg.vouch;
    if (!channel?.send) return;
    if (cfg.stickyMsgId) {
      const old = await Promise.resolve(channel.messages?.fetch?.(cfg.stickyMsgId)).catch(() => null);
      await old?.delete?.().catch(() => {});
    }
    const message = await channel.send(stickyBody()).catch(() => null);
    cfg.stickyMsgId = message?.id || "";
    save();
  }
  function queueSticky(channel) {
    if (!channel?.id || stickyTimers.has(channel.id)) return;
    const timer = setTimeout(() => {
      stickyTimers.delete(channel.id);
      postSticky(channel).catch(() => {});
    }, STICKY_WAIT);
    timer.unref?.();
    stickyTimers.set(channel.id, timer);
  }
  /* A normal message in the vouch channel: removed, with a short hint that disappears. Staff can still talk. */
  async function onVouchChannelMessage(message) {
    const id = vouchChannelId();
    if (!id || message.channelId !== id || message.author?.bot || !message.guild) return false;
    if (message.member?.permissions?.has?.(P.ManageMessages)) {
      queueSticky(message.channel);
      return false;
    }
    await message.delete?.().catch(() => {});
    const hint = await Promise.resolve(message.channel.send?.({ content: t(`<@${message.author.id}> ici on vouch uniquement avec **\`/vouch\`** ⭐`, `<@${message.author.id}> here you can only vouch with **\`/vouch\`** ⭐`), allowedMentions: { users: [message.author.id] } })).catch(() => null);
    if (hint?.delete) setTimeout(() => hint.delete().catch(() => {}), 8000).unref?.();
    return true;
  }

  H.vouchadmin = async (i) => {
    const sub = i.options.getSubcommand();
    if (need_perm(i, P.ManageGuild)) return;
    if (sub === "panel") {
      const cfg = db.cfg.vouch;
      const channel = i.options.getChannel?.("salon") || i.channel;
      if (!channel?.send) return reply(i, no(t("Je ne peux pas écrire dans ce salon.", "I cannot write in that channel.")));
      await i.deferReply({ flags: ephemeral });
      // only one panel: the old one is removed
      if (cfg.panelChannelId && cfg.panelMsgId) {
        const old = await Promise.resolve(i.guild.channels.fetch(cfg.panelChannelId)).catch(() => null);
        const message = await Promise.resolve(old?.messages?.fetch?.(cfg.panelMsgId)).catch(() => null);
        await message?.delete?.().catch(() => {});
      }
      let message;
      try {
        message = await channel.send(await vouchPanelBody(i.guild));
      } catch (error) {
        console.error("⚠️ Vouch panel:", error?.message || error);
        return i.editReply(no(t(`Je ne peux pas écrire dans <#${channel.id}>.`, `I cannot write in <#${channel.id}>.`)));
      }
      cfg.panelChannelId = channel.id;
      cfg.panelMsgId = message?.id || "";
      panelShown = panelSignature(i.guild);
      save(true);
      return i.editReply(ok(t(`Top vouches posté dans <#${channel.id}> : il se met à jour tout seul et ne se remet jamais à zéro.`, `Top vouches posted in <#${channel.id}>: it updates by itself and never resets.`)));
    }
    if (sub === "salon") {
      const channel = i.options.getChannel?.("salon");
      db.cfg.vouch.channelId = channel?.id || i.channelId;
      db.cfg.vouch.stickyMsgId = "";
      save();
      await postSticky(channel || i.channel).catch(() => {});
      return reply(i, ok(t(`Les vouches seront postés dans <#${db.cfg.vouch.channelId}>.`, `Vouches will be posted in <#${db.cfg.vouch.channelId}>.`)));
    }
    if (sub === "retirer") {
      const n = i.options.getInteger("numero");
      for (const [id, list] of Object.entries(db.vouches)) {
        const k = list.findIndex((v) => v.n === n);
        if (k < 0) continue;
        const [v] = list.splice(k, 1);
        if (!list.length) delete db.vouches[id];
        save(true);
        queueVouchPanel();
        const channel = await Promise.resolve(i.guild.channels.fetch(v.channelId)).catch(() => null);
        const message = await channel?.messages?.fetch?.(v.msgId).catch(() => null);
        await message?.delete?.().catch(() => {});
        await log(i.guild, `🗑️ **Vouch #${n}** ${t("retiré par", "removed by")} <@${i.user.id}>  ·  <@${v.from}> ➜ <@${id}>`, 0xed4245);
        return reply(i, ok(t(`Vouch #${n} retiré (de <@${v.from}> pour <@${id}>).`, `Vouch #${n} removed (from <@${v.from}> for <@${id}>).`)));
      }
      return reply(i, no(t(`Aucun vouch #${n}.`, `No vouch #${n}.`)));
    }
    if (sub === "reset") {
      const user = i.options.getUser("membre");
      const count = (db.vouches[user.id] || []).length;
      delete db.vouches[user.id];
      save(true);
      queueVouchPanel();
      return reply(i, count ? ok(t(`${count} vouch(es) de <@${user.id}> effacé(s).`, `${count} vouch(es) of <@${user.id}> cleared.`)) : no(t(`<@${user.id}> n'a aucun vouch.`, `<@${user.id}> has no vouch.`)));
    }
  };

  /* small fun */
  const BALL = {
    fr: ["Oui, sans aucun doute.", "C'est certain.", "Très probable.", "Les signes disent oui.", "Demande plus tard.", "Je ne peux pas te répondre maintenant.", "Peu probable.", "Mes sources disent non.", "Non.", "Certainement pas."],
    en: ["Yes, without a doubt.", "It is certain.", "Very likely.", "Signs point to yes.", "Ask again later.", "Cannot predict now.", "Unlikely.", "My sources say no.", "No.", "Definitely not."],
  };
  H["8ball"] = (i) => {
    const question = i.options.getString("question");
    if (!question) return startQuiz(i, "random");
    const card = picture("8ball.png", gfx.eightBall());
    return i.reply({
      embeds: [embed(0x2c2f33).setTitle(t("🎱 Boule magique", "🎱 Magic 8-ball")).setThumbnail(card.url).addFields({ name: t("Question", "Question"), value: question }, { name: t("Réponse", "Answer"), value: BALL[FR ? "fr" : "en"][Math.floor(Math.random() * 10)] })],
      files: [card.file],
    });
  };
  H.coinflip = (i) => {
    const heads = Math.random() < 0.5;
    const card = picture("coin.png", gfx.coin(heads ? "A" : "B", heads ? t("F", "H") : t("P", "T"), heads ? t("FACE", "HEADS") : t("PILE", "TAILS")));
    return i.reply({ embeds: [embed(0xf1c40f).setTitle(`🪙 ${heads ? t("Face", "Heads") : t("Pile", "Tails")} !`).setImage(card.url)], files: [card.file] });
  };
  H.dice = (i) => {
    const faces = i.options.getInteger("faces") || 6;
    const value = 1 + Math.floor(Math.random() * faces);
    const card = picture("dice.png", gfx.dice(faces, value));
    return i.reply({ embeds: [embed(0xe74c3c).setTitle(`🎲 d${faces} → ${value}`).setImage(card.url)], files: [card.file] });
  };

  /* ---------- quiz: a picture and a question, the first right answer in the channel wins xp ---------- */
  const norm = (text) => String(text ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
  // [flag code, French name, English name, other accepted answers]
  const FLAGS = [
    ["fr", "France", "France"], ["de", "Allemagne", "Germany"], ["it", "Italie", "Italy"], ["es", "Espagne", "Spain"], ["pt", "Portugal", "Portugal"], ["be", "Belgique", "Belgium"],
    ["ch", "Suisse", "Switzerland"], ["nl", "Pays-Bas", "Netherlands", ["hollande", "holland"]], ["gb", "Royaume-Uni", "United Kingdom", ["angleterre", "england", "uk"]], ["us", "États-Unis", "United States", ["usa", "etats unis", "amerique", "america"]],
    ["ca", "Canada", "Canada"], ["mx", "Mexique", "Mexico"], ["br", "Brésil", "Brazil"], ["ar", "Argentine", "Argentina"], ["jp", "Japon", "Japan"], ["cn", "Chine", "China"],
    ["kr", "Corée du Sud", "South Korea", ["coree", "korea"]], ["in", "Inde", "India"], ["ru", "Russie", "Russia"], ["tr", "Turquie", "Turkey"], ["eg", "Égypte", "Egypt"], ["ma", "Maroc", "Morocco"],
    ["dz", "Algérie", "Algeria"], ["tn", "Tunisie", "Tunisia"], ["sn", "Sénégal", "Senegal"], ["ci", "Côte d'Ivoire", "Ivory Coast", ["cote d ivoire"]], ["ng", "Nigéria", "Nigeria"], ["za", "Afrique du Sud", "South Africa"],
    ["au", "Australie", "Australia"], ["nz", "Nouvelle-Zélande", "New Zealand"], ["se", "Suède", "Sweden"], ["no", "Norvège", "Norway"], ["dk", "Danemark", "Denmark"], ["fi", "Finlande", "Finland"],
    ["pl", "Pologne", "Poland"], ["gr", "Grèce", "Greece"], ["ie", "Irlande", "Ireland"], ["at", "Autriche", "Austria"], ["ua", "Ukraine", "Ukraine"], ["sa", "Arabie saoudite", "Saudi Arabia"],
    ["cm", "Cameroun", "Cameroon"], ["ro", "Roumanie", "Romania"],
  ];
  const WORDS = {
    fr: ["ORDINATEUR", "TELEPHONE", "BIBLIOTHEQUE", "CHOCOLAT", "VOITURE", "MONTAGNE", "GUITARE", "FENETRE", "ELEPHANT", "PYRAMIDE", "PAPILLON", "BOULANGERIE", "AVENTURE", "TROTTINETTE", "DINOSAURE", "PARAPLUIE", "CROISSANT", "ASTRONAUTE", "TELEVISION", "CHAMPIGNON"],
    en: ["COMPUTER", "TELEPHONE", "LIBRARY", "CHOCOLATE", "MOUNTAIN", "GUITAR", "WINDOW", "ELEPHANT", "PYRAMID", "BUTTERFLY", "BAKERY", "ADVENTURE", "SCOOTER", "DINOSAUR", "UMBRELLA", "SANDWICH", "ASTRONAUT", "TELEVISION", "MUSHROOM", "KEYBOARD"],
  };
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const shuffle = (word) => {
    const letters = word.split("");
    for (let n = 0; n < 20; n++) {
      for (let k = letters.length - 1; k > 0; k--) {
        const j = Math.floor(Math.random() * (k + 1));
        [letters[k], letters[j]] = [letters[j], letters[k]];
      }
      if (letters.join("") !== word) break;
    }
    return letters.join("");
  };
  const QUIZ_SECONDS = 30;
  const quizzes = new Map(); // channelId -> running quiz
  let canRead = true;

  function makeQuiz(type) {
    const kind = type === "random" || !type ? pick(["flag", "math", "word"]) : type;
    if (kind === "flag") {
      const [code, frName, enName, extra = []] = pick(FLAGS);
      const answers = [...new Set([norm(frName), norm(enName), ...extra.map(norm)])];
      return { kind, question: t("🏳️ De quel pays est ce drapeau ?", "🏳️ Which country is this flag?"), imageUrl: `https://flagcdn.com/w640/${code}.png`, answers, reveal: FR ? frName : enName };
    }
    if (kind === "word") {
      const word = pick(WORDS[FR ? "fr" : "en"]);
      return { kind, question: t("🔤 Remets les lettres dans l'ordre : quel est ce mot ?", "🔤 Put the letters in order: what is this word?"), image: gfx.quizCard([shuffle(word)], "QUIZ", { spacing: 10 }), answers: [norm(word)], reveal: word.toLowerCase() };
    }
    const op = pick(["+", "-", "*"]);
    let a = 0;
    let b = 0;
    if (op === "*") { a = 2 + Math.floor(Math.random() * 11); b = 2 + Math.floor(Math.random() * 11); }
    else { a = 10 + Math.floor(Math.random() * 90); b = 10 + Math.floor(Math.random() * 90); if (op === "-" && b > a) [a, b] = [b, a]; }
    const result = op === "+" ? a + b : op === "-" ? a - b : a * b;
    return { kind: "math", question: t("🧮 Combien font ce calcul ?", "🧮 What is the result?"), image: gfx.quizCard([`${a} ${op === "*" ? "×" : op} ${b} = ?`], "QUIZ"), answers: [String(result)], reveal: String(result) };
  }

  /* Builds the quiz message and registers the quiz of the channel (call armQuiz once it is posted). */
  function buildQuiz(type, channel) {
    const q = makeQuiz(type);
    const xp = db.cfg.levels.quizXp;
    const e = embed(0x9b59b6).setTitle(q.question).setDescription(t(`Écris la réponse dans le salon ! **${QUIZ_SECONDS} secondes**, la première bonne réponse gagne **${xp} XP**.`, `Type the answer in the channel! **${QUIZ_SECONDS} seconds**, the first right answer wins **${xp} XP**.`));
    const body = { embeds: [e] };
    if (q.image) {
      const card = picture("quiz.png", q.image);
      e.setImage(card.url);
      body.files = [card.file];
    } else e.setImage(q.imageUrl);
    quizzes.set(channel.id, { ...q, xp, channel });
    return body;
  }
  function armQuiz(channelId) {
    const running = quizzes.get(channelId);
    if (!running) return;
    running.timer = setTimeout(() => expireQuiz(channelId), QUIZ_SECONDS * 1000);
    running.timer.unref?.();
  }

  async function startQuiz(i, type) {
    if (!canRead) return reply(i, no(t("Le quiz a besoin de lire les messages : active « Message Content Intent » dans le Developer Portal (onglet Bot), puis redémarre le bot.", "The quiz needs to read messages: switch on \"Message Content Intent\" in the Developer Portal (Bot tab), then restart the bot.")));
    if (quizzes.has(i.channelId)) return reply(i, no(t("Un quiz est déjà en cours dans ce salon.", "A quiz is already running in this channel.")));
    const body = buildQuiz(type, i.channel);
    await i.reply(body);
    armQuiz(i.channelId);
  }

  /* ---------- automatic quiz: one every N minutes (30 by default) in the chosen channel ---------- */
  async function tickAutoQuiz() {
    const cfg = db.cfg.autoquiz;
    if (!cfg.on || !cfg.channelId || !canRead) return;
    const now = Date.now();
    if (!cfg.nextAt) {
      cfg.nextAt = now + cfg.minutes * 60_000;
      save();
      return;
    }
    if (now < cfg.nextAt) return;
    cfg.nextAt = now + cfg.minutes * 60_000;
    save();
    const channel = await Promise.resolve(client?.channels?.fetch?.(cfg.channelId)).catch(() => null);
    if (!channel?.isTextBased?.() || quizzes.has(channel.id)) return;
    const body = buildQuiz("random", channel);
    try {
      await channel.send(body);
    } catch (error) {
      quizzes.delete(channel.id);
      console.error("⚠️ Auto quiz could not be posted:", error?.message || error);
      return;
    }
    armQuiz(channel.id);
  }
  H.autoquiz = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const cfg = db.cfg.autoquiz;
    const sub = i.options.getSubcommand();
    if (sub === "start") {
      if (!canRead) return reply(i, no(t("Le quiz a besoin de lire les messages : active « Message Content Intent » dans le Developer Portal (onglet Bot), puis redémarre le bot.", "The quiz needs to read messages: switch on \"Message Content Intent\" in the Developer Portal (Bot tab), then restart the bot.")));
      const channel = i.options.getChannel("salon");
      cfg.channelId = channel?.id || i.channelId;
      cfg.minutes = i.options.getInteger("minutes") || 30;
      cfg.on = true;
      cfg.nextAt = Date.now(); // the first one comes within the minute
      save();
      return reply(i, ok(t(`Un quiz sera lancé toutes les **${cfg.minutes} minutes** dans <#${cfg.channelId}>. Le premier arrive dans moins d'une minute.`, `A quiz will start every **${cfg.minutes} minutes** in <#${cfg.channelId}>. The first one comes within a minute.`)));
    }
    if (sub === "stop") {
      cfg.on = false;
      cfg.nextAt = 0;
      save();
      return reply(i, ok(t("Quiz automatique arrêté.", "Automatic quiz stopped.")));
    }
    return reply(i, cfg.on ? t(`✅ Un quiz toutes les ${cfg.minutes} min dans <#${cfg.channelId}>. Prochain <t:${Math.floor((cfg.nextAt || Date.now()) / 1000)}:R>.`, `✅ A quiz every ${cfg.minutes} min in <#${cfg.channelId}>. Next one <t:${Math.floor((cfg.nextAt || Date.now()) / 1000)}:R>.`) : t("❌ Le quiz automatique est arrêté. Lance-le avec `/autoquiz start`.", "❌ The automatic quiz is off. Start it with `/autoquiz start`."));
  };
  H.quiz = (i) => startQuiz(i, i.options.getString("type") || "random");

  async function expireQuiz(channelId) {
    const q = quizzes.get(channelId);
    if (!q) return;
    quizzes.delete(channelId);
    await q.channel.send({ embeds: [embed(0x747f8d).setDescription(t(`⏰ Temps écoulé ! La réponse était **${q.reveal}**.`, `⏰ Time is up! The answer was **${q.reveal}**.`))] }).catch(() => {});
  }

  /* Returns true when the message was the right answer of the quiz of its channel. */
  async function onQuizAnswer(message) {
    const q = quizzes.get(message.channelId);
    if (!q || message.author.bot || !message.member) return false;
    const text = norm(message.content);
    if (!text || !q.answers.some((a) => text === a || ` ${text} `.includes(` ${a} `))) return false;
    clearTimeout(q.timer);
    quizzes.delete(message.channelId);
    await message.channel.send({ content: `<@${message.author.id}>`, embeds: [embed(0x57f287).setDescription(t(`🎉 Bravo ! La réponse était **${q.reveal}**.\n**+${q.xp} XP** pour toi !`, `🎉 Well done! The answer was **${q.reveal}**.\n**+${q.xp} XP** for you!`))], allowedMentions: { users: [message.author.id] } }).catch(() => {});
    await addXp(message.member, q.xp, message.channel);
    return true;
  }

  H.avatar = (i) => {
    const user = i.options.getUser("membre") || i.user;
    return i.reply({ embeds: [embed().setTitle(user.username).setImage(user.displayAvatarURL({ size: 1024 }))] });
  };
  H.userinfo = async (i) => {
    const user = i.options.getUser("membre") || i.user;
    const member = await i.guild.members.fetch(user.id).catch(() => null);
    const e = embed()
      .setTitle(user.username)
      .setThumbnail(user.displayAvatarURL?.())
      .addFields(
        { name: "ID", value: user.id, inline: true },
        { name: t("Compte créé", "Account created"), value: `<t:${Math.floor(user.createdTimestamp / 1000)}:R>`, inline: true },
        { name: t("A rejoint", "Joined"), value: member?.joinedTimestamp ? `<t:${Math.floor(member.joinedTimestamp / 1000)}:R>` : "—", inline: true },
        { name: t("Niveau", "Level"), value: `${levelOf(db.xp[user.id] || 0).level}`, inline: true },
        { name: t("Avertissements", "Warnings"), value: `${(db.warns[user.id] || []).length}`, inline: true }
      );
    return i.reply({ embeds: [e] });
  };
  H.serverinfo = async (i) => {
    const g = i.guild;
    return i.reply({
      embeds: [
        embed()
          .setTitle(g.name)
          .setThumbnail(g.iconURL?.() || null)
          .addFields(
            { name: t("Membres", "Members"), value: String(g.memberCount), inline: true },
            { name: t("Salons", "Channels"), value: String(g.channels.cache.size), inline: true },
            { name: t("Rôles", "Roles"), value: String(g.roles.cache.size), inline: true },
            { name: t("Créé", "Created"), value: `<t:${Math.floor(g.createdTimestamp / 1000)}:R>`, inline: true },
            { name: t("Propriétaire", "Owner"), value: `<@${g.ownerId}>`, inline: true }
          ),
      ],
    });
  };
  H.ping = (i) => i.reply(`🏓 ${Math.round(client?.ws?.ping ?? 0)} ms`);
  /* ---------- /setup: channels made (and removed) by the bot ---------- */
  // kind: text | readonly | private | privatetext. Every name is created once, remembered, and only those are ever deleted.
  const TEMPLATES = {
    full: [
      { category: t("📌 INFORMATIONS", "📌 INFORMATION"), channels: [
        { key: "rules", name: t("📜│règles", "📜│rules"), kind: "readonly" },
        { key: "news", name: t("📢│annonces", "📢│announcements"), kind: "readonly" },
        { key: "welcome", name: t("👋│bienvenue", "👋│welcome"), kind: "readonly" },
        { key: "goodbye", name: t("🚪│au-revoir", "🚪│goodbye"), kind: "readonly" },
      ] },
      { category: t("💬 COMMUNAUTÉ", "💬 COMMUNITY"), channels: [
        { key: "general", name: t("💬│général", "💬│general"), kind: "text" },
        { key: "media", name: t("🖼️│médias", "🖼️│media"), kind: "text" },
        { key: "commands", name: t("🤖│commandes", "🤖│commands"), kind: "text" },
        { key: "suggestions", name: t("💡│suggestions", "💡│suggestions"), kind: "readonly" },
        { key: "levels", name: t("📈│niveaux", "📈│levels"), kind: "text" },
        { key: "xp", name: t("⭐│xp", "⭐│xp"), kind: "readonly", topic: t("Un message à chaque palier d'XP.", "A message at every XP step.") },
      ] },
      { category: t("🎉 ÉVÉNEMENTS", "🎉 EVENTS"), channels: [
        { key: "giveaways", name: t("🎁│concours", "🎁│giveaways"), kind: "readonly" },
        { key: "polls", name: t("📊│sondages", "📊│polls"), kind: "readonly" },
      ] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [
        { key: "logs", name: t("📋│logs", "📋│logs"), kind: "privatetext" },
        { key: "staff", name: t("🛡️│staff", "🛡️│staff"), kind: "privatetext" },
      ] },
    ],
    brainrot: [
      { category: t("📌 INFORMATIONS", "📌 INFORMATION"), channels: [
        { key: "rules", name: t("📜│règles", "📜│rules"), kind: "readonly", topic: t("Les règles du serveur. Lis-les avant de trader.", "The server rules. Read them before trading.") },
        { key: "news", name: t("📢│annonces", "📢│announcements"), kind: "readonly", topic: t("Les annonces du serveur.", "Server announcements.") },
        { key: "welcome", name: t("👋│bienvenue", "👋│welcome"), kind: "readonly" },
        { key: "goodbye", name: t("🚪│au-revoir", "🚪│goodbye"), kind: "readonly" },
        { key: "scam", name: t("🚨│anti-scam", "🚨│scam-alerts"), kind: "readonly", topic: t("Comment ne pas te faire arnaquer. Utilise toujours un middleman.", "How not to get scammed. Always use a middleman.") },
      ] },
      { category: t("💬 COMMUNAUTÉ", "💬 COMMUNITY"), channels: [
        { key: "general", name: t("💬│général", "💬│general"), kind: "text" },
        { key: "memes", name: t("🧠│brainrot-memes", "🧠│brainrot-memes"), kind: "text", slow: 5 },
        { key: "clips", name: t("🎥│clips-steal", "🎥│steal-clips"), kind: "text", topic: t("Tes meilleurs vols et clips de Steal a Brainrot.", "Your best steals and Steal a Brainrot clips.") },
        { key: "commands", name: t("🤖│commandes", "🤖│commands"), kind: "text" },
        { key: "levels", name: t("📈│niveaux", "📈│levels"), kind: "text" },
        { key: "xp", name: t("⭐│xp", "⭐│xp"), kind: "readonly", topic: t("Un message à chaque palier d'XP.", "A message at every XP step.") },
        { key: "suggestions", name: t("💡│suggestions", "💡│suggestions"), kind: "readonly" },
      ] },
      { category: t("🔄 TRADES", "🔄 TRADES"), channels: [
        { key: "trades", name: t("🤝│trade-brainrot", "🤝│trade-brainrot"), kind: "text", slow: 30, topic: t("Poste ton offre de trade : ce que tu donnes, ce que tu veux. 1 message toutes les 30 s.", "Post your trade offer: what you give, what you want. 1 message every 30 s.") },
        { key: "lookingfor", name: t("🔎│je-cherche", "🔎│looking-for"), kind: "text", slow: 30, topic: t("Tu cherches un brainrot précis ? Demande-le ici.", "Looking for a specific brainrot? Ask here.") },
        { key: "rare", name: t("💎│trades-rares", "💎│rare-trades"), kind: "text", slow: 30, topic: t("Brainrots rares, secrets et mutations.", "Rare brainrots, secrets and mutations.") },
      ] },
      { category: t("🛒 SHOPS", "🛒 SHOPS"), channels: [
        { key: "shopbrainrot", name: t("🛒│shop-brainrot", "🛒│shop-brainrot"), kind: "text", slow: 60, topic: t("Vends tes brainrots : prix, photo, pseudo. 1 message par minute.", "Sell your brainrots: price, picture, username. 1 message per minute.") },
        { key: "shopmutations", name: t("🧬│shop-mutations", "🧬│shop-mutations"), kind: "text", slow: 60, topic: t("Mutations et brainrots spéciaux à vendre.", "Mutations and special brainrots for sale.") },
        { key: "shopitems", name: t("🎁│shop-autres", "🎁│shop-other"), kind: "text", slow: 60, topic: t("Autres objets à vendre.", "Other items for sale.") },
        { key: "prices", name: t("💰│prix-et-valeurs", "💰│prices-and-values"), kind: "text", topic: t("Discute de la valeur des brainrots.", "Talk about brainrot values.") },
      ] },
      { category: t("🛡️ MIDDLEMAN", "🛡️ MIDDLEMAN"), channels: [
        { key: "middleman", name: t("💱│middleman", "💱│middleman"), kind: "readonly", topic: t("Trade sécurisé : ouvre un ticket avec le bouton du panneau.", "Safe trade: open a ticket with the panel button.") },
        { key: "vouches", name: t("⭐│vouches", "⭐│vouches"), kind: "text", slow: 60, topic: t("Laisse un avis après un trade réussi.", "Leave a review after a successful trade.") },
      ] },
      { category: t("🎉 ÉVÉNEMENTS", "🎉 EVENTS"), channels: [
        { key: "giveaways", name: t("🎁│concours", "🎁│giveaways"), kind: "readonly" },
        { key: "polls", name: t("📊│sondages", "📊│polls"), kind: "readonly" },
        { key: "quiz", name: t("🎯│quiz", "🎯│quiz"), kind: "text", topic: t("Tape /8ball ici : une image, une question, de l'XP à gagner.", "Type /8ball here: a picture, a question, XP to win.") },
      ] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [
        { key: "logs", name: t("📋│logs", "📋│logs"), kind: "privatetext" },
        { key: "staff", name: t("🛡️│staff", "🛡️│staff"), kind: "privatetext" },
      ] },
    ],
    minimal: [
      { category: t("💬 SERVEUR", "💬 SERVER"), channels: [
        { key: "welcome", name: t("👋│bienvenue", "👋│welcome"), kind: "readonly" },
        { key: "goodbye", name: t("🚪│au-revoir", "🚪│goodbye"), kind: "readonly" },
        { key: "general", name: t("💬│général", "💬│general"), kind: "text" },
      ] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [{ key: "logs", name: t("📋│logs", "📋│logs"), kind: "privatetext" }] },
    ],
  };

  function overwritesFor(guild, kind, isPrivate) {
    const everyone = guild.roles.everyone.id;
    const me = client?.user?.id;
    const bot = me ? [{ id: me, allow: [P.ViewChannel, P.SendMessages, P.EmbedLinks, P.ManageChannels, P.ReadMessageHistory] }] : [];
    if (isPrivate || kind === "private" || kind === "privatetext") return [{ id: everyone, deny: [P.ViewChannel] }, ...bot];
    if (kind === "readonly") return [{ id: everyone, deny: [P.SendMessages, P.AddReactions] }, ...bot];
    return [];
  }

  /* ---------- /setup voc-create: lots of different voice channels ---------- */
  const nums = (key, emoji, fr, en, count, limit = 0) => Array.from({ length: count }, (_, n) => ({ key: `${key}${n + 1}`, name: `${emoji}│${t(fr, en)} ${n + 1}`, limit }));
  const one = (key, emoji, fr, en, limit = 0) => ({ key, name: `${emoji}│${t(fr, en)}`, limit });
  const hubChannel = () => ({ key: "hub", name: t("➕│Créer ton vocal", "➕│Create your voice"), limit: 0 });
  const VOICE_TEMPLATES = {
    brainrot: [
      { category: t("🔊 ACCUEIL", "🔊 LOBBY"), channels: [hubChannel(), ...nums("gen", "🎙️", "Général", "General", 3), one("lounge", "🛋️", "Lounge", "Lounge")] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [...nums("staff", "🛡️", "Staff", "Staff", 2), one("meeting", "📋", "Réunion", "Meeting"), one("interview", "🧑‍💼", "Entretien", "Interview")] },
      { category: t("🤝 TRADE", "🤝 TRADE"), channels: nums("trade", "🤝", "Trade", "Trade", 3) },
      { category: t("🎮 GAMING", "🎮 GAMING"), channels: [...nums("game", "🎮", "Gaming", "Gaming", 4), one("duo", "👥", "Duo", "Duo", 2), one("trio", "👥", "Trio", "Trio", 3), one("squad", "👥", "Squad", "Squad", 4), one("lfg", "🔎", "Recherche de team", "Looking for team")] },
      { category: t("🆘 SUPPORT", "🆘 SUPPORT"), channels: nums("support", "🆘", "Support", "Support", 2) },
      { category: t("🎵 DÉTENTE", "🎵 CHILL"), channels: [one("music1", "🎵", "Musique 1", "Music 1"), one("music2", "🎵", "Musique 2", "Music 2"), one("chill", "😌", "Chill", "Chill"), one("lofi", "📻", "Lo-fi", "Lo-fi"), one("movie", "🎬", "Film", "Movie"), one("stream", "📺", "Stream", "Stream"), one("karaoke", "🎤", "Karaoké", "Karaoke"), one("study", "📚", "Étude / Travail", "Study / Work")] },
      { category: t("🎉 ÉVÉNEMENTS", "🎉 EVENTS"), channels: [...nums("event", "🎉", "Événement", "Event", 2), one("party", "🥳", "Soirée", "Party")] },
      { category: t("😴 AFK", "😴 AFK"), channels: [one("afk", "😴", "AFK", "AFK")] },
    ],
    full: [
      { category: t("🔊 ACCUEIL", "🔊 LOBBY"), channels: [hubChannel(), ...nums("gen", "🎙️", "Général", "General", 3)] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [one("meeting", "📋", "Réunion", "Meeting"), one("staff", "🛡️", "Staff", "Staff")] },
      { category: t("🎮 GAMING", "🎮 GAMING"), channels: [...nums("game", "🎮", "Gaming", "Gaming", 4), one("duo", "👥", "Duo", "Duo", 2), one("trio", "👥", "Trio", "Trio", 3), one("squad", "👥", "Squad", "Squad", 4)] },
      { category: t("🎵 DÉTENTE", "🎵 CHILL"), channels: [one("music", "🎵", "Musique", "Music"), one("chill", "😌", "Chill", "Chill"), one("movie", "🎬", "Film", "Movie")] },
      { category: t("😴 AFK", "😴 AFK"), channels: [one("afk", "😴", "AFK", "AFK")] },
    ],
    minimal: [
      { category: t("🔊 VOCAUX", "🔊 VOICE"), channels: [hubChannel(), ...nums("gen", "🎙️", "Général", "General", 2)] },
      { category: t("🔒 STAFF", "🔒 STAFF"), private: true, channels: [one("meeting", "📋", "Réunion", "Meeting")] },
    ],
  };

  async function setupVocCreate(i) {
    if (db.setup.voiceItems.length) return reply(i, no(t("Les vocaux ont déjà été créés. Utilise `/setup voc-delete` d'abord.", "The voice channels were already created. Use `/setup voc-delete` first.")));
    await i.deferReply({ flags: ephemeral });
    const key = VOICE_TEMPLATES[i.options.getString("modele")] ? i.options.getString("modele") : "brainrot";
    const guild = i.guild;
    let channelsMade = 0;
    let hubId = "";
    try {
      for (const group of VOICE_TEMPLATES[key]) {
        const category = await guild.channels.create({ name: group.category, type: ChannelType.GuildCategory, permissionOverwrites: overwritesFor(guild, group.private ? "private" : "text", group.private), reason: "voice setup" });
        db.setup.voiceItems.push({ id: category.id, kind: "category" });
        for (const c of group.channels) {
          const channel = await guild.channels.create({ name: c.name, type: ChannelType.GuildVoice, parent: category.id, ...(c.limit ? { userLimit: c.limit } : {}), permissionOverwrites: overwritesFor(guild, "text", group.private), reason: "voice setup" });
          db.setup.voiceItems.push({ id: channel.id, kind: "voice", key: c.key });
          channelsMade++;
          if (c.key === "hub") {
            hubId = channel.id;
            db.voc.hubs.push(channel.id);
          }
        }
      }
    } catch (error) {
      save(true);
      console.error("⚠️ Voice setup error:", error?.message || error);
      return i.editReply(no(t(`Je n'ai créé que ${channelsMade} vocal(aux) : il me faut la permission « Gérer les salons ». Ce qui existe est gardé : \`/setup voc-delete\` le supprime.`, `I only created ${channelsMade} voice channel(s): I need the Manage Channels permission. What exists is kept: \`/setup voc-delete\` removes it.`)));
    }
    save(true);
    const cats = db.setup.voiceItems.filter((x) => x.kind === "category").length;
    return i.editReply(ok(t(`**${channelsMade} vocaux** créés dans ${cats} catégories.${hubId ? `\nEn rejoignant <#${hubId}>, chacun obtient son propre vocal (supprimé quand il est vide).` : ""}\nPour tout enlever : \`/setup voc-delete\`.`, `**${channelsMade} voice channels** created in ${cats} categories.${hubId ? `\nJoining <#${hubId}> gives everyone their own voice room (deleted when empty).` : ""}\nTo remove everything: \`/setup voc-delete\`.`)));
  }
  async function setupVocDeleteButton(i, answer) {
    if (!(i.memberPermissions?.has?.(P.Administrator) || i.member?.permissions?.has?.(P.Administrator))) return reply(i, no(t("Réservé aux administrateurs.", "Administrators only.")));
    if (answer !== "yes") return i.update({ content: t("Annulé.", "Cancelled."), components: [] });
    await i.update({ content: t("⏳ Suppression…", "⏳ Deleting…"), components: [] });
    let removed = 0;
    const ids = new Set(db.setup.voiceItems.map((x) => x.id));
    for (const item of [...db.setup.voiceItems].reverse()) {
      const channel = await i.guild.channels.fetch(item.id).catch(() => null);
      if (channel) {
        try {
          await channel.delete("voice setup delete");
          removed++;
        } catch {
          /* forgotten below */
        }
      }
    }
    db.voc.hubs = db.voc.hubs.filter((h) => !ids.has(h));
    for (const roomId of Object.keys(db.voc.rooms)) { // the personal rooms made from the hub go too
      const room = await i.guild.channels.fetch(roomId).catch(() => null);
      await room?.delete?.("voice setup delete").catch(() => {});
      delete db.voc.rooms[roomId];
    }
    db.setup.voiceItems = [];
    save(true);
    return i.editReply({ content: ok(t(`${removed} vocal(aux) et catégorie(s) supprimé(s).`, `${removed} voice channel(s) and category(ies) deleted.`)), components: [] });
  }

  async function setupCreate(i) {
    if (db.setup.items.length) return reply(i, no(t("Les salons ont déjà été créés. Utilise `/setup delete` d'abord, ou `/setup status`.", "The channels were already created. Use `/setup delete` first, or `/setup status`.")));
    await i.deferReply({ flags: ephemeral });
    const modelKey = TEMPLATES[i.options.getString("modele")] ? i.options.getString("modele") : "brainrot";
    const model = TEMPLATES[modelKey];
    const guild = i.guild;
    const made = {};
    try {
      for (const group of model) {
        const category = await guild.channels.create({ name: group.category, type: ChannelType.GuildCategory, permissionOverwrites: overwritesFor(guild, group.private ? "private" : "text", group.private), reason: "setup" });
        db.setup.items.push({ id: category.id, kind: "category" });
        for (const c of group.channels) {
          const channel = await guild.channels.create({ name: c.name, type: ChannelType.GuildText, parent: category.id, permissionOverwrites: overwritesFor(guild, c.kind, group.private), ...(c.topic ? { topic: c.topic } : {}), ...(c.slow ? { rateLimitPerUser: c.slow } : {}), reason: "setup" });
          db.setup.items.push({ id: channel.id, kind: "text", key: c.key });
          made[c.key] = channel;
        }
      }
    } catch (error) {
      save(true);
      console.error("⚠️ Setup error:", error?.message || error);
      return i.editReply(no(t("Je n'ai pas pu tout créer (il me faut la permission « Gérer les salons »). Ce qui a déjà été créé est gardé : `/setup delete` le supprime.", "I could not create everything (I need the Manage Channels permission). What was created is kept: `/setup delete` removes it.")));
    }
    // wire the new channels to the tools
    if (made.welcome) {
      db.cfg.welcome.channelId = made.welcome.id;
      if (!db.cfg.welcome.message || db.setup.autoWelcome) {
        db.setup.autoWelcome = true; // a text written by the bot, replaced next time; a text typed with /welcome message is never touched
        db.cfg.welcome.message = modelKey === "brainrot"
          ? t("🧠 Bienvenue {user} sur **{server}** ! Trade, achète et vends tes brainrots ici. Lis les règles, et pour un trade sûr passe toujours par le **middleman**. Nous sommes {count} !", "🧠 Welcome {user} to **{server}**! Trade, buy and sell your brainrots here. Read the rules, and for a safe trade always use the **middleman**. We are {count}!")
          : t("Bienvenue {user} sur **{server}** ! Nous sommes {count}.", "Welcome {user} to **{server}**! We are {count}.");
      }
      if (!db.cfg.welcome.leave) db.cfg.welcome.leave = t("{user} a quitté {server}.", "{user} left {server}.");
    }
    if (made.goodbye) {
      db.cfg.welcome.leaveChannelId = made.goodbye.id;
      if (!db.cfg.welcome.leave) db.cfg.welcome.leave = t("{user} a quitté {server}.", "{user} left {server}.");
    }
    if (made.logs) db.cfg.logs.channelId = made.logs.id;
    if (made.vouches) db.cfg.vouch.channelId = made.vouches.id;
    if (made.levels) db.cfg.levels.channelId = made.levels.id;
    if (made.xp) db.cfg.levels.xpChannelId = made.xp.id;
    if (made.suggestions) db.cfg.suggest.channelId = made.suggestions.id;
    if (made.quiz) {
      Object.assign(db.cfg.autoquiz, { on: true, channelId: made.quiz.id, minutes: db.cfg.autoquiz.minutes || 30, nextAt: Date.now() + 60_000 });
    }
    if (made.rules) {
      await made.rules.send({ embeds: [embed().setTitle(t("📜 Règlement", "📜 Rules")).setDescription(t("1. Respecte tout le monde.\n2. Pas de spam ni de pub.\n3. Pas de contenu choquant.\n4. Écoute le staff.\n\n*Modifie ce message comme tu veux.*", "1. Respect everyone.\n2. No spam or ads.\n3. No shocking content.\n4. Listen to the staff.\n\n*Edit this message as you like.*"))] }).catch(() => {});
    }
    let levelRolesNote = "";
    if (modelKey !== "minimal" && !db.setup.levelRoles.length) {
      try {
        const n = await createLevelRoles(guild);
        levelRolesNote = t(`\n🏅 ${n} rôles de niveau créés (donnés automatiquement).`, `\n🏅 ${n} level roles created (given automatically).`);
      } catch (error) {
        save(true);
        console.error("⚠️ Level roles error:", error?.message || error);
        levelRolesNote = t("\n⚠️ Rôles de niveau non créés (il faut la permission « Gérer les rôles »). Essaie `/levels roles-create` ensuite.", "\n⚠️ Level roles not created (the Manage Roles permission is needed). Try `/levels roles-create` afterwards.");
      }
    }
    if (modelKey === "brainrot") {
      if (made.rules) {
        await made.rules.send({ embeds: [embed(0xf1c40f).setTitle(t("📜 Règlement : Steal a Brainrot", "📜 Rules: Steal a Brainrot")).setDescription(t(
          "1. Respecte tout le monde, pas d'insultes.\n2. **Tout trade de valeur passe par un middleman** (salon 💱│middleman).\n3. Pas de spam, pas de pub, pas de liens suspects.\n4. Ne donne **jamais** ton mot de passe ou ton code Roblox.\n5. Poste ton offre dans le bon salon (trade, shop, je-cherche).\n6. Les arnaques mènent à un bannissement définitif.\n7. Écoute le staff.\n\n*Modifie ce message comme tu veux.*",
          "1. Respect everyone, no insults.\n2. **Every valuable trade goes through a middleman** (💱│middleman channel).\n3. No spam, no ads, no suspicious links.\n4. **Never** give your Roblox password or code.\n5. Post your offer in the right channel (trade, shop, looking-for).\n6. Scams mean a permanent ban.\n7. Listen to the staff.\n\n*Edit this message as you like.*"))] }).catch(() => {});
      }
      if (made.scam) {
        await made.scam.send({ embeds: [embed(0xed4245).setTitle(t("🚨 Évite les arnaques", "🚨 Avoid scams")).setDescription(t(
          "• Personne ne te donne de brainrot gratuit : méfie-toi des « deals trop beaux ».\n• Ne trade **jamais** hors du middleman pour un objet de valeur.\n• Vérifie toujours le pseudo : les faux comptes copient les vrais.\n• Ne clique pas sur les liens inconnus et ne scanne aucun code.\n• Un doute ? Ouvre un ticket middleman ou préviens le staff.",
          "• Nobody gives free brainrots: be careful with « too good to be true » deals.\n• **Never** trade valuable items outside the middleman.\n• Always check the username: fake accounts copy real ones.\n• Do not click unknown links or scan any code.\n• In doubt? Open a middleman ticket or tell the staff."))] }).catch(() => {});
      }
      if (made.middleman) {
        await made.middleman.send({ embeds: [embed(0x5865f2).setTitle(t("💱 Middleman", "💱 Middleman")).setDescription(t(
          "Trade sécurisé : le middleman garde l'argent ou les LTC jusqu'à ce que tout soit livré.\n\n**Les administrateurs** : tape `/panel` ici pour poster le panneau Litecoin, puis `/panel` avec le type PayPal pour le panneau PayPal.",
          "Safe trade: the middleman holds the money or LTC until everything is delivered.\n\n**Administrators**: type `/panel` here to post the Litecoin panel, then `/panel` with the PayPal type for the PayPal panel."))] }).catch(() => {});
      }
    }
    save(true);
    const list = db.setup.items.filter((x) => x.kind === "text").map((x) => `<#${x.id}>`).join(" ");
    return i.editReply(ok(t(`Salons créés : ${list}\nLa bienvenue, les logs, les niveaux et les suggestions sont déjà branchés.${made.middleman ? ` Va dans <#${made.middleman.id}> et tape \`/panel\` pour poster le middleman.` : ""} Pour tout enlever : \`/setup delete\`.${levelRolesNote}`, `Channels created: ${list}\nWelcome, logs and suggestions are already connected. To remove everything: \`/setup delete\`.${levelRolesNote}`)));
  }

  H.setup = async (i) => {
    if (need_perm(i, P.Administrator)) return;
    const sub = i.options.getSubcommand();
    if (sub === "create") return setupCreate(i);
    if (sub === "voc-create") return setupVocCreate(i);
    if (sub === "voc-delete") {
      if (!db.setup.voiceItems.length) return reply(i, no(t("Le bot n'a créé aucun vocal.", "The bot created no voice channels.")));
      const row = new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId("tl:setup:vyes").setLabel(t("Oui, tout supprimer", "Yes, delete everything")).setEmoji("🗑️").setStyle(ButtonStyle.Danger),
        new ButtonBuilder().setCustomId("tl:setup:vno").setLabel(t("Annuler", "Cancel")).setStyle(ButtonStyle.Secondary)
      );
      return i.reply({ flags: ephemeral, content: t(`⚠️ Je vais supprimer **${db.setup.voiceItems.length}** vocal(aux)/catégorie(s) créés par moi, et les vocaux perso en cours. Seulement ceux-là, rien d'autre. C'est irréversible.`, `⚠️ I will delete **${db.setup.voiceItems.length}** voice channel(s)/category(ies) I created, and the personal rooms in use. Only those, nothing else. This cannot be undone.`), components: [row] });
    }
    if (sub === "status") {
      const list = db.setup.items.filter((x) => x.kind === "text").map((x) => `<#${x.id}>`).join(" ");
      const voices = db.setup.voiceItems.filter((x) => x.kind === "voice").length;
      const parts = [list ? t(`Salons créés par le bot : ${list}`, `Channels created by the bot: ${list}`) : t("Salons : aucun.", "Channels: none."), voices ? t(`Vocaux créés par le bot : ${voices}`, `Voice channels created by the bot: ${voices}`) : t("Vocaux : aucun.", "Voice channels: none.")];
      return reply(i, parts.join("\n"));
    }
    if (sub === "delete") {
      if (!db.setup.items.length && !db.setup.levelRoles.length) return reply(i, no(t("Le bot n'a créé aucun salon.", "The bot created no channels.")));
      const row = new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId("tl:setup:yes").setLabel(t("Oui, tout supprimer", "Yes, delete everything")).setEmoji("🗑️").setStyle(ButtonStyle.Danger),
        new ButtonBuilder().setCustomId("tl:setup:no").setLabel(t("Annuler", "Cancel")).setStyle(ButtonStyle.Secondary)
      );
      return i.reply({
        flags: ephemeral,
        content: t(`⚠️ Je vais supprimer **${db.setup.items.length}** salon(s)/catégorie(s) et **${db.setup.levelRoles.length}** rôle(s) de niveau créés par moi. Seulement ceux-là, rien d'autre. C'est irréversible.`, `⚠️ I will delete **${db.setup.items.length}** channel(s)/category(ies) and **${db.setup.levelRoles.length}** level role(s) I created. Only those, nothing else. This cannot be undone.`),
        components: [row],
      });
    }
  };
  async function setupDeleteButton(i, answer) {
    if (!(i.memberPermissions?.has?.(P.Administrator) || i.member?.permissions?.has?.(P.Administrator))) return reply(i, no(t("Réservé aux administrateurs.", "Administrators only.")));
    if (answer !== "yes") return i.update({ content: t("Annulé.", "Cancelled."), components: [] });
    await i.update({ content: t("⏳ Suppression…", "⏳ Deleting…"), components: [] });
    let removed = 0;
    const ids = new Set(db.setup.items.map((x) => x.id));
    for (const item of [...db.setup.items].reverse()) {
      const channel = await i.guild.channels.fetch(item.id).catch(() => null);
      if (channel) {
        try {
          await channel.delete("setup delete");
          removed++;
        } catch {
          /* kept in the list below */
        }
      }
    }
    // forget the settings that pointed to a removed channel
    if (ids.has(db.cfg.welcome.channelId)) db.cfg.welcome.channelId = "";
    if (ids.has(db.cfg.welcome.leaveChannelId)) db.cfg.welcome.leaveChannelId = "";
    if (ids.has(db.cfg.vouch.channelId)) db.cfg.vouch.channelId = "";
    if (ids.has(db.cfg.logs.channelId)) db.cfg.logs.channelId = "";
    if (ids.has(db.cfg.suggest.channelId)) db.cfg.suggest.channelId = "";
    if (ids.has(db.cfg.levels.channelId)) db.cfg.levels.channelId = "";
    if (ids.has(db.cfg.levels.xpChannelId)) db.cfg.levels.xpChannelId = "";
    if (ids.has(db.cfg.autoquiz.channelId)) Object.assign(db.cfg.autoquiz, { on: false, channelId: "", nextAt: 0 });
    db.cfg.levels.ignored = db.cfg.levels.ignored.filter((c) => !ids.has(c));
    db.setup.items = [];
    const rolesRemoved = db.setup.levelRoles.length ? await removeLevelRoles(i.guild) : 0;
    save(true);
    return i.editReply({ content: ok(t(`${removed} salon(s) et catégorie(s) supprimé(s)${rolesRemoved ? `, ${rolesRemoved} rôle(s) de niveau` : ""}.`, `${removed} channel(s) and category(ies) deleted${rolesRemoved ? `, ${rolesRemoved} level role(s)` : ""}.`)), components: [] });
  }

  /* /help lists only the commands the person can use (the others are hidden from them in Discord too). */
  H.help = (i) => {
    const can = (flag) => !flag || Boolean(i.memberPermissions?.has?.(flag));
    const sections = [
      [t("📈 Niveaux", "📈 Levels"), "`/rank` `/leaderboard` `/quiz`"],
      [t("📈 Niveaux (staff)", "📈 Levels (staff)"), "`/levels` `/xp` `/autoquiz`", P.ManageGuild],
      [t("⭐ Vouches", "⭐ Vouches"), t("`/vouch` · le classement est dans le panel Top vouches", "`/vouch` · the ranking is in the Top vouches panel")],
      [t("⭐ Vouches (staff)", "⭐ Vouches (staff)"), "`/vouchadmin panel` `/vouchadmin salon` `/vouchadmin retirer` `/vouchadmin reset`", P.ManageGuild],
      [t("🎉 Fun et outils", "🎉 Fun and tools"), "`/poll` `/suggest` `/8ball` `/coinflip` `/dice` `/avatar` `/userinfo` `/serverinfo` `/ping`"],
      [t("🔊 Ton vocal", "🔊 Your voice channel"), t("Rejoins « ➕ Créer ton vocal » : les boutons pour le gérer sont dans le chat du vocal", "Join \"➕ Create your voice\": the buttons to manage it are in the room's chat")],
      [t("🔨 Bannir", "🔨 Ban"), "`/ban` `/unban`", P.BanMembers],
      [t("🔨 Expulser", "🔨 Kick"), "`/kick`", P.KickMembers],
      [t("🔨 Sanctions", "🔨 Sanctions"), "`/timeout` `/untimeout` `/warn` `/warnings` `/clearwarns`", P.ModerateMembers],
      [t("🧹 Messages", "🧹 Messages"), "`/clear`", P.ManageMessages],
      [t("🔒 Salons", "🔒 Channels"), "`/lock` `/unlock` `/vocadmin create` `/vocadmin hub`", P.ManageChannels],
      [t("🎭 Rôles", "🎭 Roles"), "`/rolepanel`", P.ManageRoles],
      [t("⚙️ Réglages", "⚙️ Settings"), "`/welcome` `/giveaway` `/suggestions` `/logs` `/security` `/ticketpanel` `/apps`", P.ManageGuild],
      [t("💳 PayPal (staff)", "💳 PayPal (staff)"), "`/paypal`", P.ManageMessages],
      [t("👑 Admin", "👑 Admin"), "`/setup` `/panel` `/access` `/tiers`", P.Administrator],
    ];
    return i.reply({
      flags: ephemeral,
      embeds: [embed().setTitle(t("🧰 Tes commandes", "🧰 Your commands")).addFields(sections.filter((x) => can(x[2])).map(([name, value]) => ({ name, value })))],
    });
  };

  /* logs and security settings */
  H.logs = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    if (i.options.getSubcommand() === "off") db.cfg.logs.channelId = "";
    else db.cfg.logs.channelId = i.channelId;
    save();
    return reply(i, ok(db.cfg.logs.channelId ? t("Les logs arriveront ici.", "Logs will go here.") : t("Logs coupés.", "Logs off.")));
  };
  H.security = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const s = db.cfg.security;
    const sub = i.options.getSubcommand();
    if (sub === "antispam") s.antiSpam = i.options.getBoolean("actif");
    if (sub === "antiraid") s.antiRaid = i.options.getBoolean("actif");
    if (sub === "antilink") s.antiLink = i.options.getString("mode");
    save();
    const onOff = (v) => (v ? "✅" : "❌");
    return reply(
      i,
      `🛡️ ${t("Anti-spam", "Anti-spam")} ${onOff(s.antiSpam)}  ·  ${t("Anti-liens", "Anti-links")} **${s.antiLink}**  ·  ${t("Anti-raid", "Anti-raid")} ${onOff(s.antiRaid)}\n${t("Les modérateurs (Gérer les messages) ne sont jamais touchés.", "Moderators (Manage Messages) are never affected.")}`
    );
  };

  /* ---------- message protection ---------- */
  const spam = new Map();
  const INVITE = /(discord\.gg|discord(?:app)?\.com\/invite)\/[\w-]+/i;
  const ANY_LINK = /https?:\/\/\S+/i;
  async function protect(message) {
    const s = db.cfg.security;
    if (message.author.bot || !message.guild || !message.member) return false;
    if (message.member.permissions?.has?.(P.ManageMessages)) return false;
    if (s.antiLink !== "off") {
      const hit = s.antiLink === "all" ? ANY_LINK.test(message.content) : INVITE.test(message.content);
      if (hit) {
        await message.delete().catch(() => {});
        const warning = await message.channel.send({ content: t(`🔗 ${message.author}, les liens ne sont pas autorisés ici.`, `🔗 ${message.author}, links are not allowed here.`), allowedMentions: { users: [message.author.id] } }).catch(() => null);
        if (warning) setTimeout(() => warning.delete().catch(() => {}), 6000);
        await log(message.guild, `🔗 **Anti-link** ${message.author} <#${message.channelId}>\n${String(message.content).slice(0, 300)}`, 0xe67e22);
        return true;
      }
    }
    if (s.antiSpam) {
      const now = Date.now();
      const list = (spam.get(message.author.id) || []).filter((x) => now - x < 5000);
      list.push(now);
      spam.set(message.author.id, list);
      if (list.length >= 5) {
        spam.delete(message.author.id);
        await message.member.timeout(300_000, "anti-spam").catch(() => {});
        await message.channel.send({ content: t(`🔇 ${message.author} est en sourdine 5 min (spam).`, `🔇 ${message.author} is timed out for 5 min (spam).`), allowedMentions: { users: [message.author.id] } }).catch(() => {});
        await log(message.guild, `🔇 **Anti-spam** ${message.author} <#${message.channelId}>`, 0xe67e22);
        return true;
      }
    }
    return false;
  }

  /* ---------- application tickets: become a middleman, or ask for access to the OG channels ---------- */
  const appStaff = (member) => Boolean(member?.permissions?.has?.(P.Administrator) || member?.permissions?.has?.(P.ManageGuild) || (db.cfg.apps.staffRoleId && member?.roles?.cache?.has?.(db.cfg.apps.staffRoleId)));
  const APP_KINDS = {
    mm: {
      color: 0x19c7a0,
      title: () => t("🛡️  Candidature middleman", "🛡️  Middleman application"),
      modal: () => t("Devenir middleman", "Become a middleman"),
      inputs: () => [
        ["experience", t("Ton expérience comme middleman", "Your experience as a middleman"), TextInputStyle.Paragraph, true, 600],
        ["deals", t("Nombre de deals / vouches (avec preuves)", "Number of deals / vouches (with proof)"), TextInputStyle.Paragraph, true, 600],
        ["availability", t("Tes disponibilités et ton fuseau horaire", "Your availability and time zone"), TextInputStyle.Short, true, 200],
        ["why", t("Pourquoi toi ?", "Why you?"), TextInputStyle.Paragraph, false, 500],
      ],
      channelName: (name) => `mm-candidature-${name}`,
    },
    trade: {
      color: 0xf1c40f,
      title: () => t("💎  Demande d'accès : Trade OG", "💎  Access request: Trade OG"),
      modal: () => t("Accès Trade OG", "Trade OG access"),
      inputs: () => [
        ["why", t("Pourquoi veux-tu l'accès à Trade OG ?", "Why do you want access to Trade OG?"), TextInputStyle.Paragraph, true, 600],
        ["proof", t("Preuves (vouches, liens, captures)", "Proof (vouches, links, screenshots)"), TextInputStyle.Paragraph, true, 600],
      ],
      channelName: (name) => `acces-trade-${name}`,
    },
    claim: {
      color: 0xe67e22,
      title: () => t(`🎁  Réclamer ${db.cfg.apps.claim.reward}`, `🎁  Claim ${db.cfg.apps.claim.reward}`),
      modal: () => t(`Réclamer ${db.cfg.apps.claim.reward}`, `Claim ${db.cfg.apps.claim.reward}`),
      inputs: () => [["roblox", t("Ton pseudo Roblox", "Your Roblox username"), TextInputStyle.Short, true, 60]],
      channelName: (name) => `reclame-${String(db.cfg.apps.claim.reward).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 20) || "brainrot"}-${name}`,
    },
    shop: {
      color: 0x9b59b6,
      title: () => t("🛍️  Demande d'accès : Shop OG", "🛍️  Access request: Shop OG"),
      modal: () => t("Accès Shop OG", "Shop OG access"),
      inputs: () => [
        ["why", t("Pourquoi veux-tu l'accès à Shop OG ?", "Why do you want access to Shop OG?"), TextInputStyle.Paragraph, true, 600],
        ["proof", t("Preuves (vouches, liens, captures)", "Proof (vouches, links, screenshots)"), TextInputStyle.Paragraph, true, 600],
      ],
      channelName: (name) => `acces-shop-${name}`,
    },
  };
  /* "" when the person may claim, otherwise the refusal. The xp is not spent, but each person claims once. */
  function claimGate(userId) {
    const c = db.cfg.apps.claim;
    const xp = db.xp[userId] || 0;
    if (db.claims[userId]?.status === "accepted") return no(t(`Tu as déjà réclamé **${c.reward}**. Une seule réclamation par personne.`, `You already claimed **${c.reward}**. One claim per person.`));
    if (xp < c.xp) {
      return no(t(`Il te faut **${c.xp} XP** pour réclamer **${c.reward}**.\nTu as **${xp} XP** (il t'en manque **${c.xp - xp}**).\n${bar(xp, c.xp, 14)}  ${Math.floor((xp / c.xp) * 100)} %\n\n💬 Parle dans le chat et 🎙️ reste en vocal avec d'autres membres pour gagner de l'XP : sois actif !`, `You need **${c.xp} XP** to claim **${c.reward}**.\nYou have **${xp} XP** (**${c.xp - xp}** missing).\n${bar(xp, c.xp, 14)}  ${Math.floor((xp / c.xp) * 100)}%\n\n💬 Talk in the chat and 🎙️ stay in voice with other members to earn XP: be active!`));
    }
    return "";
  }
  const appRow = (...buttons) => new ActionRowBuilder().addComponents(buttons);
  const appButton = (id, label, style, emoji) => new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style).setEmoji(emoji);
  const appTicketOf = (channel) => {
    const m = String(channel?.topic || "").match(/^app-ticket:(\w+):(mm|trade|shop|claim)$/);
    return m ? { userId: m[1], kind: m[2] } : null;
  };

  /* The panels people click to open a ticket. */
  H.ticketpanel = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const type = i.options.getString("type");
    const access = db.cfg.apps.access;
    const embedFor = {
      middleman: () =>
        embed(0x19c7a0)
          .setTitle(t("🛡️  Devenir middleman", "🛡️  Become a middleman"))
          .setDescription(t("Tu veux rejoindre l'équipe middleman ? Dépose ta candidature : le staff la lit et te répond dans ton ticket.\n\n**À préparer :** ton expérience, tes deals ou vouches avec preuves, tes disponibilités.", "Do you want to join the middleman team? Send your application: staff reads it and answers in your ticket.\n\n**Get ready:** your experience, your deals or vouches with proof, your availability."))
          .addFields({ name: t("1️⃣  Postule", "1️⃣  Apply"), value: t("Appuie sur le bouton et remplis le formulaire.", "Press the button and fill in the form."), inline: true }, { name: t("2️⃣  Le staff étudie", "2️⃣  Staff reviews"), value: t("Tu reçois la décision dans le ticket.", "You get the decision in the ticket."), inline: true }, { name: t("3️⃣  Bienvenue", "3️⃣  Welcome"), value: t("Si tu es accepté, tu reçois le rôle middleman.", "If accepted, you get the middleman role."), inline: true })
          .setImage("attachment://apps-middleman.png"),
      crosstrade: () =>
        embed(0x19c7a0)
          .setTitle(t("🔁  Cross-trade", "🔁  Cross-trade"))
          .setDescription(t("Échange un objet contre un autre **sans risque** : un **middleman** reçoit les deux objets, vérifie, puis remet chacun à l'autre.", "Swap one item for another **safely**: a **middleman** receives both items, checks them, then hands each one to the other person."))
          .addFields(
            { name: t("1️⃣  Ouvre", "1️⃣  Open"), value: t("Ouvre un ticket et ajoute l'autre personne.", "Open a ticket and add the other person."), inline: true },
            { name: t("2️⃣  Offres", "2️⃣  Offers"), value: t("Chacun écrit son offre, puis confirme.", "Each person writes their offer, then confirms."), inline: true },
            { name: t("3️⃣  Middleman", "3️⃣  Middleman"), value: t("Il prend le ticket, reçoit les objets, les remet.", "He takes the ticket, receives the items, hands them over."), inline: true },
            { name: t("🚨  Anti-arnaque", "🚨  Anti-scam"), value: t("Ne donne **rien** avant que le middleman soit **annoncé dans le ticket**, et jamais en dehors du ticket.", "Give **nothing** before the middleman is **announced in the ticket**, and never outside the ticket."), inline: false }
          )
          .setFooter({ text: t(`${db.crossStats.done} cross-trade(s) terminé(s)`, `${db.crossStats.done} cross-trade(s) completed`) })
          .setImage("attachment://apps-crosstrade.png"),
      claim: () => {
        const c = db.cfg.apps.claim;
        const lv = db.cfg.levels;
        return embed(0xe67e22)
          .setTitle(t(`🎁  Réclame ${c.reward}`, `🎁  Claim ${c.reward}`))
          .setDescription(t(`Tu as **${c.xp} XP** ? Tu peux réclamer le brainrot **${c.reward}** en ouvrant un ticket. Sans assez d'XP, le ticket est refusé.\nUne seule réclamation par personne.`, `Do you have **${c.xp} XP**? You can claim the **${c.reward}** brainrot by opening a ticket. Without enough XP the ticket is refused.\nOne claim per person.`))
          .addFields(
            { name: t("💬  Chat", "💬  Chat"), value: t("Parle dans le chat : de l'XP à chaque message (1 par minute).", "Talk in the chat: XP for every message (one per minute)."), inline: true },
            { name: t("🎙️  Vocal", "🎙️  Voice"), value: lv.voiceOn && lv.voiceXp > 0 ? t(`Reste en vocal avec d'autres membres : **${lv.voiceXp} XP par minute**.`, `Stay in voice with other members: **${lv.voiceXp} XP per minute**.`) : t("Pas d'XP en vocal pour le moment.", "No voice XP for now."), inline: true },
            { name: t("🧭  Sois actif", "🧭  Be active"), value: t("Seuls ceux qui restent vraiment actifs gagnent : seul dans un vocal ou en sourdine, rien.", "Only people who really stay active earn: alone in a voice channel or deafened earns nothing."), inline: false }
          )
          .setImage("attachment://apps-claim.png");
      },
      access: () =>
        embed(0xf1c40f)
          .setTitle(t("🔑  Accès aux salons OG", "🔑  OG channel access"))
          .setDescription(t("Tu veux accéder à un salon réservé ? Ouvre un ticket pour le salon voulu : le staff vérifie ta demande et t'ouvre l'accès.", "Want access to a restricted channel? Open a ticket for the channel you want: staff checks your request and opens it for you."))
          .addFields({ name: `💎  ${access.trade.label}`, value: t("Trade des objets rares entre membres de confiance.", "Trade rare items between trusted members."), inline: true }, { name: `🛍️  ${access.shop.label}`, value: t("Vends et achète dans le shop réservé.", "Sell and buy in the restricted shop."), inline: true })
          .setImage("attachment://apps-access.png"),
    };
    const banners = { middleman: ["MIDDLEMAN APPLICATION", "#0b4d3c", "#19c7a0", "apps-middleman.png"], access: ["OG ACCESS", "#5a3a08", "#c9871f", "apps-access.png"], claim: [`${String(db.cfg.apps.claim.reward).toUpperCase()} REWARD`, "#5a2a08", "#e08a1e", "apps-claim.png"], crosstrade: ["CROSS-TRADE", "#0b4d3c", "#19c7a0", "apps-crosstrade.png"] }[type];
    const file = new AttachmentBuilder(gfx.banner("KAZUKI MM", banners[0], banners[1], banners[2], type === "crosstrade" ? "swap" : undefined), { name: banners[3] });
    const row =
      type === "middleman"
        ? appRow(appButton("ap:open:mm", t("Postuler comme middleman", "Apply as a middleman"), ButtonStyle.Success, "📝"))
        : type === "crosstrade"
          ? appRow(appButton("ct:open", t("Ouvrir un cross-trade", "Open a cross-trade"), ButtonStyle.Success, "🔁"))
          : type === "claim"
          ? appRow(appButton("ap:open:claim", t(`Réclamer ${db.cfg.apps.claim.reward}`, `Claim ${db.cfg.apps.claim.reward}`), ButtonStyle.Success, "🎁"), appButton("ap:myxp", t("Mon XP", "My XP"), ButtonStyle.Secondary, "📊"))
          : appRow(appButton("ap:open:trade", access.trade.label, ButtonStyle.Primary, "💎"), appButton("ap:open:shop", access.shop.label, ButtonStyle.Primary, "🛍️"));
    await i.channel.send({ embeds: [embedFor[type]()], components: [row], files: [file] });
    return reply(i, ok(t("Panneau posté.", "Panel posted.")));
  };

  /* /apps: who handles the tickets, which role / channels they give. */
  H.apps = async (i) => {
    if (need_perm(i, P.ManageGuild)) return;
    const a = db.cfg.apps;
    const sub = i.options.getSubcommand();
    if (sub === "staff" || sub === "mmrole") {
      const role = i.options.getRole("role");
      a[sub === "staff" ? "staffRoleId" : "mmRoleId"] = role?.id || "";
      save();
      if (sub === "staff") return reply(i, ok(role ? t(`${role} voit et traite maintenant ces tickets.`, `${role} now sees and handles these tickets.`) : t("Plus de rôle staff : seuls les administrateurs les traitent.", "No staff role: only administrators handle them.")));
      return reply(i, ok(role ? t(`${role} sera donné aux candidatures middleman acceptées.`, `${role} will be given to accepted middleman applications.`) : t("Aucun rôle donné automatiquement : le staff le donne à la main.", "No role given automatically: staff gives it by hand.")));
    }
    if (sub === "category") {
      const cat = i.options.getChannel("categorie");
      a.categoryId = cat?.id || "";
      save();
      return reply(i, ok(cat ? t(`Les tickets seront créés dans ${cat}.`, `Tickets will be created in ${cat}.`) : t("Les tickets seront créés sans catégorie.", "Tickets will be created with no category.")));
    }
    if (sub === "access") {
      const kind = i.options.getString("type");
      const role = i.options.getRole("role");
      const channel = i.options.getChannel("salon");
      if (!role && !channel) return reply(i, no(t("Choisis un rôle, un salon, ou les deux.", "Pick a role, a channel, or both.")));
      if (role) a.access[kind].roleId = role.id;
      if (channel) a.access[kind].channelId = channel.id;
      save();
      const bits = [role ? t(`donne maintenant ${role}`, `now gives ${role}`) : "", channel ? t(`affiche ${channel}`, `shows ${channel}`) : ""].filter(Boolean).join(t(" et ", " and "));
      return reply(i, ok(`${a.access[kind].label} ${bits}.`));
    }
    if (sub === "claim") {
      const xp = i.options.getInteger("xp");
      const reward = i.options.getString("recompense")?.trim();
      if (xp) a.claim.xp = xp;
      if (reward) a.claim.reward = reward;
      save();
      return reply(i, ok(t(`Réclamation : **${a.claim.reward}** à partir de **${a.claim.xp} XP**.`, `Claim: **${a.claim.reward}** from **${a.claim.xp} XP**.`)));
    }
    if (sub === "claimreset") {
      const user = i.options.getUser("membre");
      const had = Boolean(db.claims[user.id]);
      delete db.claims[user.id];
      save(true);
      return reply(i, had ? ok(t(`${user.username} peut réclamer à nouveau.`, `${user.username} can claim again.`)) : no(t(`${user.username} n'a aucune réclamation.`, `${user.username} has no claim.`)));
    }
    if (sub === "revoke") {
      const user = i.options.getUser("membre");
      const kind = i.options.getString("type");
      const roleId = a.access[kind].roleId;
      const channel = roleId ? null : await i.guild.channels.fetch(a.access[kind].channelId).catch(() => null);
      const person = roleId ? await i.guild.members.fetch(user.id).catch(() => null) : null;
      if (roleId && !person) return reply(i, no(t("Cette personne n'est pas sur le serveur.", "This person is not on the server.")));
      if (!roleId && !channel?.permissionOverwrites) return reply(i, no(t("Salon introuvable : vérifie-le avec `/apps access`.", "Channel not found: check it with `/apps access`.")));
      try {
        if (roleId) await person.roles.remove(roleId, `revoke by ${i.user.username}`);
        else await channel.permissionOverwrites.delete(user.id, `revoke by ${i.user.username}`);
      } catch {
        return reply(i, no(t("Je n'ai pas pu retirer l'accès (il me faut « Gérer les rôles », et mon rôle doit être au-dessus).", "I could not take the access away (I need Manage Roles, and my role must be above).")));
      }
      await log(i.guild, `🔒 **${a.access[kind].label}** ${t("retiré à", "removed from")} ${user}  ·  ${t("par", "by")} <@${i.user.id}>`, 0xe67e22);
      return reply(i, ok(t(`Accès ${a.access[kind].label} retiré à ${user.username}.`, `${a.access[kind].label} access removed from ${user.username}.`)));
    }
    const line = (label, id, mention) => `${label} ${id ? mention(id) : t("*non réglé*", "*not set*")}`;
    return i.reply({
      flags: ephemeral,
      allowedMentions: { parse: [] },
      embeds: [
        embed(0x5865f2)
          .setTitle(t("🎫  Tickets de candidature et d'accès", "🎫  Application and access tickets"))
          .setDescription(
            [
              line(t("**Rôle staff :**", "**Staff role:**"), a.staffRoleId, (id) => `<@&${id}>`),
              line(t("**Rôle middleman donné :**", "**Middleman role given:**"), a.mmRoleId, (id) => `<@&${id}>`),
              line(t("**Catégorie des tickets :**", "**Tickets category:**"), a.categoryId, (id) => `<#${id}>`),
              t(`**Réclamation :** ${a.claim.reward} à ${a.claim.xp} XP`, `**Claim:** ${a.claim.reward} at ${a.claim.xp} XP`),
              line(t(`**${a.access.trade.label} : rôle**`, `**${a.access.trade.label}: role**`), a.access.trade.roleId, (id) => `<@&${id}>`) + (a.access.trade.channelId ? `  ·  <#${a.access.trade.channelId}>` : ""),
              line(t(`**${a.access.shop.label} : rôle**`, `**${a.access.shop.label}: role**`), a.access.shop.roleId, (id) => `<@&${id}>`) + (a.access.shop.channelId ? `  ·  <#${a.access.shop.channelId}>` : ""),
            ].join("\n")
          ),
      ],
    });
  };

  /* "My XP": where the person stands against the XP needed to claim. */
  async function appMyXp(i) {
    const c = db.cfg.apps.claim;
    const xp = db.xp[i.user.id] || 0;
    const l = levelOf(xp);
    const ready = xp >= c.xp;
    return i.reply({
      flags: ephemeral,
      embeds: [
        embed(ready ? 0x57f287 : 0xe67e22)
          .setTitle(t("📊  Ton XP", "📊  Your XP"))
          .setDescription(`**${xp} / ${c.xp} XP**\n${bar(Math.min(xp, c.xp), c.xp, 16)}  ${Math.min(100, Math.floor((xp / c.xp) * 100))}${FR ? " %" : "%"}\n${t("Niveau", "Level")} **${l.level}**\n\n${ready ? t(`✅ Tu peux réclamer **${c.reward}** !`, `✅ You can claim **${c.reward}**!`) : t(`Il t'en manque **${c.xp - xp} XP** pour **${c.reward}**. 💬 Chat et 🎙️ vocal = de l'XP.`, `**${c.xp - xp} XP** to go for **${c.reward}**. 💬 Chat and 🎙️ voice = XP.`)}`),
      ],
    });
  }

  /* A button of a panel: show the form. */
  async function appOpen(i, kind) {
    const k = APP_KINDS[kind];
    if (!k) return;
    const existing = [...(i.guild.channels.cache?.values?.() || [])].find((c) => String(c.topic || "").startsWith(`app-ticket:${i.user.id}:${kind}`));
    if (existing) return reply(i, no(t(`Tu as déjà un ticket ouvert : ${existing}`, `You already have an open ticket: ${existing}`)));
    if (kind === "claim") {
      const refusal = claimGate(i.user.id);
      if (refusal) return reply(i, refusal);
    } else if (kind !== "mm" && !db.cfg.apps.access[kind]?.roleId && !db.cfg.apps.access[kind]?.channelId) return reply(i, no(t("Cette demande n'est pas encore réglée. Préviens le staff.", "This request is not set up yet. Tell the staff.")));
    const modal = new ModalBuilder().setCustomId(`ap:m:${kind}`).setTitle(k.modal().slice(0, 45));
    for (const [id, label, style, required, max] of k.inputs()) modal.addComponents(new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId(id).setLabel(label.slice(0, 45)).setStyle(style).setRequired(required).setMaxLength(max)));
    return i.showModal(modal);
  }

  /* The form is sent: create the private ticket with the answers and the staff buttons. */
  async function appSubmit(i, kind) {
    const k = APP_KINDS[kind];
    if (!k) return;
    await i.deferReply({ flags: ephemeral });
    const guild = i.guild;
    const existing = [...(guild.channels.cache?.values?.() || [])].find((c) => String(c.topic || "").startsWith(`app-ticket:${i.user.id}:${kind}`));
    if (existing) return i.editReply(no(t(`Tu as déjà un ticket ouvert : ${existing}`, `You already have an open ticket: ${existing}`)));
    if (kind === "claim") {
      const refusal = claimGate(i.user.id);
      if (refusal) return i.editReply(refusal);
    }
    const a = db.cfg.apps;
    const allow = [P.ViewChannel, P.SendMessages, P.ReadMessageHistory, P.AttachFiles];
    const overwrites = [{ id: guild.roles.everyone.id, deny: [P.ViewChannel] }, { id: i.user.id, allow }];
    if (client?.user?.id) overwrites.push({ id: client.user.id, allow: [...allow, P.EmbedLinks, P.ManageChannels, P.ManageRoles] });
    if (a.staffRoleId && guild.roles.cache?.get?.(a.staffRoleId)) overwrites.push({ id: a.staffRoleId, allow });
    const safe = String(i.user.username || "user").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 18) || "user";
    let channel;
    try {
      channel = await guild.channels.create({ name: k.channelName(safe), type: ChannelType.GuildText, parent: a.categoryId || undefined, topic: `app-ticket:${i.user.id}:${kind}`, permissionOverwrites: overwrites, reason: `${kind} ticket` });
    } catch (error) {
      console.error("⚠️ Application ticket error:", error?.message || error);
      return i.editReply(no(t("Je n'ai pas pu créer le ticket (il me faut « Gérer les salons »).", "I could not create the ticket (I need Manage Channels).")));
    }
    if (kind === "claim") {
      db.claims[i.user.id] = { status: "pending", channelId: channel.id, at: Date.now() };
      save(true);
    }
    const e = embed(k.color).setTitle(k.title()).setDescription(t(`Demande de <@${i.user.id}>. Le staff va la lire et te répondre ici.`, `Request from <@${i.user.id}>. Staff will read it and answer here.`)).setThumbnail(i.user.displayAvatarURL?.() || null);
    for (const [id, label] of k.inputs()) {
      const value = i.fields.getTextInputValue(id)?.trim();
      if (value) e.addFields({ name: label.slice(0, 256), value: value.slice(0, 1000) });
    }
    if (kind === "claim") e.addFields({ name: "XP", value: `**${db.xp[i.user.id] || 0}** / ${a.claim.xp}`, inline: true }, { name: t("Récompense", "Reward"), value: a.claim.reward, inline: true });
    else if (kind !== "mm") e.addFields({ name: t("Salon demandé", "Requested channel"), value: `<#${a.access[kind].channelId}>`, inline: true });
    e.addFields({ name: t("Statut", "Status"), value: t("⏳ En attente du staff", "⏳ Waiting for staff"), inline: true });
    const staffPing = a.staffRoleId ? `<@&${a.staffRoleId}> ` : "";
    await channel.send({
      content: `${staffPing}<@${i.user.id}>`,
      embeds: [e],
      components: [appRow(appButton("ap:acc", t("Accepter", "Accept"), ButtonStyle.Success, "✅"), appButton("ap:dec", t("Refuser", "Decline"), ButtonStyle.Danger, "✖️"), appButton("ap:close", t("Fermer", "Close"), ButtonStyle.Secondary, "🔒"))],
      allowedMentions: { users: [i.user.id], roles: a.staffRoleId ? [a.staffRoleId] : [] },
    });
    await log(guild, `🎫 **${k.title().replace(/^\S+\s+/, "")}**  ·  <@${i.user.id}>  ·  ${channel}`, 0x3498db);
    return i.editReply(ok(t(`Ticket créé : ${channel}`, `Ticket created: ${channel}`)));
  }

  /* Accept: the middleman role is given, or the requested channel is opened. */
  async function appAccept(i) {
    const info = appTicketOf(i.channel);
    if (!info) return reply(i, no(t("Ce n'est pas un ticket de candidature.", "This is not an application ticket.")));
    if (!appStaff(i.member)) return reply(i, no(t("Réservé au staff.", "Staff only.")));
    const a = db.cfg.apps;
    const member = await i.guild.members.fetch(info.userId).catch(() => null);
    if (!member) return reply(i, no(t("Cette personne a quitté le serveur.", "This person left the server.")));
    let done;
    try {
      if (info.kind === "mm") {
        if (a.mmRoleId) {
          await member.roles.add(a.mmRoleId, `middleman application accepted by ${i.user.username}`);
          done = t(`Bienvenue dans l'équipe middleman ! Le rôle <@&${a.mmRoleId}> t'a été donné.`, `Welcome to the middleman team! You were given <@&${a.mmRoleId}>.`);
        } else done = t("Bienvenue dans l'équipe middleman ! Le staff va te donner ton rôle.", "Welcome to the middleman team! Staff will give you your role.");
      } else if (info.kind === "claim") {
        db.claims[info.userId] = { ...(db.claims[info.userId] || {}), status: "accepted", at: Date.now(), by: i.user.id };
        save(true);
        done = t(`Ta réclamation de **${a.claim.reward}** est validée : le staff te le remet en jeu.`, `Your claim of **${a.claim.reward}** is approved: staff gives it to you in the game.`);
      } else {
        const grant = a.access[info.kind];
        const seen = grant.channelId ? t(` Tu peux maintenant voir <#${grant.channelId}>.`, ` You can now see <#${grant.channelId}>.`) : "";
        if (grant.roleId) {
          await member.roles.add(grant.roleId, `${info.kind} access accepted by ${i.user.username}`);
          done = t(`Accès **${grant.label}** accordé : le rôle <@&${grant.roleId}> t'a été donné.${seen}`, `**${grant.label}** access granted: you were given <@&${grant.roleId}>.${seen}`);
        } else {
          const target = await i.guild.channels.fetch(grant.channelId).catch(() => null);
          if (!target?.permissionOverwrites) return reply(i, no(t(`Le salon ${grant.label} est introuvable. Règle-le avec \`/apps access\`.`, `The ${grant.label} channel was not found. Set it with \`/apps access\`.`)));
          await target.permissionOverwrites.edit(info.userId, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true }, { reason: `${info.kind} access accepted by ${i.user.username}` });
          done = t(`Accès **${grant.label}** accordé.${seen}`, `**${grant.label}** access granted.${seen}`);
        }
      }
    } catch (error) {
      console.error("⚠️ Application accept error:", error?.message || error);
      return reply(i, no(t("Je n'ai pas pu appliquer la décision (permissions du bot : « Gérer les rôles » et « Gérer les salons », et mon rôle doit être au-dessus).", "I could not apply the decision (bot permissions: Manage Roles and Manage Channels, and my role must be above).")));
    }
    const base = i.message.embeds?.[0]?.toJSON?.() || {};
    const updated = EmbedBuilder.from(base).setColor(0x57f287).setFields((base.fields || []).filter((f) => f.name !== t("Statut", "Status")).concat({ name: t("Statut", "Status"), value: t(`✅ Accepté par <@${i.user.id}>`, `✅ Accepted by <@${i.user.id}>`), inline: true }));
    await i.update({ embeds: [updated], components: [appRow(appButton("ap:close", t("Fermer le ticket", "Close the ticket"), ButtonStyle.Secondary, "🔒"))] });
    await i.channel.send({ content: `<@${info.userId}>`, embeds: [embed(0x57f287).setDescription(`✅ ${done}`)], allowedMentions: { users: [info.userId] } }).catch(() => {});
    await log(i.guild, `✅ **${APP_KINDS[info.kind].title().replace(/^\S+\s+/, "")}**  ·  <@${info.userId}>  ·  ${t("accepté par", "accepted by")} <@${i.user.id}>`, 0x2ecc71);
  }

  /* Decline: ask the reason first. */
  async function appDecline(i) {
    if (!appTicketOf(i.channel)) return reply(i, no(t("Ce n'est pas un ticket de candidature.", "This is not an application ticket.")));
    if (!appStaff(i.member)) return reply(i, no(t("Réservé au staff.", "Staff only.")));
    return i.showModal(new ModalBuilder().setCustomId("ap:m:dec").setTitle(t("Refuser", "Decline")).addComponents(new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("reason").setLabel(t("Raison (vue par la personne)", "Reason (seen by the person)")).setStyle(TextInputStyle.Paragraph).setRequired(false).setMaxLength(500))));
  }
  async function appDeclined(i) {
    const info = appTicketOf(i.channel);
    if (!info) return reply(i, no(t("Ce n'est pas un ticket de candidature.", "This is not an application ticket.")));
    if (!appStaff(i.member)) return reply(i, no(t("Réservé au staff.", "Staff only.")));
    const reason = i.fields.getTextInputValue("reason")?.trim() || t("Aucune raison donnée.", "No reason given.");
    if (info.kind === "claim" && db.claims[info.userId]?.status !== "accepted") {
      delete db.claims[info.userId]; // declined: the person may try again
      save(true);
    }
    const base = i.message?.embeds?.[0]?.toJSON?.() || {};
    const updated = EmbedBuilder.from(base).setColor(0xed4245).setFields((base.fields || []).filter((f) => f.name !== t("Statut", "Status")).concat({ name: t("Statut", "Status"), value: t(`✖️ Refusé par <@${i.user.id}>`, `✖️ Declined by <@${i.user.id}>`), inline: true }));
    const closeRow = appRow(appButton("ap:close", t("Fermer le ticket", "Close the ticket"), ButtonStyle.Secondary, "🔒"));
    if (i.isFromMessage?.()) await i.update({ embeds: [updated], components: [closeRow] });
    else {
      await i.message?.edit?.({ embeds: [updated], components: [closeRow] }).catch(() => {});
      await i.reply({ content: ok(t("Décision enregistrée.", "Decision saved.")), flags: ephemeral });
    }
    await i.channel.send({ content: `<@${info.userId}>`, embeds: [embed(0xed4245).setDescription(t(`✖️ Ta demande est refusée.\n**Raison :** ${reason}`, `✖️ Your request was declined.\n**Reason:** ${reason}`))], allowedMentions: { users: [info.userId] } }).catch(() => {});
    await log(i.guild, `✖️ **${APP_KINDS[info.kind].title().replace(/^\S+\s+/, "")}**  ·  <@${info.userId}>  ·  ${t("refusé par", "declined by")} <@${i.user.id}>  ·  ${reason}`, 0xed4245);
  }

  async function appClose(i) {
    const info = appTicketOf(i.channel);
    if (!info) return reply(i, no(t("Ce n'est pas un ticket de candidature.", "This is not an application ticket.")));
    if (i.user.id !== info.userId && !appStaff(i.member)) return reply(i, no(t("Seule la personne ou le staff peut fermer ce ticket.", "Only the person or staff can close this ticket.")));
    if (info.kind === "claim" && db.claims[info.userId]?.status !== "accepted") {
      delete db.claims[info.userId]; // closed with no decision: the claim is given back
      save(true);
    }
    await i.deferUpdate().catch(() => {}); // acknowledged with no message: the channel is gone right away
    await log(i.guild, `🔒 ${t("Ticket fermé", "Ticket closed")}  ·  <@${info.userId}>  ·  ${t("par", "by")} <@${i.user.id}>`, 0x747f8d);
    await i.channel.delete("application ticket closed").catch((error) => console.error("⚠️ Could not delete the ticket:", error?.message || error));
  }

  /* ---------- cross-trade: item for item. A middleman takes the ticket, receives both items, hands each over ---------- */
  const ctPhase = (c) => {
    if (c.state === "cancelled") return "cancelled";
    if (!c.b) return "partner";
    if (!(c.confA && c.confB)) return "offers";
    if (!c.mm) return "waiting_mm";
    if (!(c.recvA && c.recvB)) return "deposit";
    if (!(c.delA && c.delB)) return "delivery";
    return "done";
  };
  const ctFinal = (c) => ["done", "cancelled"].includes(ctPhase(c));
  const ctParty = (c, id) => id === c.a || id === c.b;
  const ctSide = (c, id) => (id === c.a ? "A" : id === c.b ? "B" : null);
  /* The middlemen: the holders of the middleman role (given by the applications), and the staff. */
  const ctCanClaim = (member) => appStaff(member) || Boolean(db.cfg.apps.mmRoleId && member?.roles?.cache?.has?.(db.cfg.apps.mmRoleId));
  const ctTicketOf = (channel) => db.crosstrades[channel?.id] || null;

  const ctBtn = (id, label, style, emoji, disabled = false) => new ButtonBuilder().setCustomId(`ct:${id}`).setLabel(String(label).slice(0, 80)).setStyle(style).setEmoji(emoji).setDisabled(disabled);

  /* The card: both offers side by side, who confirmed, the middleman, the next step, the buttons that fit the step. */
  function ctBody(c) {
    const phase = ctPhase(c);
    const side = (who) => {
      const id = c[who === "A" ? "a" : "b"];
      if (!id) return t("⏳ En attente de l'autre personne…", "⏳ Waiting for the other person…");
      const give = c[`give${who}`];
      const conf = c[`conf${who}`];
      const got = c[`recv${who}`] ? t("📥 reçu par le middleman", "📥 received by the middleman") : "";
      const sent = c[`del${who}`] ? t("📤 remis à l'autre", "📤 handed over") : "";
      return [`<@${id}>`, give ? `📦 ${give}` : t("📦 *offre pas encore écrite*", "📦 *offer not written yet*"), c[`roblox${who}`] ? `🎮 ${c[`roblox${who}`]}` : "", conf ? t("✅ confirmé", "✅ confirmed") : t("⏳ pas confirmé", "⏳ not confirmed"), got, sent].filter(Boolean).join("\n");
    };
    const next = {
      partner: t("👤 Ajoute la personne avec qui tu échanges (bouton ci-dessous).", "👤 Add the person you trade with (button below)."),
      offers: t("📦 Chacun écrit **son offre** (bouton *Mon offre*), puis les deux appuient sur **✅ Je confirme**.", "📦 Each person writes **their offer** (*My offer* button), then both press **✅ I confirm**."),
      waiting_mm: t("🛡️ Offres confirmées. En attente d'un **middleman** : les middlemen et le staff sont prévenus.", "🛡️ Offers confirmed. Waiting for a **middleman**: middlemen and staff were notified."),
      deposit: t(`📤 Chacun **remet son objet à ${c.mm ? `<@${c.mm}>` : "le middleman"}** en jeu. Le middleman coche la réception ci-dessous.`, `📤 Each person **hands their item to ${c.mm ? `<@${c.mm}>` : "the middleman"}** in the game. The middleman ticks the reception below.`),
      delivery: t("📥 Le middleman **remet chaque objet** à l'autre personne, puis coche la livraison.", "📥 The middleman **hands each item over** to the other person, then ticks the delivery."),
      done: t("🎉 **Cross-trade terminé !** Merci à vous.", "🎉 **Cross-trade completed!** Thank you both."),
      cancelled: t("✖️ **Cross-trade annulé.**", "✖️ **Cross-trade cancelled.**") + (c.recvA || c.recvB ? t(`\n⚠️ Des objets ont été reçus : ${c.mm ? `<@${c.mm}>` : "le middleman"} doit les **rendre** à leur propriétaire.`, `\n⚠️ Items were received: ${c.mm ? `<@${c.mm}>` : "the middleman"} must **give them back** to their owners.`) : ""),
    }[phase];
    const steps = [t("Offres", "Offers"), t("Confirmation", "Confirm"), t("Middleman", "Middleman"), t("Dépôt", "Deposit"), t("Livraison", "Delivery")];
    const order = ["partner", "offers", "waiting_mm", "deposit", "delivery", "done"];
    const at = phase === "cancelled" ? -1 : Math.max(0, order.indexOf(phase) - 1);
    const progress = steps.map((name, n) => `${phase === "done" || n < at ? "✅" : n === at ? "▶️" : "▫️"} ${name}`).join("  ·  ");
    const e = embed(phase === "done" ? 0x57f287 : phase === "cancelled" ? 0xed4245 : c.frozen ? 0x3498db : 0x19c7a0)
      .setTitle(`🔁  Cross-trade #${c.n}`)
      .setDescription(`${c.frozen ? `${t("🧊  **GELÉ** : un litige est ouvert, le staff va décider.", "🧊  **FROZEN**: a dispute is open, staff will decide.")}\n\n` : ""}${next}${phase === "done" ? `\n${t("⭐ Laisse un vouch avec `/vouch`", "⭐ Leave a vouch with `/vouch`")}${vouchChannelId() ? ` → <#${vouchChannelId()}>` : ""}` : ""}\n\n${progress}`)
      .addFields(
        { name: t("👤  Partie A", "👤  Side A"), value: side("A"), inline: true },
        { name: t("👤  Partie B", "👤  Side B"), value: side("B"), inline: true },
        { name: t("🛡️  Middleman", "🛡️  Middleman"), value: c.mm ? `<@${c.mm}>\n${t("✅ **annoncé et légitime**", "✅ **announced and legitimate**")}` : t("⏳ pas encore pris en charge", "⏳ not taken yet"), inline: false },
        { name: t("🚨  Anti-arnaque", "🚨  Anti-scam"), value: t("Seul le middleman **annoncé ici** est légitime. Ne donne **rien** à quelqu'un d'autre ni en dehors de ce ticket.", "Only the middleman **announced here** is legitimate. Give **nothing** to anyone else or outside this ticket."), inline: false }
      )
      .setFooter({ text: `Kazuki MM  ·  Cross-trade #${c.n}` });
    const rows = [];
    if (!ctFinal(c)) {
      const locked = ["waiting_mm", "deposit", "delivery"].includes(phase);
      const r1 = [];
      if (phase === "partner") r1.push(ctBtn("add", t("Ajouter l'autre personne", "Add the other person"), ButtonStyle.Primary, "➕"));
      else r1.push(ctBtn("offer", t("Mon offre", "My offer"), ButtonStyle.Primary, "📦", locked || c.frozen), ctBtn("confirm", t("Je confirme", "I confirm"), ButtonStyle.Success, "✅", locked || c.frozen));
      r1.push(ctBtn("cancel", t("Annuler", "Cancel"), ButtonStyle.Danger, "✖️"), c.frozen ? ctBtn("unfreeze", t("Dégeler (staff)", "Unfreeze (staff)"), ButtonStyle.Secondary, "🧊") : ctBtn("freeze", t("Appeler le staff", "Call staff"), ButtonStyle.Danger, "🚨"));
      rows.push(new ActionRowBuilder().addComponents(r1));
      const r2 = [];
      if (!c.mm) r2.push(ctBtn("claim", t("Prendre en charge", "Take this ticket"), ButtonStyle.Secondary, "🛡️", phase !== "waiting_mm" || c.frozen));
      else {
        r2.push(ctBtn("release", t("Se retirer", "Step down"), ButtonStyle.Secondary, "↩️"));
        const tick = (key, label, emoji) => ctBtn(key, label, c[key] ? ButtonStyle.Success : ButtonStyle.Secondary, emoji, c.frozen);
        if (phase === "deposit") r2.push(tick("recvA", t("Reçu de A", "Got from A"), "📥"), tick("recvB", t("Reçu de B", "Got from B"), "📥"));
        if (phase === "delivery") r2.push(tick("delA", t("Remis à A", "Gave to A"), "📤"), tick("delB", t("Remis à B", "Gave to B"), "📤"));
      }
      rows.push(new ActionRowBuilder().addComponents(r2));
    } else rows.push(new ActionRowBuilder().addComponents(ctBtn("close", t("Fermer le ticket", "Close the ticket"), ButtonStyle.Secondary, "🔒")));
    return { embeds: [e], components: rows };
  }

  /* Shows the new state of the card: edits the message the click came from, or fetches it. */
  async function ctPush(i, c, ack) {
    const body = ctBody(c);
    if (i.isFromMessage?.() && i.message?.id === c.msgId) return i.update(body);
    const message = await i.channel.messages?.fetch?.(c.msgId).catch(() => null);
    await message?.edit?.(body).catch(() => {});
    if (ack !== undefined && !i.replied && !i.deferred) await i.reply({ content: ack, flags: ephemeral });
  }
  const ctSay = (i, text, mentions = []) => i.channel.send({ content: text, allowedMentions: { users: mentions, roles: [] } }).catch(() => {});
  const ctNeed = (i, c) => {
    if (!c) { reply(i, no(t("Ce n'est pas un ticket de cross-trade.", "This is not a cross-trade ticket."))); return false; }
    return true;
  };

  /* The panel button: a private ticket for the person. */
  async function ctOpen(i) {
    const guild = i.guild;
    const existing = [...(guild.channels.cache?.values?.() || [])].find((c) => String(c.topic || "").startsWith(`ct-ticket:${i.user.id}`));
    if (existing) return reply(i, no(t(`Tu as déjà un cross-trade ouvert : ${existing}`, `You already have an open cross-trade: ${existing}`)));
    await i.deferReply({ flags: ephemeral });
    const a = db.cfg.apps;
    const allow = [P.ViewChannel, P.SendMessages, P.ReadMessageHistory, P.AttachFiles];
    const overwrites = [{ id: guild.roles.everyone.id, deny: [P.ViewChannel] }, { id: i.user.id, allow }];
    if (client?.user?.id) overwrites.push({ id: client.user.id, allow: [...allow, P.EmbedLinks, P.ManageChannels, P.ManageRoles] });
    for (const roleId of [a.staffRoleId, a.mmRoleId]) if (roleId && guild.roles.cache?.get?.(roleId) && !overwrites.some((o) => o.id === roleId)) overwrites.push({ id: roleId, allow });
    const safe = String(i.user.username || "user").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 18) || "user";
    const n = (db.crossStats.opened || 0) + 1;
    let channel;
    try {
      channel = await guild.channels.create({ name: `crosstrade-${n}-${safe}`.slice(0, 90), type: ChannelType.GuildText, parent: a.categoryId || undefined, topic: `ct-ticket:${i.user.id}`, permissionOverwrites: overwrites, reason: "cross-trade" });
    } catch (error) {
      console.error("⚠️ Cross-trade ticket error:", error?.message || error);
      return i.editReply(no(t("Je n'ai pas pu créer le ticket (il me faut « Gérer les salons »).", "I could not create the ticket (I need Manage Channels).")));
    }
    db.crossStats.opened = n;
    const c = { n, a: i.user.id, nameA: i.member?.displayName || i.user.username, b: "", nameB: "", giveA: "", giveB: "", robloxA: "", robloxB: "", confA: false, confB: false, mm: "", mmName: "", recvA: false, recvB: false, delA: false, delB: false, frozen: false, state: "open", msgId: "", at: Date.now() };
    db.crosstrades[channel.id] = c;
    const ping = a.mmRoleId || a.staffRoleId;
    const message = await channel.send({ content: `<@${i.user.id}>`, ...ctBody(c), allowedMentions: { users: [i.user.id] } });
    c.msgId = message?.id || "";
    save(true);
    await log(guild, `🔁 **Cross-trade #${n}**  ·  <@${i.user.id}>  ·  ${channel}`, 0x19c7a0);
    return i.editReply(ok(t(`Cross-trade créé : ${channel}${ping ? "" : ""}`, `Cross-trade created: ${channel}`)));
  }

  /* A adds the other person (a member menu: no typing of an @mention). */
  async function ctAdd(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (i.user.id !== c.a) return reply(i, no(t("Seule la personne qui a ouvert le ticket ajoute l'autre.", "Only the person who opened the ticket adds the other one.")));
    if (ctPhase(c) !== "partner") return reply(i, no(t("L'autre personne est déjà ajoutée.", "The other person is already added.")));
    return i.reply({ flags: ephemeral, content: t("👤 **Avec qui échanges-tu ?** Choisis la personne dans la liste.", "👤 **Who do you trade with?** Pick the person in the list."), components: [new ActionRowBuilder().addComponents(new UserSelectMenuBuilder().setCustomId("ct:pick").setPlaceholder(t("Cherche un membre", "Search a member")).setMinValues(1).setMaxValues(1))] });
  }
  async function ctPick(i) {
    const c = ctTicketOf(i.channel);
    if (!c) return i.update({ content: no(t("Ce n'est pas un ticket de cross-trade.", "This is not a cross-trade ticket.")), components: [] });
    const fail = (text) => i.update({ content: no(text), components: i.message?.components || [] });
    if (i.user.id !== c.a || ctPhase(c) !== "partner") return i.update({ content: no(t("Impossible pour le moment.", "Not possible right now.")), components: [] });
    const id = i.values?.[0];
    if (!id) return;
    if (id === c.a) return fail(t("Tu ne peux pas échanger avec toi-même.", "You cannot trade with yourself."));
    const person = await i.guild.members.fetch(id).catch(() => null);
    if (!person || person.user?.bot) return fail(t("Je ne trouve pas cette personne (les bots ne sont pas autorisés).", "I could not find that person (bots are not allowed)."));
    await i.channel.permissionOverwrites.edit(id, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true });
    c.b = id;
    c.nameB = person.displayName || person.user?.username || "B";
    save(true);
    await i.update({ content: ok(t(`<@${id}> est ajouté.`, `<@${id}> is added.`)), components: [] });
    const card = await i.channel.messages?.fetch?.(c.msgId).catch(() => null);
    await card?.edit?.(ctBody(c)).catch(() => {});
    await ctSay(i, t(`<@${id}> tu es invité à un cross-trade avec <@${c.a}>. Écris **ton offre** avec le bouton *Mon offre* !`, `<@${id}> you are invited to a cross-trade with <@${c.a}>. Write **your offer** with the *My offer* button!`), [id]);
  }

  /* Each person writes what they give (and their Roblox name, to find them in the game). */
  async function ctOffer(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!ctParty(c, i.user.id)) return reply(i, no(t("Réservé aux deux personnes du cross-trade.", "Only for the two people of the cross-trade.")));
    if (ctPhase(c) !== "offers" || c.frozen) return reply(i, no(t("Les offres ne peuvent plus être modifiées.", "Offers can no longer be changed.")));
    const who = ctSide(c, i.user.id);
    const modal = new ModalBuilder().setCustomId("ct:m:offer").setTitle(t("Mon offre", "My offer"));
    modal.addComponents(
      new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("give").setLabel(t("Ce que tu donnes", "What you give")).setStyle(TextInputStyle.Paragraph).setRequired(true).setMaxLength(300).setValue(c[`give${who}`] || "")),
      new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("roblox").setLabel(t("Ton pseudo Roblox", "Your Roblox username")).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(60).setValue(c[`roblox${who}`] || ""))
    );
    return i.showModal(modal);
  }
  async function ctOfferSubmit(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!ctParty(c, i.user.id) || ctPhase(c) !== "offers" || c.frozen) return reply(i, no(t("Impossible pour le moment.", "Not possible right now.")));
    const who = ctSide(c, i.user.id);
    const give = i.fields.getTextInputValue("give").trim().slice(0, 300);
    const roblox = i.fields.getTextInputValue("roblox").trim().slice(0, 60);
    if (!give || !roblox) return reply(i, no(t("Écris ton offre et ton pseudo Roblox.", "Write your offer and your Roblox username.")));
    const changed = c[`give${who}`] && (c[`give${who}`] !== give);
    c[`give${who}`] = give;
    c[`roblox${who}`] = roblox;
    const hadConf = c.confA || c.confB;
    c.confA = false; // any change means both look at it again
    c.confB = false;
    save(true);
    await ctPush(i, c, ok(t("Offre enregistrée.", "Offer saved.")));
    if (changed || hadConf) await ctSay(i, t(`✏️ <@${i.user.id}> a modifié son offre : **les confirmations sont remises à zéro**, relisez et confirmez à nouveau.`, `✏️ <@${i.user.id}> changed their offer: **confirmations are reset**, read again and confirm again.`), [i.user.id]);
  }
  async function ctConfirm(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!ctParty(c, i.user.id)) return reply(i, no(t("Réservé aux deux personnes du cross-trade.", "Only for the two people of the cross-trade.")));
    if (ctPhase(c) !== "offers" || c.frozen) return reply(i, no(t("Rien à confirmer pour le moment.", "Nothing to confirm right now.")));
    if (!c.giveA || !c.giveB) return reply(i, no(t("Les deux offres doivent d'abord être écrites.", "Both offers must be written first.")));
    const who = ctSide(c, i.user.id);
    c[`conf${who}`] = true;
    save(true);
    const both = c.confA && c.confB;
    await i.update(ctBody(c));
    if (both) {
      const ping = db.cfg.apps.mmRoleId || db.cfg.apps.staffRoleId;
      await i.channel.send({ content: t(`✅ Les deux offres sont confirmées. ${ping ? `<@&${ping}>` : "Un middleman"} : qui prend ce cross-trade en charge ?`, `✅ Both offers are confirmed. ${ping ? `<@&${ping}>` : "A middleman"}: who takes this cross-trade?`), allowedMentions: { roles: ping ? [ping] : [] } }).catch(() => {});
    }
  }

  /* A middleman (holder of the middleman role, or staff) takes the ticket: announced in the card. */
  async function ctClaim(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!ctCanClaim(i.member)) return reply(i, no(t("Seuls les middlemen et le staff peuvent prendre un cross-trade en charge.", "Only middlemen and staff can take a cross-trade.")));
    if (ctParty(c, i.user.id)) return reply(i, no(t("Tu ne peux pas être middleman de ton propre échange.", "You cannot be the middleman of your own trade.")));
    if (c.mm) return reply(i, no(t(`<@${c.mm}> a déjà pris ce cross-trade en charge.`, `<@${c.mm}> already took this cross-trade.`)));
    if (ctPhase(c) !== "waiting_mm" || c.frozen) return reply(i, no(t("Impossible pour le moment.", "Not possible right now.")));
    await i.channel.permissionOverwrites.edit(i.user.id, { ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true }).catch(() => {});
    c.mm = i.user.id;
    c.mmName = i.member?.displayName || i.user.username;
    save(true);
    await i.update(ctBody(c));
    await ctSay(i, t(`🛡️ <@${i.user.id}> prend ce cross-trade en charge : **il est le seul middleman légitime de ce ticket**.`, `🛡️ <@${i.user.id}> takes this cross-trade: **he is the only legitimate middleman of this ticket**.`), [i.user.id]);
    await log(i.guild, `🛡️ **Cross-trade #${c.n}**  ·  ${t("pris en charge par", "taken by")} <@${i.user.id}>`, 0x19c7a0);
  }
  async function ctRelease(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!c.mm) return reply(i, no(t("Aucun middleman à retirer.", "No middleman to remove.")));
    if (i.user.id !== c.mm && !appStaff(i.member)) return reply(i, no(t("Seuls le middleman ou le staff peuvent le retirer.", "Only the middleman or staff can remove him.")));
    if ((c.recvA || c.recvB) && !appStaff(i.member)) return reply(i, no(t("Des objets sont déjà chez le middleman : le staff doit reprendre la main.", "Items are already with the middleman: staff has to take over.")));
    const old = c.mm;
    c.mm = "";
    c.mmName = "";
    c.recvA = c.recvB = c.delA = c.delB = false;
    save(true);
    await i.update(ctBody(c));
    await ctSay(i, t(`↩️ <@${old}> n'est plus le middleman de ce ticket. Un autre middleman peut le prendre en charge.`, `↩️ <@${old}> is no longer the middleman of this ticket. Another middleman can take it.`), []);
  }

  /* The middleman ticks what he received and what he handed over. */
  async function ctTick(i, key) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (i.user.id !== c.mm && !appStaff(i.member)) return reply(i, no(t("Seul le middleman du ticket peut cocher ça.", "Only the middleman of this ticket can tick this.")));
    if (c.frozen) return reply(i, no(t("Le ticket est gelé : le staff décide.", "The ticket is frozen: staff decides.")));
    const phase = ctPhase(c);
    const ok1 = (phase === "deposit" && (key === "recvA" || key === "recvB")) || (phase === "delivery" && (key === "delA" || key === "delB"));
    if (!ok1) return reply(i, no(t("Pas possible à cette étape.", "Not possible at this step.")));
    c[key] = !c[key];
    save(true);
    const after = ctPhase(c);
    await i.update(ctBody(c));
    const who = key.endsWith("A") ? c.a : c.b;
    if (key.startsWith("recv") && c[key]) await ctSay(i, t(`📥 Le middleman a **reçu l'objet de** <@${who}>.`, `📥 The middleman **received the item from** <@${who}>.`), []);
    if (key.startsWith("recv") && c.recvA && c.recvB && after === "delivery") await ctSay(i, t(`✅ Les deux objets sont chez <@${c.mm}>. Il va maintenant les remettre.`, `✅ Both items are with <@${c.mm}>. He will now hand them over.`), []);
    if (key.startsWith("del") && c[key]) await ctSay(i, t(`📤 L'objet a été **remis à** <@${who}>.`, `📤 The item was **handed to** <@${who}>.`), []);
    if (after === "done") {
      db.crossStats.done = (db.crossStats.done || 0) + 1;
      save(true);
      await ctSay(i, t(`🎉 **Cross-trade #${c.n} terminé** entre <@${c.a}> et <@${c.b}> ! Merci à <@${c.mm}>.`, `🎉 **Cross-trade #${c.n} completed** between <@${c.a}> and <@${c.b}>! Thanks to <@${c.mm}>.`), []);
      await log(i.guild, `🎉 **Cross-trade #${c.n}**  ·  <@${c.a}> ⇄ <@${c.b}>  ·  ${t("middleman", "middleman")} <@${c.mm}>`, 0x57f287);
    }
  }

  async function ctCancel(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    const priv = i.user.id === c.mm || appStaff(i.member);
    if (!ctParty(c, i.user.id) && !priv) return reply(i, no(t("Réservé aux personnes du cross-trade, au middleman et au staff.", "Only for the people of the cross-trade, the middleman and staff.")));
    if (ctFinal(c)) return reply(i, no(t("C'est déjà terminé.", "It is already over.")));
    if ((c.recvA || c.recvB) && !priv) return reply(i, no(t("Des objets sont déjà chez le middleman : lui ou le staff doit annuler.", "Items are already with the middleman: he or staff has to cancel.")));
    c.state = "cancelled";
    save(true);
    await i.update(ctBody(c));
    await ctSay(i, t(`✖️ <@${i.user.id}> a annulé le cross-trade.${c.recvA || c.recvB ? " Le middleman rend les objets reçus." : ""}`, `✖️ <@${i.user.id}> cancelled the cross-trade.${c.recvA || c.recvB ? " The middleman gives back the items received." : ""}`), []);
    await log(i.guild, `✖️ **Cross-trade #${c.n}**  ·  ${t("annulé par", "cancelled by")} <@${i.user.id}>`, 0xed4245);
  }
  async function ctFreeze(i, on) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (ctFinal(c)) return reply(i, no(t("C'est déjà terminé.", "It is already over.")));
    if (on && !ctParty(c, i.user.id) && i.user.id !== c.mm && !appStaff(i.member)) return reply(i, no(t("Réservé aux personnes du cross-trade, au middleman et au staff.", "Only for the people of the cross-trade, the middleman and staff.")));
    if (!on && !appStaff(i.member)) return reply(i, no(t("Seul le staff peut dégeler.", "Only staff can unfreeze.")));
    if (c.frozen === on) return reply(i, no(t("Déjà dans cet état.", "Already in that state.")));
    c.frozen = on;
    save(true);
    await i.update(ctBody(c));
    const staff = db.cfg.apps.staffRoleId;
    await i.channel.send({ content: on ? t(`🚨 <@${i.user.id}> appelle le staff : le cross-trade est **gelé**. ${staff ? `<@&${staff}>` : "Staff"}, merci de regarder.`, `🚨 <@${i.user.id}> calls staff: the cross-trade is **frozen**. ${staff ? `<@&${staff}>` : "Staff"}, please look.`) : t("🧊 Le staff a dégelé le cross-trade.", "🧊 Staff unfroze the cross-trade."), allowedMentions: { roles: on && staff ? [staff] : [] } }).catch(() => {});
    await log(i.guild, `${on ? "🚨" : "🧊"} **Cross-trade #${c.n}**  ·  ${on ? t("gelé par", "frozen by") : t("dégelé par", "unfrozen by")} <@${i.user.id}>`, 0x3498db);
  }
  async function ctClose(i) {
    const c = ctTicketOf(i.channel);
    if (!ctNeed(i, c)) return;
    if (!ctParty(c, i.user.id) && i.user.id !== c.mm && !appStaff(i.member)) return reply(i, no(t("Réservé aux personnes du cross-trade, au middleman et au staff.", "Only for the people of the cross-trade, the middleman and staff.")));
    if ((c.recvA || c.recvB) && !ctFinal(c)) return reply(i, no(t("Des objets sont chez le middleman : termine ou annule le cross-trade avant de fermer.", "Items are with the middleman: finish or cancel the cross-trade before closing.")));
    await i.deferUpdate().catch(() => {});
    delete db.crosstrades[i.channel.id];
    save(true);
    await log(i.guild, `🔒 **Cross-trade #${c.n}**  ·  ${t("ticket fermé par", "ticket closed by")} <@${i.user.id}>`, 0x747f8d);
    await i.channel.delete("cross-trade closed").catch((error) => console.error("⚠️ Could not delete the ticket:", error?.message || error));
  }

  /* ---------- wiring ---------- */
  async function handleInteraction(i) {
    if (!ON) return false;
    try {
      if (i.isChatInputCommand?.() && NAMES.has(i.commandName)) {
        if (!i.guild) return (await reply(i, no(t("Utilise cette commande sur le serveur.", "Use this command in the server."))), true);
        await H[i.commandName](i);
        return true;
      }
      if (typeof i.customId === "string" && i.customId.startsWith("ct:")) {
        const [, kind, arg] = i.customId.split(":");
        if (i.isButton?.()) {
          if (kind === "open") await ctOpen(i);
          else if (kind === "add") await ctAdd(i);
          else if (kind === "offer") await ctOffer(i);
          else if (kind === "confirm") await ctConfirm(i);
          else if (kind === "claim") await ctClaim(i);
          else if (kind === "release") await ctRelease(i);
          else if (["recvA", "recvB", "delA", "delB"].includes(kind)) await ctTick(i, kind);
          else if (kind === "cancel") await ctCancel(i);
          else if (kind === "freeze") await ctFreeze(i, true);
          else if (kind === "unfreeze") await ctFreeze(i, false);
          else if (kind === "close") await ctClose(i);
        } else if (i.isModalSubmit?.() && kind === "m" && arg === "offer") await ctOfferSubmit(i);
        else if (i.isUserSelectMenu?.() && kind === "pick") await ctPick(i);
        return true;
      }
      if (typeof i.customId === "string" && i.customId.startsWith("ap:")) {
        const [, kind, arg] = i.customId.split(":");
        if (i.isButton?.()) {
          if (kind === "open") await appOpen(i, arg);
          else if (kind === "myxp") await appMyXp(i);
          else if (kind === "acc") await appAccept(i);
          else if (kind === "dec") await appDecline(i);
          else if (kind === "close") await appClose(i);
        } else if (i.isModalSubmit?.() && kind === "m") {
          if (arg === "dec") await appDeclined(i);
          else await appSubmit(i, arg);
        }
        return true;
      }
      if (i.isModalSubmit?.() && typeof i.customId === "string" && i.customId.startsWith("tl:vrm:")) {
        await roomModal(i, i.customId.split(":")[2]);
        return true;
      }
      if (i.isButton?.() && typeof i.customId === "string" && i.customId.startsWith("tl:")) {
        const [, kind, arg] = i.customId.split(":");
        if (kind === "rr") await roleButton(i, arg);
        else if (kind === "poll") await pollVote(i, Number(arg));
        else if (kind === "gw") await giveawayJoin(i);
        else if (kind === "gwlist") await giveawayList(i);
        else if (kind === "vr") await roomButton(i, arg);
        else if (kind === "setup") await (arg === "vyes" || arg === "vno" ? setupVocDeleteButton(i, arg === "vyes" ? "yes" : "no") : setupDeleteButton(i, arg));
        return true;
      }
    } catch (error) {
      console.error("⚠️ Tools error:", error?.message || error);
      const message = { content: no(t("Une erreur est survenue.", "Something went wrong.")), flags: ephemeral };
      if (i.deferred || i.replied) await i.followUp(message).catch(() => {});
      else await i.reply(message).catch(() => {});
      return true;
    }
    return false;
  }

  let tickTimer = null;
  let panelTimer = null;
  let exitHooked = false;
  function attach(discordClient, canReadMessages) {
    client = discordClient;
    canRead = Boolean(canReadMessages);
    if (!ON) return;
    load();
    client.on(Events.MessageCreate, async (message) => {
      try {
        if (await protect(message)) return;
        if (await onVouchChannelMessage(message)) return;
        if (await onQuizAnswer(message)) return;
        await onXp(message);
      } catch (error) {
        console.error("⚠️ Tools message error:", error?.message || error);
      }
    });
    client.on(Events.MessageDelete, (m) => {
      if (m.author?.bot || !m.guild) return;
      log(m.guild, `🗑️ ${t("Message supprimé", "Message deleted")} ${m.author ? `${m.author}` : ""} <#${m.channelId}>\n${m.content ? String(m.content).slice(0, 1500) : t("(contenu inconnu)", "(unknown content)")}`);
    });
    client.on(Events.MessageUpdate, (a, b) => {
      if (a.author?.bot || !a.guild || !a.content || a.content === b.content) return;
      log(a.guild, `✏️ ${t("Message modifié", "Message edited")} ${a.author} <#${a.channelId}>\n**${t("Avant", "Before")}:** ${String(a.content).slice(0, 700)}\n**${t("Après", "After")}:** ${String(b.content || "").slice(0, 700)}`);
    });
    client.on(Events.GuildMemberAdd, (m) => onJoin(m).catch((e) => console.error("⚠️ Tools join error:", e?.message || e)));
    client.on(Events.GuildMemberRemove, (m) => onLeave(m).catch(() => {}));
    client.on(Events.VoiceStateUpdate, (a, b) => onVoice(a, b).catch((e) => console.error("⚠️ Tools voice error:", e?.message || e)));
    client.on(Events.GuildBanAdd, (b) => log(b.guild, `🔨 **Ban** ${b.user.username} (${b.user.id})`, 0xed4245));
    if (tickTimer) clearInterval(tickTimer);
    tickTimer = setInterval(() => {
      tickGiveaways().catch(() => {});
      tickLocks().catch((e) => console.error("⚠️ locks:", e?.message || e));
      tickVoc().catch((e) => console.error("⚠️ voc:", e?.message || e));
      tickVoiceXp().catch((e) => console.error("⚠️ voice xp:", e?.message || e));
      tickAutoQuiz().catch((e) => console.error("⚠️ auto quiz:", e?.message || e));
    }, 30_000);
    tickTimer.unref?.();
    // the vouch ranking is checked every second and redrawn quietly when it changed
    if (panelTimer) clearInterval(panelTimer);
    panelTimer = setInterval(() => refreshVouchPanel().catch((e) => console.error("⚠️ Vouch panel:", e?.message || e)), 1000);
    panelTimer.unref?.();
    if (!exitHooked) {
      exitHooked = true;
      process.on("exit", () => save(true));
    }
    if (!canReadMessages) console.log("ℹ️ Multitools: levels, anti-spam, anti-links and welcome need the Message Content and Server Members intents (see the setup note).");
    else console.log("🧰 Multitools enabled (levels, moderation, welcome, roles, fun, logs, security).");
  }

  return { ON, commands, handleInteraction, attach, _test: { vouchStats, vouchRanking, refreshVouchPanel, onVouchChannelMessage, postSticky, roomPanel, onLeave, ctPhase, tickVoiceXp, claimGate, loadAvatar, onVoice, tickVoc, tickLocks, createLevelRoles, giveRewards, tickAutoQuiz, quizzes, expireQuiz, onQuizAnswer, addXp, norm, makeQuiz, gfx, save, load, levelOf, need, onXp, protect, parseDuration, getDb: () => db, H, fill, draw, endGiveaway, tickGiveaways, onJoin, roleButton, pollVote, giveawayJoin } };
})();

/* =====================================================
   PART 2: DISCORD BOT (panel + tickets)
===================================================== */

const {
  ActionRowBuilder,
  AttachmentBuilder,
  ButtonBuilder,
  ButtonStyle,
  ChannelType,
  Client,
  EmbedBuilder,
  Events,
  GatewayIntentBits,
  MessageFlags,
  PermissionFlagsBits,
  REST,
  Routes,
  SlashCommandBuilder,
  StringSelectMenuBuilder,
} = require("discord.js");

if (process.argv[2] === "new-seed") {
  middleman.newSeed(process.argv.includes("--save"), process.argv.includes("--force"));
  process.exit(0);
}

const missing = ["DISCORD_TOKEN", "CLIENT_ID", "GUILD_ID", "MM_SEED"].filter((key) => !process.env[key]);
if (missing.length) {
  console.error(`❌ Missing in .env: ${missing.join(", ")} (see .env.example)`);
  process.exit(1);
}

const STAFF_ROLE_ID = process.env.MM_STAFF_ROLE_ID || "";
const CATEGORY_ID = process.env.MM_CATEGORY_ID || "";
const LOG_CHANNEL_ID = process.env.MM_LOG_CHANNEL_ID || "";
const ephemeral = MessageFlags.Ephemeral;

const FULL_INTENTS = [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent, GatewayIntentBits.GuildMembers, GatewayIntentBits.GuildModeration, GatewayIntentBits.GuildVoiceStates];
const BASIC_INTENTS = [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.GuildModeration, GatewayIntentBits.GuildVoiceStates];
let client = new Client({ intents: tools.ON ? FULL_INTENTS : [GatewayIntentBits.Guilds] });

const isStaff = (member) =>
  Boolean(
    member?.permissions?.has(PermissionFlagsBits.Administrator) ||
      (STAFF_ROLE_ID && member?.roles?.cache?.has(STAFF_ROLE_ID))
  );

/* ---------- panels: one for Litecoin, one for PayPal ---------- */

const PANEL_FR = String(process.env.TOOLS_LANG || "fr").trim().toLowerCase() !== "en";
const pt = (fr, en) => (PANEL_FR ? fr : en);
const PANELS_FILE = require("path").join(process.env.DATA_DIR || __dirname, "panels.json");
const panelRegistry = (() => {
  let list = [];
  try {
    list = JSON.parse(require("fs").readFileSync(PANELS_FILE, "utf8"));
    if (!Array.isArray(list)) list = [];
  } catch {
    /* no panel yet */
  }
  return {
    all: () => list,
    add: (entry) => {
      list.push(entry);
      panelRegistry.save();
    },
    drop: (messageId) => {
      list = list.filter((p) => p.messageId !== messageId);
      panelRegistry.save();
    },
    save: () => {
      try {
        require("fs").writeFileSync(PANELS_FILE, JSON.stringify(list));
      } catch (error) {
        console.error("⚠️ Could not save panels.json:", error?.message || error);
      }
    },
  };
})();

const PANEL_LOOK = {
  ltc: { color: 0x5865f2, banner: ["#2b3a8f", "#7b4dd6"], subtitle: "LITECOIN MIDDLEMAN", title: "💱  KAZUKI MM  ·  Litecoin Middleman", button: "Open a Litecoin ticket", buttonFr: "Ouvrir un ticket Litecoin", emoji: "💱", style: ButtonStyle.Primary },
  paypal: { color: 0x0070ba, banner: ["#0a3d91", "#1a8cff"], subtitle: "PAYPAL MIDDLEMAN", title: "💙  KAZUKI MM  ·  PayPal Middleman", button: "Open a PayPal ticket", buttonFr: "Ouvrir un ticket PayPal", emoji: "💙", style: ButtonStyle.Success },
};

/* The panel as it is posted and refreshed: banner, steps, live numbers and the buttons. */
function buildPanel(type) {
  const look = PANEL_LOOK[type];
  const stats = middleman.panelStats(type);
  const file = new AttachmentBuilder(gfx.banner("KAZUKI MM", look.subtitle, look.banner[0], look.banner[1], type), { name: `kazuki-${type}.png` });
  const steps =
    type === "paypal"
      ? pt("**①** Ticket  **②** Accord  **③** PayPal du staff  **④** Vérification  **⑤** Livraison  **⑥** Versement", "**①** Ticket  **②** Agree  **③** Staff PayPal  **④** Check  **⑤** Delivery  **⑥** Payout")
      : pt("**①** Ticket  **②** Accord  **③** Dépôt  **④** Livraison  **⑤** Libération", "**①** Ticket  **②** Agree  **③** Deposit  **④** Delivery  **⑤** Release");
  const intro =
    type === "paypal"
      ? pt("Le **staff vérifie le paiement** et ne paie le vendeur qu'une fois le deal terminé.", "**Staff checks the payment** and only pays the seller once the deal is done.")
      : pt("Le bot **garde les LTC** jusqu'à ce que les deux soient satisfaits.", "The bot **holds the LTC** until both sides are happy.");
  const numbers = pt(
    `📊  ✅ **${stats.done}** terminés  ·  ⏳ **${stats.active}** en cours  ·  💰 **${stats.volume}**  ·  🟢 en ligne`,
    `📊  ✅ **${stats.done}** completed  ·  ⏳ **${stats.active}** in progress  ·  💰 **${stats.volume}**  ·  🟢 online`
  );
  const main = new EmbedBuilder()
    .setColor(look.color)
    .setTitle(look.title)
    .setDescription(`${intro}\n${steps}\n${numbers}`)
    .setImage(`attachment://kazuki-${type}.png`)
    .setFooter({ text: type === "paypal" ? pt("Écris toujours la référence dans la note PayPal  ·  🇫🇷 / 🇬🇧", "Always write the reference in the PayPal note  ·  🇫🇷 / 🇬🇧") : pt("Montants en LTC, $ ou €  ·  petits frais réseau  ·  🇫🇷 / 🇬🇧", "Amounts in LTC, $ or €  ·  small network fee  ·  🇫🇷 / 🇬🇧") })
    .setTimestamp();

  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId(`open_ticket:${type}`).setLabel(pt(look.buttonFr, look.button)).setEmoji(look.emoji).setStyle(look.style),
    new ButtonBuilder().setCustomId(`panel:how:${type}`).setLabel(pt("Comment ça marche", "How it works")).setEmoji("❓").setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId(`panel:fees:${type}`).setLabel(pt("Frais et limites", "Fees and limits")).setEmoji("💰").setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId(`panel:mine:${type}`).setLabel(pt("Mon ticket", "My ticket")).setEmoji("🎫").setStyle(ButtonStyle.Secondary)
  );
  // Litecoin only: short and red. The system is automatic: nobody may ask for a payment to their own address
  const alert = new EmbedBuilder()
    .setColor(0xed4245)
    .setTitle(pt("🚨  Système 100 % automatique", "🚨  100% automatic system"))
    .setDescription(
      pt(
        "Personne ne reçoit ton paiement : le bot s'en charge. Si un **staff** ou un **middleman** te demande de payer **son adresse** : **ne le fais pas** et **signale-le** à un administrateur (arnaque).",
        "Nobody receives your payment: the bot handles it. If a **staff** member or **middleman** asks you to pay **their address**: **do not do it** and **report it** to an administrator (scam)."
      )
    );
  return { embeds: type === "ltc" ? [main, alert] : [main], components: [row], files: [file] };
}

async function postPanel(interaction) {
  if (!interaction.memberPermissions.has(PermissionFlagsBits.Administrator)) {
    return interaction.reply({ content: "❌ Only administrators can use this command.", flags: ephemeral });
  }
  const type = interaction.options?.getString("type") === "paypal" ? "paypal" : "ltc";
  if (type === "paypal" && !middleman.paypalStatus().configured) {
    return interaction.reply({ content: "❌ PayPal is not available.", flags: ephemeral });
  }
  const message = await interaction.channel.send(buildPanel(type));
  if (message?.id) panelRegistry.add({ channelId: interaction.channelId, messageId: message.id, type });
  return interaction.reply({ content: `✅ ${type === "paypal" ? "PayPal" : "Litecoin"} panel posted. ${pt("Les chiffres se mettent à jour tout seuls.", "The numbers update by themselves.")}`, flags: ephemeral });
}

/* Every few minutes the posted panels get fresh numbers (a panel that was deleted is forgotten). */
async function refreshPanels() {
  for (const entry of [...panelRegistry.all()]) {
    const channel = await client.channels.fetch(entry.channelId).catch(() => null);
    const message = channel?.messages ? await channel.messages.fetch(entry.messageId).catch(() => null) : null;
    if (!message) {
      panelRegistry.drop(entry.messageId);
      continue;
    }
    const fresh = buildPanel(entry.type);
    await message.edit({ embeds: fresh.embeds, components: fresh.components }).catch((error) => console.error("⚠️ Panel refresh failed:", error?.message || error));
  }
}

/* The info buttons of a panel answer in the language of the person who clicks. */
async function panelButton(interaction) {
  const [, action, rawType] = String(interaction.customId).split(":"); // panel:<how|fees|mine>:<ltc|paypal>
  const type = rawType === "paypal" ? "paypal" : "ltc";
  const fr = userIsFrench(interaction);
  const T = (en, frText) => (fr ? frText : en);
  const info = middleman.panelInfo();
  const look = PANEL_LOOK[type];
  if (action === "mine") {
    const existing = findOpenTicket(interaction.guild, interaction.user.id, type);
    return interaction.reply({ content: existing ? T(`🎫 Your open ticket: ${existing}`, `🎫 Ton ticket ouvert : ${existing}`) : T("🎫 You have no open ticket. Press the first button to open one.", "🎫 Tu n'as pas de ticket ouvert. Appuie sur le premier bouton pour en ouvrir un."), flags: ephemeral });
  }
  if (action === "fees") {
    const lines =
      type === "paypal"
        ? [
            T(`• Minimum deal: **${info.paypalMin}**`, `• Deal minimum : **${info.paypalMin}**`),
            T("• Currency: **dollars or euros**, you choose in the ticket", "• Devise : **dollars ou euros**, tu choisis dans le ticket"),
            T("• Every payment is **checked by staff** on PayPal before the deal goes on", "• Chaque paiement est **vérifié par le staff** sur PayPal avant la suite du deal"),
            ...(info.paypalNote ? [`• ℹ️ ${info.paypalNote}`] : []),
          ]
        : [
            T(`• Minimum deal: **${info.minLtc} LTC**`, `• Deal minimum : **${info.minLtc} LTC**`),
            T(`• Payment is secured after **${info.confirmations} confirmations**`, `• Le paiement est sécurisé après **${info.confirmations} confirmations**`),
            T("• Only a small **network fee** is taken from the amount sent, nothing else", "• Seuls de petits **frais réseau** sont déduits du montant envoyé, rien d'autre"),
            T("• Type the amount in **LTC, $ or €**", "• Écris le montant en **LTC, $ ou €**"),
          ];
    return interaction.reply({ embeds: [new EmbedBuilder().setColor(look.color).setTitle(T("💰  Fees and limits", "💰  Frais et limites")).setDescription(lines.join("\n"))], flags: ephemeral });
  }
  const how =
    type === "paypal"
      ? [
          T("**1.** Open a ticket and add the person you trade with.", "**1.** Ouvre un ticket et ajoute la personne avec qui tu échanges."),
          T("**2.** Choose who pays and who gets paid, then the amount ($ or €).", "**2.** Choisissez qui paie et qui est payé, puis le montant ($ ou €)."),
          T("**3.** A staff member gives their PayPal, the payer sends the money with the **reference**.", "**3.** Un staff donne son PayPal, le payeur envoie l'argent avec la **référence**."),
          T("**4.** Staff checks the payment. The seller then delivers.", "**4.** Le staff vérifie le paiement. Le vendeur livre ensuite."),
          T("**5.** The payer releases, staff pays the seller. 🎉", "**5.** Le payeur libère, le staff paie le vendeur. 🎉"),
          T("🛟 A problem at any step? **Call staff**: the deal is frozen until staff decides.", "🛟 Un problème ? **Appeler le staff** : le deal est gelé jusqu'à la décision du staff."),
        ]
      : [
          T("**1.** Open a ticket and add the person you trade with.", "**1.** Ouvre un ticket et ajoute la personne avec qui tu échanges."),
          T("**2.** Choose who sends and who receives the LTC, then the amount.", "**2.** Choisissez qui envoie et qui reçoit les LTC, puis le montant."),
          T("**3.** The sender pays the deposit address; the bot waits for the confirmations.", "**3.** L'expéditeur paie l'adresse de dépôt ; le bot attend les confirmations."),
          T("**4.** The receiver delivers what was agreed.", "**4.** Le destinataire donne ce qui était convenu."),
          T("**5.** The sender releases, the bot pays the receiver. 🎉", "**5.** L'expéditeur libère, le bot paie le destinataire. 🎉"),
          T("🚨 The system is **automatic**. If staff or a middleman asks you to pay **their own address**: do not do it and **report it** to an administrator.", "🚨 Le système est **automatique**. Si un staff ou un middleman te demande de payer **sa propre adresse** : ne le fais pas et **signale-le** à un administrateur."),
          T("🛟 A problem at any step? **Call staff**: the deal is frozen until staff decides.", "🛟 Un problème ? **Appeler le staff** : le deal est gelé jusqu'à la décision du staff."),
        ];
  return interaction.reply({ embeds: [new EmbedBuilder().setColor(look.color).setTitle(T("❓  How it works", "❓  Comment ça marche")).setDescription(how.join("\n"))], flags: ephemeral });
}

/* Before a language is chosen, the texts follow the Discord language of the person. */
const userIsFrench = (interaction) => String(interaction.locale || "").toLowerCase().startsWith("fr");
const byUser = (interaction, en, fr) => (userIsFrench(interaction) ? fr : en);
const byLang = (lang, en, fr) => (lang === "fr" ? fr : en);
const topicLang = (channel) => (/:fr$/.test(channel?.topic || "") ? "fr" : "en");

const methodOf = (customId) => (String(customId).split(":")[1] === "paypal" ? "paypal" : "ltc"); // an older panel button is just "open_ticket"

const findOpenTicket = (guild, userId, method) =>
  guild.channels.cache.find(
    (c) => c.type === ChannelType.GuildText && (c.topic?.startsWith(`mm-ticket:${userId}:${method}`) || (method === "ltc" && c.topic === `mm-ticket:${userId}`))
  );

/* Step 1: the person clicked a panel button, ask French or English. */
async function askLanguage(interaction) {
  const method = methodOf(interaction.customId);
  if (method === "paypal") {
    const status = middleman.paypalStatus();
    if (!status.configured) return interaction.reply({ content: byUser(interaction, "❌ PayPal tickets are not available right now.", "❌ Les tickets PayPal ne sont pas disponibles pour le moment."), flags: ephemeral });
    if (!status.available) {
      return interaction.reply({
        content: byUser(interaction, "❌ No PayPal account is available right now (everyone is absent). Please try again later.", "❌ Aucun compte PayPal n'est disponible pour le moment (tout le monde est absent). Réessaie plus tard."),
        flags: ephemeral,
      });
    }
  }
  const existing = findOpenTicket(interaction.guild, interaction.user.id, method);
  if (existing) return interaction.reply({ content: byUser(interaction, `❌ You already have an open ticket: ${existing}`, `❌ Tu as déjà un ticket ouvert : ${existing}`), flags: ephemeral });

  const fr = userIsFrench(interaction);
  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId(`ticket_lang:${method}:fr`).setLabel(fr ? "Français" : "French").setEmoji("🇫🇷").setStyle(ButtonStyle.Primary),
    new ButtonBuilder().setCustomId(`ticket_lang:${method}:en`).setLabel(fr ? "Anglais" : "English").setEmoji("🇬🇧").setStyle(ButtonStyle.Primary)
  );
  return interaction.reply({
    content: fr ? "🌍 **Choisis la langue de ton ticket**\nFrançais ou anglais ?" : "🌍 **Choose the language of your ticket**\nFrench or English?",
    components: [row],
    flags: ephemeral,
  });
}

const parseTicketId = (customId) => {
  const [, rawMethod, rawLang] = String(customId).split(":"); // <prefix>:<method>:<fr|en>
  return { method: rawMethod === "paypal" ? "paypal" : "ltc", lang: rawLang === "fr" ? "fr" : "en" };
};

/* Step 2: the language is chosen. Ask the amount range of the deal with a menu (nothing to ask when there are no ranges). */
async function askTier(interaction) {
  const { method, lang } = parseTicketId(interaction.customId);
  const T = (en, fr) => byLang(lang, en, fr);
  if (method === "paypal") {
    const status = middleman.paypalStatus(); // PayPal may have become unavailable since the panel button was clicked
    if (!status.configured) return interaction.update({ content: T("❌ PayPal tickets are not available right now.", "❌ Les tickets PayPal ne sont pas disponibles pour le moment."), components: [] });
    if (!status.available) {
      return interaction.update({
        content: T("❌ No PayPal account is available right now (everyone is absent). Please try again later.", "❌ Aucun compte PayPal n'est disponible pour le moment (tout le monde est absent). Réessaie plus tard."),
        components: [],
      });
    }
  }
  const options = middleman.tierOptions(lang);
  if (options.length <= 1) return openTicket(interaction, method, lang, options.length ? options[0].value : "");

  const menu = new StringSelectMenuBuilder()
    .setCustomId(`ticket_tier:${method}:${lang}`)
    .setPlaceholder(T("Choose an amount range", "Choisis une tranche de montant"))
    .addOptions(options.map((o) => ({ label: o.label, description: o.description, value: o.value })));
  return interaction.update({
    content: T(
      "💰 **How much is your deal?**\nPick the range that matches the amount of your deal.",
      "💰 **Quelle est la somme de ton deal ?**\nChoisis la tranche qui correspond au montant de ton deal."
    ),
    components: [new ActionRowBuilder().addComponents(menu)],
  });
}

/* Step 3: a range is picked in the menu. */
async function openTicketFromMenu(interaction) {
  const { method, lang } = parseTicketId(interaction.customId);
  return openTicket(interaction, method, lang, String(interaction.values?.[0] || ""));
}

/* Step 4: create the ticket, entirely in the chosen language. */
async function openTicket(interaction, method, lang, tierId = "") {
  const T = (en, fr) => byLang(lang, en, fr);
  const options = middleman.tierOptions(lang);
  const tier = options.find((o) => o.value === tierId);
  if (options.length && !tier) return interaction.update({ content: T("❌ Invalid choice.", "❌ Choix invalide."), components: [] });

  await interaction.update({ content: T("⏳ Creating your ticket…", "⏳ Création de ton ticket…"), components: [] });
  const { guild, user } = interaction;

  if (method === "paypal" && !middleman.paypalStatus().available) {
    return interaction.editReply(T("❌ No PayPal account is available right now (everyone is absent). Please try again later.", "❌ Aucun compte PayPal n'est disponible pour le moment (tout le monde est absent). Réessaie plus tard."));
  }
  const existing = findOpenTicket(guild, user.id, method);
  if (existing) return interaction.editReply(T(`❌ You already have an open ticket: ${existing}`, `❌ Tu as déjà un ticket ouvert : ${existing}`));

  const allow = [
    PermissionFlagsBits.ViewChannel,
    PermissionFlagsBits.SendMessages,
    PermissionFlagsBits.ReadMessageHistory,
    PermissionFlagsBits.AttachFiles,
  ];
  const overwrites = [
    { id: guild.roles.everyone.id, deny: [PermissionFlagsBits.ViewChannel] },
    { id: user.id, allow },
    {
      id: client.user.id,
      allow: [...allow, PermissionFlagsBits.EmbedLinks, PermissionFlagsBits.ManageChannels, PermissionFlagsBits.ManageRoles],
    },
  ];
  let pingRoleId = "";
  if (method === "paypal") {
    if (STAFF_ROLE_ID && guild.roles.cache.has(STAFF_ROLE_ID)) overwrites.push({ id: STAFF_ROLE_ID, allow });
    // the role of the amount range sees this ticket (and no other range's tickets)
    const tierRoleId = tier ? middleman.tierRole(tier.value) : "";
    if (tierRoleId && tierRoleId !== STAFF_ROLE_ID && guild.roles.cache.has(tierRoleId)) overwrites.push({ id: tierRoleId, allow });
    pingRoleId = tierRoleId && guild.roles.cache.has(tierRoleId) ? tierRoleId : STAFF_ROLE_ID;
  } else {
    // Litecoin tickets are private: the opener, the person they add, and only the roles given with /access
    for (const id of middleman.accessRoles()) if (guild.roles.cache.has(id)) overwrites.push({ id, allow });
  }

  const parent = CATEGORY_ID ? await guild.channels.fetch(CATEGORY_ID).catch(() => null) : null;
  const safeName = user.username.toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 18) || "user";

  const channel = await guild.channels.create({
    name: `${method === "paypal" ? "paypal" : "ltc"}-${tier ? `${tier.slug}-` : ""}${safeName}`,
    type: ChannelType.GuildText,
    parent: parent?.type === ChannelType.GuildCategory ? parent.id : undefined,
    topic: `mm-ticket:${user.id}:${method}:${lang}`,
    permissionOverwrites: overwrites,
  });

  const welcome = new EmbedBuilder()
    .setColor(method === "paypal" ? 0x0070ba : 0x5865f2)
    .setTitle(
      method === "paypal"
        ? T("💙  Your PayPal middleman ticket", "💙  Ton ticket middleman PayPal")
        : T("💱  Your Litecoin middleman ticket", "💱  Ton ticket middleman Litecoin")
    )
    .setDescription(
      T(
        `Welcome ${user}!\nFollow the **deal card** below, it guides you step by step and updates by itself.\n\n🚨 Anything wrong? **Call staff** on the card, the deal is frozen until staff decides.`,
        `Bienvenue ${user} !\nSuis la **carte du deal** ci-dessous, elle te guide étape par étape et se met à jour toute seule.\n\n🚨 Un problème ? **Appelle le staff** sur la carte, le deal est gelé jusqu'à la décision du staff.`
      )
    );
  if (tier) welcome.setDescription(`${welcome.data.description}\n\n${T(`🎚️ Range: **${tier.label}**`, `🎚️ Tranche : **${tier.label}**`)}`);
  const close = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId("ticket_close").setLabel(T("Close ticket", "Fermer le ticket")).setEmoji("🔒").setStyle(ButtonStyle.Secondary)
  );
  await channel.send({
    content: pingRoleId ? `<@&${pingRoleId}> ${user}` : `${user}`,
    embeds: [welcome],
    components: [close],
    allowedMentions: { roles: pingRoleId ? [pingRoleId] : [], users: [user.id] },
  });

  await middleman.openDeal(channel, user, method, lang, tier ? tier.value : "").catch((error) => {
    console.error("Middleman could not start:", error?.message || error);
    return channel.send(T("❌ The middleman could not start. Staff has been pinged.", "❌ Le middleman n'a pas pu démarrer. Le staff est prévenu.")).catch(() => {});
  });

  return interaction.editReply(T(`✅ Ticket created: ${channel}`, `✅ Ticket créé : ${channel}`));
}

async function closeTicket(interaction) {
  const channel = interaction.channel;
  const lang = topicLang(channel);
  const T = (en, fr) => byLang(lang, en, fr);
  if (!channel?.topic?.startsWith("mm-ticket:")) {
    return interaction.reply({ content: T("❌ This is not a middleman ticket.", "❌ Ce n'est pas un ticket middleman."), flags: ephemeral });
  }
  const ownerId = channel.topic.split(":")[1];
  if (interaction.user.id !== ownerId && !middleman.isStaffFor(channel.id, interaction.member)) {
    return interaction.reply({ content: T("❌ Only the ticket owner or staff can close this ticket.", "❌ Seul le propriétaire du ticket ou le staff peut fermer ce ticket."), flags: ephemeral });
  }
  if (middleman.blocksClose(channel.id)) {
    return interaction.reply({ content: T("❌ The deal in this ticket still holds funds. Finish it or refund it first.", "❌ Le deal de ce ticket garde encore des fonds. Termine-le ou rembourse-le d'abord."), flags: ephemeral });
  }
  middleman.forget(channel.id);
  await interaction.deferUpdate().catch(() => {}); // acknowledged with no message: the channel is gone right away
  await channel.delete("middleman ticket closed").catch((error) => console.error("⚠️ Could not delete the ticket:", error?.message || error));
}

/* ---------- events ---------- */

const onInteraction = async (interaction) => {
  try {
    if (await middleman.handleInteraction(interaction)) return;
    if (await tools.handleInteraction(interaction)) return;

    if (interaction.isChatInputCommand() && interaction.commandName === "panel") return await postPanel(interaction);
    if (interaction.isButton() && String(interaction.customId).startsWith("panel:")) return await panelButton(interaction);
    if (interaction.isButton() && (interaction.customId === "open_ticket" || interaction.customId.startsWith("open_ticket:"))) return await askLanguage(interaction);
    if (interaction.isButton() && interaction.customId.startsWith("ticket_lang:")) return await askTier(interaction);
    if (interaction.isStringSelectMenu?.() && interaction.customId.startsWith("ticket_tier:")) return await openTicketFromMenu(interaction);
    if (interaction.isButton() && interaction.customId === "ticket_close") return await closeTicket(interaction);
  } catch (error) {
    console.error("Interaction error:", error?.message || error);
    const message = { content: "❌ Something went wrong. Check the bot console.", flags: ephemeral };
    if (interaction.deferred || interaction.replied) await interaction.followUp(message).catch(() => {});
    else await interaction.reply(message).catch(() => {});
  }
};

const onReady = () => {
  console.log(`✅ Logged in as ${client.user.tag}`);
  middleman.init(client, { staffRoleId: STAFF_ROLE_ID, ownerRoleId: "", logChannelId: LOG_CHANNEL_ID });
  refreshPanels().catch(() => {});
  setInterval(() => refreshPanels().catch(() => {}), 5 * 60_000).unref?.();
};

const onInvalidated = () => {
  console.error("❌ Discord session invalidated: restarting the bot.");
  process.exit(1);
};

let toolsAttached = false;
function wire(canReadMessages) {
  client.on(Events.InteractionCreate, onInteraction);
  client.once(Events.ClientReady, onReady);
  client.on(Events.Invalidated, onInvalidated);
  if (!toolsAttached) {
    toolsAttached = true;
    tools.attach(client, canReadMessages);
  }
}

/* The Message Content and Server Members intents must be switched on in the Developer Portal.
   When they are not, the bot starts anyway without them (levels still work, but not anti-links and welcome). */
async function loginWithFallback() {
  wire(tools.ON);
  try {
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    if (!tools.ON || !/disallowed intents/i.test(String(error?.message || error))) throw error;
    console.warn("⚠️ The Message Content / Server Members intents are not enabled: starting without them. Switch them on in the Discord Developer Portal (Bot tab, Privileged Gateway Intents), then restart.");
    await client.destroy().catch(() => {});
    client = new Client({ intents: BASIC_INTENTS });
    client.on(Events.InteractionCreate, onInteraction);
    client.once(Events.ClientReady, onReady);
    client.on(Events.Invalidated, onInvalidated);
    tools.attach(client, false);
    await client.login(process.env.DISCORD_TOKEN);
  }
}

(async () => {
  try {
    const rest = new REST({ version: "10" }).setToken(process.env.DISCORD_TOKEN);
    await rest.put(Routes.applicationGuildCommands(process.env.CLIENT_ID, process.env.GUILD_ID), {
      body: [
        new SlashCommandBuilder()
          .setName("panel")
          .setDescription("Post a middleman ticket panel here.")
          .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
          .addStringOption((option) =>
            option
              .setName("type")
              .setDescription("Which panel to post (default: Litecoin)")
              .addChoices({ name: "Litecoin (automatic)", value: "ltc" }, { name: "PayPal (manual, checked by staff)", value: "paypal" })
          )
          .toJSON(),
        new SlashCommandBuilder().setName("paypal").setDescription("Manage the PayPal accounts: add, change, remove, set present or absent").setDefaultMemberPermissions(PermissionFlagsBits.ManageMessages).toJSON(),
        new SlashCommandBuilder().setName("access").setDescription("Choose which roles can see the private Litecoin tickets").setDefaultMemberPermissions(PermissionFlagsBits.Administrator).toJSON(),
        new SlashCommandBuilder().setName("tiers").setDescription("Manage the amount ranges and the staff role of each one").setDefaultMemberPermissions(PermissionFlagsBits.Administrator).toJSON(),
        ...tools.commands(),
      ],
    });
    await loginWithFallback();
  } catch (error) {
    console.error("❌ Could not start:", error?.message || error);
    process.exit(1);
  }
})();
