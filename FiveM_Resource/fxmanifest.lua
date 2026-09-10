fx_version 'cerulean'
games {
    'gta5'
}

author 'Hadgebury'
description 'Cross-platform In-Game and Discord Voting System'
version '1.2.0'
lua54 'yes'

-- Security Fix: config.lua contains the Discord Webhook URL and Bot Secret.
-- It MUST be a server_script so clients cannot dump secrets from cache.
server_scripts {
    'config.lua',
    'server/server.lua'
}

client_scripts {
    'client/client.lua'
}