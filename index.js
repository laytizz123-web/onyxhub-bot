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
              name: "ℹ️ Information",
              value:
                "`/serverinfo` — Server information.\n" +
                "`/userinfo` — User information.",
            },
            {
              name: "📢 Administration",
              value:
                "`/announce` — Send an announcement.\n" +
                "`/say` — Send a message as the bot.",
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

        return interaction.reply({ embeds: [embed] });
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

        return interaction.reply({ embeds: [embed] });
      }

      /* -----------------------------------------------
         /announce
      ----------------------------------------------- */

      if (command === "announce") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const title = interaction.options.getString("title", true);
        const message = interaction.options.getString("message", true);

        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle(`📢 ${title}`)
          .setDescription(message)
          .setFooter({ text: `Posted by ${interaction.user.tag}` })
          .setTimestamp();

        await interaction.channel.send({ embeds: [embed] });

        return interaction.reply({
          content: "✅ Announcement sent.",
          ephemeral: true,
        });
      }

      /* -----------------------------------------------
         /say
      ----------------------------------------------- */

      if (command === "say") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Only staff can use this command.",
            ephemeral: true,
          });
        }

        const message = interaction.options.getString("message", true);

        await interaction.channel.send({
          content: message,
          allowedMentions: { parse: [] },
        });

        return interaction.reply({
          content: "✅ Message sent.",
          ephemeral: true,
        });
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
        const minutes = interaction.options.getInteger("minutes", true);
        const reason =
          interaction.options.getString("reason") || "No reason provided.";

        if (!member) {
          return interaction.reply({
            content: "❌ Member not found.",
            ephemeral: true,
          });
        }

        await member.timeout(minutes * 60 * 1000, reason);

        return interaction.reply({
          content: `⏱️ ${member} has been timed out for ${minutes} minute(s).`,
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

      return;
    }

    /* =================================================
       BUTTONS
    ================================================= */

    if (!interaction.isButton()) return;

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
      .setName("say")
      .setDescription("Send a message as the bot.")
      .addStringOption((option) =>
        option
          .setName("message")
          .setDescription("Message to send.")
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
      .addIntegerOption((option) =>
        option
          .setName("minutes")
          .setDescription("Timeout duration in minutes.")
          .setMinValue(1)
          .setMaxValue(40320)
          .setRequired(true)
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
