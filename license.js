/*
  Onyx HUB licensing (Luarmor / Polsec style).

  - Keys are created with /key generate, redeemed by customers with the "Redeem Key" button of the /keypanel panel.
  - The customer runs a small loader in their executor. It sends the key and the HWID to the HTTP API below;
    the API binds the key to the first HWID that uses it and then returns the script (it is never posted on Discord).
  - Everything is stored in keys.json (in DATA_DIR if set: on Railway mount a Volume, or the keys vanish at every redeploy).

  Environment variables:
    SCRIPT_URL           private URL the real script is downloaded from (required to deliver the script)
    SCRIPT_AUTH          optional Authorization header for SCRIPT_URL (ex: "token ghp_xxx")
    PUBLIC_URL           public URL of this bot (Railway domain, ex: https://onyxhub-bot.up.railway.app)
    PORT                 set by Railway
    CUSTOMER_ROLE_ID     optional role given when a key is redeemed
    HWID_RESET_COOLDOWN_H  hours between two self-service HWID resets (default 24)
*/

const fs = require("fs");
const path = require("path");
const http = require("http");
const crypto = require("crypto");
const {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  EmbedBuilder,
  ModalBuilder,
  SlashCommandBuilder,
  TextInputBuilder,
  TextInputStyle,
} = require("discord.js");

const KEYS_FILE = path.join(process.env.DATA_DIR || __dirname, "keys.json");
const CUSTOMER_ROLE_ID = process.env.CUSTOMER_ROLE_ID || "";
const RESET_COOLDOWN_MS =
  (Number(process.env.HWID_RESET_COOLDOWN_H) || 24) * 60 * 60 * 1000;
const COLOR = 0x7c3aed;

const DURATION_UNITS = { m: 60e3, h: 3600e3, d: 86400e3, w: 7 * 86400e3 };

/* "30d", "12h", "1w", "lifetime" -> ms, null (lifetime) or undefined (invalid). */
function parseKeyDuration(text) {
  const value = (text || "").trim().toLowerCase();
  if (["lifetime", "life", "perm", "permanent"].includes(value)) return null;
  const match = /^(\d+)([mhdw])$/.exec(value);
  return match ? Number(match[1]) * DURATION_UNITS[match[2]] : undefined;
}

/* ---------------- storage ---------------- */

let store = {};

try {
  store = JSON.parse(fs.readFileSync(KEYS_FILE, "utf8"));
} catch {
  /* no file yet */
}

function save() {
  try {
    const tmp = `${KEYS_FILE}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(store, null, 2));
    fs.renameSync(tmp, KEYS_FILE);
  } catch (error) {
    console.error("Could not save keys.json:", error?.message || error);
  }
}

function newKey() {
  const part = () => crypto.randomBytes(2).toString("hex").toUpperCase();
  return `ONYX-${part()}${part()}-${part()}${part()}-${part()}${part()}`;
}

function createKey(durationMs, createdBy, note) {
  let key;
  do key = newKey();
  while (store[key]);

  store[key] = {
    createdAt: Date.now(),
    createdBy,
    note: note || "",
    durationMs, // null = lifetime
    expiresAt: null, // starts at redeem / first use
    hwid: null,
    userId: null,
    revoked: false,
    lastUsed: null,
    uses: 0,
    lastReset: 0,
  };
  save();
  return key;
}

function normalize(key) {
  return (key || "").trim().toUpperCase();
}

function activate(entry) {
  if (!entry.expiresAt && entry.durationMs) {
    entry.expiresAt = Date.now() + entry.durationMs;
  }
}

function isExpired(entry) {
  return Boolean(entry.expiresAt && entry.expiresAt < Date.now());
}

function keysOfUser(userId) {
  return Object.entries(store)
    .filter(([, entry]) => entry.userId === userId)
    .sort((a, b) => b[1].createdAt - a[1].createdAt);
}

function activeKeyOfUser(userId) {
  return keysOfUser(userId).find(
    ([, entry]) => !entry.revoked && !isExpired(entry)
  );
}

function expiryText(entry) {
  if (entry.durationMs === null) return "Lifetime";
  if (!entry.expiresAt) return `Not started (${Math.round(entry.durationMs / 86400e3 * 10) / 10} day(s) once used)`;
  return `<t:${Math.floor(entry.expiresAt / 1000)}:F> (<t:${Math.floor(entry.expiresAt / 1000)}:R>)`;
}

function keyEmbed(key, entry) {
  const status = entry.revoked ? "⛔ Revoked" : isExpired(entry) ? "⌛ Expired" : "✅ Active";
  return new EmbedBuilder()
    .setColor(COLOR)
    .setTitle("🔑 Key information")
    .addFields(
      { name: "Key", value: `\`${key}\`` },
      { name: "Status", value: status, inline: true },
      { name: "Expires", value: expiryText(entry), inline: true },
      { name: "Owner", value: entry.userId ? `<@${entry.userId}>` : "Not redeemed", inline: true },
      { name: "HWID", value: entry.hwid ? "🔒 Linked" : "Not linked yet", inline: true },
      { name: "Executions", value: String(entry.uses), inline: true },
      {
        name: "Last used",
        value: entry.lastUsed ? `<t:${Math.floor(entry.lastUsed / 1000)}:R>` : "Never",
        inline: true,
      }
    );
}

