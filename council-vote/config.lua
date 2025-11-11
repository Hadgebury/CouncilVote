Config = {}

-- 1. Discord Webhook
-- Used by the server to POST messages *to* Discord (e.g., "Vote Started!")
Config.WebhookURL = "YOUR_DISCORD_WEBHOOK_URL_HERE"

-- 2. Bot Secret
-- A secret password you share between this script and your Discord bot.
-- This PREVENTS random people from faking votes by sending requests to your server.
Config.BotSecret = "CHANGE_ME_TO_A_VERY_LONG_RANDOM_STRING"

-- 3. ACE Permissions
-- The permission group (in your server.cfg) for people who can vote.
Config.VotePermissionGroup = "council.voter"

-- The permission group for people who can start/end votes.
Config.StartVotePermissionGroup = "council.leader"

-- 4. Vote Duration
-- How long a vote lasts, in seconds.
Config.VoteDuration = 300 -- 5 minutes