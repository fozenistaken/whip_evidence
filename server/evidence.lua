-- Evidence on the ground: create, age, rain, pick up, destroy, laser pointer.
-- The server only keeps data; every client spawns its own props near itself (client/props.lua).
WhipEvidence.Evidence = {}

local Evidence = {}       -- [id] = evidence
local count = 0
local grid = {}           -- ["x:y"] = { [id] = true }, 32 m cells for quick "what is near"
local CELL = 32.0
local lastShot = {}       -- [source] = { at, item, serial }  (from whip_gunny:weapon:fired)
local fragmentCooldown = {}
local drops = {}          -- [charId] = { evidence ids }: blood and prints a player dropped, oldest first
local pendingAdds = {}    -- new evidence, sent to clients in batches (a burst of shots = one message)
local dirty, removed = {}, {}   -- to save: changed ids / removed ids (written every 5 s in one transaction)

local RAIN = { RAIN = true, THUNDER = true, CLEARING = true }

---------------------------------------------------------------- Helpers

function WhipEvidence.isPolice(source)
    local job = exports.whip_core:GetPlayerJob(source)
    return job ~= nil and WhipEvidence.isPoliceJob(job.key)
end

-- "Rank | Last name" for the bag
function WhipEvidence.officerLabel(source, player)
    local job = exports.whip_core:GetPlayerJob(source)
    local rank = job and (job.roleName or job.name) or L('officer')
    return ('%s | %s'):format(rank, player and player.lastName or '?')
end

function WhipEvidence.roll(chance)
    return math.random(1, 100) <= (tonumber(chance) or 0)
end
local roll = WhipEvidence.roll

local function cellOf(pos)
    return ('%d:%d'):format(math.floor(pos.x / CELL), math.floor(pos.y / CELL))
end

local function gridAdd(ev)
    local key = cellOf(ev.coords)
    grid[key] = grid[key] or {}
    grid[key][ev.id] = true
end

local function gridRemove(ev)
    local key = cellOf(ev.coords)
    local cell = grid[key]
    if cell then
        cell[ev.id] = nil
        if not next(cell) then grid[key] = nil end
    end
end

-- calls fn(ev) for every piece of evidence in the cells around pos (radius <= CELL * reach)
local function eachNear(pos, radius, fn)
    local reach = math.ceil(radius / CELL)
    local cx, cy = math.floor(pos.x / CELL), math.floor(pos.y / CELL)
    for x = cx - reach, cx + reach do
        for y = cy - reach, cy + reach do
            local cell = grid[('%d:%d'):format(x, y)]
            if cell then
                for id in pairs(cell) do
                    local ev = Evidence[id]
                    if ev and #(ev.coords - pos) <= radius and fn(ev) then return end
                end
            end
        end
    end
end

local function phaseOf(ev, t)
    local age = t - ev.created
    local scale = (ev.expires - ev.created) / math.max(1, Config.Aging.Lifetime)
    if age >= Config.Aging.Old * scale then return 'red' end
    if age >= Config.Aging.Fresh * scale then return 'yellow' end
    return 'green'
end

-- What clients may know about a piece of evidence (no serials etc.)
-- no: marker number, shot: links a casing and a bullet from the same shot (trajectory line)
local function view(ev, t)
    return {
        id = ev.id, kind = ev.kind, coords = ev.coords, heading = ev.heading,
        origin = ev.origin, phase = ev.phase, fails = ev.fails, laser = ev.laser ~= nil,
        no = ev.no, shot = ev.shot, photo = ev.photo ~= nil, dir = ev.dir,
        age = t - ev.created, left = math.max(0, ev.expires - t),   -- seconds, for the scan overlay
        look = ev.data and ev.data.look,   -- shoe prints and tyre tracks: how they are drawn (surface, length)
        bloody = (ev.kind == 'bullet' and ev.data and ev.data.blood) and true or nil,   -- went through someone
    }
end

local function giveLaserBack(ev)
    if not ev.laser then return end
    local charId = ev.laser
    ev.laser = nil
    CreateThread(function()
        Whip.core:GiveOnLogin({ charId = charId }, WhipEvidence.Items.laser, 1, nil, { reason = 'Laser pointer returned (evidence gone)' })
    end)
end

local function broadcastUpdate(list)
    if #list > 0 then TriggerClientEvent('whip_evidence:client:update', -1, list) end
end

---------------------------------------------------------------- Create / remove

