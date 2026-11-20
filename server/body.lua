-- Traces on a person, each a stat with a ring on the player's own HUD:
--   blood on clothes and hands (and whose blood it is), and the condition of their gloves.
WhipEvidence.Body = {}

local BLOOD, GLOVES = 'evidence_bloody', 'evidence_gloves'
local DONORS = WhipEvidence.Res .. ':bloodon'   -- flag: "charId,charId,charId" (newest first, up to 3)
local PAIRS = WhipEvidence.Res .. ':gloves'     -- flag: "drawable:condition,..." (each pair keeps its own wear)

local worn = {}    -- [source] = glove drawable worn now
local conds = {}   -- [source] = { [drawable] = condition 0-100 }
local dirty = {}   -- [source] = true: glove conditions not saved yet

local ICON_BLOOD = 'M12,20A6,6 0 0,1 6,14C6,10 12,3.25 12,3.25C12,3.25 18,10 18,14A6,6 0 0,1 12,20Z'
local ICON_GLOVES = 'M7 11V5.5a1.5 1.5 0 0 1 3 0V10h.5V3.5a1.5 1.5 0 0 1 3 0V10h.5V4.5a1.5 1.5 0 0 1 3 0V12h.5V8.5'
    .. 'a1.5 1.5 0 0 1 3 0V15a7 7 0 0 1-7 7h-1a7 7 0 0 1-5.6-2.8L3 15.2a1.5 1.5 0 0 1 2.3-1.9L7 15Z'

local function statOf(source, name)
    local v = exports.whip_core:GetStat(source, name)   -- nil while not loaded
    return type(v) == 'number' and v or 0
end

local function registerStats()
    local ok, why = Whip.core:RegisterStat(BLOOD, {
        type = 'custom', default = 0, min = 0, max = 100, persist = true,
        decay = -100 / math.max(1, (tonumber(Config.BloodOnMinutes) or 120) * 6), decayInterval = 10,
        hud = Config.BloodOnHud ~= false and {
            icon = ICON_BLOOD, color = '#dc2626', order = 61, noCritical = true, showAboveZero = true, glide = true,
        } or nil,
    })
    if not ok then Whip.startProblem('blood stat: %s', tostring(why)) end
    -- 0 = no gloves (ring hidden), 1-101 = condition 0-100 % (red when worn out)
    ok, why = Whip.core:RegisterStat(GLOVES, {
        type = 'custom', default = 0, min = 0, max = 101, persist = false,
        hud = Config.GloveHud ~= false and { icon = ICON_GLOVES, color = '#cbd5e1', order = 62, showAboveZero = true } or nil,
    })
    if not ok then Whip.startProblem('gloves stat: %s', tostring(why)) end
end

for _, key in ipairs({ 'BloodOnMinutes', 'BloodOnHud', 'GloveHud' }) do
    Whip.onConfigChanged(key, function() if Whip.isReady() then registerStats() end end)
end

---------------------------------------------------------------- Blood on clothes

