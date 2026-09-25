fx_version 'cerulean'
game 'gta5'

name 'mri_Qvehicles'
description 'Cadastro e edicao de veiculos em runtime, como plugin do mri_Qadmin'
author 'MRI'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/**/*',
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
