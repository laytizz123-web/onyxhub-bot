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
  OWNER_ID,
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

if (!DISCORD_TOKEN || !CLIENT_ID || !GUILD_ID || !OWNER_ID) {
  console.error(
    "❌ Missing DISCORD_TOKEN, CLIENT_ID, GUILD_ID or OWNER_ID."
  );
  process.exit(1);
}

/* =========================================================
   STAFF CHECK
========================================================= */

function isStaff(interaction) {
  if (
    interaction.memberPermissions &&
    interaction.memberPermissions.has(
      PermissionFlagsBits.ManageChannels
    )
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

/* =========================================================
   TICKET BUTTONS
========================================================= */

function ticketButtons(channelId, type) {
  const claimed = claimedTickets.has(channelId);

  const buttons = [
    new ButtonBuilder()
      .setCustomId(
        claimed ? "ticket_unclaim" : "ticket_claim"
      )
      .setLabel(
        claimed
          ? "🔓 Unclaim Ticket"
          : "🎫 Claim Ticket"
      )
      .setStyle(
        claimed
          ? ButtonStyle.Secondary
          : ButtonStyle.Primary
      ),

    new ButtonBuilder()
      .setCustomId("ticket_close")
      .setLabel("🔒 Close Ticket")
      .setStyle(ButtonStyle.Danger),
  ];

  // Only Purchase tickets get the Brainrot button
  if (type === "purchase") {
    buttons.push(
      new ButtonBuilder()
        .setCustomId("buy_brainrot")
        .setLabel("🧠 Buy with Brainrot")
        .setStyle(ButtonStyle.Success)
    );
  }

  return new ActionRowBuilder().addComponents(buttons);
}

/* =========================================================
   SLASH COMMAND
========================================================= */

const commands = [
  new SlashCommandBuilder()
    .setName("tickets")
    .setDescription("Send the ticket panel")
    .setDefaultMemberPermissions(
      PermissionFlagsBits.Administrator
    ),
].map((command) => command.toJSON());

/* =========================================================
   READY
========================================================= */

client.once(Events.ClientReady, async (readyClient) => {
  console.log(
    `✅ Logged in as ${readyClient.user.tag}`
  );

  try {
    const rest = new REST({ version: "10" }).setToken(
      DISCORD_TOKEN
    );

    await rest.put(
      Routes.applicationGuildCommands(
        CLIENT_ID,
        GUILD_ID
      ),
      {
        body: commands,
      }
    );

    console.log("✅ /tickets command registered.");
  } catch (error) {
    console.error(
      "❌ Error registering commands:",
      error
    );
  }
});

/* =========================================================
   INTERACTIONS
========================================================= */

client.on(
  Events.InteractionCreate,
  async (interaction) => {
    try {
      /* =====================================================
         /tickets
      ===================================================== */

      if (interaction.isChatInputCommand()) {
        if (interaction.commandName !== "tickets") {
          return;
        }

        if (
          !interaction.memberPermissions.has(
            PermissionFlagsBits.Administrator
          )
        ) {
          return interaction.reply({
            content:
              "❌ You do not have permission to use this command.",
            ephemeral: true,
          });
        }

        const embed = new EmbedBuilder()
          .setColor(COLORS.main)
          .setTitle("ONYX HUB | Support Center")
          .setDescription(
            [
              "Welcome to **Onyx Hub Support**.",
              "",
              "🛒 **Purchase**",
              "Open a ticket if you want to make a purchase.",
              `🌐 Shop: ${SHOP_URL}`,
              "",
              "🛠️ **Support**",
              "Open a ticket if you need help or have a question.",
              "",
              "Please select a ticket type below.",
            ].join("\n")
          )
          .setFooter({
            text: "ONYX HUB",
          });

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
          content: "✅ Ticket panel sent.",
          ephemeral: true,
        });

        await interaction.channel.send({
          embeds: [embed],
          components: [row],
        });

        return;
      }

      /* =====================================================
         CREATE PURCHASE TICKET
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "ticket_purchase"
      ) {
        await createTicket(
          interaction,
          "purchase"
        );

        return;
      }

      /* =====================================================
         CREATE SUPPORT TICKET
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "ticket_support"
      ) {
        await createTicket(
          interaction,
          "support"
        );

        return;
      }

      /* =====================================================
         BUY WITH BRAINROT
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "buy_brainrot"
      ) {
        const modal = new ModalBuilder()
          .setCustomId("brainrot_purchase_modal")
          .setTitle("Buy with Brainrot");

        const robloxUsername =
          new TextInputBuilder()
            .setCustomId("roblox_username")
            .setLabel("Roblox username")
            .setPlaceholder(
              "Example: RobloxPlayer123"
            )
            .setStyle(TextInputStyle.Short)
            .setRequired(true)
            .setMinLength(3)
            .setMaxLength(30);

        const brainrotName =
          new TextInputBuilder()
            .setCustomId("brainrot_name")
            .setLabel("Brainrot you are giving")
            .setPlaceholder(
              "Example: Garama"
            )
            .setStyle(TextInputStyle.Short)
            .setRequired(true)
            .setMinLength(1)
            .setMaxLength(100);

        modal.addComponents(
          new ActionRowBuilder().addComponents(
            robloxUsername
          ),
          new ActionRowBuilder().addComponents(
            brainrotName
          )
        );

        await interaction.showModal(modal);

        return;
      }

      /* =====================================================
         CLAIM
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "ticket_claim"
      ) {
        if (!isStaff(interaction)) {
          return interaction.reply({
            content:
              "❌ You do not have permission to claim this ticket.",
            ephemeral: true,
          });
        }

        if (
          claimedTickets.has(
            interaction.channel.id
          )
        ) {
          return interaction.reply({
            content:
              "❌ This ticket has already been claimed.",
            ephemeral: true,
          });
        }

        claimedTickets.set(
          interaction.channel.id,
          interaction.user.id
        );

        const type =
          interaction.channel.name.startsWith(
            "purchase-"
          )
            ? "purchase"
            : "support";

        await interaction.update({
          components: [
            ticketButtons(
              interaction.channel.id,
              type
            ),
          ],
        });

        await interaction.channel.send({
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

      /* =====================================================
         UNCLAIM
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "ticket_unclaim"
      ) {
        const claimedBy =
          claimedTickets.get(
            interaction.channel.id
          );

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

        claimedTickets.delete(
          interaction.channel.id
        );

        const type =
          interaction.channel.name.startsWith(
            "purchase-"
          )
            ? "purchase"
            : "support";

        await interaction.update({
          components: [
            ticketButtons(
              interaction.channel.id,
              type
            ),
          ],
        });

        await interaction.channel.send({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.warning)
              .setDescription(
                `🔓 ${interaction.user} unclaimed this ticket.`
              ),
          ],
        });

        return;
      }

      /* =====================================================
         CLOSE TICKET
      ===================================================== */

      if (
        interaction.isButton() &&
        interaction.customId === "ticket_close"
      ) {
        const topic =
          interaction.channel.topic || "";

        const match = topic.match(
          /^onyx-ticket:(\d+)$/
        );

        if (!match) {
          return interaction.reply({
            content:
              "❌ This channel is not an Onyx Hub ticket.",
            ephemeral: true,
          });
        }

        const ownerId = match[1];

        const canClose =
          interaction.user.id === ownerId ||
          isStaff(interaction);

        if (!canClose) {
          return interaction.reply({
            content:
              "❌ You cannot close this ticket.",
            ephemeral: true,
          });
        }

        claimedTickets.delete(
          interaction.channel.id
        );

        await interaction.reply({
          embeds: [
            new EmbedBuilder()
              .setColor(COLORS.error)
              .setDescription(
                "🔒 This ticket will be closed in **5 seconds**."
              ),
          ],
        });

        setTimeout(async () => {
          try {
            await interaction.channel.delete();
          } catch (error) {
            console.error(
              "❌ Could not delete ticket:",
              error
            );
          }
        }, 5000);

        return;
      }

      /* =====================================================
         BRAINROT MODAL
      ===================================================== */

      if (
        interaction.isModalSubmit() &&
        interaction.customId ===
          "brainrot_purchase_modal"
      ) {
        const robloxUsername =
          interaction.fields.getTextInputValue(
            "roblox_username"
          );

        const brainrotName =
          interaction.fields.getTextInputValue(
            "brainrot_name"
          );

        const user = interaction.user;
        const channel = interaction.channel;

        /* ---------------------------------------------
           MESSAGE IN TICKET
        --------------------------------------------- */

        await interaction.reply({
          content:
            "🧠 **Wait for the owner to take your Brainrot.**",
        });

        /* ---------------------------------------------
           SEND DM TO OWNER
        --------------------------------------------- */

        try {
          const owner =
            await client.users.fetch(OWNER_ID);

          const dmEmbed = new EmbedBuilder()
            .setColor(COLORS.main)
            .setTitle(
              "🧠 New Brainrot Payment"
            )
            .addFields(
              {
                name: "👤 Discord",
                value:
                  `${user.tag}\n\`${user.id}\``,
                inline: true,
              },
              {
                name: "🎮 Roblox",
                value:
                  `\`${robloxUsername}\``,
                inline: true,
              },
              {
                name: "🧠 Brainrot",
                value:
                  `\`${brainrotName}\``,
                inline: false,
              },
              {
                name: "🎫 Ticket",
                value:
                  `<#${channel.id}>`,
                inline: false,
              }
            )
            .setFooter({
              text:
                "ONYX HUB • Brainrot Payment",
            })
            .setTimestamp();

          await owner.send({
            embeds: [dmEmbed],
          });

          console.log(
            `🧠 Brainrot request received from ${user.tag}`
          );
        } catch (error) {
          console.error(
            "❌ Could not send DM to owner:",
            error
          );
        }

        return;
      }
    } catch (error) {
      console.error(
        "❌ Interaction error:",
        error
      );

      try {
        if (
          interaction.replied ||
          interaction.deferred
        ) {
          await interaction.followUp({
            content:
              "❌ An error occurred.",
            ephemeral: true,
          });
        } else {
          await interaction.reply({
            content:
              "❌ An error occurred.",
            ephemeral: true,
          });
        }
      } catch {}
    }
  }
);

