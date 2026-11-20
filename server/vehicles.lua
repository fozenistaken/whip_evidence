-- Traces inside vehicles. A car remembers who sat in it, who bled in it, shots fired from inside
-- (casings, GSR) and bullet holes. Police collects them at a front door, a cleaning cloth removes them.
WhipEvidence.Vehicles = {}

local traces = {}   -- [key] = { net, plate, no, pos, prints = { [charId] = t }, blood = { [charId] = { t, data } },
                    --           casing = { [serial] = { t, n, data } }, bullet = { [serial] = { t, n, data } }, gsr = t,
                    --           fragments = n, fragT = t (pieces of it on the ground), photo = id, plateSeen = true,
                    --           outBlood = { [who] = { t, data } } (someone it hit), paint = { [car key] = { t, colour } } (a car it hit) }

local POS = { { 'x', 'number', -16000, 16000 }, { 'y', 'number', -16000, 16000 }, { 'z', 'number', -1000, 3000 } }

local function entityOf(net)
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2 then return ent end
    return nil
end

-- WHIP vehicles by vehicleId, everything else by plate
local function keyOf(ent)
    local v = exports.whip_core:GetVehicle({ entity = ent })
    if type(v) == 'table' and v.vehicleId then return 'v' .. v.vehicleId, v.plate end
    local plate = (GetVehicleNumberPlateText(ent) or ''):gsub('%s+', '')
    return 'p' .. plate, plate
end

function WhipEvidence.Vehicles.keyOf(ent) return (keyOf(ent)) end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- What clients see while scanning (no names, no serials). The plate is on the car for everyone to see.
local function summary(tr)
    local casings, bullets = 0, 0
    for _, c in pairs(tr.casing) do casings = casings + c.n end
    for _, b in pairs(tr.bullet) do bullets = bullets + b.n end
    local s = { prints = next(tr.prints) ~= nil, blood = count(tr.blood), casing = casings, bullet = bullets, gsr = tr.gsr ~= nil,
                fragments = tr.fragments or 0, no = tr.no, plate = tr.plate,
                outBlood = count(tr.outBlood or {}), paint = count(tr.paint or {}),
                photo = tr.photo ~= nil, plateSeen = tr.plateSeen == true, burnt = tr.burnt == true }
    if not s.prints and s.blood == 0 and s.casing == 0 and s.bullet == 0 and not s.gsr and s.fragments == 0
        and s.outBlood == 0 and s.paint == 0 then return nil end
    return s
end

-- traces a police officer can bag at the door: inside, plus blood and foreign paint on the outside
-- (fragments lie on the ground)
local function hasInside(tr)
    return next(tr.prints) ~= nil or next(tr.blood) ~= nil or next(tr.casing) ~= nil or next(tr.bullet) ~= nil or tr.gsr ~= nil
        or next(tr.outBlood or {}) ~= nil or next(tr.paint or {}) ~= nil
end

-- V1, V2, ...: one higher than the involved cars around
local function nextNo(pos)
    local n = 0
    for _, o in pairs(traces) do
        if o.no and o.pos and #(o.pos - pos) < 80.0 and o.no > n then n = o.no end
    end
    return n + 1
end

-- Changed cars go out together every 500 ms (shots from inside a car change it every shot)
local pushQueue = {}
local function push(tr)
    pushQueue[tr] = true
end

CreateThread(function()
    while true do
        Wait(500)
        if next(pushQueue) then
            local q = pushQueue
            pushQueue = {}
            for tr in pairs(q) do
                TriggerClientEvent('whip_evidence:client:vehicleTraces', -1, tr.net, summary(tr))
            end
        end
    end
end)

local function traceOf(ent, create)
    local key, plate = keyOf(ent)
    local tr = traces[key]
    if not tr and create then
        local pos = GetEntityCoords(ent)
        tr = { prints = {}, blood = {}, casing = {}, bullet = {}, outBlood = {}, paint = {}, no = nextNo(pos), pos = pos }
        traces[key] = tr
    end
    if tr then
        tr.net, tr.plate, tr.key = NetworkGetNetworkIdFromEntity(ent), plate, key
        tr.pos = GetEntityCoords(ent)
    end
    return tr
end

