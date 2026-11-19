-- Case lockers. The MDT knows the cases; this resource keeps the evidence of each case in a locker.
-- * An officer uploads analysed evidence from their pockets to a case (MDT): it gets "Case: <id>",
--   a chain of custody entry, and moves into that case's locker.
-- * Officers open a case's locker at any evidence locker (Config.Lockers) by typing the case ID.
--   Taking out and putting back is logged in the chain of custody; only items of that case go back in.
-- * A closed case's locker can only be looked at.
-- Each locker is a WHIP store kind (whip_evidence_case:<caseId>) kept in memory and saved to
-- whip_evidence_cases / whip_evidence_case_items.
WhipEvidence.Cases = {}

local I = WhipEvidence.Items
local KIND = 'whip_evidence_case'
local caseCheck, caseCheckOwner = nil, nil   -- set by the MDT (SetCaseCheck): does a case ID exist?
local openLockers = {}   -- [source] = caseId: lockers on a player's screen (closed on rank/duty changes)
local Cases = {}   -- [caseId] = { id, created, closed, closedBy, taken = { [ref] = { by, at, what } }, slots = { [n] = item } }

local function validId(id)
    id = tostring(id or ''):gsub('^#', '')
    if id == '' or #id > 32 or not id:find('^[%w_%-]+$') then return nil end
    return id
end

local function isGun(item)
    return Config.Calibers[item] ~= nil
end

local function allowedItem(item)
    return item == I.bag or item == I.photo or isGun(item)
end

-- One id per piece of evidence: bag:<id>, photo:<id>, gun:<serial>
local function refOf(item, m)
    m = m or {}
    if item == I.bag and m.evidence_id then return 'bag:' .. m.evidence_id end
    if item == I.photo and m.photo_id then return 'photo:' .. m.photo_id end
    if isGun(item) and m.serial then return 'gun:' .. m.serial end
    return nil
end

local REVEAL = { 'weapon_serial', 'fingerprint', 'blood_type', 'paint', 'ammo', 'age', 'shoe_profile', 'shoe_size', 'tyre_profile', 'tyre_width', 'fiber', 'cleaner' }

-- Uploadable = analysed: no lab value still '???'; a photo always; a gun once the lab test-fired it
local function analysed(item, m)
    if item == I.photo then return true end
    if isGun(item) then return m.ballistics ~= nil end
    for _, k in ipairs(REVEAL) do
        if m[k] == '???' then return false end
    end
    return true
end

-- Would "Upload to case" at a lab take it? Analysed bags, ready-made reports (serial, post-mortem), tested guns
function WhipEvidence.Cases.ready(item, m)
    m = type(m) == 'table' and m or {}
    return allowedItem(item) and refOf(item, m) ~= nil and analysed(item, m)
end

local function gunName(item)
    local def = exports.whip_core:GetItemDef(item)
    return def and def.name or item
end

-- What an MDT gets for one piece of evidence
local function entryOf(item, m)
    m = type(m) == 'table' and m or {}
    local e = { ref = refOf(item, m), item = item, case = m.case, custody = m.custody, analysed = analysed(item, m) }
    if item == I.bag then
        e.kind, e.type = m.kind, m.type
        e.time, e.street, e.collected_by, e.marker, e.photographed = m.time, m.street, m.collected_by, m.marker, m.photographed
        e.tested_on, e.body = m.tested_on, m.body
        if m.kind == 'autopsy' and type(m.report) == 'string' then
            local ok, report = pcall(json.decode, m.report)
            e.report = ok and report or nil
        end
        e.results = {
            ammo = m.ammo, weapon_serial = m.weapon_serial, fingerprint = m.fingerprint, blood_type = m.blood_type,
            paint = m.paint, gsr = m.gsr, ballistics = m.ballistics, age = m.age,
            surface = m.surface, shoe_profile = m.shoe_profile, shoe_size = m.shoe_size,
            tyre_profile = m.tyre_profile, tyre_width = m.tyre_width, fiber = m.fiber, cleaner = m.cleaner, quality = m.quality,
            cause = m.cause, findings = m.findings,
        }
    elseif item == I.photo then
        e.kind, e.type = 'photo', L('type_photo')
        e.photo_id, e.time, e.street, e.scene, e.taken_by = m.photo_id, m.time, m.street, m.scene, m.taken_by
        e.entries, e.cars, e.bodies = m.entries, m.cars, m.bodies
    else
        e.kind, e.type = 'weapon', gunName(item)
        e.serial, e.ballistics, e.caliber = m.serial, m.ballistics, Config.Calibers[item]
    end
    return e
