-- Client: scan mode. Aim a flashlight or hold the camera item:
--  * every piece of evidence in view gets a numbered marker tag (the number is the same for everyone)
--  * the one you aim at gets a card with details, cars with traces get a card (V1, V2, ...)
--  * police see shot trajectories: a line from a casing to the bullet of the same shot
--  * with the camera: a legend of everything in the picture, and a key that takes a photo (an item)
--  * a key cycles a filter (all, blood, casings, ...)
-- One DUI browser draws everything (atlas, painted only on change). Nothing runs per frame unless there is something to draw.
WhipEvidence.Scan = {}

local FLASHLIGHT = GetHashKey('WEAPON_FLASHLIGHT')
local MAX_MARKERS, CAR_CARDS, LEGEND_ROWS, MAX_LINES = 60, 3, 12, 40
local TAG_LIFT = 0.4          -- metres between evidence and the bottom of its tag
local cameraUp = false        -- told by the server while the WHIP camera item is in hand
local cardsHidden = false     -- camera: the big card of the aimed-at trace off (K); markers, legend and text stay
local scanning = false
local worldHidden = false     -- WHIP's clean screen (filming) hides world UI
local markers, focus, cars, lines, lasers = {}, nil, {}, {}, {}
local picture = { ids = {}, cars = {} }   -- what a photo would show right now
local legendOn = false
-- the player's layout (client/settings.lua), read every 500 ms
local layout = { legend = true, side = 'right', top = 0.08, width = 0.2, tag = 1.0, card = 1.0, lines = true }

local function readLayout()
    layout.legend = WhipEvidence.ui('legend') ~= false
    layout.side = WhipEvidence.ui('legendSide') == 'left' and 'left' or 'right'
    layout.top = (tonumber(WhipEvidence.ui('legendTop')) or 8) / 100
    layout.width = (tonumber(WhipEvidence.ui('legendSize')) or 20) / 100
    layout.tag = (tonumber(WhipEvidence.ui('tagSize')) or 100) / 100
    layout.card = (tonumber(WhipEvidence.ui('cardSize')) or 100) / 100
    layout.lines = WhipEvidence.ui('trajectories') ~= false
end
local shooting = false        -- a screenshot is being taken: legend and card stay out of the picture
local highlight = {}          -- [id] = until (GetGameTimer): markers that blink (missing photos)
local lastSummary

-- phase keys are the old names; shown as blue = too fresh, green = ready, red = gone soon
local PHASE = {
    green  = { key = 'phase_fresh', i = 0, color = 'blue' },
    yellow = { key = 'phase_ready', i = 1, color = 'green' },
    red    = { key = 'phase_old',   i = 2, color = 'red' },
}

local FILTERS = {
    { key = 'all',              label = 'filter_all' },
    { key = 'blood',            label = 'filter_blood' },
    { key = 'casing',           label = 'filter_casing' },
    { key = 'bullet',           label = 'filter_bullet' },
    { key = 'fingerprint',      label = 'filter_fingerprint' },
    { key = 'vehicle_fragment', label = 'filter_fragment' },
    { key = 'tracks',           label = 'filter_tracks' },
    { key = 'vehicles',         label = 'filter_vehicles' },
    { key = 'bodies',           label = 'filter_bodies' },
}
local filter = 1

local function passes(kind)
    local f = FILTERS[filter].key
    return f == 'all' or f == kind or (f == 'tracks' and (kind == 'shoeprint' or kind == 'tyre_track'))
end

---------------------------------------------------------------- DUI atlas (one browser for everything)

local PAGE = ('nui://%s/html/scan.html'):format(WhipEvidence.Res)
local TXD, TEX = 'whip_evidence_scan', 'atlas'
local W, H = 1024, 1024
local IDLE_MS = 60000
local dui, up, waiting, painted, lastUsed = nil, false, {}, {}, 0

local resetMarks   -- set further down: the whole-marker cells are gone with the page

local function release()
    if dui then DestroyDui(dui) end
    dui, up, waiting, painted = nil, false, {}, {}
    if resetMarks then resetMarks() end
end

local function checkIdle()
    if not dui then return end
    local left = lastUsed + IDLE_MS - GetGameTimer()
    if left > 0 then SetTimeout(left, checkIdle) else release() end
end

local function ensure()
    lastUsed = GetGameTimer()
    if dui then return end
    local ok, handle = pcall(CreateDui, PAGE, W, H)
    if not ok or not handle then return end
    dui = handle
    CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(TXD), TEX, GetDuiHandle(dui))
    local mine = dui
    CreateThread(function()
        local untilAt = GetGameTimer() + 10000
        while dui == mine and not IsDuiAvailable(mine) and GetGameTimer() < untilAt do Wait(50) end
        if dui ~= mine then return end
        Wait(250)   -- a fresh page can miss its very first message
        up = true
        for _, m in ipairs(waiting) do SendDuiMessage(dui, json.encode(m)) end
        waiting = {}
    end)
    SetTimeout(IDLE_MS, checkIdle)
end

