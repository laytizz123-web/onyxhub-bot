"use strict";

/*
  LTC MIDDLEMAN BOT: standalone Discord bot (discord.js v14).
  An admin posts the panel with /panel. Each click on "Open a middleman ticket" creates a private
  ticket; the Litecoin escrow steps then run inside it (see middleman.js).
*/

require("dotenv").config();
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
const middleman = require("./middleman");

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
    .setTitle("💱 Litecoin Middleman")
    .setDescription(
      [
        "Trade safely: the bot holds the **LTC** until both sides are happy.",
        "",
        "1. Open a ticket and add the person you trade with",
        "2. Choose who sends and who receives the LTC",
        "3. The sender pays the address given by the bot",
        "4. The receiver delivers, the sender clicks **Release**",
        "5. The bot sends the funds to the receiver",
      ].join("\n")
    );
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
    .setTitle("💱 Middleman ticket")
    .setDescription(`Hello ${user}, follow the steps below. A staff member can join at any time with **Call staff**.`);
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
