// bot.js
const { Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder, EmbedBuilder, PermissionsBitField } = require('discord.js');
const { open } = require('sqlite');
const sqlite3 = require('sqlite3');
const axios = require('axios');
const config = require('./config.json'); // <-- FIXED PATH

// -------------------------------------------------------------------
//  DATABASE SETUP (using simple SQLite)
// -------------------------------------------------------------------
let db;
(async () => {
    // Open the database
    db = await open({
        filename: './links.db', // This file will be created in the same folder
        driver: sqlite3.Database
    });
    // Create the table if it doesn't exist
    await db.exec('CREATE TABLE IF NOT EXISTS user_links (discord_id TEXT PRIMARY KEY, fivem_license TEXT)');
    console.log('Database connection established.');
})();

// -------------------------------------------------------------------
//  BOT & COMMANDS SETUP
// -------------------------------------------------------------------
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessageReactions, GatewayIntentBits.GuildMembers] });
const commands = [
    // 1. Admin Command to link a Discord user to a FiveM license
    new SlashCommandBuilder()
        .setName('linkuser')
        .setDescription('Admin: Link a user to their FiveM license.')
        .addUserOption(option => 
            option.setName('user')
                .setDescription('The Discord user to link')
                .setRequired(true))
        .addStringOption(option =>
            option.setName('license')
                .setDescription('The user\'s FiveM license (e.g., license:xxxxxxxx)')
                .setRequired(true))
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageGuild), // Only admins can use
    
    // 2. Command to start a vote
    new SlashCommandBuilder()
        .setName('startcouncilvote')
        .setDescription('Starts a city council vote.')
        .addStringOption(option =>
            option.setName('question')
                .setDescription('The question to vote on')
                .setRequired(true))
        .setDefaultMemberPermissions(PermissionsBitField.Flags.ManageMessages), // Or use your council role perm
];

// Register commands with Discord
const rest = new REST({ version: '10' }).setToken(config.botToken);

// We need to wait for the client to be ready to get the user ID
client.once('ready', async () => {
    try {
        console.log('Started refreshing application (/) commands.');
        await rest.put(
            Routes.applicationGuildCommands(client.user.id, config.guildId),
            { body: commands },
        );
        console.log('Successfully reloaded application (/) commands.');
    } catch (error) {
        console.error(error);
    }

    console.log(`Logged in as ${client.user.tag}!`);
    client.user.setActivity('Watching City Hall');
});