/* =========================================================
   CREATE TICKET
========================================================= */

async function createTicket(
  interaction,
  type
) {
  const guild = interaction.guild;
  const user = interaction.user;

  const categoryName = "ONYX TICKETS";

  let category =
    guild.channels.cache.find(
      (channel) =>
        channel.type ===
          ChannelType.GuildCategory &&
        channel.name === categoryName
    );

  if (!category) {
    category =
      await guild.channels.create({
        name: categoryName,
        type: ChannelType.GuildCategory,
      });
  }

  const channelName =
    `${type}-${user.username}`
      .toLowerCase()
      .replace(
        /[^a-z0-9-_]/g,
        "-"
      )
      .slice(0, 90);

  /* ---------------------------------------------
     CHECK EXISTING TICKET
  --------------------------------------------- */

  const existingTicket =
    guild.channels.cache.find(
      (channel) =>
        channel.parentId === category.id &&
        channel.topic ===
          `onyx-ticket:${user.id}`
    );

  if (existingTicket) {
    return interaction.reply({
      content:
        `❌ You already have an open ticket: ${existingTicket}`,
      ephemeral: true,
    });
  }

  /* ---------------------------------------------
     PERMISSIONS
  --------------------------------------------- */

  const permissionOverwrites = [
    {
      id: guild.roles.everyone.id,
      deny: [
        PermissionFlagsBits.ViewChannel,
      ],
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

  /* ---------------------------------------------
     CREATE CHANNEL
  --------------------------------------------- */

  const channel =
    await guild.channels.create({
      name: channelName,
      type: ChannelType.GuildText,
      parent: category.id,
      topic:
        `onyx-ticket:${user.id}`,
      permissionOverwrites,
    });

  /* ---------------------------------------------
     PURCHASE TICKET
  --------------------------------------------- */

  if (type === "purchase") {
    const embed =
      new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle(
          "🛒 Purchase Ticket"
        )
        .setDescription(
          [
            `Hello ${user}, welcome to your purchase ticket!`,
            "",
            "🛒 This ticket is for purchases.",
            "",
            `🌐 Shop: ${SHOP_URL}`,
            "",
            "You can also use **Buy with Brainrot** if you want to pay with a Brainrot.",
            "",
            "Please wait for a staff member to assist you.",
          ].join("\n")
        )
        .setFooter({
          text: "ONYX HUB",
        });

    await channel.send({
      content: `${user}`,
      embeds: [embed],
      components: [
        ticketButtons(
          channel.id,
          "purchase"
        ),
      ],
    });
  }

  /* ---------------------------------------------
     SUPPORT TICKET
  --------------------------------------------- */

  if (type === "support") {
    const embed =
      new EmbedBuilder()
        .setColor(COLORS.main)
        .setTitle(
          "🛠️ Support Ticket"
        )
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
        )
        .setFooter({
          text: "ONYX HUB",
        });

    await channel.send({
      content: `${user}`,
      embeds: [embed],
      components: [
        ticketButtons(
          channel.id,
          "support"
        ),
      ],
    });
  }

  /* ---------------------------------------------
     CONFIRM TICKET CREATION
  --------------------------------------------- */

  await interaction.reply({
    content:
      `✅ Your ticket has been created: ${channel}`,
    ephemeral: true,
  });
}

/* =========================================================
   LOGIN
========================================================= */

client.login(DISCORD_TOKEN);