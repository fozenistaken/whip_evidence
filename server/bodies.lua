-- Bodies: someone killed by a player (a player or a pedestrian) can be examined by police.
-- Hits come from the attacker's game (wound type, body part), the bullet's gun from whip_gunny.
-- Findings: time of death, wounds, bullets still in the body, blood sample, GSR on the hands.
-- Kept in memory only. A pedestrian's body is kept from despawning and taken away later;
-- a dead player can't respawn while police examine them (Config.BodyHoldMinutes).
WhipEvidence.Bodies = {}

local Bodies = {}     -- [id] = body
local pending = {}    -- ['p:' .. source | 'n:' .. net] = { hits, bullets, armed, at }: hits before the death
local selfCause = {}  -- [source] = { wound, part }: what a dead player's own game says (only used without hits)
local clones = {}     -- [net] = { charId, source }: dev test "copy of me"
local HOLD_KEY = 'whip_evidence'
local MAX_HITS, MAX_BULLETS = 12, 6

local WOUNDS = { 'gunshot', 'stab', 'blunt', 'vehicle', 'fall', 'burn', 'explosion', 'other' }
local PARTS = { 'head', 'torso', 'arms', 'legs' }
local SPOTS = { 'none', 'head', 'neck', 'chest', 'belly', 'pelvis', 'shoulder_l', 'shoulder_r',
    'upperarm_l', 'forearm_l', 'hand_l', 'upperarm_r', 'forearm_r', 'hand_r',
    'thigh_l', 'shin_l', 'foot_l', 'thigh_r', 'shin_r', 'foot_r' }
