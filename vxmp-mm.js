"use strict";

/*
  VXMP MM: single-file Discord bot, Litecoin middleman (escrow) inside tickets.

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

  let store = { nextIndex: 0, nextDeal: 1, walletCheck: "", deals: {}, paypal: [], nextPaypal: 1, tiers: [], nextTier: 1, tiersReady: false, access: [] };

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
          ? T("VXMP MM  ·  every PayPal payment is checked and sent by staff", "VXMP MM  ·  chaque paiement PayPal est vérifié et envoyé par le staff")
          : T("VXMP MM  ·  funds are held by the bot until release", "VXMP MM  ·  les fonds sont gardés par le bot jusqu'à la libération"),
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

  return { init, openDeal, blocksClose, forget, handleInteraction, newSeed, paypalStatus, tierOptions, tierRole: tierRoleId, isStaffFor, accessRoles: ltcAccess };
})();

/* =====================================================
   PART 2: DISCORD BOT (panel + tickets)
===================================================== */

const {
  ActionRowBuilder,
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

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

const isStaff = (member) =>
  Boolean(
    member?.permissions?.has(PermissionFlagsBits.Administrator) ||
      (STAFF_ROLE_ID && member?.roles?.cache?.has(STAFF_ROLE_ID))
  );

/* ---------- panels: one for Litecoin, one for PayPal ---------- */

async function postPanel(interaction) {
  if (!interaction.memberPermissions.has(PermissionFlagsBits.Administrator)) {
    return interaction.reply({ content: "❌ Only administrators can use this command.", flags: ephemeral });
  }
  const type = interaction.options?.getString("type") === "paypal" ? "paypal" : "ltc";

  let embed;
  let row;
  if (type === "paypal") {
    if (!middleman.paypalStatus().configured) {
      return interaction.reply({ content: "❌ No PayPal account yet. Add one with `/paypal` first, then post this panel again.", flags: ephemeral });
    }
    embed = new EmbedBuilder()
      .setColor(0x0070ba)
      .setTitle("💙  VXMP MM  ·  PayPal Middleman")
      .setDescription("Trade with PayPal: **staff checks the payment** and only pays the seller once the deal is done.")
      .addFields(
        { name: "1️⃣  Open a ticket", value: "Add the person you trade with.", inline: true },
        { name: "2️⃣  Agree", value: "Pick payer and seller, set the amount.", inline: true },
        { name: "3️⃣  Pay", value: "The payer sends it to the account shown, with the **reference**.", inline: true },
        { name: "4️⃣  Staff checks", value: "Staff verifies the payment on PayPal.", inline: true },
        { name: "5️⃣  Deliver & release", value: "The seller delivers, the payer releases.", inline: true },
        { name: "6️⃣  Payout", value: "Staff sends the money to the seller.", inline: true }
      )
      .setFooter({ text: "Always write the reference in the PayPal note  ·  every payment is checked by staff  ·  🇫🇷 / 🇬🇧" });
    row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId("open_ticket:paypal").setLabel("Open a PayPal ticket").setEmoji("💙").setStyle(ButtonStyle.Success)
    );
  } else {
    embed = new EmbedBuilder()
      .setColor(0x5865f2)
      .setTitle("💱  VXMP MM  ·  Litecoin Middleman")
      .setDescription("Trade safely: the bot **holds the LTC** until both sides are happy.\nNo trust needed, everything is tracked on the blockchain.")
      .addFields(
        { name: "1️⃣  Open a ticket", value: "Add the person you trade with.", inline: true },
        { name: "2️⃣  Agree", value: "Pick who sends / receives, set the amount.", inline: true },
        { name: "3️⃣  Pay", value: "The sender pays the address given by the bot.", inline: true },
        { name: "4️⃣  Deliver", value: "The receiver gives what was agreed.", inline: true },
        { name: "5️⃣  Release", value: "The sender confirms, the bot pays the receiver.", inline: true },
        { name: "🛟  Problem?", value: "**Call staff** freezes the deal at any time.", inline: true }
      )
      .setFooter({ text: "Amounts can be typed in LTC, $ or €  ·  small network fee applies  ·  🇫🇷 / 🇬🇧" });
    row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId("open_ticket:ltc").setLabel("Open a Litecoin ticket").setEmoji("💱").setStyle(ButtonStyle.Primary)
    );
  }
  await interaction.channel.send({ embeds: [embed], components: [row] });
  return interaction.reply({ content: `✅ ${type === "paypal" ? "PayPal" : "Litecoin"} panel posted.`, flags: ephemeral });
}

/* ---------- tickets ---------- */

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

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    if (await middleman.handleInteraction(interaction)) return;

    if (interaction.isChatInputCommand() && interaction.commandName === "panel") return await postPanel(interaction);
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
});

client.once(Events.ClientReady, () => {
  console.log(`✅ Logged in as ${client.user.tag}`);
  middleman.init(client, { staffRoleId: STAFF_ROLE_ID, ownerRoleId: "", logChannelId: LOG_CHANNEL_ID });
});

client.on(Events.Invalidated, () => {
  console.error("❌ Discord session invalidated: restarting the bot.");
  process.exit(1);
});

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
      ],
    });
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    console.error("❌ Could not start:", error?.message || error);
    process.exit(1);
  }
})();
