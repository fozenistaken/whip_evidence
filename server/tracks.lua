-- Shoe prints and tyre tracks. Left in mud, sand and snow (and blood for shoes); tyres also on grass
-- and when skidding. The client sees the ground and reports a stretch; the server checks it and makes
-- one piece of evidence per stretch (4 steps, or a few metres of track).
-- Police compare them: a shoe print taken from a person, a tyre print taken at a car (the lab gives both a code).
WhipEvidence.Tracks = {}

local POS = { { 'x', 'number', -16000, 16000 }, { 'y', 'number', -16000, 16000 }, { 'z', 'number', -1000, 3000 } }
local SURFACES = { 'mud', 'sand', 'snow', 'grass', 'blood', 'skid' }
local MALE, FEMALE = `mp_m_freemode_01`, `mp_f_freemode_01`

local shoes = {}   -- [source] = shoe drawable (the client reports it, like the gloves)
local mine = {}    -- [charId] = { evidence ids, oldest first }

-- "SP-3F2A": the same shoes (or tyres on the same car and rims) always give the same code
local function code(prefix, ...)
    return ('%s-%04X'):format(prefix, GetHashKey(table.concat({ ... }, ':')) & 0xFFFF)
end

local function shoeData(source, charId)
    local ped = GetPlayerPed(source)
    local model = GetEntityModel(ped)
    -- the shoes the client reports (a FiveM server cannot read a ped's clothes)
    local d = shoes[source] or 0
    local bare = (model == MALE and d == 34) or (model == FEMALE and d == 35)
    -- the foot size belongs to the character
    local n = (GetHashKey('whip_evidence:size:' .. tostring(charId)) & 0xFF) % 6
    return { profile = bare and 'barefoot' or code('SP', model, d), size = (model == FEMALE and 36 or 41) + n }
end

local function tyreData(ent, wheelType, wheelMod)
    local model = GetEntityModel(ent)
    local vt = GetVehicleType(ent) or 'automobile'
    local step = (GetHashKey('whip_evidence:width:' .. model) & 0xF) % 8
    local width = vt == 'bike' and (110 + step * 10) or (185 + step * 15)
    return { profile = code('RP', model, wheelType, wheelMod), width = width, vtype = vt }
end

local function policeOnDuty(source)
    local job = exports.whip_core:GetPlayerJob(source)
    return job ~= nil and WhipEvidence.isPoliceJob(job.key) and job.onDuty ~= false
end

-- Keeps a player's prints and tracks to Config.TrackMaxPerPlayer (the oldest go)
local function remember(charId, id)
    local list = mine[charId] or {}
    mine[charId] = list
    for i = #list, 1, -1 do
        if not WhipEvidence.Evidence.get(list[i]) then table.remove(list, i) end
    end
    list[#list + 1] = id
    local cap = math.max(1, tonumber(Config.TrackMaxPerPlayer) or 12)
    while #list > cap do
        WhipEvidence.Evidence.remove({ table.remove(list, 1) })
    end
end

local function bagMeta(source, player, kind, typeLabel, testedOn, street)
    local officer = WhipEvidence.officerLabel(source, player)
    return {
        evidence_id = WhipEvidence.Data.newId(), kind = kind, type = typeLabel,
        time = os.date('%Y-%m-%d %H:%M:%S'), street = street, collected_by = officer,
        custody = WhipEvidence.custody(nil, L('custody_collected'), officer), tested_on = testedOn,
    }
end

-- Gives one reference bag (shoe print of a person, tyre print of a car, glove fibres) with its lab values
local function giveReference(source, meta, data, why)
    if not WhipEvidence.useEmptyBag(source) then return false, L('no_empty_bags') end
    local secret = WhipEvidence.Evidence.secretFor(meta.kind, data, meta)
    local given, err = WhipEvidence.giveBag(source, meta, why)
    if not given then
        WhipEvidence.returnEmptyBag(source)
        return false, err
    end
    WhipEvidence.Data.saveBags({ WhipEvidence.Data.bagQuery(meta.evidence_id, meta.kind, secret) })
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    exports.whip_core:NotifyPlayer(source, L(given == 'case' and 'collected_case' or 'collected', meta.type), 'success')
    return true
end

WhipEvidence.bagMeta, WhipEvidence.giveReference = bagMeta, giveReference

-- Does this player leave prints and tracks at all? (off, or police on duty without TrackPolice)
function WhipEvidence.Tracks.leavesTracks(source)
    if Config.Tracks == false then return false end
    return Config.TrackPolice == true or not policeOnDuty(source)
end

-- Did this character leave a skid mark near pos since then? (run over: braked or not)
function WhipEvidence.Tracks.skidNear(charId, pos, since)
    for _, id in ipairs(mine[charId] or {}) do
        local ev = WhipEvidence.Evidence.get(id)
        if ev and ev.kind == 'tyre_track' and ev.data and ev.data.surface == 'skid'
            and (ev.created or 0) >= since and #(ev.coords - pos) <= 40.0 then
            return true
        end
    end
    return false
end

function WhipEvidence.Tracks.register()
    -- The client's shoes (component 6), sent when they change
    Whip.core:SecureEvent('whip_evidence:shoes', {
        rateLimit = 500, burst = 3, sheet = 'light',
        params = { { 'drawable', 'int', -1, 5000 } },
    }, function(source, _, drawable)
        shoes[source] = drawable >= 0 and drawable or nil
    end)

    -- A stretch of prints or track from the player's own client
    Whip.core:SecureEvent('whip_evidence:track', {
        rateLimit = 1200, burst = 2, sheet = 'light',
        params = {
            { 'kind', 'enum', { 'shoe', 'tyre' } },
            { 'surface', 'enum', SURFACES },
            { 'at', 'record', POS },
            { 'heading', 'number', -360, 720, 0 },
            { 'len', 'number', 0, 20, 0 },
            { 'net', 'int', 0, 2147483647, 0 },
            { 'wheels', 'record', {
                { 'type', 'int', -1, 30, -1 }, { 'mod', 'int', -1, 1000, -1 }, { 'gauge', 'number', 0, 4, 1.6 },
            } },
            { 'blood', 'string', 16, '-' },
        },
        near = { at = function(_, _, _, _, at) return at end, range = 25.0, message = false },
    }, function(source, player, kind, surface, at, heading, len, net, wheels, bloodId)
        if Config.Tracks == false then return false end
        if Config.TrackPolice ~= true and policeOnDuty(source) then return false end
        local pos = WhipEvidence.vec(at)
        local ped = GetPlayerPed(source)
        local inCar = GetVehiclePedIsIn(ped, false)
        local data, look

        if kind == 'shoe' then
            if inCar ~= 0 or surface == 'grass' or surface == 'skid' then return false end
            data = shoeData(source, player.charId)
            if surface == 'blood' then
                -- walked through a blood stain: that blood is in the print
                local ev = WhipEvidence.Evidence.get(bloodId)
                if not ev or ev.kind ~= 'blood' or #(ev.coords - pos) > 30.0 then return false end
                data.blood = ev.data and ev.data.blood
            end
            look = { s = surface }
        else
            local ent = net > 0 and NetworkGetEntityFromNetworkId(net) or 0
            if not ent or ent == 0 or not DoesEntityExist(ent) or ent ~= inCar then return false end
            if GetPedInVehicleSeat(ent, -1) ~= ped then return false end
            if #(GetEntityCoords(ent) - pos) > 25.0 then return false end
            data = tyreData(ent, wheels.type, wheels.mod)
            look = { s = surface, l = math.min(14.0, math.max(2.0, len)), w = math.min(3.0, wheels.gauge), b = data.vtype == 'bike' or nil }
        end
        data.surface, data.look = surface, look

        local minutes = tonumber(Config.TrackMinutes) or 20
        local id = WhipEvidence.Evidence.create(kind == 'shoe' and 'shoeprint' or 'tyre_track', {
            coords = pos, heading = heading % 360, data = data, lifetime = math.max(60, minutes * 60),
        })
        if id then remember(player.charId, id) end
    end)

    -- Police takes a print of a person's shoes (to compare)
    Whip.core:SecureEvent('whip_evidence:shoeSample', {
        rateLimit = 3000,
        params = { { 'target', 'player', { range = 3.0 } }, { 'street', 'string', 80, 'Unknown' } },
    }, function(source, player, target, street)
        if not WhipEvidence.isPolice(source) then return false, L('police_only') end
        if not WhipEvidence.can(source, 'evidence_collect') then return false, WhipEvidence.why(source, 'evidence_collect') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        exports.whip_core:NotifyPlayer(target.source, L('being_shoeprinted'), 'info')
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('collect', {
            label = L('taking_shoeprint'), duration = 3500, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(GetPlayerPed(target.source)), range = 3.5 },
        }))
        if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        local meta = bagMeta(source, player, 'shoeprint', L('type_shoe_person'), target.fullName, street)
        exports.whip_core:LogActivity(source, 'evidence_shoeprint', { detail = target.fullName })
        local ok, why = giveReference(source, meta, shoeData(target.source, target.charId), 'Shoe print ' .. target.fullName)
        if not ok then return false, why end
    end)

    -- Police takes a print of a car's tyres (to compare). Rims and tyres come from the client that sees the car.
    Whip.core:SecureEvent('whip_evidence:tyreSample', {
        rateLimit = 3000,
        params = {
            { 'net', 'id', 1, 2147483647 },
            { 'wheels', 'record', { { 'type', 'int', -1, 30, -1 }, { 'mod', 'int', -1, 1000, -1 } } },
            { 'street', 'string', 80, 'Unknown' },
        },
        near = {
            at = function(_, _, net)
                local ent = NetworkGetEntityFromNetworkId(net)
                return (ent and ent ~= 0 and DoesEntityExist(ent)) and GetEntityCoords(ent) or nil
            end,
            range = 6.0,
        },
    }, function(source, player, net, wheels, street)
        local ent = NetworkGetEntityFromNetworkId(net)
        if not ent or ent == 0 or not DoesEntityExist(ent) then return false, L('vehicle_not_found') end
        if not WhipEvidence.isPolice(source) then return false, L('police_only') end
        if not WhipEvidence.can(source, 'evidence_collect') then return false, WhipEvidence.why(source, 'evidence_collect') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('collect', {
            label = L('taking_tyreprint'), duration = 3500, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(ent), range = 4.5 },
        }))
        if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        if not DoesEntityExist(ent) then return false, L('vehicle_not_found') end
        local plate = (GetVehicleNumberPlateText(ent) or '?'):gsub('^%s+', ''):gsub('%s+$', '')
        local meta = bagMeta(source, player, 'tyre_track', L('type_tyre_vehicle'), L('vehicle_plate', plate), street)
        exports.whip_core:LogActivity(source, 'evidence_tyreprint', { detail = plate })
        local ok, why = giveReference(source, meta, tyreData(ent, wheels.type, wheels.mod), 'Tyre print ' .. plate)
        if not ok then return false, why end
    end)
end

-- Dev tools: test data for the admin's own shoes and a made-up car
function WhipEvidence.Tracks.testShoe(source, charId) return shoeData(source, charId) end
function WhipEvidence.Tracks.testTyre()
    return { profile = code('RP', 'test', 0, -1), width = 225, vtype = 'automobile' }
end

AddEventHandler('playerDropped', function() shoes[source] = nil end)
