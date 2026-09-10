-- ===================================================================
--  STATE VARIABLES
-- ===================================================================

local isVoteActive = false
local voteQuestion = ""
local voteDuration = 300
local voteStartTime = 0
local voteEndTime = 0
local votes = {} -- Format: votes[license] = { vote = 'yes'|'no'|'abstain', name = string, platform = 'in-game'|'discord' }
local voteTimerToken = 0 -- Monotonic counter to invalidate old timeouts

-- ===================================================================
--  HELPER FUNCTIONS
-- ===================================================================

-- Safely get a player's FiveM license identifier
local function GetIdentifier(source)
    if not source or source == 0 then return nil end

    -- Preferred native in modern FXServer
    local license = GetPlayerIdentifierByType(source, 'license')
    if license and #license > 0 then
        if not string.match(license, '^license:') then
            license = 'license:' .. license
        end
        return license
    end

    -- Fallback: iterate identifiers
    local numIdentifiers = GetNumPlayerIdentifiers(source)
    for i = 0, numIdentifiers - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id and string.sub(id, 1, 8) == 'license:' then
            return id
        end
    end

    return nil
end

-- Helper: Check ACE permission
local function HasPermission(source, group)
    if source == 0 then return true end -- Server console always allowed
    return IsPlayerAceAllowed(source, group)
end

-- Count current votes
local function CountVotes()
    local yesCount, noCount, abstainCount = 0, 0, 0
    for _, data in pairs(votes) do
        if data.vote == 'yes' then
            yesCount = yesCount + 1
        elseif data.vote == 'no' then
            noCount = noCount + 1
        elseif data.vote == 'abstain' then
            abstainCount = abstainCount + 1
        end
    end
    return yesCount, noCount, abstainCount, (yesCount + noCount + abstainCount)
end

-- Forward declaration
local EndVote

-- ===================================================================
--  VOTE LIFECYCLE MANAGEMENT
-- ===================================================================

-- Start a council vote
local function StartVote(question, duration, starterName, starterPlatform)
    if isVoteActive then return false, "A vote is already active." end

    duration = tonumber(duration) or Config.DefaultVoteDuration or 300
    if duration < 10 then duration = 10 end -- Minimum 10 seconds

    isVoteActive = true
    voteQuestion = question
    voteDuration = duration
    voteStartTime = GetGameTimer()
    voteEndTime = voteStartTime + (duration * 1000)
    votes = {}

    voteTimerToken = voteTimerToken + 1
    local currentToken = voteTimerToken

    local minutesText = string.format("%.1f", duration / 60)
    if duration % 60 == 0 then
        minutesText = tostring(math.floor(duration / 60))
    end

    -- 1. Announce to In-Game Chat
    local announceMsg = string.format(
        "A new City Council vote has been called by %s (%s)!\n" ..
        "Motion: %s\n" ..
        "Options: /castvote yes | /castvote no" .. (Config.AllowAbstain and " | /castvote abstain" or "") .. "\n" ..
        "Time Remaining: %s minute(s) (%d seconds).",
        starterName or "City Official",
        starterPlatform or "City Hall",
        question,
        minutesText,
        duration
    )

    TriggerClientEvent('chat:addMessage', -1, {
        color = { 0, 200, 255 },
        multiline = true,
        args = { 'CITY HALL', announceMsg }
    })

    -- 2. Trigger audio cues & notifications
    if Config.SoundEffects then
        TriggerClientEvent('council:playSound', -1, 'start')
    end
    TriggerClientEvent('council:notify', -1, '~y~Council Vote Started!~s~ Type /castvote to vote.')

    -- 3. Post to Discord Webhook (if not already triggered directly by the Discord bot)
    if starterPlatform ~= 'Discord' and Config.WebhookURL and Config.WebhookURL ~= "YOUR_DISCORD_WEBHOOK_URL_HERE" then
        SendVoteEmbedToDiscord(question, duration, starterName)
    end

    -- 4. Set auto-conclusion timer
    SetTimeout(duration * 1000, function()
        if isVoteActive and voteTimerToken == currentToken then
            EndVote("Timer Expired")
        end
    end)

    return true, "Vote started successfully."
end

