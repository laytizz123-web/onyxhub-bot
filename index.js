require("dotenv").config();

const {
  Client,
  GatewayIntentBits,
  ChannelType,
  PermissionFlagsBits,
  EmbedBuilder,
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  Events,
  REST,
  Routes,
  SlashCommandBuilder,
} = require("discord.js");

/* =====================================================
   CLIENT
===================================================== */

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
});

/* =====================================================
   CONFIG
===================================================== */

const SHOP_URL =
  process.env.SHOP_URL || "https://onyxhub7.mysellauth.com/";

const OWNER_ROLE_ID = "1555941354096427040";
const STAFF_ROLE_ID = "1557110463907766432";

const AUTO_ROLE_ID = process.env.AUTO_ROLE_ID || "";
const LOG_CHANNEL_ID = process.env.LOG_CHANNEL_ID || "";

const COLORS = {
  main: 0x7c3aed,
  success: 0x22c55e,
  error: 0xef4444,
  warning: 0xf59e0b,
  info: 0x3b82f6,
};

const claimedTickets = new Map();

/* =====================================================
   HELPERS
===================================================== */

function isStaff(interaction) {
  return (
    interaction.memberPermissions?.has(PermissionFlagsBits.ManageChannels) ||
    interaction.member?.roles?.cache?.has(STAFF_ROLE_ID) ||
    interaction.member?.roles?.cache?.has(OWNER_ROLE_ID)
  );
}

function isOwner(interaction) {
  return (
    interaction.user.id === process.env.OWNER_ID ||
    interaction.member?.roles?.cache?.has(OWNER_ROLE_ID)
  );
}

async function sendLog(guild, embed) {
  if (!LOG_CHANNEL_ID) return;

  const channel = guild.channels.cache.get(LOG_CHANNEL_ID);

  if (!channel || !channel.isTextBased()) return;

  await channel.send({ embeds: [embed] }).catch(() => {});
}

/*
  Prefix commands can't be ephemeral, so the reply goes to the author's DMs
  and their command message is deleted. If DMs are closed, the reply is
  posted in the channel and deleted after a few seconds.
*/
async function privateReply(message, payload) {
  if (typeof payload === "string") payload = { content: payload };

  await message.delete().catch(() => {});

  const sent = await message.author.send(payload).catch(() => null);

  if (sent) return sent;

  const fallback = await message.channel.send({
    ...payload,
    content: `${message.author} ${payload.content || ""}`.trim(),
    allowedMentions: { users: [message.author.id] },
  });

  setTimeout(() => fallback.delete().catch(() => {}), 15000);

  return fallback;
}

const DEFAULT_TIMEOUT_MS = 10 * 60 * 1000;
const MAX_TIMEOUT_MS = 28 * 24 * 60 * 60 * 1000;

const DURATION_UNITS = {
  s: 1000,
  m: 60 * 1000,
  h: 60 * 60 * 1000,
  d: 24 * 60 * 60 * 1000,
  w: 7 * 24 * 60 * 60 * 1000,
};

/*
  Parses durations like "30m", "1h", "1d", "1h30m" or "45" (minutes).
  Returns milliseconds, or null if the text is not a duration.
*/
function parseDuration(text) {
  if (!text) return null;

  const value = text.toLowerCase();

  if (/^\d+$/.test(value)) return Number(value) * DURATION_UNITS.m;

  if (!/^(\d+[smhdw])+$/.test(value)) return null;

  let total = 0;

  for (const [, amount, unit] of value.matchAll(/(\d+)([smhdw])/g)) {
    total += Number(amount) * DURATION_UNITS[unit];
  }

  return total;
}

function formatDuration(ms) {
  const parts = [];
  let rest = Math.floor(ms / 1000);

  for (const [unit, size] of [["d", 86400], ["h", 3600], ["m", 60], ["s", 1]]) {
    const amount = Math.floor(rest / size);
    if (amount) parts.push(`${amount}${unit}`);
    rest %= size;
  }

  return parts.join(" ") || "0s";
}

/* =====================================================
   LOCK / UNLOCK / NUKE
===================================================== */

async function setChannelLock(channel, locked, moderator) {
  await channel.permissionOverwrites.edit(
    channel.guild.roles.everyone,
    {
      SendMessages: locked ? false : null,
      SendMessagesInThreads: locked ? false : null,
      CreatePublicThreads: locked ? false : null,
      CreatePrivateThreads: locked ? false : null,
    },
    { reason: `${locked ? "Locked" : "Unlocked"} by ${moderator.tag}` }
  );

  await channel.send({
    embeds: [
      new EmbedBuilder()
        .setColor(locked ? COLORS.error : COLORS.success)
        .setDescription(
          locked
            ? `🔒 This channel has been locked by ${moderator}.`
            : `🔓 This channel has been unlocked by ${moderator}.`
        ),
    ],
  });

  await sendLog(
    channel.guild,
    new EmbedBuilder()
      .setColor(locked ? COLORS.error : COLORS.success)
      .setTitle(locked ? "🔒 Channel Locked" : "🔓 Channel Unlocked")
      .addFields(
        { name: "Channel", value: `${channel}` },
        { name: "Moderator", value: `${moderator}` }
      )
      .setTimestamp()
  );
}

