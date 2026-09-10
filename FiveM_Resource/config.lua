Config = {}

-- ===================================================================
--  SECURITY & BOT CREDENTIALS
-- ===================================================================

-- 1. Discord Webhook
-- Used by the FiveM server to send notifications & embeds to your Discord channel.
Config.WebhookURL = "YOUR_DISCORD_WEBHOOK_URL_HERE"

-- 2. Bot Secret
-- Shared secret authentication string between this FiveM server and your Discord bot.
-- Keep this long, secure, and private.
Config.BotSecret = "CHANGE_ME_TO_A_VERY_LONG_RANDOM_STRING"


-- ===================================================================
--  PERMISSIONS (ACE Permissions)
-- ===================================================================

-- The ACE permission group for members eligible to cast votes.
Config.VotePermissionGroup = "council.voter"

-- The ACE permission group for leaders authorized to start and conclude votes.
Config.StartVotePermissionGroup = "council.leader"


-- ===================================================================
--  VOTING MECHANICS & TIMING
-- ===================================================================

-- Default duration of a vote in seconds if not specified in the command (300 = 5 minutes).
Config.DefaultVoteDuration = 300

-- Allow voters to choose 'abstain' in addition to 'yes' and 'no'.
Config.AllowAbstain = true

-- Allow voters to change their vote before the timer expires.
Config.AllowVoteChange = true

-- Quorum / Minimum votes required for a vote outcome to be considered valid.
-- If total votes cast are less than this number, the motion fails due to lack of quorum.
-- Set to 0 to disable quorum requirements.
Config.MinimumVotes = 0


-- ===================================================================
--  USER EXPERIENCE & NOTIFICATIONS
-- ===================================================================

-- Play frontend sound effects when a vote starts, ends, or is cast.
Config.SoundEffects = true

-- If true, broadcasts a notification across the entire server every time an individual vote is cast.
-- Recommended: false to prevent spamming innocent players during a vote.
Config.BroadcastIndividualVotes = false

-- Display roll-call list of who voted what in the final results summary.
Config.ShowVoterNamesInResults = true