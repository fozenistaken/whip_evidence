-- Client: bodies (server/bodies.lua keeps them).
--  * reports the hits this player deals (wound type, body part) and their own cause of death
--  * keeps a pedestrian's body from despawning once it is a body
--  * prompts on a body for police on duty: examine, bullet, blood sample, GSR, release
--  * WhipEvidence.Bodies.* for the scan overlay (cards "L1", legend rows)
WhipEvidence.Bodies = {}

local Bodies, byNet = {}, {}   -- [id] = view from the server (+ at: when it arrived), [net] = id
local reported = {}            -- [net] = true: a pedestrian this player killed (kept once it is a body)
local GROUP = 'whip_evidence_bodies'
local PROMPT_RANGE = 25.0

---------------------------------------------------------------- Wounds and body parts

local function h(name) return GetHashKey(name) & 0xFFFFFFFF end

local SPECIAL = {
    [h('WEAPON_RUN_OVER_BY_CAR')] = 'vehicle', [h('WEAPON_RAMMED_BY_CAR')] = 'vehicle',
    [h('WEAPON_FALL')] = 'fall',
    [h('WEAPON_FIRE')] = 'burn', [h('WEAPON_MOLOTOV')] = 'burn', [h('WEAPON_PETROLCAN')] = 'burn', [h('WEAPON_FLARE')] = 'burn',
    [h('WEAPON_EXPLOSION')] = 'explosion',
}
for _, w in ipairs({ 'WEAPON_KNIFE', 'WEAPON_DAGGER', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE',
                     'WEAPON_HATCHET', 'WEAPON_STONE_HATCHET', 'WEAPON_BOTTLE' }) do
    SPECIAL[h(w)] = 'stab'
end

local GROUPS = {
    [0x18D5FA97] = 'gunshot', [0xC6E9A5C5] = 'gunshot', [0x39D5C192] = 'gunshot', [0x451B04BC] = 'gunshot',
    [0x33431399] = 'gunshot', [0xB7BBD827] = 'gunshot',               -- pistol, smg, rifle, mg, shotgun, sniper
    [0xA27A4F9F] = 'explosion', [0x5C4C5883] = 'explosion',           -- heavy, thrown
    [0xD49321D4] = 'blunt', [0xA00FC1E4] = 'blunt',                   -- melee, unarmed
}

local function woundOf(weapon)
    weapon = (tonumber(weapon) or 0) & 0xFFFFFFFF
    if weapon == 0 then return 'other' end
    if SPECIAL[weapon] then return SPECIAL[weapon] end
    return GROUPS[GetWeapontypeGroup(weapon) & 0xFFFFFFFF] or 'other'
end

local PART = {}
for _, b in ipairs({ 31086, 39317, 12844, 65068 }) do PART[b] = 'head' end
for _, b in ipairs({ 45509, 61163, 18905, 40269, 28252, 57005, 64729, 10706 }) do PART[b] = 'arms' end
for _, b in ipairs({ 58271, 63931, 14201, 2108, 51826, 36864, 52301, 20781, 65245, 35502 }) do PART[b] = 'legs' end

