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
  ModalBuilder,
  TextInputBuilder,
  TextInputStyle,
  Events,
  REST,
  Routes,
  SlashCommandBuilder,
} = require("discord.js");

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

const {
  DISCORD_TOKEN,
  CLIENT_ID,
  GUILD_ID,
  STAFF_ROLE_ID,
} = process.env;

const SHOP_URL = "https://onyxhub7.mysellauth.com/";

const COLORS = {
  main: 0x7c3aed,
  success: 0x22c55e,
  error: 0xef4444,
  warning: 0xf59e0b,
};

const claimedTickets = new Map();

/* =========================================================
   CHECK ENV
========================================================= */

if (!DISCORD_TOKEN || !CLIENT_ID || !GUILD_ID) {
  console.error(
    "❌ Il manque DISCORD_TOKEN, CLIENT_ID ou GUILD_ID dans les variables d'environnement."
  );
  process.exit(1);
}

/* =========================================================
   HELPERS
========================================================= */

function isStaff(interaction) {
  if (
    interaction.memberPermissions &&
    interaction.memberPermissions.has(PermissionFlagsBits.ManageChannels)
  ) {
    return true;
  }

  if (
    STAFF_ROLE_ID &&
    interaction.member &&
    interaction.member.roles &&
    interaction.member.roles.cache.has(STAFF_ROLE_ID)
  ) {
    return true;
  }

  return false;
}

function ticketButtons(channelId) {
  const claimed = claimedTickets.has(channelId);

  return new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId(claimed ? "ticket_unclaim" : "ticket_claim")
      .setLabel(claimed ? "🔓 Unclaim Ticket" : "🎫 Claim Ticket")
      .setStyle(claimed ? ButtonStyle.Secondary : ButtonStyle.Primary),

    new ButtonBuilder()
      .setCustomId("ticket_close")
      .setLabel("🔒 Close Ticket")
      .setStyle(ButtonStyle.Danger),

    new ButtonBuilder()
      .setCustomId("buy_brainrot")
      .setLabel("🧠 Buy with Brainrot")
      .setStyle(ButtonStyle.Success)
  );
}

/* =========================================================
   SLASH COMMAND
========================================================= */

const commands = [
  new SlashCommandBuilder()
    .setName("tickets")
    .setDescription("Envoie le panneau des tickets")
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator),
].map((command) => command.toJSON());

/* =========================================================
   READY
========================================================= */

client.once(Events.ClientReady, async (readyClient) => {
  console.log(`✅ Connecté en tant que ${readyClient.user.tag}`);

  try {
    const rest = new REST({ version: "10" }).setToken(DISCORD_TOKEN);

    await rest.put(
      Routes.applicationGuildCommands(CLIENT_ID, GUILD_ID),
      { body: commands }
    );

    console.log("✅ Commande /tickets enregistrée.");
  } catch (error) {
    console.error("❌ Erreur enregistrement commande :", error);
  }
});

/* =========================================================
   INTERACTIONS
========================================================= */

