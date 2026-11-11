"use strict";

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
    MM_MIN_LTC=0.001                       smallest deal accepted
    MM_CATEGORY_ID=...                     category where the deal channels are created (optional)
    LTC_API_URL=https://litecoinspace.org/api    Esplora-compatible API (default)
    LTC_EXPLORER_TX_URL=https://litecoinspace.org/tx/
    MM_POLL_SECONDS=30  MM_MIN_FEE_RATE=2

  SECURITY: MM_SEED controls every deposit address. Keep it out of git, keep the host private, and do
  not leave large amounts on it: it is a hot wallet. Back the seed up offline.
*/

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

const cfg = {
  seed: (process.env.MM_SEED || "").trim(),
  apiUrl: (process.env.LTC_API_URL || "https://litecoinspace.org/api").replace(/\/+$/, ""),
  explorerTx: process.env.LTC_EXPLORER_TX_URL || "https://litecoinspace.org/tx/",
  confirmations: Math.max(1, Number(process.env.MM_CONFIRMATIONS) || 2),
  pollMs: Math.max(10, Number(process.env.MM_POLL_SECONDS) || 30) * 1000,
  minFeeRate: Math.max(1, Number(process.env.MM_MIN_FEE_RATE) || 2),
  minSat: ltcToSat(process.env.MM_MIN_LTC || "0.001") || 100000,
  categoryId: process.env.MM_CATEGORY_ID || "",
};

const DATA_FILE = path.join(process.env.DATA_DIR || __dirname, "middleman.json");

/* =====================================================
   WALLET (HD, BIP84, coin type 2 = Litecoin)
===================================================== */

let root = null;