-- Conclude a vote
EndVote = function(reason)
    if not isVoteActive then return false, "No vote is currently active." end

    isVoteActive = false
    local yesCount, noCount, abstainCount, totalCount = CountVotes()

    -- Determine outcome & check quorum
    local outcome = "FAILED"
    local outcomeColor = 15158332 -- Red

    local quorumMet = true
    if Config.MinimumVotes and Config.MinimumVotes > 0 and totalCount < Config.MinimumVotes then
        quorumMet = false
        outcome = "FAILED (QUORUM NOT MET)"
        outcomeColor = 15105570 -- Orange
    else
        if yesCount > noCount then
            outcome = "PASSED"
            outcomeColor = 3066993 -- Green
        elseif noCount > yesCount then
            outcome = "FAILED"
            outcomeColor = 15158332 -- Red
        else
            outcome = "TIED"
            outcomeColor = 15844367 -- Gold / Yellow
        end
    end

    -- Format result summary
    local resultChat = string.format(
        "COUNCIL VOTE CONCLUDED!\n" ..
        "Motion: %s\n" ..
        "Results: Yes: %d | No: %d%s | Total: %d\n" ..
        (Config.MinimumVotes > 0 and string.format("Quorum Required: %d (%s)\n", Config.MinimumVotes, quorumMet and "Met" or "Not Met") or "") ..
        "Outcome: %s",
        voteQuestion,
        yesCount,
        noCount,
        Config.AllowAbstain and (" | Abstain: " .. abstainCount) or "",
        totalCount,
        outcome
    )

    -- 1. Broadcast in-game
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 0, 200, 255 },
        multiline = true,
        args = { 'CITY HALL', resultChat }
    })

    if Config.SoundEffects then
        TriggerClientEvent('council:playSound', -1, 'end')
    end
    TriggerClientEvent('council:notify', -1, string.format("~b~Council Vote Concluded:~s~ %s", outcome))

    -- 2. Send detailed results to Discord
    SendResultsEmbedToDiscord(voteQuestion, outcome, yesCount, noCount, abstainCount, totalCount, outcomeColor, quorumMet)

    -- 3. Reset state
    local concludedQuestion = voteQuestion
    voteQuestion = ""
    votes = {}

    return true, "Vote concluded: " .. outcome
end

-- ===================================================================
--  DISCORD WEBHOOK INTEGRATION
-- ===================================================================

