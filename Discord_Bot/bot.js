// ===================================================================
//  FiveM & Discord Council Voting System - Discord Bot (v2.0)
// ===================================================================

const { 
    Client, 
    GatewayIntentBits, 
    Partials,
    REST, 
    Routes, 
    SlashCommandBuilder, 
    EmbedBuilder, 
    ActionRowBuilder, 
    ButtonBuilder, 
    ButtonStyle,
    PermissionsBitField 
} = require('discord.js');
const { open } = require('sqlite');
const sqlite3 = require('sqlite3');
const axios = require('axios');
const path = require('path');
const config = require('./config.json');

// Global database and active message tracking
let db;
let activeVoteMessage = null;
let activeVoteTimer = null;

// ===================================================================
//  1. DATABASE INITIALIZATION
// ===================================================================

async function initDatabase() {
    try {
        db = await open({
            filename: path.join(__dirname, 'links.db'),
            driver: sqlite3.Database
        });

        await db.exec(`
            CREATE TABLE IF NOT EXISTS user_links (
                discord_id TEXT PRIMARY KEY,
                fivem_license TEXT NOT NULL,
                username TEXT,
                linked_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('✅ SQLite database initialized and ready.');
    } catch (err) {
        console.error('❌ Failed to initialize SQLite database:', err);
        process.exit(1);
    }
}

// ===================================================================
//  2. SLASH COMMAND DEFINITIONS
// ===================================================================

const commands = [
    // 1. Link a Discord user to a FiveM license
    new SlashCommandBuilder()
        .setName('linkuser')
        .setDescription('Admin: Link a Discord member to their FiveM license.')
        .addUserOption(opt => opt.setName('user').setDescription('The Discord user to link').setRequired(true))
        .addStringOption(opt => opt.setName('license').setDescription('FiveM license (e.g. license:1234abcd...)').setRequired(true))
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild),

    // 2. Unlink a user
    new SlashCommandBuilder()
        .setName('unlinkuser')
        .setDescription('Admin: Remove a linked FiveM license from a Discord member.')
        .addUserOption(opt => opt.setName('user').setDescription('The Discord user to unlink').setRequired(true))
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild),

    // 3. List linked council members
    new SlashCommandBuilder()
        .setName('listcouncil')
        .setDescription('Admin: List all linked council members in the database.')
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild),

    // 4. Start a council vote
    new SlashCommandBuilder()
        .setName('startcouncilvote')
        .setDescription('Initiate a new City Council vote across Discord and FiveM.')
        .addStringOption(opt => opt.setName('question').setDescription('The motion/question to vote on').setRequired(true))
        .addIntegerOption(opt => opt.setName('duration').setDescription('Vote duration in seconds (Default: 300)').setRequired(false)),

    // 5. Conclude an active vote early
    new SlashCommandBuilder()
        .setName('endcouncilvote')
        .setDescription('Conclude the active council vote early.')
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageMessages),

    // 6. Check active vote information
    new SlashCommandBuilder()
        .setName('voteinfo')
        .setDescription('Check status and remaining time for the active council vote.')
];

// ===================================================================
//  3. DISCORD CLIENT SETUP
// ===================================================================

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMembers
    ],
    partials: [
        Partials.Message,
        Partials.Channel
    ]
});

// Create button action row
function createVoteButtonRow(disabled = false) {
    return new ActionRowBuilder().addComponents(
        new ButtonBuilder()
            .setCustomId('vote_yes')
            .setLabel('Vote Yes')
            .setStyle(ButtonStyle.Success)
            .setEmoji('👍')
            .setDisabled(disabled),
        new ButtonBuilder()
            .setCustomId('vote_no')
            .setLabel('Vote No')
            .setStyle(ButtonStyle.Danger)
            .setEmoji('👎')
            .setDisabled(disabled),
        new ButtonBuilder()
            .setCustomId('vote_abstain')
            .setLabel('Abstain')
            .setStyle(ButtonStyle.Secondary)
            .setEmoji('⚪')
            .setDisabled(disabled)
    );
}

// Register slash commands on ready
client.once('ready', async () => {
    console.log(`🤖 Logged in as ${client.user.tag}!`);
    client.user.setActivity('City Hall Council', { type: 3 }); // Watching

    const rest = new REST({ version: '10' }).setToken(config.botToken);
    try {
        console.log('🔄 Registering slash commands...');
        await rest.put(
            Routes.applicationGuildCommands(client.user.id, config.guildId),
            { body: commands }
        );
        console.log('✅ Application slash commands registered successfully.');
    } catch (err) {
        console.error('❌ Failed to register slash commands:', err);
    }
});

// Helper: Check council role
function hasCouncilRole(member) {
    if (!config.councilRoleId || config.councilRoleId === "THE_ID_OF_YOUR_CITY_COUNCIL_ROLE") {
        return true;
    }
    return member.roles.cache.has(config.councilRoleId) || member.permissions.has(PermissionsBitField.Flags.Administrator);
}

// Helper: Check admin role
function hasAdminRole(member) {
    if (!config.adminRoleId || config.adminRoleId === "THE_ID_OF_AN_ADMIN_ROLE_WHO_CAN_LINK_USERS") {
        return member.permissions.has(PermissionsBitField.Flags.ManageGuild);
    }
    return member.roles.cache.has(config.adminRoleId) || member.permissions.has(PermissionsBitField.Flags.Administrator);
}

// ===================================================================
//  4. INTERACTION HANDLING (COMMANDS & BUTTONS)
// ===================================================================

client.on('interactionCreate', async interaction => {
    // ---------------------------------------------------------------
    // A. SLASH COMMAND HANDLER
    // ---------------------------------------------------------------
    if (interaction.isChatInputCommand()) {
        const { commandName } = interaction;

        // Command: /linkuser
        if (commandName === 'linkuser') {
            if (!hasAdminRole(interaction.member)) {
                return interaction.reply({ content: '❌ You lack permission to link accounts.', ephemeral: true });
            }

            const targetUser = interaction.options.getUser('user');
            let license = interaction.options.getString('license').trim();

            if (!license.startsWith('license:')) {
                license = `license:${license}`;
            }

            try {
                await db.run(
                    'INSERT OR REPLACE INTO user_links (discord_id, fivem_license, username) VALUES (?, ?, ?)',
                    targetUser.id,
                    license,
                    targetUser.tag
                );
                return interaction.reply({
                    content: `✅ Successfully linked **${targetUser.tag}** to \`${license}\`.`,
                    ephemeral: true
                });
            } catch (err) {
                console.error('DB Error in /linkuser:', err);
                return interaction.reply({ content: '❌ Database error saving link.', ephemeral: true });
            }
        }

        // Command: /unlinkuser
        if (commandName === 'unlinkuser') {
            if (!hasAdminRole(interaction.member)) {
                return interaction.reply({ content: '❌ You lack permission to unlink accounts.', ephemeral: true });
            }

            const targetUser = interaction.options.getUser('user');
            try {
                const result = await db.run('DELETE FROM user_links WHERE discord_id = ?', targetUser.id);
                if (result.changes > 0) {
                    return interaction.reply({ content: `✅ Unlinked **${targetUser.tag}** from their FiveM license.`, ephemeral: true });
                } else {
                    return interaction.reply({ content: `⚠️ **${targetUser.tag}** was not linked to any license.`, ephemeral: true });
                }
            } catch (err) {
                console.error('DB Error in /unlinkuser:', err);
                return interaction.reply({ content: '❌ Database error unlinking account.', ephemeral: true });
            }
        }

        // Command: /listcouncil
        if (commandName === 'listcouncil') {
            if (!hasAdminRole(interaction.member)) {
                return interaction.reply({ content: '❌ You lack permission to view this list.', ephemeral: true });
            }

            try {
                const rows = await db.all('SELECT * FROM user_links ORDER BY linked_at DESC LIMIT 50');
                if (!rows || rows.length === 0) {
                    return interaction.reply({ content: 'ℹ️ No council accounts are currently linked in the database.', ephemeral: true });
                }

                const list = rows.map((r, i) => `${i + 1}. <@${r.discord_id}> (${r.username || 'N/A'}) ➔ \`${r.fivem_license}\``).join('\n');
                const embed = new EmbedBuilder()
                    .setTitle('🏛️ Linked Council Members')
                    .setDescription(list)
                    .setColor('#3498DB')
                    .setFooter({ text: `Total Registered: ${rows.length}` });

                return interaction.reply({ embeds: [embed], ephemeral: true });
            } catch (err) {
                console.error('DB Error in /listcouncil:', err);
                return interaction.reply({ content: '❌ Database error retrieving list.', ephemeral: true });
            }
        }

        // Command: /startcouncilvote
        if (commandName === 'startcouncilvote') {
            if (!hasCouncilRole(interaction.member)) {
                return interaction.reply({ content: '❌ You must be a verified City Council member to initiate a vote.', ephemeral: true });
            }

            const question = interaction.options.getString('question');
            const duration = interaction.options.getInteger('duration') || 300;

            await interaction.deferReply();

            // Contact FiveM server
            try {
                const endpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/start-vote`;
                const response = await axios.post(endpoint, {
                    secret: config.fivemBotSecret,
                    question: question,
                    duration: duration,
                    starterName: interaction.user.tag
                }, { timeout: 7000 });

                if (!response.data.success) {
                    return interaction.editReply({ content: `⚠️ Failed to start vote: ${response.data.message || 'Unknown server error.'}` });
                }
            } catch (err) {
                console.error('Error contacting FiveM server:', err.message);
                const errMsg = err.response?.data?.message || 'Could not connect to the FiveM server endpoint.';
                return interaction.editReply({ content: `❌ Error communicating with FiveM server: ${errMsg}` });
            }

            // Create Discord Voting Embed
            const voteEmbed = new EmbedBuilder()
                .setTitle('🏛️ A New City Council Vote Has Started!')
                .setDescription(`**Motion Under Consideration:**\n${question}`)
                .setColor('#3498DB')
                .addFields(
                    { name: 'Sponsored By', value: `<@${interaction.user.id}>`, inline: true },
                    { name: 'Duration', value: `${duration}s (~${(duration / 60).toFixed(1)} mins)`, inline: true },
                    { name: 'Instructions', value: 'Council members may vote by clicking the buttons below or using `/castvote` in-game.', inline: false }
                )
                .setFooter({ text: 'Official City Hall Legislative Ballot' })
                .setTimestamp();

            const buttonRow = createVoteButtonRow(false);
            const voteMsg = await interaction.channel.send({
                embeds: [voteEmbed],
                components: [buttonRow]
            });

            activeVoteMessage = voteMsg;

            // Schedule auto-disable on button message when time expires
            if (activeVoteTimer) clearTimeout(activeVoteTimer);
            activeVoteTimer = setTimeout(async () => {
                try {
                    if (activeVoteMessage) {
                        const disabledRow = createVoteButtonRow(true);
                        const closedEmbed = EmbedBuilder.from(voteEmbed)
                            .setTitle('📜 Council Vote Concluded')
                            .setColor('#7F8C8D');
                        await activeVoteMessage.edit({ embeds: [closedEmbed], components: [disabledRow] });
                        activeVoteMessage = null;
                    }
                } catch (e) {
                    console.log('Note: Could not edit expired vote message.');
                }
            }, duration * 1000);

            return interaction.editReply({ content: '✅ Council vote successfully initiated both in-game and on Discord!' });
        }

        // Command: /endcouncilvote
        if (commandName === 'endcouncilvote') {
            if (!hasCouncilRole(interaction.member)) {
                return interaction.reply({ content: '❌ You lack permission to conclude council votes.', ephemeral: true });
            }

            await interaction.deferReply({ ephemeral: true });

            try {
                const endpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/end-vote`;
                const response = await axios.post(endpoint, {
                    secret: config.fivemBotSecret,
                    name: interaction.user.tag
                }, { timeout: 7000 });

                // Disable active Discord buttons if present
                if (activeVoteMessage) {
                    try {
                        const disabledRow = createVoteButtonRow(true);
                        await activeVoteMessage.edit({ components: [disabledRow] });
                    } catch (e) {}
                    activeVoteMessage = null;
                }
                if (activeVoteTimer) clearTimeout(activeVoteTimer);

                return interaction.editReply({ content: `✅ ${response.data.message || 'Vote concluded successfully.'}` });
            } catch (err) {
                console.error('Error concluding vote via HTTP:', err.message);
                const errMsg = err.response?.data?.message || 'Could not contact FiveM server.';
                return interaction.editReply({ content: `❌ Failed to conclude vote: ${errMsg}` });
            }
        }

        // Command: /voteinfo
        if (commandName === 'voteinfo') {
            try {
                const endpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/status`;
                const response = await axios.get(endpoint, { timeout: 5000 });
                const data = response.data;

                if (!data.active) {
                    return interaction.reply({ content: 'ℹ️ There is no active council vote currently in progress.', ephemeral: true });
                }

                const embed = new EmbedBuilder()
                    .setTitle('🏛️ Current Council Vote Status')
                    .setDescription(`**Motion:**\n${data.question}`)
                    .addFields(
                        { name: 'Time Remaining', value: `${data.timeRemaining} seconds`, inline: true },
                        { name: 'Total Cast', value: `${data.tally?.total || 0}`, inline: true },
                        { name: 'Live Tally', value: `✅ Yes: **${data.tally?.yes || 0}** | ❌ No: **${data.tally?.no || 0}** | ⚪ Abstain: **${data.tally?.abstain || 0}**`, inline: false }
                    )
                    .setColor('#F39C12');

                return interaction.reply({ embeds: [embed], ephemeral: true });
            } catch (err) {
                return interaction.reply({ content: '❌ Failed to reach the FiveM server status endpoint.', ephemeral: true });
            }
        }
    }

    // ---------------------------------------------------------------
    // B. INTERACTIVE BUTTON HANDLER
    // ---------------------------------------------------------------
    if (interaction.isButton()) {
        const customId = interaction.customId;
        if (!customId.startsWith('vote_')) return;

        // 1. Verify council member role
        if (!hasCouncilRole(interaction.member)) {
            return interaction.reply({
                content: '❌ You cannot vote because you do not have the designated City Council role.',
                ephemeral: true
            });
        }

        // 2. Query user link from database
        let link;
        try {
            link = await db.get('SELECT fivem_license FROM user_links WHERE discord_id = ?', interaction.user.id);
        } catch (err) {
            console.error('DB query error on button click:', err);
            return interaction.reply({
                content: '❌ A database error occurred. Please report this to an administrator.',
                ephemeral: true
            });
        }

        if (!link || !link.fivem_license) {
            return interaction.reply({
                content: '❌ Your Discord account is not linked to a FiveM license.\nPlease ask a server administrator to run `/linkuser` for your account.',
                ephemeral: true
            });
        }

        // 3. Map button choice
        const choice = customId.replace('vote_', ''); // 'yes', 'no', or 'abstain'

        // 4. Send vote to FiveM Server
        try {
            const endpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/vote`;
            const response = await axios.post(endpoint, {
                secret: config.fivemBotSecret,
                identifier: link.fivem_license,
                vote: choice,
                name: interaction.user.tag
            }, { timeout: 6000 });

            if (response.data.success) {
                const choiceDisplay = choice === 'yes' ? '✅ YES' : choice === 'no' ? '❌ NO' : '⚪ ABSTAIN';
                return interaction.reply({
                    content: `Your ballot has been officially recorded as **${choiceDisplay}**!`,
                    ephemeral: true
                });
            } else {
                return interaction.reply({
                    content: `⚠️ ${response.data.message || 'Unable to record ballot.'}`,
                    ephemeral: true
                });
            }
        } catch (err) {
            console.error('Error submitting vote to FiveM:', err.message);
            const serverMsg = err.response?.data?.message || 'Could not contact the FiveM server.';
            return interaction.reply({
                content: `❌ Vote submission failed: ${serverMsg}`,
                ephemeral: true
            });
        }
    }
});

// ===================================================================
//  5. START BOT
// ===================================================================

async function main() {
    await initDatabase();
    await client.login(config.botToken);
}

main().catch(err => {
    console.error('Fatal bot startup error:', err);
});