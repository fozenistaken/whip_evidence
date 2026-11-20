-- Config as a page in /whip -> Settings -> Forensics
local function chance(key, label)
    return { key = 'DropChance.' .. key, type = 'int', min = 0, max = 100, unit = '%', label = label }
end

local function restart(entry)
    entry.apply, entry.why = 'restart', 'Built when the resource starts'
    return entry
end

Whip.configPage({
    label = 'Forensics',
    groups = {
        { label = 'General', settings = {
            { key = 'Debug', type = 'bool', label = 'Debug prints' },
            restart({ key = 'Locale', type = 'enum', label = 'Language', help = 'Texts for players (locales/).',
              options = { { value = 'en', label = 'English' }, { value = 'de', label = 'Deutsch' },
                          { value = 'fr', label = 'Français' }, { value = 'es', label = 'Español' },
                          { value = 'it', label = 'Italiano' }, { value = 'pl', label = 'Polski' } } }),
            restart({ key = 'PoliceJobs', type = 'list', item = { type = 'string', maxLen = 40 }, label = 'Police jobs',
              help = 'Job keys from your job scripts or /whip -> Jobs. On duty they collect evidence, run GSR tests and use the labs. Nothing is created.' }),
            { key = 'UsePermissions', type = 'bool', label = 'Rank permissions',
              help = 'On: each action needs the rank level below. Off: every on-duty officer may do everything.' },
            { key = 'Permissions', type = 'record', label = 'Lowest rank level',
              help = 'The level of the rank in /whip -> Jobs (1-100), the same for every police job.',
              fields = (function()
                  local list = {}
                  for _, p in ipairs(WhipEvidence.PERMISSIONS) do
                      list[#list + 1] = { key = p[1], type = 'int', min = 1, max = 100, label = p[2] }
                  end
                  return list
              end)() },
        } },
        { label = 'Evidence', settings = {
            { key = 'MaxEvidence', type = 'int', min = 10, max = 2000, label = 'Max evidence at once' },
            { key = 'MinDistance', type = 'number', min = 0.2, max = 10, step = 0.1, unit = 'm', label = 'Distance between evidence' },
            { key = 'PickupDistance', type = 'number', min = 0.5, max = 5, step = 0.1, unit = 'm', label = 'Pickup reach' },
            { key = 'SeeDistance', type = 'number', min = 5, max = 100, step = 1, unit = 'm', label = 'View distance',
              help = 'Aimed flashlight or camera: evidence within this range gets a marker and info.' },
            { key = 'RenderDistance', type = 'number', min = 10, max = 300, step = 5, unit = 'm', label = 'Prop view distance',
              help = 'Lower = less work for every player.' },
            { key = 'MaxShotDistance', type = 'number', min = 10, max = 500, step = 5, unit = 'm', label = 'Max shot distance' },
            { key = 'NeedFlashlight', type = 'bool', label = 'Only visible with flashlight or camera' },
            { key = 'MaxFails', type = 'int', min = 1, max = 10, label = 'Fails until ruined' },
            { key = 'BagsIntoCase', type = 'bool', label = 'New bags into the evidence case',
              help = 'Carried and not full: new bags go into the case first.' },
            { key = 'NeedEmptyBag', type = 'bool', label = 'Collecting uses up an empty bag',
              help = 'Police need whip_evidence_empty_bag items to collect evidence.' },
            { key = 'ReleaseRadius', type = 'number', min = 5, max = 100, step = 1, unit = 'm', label = 'Release crime scene radius',
              help = 'Police clears everything this close from the F1 wheel.' },
            { key = 'Photo', type = 'record', label = 'Crime scene photos',
              help = 'A real screenshot, kept in the database.',
              fields = {
                  { key = 'Width', type = 'int', min = 0, max = 3840, unit = 'px', label = 'Picture width (0 = full screen)' },
                  { key = 'Format', type = 'enum', options = { { value = 'webp', label = 'WebP (sharp, small)' }, { value = 'jpg', label = 'JPG' } }, label = 'Format' },
                  { key = 'Quality', type = 'number', min = 0.1, max = 1, step = 0.05, label = 'Quality' },
                  { key = 'MaxKB', type = 'int', min = 50, max = 4000, unit = 'KB', label = 'Biggest picture kept' },
                  { key = 'KeepDays', type = 'int', min = 0, max = 3650, unit = 'days', label = 'Delete pictures after (0 = never)' },
              } },
            { key = 'HandProps', type = 'bool', label = 'Props in the hand', help = 'Notepad, sponge, torch and the like while a bar runs (Config.Animations).' },
            { key = 'MinigameLevel', type = 'enum', label = 'Minigame difficulty', options = {
                { value = 'easy', label = 'Easy' }, { value = 'medium', label = 'Medium' }, { value = 'hard', label = 'Hard' } } },
            { key = 'Minigames', type = 'record', label = 'Minigame per job',
              help = 'The forensic game, or WHIP\'s ring.',
              fields = (function()
                  local games = { { value = 'dust', label = 'Dust for prints' }, { value = 'tweezers', label = 'Tweezers' },
                      { value = 'swab', label = 'Swab' }, { value = 'pull', label = 'Pull it out' },
                      { value = 'shards', label = 'Pick up fragments' }, { value = 'gsrswab', label = 'GSR swab' },
                      { value = 'castshoe', label = 'Plaster cast (shoe)' }, { value = 'casttyre', label = 'Plaster cast (tyre)' },
                      { value = 'fibers', label = 'Glove fibres' }, { value = 'ring', label = 'WHIP ring' } }
                  local list = {}
                  for _, row in ipairs({ { 'fingerprint', 'Fingerprint' }, { 'casing', 'Casing' }, { 'blood', 'Blood' },
                      { 'bullet', 'Bullet' }, { 'vehicle_fragment', 'Vehicle fragments' }, { 'gsr', 'GSR test' },
                      { 'wipe', 'Civilians wiping' }, { 'dust', 'Dusting a weapon' }, { 'body_bullet', 'Bullet from a body' },
                      { 'shoeprint', 'Shoe print' }, { 'tyre_track', 'Tyre track' }, { 'cleaned', 'Cleaned spot' },
                      { 'fiber_sample', 'Glove fibres from a person' } }) do
                      list[#list + 1] = { key = row[1], type = 'enum', label = row[2], options = games }
                  end
                  return list
              end)() },
            { key = 'SkillCheck', type = 'record', label = 'Skill check (ring)',
              help = 'Bigger gap, fewer rounds and more time make it easier.',
              fields = {
                  { key = 'pieces', type = 'int', min = 1, max = 16, label = 'Ring pieces' },
                  { key = 'widest', type = 'int', min = 1, max = 16, label = 'Gap at start (pieces)' },
                  { key = 'narrowest', type = 'int', min = 1, max = 16, label = 'Gap at end (pieces)' },
                  { key = 'parts', type = 'int', min = 1, max = 20, label = 'Rounds' },
                  { key = 'msPerPart', type = 'int', min = 200, max = 5000, unit = 'ms', label = 'Time per round' },
              } },
            chance('casing', 'Casing chance'),
            chance('bullet', 'Bullet chance'),
            chance('vehicle_fragment', 'Vehicle fragment chance'),
            chance('runover', 'Fragment chance when run over'),
            chance('carcrash', 'Fragment chance car against car'),
            chance('weapon_blood', 'Blood on melee weapons'),
            chance('blood', 'Blood chance'),
            chance('fingerprint', 'Fingerprint chance'),
            { key = 'Aging.Fresh', type = 'int', min = 0, max = 7200, unit = 's', label = 'Too fresh to collect for', help = '0 = can be collected right away.' },
            { key = 'Aging.Old', type = 'int', min = 60, max = 14400, unit = 's', label = 'Red from' },
            { key = 'Aging.Lifetime', type = 'int', min = 120, max = 28800, unit = 's', label = 'Removed after' },
            { key = 'RainFactor', type = 'number', min = 0.05, max = 1, step = 0.05, label = 'Time left in rain (share)' },
            { key = 'AgeShown', type = 'enum', label = 'Age on the scan and photos', help = 'Real traces have no clock on them.',
              options = { { value = 'exact', label = 'Exact (12 min)' }, { value = 'rough', label = 'Rough (fresh, older, old)' }, { value = 'off', label = 'Not shown' } } },
            { key = 'LabAge', type = 'enum', label = 'Age the lab tells', help = 'Shoe prints and tyre tracks are always rough.',
              options = { { value = 'exact', label = 'Exact (20-30 min)' }, { value = 'rough', label = 'Rough (under 1 h ...)' }, { value = 'off', label = 'Not told' } } },
            { key = 'NoEvidenceZones', type = 'records', widget = 'mapPoints', label = 'Areas without evidence',
              marker = { sprite = 1, colour = 1, name = 'No evidence' },
              fields = {
                  { key = 'name', type = 'string', maxLen = 40, label = 'Name' },
                  { key = 'coords', type = 'vec3', label = 'Centre' },
                  { key = 'radius', type = 'number', min = 1, max = 5000, unit = 'm', label = 'Radius' },
              } },
        } },
        { label = 'Blood', settings = {
            { key = 'Bleeding', type = 'bool', label = 'Bleed when hurt' },
            { key = 'BleedMinDamage', type = 'int', min = 1, max = 100, label = 'Health lost before bleeding', help = 'Health is 0-200.' },
            { key = 'BloodOnDeath', type = 'bool', label = 'Blood where someone dies' },
            { key = 'BloodTrail', type = 'bool', label = 'Blood trail after a hit' },
            { key = 'BloodTrailSeconds', type = 'int', min = 5, max = 300, unit = 's', label = 'Trail lasts (normal hit)',
              help = 'For a hit of 30 health. Light hits shorter, heavy ones up to twice as long. Healing stops it.' },
            { key = 'BloodTrailMeters', type = 'number', min = 2, max = 20, step = 0.5, unit = 'm', label = 'Trail: a drop every',
              help = 'At first. The drops get further apart towards the end.' },
            { key = 'BloodCriticalHealth', type = 'int', min = 0, max = 199, label = 'Keeps bleeding at or below health',
              help = 'Until healed. 0 = off. Alive is 100-200.' },
            { key = 'BloodTrailHealth', type = 'int', min = 101, max = 199, label = 'Badly hurt below health',
              help = 'Carrying someone this hurt gets their blood on you. Alive is 100-200.' },
        } },
        { label = 'Shoe prints and tyre tracks', settings = {
            { key = 'Tracks', type = 'bool', label = 'Shoe prints and tyre tracks', help = 'Mud, sand, snow and blood. Tyres also on grass and when skidding.' },
            { key = 'TrackMinutes', type = 'int', min = 1, max = 240, unit = 'min', label = 'Stay for' },
            { key = 'TrackMaxPerPlayer', type = 'int', min = 1, max = 100, label = 'Most per player', help = 'The oldest go first.' },
            { key = 'TrackPolice', type = 'bool', label = 'Police on duty leave some too' },
        } },
        { label = 'Gunshot residue', settings = {
            { key = 'GsrMinutes', type = 'int', min = 1, max = 240, unit = 'min', label = 'Stays for' },
            { key = 'GsrHud', type = 'bool', label = 'Show on the HUD', help = 'A ring on the player\'s own HUD while they have GSR.' },
            { key = 'WashSeconds', type = 'int', min = 3, max = 120, unit = 's', label = 'Washing takes', help = 'In water (F1 wheel), or swimming this long.' },
            { key = 'GsrRainSeconds', type = 'int', min = 10, max = 900, unit = 's', label = 'Rain washes it off after', help = 'On foot, outside.' },
            restart({ key = 'GsrCleaners', type = 'records', label = 'Cleaning items', help = 'Right-click the item to clean off GSR.',
              fields = {
                  { key = 'item', type = 'string', maxLen = 50, pattern = '^[%w_]+$', patternWhy = 'an item name', label = 'Item' },
                  { key = 'seconds', type = 'int', min = 1, max = 120, unit = 's', label = 'Takes' },
                  { key = 'use', type = 'enum', options = { { value = 'remove', label = 'Used up' }, { value = 'wear', label = 'Wears out' },
                      { value = 'keep', label = 'Stays' } }, label = 'After use' },
                  { key = 'blood', type = 'bool', label = 'Also cleans blood' },
              } }),
        } },
        { label = 'Blood on clothes and gloves', settings = {
            { key = 'BloodOnClothes', type = 'bool', label = 'Blood on clothes', help = 'Own blood when hurt, others\' when close by or carrying them.' },
            { key = 'BloodOnHud', type = 'bool', label = 'Blood: show on the HUD' },
            { key = 'BloodOnMinutes', type = 'int', min = 5, max = 1440, unit = 'min', label = 'Blood fades after' },
            { key = 'BloodSplashRange', type = 'number', min = 0, max = 5, step = 0.1, unit = 'm', label = 'Blood splashes on people within' },
            { key = 'GloveHud', type = 'bool', label = 'Gloves: show their condition on the HUD' },
            { key = 'GloveWearShot', type = 'number', min = 0, max = 20, step = 0.1, unit = '%', label = 'Glove wear per shot' },
            { key = 'GloveWearTouch', type = 'number', min = 0, max = 50, step = 0.5, unit = '%', label = 'Glove wear per touch' },
            { key = 'GloveTornLeak', type = 'int', min = 0, max = 100, unit = '%', label = 'Print through torn gloves' },
        } },
        { label = 'Bodies', settings = {
            { key = 'Bodies', type = 'bool', label = 'Bodies can be examined', help = 'Killed by a player: people and pedestrians.' },
            { key = 'BodyKeepMinutes', type = 'int', min = 5, max = 240, unit = 'min', label = 'Pedestrian bodies stay for' },
            { key = 'BodyReportDays', type = 'int', min = 0, max = 365, unit = 'days', label = 'Post-mortem reports kept for (0 = forever, on start)' },
            { key = 'BodyMax', type = 'int', min = 1, max = 40, label = 'Most pedestrian bodies at once' },
            { key = 'BodyHoldMinutes', type = 'int', min = 0, max = 60, unit = 'min', label = 'No respawn while examined, up to', help = '0 = players can always respawn.' },
            { key = 'BodyBulletStays', type = 'int', min = 0, max = 100, unit = '%', label = 'Bullet stays in the body' },
            { key = 'ThroughShotRange', type = 'number', min = 0, max = 100, step = 5, unit = 'm', label = 'A bullet through a body flies on',
              help = 'It lands in the first wall, ground, object or car behind the body. 0 = off.' },
        } },
        { label = 'Vehicles and weapons', settings = {
            { key = 'VehicleTraceMinutes', type = 'int', min = 1, max = 240, unit = 'min', label = 'Vehicle traces stay for' },
            { key = 'CarCrash', type = 'bool', label = 'Car crashes leave traces', help = 'Fragments of both cars and foreign paint on each.' },
            { key = 'PrintDelayMin', type = 'int', min = 5, max = 600, unit = 's', label = 'Print after (min)' },
            { key = 'PrintDelayMax', type = 'int', min = 5, max = 900, unit = 's', label = 'Print after (max)' },
            { key = 'GloveLeakChance', type = 'int', min = 0, max = 100, unit = '%', label = 'Print despite gloves' },
            { key = 'FiberChance', type = 'int', min = 0, max = 100, unit = '%', label = 'Gloves leave fibres', help = 'When the gloves stop a print (cars, weapons).' },
            { key = 'BleachRadius', type = 'number', min = 0.5, max = 10, step = 0.5, unit = 'm', label = 'Bleach cleans within' },
            { key = 'BleachMinutes', type = 'int', min = 1, max = 480, unit = 'min', label = 'Cleaned spot stays for' },
            { key = 'SerialRestoreChance', type = 'int', min = 0, max = 100, unit = '%', label = 'Filed serial: each character comes back' },
            { key = 'SerialLostChance', type = 'int', min = 0, max = 100, unit = '%', label = 'Filed serial: nothing comes back' },
            { key = 'WeaponPrintHours', type = 'int', min = 1, max = 720, unit = 'h', label = 'Weapon prints stay for' },
        } },
        { label = 'Labs', settings = {
            restart({ key = 'Labs', type = 'records', unique = 'id', minItems = 1, label = 'Labs',
              help = 'Each lab is a storage and its analysis device.',
              fields = {
                  { key = 'id', type = 'string', maxLen = 32, pattern = '^[%w_%-]+$', patternWhy = 'letters, digits, _ and -', label = 'ID' },
                  { key = 'label', type = 'string', maxLen = 40, label = 'Name' },
                  { key = 'stash', type = 'vec3', here = true, label = 'Storage' },
                  { key = 'heading', type = 'number', min = 0, max = 360, step = 1, label = 'Storage heading' },
                  { key = 'device', type = 'vec3', here = true, label = 'Analysis device' },
                  { key = 'screen', type = 'vec3', here = true, label = 'Screen (monitor)' },
                  { key = 'screenHeading', type = 'number', min = 0, max = 360, step = 1, label = 'Screen heading' },
                  { key = 'screenModel', type = 'string', maxLen = 64, pattern = '^[%w_]+$', patternWhy = 'a prop name or none',
                    label = 'Screen model', help = 'Any prop, e.g. prop_monitor_w_large. none = use a monitor that is already there. Fit it: /w -> Forensics -> Fit the lab screen.' },
                  { key = 'slots', type = 'int', min = 1, max = 50, label = 'Slots' },
                  { key = 'weight', type = 'number', min = 1, max = 500, step = 1, unit = 'kg', label = 'Max weight' },
              } }),
            restart({ key = 'Lockers', type = 'records', unique = 'id', minItems = 1, label = 'Evidence lockers',
              help = 'Where officers open the locker of a case. Every case opens at every locker.',
              fields = {
                  { key = 'id', type = 'string', maxLen = 32, pattern = '^[%w_%-]+$', patternWhy = 'letters, digits, _ and -', label = 'ID' },
                  { key = 'label', type = 'string', maxLen = 40, label = 'Name' },
                  { key = 'coords', type = 'vec3', here = true, label = 'Position' },
              } }),
            { key = 'CaseSlots', type = 'int', min = 10, max = 200, label = 'Slots per case locker' },
            { key = 'LabMinMinutes', type = 'int', min = 0, max = 120, unit = 'min', label = 'Analysis at least',
              help = 'Each bag takes time by its age (fresh about 1 min, old about 2.5 min), all added up.' },
            { key = 'LabMaxMinutes', type = 'int', min = 0, max = 120, unit = 'min', label = 'Analysis at most' },
            { key = 'LabPartial', type = 'bool', label = 'Old traces partly readable', help = 'Over 30 min old when collected: sometimes only part of the result.' },
            { key = 'LabPartialChance', type = 'int', min = 0, max = 100, unit = '%', label = 'Partly readable chance' },
        } },
        { label = 'Weapons', settings = {
            restart({ key = 'Calibers', type = 'map', each = { type = 'string', maxLen = 40 }, keyPattern = '^[%w_%-]+$',
              keyWhy = 'Weapon item name, e.g. gunny_pistol', keyLabel = 'Weapon', label = 'Caliber per weapon' }),
            { key = 'IgnoreWeapons', type = 'list', item = { type = 'string', maxLen = 50 }, label = 'No evidence / GSR',
              help = 'Item names of weapons that leave nothing behind.' },
            restart({ key = 'MeleeWeapons', type = 'list', item = { type = 'string', maxLen = 50 }, label = 'Melee weapons with prints' }),
        } },
    },
})