function SendVoteEmbedToDiscord(question, duration, starterName)
    local payload = {
        embeds = {
            {
                title = "🏛️ City Council Vote Started",
                description = "**Motion Under Consideration:**\n" .. question,
                color = 3447003, -- Blue
                fields = {
                    { name = "Started By", value = starterName or "Council Official", inline = true },
                    { name = "Duration", value = string.format("%d seconds (%.1f mins)", duration, duration / 60), inline = true },
                    { name = "Voting Instructions", value = "Council members may vote in-game with `/castvote` or click the voting buttons below on Discord.", inline = false }
                },
                footer = { text = "City Hall Legislative Voting System" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }

    PerformHttpRequest(Config.WebhookURL, function(err, text, headers)
        if err ~= 200 and err ~= 204 then
            print('^1[Council Vote] Failed to send Discord webhook notice. HTTP Code: ' .. tostring(err) .. '^0')
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function SendResultsEmbedToDiscord(question, outcome, yesCount, noCount, abstainCount, totalCount, colorHex, quorumMet)
    if not Config.WebhookURL or Config.WebhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" then return end

    local fields = {
        { name = "Outcome", value = "**" .. outcome .. "**", inline = true },
        { name = "Total Ballots", value = tostring(totalCount), inline = true },
        { name = "Tally Breakdown", value = string.format("✅ Yes: **%d**\n❌ No: **%d**%s", yesCount, noCount, Config.AllowAbstain and ("\n⚪ Abstain: **" .. abstainCount .. "**") or ""), inline = false }
    }

    if Config.MinimumVotes and Config.MinimumVotes > 0 then
        table.insert(fields, { name = "Quorum Requirement", value = string.format("%d required (%s)", Config.MinimumVotes, quorumMet and "Met" or "Not Met"), inline = true })
    end

    if Config.ShowVoterNamesInResults and totalCount > 0 then
        local voterBreakdown = ""
        for _, data in pairs(votes) do
            local icon = (data.vote == 'yes' and '✅') or (data.vote == 'no' and '❌') or '⚪'
            voterBreakdown = voterBreakdown .. string.format("%s %s (%s)\n", icon, data.name or "Unknown", data.platform or "FiveM")
        end
        if #voterBreakdown > 1000 then
            voterBreakdown = string.sub(voterBreakdown, 1, 997) .. "..."
        end
        table.insert(fields, { name = "Roll Call", value = voterBreakdown, inline = false })
    end

    local payload = {
        embeds = {
            {
                title = "📜 Council Vote Concluded",
                description = "**Motion:**\n" .. question,
                color = colorHex,
                fields = fields,
                footer = { text = "City Hall Archives" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }

    PerformHttpRequest(Config.WebhookURL, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- ===================================================================
--  IN-GAME COMMANDS & EVENTS
-- ===================================================================

-- /startvote [question] [optional duration]
RegisterCommand('startvote', function(source, args, raw)
    local src = source

    if not HasPermission(src, Config.StartVotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You lack permission to initiate a council vote.' } })
        return
    end

    if isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'A vote is already currently active.' } })
        return
    end

    if #args == 0 then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'Usage: /startvote [Motion/Question] [Optional Duration in Seconds]' } })
        return
    end

    -- Check if the last argument is a numeric duration
    local duration = Config.DefaultVoteDuration or 300
    local lastArg = tonumber(args[#args])
    if lastArg and lastArg >= 10 and #args > 1 then
        duration = lastArg
        table.remove(args, #args)
    end

    local question = table.concat(args, " ")
    local starterName = (src == 0) and "Server Console" or GetPlayerName(src)

    StartVote(question, duration, starterName, "In-Game")
end, false)

-- /endvote: Conclude active vote early
RegisterCommand('endvote', function(source, args, raw)
    local src = source

    if not HasPermission(src, Config.StartVotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You lack permission to conclude a council vote.' } })
        return
    end

    if not isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'No vote is currently active.' } })
        return
    end

    EndVote("Manually concluded by " .. ((src == 0) and "Console" or GetPlayerName(src)))
end, false)

-- Event: In-game player casting vote
RegisterNetEvent('council:castVote', function(voteChoice)
    local src = source
    local identifier = GetIdentifier(src)

    if not isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'No council vote is currently active.' } })
        return
    end

    if not identifier then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'Could not verify your FiveM license.' } })
        return
    end

    if not HasPermission(src, Config.VotePermissionGroup) then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'SYSTEM', 'You do not have permission to vote in City Council.' } })
        return
    end

    voteChoice = string.lower(voteChoice or '')
    if voteChoice ~= 'yes' and voteChoice ~= 'no' and voteChoice ~= 'abstain' then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'Invalid vote option. Choose yes, no, or abstain.' } })
        return
    end

    if voteChoice == 'abstain' and not Config.AllowAbstain then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'Abstaining is disabled for this council vote.' } })
        return
    end

    local playerName = GetPlayerName(src)
    local isUpdate = (votes[identifier] ~= nil)

    if isUpdate and not Config.AllowVoteChange then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 100, 0 }, args = { 'SYSTEM', 'You have already voted on this motion and vote changing is disabled.' } })
        return
    end

    -- Store or update vote
    votes[identifier] = {
        vote = voteChoice,
        name = playerName,
        platform = 'In-Game'
    }

    local feedback = isUpdate and string.format("Your vote has been updated to: %s", voteChoice:upper()) or string.format("Your vote (%s) has been recorded.", voteChoice:upper())
    TriggerClientEvent('chat:addMessage', src, { color = { 0, 255, 100 }, args = { 'CITY HALL', feedback } })

    if Config.SoundEffects then
        TriggerClientEvent('council:playSound', src, 'cast')
    end

    if Config.BroadcastIndividualVotes then
        TriggerClientEvent('chat:addMessage', -1, { color = { 0, 200, 255 }, args = { 'CITY HALL', 'A council ballot was cast in-game.' } })
    end
end)

-- Event: Player requests vote status info
RegisterNetEvent('council:getVoteInfo', function()
    local src = source
    if not isVoteActive then
        TriggerClientEvent('chat:addMessage', src, { color = { 255, 200, 0 }, args = { 'CITY HALL', 'There is currently no active council vote.' } })
        return
    end

    local remaining = math.max(0, math.floor((voteEndTime - GetGameTimer()) / 1000))
    local identifier = GetIdentifier(src)
    local myVote = identifier and votes[identifier] and votes[identifier].vote or "Not yet voted"

    TriggerClientEvent('chat:addMessage', src, {
        color = { 0, 200, 255 },
        multiline = true,
        args = {
            'CITY HALL',
            string.format("Active Motion: %s\nTime Remaining: %d seconds\nYour Ballot: %s", voteQuestion, remaining, myVote:upper())
        }
    })
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName and isVoteActive then
        TriggerClientEvent('chat:addMessage', -1, { color = { 255, 100, 0 }, args = { 'CITY HALL', 'The active council vote was cancelled due to a system restart.' } })
    end
end)

-- ===================================================================
--  HTTP HANDLER (Discord Bot -> FiveM Server)
-- ===================================================================

