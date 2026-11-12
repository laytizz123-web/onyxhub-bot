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
        await reply(interaction, T("🗑️ Closing the channel...", "🗑️ Fermeture du salon..."));
        delete store.deals[deal.channelId];
        saveStore();
        return setTimeout(() => interaction.channel?.delete().catch(() => {}), 3000);
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
   IMAGES: tiny PNG drawing kit (no library to install) used by the multitools cards
===================================================== */

const gfx = (() => {
  const zlib = require("zlib");
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

  const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

  class Canvas {
    constructor(w, h, bg = "#1e1f2e", bg2 = null) {
      this.w = w;
      this.h = h;
      this.px = new Uint8Array(w * h * 4);
      const a = hex(bg);
      const b = hex(bg2 || bg);
      for (let y = 0; y < h; y++) {
        const f = h > 1 ? y / (h - 1) : 0;
        for (let x = 0; x < w; x++) {
          const i = (y * w + x) * 4;
          this.px[i] = a[0] + (b[0] - a[0]) * f;
          this.px[i + 1] = a[1] + (b[1] - a[1]) * f;
          this.px[i + 2] = a[2] + (b[2] - a[2]) * f;
          this.px[i + 3] = 255;
        }
      }
    }
    blend(x, y, c, a) {
      if (a <= 0 || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
      const i = (y * this.w + x) * 4;
      this.px[i] += (c[0] - this.px[i]) * a;
      this.px[i + 1] += (c[1] - this.px[i + 1]) * a;
      this.px[i + 2] += (c[2] - this.px[i + 2]) * a;
    }
    /* Fills the pixels where sdf(x, y) <= 0, with a soft edge. */
    shape(sdf, x0, y0, x1, y1, color, alpha = 1) {
      const c = hex(color);
      for (let y = Math.max(0, Math.floor(y0)); y < Math.min(this.h, Math.ceil(y1)); y++) {
        for (let x = Math.max(0, Math.floor(x0)); x < Math.min(this.w, Math.ceil(x1)); x++) {
          const cover = clamp01(0.5 - sdf(x + 0.5, y + 0.5));
          if (cover > 0) this.blend(x, y, c, cover * alpha);
        }
      }
    }
    rect(x, y, w, h, color, alpha = 1) {
      this.shape((px, py) => Math.max(Math.abs(px - (x + w / 2)) - w / 2, Math.abs(py - (y + h / 2)) - h / 2), x, y, x + w, y + h, color, alpha);
    }
    round(x, y, w, h, r, color, alpha = 1) {
      r = Math.min(r, w / 2, h / 2);
      this.shape(
        (px, py) => {
          const dx = Math.abs(px - (x + w / 2)) - (w / 2 - r);
          const dy = Math.abs(py - (y + h / 2)) - (h / 2 - r);
          return Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) + Math.min(Math.max(dx, dy), 0) - r;
        },
        x - 1, y - 1, x + w + 1, y + h + 1, color, alpha
      );
    }
    circle(cx, cy, r, color, alpha = 1) {
      this.shape((px, py) => Math.hypot(px - cx, py - cy) - r, cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, color, alpha);
    }
    ring(cx, cy, r, thickness, color, alpha = 1) {
      this.shape((px, py) => Math.abs(Math.hypot(px - cx, py - cy) - r) - thickness / 2, cx - r - thickness, cy - r - thickness, cx + r + thickness, cy + r + thickness, color, alpha);
    }
    text(str, x, y, scale, color = "#ffffff", align = "left") {
      const s = ascii(str);
      const width = measure(s, scale);
      let cx = align === "center" ? x - width / 2 : align === "right" ? x - width : x;
      const c = hex(color);
      for (const ch of s) {
        const g = FONT[ch] || FONT["?"];
        for (let row = 0; row < 7; row++) {
          for (let col = 0; col < 5; col++) {
            if (g[row][col] !== "1") continue;
            for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) this.blend(Math.round(cx) + col * scale + dx, Math.round(y) + row * scale + dy, c, 1);
          }
        }
        cx += 6 * scale;
      }
    }
    png() {
      const raw = Buffer.alloc((this.w * 4 + 1) * this.h);
      for (let y = 0; y < this.h; y++) {
        raw[y * (this.w * 4 + 1)] = 0;
        Buffer.from(this.px.buffer, this.px.byteOffset + y * this.w * 4, this.w * 4).copy(raw, y * (this.w * 4 + 1) + 1);
      }
      const ihdr = Buffer.alloc(13);
      ihdr.writeUInt32BE(this.w, 0);
      ihdr.writeUInt32BE(this.h, 4);
      ihdr[8] = 8; // bit depth
      ihdr[9] = 6; // RGBA
      return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 6 })), chunk("IEND", Buffer.alloc(0))]);
    }
  }

  /* 5x7 pixel font: letters (as capitals), digits and a few signs. */
  const G = (s) => s.trim().split(/\s+/);
  const FONT = {
    " ": G("00000 00000 00000 00000 00000 00000 00000"),
    A: G("01110 10001 10001 11111 10001 10001 10001"), B: G("11110 10001 10001 11110 10001 10001 11110"), C: G("01110 10001 10000 10000 10000 10001 01110"),
    D: G("11110 10001 10001 10001 10001 10001 11110"), E: G("11111 10000 10000 11110 10000 10000 11111"), F: G("11111 10000 10000 11110 10000 10000 10000"),
    G: G("01110 10001 10000 10111 10001 10001 01111"), H: G("10001 10001 10001 11111 10001 10001 10001"), I: G("01110 00100 00100 00100 00100 00100 01110"),
    J: G("00111 00010 00010 00010 00010 10010 01100"), K: G("10001 10010 10100 11000 10100 10010 10001"), L: G("10000 10000 10000 10000 10000 10000 11111"),
    M: G("10001 11011 10101 10101 10001 10001 10001"), N: G("10001 11001 10101 10011 10001 10001 10001"), O: G("01110 10001 10001 10001 10001 10001 01110"),
    P: G("11110 10001 10001 11110 10000 10000 10000"), Q: G("01110 10001 10001 10001 10101 10010 01101"), R: G("11110 10001 10001 11110 10100 10010 10001"),
    S: G("01111 10000 10000 01110 00001 00001 11110"), T: G("11111 00100 00100 00100 00100 00100 00100"), U: G("10001 10001 10001 10001 10001 10001 01110"),
    V: G("10001 10001 10001 10001 10001 01010 00100"), W: G("10001 10001 10001 10101 10101 10101 01010"), X: G("10001 10001 01010 00100 01010 10001 10001"),
    Y: G("10001 10001 01010 00100 00100 00100 00100"), Z: G("11111 00001 00010 00100 01000 10000 11111"),
    0: G("01110 10001 10011 10101 11001 10001 01110"), 1: G("00100 01100 00100 00100 00100 00100 01110"), 2: G("01110 10001 00001 00010 00100 01000 11111"),
    3: G("11110 00001 00001 01110 00001 00001 11110"), 4: G("00010 00110 01010 10010 11111 00010 00010"), 5: G("11111 10000 11110 00001 00001 10001 01110"),
    6: G("00110 01000 10000 11110 10001 10001 01110"), 7: G("11111 00001 00010 00100 01000 01000 01000"), 8: G("01110 10001 10001 01110 10001 10001 01110"),
    9: G("01110 10001 10001 01111 00001 00010 01100"),
    ".": G("00000 00000 00000 00000 00000 01100 01100"), ",": G("00000 00000 00000 00000 01100 00100 01000"), ":": G("00000 01100 01100 00000 01100 01100 00000"),
    "!": G("00100 00100 00100 00100 00100 00000 00100"), "?": G("01110 10001 00001 00110 00100 00000 00100"), "-": G("00000 00000 00000 11111 00000 00000 00000"),
    "+": G("00000 00100 00100 11111 00100 00100 00000"), "/": G("00001 00010 00010 00100 01000 01000 10000"), "%": G("11001 11010 00010 00100 01000 01011 10011"),
    "#": G("01010 01010 11111 01010 11111 01010 01010"), "=": G("00000 00000 11111 00000 11111 00000 00000"), "'": G("00100 00100 01000 00000 00000 00000 00000"),
    "(": G("00010 00100 01000 01000 01000 00100 00010"), ")": G("01000 00100 00010 00010 00010 00100 01000"), "*": G("00000 10101 01110 11111 01110 10101 00000"),
    _: G("00000 00000 00000 00000 00000 00000 11111"),
  };
  const ascii = (str) =>
    String(str ?? "")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[×✕]/g, "X")
      .toUpperCase()
      .replace(/\s+/g, " ")
      .split("")
      .map((ch) => (FONT[ch] ? ch : "?"))
      .join("");
  const measure = (str, scale) => (ascii(str).length ? ascii(str).length * 6 * scale - scale : 0);
  const fit = (str, maxWidth, maxScale) => {
    let s = maxScale;
    while (s > 1 && measure(str, s) > maxWidth) s--;
    return s;
  };
  const cut = (str, maxWidth, scale) => {
    let s = ascii(str);
    while (s.length > 1 && measure(s, scale) > maxWidth) s = s.slice(0, -1);
    return s;
  };
  const hue = (seed) => {
    let h = 0;
    for (const ch of String(seed)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    const palette = ["#5865f2", "#eb459e", "#57f287", "#fee75c", "#ed4245", "#3498db", "#e67e22", "#9b59b6"];
    return palette[h % palette.length];
  };

  /* ---------- cards ---------- */
  function rank({ name, level, into, need, rank: place, xp, label }) {
    const c = new Canvas(640, 200, "#1e1f2e", "#2b2d42");
    c.round(14, 14, 612, 172, 22, "#ffffff", 0.06);
    c.circle(100, 100, 54, hue(name));
    c.text((ascii(name)[0] || "?"), 100, 78, 6, "#ffffff", "center");
    c.text(cut(name, 380, 4), 180, 34, 4, "#ffffff");
    c.text(`${label.level} ${level}`, 180, 72, 3, "#fee75c");
    c.text(`${label.rank} #${place}`, 620, 72, 3, "#b9bbbe", "right");
    c.round(180, 118, 420, 26, 13, "#000000", 0.35);
    const fill = Math.max(0, Math.min(1, into / need));
    if (fill > 0) c.round(180, 118, Math.max(26, 420 * fill), 26, 13, "#57f287");
    c.text(`${into} / ${need} XP`, 600, 154, 2, "#b9bbbe", "right");
    c.text(`${xp} XP`, 180, 154, 2, "#b9bbbe");
    return c.png();
  }

  function leaderboard(rows, label) {
    const rowH = 58;
    const h = 96 + rows.length * rowH + 16;
    const c = new Canvas(720, h, "#1e1f2e", "#2b2d42");
    c.text(label.title, 360, 26, 6, "#fee75c", "center");
    const medal = ["#f1c40f", "#bdc3c7", "#cd7f32"];
    rows.forEach((r, n) => {
      const y = 92 + n * rowH;
      c.round(20, y, 680, rowH - 8, 14, "#ffffff", n % 2 ? 0.04 : 0.08);
      c.circle(60, y + 25, 19, medal[n] || "#4f545c");
      c.text(String(n + 1), 60, y + 15, 3, n < 3 ? "#1e1f2e" : "#ffffff", "center");
      c.text(cut(r.name, 330, 3), 96, y + 6, 3, "#ffffff");
      c.round(96, y + 33, 300, 8, 4, "#000000", 0.35);
      const f = Math.max(0, Math.min(1, r.into / r.need));
      if (f > 0) c.round(96, y + 33, Math.max(8, 300 * f), 8, 4, "#57f287");
      c.text(`${label.level} ${r.level}`, 676, y + 6, 3, "#fee75c", "right");
      c.text(`${r.xp} XP`, 676, y + 32, 2, "#b9bbbe", "right");
    });
    return c.png();
  }

  function levelUp({ name, level, label }) {
    const c = new Canvas(560, 170, "#2c2f6b", "#1e1f2e");
    c.round(12, 12, 536, 146, 20, "#ffffff", 0.07);
    c.text(label.up, 280, 28, fit(label.up, 480, 6), "#fee75c", "center");
    c.text(cut(name, 500, 3), 280, 86, 3, "#ffffff", "center");
    c.text(`${label.level} ${level}`, 280, 120, 4, "#57f287", "center");
    return c.png();
  }

  function coin(face /* "A" or "B" */, letter) {
    const c = new Canvas(280, 280, "#2b2d31");
    c.circle(142, 148, 118, "#000000", 0.25); // shadow
    c.circle(140, 140, 118, "#b8860b");
    c.circle(140, 140, 108, "#f1c40f");
    c.ring(140, 140, 90, 6, "#b8860b");
    c.text(letter, 140, 140 - 7 * 7, 14, "#8a6508", "center");
    c.circle(72, 78, 9, "#ffffff", 0.3);
    return c.png();
  }

  function dice(faces, value) {
    const c = new Canvas(280, 280, "#2b2d31");
    c.round(48, 56, 190, 190, 38, "#000000", 0.25);
    c.round(40, 44, 190, 190, 38, "#f8f9fa");
    const pips = { 1: [[0, 0]], 2: [[-1, -1], [1, 1]], 3: [[-1, -1], [0, 0], [1, 1]], 4: [[-1, -1], [1, -1], [-1, 1], [1, 1]], 5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]], 6: [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]] };
    if (faces <= 6) for (const [dx, dy] of pips[value]) c.circle(135 + dx * 48, 139 + dy * 48, 17, "#1e1f2e");
    else {
      const s = fit(String(value), 150, 12);
      c.text(String(value), 135, 139 - (7 * s) / 2, s, "#1e1f2e", "center");
    }
    return c.png();
  }

  function eightBall() {
    const c = new Canvas(280, 280, "#2b2d31");
    c.circle(146, 150, 118, "#000000", 0.3);
    c.circle(140, 140, 118, "#111318");
    c.circle(110, 90, 40, "#ffffff", 0.07);
    c.circle(140, 128, 54, "#f8f9fa");
    c.text("8", 140, 128 - 28, 8, "#111318", "center");
    return c.png();
  }

  function quizCard(lines, label) {
    const c = new Canvas(640, 260, "#2c2f6b", "#1e1f2e");
    c.round(12, 12, 616, 236, 22, "#ffffff", 0.07);
    c.text(label, 36, 30, 4, "#fee75c");
    const scale = Math.min(...lines.map((l) => fit(l, 560, 10)));
    const total = lines.length * 7 * scale + (lines.length - 1) * 14;
    let y = 150 - total / 2 + 20;
    for (const l of lines) {
      c.text(l, 320, y, scale, "#ffffff", "center");
      y += 7 * scale + 14;
    }
    return c.png();
  }

  function banner(title, subtitle, colorA, colorB) {
    const c = new Canvas(720, 220, colorA, colorB);
    c.circle(650, 30, 100, "#ffffff", 0.07);
    c.circle(700, 200, 130, "#ffffff", 0.05);
    c.circle(30, 230, 90, "#ffffff", 0.05);
    c.round(24, 24, 672, 172, 26, "#000000", 0.2);
    c.text(title, 360, 54, fit(title, 620, 10), "#ffffff", "center");
    c.text(subtitle, 360, 142, fit(subtitle, 620, 4), "#fee75c", "center");
    return c.png();
  }

  return { Canvas, banner, rank, leaderboard, levelUp, coin, dice, eightBall, quizCard, ascii, measure };
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
    PermissionFlagsBits: P,
    SlashCommandBuilder,
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
    voc: { hubs: [], rooms: {} },
    setup: { items: [], voiceItems: [], levelRoles: [], autoWelcome: false },
    cfg: {
      levels: { on: true, rewards: [], announce: true, ignored: [], channelId: "", quizXp: 50, stack: false },
      welcome: { channelId: "", message: "", leave: "", autorole: "" },
      logs: { channelId: "" },
      suggest: { channelId: "" },
      autoquiz: { on: false, channelId: "", minutes: 30, nextAt: 0 },
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
    next.voc = { ...base.voc, ...(raw.voc || {}) };
    if (!Array.isArray(next.voc.hubs)) next.voc.hubs = [];
    if (!next.voc.rooms || typeof next.voc.rooms !== "object") next.voc.rooms = {};
    for (const key of ["xp", "warns", "polls", "giveaways", "locks"]) if (!next[key] || typeof next[key] !== "object") next[key] = {};
    for (const [group, keys] of [[next.setup, ["items", "voiceItems", "levelRoles"]], [next.cfg.levels, ["rewards", "ignored"]]]) for (const k of keys) if (!Array.isArray(group[k])) group[k] = [];
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

  const cardLabel = () => ({ level: t("NIVEAU", "LEVEL"), rank: t("RANG", "RANK"), title: t("CLASSEMENT", "LEADERBOARD"), up: t("NIVEAU SUPERIEUR !", "LEVEL UP!") });
  const picture = (name, buffer) => ({ file: new AttachmentBuilder(buffer, { name }), url: `attachment://${name}` });

  async function announceLevel(member, level, fallbackChannel) {
    const cfg = db.cfg.levels;
    let channel = fallbackChannel;
    if (cfg.channelId) {
      const chosen = await Promise.resolve(member.guild?.channels?.fetch?.(cfg.channelId)).catch(() => null);
      if (chosen?.isTextBased?.()) channel = chosen;
    }
    if (!channel?.send) return;
    const name = member.displayName || member.user?.username || "?";
    const card = picture("levelup.png", gfx.levelUp({ name, level, label: cardLabel() }));
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
  async function addXp(member, amount, fallbackChannel) {
    const before = levelOf(db.xp[member.id] || 0).level;
    db.xp[member.id] = (db.xp[member.id] || 0) + amount;
    const after = levelOf(db.xp[member.id]).level;
    save();
    await giveRewards(member, after);
    if (after > before && db.cfg.levels.announce) await announceLevel(member, after, fallbackChannel);
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
          .addSubcommand((s) => s.setName("leave").setDescription(t("Texte de départ : {user} {server}", "Leave text: {user} {server}")).addStringOption((o) => o.setName("texte").setDescription("{user} {server}").setRequired(true).setMaxLength(1000)))
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
      strOpt(cmd("suggest", t("Proposer une idée", "Suggest an idea")), "idee", t("Ton idée", "Your idea"), true, 900),
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
      // voice channels
      cmd("voc", t("Salons vocaux : en créer, ou gérer ton vocal", "Voice channels: create one, or manage yours"))
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
        .addSubcommand((s) => s.setName("rename").setDescription(t("Renommer ton vocal", "Rename your voice channel")).addStringOption((o) => o.setName("nom").setDescription(t("Nouveau nom", "New name")).setRequired(true).setMaxLength(80)))
        .addSubcommand((s) => s.setName("limit").setDescription(t("Limiter les places de ton vocal", "Limit the seats of your voice channel")).addIntegerOption((o) => o.setName("places").setDescription(t("0 = illimité", "0 = unlimited")).setRequired(true).setMinValue(0).setMaxValue(99)))
        .addSubcommand((s) => s.setName("lock").setDescription(t("Fermer ton vocal : plus personne ne peut le rejoindre", "Close your voice channel: nobody else can join")))
        .addSubcommand((s) => s.setName("unlock").setDescription(t("Rouvrir ton vocal", "Open your voice channel again"))),
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
  const NAMES = new Set(["rank", "leaderboard", "levels", "xp", "ban", "unban", "kick", "timeout", "untimeout", "warn", "warnings", "clearwarns", "clear", "welcome", "rolepanel", "poll", "giveaway", "suggest", "suggestions", "8ball", "coinflip", "dice", "avatar", "userinfo", "serverinfo", "ping", "help", "logs", "security", "setup", "quiz", "autoquiz", "lock", "unlock", "voc"]);

  /* ---------- command handlers ---------- */
  const H = {};

  H.rank = async (i) => {
    const user = i.options.getUser("membre") || i.user;
    const xp = db.xp[user.id] || 0;
    const l = levelOf(xp);
    const member = await i.guild.members.fetch(user.id).catch(() => null);
    const name = member?.displayName || user.username;
    const card = picture("rank.png", gfx.rank({ name, level: l.level, into: l.into, need: l.need, rank: rankOf(user.id), xp, label: cardLabel() }));
    const e = embed().setAuthor({ name: user.username, iconURL: user.displayAvatarURL?.() }).setTitle(t(`Niveau ${l.level}`, `Level ${l.level}`)).setImage(card.url);
    return i.reply({ embeds: [e], files: [card.file] });
  };

  H.leaderboard = async (i) => {
    const top = Object.entries(db.xp).sort((a, b) => b[1] - a[1]).slice(0, 10);
    if (!top.length) return reply(i, t("Personne n'a encore d'XP.", "Nobody has XP yet."));
    await i.deferReply();
    const rows = [];
    for (const [id, xp] of top) {
      const m = await i.guild.members.fetch(id).catch(() => null);
      const l = levelOf(xp);
      rows.push({ name: m?.displayName || m?.user?.username || t("Ancien membre", "Former member"), level: l.level, into: l.into, need: l.need, xp });
    }
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
  async function ownRoom(i) {
    const id = i.member?.voice?.channelId;
    const room = id ? db.voc.rooms[id] : null;
    if (!room) return reply(i, no(t("Rejoins d'abord ton vocal (créé avec « ➕ Créer ton vocal »).", "Join your own voice room first (made with \"➕ Create your voice\").")));
    if (room.owner !== i.user.id && !i.member.permissions?.has?.(P.ManageChannels)) return reply(i, no(t("Ce vocal appartient à quelqu'un d'autre.", "This voice room belongs to someone else.")));
    return i.member.voice.channel || (await i.guild.channels.fetch(id).catch(() => null)) || reply(i, no(t("Vocal introuvable.", "Voice channel not found.")));
  }
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
    const channel = await ownRoom(i);
    if (!channel?.id) return; // ownRoom already answered
    try {
      if (sub === "rename") await channel.setName(`🔊│${i.options.getString("nom")}`.slice(0, 100));
      if (sub === "limit") await channel.setUserLimit(i.options.getInteger("places"));
      if (sub === "lock") await channel.permissionOverwrites.edit(i.guild.roles.everyone.id, { Connect: false });
      if (sub === "unlock") await channel.permissionOverwrites.edit(i.guild.roles.everyone.id, { Connect: null });
    } catch {
      return reply(i, no(t("Je n'ai pas pu modifier ce vocal.", "I could not change this voice room.")));
    }
    const done = { rename: t("Vocal renommé.", "Voice room renamed."), limit: t("Nombre de places modifié.", "Seats changed."), lock: t("🔒 Vocal fermé : plus personne ne peut le rejoindre.", "🔒 Voice room closed: nobody else can join."), unlock: t("🔓 Vocal rouvert.", "🔓 Voice room open again.") };
    return reply(i, ok(done[sub]));
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
      w.leave = i.options.getString("texte");
      save();
      return reply(i, ok(t("Message de départ enregistré.", "Leave message saved.")));
    }
    if (sub === "autorole") {
      const role = i.options.getRole("role");
      w.autorole = role?.id || "";
      save();
      return reply(i, ok(role ? t(`Les nouveaux recevront ${role}.`, `New members will get ${role}.`) : t("Plus de rôle automatique.", "No more auto role.")));
    }
    if (sub === "off") {
      db.cfg.welcome = { channelId: "", message: "", leave: "", autorole: "" };
      save();
      return reply(i, ok(t("Bienvenue coupé.", "Welcome turned off.")));
    }
    if (sub === "test") {
      if (!w.message) return reply(i, no(t("Aucun message. Utilise `/welcome channel`.", "No message. Use `/welcome channel`.")));
      return reply(i, fill(w.message, i.member));
    }
  };
  async function onJoin(member) {
    const w = db.cfg.welcome;
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
      if (channel?.isTextBased?.()) await channel.send({ content: fill(w.message, member), allowedMentions: { users: [member.id] } }).catch(() => {});
    }
    await log(member.guild, `📥 ${member.user} ${t("a rejoint", "joined")}  ·  ${t("compte créé", "account created")} <t:${Math.floor(member.user.createdTimestamp / 1000)}:R>`, 0x2ecc71);
  }
  async function onLeave(member) {
    const w = db.cfg.welcome;
    if (w.channelId && w.leave) {
      const channel = await member.guild.channels.fetch(w.channelId).catch(() => null);
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
  const gwEmbed = (g, ended = false, winners = []) =>
    embed(ended ? 0x747f8d : 0xf1c40f)
      .setTitle(`🎉 ${g.prize}`)
      .setDescription(
        ended
          ? winners.length ? t(`Gagnant(s) : ${winners.map((w) => `<@${w}>`).join(", ")}`, `Winner(s): ${winners.map((w) => `<@${w}>`).join(", ")}`) : t("Personne n'a participé.", "Nobody joined.")
          : t(`Appuie sur le bouton pour participer !\nFin : <t:${Math.floor(g.endsAt / 1000)}:R>\nGagnant(s) : **${g.winners}**`, `Press the button to join!\nEnds: <t:${Math.floor(g.endsAt / 1000)}:R>\nWinner(s): **${g.winners}**`)
      )
      .setFooter({ text: t(`${g.entries.length} participant(s)`, `${g.entries.length} entrant(s)`) });
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
    if (message) await message.edit({ embeds: [gwEmbed(g, true, winners)], components: [] }).catch(() => {});
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
      const g = { channelId: i.channelId, prize: i.options.getString("lot"), winners: i.options.getInteger("gagnants") || 1, endsAt: Date.now() + ms, entries: [], ended: false };
      const row = new ActionRowBuilder().addComponents(new ButtonBuilder().setCustomId("tl:gw").setLabel(t("Participer", "Join")).setEmoji("🎉").setStyle(ButtonStyle.Success));
      await i.reply({ embeds: [gwEmbed(g)], components: [row] });
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
      await i.update({ embeds: [gwEmbed(g)] });
      return;
    }
    g.entries.push(i.user.id);
    save();
    return i.update({ embeds: [gwEmbed(g)] });
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
    const card = picture("coin.png", gfx.coin(heads ? "A" : "B", heads ? t("F", "H") : t("P", "T")));
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
      return { kind, question: t("🔤 Remets les lettres dans l'ordre : quel est ce mot ?", "🔤 Put the letters in order: what is this word?"), image: gfx.quizCard([shuffle(word)], "QUIZ"), answers: [norm(word)], reveal: word.toLowerCase() };
    }
    const op = pick(["+", "-", "*"]);
    let a = 0;
    let b = 0;
    if (op === "*") { a = 2 + Math.floor(Math.random() * 11); b = 2 + Math.floor(Math.random() * 11); }
    else { a = 10 + Math.floor(Math.random() * 90); b = 10 + Math.floor(Math.random() * 90); if (op === "-" && b > a) [a, b] = [b, a]; }
    const result = op === "+" ? a + b : op === "-" ? a - b : a * b;
    return { kind: "math", question: t("🧮 Combien font ce calcul ?", "🧮 What is the result?"), image: gfx.quizCard([`${a} ${op === "*" ? "X" : op} ${b} = ?`], "QUIZ"), answers: [String(result)], reveal: String(result) };
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
      ] },
      { category: t("💬 COMMUNAUTÉ", "💬 COMMUNITY"), channels: [
        { key: "general", name: t("💬│général", "💬│general"), kind: "text" },
        { key: "media", name: t("🖼️│médias", "🖼️│media"), kind: "text" },
        { key: "commands", name: t("🤖│commandes", "🤖│commands"), kind: "text" },
        { key: "suggestions", name: t("💡│suggestions", "💡│suggestions"), kind: "readonly" },
        { key: "levels", name: t("📈│niveaux", "📈│levels"), kind: "text" },
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
        { key: "scam", name: t("🚨│anti-scam", "🚨│scam-alerts"), kind: "readonly", topic: t("Comment ne pas te faire arnaquer. Utilise toujours un middleman.", "How not to get scammed. Always use a middleman.") },
      ] },
      { category: t("💬 COMMUNAUTÉ", "💬 COMMUNITY"), channels: [
        { key: "general", name: t("💬│général", "💬│general"), kind: "text" },
        { key: "memes", name: t("🧠│brainrot-memes", "🧠│brainrot-memes"), kind: "text", slow: 5 },
        { key: "clips", name: t("🎥│clips-steal", "🎥│steal-clips"), kind: "text", topic: t("Tes meilleurs vols et clips de Steal a Brainrot.", "Your best steals and Steal a Brainrot clips.") },
        { key: "commands", name: t("🤖│commandes", "🤖│commands"), kind: "text" },
        { key: "levels", name: t("📈│niveaux", "📈│levels"), kind: "text" },
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
    if (made.logs) db.cfg.logs.channelId = made.logs.id;
    if (made.levels) db.cfg.levels.channelId = made.levels.id;
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
    if (ids.has(db.cfg.logs.channelId)) db.cfg.logs.channelId = "";
    if (ids.has(db.cfg.suggest.channelId)) db.cfg.suggest.channelId = "";
    if (ids.has(db.cfg.levels.channelId)) db.cfg.levels.channelId = "";
    if (ids.has(db.cfg.autoquiz.channelId)) Object.assign(db.cfg.autoquiz, { on: false, channelId: "", nextAt: 0 });
    db.cfg.levels.ignored = db.cfg.levels.ignored.filter((c) => !ids.has(c));
    db.setup.items = [];
    const rolesRemoved = db.setup.levelRoles.length ? await removeLevelRoles(i.guild) : 0;
    save(true);
    return i.editReply({ content: ok(t(`${removed} salon(s) et catégorie(s) supprimé(s)${rolesRemoved ? `, ${rolesRemoved} rôle(s) de niveau` : ""}.`, `${removed} channel(s) and category(ies) deleted${rolesRemoved ? `, ${rolesRemoved} level role(s)` : ""}.`)), components: [] });
  }

  H.help = (i) =>
    i.reply({
      flags: ephemeral,
      embeds: [
        embed()
          .setTitle(t("🧰 Commandes", "🧰 Commands"))
          .addFields(
            { name: t("📈 Niveaux", "📈 Levels"), value: "`/rank` `/leaderboard` `/levels` `/xp` `/quiz` `/autoquiz`" },
            { name: t("🔨 Modération", "🔨 Moderation"), value: "`/ban` `/unban` `/kick` `/timeout` `/untimeout` `/warn` `/warnings` `/clearwarns` `/clear` `/lock` `/unlock`" },
            { name: t("👋 Bienvenue et rôles", "👋 Welcome and roles"), value: "`/welcome` `/rolepanel`" },
            { name: t("🎉 Fun et outils", "🎉 Fun and tools"), value: "`/poll` `/giveaway` `/suggest` `/suggestions` `/8ball` `/quiz` `/coinflip` `/dice` `/avatar` `/userinfo` `/serverinfo` `/ping`" },
            { name: t("🛡️ Logs et sécurité", "🛡️ Logs and security"), value: "`/logs` `/security`" },
            { name: t("🔊 Vocaux", "🔊 Voice"), value: "`/voc create` `/voc hub` `/voc rename` `/voc limit` `/voc lock` `/voc unlock`" },
            { name: t("🏗️ Salons automatiques", "🏗️ Automatic channels"), value: "`/setup create` `/setup delete` `/setup voc-create` `/setup voc-delete` `/setup status`" },
            { name: t("💱 Middleman", "💱 Middleman"), value: "`/panel` `/paypal` `/tiers` `/access`" }
          ),
      ],
    });

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

  /* ---------- wiring ---------- */
  async function handleInteraction(i) {
    if (!ON) return false;
    try {
      if (i.isChatInputCommand?.() && NAMES.has(i.commandName)) {
        if (!i.guild) return (await reply(i, no(t("Utilise cette commande sur le serveur.", "Use this command in the server."))), true);
        await H[i.commandName](i);
        return true;
      }
      if (i.isButton?.() && typeof i.customId === "string" && i.customId.startsWith("tl:")) {
        const [, kind, arg] = i.customId.split(":");
        if (kind === "rr") await roleButton(i, arg);
        else if (kind === "poll") await pollVote(i, Number(arg));
        else if (kind === "gw") await giveawayJoin(i);
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
  let exitHooked = false;
  function attach(discordClient, canReadMessages) {
    client = discordClient;
    canRead = Boolean(canReadMessages);
    if (!ON) return;
    load();
    client.on(Events.MessageCreate, async (message) => {
      try {
        if (await protect(message)) return;
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
      tickAutoQuiz().catch((e) => console.error("⚠️ auto quiz:", e?.message || e));
    }, 30_000);
    tickTimer.unref?.();
    if (!exitHooked) {
      exitHooked = true;
      process.on("exit", () => save(true));
    }
    if (!canReadMessages) console.log("ℹ️ Multitools: levels, anti-spam, anti-links and welcome need the Message Content and Server Members intents (see the setup note).");
    else console.log("🧰 Multitools enabled (levels, moderation, welcome, roles, fun, logs, security).");
  }

  return { ON, commands, handleInteraction, attach, _test: { onVoice, tickVoc, tickLocks, createLevelRoles, giveRewards, tickAutoQuiz, quizzes, expireQuiz, onQuizAnswer, addXp, norm, makeQuiz, gfx, save, load, levelOf, need, onXp, protect, parseDuration, getDb: () => db, H, fill, draw, endGiveaway, tickGiveaways, onJoin, roleButton, pollVote, giveawayJoin } };
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
  const file = new AttachmentBuilder(gfx.banner("KAZUKI MM", look.subtitle, look.banner[0], look.banner[1]), { name: `kazuki-${type}.png` });
  const steps =
    type === "paypal"
      ? [
          [pt("1️⃣  Ouvre un ticket", "1️⃣  Open a ticket"), pt("Ajoute la personne avec qui tu échanges.", "Add the person you trade with.")],
          [pt("2️⃣  Mettez-vous d'accord", "2️⃣  Agree"), pt("Qui paie, qui est payé, le montant en $ ou €.", "Who pays, who gets paid, the amount in $ or €.")],
          [pt("3️⃣  Un staff donne son PayPal", "3️⃣  Staff gives their PayPal"), pt("Le payeur voit le compte et la **référence**.", "The payer sees the account and the **reference**.")],
          [pt("4️⃣  Paiement vérifié", "4️⃣  Payment checked"), pt("Le staff vérifie le paiement sur PayPal.", "Staff checks the payment on PayPal.")],
          [pt("5️⃣  Livraison", "5️⃣  Delivery"), pt("Le vendeur livre, le payeur libère.", "The seller delivers, the payer releases.")],
          [pt("6️⃣  Versement", "6️⃣  Payout"), pt("Le staff envoie l'argent au vendeur.", "Staff sends the money to the seller.")],
        ]
      : [
          [pt("1️⃣  Ouvre un ticket", "1️⃣  Open a ticket"), pt("Ajoute la personne avec qui tu échanges.", "Add the person you trade with.")],
          [pt("2️⃣  Mettez-vous d'accord", "2️⃣  Agree"), pt("Qui envoie, qui reçoit, le montant.", "Who sends, who receives, the amount.")],
          [pt("3️⃣  Dépôt", "3️⃣  Deposit"), pt("L'expéditeur paie l'adresse donnée par le bot.", "The sender pays the address given by the bot.")],
          [pt("4️⃣  Livraison", "4️⃣  Delivery"), pt("Le destinataire donne ce qui était convenu.", "The receiver gives what was agreed.")],
          [pt("5️⃣  Libération", "5️⃣  Release"), pt("L'expéditeur confirme, le bot paie le destinataire.", "The sender confirms, the bot pays the receiver.")],
          [pt("🛟  Un problème ?", "🛟  Problem?"), pt("**Appeler le staff** gèle le deal à tout moment.", "**Call staff** freezes the deal at any time.")],
        ];
  const main = new EmbedBuilder()
    .setColor(look.color)
    .setTitle(look.title)
    .setDescription(
      type === "paypal"
        ? pt("Échange avec PayPal : **le staff vérifie le paiement** et ne paie le vendeur qu'une fois le deal terminé.", "Trade with PayPal: **staff checks the payment** and only pays the seller once the deal is done.")
        : pt("Échange en sécurité : le bot **garde les LTC** jusqu'à ce que les deux soient satisfaits.\nAucune confiance nécessaire, tout est suivi sur la blockchain.", "Trade safely: the bot **holds the LTC** until both sides are happy.\nNo trust needed, everything is tracked on the blockchain.")
    )
    .addFields(...steps.map(([name, value]) => ({ name, value, inline: true })))
    .setImage(`attachment://kazuki-${type}.png`)
    .setFooter({ text: type === "paypal" ? pt("Écris toujours la référence dans la note PayPal  ·  🇫🇷 / 🇬🇧", "Always write the reference in the PayPal note  ·  🇫🇷 / 🇬🇧") : pt("Montants en LTC, $ ou €  ·  petits frais réseau  ·  🇫🇷 / 🇬🇧", "Amounts in LTC, $ or €  ·  small network fee  ·  🇫🇷 / 🇬🇧") });

  const live = new EmbedBuilder()
    .setColor(0x2ecc71)
    .setTitle(pt("📊  En direct", "📊  Live"))
    .addFields(
      { name: pt("✅  Deals terminés", "✅  Deals completed"), value: `**${stats.done}**`, inline: true },
      { name: pt("⏳  En cours", "⏳  In progress"), value: `**${stats.active}**`, inline: true },
      { name: pt("💰  Volume traité", "💰  Volume handled"), value: `**${stats.volume}**`, inline: true }
    )
    .setDescription(`🟢  ${pt("Middleman en ligne", "Middleman online")}  ·  ${pt("mis à jour", "updated")} <t:${Math.floor(Date.now() / 1000)}:R>`);

  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId(`open_ticket:${type}`).setLabel(pt(look.buttonFr, look.button)).setEmoji(look.emoji).setStyle(look.style),
    new ButtonBuilder().setCustomId(`panel:how:${type}`).setLabel(pt("Comment ça marche", "How it works")).setEmoji("❓").setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId(`panel:fees:${type}`).setLabel(pt("Frais et limites", "Fees and limits")).setEmoji("💰").setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId(`panel:mine:${type}`).setLabel(pt("Mon ticket", "My ticket")).setEmoji("🎫").setStyle(ButtonStyle.Secondary)
  );
  return { embeds: [main, live], components: [row], files: [file] };
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
  await interaction.reply(T("🔒 Ticket closed. This channel will be deleted in 5 seconds.", "🔒 Ticket fermé. Ce salon sera supprimé dans 5 secondes."));
  setTimeout(() => channel.delete("middleman ticket closed").catch(() => {}), 5000);
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
          .addStringOption((option) =>
            option
              .setName("type")
              .setDescription("Which panel to post (default: Litecoin)")
              .addChoices({ name: "Litecoin (automatic)", value: "ltc" }, { name: "PayPal (manual, checked by staff)", value: "paypal" })
          )
          .toJSON(),
        new SlashCommandBuilder().setName("paypal").setDescription("Manage the PayPal accounts: add, change, remove, set present or absent").toJSON(),
        new SlashCommandBuilder().setName("access").setDescription("Choose which roles can see the private Litecoin tickets").toJSON(),
        new SlashCommandBuilder().setName("tiers").setDescription("Manage the amount ranges and the staff role of each one").toJSON(),
        ...tools.commands(),
      ],
    });
    await loginWithFallback();
  } catch (error) {
    console.error("❌ Could not start:", error?.message || error);
    process.exit(1);
  }
})();
