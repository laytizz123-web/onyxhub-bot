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

// =====================================================
// CLAIM SYSTEM
// =====================================================

// channelId -> staffUserId
const claimedTickets = new Map();

// =====================================================
// BOT READY
// =====================================================

client.once(Events.ClientReady, (bot) => {
  console.log(`✅ ${bot.user.tag} est connecté !`);
});

// =====================================================
// INTERACTIONS
// =====================================================

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    // =================================================
    // /tickets
    // =================================================

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
        .setTitle("ONYX HUB | Tickets Center")
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

    // =================================================
    // BUTTONS
    // =================================================

    if (!interaction.isButton()) return;

    // =================================================
    // CREATE TICKET
    // =================================================

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

      // -------------------------------------------------
      // CHECK EXISTING TICKET
      // -------------------------------------------------

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

      // -------------------------------------------------
      // FIND / CREATE CATEGORY
      // -------------------------------------------------

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

      // -------------------------------------------------
      // USERNAME
      // -------------------------------------------------

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

      // -------------------------------------------------
      // PERMISSIONS
      // -------------------------------------------------

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

      // -------------------------------------------------
      // STAFF ROLE
      // -------------------------------------------------

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

      // -------------------------------------------------
      // CREATE CHANNEL
      // -------------------------------------------------

      const ticketChannel = await guild.channels.create({
        name: channelName,
        type: ChannelType.GuildText,
        parent: category.id,

        topic: `onyx-ticket:${user.id}`,

        permissionOverwrites,
      });

      // =================================================
      // BUTTONS
      // =================================================

      const ticketButtons = new ActionRowBuilder().addComponents(
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

      // =================================================
      // PURCHASE TICKET
      // =================================================

      if (isPurchase) {
        const purchaseEmbed = new EmbedBuilder()
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

      // =================================================
      // SUPPORT TICKET
      // =================================================

      else {
        const supportEmbed = new EmbedBuilder()
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

      // -------------------------------------------------
      // CONFIRMATION
      // -------------------------------------------------

      return interaction.editReply({
        content: `✅ Your ticket has been created: ${ticketChannel}`,
      });
    }

    // =================================================
    // CLAIM TICKET
    // =================================================

    if (interaction.customId === "ticket_claim") {
      const channel = interaction.channel;

      // Vérifier que c'est bien un ticket
      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("onyx-ticket:")
      ) {
        return interaction.reply({
          content: "❌ This is not an Onyx Hub ticket.",
          ephemeral: true,
        });
      }

      // Vérifier le staff
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

      // Vérifier si déjà claim
      const currentClaim = claimedTickets.get(
        channel.id
      );

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

      // Claim
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

    // =================================================
    // UNCLAIM TICKET
    // =================================================

    if (interaction.customId === "ticket_unclaim") {
      const channel = interaction.channel;

      if (
        !channel ||
        channel.type !== ChannelType.GuildText ||
        !channel.topic?.startsWith("onyx-ticket:")
      ) {
        return interaction.reply({
          content: "❌ This is not an Onyx Hub ticket.",
          ephemeral: true,
        });
      }

      const claimedBy = claimedTickets.get(
        channel.id
      );

      if (!claimedBy) {
        return interaction.reply({
          content:
            "❌ This ticket is not currently claimed.",
          ephemeral: true,
        });
      }

      // Seul le staff qui a claim peut unclaim
      if (claimedBy !== interaction.user.id) {
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

    // =================================================
    // CLOSE TICKET
    // =================================================

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
        interaction.user.id === ticketOwnerId;

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

      // Remove claim from memory
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

// =====================================================
// CHECK ENV VARIABLES
// =====================================================

if (
  !process.env.DISCORD_TOKEN ||
  !process.env.CLIENT_ID ||
  !process.env.GUILD_ID
) {
  console.error(
    "❌ Missing DISCORD_TOKEN, CLIENT_ID or GUILD_ID in .env"
  );

  process.exit(1);
}

// =====================================================
// REGISTER COMMAND
// =====================================================

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

// =====================================================
// START BOT
// =====================================================

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