function initWallet() {
  if (!bip39.validateMnemonic(cfg.seed)) {
    throw new Error("MM_SEED is not a valid BIP39 mnemonic.");
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

function dealEmbed(deal) {
  const color = deal.state === "done" ? COLORS.ok : FINAL.has(deal.state) ? COLORS.grey : deal.frozen ? COLORS.bad : COLORS.info;
  const embed = new EmbedBuilder()
    .setColor(color)
    .setTitle(`Litecoin middleman — deal #${deal.n}`)
    .addFields(
      { name: "LTC sender", value: mention(deal.senderId), inline: true },
      { name: "LTC receiver", value: mention(deal.receiverId), inline: true },
      { name: "Amount", value: deal.amountSat ? `**${satToLtc(deal.amountSat)} LTC**` : "*not set*", inline: true },
      { name: "Status", value: `${deal.frozen ? "🧊 **FROZEN (dispute)** — " : ""}${STATE_TEXT[deal.state] || deal.state}` }
    );

  if (deal.state === "partner") {
    embed.setDescription("**Step 1.** Click the button and give the **@mention or ID** of the person you are trading with. They will be added to this ticket.");
  } else if (deal.state === "roles") {
    embed.setDescription("Each of you picks a role. The **sender** pays the LTC, the **receiver** gets it once the deal is done.");
  } else if (deal.state === "awaiting_payment" || deal.state === "confirming") {
    embed.setColor(deal.frozen ? COLORS.bad : COLORS.wait).addFields(
      { name: "Send exactly", value: `\`${satToLtc(deal.amountSat)}\` LTC`, inline: true },
      { name: "To this address (only for this deal)", value: `\`${deal.address}\`` },
      {
        name: "Progress",
        value: deal.state === "confirming"
          ? `Detected **${satToLtc(deal.seenSat)} LTC**, ${deal.confirmations}/${cfg.confirmations} confirmations.`
          : `Needs ${cfg.confirmations} confirmation(s) (about ${cfg.confirmations * 2.5} min). Send from a wallet you control. Do not send after the deal is cancelled.`,
      }
    );
  } else if (deal.state === "funded") {
    embed.setColor(COLORS.ok).addFields({
      name: "Next",
      value: `${mention(deal.receiverId)} delivers what was agreed.\n${mention(deal.senderId)} clicks **Release** only after you really received it.`,
    });
  } else if (deal.state === "released") {
    embed.addFields({ name: "Next", value: `${mention(deal.receiverId)} clicks **Enter my LTC address**. The bot sends the funds right after.` });
  }

  if (deal.payoutTxid) embed.addFields({ name: "Payout", value: `${txLink(deal.payoutTxid)} → \`${deal.payoutAddress}\``, });
  if (deal.refundTxid) embed.addFields({ name: "Refund", value: `${txLink(deal.refundTxid)} → \`${deal.refundAddress}\`` });
  if (deal.payoutTxid || deal.refundTxid) embed.addFields({ name: "Network fee", value: `${satToLtc(deal.feeSat)} LTC (deducted from the amount sent)` });
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
  if (s === "funded" || s === "released") staff.push(button("refund", "Refund sender (staff)", ButtonStyle.Danger, "↩️"));
  if (FINAL.has(s)) staff.push(button("close", "Close channel (staff)", ButtonStyle.Secondary, "🗑️"));
  if (staff.length) rows.push(new ActionRowBuilder().addComponents(staff));
  return rows;
}

const render = (deal) => ({ embeds: [dealEmbed(deal)], components: dealComponents(deal) });

async function getChannel(deal) {
  return client.channels.fetch(deal.channelId).catch(() => null);
}

async function refreshMain(deal) {
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

async function say(deal, content) {
  const channel = await getChannel(deal);
  if (channel) await channel.send({ content, allowedMentions: { parse: ["users", "roles"] } }).catch(() => {});
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
    await say(deal, `✅ ${mention(deal.senderId)} ${mention(deal.receiverId)} — **${satToLtc(confirmedSat)} LTC** received and confirmed. The funds are held by the bot.\n${mention(deal.receiverId)}: deliver what was agreed. ${mention(deal.senderId)}: click **Release** once you got it.`);
    await logLine(`💰 Deal #${deal.n} funded: ${satToLtc(confirmedSat)} LTC (<#${deal.channelId}>).`);
    return;
  }

  if (deal.state === "awaiting_payment") {
    deal.state = "confirming";
    saveStore();
    await refreshMain(deal);
    await say(deal, `👀 Payment detected: **${satToLtc(seenSat)} LTC**. Waiting for ${cfg.confirmations} confirmation(s).`);
    return;
  }

  if (`${deal.state}|${deal.seenSat}|${deal.confirmations}` !== before) {
    saveStore();
    await refreshMain(deal);
  }

  if (confirmedSat > 0 && confirmedSat === seenSat && !deal.shortWarned) {
    deal.shortWarned = true;
    saveStore();
    await say(deal, `⚠️ ${mention(deal.senderId)} the confirmed payment (**${satToLtc(confirmedSat)} LTC**) is lower than the agreed **${satToLtc(deal.amountSat)} LTC**. Send the missing part to the same address, or ${staffPing()} can refund it.`);
  }
}

let ticking = false;
async function watcherTick() {
  if (ticking) return;
  ticking = true;
  try {
    for (const deal of Object.values(store.deals)) {
      if (deal.state !== "awaiting_payment" && deal.state !== "confirming") continue;
      await withLock(deal.channelId, () => checkDeal(deal)).catch((error) =>
        console.error(`⚠️ Middleman: check failed for deal #${deal.n}:`, error?.message || error)
      );
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
          new TextInputBuilder().setCustomId("value").setLabel("Amount in LTC (example: 0.25)").setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(20)
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
      return say(deal, `💳 ${mention(deal.senderId)} send exactly **${satToLtc(deal.amountSat)} LTC** to \`${deal.address}\`.\nThe bot will announce it here as soon as it sees the transaction.`);
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
      return say(deal, `🔓 ${mention(deal.senderId)} released the funds. ${mention(deal.receiverId)}: click **Enter my LTC address** to get paid.`);
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
      await say(deal, `🚨 ${staffPing()} — ${mention(user.id)} called staff on deal #${deal.n}. The deal is **frozen** until staff decides.`);
      return logLine(`🚨 Deal #${deal.n} frozen by <@${user.id}> (<#${deal.channelId}>).`);
    }

    case "unfreeze": {
      if (needStaff()) return;
      deal.frozen = false;
      saveStore();
      await interaction.update(render(deal));
      return say(deal, `🧊 Deal unfrozen by ${mention(user.id)}.`);
    }

    case "force_release": {
      if (needStaff()) return;
      if (deal.state !== "funded") return reply(interaction, "❌ Funds are not in a releasable state.");
      deal.state = "released";
      deal.frozen = false;
      saveStore();
      await interaction.update(render(deal));
      await say(deal, `⚖️ Staff (${mention(user.id)}) released the funds. ${mention(deal.receiverId)}: click **Enter my LTC address**.`);
      return logLine(`⚖️ Deal #${deal.n} force-released by <@${user.id}>.`);
    }

    case "refund": {
      if (needStaff()) return;
      if (!["funded", "released"].includes(deal.state)) return reply(interaction, "❌ Nothing to refund.");
      return interaction.showModal(addressModal("mm:m:refund", "Refund address of the sender", "Sender's Litecoin address"));
    }

    case "cancel": {
      if (needParticipant()) return;
      if (!["partner", "roles", "amount", "amount_confirm", "awaiting_payment"].includes(deal.state)) return reply(interaction, "❌ This deal can no longer be cancelled here. Call staff.");
      deal.state = "cancelled";
      saveStore();
      await interaction.update(render(deal));
      return say(deal, `✖️ Deal cancelled by ${mention(user.id)}. Do **not** send any LTC to the deposit address anymore.`);
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
    return say(deal, `➕ ${mention(id)} was added to the ticket by ${mention(user.id)}.\n${mention(deal.userA)} ${mention(id)}: each of you picks a role with the buttons above.`);
  }

  if (kind === "amount") {
    if (user.id !== deal.senderId || !["amount", "amount_confirm"].includes(deal.state)) return reply(interaction, "❌ Not possible right now.");
    const sat = ltcToSat(value);
    if (!sat) return reply(interaction, "❌ Invalid amount. Use a number like `0.25` (max 8 decimals).");
    if (sat < cfg.minSat) return reply(interaction, `❌ Minimum deal: ${satToLtc(cfg.minSat)} LTC.`);
    deal.amountSat = sat;
    deal.state = "amount_confirm";
    saveStore();
    await interaction.deferUpdate();
    await refreshMain(deal);
    return say(deal, `💰 ${mention(deal.senderId)} set the amount to **${satToLtc(sat)} LTC**. ${mention(deal.receiverId)}: confirm it with the button above.`);
  }

  // payout / refund: both send the whole balance of the deal address
  const isRefund = kind === "refund";
  if (isRefund ? !isStaff(interaction.member) : user.id !== deal.receiverId) return reply(interaction, "❌ Not allowed.");
  if (!isValidLtcAddress(value)) return reply(interaction, "❌ That is not a valid Litecoin address.");
  if (value === deal.address) return reply(interaction, "❌ You cannot send the funds back to the deposit address.");

  await interaction.deferReply({ flags: ephemeral });

  const result = await withLock(deal.channelId, async () => {
    const allowed = isRefund ? ["funded", "released"] : ["released"];
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
  await say(deal, isRefund
    ? `↩️ Refund of **${satToLtc(sent.outValue)} LTC** sent to the sender: ${txLink(sent.txid)}`
    : `🎉 ${mention(deal.receiverId)} you received **${satToLtc(sent.outValue)} LTC** (network fee ${satToLtc(sent.fee)} LTC): ${txLink(sent.txid)}\nDeal complete, thank you both.`);
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

module.exports = {
  init,
  openDeal,
  blocksClose,
  forget,
  handleInteraction,
  // exported for tests
  _test: { ltcToSat, satToLtc, initWallet, addressOf, isValidLtcAddress, buildSweepTx, LITECOIN, cfg, watcherTick, getStore: () => store },
};

/* node middleman.js new-seed -> prints a fresh wallet seed and its first address */
if (require.main === module && process.argv[2] === "new-seed") {
  const mnemonic = bip39.generateMnemonic();
  cfg.seed = mnemonic;
  initWallet();
  console.log("\nMM_SEED=" + mnemonic);
  console.log("First deposit address:", addressOf(0));
  console.log("\nPut the MM_SEED line in your .env, and back the words up OFFLINE. Anyone with them controls the funds.\n");
}
