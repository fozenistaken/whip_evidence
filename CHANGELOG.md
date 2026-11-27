# Changelog

## 4.3.0

### New

- **Ballistic archive ([whip_gunstore](https://github.com/LeSiiN/whip_gunstore))**: when the lab analyses a casing or a bullet, it asks whip_gunstore's ballistic archive (every gun its stores sold was test-fired). A match adds "Ballistic archive: Matches a gun sold to John Doe on 2026-11-20 (Ammu-Nation Pillbox Hill)". **Also with the serial filed off**: the barrel still matches ("Serial filed off, but the barrel matches a gun sold to ..."), and a partly readable serial does not stop it. The field is `archive` on the bag and in `GetCase` / `Upload` entries (es_mdt shows it as "Archive" without an update). Without whip_gunstore nothing changes.

## 4.2.9

### Fixes

- **Ghost evidence on clients**: evidence made and removed again within a quarter second (the per-player drop cap, `MaxEvidence` pushing the oldest out) reached clients as "removed" first and "added" after it, so they kept a piece the server no longer had (a marker that could not be collected). The add is now taken out of the batch.
- **Correction to 4.2.6 "Shoes and gloves from the server"**: a FiveM server cannot read a ped's clothes (`GetPedDrawableVariation` is client-only), so that check never ran; the sole and fibre codes still come from the client, as before 4.2.6. The dead code is removed. Nothing changes in play.

## 4.2.8

### New

- **"Blood found on the bullet"**: a bullet with blood on it (a through-shot, or one taken out of a body) shows a new field "Blood traces: Blood found on the bullet" on the bag right away, also in an MDT (`results.blood_traces` in `GetCase` / `Upload` entries; es_mdt shows it as "Blood traces" without an update). The blood type itself still comes from the lab.

## 4.2.7

### New

- **Deaths in cars are bodies too**: someone shot dead in a car was already a body; now also a pedestrian killed in a crash (car against car, or a crash nobody caused: the game that owns the ped reports it). A body in a car keeps the car from despawning, and its blood goes into the car (bagged at the door) instead of a pool under it. A pedestrian killed in a car by another car gets impact speed and skid marks in the report, but no "blood on the outside" or run-over pieces (the crash leaves pieces of both cars).
- **Only people become bodies**: animals never do (the game checks `IsPedHuman`, the server checks the model), and neither do the models in `BodyIgnoreModels` (aliens, zombies, Bigfoot, ... ; add your own names or hashes).
- **Through-shots fly on**: a bullet that goes through a body (the share `BodyBulletStays` does not keep) lands behind it, in the first wall, ground or object within `ThroughShotRange` (40 m) as a bullet with a laser trajectory back to the shooter, or as a bullet hole in a car behind (or in the victim's own car, from inside). Same serial and calibre as the gun, `DropChance.bullet`. The bullet carries the victim's blood: "Blood on it" on the scan card, and the lab gives the blood type next to serial and calibre. A bullet taken out of a body has that body's blood on it too.

### Fixes

- **Car crash "refused by the handler", no fragments**: 4.2.6 asked for a dent on one of the cars, but a car's body health often does not reach the server (and servers with low vehicle damage barely dent). Now a crash counts when the server saw one of the cars going faster than 5 m/s in the 2.5 s before, or a dent. A parking bump is ignored without a message.

### Security

- A "hit by a vehicle" from someone who is not driving next to the victim is refused, unless it comes from the game that owns the ped, for a pedestrian in or next to a car.

## 4.2.6

### New

- **Run over = car pieces**: running someone over (fast, or slow but deadly) leaves vehicle fragments in the car's colour where they were hit, and the car counts as involved ("Fragments at the scene"). One drop per victim and impact, `DropChance.runover` (default 100) in `/whip` → Forensics.
- **Case locker full**: uploading to a case checks the locker first. A full locker says so ("The locker of case X is full.") instead of "0 uploaded", items that do not fit stay where they are, and the lab says how many did not fit. MDTs get `why` per item as before.
- **Blood on the car**: a car that runs someone over gets their blood on the outside ("Blood on the outside" on the card). Police bag it at the door with the other traces ("Blood (vehicle, outside)"), the lab gives the blood type. A cleaning cloth wipes it off, a fire burns it.
- **Impact speed and skid marks in the post-mortem report**: "Impact speed: about 50–70 km/h" and "Skid marks: none: no braking before the impact" (or "braked before the impact"). The skid line only shows where the driver leaves tracks (`Tracks` on, not police on duty without `TrackPolice`).
- **Car against car**: a crash over ~22 km/h leaves a piece of each car on the road (each in its own colour), and each car gets the other one's paint ("Foreign paint" on the card, "Foreign paint (vehicle)" bag at the door, the lab tells the colour). Paint is in the paintwork: a cloth does not remove it. `CarCrash`, `DropChance.carcrash`.
- **Blood on blades and bats**: stabbing or hitting someone with a melee weapon puts their blood on it (by serial, kept like prints for `WeaponPrintHours`). "Dust for prints" on the weapon also bags the blood ("Blood (weapon)"), a cleaning cloth wipes it. `DropChance.weapon_blood`. New table `whip_evidence_weapon_blood` (made on start).
- **New languages**: French (`fr`), Spanish (`es`), Italian (`it`) and Polish (`pl`), pick them in `/whip` → Forensics → General → Language.

### Security

- **Fragment colour from the server**: a bullet hitting a car took the fragment colour from the shooter's client. The server now reads the car's colours itself (a cheat could plant fragments of a wrong colour).
- **Drop flooding**: blood and fingerprints a player drops are kept to `DropMaxPerPlayer` (60) per player. Before, one player spamming drops could push the whole server's evidence out through `MaxEvidence`.
- **Shoes and gloves from the server**: the sole code uses the shoes the server sees on the ped, and a glove report that does not match the ped is refused (a cheat could pick someone else's sole or fibre code).
- **Run over / car crash / weapon blood**: only the driver can run someone over; a slow bump counts only when the server sees the victim dying; blood gets on a melee weapon only within 3 m; a car crash needs a dent on one of the cars and counts once per driver every 10 s.

## 4.2.5

### New

- **Lab screen updates at once**: while someone has the lab storage open, "Bags waiting for analysis" and "Analysed, in storage" update at once when a bag is put in or taken out (before: up to 15 s).
- **Fix**: "Analysed, in storage" now counts everything "Upload to case" would take, also reports that come ready (restored serial number, post-mortem report) and test-fired guns. Before it stayed at 0 for them.

## 4.2.4

### New
- **Exact hit spots**: the findings sheet puts every hit where it landed (from the bone that was hit: head, neck, chest, belly, pelvis, left/right shoulder, upper arm, forearm, hand, thigh, lower leg, foot). Hover shows wound and spot. For an MDT: `report.details.marks[].s` (missing when the bone is not known).

## 4.2.0

### New
- **Shoe prints**: walking through mud, sand or snow (in snowy weather anywhere outside) leaves prints, and after stepping in blood a few bloody ones. The lab tells the sole pattern ("SP-3F2A", the same shoes always give the same code) and the shoe size; a bloody print also the blood type. Police take a shoe print from a person to compare ("Take a shoe print").
- **Tyre tracks**: driving over mud, sand, snow or grass, and skidding or a burnout on any ground. The lab tells the tread pattern (same car and rims = same code) and the tyre width. Police take a tyre print at a front door (bikes: at the handlebar) to compare.
- Drawn on the ground (no props), they fade with age and stay 20 minutes (`TrackMinutes`). At most 12 per player at once; police on duty leave none (`TrackPolice`). Scan filter "Prints & tracks", lab visuals for both, settings group in `/whip`.
- **Glove fibres**: gloves that stop a print leave fibres instead (in cars and on weapons, `FiberChance`). The lab gives a code ("FA-3F2A", the same gloves always give the same one). Police take fibres from a person's gloves to compare ("Take glove fibres").
- **Burnt-out cars**: a car with traces that burns loses what was inside (prints, blood, casings, GSR). Bullet holes, pieces on the ground, the number and the plate stay. The card and photos say "Burnt out".
- **Bleach** (new item): cleans blood, prints and bloody shoe prints within 2.5 m at once (no minigame), but leaves a "cleaned spot" (60 min). A swab of it: the lab finds bleach.
- **Filing a serial off** (new item: metal file): right-click a holstered gun. A few characters stay ("##3####M####"), prints on the weapon move along. Police at a lab device: "Restore serial (acid)" brings part of it back ("AB3?9X?M7Q?L", `SerialRestoreChance`) or nothing (`SerialLostChance`), once per weapon, as a lab report bag.
- Dev tools: test pieces and "Give me every evidence bag" include shoe and tyre prints, fibres and a cleaned spot; the test kit has bleach and a file.
- Prints and tracks on the ground cost much less: one picture per piece (four steps, or both tyres of a car, baked into one texture), one side of the polygon, corners and colour worked out twice a second, pieces off screen skipped, drawn within 25 m. Timed in `/whipcost` ("evidence: prints and tracks"). `/evidence_trackfaces` switches the drawn side if a GPU shows the other one.
- Scan markers are painted whole on the page (tag, number and photo badge in one picture): one sprite per marker per frame instead of three to five.
- Lighter: the player's job is kept instead of read from the state bag in every loop, the layout settings are asked of whip_core once a minute instead of every 10 s, evidence prompts go up within 3.5 m instead of 6 m (whip_core scores every prompt that is up, every frame), marker stems only within 12 m.
- **Clean view in the camera**: K (controller: LB + D-pad up) hides the big card of the trace you aim at. Markers (also V1, L1), legend and text line stay. Again K or putting the camera away brings it back.
- **Lab time by age**: each bag takes its own time by how old it was when collected (fresh ~1 min, older ~1.5, old ~2.5; samples from people, cars and weapons 1 min; a gun to test-fire 1 min), a little random, all added up and kept between `LabMinMinutes` and `LabMaxMinutes` (now 2 and 15). The monitor's bag list uses the real times.
- **Partly readable** (`LabPartial`, off by default): traces over 30 min old when collected sometimes come back with some characters as "?" (fingerprint, serial, sole and tread pattern, fibre; blood type without +/-), marked "partly readable" (`LabPartialChance`).
- **Age without a clock**: `AgeShown` (scan card, legend, photos) and `LabAge` (the lab's age at collection), each 'exact', 'rough' (default) or 'off'. Rough: "fresh", "a while ago", "older", "old" on the scene; "Under 15 min", "Under 1 h", "Over 1 h" in the lab. The "time left" chip only shows with exact ages. Shoe prints, tyre tracks and cleaned spots are always rough in the lab. Settings in `/whip`.
- **Post-mortem report**: examining a body gives a report item (cause of death, findings, the whole report for an MDT) that goes into a case like any bag. For an MDT: `entry.report`, `entry.body` on bags taken from a body, `entry.bodies` on photos, event `whip_evidence:bodyExamined(report)` and export `GetBodyReport(bodyId)` (behind `ApiResources`; reports are saved, so this also works after the body is gone, `BodyReportDays` = 30).
- **New findings sheet**: a body picture with every hit where it landed (from the bone that was hit: head, neck, chest, belly, pelvis, shoulder, upper arm, forearm, hand, thigh, lower leg, foot, left/right; hover shows what it is). Marks: bullet still inside, went through, stab, other; the fatal one circled. Cause of death on top, hits / bullets / time of death as tiles.
- **New minigames**: "Plaster cast" for shoe prints and tyre tracks (pour plaster over the whole print without spilling or pouring too thick, then lift the cast when it is set) and "Glove fibres" for fibres from a person (pick only the fibres in the glove's colour, not lint or hairs). Choosable per job in `/whip` like the others.

## 4.1.0

### Changed
- **Jobs are only listened to**: `Config.PoliceJobs` names jobs from your job scripts; nothing is created or changed (no more conflicts with the script that owns the job).
- **Rank permissions by level**: "Lowest rank level" per action in `/whip` → Settings → Forensics, the same for every police job (no more toggles in the Job Manager).

### New
- **More immersion**: every bar has a fitting animation, many with a prop in the hand (notepad, clipboard, sponge, torch), taken from WHIP's emotes and listed in `Config.Animations` (`Config.HandProps = false`: no props). Collecting ends with sealing and labelling the bag. New short bars for lab unload/upload and opening a locker. A sealed bag makes a sound. A tested or swabbed person holds their hands out.
- **Vehicles at a scene**: every vehicle with traces gets a blue marker "V1", "V2", ... (card when aimed at, no limit). A photo lists number, plate, model and colour; the plate only counts from the front or back within 12 m. The card shows "No photo yet" / "Photo without plate" / "Photographed". Releasing a scene asks when vehicles have no photo of their plate (and logs them).
- **Fragments name their car**: the car hit pieces came from is involved too ("Fragments at the scene"), even with nothing inside.
- **Bodies**: players and pedestrians killed by a player can be examined (time of death, wounds, body parts), bullets taken out for the lab, blood sample and GSR test on the hands. Card "L1" in the scan, respawn held while police examine, pedestrian bodies don't despawn. Dev tools: test pedestrians and a stand-in with your blood.
- Findings sheet per body (cause of death, wounds per body part, shot distance, bullets in the body or through, defence wounds, weapon in hand, moved after death), copy as text, controller.
- Every body gets its own purple marker ("L1", "L2", ...) like evidence, the card shows for the one you aim at. Bodies are listed on crime scene photos. Every pedestrian works, also ones only your game knows. The prompt sits on the chest.
- **Evidence locker case list**: the locker shows the cases instead of asking for an ID: 15 latest changed first (more with a button), closed ones greyed (look only), with evidence count, items taken out and last change. The search field also opens an ID not in the list. Mouse, keyboard and controller. "Upload to a case" at the lab uses the same list (open cases only; a new MDT case ID is typed in the search field).
- Fix: the evidence locker did not open after typing the case ID (no message) since whip_core's early panel drawing (2026-11-18): each press of the locker prompt now has a fresh id, so nothing early is drawn and declined.
- A refused action says why: "Your rank is level 10, this needs level 20". The evidence locker prompt shows for every officer on duty (the rank is checked when opening).
- Fix: shots at police, emergency and parked NPC cars made no fragments or bullet holes (the car was not found). The car hit is now found by a ray through the impact; a car only one game knew is networked first.
- Fix: blood, casings and fragments landed on top of awnings, balconies or roofs above the spot. The floor is now found straight below.
- Settings group "Bodies" in `/whip`, rank level for "Examine bodies".
- **Lab monitor**: locked with clock and status when nobody is at the device; an officer stepping up signs in ("Welcome, name") and is shown in the taskbar; screensaver after 2 minutes. Start and finish play a sound at the monitor, the notification also shows on the lock screen. While running: each bag in turn (done / running % / about when), who started it, progress under the taskbar icon, a badge with the results. The current bag shows what the instrument sees: DNA peaks (blood), fingerprint points, striations lining up (casings, bullets), lead/barium/antimony (GSR), paint layers (vehicle fragments). Everything moves in steps once a second with the analysis (smooth motion shimmers on a monitor in the world).
- Upload to a case at the lab: the monitor shows the transfer (bags → case folder, item by item), then "uploaded" with a sound; once no analysed bag is left in the lab it goes back to "Ready".
- Dev tool "Give me every evidence bag": each kind once, not analysed (ground, person, weapon, vehicle, body), with your own fingerprint and blood.

## 4.0.0

### New
- **Crime scene photos**: a real screenshot with the camera (key H), shown as a polaroid with every marker listed. "Copy as text" for reports.
- **Numbered markers**, legend, scan filter (key G), shot trajectories, camera badge on photographed traces.
- **Chain of custody** on every bag and photo, "Sign for evidence".
- **Six forensic minigames** (dust, tweezers, swab, pull, shards, GSR swab), mouse and controller. Other resources can use them.
- **Civilians** remove traces with pliers / cleaning cloth and a minigame. The scan overlay is police only.
- **Rank permissions**: 15 toggles per rank in `/whip` → Jobs.
- **Case lockers + MDT exports**: upload analysed evidence to a case, it moves into that case's locker. Open it at any evidence locker.
- **Evidence case**: 30 compartments, new bags go in first, unload at the lab in one go.
- **Lab monitor**: Windows-style screen at each lab showing progress and results. Any prop per lab (`screenModel`), sharp picture drawn straight onto it, fit tool in `/w`, real clock. Your own logo possible.
- **Lab results**: age of a trace at collection. **Blood trails** show the walking direction.
- **GSR on the HUD**: a ring that fades over time. Cleaning items (water bottle, cloth, configurable), swimming and rain wash it off. The test tells strong or weak traces.
- **Blood on clothes**: own blood when hurt, others' when close by or carrying them. HUD ring, police can swab clothes, washing or new clothes remove it.
- **Blood trail** lasts a while after a hit (longer for heavy hits), thins out, stops when healed; critical injuries keep bleeding.
- **Glove wear**: HUD ring, worn gloves let more prints through.
- **Less garbage while scanning**: the overlay reuses its tables (about 45 KB → 2 KB per rebuild), prompts check rank permissions once instead of every frame and don't flicker on and off at the edge of their range.
- **Controller support** everywhere: scan filter and photo on WHIP's pad buttons, photo viewer, minigames and the lab screen fit tool.
- README with screenshot slots, where to get the items, GPL-3.0 `LICENSE`. Default evidence locker at Mission Row.
- **MDT guide** in the README: step-by-step integration with examples and a checklist.
- Item pictures for everything, a bag colour per evidence type.
- Update notices: whip_core tells you when a new release is on GitHub (`whip_updates`).
- **Languages**: English and German (`Config.Locale`), every text players see. Add your own in `locales/`.
- Player settings for the scan and photo layout. Admin dev tools and case management in `/w` → Forensics.

### Changed
- **Performance**: much lower resmon (spatial grid, painted overlay, idle back-off, chunked transfers). Lab screens only send changes, vehicle traces and glove wear are batched, the lab monitor works out its corners once.
- Prompts: hold to confirm risky actions (clear away, lab device), press for the rest.
- The default lab is now called "Police Lab".
- No more waiting before collecting (`Aging.Fresh = 0`, can be turned back on). Marker colours: green = ready, red = gone soon (blue = too fresh). Laser pointer and clearing away work on fresh evidence too.
- Lab device options in the order you use them: unload, analyse, upload.

### Removed
- "Set incident ID": the case ID now comes from the MDT upload.

### Fixed
- Kicked for "latent event packet overflow" when sending photos.
- G/H didn't work while looking through the camera.
- Photo badge and blood trail direction were lost after a restart. The last seconds before a stop are now saved too.
- A bag could exist twice if moving it out of the evidence case failed (upload to a case, unloading at the lab).
- The same evidence could be uploaded twice if the MDT sent it twice.
- Handing over the evidence case could sign the bags twice after a `whip_core` restart (same for the lab monitor).
- An empty bag was lost when dusting a weapon with full pockets.
- The scan didn't come back after a restart while the camera was already in hand.

### Upgrading from 3.x
Just replace both folders and restart. New tables are created on start, evidence on the ground and bags stay.
Check `/whip` → Jobs: the new permissions are on from their level up.