local POS = { { 'x', 'number', -16000, 16000 }, { 'y', 'number', -16000, 16000 }, { 'z', 'number', -1000, 3000 } }
local BLOOD = { 'A+', 'A+', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O+', 'O+', 'O-' }

local function xyz(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
local function roll(p) return math.random(1, 100) <= (tonumber(p) or 0) end

local function pedOf(net)
    if not net or net <= 0 then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 1 then return ent end
    return nil
end

local function playerOf(ent)
    if not IsPedAPlayer(ent) then return nil end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if GetPlayerPed(src) == ent then return src end
    end
    return nil
end

-- A bullet that went through a body lands behind it. The spot comes from the shooter's game; it has to lie
-- on along the shot (behind the victim, seen from the shooter) and within ThroughShotRange.
local function throughShot(source, ent, exit, exitNet, blood)
    local shot = WhipEvidence.Evidence.shotOf(source)
    if not shot or WhipEvidence.isIgnoredWeapon(shot.item) then return end
    local shooter = GetPlayerPed(source)
    local from, vpos, out = GetEntityCoords(shooter), GetEntityCoords(ent), xyz(exit)
    local d1, d2 = vpos - from, out - vpos
    local f1, f2 = vector2(d1.x, d1.y), vector2(d2.x, d2.y)
    local l1, l2 = #f1, #d2
    if l1 < 0.3 or l2 < 0.3 or l2 > (tonumber(Config.ThroughShotRange) or 40.0) + 3.0 then return end
    -- the same way the shot went (flat, a shot down at someone lying still counts)
    if #f2 > 0.3 and (f1.x * f2.x + f1.y * f2.y) / (l1 * #f2) < 0.7 then return end
    -- it went through them: their blood is on it (the lab gives the blood type)
    local data = { serial = shot.serial or L('unknown'), caliber = Config.Calibers[shot.item] or L('unknown'), blood = blood }
    if exitNet > 0 then
        local car = NetworkGetEntityFromNetworkId(exitNet)
        if car and car ~= 0 and DoesEntityExist(car) and GetEntityType(car) == 2 and #(GetEntityCoords(car) - out) <= 8.0
            and roll(Config.DropChance.bullet or 50) then
            WhipEvidence.Vehicles.addTrace(car, 'bullet', data)
        end
        return
    end
    if roll(Config.DropChance.bullet or 50) then
        WhipEvidence.Evidence.create('bullet', { coords = out, heading = GetEntityHeading(shooter), origin = from, data = data })
    end
end

-- In a car, or right next to one (thrown out in the crash)
local function carNear(ent)
    if GetVehiclePedIsIn(ent, false) ~= 0 then return true end
    local pos = GetEntityCoords(ent)
    for _, car in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(car) - pos) <= 10.0 then return true end
    end
    return false
end

-- The victim's blood type: a player's own; a pedestrian's is picked once and kept (its body gets the same)
local function bloodOf(victim, net, p)
    local charId = victim and exports.whip_core:GetCharId(victim) or (clones[net] and clones[net].charId)
    local traits = charId and WhipEvidence.Data.traits(charId)
    if traits and traits.blood then return traits.blood end
    p.blood = p.blood or BLOOD[math.random(1, #BLOOD)]
    return p.blood
end

-- Who a trace on a car or weapon came from: a character, or a pedestrian (never a server id)
local function whoOf(victim, net)
    local charId = victim and exports.whip_core:GetCharId(victim)
    return charId and ('c:' .. charId) or ('n:' .. net)
end

-- Run over: the car breaks a little and leaves pieces where it hit, gets the victim's blood on it,
-- and the post-mortem report gets the speed and whether it braked (one impact per victim every 10 s).
-- The car is the one the reporting driver sits in; its colours and speed are read here, never sent by the client.
local RUNOVER_SPEED = 4.0   -- m/s (~15 km/h): a slow bump leaves nothing unless it killed
local function runOver(source, ent, victim, net, p, hit, fatal, ground)
    local ped = GetPlayerPed(source)
    local car = GetVehiclePedIsIn(ped, false)
    if not car or car == 0 or GetPedInVehicleSeat(car, -1) ~= ped then return end   -- only the driver runs someone over
    local vpos = GetEntityCoords(ent)
    if #(GetEntityCoords(car) - vpos) > 8.0 then return end
    local now = GetGameTimer()
    if p.fragAt and now - p.fragAt < 10000 then return end   -- one impact sends several hits
    local speed = #GetEntityVelocity(car)
    -- "fatal" comes from the client: a slow bump only counts when the server sees the victim dying too
    if speed < RUNOVER_SPEED and not (fatal and GetEntityHealth(ent) <= 100) then return end
    p.fragAt = now
    hit.kmh = math.floor(speed * 3.6 + 0.5)

    local pos = ground and xyz(ground) or vpos
    if #(pos - vpos) > 3.0 then pos = vpos end
    -- sitting in a car themselves (car against car): no blood on the outside, no run-over pieces
    -- (the crash leaves pieces of both cars, carCrash in vehicles.lua); speed and braking still count
    local victimInCar = GetVehiclePedIsIn(ent, false) ~= 0

    -- their blood on the outside of the car (police bag it at the door, the lab gives the blood type)
    if not victimInCar and roll(fatal and 100 or (Config.DropChance.blood or 75)) then
        WhipEvidence.Vehicles.addTrace(car, 'outblood', { blood = bloodOf(victim, net, p) }, whoOf(victim, net))
    end

    if not victimInCar and roll(Config.DropChance.runover or Config.DropChance.vehicle_fragment) then
        local c1, c2 = GetVehicleColours(car)
        local ok = WhipEvidence.Evidence.create('vehicle_fragment', {
            coords = pos, anyDistance = true,   -- the victim's blood lands on the same spot
            data = { colour = WhipEvidence.Evidence.colourName(c1, c2) },
        })
        if ok then WhipEvidence.Vehicles.addTrace(car, 'fragment') end
    end

    -- Did it brake? Only where this driver leaves tracks at all. The client sends a skid in stretches,
    -- so it is looked at a few seconds later.
    if WhipEvidence.Tracks.leavesTracks(source) then
        local charId, since = exports.whip_core:GetCharId(source), os.time() - 10
        if charId then
            CreateThread(function()
                Wait(5000)
                hit.skid = WhipEvidence.Tracks.skidNear(charId, pos, since) and 'yes' or 'none'
            end)
        end
    end
end

-- where the body is now (it can be carried away)
local function coordsOf(b)
    local ent = b.source and GetPlayerPed(b.source) or pedOf(b.net)
    if ent and ent ~= 0 and DoesEntityExist(ent) then b.coords = GetEntityCoords(ent) end
    return b.coords
end

-- L1, L2, ...: one higher than the bodies around
local function nextNo(pos)
    local n = 0
    for _, b in pairs(Bodies) do
        if #(b.coords - pos) < 80.0 and b.no > n then n = b.no end
    end
    return n + 1
end

-- shot distance (server: shooter to victim at the hit) as the coroner reads it from the wound
local function rangeOf(d)
    if d < 2.0 then return 'close' end
    if d <= 10.0 then return 'short' end
    return 'far'
end

-- What clients get. Findings only once examined; never names or serials.
local function view(b)
    local v = {
        id = b.id, net = b.net, no = b.no, kind = b.kind, coords = b.coords,
        age = os.time() - b.diedAt, examined = b.examined == true, held = b.held ~= nil,
        blood = b.bloodTaken == true, gsr = b.gsrTaken == true, photo = b.photo ~= nil,
    }
    if not b.examined then return v end
    local count, perPart, ranges, through, defense, fatal = {}, {}, {}, 0, false, nil
    for _, h in ipairs(b.hits) do
        count[h.wound] = (count[h.wound] or 0) + 1
        local pp = perPart[h.part] or {}
        perPart[h.part] = pp
        pp[h.wound] = (pp[h.wound] or 0) + 1
        if h.wound == 'gunshot' then
            if h.dist then ranges[rangeOf(h.dist)] = true end
            if not h.stays then through = through + 1 end
        end
        if h.part == 'arms' and (h.wound == 'stab' or h.wound == 'blunt') then defense = true end
        if h.fatal then fatal = h end
    end
    fatal = fatal or b.hits[#b.hits]
    local wounds, parts, byPart = {}, {}, {}
    for _, w in ipairs(WOUNDS) do
        if count[w] then wounds[#wounds + 1] = { w = w, n = count[w] } end
    end
    if #wounds == 0 then wounds[1] = { w = 'other', n = 1 } end
    for _, p in ipairs(PARTS) do
        local pp = perPart[p]
        if pp then
            parts[#parts + 1] = p
            local list = {}
            for _, w in ipairs(WOUNDS) do
                if pp[w] then list[#list + 1] = { w = w, n = pp[w] } end
            end
            byPart[#byPart + 1] = { p = p, w = list }
        end
    end
    local rlist = {}
    for _, r in ipairs({ 'close', 'short', 'far' }) do
        if ranges[r] then rlist[#rlist + 1] = r end
    end
    local moved = b.deathCoords and #(coordsOf(b) - b.deathCoords) or 0
    -- every hit for the body picture: where, what, and whether its bullet is still in the body
    local inside = {}
    for _, bl in ipairs(b.bullets) do
        local p = bl.part or 'torso'
        inside[p] = (inside[p] or 0) + 1
    end
    local marks = {}
    for i, h in ipairs(b.hits) do
        local stays = false
        if h.wound == 'gunshot' and h.stays and (inside[h.part] or 0) > 0 then
            inside[h.part] = inside[h.part] - 1
            stays = true
        end
        marks[i] = { p = h.part, s = h.spot, w = h.wound, i = stays or nil, f = (h == fatal) or nil }
    end
    -- hit by a car: the hardest impact, its speed (as a range) and whether the car braked
    local impact
    for _, h in ipairs(b.hits) do
        if h.wound == 'vehicle' and h.kmh and (not impact or h.kmh > impact.kmh) then impact = h end
    end
    if impact then
        local mid = math.floor(impact.kmh / 10 + 0.5) * 10
        impact = { lo = math.max(0, mid - 10), hi = mid + 10, skid = impact.skid }
    end
    v.wounds, v.parts, v.bullets = wounds, parts, #b.bullets
    v.details = {
        hits = #b.hits, byPart = byPart, ranges = rlist, through = through, defense = defense,
        fatal = fatal and { w = fatal.wound, p = fatal.part } or nil,
        sex = b.male == true and 'male' or (b.male == false and 'female' or nil),
        armed = b.armed == true, moved = moved >= 3.0 and math.floor(moved + 0.5) or nil,
        marks = marks, impact = impact,
    }
    return v
end

local function send(b) TriggerClientEvent('whip_evidence:client:body', -1, view(b)) end

local function deletePed(net)
    local ent = pedOf(net)
    if ent and not IsPedAPlayer(ent) then DeleteEntity(ent) end
end

local function release(b)
    if b.held and b.source then exports.whip_core:ReleaseRespawn(b.source, HOLD_KEY) end
    b.held = nil
end

local keepReport   -- below: saves the report of an examined body

local function remove(id, takeAway)
    local b = Bodies[id]
    if not b then return end
    if b.examined and keepReport then keepReport(b) end   -- last state (samples taken) for GetBodyReport later
    Bodies[id] = nil
    release(b)
    if takeAway and b.kind == 'ped' then deletePed(b.net) end
    clones[b.net] = nil
    TriggerClientEvent('whip_evidence:client:bodyGone', -1, id)
end

local function newId()
    local id
    repeat id = WhipEvidence.Data.newId() until not Bodies[id]
    return id
end

local function create(kind, data)
    if Config.Bodies == false then return nil end
    local id = newId()
    local b = {
        id = id, kind = kind, net = data.net, source = data.source, charId = data.charId,
        coords = data.coords, diedAt = os.time(), no = nextNo(data.coords),
        hits = data.hits or {}, bullets = data.bullets or {}, gsr = data.gsr or 0, blood = data.blood,
        deathCoords = data.coords, male = data.male, armed = data.armed,
    }
    Bodies[id] = b
    -- too many pedestrian bodies: the oldest is taken away
    local peds, oldest = 0, nil
    for _, o in pairs(Bodies) do
        if o.kind == 'ped' then
            peds = peds + 1
            if not oldest or o.diedAt < oldest.diedAt then oldest = o end
        end
    end
    if peds > (Config.BodyMax or 12) and oldest then remove(oldest.id, true) end
    send(b)
    WhipEvidence.debug('body %s (%s) L%d, %d hit(s), %d bullet(s)', id, kind, b.no, #b.hits, #b.bullets)
    return b
end

---------------------------------------------------------------- Hits and deaths

local function pendingOf(key)
    local p = pending[key]
    if not p or os.time() - p.at > 600 then
        p = { hits = {}, bullets = {}, armed = false }
        pending[key] = p
    end
    p.at = os.time()
    return p
end

local function pedDied(net, ent, p, ground)
    local clone = clones[net]
    local blood, gsr
    if clone then
        local traits = WhipEvidence.Data.traits(clone.charId)
        blood = traits and traits.blood
        gsr = WhipEvidence.Gsr.level(clone.source)
    else
        gsr = p.armed and math.random(30, 80) or 0
    end
    blood = blood or p.blood or BLOOD[math.random(1, #BLOOD)]
    local b = create('ped', { net = net, coords = GetEntityCoords(ent), hits = p.hits, bullets = p.bullets, gsr = gsr, blood = blood,
                              male = p.male, armed = p.armed })
    if not b then return end
    pcall(SetEntityOrphanMode, ent, 2)   -- stays when its owner leaves
    local car = GetVehiclePedIsIn(ent, false)
    if car ~= 0 then
        -- died in a car: the car stays with them, and their blood is inside it (bagged at the door)
        pcall(SetEntityOrphanMode, car, 2)
        if roll(Config.DropChance.blood or 100) then
            WhipEvidence.Vehicles.addTrace(car, 'blood', { blood = blood }, 'n:' .. net)
        end
    elseif ground and roll(Config.DropChance.blood or 100) then
        -- a pool of their blood where they fell
        WhipEvidence.Evidence.create('blood', { coords = ground, data = { blood = blood } })
    end
end

local function playerDied(src, charId)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    for _, b in pairs(Bodies) do
        if b.source == src then remove(b.id) end   -- an older death of theirs
    end
    local p = pending['p:' .. src] or { hits = {}, bullets = {} }
    pending['p:' .. src] = nil
    local hits = p.hits
    if #hits == 0 and selfCause[src] then hits = { selfCause[src] } end
    selfCause[src] = nil
    local traits = WhipEvidence.Data.traits(charId)
    create('player', {
        net = NetworkGetNetworkIdFromEntity(ped), source = src, charId = charId, coords = GetEntityCoords(ped),
        hits = hits, bullets = p.bullets, gsr = WhipEvidence.Gsr.level(src), male = p.male, armed = p.armed,
        blood = traits and traits.blood or BLOOD[math.random(1, #BLOOD)],
    })
end

AddEventHandler('whip_core:player:died', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source then return end
    local src, charId = e.source, e.charId
    CreateThread(function()
        if not exports.whip_core:IsPlayerDead(src) then return end
        playerDied(src, charId or exports.whip_core:GetCharId(src))
    end)
end)

AddEventHandler('whip_core:player:revived', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source then return end
    pending['p:' .. e.source] = nil
    for _, b in pairs(Bodies) do
        if b.source == e.source then remove(b.id) end
    end
end)

local function forget(src)
    pending['p:' .. src], selfCause[src] = nil, nil
    for _, b in pairs(Bodies) do
        if b.source == src then remove(b.id) end
    end
end
AddEventHandler('playerDropped', function() forget(source) end)
AddEventHandler('whip_core:player:logout', function(e)
    if GetInvokingResource() == 'whip_core' and type(e) == 'table' and e.source then forget(e.source) end
end)

---------------------------------------------------------------- Ticking: holds run out, bodies taken away

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for id, b in pairs(Bodies) do
            if b.held and now >= b.held then
                release(b)
                send(b)
            end
            if b.kind == 'ped' then
                if now - b.diedAt > (Config.BodyKeepMinutes or 30) * 60 then
                    remove(id, true)
                elseif not pedOf(b.net) then
                    b.missing = (b.missing or 0) + 1
                    if b.missing >= 3 then remove(id) end   -- gone (deleted by someone else)
                else
                    b.missing = nil
                end
            end
        end
        for key, p in pairs(pending) do
            if now - p.at > 600 then pending[key] = nil end
        end
    end
end)

---------------------------------------------------------------- Police actions

local function withLock(name, source, b, fn)
    if b.busy then return false, L('body_busy') end
    b.busy = source
    local id = b.id
    exports.whip_core:TrackInvocationLock(function()
        if Bodies[id] then Bodies[id].busy = nil end
    end, name, source)
    local ok, why = fn()
    if Bodies[id] then Bodies[id].busy = nil end
    return ok, why
end

local function bodyNear()
    return {
        at = function(_, _, id)
            local b = Bodies[id]
            return b and coordsOf(b) or nil
        end,
        range = 3.5,
        allowUnknown = true,
    }
end

local function allowed(source)
    if not WhipEvidence.isPolice(source) then return false, L('police_only') end
    if not WhipEvidence.can(source, 'evidence_body') then return false, WhipEvidence.why(source, 'evidence_body') end
    if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
    return true
end

local function kneel(source, b, label, ms, key)
    return exports.whip_core:Progress(source, WhipEvidence.bar(key or 'body_sample', {
        label = label, duration = ms, icon = 'target',
        disable = { move = true, combat = true, car = true },
        near = { coords = coordsOf(b), range = 3.5 },
    }))
end

local function label(b) return L('body_label', b.no) end

-- "Gunshot ×3, Stab ×1 · head, torso · died 10-20 min ago · 2 bullet(s) in the body"
local function findings(b)
    local v = view(b)
    local w = {}
    for _, x in ipairs(v.wounds) do w[#w + 1] = L('wound_' .. x.w) .. (x.n > 1 and (' ×' .. x.n) or '') end
    local p = {}
    for _, x in ipairs(v.parts) do p[#p + 1] = L('part_' .. x) end
    local text = table.concat(w, ', ')
    if #p > 0 then text = text .. ' · ' .. table.concat(p, ', ') end
    text = text .. ' · ' .. L('body_died', WhipEvidence.Evidence.ageText(v.age))
    if v.bullets > 0 then text = text .. ' · ' .. L('body_bullets_in', v.bullets) end
    return text
end

-- The post-mortem report: the findings (view) plus when, by whom, where, and the text of "Copy as text"
local function reportOf(b)
    local v = view(b)
    local title, _, _, text = WhipEvidence.bodyReport(v, L('body_died', WhipEvidence.Evidence.ageText(v.age)))
    v.title, v.text = title, text
    v.at, v.examinedBy, v.street = b.examinedAt and os.date('%Y-%m-%d %H:%M:%S', b.examinedAt), b.examinedBy, b.street
    return v
end

keepReport = function(b, report)
    local ok, text = pcall(json.encode, report or reportOf(b))
    if ok and text then WhipEvidence.Data.saveReport(b.id, text, b.examinedAt) end
end

-- The officer gets the report as an item (like the serial lab report): it goes into a case like any bag
local function giveReport(source, player, b, report)
    local d = report.details or {}
    local officer = WhipEvidence.officerLabel(source, player)
    local meta = {
        evidence_id = WhipEvidence.Data.newId(), kind = 'autopsy', type = L('type_autopsy'),
        time = report.at, street = report.street, collected_by = officer, marker = 'L' .. b.no,
        tested_on = label(b), body = b.id,
        cause = d.fatal and L('rep_fatal_v', L('wound_' .. d.fatal.w), L('part_' .. d.fatal.p)) or L('unknown'),
        findings = findings(b),
        report = json.encode(report),   -- the whole report for the MDT (not shown on the item)
        custody = WhipEvidence.custody(nil, L('custody_examined'), officer),
    }
    local given = WhipEvidence.giveBag(source, meta, 'Post-mortem report ' .. label(b))
    if given then WhipEvidence.logBag(source, 'evidence_pickup', meta.type .. ' · ' .. label(b), meta.evidence_id) end
end

local function examine(source, player, b, street)
    -- a dead player stays down while they are examined
    local holdMin = tonumber(Config.BodyHoldMinutes) or 0
    if b.source and holdMin > 0 and not b.held then
        if exports.whip_core:HoldRespawn(b.source, HOLD_KEY, L('body_hold_label')) then
            b.held = os.time() + holdMin * 60
            exports.whip_core:NotifyPlayer(b.source, L('body_held_you'), 'info')
        end
    end
    if not kneel(source, b, L('body_examining'), 6000, 'body_examine') then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) or not Bodies[b.id] then return false end
    b.examined = true
    b.examinedAt, b.examinedBy, b.street = os.time(), WhipEvidence.officerLabel(source, player), street
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    send(b)
    local report = reportOf(b)
    giveReport(source, player, b, report)
    keepReport(b, report)
    TriggerEvent('whip_evidence:bodyExamined', report)   -- for an MDT (server side)
    local text = findings(b)
    exports.whip_core:LogActivity(source, 'evidence_body_examine', { detail = label(b) .. ': ' .. text })
    exports.whip_core:NotifyPlayer(source, L('body_findings', b.no, text), 'info', 8000)
    TriggerClientEvent('whip_evidence:client:bodyReport', source, b.id)
    return true
end

local function bag(source, player, b, meta, kind, data, why)
    local officer = WhipEvidence.officerLabel(source, player)
    meta.evidence_id = WhipEvidence.Data.newId()
    meta.kind = kind
    meta.time = os.date('%Y-%m-%d %H:%M:%S')
    meta.collected_by = officer
    meta.custody = WhipEvidence.custody(nil, L('custody_collected'), officer)
    meta.body = b.id   -- which body it came from (the MDT links it to the post-mortem report)
    local secret = data and WhipEvidence.Evidence.secretFor(kind, data, meta) or nil
    if not WhipEvidence.useEmptyBag(source) then return false, L('no_empty_bags') end
    local given, err = WhipEvidence.giveBag(source, meta, why)
    if not given then
        WhipEvidence.returnEmptyBag(source)
        return false, err
    end
    if secret then WhipEvidence.Data.saveBags({ WhipEvidence.Data.bagQuery(meta.evidence_id, kind, secret) }) end
    WhipEvidence.logBag(source, 'evidence_pickup', meta.type .. ' · ' .. label(b), meta.evidence_id)
    return given
end

local function takeBullet(source, player, b, street)
    if #b.bullets == 0 then return false, L('body_no_bullets') end
    local game = (Config.Minigames or {}).body_bullet and 'body_bullet' or 'bullet'
    local passed, res = WhipEvidence.minigame(source, game)
    if not passed then return false, res == 'busy' and L('busy') or L('body_bullet_slipped') end
    if not kneel(source, b, L('body_taking_bullet'), 3000) then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) or not Bodies[b.id] then return false end
    local bullet = b.bullets[#b.bullets]
    if not bullet then return false, L('body_no_bullets') end
    local given, why = bag(source, player, b, {
        type = L('type_bullet_body'), street = street, marker = 'L' .. b.no, tested_on = label(b),
    }, 'bullet', { serial = bullet.serial, caliber = bullet.caliber, blood = b.blood }, 'Bullet from ' .. label(b))
    if not given then return false, why end
    b.bullets[#b.bullets] = nil
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    send(b)
    exports.whip_core:NotifyPlayer(source, L(given == 'case' and 'collected_case' or 'collected', L('type_bullet_body')), 'success')
    return true
end

local function takeBlood(source, player, b, street)
    if b.bloodTaken then return false, L('body_blood_done') end
    local passed, res = WhipEvidence.minigame(source, 'blood')
    if not passed then return false, res == 'busy' and L('busy') or nil end
    if not kneel(source, b, L('swabbing'), 3000) then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) or not Bodies[b.id] then return false end
    local given, why = bag(source, player, b, {
        type = L('type_blood_body'), street = street, marker = 'L' .. b.no, tested_on = label(b),
    }, 'blood', { blood = b.blood }, 'Blood sample ' .. label(b))
    if not given then return false, why end
    b.bloodTaken = true
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    send(b)
    exports.whip_core:NotifyPlayer(source, L(given == 'case' and 'collected_case' or 'collected', L('type_blood_body')), 'success')
    return true
end

local function testGsr(source, player, b, street)
    if b.gsrTaken then return false, L('body_gsr_done') end
    local passed, res = WhipEvidence.minigame(source, 'gsr')
    if not passed then return false, res == 'busy' and L('busy') or nil end
    if not kneel(source, b, L('testing_gsr'), 3000) then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) or not Bodies[b.id] then return false end
    b.gsrTaken = true
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    send(b)
    exports.whip_core:LogActivity(source, 'evidence_gsr_test', { detail = label(b) .. ': ' .. (b.gsr > 0 and 'positive' or 'negative') })
    if b.gsr <= 0 then
        exports.whip_core:NotifyPlayer(source, L('gsr_negative'), 'info')
        return true
    end
    exports.whip_core:NotifyPlayer(source, b.gsr >= 50 and L('gsr_positive_strong') or L('gsr_positive_weak'), 'warning')
    local given, why = bag(source, player, b, {
        type = L('gsr_test'), street = street, tested_on = label(b),
        gsr = b.gsr >= 50 and L('gsr_strong') or L('gsr_weak'),
    }, 'gsr', nil, L('gsr_test'))
    if not given then return false, why == L('no_empty_bags') and L('gsr_no_bag') or why end
    return true
end

---------------------------------------------------------------- Registration

function WhipEvidence.Bodies.register()
    -- A hit from this player's game: who (net id), what kind of wound, where; fatal for a pedestrian
    -- starts a body. The bullet's gun comes from whip_gunny (Evidence.shotOf), not from the client.
    Whip.core:SecureEvent('whip_evidence:bodyHit', {
        rateLimit = 100, burst = 8, sheet = 'light',
        params = {
            { 'net', 'int', 1, 2147483647 },
            { 'wound', 'enum', WOUNDS, 'other' },
            { 'part', 'enum', PARTS, 'torso' },
            { 'fatal', 'bool', false },
            { 'armed', 'bool', false },
            { 'ground', 'record', POS },
            { 'male', 'bool', true },
            { 'spot', 'enum', SPOTS, 'none' },
            -- where a bullet that went through lands (the shooter's game traced it), 0/0/0 = nowhere
            { 'exit', 'record', { { 'x', 'number', -16000, 16000, 0 }, { 'y', 'number', -16000, 16000, 0 }, { 'z', 'number', -1000, 3000, 0 } } },
            { 'exitNet', 'int', 0, 2147483647, 0 },
        },
        near = { at = function(_, _, net) local e = pedOf(net); return e and GetEntityCoords(e) or nil end,
                 range = function() return (Config.MaxShotDistance or 150.0) + 10.0 end, message = false },
    }, function(source, player, net, wound, part, fatal, armed, ground, male, spot, exit, exitNet)
        if Config.Bodies == false then return end
        local ent = pedOf(net)
        if not ent then return false end
        if WhipEvidence.bodyIgnored(GetEntityModel(ent)) then return false end   -- animals and the like
        local victim = playerOf(ent)
        if victim == source then return false end
        -- a car wound from someone not driving next to the victim: only the game that owns the ped may report
        -- that (a crash nobody caused), and only for a pedestrian in a car
        if wound == 'vehicle' then
            local myPed = GetPlayerPed(source)
            local myCar = GetVehiclePedIsIn(myPed, false)
            local driving = myCar ~= 0 and GetPedInVehicleSeat(myCar, -1) == myPed and #(GetEntityCoords(myCar) - GetEntityCoords(ent)) <= 8.0
            if not driving and (victim or NetworkGetEntityOwner(ent) ~= source or not carNear(ent)) then return false end
        end
        local key = victim and ('p:' .. victim) or ('n:' .. net)
        for _, b in pairs(Bodies) do
            if b.net == net or (victim and b.source == victim) then return end   -- already a body
        end
        local p = pendingOf(key)
        local hit = { wound = wound, part = part, fatal = fatal or nil, spot = spot ~= 'none' and spot or nil,
                      dist = #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(ent)) }
        if #p.hits < MAX_HITS then p.hits[#p.hits + 1] = hit end
        if armed then p.armed = true end
        p.male = male
        if wound == 'vehicle' then runOver(source, ent, victim, net, p, hit, fatal, ground) end
        -- a blade or a bat in hand: the victim's blood is on it
        if (wound == 'stab' or wound == 'blunt') and hit.dist <= 3.0 and roll(Config.DropChance.weapon_blood or 100) then
            local serial = WhipEvidence.Weapons.meleeInHand(source)
            if serial then WhipEvidence.Weapons.addBlood(serial, bloodOf(victim, net, p), whoOf(victim, net)) end
        end
        if wound == 'gunshot' and #p.bullets < MAX_BULLETS and roll(Config.BodyBulletStays or 70) then
            local shot = WhipEvidence.Evidence.shotOf(source)
            if shot and not WhipEvidence.isIgnoredWeapon(shot.item) then
                p.bullets[#p.bullets + 1] = { serial = shot.serial or L('unknown'), caliber = Config.Calibers[shot.item] or L('unknown'), part = part }
                hit.stays = true
            end
        end
        -- went through: the bullet flies on and lands behind the body (a wall, the ground, a car)
        if wound == 'gunshot' and not hit.stays and (exit.x ~= 0 or exit.y ~= 0) then
            throughShot(source, ent, exit, exitNet, bloodOf(victim, net, p))
        end
        if victim or not fatal then return end
        -- a pedestrian: wait for the server to see it dead too (a dead ped is at 100 or below)
        for _ = 1, 15 do
            if not DoesEntityExist(ent) then return end
            if GetEntityHealth(ent) <= 100 then break end
            Wait(100)
        end
        if not DoesEntityExist(ent) or GetEntityHealth(ent) > 100 then return end
        for _, b in pairs(Bodies) do
            if b.net == net then return end
        end
        pending[key] = nil
        pedDied(net, ent, p, xyz(ground))
    end)

    -- A dead player's own game: the cause, used only when no attacker reported a hit (a fall, a fire)
    Whip.core:SecureEvent('whip_evidence:myDeath', {
        rateLimit = 2000, whileDead = true,
        params = { { 'wound', 'enum', WOUNDS, 'other' }, { 'part', 'enum', PARTS, 'torso' }, { 'spot', 'enum', SPOTS, 'none' } },
    }, function(source, player, wound, part, spot)
        spot = spot ~= 'none' and spot or nil
        if not exports.whip_core:IsPlayerDead(source) then return false end
        for _, b in pairs(Bodies) do
            if b.source == source then
                if #b.hits == 0 then b.hits[1] = { wound = wound, part = part, spot = spot } end
                return
            end
        end
        selfCause[source] = { wound = wound, part = part, spot = spot }
    end)

    local ID = { 'id', 'key', 16 }
    local STREET = { 'street', 'string', 80, 'Unknown' }
    local function action(name, fn, needExamined)
        Whip.core:SecureEvent(name, {
            rateLimit = 1500,
            params = { ID, STREET },
            near = bodyNear(),
        }, function(source, player, id, street)
            local b = Bodies[id]
            if not b then return false, L('body_gone') end
            local ok, why = allowed(source)
            if not ok then return false, why end
            if needExamined and not b.examined then return false, L('body_examine_first') end
            ok, why = withLock(name, source, b, function() return fn(source, player, b, street) end)
            if not ok and why then return false, why end
        end)
    end
    action('whip_evidence:bodyExamine', function(source, player, b, street)
        if b.examined then return false, L('body_already_examined') end
        return examine(source, player, b, street)
    end)
    action('whip_evidence:bodyBullet', takeBullet, true)
    action('whip_evidence:bodyBlood', takeBlood)
    action('whip_evidence:bodyGsr', testGsr)
    action('whip_evidence:bodyRelease', function(source, _, b)
        exports.whip_core:LogActivity(source, 'evidence_body_release', { detail = label(b) })
        remove(b.id, true)
        exports.whip_core:NotifyPlayer(source, L('body_released', b.no), 'success')
        return true
    end)

    Whip.core:SecureCallback('whip_evidence:bodies', { rateLimit = 3000, burst = 2, sheet = 'light' }, function()
        local list = {}
        for _, b in pairs(Bodies) do list[#list + 1] = view(b) end
        return list
    end)
end

-- Photos: a row for each body in the picture ("L1 Body · Gunshot ×2 · 4 m"), and the camera badge
function WhipEvidence.Bodies.photoRows(ids, pos, range)
    local rows, shown = {}, {}
    for _, id in ipairs(ids) do
        local b = Bodies[id]
        local d = b and #(coordsOf(b) - pos)
        if d and d <= range then
            local info = L('body_not_examined')
            if b.examined then
                local v = view(b)
                local w = {}
                for _, x in ipairs(v.wounds) do w[#w + 1] = L('wound_' .. x.w) .. (x.n > 1 and (' ×' .. x.n) or '') end
                info = table.concat(w, ', ')
            end
            rows[#rows + 1] = { n = 'L' .. b.no, t = L('body'), i = info, d = math.floor(d + 0.5) }
            shown[#shown + 1] = id
        end
    end
    table.sort(rows, function(a, b) return a.n < b.n end)
    return rows, shown
end

function WhipEvidence.Bodies.markPhotographed(ids, photoId)
    for _, id in ipairs(ids) do
        local b = Bodies[id]
        if b and not b.photo then
            b.photo = photoId
            send(b)
        end
    end
end

-- Dev tools: a pedestrian that is "a copy of me" (my blood, my GSR) to test player bodies alone
function WhipEvidence.Bodies.markClone(net, source, charId)
    clones[net] = { source = source, charId = charId }
end

-- The report of an examined body: live while it is there, else the saved one (Config.BodyReportDays), else nil
function WhipEvidence.Bodies.report(id)
    local b = Bodies[id]
    if b then return b.examined and reportOf(b) or nil end
    local text = WhipEvidence.Data.loadReport(id)
    if not text then return nil end
    local ok, report = pcall(json.decode, text)
    return ok and report or nil
end

function WhipEvidence.Bodies.clearAll()
    local n = 0
    for id in pairs(Bodies) do
        remove(id, true)
        n = n + 1
    end
    return n
end

AddEventHandler('onResourceStop', function(res)
    if res ~= WhipEvidence.Res then return end
    for _, b in pairs(Bodies) do release(b) end
end)
