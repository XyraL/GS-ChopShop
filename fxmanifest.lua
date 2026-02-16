fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'GS-ChopShop'
author 'GooberScripts'
version '0.1.0'
description 'Chop Shop (Qbox/QBCore)'

shared_scripts {
  'config.lua',
  'shared/*.lua',
}

client_scripts {
  'client/*.lua',
}

server_scripts {
  'server/*.lua',
}

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/app.js',
}

dependencies {
  'oxmysql',
}