SetHttpHandler(function(request, response)
    local path = request.path
    local method = request.method

    local function sendResponse(statusCode, data)
        response.writeHead(statusCode, {
            ["Content-Type"] = "application/json",
            ["Access-Control-Allow-Origin"] = "*"
        })
        if type(data) == "table" then
            response.send(json.encode(data))
        else
            response.send(tostring(data))
        end
    end

    -- Pre-flight CORS support
    if method == 'OPTIONS' then
        response.writeHead(200, {
            ["Access-Control-Allow-Origin"] = "*",
            ["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS",
            ["Access-Control-Allow-Headers"] = "Content-Type"
        })
        response.send('')
        return
    end

    -- Health / Status query
    if path == '/status' or path == '/health' then
        local yesCount, noCount, abstainCount, totalCount = CountVotes()
        local remaining = 0
        if isVoteActive then
            remaining = math.max(0, math.floor((voteEndTime - GetGameTimer()) / 1000))
        end
        sendResponse(200, {
            active = isVoteActive,
            question = voteQuestion,
            timeRemaining = remaining,
            duration = voteDuration,
            tally = { yes = yesCount, no = noCount, abstain = abstainCount, total = totalCount }
        })
        return
    end

    -- POST Routes
    if method == 'POST' then
        request.setDataHandler(function(rawBody)
            local ok, body = pcall(json.decode, rawBody or "")
            if not ok or not body then
                sendResponse(400, { success = false, message = "Malformed JSON request body." })
                return
            end

            -- Validate secret
            if not body.secret or body.secret ~= Config.BotSecret then
                sendResponse(403, { success = false, message = "Unauthorized: Invalid secret." })
                return
            end

            -- 1. Cast Vote from Discord
            if path == '/vote' then
                if not isVoteActive then
                    sendResponse(400, { success = false, message = "No vote is currently active." })
                    return
                end

                local identifier = body.identifier
                local voteChoice = string.lower(body.vote or '')
                local voterName = body.name or "Discord User"

                if not identifier or not voteChoice then
                    sendResponse(400, { success = false, message = "Missing identifier or vote choice." })
                    return
                end

                if voteChoice ~= 'yes' and voteChoice ~= 'no' and voteChoice ~= 'abstain' then
                    sendResponse(400, { success = false, message = "Invalid vote option. Must be yes, no, or abstain." })
                    return
                end

                if voteChoice == 'abstain' and not Config.AllowAbstain then
                    sendResponse(400, { success = false, message = "Abstaining is not permitted for this vote." })
                    return
                end

                local isUpdate = (votes[identifier] ~= nil)
                if isUpdate and not Config.AllowVoteChange then
                    sendResponse(409, { success = false, message = "You have already cast a vote on this motion." })
                    return
                end

                votes[identifier] = {
                    vote = voteChoice,
                    name = voterName,
                    platform = 'Discord'
                }

                if Config.BroadcastIndividualVotes then
                    TriggerClientEvent('chat:addMessage', -1, { color = { 88, 101, 242 }, args = { 'DISCORD', 'A council ballot was cast from Discord.' } })
                end

                local yesCount, noCount, abstainCount, totalCount = CountVotes()
                sendResponse(200, {
                    success = true,
                    message = isUpdate and "Vote updated successfully." or "Vote recorded successfully.",
                    tally = { yes = yesCount, no = noCount, abstain = abstainCount, total = totalCount }
                })
                return

            -- 2. Start Vote from Discord
            elseif path == '/start-vote' then
                if isVoteActive then
                    sendResponse(400, { success = false, message = "A vote is already currently active in-game." })
                    return
                end

                local question = body.question
                local duration = tonumber(body.duration) or Config.DefaultVoteDuration or 300
                local starterName = body.starterName or "Discord Council Member"

                if not question or #question == 0 then
                    sendResponse(400, { success = false, message = "Missing question string." })
                    return
                end

                local success, err = StartVote(question, duration, starterName, "Discord")
                if success then
                    sendResponse(200, { success = true, message = "Vote started successfully.", duration = duration })
                else
                    sendResponse(400, { success = false, message = err })
                end
                return

            -- 3. Conclude Vote from Discord
            elseif path == '/end-vote' then
                if not isVoteActive then
                    sendResponse(400, { success = false, message = "No vote is currently active." })
                    return
                end

                local requester = body.name or "Discord Admin"
                local success, msg = EndVote("Ended by " .. requester .. " via Discord")
                sendResponse(200, { success = true, message = msg })
                return

            else
                sendResponse(404, { success = false, message = "Endpoint not found." })
                return
            end
        end)
    else
        sendResponse(405, { success = false, message = "Method Not Allowed." })
    end
end)
