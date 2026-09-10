# 🏛️ FiveM & Discord City Council Voting System

A secure, real-time, cross-platform legislative voting system bridging your **FiveM GTA V server** and your **Discord community**. Council members can deliberate and vote seamlessly on active motions either in-game or directly from Discord with synchronized tallies and duplicate-vote prevention.

---

## 🌟 Key Features (v2.0 Upgrades)

* **Modern Discord Component Buttons**: Replaced legacy emoji reactions with interactive Discord Buttons (`[ 👍 Vote Yes ]`, `[ 👎 Vote No ]`, `[ ⚪ Abstain ]`). Provides instant, private ephemeral confirmations without relying on DMs.
* **Synchronized Cross-Platform Voting**: Votes cast in-game or on Discord update the same ballot. Double voting across platforms is prevented using verified FiveM license identifiers.
* **Abstain & Quorum Support**: Support for formal abstentions and configurable quorum requirements (`Config.MinimumVotes`).
* **Vote Changing**: Council members can change their ballot before the timer expires if enabled (`Config.AllowVoteChange`).
* **In-Game UX & Audio**: Plays GTA frontend sound effects and on-screen feed notifications when votes start, conclude, or are cast.
* **Chat Autocomplete**: Includes built-in `chat:addSuggestion` autocomplete hints for all in-game commands.
* **Hardened Security**: Server configuration and secrets are protected against client cache dumping.
* **Live Message Updates**: Automatically disables Discord voting buttons and posts final tallies with roll-call breakdowns when voting concludes.

---

## 📋 Command Reference

### In-Game Commands (FiveM)
| Command | Permission Required | Description |
| :--- | :--- | :--- |
| `/startvote [motion] [seconds]` | `council.leader` | Initiates a council vote across in-game and Discord. Duration is optional (defaults to config). |
| `/endvote` | `council.leader` | Immediately concludes and tallies the active vote early. |
| `/castvote [yes/no/abstain]` | `council.voter` | Casts or updates your vote on the active motion. |
| `/voteinfo` | Everyone | Displays the active motion, time remaining, and your cast ballot. |

### Discord Slash Commands
| Command | Permission Required | Description |
| :--- | :--- | :--- |
| `/startcouncilvote [question] [duration]` | Council Role / Admin | Starts a vote simultaneously on Discord and FiveM. |
| `/endcouncilvote` | Council Role / Admin | Concludes the active vote early and disables Discord buttons. |
| `/voteinfo` | Everyone | Checks status, time remaining, and live ballot count. |
| `/linkuser [user] [license]` | Manage Guild / Admin | Links a Discord user to their FiveM `license:xxxxxx`. |
| `/unlinkuser [user]` | Manage Guild / Admin | Removes a user's link from the database. |
| `/listcouncil` | Manage Guild / Admin | Displays a list of all linked council members. |

---

## 🛠️ Installation & Setup Guide

### Part 1: FiveM Resource Setup

1. Place the `FiveM_Resource` folder inside your server's `resources` directory (e.g., `resources/[standalone]/FiveM_Resource`).
2. Open `FiveM_Resource/config.lua` and configure your settings:
   ```lua
   -- Discord Webhook URL for vote announcements
   Config.WebhookURL = "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

   -- Shared secret between FiveM and your Discord bot (keep this private!)
   Config.BotSecret = "A_STRONG_RANDOM_SECRET_KEY_HERE"

   -- Permissions
   Config.VotePermissionGroup = "council.voter"
   Config.StartVotePermissionGroup = "council.leader"

   -- Mechanics
   Config.DefaultVoteDuration = 300   -- 5 minutes
   Config.AllowAbstain = true          -- Enable abstain option
   Config.AllowVoteChange = true       -- Allow changing vote before timer expires
   Config.MinimumVotes = 0             -- Quorum requirement (0 to disable)
   ```