/* ---------------- validation (used by the HTTP API) ---------------- */

function validate(rawKey, hwid) {
  const key = normalize(rawKey);
  const entry = store[key];

  if (!entry) return { ok: false, reason: "Invalid key." };
  if (entry.revoked) return { ok: false, reason: "This key has been revoked." };
  if (!hwid || hwid.length < 4) return { ok: false, reason: "Missing HWID." };

  activate(entry);

  if (isExpired(entry)) return { ok: false, reason: "This key has expired." };

  if (!entry.hwid) {
    entry.hwid = hwid;
  } else if (entry.hwid !== hwid) {
    return {
      ok: false,
      reason: "HWID mismatch. Reset your HWID from the Discord panel.",
    };
  }

  entry.lastUsed = Date.now();
  entry.uses += 1;
  save();

  return { ok: true };
}

/* ---------------- HTTP API ---------------- */

const hits = new Map(); // ip -> [timestamps]

function rateLimited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 60e3);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > 20;
}

function baseUrl() {
  return (
    process.env.PUBLIC_URL ||
    (process.env.RAILWAY_PUBLIC_DOMAIN ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}` : "")
  ).replace(/\/+$/, "");
}

function loaderLua() {
  return `local key = (getgenv and getgenv().script_key) or script_key
if not key then
  game:GetService("Players").LocalPlayer:Kick("Onyx HUB: set script_key before loading.")
  return
end
local hwid = (gethwid and gethwid()) or game:GetService("RbxAnalyticsService"):GetClientId()
local http = game:GetService("HttpService")
local ok, code = pcall(function()
  return game:HttpGet("${baseUrl()}/script?key=" .. http:UrlEncode(key) .. "&hwid=" .. http:UrlEncode(hwid))
end)
if not ok then
  game:GetService("Players").LocalPlayer:Kick("Onyx HUB: could not reach the server.")
  return
end
loadstring(code)()`;
}

function loadstringFor(key) {
  return `script_key="${key}";\nloadstring(game:HttpGet("${baseUrl()}/load"))()`;
}

function kickLua(reason) {
  return `game:GetService("Players").LocalPlayer:Kick(${JSON.stringify("Onyx HUB: " + reason)})`;
}

let scriptCache = { at: 0, body: "" };

async function fetchScript() {
  if (scriptCache.body && Date.now() - scriptCache.at < 60e3) return scriptCache.body;
  if (!process.env.SCRIPT_URL) throw new Error("SCRIPT_URL is not set");

  const response = await fetch(process.env.SCRIPT_URL, {
    headers: process.env.SCRIPT_AUTH ? { Authorization: process.env.SCRIPT_AUTH } : {},
  });

  if (!response.ok) throw new Error(`script download failed (${response.status})`);

  scriptCache = { at: Date.now(), body: await response.text() };
  return scriptCache.body;
}

function startServer() {
  const port = process.env.PORT;
  if (!port) {
    console.log("ℹ️ No PORT: licensing HTTP API not started.");
    return;
  }

  http
    .createServer(async (req, res) => {
      const url = new URL(req.url, "http://localhost");
      const send = (status, body, type = "text/plain; charset=utf-8") => {
        res.writeHead(status, { "Content-Type": type });
        res.end(body);
      };

      try {
        const ip = (req.headers["x-forwarded-for"] || req.socket.remoteAddress || "").split(",")[0].trim();

        if (url.pathname === "/") return send(200, "Onyx HUB");
        if (url.pathname === "/load") return send(200, loaderLua());

        if (url.pathname === "/script" || url.pathname === "/check") {
          if (rateLimited(ip)) {
            return send(429, kickLua("too many requests, wait a minute."));
          }

          const result = validate(url.searchParams.get("key"), url.searchParams.get("hwid"));

          if (url.pathname === "/check") {
            return send(200, JSON.stringify(result), "application/json");
          }

          if (!result.ok) return send(200, kickLua(result.reason));

          try {
            return send(200, await fetchScript());
          } catch (error) {
            console.error("Script delivery error:", error?.message || error);
            return send(200, kickLua("script temporarily unavailable."));
          }
        }

        send(404, "Not found");
      } catch (error) {
        console.error("HTTP error:", error?.message || error);
        send(500, "error");
      }
    })
    .listen(Number(port), () => console.log(`🔑 Licensing API listening on :${port}`));
}

/* ---------------- Discord side ---------------- */

const commands = [
  new SlashCommandBuilder()
    .setName("key")
    .setDescription("Manage Onyx HUB keys (staff).")
    .addSubcommand((sub) =>
      sub
        .setName("generate")
        .setDescription("Create keys.")
        .addStringOption((o) =>
          o.setName("duration").setDescription("30m, 12h, 7d, 4w or lifetime").setRequired(true)
        )
        .addIntegerOption((o) =>
          o.setName("amount").setDescription("How many keys (1-20).").setMinValue(1).setMaxValue(20)
        )
        .addUserOption((o) =>
          o.setName("user").setDescription("Send the key to this member (DM) and link it to them.")
        )
        .addStringOption((o) => o.setName("note").setDescription("Private note."))
    )
    .addSubcommand((sub) =>
      sub
        .setName("revoke")
        .setDescription("Revoke a key (it stops working).")
        .addStringOption((o) => o.setName("key").setDescription("The key.").setRequired(true))
    )
    .addSubcommand((sub) =>
      sub
        .setName("unrevoke")
        .setDescription("Re-enable a revoked key.")
        .addStringOption((o) => o.setName("key").setDescription("The key.").setRequired(true))
    )
    .addSubcommand((sub) =>
      sub
        .setName("resethwid")
        .setDescription("Unlink the HWID of a key.")
        .addStringOption((o) => o.setName("key").setDescription("The key.").setRequired(true))
    )
    .addSubcommand((sub) =>
      sub
        .setName("info")
        .setDescription("Show a key, or the keys of a member.")
        .addStringOption((o) => o.setName("key").setDescription("The key."))
        .addUserOption((o) => o.setName("user").setDescription("The member."))
    )
    .addSubcommand((sub) =>
      sub.setName("stats").setDescription("Key counters.")
    ),

  new SlashCommandBuilder()
    .setName("keypanel")
    .setDescription("Post the customer panel (redeem key, get script, reset HWID)."),
];

function panelButtons() {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId("key_redeem").setLabel("Redeem Key").setEmoji("🔑").setStyle(ButtonStyle.Success),
    new ButtonBuilder().setCustomId("key_script").setLabel("Get Script").setEmoji("📜").setStyle(ButtonStyle.Primary),
    new ButtonBuilder().setCustomId("key_reset").setLabel("Reset HWID").setEmoji("♻️").setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId("key_info").setLabel("My Key").setEmoji("ℹ️").setStyle(ButtonStyle.Secondary)
  );
}

function panelEmbed() {
  return new EmbedBuilder()
    .setColor(COLOR)
    .setTitle("🔑 Onyx HUB • Key panel")
    .setDescription(
      [
        "🔑 **Redeem Key** — link the key you bought to your Discord account.",
        "📜 **Get Script** — get your personal loader (works with your key and one device).",
        "♻️ **Reset HWID** — unlink your device so you can use the key on another one.",
        "ℹ️ **My Key** — see your key, its expiry and its status.",
      ].join("\n")
    )
    .setFooter({ text: "ORYX HUB • Never share your key." });
}

function noKey(interaction) {
  return interaction.reply({
    content: "❌ You have no active key. Use **Redeem Key** first.",
    ephemeral: true,
  });
}

/* Returns true if the interaction was handled here. */
async function handleInteraction(interaction, { isStaff }) {
  if (interaction.isChatInputCommand() && ["key", "keypanel"].includes(interaction.commandName)) {
    if (!isStaff(interaction)) {
      await interaction.reply({ content: "❌ Only staff can use this command.", ephemeral: true });
      return true;
    }

    if (interaction.commandName === "keypanel") {
      await interaction.channel.send({ embeds: [panelEmbed()], components: [panelButtons()] });
      await interaction.reply({ content: "✅ Key panel posted.", ephemeral: true });
      return true;
    }

    const sub = interaction.options.getSubcommand();

    if (sub === "generate") {
      const duration = parseKeyDuration(interaction.options.getString("duration", true));

      if (duration === undefined) {
        await interaction.reply({ content: "❌ Invalid duration. Use `30m`, `12h`, `7d`, `4w` or `lifetime`.", ephemeral: true });
        return true;
      }

      const amount = interaction.options.getInteger("amount") || 1;
      const user = interaction.options.getUser("user");
      const note = interaction.options.getString("note");
      const keys = [];

      for (let i = 0; i < amount; i++) {
        const key = createKey(duration, interaction.user.id, note);
        if (user) {
          store[key].userId = user.id;
          activate(store[key]);
        }
        keys.push(key);
      }
      save();

      let dmNote = "";

      if (user) {
        const sent = await user
          .send({
            embeds: [
              new EmbedBuilder()
                .setColor(COLOR)
                .setTitle("🔑 Your Onyx HUB key")
                .setDescription(
                  `${keys.map((k) => `\`${k}\``).join("\n")}\n\nUse the **Get Script** button of the key panel to get your loader. Never share your key.`
                ),
            ],
          })
          .then(() => true)
          .catch(() => false);

        dmNote = sent ? `\nSent in DM to ${user}.` : `\n⚠️ Could not DM ${user} (DMs closed); give them the key yourself.`;

        if (CUSTOMER_ROLE_ID) {
          await interaction.guild.members.fetch(user.id).then((m) => m.roles.add(CUSTOMER_ROLE_ID)).catch(() => {});
        }
      }

      await interaction.reply({
        content: `✅ ${amount} key(s) created (${duration === null ? "lifetime" : interaction.options.getString("duration")}):\n${keys.map((k) => `\`${k}\``).join("\n")}${dmNote}`,
        ephemeral: true,
      });
      return true;
    }

    if (sub === "stats") {
      const all = Object.values(store);
      const active = all.filter((e) => !e.revoked && !isExpired(e)).length;
      await interaction.reply({
        content: `📊 **${all.length}** keys: ${active} active, ${all.filter((e) => e.revoked).length} revoked, ${all.filter(isExpired).length} expired, ${all.filter((e) => e.userId).length} redeemed, ${all.filter((e) => e.hwid).length} linked to a device.`,
        ephemeral: true,
      });
      return true;
    }

    if (sub === "info") {
      const rawKey = interaction.options.getString("key");
      const user = interaction.options.getUser("user");

      if (rawKey) {
        const key = normalize(rawKey);
        if (!store[key]) {
          await interaction.reply({ content: "❌ Unknown key.", ephemeral: true });
        } else {
          await interaction.reply({ embeds: [keyEmbed(key, store[key])], ephemeral: true });
        }
        return true;
      }

      if (user) {
        const list = keysOfUser(user.id).slice(0, 5);
        await interaction.reply(
          list.length
            ? { embeds: list.map(([k, e]) => keyEmbed(k, e)), ephemeral: true }
            : { content: "❌ This member has no key.", ephemeral: true }
        );
        return true;
      }

      await interaction.reply({ content: "❌ Give a `key` or a `user`.", ephemeral: true });
      return true;
    }

    const key = normalize(interaction.options.getString("key", true));
    const entry = store[key];

    if (!entry) {
      await interaction.reply({ content: "❌ Unknown key.", ephemeral: true });
      return true;
    }

    if (sub === "revoke") entry.revoked = true;
    if (sub === "unrevoke") entry.revoked = false;
    if (sub === "resethwid") entry.hwid = null;
    save();

    await interaction.reply({
      content:
        sub === "revoke" ? "⛔ Key revoked." : sub === "unrevoke" ? "✅ Key re-enabled." : "♻️ HWID unlinked.",
      ephemeral: true,
    });
    return true;
  }

  /* ---- customer panel ---- */

  if (interaction.isButton() && interaction.customId.startsWith("key_")) {
    const id = interaction.customId;

    if (id === "key_redeem") {
      await interaction.showModal(
        new ModalBuilder()
          .setCustomId("key_redeem_modal")
          .setTitle("Redeem your key")
          .addComponents(
            new ActionRowBuilder().addComponents(
              new TextInputBuilder()
                .setCustomId("key")
                .setLabel("Your key")
                .setPlaceholder("ONYX-XXXXXXXX-XXXXXXXX-XXXXXXXX")
                .setStyle(TextInputStyle.Short)
                .setRequired(true)
            )
          )
      );
      return true;
    }

    const found = activeKeyOfUser(interaction.user.id);

    if (id === "key_info") {
      if (!found) {
        const any = keysOfUser(interaction.user.id)[0];
        await interaction.reply(
          any
            ? { embeds: [keyEmbed(...any)], ephemeral: true }
            : { content: "❌ You have no key. Use **Redeem Key**.", ephemeral: true }
        );
      } else {
        await interaction.reply({ embeds: [keyEmbed(...found)], ephemeral: true });
      }
      return true;
    }

    if (!found) {
      await noKey(interaction);
      return true;
    }

    const [key, entry] = found;

    if (id === "key_script") {
      if (!baseUrl()) {
        await interaction.reply({ content: "❌ The licensing server is not configured yet (PUBLIC_URL). Tell a staff member.", ephemeral: true });
        return true;
      }
      await interaction.reply({
        content: `📜 Your loader — paste it in your executor. It only works with your key and your device. **Do not share it.**\n\`\`\`lua\n${loadstringFor(key)}\n\`\`\``,
        ephemeral: true,
      });
      return true;
    }

    if (id === "key_reset") {
      const wait = entry.lastReset + RESET_COOLDOWN_MS - Date.now();

      if (!entry.hwid) {
        await interaction.reply({ content: "ℹ️ No device is linked to your key yet.", ephemeral: true });
      } else if (wait > 0) {
        await interaction.reply({
          content: `⏳ You can reset your HWID again <t:${Math.floor((Date.now() + wait) / 1000)}:R>. A staff member can reset it sooner.`,
          ephemeral: true,
        });
      } else {
        entry.hwid = null;
        entry.lastReset = Date.now();
        save();
        await interaction.reply({ content: "♻️ HWID reset. The next device that runs the script will be linked.", ephemeral: true });
      }
      return true;
    }
  }

  if (interaction.isModalSubmit() && interaction.customId === "key_redeem_modal") {
    const key = normalize(interaction.fields.getTextInputValue("key"));
    const entry = store[key];

    let error = null;
    if (!entry) error = "Invalid key.";
    else if (entry.revoked) error = "This key has been revoked.";
    else if (entry.userId && entry.userId !== interaction.user.id) error = "This key is already used by someone else.";
    else if (isExpired(entry)) error = "This key has expired.";

    if (error) {
      await interaction.reply({ content: `❌ ${error}`, ephemeral: true });
      return true;
    }

    entry.userId = interaction.user.id;
    activate(entry);
    save();

    if (CUSTOMER_ROLE_ID) {
      await interaction.member?.roles?.add(CUSTOMER_ROLE_ID).catch(() => {});
    }

    await interaction.reply({
      content: "✅ Key redeemed! Click **Get Script** to get your loader.",
      embeds: [keyEmbed(key, entry)],
      ephemeral: true,
    });
    return true;
  }

  return false;
}

module.exports = { commands, handleInteraction, startServer };