function nukeConfirmButtons() {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId("nuke_confirm")
      .setLabel("Confirm Nuke")
      .setEmoji("💣")
      .setStyle(ButtonStyle.Danger),
    new ButtonBuilder()
      .setCustomId("nuke_cancel")
      .setLabel("Cancel")
      .setStyle(ButtonStyle.Secondary)
  );
}

const NUKE_WARNING =
  "⚠️ This will delete this channel and recreate it with the same name, topic, category, position and permissions. **All messages will be lost.**";

/*
  Recreates the channel with the same settings and permission overwrites
  (channel.clone copies them), then deletes the old one.
*/
async function nukeChannel(channel, moderator) {
  const newChannel = await channel.clone({
    reason: `Nuked by ${moderator.tag}`,
  });

  await newChannel.setPosition(channel.position).catch(() => {});
  await channel.delete(`Nuked by ${moderator.tag}`);

  await newChannel.send({
    embeds: [
      new EmbedBuilder()
        .setColor(COLORS.main)
        .setDescription(`💣 This channel has been nuked by ${moderator}.`)
        .setTimestamp(),
    ],
  });

  await sendLog(
    channel.guild,
    new EmbedBuilder()
      .setColor(COLORS.warning)
      .setTitle("💣 Channel Nuked")
      .addFields(
        { name: "Channel", value: `${newChannel} (#${channel.name})` },
        { name: "Moderator", value: `${moderator}` }
      )
      .setTimestamp()
  );

  return newChannel;
}

function ticketPermissionOverwrites(guild, user) {
  return [
    {
      id: guild.roles.everyone.id,
      deny: [PermissionFlagsBits.ViewChannel],
    },
    {
      id: user.id,
      allow: [
        PermissionFlagsBits.ViewChannel,
        PermissionFlagsBits.SendMessages,
        PermissionFlagsBits.ReadMessageHistory,
        PermissionFlagsBits.AttachFiles,
        PermissionFlagsBits.EmbedLinks,
      ],
    },
    {
      id: client.user.id,
      allow: [
        PermissionFlagsBits.ViewChannel,
        PermissionFlagsBits.SendMessages,
        PermissionFlagsBits.ReadMessageHistory,
        PermissionFlagsBits.ManageChannels,
        PermissionFlagsBits.ManageMessages,
      ],
    },
    {
      id: OWNER_ROLE_ID,
      allow: [
        PermissionFlagsBits.ViewChannel,
        PermissionFlagsBits.SendMessages,
        PermissionFlagsBits.ReadMessageHistory,
        PermissionFlagsBits.AttachFiles,
        PermissionFlagsBits.EmbedLinks,
        PermissionFlagsBits.ManageChannels,
      ],
    },
    {
      id: STAFF_ROLE_ID,
      allow: [
        PermissionFlagsBits.ViewChannel,
        PermissionFlagsBits.SendMessages,
        PermissionFlagsBits.ReadMessageHistory,
        PermissionFlagsBits.AttachFiles,
        PermissionFlagsBits.EmbedLinks,
        PermissionFlagsBits.ManageChannels,
      ],
    },
  ];
}

async function getTicketCategory(guild) {
  let category = guild.channels.cache.find(
    (channel) =>
      channel.type === ChannelType.GuildCategory &&
      channel.name === "ORYX TICKETS"
  );

  if (!category) {
    category = await guild.channels.create({
      name: "ORYX TICKETS",
      type: ChannelType.GuildCategory,
    });
  }

  return category;
}