3. Add the resource and ACE permissions to your `server.cfg`:
   ```cfg
   # Start the resource
   ensure FiveM_Resource

   # Council Leaders (Start & End Votes)
   add_ace group.admin council.leader allow
   add_ace group.moderator council.leader allow

   # Council Members (Cast Votes)
   add_ace group.admin council.voter allow
   add_ace group.moderator council.voter allow
   add_ace group.council_member council.voter allow

   # Assign players to groups via FiveM license
   add_principal identifier.license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx group.admin
   add_principal identifier.license:yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy group.council_member
   ```
4. **Network / Firewall**: Ensure incoming HTTP traffic to your FXServer port (e.g., `30120`) is reachable from the machine hosting your Discord bot.

---

### Part 2: Discord Bot Setup

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and create a new Application.
2. In the **Bot** tab:
   * Create a Bot and copy the **Bot Token**.
   * Under **Privileged Gateway Intents**, enable **Server Members Intent**.
3. In the **OAuth2 -> URL Generator** tab:
   * Select scopes: `bot` and `applications.commands`.
   * Bot permissions: `Send Messages`, `Embed Links`, `Manage Messages`, `Use Application Commands`.
   * Copy the generated invite link and authorize the bot into your Discord server.
4. Place the `Discord_Bot` folder on your server or VPS.
5. Open `Discord_Bot/config.json` and fill in your details:
   ```json
   {
     "botToken": "YOUR_DISCORD_BOT_TOKEN",
     "guildId": "YOUR_DISCORD_GUILD_SERVER_ID",
     "councilRoleId": "YOUR_COUNCIL_ROLE_ID",
     "adminRoleId": "YOUR_ADMIN_ROLE_ID",
     "fivemServerUrl": "http://YOUR_SERVER_IP:30120",
     "fivemResourceName": "FiveM_Resource",
     "fivemBotSecret": "A_STRONG_RANDOM_SECRET_KEY_HERE"
   }
   ```
   > **Note:** `fivemBotSecret` must match `Config.BotSecret` in `FiveM_Resource/config.lua`.

6. Install dependencies and start the bot:
   ```bash
   cd Discord_Bot
   npm install
   node bot.js
   ```
   *(For 24/7 production use, run with PM2: `pm2 start bot.js --name "council-bot"`)*

---

### Part 3: Linking Accounts

Council members must have their Discord account linked to their FiveM license to vote on Discord:

1. Retrieve the member's FiveM license (from server logs, database, or txAdmin).
2. An Admin runs the slash command in Discord:
   ```text
   /linkuser user:@CouncilMember license:license:1234567890abcdef1234567890abcdef12345678
   ```
3. Use `/listcouncil` to verify the registration.

---

## 🔒 Security Architecture

* **No Client Leaks**: `config.lua` is strictly registered under `server_scripts`. Client files never receive webhook URLs or secrets.
* **Shared Secret Authentication**: All incoming HTTP requests between Discord and FiveM require authentication against `Config.BotSecret`.
* **Standardized FXServer Endpoints**: Uses FXServer's native `SetHttpHandler` with `application/json` payloads and proper status code propagation.
* **Verified Identification**: Uses `GetPlayerIdentifierByType(source, 'license')` to guarantee consistent cross-platform identity matching.

---

## 📄 License & Attribution

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)** license.

### Terms Summary:
* ✅ **Free Use**: You are free to download, use, run, and adapt this system for your community or server.
* ❌ **Non-Commercial Only**: You may **NOT** sell, resell, lease, sub-license, or monetize this software or any derivatives. It cannot be sold on Tebex, Patreon, or bundled into paid server packages.
* ⚠️ **Mandatory Credit**: You **MUST** attribute and credit **Hadgebury** as the original creator in your documentation, repository, or visible credits—even if the code is refactored, modified, or tailored for specific frameworks.
* 🔄 **ShareAlike**: If you modify or adapt this project, your contributions must be distributed under the same license terms.

See the full [LICENSE](file:///c:/Users/rocki/Documents/GitHub/CouncilVote/LICENSE) file for complete legal details.