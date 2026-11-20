-- Items: evidence bag, crime scene photo, forensics kit, laser pointer, pliers, cleaning cloth, bleach, file
WhipEvidence.ItemDefs = {}

local I = WhipEvidence.Items
local ACT_COPY     = WhipEvidence.Res .. ':copy'
local ACT_SIGN     = WhipEvidence.Res .. ':sign'
local CUSTODY_SEP, CUSTODY_KEEP = ' → ', 6

-- Empty bags: only used up when Config.NeedEmptyBag is on
function WhipEvidence.hasEmptyBags(source, n)
    if not Config.NeedEmptyBag then return true end
    return (exports.whip_core:GetItemCount(source, I.empty) or 0) >= (n or 1)
end

function WhipEvidence.useEmptyBag(source)
    if not Config.NeedEmptyBag then return true end
    return exports.whip_core:RemoveItem(source, I.empty, 1, nil, 'Evidence bagged') == true
end

-- A bag could not be given after all: the empty one goes back
function WhipEvidence.returnEmptyBag(source)
    if Config.NeedEmptyBag then exports.whip_core:AddItem(source, I.empty, 1, nil, 'Evidence bag returned') end
end

-- Chain of custody: "11/16 14:02 Collected · Sgt | Smith → 11/16 14:20 In lab: Police Lab · ..."
-- Keeps the first entry (who collected it) and the newest ones.
function WhipEvidence.custody(old, what, who)
    local list = {}
    if type(old) == 'string' and old ~= '' then
        local from = 1
        while true do
            local a, b = old:find(CUSTODY_SEP, from, true)
            list[#list + 1] = old:sub(from, (a or 0) - 1)
            if not a then break end
            from = b + 1
        end
    end
    list[#list + 1] = ('%s %s%s'):format(os.date('%m/%d %H:%M'), what, who and (' · ' .. who) or '')
    while #list > CUSTODY_KEEP do table.remove(list, 2) end
    return table.concat(list, CUSTODY_SEP)
end

-- Wear: durability drops per use by the item setting "wear" (/whip -> Economy -> Items)
function WhipEvidence.wear(source, item)
    local setting = exports.whip_core:GetItemSetting(item, 'wear')
    local wear = tonumber(setting) or 0
    if wear <= 0 then return end
    local found = exports.whip_core:FindItem(source, item)
    if not found then return end
    local left = (tonumber(found.metadata and found.metadata.durability) or 100) - wear
    if left <= 0 then
        exports.whip_core:StoreTake(found.addr, 1, { reason = 'worn out' })
        local def = exports.whip_core:GetItemDef(item)
        exports.whip_core:NotifyPlayer(source, L('worn_out', (def and def.name) or item), 'warning')
    else
        exports.whip_core:SetItemMetadata(found.addr, { durability = math.floor(left * 10 + 0.5) / 10 })
    end
end

-- Activity log entry that also lands in the bag's own item history (chain of custody)
function WhipEvidence.logBag(source, event, detail, bagId)
    local addr
    for _, found in ipairs(exports.whip_core:FindAllItems(source, WhipEvidence.Items.bag) or {}) do
        if found.metadata and found.metadata.evidence_id == bagId then addr = found.addr break end
    end
    exports.whip_core:LogActivity(source, event, { detail = detail, slotData = addr })
end

local function wearSetting(default)
    return { { key = 'wear', type = 'number', default = default, min = 0, max = 100, step = 0.5, unit = '%',
               label = 'Wear per use', help = '0 = lasts forever' } }
end

local function newTool()
    return { durability = 100 }
end

-- Values the lab reveals, in the order "Copy data" looks for them
local COPY_FIELDS = {
    { 'weapon_serial', L('f_serial') },
    { 'fingerprint', L('f_fingerprint') },
    { 'blood_type', L('f_blood_type') },
    { 'paint', L('f_paint') },
    { 'fiber', L('f_fiber') },
    { 'shoe_profile', L('f_shoe_profile') },
    { 'tyre_profile', L('f_tyre_profile') },
}

function WhipEvidence.ItemDefs.register()
    Whip.core:RegisterItem(I.bag, {
        name = L('item_bag'), desc = L('item_bag_desc'),
        weight = 0.005, type = 'evidence', stack = false, usable = false,
        prop = 'prop_paper_bag_small',
        -- picture per type: html/img/items/bag_casing.webp, bag_bullet.webp, ... (no type = empty bag picture)
        images = { { image = 'html/img/items/bag_{kind}.webp' } },
        metaFields = {
            { key = 'case',          label = L('f_case') },
            { key = 'type',          label = L('f_type') },
            { key = 'time',          label = L('f_time') },
            { key = 'street',        label = L('f_street') },
            { key = 'ammo',          label = L('f_ammo') },
            { key = 'weapon_serial', label = L('f_serial') },
            { key = 'fingerprint',   label = L('f_fingerprint') },
            { key = 'blood_type',    label = L('f_blood_type') },
            { key = 'blood_traces',  label = L('f_blood_traces') },
            { key = 'paint',         label = L('f_paint') },
            { key = 'quality',       label = L('f_quality') },
            { key = 'cause',         label = L('f_cause') },
            { key = 'findings',      label = L('f_findings') },
            { key = 'fiber',         label = L('f_fiber') },
            { key = 'cleaner',       label = L('f_cleaner') },
            { key = 'surface',       label = L('f_surface') },
            { key = 'shoe_profile',  label = L('f_shoe_profile') },
            { key = 'shoe_size',     label = L('f_shoe_size') },
            { key = 'tyre_profile',  label = L('f_tyre_profile') },
            { key = 'tyre_width',    label = L('f_tyre_width') },
            { key = 'gsr',           label = L('f_gsr') },
            { key = 'ballistics',    label = L('f_ballistics') },
            { key = 'tested_on',     label = L('f_tested_on') },
            { key = 'marker',        label = L('f_marker') },
            { key = 'age',           label = L('f_age') },
            { key = 'photographed',  label = L('f_photographed') },
            { key = 'collected_by',  label = L('f_collected_by') },
            { key = 'custody',       label = L('f_custody') },
        },
        contextOptions = {
            { action = ACT_COPY, label = L('opt_copy'), order = 1, anywhere = true },
            { action = ACT_SIGN, label = L('opt_sign'), order = 3, anywhere = true,
              require = WhipEvidence.req('evidence_sign') },
        },
    })

    WhipEvidence.Photo.registerItem(ACT_SIGN)

    Whip.core:RegisterItem(I.kit, {
        name = L('item_kit'), desc = L('item_kit_desc'),
        weight = 3.0, type = 'tool', stack = false, usable = false,
        metaFields = { { key = 'durability', label = L('f_condition'), value = '100' } },
        settings = wearSetting(2.5),
    })

    Whip.core:RegisterItem(I.pliers, {
        name = L('item_pliers'), desc = L('item_pliers_desc'),
        weight = 0.75, type = 'tool', stack = false, usable = false,
        metaFields = { { key = 'durability', label = L('f_condition'), value = '100' } },
        settings = wearSetting(1.0),
    })

    Whip.core:RegisterItem(I.empty, {
        name = L('item_empty'), desc = L('item_empty_desc'),
        weight = 0.005, type = 'tool', stack = true, maxStack = 50, usable = false,
    })

    Whip.core:RegisterItem(I.laser, {
        name = L('item_laser'), desc = L('item_laser_desc'),
        weight = 0.5, type = 'tool', stack = true, maxStack = 10, usable = false,
    })

    Whip.core:RegisterItem(I.wipe, {
        name = L('item_wipe'), desc = L('item_wipe_desc'),
        weight = 0.05, type = 'tool', stack = true, maxStack = 20, usable = false,
    })

    Whip.core:RegisterItem(I.bleach, {
        name = L('item_bleach'), desc = L('item_bleach_desc'),
        weight = 1.0, type = 'consumable', stack = true, maxStack = 5, usable = true,
        prop = 'prop_blox_spray',
    })

    Whip.core:RegisterItem(I.file, {
        name = L('item_file'), desc = L('item_file_desc'),
        weight = 0.3, type = 'tool', stack = false, usable = false,
        metaFields = { { key = 'durability', label = L('f_condition'), value = '100' } },
        settings = wearSetting(20),
    })

    Whip.core:RegisterItemDefaultMetadata(I.kit, newTool)
    Whip.core:RegisterItemDefaultMetadata(I.file, newTool)
    Whip.core:RegisterItemDefaultMetadata(I.pliers, newTool)

    -- Right-click "Copy data": the first analysed value goes to the clipboard
    Whip.core:RegisterContextAction(ACT_COPY, function(source, player, slotData)
        local m = slotData.metadata or {}
        for _, field in ipairs(COPY_FIELDS) do
            local value = m[field[1]]
            if value and value ~= '???' then
                TriggerClientEvent('whip_evidence:client:copy', source, tostring(value), field[2])
                return
            end
        end
        return false, L('copy_nothing')
    end)

    -- Right-click "Sign for evidence": the officer who takes it over signs the chain of custody
    Whip.core:RegisterContextAction(ACT_SIGN, function(source, player, slotData, addr)
        if not WhipEvidence.can(source, 'evidence_sign') then return false, WhipEvidence.why(source, 'evidence_sign') end
        local who = WhipEvidence.officerLabel(source, player)
        local old = slotData.metadata and slotData.metadata.custody
        if type(old) == 'string' and old:sub(-#who) == who then return false, L('sign_already') end
        local ok, why = exports.whip_core:SetItemMetadata(addr, { custody = WhipEvidence.custody(old, L('custody_received'), who) })
        if not ok then return false, why end
        exports.whip_core:LogActivity(source, 'evidence_signed', { detail = who, slotData = addr })
        exports.whip_core:NotifyPlayer(source, L('signed'), 'success')
    end)

end
