-- whip_evidence: evidence, gunshot residue, vehicle and weapon prints, lab for WHIP
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_evidence'
author 'LeSiiN'
description 'Forensics for WHIP: evidence, GSR, vehicle traces, weapon prints, labs'
version '4.3.0.1'

dependencies {
    'whip_core',
    'whip_evidence_assets',   -- the props live there, so this resource can restart safely
}
whip_requires '1.0'
whip_updates 'fozenistaken/whip_evidence'   -- whip_core compares `version` with this fork's latest GitHub release (upstream version plus a fourth number)

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config/config.lua',
    'config/colors.lua',
    'locales/en.lua',
    'locales/de.lua',
    'locales/fr.lua',
    'locales/es.lua',
    'locales/it.lua',
    'locales/pl.lua',
    'shared/locale.lua',
    'shared/util.lua',
    'shared/settings.lua',
    'shared/games.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/data.lua',
    'server/jobs.lua',
    'server/camera.lua',
    'server/evidence.lua',
    'server/gsr.lua',
    'server/body.lua',
    'server/bodies.lua',
    'server/vehicles.lua',
    'server/tracks.lua',
    'server/weapons.lua',
    'server/lab.lua',
    'server/photo.lua',
    'server/cases.lua',
    'server/admin.lua',
    'server/items.lua',
    'server/briefcase.lua',
    'server/main.lua',
}

client_scripts {
    '@whip_core/lib/cost.lua',   -- WhipCost: measures the scan overlay (/whipcost)
    'client/main.lua',
    'client/props.lua',
    'client/evidence.lua',
    'client/settings.lua',
    'client/scan.lua',
    'client/photo.lua',
    'client/games.lua',
    'client/labscreen.lua',
    'client/lockers.lua',
    'client/police.lua',
    'client/gsr.lua',
    'client/body.lua',
    'client/bodies.lua',
    'client/tracks.lua',
    'client/admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',   -- clipboard, photo viewer, minigames
    'html/games.js',     -- the forensic minigames
    'html/lab.html',     -- the lab monitor (DUI)
    'html/img/screen/*.png',
    'html/scan.html',   -- scan markers, cards, legend, photo view (DUI)
    'html/img/items/*.webp',
    'html/img/items/*.png',
    'html/img/tracks/*.png',   -- shoe prints and tyre tracks on the ground
    'html/*.css',              -- pure-whip-police theme
    'html/pure-*.js',
    'html/fonts/*.woff2',
    'html/img/*.webp',
}