async function createTicket(interaction, type) {
  await interaction.deferReply({ ephemeral: true });

  const guild = interaction.guild;
  const user = interaction.user;

  const existing = guild.channels.cache.find(
    (channel) =>
      channel.type === ChannelType.GuildText &&
      channel.topic?.startsWith(`oryx-ticket:${user.id}:`)
  );

  if (existing) {
    return interaction.editReply({
      content: `❌ You already have an open ticket: ${existing}`,
    });
  }

  const category = await getTicketCategory(guild);

  const safeName =
    user.username
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, "")
      .slice(0, 18) || "user";

  const prefix =
    type === "purchase"
      ? "purchase"
      : type === "support"
        ? "support"
        : "partnership";

  const channelName = `${prefix}-${safeName}`.slice(0, 90);

  const ticketChannel = await guild.channels.create({
    name: channelName,
    type: ChannelType.GuildText,
    parent: category.id,
    topic: `oryx-ticket:${user.id}:${type}`,
    permissionOverwrites: ticketPermissionOverwrites(guild, user),
  });

  const ticketCreatedAt = new Date();

  let title;
  let description;

  if (type === "purchase") {
    title = "🛒 Purchase Ticket";
    description = [
      `Hello ${user}, welcome to your purchase ticket!`,
      "",
      "Please tell us what you would like to purchase and include any useful order information.",
      "",
      "🌐 You can also purchase directly from our website:",
      SHOP_URL,
      "",
      "A staff member will assist you as soon as possible.",
    ].join("\n");
  } else if (type === "support") {
    title = "🛠️ Support Ticket";
    description = [
      `Hello ${user}, welcome to your support ticket!`,
      "",
      "This ticket is for help and support.",
      "",
      "Please explain your problem clearly and provide screenshots, error messages, or other useful information when possible.",
      "",
      "A staff member will assist you as soon as possible.",
    ].join("\n");
  } else {
    title = "🤝 Partnership Ticket";
    description = [
      `Hello ${user}, welcome to your partnership ticket!`,
      "",
      "Please send the following information:",
      "• Server name",
      "• Server invite",
      "• Member count",
      "• Partnership offer/details",
      "",
      "Our team will review your request.",
    ].join("\n");
  }

  const buttons = new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId("ticket_claim")
      .setLabel("Claim Ticket")
      .setEmoji("🎫")
      .setStyle(ButtonStyle.Success),
    new ButtonBuilder()
      .setCustomId("ticket_close")
      .setLabel("Close Ticket")
      .setEmoji("🔒")
      .setStyle(ButtonStyle.Danger)
  );

  const embed = new EmbedBuilder()
    .setColor(COLORS.main)
    .setTitle(title)
    .setDescription(description)
    .setFooter({ text: "ORYX HUB • Ticket System" })
    .setTimestamp();

  await ticketChannel.send({
    content: `<@&${OWNER_ROLE_ID}> <@&${STAFF_ROLE_ID}> ${user}`,
    embeds: [embed],
    components: [buttons],
    allowedMentions: {
      roles: [OWNER_ROLE_ID, STAFF_ROLE_ID],
      users: [user.id],
    },
  });

  /* Original owner DM notification, kept and translated. */
  try {
    const ownerId = process.env.OWNER_ID;

    if (ownerId) {
      const owner = await client.users.fetch(ownerId);

      const dmEmbed = new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle("🎫 New ORYX HUB Ticket")
        .setThumbnail(user.displayAvatarURL())
        .setDescription("A new ticket has been opened.")
        .addFields(
          {
            name: "👤 User",
            value:
              `**Username:** ${user.username}\n` +
              `**Display Name:** ${user.displayName}\n` +
              `**Mention:** ${user}\n` +
              `**ID:** \`${user.id}\``,
          },
          {
            name: "🎫 Ticket Information",
            value:
              `**Type:** ${type}\n` +
              `**Channel:** ${ticketChannel}\n` +
              `**Channel name:** \`${ticketChannel.name}\`\n` +
              `**Channel ID:** \`${ticketChannel.id}\``,
          },
          {
            name: "🕐 Creation Information",
            value:
              `**Created:** <t:${Math.floor(
                ticketCreatedAt.getTime() / 1000
              )}:F>\n` +
              `**Created:** <t:${Math.floor(
                ticketCreatedAt.getTime() / 1000
              )}:R>`,
          },
          {
            name: "🔗 Direct Ticket Link",
            value: `[Open Ticket](https://discord.com/channels/${guild.id}/${ticketChannel.id})`,
          }
        )
        .setFooter({ text: "ORYX HUB • Ticket Notification" })
        .setTimestamp();

      await owner.send({ embeds: [dmEmbed] }).catch(() => {});
    }
  } catch (error) {
    console.error("Could not send ticket DM:", error);
  }

  await sendLog(
    guild,
    new EmbedBuilder()
      .setColor(COLORS.info)
      .setTitle("🎫 Ticket Created")
      .addFields(
        { name: "User", value: `${user} (\`${user.id}\`)` },
        { name: "Type", value: type, inline: true },
        { name: "Channel", value: `${ticketChannel}`, inline: true }
      )
      .setTimestamp()
  );

  return interaction.editReply({
    content: `✅ Your ticket has been created: ${ticketChannel}`,
  });
}

/* =====================================================
   BOT READY
===================================================== */

client.once(Events.ClientReady, (bot) => {
  console.log(`✅ ${bot.user.tag} is online!`);
  console.log(`📊 Serving ${bot.guilds.cache.size} server(s).`);
});

/* =====================================================
   AUTO ROLE
===================================================== */

client.on(Events.GuildMemberAdd, async (member) => {
  if (!AUTO_ROLE_ID) return;

  const role = member.guild.roles.cache.get(AUTO_ROLE_ID);

  if (!role) return;

  await member.roles.add(role).catch((error) => {
    console.error("Could not assign auto-role:", error);
  });

  await sendLog(
    member.guild,
    new EmbedBuilder()
      .setColor(COLORS.success)
      .setTitle("👋 Member Joined")
      .setDescription(`${member} joined the server and was given the automatic role.`)
      .setTimestamp()
  );
});

/* =====================================================
   INTERACTIONS
===================================================== */