-- the exact spot for the body picture (left/right = the body's own side)
local SPOT = {
    [31086] = 'head', [12844] = 'head', [65068] = 'head', [39317] = 'neck',
    [24818] = 'chest', [24817] = 'chest', [24816] = 'belly', [23553] = 'belly',
    [57597] = 'pelvis', [11816] = 'pelvis', [0] = 'pelvis',
    [64729] = 'shoulder_l', [10706] = 'shoulder_r',
    [45509] = 'upperarm_l', [61163] = 'forearm_l', [18905] = 'hand_l', [60309] = 'hand_l', [36029] = 'hand_l',
    [40269] = 'upperarm_r', [28252] = 'forearm_r', [57005] = 'hand_r', [28422] = 'hand_r', [6286] = 'hand_r',
    [58271] = 'thigh_l', [63931] = 'shin_l', [46078] = 'shin_l', [14201] = 'foot_l', [2108] = 'foot_l', [65245] = 'foot_l',
    [51826] = 'thigh_r', [36864] = 'shin_r', [16335] = 'shin_r', [52301] = 'foot_r', [20781] = 'foot_r', [35502] = 'foot_r',
}

-- body part (head/torso/arms/legs) and the exact spot ('none' when the bone is not known)
local function partOf(ped)
    local ok, bone = GetPedLastDamageBone(ped)
    if not ok then return 'torso', 'none' end
    return PART[bone] or 'torso', SPOT[bone] or 'none'
end

local function xyz(v) return { x = v.x, y = v.y, z = v.z } end

-- Where a bullet that went through would land: on along its line, past the body, the first wall, ground,
-- object or car (the body itself is left out). The server decides whether it went through, and checks the spot.
local NO_EXIT = { x = 0.0, y = 0.0, z = 0.0 }
local function exitOf(victim)
    local me = PlayerPedId()
    local ok, ip = GetPedLastWeaponImpactCoord(me)
    if not ok then return NO_EXIT, 0 end
    local wep = GetCurrentPedWeaponEntityIndex(me)
    local from = (wep and wep ~= 0 and DoesEntityExist(wep)) and GetEntityCoords(wep) or GetPedBoneCoords(me, 57005, 0.0, 0.0, 0.0)
    local d = ip - from
    local len = #d
    if len < 0.3 then return NO_EXIT, 0 end
    d = d / len
    local range = tonumber(Config.ThroughShotRange) or 40.0
    if range <= 0.5 then return NO_EXIT, 0 end   -- turned off
    local a, b = ip + d * 0.4, ip + d * range
    -- 1 world, 2 vehicles, 16 objects; the victim is ignored
    local ray = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, 1 | 2 | 16, victim, 7)
    local _, hit, pos, _, ent = GetShapeTestResult(ray)
    if hit ~= 1 then return NO_EXIT, 0 end
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2 then
        -- a car behind (or the victim's own car, from inside): a bullet hole in it
        if not NetworkGetEntityIsNetworked(ent) then return NO_EXIT, 0 end
        return xyz(pos), NetworkGetNetworkIdFromEntity(ent)
    end
    return xyz(pos), 0
end

---------------------------------------------------------------- Hits this player deals

local lastHit, lastClean = {}, 0
local localHits = {}   -- [entity] = hits on a pedestrian only this game knows (not networked yet)

local function sendHit(net, h, fatal)
    TriggerServerEvent('whip_evidence:bodyHit', net, h.wound, h.part, fatal == true, h.armed == true, h.ground, h.male == true, h.spot,
        h.exit or NO_EXIT, h.exitNet or 0)
end

-- A pedestrian that only exists in this game (no server copy): make it networked once it dies,
-- then send the hits it took. Afterwards it is a body like any other.
local function networkAndSend(victim, hits, last)
    CreateThread(function()
        SetEntityAsMissionEntity(victim, true, true)
        NetworkRegisterEntityAsNetworked(victim)
        local untilAt = GetGameTimer() + 2000
        while DoesEntityExist(victim) and not NetworkGetEntityIsNetworked(victim) and GetGameTimer() < untilAt do Wait(50) end
        if not DoesEntityExist(victim) or not NetworkGetEntityIsNetworked(victim) then return end
        local net = NetworkGetNetworkIdFromEntity(victim)
        SetNetworkIdCanMigrate(net, true)
        Wait(250)   -- the server has to know it first
        reported[net] = true
        for i = math.max(1, #hits - 6), #hits do sendHit(net, hits[i], false) end
        sendHit(net, last, true)
    end)
end

-- Only people become bodies: no animals, no models in Config.BodyIgnoreModels (aliens, zombies, ...)
local function isPerson(ped)
    return IsPedHuman(ped) and not WhipEvidence.bodyIgnored(GetEntityModel(ped))
end

-- A ped in a car (or just thrown out of one) that died in a crash nobody else caused
local CRASH_WOUND = { vehicle = true, fall = true, other = true, explosion = true, burn = true }
local function inCar(ped)
    return IsPedInAnyVehicle(ped, false) or GetVehiclePedIsIn(ped, true) ~= 0
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or Config.Bodies == false then return end
    local victim, attacker = args[1], args[2]
    local me = PlayerPedId()
    if victim == me or not victim or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end
    if not isPerson(victim) then return end
    local crash = false
    if attacker ~= me then
        local car = GetVehiclePedIsIn(me, false)
        if car == 0 or attacker ~= car then
            -- a crash nobody caused (the attacker is their own car, the world or nobody): the game that owns
            -- the ped reports its death, once, so a pedestrian who dies in a car crash is a body too
            if IsPedAPlayer(victim) or not inCar(victim) or NetworkGetEntityOwner(victim) ~= PlayerId() then return end
            -- a player shot them or drove into them: that player's game reports it (no second report)
            if attacker and attacker ~= 0 and DoesEntityExist(attacker) then
                local by = IsEntityAVehicle(attacker) and GetPedInVehicleSeat(attacker, -1) or attacker
                if by ~= 0 and IsEntityAPed(by) and IsPedAPlayer(by) then return end
            end
            crash = true
        end
    end
    if WhipEvidence.blocked() then return end
    local fatal = args[6] == 1 or IsPedDeadOrDying(victim, true)
    if crash and not fatal then return end
    local now = GetGameTimer()
    if now - lastClean > 60000 then lastHit, localHits, lastClean = {}, {}, now end
    if not fatal and lastHit[victim] and now - lastHit[victim] < 150 then return end   -- shotgun pellets: one hit
    lastHit[victim] = now
    local part, spot = partOf(victim)
    local wound = woundOf(args[7])
    if crash then
        if not CRASH_WOUND[wound] then return end
        if wound == 'other' or wound == 'fall' then wound = 'vehicle' end
    end
    local hit = { wound = wound, part = part, spot = spot, armed = IsPedArmed(victim, 4 | 2) == true,
                  male = IsPedMale(victim) == true, ground = xyz(WhipEvidence.ground(GetEntityCoords(victim))) }
    -- my shot: where it would land if it went through (right now, while the impact is this shot's)
    if wound == 'gunshot' and attacker == me then hit.exit, hit.exitNet = exitOf(victim) end

    if not NetworkGetEntityIsNetworked(victim) then
        if IsPedAPlayer(victim) then return end
        local list = localHits[victim] or {}
        localHits[victim] = list
        if not fatal then
            list[#list + 1] = hit
            return
        end
        localHits[victim] = nil
        networkAndSend(victim, list, hit)
        return
    end

    local net = NetworkGetNetworkIdFromEntity(victim)
    if byNet[net] then return end   -- already a body: shooting a corpse adds nothing
    if fatal and not IsPedAPlayer(victim) then reported[net] = true end
    sendHit(net, hit, fatal)
end)

-- Own death: the cause as this game saw it (the server uses it only when nobody reported a hit)
AddEventHandler('whip_core:player:died', function(e)
    if Config.Bodies == false or (type(e) == 'table' and (e.reconnected or e.respawnRefused)) then return end
    local ped = PlayerPedId()
    local part, spot = partOf(ped)
    TriggerServerEvent('whip_evidence:myDeath', woundOf(GetPedCauseOfDeath(ped)), part, spot)
end)

-- A pedestrian this player killed is a body now: keep it from despawning (needs control of it)
local function keep(net)
    CreateThread(function()
        local untilAt = GetGameTimer() + 3000
        while GetGameTimer() < untilAt do
            if NetworkDoesNetworkIdExist(net) then
                local ped = NetworkGetEntityFromNetworkId(net)
                if ped ~= 0 and DoesEntityExist(ped) then
                    if NetworkHasControlOfEntity(ped) then
                        SetEntityAsMissionEntity(ped, true, true)
                        -- a body in a car: the car stays too (else it despawns with the body in it)
                        local car = GetVehiclePedIsIn(ped, false)
                        if car ~= 0 and not IsPedAPlayer(GetPedInVehicleSeat(car, -1)) then
                            NetworkRequestControlOfEntity(car)
                            SetEntityAsMissionEntity(car, true, true)
                        end
                        return
                    end
                    NetworkRequestControlOfEntity(ped)
                end
            end
            Wait(100)
        end
    end)
end

---------------------------------------------------------------- Bodies from the server

local dirty = true

local function put(v)
    local old = Bodies[v.id]
    v.at = GetGameTimer()
    Bodies[v.id] = v
    byNet[v.net] = v.id
    if not old and reported[v.net] then
        reported[v.net] = nil
        keep(v.net)
    end
    dirty = true
end

RegisterNetEvent('whip_evidence:client:body', function(v)
    if type(v) == 'table' and v.id then put(v) end
end)

local hide
RegisterNetEvent('whip_evidence:client:bodyGone', function(id)
    local b = Bodies[id]
    if not b then return end
    Bodies[id] = nil
    if byNet[b.net] == id then byNet[b.net] = nil end
    hide(id)
end)

local function sync()
    local list = Whip.core:Callback('whip_evidence:bodies')
    Bodies, byNet = {}, {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do put(v) end
end

AddEventHandler('whip_core:player:loaded', function() CreateThread(sync) end)
Whip.register(function()
    CreateThread(function()
        if exports.whip_core:IsPlayerLoaded() then sync() end
    end)
end)

-- Dev tools: the test pedestrian stands still and doesn't run off
RegisterNetEvent('whip_evidence:client:testPed', function(net)
    CreateThread(function()
        local untilAt = GetGameTimer() + 5000
        while GetGameTimer() < untilAt do
            if NetworkDoesNetworkIdExist(net) then
                local ped = NetworkGetEntityFromNetworkId(net)
                if ped ~= 0 and DoesEntityExist(ped) then
                    NetworkRequestControlOfEntity(ped)
                    if NetworkHasControlOfEntity(ped) then
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedFleeAttributes(ped, 0, false)
                        SetPedKeepTask(ped, true)
                        TaskStandStill(ped, -1)
                        return
                    end
                end
            end
            Wait(100)
        end
    end)
end)

---------------------------------------------------------------- Texts for the scan overlay

local function minutesText(seconds)
    local m = math.floor(math.max(0, seconds) / 60)
    if m < 5 then return L('age_under5') end
    if m < 10 then return L('age_5_10') end
    if m < 60 then
        local lo = math.floor(m / 10) * 10
        return L('age_min', lo, lo + 10)
    end
    local hr = math.floor(m / 60)
    return L('age_hours', hr, hr + 1)
end

local function age(b) return b.age + (GetGameTimer() - b.at) / 1000 end

function WhipEvidence.Bodies.all() return Bodies end

function WhipEvidence.Bodies.label(b) return L('body_label', b.no) end

-- chips on the card
function WhipEvidence.Bodies.chips(b)
    if not b.examined then return { { text = L('body_not_examined'), color = 'yellow' } } end
    local chips = { { text = L('body_died', minutesText(age(b))) } }
    local f = b.details and b.details.fatal
    if f then chips[#chips + 1] = { text = L('body_fatal_short', L('wound_' .. f.w), L('part_' .. f.p)), color = 'red' } end
    for _, w in ipairs(b.wounds or {}) do
        chips[#chips + 1] = { text = L('wound_' .. w.w) .. (w.n > 1 and (' ×' .. w.n) or ''), color = w.w == 'gunshot' and 'red' or nil }
    end
    if (b.bullets or 0) > 0 then chips[#chips + 1] = { text = L('body_bullets_in', b.bullets), color = 'red' } end
    local parts = {}
    for _, p in ipairs(b.parts or {}) do parts[#parts + 1] = L('part_' .. p) end
    if #parts > 0 then chips[#chips + 1] = { text = table.concat(parts, ', ') } end
    if b.blood then chips[#chips + 1] = { text = L('chip_blood_taken'), color = 'green' } end
    if b.gsr then chips[#chips + 1] = { text = L('chip_gsr_taken'), color = 'green' } end
    if b.photo then chips[#chips + 1] = { text = L('chip_photo'), color = 'green' } end
    if b.held then chips[#chips + 1] = { text = L('chip_held'), color = 'blue' } end
    return chips
end

-- one line in the legend
function WhipEvidence.Bodies.info(b)
    if not b.examined then return L('body_not_examined') end
    local w = {}
    for _, x in ipairs(b.wounds or {}) do w[#w + 1] = L('wound_' .. x.w) .. (x.n > 1 and (' ×' .. x.n) or '') end
    return table.concat(w, ', ') .. ' · ' .. minutesText(age(b))
end

-- The prompt sits just above the chest of the body, wherever it lies (a ragdoll's origin is not where it looks)
local CHEST = 24818   -- SKEL_Spine3
local function chestOf(b)
    if NetworkDoesNetworkIdExist(b.net) then
        local ped = NetworkGetEntityFromNetworkId(b.net)
        if ped ~= 0 and DoesEntityExist(ped) then
            local p = GetPedBoneCoords(ped, CHEST, 0.0, 0.0, 0.0)
            return vector3(p.x, p.y, p.z + 0.35)
        end
    end
    local c = b.coords
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.35)
end

WhipEvidence.Bodies.chest = chestOf   -- the scan marker sits here too

-- where the body is now (it can be carried), and its entity if streamed in
function WhipEvidence.Bodies.where(b)
    if NetworkDoesNetworkIdExist(b.net) then
        local ent = NetworkGetEntityFromNetworkId(b.net)
        if ent ~= 0 and DoesEntityExist(ent) then return GetEntityCoords(ent), ent end
    end
    local c = b.coords
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), nil
end

---------------------------------------------------------------- Findings sheet (html/index.html)

local function reportOf(b)
    return WhipEvidence.bodyReport(b, L('body_died', minutesText(age(b))))
end

local reportId = nil
local reportPad = Whip.padScreen({
    buttons = { 'a', 'b' },
    onButton = function(cmd, down)
        if down then SendNUIMessage({ action = 'bodyReportPad', cmd = cmd }) end
    end,
})

local function closeReport(tellPage)
    if not reportId then return end
    reportId = nil
    reportPad:close()
    Whip.core:SetScreenOpen(false, 'bodyReport')
    if tellPage then SendNUIMessage({ action = 'bodyReport', open = false }) end
end

function WhipEvidence.Bodies.openReport(id)
    local b = Bodies[id]
    if not b or not b.examined then return end
    if reportId then closeReport(true) end
    reportId = id
    local title, sub, rows, text = reportOf(b)
    local d = b.details or {}
    -- the body picture (every hit on its part) and three numbers on top
    local fig = {
        marks = d.marks or {}, cause = d.fatal ~= nil, front = L('rep_front'):upper(),
        spots = (function()
            local t = {}
            for _, m in ipairs(d.marks or {}) do
                if m.s then t[m.s] = L('spot_' .. m.s) end
                t[m.p] = t[m.p] or L('part_' .. m.p)
                t['w_' .. m.w] = L('wound_' .. m.w)
            end
            t.inside, t.through, t.fatal = L('rep_legend_in'), L('rep_legend_through'), L('rep_fatal_short')
            t.side_l, t.side_r = L('rep_side_l'), L('rep_side_r')
            return t
        end)(),
        legend = { inside = L('rep_legend_in'), through = L('rep_legend_through'), stab = L('wound_stab'), other = L('rep_legend_other') },
        tiles = {
            { n = tostring(d.hits or 0), t = L('rep_hits_title') },
            { n = tostring(b.bullets or 0), t = L('rep_tile_bullets'), c = (b.bullets or 0) > 0 and 'red' or nil },
            { n = minutesText(age(b)), t = L('rep_tile_died') },
        },
    }
    Whip.core:SetScreenOpen(true, 'bodyReport')
    local pad = reportPad:open()
    SendNUIMessage({ action = 'bodyReport', open = true, pad = pad == true, kicker = L('rep_kicker'),
        title = title, sub = sub, rows = rows, text = text, fig = fig,
        copy = L('rep_copy'), close = pad and L('rep_close_pad') or L('rep_close'), copied = L('rep_copied') })
end

RegisterNUICallback('bodyReportClose', function(_, cb)
    closeReport(false)
    cb('ok')
end)

-- right after "Examine the body" (the server sent the new findings first)
RegisterNetEvent('whip_evidence:client:bodyReport', function(id)
    CreateThread(function()
        local untilAt = GetGameTimer() + 2000
        while GetGameTimer() < untilAt and not (Bodies[id] and Bodies[id].examined) do Wait(50) end
        WhipEvidence.Bodies.openReport(id)
    end)
end)

---------------------------------------------------------------- Prompts (police on duty, close by)

local shown = {}   -- [id] = state key the prompt was built with

local function here() return WhipEvidence.street(GetEntityCoords(PlayerPedId())) end


local function actionFor(b)
    local id = b.id
    local function send(event) return function() TriggerServerEvent(event, id, here()) end end
    local options = {}
    if not b.examined then
        options[#options + 1] = { id = 'examine', label = L('body_examine'), icon = 'target', onSelect = send('whip_evidence:bodyExamine') }
    else
        options[#options + 1] = { id = 'report', label = L('body_report'), icon = 'info',
            onSelect = function() WhipEvidence.Bodies.openReport(id) end }
        if (b.bullets or 0) > 0 then
            options[#options + 1] = { id = 'bullet', label = L('body_take_bullet', b.bullets), icon = 'pickup', onSelect = send('whip_evidence:bodyBullet') }
        end
    end
    if not b.blood then
        options[#options + 1] = { id = 'blood', label = L('body_take_blood'), icon = 'pickup', onSelect = send('whip_evidence:bodyBlood') }
    end
    if not b.gsr then
        options[#options + 1] = { id = 'gsr', label = L('body_test_gsr'), icon = 'target', onSelect = send('whip_evidence:bodyGsr') }
    end
    options[#options + 1] = { id = 'release', label = L('body_release'), icon = 'check', holdMs = 1500,
        onSelect = send('whip_evidence:bodyRelease') }
    return {
        id = 'body:' .. id, group = GROUP,
        at = { coords = chestOf(b), follow = function()
            local p = chestOf(Bodies[id] or b)
            return p.x, p.y, p.z
        end },
        label = L('body_label', b.no), icon = 'target', reach = 2.0, seeFrom = 8.0,
        require = { job = Config.PoliceJobs, onDuty = true, item = WhipEvidence.Items.kit },
        style = { tint = '#a78bfa', labelTint = '#a78bfa' },
        options = options,
    }
end

local function stateOf(b)
    return ('%s|%s|%s|%s|%s'):format(b.examined, b.blood, b.gsr, b.held, b.bullets or 0)
end

hide = function(id)
    if shown[id] then
        shown[id] = nil
        Whip.core:RemoveAction('body:' .. id)
    end
end

local function hideAll()
    if next(shown) then
        shown = {}
        Whip.core:RemoveActionGroup(GROUP)
    end
end

CreateThread(function()
    local allowedBefore = false
    while true do
        local wait = 1500
        local allowed = next(Bodies) ~= nil and WhipEvidence.isPoliceOnDuty() and WhipEvidence.can('evidence_body')
        if allowed ~= allowedBefore then
            hideAll()
            allowedBefore, dirty = allowed, true
        end
        if allowed then
            wait = 500
            local pos = GetEntityCoords(PlayerPedId())
            for id, b in pairs(Bodies) do
                local bpos = WhipEvidence.Bodies.where(b)
                local near = #(bpos - pos) <= PROMPT_RANGE
                if near then
                    local state = stateOf(b)
                    if shown[id] ~= state then
                        local ok = Whip.core:AddAction(actionFor(b))
                        shown[id] = ok and state or nil
                    end
                elseif shown[id] then
                    hide(id)
                end
            end
            dirty = false
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then closeReport(true) end
end)

AddEventHandler('whip_core:player:logout', function()
    closeReport(true)
    hideAll()
    Bodies, byNet, reported = {}, {}, {}
end)