client.on(Events.InteractionCreate, async (interaction) => {
  try {
    /* =====================================================
       /tickets
    ===================================================== */

    if (interaction.isChatInputCommand()) {
      if (interaction.commandName !== "tickets") return;

      if (!interaction.memberPermissions.has(PermissionFlagsBits.Administrator)) {
        return interaction.reply({
          content: "❌ Tu n'as pas la permission d'utiliser cette commande.",
          ephemeral: true,
        });
      }

      const embed = new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle("ONYX HUB | Support Center")
        .setDescription(
          [
            "Bienvenue dans le support **Onyx Hub**.",
            "",
            "🛒 **Purchase**",
            "Ouvre un ticket pour effectuer un achat.",
            `🌐 Site : ${SHOP_URL}`,
            "",
            "🛠️ **Support**",
            "Ouvre un ticket si tu as besoin d'aide ou si tu as une question.",
            "",
            "Choisis le type de ticket ci-dessous."
          ].join("\n")
        )
        .setFooter({ text: "ONYX HUB" });

      const row = new ActionRowBuilder().addComponents(
        new ButtonBuilder()
          .setCustomId("ticket_purchase")
          .setLabel("🛒 Purchase")
          .setStyle(ButtonStyle.Primary),

        new ButtonBuilder()
          .setCustomId("ticket_support")
          .setLabel("🛠️ Support")
          .setStyle(ButtonStyle.Secondary)
      );

      await interaction.reply({
        content: "✅ Panel envoyé.",
        ephemeral: true,
      });

      await interaction.channel.send({
        embeds: [embed],
        components: [row],
      });

      return;
    }

    /* =====================================================
       BUY WITH BRAINROT
    ===================================================== */

    if (interaction.isButton() && interaction.customId === "buy_brainrot") {
      const modal = new ModalBuilder()
        .setCustomId("brainrot_purchase_modal")
        .setTitle("Buy with Brainrot");

      const robloxUsername = new TextInputBuilder()
        .setCustomId("roblox_username")
        .setLabel("Ton pseudo Roblox")
        .setPlaceholder("Exemple : RobloxPlayer123")
        .setStyle(TextInputStyle.Short)
        .setRequired(true)
        .setMinLength(3)
        .setMaxLength(30);

      const brainrotName = new TextInputBuilder()
        .setCustomId("brainrot_name")
        .setLabel("Brainrot que tu donnes")
        .setPlaceholder("Exemple : Secret Brainrot")
        .setStyle(TextInputStyle.Short)
        .setRequired(true)
        .setMinLength(1)
        .setMaxLength(100);

      const firstRow = new ActionRowBuilder().addComponents(
        robloxUsername
      );

      const secondRow = new ActionRowBuilder().addComponents(
        brainrotName
      );

      modal.addComponents(firstRow, secondRow);

      await interaction.showModal(modal);
      return;
    }

    /* =====================================================
       TICKET BUTTONS
    ===================================================== */

    if (interaction.isButton()) {
      const customId = interaction.customId;

      /* ---------------------------------------------
         CREATE PURCHASE TICKET
      --------------------------------------------- */

      if (customId === "ticket_purchase") {
        await createTicket(interaction, "purchase");
        return;
      }

      /* ---------------------------------------------
         CREATE SUPPORT TICKET
      --------------------------------------------- */

      if (customId === "ticket_support") {
        await createTicket(interaction, "support");
        return;
      }

      /* ---------------------------------------------
         CLAIM
      --------------------------------------------- */

      if (customId === "ticket_claim") {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content: "❌ Tu n'as pas la permission de claim ce ticket.",
            ephemeral: true,
          });
        }

        if (claimedTickets.has(interaction.channel.id)) {
          return interaction.reply({
            content: "❌ Ce ticket est déjà claim.",
            ephemeral: true,
          });
        }

        claimedTickets.set(
          interaction.channel.id,
          interaction.user.id
        );

        await interaction.update({
          components: [ticketButtons(interaction.channel.id)],
        });

        await interaction.channel.send({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.success)
              .setDescription(
                `🎫 Ce ticket a été claim par ${interaction.user}.`
              ),
          ],
        });

        return;
      }

      /* ---------------------------------------------
         UNCLAIM
      --------------------------------------------- */

      if (customId === "ticket_unclaim") {
        const claimedBy = claimedTickets.get(interaction.channel.id);

        if (!claimedBy) {
          return interaction.reply({
            content: "❌ Ce ticket n'est actuellement pas claim.",
            ephemeral: true,
          });
        }

        if (claimedBy !== interaction.user.id) {
          return interaction.reply({
            content:
              "❌ Seul le membre du staff qui a claim ce ticket peut l'unclaim.",
            ephemeral: true,
          });
        }

        claimedTickets.delete(interaction.channel.id);

        await interaction.update({
          components: [ticketButtons(interaction.channel.id)],
        });

        await interaction.channel.send({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.warning)
              .setDescription(
                `🔓 ${interaction.user} a unclaim le ticket.`
              ),
          ],
        });

        return;
      }

      /* ---------------------------------------------
         CLOSE
      --------------------------------------------- */

      if (customId === "ticket_close") {
        const topic = interaction.channel.topic || "";

        const match = topic.match(/^onyx-ticket:(\d+)$/);

        if (!match) {
          return interaction.reply({
            content: "❌ Ce channel n'est pas un ticket Onyx Hub.",
            ephemeral: true,
          });
        }

        const ownerId = match[1];

        const canClose =
          interaction.user.id === ownerId ||
          isStaff(interaction);

        if (!canClose) {
          return interaction.reply({
            content: "❌ Tu ne peux pas fermer ce ticket.",
            ephemeral: true,
          });
        }

        claimedTickets.delete(interaction.channel.id);

        await interaction.reply({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.error)
              .setDescription(
                "🔒 Ce ticket sera fermé dans **5 secondes**."
              ),
          ],
        });

        setTimeout(async () => {
          try {
            await interaction.channel.delete();
          } catch (error) {
            console.error("❌ Impossible de supprimer le ticket :", error);
          }
        }, 5000);

        return;
      }
    }

    /* =====================================================
       BRAINROT MODAL
    ===================================================== */

    if (
      interaction.isModalSubmit() &&
      interaction.customId === "brainrot_purchase_modal"
    ) {
      const robloxUsername =
        interaction.fields.getTextInputValue("roblox_username");

      const brainrotName =
        interaction.fields.getTextInputValue("brainrot_name");

      const user = interaction.user;
      const channel = interaction.channel;

      /* ---------------------------------------------
         TICKET STATUS
      --------------------------------------------- */

      const statusEmbed = new EmbedBuilder()
        .setColor(COLORS.warning)
        .setTitle("🧠 Buy with Brainrot")
        .setDescription(
          [
            `👤 **Discord :** ${user}`,
            `🎮 **Roblox :** \`${robloxUsername}\``,
            `🧠 **Brainrot :** \`${brainrotName}\``,
            "",
            "🟡 **Waiting for trade**",
            "",
            "Un membre du staff va prendre en charge votre demande.",
          ].join("\n")
        )
        .setTimestamp();

      await interaction.reply({
        embeds: [statusEmbed],
      });

      /* ---------------------------------------------
         DM STAFF / OWNER
      --------------------------------------------- */

      const ownerId = process.env.OWNER_ID;

      if (!ownerId) {
        console.warn(
          "⚠️ OWNER_ID n'est pas configuré dans les variables d'environnement."
        );

        return;
      }

      try {
        const owner = await client.users.fetch(ownerId);

        const dmEmbed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle("🧠 Nouvelle demande — Buy with Brainrot")
          .addFields(
            {
              name: "👤 Discord",
              value: `${user.tag}\n\`${user.id}\``,
              inline: true,
            },
            {
              name: "🎮 Roblox",
              value: `\`${robloxUsername}\``,
              inline: true,
            },
            {
              name: "🧠 Brainrot",
              value: `\`${brainrotName}\``,
              inline: false,
            },
            {
              name: "🎫 Ticket",
              value: `<#${channel.id}>`,
              inline: false,
            }
          )
          .setFooter({
            text: "ONYX HUB • Buy with Brainrot",
          })
          .setTimestamp();

        await owner.send({
          embeds: [dmEmbed],
        });
      } catch (error) {
        console.error(
          "❌ Impossible d'envoyer le DM au propriétaire :",
          error
        );
      }

      return;
    }
  } catch (error) {
    console.error("❌ Erreur interaction :", error);

    try {
      if (interaction.replied || interaction.deferred) {
        await interaction.followUp({
          content: "❌ Une erreur est survenue.",
          ephemeral: true,
        });
      } else {
        await interaction.reply({
          content: "❌ Une erreur est survenue.",
          ephemeral: true,
        });
      }
    } catch {}
  }
});