-- Paints one cell (0-5, 'legend' or 'photo'), only when its content changed
local function paint(cell, data)
    data.action, data.cell = 'paint', cell
    local text = json.encode(data)
    if painted[cell] == text then return end
    painted[cell] = text
    if up then SendDuiMessage(dui, text) else waiting[#waiting + 1] = data end
end

-- UVs (see the layout in html/scan.html)
local function uv(x, y, w, h)
    return x / W, y / H, (x + w) / W, (y + h) / H
end
local function cardUv(cell)
    return uv((cell % 2) * 256 + 8, math.floor(cell / 2) * 128 + 8, 240, 112)
end
local LEGEND_UV = { uv(512, 0, 512, 640) }
local BADGE_UV  = { uv(512 + 6 * 64, 640, 64, 64) }   -- camera badge: already photographed
local ARROW_UV  = { uv(512 + 7 * 64, 640, 64, 64) }   -- blood trail: the way the person walked

-- Whole markers painted on the atlas (tag, number, badge in one picture): one sprite per marker per frame.
-- A cell stays with its marker while it is in view; a new cell is used only once the page has painted it.
local MARK_CELLS = 64
local MARK_UV = {}
for i = 0, MARK_CELLS - 1 do MARK_UV[i] = { uv((i % 8) * 64, 384 + math.floor(i / 8) * 80, 64, 80) } end
local markCell, markSeen, markReady = {}, {}, {}   -- [key] = cell, last rebuild it was used, time it can be drawn
local freeCells = {}
for i = MARK_CELLS - 1, 0, -1 do freeCells[#freeCells + 1] = i end
local markMsg = { action = 'marks', list = {} }

local function markKey(m)
    local k = m.body and 'L' or (m.car and 'V' or m.phase)
    return ('%s:%d:%d'):format(k, m.no or 0, m.photo and 1 or 0)
end

resetMarks = function()
    markCell, markSeen, markReady, freeCells = {}, {}, {}, {}
    for i = MARK_CELLS - 1, 0, -1 do freeCells[#freeCells + 1] = i end
end

-- once per rebuild: give every marker in the list its cell (painted once), free cells not used for 3 s
local function assignMarks(list, n, rebuildNo)
    if not (dui and up) then
        for i = 1, n do list[i].cellUv = nil end   -- drawn from parts until the page is there
        return
    end
    local now = GetGameTimer()
    local out, nOut = markMsg.list, 0
    for i = 1, n do
        local m = list[i]
        local key = m.markKey
        if not key or m.markKeyOf ~= (m.no or 0) * 10 + (m.photo and 1 or 0) + (m.phase or 0) * 100 then
            key = markKey(m)
            m.markKey, m.markKeyOf = key, (m.no or 0) * 10 + (m.photo and 1 or 0) + (m.phase or 0) * 100
        end
        local cell = markCell[key]
        if not cell and #freeCells > 0 then
            cell = table.remove(freeCells)
            markCell[key], markReady[key] = cell, now + 400   -- the page needs a moment to paint it
            local text = m.body and ('L' .. m.no) or (m.car and ('V' .. m.no) or tostring(m.no))
            nOut = nOut + 1
            out[nOut] = { i = cell, k = m.body and 'L' or (m.car and 'V' or m.phase), t = text, p = m.photo == true }
        end
        markSeen[key] = rebuildNo
        m.cellUv = (cell and now >= markReady[key]) and MARK_UV[cell] or nil
    end
    for key, cell in pairs(markCell) do
        if rebuildNo - (markSeen[key] or 0) > 6 then
            markCell[key], markSeen[key], markReady[key] = nil, nil, nil
            freeCells[#freeCells + 1] = cell
        end
    end
    if nOut > 0 and dui then
        for i = nOut + 1, #out do out[i] = nil end
        if up then SendDuiMessage(dui, json.encode(markMsg)) end
    end
end

-- GTA heading (0 = north, 90 = west) as a compass word
local COMPASS = { 'N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE' }
local function compass(h)
    return COMPASS[math.floor(((h % 360) + 22.5) / 45) % 8 + 1]
end
local TAG_UV, RING_UV, DIGIT_UV = {}, {}, {}
for i = 0, 2 do
    TAG_UV[i] = { uv(512 + i * 64, 704, 64, 80) }
    RING_UV[i] = { uv(512 + (i + 3) * 64, 640, 64, 64) }
end
for d = 0, 9 do DIGIT_UV[d] = { uv(512 + d * 32, 784, 32, 64) } end
local BODY_TAG_UV = { uv(512 + 3 * 64, 704, 64, 80) }   -- bodies: purple tag
local LETTER_L_UV = { uv(512 + 10 * 32, 784, 32, 64) }
local CAR_TAG_UV = { uv(512 + 4 * 64, 704, 64, 80) }    -- vehicles: blue tag
local LETTER_V_UV = { uv(512 + 11 * 32, 784, 32, 64) }

---------------------------------------------------------------- Keys

local function keyLabel(command, fallback)
    local ok, label = pcall(GetControlInstructionalButton, 0, joaat(command) | 0x80000000, true)
    if ok and type(label) == 'string' and label:sub(1, 2) == 't_' then return label:sub(3) end
    return fallback
end

-- On a controller: the button the action sits on ('LB+D-pad left'), else the keyboard key
local padOn, padAt = false, -10000
AddEventHandler('whip_core:pad:deviceChanged', function() padAt = -10000 end)
local function keyFor(padId, command, key)
    local now = GetGameTimer()
    if now - padAt > 5000 then padOn, padAt = Whip.core:IsControllerActive() == true, now end
    if padOn then
        local _, _, name = Whip.core:GetPadActionButton(padId)
        if name then return name end
    end
    return keyLabel(command, key)
end

local function hint()
    local text = L('hint_filter', keyFor('evidence_filter', 'whip_evidence_filter', Config.ScanKeys.Filter), L(FILTERS[filter].label))
    if cameraUp then
        text = text .. L('hint_photo', keyFor('evidence_photo', 'whip_evidence_photo', Config.ScanKeys.Photo))
        text = text .. L(cardsHidden and 'hint_card_on' or 'hint_card_off', keyFor('evidence_cards', 'whip_evidence_cards', Config.ScanKeys.Cards or 'K'))
    end
    return text
end

-- WHIP's camera viewfinder holds the game input (IsGameInputFree() is false while it is up),
-- so with the camera in hand only the pause menu stops the keys. Typing never reaches key mappings.
local function keysAllowed()
    if cameraUp then return not IsPauseMenuActive() end
    return Whip.core:IsGameInputFree()
end

-- A key can arrive twice (key mapping and the camera fallback below): only once per 300 ms
local lastPress = {}
local function once(what)
    local now = GetGameTimer()
    if lastPress[what] and now - lastPress[what] < 300 then return false end
    lastPress[what] = now
    return true
end

local function nextFilter()
    if not scanning or not keysAllowed() or not once('filter') then return end
    filter = filter % #FILTERS + 1
    PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function flash()
    CreateThread(function()
        local untilAt = GetGameTimer() + 180
        while GetGameTimer() < untilAt do
            local a = math.floor(220 * (untilAt - GetGameTimer()) / 180)
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 255, 255, a)
            Wait(0)
        end
    end)
end

-- A real photo: WHIP's TakeScreenshot (the markers are in it, the legend and card are not).
-- The server makes the item, then asks for the picture (whip_evidence:client:photoUpload).
local snapping, pendingPicture = false, nil

local function takePhoto()
    if not cameraUp or not scanning or not keysAllowed() or not once('photo') or snapping then return end
    if not WhipEvidence.can('evidence_photo') then return WhipEvidence.notify(L('photo_rank'), 'info') end
    if #picture.ids == 0 and #picture.cars == 0 and #(picture.bodies or {}) == 0 then
        return WhipEvidence.notify(L('photo_nothing'), 'info')
    end
    snapping = true
    local ids, carNets, bodyIds = { table.unpack(picture.ids) }, picture.cars, picture.bodies or {}
    local models = picture.models or {}
    local street = WhipEvidence.street(GetEntityCoords(PlayerPedId()))
    CreateThread(function()
        PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
        shooting = true
        Wait(0)
        Wait(0)
        local shot = { format = Config.Photo.Format == 'jpg' and 'jpg' or 'webp', quality = Config.Photo.Quality }
        if (Config.Photo.Width or 0) > 0 then shot.width = Config.Photo.Width end   -- 0: full screen, sharpest
        local image = Whip.core:TakeScreenshot(shot)
        shooting = false
        flash()
        pendingPicture = type(image) == 'string' and image or nil
        if not pendingPicture then WhipEvidence.notify(L('photo_failed'), 'warning') end
        TriggerServerEvent('whip_evidence:photo', ids, carNets, street, pendingPicture ~= nil, bodyIds, models)
        snapping = false
    end)
end

-- The picture goes in small parts with a short pause: one big event gets you kicked
RegisterNetEvent('whip_evidence:client:photoUpload', function(photoId)
    local image = pendingPicture
    pendingPicture = nil
    if not image then return end
    CreateThread(function()
        local size = WhipEvidence.PhotoChunk
        local parts = math.ceil(#image / size)
        TriggerServerEvent('whip_evidence:photoBegin', photoId, parts, #image)
        Wait(200)
        for i = 1, parts do
            TriggerServerEvent('whip_evidence:photoPart', photoId, i, image:sub((i - 1) * size + 1, i * size))
            Wait(80)   -- about 125 KB/s: never floods the connection
        end
    end)
end)

-- Blink these markers for a while (e.g. evidence that still needs a photo)
function WhipEvidence.Scan.highlight(ids, seconds)
    local untilAt = GetGameTimer() + (seconds or 30) * 1000
    for _, id in ipairs(ids) do highlight[id] = untilAt end
end

RegisterCommand('whip_evidence_filter', nextFilter, false)
RegisterKeyMapping('whip_evidence_filter', L('key_filter'), 'keyboard', Config.ScanKeys.Filter)
RegisterCommand('whip_evidence_photo', takePhoto, false)
RegisterKeyMapping('whip_evidence_photo', L('key_photo'), 'keyboard', Config.ScanKeys.Photo)

-- Camera in hand: hide the big card of the aimed-at trace for a clean picture (markers, legend and text stay)
local cardsPressedAt = 0
local function toggleCards()
    if not cameraUp or not keysAllowed() then return end
    local now = GetGameTimer()
    if now - cardsPressedAt < 250 then return end   -- key mapping and the camera fallback in the same frame
    cardsPressedAt = now
    cardsHidden = not cardsHidden
    lastSummary = nil   -- the hint in the text line changes
end
RegisterCommand('whip_evidence_cards', toggleCards, false)
RegisterKeyMapping('whip_evidence_cards', L('key_cards'), 'keyboard', Config.ScanKeys.Cards or 'K')

-- Controller: the same two on WHIP's pad buttons (movable on the pause menu's Controller screen).
-- Ready only while scanning (photo: camera up), otherwise the buttons stay GTA's.
local padReady = { evidence_filter = false, evidence_photo = false, evidence_cards = false }
Whip.register(function()
    padReady = { evidence_filter = false, evidence_photo = false, evidence_cards = false }
    Whip.core:RegisterPadAction('evidence_cards', { label = L('pad_cards'), slot = 'lb_dpad_up', menus = true, ready = false,
        onPress = function() toggleCards() end })
    Whip.core:RegisterPadAction('evidence_filter', { label = L('pad_filter'), slot = 'lb_dpad_left', menus = true, ready = false,
        onPress = function() nextFilter() end })
    Whip.core:RegisterPadAction('evidence_photo', { label = L('pad_photo'), slot = 'lb_dpad_right', menus = true, ready = false,
        onPress = function() takePhoto() end })
end)

local function padActions(filterOn, photoOn)
    for id, on in pairs({ evidence_filter = filterOn, evidence_photo = photoOn, evidence_cards = photoOn }) do
        if padReady[id] ~= on then
            padReady[id] = on
            Whip.core:SetPadActionReady(id, on)
        end
    end
end

-- Fallback while the viewfinder is up: read G and H as game controls too (they still report while
-- disabled). Only while the binding is still G / H, so a player who rebinds gets just their key.
local KEY_CONTROLS = { G = { 47, 58 }, H = { 74, 304 }, K = { 311 } }
local bound = { filter = nil, photo = nil, cards = nil, checkedAt = 0 }

local function pressed(key)
    local list = KEY_CONTROLS[key]
    if not list then return false end
    for i = 1, #list do
        if IsDisabledControlJustPressed(0, list[i]) or IsControlJustPressed(0, list[i]) then return true end
    end
    return false
end

local function cameraKeys()
    local now = GetGameTimer()
    if now - bound.checkedAt > 2000 then
        bound.checkedAt = now
        bound.filter = keyLabel('whip_evidence_filter', Config.ScanKeys.Filter)
        bound.photo = keyLabel('whip_evidence_photo', Config.ScanKeys.Photo)
        bound.cards = keyLabel('whip_evidence_cards', Config.ScanKeys.Cards or 'K')
    end
    if pressed(bound.filter) then nextFilter() end
    if pressed(bound.photo) then takePhoto() end
    if pressed(bound.cards) then toggleCards() end
end

---------------------------------------------------------------- What to show

RegisterNetEvent('whip_evidence:client:camera', function(on)
    cameraUp = on == true
    if not cameraUp then cardsHidden = false end   -- camera away: everything back
end)

AddEventHandler('whip_core:player:logout', function()
    cameraUp = false
end)

AddEventHandler('whip_core:ui:cleanScreen', function(e)
    worldHidden = type(e) == 'table' and e.on == true and e.world == true
end)

-- a setting was changed: read the layout on the next rebuild
local lastLayout = 0
function WhipEvidence.Scan.layoutChanged() lastLayout = -100000 end

function WhipEvidence.Scan.active()
    return scanning
end

-- Only on-duty police with the scan permission get the scan (markers, cards, legend, trajectories, photos)
local function detect()
    if not WhipEvidence.can('evidence_scan') then return false end
    if cameraUp then return true end
    local ped = PlayerPedId()
    if GetSelectedPedWeapon(ped) == FLASHLIGHT and IsPlayerFreeAiming(PlayerId()) then return true end
    return IsPedUsingScenario(ped, 'WORLD_HUMAN_PAPARAZZI')
end

local function minutes(ms)
    local m = math.floor(ms / 60000)
    if m < 1 then return '<1 min' end
    return ('%d min'):format(m)
end

local function metres(d)
    return ('%d m'):format(math.floor(d + 0.5))
end

-- Card for the aimed-at evidence. Police on duty see everything, others only type and state.
local function evidenceCard(ev, dist, police)
    local st = PHASE[ev.phase] or PHASE.yellow
    local chips = { { text = L(st.key), color = st.color } }
    if police then
        local now = GetGameTimer()
        local age = WhipEvidence.ageWords((now - (ev.bornAt or now)) / 1000)
        if age then chips[#chips + 1] = { text = age } end
        -- the time left would give the age away: only with exact ages
        if (Config.AgeShown or 'rough') == 'exact' then
            chips[#chips + 1] = { text = L('chip_left', minutes(math.max(0, (ev.endsAt or now) - now))) }
        end
        if ev.fails and ev.fails > 0 then chips[#chips + 1] = { text = L('chip_failed', ev.fails, Config.MaxFails), color = 'red' } end
        if ev.laser then chips[#chips + 1] = { text = L('chip_laser'), color = 'red' } end
        if ev.bloody then chips[#chips + 1] = { text = L('chip_bloody'), color = 'red' } end
        chips[#chips + 1] = ev.photo and { text = L('chip_photo'), color = 'green' } or { text = L('chip_no_photo'), color = 'yellow' }
        if ev.dir then chips[#chips + 1] = { text = L('chip_trail', compass(ev.dir)), color = 'red' } end
    end
    return { no = ev.no and tostring(ev.no) or nil, title = WhipEvidence.label(ev.kind), color = st.color, dist = metres(dist), chips = chips }
end

-- Short line for the legend
local function evidenceInfo(ev, police)
    local st = PHASE[ev.phase] or PHASE.yellow
    if not police then return L(st.key) end
    local now = GetGameTimer()
    local age = WhipEvidence.ageWords((now - (ev.bornAt or now)) / 1000)
    local text = age and L('legend_info', L(st.key), age) or L(st.key)
    if ev.laser then text = text .. ' · ' .. L('chip_laser') end
    if ev.dir then text = text .. L('legend_trail', compass(ev.dir)) end
    return text
end

local function carParts(s, police)
    local parts = {}
    if s.burnt then parts[#parts + 1] = { text = L('car_burnt'), color = 'red' } end
    if s.blood > 0 then parts[#parts + 1] = { text = WhipEvidence.label('blood'), color = 'red' } end
    if s.casing > 0 then parts[#parts + 1] = { text = ('%d× %s'):format(s.casing, WhipEvidence.label('casing')) } end
    if s.bullet > 0 then parts[#parts + 1] = { text = L('car_bullet_holes', s.bullet) } end
    if s.gsr then parts[#parts + 1] = { text = 'GSR', color = 'yellow' } end
    if s.prints and police then parts[#parts + 1] = { text = L('possible_prints') } end
    if (s.fragments or 0) > 0 then parts[#parts + 1] = { text = L('car_fragments_scene'), color = 'yellow' } end
    if (s.outBlood or 0) > 0 then parts[#parts + 1] = { text = L('car_blood_outside'), color = 'red' } end
    if (s.paint or 0) > 0 then parts[#parts + 1] = { text = L('car_paint'), color = 'yellow' } end
    return parts
end

-- the card adds the photo state: a car counts as photographed once its plate was readable on a photo
local function carCardChips(s, police)
    local chips = carParts(s, police)
    if s.plateSeen then
        chips[#chips + 1] = { text = L('chip_photo'), color = 'green' }
    elseif s.photo then
        chips[#chips + 1] = { text = L('car_photo_no_plate'), color = 'yellow' }
    else
        chips[#chips + 1] = { text = L('car_no_photo'), color = 'yellow' }
    end
    return chips
end

-- top of the roof (marker spot) and the model's name, both kept per model
local roofCache, modelCache = {}, {}
local function roofOf(ent)
    local model = GetEntityModel(ent)
    local top = roofCache[model]
    if not top then
        local _, max = GetModelDimensions(model)
        top = (max and max.z or 1.0) + 0.05
        roofCache[model] = top
    end
    return GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, top)
end
local function modelName(ent)
    local model = GetEntityModel(ent)
    local name = modelCache[model]
    if not name then
        local code = GetDisplayNameFromVehicleModel(model)
        name = GetLabelText(code)
        if not name or name == 'NULL' or name == '' then name = code or '' end
        modelCache[model] = name
    end
    return name
end

local function onScreen(pos)
    local on, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    return on, x, y
end

-- Rebuilt every 500 ms: markers, focus card, car cards, trajectories, legend, summary, lasers
-- Lasers are drawn for everyone (a real beam); usually there are none, then this costs nothing
-- Rebuild reuses its tables (no new garbage twice a second): markers per evidence id, lists cleared and refilled
local function clearFrom(t, n) for i = #t, n, -1 do t[i] = nil end end

local laserBuf, laserRows = {}, {}
local function collectLasers(pos)
    local n = 0
    for _, ev in pairs(WhipEvidence.Ev.lasers()) do
        if ev.origin and #(ev.coords - pos) < 60.0 then
            n = n + 1
            local row = laserRows[n] or {}
            laserRows[n] = row
            row.from, row.to = ev.origin + vector3(0.0, 0.0, 0.5), ev.coords
            laserBuf[n] = row
        end
    end
    clearFrom(laserBuf, n + 1)
    return laserBuf
end

-- the digit pictures of a marker number, made once per number
local digitCache = {}
local function digitsOf(no)
    local list = digitCache[no]
    if list then return list end
    list = {}
    local text = tostring(no)
    for i = 1, #text do
        local d = tonumber(text:sub(i, i))
        if d then list[#list + 1] = DIGIT_UV[d] end
    end
    digitCache[no] = list
    return list
end

-- a letter and the digits: "L1" for bodies, "V1" for vehicles
local letterDigitCache = { [LETTER_L_UV] = {}, [LETTER_V_UV] = {} }
local function letterDigitsOf(letter, no)
    local cache = letterDigitCache[letter]
    local list = cache[no]
    if list then return list end
    list = { letter }
    for _, uvs in ipairs(digitsOf(no)) do list[#list + 1] = uvs end
    cache[no] = list
    return list
end

-- Everything a marker needs per frame, worked out here once (no strings per frame)
local function markerGeometry(m, aspect)
    local w = math.max(0.011, math.min(0.024, 0.024 - m.dist * 0.0005)) * layout.tag
    local h = w * (80 / 64) * aspect
    m.w, m.h = w, h
    if m.body then
        m.digits, m.tagUv = letterDigitsOf(LETTER_L_UV, m.no), BODY_TAG_UV
    elseif m.car then
        m.digits, m.tagUv = letterDigitsOf(LETTER_V_UV, m.no), CAR_TAG_UV
    else
        m.digits, m.tagUv = digitsOf(m.no), TAG_UV[m.phase]
    end
    local n = #m.digits
    local scale = n == 1 and 0.95 or (n == 2 and 0.72 or 0.55)
    local dw = w * 0.5 * scale
    m.dw, m.dh = dw, dw * 2 * aspect
    m.step = dw * 0.78
    m.line = m.dist < 12.0   -- the stem to the ground only close up (one line less per marker further away)
    m.bw = w * 0.55
    m.ring = math.max(0.014, 0.03 - m.dist * 0.0006)
    local dir = m.ev and m.ev.dir
    if dir then
        -- a point 0.6 m ahead on the ground: the arrow turns to face it on screen
        local r = math.rad(dir)
        m.tip = m.pos + vector3(-math.sin(r) * 0.6, math.cos(r) * 0.6, 0.03)
        m.aw = math.max(0.012, 0.026 - m.dist * 0.0006) * layout.tag
    else
        m.tip = nil
    end
end

local foundBuf, markerBuf, picBuf, picIds, lineBuf, lineRows = {}, {}, {}, {}, {}, {}
local casingOf, bulletOf, countBuf = {}, {}, {}
local markerOf, bodyMarkOf, carMarkOf, rebuildNo = {}, {}, {}, 0
local NO_BODIES = {}
local function byDist(a, b) return a.scanDist < b.scanDist end

local function rebuild()
    if scanning and GetGameTimer() - lastLayout > 10000 then
        lastLayout = GetGameTimer()
        readLayout()
    end
    local pos = GetEntityCoords(PlayerPedId())
    if not scanning then
        lasers = collectLasers(pos)
        return
    end
    local police = WhipEvidence.isPoliceOnDuty()
    local aspect = GetAspectRatio(false)
    local found, nFound = foundBuf, 0
    WhipEvidence.Ev.eachNear(pos, Config.SeeDistance, function(ev, dist)
        if passes(ev.kind) then
            nFound = nFound + 1
            found[nFound] = ev
            ev.scanDist = dist
        end
    end)
    clearFrom(found, nFound + 1)
    local laserList = collectLasers(pos)
    table.sort(found, byDist)

    local counts = countBuf
    counts.green, counts.yellow, counts.red = 0, 0, 0
    local photographed = 0
    local list, inPicture, nList, nPic = markerBuf, picBuf, 0, 0
    for k in pairs(casingOf) do casingOf[k] = nil end
    for k in pairs(bulletOf) do bulletOf[k] = nil end
    local best, bestScore
    rebuildNo = rebuildNo + 1
    for i = 1, nFound do
        local ev = found[i]
        counts[ev.phase] = (counts[ev.phase] or 0) + 1
        if ev.photo then photographed = photographed + 1 end
        if i <= MAX_MARKERS then
            local m = markerOf[ev.id]
            if not m or m.ev ~= ev then
                m = { id = ev.id, ev = ev }
                markerOf[ev.id] = m
            end
            m.seen, m.pos, m.dist, m.no = rebuildNo, ev.coords, ev.scanDist, ev.no or 0
            m.phase, m.photo = (PHASE[ev.phase] or PHASE.yellow).i, ev.photo == true
            markerGeometry(m, aspect)
            nList = nList + 1
            list[nList] = m
            local on, sx, sy = onScreen(ev.coords + vector3(0.0, 0.0, TAG_LIFT))
            if on then
                nPic = nPic + 1
                inPicture[nPic] = m
                local dx, dy = sx - 0.5, (sy - 0.5) / aspect
                local score = dx * dx + dy * dy
                if score < 0.006 and (not bestScore or score < bestScore) then best, bestScore = m, score end
            end
        end
        if police and ev.shot then
            if ev.kind == 'casing' then casingOf[ev.shot] = ev.coords
            elseif ev.kind == 'bullet' then bulletOf[ev.shot] = ev.coords end
        end
    end
    clearFrom(inPicture, nPic + 1)
    -- markers of evidence out of range for a while are let go
    if rebuildNo % 20 == 0 then
        for id, m in pairs(markerOf) do
            if rebuildNo - m.seen > 20 then markerOf[id] = nil end
        end
    end


    -- shot trajectories (police): casing -> bullet of the same shot
    local lineList, nLines = lineBuf, 0
    for shot, from in pairs(casingOf) do
        local to = bulletOf[shot]
        if to and nLines < MAX_LINES then
            nLines = nLines + 1
            local row = lineRows[nLines] or {}
            lineRows[nLines] = row
            row.from, row.to = from, to
            lineList[nLines] = row
        end
    end
    clearFrom(lineList, nLines + 1)

    -- vehicles with traces: a blue marker "V1", "V2", ... (numbered by the server) on the roof of each,
    -- like evidence; the one aimed at gets the card, the legend and a photo list them all
    local carList, carRows, carNets, carModels, nCars = NO_BODIES, {}, NO_BODIES, NO_BODIES, 0
    if scanning and passes('vehicles') then
        for net, s in pairs(WhipEvidence.Ev.vehicles()) do
            if nList >= MAX_MARKERS then break end
            if NetworkDoesNetworkIdExist(net) then
                local ent = NetworkGetEntityFromNetworkId(net)
                if ent ~= 0 and DoesEntityExist(ent) then
                    local cpos = roofOf(ent)
                    local dist = #(cpos - pos)
                    if dist <= Config.SeeDistance and #carParts(s, police) > 0 then
                        nCars = nCars + 1
                        local m = carMarkOf[net]
                        if not m then
                            m = { id = 'car:' .. net, car = true, phase = 1 }
                            carMarkOf[net] = m
                        end
                        m.s, m.seen, m.pos, m.dist, m.no, m.photo = s, rebuildNo, cpos, dist, s.no or nCars, s.plateSeen == true
                        markerGeometry(m, aspect)
                        nList = nList + 1
                        list[nList] = m
                        local on, sx, sy = onScreen(cpos + vector3(0.0, 0.0, TAG_LIFT))
                        if on then
                            if carNets == NO_BODIES then carNets, carModels = {}, {} end
                            carNets[#carNets + 1] = net
                            carModels[#carModels + 1] = modelName(ent)
                            local texts = {}
                            for _, p in ipairs(carParts(s, police)) do texts[#texts + 1] = p.text end
                            carRows[#carRows + 1] = { no = 'V' .. m.no, car = true, title = L('vehicle') .. ' · ' .. (s.plate or '?'),
                                                      info = table.concat(texts, ', '), dist = metres(dist) }
                            local dx, dy = sx - 0.5, (sy - 0.5) / aspect
                            local score = dx * dx + dy * dy
                            if score < 0.006 and (not bestScore or score < bestScore) then best, bestScore = m, score end
                        end
                    end
                end
            end
        end
        if rebuildNo % 20 == 0 then
            for net, m in pairs(carMarkOf) do
                if rebuildNo - m.seen > 20 then carMarkOf[net] = nil end
            end
        end
    end

    -- bodies: a purple marker "L1", "L2", ... on each (as many as there are, like evidence);
    -- the one aimed at gets the card (cell 0), the legend and a photo list them all
    local bodyRows, nBodies, bodyIds = {}, 0, NO_BODIES
    if scanning and passes('bodies') and WhipEvidence.Bodies and next(WhipEvidence.Bodies.all()) then
        for id, b in pairs(WhipEvidence.Bodies.all()) do
            local bpos = WhipEvidence.Bodies.chest(b)
            local dist = #(bpos - pos)
            if dist <= Config.SeeDistance and nList < MAX_MARKERS then
                nBodies = nBodies + 1
                local m = bodyMarkOf[id]
                if not m then
                    m = { id = id, body = true, phase = 1 }
                    bodyMarkOf[id] = m
                end
                m.b, m.seen, m.pos, m.dist, m.no, m.photo = b, rebuildNo, bpos, dist, b.no, b.photo == true
                markerGeometry(m, aspect)
                nList = nList + 1
                list[nList] = m
                local on, sx, sy = onScreen(bpos + vector3(0.0, 0.0, TAG_LIFT))
                if on then
                    if bodyIds == NO_BODIES then bodyIds = {} end
                    bodyIds[#bodyIds + 1] = id
                    bodyRows[#bodyRows + 1] = { no = 'L' .. b.no, body = true, title = L('body'), info = WhipEvidence.Bodies.info(b), dist = metres(dist) }
                    local dx, dy = sx - 0.5, (sy - 0.5) / aspect
                    local score = dx * dx + dy * dy
                    if score < 0.006 and (not bestScore or score < bestScore) then best, bestScore = m, score end
                end
            end
        end
        if rebuildNo % 20 == 0 then
            for id, m in pairs(bodyMarkOf) do
                if rebuildNo - m.seen > 20 then bodyMarkOf[id] = nil end
            end
        end
    end
    -- the aimed-at one gets a card (cell 0): evidence, vehicle or body
    if best then
        if best.car then
            paint(0, { no = 'V' .. best.no, car = true, title = L('vehicle') .. ' · ' .. (best.s.plate or '?'),
                       dist = metres(best.dist), chips = carCardChips(best.s, police) })
        elseif best.body then
            paint(0, { no = 'L' .. best.no, body = true, title = L('body'), dist = metres(best.dist), chips = WhipEvidence.Bodies.chips(best.b) })
        else
            paint(0, evidenceCard(best.ev, best.dist, police))
        end
    end
    focus = best

    clearFrom(list, nList + 1)
    assignMarks(list, nList, rebuildNo)
    markers, cars, lines, lasers = list, carList, lineList, laserList

    -- what a photo would show (takePhoto copies it)
    local ids = picIds
    for i = 1, nPic do ids[i] = inPicture[i].id end
    clearFrom(ids, nPic + 1)
    picture.ids, picture.cars, picture.models, picture.bodies = ids, carNets, carModels, bodyIds

    if not scanning then return end

    -- camera: legend of everything in the picture (sorted by marker number)
    legendOn = cameraUp and layout.legend
    if legendOn then
        table.sort(inPicture, function(a, b) return a.no < b.no end)
        local rows = {}
        for _, m in ipairs(inPicture) do
            if #rows >= LEGEND_ROWS then break end
            rows[#rows + 1] = { no = tostring(m.no), title = WhipEvidence.label(m.ev.kind), info = evidenceInfo(m.ev, police),
                                color = (PHASE[m.ev.phase] or PHASE.yellow).color, dist = metres(m.dist), photo = m.photo }
        end
        for _, r in ipairs(carRows) do
            if #rows >= LEGEND_ROWS then break end
            rows[#rows + 1] = r
        end
        for _, r in ipairs(bodyRows) do
            if #rows >= LEGEND_ROWS then break end
            rows[#rows + 1] = r
        end
        local total = #inPicture + #carRows + #bodyRows
        paint('legend', {
            label = L('crime_scene'), street = WhipEvidence.street(pos),
            sub = L('legend_sub', GetClockHours(), GetClockMinutes(), total, photographed, #found),
            rows = rows, more = total > #rows and L('legend_more', total - #rows) or nil, hint = hint(), empty = L('legend_nothing'),
        })
        if lastSummary then
            lastSummary = nil
            Whip.core:HideText()
        end
        return
    end

    local summary = L('summary', #found, counts.yellow, counts.green, counts.red, photographed, #found)
    if nBodies > 0 then summary = summary .. L('summary_bodies', nBodies) end
    if nCars > 0 then summary = summary .. L('summary_cars', nCars) end
    summary = summary .. ' | ' .. hint()
    if summary ~= lastSummary then
        lastSummary = summary
        Whip.core:ShowText(summary, { icon = 'target' })
    end
end

local function stopScan()
    scanning, legendOn = false, false
    markers, focus, cars, lines = {}, nil, {}, {}
    picture = { ids = {}, cars = {} }
    markerBuf, lineBuf, picIds, markerOf, bodyMarkOf, carMarkOf = markers, lines, picture.ids, {}, {}, {}
    if lastSummary then
        lastSummary = nil
        Whip.core:HideText()
    end
end

---------------------------------------------------------------- Drawing (every frame, only while needed)

-- natives as locals: the draw loop runs every frame
local DrawSpriteUv, DrawLine = DrawSpriteUv, DrawLine
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord

local function sprite(x, y, w, h, t)
    DrawSpriteUv(TXD, TEX, x, y, w, h, t[1], t[2], t[3], t[4], 0.0, 255, 255, 255, 255)
end

local function cardSprite(x, y, w, h, cell)
    local u1, v1, u2, v2 = cardUv(cell)
    DrawSpriteUv(TXD, TEX, x, y, w, h, u1, v1, u2, v2, 0.0, 255, 255, 255, 255)
end

local function cardSize(dist, aspect)
    local w = math.max(0.07, math.min(0.13, 0.135 - dist * 0.003)) * layout.card
    return w, w * (112 / 240) * aspect
end

-- one marker: yellow tag, coloured stripe (age), digits, badge. Geometry from markerGeometry.
-- Painted whole on the atlas (m.cellUv): one sprite; until then from its parts.
local function drawMarker(m, x, y, aspect)
    local cy = y - m.h / 2
    local whole = m.cellUv
    if whole then
        sprite(x, cy, m.w, m.h, whole)
        return cy - m.h / 2
    end
    sprite(x, cy, m.w, m.h, m.tagUv)
    local dy, digits = cy - m.h * 0.11, m.digits
    local n, step = #digits, m.step
    for i = 1, n do
        sprite(x + (i - (n + 1) / 2) * step, dy, m.dw, m.dh, digits[i])
    end
    local top = cy - m.h / 2
    if m.photo then sprite(x + m.w * 0.45, top + m.bw * aspect * 0.15, m.bw, m.bw * aspect, BADGE_UV) end
    return top
end

local function trailArrow(m, aspect)
    local p, t = m.pos, m.tip
    local on, gx, gy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.03)
    if not on then return end
    local on2, tx, ty = GetScreenCoordFromWorldCoord(t.x, t.y, t.z)
    if not on2 then return end
    local angle = math.deg(math.atan((tx - gx) * aspect, -(ty - gy)))
    local u = ARROW_UV
    DrawSpriteUv(TXD, TEX, gx, gy, m.aw, m.aw * aspect, u[1], u[2], u[3], u[4], angle, 255, 255, 255, 235)
end

local function groundRing(p, size, uvs, aspect)
    local on, gx, gy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.02)
    if on then sprite(gx, gy, size, size * aspect, uvs) end
end

local function drawFrame(aspect)
    if shooting then HideHudAndRadarThisFrame() end
    if up and not worldHidden then
        local focused = not shooting and not cardsHidden and focus
        local now = GetGameTimer()
        for i = 1, #markers do
            local m = markers[i]
            local p = m.pos
            local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + TAG_LIFT)
            if on then
                if m.line then DrawLine(p.x, p.y, p.z + 0.03, p.x, p.y, p.z + TAG_LIFT, 255, 255, 255, 120) end
                local top = drawMarker(m, x, y, aspect)
                if m.tip then trailArrow(m, aspect) end
                local hl = highlight[m.id]
                if hl then
                    if hl < now then
                        highlight[m.id] = nil
                    else
                        groundRing(p, (0.03 + 0.012 * math.sin(now / 120)) * math.max(0.5, 1.0 - m.dist / 40), RING_UV[2], aspect)
                    end
                end
                if m == focused then
                    groundRing(p, m.ring, RING_UV[m.phase], aspect)
                    local cw, ch = cardSize(m.dist, aspect)
                    cardSprite(x, top - 0.006 - ch / 2, cw, ch, 0)
                end
            end
        end
        for i = 1, cardsHidden and 0 or #cars do
            local c = cars[i]
            local p = (c.ent and DoesEntityExist(c.ent)) and GetEntityCoords(c.ent) or c.pos
            if p then
                local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + (c.lift or 1.3))
                if on then
                    local cw, ch = cardSize(c.dist, aspect)
                    cardSprite(x, y - ch / 2, cw, ch, c.cell)
                end
            end
        end
        if layout.lines then
            for i = 1, #lines do
                local l = lines[i]
                DrawLine(l.from.x, l.from.y, l.from.z + 0.03, l.to.x, l.to.y, l.to.z, 250, 204, 21, 210)
            end
        end
        if legendOn and not shooting then
            local w = layout.width
            local h = w * (640 / 512) * aspect
            local x = layout.side == 'left' and (0.012 + w / 2) or (1.0 - 0.012 - w / 2)
            sprite(x, layout.top + h / 2, w, h, LEGEND_UV)
        end
    end
    for i = 1, #lasers do
        local l = lasers[i]
        DrawLine(l.from.x, l.from.y, l.from.z, l.to.x, l.to.y, l.to.z, 255, 0, 0, 200)
    end
end

-- draws for 500 ms, then everything is looked up again
local function drawFor500ms()
    local untilAt = GetGameTimer() + 500
    local aspect = GetAspectRatio(false)
    repeat
        local t = WhipCost and WhipCost.start()
        drawFrame(aspect)
        if cameraUp and scanning then cameraKeys() end
        if t then WhipCost.stop('evidence: scan overlay', t) end
        Wait(0)
    until GetGameTimer() >= untilAt
end

-- Idle cost: civilians and officers off duty only check for lasers (a table that is almost always empty)
-- and sleep 1.5 s. On duty, without flashlight or camera: one cheap check every 500 ms.
CreateThread(function()
    while true do
        local police = WhipEvidence.isPoliceOnDuty()
        local hasData = WhipEvidence.Ev.count() > 0 or next(WhipEvidence.Ev.vehicles()) ~= nil
            or (WhipEvidence.Bodies and next(WhipEvidence.Bodies.all()) ~= nil)
        local active = police and hasData and detect()
        if active then
            if not scanning then readLayout() end
            scanning = true
            ensure()
        elseif scanning then
            stopScan()
        end
        padActions(scanning, scanning and cameraUp)
        if hasData then rebuild() elseif #lasers > 0 then lasers = {} end
        if #markers > 0 or #cars > 0 or #lasers > 0 or legendOn then
            drawFor500ms()
        else
            Wait(active and 250 or (police and 500 or 1500))
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= WhipEvidence.Res then return end
    stopScan()
    release()
end)
