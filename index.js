
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

client.once(Events.ClientReady, (bot) => {
  console.log(`✅ ${bot.user.tag} est connecté !`);
});

// Créer le panneau de tickets avec /tickets
client.on(Events.InteractionCreate, async (interaction) => {
  try {
    // Commande slash /tickets
    if (interaction.isChatInputCommand()) {
      if (interaction.commandName !== "tickets") return;

      if (
        !interaction.memberPermissions.has(
          PermissionFlagsBits.Administrator
        )
      ) {
        return interaction.reply({
          content: "❌ Seuls les administrateurs peuvent utiliser cette commande.",
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
            `You can also purchase directly from our website:`,
            SHOP_URL,
            "",
            "Our team will assist you as soon as possible.",
          ].join("\n")
        )
        .setFooter({ text: "Onyx Hub • Ticket System" })
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

    // Ignorer les autres interactions
    if (!interaction.isButton()) return;

    // Ouvrir un ticket
    if (
      interaction.customId === "ticket_purchase" ||
      interaction.customId === "ticket_support"
    ) {
      await interaction.deferReply({ ephemeral: true });

      const guild = interaction.guild;
      const user = interaction.user;
      const isPurchase =
        interaction.customId === "ticket_purchase";

      // Empêcher plusieurs tickets ouverts par la même personne
      const existing = guild.channels.cache.find(
        (channel) =>
          channel.type === ChannelType.GuildText &&
          channel.topic === `onyx-ticket:${user.id}`
      );

      if (existing) {
        return interaction.editReply({
          content: `❌ You already have an open ticket: ${existing}`,
        });
      }

      // Chercher une catégorie de tickets existante
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

      const safeName = user.username
        .toLowerCase()
        .replace(/[^a-z0-9-]/g, "")
        .slice(0, 18) || "user";

      const channelName = `${isPurchase ? "purchase" : "support"}-${safeName}`
        .slice(0, 90);

      const ticketChannel = await guild.channels.create({
        name: channelName,
        type: ChannelType.GuildText,
        parent: category.id,
        topic: `onyx-ticket:${user.id}`,
        permissionOverwrites: [
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
            ],
          },
        ],
      });

      const ticketEmbed = new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle(
          isPurchase
            ? "🛒 Purchase Ticket"
            : "🛠️ Support Ticket"
        )
        .setDescription(
          [
            `Hello ${user}, welcome to your ticket!`,
            "",
            isPurchase
              ? "Please tell us what you want to purchase and include any useful order information."
              : "Please describe your issue in detail so our team can help you.",
            "",
            "🌐 You can also buy directly from our website:",
            SHOP_URL,
            "",
            "Please wait for a staff member to respond.",
          ].join("\n")
        )
        .setFooter({ text: "Onyx Hub • Private Ticket" })
        .setTimestamp();

      const closeButton = new ActionRowBuilder().addComponents(
        new ButtonBuilder()
          .setCustomId("ticket_close")
          .setLabel("Close Ticket")
          .setEmoji("🔒")
          .setStyle(ButtonStyle.Danger)
      );

      await ticketChannel.send({
        content: `${user}`,
        embeds: [ticketEmbed],
        components: [closeButton],
        allowedMentions: { users: [user.id] },
      });

      return interaction.editReply({
        content: `✅ Your ticket has been created: ${ticketChannel}`,
      });
    }

    // Fermer un ticket
    if (interaction.customId === "ticket_close") {
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

      const ticketOwnerId = channel.topic.slice(
        "onyx-ticket:".length
      );

      const isOwner = interaction.user.id === ticketOwnerId;
      const isStaff = interaction.memberPermissions.has(
        PermissionFlagsBits.ManageChannels
      );

      if (!isOwner && !isStaff) {
        return interaction.reply({
          content: "❌ Only the ticket owner or staff can close this ticket.",
          ephemeral: true,
        });
      }

      await interaction.reply({
        content: "🔒 Ticket closed. This channel will be deleted in 5 seconds.",
      });

      setTimeout(async () => {
        try {
          await channel.delete("Onyx Hub ticket closed");
        } catch (error) {
          console.error("Could not delete ticket:", error);
        }
      }, 5000);
    }
  } catch (error) {
    console.error("Interaction error:", error);

    const message = {
      content: "❌ An error occurred. Check the bot console.",
      ephemeral: true,
    };

    if (interaction.deferred && !interaction.replied) {
      await interaction.editReply({
        content: message.content,
      }).catch(() => {});
    } else if (!interaction.replied) {
      await interaction.reply(message).catch(() => {});
    }
  }
});

if (!process.env.DISCORD_TOKEN || !process.env.CLIENT_ID || !process.env.GUILD_ID) {
  console.error(
    "❌ Missing DISCORD_TOKEN, CLIENT_ID or GUILD_ID in your .env file."
  );
  process.exit(1);
}

// Register the /tickets slash command
async function registerCommands() {
  const { REST, Routes, SlashCommandBuilder } = require("discord.js");

  const commands = [
    new SlashCommandBuilder()
      .setName("tickets")
      .setDescription("Post the Onyx Hub ticket panel.")
      .toJSON(),
  ];

  const rest = new REST({ version: "10" }).setToken(
    process.env.DISCORD_TOKEN
  );

  await rest.put(
    Routes.applicationGuildCommands(
      process.env.CLIENT_ID,
      process.env.GUILD_ID
    ),
    { body: commands }
  );

  console.log("✅ Slash commands registered.");
}

async function startBot() {
  try {
    await registerCommands();
    await client.login(process.env.DISCORD_TOKEN);
  } catch (error) {
    console.error("❌ Failed to start bot:", error);
  }
}

startBot();