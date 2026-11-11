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

  Flow (everything happens inside a ticket opened with the "Open a middleman ticket" button of the panel):
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
  async function resolveAmount(text) {
    const parsed = parseAmountInput(text);
    if (!parsed) return { error: "Invalid amount. Examples: `0.25` (LTC), `5$` (dollars), `5€` (euros)." };

    if (parsed.kind === "LTC") {
      const sat = ltcToSat(parsed.value);
      if (!sat) return { error: "Invalid amount. Use at most 8 decimals, for example `0.25`." };
      const prices = await getLtcPrice().catch(() => null);
      return { sat, quote: prices ? { fiat: (sat / SAT_PER_LTC) * prices.usd, currency: "USD", price: prices.usd, indicative: true } : null };
    }

    const fiat = Number(parsed.value);
    if (!(fiat > 0) || fiat > 1000000) return { error: "Invalid amount." };
    const prices = await getLtcPrice();
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

  let store = { nextIndex: 0, nextDeal: 1, walletCheck: "", deals: {}, paypal: [], nextPaypal: 1 };

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

  const mention = (id) => (id ? `<@${id}>` : "*not chosen yet*");
  const txLink = (txid) => `[${txid.slice(0, 12)}…](${cfg.explorerTx}${txid})`;
  const isParticipant = (deal, id) => id === deal.userA || id === deal.userB;

  /* ---------- PayPal (manual mode): the bot guides the steps, staff checks PayPal and sends the money ---------- */
  const isPaypal = (deal) => deal.method === "paypal";
  const CUR = { USD: "$", EUR: "€" };
  const fmtFiat = (cents, currency) => `${CUR[currency] || ""}${(cents / 100).toFixed(2)} ${currency}`;
  const words = (deal) => (isPaypal(deal) ? { sender: "Payer", receiver: "Seller" } : { sender: "Sender", receiver: "Receiver" });
  const makeRef = (deal) => `MM${deal.n}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
  const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  /* "5", "5.50", "5$", "$5", "5 usd", "5€", "5 eur"  ->  { cents } in the PayPal currency, or { error } */
  function parseFiatCents(text) {
    let raw = String(text || "").trim().toLowerCase().replace(",", ".").replace(/\s+/g, "");
    let currency = cfg.paypalCurrency;
    if (/\$|usd|dollars?/.test(raw)) {
      currency = "USD";
      raw = raw.replace(/\$|usd|dollars?/g, "");
    } else if (/€|eur|euros?/.test(raw)) {
      currency = "EUR";
      raw = raw.replace(/€|eur|euros?/g, "");
    }
    const example = `\`5${CUR[cfg.paypalCurrency]}\``;
    if (!/^\d+(\.\d{1,2})?$/.test(raw)) return { error: `Invalid amount. Example: ${example}.` };
    if (currency !== cfg.paypalCurrency) return { error: `This server takes PayPal in ${cfg.paypalCurrency}. Type for example ${example}.` };
    const cents = Math.round(Number(raw) * 100);
    if (!(cents > 0) || cents > 100000000) return { error: "Invalid amount." };
    return { cents };
  }

  const amountText = (deal) =>
    isPaypal(deal)
      ? deal.amountCents ? `**${fmtFiat(deal.amountCents, deal.currency)}**` : "*not set yet*"
      : deal.amountSat ? `**${satToLtc(deal.amountSat)} LTC**${deal.quote ? `\n${quoteText(deal.quote)}` : ""}` : "*not set yet*";

  function isStaff(member) {
    if (!member) return false;
    return (
      member.permissions?.has(PermissionFlagsBits.Administrator) ||
      (options.staffRoleId && member.roles?.cache?.has(options.staffRoleId)) ||
      (options.ownerRoleId && member.roles?.cache?.has(options.ownerRoleId))
    );
  }

  function button(id, label, style = ButtonStyle.Secondary, emoji) {
    const b = new ButtonBuilder().setCustomId(`mm:${id}`).setLabel(label).setStyle(style);
    if (emoji) b.setEmoji(emoji);
    return b;
  }

  /* ---------- look & feel ---------- */

  const STEPS = ["Partner", "Roles", "Amount", "Payment", "Delivery", "Payout"];
  const STEP_OF = { partner: 0, roles: 1, amount: 2, amount_confirm: 2, awaiting_payment: 3, confirming: 3, funded: 4, released: 5, payout_pending: 5, paying: 5, done: 6 };
  const STATE_COLOR = {
    partner: 0x5865f2, roles: 0x5865f2, amount: 0x5865f2, amount_confirm: 0x5865f2,
    awaiting_payment: 0xfaa61a, confirming: 0xf57c00, funded: 0x2ecc71, released: 0x1abc9c, payout_pending: 0x1abc9c, paying: 0x1abc9c,
    done: 0x2ecc71, refunded: 0x747f8d, cancelled: 0x747f8d,
  };

  /* "▰▰▰▰▰▱  Step 5 of 6 · Delivery" */
  const stepper = (deal) => {
    const current = STEP_OF[deal.state];
    if (current === undefined) return "";
    if (current >= STEPS.length) return `${bar(STEPS.length, STEPS.length, STEPS.length)}  **Complete**`;
    return `${bar(current + 1, STEPS.length, STEPS.length)}  Step ${current + 1} of ${STEPS.length}  ·  **${STEPS[current]}**`;
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
    const sender = mention(deal.senderId);
    const receiver = mention(deal.receiverId);
    const block = (title, lines = []) => [`### ${title}`, ...lines.map((l) => `> ${l}`)].join("\n");
    switch (deal.state) {
      case "partner": return block("➕  Add your partner", ["Click the button below and send their **@mention or user ID**."]);
      case "roles":
        return pp
          ? block("🎭  Pick your roles", ["📤 The **payer** sends the money.", "📥 The **seller** gets paid when the deal is done."])
          : block("🎭  Pick your roles", ["📤 The **sender** pays the LTC.", "📥 The **receiver** gets it when the deal is done."]);
      case "amount":
        return pp
          ? block("💰  Set the amount", [`${sender} type it in ${cfg.paypalCurrency === "EUR" ? "euros" : "dollars"}, for example \`5${CUR[cfg.paypalCurrency]}\`.`])
          : block("💰  Set the amount", [`${sender} type it in money (\`5$\`, \`5€\`) or in LTC (\`0.25 ltc\`).`, "With a plain number, I ask which one you mean."]);
      case "amount_confirm":
        return block(pp ? "🤝  Waiting for the seller" : "🤝  Waiting for the receiver", [
          `${receiver} accept or decline on the **amount card** below.`,
          pp ? "🔒 Once confirmed, the amount is locked." : "🔒 Once confirmed, the LTC figure is locked.",
        ]);
      case "awaiting_payment":
        return pp
          ? block("💳  Waiting for the PayPal payment", [
              `${sender} pay as shown in the **payment card** below.`,
              deal.paidClaimed ? "Staff is checking PayPal, this updates when it is verified." : "Then click **I've paid**, staff checks PayPal.",
            ])
          : block("💳  Waiting for the payment", [`${sender} send the exact amount shown in the **payment card** below.`, "The bot spots it by itself, nothing to click."]);
      case "confirming": return block("⏳  Payment spotted", ["The network is confirming it.", "This card updates by itself."]);
      case "funded":
        return block(pp ? "🔒  Payment verified" : "🔒  Funds secured", [`📥 ${receiver} deliver what was agreed.`, `📤 ${sender} click **Release** only once you really received it.`]);
      case "released":
        return block("🔓  Funds released", [`📥 ${receiver} click **${pp ? "Enter my PayPal email" : "Enter my LTC address"}** to get paid.`]);
      case "payout_pending":
        return block("🏦  Staff is sending the money", [`Staff sends **${fmtFiat(deal.amountCents, deal.currency)}** to \`${deal.payoutPaypal}\`.`, "This card updates when it is done."]);
      case "paying": return block("📤  Sending the funds…");
      case "done": return block("🎉  Deal complete", ["Thank you both 💜"]);
      case "refunded": return block("↩️  Refunded", [pp ? "The payment went back to the payer." : "The funds went back to the sender."]);
      case "cancelled":
        return block("✖️  Cancelled", deal.address ? ["Do **not** send any LTC to the deposit address anymore."] : deal.ref ? ["Do **not** send any money anymore."] : ["Nothing was paid."]);
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
    const panels = [];
    const color = deal.frozen ? COLORS.bad : STATE_COLOR[deal.state] || COLORS.info;

    // 1. header
    panels.push(
      new EmbedBuilder()
        .setColor(color)
        .setTitle(isPaypal(deal) ? `💙  PayPal Middleman  ·  Deal #${deal.n}` : `💱  Litecoin Middleman  ·  Deal #${deal.n}`)
        .setDescription(
          [
            deal.frozen ? "🧊  **FROZEN**: a dispute is open, staff will decide." : null,
            deal.notice || null,
            stepper(deal) || null,
            stateText(deal) || null,
          ].filter(Boolean).join("\n\u200b\n")
        )
    );

    // 2. details (from the roles step on)
    const amountLine = amountText(deal);
    if (deal.state !== "partner") panels.push(
      new EmbedBuilder()
        .setColor(0x4f545c)
        .setTitle("📋  Deal details")
        .addFields(
          { name: `📤  ${words(deal).sender}`, value: deal.senderId ? mention(deal.senderId) : "*waiting…*", inline: true },
          { name: `📥  ${words(deal).receiver}`, value: deal.receiverId ? mention(deal.receiverId) : "*waiting…*", inline: true },
          { name: "💰  Amount", value: amountLine, inline: true }
        )
    );

    // 3. result
    if (deal.payoutTxid || deal.refundTxid) {
      const refund = Boolean(deal.refundTxid);
      panels.push(
        new EmbedBuilder()
          .setColor(refund ? COLORS.grey : COLORS.ok)
          .setTitle(refund ? "↩️  Refund" : "🏦  Payout")
          .setDescription(
            [
              `${txLink(refund ? deal.refundTxid : deal.payoutTxid)}`,
              `\`${refund ? deal.refundAddress : deal.payoutAddress}\``,
              `🧾 Network fee: ${satToLtc(deal.feeSat)} LTC (deducted from the amount sent)`,
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
          .setTitle(refund ? "↩️  Refund" : "🏦  Payout")
          .setDescription(
            [
              refund ? "Refunded to the payer by staff." : `**${fmtFiat(deal.amountCents, deal.currency)}** sent to \`${deal.payoutPaypal}\` by staff.`,
              deal.resultNote ? `🧾 ${deal.resultNote}` : null,
            ].filter(Boolean).join("\n")
          )
      );
    }

    panels[panels.length - 1]
      .setFooter({ text: isPaypal(deal) ? "VXMP MM  ·  every PayPal payment is checked and sent by staff" : "VXMP MM  ·  funds are held by the bot until release" })
      .setTimestamp();
    return panels;
  }

  /* The payment card is a message of its own, edited in place while the payment goes through:
     instructions -> payment spotted (confirmations 1/2, 2/2) -> payment confirmed. */
  function paypalPaymentEmbed(deal) {
    const embed = new EmbedBuilder().setTimestamp();
    if (deal.state === "cancelled") {
      return embed.setColor(COLORS.grey).setTitle("✖️  Payment cancelled").setDescription("The deal was cancelled. Do **not** send any money anymore.");
    }
    if (deal.state === "refunded") {
      return embed.setColor(COLORS.grey).setTitle("↩️  Payment refunded").setDescription("The payment went back to the payer.");
    }
    if (deal.state !== "awaiting_payment") {
      return embed
        .setColor(COLORS.ok)
        .setTitle("✅  Payment verified")
        .setDescription([`**${fmtFiat(deal.amountCents, deal.currency)}** received and checked by staff.`, "​", "Staff holds the payment until the deal is done."].join("\n"));
    }
    return embed
      .setColor(deal.paidClaimed ? 0xf57c00 : 0xfaa61a)
      .setTitle(deal.paidClaimed ? "⏳  Waiting for staff to verify" : "💙  PayPal payment instructions")
      .setDescription(
        [
          deal.frozen ? "🧊  **FROZEN**: a dispute is open, staff will decide.\n​" : null,
          `📤 ${mention(deal.senderId)} send exactly`,
          `\`\`\`${fmtFiat(deal.amountCents, deal.currency)}\`\`\``,
          `to this PayPal account (**${deal.ppLabel}**)`,
          `\`\`\`${deal.ppEmail}\`\`\``,
          "and write this **reference** in the PayPal note",
          `\`\`\`${deal.ref}\`\`\``,
          cfg.paypalNote ? `ℹ️ ${cfg.paypalNote}` : null,
          "🔒 The amount is **locked**.",
          "​",
          "### ⏱️  Status",
          deal.paidClaimed
            ? "🔔 The payer says it is sent. Staff is checking PayPal."
            : "⏳ Waiting for your payment. Once it is sent, click **I've paid**.",
        ].filter(Boolean).join("\n")
      );
  }

  function paymentEmbed(deal) {
    if (isPaypal(deal)) return paypalPaymentEmbed(deal);
    const need = cfg.confirmations;
    const live = deal.state === "awaiting_payment" || deal.state === "confirming";
    const embed = new EmbedBuilder().setTimestamp();

    if (deal.state === "cancelled") {
      return embed.setColor(COLORS.grey).setTitle("✖️  Payment cancelled").setDescription("The deal was cancelled. Do **not** send any LTC to this address anymore.");
    }
    if (deal.state === "refunded") {
      return embed.setColor(COLORS.grey).setTitle("↩️  Payment refunded").setDescription("The funds went back to the sender.");
    }

    if (live) {
      const confirming = deal.state === "confirming";
      const checked = deal.lastCheck ? `🔄 Last check <t:${unix(deal.lastCheck)}:R>` : null;
      embed
        .setColor(confirming ? 0xf57c00 : 0xfaa61a)
        .setTitle(confirming ? "⏳  Payment spotted" : "💳  Payment instructions")
        .setDescription(
          [
            deal.frozen ? "🧊  **FROZEN**: a dispute is open, staff will decide.\n\u200b" : null,
            `📤 ${mention(deal.senderId)} send exactly`,
            `\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\``,
            "to this address",
            `\`\`\`${deal.address}\`\`\``,
            "🔒 The amount is **locked**, it will not change even if the price moves.",
            "\u200b",
            "### ⏱️  Confirmations",
            confirming
              ? `${bar(deal.confirmations, need)}  **${Math.min(deal.confirmations, need)}/${need}**  ·  seen **${satToLtc(deal.seenSat)} LTC**`
              : `${bar(0, need)}  waiting for the payment\nNeeds ${need} confirmation(s) after sending (about ${Math.round(need * 2.5)} min)`,
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
      .setTitle("✅  Payment confirmed")
      .setDescription(
        [
          `**${satToLtc(deal.receivedSat || deal.amountSat)} LTC** received and confirmed.`,
          `${bar(need, need)}  **${need}/${need}** confirmations`,
          txs ? `🔗 ${txs}` : null,
          "\u200b",
          "The bot holds the funds until the deal is done.",
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
    const rows = [];
    const s = deal.state;
    const main = [];

    if (s === "partner") main.push(button("partner", "Add the other person", ButtonStyle.Primary, "➕"));
    const pp = isPaypal(deal);
    if (s === "roles") main.push(button("role:sender", pp ? "I pay" : "I send the LTC", ButtonStyle.Primary, "📤"), button("role:receiver", pp ? "I get paid" : "I receive the LTC", ButtonStyle.Success, "📥"));
    if (s === "amount") main.push(button("amount", "Set the amount", ButtonStyle.Primary, "💰"));
      if (s === "funded") main.push(button("release", "Release the funds", ButtonStyle.Success, "🔓"));
    if (s === "released") main.push(button("payout", pp ? "Enter my PayPal email" : "Enter my LTC address", ButtonStyle.Success, "🏦"));
    if (s === "awaiting_payment" || s === "confirming") main.push(button("copy", "Copy details", ButtonStyle.Secondary, "📋"));
    if (pp && s === "awaiting_payment" && !deal.paidClaimed) main.push(button("paid", "I've paid", ButtonStyle.Success, "💸"));
    if (["partner", "roles", "amount", "amount_confirm", "awaiting_payment"].includes(s) && !(pp && deal.paidClaimed)) main.push(button("cancel", "Cancel", ButtonStyle.Danger, "✖️"));
    if (["awaiting_payment", "confirming", "funded", "released", "payout_pending"].includes(s) && !deal.frozen) main.push(button("dispute", "Call staff", ButtonStyle.Danger, "🚨"));

    if (staffComponents(deal).length) main.push(button("staff", "Staff tools", ButtonStyle.Secondary, "🛠️"));
    if (main.length) rows.push(new ActionRowBuilder().addComponents(main));
    return rows;
  }

  /* Buttons shown only inside the private "Staff tools" panel. */
  function staffComponents(deal) {
    const s = deal.state;
    const staff = [];
    if (deal.frozen) staff.push(button("unfreeze", "Unfreeze", ButtonStyle.Secondary, "🧊"));
    if (isPaypal(deal)) {
      if (s === "awaiting_payment") {
        staff.push(button("mark_paid", "Payment received", ButtonStyle.Success, "✅"));
        if (!deal.paidClaimed && pickPaypal(deal.ppId)) staff.push(button("switch_pp", "Switch PayPal account", ButtonStyle.Secondary, "🔁"));
      }
      if (s === "funded") staff.push(button("force_release", "Force release", ButtonStyle.Primary, "⚖️"));
      if (s === "payout_pending") staff.push(button("payout_sent", "Payout sent", ButtonStyle.Success, "🏦"));
      if (["funded", "released", "payout_pending"].includes(s)) staff.push(button("refund", "Refund payer", ButtonStyle.Danger, "↩️"));
    } else {
      if (s === "funded") staff.push(button("force_release", "Force release", ButtonStyle.Primary, "⚖️"));
      if (s === "confirming" || s === "funded" || s === "released") staff.push(button("refund", "Refund sender", ButtonStyle.Danger, "↩️"));
    }
    if (FINAL.has(s)) staff.push(button("close", "Close channel", ButtonStyle.Secondary, "🗑️"));
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
    else await interaction.update({ content: "✅ Done.", components: [] });
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
    await foldStepCard(deal, summary || "✅  **Done**");
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

  const AMOUNT_CARD = {
    pending: { title: "💰  Amount to confirm", color: COLORS.wait },
    confirmed: { title: "✅  Amount confirmed", color: COLORS.ok },
    declined: { title: "❌  Amount declined", color: COLORS.grey },
    superseded: { title: "↪️  Amount replaced", color: COLORS.grey },
  };

  function amountCard(deal, status = "pending", by = null) {
    const info = AMOUNT_CARD[status];
    const pp = isPaypal(deal);
    const lines = [
      `${mention(deal.senderId)} set the amount to`,
      pp ? `\`\`\`${fmtFiat(deal.amountCents, deal.currency)}\`\`\`` : `\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\``,
      !pp && deal.quote ? quoteText(deal.quote) : "",
      "",
    ];
    if (status === "pending") lines.push(`📥 ${mention(deal.receiverId)} do you accept this amount?`, pp ? "🔒 Once you confirm, the amount is locked." : "🔒 Once you confirm, the LTC figure is locked.");
    if (status === "confirmed") lines.push(`Confirmed by ${mention(by)}. The amount is locked.`);
    if (status === "declined") lines.push(`Declined by ${mention(by)}.`);
    if (status === "superseded") lines.push("A new amount was proposed, or the deal was cancelled.");
    return new EmbedBuilder().setColor(info.color).setTitle(info.title).setDescription(lines.join("\n")).setTimestamp();
  }

  const amountButtons = () => [
    new ActionRowBuilder().addComponents(
      button("confirm_amount", "Confirm", ButtonStyle.Success, "✅"),
      button("decline_amount", "Decline", ButtonStyle.Danger, "❌")
    ),
  ];

  async function postAmountCard(deal) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const message = await channel
      .send({ content: mention(deal.receiverId), embeds: [amountCard(deal)], components: amountButtons(), allowedMentions: { users: [deal.receiverId] } })
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
  async function setDealAmount(deal, text) {
    if (!["amount", "amount_confirm"].includes(deal.state)) return { error: "The amount can no longer be changed." };

    if (isPaypal(deal)) {
      const parsed = parseFiatCents(text);
      if (parsed.error) return { error: parsed.error };
      if (parsed.cents < cfg.paypalMinCents) return { error: `Minimum deal: ${fmtFiat(cfg.paypalMinCents, cfg.paypalCurrency)}.` };
      await closeAmountCard(deal, "superseded");
      deal.amountCents = parsed.cents;
      deal.currency = cfg.paypalCurrency;
      deal.state = "amount_confirm";
      saveStore();
      await foldStepCard(deal, `💰  **Amount proposed**  ·  ${fmtFiat(deal.amountCents, deal.currency)}`);
      await postAmountCard(deal);
      return {};
    }

    const result = await resolveAmount(text).catch((error) => ({ error: error?.message || String(error) }));
    if (result.error) return { error: result.error };
    if (result.sat < cfg.minSat) return { error: `That is only ${satToLtc(result.sat)} LTC. Minimum deal: ${satToLtc(cfg.minSat)} LTC.` };
    await closeAmountCard(deal, "superseded"); // a previous, still pending card is replaced
    deal.amountSat = result.sat;
    deal.quote = result.quote;
    deal.state = "amount_confirm";
    saveStore();
    await foldStepCard(deal, `💰  **Amount proposed**  ·  ${satToLtc(deal.amountSat)} LTC`);
    await postAmountCard(deal);
    return {};
  }

  async function logLine(text) {
    if (!options.logChannelId) return;
    const channel = await client.channels.fetch(options.logChannelId).catch(() => null);
    if (channel?.isTextBased()) await channel.send({ content: text, allowedMentions: { parse: [] } }).catch(() => {});
  }

  const staffPing = () => (options.staffRoleId ? `<@&${options.staffRoleId}>` : "Staff");
  const reply = (interaction, content) => interaction.reply({ content, flags: ephemeral });

  /* ---------- PayPal accounts, managed from Discord with /paypal ---------- */

  const MAX_PAYPAL = 4;
  const ppList = () => (store.paypal = Array.isArray(store.paypal) ? store.paypal : []);
  const ppActiveDeals = (account) => Object.values(store.deals).filter((d) => isPaypal(d) && d.ppId === account.id && !FINAL.has(d.state));
  const ppWaiting = (account) => ppActiveDeals(account).filter((d) => d.state === "awaiting_payment" && !d.paidClaimed);
  const isAdmin = (member) =>
    Boolean(member?.permissions?.has(PermissionFlagsBits.Administrator) || (options.ownerRoleId && member?.roles?.cache?.has(options.ownerRoleId)));

  /* configured: at least one account exists. available: at least one is present (not marked absent). */
  function paypalStatus() {
    const list = ppList();
    return { configured: list.length > 0, available: list.some((a) => !a.away) };
  }

  /* The present account with the fewest deals in progress (never the one in `excludeId`). */
  function pickPaypal(excludeId) {
    const present = ppList().filter((a) => !a.away && a.id !== excludeId);
    present.sort((a, b) => ppActiveDeals(a).length - ppActiveDeals(b).length);
    return present[0] || null;
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
        title: "👀  Payment spotted",
        body: `**${satToLtc(seenSat)} LTC** seen on the deposit address.\nThe confirmations are tracked live in the **payment card** above.`,
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
        title: "⚠️  Payment too small",
        body: `The confirmed payment is **${satToLtc(confirmedSat)} LTC** but the deal is **${satToLtc(deal.amountSat)} LTC**.\n\n📤 ${mention(deal.senderId)} send the missing **${satToLtc(deal.amountSat - confirmedSat)} LTC** to the same address,\nor ${staffPing()} can refund it.`,
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
  async function openDeal(channel, user, method = "ltc") {
    if (!enabled) {
      await channel.send("❌ The middleman is not configured yet (MM_SEED is missing). Staff has been notified in this ticket.");
      return false;
    }
    if (method === "paypal" && !paypalStatus().available) {
      await channel.send(
        paypalStatus().configured
          ? "❌ No PayPal account is available right now (everyone is absent). Staff has been notified in this ticket."
          : "❌ PayPal is not set up yet: an administrator adds an account with `/paypal`. Staff has been notified in this ticket."
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

    await logLine(`🆕 Middleman deal #${n} opened by <@${deal.userA}> (<#${channel.id}>).`);
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

  async function handleButton(interaction, deal, action, arg, extra) {
    const user = interaction.user;
    const staff = isStaff(interaction.member);
    const participant = isParticipant(deal, user.id);

    const needParticipant = () => !participant && !staff && (reply(interaction, "❌ You are not part of this deal."), true);
    const needStaff = () => !staff && (reply(interaction, "❌ Staff only."), true);
    const frozenBlock = () => deal.frozen && (reply(interaction, "🧊 This deal is frozen. Wait for staff."), true);

    switch (action) {
      case "partner": {
        if (user.id !== deal.userA) return reply(interaction, "❌ Only the person who opened the ticket can add the other person.");
        if (deal.state !== "partner") return reply(interaction, "❌ The other person was already added.");
        return interaction.showModal(
          new ModalBuilder().setCustomId("mm:m:partner").setTitle("Who do you trade with?").addComponents(
            new ActionRowBuilder().addComponents(
              new TextInputBuilder().setCustomId("value").setLabel("@mention or user ID").setStyle(TextInputStyle.Short).setRequired(true).setMinLength(5).setMaxLength(60)
            )
          )
        );
      }

      case "role": {
        if (!participant) return reply(interaction, "❌ You are not part of this deal.");
        if (deal.state !== "roles") return reply(interaction, "❌ Roles are already set.");
        const other = arg === "sender" ? "receiver" : "sender";
        if (deal[`${arg}Id`] && deal[`${arg}Id`] !== user.id) return reply(interaction, `❌ The ${arg} role is already taken by the other person.`);
        if (deal[`${other}Id`] === user.id) deal[`${other}Id`] = null;
        deal[`${arg}Id`] = user.id;
        const ready = Boolean(deal.senderId && deal.receiverId);
        if (ready) deal.state = "amount";
        saveStore();
        if (!ready) return interaction.update(render(deal)); // still choosing: this card updates in place
        await interaction.deferUpdate();
        return advance(deal, { summary: `✅  **Roles**  ·  📤 ${mention(deal.senderId)}  ·  📥 ${mention(deal.receiverId)}`, ping: [deal.senderId] });
      }

      case "amount": {
        if (!["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ The amount can no longer be changed.");
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender sets the amount.");
        const modal = new ModalBuilder().setCustomId("mm:m:amount").setTitle("Amount to send")
          .addComponents(new ActionRowBuilder().addComponents(
            isPaypal(deal)
              ? new TextInputBuilder().setCustomId("value").setLabel(`Amount in ${deal.currency || cfg.paypalCurrency}`).setPlaceholder(`5${CUR[cfg.paypalCurrency]}`).setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(24)
              : new TextInputBuilder().setCustomId("value").setLabel("Amount: 5$ / 5€ / 0.25 LTC").setPlaceholder("0.01   (I will ask: dollars or LTC?)").setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(24)
          ));
        return interaction.showModal(modal);
      }

      case "confirm_amount": {
        if (deal.state !== "amount_confirm") return reply(interaction, "❌ Nothing to confirm right now.");
        if (user.id !== deal.receiverId) return reply(interaction, "❌ Only the LTC receiver confirms the amount.");
        if (isPaypal(deal)) {
          if (!deal.ppId) {
            const account = pickPaypal();
            if (!account) {
              await reply(interaction, "❌ No PayPal account is available right now (everyone is absent). Staff was pinged, try again in a moment.");
              return notify(deal, {
                title: "⚠️  No PayPal available",
                body: `The seller wants to confirm the amount but every PayPal account is absent.\n\n${staffPing()} set an account present with \`/paypal\`.`,
                color: COLORS.bad,
                ping: [staffPing()],
              });
            }
            assignPaypal(deal, account);
          }
          deal.ref = deal.ref || makeRef(deal);
        } else if (!deal.address) {
          deal.index = store.nextIndex++;
          deal.address = addressOf(deal.index);
        }
        deal.state = "awaiting_payment";
        saveStore();
        if (deal.messageId && interaction.message?.id === deal.messageId) {
          await interaction.deferUpdate(); // an old card carried the button: fold it
          await foldStepCard(deal, "✅  **Amount confirmed**");
        } else {
          deal.amountMsgId = "";
          await interaction.update({ embeds: [amountCard(deal, "confirmed", user.id)], components: [] });
        }
        return postPaymentCard(deal);
      }

      case "release": {
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender can release the funds.");
        if (deal.state !== "funded") return reply(interaction, "❌ The funds are not ready to be released.");
        if (frozenBlock()) return;
        return interaction.reply({
          flags: ephemeral,
          content: "⚠️ Release the funds **only if you received what was agreed**. This cannot be undone.",
          components: [new ActionRowBuilder().addComponents(button("release_yes", "Yes, I received it", ButtonStyle.Success), button("release_no", "No", ButtonStyle.Secondary))],
        });
      }

      case "pick": {
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender sets the amount.");
        if (!["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ The amount can no longer be changed.");
        if ((arg !== "usd" && arg !== "ltc") || !parseAmountInput(extra)?.bare) return reply(interaction, "❌ Invalid choice.");
        await interaction.update({ content: "⏳ Setting the amount…", components: [] });
        const outcome = await withLock(deal.channelId, () => setDealAmount(deal, arg === "usd" ? `${extra}$` : `${extra} ltc`));
        return interaction.editReply({ content: outcome.error ? `❌ ${outcome.error}` : "✅ Sent to the receiver for confirmation.", components: [] });
      }

      case "copy": {
        if (user.id !== deal.senderId && !staff) return reply(interaction, "❌ Only the sender needs the payment details.");
        if (!["awaiting_payment", "confirming"].includes(deal.state)) return reply(interaction, "❌ There is nothing to pay right now.");
        if (isPaypal(deal)) {
          await interaction.reply({ content: deal.ppEmail, flags: ephemeral });
          await interaction.followUp({ content: (deal.amountCents / 100).toFixed(2), flags: ephemeral });
          await interaction.followUp({ content: deal.ref, flags: ephemeral });
          return interaction.followUp({
            content: `📋 **Tap and hold** a message above, then **Copy Text**.\n1️⃣ the **PayPal email**   2️⃣ the **amount** (${deal.currency})   3️⃣ the **reference** to write in the PayPal note`,
            flags: ephemeral,
          });
        }
        // one value per message so "Copy Text" on mobile copies exactly that value
        await interaction.reply({ content: deal.address, flags: ephemeral });
        await interaction.followUp({ content: satToLtc(deal.amountSat), flags: ephemeral });
        return interaction.followUp({
          content: "📋 **Tap and hold** a message above, then **Copy Text**.\n1️⃣ the **address**   2️⃣ the **amount** in LTC\nSend exactly that amount to that address.",
          flags: ephemeral,
        });
      }

      case "decline_amount": {
        if (deal.state !== "amount_confirm") return reply(interaction, "❌ Nothing to decline right now.");
        if (user.id !== deal.receiverId) return reply(interaction, "❌ Only the LTC receiver can decline the amount.");
        const declined = { ...deal };
        deal.state = "amount";
        deal.amountSat = 0;
        deal.quote = null;
        deal.amountMsgId = "";
        saveStore();
        await interaction.update({ embeds: [amountCard(declined, "declined", user.id)], components: [] });
        return advance(deal, { ping: [deal.senderId], notice: `❌  ${mention(user.id)} declined the previous amount.` });
      }

      case "paid": {
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, "❌ Nothing to confirm right now.");
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the payer can say the payment was sent.");
        if (frozenBlock()) return;
        if (deal.paidClaimed) return reply(interaction, "Staff was already notified.");
        deal.paidClaimed = true;
        saveStore();
        await ack(interaction, deal);
        await notify(deal, {
          title: "💸  Payment sent?",
          body: `${mention(user.id)} says the PayPal payment is sent.\n\n${staffPing()} check PayPal for **${fmtFiat(deal.amountCents, deal.currency)}** with the reference \`${deal.ref}\`, then open **Staff tools → Payment received**.`,
          color: 0xf57c00,
          ping: [staffPing(), deal.ppHolder],
        });
        return logLine(`💸 Deal #${deal.n}: payer says PayPal ${fmtFiat(deal.amountCents, deal.currency)} sent, ref ${deal.ref} (<#${deal.channelId}>).`);
      }

      case "mark_paid": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, "❌ Nothing to confirm right now.");
        deal.state = "funded";
        saveStore();
        await ack(interaction, deal, false);
        await refreshPaymentCard(deal);
        await advance(deal, { ping: [deal.receiverId, deal.senderId] });
        return logLine(`💙 Deal #${deal.n}: PayPal payment verified by <@${user.id}> (${fmtFiat(deal.amountCents, deal.currency)}).`);
      }

      case "switch_pp": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "awaiting_payment") return reply(interaction, "❌ Nothing to change right now.");
        if (deal.paidClaimed) return reply(interaction, "❌ The payer says it is already paid: check PayPal first.");
        const account = pickPaypal(deal.ppId);
        if (!account) return reply(interaction, "❌ No other PayPal account is available.");
        assignPaypal(deal, account);
        saveStore();
        await ack(interaction, deal, false);
        await refreshPaymentCard(deal);
        return notify(deal, {
          title: "🔁  PayPal account changed",
          body: `Please pay to the **new** account shown in the payment card: **${account.label}**.\nDo not use the previous one.`,
          color: 0xf57c00,
          ping: [deal.senderId],
        });
      }

      case "payout_sent": {
        if (needStaff()) return;
        if (!isPaypal(deal) || deal.state !== "payout_pending") return reply(interaction, "❌ Nothing to confirm right now.");
        return interaction.showModal(noteModal("mm:m:payout_sent", "Payout sent", "PayPal transaction ID (optional)"));
      }

      case "release_no":
        return interaction.update({ content: "Cancelled, nothing was released.", components: [] });

      case "release_yes": {
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender can release the funds.");
        if (deal.state !== "funded" || deal.frozen) return interaction.update({ content: "❌ Not possible right now.", components: [] });
        deal.state = "released";
        saveStore();
        await interaction.update({ content: "✅ Released.", components: [] });
        return advance(deal, { summary: `✅  **Delivery confirmed**  ·  ${mention(deal.senderId)} released the funds`, ping: [deal.receiverId] });
      }

      case "payout": {
        if (user.id !== deal.receiverId) return reply(interaction, "❌ Only the LTC receiver can enter the payout address.");
        if (deal.state !== "released") return reply(interaction, "❌ The funds were not released yet.");
        if (frozenBlock()) return;
        return interaction.showModal(isPaypal(deal) ? emailModal() : addressModal("mm:m:payout", "Where should we send the LTC?", "Your Litecoin address"));
      }

      case "dispute": {
        if (needParticipant()) return;
        if (deal.frozen) return reply(interaction, "Already frozen.");
        deal.frozen = true;
        saveStore();
        await ack(interaction, deal);
        await notify(deal, {
          title: "🚨  Staff called",
          body: `${mention(user.id)} called staff on deal #${deal.n}.\nThe deal is **frozen** until staff decides.`,
          color: COLORS.bad,
          ping: [staffPing()],
        });
        return logLine(`🚨 Deal #${deal.n} frozen by <@${user.id}> (<#${deal.channelId}>).`);
      }

      case "staff": {
        if (needStaff()) return;
        const rows = staffComponents(deal);
        if (!rows.length) return reply(interaction, "Nothing to do for staff right now.");
        return interaction.reply({ content: `🛠️ **Staff tools** · deal #${deal.n}`, components: rows, flags: ephemeral });
      }

      case "unfreeze": {
        if (needStaff()) return;
        deal.frozen = false;
        saveStore();
        await ack(interaction, deal);
        return notify(deal, { title: "🧊  Deal unfrozen", body: `Unfrozen by ${mention(user.id)}. The deal can continue.`, color: COLORS.info });
      }

      case "force_release": {
        if (needStaff()) return;
        if (deal.state !== "funded") return reply(interaction, "❌ Funds are not in a releasable state.");
        deal.state = "released";
        deal.frozen = false;
        saveStore();
        await ack(interaction, deal, false);
        await advance(deal, { summary: `⚖️  **Released by staff**  ·  ${mention(user.id)}`, ping: [deal.receiverId] });
        return logLine(`⚖️ Deal #${deal.n} force-released by <@${user.id}>.`);
      }

      case "refund": {
        if (needStaff()) return;
        if (isPaypal(deal)) {
          if (!["funded", "released", "payout_pending"].includes(deal.state)) return reply(interaction, "❌ Nothing to refund.");
          return interaction.showModal(noteModal("mm:m:refund_pp", "Refund the payer", "PayPal refund transaction ID (optional)"));
        }
        if (!["confirming", "funded", "released"].includes(deal.state)) return reply(interaction, "❌ Nothing to refund.");
        return interaction.showModal(addressModal("mm:m:refund", "Refund address of the sender", "Sender's Litecoin address"));
      }

      case "cancel": {
        if (needParticipant()) return;
        if (!["partner", "roles", "amount", "amount_confirm", "awaiting_payment"].includes(deal.state) || (isPaypal(deal) && deal.paidClaimed)) return reply(interaction, "❌ This deal can no longer be cancelled here. Call staff.");
        await closeAmountCard(deal, "superseded");
        deal.state = "cancelled";
        saveStore();
        await ack(interaction, deal, false);
        await refreshPaymentCard(deal);
        return advance(deal, { summary: `✖️  **Cancelled**  ·  by ${mention(user.id)}` });
      }

      case "close": {
        if (needStaff()) return;
        if (!FINAL.has(deal.state)) return reply(interaction, "❌ The deal is not finished.");
        await reply(interaction, "🗑️ Closing the channel...");
        delete store.deals[deal.channelId];
        saveStore();
        return setTimeout(() => interaction.channel?.delete().catch(() => {}), 3000);
      }
    }
  }

  const emailModal = () =>
    new ModalBuilder().setCustomId("mm:m:payout").setTitle("Where should staff pay you?").addComponents(
      new ActionRowBuilder().addComponents(
        new TextInputBuilder().setCustomId("value").setLabel("Your PayPal email").setStyle(TextInputStyle.Short).setRequired(true).setMinLength(5).setMaxLength(100)
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

  async function handleModal(interaction, deal, kind) {
    const user = interaction.user;
    const value = interaction.fields.getTextInputValue("value").trim();

    if (kind === "partner") {
      if (user.id !== deal.userA || deal.state !== "partner") return reply(interaction, "❌ Not possible right now.");
      const id = value.match(/\d{15,25}/)?.[0];
      if (!id) return reply(interaction, "❌ Send an @mention or the numeric user ID.");
      if (id === user.id) return reply(interaction, "❌ You cannot trade with yourself.");
      const member = await interaction.guild.members.fetch(id).catch(() => null);
      if (!member || member.user.bot) return reply(interaction, "❌ I could not find that person in this server (bots are not allowed).");
      await interaction.channel.permissionOverwrites.edit(id, {
        ViewChannel: true, SendMessages: true, ReadMessageHistory: true, AttachFiles: true,
      });
      deal.userB = id;
      deal.state = "roles";
      saveStore();
      await interaction.deferUpdate();
      return advance(deal, { summary: `✅  **Partner added**  ·  ${mention(id)}`, ping: [deal.userA, id] });
    }

    if (kind === "amount") {
      if (user.id !== deal.senderId || !["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ Not possible right now.");
      const parsed = isPaypal(deal) ? null : parseAmountInput(value);
      if (!isPaypal(deal) && !parsed) return reply(interaction, "❌ Invalid amount. Examples: `5$` (dollars), `5€` (euros), `0.25 ltc`.");

      if (parsed?.bare) {
        // "0.01" alone is ambiguous: show both readings side by side and let the sender pick
        await interaction.deferReply({ flags: ephemeral });
        const prices = await getLtcPrice().catch(() => null);
        const asLtc = ltcToSat(parsed.value);
        const dollarSat = prices ? Math.round((Number(parsed.value) / prices.usd) * SAT_PER_LTC) : 0;
        const dollarLabel = prices ? `$${parsed.value}  =  ${satToLtc(dollarSat)} LTC` : `$${parsed.value} (price unavailable)`;
        const ltcLabel = asLtc ? `${parsed.value} LTC${prices ? `  (≈ $${fmtMoney((asLtc / SAT_PER_LTC) * prices.usd)})` : ""}` : "invalid LTC amount";
        return interaction.editReply({
          content: `**${parsed.value}** what do you mean?\nPick one, the receiver then confirms it.`,
          components: [
            new ActionRowBuilder().addComponents(
              button(`pick:usd:${parsed.value}`, dollarLabel.slice(0, 80), ButtonStyle.Primary, "💵").setDisabled(!prices || dollarSat < 1),
              button(`pick:ltc:${parsed.value}`, ltcLabel.slice(0, 80), ButtonStyle.Secondary, "🪙").setDisabled(!asLtc)
            ),
          ],
        });
      }

      await interaction.deferUpdate(); // the price lookup can take a moment
      const outcome = await withLock(deal.channelId, () => setDealAmount(deal, value));
      if (outcome.error) return interaction.followUp({ content: `❌ ${outcome.error}`, flags: ephemeral });
      return;
    }

    if (isPaypal(deal) && kind === "payout") {
      if (user.id !== deal.receiverId) return reply(interaction, "❌ Not allowed.");
      if (deal.state !== "released" || deal.frozen) return reply(interaction, "❌ This is not possible in the current state of the deal.");
      if (!EMAIL.test(value)) return reply(interaction, "❌ That is not a valid PayPal email address.");
      deal.payoutPaypal = value;
      deal.state = "payout_pending";
      saveStore();
      await reply(interaction, "✅ Sent to staff. They pay you and mark the deal as done.");
      await advance(deal, { summary: "🏦  **PayPal email received**", ping: [staffPing(), deal.senderId] });
      return logLine(`🏦 Deal #${deal.n}: pay ${fmtFiat(deal.amountCents, deal.currency)} to ${value} (<#${deal.channelId}>).`);
    }

    if (isPaypal(deal) && kind === "payout_sent") {
      if (!isStaff(interaction.member)) return reply(interaction, "❌ Staff only.");
      if (deal.state !== "payout_pending") return reply(interaction, "❌ This is not possible in the current state of the deal.");
      deal.resultNote = value;
      deal.state = "done";
      saveStore();
      await reply(interaction, "✅ Deal marked as done.");
      await advance(deal, { summary: `🏦  **Payout sent by staff**  ·  ${mention(user.id)}`, ping: [deal.receiverId, deal.senderId] });
      return logLine(`✅ Deal #${deal.n}: PayPal payout sent by <@${user.id}>.`);
    }

    if (isPaypal(deal) && kind === "refund_pp") {
      if (!isStaff(interaction.member)) return reply(interaction, "❌ Staff only.");
      if (!["funded", "released", "payout_pending"].includes(deal.state)) return reply(interaction, "❌ Nothing to refund.");
      deal.resultNote = value;
      deal.state = "refunded";
      saveStore();
      await reply(interaction, "✅ Deal marked as refunded.");
      await refreshPaymentCard(deal);
      await advance(deal, { summary: `↩️  **Refunded by staff**  ·  ${mention(user.id)}`, ping: [deal.senderId] });
      return logLine(`↩️ Deal #${deal.n}: PayPal payment refunded by <@${user.id}>.`);
    }

    // payout / refund: both send the whole balance of the deal address
    const isRefund = kind === "refund";
    if (isRefund ? !isStaff(interaction.member) : user.id !== deal.receiverId) return reply(interaction, "❌ Not allowed.");
    if (!isValidLtcAddress(value)) return reply(interaction, "❌ That is not a valid Litecoin address.");
    if (value === deal.address) return reply(interaction, "❌ You cannot send the funds back to the deposit address.");

    await interaction.deferReply({ flags: ephemeral });

    const result = await withLock(deal.channelId, async () => {
      const allowed = isRefund ? ["confirming", "funded", "released"] : ["released"];
      if (!allowed.includes(deal.state) || (!isRefund && deal.frozen)) return { error: "This is not possible in the current state of the deal." };
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
        return { error: error?.message || String(error) };
      }
    });

    if (result.error) {
      console.error(`⚠️ Middleman: ${isRefund ? "refund" : "payout"} failed for deal #${deal.n}:`, result.error);
      return interaction.editReply(`❌ Could not send the funds: ${result.error}\nNothing was lost, you can try again.`);
    }

    const { sent } = result;
    await interaction.editReply("✅ Funds sent.");
    await refreshPaymentCard(deal);
    await advance(deal, {
      summary: isRefund
        ? `↩️  **Refunded by staff**  ·  ${satToLtc(sent.outValue)} LTC`
        : `🏦  **Payout address received**  ·  ${satToLtc(sent.outValue)} LTC sent`,
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
    if (typeof id !== "string" || !id.startsWith("mm:")) return false;

    try {
      if (!enabled) {
        await reply(interaction, "❌ The middleman is not configured yet (MM_SEED is missing).");
        return true;
      }

      const deal = store.deals[interaction.channelId];
      if (!deal) {
        await reply(interaction, "❌ This deal no longer exists.");
        return true;
      }

      const parts = id.split(":"); // mm:action[:arg]  |  mm:m:kind
      if (interaction.isModalSubmit()) await handleModal(interaction, deal, parts[2]);
      else if (interaction.isButton()) await handleButton(interaction, deal, parts[1], parts[2], parts[3]);
    } catch (error) {
      console.error("⚠️ Middleman error:", error?.message || error);
      const message = "❌ Something went wrong. Check the bot console.";
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

  return { init, openDeal, blocksClose, forget, handleInteraction, newSeed, paypalStatus };
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
        { name: "3️⃣  Pay", value: "The payer sends it by PayPal with the **reference**.", inline: true },
        { name: "4️⃣  Staff checks", value: "Staff verifies the payment on PayPal.", inline: true },
        { name: "5️⃣  Deliver & release", value: "The seller delivers, the payer releases.", inline: true },
        { name: "6️⃣  Payout", value: "Staff sends the money to the seller.", inline: true }
      )
      .setFooter({ text: "Always write the reference in the PayPal note  ·  every payment is checked by staff" });
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
      .setFooter({ text: "Amounts can be typed in LTC, $ or €  ·  small network fee applies" });
    row = new ActionRowBuilder().addComponents(
      new ButtonBuilder().setCustomId("open_ticket:ltc").setLabel("Open a Litecoin ticket").setEmoji("💱").setStyle(ButtonStyle.Primary)
    );
  }
  await interaction.channel.send({ embeds: [embed], components: [row] });
  return interaction.reply({ content: `✅ ${type === "paypal" ? "PayPal" : "Litecoin"} panel posted.`, flags: ephemeral });
}

/* ---------- tickets ---------- */

async function openTicket(interaction) {
  const method = interaction.customId === "open_ticket:paypal" ? "paypal" : "ltc"; // an older panel button is just "open_ticket"
  if (method === "paypal") {
    const status = middleman.paypalStatus();
    if (!status.configured) return interaction.reply({ content: "❌ PayPal tickets are not available right now.", flags: ephemeral });
    if (!status.available) return interaction.reply({ content: "❌ No PayPal account is available right now (everyone is absent). Please try again later.", flags: ephemeral });
  }
  await interaction.deferReply({ flags: ephemeral });
  const { guild, user } = interaction;

  const existing = guild.channels.cache.find(
    (c) => c.type === ChannelType.GuildText && (c.topic === `mm-ticket:${user.id}:${method}` || (method === "ltc" && c.topic === `mm-ticket:${user.id}`))
  );
  if (existing) return interaction.editReply(`❌ You already have an open ticket: ${existing}`);

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
  if (STAFF_ROLE_ID && guild.roles.cache.has(STAFF_ROLE_ID)) overwrites.push({ id: STAFF_ROLE_ID, allow });

  const parent = CATEGORY_ID ? await guild.channels.fetch(CATEGORY_ID).catch(() => null) : null;
  const safeName = user.username.toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 18) || "user";

  const channel = await guild.channels.create({
    name: `${method === "paypal" ? "paypal" : "ltc"}-${safeName}`,
    type: ChannelType.GuildText,
    parent: parent?.type === ChannelType.GuildCategory ? parent.id : undefined,
    topic: `mm-ticket:${user.id}:${method}`,
    permissionOverwrites: overwrites,
  });

  const welcome = new EmbedBuilder()
    .setColor(method === "paypal" ? 0x0070ba : 0x5865f2)
    .setTitle(method === "paypal" ? "💙  Your PayPal middleman ticket" : "💱  Your Litecoin middleman ticket")
    .setDescription(`Welcome ${user}!\nFollow the **deal card** below, it guides you step by step and updates by itself.\n\n🚨 Anything wrong? **Call staff** on the card, the deal is frozen until staff decides.`);
  const close = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId("ticket_close").setLabel("Close ticket").setEmoji("🔒").setStyle(ButtonStyle.Secondary)
  );
  await channel.send({
    content: STAFF_ROLE_ID ? `<@&${STAFF_ROLE_ID}> ${user}` : `${user}`,
    embeds: [welcome],
    components: [close],
    allowedMentions: { roles: STAFF_ROLE_ID ? [STAFF_ROLE_ID] : [], users: [user.id] },
  });

  await middleman.openDeal(channel, user, method).catch((error) => {
    console.error("Middleman could not start:", error?.message || error);
    return channel.send("❌ The middleman could not start. Staff has been pinged.").catch(() => {});
  });

  return interaction.editReply(`✅ Ticket created: ${channel}`);
}

async function closeTicket(interaction) {
  const channel = interaction.channel;
  if (!channel?.topic?.startsWith("mm-ticket:")) {
    return interaction.reply({ content: "❌ This is not a middleman ticket.", flags: ephemeral });
  }
  const ownerId = channel.topic.split(":")[1];
  if (interaction.user.id !== ownerId && !isStaff(interaction.member)) {
    return interaction.reply({ content: "❌ Only the ticket owner or staff can close this ticket.", flags: ephemeral });
  }
  if (middleman.blocksClose(channel.id)) {
    return interaction.reply({ content: "❌ The deal in this ticket still holds funds. Finish it or refund it first.", flags: ephemeral });
  }
  middleman.forget(channel.id);
  await interaction.reply("🔒 Ticket closed. This channel will be deleted in 5 seconds.");
  setTimeout(() => channel.delete("middleman ticket closed").catch(() => {}), 5000);
}

/* ---------- events ---------- */

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    if (await middleman.handleInteraction(interaction)) return;

    if (interaction.isChatInputCommand() && interaction.commandName === "panel") return await postPanel(interaction);
    if (interaction.isButton() && (interaction.customId === "open_ticket" || interaction.customId.startsWith("open_ticket:"))) return await openTicket(interaction);
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
      ],
    });
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    console.error("❌ Could not start:", error?.message || error);
    process.exit(1);
  }
})();
