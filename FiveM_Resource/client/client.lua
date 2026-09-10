-- ===================================================================
--  HELPERS & NOTIFICATIONS
-- ===================================================================

local function ShowNotification(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawNotification(false, false)
end

-- Play GTA frontend sound effect
local function PlayAudioCue(soundType)
    if soundType == 'start' then
        PlaySoundFrontend(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", true)
    elseif soundType == 'end' then
        PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", true)
    elseif soundType == 'cast' then
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    elseif soundType == 'error' then
        PlaySoundFrontend(-1, "ERROR", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

-- ===================================================================
--  CHAT SUGGESTIONS
-- ===================================================================

local function RegisterSuggestions()
    TriggerEvent('chat:addSuggestion', '/castvote', 'Cast your vote on the active council motion.', {
        { name = 'vote', help = 'yes | no | abstain' }
    })
    TriggerEvent('chat:addSuggestion', '/voteinfo', 'View details and your status on the active council vote.')
    TriggerEvent('chat:addSuggestion', '/startvote', 'Council Leader: Start a new council vote.', {
        { name = 'question', help = 'The motion to vote on' },
        { name = 'duration', help = '[Optional] Duration in seconds (e.g. 180)' }
    })
    TriggerEvent('chat:addSuggestion', '/endvote', 'Council Leader: Conclude the active council vote immediately.')
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        RegisterSuggestions()
    end
end)

-- Also register suggestions on player spawn
AddEventHandler('playerSpawned', function()
    RegisterSuggestions()
end)

-- ===================================================================
--  CLIENT COMMANDS
-- ===================================================================

-- Command to cast vote
RegisterCommand('castvote', function(source, args, raw)
    if #args == 0 then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 0 },
            args = { 'SYSTEM', 'Usage: /castvote [yes/no/abstain]' }
        })
        PlayAudioCue('error')
        return
    end

    local vote = string.lower(args[1])

    if vote ~= 'yes' and vote ~= 'no' and vote ~= 'abstain' then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 0 },
            args = { 'SYSTEM', 'Invalid vote option. Please use "yes", "no", or "abstain".' }
        })
        PlayAudioCue('error')
        return
    end

    TriggerServerEvent('council:castVote', vote)
end, false)

-- Command to check current vote status
RegisterCommand('voteinfo', function()
    TriggerServerEvent('council:getVoteInfo')
end, false)

-- ===================================================================
--  CLIENT NET EVENTS
-- ===================================================================

-- Play sound cue triggered by server
RegisterNetEvent('council:playSound', function(soundType)
    PlayAudioCue(soundType)
end)

-- Display notification banner triggered by server
RegisterNetEvent('council:notify', function(message)
    ShowNotification(message)
end)