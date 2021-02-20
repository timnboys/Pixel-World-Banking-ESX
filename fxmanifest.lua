fx_version 'bodacious'
games {'gta5'}

server_scripts {
	'@mysql-async/lib/MySQL.lua',
    'config/main.lua',
    'server/main.lua',
}

client_scripts {
    'config/main.lua',
    'client/nui.lua',
    'client/main.lua',
}

ui_page 'nui/pw_index.html'

files {
    'nui/*',
    'nui/assets/*'
}