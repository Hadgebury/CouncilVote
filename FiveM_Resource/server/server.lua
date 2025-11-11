-- Vote State Variables
local isVoteActive = false
local voteQuestion = ""
local voteEndTime = 0
local votes = {} -- Stores votes, e.g., votes["license:xxxxx"] = "yes"
local discordMessageId = nil -- Stores the ID of the bot's message

-- Helper: Get a player's license identifier
local function GetIdentifier(source)
    return GetPlayerIdentifier(source, 0) -- 0 = license
end

-- Helper: Check ACE permission
local function HasPermission(source, group)
    return IsPlayerAceAllowed(source, group)
end

-------------------------------------------------------------------
-- 1. COMMANDS (Start / End Vote)
-------------------------------------------------------------------

-- Command to START a vote
RegisterCommand('startvote', function(source, args, raw)
    local src = source

    if not HasPermission(src, Config.StartVotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You do not have permission to start a vote.' } })
        return
    end

    if isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'A vote is already active.' } })
        return
    end

    local question = table.concat(args, " ")
    if #question == 0 then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'Usage: /startvote [Question]' } })
        return
    end

    -- Initialize vote
    isVoteActive = true
    voteQuestion = question
    votes = {} -- Clear old votes
    voteEndTime = GetGameTimer() + (Config.VoteDuration * 1000)

    -- Announce in-game
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 0, 200, 255 },
        multiline = true,
        args = { 'CITY HALL', "A new vote has started!\nQuestion: " .. question .. "\nType /castvote yes or /castvote no to vote. You have " .. (Config.VoteDuration / 60) .. " minutes." }
    })

    -- Announce on Discord
    -- This sends the webhook, but a *real bot* is needed to get the message ID back
    SendVoteToDiscord(question)

    -- Start timer to end the vote
    SetTimeout(Config.VoteDuration * 1000, EndVote)

end, false) -- 'false' because we do the permission check ourselves

-- Command to MANUALLY END a vote
RegisterCommand('endvote', function(source, args, raw)
    local src = source
    if not HasPermission(src, Config.StartVotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You do not have permission to end the vote.' } })
        return
    end

    if not isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'No vote is active.' } })
        return
    end

    EndVote()
end, false)

-------------------------------------------------------------------
-- 2. VOTING LOGIC
-------------------------------------------------------------------

-- Receives a vote from a client
RegisterNetEvent('council:castVote', function(vote)
    local src = source
    local identifier = GetIdentifier(src)

    if not isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'No vote is currently active.' } })
        return
    end

    if not HasPermission(src, Config.VotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You do not have permission to vote.' } })
        return
    end

    if votes[identifier] then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'You have already voted on this matter.' } })
        return
    end

    -- Cast the vote
    votes[identifier] = vote
    TriggerClientEvent('chat:addMessage', src, { color = { 0, 255, 0 }, args = { 'SYSTEM', 'Your vote (' .. vote .. ') has been cast.' } })

    -- Announce (anonymously)
    TriggerClientEvent('chat:addMessage', -1, { color = { 0, 200, 255 }, args = { 'CITY HALL', 'A new vote has been cast in-game.' } })
end)

-- Function to end the vote (called by timer or command)
function EndVote()
    if not isVoteActive then return end

    isVoteActive = false
    local yesVotes = 0
    local noVotes = 0

    -- Tally votes
    for identifier, vote in pairs(votes) do
        if vote == 'yes' then
            yesVotes = yesVotes + 1
        elseif vote == 'no' then
            noVotes = noVotes + 1
        end
    end

    local resultMessage = "VOTE CONCLUDED!\nQuestion: " .. voteQuestion .. "\n\nResults:\nYes: " .. yesVotes .. "\nNo: " .. noVotes
    local outcome = (yesVotes > noVotes) and "PASSED" or "FAILED"
    if yesVotes == noVotes then outcome = "TIED" end
    resultMessage = resultMessage .. "\n\nOutcome: **" .. outcome .. "**"

    -- Announce results in-game
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 0, 200, 255 },
        multiline = true,
        args = { 'CITY HALL', resultMessage }
    })

    -- Announce results on Discord
    SendResultsToDiscord(resultMessage)

    -- Clear data
    voteQuestion = ""
    votes = {}
    discordMessageId = nil