-- kind: print | fiber | blood | casing | bullet | gsr | fragment
--       outblood (data = { blood }, charId = who it came from) | paint (data = colour, charId = the other car's key)
function WhipEvidence.Vehicles.addTrace(ent, kind, data, charId)
    local tr = traceOf(ent, true)
    local t = os.time()
    local before = summary(tr)
    if kind == 'print' then
        tr.prints[charId] = t
    elseif kind == 'fiber' then
        tr.prints['f' .. data] = t   -- fibres share the prints list (a text key instead of a charId)
    elseif kind == 'blood' then
        tr.blood[charId] = { t = t, data = data }
    elseif kind == 'casing' or kind == 'bullet' then
        local list = tr[kind]
        local key = data.serial or 'Unknown'
        local entry = list[key] or { n = 0, data = data }
        entry.n, entry.t = math.min(entry.n + 1, 99), t
        list[key] = entry
    elseif kind == 'gsr' then
        tr.gsr = t
    elseif kind == 'fragment' then
        tr.fragments, tr.fragT = math.min((tr.fragments or 0) + 1, 99), t
    elseif kind == 'outblood' then
        tr.outBlood = tr.outBlood or {}
        tr.outBlood[charId] = { t = t, data = data }
    elseif kind == 'paint' then
        tr.paint = tr.paint or {}
        tr.paint[charId] = { t = t, colour = data }
    end
    local after = summary(tr)
    if json.encode(before) ~= json.encode(after) then push(tr) end
end

-- Can a camera at camPos read the plate? Close enough, and from the front or the back (not the side)
local PLATE_RANGE = 12.0
local function plateReadable(ent, camPos)
    local pos = GetEntityCoords(ent)
    local to = camPos - pos
    local d = #to
    if d > PLATE_RANGE then return false end
    if d < 0.5 then return true end
    local h = math.rad(GetEntityHeading(ent))
    local fx, fy = -math.sin(h), math.cos(h)
    local flat = math.sqrt(to.x * to.x + to.y * to.y)
    if flat < 0.01 then return false end
    local cos = (fx * to.x + fy * to.y) / flat
    return math.abs(cos) >= 0.5   -- within 60 degrees of straight ahead or straight behind
end

-- For photos: what a car shows, its plate (when readable), number and colour (nil without traces)
function WhipEvidence.Vehicles.photoInfo(ent, camPos)
    local tr = traceOf(ent, false)
    local s = tr and summary(tr)
    if not s then return nil end
    local c1, c2 = GetVehicleColours(ent)
    return s, plateReadable(ent, camPos) and tr.plate or nil, tr.no, WhipEvidence.Evidence.colourName(c1, c2)
end

-- The car was on a photo: photographed, and its plate is on record when it was readable
function WhipEvidence.Vehicles.markPhotographed(ent, photoId, plateSeen)
    local tr = traceOf(ent, false)
    if not tr then return end
    local before = (tr.photo and 'p' or '') .. (tr.plateSeen and 's' or '')
    tr.photo = tr.photo or photoId
    if plateSeen then tr.plateSeen = true end
    if before ~= (tr.photo and 'p' or '') .. (tr.plateSeen and 's' or '') then push(tr) end
end

-- Involved cars near a spot without a photo of their plate: { 'V1 (ABC123)', ... }
function WhipEvidence.Vehicles.unphotographed(pos, radius)
    local list = {}
    for _, tr in pairs(traces) do
        local ent = tr.net and entityOf(tr.net)
        if ent and summary(tr) and not tr.plateSeen and #(GetEntityCoords(ent) - pos) <= radius then
            list[#list + 1] = ('V%d (%s)'):format(tr.no or 0, tr.plate or '?')
        end
    end
    table.sort(list)
    return list
end

function WhipEvidence.Vehicles.summaries()
    local out = {}
    for _, tr in pairs(traces) do
        local s = summary(tr)
        if s and tr.net then out[#out + 1] = { net = tr.net, s = s } end
    end
    return out
end

function WhipEvidence.Vehicles.tick()
    if not next(traces) then return end
    local cutoff = os.time() - Config.VehicleTraceMinutes * 60
    for key, tr in pairs(traces) do
        local before = json.encode(summary(tr))
        for id, t in pairs(tr.prints) do if t < cutoff then tr.prints[id] = nil end end
        for id, b in pairs(tr.blood) do if b.t < cutoff then tr.blood[id] = nil end end
        for id, c in pairs(tr.casing) do if c.t < cutoff then tr.casing[id] = nil end end
        for id, b in pairs(tr.bullet) do if b.t < cutoff then tr.bullet[id] = nil end end
        if tr.gsr and tr.gsr < cutoff then tr.gsr = nil end
        if tr.fragT and tr.fragT < cutoff then tr.fragments, tr.fragT = nil, nil end
        for id, b in pairs(tr.outBlood or {}) do if b.t < cutoff then tr.outBlood[id] = nil end end
        for id, p in pairs(tr.paint or {}) do if p.t < cutoff then tr.paint[id] = nil end end
        local s = summary(tr)
        if json.encode(s) ~= before then push(tr) end
        if not s then traces[key] = nil end
    end
end

local function vehicleNear(range)
    return {
        at = function(_, _, net)
            local ent = entityOf(net)
            return ent and GetEntityCoords(ent) or nil
        end,
        range = range,
    }
end

local function isEmpty(ent)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(ent, seat)
        if ped and ped ~= 0 then return false end
    end
    return true
end

local function examine(source, ent, label)
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('vehicle', {
        label = label, duration = 15000, icon = 'car',
        disable = { move = true, combat = true, car = true },
        near = { coords = GetEntityCoords(ent), range = 6.0 },
    }))
    return done
end

-- One bag per trace. Returns the number of bags.
local function collect(source, player, tr, street)
    local stamp = {
        time         = os.date('%Y-%m-%d %H:%M:%S'),
        street       = street,
        collected_by = WhipEvidence.officerLabel(source, player),
        tested_on    = L('vehicle_plate', tr.plate or '?'),
    }
    local queries, made, lost = {}, 0, 0

    local function give(kind, typeLabel, data, extra)
        local meta = {}
        for k, v in pairs(stamp) do meta[k] = v end
        meta.evidence_id, meta.kind, meta.type = WhipEvidence.Data.newId(), kind, typeLabel
        for k, v in pairs(extra or {}) do meta[k] = v end
        meta.custody = WhipEvidence.custody(nil, L('custody_collected'), stamp.collected_by)
        local secret = WhipEvidence.Evidence.secretFor(kind, data, meta)
        if not WhipEvidence.useEmptyBag(source) then
            lost = lost + 1
            return
        end
        if not WhipEvidence.giveBag(source, meta, 'Vehicle traces ' .. (tr.plate or '?')) then
            WhipEvidence.returnEmptyBag(source)
            lost = lost + 1
        else
            if next(secret) then queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, kind, secret) end
            made = made + 1
        end
    end

    for key in pairs(tr.prints) do
        if type(key) == 'string' then
            give('fiber', L('type_fiber_vehicle'), { fiber = tonumber(key:sub(2)) })
        else
            local traits = WhipEvidence.Data.traits(key)
            if traits then give('fingerprint', L('type_fp_vehicle'), { fingerprint = traits.fingerprint }) end
        end
    end
    for _, b in pairs(tr.blood) do give('blood', L('type_blood_vehicle'), b.data) end
    for _, c in pairs(tr.casing) do give('casing', L('type_casing_vehicle', c.n), c.data) end
    for _, b in pairs(tr.bullet) do give('bullet', L('type_bullet_vehicle', b.n), b.data) end
    if tr.gsr then give('gsr', L('type_gsr_vehicle'), {}, { gsr = 'POSITIVE' }) end
    for _, b in pairs(tr.outBlood or {}) do give('blood', L('type_blood_car_outside'), b.data) end
    for _, p in pairs(tr.paint or {}) do give('vehicle_fragment', L('type_paint_vehicle'), { colour = p.colour }) end

    WhipEvidence.Data.saveBags(queries)
    return made, lost
end

local crashBy = {}   -- [source] = game time of their last reported crash
AddEventHandler('playerDropped', function() crashBy[source] = nil end)

-- Speeds the server saw on players' cars in the last seconds. A crash report needs real speed, and at the
-- report itself both cars have already stopped. (Body health is no proof: it often does not reach the server,
-- and servers with low vehicle damage barely dent.)
local speedSeen = {}   -- [vehicle] = { { t, v }, ... } newest last, at most 12
CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        for _, s in ipairs(GetPlayers()) do
            local car = GetVehiclePedIsIn(GetPlayerPed(s), false)
            if car and car ~= 0 then
                local list = speedSeen[car] or {}
                speedSeen[car] = list
                list[#list + 1] = { t = now, v = #GetEntityVelocity(car) }
                if #list > 12 then table.remove(list, 1) end
            end
        end
        for car, list in pairs(speedSeen) do
            if now - list[#list].t > 5000 then speedSeen[car] = nil end
        end
    end
end)

local function recentSpeed(car)
    local best, now = 0.0, GetGameTimer()
    for _, e in ipairs(speedSeen[car] or {}) do
        if now - e.t <= 2500 and e.v > best then best = e.v end
    end
    return best
end

local CRASH_SPEED = 5.0   -- m/s the server saw on one of the cars just before (the client asks for ~6)

function WhipEvidence.Vehicles.register()
    -- The client sat in the car long enough (without gloves)
    -- gloves = true: the gloves stopped the print, they may leave fibres instead
    Whip.core:SecureEvent('whip_evidence:touchVehicle', {
        rateLimit = 10000, burst = 2, sheet = 'light',
        params = { { 'net', 'id', 1, 2147483647 }, { 'gloves', 'bool', false } },
        near = { at = vehicleNear(6.0).at, range = 6.0, message = false },
    }, function(source, player, net, gloves)
        local ent = entityOf(net)
        if not ent or GetVehiclePedIsIn(GetPlayerPed(source), false) ~= ent then return false end
        if gloves then
            local fiber = WhipEvidence.Body.fiber(source)
            if fiber and WhipEvidence.roll(Config.FiberChance or 60) then WhipEvidence.Vehicles.addTrace(ent, 'fiber', fiber) end
            return
        end
        WhipEvidence.Vehicles.addTrace(ent, 'print', nil, player.charId)
    end)

    -- Police collects every trace at a front door
    Whip.core:SecureEvent('whip_evidence:collectVehicle', {
        rateLimit = 5000,
        params = { { 'net', 'id', 1, 2147483647 }, { 'street', 'string', 80, 'Unknown' } },
        near = vehicleNear(5.0),
    }, function(source, player, net, street)
        local ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end
        if not WhipEvidence.isPolice(source) then return false, L('police_only_collect') end
        if not WhipEvidence.can(source, 'evidence_vehicle') then return false, WhipEvidence.why(source, 'evidence_vehicle') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        if not isEmpty(ent) then return false, L('vehicle_not_empty') end
        if #(GetEntityVelocity(ent)) > 0.5 then return false, L('vehicle_moving') end

        local done = examine(source, ent, L('examining'))
        TriggerClientEvent('whip_evidence:client:vehicleDone', source, net)
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end

        WhipEvidence.wear(source, WhipEvidence.Items.kit)
        local tr = traceOf(ent, false)
        if not tr or not hasInside(tr) then return false, L('no_traces') end
        local made, lost = collect(source, player, tr, street)
        -- the inside (and blood and paint on the outside) is bagged; pieces on the ground, the number and the photo stay
        tr.prints, tr.blood, tr.casing, tr.bullet, tr.gsr = {}, {}, {}, {}, nil
        tr.outBlood, tr.paint = {}, {}
        if summary(tr) then push(tr) else
            traces[tr.key] = nil
            TriggerClientEvent('whip_evidence:client:vehicleTraces', -1, tr.net, nil)
        end
        exports.whip_core:LogActivity(source, 'evidence_vehicle_traces', { detail = ('%s: %d'):format(tr.plate or '?', made) })
        if lost > 0 then
            exports.whip_core:NotifyPlayer(source, L('traces_lost', made, lost), 'warning')
        else
            exports.whip_core:NotifyPlayer(source, L('traces_collected', made), 'success')
        end
    end)

    -- A car with traces burnt out (a client near it saw it burn): the inside is gone.
    -- Bullet holes, pieces on the ground, the number, the plate and the photo stay.
    Whip.core:SecureEvent('whip_evidence:carBurnt', {
        rateLimit = 3000, burst = 2, sheet = 'light',
        params = { { 'net', 'id', 1, 2147483647 } },
        near = { at = vehicleNear(150.0).at, range = 150.0, message = false },
    }, function(source, player, net)
        local ent = entityOf(net)
        if not ent then return false end
        -- only a car that really burnt (engine, tank or the car itself destroyed)
        if GetVehicleEngineHealth(ent) > 0 and GetVehiclePetrolTankHealth(ent) > 0 and GetEntityHealth(ent) > 0 then return false end
        local tr = traceOf(ent, false)
        if not tr or tr.burnt then return end
        tr.burnt = true
        tr.prints, tr.blood, tr.casing, tr.gsr, tr.outBlood = {}, {}, {}, nil, {}
        push(tr)
        if not summary(tr) then traces[tr.key] = nil end
        exports.whip_core:LogActivity(source, 'evidence_vehicle_burnt', { detail = ('V%d (%s)'):format(tr.no or 0, tr.plate or '?') })
    end)

    -- Car against car (the driver's own client saw the crash): a piece of each car on the road, and each
    -- car gets the other one's paint. Both cars and their colours are read here, never sent by the client.
    local crashes, crashClean = {}, 0   -- ["keyA|keyB"] = game time: both drivers report the same crash
    Whip.core:SecureEvent('whip_evidence:carCrash', {
        rateLimit = 2000, burst = 2, sheet = 'light',
        params = { { 'net', 'id', 1, 2147483647 }, { 'at', 'record', POS } },
        near = { at = function(_, _, _, at) return at end, range = 15.0, message = false },
    }, function(source, player, net, at)
        if Config.CarCrash == false then return end
        local ped = GetPlayerPed(source)
        local mine = GetVehiclePedIsIn(ped, false)
        if not mine or mine == 0 or GetPedInVehicleSeat(mine, -1) ~= ped then return false, 'not the driver' end
        local other = entityOf(net)
        if not other or other == mine then return false, 'other car not found' end
        local a, b = GetEntityCoords(mine), GetEntityCoords(other)
        local pos = WhipEvidence.vec(at)
        if #(a - b) > 15.0 or #(pos - a) > 15.0 then return false, 'cars too far apart' end

        -- a real crash: one of the cars was fast just before, or something got dented.
        -- Not a crash (a parking bump) and the cool-down are no errors: nothing happens, no message.
        local fast = math.max(recentSpeed(mine), recentSpeed(other), #GetEntityVelocity(mine), #GetEntityVelocity(other))
        local dented = GetVehicleBodyHealth(mine) < 990.0 or GetVehicleBodyHealth(other) < 990.0
        if fast < CRASH_SPEED and not dented then
            WhipEvidence.debug('car crash from %d ignored: %.1f m/s, no dent', source, fast)
            return
        end
        local last = crashBy[source]
        if last and GetGameTimer() - last < 5000 then return end   -- one driver, one crash at a time
        crashBy[source] = GetGameTimer()

        local ka, kb = keyOf(mine), keyOf(other)
        local pair = ka < kb and (ka .. '|' .. kb) or (kb .. '|' .. ka)
        local now = GetGameTimer()
        if now - crashClean > 60000 then crashes, crashClean = {}, now end
        if crashes[pair] and now - crashes[pair] < 15000 then return end
        crashes[pair] = now
        if not WhipEvidence.roll(Config.DropChance.carcrash or 100) then return end

        local colourA = WhipEvidence.Evidence.colourName(GetVehicleColours(mine))
        local colourB = WhipEvidence.Evidence.colourName(GetVehicleColours(other))
        -- one piece of each car, side by side across the impact
        local flat = vector3(b.x - a.x, b.y - a.y, 0.0)
        local off = #flat > 0.01 and (flat / #flat) * 0.9 or vector3(0.9, 0.0, 0.0)
        if WhipEvidence.Evidence.create('vehicle_fragment', { coords = pos - off, anyDistance = true, data = { colour = colourA } }) then
            WhipEvidence.Vehicles.addTrace(mine, 'fragment')
        end
        if WhipEvidence.Evidence.create('vehicle_fragment', { coords = pos + off, anyDistance = true, data = { colour = colourB } }) then
            WhipEvidence.Vehicles.addTrace(other, 'fragment')
        end
        WhipEvidence.Vehicles.addTrace(mine, 'paint', colourB, kb)
        WhipEvidence.Vehicles.addTrace(other, 'paint', colourA, ka)
    end)

    -- Anyone with a cleaning cloth: clean the inside (prints, blood, GSR, casings). Bullet holes stay.
    Whip.core:SecureEvent('whip_evidence:wipeVehicle', {
        rateLimit = 5000,
        params = { { 'net', 'id', 1, 2147483647 } },
        near = vehicleNear(5.0),
    }, function(source, player, net)
        local ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.wipe) then return false, L('need_cloth') end

        local done = exports.whip_core:Progress(source, WhipEvidence.bar('vehicle_clean', {
            label = L('cleaning_interior'), duration = 8000, icon = 'car',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(ent), range = 6.0 },
        }))
        TriggerClientEvent('whip_evidence:client:vehicleDone', source, net)
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        ent = entityOf(net)
        if not ent then return false end

        local tr = traceOf(ent, false)
        if not tr or (not next(tr.prints) and not next(tr.blood) and not next(tr.casing) and not tr.gsr
            and not next(tr.outBlood or {})) then
            return false, L('nothing_to_clean_car')
        end
        -- blood on the outside wipes off too; foreign paint is in the paintwork and stays
        tr.prints, tr.blood, tr.casing, tr.gsr, tr.outBlood = {}, {}, {}, nil, {}
        push(tr)
        if not summary(tr) then traces[tr.key] = nil end
        exports.whip_core:LogActivity(source, 'evidence_vehicle_cleaned')
        exports.whip_core:NotifyPlayer(source, L('interior_clean'), 'success')
    end)
end
