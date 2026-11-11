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
    if (/^(ltc)?$/.test(rest)) return { kind: "LTC", value: number };
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

  let store = { nextIndex: 0, nextDeal: 1, walletCheck: "", deals: {} };

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
  const STEP_OF = { partner: 0, roles: 1, amount: 2, amount_confirm: 2, awaiting_payment: 3, confirming: 3, funded: 4, released: 5, paying: 5, done: 6 };
  const STATE_COLOR = {
    partner: 0x5865f2, roles: 0x5865f2, amount: 0x5865f2, amount_confirm: 0x5865f2,
    awaiting_payment: 0xfaa61a, confirming: 0xf57c00, funded: 0x2ecc71, released: 0x1abc9c, paying: 0x1abc9c,
    done: 0x2ecc71, refunded: 0x747f8d, cancelled: 0x747f8d,
  };

  const stepper = (deal) => {
    const current = STEP_OF[deal.state];
    if (current === undefined) return "";
    return STEPS.map((label, i) => (i < current ? `✅ ${label}` : i === current ? `🔵 **${label}**` : `⚪ ${label}`)).join("  ›  ");
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

  function stateText(deal) {
    const sender = mention(deal.senderId);
    const receiver = mention(deal.receiverId);
    switch (deal.state) {
      case "partner": return "**Add the person you trade with.**\nClick the button below and send their @mention or user ID.";
      case "roles": return "**Pick your roles.**\n📤 The *sender* pays the LTC.   📥 The *receiver* gets it when the deal is done.";
      case "amount": return `**${sender}: set the amount.**\nType it in LTC (\`0.25\`) or in money (\`5$\`, \`5€\`).`;
      case "amount_confirm": return `**${receiver}: check the amount and confirm it.**\nOnce confirmed, the LTC figure is locked, even if the price moves.`;
      case "awaiting_payment": return `**${sender}: send the exact amount below** from a wallet you control.\nThe bot spots the payment by itself, nothing to click.`;
      case "confirming": return "**Payment spotted!**\nThe network is confirming it, this card updates by itself.";
      case "funded": return `**Funds secured.**\n📥 ${receiver}: deliver what was agreed.\n📤 ${sender}: click **Release** only once you really received it.`;
      case "released": return `**Funds released.**\n📥 ${receiver}: click **Enter my LTC address** to get paid.`;
      case "paying": return "**Sending the funds…**";
      case "done": return "**Deal complete.** Thank you both 💜";
      case "refunded": return "**Refunded to the sender.**";
      case "cancelled": return "**Deal cancelled.**";
      default: return "";
    }
  }

  function dealEmbed(deal) {
    const color = deal.frozen ? COLORS.bad : STATE_COLOR[deal.state] || COLORS.info;
    const amountLine = deal.amountSat
      ? `**${satToLtc(deal.amountSat)} LTC**${deal.quote ? `\n${quoteText(deal.quote)}` : ""}`
      : "*not set yet*";

    const embed = new EmbedBuilder()
      .setColor(color)
      .setTitle(`💱  Litecoin Middleman  ·  Deal #${deal.n}`)
      .setDescription([deal.frozen ? "🧊 **FROZEN: a dispute is open, staff will decide.**\n" : "", stepper(deal), "", stateText(deal)].filter((x) => x !== "").join("\n"))
      .addFields(
        { name: "📤  Sender", value: deal.senderId ? mention(deal.senderId) : "*waiting…*", inline: true },
        { name: "📥  Receiver", value: deal.receiverId ? mention(deal.receiverId) : "*waiting…*", inline: true },
        { name: "💰  Amount", value: amountLine, inline: true }
      )
      .setFooter({ text: "VXMP MM  ·  funds are held by the bot until release" })
      .setTimestamp();

    if (deal.state === "awaiting_payment" || deal.state === "confirming") {
      const confirming = deal.state === "confirming";
      const checked = deal.lastCheck ? `\n🔄 Last check <t:${unix(deal.lastCheck)}:R>` : "";
      embed.addFields(
        { name: "💳  Send exactly", value: `\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\``, inline: true },
        { name: "📮  To this address (this deal only)", value: `\`\`\`${deal.address}\`\`\`` },
        {
          name: "⏱️  Progress",
          value: confirming
            ? `${bar(deal.confirmations, cfg.confirmations)}  **${Math.min(deal.confirmations, cfg.confirmations)}/${cfg.confirmations}** confirmations\nSeen: **${satToLtc(deal.seenSat)} LTC**${checked}`
            : `${bar(0, cfg.confirmations)}  waiting for the payment\nNeeds ${cfg.confirmations} confirmation(s) after sending (about ${Math.round(cfg.confirmations * 2.5)} min)${checked}`,
        }
      );
      if (cfg.qr && deal.address) embed.setThumbnail(qrUrl(deal));
    }

    if (deal.payoutTxid) embed.addFields({ name: "🏦  Payout", value: `${txLink(deal.payoutTxid)}\n\`${deal.payoutAddress}\`` });
    if (deal.refundTxid) embed.addFields({ name: "↩️  Refund", value: `${txLink(deal.refundTxid)}\n\`${deal.refundAddress}\`` });
    if (deal.payoutTxid || deal.refundTxid) embed.addFields({ name: "🧾  Network fee", value: `${satToLtc(deal.feeSat)} LTC (deducted from the amount sent)` });
    return embed;
  }

  function dealComponents(deal) {
    const rows = [];
    const s = deal.state;
    const main = [];

    if (s === "partner") main.push(button("partner", "Add the other person", ButtonStyle.Primary, "➕"));
    if (s === "roles") main.push(button("role:sender", "I send the LTC", ButtonStyle.Primary, "📤"), button("role:receiver", "I receive the LTC", ButtonStyle.Success, "📥"));
    if (s === "amount") main.push(button("amount", "Set the amount", ButtonStyle.Primary, "💰"));
    if (s === "amount_confirm") main.push(button("confirm_amount", "Confirm the amount", ButtonStyle.Success, "✅"), button("amount", "Change amount", ButtonStyle.Secondary, "✏️"));
    if (s === "funded") main.push(button("release", "Release the funds", ButtonStyle.Success, "🔓"));
    if (s === "released") main.push(button("payout", "Enter my LTC address", ButtonStyle.Success, "🏦"));
    if (["partner", "roles", "amount", "amount_confirm", "awaiting_payment"].includes(s)) main.push(button("cancel", "Cancel", ButtonStyle.Danger, "✖️"));
    if (["awaiting_payment", "confirming", "funded", "released"].includes(s) && !deal.frozen) main.push(button("dispute", "Call staff", ButtonStyle.Danger, "🚨"));
    if (main.length) rows.push(new ActionRowBuilder().addComponents(main));

    const staff = [];
    if (deal.frozen) staff.push(button("unfreeze", "Unfreeze (staff)", ButtonStyle.Secondary, "🧊"));
    if (s === "funded") staff.push(button("force_release", "Force release (staff)", ButtonStyle.Primary, "⚖️"));
    if (s === "confirming" || s === "funded" || s === "released") staff.push(button("refund", "Refund sender (staff)", ButtonStyle.Danger, "↩️"));
    if (FINAL.has(s)) staff.push(button("close", "Close channel (staff)", ButtonStyle.Secondary, "🗑️"));
    if (staff.length) rows.push(new ActionRowBuilder().addComponents(staff));
    return rows;
  }

  const render = (deal) => ({ embeds: [dealEmbed(deal)], components: dealComponents(deal) });

  async function getChannel(deal) {
    return client.channels.fetch(deal.channelId).catch(() => null);
  }

  async function refreshMain(deal) {
    deal.lastRefresh = Date.now();
    const channel = await getChannel(deal);
    if (!channel) return;
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

  /* A short coloured card (with pings) posted under the main deal card. */
  async function notify(deal, { title, body, color = COLORS.info, ping = [], thumbnail }) {
    const channel = await getChannel(deal);
    if (!channel) return;
    const embed = new EmbedBuilder().setColor(color).setTitle(title).setDescription(body).setTimestamp();
    if (thumbnail) embed.setThumbnail(thumbnail);
    const mentions = ping.filter(Boolean).map((id) => (/^\d{15,25}$/.test(String(id)) ? mention(id) : id));
    await channel
      .send({ content: mentions.join(" ") || undefined, embeds: [embed], allowedMentions: { parse: ["users", "roles"] } })
      .catch(() => {});
  }

  async function logLine(text) {
    if (!options.logChannelId) return;
    const channel = await client.channels.fetch(options.logChannelId).catch(() => null);
    if (channel?.isTextBased()) await channel.send({ content: text, allowedMentions: { parse: [] } }).catch(() => {});
  }

  const staffPing = () => (options.staffRoleId ? `<@&${options.staffRoleId}>` : "Staff");
  const reply = (interaction, content) => interaction.reply({ content, flags: ephemeral });

  /* ---------- blockchain watcher ---------- */

  async function checkDeal(deal) {
    const utxos = await getUtxos(deal.address);
    if (!utxos.length) return;
    const tip = await getTipHeight();

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
      await refreshMain(deal);
      await notify(deal, {
        title: "✅  Funds secured",
        body: `**${satToLtc(confirmedSat)} LTC** received and confirmed.\nThe bot holds them until the deal is done.\n\n📥 ${mention(deal.receiverId)} deliver what was agreed.\n📤 ${mention(deal.senderId)} click **Release** once you got it.`,
        color: COLORS.ok,
        ping: [deal.receiverId, deal.senderId],
      });
      await logLine(`💰 Deal #${deal.n} funded: ${satToLtc(confirmedSat)} LTC (<#${deal.channelId}>).`);
      return;
    }

    if (deal.state === "awaiting_payment") {
      deal.state = "confirming";
      saveStore();
      await refreshMain(deal);
      await notify(deal, {
        title: "👀  Payment spotted",
        body: `**${satToLtc(seenSat)} LTC** seen on the deposit address.\nWaiting for **${cfg.confirmations}** confirmation(s), about ${Math.round(cfg.confirmations * 2.5)} min.\n\nThe deal card above shows the live progress.`,
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
        if (deal.state !== "awaiting_payment" && deal.state !== "confirming") continue;
        deal.lastCheck = Date.now();
        await withLock(deal.channelId, () => checkDeal(deal)).catch((error) =>
          console.error(`⚠️ Middleman: check failed for deal #${deal.n}:`, error?.message || error)
        );
        // refresh the card now and then so "Last check" stays alive (about once a minute)
        if (["awaiting_payment", "confirming"].includes(deal.state) && Date.now() - (deal.lastRefresh || 0) > 55000) {
          await refreshMain(deal).catch(() => {});
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
  async function openDeal(channel, user) {
    if (!enabled) {
      await channel.send("❌ The middleman is not configured yet (MM_SEED is missing). Staff has been notified in this ticket.");
      return false;
    }

    const n = store.nextDeal++;
    const deal = {
      n,
      channelId: channel.id,
      messageId: "",
      userA: user.id,
      userB: null,
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
    if (["confirming", "funded", "released", "paying"].includes(deal.state)) return true;
    return deal.state === "awaiting_payment" && deal.seenSat > 0;
  }

  async function handleButton(interaction, deal, action, arg) {
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
        if (deal.senderId && deal.receiverId) deal.state = "amount";
        saveStore();
        return interaction.update(render(deal));
      }

      case "amount": {
        if (!["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ The amount can no longer be changed.");
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender sets the amount.");
        const modal = new ModalBuilder().setCustomId("mm:m:amount").setTitle("Amount to send")
          .addComponents(new ActionRowBuilder().addComponents(
            new TextInputBuilder().setCustomId("value").setLabel("Amount: 0.25 (LTC) / 5$ / 5€").setPlaceholder("0.25   or   0.01$   or   5€").setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(24)
          ));
        return interaction.showModal(modal);
      }

      case "confirm_amount": {
        if (deal.state !== "amount_confirm") return reply(interaction, "❌ Nothing to confirm right now.");
        if (user.id !== deal.receiverId) return reply(interaction, "❌ Only the LTC receiver confirms the amount.");
        if (!deal.address) {
          deal.index = store.nextIndex++;
          deal.address = addressOf(deal.index);
        }
        deal.state = "awaiting_payment";
        saveStore();
        await interaction.update(render(deal));
        return notify(deal, {
          title: "💳  Payment instructions",
          body: `📤 ${mention(deal.senderId)} send exactly\n\`\`\`${satToLtc(deal.amountSat)} LTC\`\`\`to this address\n\`\`\`${deal.address}\`\`\`🔒 The amount is **locked** now, it will not change even if the price moves.\nThe bot announces it here as soon as it sees the transaction.`,
          color: COLORS.wait,
          ping: [deal.senderId],
          thumbnail: cfg.qr ? qrUrl(deal) : undefined,
        });
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

      case "release_no":
        return interaction.update({ content: "Cancelled, nothing was released.", components: [] });

      case "release_yes": {
        if (user.id !== deal.senderId) return reply(interaction, "❌ Only the LTC sender can release the funds.");
        if (deal.state !== "funded" || deal.frozen) return interaction.update({ content: "❌ Not possible right now.", components: [] });
        deal.state = "released";
        saveStore();
        await interaction.update({ content: "✅ Released.", components: [] });
        await refreshMain(deal);
        return notify(deal, {
          title: "🔓  Funds released",
          body: `${mention(deal.senderId)} confirmed the delivery.\n\n📥 ${mention(deal.receiverId)} click **Enter my LTC address** to get paid.`,
          color: 0x1abc9c,
          ping: [deal.receiverId],
        });
      }

      case "payout": {
        if (user.id !== deal.receiverId) return reply(interaction, "❌ Only the LTC receiver can enter the payout address.");
        if (deal.state !== "released") return reply(interaction, "❌ The funds were not released yet.");
        if (frozenBlock()) return;
        return interaction.showModal(addressModal("mm:m:payout", "Where should we send the LTC?", "Your Litecoin address"));
      }

      case "dispute": {
        if (needParticipant()) return;
        if (deal.frozen) return reply(interaction, "Already frozen.");
        deal.frozen = true;
        saveStore();
        await interaction.update(render(deal));
        await notify(deal, {
          title: "🚨  Staff called",
          body: `${mention(user.id)} called staff on deal #${deal.n}.\nThe deal is **frozen** until staff decides.`,
          color: COLORS.bad,
          ping: [staffPing()],
        });
        return logLine(`🚨 Deal #${deal.n} frozen by <@${user.id}> (<#${deal.channelId}>).`);
      }

      case "unfreeze": {
        if (needStaff()) return;
        deal.frozen = false;
        saveStore();
        await interaction.update(render(deal));
        return notify(deal, { title: "🧊  Deal unfrozen", body: `Unfrozen by ${mention(user.id)}. The deal can continue.`, color: COLORS.info });
      }

      case "force_release": {
        if (needStaff()) return;
        if (deal.state !== "funded") return reply(interaction, "❌ Funds are not in a releasable state.");
        deal.state = "released";
        deal.frozen = false;
        saveStore();
        await interaction.update(render(deal));
        await notify(deal, {
          title: "⚖️  Released by staff",
          body: `Staff (${mention(user.id)}) released the funds.\n\n📥 ${mention(deal.receiverId)} click **Enter my LTC address**.`,
          color: 0x1abc9c,
          ping: [deal.receiverId],
        });
        return logLine(`⚖️ Deal #${deal.n} force-released by <@${user.id}>.`);
      }

      case "refund": {
        if (needStaff()) return;
        if (!["confirming", "funded", "released"].includes(deal.state)) return reply(interaction, "❌ Nothing to refund.");
        return interaction.showModal(addressModal("mm:m:refund", "Refund address of the sender", "Sender's Litecoin address"));
      }

      case "cancel": {
        if (needParticipant()) return;
        if (!["partner", "roles", "amount", "amount_confirm", "awaiting_payment"].includes(deal.state)) return reply(interaction, "❌ This deal can no longer be cancelled here. Call staff.");
        deal.state = "cancelled";
        saveStore();
        await interaction.update(render(deal));
        return notify(deal, {
          title: "✖️  Deal cancelled",
          body: `Cancelled by ${mention(user.id)}.\nDo **not** send any LTC to the deposit address anymore.`,
          color: COLORS.grey,
        });
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
      await refreshMain(deal);
      return notify(deal, {
        title: "➕  Partner added",
        body: `${mention(id)} joined the ticket (added by ${mention(user.id)}).\n\n📤📥 ${mention(deal.userA)} ${mention(id)} each of you picks a role with the buttons above.`,
        color: COLORS.info,
        ping: [id],
      });
    }

    if (kind === "amount") {
      if (user.id !== deal.senderId || !["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ Not possible right now.");
      if (!parseAmountInput(value)) return reply(interaction, "❌ Invalid amount. Examples: `0.25` (LTC), `5$` (dollars), `5€` (euros).");
      await interaction.deferUpdate(); // the price lookup can take a moment
      const result = await resolveAmount(value).catch((error) => ({ error: error?.message || String(error) }));
      if (result.error) return interaction.followUp({ content: `❌ ${result.error}`, flags: ephemeral });
      if (result.sat < cfg.minSat) {
        return interaction.followUp({ content: `❌ That is only ${satToLtc(result.sat)} LTC. Minimum deal: ${satToLtc(cfg.minSat)} LTC.`, flags: ephemeral });
      }
      deal.amountSat = result.sat;
      deal.quote = result.quote;
      deal.state = "amount_confirm";
      saveStore();
      await refreshMain(deal);
      return notify(deal, {
        title: "💰  Amount set",
        body: `${mention(deal.senderId)} set the amount to\n\`\`\`${satToLtc(result.sat)} LTC\`\`\`${result.quote ? `${quoteText(result.quote)}\n\n` : "\n"}📥 ${mention(deal.receiverId)} confirm it with the button above.\n⚠️ **Not final yet.** The sender can still change it. Once you confirm, the LTC figure is locked.`,
        color: COLORS.info,
        ping: [deal.receiverId],
      });
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
    await refreshMain(deal);
    await notify(deal, isRefund
      ? { title: "↩️  Refund sent", body: `**${satToLtc(sent.outValue)} LTC** went back to the sender.\n${txLink(sent.txid)}`, color: COLORS.grey, ping: [deal.senderId] }
      : { title: "🎉  Deal complete", body: `${mention(deal.receiverId)} received **${satToLtc(sent.outValue)} LTC**.\nNetwork fee: ${satToLtc(sent.fee)} LTC\n${txLink(sent.txid)}\n\nThank you both 💜`, color: COLORS.ok, ping: [deal.receiverId, deal.senderId] });
    return logLine(`${isRefund ? "↩️ Refund" : "✅ Payout"} deal #${deal.n}: ${satToLtc(sent.outValue)} LTC, tx ${sent.txid}`);
  }

  /* Returns true when the interaction belongs to the middleman, so index.js stops there. */
  async function handleInteraction(interaction) {
    const id = interaction.customId;
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
      else if (interaction.isButton()) await handleButton(interaction, deal, parts[1], parts[2]);
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

  return { init, openDeal, blocksClose, forget, handleInteraction, newSeed };
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

/* ---------- panel ---------- */

async function postPanel(interaction) {
  if (!interaction.memberPermissions.has(PermissionFlagsBits.Administrator)) {
    return interaction.reply({ content: "❌ Only administrators can use this command.", flags: ephemeral });
  }
  const embed = new EmbedBuilder()
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
  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId("open_ticket").setLabel("Open a middleman ticket").setEmoji("💱").setStyle(ButtonStyle.Primary)
  );
  await interaction.channel.send({ embeds: [embed], components: [row] });
  return interaction.reply({ content: "✅ Panel posted.", flags: ephemeral });
}

/* ---------- tickets ---------- */

async function openTicket(interaction) {
  await interaction.deferReply({ flags: ephemeral });
  const { guild, user } = interaction;

  const existing = guild.channels.cache.find(
    (c) => c.type === ChannelType.GuildText && c.topic === `mm-ticket:${user.id}`
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
    name: `middleman-${safeName}`,
    type: ChannelType.GuildText,
    parent: parent?.type === ChannelType.GuildCategory ? parent.id : undefined,
    topic: `mm-ticket:${user.id}`,
    permissionOverwrites: overwrites,
  });

  const welcome = new EmbedBuilder()
    .setColor(0x5865f2)
    .setTitle("🎫  Your middleman ticket")
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

  await middleman.openDeal(channel, user).catch((error) => {
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
    if (interaction.isButton() && interaction.customId === "open_ticket") return await openTicket(interaction);
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
      body: [new SlashCommandBuilder().setName("panel").setDescription("Post the middleman ticket panel here.").toJSON()],
    });
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    console.error("❌ Could not start:", error?.message || error);
    process.exit(1);
  }
})();