local function donorsOf(source)
    local v, list = Whip.core:GetPlayerFlag(source, DONORS), {}
    if type(v) == 'string' then
        for id in v:gmatch('%d+') do list[#list + 1] = tonumber(id) end
    end
    return list
end

local function addBlood(source, charId, amount)
    if not charId or not Config.BloodOnClothes then return end
    local list = donorsOf(source)
    for i = #list, 1, -1 do
        if list[i] == charId then table.remove(list, i) end
    end
    table.insert(list, 1, charId)
    while #list > 3 do table.remove(list) end
    Whip.core:SetPlayerFlag(source, DONORS, table.concat(list, ','))
    if amount > statOf(source, BLOOD) then exports.whip_core:SetStat(source, BLOOD, math.min(100, amount), 'blood') end
end

function WhipEvidence.Body.bloody(source)
    return statOf(source, BLOOD) > 0
end

function WhipEvidence.Body.clearBlood(source, reason)
    if not WhipEvidence.Body.bloody(source) then return false end
    exports.whip_core:SetStat(source, BLOOD, 0, reason or 'washed')
    Whip.core:SetPlayerFlag(source, DONORS, false)
    return true
end

-- A hit that made them bleed: their own blood on them, and on whoever stands right next to them
function WhipEvidence.Body.onHurt(source, loss)
    if not Config.BloodOnClothes then return end
    local charId = exports.whip_core:GetCharId(source)
    if not charId then return end
    addBlood(source, charId, 40 + loss)
    local pos = GetEntityCoords(GetPlayerPed(source))
    local range = Config.BloodSplashRange or 1.5
    for _, id in ipairs(GetPlayers()) do
        local other = tonumber(id)
        local ped = other ~= source and GetPlayerPed(other) or 0
        if ped ~= 0 and #(GetEntityCoords(ped) - pos) <= range and exports.whip_core:IsPlayerLoaded(other) then
            addBlood(other, charId, 35)
        end
    end
end

-- Whose blood is on them (charIds, newest first), only while there is blood
function WhipEvidence.Body.donors(source)
    if not WhipEvidence.Body.bloody(source) then return {} end
    return donorsOf(source)
end

-- Carrying or escorting someone who is badly hurt or dead: their blood gets on you
AddStateBagChangeHandler('whipEscortedBy', nil, function(bagName, _, holder)
    if not holder or not Config.BloodOnClothes then return end
    local src = tonumber(tostring(bagName):match('^player:(%d+)$'))
    holder = tonumber(holder)
    if not src or not holder then return end
    local hp = statOf(src, 'health')
    if exports.whip_core:IsPlayerDead(src) or (hp > 0 and hp < Config.BloodTrailHealth) then
        addBlood(holder, exports.whip_core:GetCharId(src), 50)
    end
end)

---------------------------------------------------------------- Gloves

local function parse(v)
    local t = {}
    if type(v) == 'string' then
        for d, c in v:gmatch('(%d+):(%d+)') do t[tonumber(d)] = tonumber(c) end
    end
    return t
end

local function encode(t)
    local parts = {}
    for d, c in pairs(t) do parts[#parts + 1] = ('%d:%d'):format(d, math.floor(c + 0.5)) end
    while #parts > 8 do table.remove(parts, 1) end   -- the flag holds 100 characters
    return table.concat(parts, ',')
end

local function condsOf(source)
    conds[source] = conds[source] or parse(Whip.core:GetPlayerFlag(source, PAIRS))
    return conds[source]
end

local function save(source)
    if not dirty[source] then return end
    dirty[source] = nil
    Whip.core:SetPlayerFlag(source, PAIRS, encode(condsOf(source)))
end

-- condition 0-100 of the gloves worn now, nil without gloves
local function condNow(source)
    if not worn[source] then return nil end
    return math.max(0, statOf(source, GLOVES) - 1)
end

-- Wear adds up and is written at most every 2 s (an automatic weapon fires 10 times a second)
local pendingWear = {}

local function applyWear(source, amount)
    local c = condNow(source)
    if not c or not amount or amount <= 0 then return end
    local n = math.max(0, c - amount)
    if n == c then return end
    exports.whip_core:SetStat(source, GLOVES, n + 1, 'wear')
    condsOf(source)[worn[source]] = n
    dirty[source] = true
    if c > 0 and n == 0 then exports.whip_core:NotifyPlayer(source, L('gloves_torn'), 'warning') end
end

-- Fibres of the gloves someone wears now: a number 0-65535 ("FA-3F2A"), nil without gloves.
-- The same gloves always give the same fibre.
function WhipEvidence.Body.fiber(source)
    local d = worn[source]
    if not d then return nil end
    return GetHashKey(('whip_evidence:fiber:%d:%d'):format(GetEntityModel(GetPlayerPed(source)), d)) & 0xFFFF
end

function WhipEvidence.fiberCode(n) return ('FA-%04X'):format(tonumber(n) or 0) end

function WhipEvidence.Body.gloveWear(source, amount)
    if not worn[source] or not amount or amount <= 0 then return end
    pendingWear[source] = (pendingWear[source] or 0) + amount
end

CreateThread(function()
    while true do
        Wait(2000)
        if next(pendingWear) then
            local q = pendingWear
            pendingWear = {}
            for source, amount in pairs(q) do applyWear(source, amount) end
        end
    end
end)

function WhipEvidence.Body.forget(source)
    if pendingWear[source] then applyWear(source, pendingWear[source]); pendingWear[source] = nil end
    save(source)
    worn[source], conds[source], dirty[source] = nil, nil, nil
end

CreateThread(function()
    while true do
        Wait(30000)
        for source in pairs(dirty) do save(source) end
    end
end)

---------------------------------------------------------------- Registration

function WhipEvidence.Body.register()
    registerStats()

    -- Donors are gone once the blood has faded
    Whip.core:OnStatChanged(BLOOD, function(e)
        if e.value <= 0 and (e.old or 0) > 0 then Whip.core:SetPlayerFlag(e.source, DONORS, false) end
    end, nil, { table = true })

    -- The client reports which gloves it wears (-1 = none). Each pair keeps its own wear.
    Whip.core:SecureEvent('whip_evidence:gloves', {
        rateLimit = 500, burst = 3, sheet = 'light',
        params = { { 'drawable', 'int', -1, 5000 } },
    }, function(source, player, drawable)
        -- what the client reports (a FiveM server cannot read a ped's clothes)
        if drawable < 0 then drawable = nil end
        if worn[source] == drawable then return end
        local was = condNow(source)
        if was and worn[source] then
            condsOf(source)[worn[source]] = was
            dirty[source] = true
        end
        worn[source] = drawable
        if not drawable then
            exports.whip_core:SetStat(source, GLOVES, 0, 'gloves off')
            save(source)
            return
        end
        exports.whip_core:SetStat(source, GLOVES, (condsOf(source)[drawable] or 100) + 1, 'gloves on')
    end)

    -- A touch the gloves caught (car, weapon, ...): they wear a little
    Whip.core:SecureEvent('whip_evidence:gloveTouch', {
        rateLimit = 3000, burst = 2, sheet = 'light',
    }, function(source)
        WhipEvidence.Body.gloveWear(source, Config.GloveWearTouch)
    end)

    -- Police takes fibres from the gloves someone wears (to compare with fibres from cars and weapons)
    Whip.core:SecureEvent('whip_evidence:fiberSample', {
        rateLimit = 3000,
        params = { { 'target', 'player', { range = 3.0 } }, { 'street', 'string', 80, 'Unknown' } },
    }, function(source, player, target, street)
        if not WhipEvidence.isPolice(source) then return false, L('police_only') end
        if not WhipEvidence.can(source, 'evidence_collect') then return false, WhipEvidence.why(source, 'evidence_collect') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        if not WhipEvidence.Body.fiber(target.source) then return false, L('no_gloves_on') end
        local passed, res = WhipEvidence.minigame(source, 'fiber_sample')
        if not passed then return false, res == 'busy' and L('busy') or nil end
        exports.whip_core:NotifyPlayer(target.source, L('being_fibered'), 'info')
        TriggerClientEvent('whip_evidence:client:handsOut', target.source, 3000)
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('swab_person', {
            label = L('taking_fibers'), duration = 3000, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(GetPlayerPed(target.source)), range = 3.5 },
        }))
        if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        local fiber = WhipEvidence.Body.fiber(target.source)
        if not fiber then return false, L('no_gloves_on') end
        local meta = WhipEvidence.bagMeta(source, player, 'fiber', L('type_fiber_person'), target.fullName, street)
        exports.whip_core:LogActivity(source, 'evidence_fiber_sample', { detail = target.fullName })
        local ok, why = WhipEvidence.giveReference(source, meta, { fiber = fiber }, 'Glove fibres ' .. target.fullName)
        if not ok then return false, why end
    end)

    -- New clothes: the blood on the old ones is gone
    Whip.core:SecureEvent('whip_evidence:changedClothes', {
        rateLimit = 5000, sheet = 'light',
    }, function(source)
        if WhipEvidence.Body.clearBlood(source, 'changed clothes') then
            exports.whip_core:NotifyPlayer(source, L('clothes_fresh'), 'info')
        end
    end)

    -- Police swabs a person's clothes: one bag per person whose blood is on them (the lab tells the blood type)
    Whip.core:SecureEvent('whip_evidence:bloodSwab', {
        rateLimit = 3000,
        params = { { 'target', 'player', { range = 3.0 } }, { 'street', 'string', 80, 'Unknown' } },
    }, function(source, player, target, street)
        if not WhipEvidence.isPolice(source) then return false, L('police_only') end
        if not WhipEvidence.can(source, 'evidence_collect') then return false, WhipEvidence.why(source, 'evidence_collect') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end

        local passed, res = WhipEvidence.minigame(source, 'blood')
        if not passed then return false, res == 'busy' and L('busy') or nil end
        exports.whip_core:NotifyPlayer(target.source, L('being_swabbed'), 'info')
        TriggerClientEvent('whip_evidence:client:handsOut', target.source, 3000)
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('swab_person', {
            label = L('swabbing'), duration = 3000, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(GetPlayerPed(target.source)), range = 3.5 },
        }))
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        WhipEvidence.wear(source, WhipEvidence.Items.kit)

        local donors = WhipEvidence.Body.donors(target.source)
        exports.whip_core:LogActivity(source, 'evidence_blood_swab', { detail = ('%s: %d sample(s)'):format(target.fullName, #donors) })
        if #donors == 0 then
            exports.whip_core:NotifyPlayer(source, L('no_blood_clothes'), 'info')
            return
        end
        local officer = WhipEvidence.officerLabel(source, player)
        local queries, made = {}, 0
        for _, charId in ipairs(donors) do
            local traits = WhipEvidence.Data.traits(charId)
            if traits and WhipEvidence.useEmptyBag(source) then
                local meta = {
                    evidence_id  = WhipEvidence.Data.newId(),
                    kind         = 'blood',
                    type         = L('type_blood_clothing'),
                    time         = os.date('%Y-%m-%d %H:%M:%S'),
                    street       = street,
                    collected_by = officer,
                    custody      = WhipEvidence.custody(nil, L('custody_collected'), officer),
                    tested_on    = target.fullName,
                }
                local secret = WhipEvidence.Evidence.secretFor('blood', { blood = traits.blood }, meta)
                if WhipEvidence.giveBag(source, meta, 'Blood swab ' .. target.fullName) then
                    queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, 'blood', secret)
                    made = made + 1
                else
                    WhipEvidence.returnEmptyBag(source)
                end
            end
        end
        WhipEvidence.Data.saveBags(queries)
        exports.whip_core:NotifyPlayer(source, L('blood_found', made), 'warning')
    end)
end