// -------------------------------------------------------------------
//  INTERACTION (COMMAND) HANDLER
// -------------------------------------------------------------------
client.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    const { commandName } = interaction;

    // --- Handle /linkuser ---
    if (commandName === 'linkuser') {
        if (!interaction.member.roles.cache.has(config.adminRoleId)) {
            return interaction.reply({ content: 'You do not have permission to use this command.', ephemeral: true });
        }
        
        const user = interaction.options.getUser('user');
        const license = interaction.options.getString('license');

        if (!license.startsWith('license:')) {
            return interaction.reply({ content: 'Invalid license format. It must start with `license:`', ephemeral: true });
        }

        try {
            await db.run('INSERT OR REPLACE INTO user_links (discord_id, fivem_license) VALUES (?, ?)', user.id, license);
            await interaction.reply({ content: `Successfully linked ${user.tag} to \`${license}\`.`, ephemeral: true });
        } catch (err) {
            console.error(err);
            await interaction.reply({ content: 'Failed to write to the database.', ephemeral: true });
        }
    }

    // --- Handle /startcouncilvote ---
    if (commandName === 'startcouncilvote') {
        if (!interaction.member.roles.cache.has(config.councilRoleId)) {
            return interaction.reply({ content: 'You are not a council member and cannot start a vote.', ephemeral: true });
        }

        const question = interaction.options.getString('question');

        // --- START OF CRITICAL FIX ---
        // Try to start the vote on the FiveM server FIRST
        try {
            const fivemEndpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/start-vote`;
            await axios.post(fivemEndpoint, {
                secret: config.fivemBotSecret,
                question: question
            });

        } catch (err) {
            // If the server fails (e.g., vote already active), stop here.
            console.error("Error starting vote on FiveM server:", err.message);
            let errorMessage = "Could not start vote: Failed to contact FiveM server.";
            if (err.response && err.response.data) {
                errorMessage = `Could not start vote: ${err.response.data}`;
            }
            return interaction.reply({ content: errorMessage, ephemeral: true });
        }
        // --- END OF CRITICAL FIX ---

        const voteEmbed = new EmbedBuilder()
            .setTitle('A New Council Vote Has Started!')
            .setDescription(`**Question:**\n${question}`)
            .setColor('#3498DB')
            .setFooter({ text: 'Council members: React with 👍 (Yes) or 👎 (No) to vote.' }); // <-- FIXED EMOJI

        // Send the message and store it
        const voteMessage = await interaction.channel.send({ embeds: [voteEmbed] });
        
        // Add reactions
        await voteMessage.react('👍'); // <-- FIXED EMOJI
        await voteMessage.react('👎'); // <-- FIXED EMOJI

        await interaction.reply({ content: 'Vote message created and vote started in-game!', ephemeral: true });
    }
});

// -------------------------------------------------------------------
//  REACTION (VOTE) HANDLER
// -------------------------------------------------------------------
client.on('messageReactionAdd', async (reaction, user) => {
    // Ignore bots
    if (user.bot) return;

    // Check if the reaction is on a message we care about (a vote embed)
    if (!reaction.message.embeds[0] || reaction.message.embeds[0].title !== 'A New Council Vote Has Started!') {
        return;
    }

    // Get the member who reacted
    const member = await reaction.message.guild.members.fetch(user.id);
    
    // Check if they have the council role
    if (!member.roles.cache.has(config.councilRoleId)) {
        // Not a council member, remove their reaction
        await reaction.users.remove(user.id);
        try {
            await user.send("You cannot vote as you do not have the 'City Council' role.");
        } catch (error) {
            console.log(`Could not DM ${user.tag}.`);
        }
        return;
    }

    // Check for a valid reaction
    // --- FIXED EMOJI LOGIC ---
    const vote = (reaction.emoji.name === '👍') ? 'yes' : (reaction.emoji.name === '👎') ? 'no' : null;
    if (!vote) {
        await reaction.users.remove(user.id); // Remove invalid reactions
        return;
    }
    // --- END OF FIX ---

    // Find the user's FiveM license from the database
    const link = await db.get('SELECT fivem_license FROM user_links WHERE discord_id = ?', user.id);
    if (!link) {
        await reaction.users.remove(user.id);
        try {
            await user.send("Your vote was not counted. Your Discord account is not linked to a FiveM license. Please contact an admin.");
        } catch (error) {
            console.log(`Could not DM ${user.tag}.`);
        }
        return;
    }

    // At this point, we have a valid council member, a valid vote, and a linked license.
    // Send the vote to the FiveM server.

    try {
        const fivemEndpoint = `${config.fivemServerUrl}/${config.fivemResourceName}/vote`;
        
        const response = await axios.post(fivemEndpoint, {
            secret: config.fivemBotSecret,
            identifier: link.fivem_license,
            vote: vote
        });

        if (response.status === 200) {
            console.log(`Successfully cast vote for ${user.tag} (${vote})`);
            await user.send(`Your vote for **${vote}** has been successfully cast in-game.`);
        }

    } catch (err) {
        console.error("Error sending vote to FiveM server:", err.message);
        if (err.response && err.response.data) {
            // If the server sent a specific error (like "No vote active")
            await user.send(`Your vote failed: ${err.response.data}`);
        } else {
            await user.send("Your vote failed: Could not connect to the FiveM server.");
        }
    }
});

// Login
client.login(config.botToken);