end

local function copyOf(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

local function caseChanged(id, why)
    local c = Cases[id]
    if c then c.touched = os.time() end   -- the locker list shows the latest change first
    TriggerEvent('whip_evidence:caseChanged', id, why)
end

-- Last change of a case after a restart: the newest of its creation, "taken out" times and the custody lines
-- of the items in it ("11/18 22:10 ..."; the year is this one, or last year if that would be in the future).
local function lastChange(c)
    local t = tonumber(c.created) or 0
    for _, e in pairs(c.taken or {}) do
        if tonumber(e.at) and e.at > t then t = e.at end
    end
    local now = os.time()
    local year = tonumber(os.date('%Y'))
    for _, it in pairs(c.slots or {}) do
        local custody = it.metadata and it.metadata.custody
        if type(custody) == 'string' then
            for mo, d, h, mi in custody:gmatch('(%d%d)/(%d%d) (%d%d):(%d%d)') do
                local at = os.time({ year = year, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
                if at and at > now + 86400 then
                    at = os.time({ year = year - 1, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
                end
                if at and at > t and at <= now + 60 then t = at end
            end
        end
    end
    return t
end

---------------------------------------------------------------- Store kind

local function persist(h)
    local c = Cases[h.id]
    if not c then return {} end
    local q = { { query = 'DELETE FROM `whip_evidence_case_items` WHERE `case_id` = ?', values = { c.id } } }
    for slot, it in pairs(c.slots) do
        q[#q + 1] = {
            query = 'INSERT INTO `whip_evidence_case_items` (`case_id`, `slot`, `item`, `amount`, `metadata`) VALUES (?, ?, ?, ?, ?)',
            values = { c.id, slot, it.item, it.amount or 1, json.encode(it.metadata or {}) },
        }
    end
    return q
end

-- Chain of custody and "taken out" list, after a player moved something (not for our own moves)
local function afterMove(h, ctx)
    local src = ctx.source
    local c = Cases[h.id]
    if not src or not c or ctx.direction == 'within' then return end
    CreateThread(function()
        local player = exports.whip_core:GetPlayer(src)
        local who = player and WhipEvidence.officerLabel(src, player) or ('ID ' .. src)
        local ref = refOf(ctx.item, ctx.metadata)
        if ctx.direction == 'out' and ctx.other and ctx.other.slot then
            exports.whip_core:SetItemMetadata(ctx.other, { custody = WhipEvidence.custody((ctx.metadata or {}).custody, L('custody_taken_locker', c.id), who) })
            if ref then c.taken[ref] = { by = who, at = os.time(), what = entryOf(ctx.item, ctx.metadata).type } end
            exports.whip_core:LogActivity(src, 'evidence_locker_take', { detail = ('case %s: %s'):format(c.id, ref or ctx.item) })
        elseif ctx.direction == 'in' then
            exports.whip_core:SetItemMetadata({ kind = KIND, id = c.id, slot = ctx.slot },
                { custody = WhipEvidence.custody((ctx.metadata or {}).custody, L('custody_returned_locker', c.id), who) })
            if ref then c.taken[ref] = nil end
            exports.whip_core:LogActivity(src, 'evidence_locker_return', { detail = ('case %s: %s'):format(c.id, ref or ctx.item) })
        end
        WhipEvidence.Data.saveCase(c)
        caseChanged(c.id, ctx.direction == 'out' and 'taken' or 'returned')
    end)
end

local function registerKind()
    local ok, why = Whip.core:RegisterStoreKind(KIND, {
        resolve = function(key)
            local id = validId(key and key.id)
            return id and Cases[id] and { id = id } or nil
        end,
        instanceId = function(key, h) return KIND .. ':' .. h.id end,
        label = function(key, h) return L('case_label', h.id) end,
        slots = function(h)
            local top = Config.CaseSlots or 50
            for slot in pairs(Cases[h.id] and Cases[h.id].slots or {}) do if slot > top then top = slot end end
            return top
        end,
        maxWeight = function() return math.huge end,
        get = function(h, slot)
            local c = Cases[h.id]
            return c and c.slots[slot] or nil
        end,
        set = function(h, slot, item, amount, metadata)
            local c = Cases[h.id]
            if not c then return false end
            c.slots[slot] = { item = item, amount = amount, metadata = metadata }
            return true
        end,
        clear = function(h, slot)
            local c = Cases[h.id]
            if not c then return false end
            c.slots[slot] = nil
            return true
        end,
        allows = function(h, item)
            if allowedItem(item) then return true end
            return false, L('locker_wrong_case')
        end,
        beforeMove = function(h, ctx)
            local c = Cases[h.id]
            if not c then return false, L('case_not_found') end
            if c.closed then return false, L('case_closed') end
            if ctx.direction == 'in' then
                local m = ctx.metadata or {}
                if tostring(m.case or '') ~= c.id then return false, L('not_this_case', c.id) end
            end
        end,
        afterMove = afterMove,
        persist = persist,
        durability = 'writeBehind',
    })
    if not ok then Whip.startProblem('case lockers: %s', tostring(why)) end
end

---------------------------------------------------------------- Load, create, close

function WhipEvidence.Cases.load()
    local rows, items = WhipEvidence.Data.loadCases()
    Cases = {}
    for _, r in ipairs(rows) do
        local ok, taken = pcall(json.decode, r.taken or '{}')
        Cases[r.id] = { id = r.id, created = r.created, closed = r.closed == 1 or r.closed == true, closedBy = r.closed_by,
                        taken = ok and type(taken) == 'table' and taken or {}, slots = {} }
    end
    for _, r in ipairs(items) do
        local c = Cases[r.case_id]
        if c then
            local ok, meta = pcall(json.decode, r.metadata or '{}')
            c.slots[tonumber(r.slot)] = { item = r.item, amount = tonumber(r.amount) or 1, metadata = ok and meta or {} }
        end
    end
    for _, c in pairs(Cases) do c.touched = lastChange(c) end
end

local function ensureCase(id)
    if not Cases[id] then
        Cases[id] = { id = id, created = os.time(), touched = os.time(), closed = false, taken = {}, slots = {} }
        WhipEvidence.Data.saveCase(Cases[id])
    end
    return Cases[id]
end

---------------------------------------------------------------- What the MDT calls

local function apiAllowed()
    local list = Config.ApiResources or {}
    if #list == 0 then return true end
    local caller = GetInvokingResource()
    if not caller or caller == WhipEvidence.Res then return true end
    for _, res in ipairs(list) do
        if res == caller then return true end
    end
    print(('[%s] %s may not use the case exports (Config.ApiResources)'):format(WhipEvidence.Res, caller))
    return false
end

-- Everything in a player's pockets that could go into a case (analysed or not, see .analysed)
local function pocketEvidence(source)
    local found = {}
    local keys = { I.bag, I.photo }
    for item in pairs(Config.Calibers) do keys[#keys + 1] = item end
    for _, key in ipairs(keys) do
        for _, f in ipairs(exports.whip_core:FindAllItems(source, key) or {}) do
            local ref = refOf(f.item, f.metadata)
            if ref then found[ref] = f end
        end
    end
    -- and what is in the player's evidence cases
    for _, c in ipairs(WhipEvidence.Briefcase.all(source)) do
        for n, it in pairs(WhipEvidence.Briefcase.slotsOf(c.metadata)) do
            local ref = refOf(it.item, it.metadata)
            if ref and not found[ref] then
                found[ref] = { item = it.item, metadata = it.metadata, caseAddr = c.addr, caseSlot = n }
            end
        end
    end
    return found
end

-- GetUploadable(source) -> list of entries (each with .ref, .analysed, .case)
function WhipEvidence.Cases.getUploadable(source)
    local list = {}
    if not WhipEvidence.isPolice(source) then return list end
    for _, f in pairs(pocketEvidence(source)) do list[#list + 1] = entryOf(f.item, f.metadata) end
    table.sort(list, function(a, b) return tostring(a.time or '') > tostring(b.time or '') end)
    return list
end

-- Empty slots in a case's locker (every piece of evidence takes a slot of its own)
local function freeSlots(id)
    local c = Cases[id]
    local top, used = Config.CaseSlots or 50, 0
    for slot in pairs(c and c.slots or {}) do
        used = used + 1
        if slot > top then top = slot end
    end
    return math.max(0, top - used)
end

-- Moves found items ({ item, metadata, addr }) into a case's locker. Results per item.
local function uploadItems(source, who, items, id)
    local results, moved = {}, 0
    local free = freeSlots(id)
    for _, f in ipairs(items) do
        local m = f.metadata or {}
        local r = { ref = f.ref or refOf(f.item, m), ok = false }
        if not f.addr and not f.caseAddr then
            r.why = L('not_in_pockets')
        elseif not analysed(f.item, m) then
            r.why = L('not_analysed')
        elseif m.case and tostring(m.case) ~= id then
            r.why = L('other_case', tostring(m.case))
        elseif free - moved <= 0 then
            -- checked before anything moves: the item stays where it is
            r.why = L('locker_full', id)
        else
            ensureCase(id)
            local custody = WhipEvidence.custody(m.custody, L('custody_uploaded', id), who)
            local ok, why
            if f.caseAddr then
                -- inside an evidence case: out of the case first, then into the locker (back into the case if that fails)
                local out = WhipEvidence.Briefcase.take(f.caseAddr, { [f.caseSlot] = m.evidence_id or m.photo_id })
                if not out then
                    ok, why = false, L('not_in_case_anymore')
                else
                    local copy = copyOf(m)
                    copy.case, copy.custody = id, custody
                    ok, why = exports.whip_core:StoreGive({ kind = KIND, id = id }, f.item, 1, copy, 'Uploaded to case ' .. id)
                    if not ok then WhipEvidence.Briefcase.putBack(source, f.caseAddr, out) end
                end
            else
                ok, why = exports.whip_core:SetItemMetadata(f.addr, { case = id, custody = custody })
            end
            if ok and not f.caseAddr then
                ok, why = exports.whip_core:StoreMove(f.addr, { kind = KIND, id = id }, { reason = 'Uploaded to case ' .. id })
                if not ok then
                    -- back as it was
                    exports.whip_core:SetItemMetadata(f.addr, { custody = m.custody or '' }, m.case == nil and { remove = { 'case' } } or nil)
                end
            end
            if ok then
                m = f.caseAddr and copyOf(m) or m
                m.case, m.custody = id, custody
                r.ok, r.entry = true, entryOf(f.item, m)
                moved = moved + 1
            else
                r.why = why or L('locker_move_failed')
            end
        end
        results[#results + 1] = r
    end
    if moved > 0 then
        exports.whip_core:LogActivity(source, 'evidence_uploaded', { detail = ('case %s: %d item(s)'):format(id, moved) })
        caseChanged(id, 'uploaded')
    end
    return results, moved
end

local function uploadCheck(source, caseId)
    local id = validId(caseId)
    if not id then return false, L('invalid_case') end
    if not WhipEvidence.can(source, 'evidence_upload') then return false, WhipEvidence.why(source, 'evidence_upload') end
    if Cases[id] and Cases[id].closed then return false, L('case_closed') end
    local player = exports.whip_core:GetPlayer(source)
    if not player then return false, 'Player not loaded' end
    return id, WhipEvidence.officerLabel(source, player)
end

-- Upload(source, refs, caseId) -> results { { ref, ok, why?, entry? } }, or false, why
function WhipEvidence.Cases.upload(source, refs, caseId)
    local id, who = uploadCheck(source, caseId)
    if not id then return false, who end
    local pockets = pocketEvidence(source)
    local items, seen = {}, {}
    for _, ref in ipairs(type(refs) == 'table' and refs or { refs }) do
        ref = tostring(ref)
        if not seen[ref] then   -- the same ref twice must not upload twice
            seen[ref] = true
            items[#items + 1] = pockets[ref] or { ref = ref }
        end
    end
    return (uploadItems(source, who, items, id))
end

-- At a lab device: everything analysed in that lab's storage goes to the case
function WhipEvidence.Cases.uploadFromLab(source, labId, caseId)
    local id, who = uploadCheck(source, caseId)
    if not id then return false, who end
    -- the lab knows no cases: the MDT has to say this one exists
    if not caseCheck then return false, L('no_mdt') end
    local okCall, exists = pcall(caseCheck, id, source)
    if not okCall then return false, L('mdt_check_failed') end
    if not exists then return false, L('case_not_in_mdt', id) end
    local containerId, why = WhipEvidence.Lab.storage(labId)
    if not containerId then return false, why end
    local stash = exports.whip_core:StoreRead({ kind = 'container', id = containerId })
    local items, waiting = {}, 0
    for slot, it in pairs(type(stash) == 'table' and stash.items or {}) do
        local m = type(it.metadata) == 'table' and it.metadata or {}
        if allowedItem(it.item) and refOf(it.item, m) and (not m.case or tostring(m.case) == id) then
            if analysed(it.item, m) then
                items[#items + 1] = { item = it.item, metadata = m, addr = { kind = 'container', id = containerId, slot = tonumber(slot) } }
            else
                waiting = waiting + 1
            end
        end
    end
    if #items == 0 then
        return false, waiting > 0 and L('lab_nothing_analysed') or L('lab_nothing')
    end
    if freeSlots(id) == 0 then return false, L('locker_full', id) end
    local results, moved = uploadItems(source, who, items, id)
    if moved == 0 then
        -- nothing went in: say why instead of "0 uploaded"
        return false, (results[1] and results[1].why) or L('locker_move_failed')
    end
    local full, left = L('locker_full', id), 0
    for _, r in ipairs(results) do if r.why == full then left = left + 1 end end
    return moved, waiting, left
end

-- GetCase(caseId) -> { id, closed, closedBy, items = entries in the locker, taken = { ref = { by, at, what } } } or nil
function WhipEvidence.Cases.get(caseId)
    local c = Cases[validId(caseId) or '']
    if not c then return nil end
    local items = {}
    for slot, it in pairs(c.slots) do
        local e = entryOf(it.item, it.metadata)
        e.slot = slot
        items[#items + 1] = e
    end
    table.sort(items, function(a, b) return a.slot < b.slot end)
    return { id = c.id, created = c.created, closed = c.closed, closedBy = c.closedBy, items = items, taken = c.taken }
end

-- CloseCase(caseId, source?) / ReopenCase(caseId, source?): with a source the rank is checked
function WhipEvidence.Cases.setClosed(caseId, closed, source)
    local c = Cases[validId(caseId) or '']
    if not c then return false, L('no_locker') end
    local who = 'MDT'
    if source then
        if not WhipEvidence.can(source, 'evidence_case_close') then return false, WhipEvidence.why(source, 'evidence_case_close') end
        local player = exports.whip_core:GetPlayer(source)
        who = player and WhipEvidence.officerLabel(source, player) or who
    end
    c.closed, c.closedBy = closed == true, closed and who or nil
    WhipEvidence.Data.saveCase(c)
    if closed then WhipEvidence.Cases.closeViewers(c.id) end
    caseChanged(c.id, closed and 'closed' or 'reopened')
    return true
end

---------------------------------------------------------------- Open lockers

local function closeFor(src)
    local id = openLockers[src]
    if not id then return end
    openLockers[src] = nil
    exports.whip_core:CloseStore(src, { kind = KIND, id = id })
end

-- Everyone looking at this case's locker (case closed or deleted)
function WhipEvidence.Cases.closeViewers(id)
    for src, open in pairs(openLockers) do
        if open == id then closeFor(src) end
    end
end

-- Rank, job or duty changed: an open locker closes (opening again checks the new rank)
local function jobChanged(e)
    local src = type(e) == 'table' and tonumber(e.source)
    if src and openLockers[src] then
        closeFor(src)
        exports.whip_core:NotifyPlayer(src, L('locker_closed_job'), 'info')
    end
end
AddEventHandler('whip_core:job:roleChanged', jobChanged)
AddEventHandler('whip_core:job:fired', jobChanged)
AddEventHandler('whip_core:job:clockedOff', jobChanged)
AddEventHandler('playerDropped', function() openLockers[source] = nil end)

local function lockerNear(source)
    local pos = GetEntityCoords(GetPlayerPed(source))
    for _, l in ipairs(Config.Lockers or {}) do
        if #(pos - WhipEvidence.vec(l.coords)) <= 3.0 then return l end
    end
    return nil
end

-- OpenLocker(source, caseId): only at an evidence locker; look-only without the take permission or when closed
function WhipEvidence.Cases.open(source, caseId)
    local id = validId(caseId)
    if not id then return false, L('invalid_case') end
    if not WhipEvidence.can(source, 'evidence_locker') then return false, WhipEvidence.why(source, 'evidence_locker') end
    local locker = lockerNear(source)
    if not locker then return false, L('need_locker') end
    local c = Cases[id]
    if not c then return false, L('no_case_evidence', id) end
    local readOnly = c.closed or not WhipEvidence.can(source, 'evidence_locker_take')
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('locker', {
        label = L('opening_locker'), duration = 1000, icon = 'pickup',
        disable = { move = true, combat = true, car = true },
        near = { coords = WhipEvidence.vec(locker.coords), range = 3.0 },
    }))
    if not done then return false end
    local ok, why = exports.whip_core:OpenStore(source, { kind = KIND, id = id },
        { coords = WhipEvidence.vec(locker.coords), range = 3.0, readOnly = readOnly })
    if not ok then return false, why or L('locker_not_opened') end
    openLockers[source] = id
    exports.whip_core:LogActivity(source, 'evidence_locker_open', { detail = 'case ' .. id })
    if readOnly then
        exports.whip_core:NotifyPlayer(source, c.closed and L('case_closed_look') or L('rank_look'), 'info')
    end
    return true
end

---------------------------------------------------------------- Admin (/w -> Forensics)

function WhipEvidence.Cases.list()
    local list = {}
    for id, c in pairs(Cases) do
        local items, taken = 0, 0
        for _ in pairs(c.slots) do items = items + 1 end
        for _ in pairs(c.taken) do taken = taken + 1 end
        list[#list + 1] = { id = id, created = c.created, closed = c.closed, items = items, taken = taken }
    end
    table.sort(list, function(a, b) return (a.created or 0) > (b.created or 0) end)
    return list
end

-- Open any case's locker without standing at a locker
function WhipEvidence.Cases.adminOpen(source, caseId)
    local id = validId(caseId)
    if not id or not Cases[id] then return false, L('no_locker') end
    local ok, why = exports.whip_core:OpenStore(source, { kind = KIND, id = id })
    if ok then openLockers[source] = id end
    return ok, why
end

-- Deletes the case and everything in its locker (logged as lost)
function WhipEvidence.Cases.delete(caseId, source)
    local id = validId(caseId)
    local c = id and Cases[id]
    if not c then return false, L('no_locker') end
    WhipEvidence.Cases.closeViewers(id)
    local n = 0
    for _ in pairs(c.slots) do n = n + 1 end
    Cases[id] = nil
    MySQL.query.await('DELETE FROM `whip_evidence_case_items` WHERE `case_id` = ?', { id })
    MySQL.query.await('DELETE FROM `whip_evidence_cases` WHERE `id` = ?', { id })
    if source then exports.whip_core:LogActivity(source, 'evidence_case_deleted', { detail = ('case %s (%d item(s) lost)'):format(id, n) }) end
    caseChanged(id, 'deleted')
    return true, n
end

---------------------------------------------------------------- Register

function WhipEvidence.Cases.register()
    WhipEvidence.Cases.load()
    registerKind()

    Whip.core:SecureEvent('whip_evidence:labUpload', {
        rateLimit = 3000,
        params = { { 'lab', 'key', 32 }, { 'case', 'string', 32 } },
        near = {
            at = function(_, _, labId)
                for _, lab in ipairs(Config.Labs) do
                    if lab.id == labId then return WhipEvidence.vec(lab.device) end
                end
            end,
            range = 3.0,
        },
    }, function(source, player, labId, caseId)
        local device
        for _, lab in ipairs(Config.Labs) do
            if lab.id == labId then device = WhipEvidence.vec(lab.device) end
        end
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('lab', {
            label = L('uploading_case'), duration = 1500, icon = 'timer',
            disable = { move = true, combat = true, car = true },
            near = device and { coords = device, range = 3.0 } or nil,
        }))
        if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        local moved, waiting, left = WhipEvidence.Cases.uploadFromLab(source, labId, caseId)
        if not moved then return false, waiting end
        WhipEvidence.Lab.uploaded(labId, validId(caseId), moved, waiting, WhipEvidence.officerLabel(source, player))
        local text = L('lab_uploaded', moved, validId(caseId))
        if waiting > 0 then text = text .. L('lab_upload_waiting', waiting) end
        if (left or 0) > 0 then text = text .. L('lab_upload_full', left) end
        exports.whip_core:NotifyPlayer(source, text, (left or 0) > 0 and 'warning' or 'success')
    end)

    -- The case list (picked with a click instead of typing): open cases by last change, then the closed ones.
    -- mode 'locker': at an evidence locker. mode 'upload': at a lab device (no closed cases: nothing goes in).
    Whip.core:SecureCallback('whip_evidence:lockerCases', {
        rateLimit = 1500, burst = 2,
        params = { { 'mode', 'enum', { 'locker', 'upload' }, 'locker' }, { 'lab', 'string', 32, '' } },
    }, function(source, player, mode, labId)
        if mode == 'upload' then
            if not WhipEvidence.can(source, 'evidence_upload') then return { error = WhipEvidence.why(source, 'evidence_upload') } end
            local here, at = GetEntityCoords(GetPlayerPed(source)), nil
            for _, lab in ipairs(Config.Labs) do
                if lab.id == labId and lab.device then at = WhipEvidence.vec(lab.device) end
            end
            if not at or #(here - at) > 3.5 then return { error = L('lab_too_far') } end
        else
            if not WhipEvidence.can(source, 'evidence_locker') then return { error = WhipEvidence.why(source, 'evidence_locker') } end
            if not lockerNear(source) then return { error = L('need_locker') } end
        end
        local list = {}
        for id, c in pairs(Cases) do
            local items, taken = 0, 0
            for _ in pairs(c.slots) do items = items + 1 end
            for _ in pairs(c.taken) do taken = taken + 1 end
            if not (mode == 'upload' and c.closed) then
                list[#list + 1] = { id = id, items = items, taken = taken, closed = c.closed == true, at = c.touched or c.created or 0 }
            end
        end
        table.sort(list, function(a, b)
            if a.closed ~= b.closed then return not a.closed end
            return a.at > b.at
        end)
        while #list > 500 do list[#list] = nil end
        return { cases = list, now = os.time() }
    end)

    Whip.core:SecureEvent('whip_evidence:openLocker', {
        rateLimit = 1500,
        params = { { 'case', 'string', 32 } },
    }, function(source, player, caseId)
        local ok, why = WhipEvidence.Cases.open(source, caseId)
        if not ok then return false, why end
    end)
end

-- Exports for an MDT (server side). See README "MDT".
exports('GetUploadable', function(source)
    if not apiAllowed() then return {} end
    return WhipEvidence.Cases.getUploadable(source)
end)
exports('Upload', function(source, refs, caseId)
    if not apiAllowed() then return false, 'Not allowed' end
    return WhipEvidence.Cases.upload(source, refs, caseId)
end)
exports('GetCase', function(caseId)
    if not apiAllowed() then return nil end
    return WhipEvidence.Cases.get(caseId)
end)
exports('CloseCase', function(caseId, source)
    if not apiAllowed() then return false, 'Not allowed' end
    return WhipEvidence.Cases.setClosed(caseId, true, source)
end)
exports('ReopenCase', function(caseId, source)
    if not apiAllowed() then return false, 'Not allowed' end
    return WhipEvidence.Cases.setClosed(caseId, false, source)
end)
exports('OpenCaseLocker', function(source, caseId)
    if not apiAllowed() then return false, 'Not allowed' end
    return WhipEvidence.Cases.open(source, caseId)
end)
exports('GetPhotoImage', function(photoId)
    if not apiAllowed() then return nil end
    return WhipEvidence.Data.loadPhoto(photoId)
end)

-- The post-mortem report of an examined body (also after it is gone, for Config.BodyReportDays; nil otherwise).
-- The report item (kind 'autopsy') keeps it for good: entry.report. Pushed too: AddEventHandler('whip_evidence:bodyExamined', fn(report))
exports('GetBodyReport', function(bodyId)
    if not apiAllowed() then return nil end
    return WhipEvidence.Bodies.report(tostring(bodyId or ''))
end)

-- Fingerprint and blood type of a character, for an MDT's prints on file: { fingerprint, blood } or nil
exports('GetTraits', function(charId)
    if not apiAllowed() then return nil end
    return WhipEvidence.Data.traits(tonumber(charId))
end)

-- The MDT tells this resource how to check a case ID (used by the lab's "Upload to a case"):
-- exports.whip_evidence:SetCaseCheck(function(caseId, source) return true/false end)
exports('SetCaseCheck', function(fn)
    if not apiAllowed() then return false, 'Not allowed' end
    caseCheck, caseCheckOwner = fn, GetInvokingResource()
    return true
end)

AddEventHandler('onResourceStop', function(res)
    -- the MDT stopped: its check is gone
    if caseCheck and res ~= WhipEvidence.Res and res == caseCheckOwner then caseCheck, caseCheckOwner = nil, nil end
end)