function WhipEvidence.Evidence.remove(ids)
    local gone, gonePending = {}, nil
    for _, id in ipairs(ids) do
        local ev = Evidence[id]
        if ev then
            Evidence[id] = nil
            count = count - 1
            gridRemove(ev)
            giveLaserBack(ev)
            gone[#gone + 1] = id
            dirty[id] = nil
            removed[#removed + 1] = id
            gonePending = gonePending or {}
            gonePending[id] = true
        end
    end
    -- made and removed before the next batch went out (the cap, MaxEvidence): drop it from the batch,
    -- or clients would get the "remove" first and the "add" after it, and keep a piece the server no longer has
    if gonePending and #pendingAdds > 0 then
        local keep = {}
        for _, v in ipairs(pendingAdds) do
            if not gonePending[v.id] then keep[#keep + 1] = v end
        end
        pendingAdds = keep
    end
    if #gone > 0 then TriggerClientEvent('whip_evidence:client:remove', -1, gone) end
end

local function removeOldest()
    local oldestId, oldest
    for id, ev in pairs(Evidence) do
        if not ev.busy and (not oldest or ev.created < oldest) then oldestId, oldest = id, ev.created end
    end
    if oldestId then WhipEvidence.Evidence.remove({ oldestId }) end
end

-- Marker numbers: one higher than the highest number around (a scene keeps its numbers,
-- a number is never reused while its scene is still there). The area is twice the view distance,
-- so two pieces a scan can show at once never share a number.
local function sceneNumber(pos)
    local top = 0
    eachNear(pos, math.max(50.0, Config.SeeDistance * 2), function(ev)
        if (ev.no or 0) > top then top = ev.no end
    end)
    return top + 1
end

local function tooClose(pos)
    local close = false
    eachNear(pos, Config.MinDistance, function() close = true; return true end)
    return close
end

-- kind: casing | bullet | blood | fingerprint | vehicle_fragment | shoeprint | tyre_track
-- opts: coords, heading?, origin? (shooter position, for the laser), shot? (shot id), data,
--       lifetime? (seconds, default Config.Aging.Lifetime; the colours scale with it), anyDistance? (skip MinDistance)
function WhipEvidence.Evidence.create(kind, opts)
    if not Config.Props[kind] then return false, 'unknown evidence type' end
    if not opts.coords then return false, 'no position' end
    local pos = WhipEvidence.vec(opts.coords)
    if WhipEvidence.inNoEvidenceZone(pos) then return false, 'area without evidence' end
    if not opts.anyDistance and tooClose(pos) then return false, 'too close to other evidence' end
    while count >= Config.MaxEvidence do
        local before = count
        removeOldest()
        if count == before then break end
    end

    local id
    repeat id = WhipEvidence.Data.newId() until not Evidence[id]

    local t = os.time()
    local ev = {
        id = id, kind = kind, coords = pos,
        heading = (opts.heading or math.random(0, 359)) + 0.0,
        origin = opts.origin,
        created = t, expires = t + (tonumber(opts.lifetime) or Config.Aging.Lifetime),
        reduced = false, fails = 0,
        no = sceneNumber(pos), shot = opts.shot, dir = tonumber(opts.dir),
        data = opts.data or {},
    }
    ev.phase = phaseOf(ev, t)
    Evidence[id] = ev
    count = count + 1
    gridAdd(ev)

    pendingAdds[#pendingAdds + 1] = view(ev, t)
    dirty[id] = true
    WhipEvidence.debug('evidence %s (%s) at %.1f %.1f %.1f', id, kind, pos.x, pos.y, pos.z)
    return id
end

---------------------------------------------------------------- Saving and restoring (survives restarts)

local function row(ev)
    local o = ev.origin
    -- marker number and shot id ride along in the data column
    local data = {}
    for k, v in pairs(ev.data or {}) do data[k] = v end
    data._no, data._shot, data._photo, data._dir = ev.no, ev.shot, ev.photo, ev.dir
    return {
        id = ev.id, kind = ev.kind, x = ev.coords.x, y = ev.coords.y, z = ev.coords.z, heading = ev.heading,
        origin = o and ('%.2f,%.2f,%.2f'):format(o.x, o.y, o.z) or '',
        created = ev.created, expires = ev.expires, reduced = ev.reduced and 1 or 0,
        fails = ev.fails, laser = ev.laser or 0, data = json.encode(data),
    }
end

local function flush()
    if not next(dirty) and #removed == 0 then return end
    local rows = {}
    for id in pairs(dirty) do
        local ev = Evidence[id]
        if ev then rows[#rows + 1] = row(ev) end
    end
    local gone = removed
    dirty, removed = {}, {}
    local ok, err = pcall(WhipEvidence.Data.saveGround, rows, gone)
    if not ok then WhipEvidence.debug('saving evidence failed: %s', tostring(err)) end
end

CreateThread(function()
    while true do
        Wait(5000)
        flush()
    end
end)

-- a stop or restart saves the last few seconds too
AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then pcall(flush) end
end)

-- On start: everything that has not expired comes back
function WhipEvidence.Evidence.restore()
    local t = os.time()
    local n, unnumbered = 0, {}
    for _, r in ipairs(WhipEvidence.Data.loadGround()) do
        if not Evidence[r.id] and Config.Props[r.kind] then
            local origin
            if r.origin and r.origin ~= '' then
                local x, y, z = r.origin:match('^(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)$')
                if x then origin = vector3(tonumber(x), tonumber(y), tonumber(z)) end
            end
            local ev = {
                id = r.id, kind = r.kind, coords = vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0),
                heading = (r.heading or 0) + 0.0, origin = origin,
                created = r.created, expires = r.expires, reduced = r.reduced == 1 or r.reduced == true,
                fails = r.fails or 0, laser = (r.laser and r.laser ~= 0) and r.laser or nil,
                data = json.decode(r.data or '{}') or {},
            }
            ev.no, ev.shot, ev.photo, ev.dir = tonumber(ev.data._no), ev.data._shot, ev.data._photo, tonumber(ev.data._dir)
            ev.data._no, ev.data._shot, ev.data._photo, ev.data._dir = nil, nil, nil, nil
            ev.phase = phaseOf(ev, t)
            Evidence[ev.id] = ev
            count = count + 1
            gridAdd(ev)
            if not ev.no then unnumbered[#unnumbered + 1] = ev end
            n = n + 1
        end
    end
    -- rows from before marker numbers: number them now
    for _, ev in ipairs(unnumbered) do
        ev.no = sceneNumber(ev.coords)
        dirty[ev.id] = true
    end
    for _, ev in pairs(Evidence) do pendingAdds[#pendingAdds + 1] = view(ev, t) end
    if n > 0 then print(('[%s] %d piece(s) of evidence restored'):format(WhipEvidence.Res, n)) end
end

-- send new evidence every 250 ms in one message
CreateThread(function()
    while true do
        Wait(250)
        if #pendingAdds > 0 then
            local batch = pendingAdds
            pendingAdds = {}
            TriggerClientEvent('whip_evidence:client:add', -1, batch)
        end
    end
end)

function WhipEvidence.Evidence.clearAll()
    local ids = {}
    for id in pairs(Evidence) do ids[#ids + 1] = id end
    WhipEvidence.Evidence.remove(ids)
    return #ids
end

function WhipEvidence.Evidence.clearNear(coords, radius)
    local ids = {}
    eachNear(coords, radius, function(ev) ids[#ids + 1] = ev.id end)
    WhipEvidence.Evidence.remove(ids)
    return #ids
end

function WhipEvidence.Evidence.list()
    local out, t = {}, os.time()
    for _, ev in pairs(Evidence) do out[#out + 1] = view(ev, t) end
    return out
end

function WhipEvidence.Evidence.count()
    return count
end

function WhipEvidence.Evidence.get(id)
    return Evidence[id]
end

-- A photo shows these: the first photo of each is remembered (marker badge, "Photographed" on the bag)
function WhipEvidence.Evidence.markPhotographed(ids, photoId)
    local updates = {}
    for _, id in ipairs(ids) do
        local ev = Evidence[id]
        if ev and not ev.photo then
            ev.photo = photoId
            dirty[id] = true
            updates[#updates + 1] = { id = id, photo = true }
        end
    end
    broadcastUpdate(updates)
end

-- Dev tools: evidence around pos becomes collectable now (as if it were older)
function WhipEvidence.Evidence.makeReady(pos, radius)
    local t, updates = os.time(), {}
    eachNear(pos, radius, function(ev)
        if ev.phase == 'green' then
            local shift = (t - ev.created) - Config.Aging.Fresh - 1
            if shift < 0 then
                ev.created, ev.expires = ev.created + shift, ev.expires + shift
                ev.phase = phaseOf(ev, t)
                dirty[ev.id] = true
                updates[#updates + 1] = view(ev, t)
            end
        end
    end)
    broadcastUpdate(updates)
    return #updates
end

function WhipEvidence.Evidence.phaseName(phase)
    return ({ green = L('phase_fresh'), yellow = L('phase_ready'), red = L('phase_old') })[phase] or '?'
end

---------------------------------------------------------------- Aging and rain (every 10 s)

function WhipEvidence.Evidence.tick(raining)
    if count == 0 then return end
    local t = os.time()
    local expired, updates = {}, {}
    for id, ev in pairs(Evidence) do
        if t >= ev.expires and not ev.busy then
            expired[#expired + 1] = id
        else
            local patch
            if raining and not ev.reduced then
                local left = math.max(0, ev.expires - t)
                ev.expires = t + math.max(1, math.floor(left * Config.RainFactor))
                ev.reduced = true
                dirty[id] = true
                patch = { id = id, left = ev.expires - t }
            end
            local phase = phaseOf(ev, t)
            if phase ~= ev.phase then
                ev.phase = phase
                patch = patch or { id = id }
                patch.phase = phase
            end
            if patch then updates[#updates + 1] = patch end
        end
    end
    WhipEvidence.Evidence.remove(expired)
    broadcastUpdate(updates)
end

function WhipEvidence.Evidence.isRaining()
    local weather = Whip.isReady() and exports.whip_core:GetWeather() or 'EXTRASUNNY'
    return RAIN[weather] == true
end

---------------------------------------------------------------- Shots

AddEventHandler('whip_gunny:weapon:fired', function(e)
    if GetInvokingResource() ~= 'whip_gunny' then return end
    if type(e) ~= 'table' or not e.source then return end
    lastShot[e.source] = { at = GetGameTimer(), item = e.item, serial = e.serial }
    if not WhipEvidence.isIgnoredWeapon(e.item) then
        WhipEvidence.Gsr.mark(e.source)
        WhipEvidence.Body.gloveWear(e.source, Config.GloveWearShot)
    end
end)

-- Our report can arrive before whip_gunny's: wait a moment
local function awaitShot(source)
    for _ = 1, 10 do
        local shot = lastShot[source]
        if shot and GetGameTimer() - shot.at <= 3000 then return shot end
        Wait(50)
    end
    return nil
end

-- bodies.lua: the gun of a shot that hit someone (whip_gunny's report, not the client's)
WhipEvidence.Evidence.shotOf = awaitShot

AddEventHandler('playerDropped', function()
    lastShot[source] = nil
    fragmentCooldown[source] = nil
end)

local function colourName(c1, c2)
    local a, b = VehicleColors[c1], VehicleColors[c2]
    if a and b then return L('colour_on', b, a) end
    return a or b or L('unknown')
end
WhipEvidence.Evidence.colourName = colourName

local function xyz(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local POS = { { 'x', 'number', -16000, 16000 }, { 'y', 'number', -16000, 16000 }, { 'z', 'number', -1000, 3000 } }

local function vehicleOf(net)
    if not net or net <= 0 then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2 then return ent end
    return nil
end

---------------------------------------------------------------- Pick up (police)

local function bagFor(source, player, ev, street)
    local bagId = WhipEvidence.Data.newId()
    local meta = {
        evidence_id  = bagId,
        kind         = ev.kind,
        type         = WhipEvidence.label(ev.kind),
        time         = os.date('%Y-%m-%d %H:%M:%S'),
        street       = street,
        collected_by = WhipEvidence.officerLabel(source, player),
        marker       = ev.no and ('#' .. ev.no) or nil,
        photographed = ev.photo and L('photographed_yes', ev.photo) or L('no'),
    }
    meta.custody = WhipEvidence.custody(nil, L('custody_collected'), meta.collected_by)
    local secret = WhipEvidence.Evidence.secretFor(ev.kind, ev.data, meta, os.time() - ev.created)
    return bagId, meta, secret
end

-- An age in ranges: "Under 5 min", "20-30 min", "1-2 h" (also the time of death on a body's report)
local function rangeText(seconds)
    local m = math.floor(math.max(0, seconds) / 60)
    if m < 5 then return L('age_under5') end
    if m < 10 then return L('age_5_10') end
    if m < 60 then
        local lo = math.floor(m / 10) * 10
        return L('age_min', lo, lo + 10)
    end
    local h = math.floor(m / 60)
    return L('age_hours', h, h + 1)
end
WhipEvidence.Evidence.ageText = rangeText

-- How old a piece was when it was collected, as the lab puts it (Config.LabAge):
-- 'exact' ranges, 'rough' ("Under 15 min", "Under 1 h", "Over 1 h"), 'off' nil (no age). rough = true forces rough.
local function labAge(seconds, rough)
    local mode = Config.LabAge or 'rough'
    if mode == 'off' then return nil end
    if rough or mode == 'rough' then
        local m = math.floor(math.max(0, seconds) / 60)
        if m < 15 then return L('lab_age_fresh') end
        if m < 60 then return L('lab_age_hour') end
        return L('lab_age_over')
    end
    return rangeText(seconds)
end

-- Fills the visible '???' fields into meta and returns the hidden values for the lab.
-- age: seconds since it was left (ground evidence); the lab reveals it as "Age at collection"
function WhipEvidence.Evidence.secretFor(kind, d, meta, age)
    local secret = {}
    local said = age and labAge(age, kind == 'shoeprint' or kind == 'tyre_track' or kind == 'cleaned')
    if said then
        meta.age, secret.age = '???', said
    end
    if age then secret._age = math.floor(age) end   -- for the lab (how long it takes); never put on the item
    if kind == 'casing' or kind == 'bullet' then
        meta.ammo, meta.weapon_serial = '???', '???'
        secret.ammo, secret.weapon_serial = d.caliber or L('unknown'), d.serial or L('unknown')
        -- a bullet that went through someone (or came out of a body) carries their blood
        -- seen at once ("Blood found on the bullet"); whose blood type it is, the lab tells
        if kind == 'bullet' and d.blood then
            meta.blood_traces = L('blood_traces_bullet')
            meta.blood_type, secret.blood_type = '???', d.blood
        end
    elseif kind == 'fingerprint' then
        meta.fingerprint = '???'
        secret.fingerprint = d.fingerprint or L('unknown')
    elseif kind == 'blood' then
        meta.blood_type = '???'
        secret.blood_type = d.blood or L('unknown')
    elseif kind == 'vehicle_fragment' then
        meta.paint = '???'
        secret.paint = d.colour or L('unknown')
    elseif kind == 'fiber' then
        meta.fiber = '???'
        secret.fiber = d.fiber and WhipEvidence.fiberCode(d.fiber) or L('unknown')
    elseif kind == 'cleaned' then
        meta.cleaner = '???'
        secret.cleaner = L('bleach_detected')
    elseif kind == 'shoeprint' then
        meta.shoe_profile, meta.shoe_size = '???', '???'
        secret.shoe_profile = d.profile == 'barefoot' and L('barefoot') or (d.profile or L('unknown'))
        secret.shoe_size = d.size and L('shoe_size_val', d.size) or L('unknown')
        if d.blood then meta.blood_type, secret.blood_type = '???', d.blood end
    elseif kind == 'tyre_track' then
        meta.tyre_profile, meta.tyre_width = '???', '???'
        secret.tyre_profile = d.profile or L('unknown')
        secret.tyre_width = d.width and L('tyre_width_val', d.width, L('vt_' .. tostring(d.vtype or 'automobile'))) or L('unknown')
    end
    if d.surface and (kind == 'shoeprint' or kind == 'tyre_track') then meta.surface = L('surface_' .. d.surface) end
    return secret
end

local function pickup(source, player, ev, street)
    local label = WhipEvidence.label(ev.kind)

    local passed, res = WhipEvidence.minigame(source, ev.kind)
    if not passed then
        if res == 'busy' then return false, L('busy') end
        if res ~= 'failed' and res ~= 'timeout' and res ~= 'too fast' then return false end
        if not Evidence[ev.id] then return false end
        ev.fails = ev.fails + 1
        if ev.fails >= Config.MaxFails then
            WhipEvidence.Evidence.remove({ ev.id })
            exports.whip_core:LogActivity(source, 'evidence_ruined', { detail = label })
            return false, L('evidence_ruined')
        end
        dirty[ev.id] = true
        broadcastUpdate({ { id = ev.id, fails = ev.fails } })
        return false, L('failed_attempt', ev.fails, Config.MaxFails)
    end

    local done = exports.whip_core:Progress(source, WhipEvidence.bar('collect', {
        label = L('collecting'), duration = 1800, icon = 'pickup',
        disable = { move = true, combat = true, car = true },
        near = { coords = ev.coords, range = Config.PickupDistance + 2.5 },
    }))
    if not done then return false end
    -- then the bag is sealed and labelled, standing (skipped without an animation for it)
    if (Config.Animations or {}).label_bag then
        done = exports.whip_core:Progress(source, WhipEvidence.bar('label_bag', {
            label = L('labelling_bag'), duration = 1200, icon = 'pickup',
            disable = { move = true, combat = true, car = true },
            near = { coords = ev.coords, range = Config.PickupDistance + 3.5 },
        }))
        if not done then return false end
    end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not Evidence[ev.id] then return false, L('evidence_gone') end

    local bagId, meta, secret = bagFor(source, player, ev, street)
    if not WhipEvidence.useEmptyBag(source) then return false, L('no_empty_bags') end
    local given, why = WhipEvidence.giveBag(source, meta, 'Evidence collected: ' .. label)
    if not given then
        WhipEvidence.returnEmptyBag(source)
        return false, why
    end
    WhipEvidence.Data.saveBags({ WhipEvidence.Data.bagQuery(bagId, ev.kind, secret) })

    WhipEvidence.Evidence.remove({ ev.id })
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    WhipEvidence.logBag(source, 'evidence_pickup', label .. ' · ' .. street, bagId)
    exports.whip_core:NotifyPlayer(source, L(given == 'case' and 'collected_case' or 'collected', label), 'success')
    return true
end

-- Civilians remove evidence: pliers for a bullet, a cleaning cloth for the rest, and a skill check
local function destroy(source, player, ev)
    local bullet = ev.kind == 'bullet'
    if not exports.whip_core:HasItem(source, bullet and WhipEvidence.Items.pliers or WhipEvidence.Items.wipe) then
        return false, bullet and L('need_pliers') or L('need_cloth')
    end
    local passed, res = WhipEvidence.minigame(source, bullet and 'bullet' or 'wipe')
    if not passed then
        if res == 'busy' then return false, L('busy') end
        if res == 'cancelled' or res == 'not started' then return false end
        return false, L('slipped')
    end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar(bullet and 'bullet' or 'wipe', {
        label = bullet and L('pulling_bullet') or L('wiping_evidence'), duration = 3000, icon = 'fail',
        disable = { move = true, combat = true, car = true },
        near = { coords = ev.coords, range = Config.PickupDistance + 2.5 },
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not Evidence[ev.id] then return false end

    WhipEvidence.Evidence.remove({ ev.id })
    if ev.kind == 'bullet' then WhipEvidence.wear(source, WhipEvidence.Items.pliers) end
    exports.whip_core:LogActivity(source, 'evidence_destroyed', { detail = WhipEvidence.label(ev.kind) })
    return true
end

local function laser(source, player, ev)
    local placing = ev.laser == nil
    if placing and not exports.whip_core:HasItem(source, WhipEvidence.Items.laser) then
        return false, L('need_laser')
    end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('laser', {
        label = placing and L('placing_laser') or L('removing_laser'), duration = 1500, icon = 'target',
        disable = { move = true, combat = true, car = true },
        near = { coords = ev.coords, range = Config.PickupDistance + 2.5 },
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not Evidence[ev.id] then return false end

    if placing then
        if ev.laser then return false, L('laser_already') end
        local ok, why = exports.whip_core:RemoveItem(source, WhipEvidence.Items.laser, 1, nil, 'Laser pointer placed')
        if not ok then return false, why end
        ev.laser = player.charId
        exports.whip_core:NotifyPlayer(source, L('laser_placed'), 'success')
    else
        if not ev.laser then return false end
        ev.laser = nil
        exports.whip_core:AddItem(source, WhipEvidence.Items.laser, 1, nil, 'Laser pointer removed')
        exports.whip_core:NotifyPlayer(source, L('laser_removed'), 'info')
    end
    dirty[ev.id] = true
    broadcastUpdate({ { id = ev.id, laser = ev.laser ~= nil } })
    return true
end

-- Police clean-up: the piece is gone, the log says whether it had a photo
local function clearAway(source, player, ev)
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('clear', {
        label = L('clearing'), duration = 2000, icon = 'pickup',
        disable = { move = true, combat = true, car = true },
        near = { coords = ev.coords, range = Config.PickupDistance + 2.5 },
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not Evidence[ev.id] then return false end
    WhipEvidence.Evidence.remove({ ev.id })
    exports.whip_core:LogActivity(source, 'evidence_cleared', {
        detail = ('#%s %s%s'):format(ev.no or '?', WhipEvidence.label(ev.kind), ev.photo and (' · photo ' .. ev.photo) or ' · NOT photographed'),
    })
    return true
end

-- Common pattern: lock the evidence, run the action, unlock
local function withLock(name, source, ev, fn)
    if ev.busy then return false, L('evidence_busy') end
    ev.busy = source
    local id = ev.id
    exports.whip_core:TrackInvocationLock(function()
        if Evidence[id] then Evidence[id].busy = nil end
    end, name, source)
    local ok, why = fn()
    if Evidence[id] then Evidence[id].busy = nil end
    return ok, why
end

local function evidenceNear(range)
    return {
        at = function(_, _, id)
            local ev = Evidence[id]
            return ev and ev.coords or nil
        end,
        range = range,
        allowUnknown = true,
    }
end

-- A player's own drops are kept to Config.DropMaxPerPlayer: someone spamming drops pushes out
-- their own oldest ones, never the rest of the server's evidence (Config.MaxEvidence)
local function rememberDrop(charId, id)
    if not id then return end
    local list = drops[charId] or {}
    drops[charId] = list
    for i = #list, 1, -1 do
        if not Evidence[list[i]] then table.remove(list, i) end
    end
    list[#list + 1] = id
    local cap = math.max(5, tonumber(Config.DropMaxPerPlayer) or 60)
    while #list > cap do
        local old = table.remove(list, 1)
        if Evidence[old] and not Evidence[old].busy then WhipEvidence.Evidence.remove({ old }) end
    end
end

-- Blood from a player: in a car it goes into the car, otherwise onto the ground
local function bleed(source, charId, pos, dir)
    local traits = WhipEvidence.Data.traits(charId)
    if not traits then return end
    local car = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if car and car ~= 0 then
        WhipEvidence.Vehicles.addTrace(car, 'blood', { blood = traits.blood }, charId)
        return
    end
    rememberDrop(charId, WhipEvidence.Evidence.create('blood', { coords = pos, dir = dir, data = { blood = traits.blood } }))
end

---------------------------------------------------------------- Bleach (anyone with the item)

-- Cleans blood, prints and bloody shoe prints around the player: no minigame, but a "cleaned spot" stays,
-- and a swab of it shows bleach in the lab. Casings, bullets and other prints stay.
local BLEACHABLE = { blood = true, fingerprint = true }
local function bleach(source, player)
    local pos = GetEntityCoords(GetPlayerPed(source))
    local radius = tonumber(Config.BleachRadius) or 2.5
    local function pick()
        local list = {}
        eachNear(pos, radius + 1.0, function(ev)
            if not ev.busy and (BLEACHABLE[ev.kind] or (ev.kind == 'shoeprint' and ev.data and ev.data.surface == 'blood'))
                and #(ev.coords - pos) <= radius + 1.0 then
                list[#list + 1] = ev.id
            end
        end)
        return list
    end
    if #pick() == 0 then return false, L('bleach_nothing') end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('bleach', {
        label = L('bleaching'), duration = 7000, icon = 'fail',
        disable = { move = true, combat = true, car = true },
        near = { coords = pos, range = 2.0 },
    }))
    if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    local ids = pick()
    if #ids == 0 then return false, L('bleach_nothing') end
    WhipEvidence.Evidence.remove(ids)
    -- the spot (MinDistance does not apply: it lies where the evidence was)
    local ground = vector3(pos.x, pos.y, pos.z - 0.95)
    local spot
    eachNear(ground, 3.0, function(ev) if ev.kind == 'cleaned' then spot = ev end end)
    if not spot then
        WhipEvidence.Evidence.create('cleaned', { coords = ground, data = { look = { s = 'cleaned' } }, anyDistance = true,
            lifetime = math.max(60, (tonumber(Config.BleachMinutes) or 60) * 60) })
    end
    exports.whip_core:LogActivity(source, 'evidence_bleached', { detail = ('%d piece(s)'):format(#ids) })
    exports.whip_core:NotifyPlayer(source, L('bleached', #ids), 'success')
    return true
end

---------------------------------------------------------------- Registration

function WhipEvidence.Evidence.register()
    local reach = function() return Config.PickupDistance + 2.5 end

    -- Bleach: one bottle per use
    Whip.core:RegisterUseHandler(WhipEvidence.Items.bleach, function(source, player)
        return bleach(source, player)
    end)

    Whip.core:SecureEvent('whip_evidence:pickup', {
        rateLimit = 1500,
        params = { { 'id', 'key', 16 }, { 'street', 'string', 80, 'Unknown' } },
        near = evidenceNear(reach),
    }, function(source, player, id, street)
        local ev = Evidence[id]
        if not ev then return false, L('evidence_gone') end
        if not WhipEvidence.isPolice(source) then return false, L('police_only_collect') end
        if not WhipEvidence.can(source, 'evidence_collect') then return false, WhipEvidence.why(source, 'evidence_collect') end
        if ev.phase == 'green' then return false, L('too_fresh') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then
            return false, L('no_kit_collect')
        end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        local ok, why = withLock('whip_evidence:pickup', source, ev, function() return pickup(source, player, ev, street) end)
        if not ok and why then return false, why end
    end)

    Whip.core:SecureEvent('whip_evidence:destroy', {
        rateLimit = 1500,
        params = { { 'id', 'key', 16 } },
        near = evidenceNear(reach),
    }, function(source, player, id)
        local ev = Evidence[id]
        if not ev then return false, L('evidence_gone') end
        if WhipEvidence.isPolice(source) then return false end
        local ok, why = withLock('whip_evidence:destroy', source, ev, function() return destroy(source, player, ev) end)
        if not ok and why then return false, why end
    end)

    Whip.core:SecureEvent('whip_evidence:laser', {
        rateLimit = 1500,
        params = { { 'id', 'key', 16 } },
        near = evidenceNear(reach),
    }, function(source, player, id)
        local ev = Evidence[id]
        if not ev then return false, L('evidence_gone') end
        if ev.kind ~= 'bullet' or not ev.origin then return false end
        if not WhipEvidence.can(source, 'evidence_laser') then return false, WhipEvidence.why(source, 'evidence_laser') end
        local ok, why = withLock('whip_evidence:laser', source, ev, function() return laser(source, player, ev) end)
        if not ok and why then return false, why end
    end)

    -- Police clears one piece away. Without a photo only with force = true (the client asked "are you sure?").
    Whip.core:SecureEvent('whip_evidence:clear', {
        rateLimit = 1500,
        params = { { 'id', 'key', 16 }, { 'force', 'bool', false } },
        near = evidenceNear(reach),
    }, function(source, player, id, force)
        local ev = Evidence[id]
        if not ev then return false, L('evidence_gone') end
        if not WhipEvidence.can(source, 'evidence_clear') then return false, WhipEvidence.why(source, 'evidence_clear') end
        if not ev.photo and not force then return false, L('not_photographed') end
        local ok, why = withLock('whip_evidence:clear', source, ev, function() return clearAway(source, player, ev) end)
        if not ok and why then return false, why end
    end)

    -- Police releases a crime scene: everything within Config.ReleaseRadius goes.
    -- mode 'photo' keeps what has no photo yet, 'all' clears it too (the client asked first).
    Whip.core:SecureEvent('whip_evidence:release', {
        rateLimit = 5000,
        params = { { 'mode', 'enum', { 'photo', 'all' } } },
    }, function(source, player, mode)
        if not WhipEvidence.can(source, 'evidence_release') then return false, WhipEvidence.why(source, 'evidence_release') end
        local pos = GetEntityCoords(GetPlayerPed(source))
        local function pick()
            local list = {}
            eachNear(pos, Config.ReleaseRadius, function(ev)
                if not ev.busy and (mode == 'all' or ev.photo) then list[#list + 1] = ev end
            end)
            return list
        end
        if #pick() == 0 then return false, L('nothing_to_clear') end

        local done = exports.whip_core:Progress(source, WhipEvidence.bar('release', {
            label = L('releasing'), duration = 6000, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = pos, range = 3.0 },
        }))
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end

        local list, ids, unphotographed = pick(), {}, {}
        for _, ev in ipairs(list) do
            ids[#ids + 1] = ev.id
            if not ev.photo then unphotographed[#unphotographed + 1] = '#' .. (ev.no or '?') end
        end
        local kept = 0
        eachNear(pos, Config.ReleaseRadius, function(ev) if not ev.photo then kept = kept + 1 end end)
        if mode == 'all' then kept = 0 end
        WhipEvidence.Evidence.remove(ids)

        local detail = ('%d cleared'):format(#ids)
        if #unphotographed > 0 then detail = detail .. ', without photo: ' .. table.concat(unphotographed, ' ') end
        local cars = WhipEvidence.Vehicles.unphotographed(pos, Config.ReleaseRadius)
        if #cars > 0 then detail = detail .. ', vehicles without photo: ' .. table.concat(cars, ', ') end
        if kept > 0 then detail = detail .. (', %d kept (no photo)'):format(kept) end
        exports.whip_core:LogActivity(source, 'evidence_scene_released', { detail = detail })
        local text = L('scene_released', #ids)
        if kept > 0 then text = text .. L('scene_kept', kept) end
        exports.whip_core:NotifyPlayer(source, text, 'success')
    end)

    -- A shot from the player's own client. Serial and weapon come from the server (whip_gunny).
    -- Shooting from inside a car: casing and GSR go into that car. Hitting a car: a bullet hole in that car.
    Whip.core:SecureEvent('whip_evidence:shot', {
        rateLimit = 400, burst = 3, sheet = 'light',
        params = {
            { 'casing', 'record', POS },
            { 'hit', 'enum', { 'none', 'world', 'vehicle' }, 'none' },
            { 'impact', 'record', POS },
            { 'veh', 'record', {
                { 'net', 'int', 0, 2147483647, 0 },
                { 'c1', 'int', 0, 255, 0 }, { 'c2', 'int', 0, 255, 0 },
                { 'gx', 'number', -16000, 16000, 0 }, { 'gy', 'number', -16000, 16000, 0 }, { 'gz', 'number', -1000, 3000, 0 },
            } },
        },
        near = { at = function(_, _, casing) return casing end, range = 6.0, message = false },
    }, function(source, player, casing, hit, impact, veh)
        local shot = awaitShot(source)
        if not shot or WhipEvidence.isIgnoredWeapon(shot.item) then return false end

        local ped = GetPlayerPed(source)
        local from = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local data = { serial = shot.serial or L('unknown'), caliber = Config.Calibers[shot.item] or L('unknown') }
        local shotId = WhipEvidence.Data.newId()   -- casing and bullet of this shot share it (trajectory line)

        local inCar = GetVehiclePedIsIn(ped, false)
        if inCar and inCar ~= 0 then
            WhipEvidence.Vehicles.addTrace(inCar, 'casing', data, player.charId)
            WhipEvidence.Vehicles.addTrace(inCar, 'gsr', {}, player.charId)
        elseif roll(Config.DropChance.casing) then
            WhipEvidence.Evidence.create('casing', { coords = xyz(casing), shot = shotId, data = data })
        end

        if hit == 'none' then return end
        local ip = xyz(impact)
        if #(ip - from) > Config.MaxShotDistance then return false end

        if hit == 'world' then
            if roll(Config.DropChance.bullet) then
                WhipEvidence.Evidence.create('bullet', { coords = ip, heading = heading, origin = from, shot = shotId, data = data })
            end
            return
        end

        local car = vehicleOf(veh.net)
        if not car or car == inCar then return false end
        local vcoords = GetEntityCoords(car)
        if #(vcoords - ip) > 8.0 then return false end

        if roll(Config.DropChance.bullet) then
            WhipEvidence.Vehicles.addTrace(car, 'bullet', data, player.charId)
        end

        local cd = fragmentCooldown[source]
        if (not cd or GetGameTimer() >= cd) and roll(Config.DropChance.vehicle_fragment) then
            fragmentCooldown[source] = GetGameTimer() + math.random(2000, 3500)
            local ground = vector3(veh.gx + 0.0, veh.gy + 0.0, veh.gz + 0.0)
            if #(ground - vcoords) < 6.0 then
                -- the colours come from the car itself, not from the client
                WhipEvidence.Evidence.create('vehicle_fragment', { coords = ground, data = { colour = colourName(GetVehicleColours(car)) } })
                -- the car the pieces came from is involved too (even without traces inside)
                WhipEvidence.Vehicles.addTrace(car, 'fragment')
            end
        end
    end)

    -- Blood or fingerprint from the player's own client. The values come from the DB.
    -- whileDead: blood where someone dies is sent while they are down.
    Whip.core:SecureEvent('whip_evidence:drop', {
        rateLimit = 1500, burst = 2, whileDead = true,
        params = {
            { 'kind', 'enum', { 'blood', 'fingerprint' } },
            { 'pos', 'record', POS },
            { 'chance', 'int', -1, 100, -1 },
            { 'dir', 'int', -1, 359, -1 },   -- blood trail: the way the person walked
        },
        near = { at = function(_, _, _, pos) return pos end, range = 6.0, message = false },
    }, function(source, player, kind, pos, chance, dir)
        if chance < 0 then chance = Config.DropChance[kind] end
        if not roll(chance) then return end
        if kind == 'blood' then return bleed(source, player.charId, xyz(pos), dir >= 0 and dir or nil) end
        local traits = WhipEvidence.Data.traits(player.charId)
        if not traits then return false end
        rememberDrop(player.charId, WhipEvidence.Evidence.create('fingerprint', { coords = xyz(pos), data = { fingerprint = traits.fingerprint } }))
    end)

    -- Lists for a client that is loading
    Whip.core:SecureCallback('whip_evidence:sync', {
        rateLimit = 3000, burst = 2, sheet = 'light',
    }, function(source)
        return WhipEvidence.Evidence.list(), WhipEvidence.Gsr.has(source), WhipEvidence.Vehicles.summaries()
    end)
end

-- For other resources (server): exports.whip_evidence:CreateEvidence('fingerprint', coords, { source = src })
exports('CreateEvidence', function(kind, coords, opts)
    if kind ~= 'blood' and kind ~= 'fingerprint' then return false, 'only blood or fingerprint' end
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return false, 'coords missing' end
    local src = type(opts) == 'table' and tonumber(opts.source) or nil
    local charId = src and exports.whip_core:GetCharId(src)
    if not charId then return false, 'source is not a loaded player' end
    local traits = WhipEvidence.Data.traits(charId)
    if not traits then return false, 'database not ready yet' end
    local data = kind == 'blood' and { blood = traits.blood } or { fingerprint = traits.fingerprint }
    return WhipEvidence.Evidence.create(kind, { coords = coords, data = data })
end)
