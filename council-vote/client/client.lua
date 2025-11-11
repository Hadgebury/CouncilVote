-- Register the command for in-game players to cast their vote
RegisterCommand('castvote', function(source, args, raw)
    if #args == 0 then
        -- No vote provided
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 0 },
            args = { 'SYSTEM', 'Usage: /castvote [yes/no]' }
        })
        return
    end

    local vote = string.lower(args[1])

    -- Validate the vote
    if vote ~= 'yes' and vote ~= 'no' then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 0 },
            args = { 'SYSTEM', 'Invalid vote. Please use "yes" or "no".' }
        })
        return
    end

    -- Send the validated vote to the server
    TriggerServerEvent('council:castVote', vote)

end, false) -- false = not restricted