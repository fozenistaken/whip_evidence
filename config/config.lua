-- Defaults. Admins change almost everything in game: /whip -> Settings -> Forensics.
-- Values saved in /whip win over this file.
Config = {
    Debug = false,
    Locale = 'en',   -- language: 'en', 'de', 'fr', 'es', 'it' or 'pl' (files in locales/)

    -- Jobs that collect evidence, run GSR tests and use the labs (on duty).
    -- Only listened to: the jobs come from your job scripts or /whip -> Jobs, nothing is created.
    PoliceJobs = { 'lspd', 'bcso' },   -- pure-whip-police departments

    -- Rank permissions: the lowest rank level (1-100, the level of the rank in /whip -> Jobs) that may do it.
    -- UsePermissions = false: every on-duty officer may do everything.
    UsePermissions = true,
    Permissions = {
        evidence_scan        = 1,    -- scan (flashlight, camera)
        evidence_photo       = 1,    -- crime scene photos
        evidence_collect     = 10,   -- collect evidence
        evidence_gsr         = 10,   -- GSR tests
        evidence_vehicle     = 10,   -- collect vehicle traces
        evidence_laser       = 10,   -- laser pointer
        evidence_sign        = 10,   -- sign for evidence
        evidence_clear       = 10,   -- clear away single traces
        evidence_upload      = 10,   -- upload to a case (MDT)
        evidence_locker      = 10,   -- open case lockers
        evidence_body        = 10,   -- examine bodies
        evidence_dust        = 20,   -- dust weapons for prints
        evidence_release     = 20,   -- release crime scenes
        evidence_lab         = 20,   -- run lab analyses
        evidence_locker_take = 20,   -- take items out of case lockers (without: look only)
        evidence_case_close  = 40,   -- close cases
    },

    -- Evidence
    MaxEvidence     = 500,    -- more at once? the oldest is removed
    DropMaxPerPlayer = 60,    -- blood and prints one player leaves at once (more: their own oldest go)
    MinDistance     = 1.6,    -- metres between two pieces of evidence
    PickupDistance  = 1.5,    -- metres to pick up
    SeeDistance     = 25.0,   -- metres you see evidence with a flashlight or camera (markers and info)
    RenderDistance  = 50.0,   -- metres the props are shown
    MaxShotDistance = 150.0,  -- max distance from shooter to bullet impact
    NeedFlashlight  = true,   -- evidence only visible with an aimed flashlight or the camera
    MaxFails        = 3,      -- failed attempts before the evidence is ruined
    NeedEmptyBag    = false,  -- true: every collected piece uses up one empty evidence bag
    BagsIntoCase    = true,   -- new bags go into the evidence case first (when carried and not full)

    -- Keys while scanning (players can change them: Settings > Key Bindings > FiveM)
    ScanKeys = {
        Filter = 'G',   -- next filter: all, blood, casings, ...
        Photo  = 'H',   -- take a crime scene photo (camera in hand)
        Cards  = 'K',   -- camera: hide/show the big card of the aimed-at trace (clean view)
    },

    -- Crime scene photos (a real screenshot, kept in the database)
    Photo = {
        Width    = 0,       -- picture width in pixels, 0 = the player's full screen (sharpest)
        Format   = 'webp',  -- 'webp' (sharp and small) or 'jpg'
        Quality  = 0.85,    -- 0.1 - 1.0 (higher = sharper, bigger, slower to send)
        MaxKB    = 2500,    -- bigger pictures are refused
        KeepDays = 60,    -- pictures older than this are deleted on start (0 = keep forever)
    },

    ReleaseRadius = 20.0,   -- metres a "Release crime scene" clears

    -- Animations and props while a bar runs. Taken from WHIP's emotes (try them with /e <name>);
    -- animation and prop always come from the same emote, the offsets only fit that animation.
    -- HandProps = false: animations without props.
    HandProps = true,
    Animations = {
        collect      = { anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 } },            -- /e medic2
        label_bag    = { anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', flag = 49 },              -- /e notepad
                         prop = { model = 'prop_notepad_01', bone = 18905, offset = { 0.1, 0.02, 0.05 }, rot = { 10.0, 0.0, 0.0 } } },
        swab_person  = { anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 } },                               -- at their hands
        clear        = { anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 } },             -- /e medic2
        bullet       = { anim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 49 } },                         -- /e inspect
        laser        = { anim = { dict = 'random@train_tracks', clip = 'idle_e', flag = 49 } },                         -- /e inspect
        wipe         = { anim = { dict = 'timetable@floyd@clean_kitchen@base', clip = 'base', flag = 49 },             -- /e clean
                         prop = { model = 'prop_sponge_01', bone = 28422, offset = { 0.0, 0.0, -0.01 }, rot = { 90.0, 0.0, 0.0 } } },
        release      = { anim = { dict = 'missfam4', clip = 'base', flag = 49 },                                        -- /e clipboard
                         prop = { model = 'p_amb_clipboard_01', bone = 36029, offset = { 0.16, 0.08, 0.1 }, rot = { -130.0, -50.0, 0.0 } } },
        body_examine = { anim = { scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD' } },                                        -- /e medic
        body_sample  = { anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 } },             -- /e medic2
        vehicle      = { anim = { dict = 'amb@world_human_security_shine_torch@male@base', clip = 'base', flag = 49 }, -- /e patrolf1
                         prop = { model = 'prop_cs_police_torch_02', bone = 60309, offset = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 80.0 } } },
        vehicle_clean = { anim = { dict = 'amb@world_human_maid_clean@', clip = 'base', flag = 49 },                    -- /e clean2
                         prop = { model = 'prop_sponge_01', bone = 28422, offset = { 0.0, 0.0, -0.01 }, rot = { 90.0, 0.0, 0.0 } } },
        dust         = { anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 } },  -- /e mechanic4
        wipe_weapon  = { anim = { dict = 'timetable@floyd@clean_kitchen@base', clip = 'base', flag = 49 },             -- /e clean
                         prop = { model = 'prop_sponge_01', bone = 28422, offset = { 0.0, 0.0, -0.01 }, rot = { 90.0, 0.0, 0.0 } } },
        lab          = { anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 49 } },  -- /e type
        locker       = { anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle', flag = 49 } },  -- /e type
        clean_self   = { anim = { dict = 'missheist_agency3aig_23', clip = 'urinal_sink_loop', flag = 49 } },           -- /e cleanhands
        hands_out    = { anim = { dict = 'anim@move_m@prisoner_cuffed', clip = 'idle', flag = 49 } },                   -- /e cuffedfront (the tested person)
        bleach       = { anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 } },             -- /e medic2
        file_serial  = { anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 } },  -- /e mechanic4
        restore_serial = { anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 } },  -- /e mechanic4
    },

    -- Minigame per job. 'ring' = WHIP's ring (Config.SkillCheck below) instead of the forensic game.
    Minigames = {
        fingerprint      = 'dust',      -- brush the print visible, press the tape on
        casing           = 'tweezers',  -- grab it at the rim, carry it into the bag
        blood            = 'swab',      -- rub in circles on the stain
        bullet           = 'pull',      -- steady pull in the green zone (police and civilians)
        vehicle_fragment = 'shards',    -- click every fragment
        gsr              = 'gsrswab',   -- swab the spots on both hands
        wipe             = 'swab',      -- civilians wiping away evidence
        dust             = 'dust',      -- dusting a weapon for prints
        body_bullet      = 'pull',      -- taking a bullet out of a body
        shoeprint        = 'castshoe',  -- pour plaster over the print, lift it when set
        tyre_track       = 'casttyre',  -- the same for a tyre track
        fiber_sample     = 'fibers',    -- fibres from a person's gloves (only the glove's colour)
        cleaned          = 'swab',      -- a swab of a cleaned spot
    },
    MinigameLevel = 'easy',   -- easy, medium or hard

    -- Skill check when collecting (the ring): bigger gap, fewer rounds, more time = easier
    SkillCheck = {
        pieces    = 4,     -- the ring is cut into this many pieces
        widest    = 2,     -- lit part at the start (in pieces)
        narrowest = 2,     -- lit part at the end (in pieces)
        parts     = 3,     -- rounds
        msPerPart = 1000,  -- time per round
    },

    DropChance = {            -- percent
        casing           = 50,
        blood            = 75,
        bullet           = 50,
        vehicle_fragment = 50,
        runover          = 100,   -- fragments where a car runs someone over (a slow bump only when it kills)
        carcrash         = 100,   -- car against car: a piece of each car on the road, each gets the other one's paint
        weapon_blood     = 100,   -- a stab or a hit with a melee weapon puts the victim's blood on it
        fingerprint      = 80,
    },

    -- Blood
    Bleeding       = true,  -- drip blood when you lose health (shot, fall, crash ...)
    BleedMinDamage = 10,    -- health lost at once before blood drips (health is 0-200)
    BloodOnDeath   = true,  -- always leave blood where you die
    BloodTrail          = true,  -- a hit makes you leave a trail of blood for a while
    BloodTrailSeconds   = 30,    -- how long after a normal hit (30 health); light hits shorter, heavy ones up to twice as long
    BloodTrailMeters    = 4.0,   -- a drop every this many metres at first; further apart towards the end
    BloodCriticalHealth = 115,   -- at or below this it keeps bleeding until healed (0 = off; alive is 100-200)
    BloodTrailHealth    = 150,   -- badly hurt below this: carrying them gets their blood on you

    -- Aging in seconds: green = ready, red = gone soon (blue = too fresh, only if Fresh is above 0)
    Aging = {
        Fresh    = 0,     -- seconds before it can be collected (0 = right away)
        Old      = 1800,  -- red after 30 min
        Lifetime = 2700,  -- removed after 45 min
    },
    RainFactor = 0.25,    -- rain leaves only this share of the remaining time

    -- How old evidence looks (real traces have no clock on them)
    AgeShown = 'rough',   -- scan card, legend, photos: 'exact' (12 min), 'rough' (fresh / a while / older / old), 'off'
    LabAge   = 'rough',   -- the lab's "age at collection": 'exact' (20-30 min), 'rough' (under 1 h ...), 'off'

    -- No evidence inside these areas
    NoEvidenceZones = {
        { name = 'Oil Rig Paleto',     coords = vector3(4331.2090, 7834.4414, 43.2909),  radius = 150.0 },
        { name = 'Oil Rig Los Santos', coords = vector3(-220.7804, -5058.2856, 44.3922), radius = 150.0 },
        { name = 'Cayo Perico',        coords = vector3(4889.8770, -5736.1929, 44.3922), radius = 2000.0 },
    },

    -- Gunshot residue (GSR) on a person
    GsrMinutes     = 30,    -- how long it stays (it fades: strong, then weak traces)
    GsrHud         = true,  -- show it as a ring on the player's HUD
    WashSeconds    = 15,    -- washing it off in water (F1 wheel), or swimming this long
    GsrRainSeconds = 60,    -- on foot outside in the rain this long washes it off
    -- Items that clean it off (right-click the item). use: 'remove' = one is used up, 'wear' = wears out, 'keep' = stays
    -- blood = true: also cleans blood off you
    GsrCleaners = {
        { item = 'water',              seconds = 8,  use = 'remove', blood = false },
        { item = 'whip_evidence_wipe', seconds = 12, use = 'wear',   blood = true },
    },

    -- Blood on clothes and hands: your own when hurt, someone else's when standing next to them or carrying them.
    -- Police swabs it ("Swab clothes for blood"); water, swimming, new clothes or a cleaning item take it off.
    BloodOnClothes   = true,
    BloodOnHud       = true,   -- ring on the player's HUD
    BloodOnMinutes   = 120,    -- fades away after this long
    BloodSplashRange = 1.5,    -- metres: blood gets on whoever stands this close to someone who is hit

    -- Gloves wear out (ring on the HUD). Worn gloves let more prints through, up to GloveTornLeak when torn.
    GloveHud       = true,
    GloveWearShot  = 0.5,   -- % per shot
    GloveWearTouch = 2,     -- % per touch the gloves catch (car, weapon, ...)
    GloveTornLeak  = 60,    -- percent: a print through torn gloves (new gloves: GloveLeakChance)

    -- Shoe prints (mud, sand, snow, blood) and tyre tracks (also grass, and skidding)
    Tracks            = true,
    TrackMinutes      = 20,     -- how long a print or track stays
    TrackMaxPerPlayer = 12,     -- most prints and tracks of one player at once (the oldest go)
    TrackPolice       = false,  -- police on duty leave some too (false: no own prints at a scene)

    -- Bodies: people and pedestrians killed by a player can be examined by police
    -- (time of death, wounds, bullets, blood sample, GSR on the hands).
    Bodies           = true,
    BodyKeepMinutes  = 30,    -- a pedestrian's body stays this long (then it is taken away)
    BodyMax          = 12,    -- most pedestrian bodies kept at once (the oldest goes first)
    -- Only people become bodies. Animals never do (checked in the game); these models never do either.
    -- The animal models are listed again for the server, which cannot ask the game whether a ped is human.
    BodyIgnoreModels = {
        's_m_m_movalien_01', 'u_m_y_zombie_01', 'ig_orleans', 'cs_orleans', 'u_m_m_jesus_01', 'u_m_y_imporage',
        'a_c_boar', 'a_c_boar_02', 'a_c_cat_01', 'a_c_chickenhawk', 'a_c_chimp', 'a_c_chimp_02', 'a_c_chop', 'a_c_chop_02',
        'a_c_cormorant', 'a_c_cow', 'a_c_coyote', 'a_c_coyote_02', 'a_c_crow', 'a_c_deer', 'a_c_deer_02', 'a_c_dolphin',
        'a_c_fish', 'a_c_hen', 'a_c_humpback', 'a_c_husky', 'a_c_killerwhale', 'a_c_mtlion', 'a_c_mtlion_02', 'a_c_panther',
        'a_c_pig', 'a_c_pigeon', 'a_c_poodle', 'a_c_pug', 'a_c_pug_02', 'a_c_rabbit_01', 'a_c_rabbit_02', 'a_c_rat',
        'a_c_retriever', 'a_c_rhesus', 'a_c_rottweiler', 'a_c_seagull', 'a_c_sharkhammer', 'a_c_sharktiger', 'a_c_shepherd',
        'a_c_stingray', 'a_c_westy',
    },
    BodyHoldMinutes  = 10,    -- a dead player can't respawn this long once police examine them (0 = never held)
    BodyReportDays   = 30,    -- post-mortem reports are kept this long for GetBodyReport (0 = forever)
    BodyBulletStays  = 70,    -- percent: a bullet stays in the body (the rest went through)
    ThroughShotRange = 40.0,  -- metres a bullet that went through flies on (into a wall, the ground or a car behind)

    -- Traces inside vehicles: prints, blood, casings, bullet holes, GSR
    VehicleTraceMinutes = 30,   -- how long they stay in the car
    CarCrash            = true, -- car against car (over ~22 km/h) leaves fragments and foreign paint
    PrintDelayMin       = 60,   -- seconds in the car before a print is left (min)
    PrintDelayMax       = 120,  -- ... (max)
    GloveLeakChance     = 5,    -- percent: a print despite gloves
    FiberChance         = 60,   -- percent: gloves that stop a print leave fibres instead (cars, weapons)

    -- Bleach: cleans blood, prints and bloody shoe prints around you (no minigame), leaves a "cleaned spot"
    BleachRadius  = 2.5,    -- metres
    BleachMinutes = 60,     -- how long the cleaned spot stays (the lab finds bleach in a swab of it)

    -- Filed serial numbers: the lab gets part of it back with acid
    SerialRestoreChance = 60,   -- percent per filed character
    SerialLostChance    = 15,   -- percent: nothing comes back at all

    -- Prints on weapons (whip_gunny), dusted at the weapon's right-click menu
    WeaponPrintHours = 48,      -- how long a print stays on a weapon

    -- Labs: each lab is a storage and its analysis device. Add as many as you like.
    Labs = {
        { id = 'mrpd', label = 'Police Lab',
          stash = vector3(-1111.9, -829.42, 31.27), heading = 310.0,
          device = vector3(-1111.9, -829.42, 31.77),
          -- screen: a monitor showing the analysis (leave out for none). Set it with "here" in /whip.
          -- screenModel: any prop, e.g. prop_monitor_w_large (PC monitor), prop_tv_flat_michael (slim TV),
          -- ex_prop_ex_tv_flat_01 (office TV), prop_tv_flat_01 (old TV). 'none' = a monitor already in the map.
          -- Put the picture on the glass: /w -> Forensics -> "Fit the lab screen" (click 3 corners).
          screen = vector3(-1111.3, -828.9, 31.85), screenHeading = 310.0, screenModel = 'prop_monitor_w_large',
          slots = 10, weight = 50.0 },
    },
    LabScreenLogo = 'img/screen/logo.png',   -- your own logo for the lab screen (html/img/screen/), PNG
    -- Analysis time: each bag by its age when collected (fresh ~1 min, older ~1.5, old ~2.5; samples from people,
    -- cars and weapons 1 min; a gun to test-fire 1 min), a little random, all added up, kept between these two
    LabMinMinutes = 2,
    LabMaxMinutes = 15,
    LabPartial       = false,  -- old traces (over 30 min when collected) sometimes come back only partly readable
    LabPartialChance = 40,     -- percent, for those old traces

    -- Evidence lockers: where officers open the locker of a case (case ID asked).
    -- Every case's locker opens at every one of these places. Set the spot in /whip -> Forensics.
    Lockers = {
        { id = 'mrpd', label = 'Evidence Lockers', coords = vector3(452.37, -980.04, 30.69) },
    },
    CaseSlots = 50,        -- slots per case locker

    -- Resources allowed to use the case exports (your MDT). Empty = any resource.
    ApiResources = { 'pure-whip-police' },

    -- Prop per evidence type
    Props = {
        casing           = { label = 'Casing',            model = 'lev_casing',             rotX = -90.0,  rotY = 0.0, z = 0.0 },
        blood            = { label = 'Blood',             model = 'p_bloodsplat_s',         rotX = -90.0,  rotY = 0.0, z = -0.25 },
        bullet           = { label = 'Bullet',            model = 'lev_bullet',             rotX = -90.0,  rotY = 0.0, z = -0.02 },
        vehicle_fragment = { label = 'Vehicle fragments', model = 'v_ret_gc_sprinkler',     rotX = -180.0, rotY = 0.0, z = -0.06 },
        fingerprint      = { label = 'Fingerprint',       model = 'p_banknote_onedollar_s', rotX = 0.0,    rotY = 0.0, z = 0.0 },
        cleaned          = { label = 'Cleaned spot' },  -- left by bleach, drawn on the ground
        shoeprint        = { label = 'Shoe print' },   -- drawn on the ground, no prop
        tyre_track       = { label = 'Tyre track' },
    },

    -- Weapon item -> caliber (whip_gunny). Missing = 'Unknown'
    Calibers = {
        gunny_pistol = '9mm', gunny_pistol_mk2 = '9mm', gunny_combatpistol = '9mm', gunny_appistol = '9mm',
        gunny_snspistol = '9mm', gunny_snspistol_mk2 = '9mm', gunny_vintagepistol = '9mm',
        gunny_ceramicpistol = '9mm', gunny_gadgetpistol = '9mm', gunny_pistol50 = '.50 AE (Action Express)',
        gunny_heavypistol = '.45 ACP', gunny_doubleaction = '.45 ACP', gunny_gusenberg = '.45 ACP',
        gunny_smg = '9mm', gunny_smg_mk2 = '9mm', gunny_microsmg = '9mm', gunny_minismg = '9mm',
        gunny_assaultsmg = '9mm', gunny_combatpdw = '9mm', gunny_machinepistol = '9mm', gunny_tecpistol = '9mm',
        gunny_rifle = '5.56x45 NATO', gunny_rifle_mk2 = '5.56x45 NATO', gunny_carbinerifle = '5.56x45 NATO',
        gunny_carbinerifle_mk2 = '5.56x45 NATO', gunny_advancedrifle = '5.56x45 NATO',
        gunny_specialcarbine = '5.56x45 NATO', gunny_specialcarbine_mk2 = '5.56x45 NATO',
        gunny_bullpuprifle = '5.56x45 NATO', gunny_bullpuprifle_mk2 = '5.56x45 NATO',
        gunny_militaryrifle = '5.56x45 NATO', gunny_tacticalrifle = '5.56x45 NATO',
        gunny_compactrifle = '7.62x39 (AK)', gunny_heavyrifle = '7.62x51 NATO',
        gunny_battlerifle = '7.62x51 NATO', gunny_mg = '7.62x51 NATO', gunny_combatmg = '7.62x51 NATO',
        gunny_combatmg_mk2 = '7.62x51 NATO', gunny_marksmanrifle = '7.62x51 NATO (marksman)',
        gunny_marksmanrifle_mk2 = '7.62x51 NATO (marksman)', gunny_sniperrifle = '.308 Win',
        gunny_heavysniper = '.50 BMG', gunny_heavysniper_mk2 = '.50 BMG', gunny_precisionrifle = '.50 BMG',
        gunny_revolver = '.44 Magnum', gunny_revolver_mk2 = '.357 Magnum', gunny_navyrevolver = '.36 Navy',
        gunny_marksmanpistol = '.22 LR (Long Rifle)', gunny_musket = 'Musket ball',
        gunny_pumpshotgun = '12 gauge', gunny_pumpshotgun_mk2 = '12 gauge', gunny_sawnoffshotgun = '12 gauge',
        gunny_dbshotgun = '12 gauge', gunny_bullpupshotgun = '12 gauge', gunny_combatshotgun = '12 gauge',
        gunny_assaultshotgun = '12 gauge', gunny_heavyshotgun = '12 gauge', gunny_autoshotgun = '12 gauge',
    },

    -- Melee weapons that also keep prints (every gun in Calibers does too)
    MeleeWeapons = {
        'gunny_knife', 'gunny_dagger', 'gunny_machete', 'gunny_switchblade', 'gunny_hatchet', 'gunny_stone_hatchet',
        'gunny_battleaxe', 'gunny_bat', 'gunny_golfclub', 'gunny_crowbar', 'gunny_hammer', 'gunny_wrench',
        'gunny_nightstick', 'gunny_knuckle', 'gunny_poolcue', 'gunny_bottle', 'gunny_torch',
    },

    -- These weapons leave no evidence and no GSR
    IgnoreWeapons = {
        'gunny_stungun', 'gunny_flaregun', 'gunny_firework', 'gunny_raypistol', 'gunny_raycarbine',
        'gunny_rayminigun', 'gunny_railgun', 'gunny_minigun', 'gunny_rpg', 'gunny_hominglauncher',
        'gunny_grenadelauncher', 'gunny_compactlauncher', 'gunny_emplauncher',
    },
}
