fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'TMG_Manic'
description 'Player inventory system providing a variety of features for storing and managing items'
version '1.2.0'

shared_scripts {
    '@tmg-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
    'config/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/drops.lua',
}

server_scripts {
    'server/main.lua',
    'server/functions.lua',
    'server/commands.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/main.css',
    'html/app.js',
    'html/images/*.png',
}

dependency 'tmg-weapons'