client.on(Events.MessageCreate, async (message) => {
  try {
    if (message.author.bot || !message.guild || !message.content.startsWith("!")) return;

    const args = message.content.slice(1).trim().split(/\s+/);
    const command = (args.shift() || "").toLowerCase();
    if (!command) return;

    const staffOnly = ["announce", "clear", "warn", "timeout", "kick", "ban", "tickets", "lock", "unlock", "nuke"];
    if (staffOnly.includes(command) && !isStaff(message)) {
      return privateReply(message, "❌ Only staff can use this command.");
    }

    if (command === "help") {
      return privateReply(message, { embeds: [new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle("ORYX HUB | Commands")
        .setDescription([
          "**Tickets:** `!tickets`",
          "**Information:** `!serverinfo`, `!userinfo @user`",
          "**Moderation:** `!warn @user reason`, `!timeout @user [30m/1h/1d] [reason]`, `!kick @user reason`, `!ban @user reason`, `!clear amount`",
          "**Channels:** `!lock`, `!unlock`, `!nuke`",
          "**Staff:** `!announce Title | message`",
          "",
          "Every command is also available with `/`.",
        ].join("\n"))
        .setTimestamp()] });
    }

    if (command === "tickets") {
      const embed = new EmbedBuilder().setColor(COLORS.main).setTitle("ORYX HUB | Ticket Center")
        .setDescription(["Welcome to **ORYX HUB**!", "", "Choose a category below to open a private ticket.", "", "🛒 **Purchase**", "Open a ticket for purchases or order questions.", "", "🛠️ **Support**", "Open a ticket if you need help or have a question.", "", "🤝 **Partnership**", "Open a ticket for partnership requests.", "", "🌐 **Website**", SHOP_URL, "", "Our support is available 24/7 through the ticket system."].join("\n"))
        .setFooter({ text: "ORYX HUB • Ticket System" }).setTimestamp();
      const buttons = new ActionRowBuilder().addComponents(
        new ButtonBuilder().setCustomId("ticket_purchase").setLabel("Purchase").setEmoji("🛒").setStyle(ButtonStyle.Primary),
        new ButtonBuilder().setCustomId("ticket_support").setLabel("Support").setEmoji("🛠️").setStyle(ButtonStyle.Secondary),
        new ButtonBuilder().setCustomId("ticket_partnership").setLabel("Partnership").setEmoji("🤝").setStyle(ButtonStyle.Success)
      );
      return message.channel.send({ embeds: [embed], components: [buttons] });
    }

    if (command === "serverinfo") {
      const g = message.guild;
      const embed = new EmbedBuilder().setColor(COLORS.info).setTitle("Server Information")
        .addFields({name:"Name",value:g.name,inline:true},{name:"Members",value:String(g.memberCount),inline:true},{name:"Channels",value:String(g.channels.cache.size),inline:true},{name:"Server ID",value:g.id})
        .setTimestamp();
      return privateReply(message, {embeds:[embed]});
    }

    if (command === "userinfo") {
      const target = message.mentions.members.first() || message.member;
      const embed = new EmbedBuilder().setColor(COLORS.info).setTitle("User Information").setThumbnail(target.user.displayAvatarURL())
        .addFields({name:"User",value:`${target.user} (\`${target.id}\`)`},{name:"Joined Server",value:target.joinedAt ? `<t:${Math.floor(target.joinedAt.getTime()/1000)}:F>` : "Unknown",inline:true},{name:"Highest Role",value:target.roles.highest?.toString() || "@everyone",inline:true}).setTimestamp();
      return privateReply(message, {embeds:[embed]});
    }

    if (command === "announce") {
      const raw = args.join(" ");
      const parts = raw.split("|");
      if (parts.length < 2) return message.reply("❌ Usage: `!announce Title | message`");
      const title = parts.shift().trim();
      const text = parts.join("|").trim();
      const embed = new EmbedBuilder().setColor(COLORS.main).setTitle(title).setDescription(text).setFooter({text:`ORYX HUB • Announcement by ${message.author.tag}`}).setTimestamp();
      await message.channel.send({embeds:[embed]});
      return message.reply({content:"✅ Announcement sent.",allowedMentions:{parse:[]}});
    }

    if (command === "clear") {
      const amount = Number(args[0]);
      if (!Number.isInteger(amount) || amount < 1 || amount > 100) return message.reply("❌ Usage: `!clear 1-100`");
      const deleted = await message.channel.bulkDelete(amount, true);
      return message.channel.send(`🧹 Deleted ${deleted.size} message(s).`).then(m=>setTimeout(()=>m.delete().catch(()=>{}),3000));
    }

    if (command === "lock" || command === "unlock") {
      await setChannelLock(message.channel, command === "lock", message.author);
      return message.delete().catch(() => {});
    }

    if (command === "nuke") {
      await message.delete().catch(() => {});
      return message.channel.send({
        content: `${message.author} ${NUKE_WARNING}`,
        components: [nukeConfirmButtons()],
        allowedMentions: { users: [message.author.id] },
      });
    }

    const target = message.mentions.members.first();
    if (["warn","timeout","kick","ban"].includes(command) && !target) return message.reply("❌ Usage: !" + command + " @user ...");

    if (command === "warn") {
      const reason = args.slice(1).join(" ") || "No reason provided.";
      await target.send(`⚠️ You have been warned in **${message.guild.name}**. Reason: ${reason}`).catch(()=>{});
      return message.reply(`⚠️ ${target} has been warned. Reason: ${reason}`);
    }

    if (command === "timeout") {
      const parsed = parseDuration(args[1]);
      const duration = parsed ?? DEFAULT_TIMEOUT_MS;
      if (duration < 1000 || duration > MAX_TIMEOUT_MS) return message.reply("❌ Duration must be between 1s and 28d. Usage: `!timeout @user [30m/1h/1d] [reason]`");
      const reason = args.slice(parsed === null ? 1 : 2).join(" ") || "No reason provided.";
      await target.timeout(duration, reason);
      return message.reply(`⏱️ ${target} has been timed out for ${formatDuration(duration)}.`);
    }

    if (command === "kick") {
      const reason = args.slice(1).join(" ") || "No reason provided.";
      await target.kick(reason);
      return message.reply(`👢 ${target.user.tag} has been kicked.`);
    }

    if (command === "ban") {
      const reason = args.slice(1).join(" ") || "No reason provided.";
      await target.ban({reason});
      return message.reply(`🔨 ${target.user.tag} has been banned.`);
    }
  } catch (error) {
    console.error("Prefix command error:", error);
    await message.reply("❌ An error occurred. Check the bot console.").catch(()=>{});
  }
});

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    /* =================================================
       SLASH COMMANDS
    ================================================= */

    if (interaction.isChatInputCommand()) {
      const command = interaction.commandName;

      /* -----------------------------------------------
         /tickets
      ----------------------------------------------- */

      if (command === "tickets") {
        if (!interaction.memberPermissions.has(PermissionFlagsBits.Administrator)) {
          return interaction.reply({
            content: "❌ Only administrators can use this command.",
            ephemeral: true,
          });
        }

        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle("ORYX HUB | Ticket Center")
          .setDescription(
            [
              "Welcome to **ORYX HUB**!",
              "",
              "Choose a category below to open a private ticket.",
              "",
              "🛒 **Purchase**",
              "Open a ticket for purchases or order questions.",
              "",
              "🛠️ **Support**",
              "Open a ticket if you need help or have a question.",
              "",
              "🤝 **Partnership**",
              "Open a ticket for partnership requests.",
              "",
              "🌐 **Website**",
              SHOP_URL,
              "",
              "Our support is available 24/7 through the ticket system.",
            ].join("\n")
          )
          .setFooter({ text: "ORYX HUB • Ticket System" })
          .setTimestamp();

        const buttons = new ActionRowBuilder().addComponents(
          new ButtonBuilder()
            .setCustomId("ticket_purchase")
            .setLabel("Purchase")
            .setEmoji("🛒")
            .setStyle(ButtonStyle.Primary),
          new ButtonBuilder()
            .setCustomId("ticket_support")
            .setLabel("Support")
            .setEmoji("🛠️")
            .setStyle(ButtonStyle.Secondary),
          new ButtonBuilder()
            .setCustomId("ticket_partnership")
            .setLabel("Partnership")
            .setEmoji("🤝")
            .setStyle(ButtonStyle.Success)
        );

        await interaction.channel.send({
          embeds: [embed],
          components: [buttons],
        });

        return interaction.reply({
          content: "✅ ORYX HUB ticket panel created!",
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /help
      ----------------------------------------------- */

      if (command === "help") {
        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle("🛠️ ORYX HUB • Help")
          .setDescription("Here are the available bot commands.")
          .addFields(
            {
              name: "🎫 Tickets",
              value:
                "`/tickets` — Create the ticket panel.\n" +
                "Purchase, Support and Partnership tickets are available.",
            },
            {
              name: "🛡️ Moderation",
              value:
                "`/warn` — Warn a member.\n" +
                "`/timeout` — Timeout a member.\n" +
                "`/kick` — Kick a member.\n" +
                "`/ban` — Ban a member.\n" +
                "`/clear` — Delete messages.",
            },
            {
              name: "🔒 Channels",
              value:
                "`/lock` — Lock the current channel.\n" +
                "`/unlock` — Unlock the current channel.\n" +
                "`/nuke` — Recreate the channel with the same permissions.",
            },
            {
              name: "ℹ️ Information",
              value:
                "`/serverinfo` — Server information.\n" +
                "`/userinfo` — User information.",
            },
            {
              name: "📢 Administration",
              value:
                "`/announce` — Send an announcement.",
            }
          )
          .setFooter({ text: "ORYX HUB • Multifunction Bot" })
          .setTimestamp();

        return interaction.reply({ embeds: [embed], ephemeral: true });
      }

      /* -----------------------------------------------
         /serverinfo
      ----------------------------------------------- */

      if (command === "serverinfo") {
        const guild = interaction.guild;

        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle(`📊 ${guild.name} • Server Information`)
          .setThumbnail(guild.iconURL({ size: 256 }))
          .addFields(
            {
              name: "👥 Members",
              value: `${guild.memberCount}`,
              inline: true,
            },
            {
              name: "💬 Channels",
              value: `${guild.channels.cache.size}`,
              inline: true,
            },
            {
              name: "🛡️ Roles",
              value: `${guild.roles.cache.size}`,
              inline: true,
            },
            {
              name: "👑 Owner",
              value: `<@${guild.ownerId}>`,
              inline: true,
            },
            {
              name: "🆔 Server ID",
              value: `\`${guild.id}\``,
              inline: true,
            },
            {
              name: "📅 Created",
              value: `<t:${Math.floor(guild.createdTimestamp / 1000)}:D>`,
              inline: true,
            }
          )
          .setTimestamp();

        return interaction.reply({ embeds: [embed], ephemeral: true });
      }

      /* -----------------------------------------------
         /userinfo
      ----------------------------------------------- */

      if (command === "userinfo") {
        const member =
          interaction.options.getMember("user") || interaction.member;
        const user = member.user;

        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle(`👤 ${user.username} • User Information`)
          .setThumbnail(user.displayAvatarURL({ size: 256 }))
          .addFields(
            {
              name: "Username",
              value: `${user}`,
              inline: true,
            },
            {
              name: "User ID",
              value: `\`${user.id}\``,
              inline: true,
            },
            {
              name: "Account Created",
              value: `<t:${Math.floor(user.createdTimestamp / 1000)}:R>`,
              inline: true,
            },
            {
              name: "Joined Server",
              value: member.joinedTimestamp
                ? `<t:${Math.floor(member.joinedTimestamp / 1000)}:R>`
                : "Unknown",
              inline: true,
            },
            {
              name: "Highest Role",
              value: member.roles.highest?.toString() || "@everyone",
              inline: true,
            }
          )
          .setTimestamp();

        return interaction.reply({ embeds: [embed], ephemeral: true });
      }

      /* -----------------------------------------------
         /clear
      ----------------------------------------------- */

      if (command === "clear") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const amount = interaction.options.getInteger("amount", true);

        if (amount < 1 || amount > 100) {
          return interaction.reply({
            content: "❌ Amount must be between 1 and 100.",
            ephemeral: true,
          });
        }

        const deleted = await interaction.channel.bulkDelete(
          amount,
          true
        );

        return interaction.reply({
          content: `🧹 Deleted ${deleted.size} message(s).`,
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /warn
      ----------------------------------------------- */

      if (command === "warn") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const member = interaction.options.getMember("user");
        const reason =
          interaction.options.getString("reason") || "No reason provided.";

        if (!member) {
          return interaction.reply({
            content: "❌ Member not found.",
            ephemeral: true,
          });
        }

        await member
          .send(
            `⚠️ You have been warned in **${interaction.guild.name}**.\nReason: ${reason}`
          )
          .catch(() => {});

        await sendLog(
          interaction.guild,
          new EmbedBuilder()
            .setColor(COLORS.warning)
            .setTitle("⚠️ Member Warned")
            .addFields(
              { name: "Member", value: `${member}` },
              { name: "Moderator", value: `${interaction.user}` },
              { name: "Reason", value: reason }
            )
            .setTimestamp()
        );

        return interaction.reply({
          content: `⚠️ ${member} has been warned.`,
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /timeout
      ----------------------------------------------- */

      if (command === "timeout") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const member = interaction.options.getMember("user");
        const durationText = interaction.options.getString("duration");
        const parsed = parseDuration(durationText);
        const duration = parsed ?? DEFAULT_TIMEOUT_MS;
        const reason =
          interaction.options.getString("reason") || "No reason provided.";

        if (!member) {
          return interaction.reply({
            content: "❌ Member not found.",
            ephemeral: true,
          });
        }

        if (
          (durationText && parsed === null) ||
          duration < 1000 ||
          duration > MAX_TIMEOUT_MS
        ) {
          return interaction.reply({
            content:
              "❌ Invalid duration. Use something like `30m`, `1h`, `1d` (max 28d).",
            ephemeral: true,
          });
        }

        await member.timeout(duration, reason);

        return interaction.reply({
          content: `⏱️ ${member} has been timed out for ${formatDuration(duration)}.`,
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /kick
      ----------------------------------------------- */

      if (command === "kick") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const member = interaction.options.getMember("user");
        const reason =
          interaction.options.getString("reason") || "No reason provided.";

        if (!member) {
          return interaction.reply({
            content: "❌ Member not found.",
            ephemeral: true,
          });
        }

        await member.kick(reason);

        return interaction.reply({
          content: `👢 ${member.user.tag} has been kicked.`,
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /ban
      ----------------------------------------------- */

      if (command === "ban") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const member = interaction.options.getMember("user");
        const reason =
          interaction.options.getString("reason") || "No reason provided.";

        if (!member) {
          return interaction.reply({
            content: "❌ Member not found.",
            ephemeral: true,
          });
        }

        await member.ban({ reason });

        return interaction.reply({
          content: `🔨 ${member.user.tag} has been banned.`,
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /lock /unlock /nuke
      ----------------------------------------------- */

      if (command === "lock" || command === "unlock" || command === "nuke") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        if (command === "nuke") {
          return interaction.reply({
            content: NUKE_WARNING,
            components: [nukeConfirmButtons()],
            ephemeral: true,
          });
        }

        await setChannelLock(
          interaction.channel,
          command === "lock",
          interaction.user
        );

        return interaction.reply({
          content: command === "lock" ? "🔒 Channel locked." : "🔓 Channel unlocked.",
          ephemeral: true,
        });
      }

      return;
    }

    /* =================================================
       BUTTONS
    ================================================= */

    if (!interaction.isButton()) return;

    /* -----------------------------------------------
       NUKE CONFIRMATION
    ----------------------------------------------- */

    if (
      interaction.customId === "nuke_confirm" ||
      interaction.customId === "nuke_cancel"
    ) {
      if (!isStaff(interaction)) {
        return interaction.reply({
          content: "❌ Only staff can use this.",
          ephemeral: true,
        });
      }

      if (interaction.customId === "nuke_cancel") {
        return interaction.update({
          content: "❌ Nuke cancelled.",
          components: [],
        });
      }

      await interaction.update({
        content: "💣 Nuking channel...",
        components: [],
      });

      await nukeChannel(interaction.channel, interaction.user);
      return;
    }

    /* -----------------------------------------------
       CREATE TICKETS
    ----------------------------------------------- */

    if (interaction.customId === "ticket_purchase") {
      return createTicket(interaction, "purchase");
    }

    if (interaction.customId === "ticket_support") {
      return createTicket(interaction, "support");
    }

    if (interaction.customId === "ticket_partnership") {
      return createTicket(interaction, "partnership");
    }

    /* -----------------------------------------------
       CLAIM TICKET
    ----------------------------------------------- */

    if (interaction.customId === "ticket_claim") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("oryx-ticket:")
      ) {
        return interaction.reply({
          content: "❌ This is not an ORYX HUB ticket.",
          ephemeral: true,
        });
      }

      if (!isStaff(interaction)) {
        return interaction.reply({
          content: "❌ Only staff members can claim tickets.",
          ephemeral: true,
        });
      }

      const currentClaim = claimedTickets.get(channel.id);

      if (currentClaim) {
        const claimedUser = await client.users
          .fetch(currentClaim)
          .catch(() => null);

        return interaction.reply({
          content: claimedUser
            ? `❌ This ticket is already claimed by ${claimedUser}.`
            : "❌ This ticket is already claimed.",
          ephemeral: true,
        });
      }

      claimedTickets.set(channel.id, interaction.user.id);

      const buttons = new ActionRowBuilder().addComponents(
        new ButtonBuilder()
          .setCustomId("ticket_unclaim")
          .setLabel("Unclaim Ticket")
          .setEmoji("🔓")
          .setStyle(ButtonStyle.Secondary),
        new ButtonBuilder()
          .setCustomId("ticket_close")
          .setLabel("Close Ticket")
          .setEmoji("🔒")
          .setStyle(ButtonStyle.Danger)
      );

      await interaction.update({ components: [buttons] });

      await channel.send({
        embeds: [
          new EmbedBuilder()
            .setColor(COLORS.success)
            .setDescription(
              `🎫 This ticket has been claimed by ${interaction.user}.`
            ),
        ],
      });

      return;
    }

    /* -----------------------------------------------
       UNCLAIM TICKET
    ----------------------------------------------- */

    if (interaction.customId === "ticket_unclaim") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("oryx-ticket:")
      ) {
        return interaction.reply({
          content: "❌ This is not an ORYX HUB ticket.",
          ephemeral: true,
        });
      }

      const claimedBy = claimedTickets.get(channel.id);

      if (!claimedBy) {
        return interaction.reply({
          content: "❌ This ticket is not currently claimed.",
          ephemeral: true,
        });
      }

      if (
        claimedBy !== interaction.user.id &&
        !isOwner(interaction)
      ) {
        return interaction.reply({
          content:
            "❌ Only the staff member who claimed this ticket or the Owner can unclaim it.",
          ephemeral: true,
        });
      }

      claimedTickets.delete(channel.id);

      const buttons = new ActionRowBuilder().addComponents(
        new ButtonBuilder()
          .setCustomId("ticket_claim")
          .setLabel("Claim Ticket")
          .setEmoji("🎫")
          .setStyle(ButtonStyle.Success),
        new ButtonBuilder()
          .setCustomId("ticket_close")
          .setLabel("Close Ticket")
          .setEmoji("🔒")
          .setStyle(ButtonStyle.Danger)
      );

      await interaction.update({ components: [buttons] });

      await channel.send({
        embeds: [
          new EmbedBuilder()
            .setColor(COLORS.main)
            .setDescription(
              `🔓 ${interaction.user} has unclaimed this ticket.`
            ),
        ],
      });

      return;
    }

    /* -----------------------------------------------
       CLOSE TICKET
    ----------------------------------------------- */

    if (interaction.customId === "ticket_close") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("oryx-ticket:")
      ) {
        return interaction.reply({
          content: "❌ This is not an ORYX HUB ticket.",
          ephemeral: true,
        });
      }

      const ticketOwnerId = channel.topic.split(":")[1];

      const isTicketOwner =
        interaction.user.id === ticketOwnerId;

      if (!isTicketOwner && !isStaff(interaction)) {
        return interaction.reply({
          content:
            "❌ Only the ticket owner or staff can close this ticket.",
          ephemeral: true,
        });
      }

      claimedTickets.delete(channel.id);

      await interaction.reply({
        content:
          "🔒 Ticket closed. This channel will be deleted in 5 seconds.",
      });

      await sendLog(
        interaction.guild,
        new EmbedBuilder()
          .setColor(COLORS.error)
          .setTitle("🔒 Ticket Closed")
          .addFields(
            { name: "Channel", value: `#${channel.name}` },
            { name: "Closed By", value: `${interaction.user}` }
          )
          .setTimestamp()
      );

      setTimeout(async () => {
        await channel
          .delete("ORYX HUB ticket closed")
          .catch((error) =>
            console.error("Could not delete ticket:", error)
          );
      }, 5000);

      return;
    }
  } catch (error) {
    console.error("❌ Interaction error:", error);

    if (interaction.deferred && !interaction.replied) {
      await interaction
        .editReply({
          content: "❌ An error occurred. Check the bot console.",
        })
        .catch(() => {});
    } else if (!interaction.replied) {
      await interaction
        .reply({
          content: "❌ An error occurred. Check the bot console.",
          ephemeral: true,
        })
        .catch(() => {});
    }
  }
});

/* =====================================================
   COMMAND REGISTRATION
===================================================== */

async function registerCommands() {
  const commands = [
    new SlashCommandBuilder()
      .setName("tickets")
      .setDescription("Post the ORYX HUB ticket panel."),

    new SlashCommandBuilder()
      .setName("help")
      .setDescription("Show all ORYX HUB bot commands."),

    new SlashCommandBuilder()
      .setName("serverinfo")
      .setDescription("Show information about the server."),

    new SlashCommandBuilder()
      .setName("userinfo")
      .setDescription("Show information about a user.")
      .addUserOption((option) =>
        option
          .setName("user")
          .setDescription("The user to inspect.")
          .setRequired(false)
      ),

    new SlashCommandBuilder()
      .setName("announce")
      .setDescription("Send a formatted announcement.")
      .addStringOption((option) =>
        option
          .setName("title")
          .setDescription("Announcement title.")
          .setRequired(true)
      )
      .addStringOption((option) =>
        option
          .setName("message")
          .setDescription("Announcement message.")
          .setRequired(true)
      ),

    new SlashCommandBuilder()
      .setName("clear")
      .setDescription("Delete messages from the current channel.")
      .addIntegerOption((option) =>
        option
          .setName("amount")
          .setDescription("Number of messages to delete.")
          .setMinValue(1)
          .setMaxValue(100)
          .setRequired(true)
      ),

    new SlashCommandBuilder()
      .setName("warn")
      .setDescription("Warn a member.")
      .addUserOption((option) =>
        option
          .setName("user")
          .setDescription("Member to warn.")
          .setRequired(true)
      )
      .addStringOption((option) =>
        option
          .setName("reason")
          .setDescription("Reason for the warning.")
          .setRequired(false)
      ),

    new SlashCommandBuilder()
      .setName("timeout")
      .setDescription("Timeout a member.")
      .addUserOption((option) =>
        option
          .setName("user")
          .setDescription("Member to timeout.")
          .setRequired(true)
      )
      .addStringOption((option) =>
        option
          .setName("duration")
          .setDescription("Duration, e.g. 30m, 1h, 1d (default: 10m, max: 28d).")
          .setRequired(false)
      )
      .addStringOption((option) =>
        option
          .setName("reason")
          .setDescription("Reason for the timeout.")
          .setRequired(false)
      ),

    new SlashCommandBuilder()
      .setName("kick")
      .setDescription("Kick a member.")
      .addUserOption((option) =>
        option
          .setName("user")
          .setDescription("Member to kick.")
          .setRequired(true)
      )
      .addStringOption((option) =>
        option
          .setName("reason")
          .setDescription("Reason for the kick.")
          .setRequired(false)
      ),

    new SlashCommandBuilder()
      .setName("ban")
      .setDescription("Ban a member.")
      .addUserOption((option) =>
        option
          .setName("user")
          .setDescription("Member to ban.")
          .setRequired(true)
      )
      .addStringOption((option) =>
        option
          .setName("reason")
          .setDescription("Reason for the ban.")
          .setRequired(false)
      ),

    new SlashCommandBuilder()
      .setName("lock")
      .setDescription("Lock the current channel."),

    new SlashCommandBuilder()
      .setName("unlock")
      .setDescription("Unlock the current channel."),

    new SlashCommandBuilder()
      .setName("nuke")
      .setDescription("Delete and recreate the current channel with the same permissions."),

  ];

  const rest = new REST({ version: "10" }).setToken(
    process.env.DISCORD_TOKEN
  );

  await rest.put(
    Routes.applicationGuildCommands(
      process.env.CLIENT_ID,
      process.env.GUILD_ID
    ),
    {
      body: commands.map((command) => command.toJSON()),
    }
  );

  console.log("✅ Slash commands registered.");
}

/* =====================================================
   ENVIRONMENT
===================================================== */

if (
  !process.env.DISCORD_TOKEN ||
  !process.env.CLIENT_ID ||
  !process.env.GUILD_ID ||
  !process.env.OWNER_ID
) {
  console.error(
    "❌ Missing DISCORD_TOKEN, CLIENT_ID, GUILD_ID or OWNER_ID in .env"
  );
  process.exit(1);
}

/* =====================================================
   START
===================================================== */

async function startBot() {
  try {
    await registerCommands();
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    console.error("❌ Failed to start bot:", error);
  }
}

startBot();
