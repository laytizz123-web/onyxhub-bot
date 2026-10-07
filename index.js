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

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

const SHOP_URL = "https://onyxhub7.mysellauth.com/";

const COLORS = {
  main: 0x7c3aed,
  success: 0x22c55e,
  error: 0xef4444,
};

const claimedTickets = new Map();

/* =====================================================
   BOT READY
===================================================== */

client.once(Events.ClientReady, (bot) => {
  console.log(`✅ ${bot.user.tag} est connecté !`);
});

/* =====================================================
   INTERACTIONS
===================================================== */

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    /* =================================================
       /tickets
    ================================================= */

    if (interaction.isChatInputCommand()) {
      if (interaction.commandName !== "tickets") return;

      if (
        !interaction.memberPermissions.has(
          PermissionFlagsBits.Administrator
        )
      ) {
        return interaction.reply({
          content:
            "❌ Seuls les administrateurs peuvent utiliser cette commande.",
          ephemeral: true,
        });
      }

      const embed = new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle("ONYX HUB | Support Center")
        .setDescription(
          [
            "Welcome to **Onyx Hub**!",
            "",
            "Choose a category below to open a private ticket.",
            "",
            "🛒 **Purchase**",
            "Open a ticket if you want to purchase or ask about an order.",
            "",
            "🛠️ **Support**",
            "Open a ticket if you need help or have a question.",
            "",
            "🌐 **Want to buy directly?**",
            "You can also purchase directly from our website:",
            SHOP_URL,
            "",
            "Our team will assist you as soon as possible.",
          ].join("\n")
        )
        .setFooter({
          text: "Onyx Hub • Ticket System",
        })
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
          .setStyle(ButtonStyle.Secondary)
      );

      await interaction.channel.send({
        embeds: [embed],
        components: [buttons],
      });

      return interaction.reply({
        content: "✅ Onyx Hub ticket panel created!",
        ephemeral: true,
      });
    }

    /* =================================================
       BUTTONS
    ================================================= */

    if (!interaction.isButton()) return;

    /* =================================================
       CREATE TICKET
    ================================================= */

    if (
      interaction.customId === "ticket_purchase" ||
      interaction.customId === "ticket_support"
    ) {
      await interaction.deferReply({
        ephemeral: true,
      });

      const guild = interaction.guild;
      const user = interaction.user;

      const isPurchase =
        interaction.customId === "ticket_purchase";

      /* -------------------------------------------------
         CHECK EXISTING TICKET
      ------------------------------------------------- */

      const existing = guild.channels.cache.find(
        (channel) =>
          channel.type === ChannelType.GuildText &&
          channel.topic?.startsWith(`onyx-ticket:${user.id}`)
      );

      if (existing) {
        return interaction.editReply({
          content: `❌ You already have an open ticket: ${existing}`,
        });
      }

      /* -------------------------------------------------
         FIND / CREATE CATEGORY
      ------------------------------------------------- */

      let category = guild.channels.cache.find(
        (channel) =>
          channel.type === ChannelType.GuildCategory &&
          channel.name === "ONYX TICKETS"
      );

      if (!category) {
        category = await guild.channels.create({
          name: "ONYX TICKETS",
          type: ChannelType.GuildCategory,
        });
      }

      /* -------------------------------------------------
         USERNAME
      ------------------------------------------------- */

      const safeName =
        user.username
          .toLowerCase()
          .replace(/[^a-z0-9-]/g, "")
          .slice(0, 18) || "user";

      const channelName =
        `${isPurchase ? "purchase" : "support"}-${safeName}`.slice(
          0,
          90
        );

      /* -------------------------------------------------
         PERMISSIONS
      ------------------------------------------------- */

      const permissionOverwrites = [
        {
          id: guild.roles.everyone.id,

          deny: [
            PermissionFlagsBits.ViewChannel,
          ],
        },

        // Ticket owner
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

        // Bot
        {
          id: client.user.id,

          allow: [
            PermissionFlagsBits.ViewChannel,
            PermissionFlagsBits.SendMessages,
            PermissionFlagsBits.ReadMessageHistory,
            PermissionFlagsBits.ManageChannels,
          ],
        },
      ];

      /* -------------------------------------------------
         STAFF ROLE
      ------------------------------------------------- */

      if (process.env.STAFF_ROLE_ID) {
        permissionOverwrites.push({
          id: process.env.STAFF_ROLE_ID,

          allow: [
            PermissionFlagsBits.ViewChannel,
            PermissionFlagsBits.SendMessages,
            PermissionFlagsBits.ReadMessageHistory,
            PermissionFlagsBits.AttachFiles,
            PermissionFlagsBits.EmbedLinks,
            PermissionFlagsBits.ManageChannels,
          ],
        });
      }

      /* -------------------------------------------------
         CREATE CHANNEL
      ------------------------------------------------- */

      const ticketCreatedAt = new Date();

      const ticketChannel = await guild.channels.create({
        name: channelName,
        type: ChannelType.GuildText,
        parent: category.id,

        topic: `onyx-ticket:${user.id}`,

        permissionOverwrites,
      });

      /* =================================================
         SEND PRIVATE TICKET INFORMATION TO OWNER
      ================================================= */

      try {
        const ownerId = process.env.OWNER_ID;

        if (!ownerId) {
          console.log(
            "⚠️ OWNER_ID is not configured. Ticket DM skipped."
          );
        } else {
          const owner = await client.users.fetch(ownerId);

          const member =
            await guild.members
              .fetch(user.id)
              .catch(() => null);

          /* -------------------------------------------------
             USER ROLES
          ------------------------------------------------- */

          let userRoles = "No roles";

          if (member) {
            const roles = member.roles.cache
              .filter(
                (role) =>
                  role.id !== guild.id
              )
              .map(
                (role) =>
                  `<@&${role.id}>`
              );

            if (roles.length > 0) {
              userRoles = roles.join(", ");
            }
          }

          /* -------------------------------------------------
             ACCOUNT DATES
          ------------------------------------------------- */

          const accountCreated =
            Math.floor(
              user.createdTimestamp / 1000
            );

          const joinedServer =
            member?.joinedTimestamp
              ? Math.floor(
                  member.joinedTimestamp / 1000
                )
              : null;

          /* -------------------------------------------------
             TICKET TYPE
          ------------------------------------------------- */

          const ticketType = isPurchase
            ? "🛒 Purchase"
            : "🛠️ Support";

          /* -------------------------------------------------
             DM EMBED
          ------------------------------------------------- */

          const dmEmbed = new EmbedBuilder()
            .setColor(COLORS.main)
            .setTitle("🎫 New Onyx Hub Ticket")
            .setThumbnail(user.displayAvatarURL())
            .setDescription(
              `A new ticket has been opened in **${guild.name}**.`
            )
            .addFields(
              {
                name: "👤 User",
                value:
                  `**Username:** ${user.username}\n` +
                  `**Display Name:** ${user.displayName}\n` +
                  `**Mention:** ${user}\n` +
                  `**ID:** \`${user.id}\``,
                inline: false,
              },

              {
                name: "📅 Account Information",
                value:
                  `**Account created:** <t:${accountCreated}:F>\n` +
                  `**Account created:** <t:${accountCreated}:R>\n` +
                  (joinedServer
                    ? `**Joined server:** <t:${joinedServer}:F>\n` +
                      `**Joined server:** <t:${joinedServer}:R>`
                    : "**Joined server:** Unknown"),
                inline: false,
              },

              {
                name: "🏷️ User Roles",
                value: userRoles,
                inline: false,
              },

              {
                name: "🎫 Ticket Information",
                value:
                  `**Type:** ${ticketType}\n` +
                  `**Channel:** ${ticketChannel}\n` +
                  `**Channel name:** \`${ticketChannel.name}\`\n` +
                  `**Channel ID:** \`${ticketChannel.id}\`\n` +
                  `**Category:** ${category.name}\n` +
                  `**Category ID:** \`${category.id}\`\n` +
                  `**Topic:** \`${ticketChannel.topic}\``,
                inline: false,
              },

              {
                name: "🏠 Server Information",
                value:
                  `**Server:** ${guild.name}\n` +
                  `**Server ID:** \`${guild.id}\`\n` +
                  `**Server owner:** <@${guild.ownerId}>\n` +
                  `**Member count:** ${guild.memberCount}`,
                inline: false,
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
                inline: false,
              },

              {
                name: "🔗 Direct Ticket Link",
                value: `[Open Ticket](https://discord.com/channels/${guild.id}/${ticketChannel.id})`,
                inline: false,
              },

              {
                name: "🤖 Bot",
                value:
                  `**Bot:** ${client.user.tag}\n` +
                  `**Bot ID:** \`${client.user.id}\``,
                inline: false,
              }
            )
            .setFooter({
              text: "Onyx Hub • Ticket Notification",
            })
            .setTimestamp();

          await owner.send({
            embeds: [dmEmbed],
          });

          console.log(
            `📩 Ticket information sent to owner for ${user.tag}`
          );
        }
      } catch (error) {
        console.error(
          "❌ Could not send ticket information by DM:",
          error
        );
      }

      /* =================================================
         BUTTONS
      ================================================= */

      const ticketButtons =
        new ActionRowBuilder().addComponents(
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

      /* =================================================
         PURCHASE TICKET
      ================================================= */

      if (isPurchase) {
        const purchaseEmbed =
          new EmbedBuilder()
            .setColor(COLORS.main)
            .setTitle("🛒 Purchase Ticket")
            .setDescription(
              [
                `Hello ${user}, welcome to your purchase ticket!`,
                "",
                "Please tell us what you want to purchase and include any useful information about your order.",
                "",
                "🌐 You can also buy directly from our website:",
                SHOP_URL,
                "",
                "Please wait for a staff member to respond.",
              ].join("\n")
            )
            .setFooter({
              text: "Onyx Hub • Purchase",
            })
            .setTimestamp();

        await ticketChannel.send({
          content: `${user}`,
          embeds: [purchaseEmbed],
          components: [ticketButtons],
          allowedMentions: {
            users: [user.id],
          },
        });
      }

      /* =================================================
         SUPPORT TICKET
      ================================================= */

      else {
        const supportEmbed =
          new EmbedBuilder()
            .setColor(COLORS.main)
            .setTitle("🛠️ Support Ticket")
            .setDescription(
              [
                `Hello ${user}, welcome to your support ticket!`,
                "",
                "🛠️ This ticket is for **help and support only**.",
                "",
                "Please explain your problem or question as clearly as possible.",
                "",
                "You can provide:",
                "• Screenshots",
                "• Error messages",
                "• Details about your problem",
                "• Any information that could help our team",
                "",
                "Please wait for a staff member to respond.",
              ].join("\n")
            )
            .setFooter({
              text: "Onyx Hub • Support",
            })
            .setTimestamp();

        await ticketChannel.send({
          content: `${user}`,
          embeds: [supportEmbed],
          components: [ticketButtons],
          allowedMentions: {
            users: [user.id],
          },
        });
      }

      /* -------------------------------------------------
         CONFIRMATION
      ------------------------------------------------- */

      return interaction.editReply({
        content: `✅ Your ticket has been created: ${ticketChannel}`,
      });
    }

    /* =================================================
       CLAIM TICKET
    ================================================= */

    if (interaction.customId === "ticket_claim") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("onyx-ticket:")
      ) {
        return interaction.reply({
          content:
            "❌ This is not an Onyx Hub ticket.",
          ephemeral: true,
        });
      }

      const isStaff =
        interaction.memberPermissions.has(
          PermissionFlagsBits.ManageChannels
        );

      if (!isStaff) {
        return interaction.reply({
          content:
            "❌ Only staff members can claim tickets.",
          ephemeral: true,
        });
      }

      const currentClaim =
        claimedTickets.get(channel.id);

      if (currentClaim) {
        const claimedUser =
          await client.users
            .fetch(currentClaim)
            .catch(() => null);

        return interaction.reply({
          content: claimedUser
            ? `❌ This ticket is already claimed by ${claimedUser}.`
            : "❌ This ticket is already claimed.",
          ephemeral: true,
        });
      }

      claimedTickets.set(
        channel.id,
        interaction.user.id
      );

      const unclaimButton =
        new ActionRowBuilder().addComponents(
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

      await interaction.update({
        components: [unclaimButton],
      });

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

    /* =================================================
       UNCLAIM TICKET
    ================================================= */

    if (interaction.customId === "ticket_unclaim") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("onyx-ticket:")
      ) {
        return interaction.reply({
          content:
            "❌ This is not an Onyx Hub ticket.",
          ephemeral: true,
        });
      }

      const claimedBy =
        claimedTickets.get(channel.id);

      if (!claimedBy) {
        return interaction.reply({
          content:
            "❌ This ticket is not currently claimed.",
          ephemeral: true,
        });
      }

      if (
        claimedBy !== interaction.user.id
      ) {
        return interaction.reply({
          content:
            "❌ Only the staff member who claimed this ticket can unclaim it.",
          ephemeral: true,
        });
      }

      claimedTickets.delete(channel.id);

      const claimButtons =
        new ActionRowBuilder().addComponents(
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

      await interaction.update({
        components: [claimButtons],
      });

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

    /* =================================================
       CLOSE TICKET
    ================================================= */

    if (interaction.customId === "ticket_close") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("onyx-ticket:")
      ) {
        return interaction.reply({
          content:
            "❌ This is not an Onyx Hub ticket.",
          ephemeral: true,
        });
      }

      const ticketOwnerId =
        channel.topic.slice(
          "onyx-ticket:".length
        );

      const isOwner =
        interaction.user.id ===
        ticketOwnerId;

      const isStaff =
        interaction.memberPermissions.has(
          PermissionFlagsBits.ManageChannels
        );

      if (!isOwner && !isStaff) {
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

      setTimeout(async () => {
        try {
          await channel.delete(
            "Onyx Hub ticket closed"
          );
        } catch (error) {
          console.error(
            "❌ Could not delete ticket:",
            error
          );
        }
      }, 5000);
    }
  } catch (error) {
    console.error(
      "❌ Interaction error:",
      error
    );

    if (
      interaction.deferred &&
      !interaction.replied
    ) {
      await interaction
        .editReply({
          content:
            "❌ An error occurred. Check the bot console.",
        })
        .catch(() => {});
    } else if (!interaction.replied) {
      await interaction
        .reply({
          content:
            "❌ An error occurred. Check the bot console.",
          ephemeral: true,
        })
        .catch(() => {});
    }
  }
});

/* =====================================================
   CHECK ENV VARIABLES
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
   REGISTER COMMAND
===================================================== */

async function registerCommands() {
  const commands = [
    new SlashCommandBuilder()
      .setName("tickets")
      .setDescription(
        "Post the Onyx Hub ticket panel."
      )
      .toJSON(),
  ];

  const rest = new REST({
    version: "10",
  }).setToken(
    process.env.DISCORD_TOKEN
  );

  await rest.put(
    Routes.applicationGuildCommands(
      process.env.CLIENT_ID,
      process.env.GUILD_ID
    ),
    {
      body: commands,
    }
  );

  console.log(
    "✅ Slash commands registered."
  );
}

/* =====================================================
   START BOT
===================================================== */

async function startBot() {
  try {
    await registerCommands();

    await client.login(
      process.env.DISCORD_TOKEN
    );
  } catch (error) {
    console.error(
      "❌ Failed to start bot:",
      error
    );
  }
}

startBot();