end

-------------------------------------------------------------------
-- 3. DISCORD COMMUNICATION (Server -> Discord)
-------------------------------------------------------------------

-- Sends the "Vote Started" message to your Discord webhook
function SendVoteToDiscord(question)
    local payload = {
        embeds = {
            {
                title = "New City Council Vote Started!",
                description = "**Question:**\n" .. question,
                color = 3447003, -- Blue
                footer = { text = "Council members may vote in-game or via Discord." }
            }
        }
    }
    
    -- This just "fires and forgets".
    PerformHttpRequest(Config.WebhookURL, function(err, text, headers)
        if err ~= 200 then
            print('^1[Council Vote] Could not send "Vote Started" message to Discord webhook.^0')
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- Sends the "Vote Ended" message to your Discord webhook
function SendResultsToDiscord(resultMessage)
    local payload = {
        embeds = {
            {
                title = "Vote Concluded",
                description = resultMessage,
                color = (string.find(resultMessage, "PASSED") and 3066993) or 15158332 -- Green or Red
            }
        }
    }
    PerformHttpRequest(Config.WebhookURL, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-------------------------------------------------------------------
-- 4. DISCORD COMMUNICATION (Discord -> Server)
-------------------------------------------------------------------

-- Your Discord bot will send a POST request to this endpoint.
-- Endpoint URL: http://YOUR_SERVER_IP:PORT/resource_name/vote
RegisterHttpHandler('vote', function(request, response)
    
    -- 1. Decode the request from the bot
    local body = json.decode(request.body)
    if not body then
        response.send(400, 'Invalid request.')
        return
    end

    -- 2. Check for the shared secret
    if not body.secret or body.secret ~= Config.BotSecret then
        response.send(403, 'Invalid secret.') -- 403 Forbidden
        return
    end

    -- 3. Check if a vote is active
    if not isVoteActive then
        response.send(400, 'No vote active.')
        return
    end

    -- 4. Get data from bot
    -- Your bot *must* send the player's FiveM license
    local identifier = body.identifier -- e.g., "license:1234abcd..."
    local vote = body.vote -- e.g., "yes" or "no"

    if not identifier or not vote then
        response.send(400, 'Missing identifier or vote.')
        return
    end

    -- 5. Check if already voted
    if votes[identifier] then
        response.send(200, 'Vote already cast.') -- 200 OK, just ignore
        return
    end

    -- 6. Cast the vote
    votes[identifier] = vote
    
    -- Announce in-game that a Discord vote was cast
    TriggerClientEvent('chat:addMessage', -1, { color = { 88, 101, 242 }, args = { 'DISCORD', 'A vote was cast from Discord.' } })

    -- 7. Send "OK" back to the bot
    response.send(200, 'Vote cast successfully.')
end)

-- This  handler allows the bot to START a vote
RegisterHttpHandler('start-vote', function(request, response)
    if isVoteActive then
        response.send(400, 'A vote is already active.')
        return
    end

    local body = json.decode(request.body)
    if not body or not body.secret or body.secret ~= Config.BotSecret then
        response.send(403, 'Invalid secret.')
        return
    end

    local question = body.question
    if not question or #question == 0 then
        response.send(400, 'Missing question.')
        return
    end

    -- Manually trigger the vote start logic
    isVoteActive = true
    voteQuestion = question
    votes = {} -- Clear old votes
    voteEndTime = GetGameTimer() + (Config.VoteDuration * 1000)

    -- Announce in-game
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 0, 200, 255 },
        multiline = true,
        args = { 'CITY HALL', "A new vote has started from Discord!\nQuestion: " .. question .. "\nType /castvote yes or /castvote no. You have " .. (Config.VoteDuration / 60) .. " minutes." }
    })
    
    -- Start timer to end the vote
    SetTimeout(Config.VoteDuration * 1000, EndVote)

    response.send(200, 'Vote started successfully.')
end)