/* =========================================================
   CREATE TICKET
========================================================= */

async function createTicket(interaction, type) {
  const guild = interaction.guild;
  const user = interaction.user;

  const categoryName = "ONYX TICKETS";

  let category = guild.channels.cache.find(
    (channel) =>
      channel.type === ChannelType.GuildCategory &&
      channel.name === categoryName
  );

  if (!category) {
    category = await guild.channels.create({
      name: categoryName,
      type: ChannelType.GuildCategory,
    });
  }

  const channelName =
    `${type}-${user.username}`
      .toLowerCase()
      .replace(/[^a-z0-9-_]/g, "-")
      .slice(0, 90);

  const existingTicket = guild.channels.cache.find(
    (channel) =>
      channel.parentId === category.id &&
      channel.topic === `onyx-ticket:${user.id}`
  );

  if (existingTicket) {
    return interaction.reply({
      content: `❌ Tu as déjà un ticket ouvert : ${existingTicket}`,
      ephemeral: true,
    });
  }

  const permissionOverwrites = [
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
  ];

  if (STAFF_ROLE_ID) {
    permissionOverwrites.push({
      id: STAFF_ROLE_ID,
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

  const channel = await guild.channels.create({
    name: channelName,
    type: ChannelType.GuildText,
    parent: category.id,
    topic: `onyx-ticket:${user.id}`,
    permissionOverwrites,
  });

  let embed;

  if (type === "purchase") {
    embed = new EmbedBuilder()
      .setColor(COLORS.main)
      .setTitle("🛒 Purchase Ticket")
      .setDescription(
        [
          `Hello ${user}, welcome to your purchase ticket!`,
          "",
          "🛒 This ticket is for purchases.",
          "",
          `🌐 Shop: ${SHOP_URL}`,
          "",
          "You can also use **Buy with Brainrot** below if you want to pay with a Brainrot.",
          "",
          "Please wait for a staff member to assist you.",
        ].join("\n")
      );
  } else {
    embed = new EmbedBuilder()
      .setColor(COLORS.main)
      .setTitle("🛠️ Support Ticket")
      .setDescription(
        [
          `Hello ${user}, welcome to your support ticket!`,
          "",
          "🛠️ This ticket is for help and support only.",
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
      );
  }

  await channel.send({
    content: `${user}`,
    embeds: [embed],
    components: [ticketButtons(channel.id)],
  });

  await interaction.reply({
    content: `✅ Ton ticket a été créé : ${channel}`,
    ephemeral: true,
  });
}

/* =========================================================
   LOGIN
========================================================= */

client.login(DISCORD_TOKEN);