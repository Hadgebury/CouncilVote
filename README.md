# 🏛️ FiveM & Discord Council Voting System

Welcome to the City Hall cross-platform voting system. This system allows authorized council members to vote on active motions either from within the FiveM server or directly from a Discord channel.

This guide is split into two sections:
1.  **Admin Installation Guide:** For server owners who need to set up the system.
2.  **User Guide:** For council members who need to link their accounts and vote.

---

## 1. Admin Installation Guide

Follow these steps precisely to install and configure the voting system. You will have two main folders: `FiveM_Resource` (which goes on your game server) and `Discord_Bot` (which goes on your hosting/VPS).

### Prerequisites
* A dedicated FiveM server with admin access.
* A Discord server with admin access.
* A place to host a 24/7 Node.js bot (e.g., a VPS or hosting service).
* Access to your server's firewall to open ports.

### Step 1: Install the FiveM Resource
1.  Take the entire `FiveM_Resource` folder and place it in your server's `resources` directory.
2.  You can rename `FiveM_Resource` to something else (e.g., `[council-vote]`), but be sure to use that name in `config.json` later.

3.  **Configure `FiveM_Resource/config.lua`:**
    * `Config.WebhookURL`: Create a Webhook in your Discord council channel and paste the URL here.
    * `Config.BotSecret`: Create a long, random, and secure password. You will need this for the Discord bot later.
    * `Config.VotePermissionGroup`: Set the ACE group for casting votes (e.g., `council.voter`).
    * `Config.StartVotePermissionGroup`: Set the ACE group for starting/ending votes (e.g., `council.leader`).

4.  **Edit your `server.cfg`:**
    * Add `ensure FiveM_Resource` (or whatever you named the folder).
    * Add `ensure webserver` (this is critical for the bot to communicate).
    * Add your ACE permissions. For example:
        ```cfg
        # Give leaders and admins the 'start vote' permission
        add_ace group.admin council.leader allow
        add_ace group.moderator council.leader allow

        # Give council members the 'cast vote' permission
        add_ace group.admin council.voter allow
        add_ace group.moderator council.voter allow
        add_ace group.council_member council.voter allow

        # Add players to the groups
        add_principal identifier.license:xxxxxx group.admin
        add_principal identifier.license:yyyyyy group.moderator
        add_principal identifier.license:zzzzzz group.council_member
        ```
5.  **Firewall:** Ensure your FiveM server's port (e.g., 30120) is open to incoming traffic so the Discord bot can send data to it.

### Step 2: Set Up the Discord Bot
1.  **Create Bot:** Go to the Discord Developer Portal, create a new application, and add a "Bot" to it.
2.  **Get Token:** Reset and copy the bot's Token.
3.  **Enable Intents:** In the "Bot" tab, enable both the **SERVER MEMBERS INTENT** and the **GUILD MESSAGE REACTIONS INTENT**.
4.  **Invite Bot:** Go to "OAuth2" -> "URL Generator". Select `bot` and `applications.commands`. Give it **Send Messages**, **Manage Messages**, and **Read Message History** permissions. Copy the generated URL to invite the bot to your server.
5.  **Get IDs:** Enable Developer Mode in Discord (Settings > Advanced).
    * Right-click your server icon -> "Copy ID" (this is `guildId`).
    * Right-click your City Council role -> "Copy ID" (this is `councilRoleId`).
    * Right-click your Admin role -> "Copy ID" (this is `adminRoleId`).

### Step 3: Configure & Run the Bot
1.  Place the entire `Discord_Bot` folder (containing `bot.js`, `package.json`, and `config.json`) on your hosting server or VPS.
2.  **Configure `Discord_Bot/config.json`:**
    * `botToken`: The token you copied from Step 2.
    * `guildId`: Your Discord server's ID.
    * `councilRoleId`: Your City Council role's ID.
    * `adminRoleId`: Your Admin role's ID.
    * `fivemServerUrl`: The public IP and port of your FiveM server (e.g., `http://123.45.67.89:30120`).
    * `fivemResourceName`: The name of the resource folder from Step 1 (e.g., `FiveM_Resource` or `council-vote`).
    * `fivemBotSecret`: The *exact same* secret password you set in the FiveM `config.lua`.
3.  **Install & Run:**
    * Open a terminal in the `Discord_Bot` folder.
    * Run `npm install` to install dependencies.
    * Run `node bot.js` to start the bot. (It's recommended to use a process manager like `pm2` to keep it running 24/7).

### Step 4: Final Check & Linking
1.  In your Discord server, use the `/linkuser` command to link your own admin account.
2.  You first need your FiveM license. You can find this in your server's logs or by using an admin tool.
3.  Run the command:
    `/linkuser user:@YourName license:license:123abcde...`

You are now ready. The system is live.

---

## 2. User Guide (For Council Members)

Here is how to use the voting system.

### 1. Linking Your Account (One-Time Setup)
Before you can vote, an Admin must link your Discord account to your FiveM character.

You cannot do this yourself. Please contact a server admin and provide them with your FiveM license. They will run a command to link you.

Until you are linked, your votes (both in-game and on Discord) will be rejected.

### 2. How to Vote
When a vote is started by a council leader, a message will appear in-game and in the official Discord channel.

**You can vote once from either location.**

* **To Vote In-Game:** Type `/castvote yes` or `/castvote no`
* **To Vote In-Discord:** React to the vote message in the channel using the **👍 (Yes)** or **👎 (No)** emoji.

Your first vote is the only one that counts. You cannot vote in-game and then change your vote on Discord (or vice-versa).

### 3. For Council Leaders (Starting/Ending Votes)
You have two ways to start a vote:

* **In-Game (Recommended):**
    `/startvote [The question you are voting on]`
    This will start the vote timer and post the message to Discord.

* **In-Discord:**
    `/startcouncilvote question:[The question you are voting on]`
    This will post the message to Discord and start the vote timer in-game.

To end any active vote early, type the following command **in-game**:
`/endvote`

This will immediately stop the vote, tally the results, and announce the outcome in-game and in Discord. If you do not end it early, the vote will automatically conclude when its timer runs out.