fx_version 'cerulean'
games {
'gta5'
}

author 'Hadgebury'
description 'Cross-platform In-Game and Discord Voting System'
version '1.0.0'
lua54 'yes'

shared_script 'config.lua'

server_scripts {
    'server/server.lua'
}

client_scripts {
    'client/client.lua'
}