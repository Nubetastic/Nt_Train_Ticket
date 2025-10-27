fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
author 'Nubetastic'
description 'Train ticket and train spawn system'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua',
    'client/tram.lua'
}

server_scripts {
    'server/server.lua',
    'server/tram_server.lua'
}

dependency 'rsg-core'
dependency 'rsg-menubase'
dependency 'ox_lib'