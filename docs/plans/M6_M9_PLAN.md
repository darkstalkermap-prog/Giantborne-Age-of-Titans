# Giantborn M6–M9 plan: sound and music, then the open world

| Item | Value |
| --- | --- |
| Base | `main` = `claude/hopeful-gauss-0f323t` @ `c9434e5` (M0–M5 merged, `0.5.0-m5`; 104 suites, 13,660 checks; the default suite 62 s of wall time against its 75 s budget) |
| Engine | Godot 4.6.3-stable (`7d41c59c4`), GDScript, Compatibility renderer, Jolt, fixed 60 Hz `Sim` |
| Targets | Windows desktop and the single-threaded Web export (the play link) |
| Inputs | The owner's direction ("add sound and music and continue to build the game"; "I like the beginning as a tutorial but it needs to open up to an open world to explore in the world"), spec `docs/GIANTBORN_SPEC_V2.md`, the three briefs in `docs/plans/briefs/` (`audio_tech.md`, `open_world_tech.md`, `growth_extension.md`), `ARCHITECTURE.md`, `DECISIONS.md`, `M2_M5_HANDOFF.md`, `HOW_IT_PLAYS.md`, `PERFORMANCE.md`, `plans/FOLLOWUPS.md`, the shipped code, and the three reviews of this plan's first draft (§8) |
| Output | 23 packages (P19–P40, P24 split into P24a and P24b) in 13 waves (W12–W24, at most 2 agents at once), four milestone gates and a ship gate. M6: complete original audio and the M5 limitations. M7: the Valley opens into a streamed 2 × 2 km world that can be seen to its far edge, with growth stages 4–5, stage-4 movesets and evolutions, a map, a compass, fast travel, the Crownmarch's content with formations, and light content in every other region. M8: siege, talents, ancestries, stage 6, three bosses and the four other regions' content. M9: a living world, a world bot, a stability run, a balance pass and the ship |
| Play link | Updated after M6 (`0.6.0-m6`, sound), after M7 (`0.7.0-m7`, the first open world), optionally after M8 (`0.8.0-m8`), and at the end (`0.9.0-m9`) |

Facts this plan depends on were measured by the three briefs (marked VERIFIED there), re-measured
for this revision (the scratch experiments named in §8), or read in the code. The ones that shape
the design:

- **Audio** (`audio_tech.md`): QOA SFX play as Web Audio *samples* on the web (gapless one-shots,
  3D attenuation and panning work, main-thread stalls do not interrupt them) but bus effects, the 3D
  distance filter, gapless loops and stem alignment silently fail in sample mode, so every loop
  (music, ambience) plays as a *stream*; with `audio/driver/output_latency.web = 200` stream
  playback survives 120 ms main-thread stalls. Forcing `PLAYBACK_TYPE_SAMPLE` on desktop is silent.
  A registered web sample is stored as stereo float32 at the context's rate (353 KB per second of
  audio) and **every `play()` allocates another full copy**; a `play()` before registration does
  both (up to 244 ms). `AudioStreamRandomizer` uses the global RNG. libvorbis loops are
  sample-exact; ffmpeg writes a random Ogg serial unless `-fflags +bitexact -flags:a +bitexact` is
  given, with which two encodes are byte-identical (re-measured). The Dummy driver mixes headless
  and `mix_audio()` renders offline at 575–2,200× real time.
- **Streaming** (`open_world_tech.md`): on the no-threads web build a threaded load runs inside the
  request; 256 m chunks in a 3 × 3 ring, time-sliced at 4 ms a frame, never let a 16 m/s giant
  within 252 m of unloaded ground (that walk freed chunks only beyond ring + 1); the worst web
  frames are navigation map rebuilds (60 → 20 ms with lean bakes and one region a frame, measured
  with 3D off and no gameplay); cross-chunk navigation needs the grown bake AABB, an aligned y grid
  and one navigation map per layer; a slope of 40° or more across a chunk border traps the giant;
  no floating origin is needed for a few kilometres. Unlimited-polygon queries with a 300 m cap cost
  0.8–3.2 ms (desktop) and 1.5–3.0 ms (web) against an unreachable target.
- **Navigation, re-measured for this revision** (Godot 4.6.3, `--fixed-fps 60`): both
  `navigation/world/map_use_async_iterations` and `region_use_async_iterations` default to true;
  the ticks until a path crossed into a newly added region were 12–24 with the defaults, 16–23 with
  only the map's async iterations off, and 1 in 5 of 5 runs with both off.
  `NavigationServer3D.map_get_path(map, origin, destination, optimize, layers)` takes no query
  parameters (it always uses the 4,096-polygon default: on an 8,100-polygon test map its path ended
  467 m short of a target 1,260 m away); `NavigationServer3D.query_path` with a
  `NavigationPathQueryParameters3D` (`path_search_max_polygons`, `path_search_max_distance`), called
  without a callback, answers in the same call and reached that target.
- **Growth** (`growth_extension.md`): stages 4–6 work as data; light 3 and the 7.5 m tree miss at
  stages 4–6 and need their own movesets; humans are 17–29 px tall under lock at stages 4–6; forty
  soldiers fit the CPU budget (3.98 ms p95) but not the draw-call budget (2,019 calls); morale breaks
  every 1.8 m unit after one death against a four-times-taller giant; enemies can only target the
  player; small attackers cannot stagger big giants; the Valley's respawn points have clearance for
  stage 3–6 capsules but its routes do not (overlaps from the Hollow's exit at stages 4–6).
- **The code**: `QuadrupedRig` has no `footfall` signal (only `ActorRig` has); the title screen's
  save line prints the checkpoint id (`ui/screens/title_screen.gd` `describe_save`); waystones have
  no records or display names; `GameSession.Mode` is `TITLE / SANDBOX / VALLEY` and every flow is a
  reload of `scenes/main.tscn`; `DataValidator.SCHEMA_PATHS`, `build_scenes.gd BUILDERS`,
  `ScreenStack.SCREENS`, `HudWidgets.WIDGETS` and `ShrineScreen.TABS` are pre-declared registries;
  `GameData` reads every `data/*.json` and `data/*/*.json`; every export preset ships everything but
  `tests/` and `tools/`, so `scenes/test/` ships today and the desktop exports need it (the stress
  route in `docs/PERFORMANCE.md`), and a level record whose scene is missing fails validation;
  `civilian.gd`, `valley_bot.gd`, `valley_walk.gd` and `bot_diagnosis.gd` call `map_get_path` on the
  default map like `EnemyActor`; shrines and waystones activate once per node (per load); the
  camera's far plane is 800 m; the quest line's end already takes a completion checkpoint (P17a), so
  a finished v1 save holds `slice.completed`; player area effects never reach neutral faction members
  (`HitFactory.skip_candidate`); a civilian flees a giant moving faster than 3 m/s.

---

## 0. Scope, interpretation, decisions and the deferred list

### 0.1 Goal

Two things, in this order. **M6** gives everything that exists today complete original sound: sound
effects for every combat, ability, enemy, world-object, UI and progression event, ambience for every
Valley district, an adaptive score (title, each district at explore, danger and combat intensity, the
Ogre King's two phases, growth, level-up, victory and death stingers, the end screen) that varies its
melodies and rests instead of repeating one loop, audio settings, mute on focus loss, and spatial cues
that make off-camera threats readable. All of it is generated by committed tools, recorded with its
provenance, built so that regions and places get their own music and ambience by data, and verified
in the web export within a size budget. M6 also closes the M5 limitations: enemy rigs cost about 33
draw calls each, Thornwick can turn hostile on a help path's return leg, the title names the
checkpoint by its id, about a fifth to a quarter of hits come from off camera, the yard pocket, the
nav-link test flake, and the Valley balance items of `HOW_IT_PLAYS.md`.

**M7–M9** keep the Valley of Broken Kings as the opening tutorial and open the game into a streamed
open world after it, as the owner asked: five regions of a 2 × 2 km world (kingdoms, villages,
forests, ruins, giant territories) that can be seen from the Kings' Door to the far highlands, free
roaming, points of interest, sealed places to come back to, a map, a compass, fast travel, a
non-linear main thread whose three oaths can each come first and each have a peaceful and a violent
resolution, settlements that treat a giant as a neighbour or a threat, wandering encounters and world
events, growth stages 4–6 with their spec unlocks, level 12 with three talent trees and three
ancestries, 24 active abilities and an ultimate, stage movesets for every weapon, axes, fists and
Giantforge refits, formations, siege crews, cavalry, trolls, rival giants and three bosses, region and
place music and ambience, persistence and save migration, a world bot, a stability run, a balance pass,
an updated how-it-plays report, the exports, the play link and the merge. Graphics stay primitive
low-poly. Stages 7–10 stay deferred, but every system is built so they can be added by data and a
later traversal spike.

### 0.2 Milestone gates and the packages that prove them

| Gate | Requirement | Proven by |
| --- | --- | --- |
| M6 Sound and music | Every event that exists today has a sound or is listed as deliberately silent; ambience in every Valley district; adaptive music with explore / danger / combat layers, melody variants, rests and silence windows, the boss's two phases and the stingers; every level and context has music or is listed silent; audio settings and focus mute; directional threat cues; generated by committed tools with provenance and bit-exact regeneration on the reference toolchain; audio has no effect on the simulation; the web export plays it within its size and memory budgets, shipped as a multi-part pack; rigs within the draw-call budget with five enemies in view; Thornwick, the title, the yard pocket and the nav-link flake closed; the off-camera share of hits taken under 20 % in the Valley matrix, or reported as a miss | P19 (engine, settings, determinism test), P21 (SFX, coverage tests, threat cues), P23 (score, ambience, web check, multi-part pack), P22 (rigs, Thornwick, factions by record, web export hygiene, ranged positioning, Valley balance), P20 (checkpoint names); the M6 gate runs the web check and the Valley matrix, and updates the play link. P24a merges in W14 but is reviewed at the M7 gate: a late P24a never holds the M6 release |
| M7 The world opens | Leave the Valley after the crown onto the Kingsgate shelf with the far view; a streamed world that runs on the web build (determinism, hysteresis, worst frames measured with gameplay); terrain; navigation across chunks with size-gated masks; the skyline; the Crownmarch with content, including two formation fights that threaten a stage-4 giant; every other region with light content (§5.10, the M7 content rule); points of interest, sealed places, map, compass, pins, fast travel; stages 4–5 with their evolutions and every reachable weapon's stage-4 moveset; the Citadel breach; size gates; world and place audio; the equipment and XP budgets | P24a, P24b (streaming, navigation), P25 (geography, skyline, light content), P26 (stages 4–6, size gates, Valley exits and revisits), P27 (UX), P28 (world audio), P29 (Crownmarch), P30 (formations), P31 (evolutions, stage movesets; merged in W18 before the gate); the M7 gate runs the stream check on the real world with the audio recorder and updates the play link |
| M8 Armies and giants | Stage 6 and siege disruption with engines on the main path; level 12; talents and ancestries; the 24 actives; refits; pike and shield formations, cavalry, siege crews, trolls, rival giants; three bosses with disengage and yield protocols; all five regions with settlements, quests, peaceful options and sealed places; the main thread completable in every order of every oath pair | P32–P37 (P37's living-world framework and the region packages' wander tables and events); the gate tier's walkthrough and combination suites |
| M9 A living world, shipped | Wandering encounters and world events that respect streaming; the bot plays the world; a 60-minute world stability run; a balance pass; the report; exports; the play link; merge to `main` | P38–P40 |
| Spec §15 rules still holding | Combat correctness, camera and growth, ability/AI/world checks | Every package keeps the existing suites green; P26 extends the growth route to stages 4–6 in both camera modes with first-person downward attacks; P30–P34 add their spec §15 checks (invalid grabs of engines and of a too-tall boss spend nothing, boss phases exactly once per attempt, fleeing units have reachable destinations on streamed ground, no invalid spawn at any Valley checkpoint for any stage) |
| Spec §16 performance and stability | Frame budgets, a stress route, the active-enemy budget, a long session without crash, softlock, duplicated reward or stuck targeting | P22 (draw calls), P24a/P24b (streaming and path-query budgets), P30 (formation budget), P38–P39 (world stability run, performance capture); real-PC and real-browser numbers stay **NOT RUN** until the owner runs them |

**The M7 content rule** (checked by P25's and P29's tests and by the M7 gate): every region has at
least two encounters (existing archetypes are enough) and at least two caches or cairns; every POI
gives discovery XP and holds at least one of an encounter, a cache, a cairn, a talker, a quest target,
a shrine, a waystone or a sealed place; every walkable chunk reachable at stage 4 lies within 400 m of
such a POI. What M7 leaves for M8 (the Greywood's, the Drowned Steps', Aldmere's and the Stonehold's
peoples and quests, stage 6) is named in the M7 launcher notes and in the journal's region pages.

### 0.3 Interpretations and decisions (P40 copies these into `DECISIONS.md`)

1. **Audio is presentation only.** One autoload, `Audio` (last in the autoload order), listens to
   `Events` and to rig footfall signals and reads state in `_process`. It never emits a gameplay
   signal, never spends or changes anything, never reads `finished` into game logic, never touches
   `Sim.rng` or the global RNG (it owns a private `RandomNumberGenerator`). A slow test runs the
   seeded sandbox soak with audio on and off (`--no-audio`) and compares the two `AUTOPILOT_RESULT`
   lines byte for byte. The default test suite runs with audio disabled; audio suites enable it.
2. **One playback policy for both platforms.** Sound effects are WAV masters imported as QOA and
   played with `PLAYBACK_TYPE_DEFAULT` (samples on the web), registered with
   `AudioServer.register_stream_as_sample` behind the loading screen, before the level's first
   simulation tick, so no `play()` ever registers. Everything on the Music and Ambience buses,
   ambience spots included, is Ogg Vorbis (libvorbis) played with `PLAYBACK_TYPE_STREAM`, so the
   only samples are short SFX. No code sets `PLAYBACK_TYPE_SAMPLE`; no `AudioStreamRandomizer`,
   `AudioStreamPolyphonic` or `AudioStreamPlaylist` is used; loops are always Ogg; every SFX file is
   at most 2.0 s; `audio/driver/output_latency.web` is 200. A test greps the code for the forbidden
   calls.
3. **Buses are made at run time** by `Audio` (Master, Music, Ambience, SFX, UI, all sending to
   Master, no effects), so there is no hand-edited `default_bus_layout.tres` and both platforms mix
   identically (bus effects do not exist for web samples).
4. **Every sound is original and generated by committed code, and the generators are the masters.**
   `tools/audio/` (Python 3 + numpy, seeded, float64, single-threaded) writes every sound; SFX WAV
   masters are committed (they are Godot's import source); music and ambience are rendered to
   lossless masters, encoded with ffmpeg's libvorbis (`-fflags +bitexact -flags:a +bitexact`) and
   only the Ogg is committed, beside a manifest with the generator, function, seed, parameters,
   frames, rate, loop data, the hash of every master (WAV and the music and ambience masters alike)
   and of every shipped file, and the tool versions. `build_audio.py --verify` regenerates **every**
   master and every Ogg and compares all hashes; it is part of `check.sh --audio`, so regeneration is
   proven bit-exact on the reference toolchain (the container's Python, numpy, ffmpeg and libvorbis,
   recorded in the manifest). `build_audio.py --masters-out=<dir>` writes the lossless music and
   ambience masters as FLAC for anyone who wants them. This deviates from spec §13's "keep audio
   masters" for music and ambience (about 60 MB of FLAC by the end, rewritten on every tuning pass,
   against a 19 MB repository): the deviation is recorded here and in `DECISIONS.md`, and the owner
   may ask for the FLAC masters to be committed instead (§6.7). `assets/audio/PROVENANCE.md` states
   that every sound is original and generated, with no recordings or third-party samples, lists the
   generator, seed and tool versions per family, and leaves the licence as "the project's licence;
   the owner chooses it" (§6.7). Building or playing the game never needs Python or ffmpeg.
5. **The score is layered stems on plain stream players** started in the same frame, with layer
   volumes eased live and set changes cross-faded at bar boundaries computed from the lead stem's
   playback position (all VERIFIED to behave the same on desktop and web). Exploration sets carry
   three aligned melody variants; the director picks a variant or a rest for each four-bar segment
   with its own RNG (no variant more than two segments in a row, no identical phrase within 60 s),
   rests the melody for one to three loops after one or two played loops, and after three minutes of
   uneventful exploration fades to ambience alone for 60–120 s. Danger and combat stems are shared by
   the zone sets of one tempo; the region's melody stays in combat at −10 dB and each region has its
   own combat-intro stinger. Boss sets have their own tempo, metre and mode and enter with a one-bar
   intro stinger. Stingers are one-shot streams that duck the stems. `AudioStreamInteractive` and
   `AudioStreamSynchronized` are not used.
6. **The listener stands at the giant's chest**, turned with the camera; every other source's
   distances scale with the player's height ÷ 3.66, so humans stay audible at every stage. Distance
   muffling uses baked "far" variants, because the distance filter does not exist for web samples.
   **The music's intensity weighs threats relative to the giant**: an enemy raises `combat` only when
   it is at least 0.3 × the giant's height or belongs to a formation, an engine crew, a boss or the
   rival giants; lesser enemies raise at most `danger`, within an unscaled 40 m; fleeing and routed
   enemies never count; the danger radius is capped at 150 m.
7. **Threats are audible and directional.** Every enemy attack with a telegraph aimed at the player
   plays a positional windup cue at the attacker; when the attacker is outside the camera's view or
   beyond 20 m (scaled), a short, broadband "threat sting" plays at the same point, unless the
   attack's expected damage is under 3 % of the giant's maximum health or its poise ratio sits at the
   0.25 floor. A formation's brace plays one wall cue per brace cycle, not one per pike; an indirect
   projectile plays its launch at the engine and a rising "incoming" whistle at its landing circle.
   Ranged enemies add a cue when they commit their aim.
8. **Size and memory budgets** (from per-file arithmetic, §4.5; checked by tests and printed by
   `build_audio.py` before encoding): M6 audio ≤ 4.0 MB imported; world audio adds ≤ 5.5 MB (≤ 9.5 MB
   in all); world data (chunks, navmeshes, index, map image, skyline, chunk scenes) ≤ 5.0 MB, measured
   on P24a's test world and extrapolated before P25 builds the real one. The web `index.pck` ships
   gzipped and base64-encoded **in parts of at most 15 MB** that the launcher joins before the engine
   sees them (P23), so the host's 16 MB per-file cap no longer limits the game's size; the download
   is limited instead: `index.pck` as shipped ≤ 7.5 MB after M6, ≤ 21 MB after M7 and ≤ 23 MB at the
   end (the whole play link about 20, 34 and 36 MB). Test content (`scenes/test/`, `assets/test_world/`,
   `data/test/`) never ships in the web release (P22). Web sample memory: the registered SFX of one
   level stay under 110 s of audio in the Valley and 170 s in the world (39 and 60 MB at 353 KB/s);
   the web check measures peak live sample bytes (registered buffers plus the copies of playing
   voices).
9. **Enemy rigs get cheaper, not fewer.** Each humanoid or quadruped rig is merged into one mesh per
   animated part with vertex colours and one material per actor (flashes become emission, tints
   become albedo), and the renderer's visibility ranges swap distant rigs for the one-box proxy by a
   per-archetype distance (bosses exempt). Target: about 7 draw calls per near rig, 1 per far one.
10. **The Valley stays the prologue, almost unchanged.** Its quest line, encounters and tests stay.
    What changes: the crown opens the Kings' Door behind the altar (an exit north onto the world's
    Kingsgate shelf); the end screen becomes "Prologue complete" with Continue; the sealed Citadel
    gets an interior and a second exit, breachable at stage 4; Thornwick's guard posts move out of the
    bridge fight; checkpoints have display names and an arrival limit (`max_stage`), so a stage-5 or
    stage-6 giant is never sent where the Valley's paths are too narrow; a sealed vault in the Barrow
    opens to a stage-5 heave. A returning player whose save has finished the prologue may skip it
    (title screen, §2.6).
11. **Two campaign levels and reload transitions.** `level.valley` and `level.world` are separate
    scenes. `GameSession.Mode.VALLEY` now means "the campaign" (both levels; `is_campaign()` is an
    alias of `is_valley()` and `--mode=valley` keeps working). Moving between them, and fast travel,
    is a checkpoint at the destination plus a reload of `main.tscn` (the existing path). The save's
    `level` field picks the level on Continue. Level-wide nodes that later packages own (`Discovery`,
    `WanderDirector`) are created at run time by `LevelRoot` from a registry P20 pre-declares, so no
    builder needs a later package's node.
12. **A 2,048 × 2,048 m world in 8 × 8 chunks of 256 m**, origin at the centre, bounded by an
    impassable mountain rim (walkable interior about 1.8 × 1.8 km). Chunks load within Chebyshev
    distance 1 of the player's chunk and unload at distance 3 or more (so at most 25 are loaded and a
    border walk never thrashes), nearest first, with a 4 ms per-frame work budget (a fixed step quota
    in headless runs), solids in batches of 16, a navmesh's load and its region's add in different
    frames, settlements as several sub-scenes, and one region a frame. Heights are 16-bit at 4 m
    spacing; no plugins; no floating origin. Chunk border slopes are at most 35°. **The world can be
    seen to its edge**: an always-loaded skyline (the whole world's terrain at 32 m spacing and the
    silhouettes of about twelve landmarks, two draw calls) shows wherever no chunk is drawn, the depth
    fog runs from 400 to 1,800 m with at most 85 % density, the camera's far plane follows the level
    record (2,400 m in the world), and lit beacons rise as columns that ignore the fog.
13. **Navigation in the world is baked offline** on three layers with one `NavigationServer3D` map
    each: human (1), large (2) and titan (16, radius 4.0 m) for stage 3–6 giants, the bot and rival
    giants. Size-gated ground is baked as separate titan regions with gate bits (32: stage ≥ 4,
    64: ≥ 5, 128: ≥ 6), so the titan query mask follows the stage. Lean bake settings, the grown
    AABB, the aligned y grid, edge connections off. Every world query goes through one `NavQuery`
    helper (`NavigationServer3D.query_path` with unlimited polygons and a distance cap: 120 m for
    chases, 300 m for the bot and the director), snaps its goal to the agent's map first, and
    respects a per-tick query budget; tier-0 repaths are throttled. The Valley's queries keep
    today's parameters (its paths do not change). When streaming is deterministic (headless runs and
    tests), every layer map and streamed region runs with async iterations off, so a newly added chunk
    is usable on the next tick; a chunk is ready when every layer map's iteration id has passed its
    last region add. Nav links in chunk scenes join their layer's map. Long routes (the bot) use a road
    graph in the world index whose edges carry stage limits. Nothing bakes at run time.
14. **A world index per level** (a builder-written resource) holds the positions and display names of
    checkpoints, markers, areas, POIs, exits, encounter centres, safe markers and quest-target props,
    the region grid and the road graph. Quests, the map, the compass, fast travel, respawns, civilians
    and the title fall back to it whenever the node is not loaded.
15. **The director in a streamed world** updates only encounters whose chunk is loaded and ready,
    despawns every living member standing in a chunk before that chunk unloads (they come back home
    at full health), filters spawns by the player's stage (`min_stage` / `max_stage`), scales
    formations for the web (`web_formation_scale`), requires a leash on every world encounter except
    arena bosses, and gives arena bosses a disengage rule instead (§2.10).
16. **Save schema 2.** `SaveSlots.migrate()` runs before `validate()` (one step per version); 1 → 2
    adds `character.talents`, `character.ancestry_chosen`, the `progress` block (with the tracked
    quest) and the checkpoint's position. A damaged v2 main file with a v1 backup recovers by migrating
    the backup. The slot (`valley_1`) and the project name stay, so desktop and web saves are kept. A
    finished Valley save (the P17a completion checkpoint holds `slice.completed`) continues at its last
    checkpoint with the Kings' Door open.
17. **Growth stages 4–6** use the growth brief's tested profiles (10.97 / 14.63 / 18.90 m, levels 7 / 9
    / 11, lock 55 / 65 / 80 m) with arc tilts −16 / −20 / −24°. Stage 4 needs `world.kingsgate.lit`;
    stage 5 needs one oath; stage 6 needs two (decision 26). In the M7 build stage 5 is reachable
    (Brannock's oath exists) and changes traversal and interactions (heave, the deep channel, the
    Needle refuses) and brings its evolutions (P31 merges before the M7 gate); stage 6 needs M8.
18. **Size gates** come in four kinds: props with `min_growth_stage` (fortified gates at 4, rockfalls
    and fallen titan-trees at 5, opened by `heave`); invisible walls on physics layers 7–9 that stop
    giants below stage 4, 5 or 6 (the Wend's deep reach, the Mere's deep channel, the Giant's Stair,
    the Moot's gate), mirrored by the titan gate bits; narrow passes by geometry (the Needle fits
    stages 3–4); and trampling (fences and palisades break when a giant of their `trample_stage` walks
    into them). Every gate names the stage it needs and answers with a diegetic cue at the contact
    point (water, stone, timber); the UI buzz is for menus.
19. **Formations are lock groups at stages 4–6** (profile `target_rules.formation_lock`): one lock
    candidate per formation, resolved to the living member nearest the attack origin, plus the
    bannerman as its own candidate (a flag icon in the lock line), so the camera, the vertical aim and
    grabs keep receiving a `CombatEntity` and breaking the banner is a choice. A formation's brace is
    one band attack of the formation that holds one melee token and lands at most one hit per target
    per pulse. Formations have ranks, a banner that halves awe and ally-death losses, a crowd renderer
    (one MultiMesh per pose) with members within 20 m or striking promoted to full rigs, and routs
    that fan out over several flee points. They count against `max_formation_members` (desktop 40,
    web 20, compositions scaled by `web_formation_scale`), not the 12 individual combatants.
20. **Enemies can target NPCs and props** through a target provider in `EnemyActor` (opt-in per
    record: `targets`), so raiders attack houses and villagers, and siege crews attack walls.
21. **Siege attacks carry a size override** (`attacker_height_override_m`), so a ballista bolt staggers
    a big giant like an 8 m attacker would; destroying an engine raises the −20 siege morale event
    (2 s debounce per unit).
22. **Talents and ancestries are passives on the `Combatant`**, never statuses (statuses expire and show
    on the HUD). Three trees of nine talents; three ancestries chosen once at a shrine after the world
    opens (a migrated save gets the same choice).
23. **The library is 24 actives and one ultimate.** The Valley's 8 actives, 6 stage evolutions, 7
    talent abilities and 3 ancestry signatures (24), plus Titan Surge. Evolutions are separate records
    (`evolves_from`, `unlock_stage`) that replace their base in the same slot, so a loadout holds 8
    actives and the ultimate; cooldowns stay per id. Ability ranks are not built (§0.4).
24. **Weapons grow with the giant once reinforced.** Base weapons fit stage 2 (the Valley's forge
    lesson stays); reinforcing (2 iron at any iron-tier forge, the Kingsgate anvil included) makes a
    weapon fit stage 6 and gives it its family's stage 4–6 moveset, whose third light lands at the
    feet. Titanforging (2 titan iron + 2 iron at a titan-tier forge) adds damage and one perk per
    family; it never gates reach. New families: axe and fists, both fitting stage 6. The tree has a
    stage 4–6 variant (the great pine). Forges have a `tier` (`iron` | `titan`).
25. **XP keeps the prototype-pacing label in the world.** A budget test guarantees level 7 at the
    Kingsgate beacon, level 9 after any one oath, level 11 after any two, level 12 at the throne,
    counting only quest XP and the discoveries on mandatory paths, from the Valley's worst outcome
    (level 6, 1,050 XP), with at least 50 XP of margin at every gate. Milestone stages also carry a
    level floor (`xp_floor_level`): completing the beacon, an oath or the second oath awards at least
    the XP that reaches the next stage's level, so a level can never block the main thread while the
    oaths remain the real gate.
26. **The main thread is non-linear, and every oath can come first.** After the opening, the three
    oaths (Brannock, the Greywood, Aldmere) start together at stage 4 and any two complete the stage.
    Each oath has a resolution available as the first oath at stage 4, peaceful and violent alike:
    the march — help, intimidate, force; the wood — slay, and drive (the woodfolk open the den's back
    wall once the nests burn; heaving it at stage 5 is a shortcut); the crown — breach, sabotage, and
    parley with any of Brannock's banner, the deserters' word, Stoneblood blood or stage 5. A choice
    that still needs something shows greyed with its reason, and the journal lists what it waits for.
    The finale needs stage 6. The combination suite runs every order of every pair.
27. **Wandering encounters and world events** come from region tables filtered by the player's stage
    and faction standings, spawn out of sight on loaded ground, persist their outcomes, and cannot be
    farmed (a template's kill XP falls to zero after its third spawn). Events start only when their
    centre chunk is loaded and the player is within 200 m, suspend their fail rule while that chunk is
    unloaded, and reset on the player's death; moving columns live as a path parameter while unloaded.
    P37 builds the framework and the Crownmarch's table; each region package owns its region's table
    and events.
28. **The world bot extends the Valley bot** (road-graph routing across chunks, tracked objectives,
    exploration, oath policies in any order); balance is judged on the novice, stability on the
    assisted bot, as in M5 (decision 30 of M2–M5).
29. **Stages 7–10 come later by data**: profiles to stage 10 already validate; nav layer, gate bits,
    size-gate layers, region records, chunk grid, skyline and world record are all data; the world
    builder accepts a larger grid. Nothing here assumes the world will stay 2 km.
30. **Every milestone has a gate review**, and the ship has its own, as in M2–M5.
31. **Peoples by site, and manners toward a giant.** Factions are records with texts, thresholds and
    per-site dispositions: Aldmere's toll-riders (the Kingsgate scouts, the toll fort and the Moot
    battery) are hostile from the start; the kingdom of Aldmere (the war camp, the ridge, the fort) is
    wary but at peace until offended. Friendly civilians give way and watch instead of fleeing;
    talkers meet a giant too big for their streets on their settlement's green; damaging a
    settlement's houses (by blows, abilities or trampling) is an offence like striking its people; a
    hostile settlement can be reconciled (a price or an errand); outcomes show on site
    (`visible_when_flag`). Quest-critical props (Brannock Bridge, the beacon, the Kings' Door) are
    indestructible by data.
32. **An equipment budget sits beside the XP budget**: on every oath-policy path, reinforcing is
    affordable at an iron-tier forge by the beacon, one titanforging is affordable (and a titan forge
    reachable) by the first oath, and two by stage 6; titan iron on the mandatory path comes from the
    beacon's cache, every oath and the Standing Stones; optional sources (the Citadel's hoard, the
    Titan's Bones, the Hidden Grove, a sealed armoury, Skarn) are extra, and none is missable.
33. **Exploration pays**: every POI gives discovery XP; vistas reveal the POIs within 400 m on the map;
    fourteen Old Kings' cairns (thirteen in the world, one in the Valley's vault) each give one
    attribute point, nine of them behind size gates; sealed places
    (rockfalls, statues, ledges a bigger giant reaches) are logged in the journal with the stage they
    need; caches at ruins and vistas give iron.
34. **Three test tiers.** The default suite (≤ 75 s, audio off, per-package caps), the slow tier
    (`tests/slow/`, ≤ 8 minutes, per-package budgets) and the gate tier (`tests/gate/`: walkthroughs,
    oath combinations, seeded boss runs and soaks; ≤ 50 minutes) run at milestone gates and at the
    merges of W18, W21 and W22. Every wave merge records the default and slow times and fails above
    75 s and 8 minutes.

### 0.4 Deferred: explicitly not built in M6–M9

- Growth stages 7–10 and what they unlock (large-monster grapple windows, colossal shockwave, titan
  executions, Worldbreaker); the large-scale traversal spike they need (spec §11).
- Dragons and flight, primordial titans, continent-scale worlds, seamless Valley-to-world embedding,
  per-region download packs, runtime navmesh baking, a floating origin.
- Boss grapples (spec: stage 7; no boss can be grabbed in M6–M9, the Troll Matriarch included), enemy
  grabs of the player, limb poise.
- Ability ranks (only stage evolutions replace abilities).
- Day and night, weather, seasons; mounts for the player; swimming (water is wading depth or a gate).
- A crafting economy beyond refits; shops and currency; inventory weight or loss; several save slots;
  cloud saves.
- Voice acting and recorded dialogue (voices are synthesized grunts and calls), localization,
  cinematic dialogue, a music system beyond layered stems and variants (no generative live music).
- Destructible walls, towers and bridges; building collapse; structural damage beyond authored
  stages; terrain destruction.
- Agent avoidance for crowds (routs fan out over several flee points instead, §2.10).
- The Unreal engine spike. Physics interpolation.
- The Valley's pacing against a timed human run (the bot's estimate is a floor; the owner's
  usability sessions decide, §6.7).
- Choosing a licence for the project and its generated assets: the owner's decision (§6.7).
- Human playtests, a real reference PC, a real gamepad and real browsers: scripts and commands are
  delivered; results stay **NOT RUN** until the owner runs them. Nobody can listen to audio in the
  development container: every audio check is a measurement, and "listen once on speakers" is an owner
  task in the usability script.

---

## 1. Execution model and wave schedule

### 1.1 Definition of done for every package

As in M2–M5 (`M2_M5_PLAN.md` §1.1), adapted to the tools that exist now. Each package is one agent in
one session, about 1,500–3,500 new lines including tests and data (an asset-generation package counts
its generators, data and tests). Before committing:

1. Every Godot command runs through `tools/gd.sh` (this worktree's own `user://`).
2. `tools/check.sh` with the right options passes: import → build scenes (`--only=<builders>` for the
   builders the package changed or whose embedded code it changed, `--build` for all) → import →
   default suite (plus `--slow` when the package added or changed slow suites, `--gate` when it
   added or changed gate suites) → the 120 s seeded soak with `"errors":0` and the breakable-path
   coverage. Audio packages add `--audio` (P19 adds the option): the generators run into a temporary
   folder and every master's hash, WAV and music and ambience alike, and every Ogg's hash must match
   the manifest; the asset suites run. World packages that change the world pass
   `--build-args=--chunks=…` (P25 adds it): the builder expands the list to the eight neighbours of
   every chunk whose navmesh sources or border heights changed, and `check.sh` then runs the seam
   height and cross-seam path checks on every rebuilt chunk and its neighbours. Every region package
   also rebuilds its chunks twice and requires no diff.
3. Shipped data validates; no runtime errors; scenes and generated resources are never hand-edited.
4. **Test budget (decision 34).** The default suite runs with `--no-audio` (audio suites call
   `Audio.enable_for_tests()`) and stays under 75 s of wall time: each package's added default time
   is capped in its spec (§3) and the caps add up to 11 s; anything that loads a world, a Valley walk
   or more than one level goes to `tests/slow/` (each package's slow budget is in its spec; the tier
   stays under 8 minutes) or, for walkthroughs, oath combinations, seeded boss runs and soaks, to
   `tests/gate/` (≤ 50 minutes, run with `--gate` at milestone gates and at the W18, W21 and W22
   merges). Each package reports its added default, slow and gate time in its system doc.
5. `docs/systems/<package-id>.md`: what was built, public APIs, data, decisions and deviations, known
   gaps, the runtime added to the suites, and (world and content packages) the pck share and the
   viewpoint draw calls. **Only P40 edits `README.md`, `ARCHITECTURE.md` and `DECISIONS.md`.** Other
   docs (`PERFORMANCE.md`, `HOW_IT_PLAYS.md`, `BALANCE_LOG.md`, `USABILITY_SCRIPT.md`, `FOLLOWUPS.md`)
   are edited by the packages named in §3.
6. Commit on `pkg/<id>` with messages that name the package id; no AI product or model names in any
   file (`test_ship_docs` checks every text file; the spec stays the one recorded exception).

### 1.2 Branches, worktrees and the wave merge

Unchanged from M2–M5 §1.2: the integration branch is `claude/hopeful-gauss-0f323t`; each package works
on a local `pkg/<id>` branch in its own worktree from the integration tip at the start of its wave; the
cross-lane API rule holds (a package uses only what exists at the start of its wave plus its own work;
"Cross-lane symbols" in §3 lists the few it must reach defensively). The wave merge: merge the first
package, import → full build → import → full suite; merge the second (conflicts only in the hotspot
hunks its spec names); import → full build (`res://tools/build_scenes.tscn`, the world included) →
import → full suite with `--slow` and `--audio` (and `--gate` at W18, W21 and W22) → the 120 s soak;
record the default and slow times (fail above 75 s and 8 minutes); commit "Merge wave N" and tag
`wave-N` (continuing from `wave-11`). Fix-forward only under about 50 lines, else revert the package
and re-run it.

**Generated outputs are always regenerated at the merge, never merged by hand**: every generated
`.tscn`, `.res`, `.png` and the world's outputs (`assets/world/**`, `scenes/world/chunks/*.tscn`,
`index_world.res`, `map_world.png`, the skyline) take "ours" during the git merge and are then
rebuilt by the full build from the merged layout tables. Region packages' tests read only their own
region's index entries, so a branch's tests never depend on another region's markers. The W21 merge
(P35 with P36) runs the full world rebuild before the oath-combination suites.

### 1.3 Wave schedule (two lanes)

| Wave | Lane A | Lane B | Leaves working |
| --- | --- | --- | --- |
| W12 | **P19** Audio engine | **P20** Campaign foundations | The Valley unchanged but with the audio engine running placeholder cues, the loading gate and audio settings; saves migrate to schema 2; the title names checkpoints and offers to skip a finished prologue; every M7–M9 enum, event, registry and anchor declared |
| W13 | **P21** Sound effects | **P22** Rigs and M5 polish | Every gameplay, world and UI event audible; threat cues; rigs at about 7 draw calls; Thornwick stays calm on help paths; factions by record; the web release without test content; ranged enemies keep to the camera's side; the Valley balance items tuned |
| W14 | **P23** Music and ambience | **P24a** Terrain and streaming runtime | **M6 gate** (P24a reviewed at M7). The Valley has its varied score and ambience; the web check passes within budget with a multi-part pack. **Play link `0.6.0-m6`.** A generated test world streams with hysteresis, the skyline and a settlement chunk |
| W15 | **P24b** Navigation across chunks and the director | **P26** Growth 4–6, size gates, the Valley's exits | Deterministic cross-chunk navigation with gate bits and one query helper; stages 4–6 grow; the Kings' Door and the Citadel lead out of the Valley; Valley checkpoints know their stage limits |
| W16 | **P25** World builder and geography | **P30** Formations | The 2 × 2 km world with regions, the skyline, POIs, shrines, waystones, caches, cairns and light content; formations as lock groups with banners, group braces and crowd rendering |
| W17 | **P27** Open-world UX | **P28** World audio | Map, compass, pins, discovery, fast travel, the tracked quest, the journal and sealed places; every region and place has music and ambience; the new creatures, engines and formations have sounds |
| W18 | **P29** The Crownmarch | **P31** Abilities and weapons | **M7 gate.** From the crown to the Kingsgate beacon, stage 4, the three oaths opening, Brannock's oath, the Crownmarch's side quests and formation fights; evolutions, the stage 4–6 movesets, axes, the great pine, titanforging. **Play link `0.7.0-m7`.** |
| W19 | **P32** Siege engines, cavalry, fists | **P33** Talents and ancestries | Ballistae, catapults, crews, cavalry, siege disruption, fists and Rampart Grip; level 12 with talents and an ancestry |
| W20 | **P34** Trolls, rival giants, the three bosses | **P37** The living world | Trolls, dire wolves, rival giants; the Iron Regiment, the Troll Matriarch, Harrok; the wander and world-event framework with streaming rules, the Crownmarch's table, the Millford raid and the army column |
| W21 | **P35** The Greywood and the Drowned Steps | **P36** Aldmere, the Stonehold and the finale | **M8 gate.** All five regions with their wander tables and events; the main thread completes in every order of every oath pair. Optional play link `0.8.0-m8` |
| W22 | **P38** The world bot | — | The bot plays the world in every policy and order |
| W23 | **P39** Stability, balance, how it plays | — | **M9 gate.** A 60-minute world stability run, the balance pass, the report |
| W24 | **P40** Ship | — | **Ship gate.** Docs, handoff, exports, play link `0.9.0-m9`, merge to `main` |

**Why this order.** Audio is pure presentation, so its three packages run beside the gameplay and world
packages whose files are disjoint (W12–W14, W17). The campaign foundations (P20) land first so every
later package adds files instead of editing registries. Streaming is proven on a generated test world
before the real world exists (P24a, P24b), as the level framework was proven before the Valley in
M2–M5; it is split in two because its scope (terrain, streaming, the skyline mechanism and the web
check; then navigation, determinism, the query helper and the director) is more than one session.
Growth to 4–6 (P26) needs only P24a's terrain to walk on and runs beside P24b. Formations (P30) land
beside the world builder so the Crownmarch (P29) can place formation fights in the M7 build, and the
abilities and stage movesets (P31) merge before the M7 gate so the M7 giant fights at stage 4 with a
moveset that lands at its feet and with its evolutions. Siege (P32) follows formations and precedes the
bosses (P34) that use engines and cavalry; the living-world framework (P37) lands before the region
packages (P35, P36) so they own their regions' tables and events; the world bot (P38) waits for all
five regions.

**Gate reviews** (each an independent review agent, then a fix agent; every confirmed finding is fixed
with a regression test or handed to the owning package through `FOLLOWUPS.md`):

| Gate | After | What the review checks | Release |
| --- | --- | --- | --- |
| M6 | W14 | Audio coverage (every event mapped or listed as silent; every level and context mapped or listed silent), determinism (soak on/off identical), bit-exact regeneration, the web check (sound after New Game, no hole in the music for 60 s, peak live sample bytes under the cap, the multi-part pack, 0 console errors), the budgets, the rigs' draw calls in the Valley walk, the Thornwick bot check, the Valley regression matrix (off-camera share under 20 % or reported as a miss; the Valley balance items) | Version `0.6.0-m6`; `tools/build_web.sh`; the orchestrator republishes the play link |
| M7 | W18 | Leaving the Valley from a finished save, from a migrated pre-crown save and from New Game; the far view from the Kings' Door; streaming budgets on desktop and in headless Chromium on the real world with the audio recorder (`stream_check.mjs` across a region border for 60 s: no music gap over 50 ms; worst frame with gameplay); seams and slopes; deterministic cross-chunk paths; stage 4 everywhere it should be and every reachable weapon's moveset at stage 4; map, compass, pins and fast travel; the Crownmarch's quests and formation fights; the M7 content rule; the XP and equipment budgets; Valley revisits at stages 4–6 | Version `0.7.0-m7`; play link (the launcher notes say what M8 adds) |
| M8 | W21 | Stage 6 and its unlocks; the three bosses' phases exactly once per attempt, disengage and yield protocols; every order of every oath pair completes (gate tier); talents and ancestries saved and migrated; budgets with formations and siege in view; the web compositions of every battle | Optional play link `0.8.0-m8` |
| M9 | W23 | The world bot's batches, the 60-minute stability run, the balance targets, the report | — |
| Ship | W24 | The handoff, every doc, the exports, the web build in Chromium, the final check | Play link `0.9.0-m9`; merge to `main` |

**Owner checkpoints (recommended, never blocking).** After the M6 gate: listen to the Valley on
speakers with the usability script's audio sheet (P23 writes it in W14: balance, harshness, threat
readability, music fatigue, the hidden-tab mute). After the M7 gate: play from the crown into the
Crownmarch (the world section P27 writes). Findings become data or tuning in the next package that owns
the data.

### 1.4 Dependencies

| Package | Depends on (merged earlier) |
| --- | --- |
| P19, P20 | — (M0–M5) |
| P21 | P19 (cue banks, router); P20 (anchors) |
| P22 | P20 (anchors P22 in `enemy_actor.gd`, `enemy_schema.gd`; the `faction` schema) |
| P23 | P19, P21 (shared synthesis library extended by P21), P22 (the launcher's argument pass-through and the web presets) |
| P24a | P20 (`LevelRoot.index()`, events, anchors, BUILDERS entry, the runtime-node registry), P22 (the `Web (test)` preset and the launcher's arguments) |
| P24b | P24a (chunk data, the streamer, the test world) |
| P25 | P24a, P24b (chunk writer, nav bake, the skyline library), P20 |
| P26 | P20 (`LevelExit`, `travel_to`, checkpoint `max_stage` in the index), P24a (the test world for walking stages 4–6) |
| P27 | P20 (index, quests in the campaign), P24a (`WorldRoot.region_at`), P25 (map image, POIs, waystones, sealed places) |
| P28 | P19, P21, P23 (audio engine and libraries), P25 (region and POI ids), P30 (formation emitters) |
| P29 | P22 (faction records), P25 (world, regions), P26 (stage 4, size gates, exits), P27 (discovery, fast travel, tracked quest, multi-marker stages), P30 (formations) |
| P30 | P22 (merged rigs), P24b (director and navigation in the world) |
| P31 | P26 (profiles 4–6, the weapons' `stage_movesets` field) |
| P32 | P30 (target provider, formations, crews in formations), P31 (the evolution mechanism for Rampart Grip) |
| P33 | P31 (the abilities talents grant) |
| P34 | P30, P32 (the battle boss uses formations, engines and cavalry), P26 |
| P35 | P29 (world content patterns, factions), P31 (great pine, axe), P34 (troll matriarch), P37 (wander framework) |
| P36 | P29, P32, P33 (ancestry dialogue tags), P34 (Iron Regiment, Harrok), P37 (world-event framework) |
| P37 | P29 (Millford), P30 (target provider, moving formations), P32 (cavalry for the army column) |
| P38 | P27 (map data and fast travel), P35, P36 (all regions), P37 (wander and event APIs) |
| P39 | P38 |
| P40 | P39 |

### 1.5 Hotspot policy

The three mechanisms of M2–M5 §1.5 stay. **P20 extends them for M6–M9 in W12:**

1. **Pre-declared registries** (P20 adds every planned path; a missing file is skipped silently):
   `DataValidator.SCHEMA_PATHS` (M7–M9 types; P19 adds the audio types itself, §1.6),
   `build_scenes.gd BUILDERS`, `ScreenStack.SCREENS` and `HOTKEYS`, `HudWidgets.WIDGETS`,
   `ShrineScreen.TABS`, `LevelRoot.RUNTIME_NODES` (new: level-wide nodes created at run time),
   `ResetHooks.AFTER_EACH` (P19 adds to `BEFORE_EACH`). The lists are in §2.15.
2. **Package anchors** (`## @anchor P<id>` lines, written by P20 in W12 and listed in
   `tests/support/anchors_expected.gd`; a package inserts only directly below its own):

| File | Anchors (M6–M9) |
| --- | --- |
| `scripts/core/events.gd` | P21–P40, P24a, P24b (P20 declares §2.4's signals above them) |
| `scripts/actors/enemy_actor.gd`, `scripts/ai/enemy_brain.gd` | P22, P24b, P30, P32, P34, P37 |
| `scripts/actors/attack_runner.gd` | P30, P31, P32, P34 |
| `scripts/combat/hit_factory.gd` | P32 |
| `scripts/world/projectile_system.gd` | P31, P32, P34 |
| `scripts/presentation/telegraph_visuals.gd` | P30, P31, P32, P34 |
| `scripts/actors/player/player_targeting.gd` | P30 |
| `scripts/world/encounter_director.gd` | P24b, P29, P30, P32, P34, P37 |
| `scripts/world/level_root.gd` | P24a, P24b, P25, P27 |
| `scripts/quests/quests.gd`, `scripts/quests/quest_conditions.gd` | P27, P29, P37 |
| `scripts/core/game_data.gd` (post-pass) | P24a, P24b, P25, P26, P29, P30, P31, P32, P33, P34, P37 |
| `scripts/core/schemas/action_schema.gd` | P26, P31, P32, P34 |
| `scripts/core/schemas/enemy_schema.gd` | P22, P30, P32, P34 |
| `scripts/core/schemas/prop_schema.gd` | P26, P30, P32 |
| `scripts/core/schemas/weapon_schema.gd` | P26, P31, P32 |
| `scripts/core/schemas/growth_profile_schema.gd` | P26, P30 |
| `scripts/core/schemas/encounter_schema.gd` | P24b, P29, P30, P37 |
| `scripts/core/schemas/level_schema.gd` | P24a, P24b, P25 |
| `scripts/core/schemas/shrine_schema.gd` | P26 |
| `scripts/core/schemas/item_schema.gd`, `ancestry_schema.gd`, `player_schema.gd` | P31, P33 |
| `scripts/presentation/camera_rig.gd` | P24a, P26, P30 |

3. **Single owner per wave** for the other shared files:

| File | W12 | W13 | W14 | W15 | W16 | W17 | W18 | W19 | W20 | W21 | W22+ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `project.godot` | P19 | — | — | P26 | — | — | — | — | — | — | gates, P40 |
| `scripts/main.gd` | P19 (loading gate) | — | P24a | — | — | — | — | — | — | — | — |
| `ui/hud.gd` | — | — | — | — | — | P27 | — | — | P34 | — | — |
| `scripts/core/game_session.gd` | P20 | — | — | — | — | — | — | — | — | — | P38 |
| `scripts/core/save_slots.gd`, `scripts/progression/character_state.gd` | P20 | — | — | — | — | — | — | P33 | — | — | — |
| `scripts/core/settings.gd`, `ui/screens/settings_pages.gd` | P19 | — | — | — | — | — | — | — | — | — | — |
| `scripts/core/data_validator.gd` | P19 + P20 (§1.6) | — | — | — | — | — | — | — | — | — | — |
| `tests/support/reset_hooks.gd` | P19 + P20 (§1.6) | — | — | — | — | — | — | — | — | — | — |
| `tools/check.sh` | P19 | — | — | — | P25 | — | — | — | — | — | — |
| `tests/test_runner.gd` | P19 | — | — | — | — | — | — | — | — | — | — |
| `export_presets.cfg`, `web/launcher.html`, `tools/build_web.sh` | — | P22 | P23 | — | — | — | — | — | — | — | gates, P40 |
| `tools/data/valley_layout.json`, `tools/builders/valley.gd` | P20 | P22 | — | P26 | — | — | — | — | — | — | — |
| `tools/builders/{soldier,wolf,ranged,heavy,npcs,player}.gd`, `tools/scene_kit.gd` | — | P22 | — | — | — | — | — | — | — | — | — |
| `scripts/presentation/actor_rig.gd`, `quadruped_rig.gd` | — | P22 | — | — | — | — | — | — | — | — | — |
| `scripts/ai/{archer_brain,mage_brain}.gd` | — | P22 | — | — | — | — | — | — | — | — | — |
| `scripts/world/{chunk_streamer,world_root}.gd`, `tools/builders/test_world.gd` (P24a's own files) | — | — | P24a | P24b | — | — | — | — | — | — | — |
| `scripts/actors/civilian.gd` | — | — | — | P24b | — | — | — | — | — | — | — |
| `scripts/ai/civilian_brain.gd` | — | P22 | — | — | — | — | — | — | — | — | — |
| `ui/screens/title_screen.gd` | P20 | — | — | — | — | — | — | — | — | — | — |
| `ui/screens/end_screen.gd` | — | — | — | P26 | — | — | — | — | — | P36 | — |
| `scripts/world/shrine.gd`, `scripts/world/waystone.gd` | P20 (activation per visit) | — | — | P26 (`shrine.gd` only) | — | — | — | — | — | — | — |
| `scripts/quests/dialogue_session.gd`, `scripts/core/schemas/dialogue_schema.gd` | P20 | — | — | — | — | — | — | — | — | — | — |
| `scripts/world/breakable_prop.gd`, `scripts/actors/player/player_growth.gd`, `player_equipment.gd` | — | — | — | P26 | — | — | — | — | — | — | — |
| `scripts/actors/player/player_motor.gd` | — | — | — | P26 | — | — | P31 | P33 | — | — | — |
| `scripts/actors/player/player_attack.gd` | — | — | — | P26 | — | — | P31 | — | — | — | — |
| `scripts/actors/player/player_grab.gd` | — | — | — | — | — | — | — | P32 | — | — | — |
| `scripts/progression/progression.gd`, `player_progression.gd` | — | — | — | — | — | — | P31 | P33 | — | — | — |
| `scripts/world/forge.gd`, `scripts/presentation/weapon_visuals.gd` | — | — | — | — | — | — | P31 | P32 (`weapon_visuals.gd`: fists) | — | — | — |
| `scripts/combat/combatant.gd` | — | — | — | — | — | — | — | P33 | — | — | — |
| `scripts/world/boss_arena.gd`, `ui/hud/boss_bar.gd` | — | — | — | — | — | — | — | — | P34 | — | — |
| `scripts/world/faction_state.gd` | — | P22 | — | — | — | — | P29 | — | — | — | — |
| `scripts/audio/cue_router.gd` | P19 | P21 | — | — | — | P28 | — | — | — | — | — |
| `scripts/audio/{music_director,ambience_director}.gd` | P19 | — | P23 | — | — | P28 | — | — | — | — | — |
| `data/progression/progression_default.json` | P20 | — | — | — | — | — | P31 | P33 | — | — | P39 |
| `data/growth/growth_0*.json` | — | — | — | P26 | P30 (`target_rules`) | — | P31 (`unlocks`) | — | — | — | P39 |
| `data/weapons/{club,sword,hammer}*.json` | — | — | — | P26 (`fit_max_stage`, `stage_movesets` keys) | — | — | P31 (movesets, refits) | — | — | — | P39 |
| `data/quests/quest_world_main.json` | — | — | — | — | — | — | P29 | — | — | P36 | P39 |
| `data/shrines/shrine_world_*.json` | — | — | — | — | P25 | — | P29 | — | — | — | P39 |
| `data/world/encounter_crownmarch_toll_fort.json` | — | — | — | — | — | — | P29 | — | — | P36 (stage-5 tower ballista) | P39 |
| `data/world/encounter_<region>_*.json` of the light content (§5.10) | — | — | — | — | P25 | — | P29 (crownmarch) | — | — | P35, P36 (their regions) | P39 |
| `tests/unit/test_world_xp_budget.gd`, `test_world_equipment_budget.gd`, `tests/support/world_xp.gd` | — | — | — | — | — | — | P29 | — | — | — (P35 and P36 add their own oath suites using the helpers) | P39 |
| `tools/data/world/world.json`, `tools/builders/world.gd`, `tools/world/*` (library) | — | — | P24a (`tools/world/` terrain library) | P24b (`nav_bake.gd`) | P25 | — | — | — | — | — | — |
| `tools/data/world/<region>.json` | — | — | — | — | P25 | — | P29 (crownmarch) | — | — | P35 (greywood, drowned_steps), P36 (aldmere, stonehold) | P39 |
| `data/input/default_bindings.json`, `scripts/adapters/input_bindings.gd` | — | — | — | — | — | P27 | — | — | — | — | — |
| `scripts/debug/autopilot.gd` | — | — | P24a | — | — | — | — | — | — | — | P38 |
| `scripts/debug/valley_bot.gd`, `bot_diagnosis.gd`, `valley_walk.gd` | — | — | — | P24b (`NavQuery` call sites) | — | — | — | — | — | — | P38 |
| `scripts/debug/bot_combat.gd`, `run_metrics.gd`, `tools/run_bots.sh`, `tools/bot_report.py` | — | P22 (`run_metrics.gd`) | — | — | — | — | — | — | — | — | P38, P39 |

### 1.6 Shared edits inside W12

P19 and P20 both touch two files in W12. To keep their hunks apart:

- `scripts/core/data_validator.gd`: P19 inserts its five audio entries into `SCHEMA_PATHS` directly
  **after the `"progression"` line**; P20 inserts its M7–M9 entries directly **after the
  `"tutorial_prompt"` line** and changes the enum constants. Audio enums live in the audio schema
  modules, not here.
- `tests/support/reset_hooks.gd`: P19 adds `["autoload", "Audio", "reset_for_tests"]` as the **first**
  entry of `BEFORE_EACH`; P20 appends its entries at the **end** of `AFTER_EACH`.

---

## 2. Shared contracts

SI units (m, s, m/s; degrees in data, radians in code). Every data record carries
`schema_version: 1`, a stable dotted `id` and a `type`; one record per JSON file under `data/<folder>/`
(two levels at most: the export filter is `data/*.json, data/*/*.json`). Signatures are GDScript 4.6.

### 2.1 Folders and owners

| Folder | New contents (owner) |
| --- | --- |
| `scripts/audio/` | `audio_director.gd` (autoload `Audio`), `voice_pool.gd`, `cue_router.gd`, `music_director.gd`, `melody_scheduler.gd`, `ambience_director.gd`, `audio_math.gd` (P19) |
| `data/audio/` | `bank_*.json` (P19 placeholder bank; P21 SFX; P23 stingers and ambience cues; P28 world), `mix_default.json` (P19, extended by P21/P23/P28), `music_*.json`, `ambience_*.json`, `region_*.json` (P23, P28) |
| `assets/audio/` | `sfx/<family>/*.wav` (+ `.import`), `music/*.ogg`, `ambience/*.ogg` (beds, emitters and spots), `manifest.json`, `PROVENANCE.md` (P19 creates; P21, P23, P28 add) |
| `tools/audio/` | `synth/` (Python library: `core.py`, `instruments.py`, `voices.py`, `fx.py`, `music.py`, `ambience.py`), `gen_<family>.py`, `build_audio.py` (runner: `--only`, `--verify`, `--masters-out`, `--budget`), `encode.py` (libvorbis, bit-exact flags), `test_synth.py` (P19 creates the runner and `core.py`; P21 the SFX families; P23 the music and ambience families; P28 the world families) |
| `tools/web/` | `audio_check.mjs` (Playwright, P23), `stream_check.mjs` (P24a), `world_check.mjs` (P39) |
| `scripts/world/` | `level_exit.gd`, `world_index.gd` (P20); `chunk_data.gd`, `terrain_chunk.gd`, `chunk_streamer.gd`, `world_root.gd`, `skyline.gd` (P24a); `nav_maps.gd`, `nav_query.gd` (P24b); `size_gate.gd` (P26); `discovery.gd` (P27); `inscription.gd` (P25); `siege_engine.gd` (P32); `battle_boss.gd` (P34); `wander_director.gd`, `world_event.gd` (P37) |
| `tools/world/` | `chunk_writer.gd`, `heights.gd`, `skyline_writer.gd` (P24a); `nav_bake.gd` (P24b); `features.gd`, `kinds/*.gd`, `map_render.gd`, `index_writer.gd`, `layout.gd` (P25) |
| `tools/data/world/` | `world.json` (frame, terrain features, rivers, lake, roads, skyline landmarks) and one file per region (`crownmarch.json`, `greywood.json`, `drowned_steps.json`, `aldmere.json`, `stonehold.json`) (P25 skeleton and light content; region packages afterwards) |
| `assets/world/` | `chunks/c<x>_<z>.res`, `nav/c<x>_<z>_<layer>.res`, `index_world.res`, `index_valley.res` (P20), `map_world.png`, `skyline.res`, `skyline_landmarks.res`, `shared/` (meshes and materials loaded once) (P24a test world under `assets/test_world/`; P25 the real one) |
| `assets/shaders/` | `skyline.gdshader` (P24a) |
| `scenes/world/` | `world.tscn` (root), `chunks/c<x>_<z>.tscn` and `chunks/c<x>_<z>_<part>.tscn` (props, settlements as several sub-scenes, POI landmarks of one chunk) (P25 and the region packages through the builder) |
| `data/world/` | `level_world.json`, `region_*.json`, `poi_*.json`, `cache` loot tables (P25); `faction_*.json` (P22 `village`; P29 the Crownmarch's and Aldmere's; P35, P36 theirs); `encounter_<region>_*.json` (P25 light content, then the region packages); `wander_*.json`, `event_*.json` (P37 the framework's Crownmarch records; P35, P36 their regions') |
| `data/test/` | every record of a test-only level (`level_*`, `encounter_*`; P22 moves today's director-test and stress-arena records here; later test levels put theirs here). Excluded from the web release |
| `data/dialogue/` | `dialogue_cairn_*.json` (P25), the talkers' dialogues (region packages) |
| `data/talents/` | `talent_*.json` (P33) |
| `tests/gate/` | walkthroughs, oath combinations, seeded boss runs, soaks (decision 34; P19 adds the runner option) |
| `tests/fixtures/saves/` | v1 saves from the end of each Valley outcome and one before the crown (P20) |

### 2.2 Physics, render and navigation layers; groups

| Physics layer (value) | Name | Used by |
| --- | --- | --- |
| 1–6 | unchanged | world, actors, hurtboxes, debris, breakables, blockers (`ACTOR_MASK` 51) |
| 7 (64) | `size_gate_4` | **New (P26).** Invisible walls that stop a giant below stage 4 (the Wend's deep reach) |
| 8 (128) | `size_gate_5` | **New.** Below stage 5 (the Mere's deep channel) |
| 9 (256) | `size_gate_6` | **New.** Below stage 6 (the Giant's Stair, the Moot's gate) |

The player's collision mask is `ACTOR_MASK | gate bits above its stage` (stage ≤ 3: 64 + 128 + 256;
stage 4: 128 + 256; stage 5: 256; stage 6: 0), set by `PlayerGrowth` with the profile
(`size_gate_mask` in the profile, §2.9). Enemies never collide with size gates; their navmeshes
exclude the gated water (human and large layers) or carry it as gate regions (titan layer). Camera,
attack occluders and sight ignore layers 7–9. Render layers are unchanged.

| Nav layer (bit) | Name | Radius / height / cell / climb / slope | Where | Used by |
| --- | --- | --- | --- | --- |
| 1 | human | 0.75 / 2.0 / 0.25 / 0.25 / 40° in the world (Valley unchanged: 0.6) | Valley, world | Soldiers, archers, mages, wolves, dire wolves, civilians, crews |
| 2 | large | 1.5 / 6.0 / 0.5 / 0.5 / 40° | Valley, world | Ogres, trolls, cavalry |
| 4 | giant | 2.0 / 8.5 / 0.5 | Valley only | Player stages 2–6 in the Valley (`player_nav_fallback` 4), the Ogre King, the Valley bot |
| 8 | small giant | 0.9 / 3.7 / 0.3 | Valley only | Player stage 1 |
| 16 | titan | **New.** 4.0 / 19.0 / 1.0 / 2.0 / 40° | World (and P24b's test world) | Player stages 3–6 in the world (`player_nav_fallback`), rival giants, the troll matriarch, the world bot |
| 32 / 64 / 128 | titan gate 4 / 5 / 6 | Same bake as titan, baked as separate regions on the titan map | World | Ground a giant of stage ≥ 4 / 5 / 6 may cross (the Wend's deep reach; the Mere's deep channel; the Giant's Stair and the Moot's gate) |

A giant's titan query mask is `16 | 32 (stage ≥ 4) | 64 (stage ≥ 5) | 128 (stage ≥ 6)`
(`PlayerGrowth.nav_query_mask()`); rival giants use 240 (giants of the old height cross every gate).
Heaved rockfalls, breached gates and the Needle are not gate regions: rockfalls and gates carry
`NavigationLink3D`s per layer that open when they break (as in the Valley), and the Needle (5.0 m) has
no titan navmesh at all (the world bot walks it on a `direct` road edge, §6.1).

World navmeshes are baked offline per chunk with lean settings (edge error 2.0, detail distance 24,
detail error 4), the bake AABB grown by `border_size = radius + 2 × cell` (whole cells), the voxel
grid's y origin floored to a world-wide multiple of the cell height (0.25 m human, 0.5 m large and
titan), source geometry including the eight neighbours' obstacles, and `use_edge_connections` off
(`open_world_tech.md` §5.2). Each layer has its own navigation map (cell size and height set per
map); the titan gate regions join the titan map.

New groups: `world_root` (P24a), `chunk_streamer` (P24a), `level_exits` (P20), `size_gates` (P26),
`poi_landmarks` (P25), `inscriptions` (P25), `crowd_renderers` (P30), `siege_engines` (P32),
`wander_director` (P37), `audio_director` (P19). Existing groups keep their meaning; in the world,
groups contain only nodes of loaded chunks (the index answers for the rest).

### 2.3 Ids and flags

| Kind | Pattern | Examples |
| --- | --- | --- |
| World entity ids (spawned actors) | `world.<region>.<name>` | `world.crownmarch.scout_1`, `world.greywood.troll_matriarch` |
| World ids (persistent props, pickups) | `world.<region>.<name>` | `world.aldmere.fort_gate`, `world.drowned.bell_3` |
| Shrines / waystones (checkpoint ids) | `world.shrine.<name>` / `world.cp.<name>` | `world.shrine.kingsgate`, `world.cp.kingsgate_shelf` |
| Markers, areas, patrols | `world.marker.<name>`, `world.area.<name>`, `world.patrol.<name>` | `world.marker.kingsgate_beacon` |
| Level exits | `<level short>.exit.<name>` | `valley.exit.kings_door`, `world.exit.kingsgate` |
| Records | `region.<name>`, `poi.<name>`, `faction.<name>`, `talent.<tree>_<name>`, `ancestry.<name>`, `wander.<region>`, `event.<name>`, `audio_bank.<name>`, `audio_mix.<name>`, `music.<name>`, `ambience.<name>`, `audio_region.<name>` | `poi.hollowmere`, `talent.destroyer_shoulder_charge` |
| Formations (in encounter data) | `<encounter short id>.<formation>` | `aldmere_patrol.pikes` |
| Battles (boss ids that are not enemy records) | `battle.<name>` | `battle.iron_regiment` |
| Chunks | `c<x>_<z>` (x, z = 0..7 west→east, north→south) | `c2_7` |
| Cues | `sfx.<family>.<...>`, `amb.<...>`, `mus.<...>` | `sfx.hit.flesh.light`, `amb.bird_a`, `mus.stinger.growth` |

New flag domains (first write wins unless noted):
- `discovered.<poi short>`, `map.seen.<chunk>`, `region.<short>.entered`, `visited.<checkpoint id>`
  (a waystone or shrine was reached; fast-travel eligibility), `sealed.<poi short>.seen`, `map.pin`
  (`[x, z]` or `""`, overwritten) (P27)
- `world.kingsgate.lit`, `world.citadel.breached`, `world.throne.claimed`, `world.<place>.<state>`
- `oath.<march|wood|crown>.done` (bool) and `oath.<march|wood|crown>.outcome` (`help` | `intimidate` | `force` / `slay` | `drive` / `breach` | `sabotage` | `parley`)
- `boss.<short>.outcome` (`slain` | `spared` | `fled` | `yielded_talk`), `boss.<short>.defeated`
- `faction.<f>.{warned,hostile,stood_down,reconciled,allied,tribute}` for every faction record (P22
  generalises `FactionState`; `reconciled` wins over `hostile`, which wins over `stood_down`);
  `settlement.<short>.<state>` is not used (factions carry it)
- `ancestry.chosen` (P33), `talent.<id>` is not a flag (talents live in the character)
- `wander.<table short>.<entry>.spawns` (int, overwritten), `event.<id>.done`, `event.<id>.outcome`
  (P37)
- `progress.world_entered`, `campaign.completed` (the world's end; `slice.completed` keeps meaning
  "the prologue is complete")

### 2.4 Events (P20 declares all of these; afterwards packages add only below their own anchor)

Existing signals are unchanged. New, in a block "campaign and world (M7–M9)" of `events.gd`:

| Signal (arguments) | Emitted by | Typical listeners |
| --- | --- | --- |
| `travel_requested(level_id: String, checkpoint_id: String, reason: String)` — reason `exit` \| `fast_travel` \| `debug` \| `bot` | `LevelExit` (P26), map screen (P27), bot | `GameSession.travel_to` |
| `level_leaving(tick: int, from_level: String, to_level: String, reason: String)` | GameSession, before the reload | Audio (fade), HUD |
| `level_entered(tick: int, level_id: String, reason: String)` — reason `new_game` \| `continue` \| `death` \| `travel` \| `fast_travel` \| `debug` | GameSession, once the level is ready (the ring loaded, the samples registered) | Audio, Quests, Discovery, tutorial, bot, the per-visit activation set |
| `world_chunk_loaded(chunk_id: String)`, `world_chunk_unloading(chunk_id: String)`, `world_chunk_unloaded(chunk_id: String)` | ChunkStreamer (P24a) | Director (despawn on `unloading`), Discovery, the skyline mask, debug |
| `region_changed(tick: int, region_id: String, previous_id: String)` | WorldRoot (P24a; 15 m hysteresis) | Audio, region banner (P27), Quests |
| `poi_discovered(tick: int, poi_id: String)` | Discovery (P27) | HUD toast, Audio stinger, Quests, bot metrics |
| `quest_tracked(quest_id: String)` | Quests (P27) | Objective marker, compass, tracker |
| `size_gate_blocked(tick: int, gate_id: String, min_stage: int, message: String)` | SizeGate, stage-gated props (P26) | HUD message, Audio (the gate's own cue), tutorial |
| `trampled(tick: int, world_id: String, entity_id: String)` | BreakableProp trample (P26) | Audio, FactionState (houses), metrics |
| `formation_changed(tick: int, formation_id: String, state: String)` — `formed` \| `advancing` \| `braced` \| `broken` \| `routed` \| `banner_fell` | Formation (P30) | HUD lock label, Audio (horn, flag drop, rout stinger), bot metrics, tutorial |
| `siege_engine_fired(tick: int, engine_id: String, action_id: String, target_id: String)`, `siege_engine_crewed(tick: int, engine_id: String, crewed: bool)` | SiegeEngine (P32) | Audio, metrics |
| `ability_evolved(tick: int, from_id: String, to_id: String, slot_key: String)` | PlayerProgression (P31) | HUD notice, Audio |
| `talent_learned(tick: int, talent_id: String)` | PlayerProgression (P33) | HUD, Audio, Quests |
| `ancestry_chosen(tick: int, ancestry_id: String)` | PlayerProgression (P33) | Quests, Audio, HUD |
| `boss_yielded(tick: int, boss_id: String)` | BattleBoss, RivalGiantBrain (P34) | Quests, Audio, boss bar, the yield prompt |
| `boss_disengaged(tick: int, boss_id: String, reason: String)` — reason `left` (the player left the arena; the boss resets) \| `fled` (the Matriarch's drive-out ending) | BossArena, BattleBoss, MatriarchBrain (P34) | Audio (back to the zone set; `fled` plays the yield stinger), boss bar, Quests |
| `wander_spawned(tick: int, template_id: String, encounter_id: String)` | WanderDirector (P37) | Metrics, debug |
| `world_event_started(tick: int, event_id: String)`, `world_event_ended(tick: int, event_id: String, outcome: String)` | WorldEvent (P37) | Quests, HUD, Audio |

### 2.5 Audio (P19)

```gdscript
# scripts/audio/audio_director.gd — autoload "Audio" (order: ... Quests, Sim, Audio)
extends Node
const BUSES := ["Music", "Ambience", "SFX", "UI"]   # made at _ready when missing; send to Master; no effects
const REFERENCE_HEIGHT_M := 3.6576
var enabled := true                  # false with --no-audio (the default suite): no listeners, no players, nothing plays
var music: MusicDirector             # child, PROCESS_MODE_ALWAYS
var ambience: AmbienceDirector       # child, PROCESS_MODE_PAUSABLE
var pool: VoicePool                  # child: voices_3d AudioStreamPlayer3D (pausable) + spot_voices (2, STREAM) + voices_2d AudioStreamPlayer (UI: always)
var router: CueRouter                # Events -> cue requests (queued; resolved and played in _process)
var listener: AudioListener3D        # at the giant's chest (camera_pivot_height × 0.8), camera yaw and pitch
func play(cue_id: String, at: Vector3 = Vector3.INF, opts: Dictionary = {}) -> int
	# opts: "source_height_m", "priority", "volume_db", "pitch", "reason", "expected_damage", "poise_ratio";
	# at INF = non-positional. Returns a voice id, or -1 (unknown cue, capped, retrigger guard,
	# under min_level_db, suppressed sting, disabled)
func resolve(cue_id: String) -> Dictionary     # the cue after the fallback chain ({} = none)
func has_cue(cue_id: String) -> bool
func distance_scale() -> float                 # clamp(player height / 3.6576, 1, 5.2)
func is_ready() -> bool                        # every sample of the current level registered (true at once on desktop)
func registration_progress() -> float          # 0..1 for the loading screen
func set_bus_volume_linear(bus: String, value: float) -> void   # Settings; 0 mutes
func enable_for_tests(on := true) -> void      # audio suites; the default suite runs with --no-audio
func cue_log() -> Array                        # last 512: {"frame","cue","bus","pos","voice","priority","reason"}
func clear_log() -> void
func reset_for_tests() -> void                 # stop all, clear log and queues, reset directors (ResetHooks); no-op when disabled
func debug_lines() -> PackedStringArray        # F3: voices, queue, music set, intensity, melody segment, ambience set
```

- **Startup and the loading gate.** `_ready`: read `--no-audio`; make the buses; build the pool from
  `audio_mix.default`; connect the router to `Events`; connect `get_tree().node_added` to wire rig
  footfall signals (`ActorRig.footfall`, and `QuadrupedRig.footfall` when it exists, P22). It detects
  a level when a node joins `level_root` (or `sandbox`) and registers that level's SFX samples
  (`AudioServer.register_stream_as_sample`, a no-op on desktop), global cues first, in slices of at
  most `register_ms_per_frame` (12 ms) while the tree is paused behind the loading screen.
  `scripts/main.gd` keeps the tree paused and shows "Loading..." until `Audio.is_ready()` (P19 adds
  this gate in W12 for every level; P24a extends the same screen to the world's ring in W14), so no
  sound plays before its sample exists and the first `play()` never registers. The music director is
  silent during registration (after `level_leaving`'s fade, before `level_entered`).
- **Focus.** On `NOTIFICATION_APPLICATION_FOCUS_OUT` and `NOTIFICATION_WM_WINDOW_FOCUS_OUT` with
  `mute_when_unfocused`, Master ramps to −80 dB in 0.2 s (back on focus in); on the web a JavaScript
  `visibilitychange` callback (`JavaScriptBridge.create_callback`) mutes Master while the page is
  hidden.
- **Pause.** SFX and ambience players are `PROCESS_MODE_PAUSABLE` (silenced by the tree pause); music
  is `PROCESS_MODE_ALWAYS` and ducked by the director while a pausing screen is open.
- **Settings** (P19 adds to `Settings.DEFAULTS` and `RANGES`, and an "Audio" section in the settings
  pages): `volume_master` 1.0, `volume_music` 0.8, `volume_ambience` 0.8, `volume_sfx` 1.0,
  `volume_ui` 0.8 (0..1, applied with `AudioServer.set_bus_volume_linear` on top of the mix's bus
  levels), `mute_when_unfocused` true.

Record types (schema modules in `scripts/core/schemas/`, registered by P19):

```json
{"schema_version": 1, "id": "audio_bank.combat", "type": "audio_bank", "display_name": "Combat",
 "cues": {
  "sfx.hit.flesh.light": {"files": ["res://assets/audio/sfx/combat/hit_flesh_light_1.wav",
                                    "res://assets/audio/sfx/combat/hit_flesh_light_2.wav"],
    "bus": "SFX", "spatial": true, "class": "impact", "volume_db": -3.0, "pitch": 1.0,
    "pitch_jitter": 0.06, "size_pitch": true, "max_voices": 8, "retrigger_ms": 45, "priority": 80,
    "far": "", "levels": []}}}
```

- `files`: 1–4 variants (WAV for the SFX and UI buses, each at most 2.0 s; Ogg for Music and
  Ambience cues: loops, stingers and ambience spots). A variant is picked by the director's RNG,
  never the same twice in a row.
- `class`: an audibility class of the mix; `size_pitch`: pitch × (3.6576 / source height)^0.25,
  clamped 0.6–1.25, so bigger bodies sound lower; `far`: a cue played instead when the source is
  farther than half the class's scaled `max_m`; `levels`: register only for these levels ([] = always).

```json
{"schema_version": 1, "id": "audio_mix.default", "type": "audio_mix",
 "bus_db": {"Music": -9, "Ambience": -12, "SFX": -6, "UI": -10},
 "pool": {"voices_3d": 24, "web_voices_3d": 16, "spot_voices": 2, "voices_2d": 8, "starts_per_frame": 16,
          "web_starts_per_frame": 8, "min_level_db": -45, "register_ms_per_frame": 12},
 "classes": {"impact": {"unit_m": 5, "max_m": 40, "scaled": true},
             "threat": {"unit_m": 8, "max_m": 80, "scaled": "sqrt"}},
 "duck": {"stinger": {"Music": -8}, "dialogue": {"Music": -6, "Ambience": -10}, "pause": {"Music": -10},
          "boss": {"Ambience": -6}, "combat": {"Ambience": -4}},
 "materials": {"prop.fence_wood": "wood", "prop.cairn": "stone", "prop.gate_fortified": "stone"},
 "voices": {"enemy.soldier": "human", "enemy.wolf": "wolf", "enemy.ogre_king": "ogre_king"},
 "surfaces": {"level.valley": {"hollow": "soft", "quarry": "hard", "ruins": "hard"}},
 "intensity": {"combat_radius_m": 35, "danger_radius_m": 70, "danger_cap_m": 150, "lesser_danger_m": 40,
               "lesser_height_ratio": 0.3, "combat_hold_s": 6, "danger_hold_s": 8,
               "hit_recent_s": 5, "telegraph_recent_s": 3, "poll_s": 0.25},
 "sting": {"min_damage_fraction": 0.03, "skip_at_poise_floor": true},
 "footfall": {"cruise_after_s": 10, "cruise_duck_db": -5}}
```

```json
{"schema_version": 1, "id": "music.valley_wild", "type": "music_set", "display_name": "The Old Wood",
 "bpm": 96, "beats_per_bar": 4, "bars": 12, "frame": "zone_96",
 "stems": {"drone": "res://assets/audio/music/drone_wild.ogg",
           "melody_a": "res://assets/audio/music/melody_wild_a.ogg", "melody_b": "res://assets/audio/music/melody_wild_b.ogg",
           "melody_c": "res://assets/audio/music/melody_wild_c.ogg",
           "pulse": "res://assets/audio/music/pulse.ogg", "drums": "res://assets/audio/music/combat_drums.ogg",
           "brass": "res://assets/audio/music/combat_brass.ogg"},
 "layers": {"explore": {"drone": 0, "melody": -2},
            "danger": {"drone": 0, "melody": -9, "pulse": -3},
            "combat": {"drone": -4, "melody": -10, "pulse": -5, "drums": 0, "brass": -2}},
 "melody": {"variants": ["melody_a", "melody_b", "melody_c"], "segment_bars": 4, "play_loops": [1, 2],
            "rest_loops": [1, 3], "max_repeat": 2, "min_phrase_gap_s": 60},
 "silence": {"after_explore_s": 180, "length_s": [60, 120], "fade_s": 8},
 "combat_intro": "mus.stinger.combat_wild",
 "phase_layers": {}, "crossfade_bars": 2, "layer_fade_beats": 2}
```

A stem missing from a layer is silent (−80 dB); the layer key `melody` means "the melody variant the
scheduler has chosen for this segment". Every stem of a set has the same length, `bars ×
beats_per_bar × 60 / bpm` seconds (validated, and checked offline to the frame by P19's asset test);
sets that share stems share a `frame` (tempo, metre and loop length), and the validator requires every
shared stem's sets to have one frame. A boss set has its own frame (its own tempo, metre and mode),
an `intro` stinger and `phase_layers` (`{"2": {"frenzy": 0}}`).

**The melody scheduler** (`melody_scheduler.gd`, P19; pure, driven by the music director at every
segment boundary of the lead stem): it plays the melody for `play_loops` loops, then rests for
`rest_loops` loops; inside a played loop it picks, per segment, one of the variants or (with weight
0.15) a rest, never the same variant for more than `max_repeat` segments in a row and never the same
phrase (variant and segment index) within `min_phrase_gap_s`; after `after_explore_s` of explore
with no discovery, region or place change, danger or combat, it fades every stem out over `fade_s`
and leaves the ambience alone for `length_s`, re-entering at the next bar (drone first, the melody one
loop later) on a discovery, a zone change or danger. It uses only the director's own RNG.

```json
{"schema_version": 1, "id": "ambience.forest", "type": "ambience_set", "display_name": "Old Wood",
 "beds": [{"cue": "amb.bed_forest", "volume_db": 0}],
 "spots": [{"cue": "amb.bird_a", "weight": 3, "flush": true}, {"cue": "amb.creak", "weight": 2}, {"cue": "amb.owl", "weight": 1}],
 "spot_interval_s": [4, 12], "spot_distance_m": [15, 40],
 "emitters": [{"cue": "amb.river_loop", "level": "level.valley", "position_m": [106, 0, -20], "radius_m": 60}],
 "reactions": {"flush_radius_m": 40, "flush_s": 8, "flush_cue": "amb.birds_flush"}}
```

Spots are Ogg one-shots played through the two `spot_voices` (3D stream players on the Ambience bus);
a `flush` spot falls silent for `flush_s` after a giant's footfall or stomp within `flush_radius_m` ×
the distance scale, which plays `flush_cue` once.

```json
{"schema_version": 1, "id": "audio_region.valley_wood", "type": "audio_region", "level": "level.valley",
 "districts": ["forest", "barrow"], "regions": [], "pois": [], "context": "", "boss": "",
 "music": "music.valley_wild", "ambience": "ambience.forest", "priority": 0}
```

`context` is `title`, `end`, `campaign_end` or `sandbox` for non-level music (`loading` is silent by
decision and is in the silent list); `boss` names a boss id — an enemy record (`enemy.ogre_king`) or a
battle (`battle.iron_regiment`) — whose `boss_engaged` switches to this record's music; `pois` (P28)
matches POI ids by their radius, so settlements and landmarks get their own bed and, optionally, a
music set or layer override. The highest `priority` match wins (POIs 10, districts and regions 0);
districts (the Valley, `LevelRoot.district_at`), regions (the world, `WorldRoot.region_at`) and POIs
are matched with 15 m hysteresis. Every level record and every context maps to a record or is listed
in the audio silent list (`stress_arena`, `director_test`, the other test levels, `loading`); P23's
test checks it.

**The router's conventions** (P19 implements every row of §4.1 with fallback chains; P21, P23 and
P28 only add cues). A request names the most specific cue first and falls back:
`sfx.<family>.<subject>.<variant>` → `sfx.<family>.<subject>` → `sfx.<family>.default`; enemy and NPC
cues use the record's voice (`audio_mix.voices`, default `human`); prop cues use the record's material
(`audio_mix.materials`, default `wood`); footfalls use the size class of the source (`giant_s1` …
`giant_s6` by the player's stage, `human`, `paw`, `hoof`, `heavy` for ogres, trolls and bosses), the
surface under it (`audio_mix.surfaces`, default `soft`) and `wade` when `WorldRoot.water_at(pos)` is
above the ground at the foot; after `cruise_after_s` of continuous movement the player's footfall
uses its `.cruise` variant (no debris tail) at `cruise_duck_db`, and returns to the full cue in combat,
on stopping, and for landings, jumps and stomps. A cue that does not resolve plays nothing and counts
as `missing` in the debug lines; the coverage tests (P21, P28) keep that list empty. Threat stings are
suppressed for attacks whose expected damage (the attack's power through `DamageResolver.preview`)
is under `sting.min_damage_fraction` of the giant's maximum health or whose poise ratio sits at the
0.25 floor. A formation's brace (one `telegraph_started` with `action_id` of the formation's band
attack) yields one `sfx.threat.windup.wall` per formation per brace cycle (merged within 0.5 s).

**Music director** (`MusicDirector`, P19): state = current set, intensity (`explore` | `danger` |
`combat`), boss phase, melody segment, stinger. Every `poll_s` it computes intensity (§4.3: weighted
by threat relative to the giant), eases layer volumes over `layer_fade_beats` (entering combat starts
at the next beat with the set's `combat_intro` stinger once per combat; leaving waits the hold times),
drives the melody scheduler at segment boundaries, changes set at the next bar boundary of the lead
stem (`stems` first key) with a `crossfade_bars` cross-fade, plays stingers as one-shot streams on the
Music bus ducking the stems, and fades out on `level_leaving` and on the player's death. **Ambience
director** (P19): beds as looping streams cross-faded over 3 s on a zone change; spots every
`spot_interval_s` at a random bearing and distance (× `distance_scale()`) through the spot voices;
reactions (flush); at most two emitters (the nearest within `radius_m`), with up to two formation
march emitters (P28, priority 75) on top.

### 2.6 Campaign session, levels, transitions and the save (P20)

```gdscript
# GameSession additions (Mode.VALLEY now means the campaign: the Valley and the world)
const WORLD_LEVEL_ID := "level.world"
var level_id := ""                                   # the campaign level being played (the save's "level")
func is_campaign() -> bool                           # = is_valley()
func current_level_id() -> String                    # level_id in the campaign; "" otherwise
func travel_to(level_id: String, checkpoint_id: String, reason: String) -> Dictionary
	# {"ok", "message"}. Refused with the checkpoint_blockers() text unless reason is "exit" (an exit
	# is never blocked by aware enemies, but is by dead, grabbed, holding, a screen); refused when the
	# checkpoint's index max_stage is below the player's stage ("The old paths here are too narrow for
	# you now.") or (fast travel) when it is not visited.<id> or its requires_flags do not hold.
	# Commits a checkpoint document with "level" = level_id and "respawn" = checkpoint_id (the index
	# position as "checkpoint.position"), emits level_leaving, and reloads main.tscn.
func respawn_transform(checkpoint_id: String) -> Transform3D   # the node if loaded, else the index entry
func respawn_checkpoint() -> String                  # the saved respawn unless a registered blocker refuses it
	# (its index max_stage is below the stage; P29: hostile guards within 120 m; P37: an active world
	# event within 120 m), then the nearest visited, unblocked checkpoint of the level
func register_respawn_blocker(blocker: Callable) -> void   # Callable(checkpoint_id: String) -> String ("" = fine)
func activated_this_visit(checkpoint_id: String) -> bool   # shrines and waystones activate once per level visit,
func mark_activated(checkpoint_id: String) -> void         # not per node: the set clears on level_entered
func start_world_for_tests(start_checkpoint := "") -> void # --mode=world --new-game [--start=<checkpoint>]
# CLI: --mode=world (= campaign starting in level.world with the world_start character and flags);
#      --start=<checkpoint id> (debug, tests, the web checks)
```

`progression.default` gains `world_start` (P20): the character and flags of the Valley's **worst
guaranteed outcome**, generated from the same numbers as `tests/unit/test_xp_budget.gd`: level 6 with
1,050 XP, stage 3, the force outcome (`slice.completed`, `quest.village.outcome = force`,
`faction.village.hostile`), the base club, the abilities the mandatory path teaches, and the
guaranteed inventory (1 iron ingot and the Ogre King's tusk; the crates are optional). It is used by
`--mode=world --new-game`, tests, the world bot and the balance runs. A P20 test asserts that its XP
equals the Valley budget's floor and its items equal the force path's guaranteed loot.

**Skipping the prologue.** When the existing save has `slice.completed`, the title screen's New Game
asks "Play the prologue" (default) or "Skip to the Old Kingdom"; skipping starts from `world_start`
at the Kingsgate shelf (P20; the M7 world must exist, else the choice is hidden).

**LevelExit** (`scripts/world/level_exit.gd`, P20; `class_name LevelExit extends Interactable`, group
`level_exits`): `@export var exit_id`, `to_level`, `to_checkpoint`, `requires_flags:
PackedStringArray`, `locked_message`, `prompt` ("Step through the Kings' Door"). `can_interact()` holds
when every flag is truthy; `interact()` emits `Events.travel_requested(to_level, to_checkpoint,
"exit")`. Interaction, not a trigger, so nobody leaves by accident, and so the giant never has to fit
through the door.

**Runtime nodes** (`LevelRoot.RUNTIME_NODES`, P20): `[["Discovery", "res://scripts/world/discovery.gd",
["level.valley", "level.world"]], ["WanderDirector", "res://scripts/world/wander_director.gd",
["level.world"]]]`; `LevelRoot._ready` instantiates each whose script exists for its level, so the
world and Valley builders never need a node from a later package.

**Save document, schema 2** (`SaveSlots.SCHEMA_VERSION = 2`):

```json
{"schema_version": 2, "build_version": "0.7.0-m7", "saved_at_unix": 1794000000, "slot": "valley_1",
 "level": "level.world",
 "checkpoint": {"respawn": "world.cp.brannock", "reason": "waystone", "position": [70.0, 11.4, 540.0], "yaw": 3.14},
 "character": {"id": "char.valley_1", "definition_id": "player.giant", "ancestry": "ancestry.stoneblood",
   "ancestry_chosen": true, "talents": ["talent.guardian_stone_hide"], "level": 9, "xp": 2260,
   "unspent_attribute_points": 0, "talent_points": 3, "attributes": {"strength": 18, "endurance": 17, "dexterity": 10,
   "intellect": 12, "willpower": 10, "constitution": 13}, "growth_stage": 5, "weapon": "weapon.club_titan",
   "weapons_owned": ["weapon.club", "weapon.club_reinforced", "weapon.club_titan"],
   "loadout": {"slots": ["ability.titan_stomp", "ability.formation_sweep", "ability.stone_skin", "ability.crushing_grip",
     "ability.crag_hurl", "ability.runic_bolt", "ability.ancestral_mend", "ability.titan_roar"], "ultimate": "ability.titan_surge"},
   "known_abilities": ["..."], "level_exempt": [], "resources": {"health": 1100.0, "stamina": 140.0, "essence": 106.0, "fury": 0.0}},
 "world": {"schema_version": 2, "deltas": {"world.aldmere.fort_gate": {"destroyed": true, "damage_stage": 1, "health": 0.0}},
   "inventory": {"item.titan_iron": 1}, "flags": {"oath.march.done": true, "discovered.brannock": true, "map.seen.c4_5": true,
   "visited.world.cp.brannock": true, "map.pin": [210.0, -40.0]}},
 "progress": {"prologue_complete": true, "world_entered": true, "levels_visited": ["level.valley", "level.world"],
   "tracked_quest": "quest.oath_wood"},
 "stats": {"deaths": 3, "checkpoint_loads": 3, "play_time_s": 5120.4}}
```

`SaveSlots.migrate(doc: Dictionary) -> Dictionary` runs after `read_json` and before `validate()`, one
pure step per version (`_migrate_1_to_2`): adds `character.talents` `[]`,
`character.ancestry_chosen` (false unless the ancestry is not `ancestry.neutral`), `progress`
(`prologue_complete` from the flag `slice.completed`, `world_entered` false, `levels_visited`
`["level.valley"]`, `tracked_quest` "") and `checkpoint.position` / `yaw` from the Valley index when the
respawn is known. Nothing else changes: the world block stays schema 2 (flags can hold ints and
arrays). A save newer than the build is kept as `valley_1.schemaN.rejected.json` (the existing rule).
**Backup recovery across the migration**: a damaged v2 main file with a v1 backup loads the backup,
migrates it and tells the player ("Your last save was damaged; the previous one was loaded."). P20's
save code writes `progress.tracked_quest` from `Quests.tracked_quest_id` when that property exists
and restores it on load; P27 adds the property. Fixtures: the four Valley outcomes' completion saves
(the P17a completion checkpoint holds `slice.completed`) and one pre-crown save, written by bot runs
(P20 records the commands); a migrated pre-crown save retakes the crown and opens the Kings' Door.

**WorldIndex** (`scripts/world/world_index.gd`, P20; `class_name WorldIndex extends Resource`):

```gdscript
@export var level_id := ""
@export var checkpoints := {}   # id -> {"position": Vector3, "yaw": float, "display_name": String, "kind": "shrine"|"waystone",
                                #        "chunk": String, "fast_travel": bool, "requires_flags": PackedStringArray,
                                #        "region": String, "max_stage": int (10 = any)}
@export var markers := {}       # id -> {"position", "kind", "chunk"} (safe markers included: kind "safe")
@export var areas := {}         # id -> {"position", "radius" | "size", "chunk"}
@export var pois := {}          # id -> {"position", "radius", "kind", "region", "display_name", "chunk", "min_stage"} (from poi records)
@export var exits := {}         # id -> {"position", "to_level", "to_checkpoint", "display_name"}
@export var encounters := {}    # id -> {"center", "chunk", "faction"}
@export var props := {}         # world id -> {"position", "chunk"} for quest targets and destroyable landmarks
@export var districts := []     # Valley: [{"id", "display_name", "min", "max"}]
@export var roads := {"nodes": PackedVector3Array(), "edges": PackedInt32Array(), "widths": PackedFloat32Array(),
                      "min_stage": PackedByteArray(), "max_stage": PackedByteArray(), "direct": PackedByteArray()}
@export var region_grid := PackedByteArray(); @export var region_ids := PackedStringArray()
@export var grid_origin := Vector2(); @export var cell_m := 64.0; @export var grid_size := Vector2i()
@export var map_image := ""     # res:// path of the map picture ("" = vector map from districts and roads)
@export var map_bounds := Rect2()
static func for_level(level_id: String) -> WorldIndex        # cached; from the level record's "index"
static func clear_cache() -> void                            # ResetHooks.AFTER_EACH
func position_of(id: String) -> Vector3                      # any kind; Vector3.INF when unknown
func display_name(id: String) -> String
func region_at(pos: Vector3) -> String
func nearest_road_node(pos: Vector3) -> int
func route(from: Vector3, to: Vector3, stage: int) -> PackedVector3Array  # A* over the road edges allowed at `stage`
```

`LevelRoot.index() -> WorldIndex` (P20). `Quests.objective_position` and `GameSession.find_checkpoint`
fall back to the index when the node is not in the tree; the title screen's save line and the
checkpoint toast use `display_name` ("Saved game: level 3, stage 2, at the Grove Shrine"). P20 makes
the Valley builder write `assets/world/index_valley.res` (shrines with their record names, waystones
with new layout names such as "Forest road waystone", markers, areas, districts, roads, exits, and
every checkpoint's `max_stage`, 10 until P26 measures them).

**Quests and dialogue additions (P20)**: a quest stage may name `markers` (several marker or POI ids)
besides `marker`; a stage may carry `xp_floor_level` (on completion it awards max(its `xp`, the XP that
reaches that level)); dialogue effects gain `attribute_points` (int, added to the character's unspent
points); quests' `start_conditions` are evaluated on every pass (today's rule), so a loaded save
starts any quest whose conditions hold.

### 2.7 World data (P25 unless noted)

```json
{"schema_version": 1, "id": "level.world", "type": "level", "display_name": "The Old Kingdom",
 "scene": "res://scenes/world/world.tscn", "start_checkpoint": "world.cp.kingsgate_shelf",
 "index": "res://assets/world/index_world.res", "player_nav_fallback": 16,
 "max_active_enemies": 12, "max_formation_members": 40,
 "lod": {"near_m": 40, "mid_m": 90, "check_ticks": 30, "corpse_free_s": 6},
 "render": {"low": {"shadow_distance_m": 0, "scenery_visibility_end_m": 220, "terrain_visibility_end_m": 700,
                    "msaa": 0, "camera_far_m": 2400},
            "medium": {"shadow_distance_m": 120, "scenery_visibility_end_m": 300, "terrain_visibility_end_m": 700,
                       "msaa": 2, "camera_far_m": 2400}},
 "web_overrides": {"quality": "low", "ai_tier1_m": 30, "max_formation_members": 20},
 "nav_query": {"max_polygons": 0, "chase_distance_m": 120, "far_distance_m": 300, "repath_min_ticks": 6,
               "repath_min_move_m": 2.0, "queries_per_tick": 8},
 "world": {"chunk_size_m": 256, "grid": [8, 8], "origin_m": [-1024, 0, -1024], "height_spacing_m": 4,
           "load_ring": 1, "unload_at": 3, "budget_ms": 4.0, "steps_per_frame_headless": 6,
           "chunk_dir": "res://assets/world/chunks", "nav_dir": "res://assets/world/nav",
           "nav_layers": [1, 2, 16], "gate_bits": {"4": 32, "5": 64, "6": 128},
           "fog_m": [400, 1800], "fog_max": 0.85, "water_level_m": 4.0,
           "skyline": "res://assets/world/skyline.res", "skyline_landmarks": "res://assets/world/skyline_landmarks.res"},
 "regions": ["region.crownmarch", "region.greywood", "region.drowned_steps", "region.aldmere", "region.stonehold"],
 "districts": []}
```

(P20 adds `index` and `player_nav_fallback` to the level schema; P24a adds `world` and the render keys
`terrain_visibility_end_m` and `camera_far_m` (default 800, today's value) at its anchor; P24b adds
`nav_query` (absent = today's queries: the Valley's paths do not change); P25 adds `regions`,
`max_formation_members` and the `web_overrides` key of the same name, which the director reads from
P30 on. `level_valley.json` gains `player_nav_fallback: 4` (P26).)

```json
{"schema_version": 1, "id": "region.greywood", "type": "region", "display_name": "The Greywood",
 "level": "level.world", "tier": 2, "recommended_stage": [4, 5],
 "bounds_m": [[-896, -440], [-320, 300]], "surface": "soft", "discover_xp": 40,
 "faction": "faction.woodfolk", "map_tint": [0.33, 0.47, 0.33], "fog_color": [0.52, 0.6, 0.55],
 "skyline_tint": [0.22, 0.33, 0.24], "wander_table": "wander.greywood",
 "m7_note": "The woodfolk and their troubles come with the next build."}
```

```json
{"schema_version": 1, "id": "poi.hollowmere", "type": "poi", "display_name": "Hollowmere",
 "level": "level.world", "region": "region.greywood", "kind": "settlement",
 "position_m": [-640, 22, -40], "radius_m": 70, "xp": 40, "map_icon": "settlement",
 "compass": true, "landmark": "world.greywood.hollowmere_hall", "skyline": true, "min_stage": 0,
 "reveals_m": 0, "max_inner_stage": 4, "green_m": [-610, 20, 20],
 "note": "The woodfolk's stilt village on the black pond."}
```

`kind`: `settlement` | `shrine` | `waystone` | `ruin` | `landmark` | `camp` | `lair` | `boss` | `forge`
| `gate` | `vista` | `exit` | `secret`. A POI's `landmark` names a layout element that must stand
within its radius (the builder checks); `skyline: true` puts the landmark's silhouette in the skyline
and lets the compass show the POI as "?" from 1,000 m before it is discovered; a `vista` reveals every
POI within `reveals_m` (default 400) on the map; a `secret` (a sealed place) has `min_stage` and a
`seal` (the prop or gate that opens it); a settlement's `max_inner_stage` and `green_m` tell its
talkers where to meet a bigger giant (§2.12).

**ChunkData** (`scripts/world/chunk_data.gd`, P24a; `class_name ChunkData extends Resource`):

```gdscript
@export var chunk_id := ""
@export var coords := Vector2i()
@export var origin := Vector3()              # world position of the chunk's min corner (y 0)
@export var size_m := 256.0
@export var spacing_m := 4.0
@export var samples := 67                    # 65 + a one-sample apron on each side
@export var heights := PackedByteArray()     # 16-bit little-endian, samples × samples (no float copy)
@export var height_min := 0.0                # metres at value 0
@export var height_step := 0.004             # metres per unit
@export var scenery := {}                    # mesh key -> PackedFloat32Array (12 floats per instance)
@export var solids := PackedFloat32Array()   # [kind, x, y, z, sx, sy, sz, yaw] × n (kind 0 box, 1 cylinder)
@export var water := PackedFloat32Array()    # [min_x, min_z, max_x, max_z, surface_y] × n
@export var nav := {}                        # layer bit (int) -> res:// path of its NavigationMesh (gate regions: their bit)
@export var props_scenes := PackedStringArray()  # res://scenes/world/chunks/c<x>_<z>[_<part>].tscn, each ≤ 150 nodes
@export var region_cells := PackedByteArray()# 4 × 4 indices into the level's region list (64 m cells)
@export var surface_cells := PackedByteArray()# 16 × 16 surface ids (0 soft, 1 hard, 2 wet; 16 m cells); colours come from these and the region tints at run time
func height_at_local(x: float, z: float) -> float   # bilinear on the grid (tests, builder)
```

**Layout tables** (`tools/data/world/*.json`, not exported): `world.json` holds the frame (grid,
origin, rim), the terrain features (`base`, `plateau`, `ridge`, `basin`, `river`, `road`, `flatten`,
`cliff_band`, `ramp`, `rim`, `shelf`), the water and the skyline landmark list; each region file holds
`elements` (`{"kind", "id" (world id when persistent), "position_m", "yaw_deg", "size_m",
"visible_when_flag", "hidden_when_flag", "faction", "indestructible", …}`), `shrines`, `waystones`,
`markers` (safe markers included), `patrols`, `triggers`, `exits`, `size_gates`, `secrets`, `caches`,
`cairns`, `scenery` (density, species, spacing) and `signs`. Element kinds are scripts
`tools/world/kinds/<kind>.gd` with `static func build(kit, el, ctx) -> Node3D` and `static func
solids(el) -> Array` (collision and navigation obstacles from the same list); a region package adds a
kind by adding its file. `visible_when_flag` / `hidden_when_flag` make an element appear or vanish by
a world flag (evaluated when its chunk loads and on `flag_changed` while loaded): the giant's banner on
an allied gate, a tribute pile, a broken south gate, a burned house, Aldmere's struck flags.
`indestructible: true` makes a prop immune to every hit (a GameData check requires it on every
quest-critical prop: Brannock Bridge, the beacons, the Kings' Door, quest talkers' halls).

### 2.8 Streaming and navigation runtime (P24a: terrain, streaming, skyline; P24b: navigation, director)

```gdscript
class_name ChunkStreamer extends Node             # child "Streamer" of WorldRoot; group chunk_streamer; PROCESS_MODE_ALWAYS
signal chunk_loaded(chunk_id: String)             # also Events.world_chunk_loaded
signal chunk_unloading(chunk_id: String)          # before any node of the chunk is freed
signal chunk_unloaded(chunk_id: String)
var deterministic := false                        # --fixed-fps or tests: steps_per_frame_headless steps, no clock, nav async off (P24b)
func configure(cfg: Dictionary, level_root: Node3D) -> void
func focus(pos: Vector3) -> void                  # WorldRoot calls it every frame with the player's position
func chunk_at(pos: Vector3) -> String
func is_loaded(chunk_id: String) -> bool          # terrain, body and props in the tree
func is_ready(chunk_id: String) -> bool           # also every nav region added and every layer map's iteration id past that add
func load_ring_slice(pos: Vector3) -> float       # one slice of the starting ring (the loading screen; returns progress 0..1)
func ring_ready(pos: Vector3) -> bool
func loaded_chunks() -> PackedStringArray
func stats() -> Dictionary                        # loads, unloads, work_ms p99 / max, steps, queue length, thrash count
```

Loader steps (one at a time until the budget is spent; a started step always finishes, and every
step is sized to stay under about 3 ms on desktop): load the `ChunkData` (`load_threaded_request` +
poll, the same code on both platforms), fill terrain rows (about 2,000 vertices a step), commit the
mesh, the `HeightMapShape3D` body, each scenery MultiMesh, solids in batches of 16, each props
sub-scene (a settlement is several sub-scenes of at most 150 nodes, one per step), then per layer:
load the navmesh resource in one frame and add its region in a later one (P24b), and assign the chunk's
`NavigationLink3D`s to their layer's map. Unload: emit `chunk_unloading`, free the props scenes and
the regions, then the rest. Chunks load within Chebyshev distance `load_ring` (1) of the player's
chunk, nearest first, and unload only at distance `unload_at` (3) or more, so at most 25 are loaded and
walking along a border never reloads a chunk. The starting ring loads behind the loading screen in
slices with progress (`main.gd` keeps the tree paused; the streamer and the loading screen run with
`PROCESS_MODE_ALWAYS`; the navigation server keeps syncing while the tree is paused).

```gdscript
class_name WorldRoot extends LevelRoot            # group world_root (and level_root)
var streamer: ChunkStreamer
func nav_map(layer: int = 0) -> RID               # the layer's own map (0 = the human map); titan gate regions join the titan map
func nav_layers() -> PackedInt32Array              # [1, 2, 16]
func region_at(pos: Vector3) -> String             # index region grid; "" outside
func surface_at(pos: Vector3) -> String            # "soft" | "hard" | "wet"
func height_at(pos: Vector3) -> float              # from loaded ChunkData (NaN when unloaded)
func water_at(pos: Vector3) -> float               # surface height or NaN
func is_ready() -> bool                            # the ring around the respawn point is ready
func loading_progress() -> float                   # 0..1 for main's loading screen
```

**The skyline** (`scripts/world/skyline.gd`, P24a): a `Skyline` node in `WorldRoot` draws the level's
skyline mesh (the whole world's terrain at 32 m spacing, each vertex the minimum of the fine heights
within 32 m minus 2 m, coloured by `skyline_tint`) and its landmark silhouettes (one merged mesh) with
`assets/shaders/skyline.gdshader`, which discards fragments over chunks whose own terrain is drawn
(WorldRoot keeps an 8 × 8 mask texture of chunks that are loaded and within
`terrain_visibility_end_m`, set as the global shader parameters `world_loaded_mask`,
`world_grid_origin` and `world_chunk_size`). Lit beacons add unshaded, fog-disabled light columns (a
MultiMesh shown by flag). Two to three draw calls and about 20,000 triangles; no shadows.

**Navigation (P24b).** `LevelRoot` gains `nav_map(layer := 0)` (the Valley: the default map for every
layer), `nav_layers()`, `nav_layer_for(layers: int) -> int` (the profile's layer when the level has it,
else the record's `player_nav_fallback`) and `nav_query_settings()` (the record's `nav_query`, or {}).
`scripts/world/nav_query.gd` (`class_name NavQuery`, static) is the one way to ask for a path:

```gdscript
static func path(level: Node, from: Vector3, to: Vector3, layers: int, purpose := "chase") -> PackedVector3Array
	# the layer's map (level.nav_map(lowest bit)); the goal snapped first with map_get_closest_point on that map;
	# NavigationServer3D.query_path with NavigationPathQueryParameters3D: navigation_layers = layers,
	# path_search_max_polygons and path_search_max_distance from nav_query_settings() by purpose
	# ("chase" 120 m, "far" 300 m); with no settings (the Valley) the parameters equal map_get_path's
	# defaults, so the Valley's paths do not change
static func closest_point(level: Node, pos: Vector3, layers: int) -> Vector3
static func budget_left(level: Node) -> int        # queries left this tick (nav_query.queries_per_tick); 0 = defer
```

Every call site converts: `EnemyActor` (agent map, repath, flee and reachability), `Civilian` (flee
snapping, which also stops using `nav_region()`), `ValleyBot`, `BotDiagnosis`, `valley_walk.gd`.
`EnemyActor` (anchor P24b) throttles tier-0 repaths (at least `repath_min_ticks` apart and only when
the goal moved `repath_min_move_m`), snaps a chase goal to its layer map (a giant wading the Wend is
chased to the bank), and formation members steer to slot offsets from their formation's one pivot
path (P30) instead of pathing each. **Determinism**: when `ChunkStreamer.deterministic` holds,
`NavMaps` calls `NavigationServer3D.map_set_use_async_iterations(map, false)` on every layer map and
`region_set_use_async_iterations(rid, false)` on every streamed region, and `is_ready(chunk)` waits
until each layer map's `map_get_iteration_id` has advanced past its value at the chunk's last region
add (one tick, re-measured); interactive desktop play keeps async iterations for smoother frames.

**The director in the world** (anchor P24b): `Encounter.chunk` = the chunk of its centre; an
encounter updates only while its chunk is loaded and ready; on `chunk_unloading(c)` every living
member standing in `c` is despawned (not killed) and encounters centred in `c` deactivate; spawns
never land in an unloaded chunk; spawn entries take `min_stage` / `max_stage` (filtered at
activation); a world encounter without `leash_radius_m` is a data error unless it has `arena: true`;
director path queries share `NavQuery.budget_left` (the rest wait a tick).

### 2.9 Growth stages 4–6 and size gates (P26)

| Field | Stage 4 | Stage 5 | Stage 6 |
| --- | --- | --- | --- |
| `height_m` (k) / `required_level` | 10.9728 (3.0) / 7 | 14.6304 (4.0) / 9 | 18.8976 (5.1667) / 11 |
| Capsule radius / height | 2.2 / 10.97 | 2.9 / 14.63 | 3.7 / 18.90 |
| Walk speed, acceleration, turn | 7.1 m/s, 21, 300°/s | 7.6, 18, 250 | 8.1, 16, 210 |
| `melee_reach_m` | 8.6 | 11.0 | 13.6 |
| Weapon pivot / attack origin / arm / `weapon_scale` | (2.46, 8.7, 0) / 7.8 / 4.5 / 3.0 | (3.28, 11.6, 0) / 10.4 / 6.0 / 4.0 | (4.24, 14.98, 0) / 13.43 / 7.75 / 5.1667 |
| `arc_pitch_offset_deg` | −16 | −20 | −24 |
| Camera distance (zoom) / pivot / shoulder / orbit scale | 15.5 (12–20.5) / 10.04 / 2.2 / 3.0 | 19.5 (15–26) / 13.39 / 2.9 / 4.0 | 23.5 (18–32) / 17.29 / 3.7 / 5.17 |
| Lock range / half-angle | 55 m / 45° | 65 / 42 | 80 / 40 |
| `resource_bonus` | health +450, stamina +30 | +600, +40 | +800, +50 |
| Grab reach / lunge / capacity / attach | 9.1 / 4.5 / medium / + two_hand | 11.5 / 6.0 / large | 14.1 / 7.5 / large |
| `nav_layers` / `size_gate_mask` / titan query mask | 16 / 384 / 48 | 16 / 256 / 112 | 16 / 0 / 240 |
| `footstep_shake` | 0.18 | 0.24 | 0.30 |
| `interaction_permissions` adds | `gate_breach`, `trample` | `formation_sweep`, `heave` | `siege_disruption` |
| `target_rules` (P30's field) | `{"formation_lock": true}` | same | same |
| `unlocks` (P31 fills) | `ability.titan_stomp`, `ability.crag_hurl` | `ability.formation_sweep`, `ability.titan_roar` | `ability.earthquake`, `ability.rampart_grip` (P32) |

Stages 1–3 gain `size_gate_mask` 448 and titan query mask 16. Shrines gain
`growth_requires_conditions` (an array of quest condition shapes, all must hold; the locked message
names the missing one), so world shrines can ask for `world.kingsgate.lit` or a count of oaths.
Weapons gain `stage_movesets` (P26 adds the field and `PlayerEquipment` reads it: `{"4": {"light_chain":
id, "heavy": id}}`, the highest key at or below the current stage wins, used only while the weapon
fits the stage; P31 fills the records).

```gdscript
class_name SizeGate extends StaticBody3D          # group size_gates; layer 64/128/256 by min_stage
@export var gate_id := ""; @export var min_stage := 4
@export var message := "Too deep to wade. Grow to stage 4."
@export var cue := "sfx.gate.water"               # sfx.gate.water | .stone | .timber, played at the contact point
# A child Area3D (1 m larger) emits Events.size_gate_blocked when the player touches it (at most once per 4 s)
```

Props gain `trample_stage` (0 = never; P26): a giant of that stage or more walking into the prop
(`PlayerMotor` reads its slide collisions) deals it a `trample` hit that destroys it and emits
`trampled`; trampling is never an offence unless the prop is tagged `house` and owned by a faction
that is not hostile (§2.12). Props gain `requires_permission: "heave"` for rockfalls, fallen
titan-trees and toppled statues (stage 5, the existing permission rule), and interactables gain
`requires_stage` (a ledge only a stage-6 giant reaches: "Out of reach. Grow to stage 6."). Abilities
gain `radius_by_stage_m` entries for stages 4–6 and `range_by_stage_m` (P26 adds the field;
`PlayerAttack` reads it for Boulder Hurl's range check): Footfall `[3, 4, 5, 6.5, 8, 9.5]`, Thunder
Roar `[6, 6, 6, 9, 11, 13]`, Boulder Hurl range `[25, 25, 25, 32, 38, 44]`.

### 2.10 Combat and enemies (P30, P32, P34)

**Target provider** (P30, `EnemyActor` anchor P30). An enemy record may add
`"targets": {"teams": ["player"], "factions": ["faction.millford"], "prop_tags": ["house"], "priority": "nearest"}`
(default: the player only, exactly today's behaviour). `_target()` returns the provider's choice:
the player when it is aware of the player and within `aggro_player_m` (default: always), else the
nearest living allowed NPC (by faction) or intact prop (by `prop_tags`, a new optional prop field) in
sight. Props as targets take hits through their `CombatEntity` like any other. Tokens stay per target
id.

**Size override** (P32, `HitFactory` anchor P32): an action may set `attacker_height_override_m`
(siege engines 8.0, a formation brace 5.0); `HitEvent.attacker_height_m` takes it, so poise and
knockback size ratios treat the hit as coming from that height. Damage's `M_size` is unchanged (it
uses `size_policy`; siege actions use `"none"`).

**Formations** (P30; data in the encounter record, `Formation` objects owned by the director):

```json
{"id": "encounter.crownmarch_toll_fort", "type": "encounter", "...": "...",
 "web_formation_scale": 0.7,
 "formations": [{"id": "pikes", "kind": "pike", "banner": "world.crownmarch.toll_banner", "min_stage": 4,
   "ranks": 2, "files": 4, "rank_spacing_m": 2.2, "file_spacing_m": 1.6, "facing": "threat",
   "turn_deg_s": 40, "advance_mps": 1.4, "brace_m": 6.0, "brace_action": "ability.formation_brace_pike",
   "morale_start": 90, "flee_points": ["world.marker.toll_flee_n", "world.marker.toll_flee_e", "world.marker.toll_flee_w"]}],
 "spawns": [{"entity_id": "world.crownmarch.toll_pike_1", "definition": "enemy.pikeman", "formation": "pikes", "slot": 0, "...": "..."},
            {"entity_id": "world.crownmarch.toll_banner", "definition": "enemy.bannerman", "formation": "pikes", "slot": -1}]}
```

```gdscript
class_name Formation extends RefCounted
var id := ""; var kind := "line"            # line | pike | shield | crew
var members: Array[EnemyActor] = []; var banner: EnemyActor = null
var pivot := Vector3(); var facing_yaw := 0.0
var state := "formed"                       # formed | advancing | braced | broken | routed
func slot_position(slot: int) -> Vector3    # ranks × files around the pivot, facing facing_yaw
func anchor() -> Vector3                    # front centre at chest height (the lock point)
func focus_member(from: Vector3, prefer_banner := false) -> EnemyActor   # living, non-fleeing member nearest `from`
func cohesion() -> float                    # living, non-fleeing share
func living_count() -> int
func front_band() -> Dictionary             # {"center", "half_width", "depth", "yaw"}: the brace band
func update(tick: int, threat: Node3D) -> void   # pivot path, facing, state, slots (director, 10 Hz)
func try_join(actor: EnemyActor) -> bool    # an outmatched soldier of the faction takes a free slot
```

A soldier record gains `"role": "line" | "pike" | "shield" | "banner" | "crew"` (enum
`SOLDIER_ROLES`). While the banner lives, a formation member's awe and ally-death morale losses are
halved and it regroups to its slot; the banner's death is `commander_died` for every member and emits
`formation_changed(..., "banner_fell")`. **The brace is the formation's, not each pike's**: when the
formation is braced and the giant is within `brace_m` of its front rank, the formation (through its
focus member's `AttackRunner`) runs one `brace_action`: a `band_pulse` (a new hit shape: a rectangle
along `front_band()`, P30) with one telegraph and one damage instance per target per pulse, holding one
of the target's two melee tokens; pikes only pose (the crowd renderer's `brace` pose). **Group lock**:
when the player's profile has `target_rules.formation_lock`, `PlayerTargeting.gather_candidates`
folds a formation's rank-and-file into one candidate `formation:<id>` (anchor, the highest member
threat, visible if any member is, distance to the anchor) and keeps the bannerman as its own
candidate (flagged `banner: true`; the lock line shows a flag icon); `locked_entity()` resolves the
group to `focus_member(attack origin)`; the lock releases (`target_died`) when no member is alive and
not routed; switching moves between formations, banners and single targets; `lock_label()` returns
"Pike Regiment (8)" or "⚑ Banner of the Toll-Riders" for the HUD (P27 shows it). **The banner is
visible**: a 7 m pole with a 2.5 × 1.8 m flag in faction colour on render layer 1, swaying, never
culled by the crowd renderer; its fall plays `sfx.formation.banner_fall`. **Routs fan out**: routed
members pick among the formation's `flee_points` (or, without them, among points 30–60 m away spread
over a 140° fan) so a breached gate does not jam. **Outmatched soldiers join formations**: a soldier
whose outmatched behaviour is `formation` joins the nearest living formation of its faction within
40 m that has a free slot (counted against `max_formation_members`), else flees. **Crowd renderer**
(`scripts/presentation/crowd_renderer.gd`, group `crowd_renderers`, one per formation): one MultiMesh
per pose (`hold`, `brace`, `advance`, `flee`) of the archetype's merged rig, instance transforms from
the members each frame; a member within 20 m (× distance scale) of the giant, in an attack phase or
staggered is promoted to its own rig (at most 6 per formation). **Web compositions**: on the web the
director scales each formation's files by the encounter's `web_formation_scale` (front rank and banner
first), so every battle's composition fits 20 members.

**Siege engines** (P32): `class_name SiegeEngine extends BreakableProp` (group `siege_engines`) with
an `engine` block in its prop record:

```json
{"id": "prop.siege_ballista", "type": "prop", "category": "structural", "health": 900, "armor": 30,
 "accepted_attack_categories": ["melee", "ability", "projectile", "siege"], "height_m": 3.2,
 "engine": {"action": "ability.ballista_bolt", "crew_radius_m": 4.0, "min_crew": 1, "reload_s": 6.0,
            "range_m": [20, 140], "turn_deg_s": 30, "morale_event_radius_m": 30, "grab_stage": 6},
 "mass_class": "large", "grab_attach": "two_hand", "prop_tags": ["engine"], "...": "..."}
```

It fires only while crewed, takes ranged tokens and launch slots (≥ 1.0 s between launches at one
target), telegraphs every shot (an aim line for the ballista; for the catapult a circle at the landing
point with a rising "incoming" cue there for the flight time), and on destruction calls
`on_morale_event("siege_destroyed")` on every enemy within `morale_event_radius_m` (debounced 2 s per
unit). At stage 6 (`siege_disruption`) `PlayerGrab` can seize a staggered-or-uncrewed engine with two
hands and throw it (a `thrown_body` projectile with the engine's visual).

**Cavalry** (P32): archetype `cavalry` (rider and horse, 2.6 m, radius 0.9, nav layer 2): a committed
charge (`motion` + `body_sweep`, line telegraph, size override 4.0, a gallop swell at its start), then
wheel away 30–50 m and re-charge; outmatched behaviour `harass`. **Trolls** (P34): archetype `troll`
(5.5 m, radius 1.4, `OgreBrain` tactics, super armour strikes, a regeneration status the brain
refreshes every second unless the troll is `Burning`, shown by a pulsing green tint and a wet regrowth
loop), grabbable from stage 5 (5.5 m ≤ half of 14.63 m). **Dire wolves** (P34): wolf archetype, 1.8 m,
health 260. **Rival giants** (P34): archetype `rival_giant` (9–15 m, titan nav mask 240, weapon arcs
through `AttackRunner`, the boss framework's sequences and phases, a shoulder charge, a boulder throw;
can yield). No rival giant, troll matriarch or boss can be grabbed (the 50 % height rule and spec §8;
boss grapples are stage 7).

**BattleBoss** (P34): a node in an arena that owns phases over several encounters and engines, shows
one boss bar with the aggregate health **of what actually spawned** (desktop or web composition), and
changes phase once per attempt at fractions of that aggregate. **Arena disengage** (every boss, P34):
when the player stays beyond the arena radius + 20 m for 5 s, the boss returns home, resets to full
health and its first phase (a new attempt), and emits `boss_disengaged(..., "left")`; the music
returns to the zone set. **The yield protocol** (Corvane, Harrok): on yielding, the boss becomes
`IMMUNE` and non-hostile at once, every pending hit and projectile created before the yield tick is
discarded against it, the player's lock releases, and a two-choice prompt opens ("Spare" / "Strike",
a dialogue with a confirm on Strike). Only that choice decides the outcome; no blow, area effect or
burning landing after the yield can. `boss_yielded` carries the boss id (`battle.iron_regiment` for
the BattleBoss, whose `boss_engaged` carries the same id).

### 2.11 Progression (P26, P31, P32, P33)

Actions gain (P31): `evolves_from` (an action id), `granted_by` (`talent` | `ancestry` | "" for
documentation) and `radius_scale` (a multiplier on `radius_from: "melee_reach"`); `unlock_level` and
`unlock_stage` exist today (gating) and now also decide when an evolution is learned. Learning an
evolution (on reaching its `unlock_stage` at or above its `unlock_level`) replaces the base in its
slot and in `known_abilities` order, keeps the base listed for display, emits `ability_evolved`, and
never shares a cooldown (per-id). A player `motion` (a scripted dash with a `body_sweep`, P31 in
`PlayerMotor`) serves Shoulder Charge.

**Weapons** (P26 adds the fields, P31 and P32 fill them): the reinforced club, sword and hammer fit
stage 6 (`fit_max_stage` 6; their base forms keep 2) and name their family's `stage_movesets`; refits
form chains whose steps name a forge tier:
`{"upgrade": {"to": "weapon.club_titan", "cost": [{"item": "item.titan_iron", "count": 2}, {"item": "item.iron_ingot", "count": 2}], "forge_tier": "titan"}}`
(the existing one-step rule is lifted; each step fits at least as high as its source). Forges gain
`tier` (`iron` | `titan`; default `iron`): an iron forge does base → reinforced, a titan forge also
reinforced → titanforged. Titanforged weapons add damage and one `perk` (§5.12).

```json
{"schema_version": 1, "id": "ability.titan_stomp", "type": "action", "kind": "ability",
 "display_name": "Titan Stomp", "hotbar_label": "STOMP", "evolves_from": "ability.heavy_footfall",
 "unlock_level": 7, "unlock_stage": 4, "granted_by": "",
 "power": 40, "damage_type": "physical", "ability_multiplier": 1.5, "stamina_cost": 24, "cooldown_s": 8,
 "windup_s": 0.35, "active_s": 0.10, "recovery_s": 0.55, "poise_damage": 40, "max_hits_per_target": 1,
 "interrupt_policy": "hard_stagger", "tags": ["Ability", "AoE", "Unparryable"], "category": "ability",
 "uses_weapon": false, "crit_eligible": false, "hit_shape": "cylinder_pulse",
 "radius_m": 7.7, "radius_from": "melee_reach", "radius_scale": 0.9, "height_m": 6.0,
 "movement": {"windup_speed_mult": 0.0, "active_speed_mult": 0.0, "recovery_speed_mult": 0.2},
 "knockback_impulse": 9.0, "knockback_max_speed": 12.0}
```

(Every key but `evolves_from`, `granted_by` and `radius_scale` exists in today's records, e.g.
`data/abilities/heavy_footfall.json`.)

```json
{"schema_version": 1, "id": "talent.destroyer_shoulder_charge", "type": "talent", "display_name": "Shoulder Charge",
 "tree": "destroyer", "tier": 2, "cost": 1, "requires": ["talent.destroyer_heavy_hands"], "requires_level": 8,
 "effects": {"modifiers": {}, "grants": ["ability.shoulder_charge"], "replaces": {}}}
```

```json
{"schema_version": 1, "id": "ancestry.stoneblood", "type": "ancestry", "display_name": "Stoneblood",
 "description": "Your line was quarried from the mountain. Hard to stagger, slow to anger.",
 "attribute_bonus": {"constitution": 3, "endurance": 2}, "resistances": {"physical": 0.0},
 "modifiers": {"armor_flat": 10, "poise_threshold_add": 20}, "signature": "ability.bedrock_ward",
 "dialogue_tags": ["stone"]}
```

`Combatant.passives: Dictionary` (P33) is rebuilt from the ancestry and the talents whenever either
changes and is folded into the accessors that already centralise modifiers (`armor_total`, outgoing
damage and poise, damage taken, slow, fury gain) plus the keys P20 pre-declares in
`STATUS_MODIFIERS`; `PlayerMotor` reads `move_speed_mult` (P33). Talent points: one per level from
level 2 (the Valley's unspent points carry over).

### 2.12 Quests, dialogue and factions

Condition types added (P20 declares the enum and implements the pure ones; the others are
implemented below their packages' anchors in `quest_conditions.gd`):
`{"type": "count", "n": 2, "of": [conditions…]}` (P20), `{"type": "quest_done", "quest": id}` (P20),
`{"type": "level_is", "level": id}` (P20), `{"type": "discovered", "poi": id}` (P27),
`{"type": "region_entered", "region": id}` (P27), `{"type": "ancestry_is", "ancestry": id}` and
`{"type": "ancestry_chosen"}` (P20: they only read the character's `ancestry` and `ancestry_chosen`,
so P33 needs no quest edit), `{"type": "event_done", "event": id, "outcome": ""}` (P37),
`{"type": "near", "target": id, "radius_m": 150}` (P29: the player within a radius of an index
position). Dialogue choices take the same conditions (the existing shared evaluator) and gain
`locked_text` (shown greyed with the reason when the conditions fail: "Return when you stand at stage
5"); a quest stage gains `waiting_text` for the journal ("Waiting: stage 5").

Bot actions added (P20 declares; P38 implements): `travel` (a world position or id, across chunks),
`fast_travel`, `discover`, `breach`, `protect`, `duel`, `choose_ancestry`, `heave`, `burn`.

Quests gain (P27): `Quests.tracked_quest_id` (saved as `progress.tracked_quest`), `track(quest_id)`,
`track_next()`; the objective marker and the compass follow the tracked quest (default: the main
quest); a stage with `markers` shows each (the compass draws them all, the marker the nearest);
`objectives()` gains `tracked`. Quests run in both campaign levels (P20): quests whose stages name
another level's targets simply wait, and the index answers their positions.

**Faction records** (P22 generalises `FactionState` and ships `faction.village`; P29, P35, P36 ship
the world's):

```json
{"schema_version": 1, "id": "faction.brannock", "type": "faction", "display_name": "Brannock",
 "flag_prefix": "faction.brannock", "initial": "neutral", "offences_to_hostile": 2, "offence_window_s": 30,
 "civilians_give_way": true, "give_way_m": 3.0,
 "reconcile": {"talker": "world.crownmarch.edda", "cost": [{"item": "item.iron_ingot", "count": 2}],
               "text": "Pay for the gate you broke (2 iron)"},
 "warn_text": "Brannock's folk scatter from your feet. Strike again and the town will fight you.",
 "hostile_text": "Brannock's bells ring: the town takes up arms.",
 "stood_down_text": "Brannock's guards lower their pikes.",
 "reconciled_text": "Brannock forgives the gate, if not the fright."}
```

`initial`: `neutral` (members spawn in HOLD, as Thornwick's do) or `hostile` (the toll-riders).
Offences are direct blows on a member (today's rule), and now also any damage the player deals (blows,
abilities, trampling) to a prop the layout marks with the faction and tags `house` or `engine`.
`civilians_give_way`: the faction's civilians step `give_way_m` plus the giant's height out of its
path and turn to watch instead of fleeing, unless the faction is warned or hostile (`faction.village`
keeps fleeing: the Valley is unchanged). `reconcile` adds a dialogue choice at the talker that sets
`faction.<f>.reconciled` (guards stand down, the forge reopens; oath outcomes stay). `faction.village`
(Thornwick) moves to a record with today's texts.

**Settlements meet big giants on their green**: a talker whose settlement POI has `max_inner_stage`
stands on the settlement's `green_m` (a flat pad with a meeting stone outside the walls) whenever the
player's stage is above it (decided when its chunk loads and on growth; it walks there when loaded).
Encounters gain `stand_down_when` (a quest condition; P29 implements at its director anchor): while it
holds, the encounter's members stand down (Aldmere's fort gate when the giant carries Brannock's
banner within 150 m).

### 2.13 The living world (P37 framework; P35 and P36 own their regions' tables and events)

```json
{"schema_version": 1, "id": "wander.aldmere", "type": "wander_table", "region": "region.aldmere",
 "max_active": 2, "interval_s": [60, 120], "min_distance_m": 120, "max_distance_m": 220,
 "anchors": "roads", "xp_full_spawns": 3,
 "entries": [{"id": "patrol_line", "weight": 3, "min_stage": 3, "max_stage": 3, "template": "encounter.tpl_aldmere_patrol"},
             {"id": "pike_column", "weight": 3, "min_stage": 4, "max_stage": 6, "template": "encounter.tpl_pike_column",
              "path": "world.patrol.kings_road", "requires_flags": [], "forbids_flags": ["oath.crown.outcome"]}]}
```

Templates are encounter records with `"template": true` (never activated by themselves; the director
instantiates a copy with ids `<template id>.<n>` and the chosen anchor as centre). A spawn's members
carry `xp_scale` = 1 for the first `xp_full_spawns` spawns of an entry, then 0 (the counter is the flag
`wander.<table short>.<entry>.spawns`). Members of a faction spawn with that faction's standing
(neutral columns walk past a giant at peace with them). World events are records with a trigger
(region, stage, flags, cooldown, or a quest flag such as accepting Ulfra's plea), a `centre_m`,
encounters to start, an objective (protect props or NPCs, destroy engines), a fail rule and outcomes
that set flags. **Streaming rules** (P37): an event starts only when its centre chunk is loaded and
ready and the player is within 200 m of the centre; while its centre chunk is unloaded its fail rule
and timers are suspended; the player's death resets its encounters (the attempt restarts, outcomes
are not lost); a moving column (`path`) advances as a path parameter in data and spawns its formation
only while its point lies in a loaded, ready chunk, despawning back into the abstract when it leaves;
at most one event at a time.

### 2.14 UI contracts

HUD widgets added to `HudWidgets.WIDGETS` (P20 pre-declares the paths): `compass.gd` (P27, top
centre, (−300..300, 4..28)), `region_banner.gd` (P27, centre, (−320..320, 150..196), 3 s),
`discovery_toast.gd` (P27, top-left under the checkpoint toast, (12..352, 92..126)). P27 moves the
target frame and the boss bar down 30 px and the ability notice to (132+30); `test_hud_layout` keeps
every region apart at five resolutions. The lock line shows `PlayerTargeting.lock_label()` (P27 reads
it; P30 provides it).

**Compass** (P27): an unscaled 600 m radius; at most 6 nearest discovered POIs, the tracked objective
(diamonds, several for a multi-marker stage), up to 3 oath leads, the player's pin, and undiscovered
POIs as "?" within 250 m or, for `skyline` POIs, within 1,000 m. **Map** (P27): every `vista` reveals
the POIs within its `reveals_m`; a pin can be placed or cleared (saved as `map.pin`); sealed places
show a lock and "Grow to stage N" once seen; region labels and the region banner show "Recommended
stage 5–6" in the warning colour when the player is below a region's `recommended_stage`; travel to a
checkpoint whose `max_stage` is below the stage is refused with its reason. **Journal** (P27): active,
waiting and completed quests, oath outcomes, "Sealed places" (seen, not yet opened, with their stage),
and per region its M7 note while one exists.

Screens added to `ScreenStack.SCREENS`: `map` (`ui/screens/map_screen.gd`, P27), `journal`
(`ui/screens/journal_screen.gd`, P27), `ancestry` (`ui/screens/ancestry_screen.gd`, P33), `yield`
(`ui/screens/yield_prompt.gd`, P34). `HOTKEYS`: `map` → `map`, `journal` → `journal`.
`ShrineScreen.TABS` gains `["Talents", "res://ui/screens/shrine/talents_tab.gd"]` and `["Ancestry",
"res://ui/screens/shrine/ancestry_tab.gd"]` (P33). The settings pages gain an Audio section (P19).

| Action | Keyboard | Pad | Owner |
| --- | --- | --- | --- |
| `map` | M | D-pad Down (without LT) | P27 |
| `journal` | J | D-pad Right (without LT) | P27 |
| `track_next` | T | D-pad Left (without LT) | P27 |
| `map_pin` (on the map screen) | P | Y | P27 |

### 2.15 Registries, scenes and builders (P20 pre-declares)

`DataValidator.SCHEMA_PATHS` gains (P19) `audio_bank`, `audio_mix`, `music_set`, `ambience_set`,
`audio_region`; (P20) `region`, `poi`, `faction`, `talent`, `wander_table`, `world_event`. Enums
(P20): `ARCHETYPES` + `troll`, `rival_giant`, `cavalry`; new `SOLDIER_ROLES` (`line`, `pike`, `shield`,
`banner`, `crew`); `WEAPON_VISUAL_SHAPES` is the weapon schema's (P31 and P32 extend it at their
anchors); `PROJECTILE_VISUALS` + `ballista_bolt`, `catapult_stone`, `rune_lance`, `storm_bolt`,
`engine`; `HIT_SHAPES` + `line_pulse`, `band_pulse`; `SIZE_POLICIES` + `fixed`;
`INTERACTION_PERMISSIONS` + `heave`, `trample`; `OUTMATCHED_BEHAVIORS` + `crew`, `charge`;
`STATUS_MODIFIERS` + `heal_received_mult`, `stamina_cost_mult`, `essence_cost_mult`, `cooldown_mult`,
`poise_threshold_add`, `poise_damage_taken_mult`, `grab_reach_add`, `fury_on_kill_add`,
`move_speed_mult`, `elemental_resist_add`, `health_add`, `stamina_add`, `essence_add`,
`heavy_damage_mult`, `throw_damage_mult`, `magic_damage_mult` (the talents and ancestries of §5.12 use
only these and the existing keys); `STATUS_TAGS` + `Burning`, `Regeneration` (stuns are fixed-length
staggers, an existing mechanism, so there is no stun tag); `CONDITION_TYPES` (§2.12); `BOT_ACTIONS`
(§2.12); `TUTORIAL_EVENTS` + `poi_discovered`, `region_changed`, `formation_changed`,
`size_gate_blocked`, `level_entered`, `ability_evolved`; `POI_KINDS` (§2.7); `FACTION_INITIAL`
(`neutral`, `hostile`); `FORGE_TIERS` (`iron`, `titan`).

`build_scenes.gd BUILDERS` gains, in order: `world_props2.gd` (P26: Kings' Door, Citadel hall props,
size gate visuals, rockfall, titan-tree, toppled statue, trample palisade, great pine) after
`world_props.gd`; `formations.gd` (P30), `siege.gd` (P32), `big.gd` (P34) after `npcs.gd`;
`test_world.gd` (P24a) after `stress.gd`; `world.gd` (P25) before `main.gd`. Required node names:
`scenes/world/world.tscn` = `WorldRoot` with `Environment`, `Sun`, `Streamer`, `Skyline`, `Chunks`,
`Navigation`, `Spawned`, `Player`, `EncounterDirector`, `DebrisPool` (`Discovery` and `WanderDirector`
are runtime nodes, §2.6); a chunk scene's root is `Chunk_<x>_<z>` (or `Chunk_<x>_<z>_<part>`) with
`Props`, `Shrines`, `Waystones`, `Markers/<kind>/<id>`, `Triggers`, `Exits`, `SizeGates`, `Landmarks`,
`NavLinks`.

`LevelRoot.RUNTIME_NODES` (P20, §2.6). `ResetHooks`: (P19) `BEFORE_EACH` first: `["autoload",
"Audio", "reset_for_tests"]`; (P20) `AFTER_EACH` last: `["script", "res://scripts/world/world_index.gd",
"clear_cache"]`.

### 2.16 Test conventions

As in M2–M5 §2.13, plus: the default suite runs with `--no-audio`; audio tests call
`Audio.enable_for_tests()`, read `Audio.cue_log()` (deterministic) instead of listening, and use
offline rendering (`instantiate_playback()` + `mix_audio()`) for asset checks, with at most one
real-time capture test (an `AudioEffectCapture` on Master); world tests run on P24a's generated test
world (`scenes/test/test_world.tscn`, 4 × 4 chunks; P24b adds its navmeshes) unless they need the real
world (then they are slow or gate suites); every streamed test sets `ChunkStreamer.deterministic`
(navigation async off) and waits for `is_ready`; tests that need a post-Valley character use
`GameSession.start_world_for_tests()` or the `world_start` block; fixtures for saves live in
`tests/fixtures/saves/`; test-only level and encounter records live in `data/test/`.

---

## 3. Package specifications

Each package lists its wave and lane, dependencies, milestone, goal, owned paths (exclusive within its
wave), allowed hotspot edits (at its own anchors, or as the single owner of §1.5), design, tests,
its test-time budget (default suite cap / slow / gate), acceptance and size. "Cross-lane symbols" are
the few things a package must reach defensively because its wave partner adds them (§1.2). Every
package also writes `docs/systems/<id>.md` and passes §1.1.

### 3.1 P19 — Audio engine: the `Audio` autoload, cue banks, voices, buses, settings, music and ambience directors, the loading gate, the generation pipeline

- **Wave / lane:** W12, A, parallel with P20. **Depends on:** M0–M5. **Milestone:** M6.
- **Goal:** everything the sound packages need so that they only add data and generated files: the
  director, the playback policies of decision 2, the loading gate that registers samples before the
  first tick, the event router with every row of §4.1 (placeholder cues), the music state machine
  with the melody scheduler and threat-weighted intensity, the ambience director with stream spots and
  reactions, audio settings, focus mute, the test tiers, the asset and policy tests, and the Python
  pipeline with its manifest, bit-exact verification and provenance record.

**Owned paths**
- `scripts/audio/{audio_director,voice_pool,cue_router,music_director,melody_scheduler,ambience_director,audio_math}.gd`
- `scripts/core/schemas/{audio_bank,audio_mix,music_set,ambience_set,audio_region}_schema.gd`
- `data/audio/{bank_placeholder,mix_default}.json`, `assets/audio/placeholder/*` (four test tones,
  one 3-variant test set, one test bed: about 80 KB, replaced by P21/P23 and deleted by P23)
- `assets/audio/{manifest.json,PROVENANCE.md}`
- `tools/audio/{build_audio.py,encode.py,manifest.py,test_synth.py}`, `tools/audio/synth/core.py`
  (oscillators, noise, envelopes, biquad and state-variable filters, FFT convolution, seamless-loop
  wrap, normalisation, 16-bit WAV writer, FLAC export through ffmpeg, seeded RNG per cue, float64 and
  single-threaded throughout)
- `tests/gate/` (the folder and its runner entry)
- Tests: `tests/unit/{test_audio_math,test_cue_router,test_music_state,test_melody_scheduler,test_audio_schemas}.gd`,
  `tests/integration/{test_audio_director,test_audio_assets,test_audio_policies}.gd`,
  `tests/gate/test_audio_determinism.gd`

**Hotspot edits:** `project.godot` (autoload `Audio` last; `audio/driver/output_latency.web=200`);
`scripts/main.gd` (W12: the loading gate — the tree stays paused behind "Loading..." until
`Audio.is_ready()`, with `PROCESS_MODE_ALWAYS` on the screen); `scripts/core/settings.gd` (DEFAULTS,
RANGES; §2.5) and `ui/screens/settings_pages.gd` (an Audio section: five sliders and the focus toggle,
pad-navigable); `scripts/core/data_validator.gd` (`SCHEMA_PATHS` after `"progression"`, §1.6);
`tests/support/reset_hooks.gd` (first `BEFORE_EACH` entry); `tests/test_runner.gd` (`--no-audio` by
default, `--gate` picks `tests/gate/`); `tools/check.sh` (`--audio`: `python3
tools/audio/build_audio.py --verify` then the asset suites, skipped with a note when `python3`, numpy
or ffmpeg is missing; `--gate`; the default suite with `--no-audio`; the recorded suite times).

**Design**
1. **Autoload and lifecycle** (§2.5): buses made at `_ready`; `--no-audio` disables everything;
   levels detected through the `level_root` / `sandbox` groups; samples of the level's cues registered
   in slices of at most 12 ms behind the paused loading screen (global cues first, then cues whose
   `levels` include the level), `is_ready()` gating `main.gd`; focus mute with the two notifications
   and, on the web, a `visibilitychange` callback.
2. **VoicePool**: `voices_3d` `AudioStreamPlayer3D` (16 on the web: `OS.has_feature("web")`), two
   `spot_voices` (3D, `PLAYBACK_TYPE_STREAM`, Ambience bus) and `voices_2d` `AudioStreamPlayer`;
   attenuation `ATTENUATION_LOGARITHMIC`, `attenuation_filter_db = 0` (no filter), `doppler_tracking`
   off, `emission_angle` off; per play: `unit_size` and `max_distance` from the cue's class ×
   `distance_scale()` (classes with `scaled` true; `"sqrt"` uses its square root), `max_db` 3,
   `volume_db` = cue + opts, pitch = cue pitch × jitter × size pitch. Stealing: an
   equal-or-higher-priority request takes the lowest-priority, oldest voice; a lower one is dropped.
   Per-cue `max_voices` and `retrigger_ms`; at most `starts_per_frame` starts a frame (8 on the web,
   since every web sample play copies its buffer); a request whose computed level at the listener is
   under `min_level_db` never starts.
3. **CueRouter**: one handler per `Events` signal and per footfall source, each building a request
   (cue chain, position, source height, priority, reason, expected damage, poise ratio) into a queue
   drained in `_process`; the routing rules are §4.1's table, coded once with the fallback chains of
   §2.5. Enemy awareness barks come from polling the brains of `enemies` within 70 m (scaled) every
   0.25 s (the unaware → aware edge), so no actor code changes. Threat cues: on `telegraph_started`
   aimed at the player, the windup cue at the attacker, plus `sfx.threat.sting` when the attacker is
   outside the camera's frustum (horizontal angle > fov × 0.55) or farther than 20 m × scale, unless
   the sting is suppressed (§2.5). The footfall cruise rule and `wade` surfaces (§2.5).
4. **MusicDirector and MelodyScheduler**: §2.5 and §4.3 (stems on separate `AudioStreamPlayer`s with
   `PLAYBACK_TYPE_STREAM`, `loop` set on the stream resource from the set at load, started in one
   frame; bar and segment math from the lead stem's `get_playback_position()`; the melody variants
   switched by volume at segment boundaries; rests and silence windows; threat-weighted intensity;
   contexts title, end, campaign end and sandbox; boss sets on `boss_engaged` (0.5 s cross-fade after
   the set's intro stinger), phase layers on `boss_phase_changed` at the next bar, victory stinger and
   back to the zone set on `boss_defeated`, the yield stinger on `boss_yielded` and
   `boss_disengaged(fled)`, straight back on `boss_disengaged(left)`; the combat-intro stinger once per
   combat; stingers duck; death fades out).
5. **AmbienceDirector**: §2.5 (beds as looping streams on the Ambience bus, spots through the spot
   voices, flush reactions, emitters nearest two within radius, POI zones with priority).
6. **Pipeline** (`tools/audio/`): `build_audio.py [--only=<family>] [--verify] [--budget]
   [--masters-out=<dir>] [--out=<dir>]` imports every `gen_*.py` module present (each exposes `CUES`
   with `name, path, seed, func, params`), renders masters, normalises, writes SFX WAVs into
   `assets/audio/sfx/…` and encodes loops, spots and stingers with `encode.py` (`ffmpeg -fflags
   +bitexact -flags:a +bitexact -c:a libvorbis -q:a <q> -ar <rate> -ac <channels>`; refuses the native
   `vorbis` encoder), then rewrites `manifest.json` (file, family, generator module, function, seed,
   params hash, frames, rate, channels, loop, bpm, beats, frame, master hash, file hash, size, and the
   Python, numpy, ffmpeg and libvorbis versions). `--budget` prints the per-file arithmetic of §4.5
   (seconds × measured rate + 3.7 KB per Ogg; the exact QOA formula) and the registered seconds per
   level, and fails over decision 8. `--verify` regenerates every master and every Ogg into a
   temporary folder and compares all hashes (it reports a toolchain mismatch separately from a content
   change). `PROVENANCE.md` states that every sound is original and synthesized by the committed
   generators with no recordings or third-party samples, lists the generator, seed range and tool
   versions per family, explains how to regenerate and how to export FLAC masters, and leaves the
   licence as "the project's licence; the owner chooses it".
7. **Data**: `mix_default.json` with every class of §4.4, the materials, voices and surfaces maps for
   every existing prop, enemy, NPC and district (placeholder cue names where P21 will fill in), the
   intensity weights and the sting suppression.

**Tests to add**
- Unit: distance scaling and class curves (the measured −20 ln(d/unit) curve at three distances);
  voice stealing by priority and age; retrigger guard; variant picking never repeats; cue fallback
  chains; music intensity state machine with hysteresis and threat weighting (a stage-6 giant among
  10 fleeing soldiers stays `explore`; a 2 m wolf raises at most `danger` within 40 m; a formation
  raises `combat`); the melody scheduler (no variant more than twice in a row, identical phrases at
  least 60 s apart, a rest within three loops, the silence window after 180 s and its re-entry on a
  discovery); bar and segment boundary math; ducking; sting suppression; schema validation (unknown
  keys, bad buses, Ogg on the SFX bus, unequal stem lengths, a shared stem across frames).
- Integration (audio enabled): a hit on a dummy logs `sfx.hit.*` at the hit point on the SFX bus; the
  player's footfall logs the stage's size class and, after 10 s of cruising, the cruise variant; a
  telegraph aimed at the player from behind logs the windup and the sting, one from in front only the
  windup; the title opens `context: title` music; a boss engagement switches the set after its intro
  and phase 2 adds its layer at the next bar; volumes reach the buses; the focus-out notification
  mutes Master and focus-in restores it; a pausing screen pauses SFX players and ducks music;
  `--no-audio` logs nothing; the loading gate holds the first tick until `is_ready()`.
- Assets (offline `mix_audio`): every referenced file loads; SFX are samplable and ≤ 2 s; loops
  repeat with an exact period (the second pass equals the first within 1e-4); stem lengths match
  their sets to the frame; the size budget holds (Ogg file sizes + the exact QOA formula for WAVs);
  the registered seconds per level hold.
- Policies: no `PLAYBACK_TYPE_SAMPLE`, `AudioStreamRandomizer`, `AudioStreamPolyphonic` or
  `AudioStreamPlaylist` in `scripts/` or `ui/`; every Music/Ambience player, spot voices included,
  sets STREAM; the audio scripts never call `randf`, `randi` or `Sim.rng`.
- Gate: the seeded 120 s sandbox soak with audio and with `--no-audio` (two processes) produce
  byte-identical `AUTOPILOT_RESULT` lines.

**Test time:** default ≤ 1.0 s; slow 0; gate ≤ 3 min. **Acceptance:** [M6] audio engine with every
router row, the loading gate, settings, focus mute, budgets, bit-exact verification and the
determinism test; `tools/check.sh --audio` passes. **Size:** ~3,500 lines (GDScript ~2,100, Python
~650, tests ~750). **Cross-lane symbols:** the §2.4 signals P20 declares in the same wave
(`level_leaving`, `level_entered`, `region_changed`, `poi_discovered`, `trampled`, `formation_changed`,
`siege_engine_*`, `world_event_*`, `travel_requested`, `boss_yielded`, `boss_disengaged`,
`ability_evolved`, `talent_learned`, `ancestry_chosen`): the router connects each only when
`Events.has_signal(name)`; their rows are tested by P28 (and by P21 for the ones that exist by W13).
Zones and wading use `level_root.has_method("region_at")` and `has_method("water_at")` the same
way (P24a adds both in W14).

### 3.2 P20 — Campaign foundations: M7–M9 pre-declarations, save schema 2, campaign levels and transitions, the world index

- **Wave / lane:** W12, B, parallel with P19. **Depends on:** M0–M5. **Milestone:** M6 (for M7).
- **Goal:** land every shared contract of M7–M9 so later packages add files and data; migrate saves;
  make the campaign span two levels with reload transitions; give every level an index that answers
  positions, display names and arrival limits when nodes are not loaded; fix the title's checkpoint id
  and let a returning player skip a finished prologue.

**Owned paths**
- `scripts/world/{level_exit,world_index}.gd`; `scripts/core/schemas/{region,poi,faction,talent,wander_table,world_event}_schema.gd` (fields as §2.7, §2.11–§2.13; P22, P25, P29, P33, P37 ship the first records and may refine semantics at their anchors in `game_data.gd`)
- `data/progression/progression_default.json` (`world_start`), `tests/fixtures/saves/*.json`
- Tests: `tests/unit/{test_save_migration,test_world_index,test_quest_conditions_v2,test_predeclared_m7,test_world_start}.gd`,
  `tests/integration/{test_campaign_travel,test_title_checkpoint_names,test_activation_per_visit}.gd`

**Hotspot edits:** `scripts/core/game_session.gd` (§2.6: travel, respawn blockers, activation per
visit, `--start`), `scripts/core/save_slots.gd` (schema 2, `migrate`, backup recovery across the
migration), `scripts/progression/character_state.gd` (new keys pass through and normalise),
`scripts/quests/quests.gd` (quests in the campaign, index fallback for positions, `level_is`,
multi-marker stages, `xp_floor_level`, `waiting_text`), `scripts/quests/quest_conditions.gd` (`count`,
`quest_done`, `level_is`; anchors P27, P29, P37), `scripts/quests/dialogue_session.gd` and
`scripts/core/schemas/dialogue_schema.gd` (`attribute_points`, `locked_text`),
`scripts/world/level_root.gd` (`index()`, `player_nav_fallback` read, `RUNTIME_NODES`; anchors P24a,
P24b, P25, P27), `scripts/world/shrine.gd` and `scripts/world/waystone.gd` (read and mark
`GameSession.activated_this_visit`), `ui/screens/title_screen.gd` (display names; the skip-prologue
choice), `ui/hud/checkpoint_toast.gd` (display names), `tools/builders/valley.gd` +
`tools/data/valley_layout.json` (writes `index_valley.res`; waystone `display_name`s; checkpoint
`max_stage` placeholders), `data/world/level_valley.json` (`index`), `scripts/core/data_validator.gd`
(§1.6; §2.15 enums), `scripts/core/events.gd` (§2.4 block, anchors P21–P40, P24a, P24b), the anchor
lines of §1.5 in every listed file, `tests/support/anchors_expected.gd`, `tools/build_scenes.gd`
(BUILDERS), `ui/screens/screen_stack.gd` (SCREENS, HOTKEYS), `ui/hud/hud_widgets.gd` (WIDGETS),
`ui/screens/shrine_screen.gd` (TABS), `tests/support/reset_hooks.gd` (last `AFTER_EACH` entry), schema
modules `level_schema.gd` (`index`, `player_nav_fallback`), `quest_schema.gd` (`markers`,
`xp_floor_level`, `waiting_text`), `encounter_schema.gd` (`stand_down_when`, `web_formation_scale`
declared) and `progression_schema.gd` (`world_start`).

**Design**
1. Pre-declarations of §2.4 and §2.15 (enums, events, registries, anchors, runtime nodes) with a test
   that every declared registry path is under a folder the plan names and every new event has an
   emitter listed in a comment.
2. Save schema 2 and `migrate()` (§2.6) with fixtures: the four Valley completion saves and a pre-crown
   save, each migrated, validated and loaded into a character that equals the original plus the new
   defaults; a v2 save round-trips (the tracked quest included); a v3 save is rejected and kept; a
   damaged v2 main file with a v1 backup loads the migrated backup with its message.
3. Campaign: `GameSession.level_id`, `travel_to` (with the arrival-limit and visited rules),
   `respawn_transform`, `respawn_checkpoint` and its blockers, `--mode=world`, `--start`,
   `start_world_for_tests()`, `level_leaving` / `level_entered` (emitted from `on_level_ready` once
   `level.is_ready()` holds when the level has the method, and `Audio.is_ready()`, else at once).
   Checkpoints and saves work on every campaign level (`checkpoints_enabled()` = `is_campaign()` or
   test checkpoints); Continue loads the save's level; a missing level scene falls back to the Valley
   with a message. Shrines and waystones activate once per level visit (`activated_this_visit`), so a
   streamed chunk that reloads never gives a second free rest or checkpoint.
4. `LevelExit` (§2.6), proven on a pair of small levels the test builds in code (each a `LevelRoot`
   with a floor, a `CheckpointMarker` and a `LevelExit`, and a stub `level` record through
   `TestFixtures.record_override`): exit → checkpoint at the destination → reload → respawn at the
   destination with the character, flags and deltas intact; a travel refused while grabbed or holding.
5. `WorldIndex` (§2.6) and the Valley's index (every shrine, waystone, marker, area, district, road and
   prop the quests name; display names: shrines from their records, waystones from new layout
   fields: "Forest road waystone", "Ruins gate waystone", "Barrow gap waystone"). The title's save line
   and the toast use them (FOLLOWUPS: the title named the checkpoint by its id).
6. Quests in the campaign; `count`, `quest_done`, `level_is`; multi-marker stages; `xp_floor_level`;
   the dialogue effect `attribute_points`; `locked_text` and `waiting_text`; the `world_start` block
   generated from the Valley XP budget's worst outcome (§2.6), with a test that its XP equals the
   budget's floor (1,050) and its items equal the force path's guaranteed loot.
7. The title's skip-prologue choice (§2.6), hidden while `level.world`'s scene does not exist.

**Tests to add:** migration of every fixture; v2 round trip; future version kept; backup recovery
across the migration; travel between two test levels (respawn, character, flags, deltas); refused
travel (grabbed, a `max_stage` below the stage, an unvisited waystone); a respawn blocker moves the
respawn to the nearest unblocked checkpoint; Continue on a world save loads `level.world` when it exists
(a stub record in the test); the index's lookups and the fallback in `Quests.objective_position` with
the marker freed; the title line "at the Grove Shrine"; the skip choice appears only with a finished
save; a shrine freed and re-instanced in the same visit gives no second rest; `xp_floor_level` lifts an
award to the level; `attribute_points` adds points once with its `once_flag`; every anchor of §1.5
present (`test_anchors`); every pre-declared enum value used by the plan exists; `world_start` equals
the budget's floor.

**Test time:** default ≤ 1.0 s; slow 0; gate 0. **Acceptance:** [M6] title shows checkpoint names;
old saves load and recover; travel works between levels; every M7–M9 seam exists and is tested.
**Size:** ~3,400 lines.

### 3.3 P21 — Sound effects: the SFX library for everything in the game, the event map, threat cues

- **Wave / lane:** W13, A, parallel with P22. **Depends on:** P19, P20. **Milestone:** M6.
- **Goal:** original, generated sound effects for every combat, ability, enemy, world-object, UI and
  progression event that exists today (§4.1, §4.2), with directional threat cues, inside the budget.

**Owned paths**
- `tools/audio/synth/{instruments,voices,fx}.py` (modal impacts, whooshes, footfall layers, formant
  voices, growls, granular rumble, FM magic, UI blips), `tools/audio/gen_{combat,abilities,steps,voices,threat,world,ui}.py`
- `assets/audio/sfx/**` (WAV masters and their `.import` files), manifest and provenance entries
- `data/audio/bank_{combat,abilities,steps,voices,threat,world,ui}.json`; `data/audio/mix_default.json`
  (classes, materials, voices, surfaces filled; `wet` over the Valley's river through its water area)
- Tests: `tests/integration/{test_sfx_coverage,test_threat_cues}.gd`, `tests/unit/test_sfx_banks.gd`,
  `tests/gate/test_sfx_valley_pass.gd`

**Hotspot edits:** `scripts/audio/cue_router.gd` (single owner in W13) only if a routing rule must
change; the change is recorded in the system doc. P22 never touches it.

**Design:** §4.1 (every cue), §4.2 (synthesis by family), §4.4 (classes, priorities, caps), §4.5
(formats: 22.05 kHz mono QOA, 32 kHz for metal; masters normalised to −6 dBFS peak; every file ≤ 2 s;
the footfall `.cruise` variants without the debris tail). Every cue has 1–4 variants. The threat
family (§4.1, F) is designed for localisation: broadband transients, a rising band-pass sweep,
0.2–0.6 s, distinct from every other family (a test compares their spectral centroids and onset
times with the impact family). Enemy voices are formant-synthesized calls, never words. Wolves'
footfalls use `QuadrupedRig.footfall` when P22's signal exists (cross-lane symbol).

**Tests to add**
- Coverage: every enemy and NPC record resolves alert, attack, hurt and death voices (and `flee` for
  humans, routed through `enemy_routed`); every action with a telegraph resolves a windup cue; every
  prop resolves hit, crack (structural) and break cues by material; every weapon family resolves light
  and heavy swings; every ability in the progression library resolves its cast or impact; every
  `Events` signal is routed or in the silent list (§4.1); every UI screen resolves open and close.
- Threat cues: a soldier's chop from behind logs windup + sting at the soldier's position; from in
  front, no sting; a chip attack under 3 % of maximum health logs no sting; an archer's shot logs the
  aim-commit cue at `tracking_fraction`; the sting's priority steals over footfalls.
- Banks: variant counts, buses, classes, caps; the budget (SFX ≤ 0.95 MB) and the per-file duration
  limits; the Valley's registered seconds ≤ 110.
- Gate: the "missing" counter stays 0 through the 120 s soak and a scripted Valley pass (the
  walkthrough's teleport route).

**Test time:** default ≤ 0.5 s; slow 20 s; gate ≤ 3 min. **Acceptance:** [M6] every event audible or
listed silent in §4.1; directional threat cues; budget held; `--audio` verify passes. **Size:** ~2,700
lines (Python ~1,450, JSON ~700, tests ~550). **Cross-lane symbols:** `QuadrupedRig.footfall` (P22),
reached with `has_signal`.

### 3.4 P22 — Rigs and M5 polish: merged rig parts, a distance LOD for actors, Thornwick's guards, factions by record, the web release without test content, ranged positioning, the Valley balance items

- **Wave / lane:** W13, B, parallel with P21. **Depends on:** P20. **Milestone:** M6.
- **Goal:** keep any Valley view with five or more enemies near the 250 draw-call budget; close the
  M5 follow-ups and known limitations that are not audio (Thornwick, the yard pocket, the nav-link
  flake, off-camera hits, the Valley's balance items); generalise factions to records for the world;
  make the web release lean and testable.

**Owned paths**
- `tools/scene_kit.gd` (`merge_vertex_colored(parts: Array[MeshInstance3D]) -> MeshInstance3D`, the
  rig material), `tools/builders/{player,soldier,wolf,ranged,heavy,npcs}.gd` and their regenerated
  scenes, `scripts/presentation/{actor_rig,quadruped_rig}.gd`
- `data/world/encounter_village_guards.json`, `data/world/faction_village.json`,
  `tools/data/valley_layout.json` (guard posts, the yard pocket), `scripts/world/faction_state.gd`,
  `scripts/ai/{civilian_brain,archer_brain,mage_brain}.gd` (W13)
- `data/test/*` (moves today's `level_director_test`, `encounter_director_test_*` and
  `level_stress_arena` records here), `export_presets.cfg`, `web/launcher.html` (the `?args=`
  pass-through), `tools/build_web.sh` (`--preset=` and `--out=`; the pck size report and gates)
- `scripts/debug/run_metrics.gd` (a `faction_hostile` field per run)
- Tests: `tests/integration/{test_rig_merge,test_render_lod,test_faction_records,test_ranged_positioning,test_web_presets}.gd`,
  `tests/slow/{test_thornwick_help_path,test_yard_pocket}.gd`

**Hotspot edits:** `scripts/actors/enemy_actor.gd` (anchor P22: `set_lod_tier` leaves the proxy to the
renderer at tiers 0–1), `scripts/core/schemas/enemy_schema.gd` (anchor P22: `render_lod_m`,
`tactics.front_arc_deg`), `data/enemies/*.json` (`render_lod_m`; the archer's and mage's positioning
data), `tests/integration/test_world_props.gd` (the nav-link test waits for the map's iteration id),
`docs/PERFORMANCE.md` (results), `docs/plans/FOLLOWUPS.md`, `docs/BALANCE_LOG.md` (the Valley items).

**Design**
1. **Merged parts.** Each rig keeps its animated pivots (hips, torso, shoulders, the quadruped's legs,
   head and tail) but each pivot's boxes become one mesh with vertex colours and one surface; the
   weapon stays its own mesh. One `StandardMaterial3D` per actor (`vertex_color_use_as_albedo`, made
   unique by the rig): a flash sets `emission` (colour × strength) and a status tint multiplies
   `albedo_color`. The giant's rig gets the same treatment; render layer 2 parts (head, chest, belt)
   stay separate meshes so first person still culls them (P26 tests the eye anchor at stages 4–6).
   `ActorRig` and `QuadrupedRig` adapt `_make_materials_unique`, `flash`, `set_status_tint` (every
   existing tint and flash test passes).
2. **Distance LOD.** Every rig part gets `visibility_range_end = render_lod_m` (+5 m margin) and the
   `Visual/LodProxy` `visibility_range_begin = render_lod_m` (− 5 m margin), so the renderer swaps
   them by distance at tiers 0 and 1; tier 2 keeps today's behaviour. `render_lod_m`: soldier,
   archer, mage, villager 45 m; wolf 40 m; ogre 70 m; the Ogre King 0 (never). A test checks the
   ranges; the Valley walk measures the result.
3. **Quadruped footfall.** `QuadrupedRig` emits `signal footfall` per paw pair contact (P21 and the
   audio router use it).
4. **Thornwick.** Guard posts 3 and 4 move from x 88 to x 72 (z −30 / −10) and the captain to (76, −20),
   out of the bridge fight's reach at stage 3 (≥ 22 m from the barricade's centre); neutral guards
   whose faction is not hostile step back 10 m from any enemy within 12 m of them (FactionState
   hook). A slow test runs the stage-3 return patrol fight at the barricade with the AI on and asserts
   no offence; P22 runs the assisted bot on help_cache and intimidate (two runs) and records
   `faction_hostile` false.
5. **The yard pocket** (x 62–72, z −50 to −35, HOW_IT_PLAYS known issue): a blocker or a fill box so
   the giant's navmesh has no pocket; the slow navigation test proves a path out.
6. **Factions by record** (§2.12): `FactionState` reads texts and thresholds from faction records,
   handles several factions, `initial` dispositions, the `reconciled` state (wins over hostile),
   offences by damage to faction-owned `house`/`engine` props (blows, abilities, trampling); civilians
   of a faction with `civilians_give_way` step aside and watch instead of fleeing unless it is warned or
   hostile. `faction.village` keeps today's texts and fleeing (the Valley is unchanged; its regression
   suites pass).
7. **The web release without test content.** Today's test-only records move to `data/test/`; the
   `Web` preset excludes `scenes/test/*, assets/test_world/*, data/test/*` (desktop presets keep them:
   the stress route's owner commands need them); a `Web (test)` preset keeps them for the streaming
   checks; the launcher passes `?args=a,b,c` to the engine's `args` (P24a's stream check and the web
   checks use it); `build_web.sh --preset=<name> --out=<dir>` builds either and prints the pck's
   shipped size, warning over the milestone's budget (decision 8). A test parses `export_presets.cfg`
   for the exclusions and builds nothing.
8. **Off-camera hits** (M5: 22–24 % against a target under 20 %). Archers and mages gain
   `tactics.front_arc_deg` (150): when a firing position in their band lies within that arc of the
   camera's yaw they take it, and a shot from outside the camera's view needs an aim time of at least
   1.2 s (the threat cue leads it). The Valley regression matrix (novice × 4 outcomes × seeds 1–3, the
   expert on seeds 1–3; §6.4) measures the share at this package and again at the M6 gate; a remaining
   miss is reported as a miss.
9. **The Valley balance items** (`HOW_IT_PLAYS.md` "Known issues"; at most two data-only iterations,
   logged in `BALANCE_LOG.md`): the novice should need 1–2 tries at the Ogre King (median); damage per
   segment ≤ 0.6 × maximum health in the forest and the ruins; the force branch's return leg finishes
   inside the bot's 240 s watchdog in 3 of 3 runs (encounter composition and spacing, never by
   removing the fight); the expert runs on seeds 1–3. The bot's short pacing is deferred to a timed
   human run (§0.4).
10. **The nav-link flake**: `test_world_props.test_a_broken_gate_opens_its_nav_link` waits until the
    map's iteration id has advanced after the link enables, instead of a fixed 3 s.

**Tests to add:** merged rigs have the expected mesh count per archetype (soldier 6, wolf 7, ogre 7,
the giant 9 including layer-2 parts); flashes and tints still read on the material; LOD ranges per
archetype and none on the boss; a rendered draw-call check (slow, Xvfb when available, else skipped
with a note): the stress arena p50 drops by at least 40 %; the Thornwick slow test; the pocket;
faction records (several factions, reconciled over hostile, a house prop's damage is an offence, a
give-way civilian stays within its distance band and does not flee); ranged enemies pick the front
arc when one exists; the web presets' exclusions.

**Test time:** default ≤ 0.5 s; slow 30 s; gate 0. **Acceptance:** [M6] the Valley walk at `low`
shows views with five enemies under 250 draw calls (measured, PERFORMANCE.md updated); FOLLOWUPS rows
closed; the Valley matrix reports the off-camera share and the balance items; the web release has no
test content. **Size:** ~3,300 lines.

### 3.5 P23 — Music and ambience: the Valley score, stingers, beds and spots, the multi-part pack, the web audio check

- **Wave / lane:** W14, A, parallel with P24a. **Depends on:** P19, P21, P22. **Milestone:** M6.
- **Goal:** the adaptive score and the ambience of §4.3 for the title, every Valley district, the
  sandbox, the Ogre King's two phases, the stingers and the end screen, with melody variants, rests and
  silence windows; proof that it plays in the web export within its memory cap; a pck that ships in
  parts so the download, not the host's per-file cap, limits the game.

**Owned paths**
- `tools/audio/synth/{music,ambience}.py` (pads, plucks, flute, brass, drums, choir; a seeded modal
  phrase writer that writes the three variants of a set from one motif; wind, insects, leaves, murmur,
  water), `tools/audio/gen_{music,stingers,ambience}.py`
- `assets/audio/{music,ambience}/**` (Ogg), manifest and provenance entries; deletes
  `assets/audio/placeholder/` and `data/audio/bank_placeholder.json`
- `data/audio/{music_*,ambience_*,region_valley_*,region_contexts,region_silent}.json`,
  `data/audio/bank_{stingers,ambience}.json`
- `tools/web/audio_check.mjs`, `web/launcher.html` (resume a suspended AudioContext on the first
  pointer or key press; "Sound on" in the page's notes; the multi-part pck), `tools/build_web.sh`
  (splits the packed pck into parts of at most 15 MB; prints the audio share)
- Tests: `tests/integration/{test_music_valley,test_ambience_valley,test_audio_zones}.gd`, `tests/slow/test_music_loops.gd`

**Hotspot edits:** `scripts/audio/{music_director,ambience_director}.gd` (single owner in W14) only
for refinements the score needs, each recorded in the system doc; `docs/USABILITY_SCRIPT.md` (the
audio sheet).

**Design:** §4.3 (the score: zone sets in one frame with three melody variants each, shared danger and
combat stems, region combat intros, the boss set in its own frame with an intro stinger), §4.2
(synthesis), §4.5 (formats and budget). **The multi-part pack**: `build_web.sh` writes
`index.pck.gz.b64.<n>.txt` parts of at most 15 MB when the packed pck is larger (one part otherwise);
the launcher's `PACKED` entry lists the parts, downloads them in order with one progress meter, joins
the text, then decodes and unpacks as today; a forced two-part build (`--parts=2`) is part of the
acceptance. **`audio_check.mjs`**: serve `builds/web/` on a free port (check the page title first),
open `play.html` in headless Chromium with an AudioContext wrapper and an AudioWorklet recorder on the
destination (as in `audio_tech.md` §8), and a buffer tracker (every `createBuffer` attached to a source
node counts while that source plays; the rest are registered buffers); click Play, New Game, then
record: sound within 5 s of the Hollow, no silent run longer than 50 ms in the music for 60 s, peak live
sample bytes ≤ the Valley's registered seconds × 353 KB + 12 MB, 0 console errors; print one
`AUDIO_CHECK {json}` line. It takes `--args=` (passed through the launcher) and `--route=` so the M7
gate can run it on the world (§6.6). **The audio sheet** in `USABILITY_SCRIPT.md`: loudness balance,
harshness, threat readability, music fatigue (does the melody rotate and rest; is the silence window
welcome), the hidden-tab mute.

**Tests to add:** every district, the sandbox and every context map to a set; every level record maps
to an audio region or is in the silent list (`region_silent.json`); intensity changes the layers at
beat or bar boundaries; the melody switches variants only at segment boundaries; a district crossing
cross-fades within `crossfade_bars`; title, end and sandbox contexts; the boss set's intro and phase
layer; stingers duck and release; the ambience bed changes with 15 m hysteresis; spots stay within
their distance band and flush; emitters cap at two; slow: every stem and loop renders seamlessly for
two periods and every set's stems are aligned to the frame.

**Test time:** default ≤ 0.5 s; slow 15 s; gate 0. **Acceptance:** [M6] the Valley has its score and
ambience; the web check passes within the M6 budget (≤ 4.0 MB audio, pck ≤ 7.5 MB as shipped) and the
forced two-part build boots and plays. **Size:** ~3,300 lines.

### 3.6 P24a — Terrain and streaming runtime: chunk data, terrain, the streamer with hysteresis, the skyline mechanism, the loading screen, the test world, the web stream check

- **Wave / lane:** W14, B, parallel with P23. **Depends on:** P20, P22. **Milestone:** M7 foundation
  (merged in W14; reviewed at the M7 gate, never holding the M6 release).
- **Goal:** the terrain and streaming half of decisions 12 and 14 and the shared offline terrain
  library, on a generated 4 × 4 test world that proves streaming budgets, seams, hysteresis, the
  skyline and a settlement-sized chunk on desktop and in the web build, and measures the world data
  budget before the real world exists.

**Owned paths**
- `scripts/world/{chunk_data,terrain_chunk,chunk_streamer,world_root,skyline}.gd`, `assets/shaders/skyline.gdshader`
- `tools/world/{chunk_writer,heights,skyline_writer}.gd` (quantise heights with an apron, surface
  cells, scenery transforms, solids, settlement sub-scene splitting at 150 nodes, border slope
  relaxation, the coarse skyline mesh)
- `tools/builders/test_world.gd`, `scenes/test/test_world.tscn`, `assets/test_world/**`,
  `data/test/{level_test_world,encounter_test_world_*}.json`
- `scripts/debug/world_walk.gd` (a streaming walk with PerfProbe sections: work per frame, the margin
  to unloaded ground, thrash count; a `--route=` of waypoints), `tools/web/stream_check.mjs`
- Tests: `tests/unit/{test_chunk_data,test_heights}.gd`, `tests/integration/{test_terrain_chunk,test_chunk_streamer,test_world_root,test_skyline}.gd`,
  `tests/slow/{test_world_seams,test_world_walk}.gd`

**Hotspot edits:** `scripts/world/level_root.gd` (anchor P24a: `camera_far_m` and
`terrain_visibility_end_m` from the render preset), `scripts/presentation/camera_rig.gd` (anchor P24a:
the far plane from the level), `scripts/core/schemas/level_schema.gd` (anchor P24a: `world`, the two
render keys), `scripts/core/game_data.gd` (anchor P24a: world record checks), `scripts/main.gd` (the
world's loading screen with progress: ring slices and sample registration, `PROCESS_MODE_ALWAYS`, at
most 8 s then a warning and on), `scripts/debug/autopilot.gd` (dispatch `--scenario=world_walk`),
`docs/PERFORMANCE.md` (streaming numbers, the world data measurement).

**Design:** §2.7 (ChunkData), §2.8 (streamer, WorldRoot, skyline); `open_world_tech.md` §3–§4 are the
reference (step order, batch sizes, the seam trap). The test world: 4 × 4 chunks of 256 m at 4 m
spacing, rolling noise with one 30° ramp and one 35° ramp crossing seams, a Brannock-sized settlement
in one chunk (a walled town of 22 merged houses, 8 breakable houses, gates and breakables with
scripts, split into sub-scenes), 120 trees per chunk with non-blocking saplings, two landmark
silhouettes and its skyline. Deterministic streaming in headless runs (a fixed step quota). The
loading screen keeps the tree paused until the ring is loaded and `Audio.is_ready()`. **The world data
measurement**: P24a writes the test world's chunk data (16-bit heights only) and reports its size per
chunk; P24b adds the per-layer navmesh sizes; together they extrapolate to 64 chunks (rim chunks at
their share) in the system docs, against decision 8's 5.0 MB.

**Tests to add**
- Unit: height quantisation round-trip (≤ 4 mm), apron normals equal across a seam, chunk id ↔
  position, slope relaxation leaves borders ≤ 35°, settlement splitting keeps every sub-scene ≤ 150
  nodes, the coarse skyline never rises above the fine heights.
- Integration: a chunk loads in slices within the step quota; unload emits `unloading` before nodes
  are freed; the ring follows a moving focus; hysteresis: walking back and forth across a border 20
  times loads each chunk once (0 thrash); at most 25 chunks loaded; `region_at` / `height_at`; the
  skyline mask hides the coarse mesh over drawn chunks and shows it elsewhere; the far plane follows
  the level.
- Slow: the stage 1–3 giant walks a loop with four seam crossings at ≥ 97 % of walk speed and never
  under the terrain; the streaming walk at 16 m/s keeps ≥ 200 m of loaded margin and work p99 ≤ 6 ms
  (desktop headless), including the settlement chunk.
- Web (`stream_check.mjs`, run by P24a on the `Web (test)` build and recorded, then at the M7 gate on
  the real world): the world walk in headless Chromium **with gameplay** (the giant walking, AI on, 3D
  on): worst frame ≤ 45 ms and p99 ≤ 25 ms (indicative), the margin, 0 console errors.

**Test time:** default ≤ 0.6 s; slow 45 s; gate 0. **Acceptance:** [M7 foundation] streaming,
terrain, hysteresis and the skyline proven on the test world; the web stream check recorded; the
world data extrapolation in the system doc. **Size:** ~3,000 lines.

### 3.7 P24b — Navigation across chunks and the director in a streamed world

- **Wave / lane:** W15, A, parallel with P26. **Depends on:** P24a. **Milestone:** M7 foundation.
- **Goal:** the navigation half of decisions 13 and 15: per-layer maps with titan gate bits,
  deterministic readiness, one query helper with throttling and a budget converted at every call
  site, nav links in chunk scenes, and the director in a streamed world.

**Owned paths**
- `scripts/world/{nav_maps,nav_query}.gd`, `tools/world/nav_bake.gd` (lean per-layer bake with the
  three fixes; titan gate regions with their bits; neighbours' obstacles)
- the test world's navmeshes (`assets/test_world/nav/**`; `tools/builders/test_world.gd` in W15 adds a
  gated ford and a breakable gate with links), `data/test/encounter_test_world_*.json` (a wolf pack and
  a soldier band across a seam; a chase into water)
- Tests: `tests/unit/test_nav_query.gd`, `tests/integration/{test_nav_maps,test_nav_links_streamed}.gd`,
  `tests/slow/{test_world_nav,test_world_director,test_unreachable_chase}.gd`, `tests/gate/test_world_determinism.gd`

**Hotspot edits:** `scripts/world/level_root.gd` (anchor P24b: `nav_map(layer)`, `nav_layers()`,
`nav_layer_for`, `nav_query_settings`), `scripts/world/chunk_streamer.gd` and `world_root.gd` (W15:
the navmesh steps, async off when deterministic, `is_ready` by iteration id, links to layer maps),
`scripts/actors/enemy_actor.gd` and `scripts/ai/enemy_brain.gd` (anchor P24b: layer maps, `NavQuery`,
repath throttle, chase-goal snapping, flee snapping), `scripts/actors/civilian.gd` (`NavQuery`, flee
snapping on its layer map), `scripts/debug/{valley_bot,bot_diagnosis,valley_walk}.gd` (`NavQuery`
call sites only), `scripts/world/encounter_director.gd` (anchor P24b: chunk index, despawn before
unload, `min_stage` / `max_stage`, the leash rule, the query budget),
`scripts/core/schemas/{level,encounter}_schema.gd` (anchors P24b: `nav_query`, `min_stage` /
`max_stage`), `scripts/core/game_data.gd` (anchor P24b: the leash rule for streamed levels),
`docs/PERFORMANCE.md` (navigation numbers).

**Design:** §2.2 and §2.8 exactly; `open_world_tech.md` §5 is the reference (the three bake fixes,
map per layer, query limits). The Valley's queries keep `map_get_path`'s defaults through `NavQuery`
(no `nav_query` block), and the Valley soak's `AUTOPILOT_RESULT` is byte-identical before and after
this package (checked on its branch).

**Tests to add**
- Unit: `NavQuery` parameters by purpose; the Valley's settings equal the defaults; the budget.
- Integration: a chunk is ready only after every layer map's iteration id passed its region add (one
  tick with async off); a breakable gate's link in a streamed chunk joins its layer map and opens a path
  when broken (waiting for the map's iteration); a stage-3 titan mask cannot cross a gate-4 ford and a
  stage-4 mask can.
- Slow: 40 random cross-chunk paths per layer succeed; a wolf and a soldier chase the giant across a
  seam without a path failure; members in an unloading chunk despawn and respawn at home; no member
  spawns in an unloaded chunk; 20 humans chasing a giant standing in the test world's deep water keep
  CPU per tick p95 ≤ 8 ms (headless desktop) with the throttle and the budget.
- Gate: two `world_walk` runs with AI on and a chase across a seam give byte-identical
  `AUTOPILOT_RESULT` lines.

**Test time:** default ≤ 0.5 s; slow 45 s; gate ≤ 3 min. **Acceptance:** [M7 foundation]
deterministic cross-chunk navigation with gate masks, every call site on `NavQuery`, the director in a
streamed world, the world data extrapolation completed with navmesh sizes. **Size:** ~2,700 lines.

### 3.8 P25 — World builder and geography: the 2 × 2 km world, regions, the skyline, POIs, shrines, waystones, caches, cairns, light content, the map picture and the index

- **Wave / lane:** W16, A, parallel with P30. **Depends on:** P24a, P24b, P20. **Milestone:** M7.
- **Goal:** the real world of §5 as an explorable world: terrain with the regions' heights, the rim,
  the Kingsgate shelf, the highland wall, the Mere, the Wend, roads, scenery, the skyline with its
  landmarks, every POI landmark, shrine, waystone and exit, caches and cairns, two light encounters per
  region, navigation on three layers with gate regions, the index with the staged road graph, and the
  map picture.

**Owned paths**
- `tools/world/{features,layout,map_render,index_writer}.gd`, `tools/world/kinds/*.gd` (house, hall,
  wall, tower, palisade, gate_prop, bridge, ruin, column, stone_circle, bones, tent, field, pier,
  beacon, statue, stair_visual, cache, cairn, green), `tools/builders/world.gd` (`--chunks=` with
  neighbour expansion)
- `tools/data/world/{world,crownmarch,greywood,drowned_steps,aldmere,stonehold}.json` (terrain, POI
  landmarks, shrines, waystones, exits, size gates, caches, cairns, safe markers, scenery, the light
  content; no settlement detail beyond landmarks and greens)
- `scenes/world/world.tscn`, `scenes/world/chunks/*.tscn`, `assets/world/**` (except
  `index_valley.res`)
- `data/world/{level_world,region_*,poi_*}.json`, `data/shrines/shrine_world_*.json`,
  `data/loot/cache_*.json`, `data/world/encounter_{greywood,drowned,aldmere,stonehold}_*.json` (the
  light content of §5.10), `data/dialogue/dialogue_cairn_*.json`, `scripts/world/inscription.gd`
- Tests: `tests/slow/test_world_build.gd`, `tests/integration/{test_world_data,test_m7_content_rule,test_skyline_view}.gd`,
  `tests/gate/test_world_reachability.gd`

**Hotspot edits:** `scripts/world/level_root.gd` (anchor P25 if needed), `scripts/core/schemas/level_schema.gd`
(anchor P25: `regions`), `scripts/core/game_data.gd` (anchor P25: every POI's region and level exist;
a POI's landmark exists in the index; quest-critical props are `indestructible`), `tools/check.sh`
(`--build-args=`, the seam checks on rebuilt chunks, the build limit raised to 1,500 s),
`docs/PERFORMANCE.md` (world sizes, the pck share, draw calls at the viewpoints).

**Design:** §5.1–§5.5 give every coordinate. The five world shrine records use only today's shrine
fields (Kingsgate: `max_stage` 4 and `growth_requires_flags: ["world.kingsgate.lit"]`; the others their
`max_stage` and no condition yet); P29 adds the oath conditions once P26's field exists. Heights: the
feature recipe of §5.3 sampled at 4 m, quantised to 16 bits (−32 m … +230 m); the builder relaxes
slopes within 8 m of a chunk border to ≤ 35° wherever the ground is walkable and fails with the
location if it cannot. Scenery: Poisson-disk trees with species per region, minimum trunk spacing 9 m
in walkable forest (stage-6 capsules pass), saplings without collision. Rim: slopes > 55°, no navmesh,
blocker walls along the walkable edge. Water: the Mere and the Wend as flat planes with `size_gate_4`
/ `size_gate_5` walls on the deep edges (P26's `SizeGate` scene) and titan gate regions under them.
Navigation: human, large, titan and gate regions per chunk (lean); chunks entirely under the rim have
none; every quest talker's green and every interactable is reachable on the titan layer from its
nearest road node at the stage that needs it (a builder check); streets and gates on quest routes are
at least 12 m wide (16 m in Brannock). The skyline: the coarse terrain from the real heights, the
landmark silhouettes of §5.4 (`skyline: true` POIs, about 12) and the beacon columns. Index: every
checkpoint (display names, `max_stage`), POI, exit, marker (safe markers included), area, prop that a
quest may name, the staged road graph (nodes every 40 m along roads plus POI connectors; edges carry
`min_stage`/`max_stage`; the Needle's edge is `direct` with `max_stage` 4), the region grid (64 m
cells). Map picture: 1,024 × 1,024 PNG, hillshade from the heights, water, roads, region tints,
settlement footprints (≤ 300 KB). The world builds in about 3–5 minutes; `--chunks=c2_6,c3_6` rebuilds
those and the neighbours whose navmesh sources or border heights they touch. **Light content** (§5.10,
the M7 content rule): two encounters of existing archetypes in each of the Greywood, the Drowned
Steps, Aldmere and the Stonehold, caches at ruins and vistas and at every POI that would otherwise
hold nothing in M7 (removed by the region package that brings its content), the seven world cairns that need no
seal (`Inscription`: a stone that opens `dialogue.cairn_<name>`, one attribute point once; the six
sealed ones come with their regions' secrets), and Fort Aldmere's gate shut and `indestructible` until
P36 makes it the real gate.

**Tests to add:** every chunk file exists and loads; border heights equal across every seam; no
walkable border slope over 35°; world data ≤ 5.0 MB; the M7 content rule (§0.2); from the Kingsgate
shelf (stage-3 camera at its default yaw, `low`) the landmark of each of the five regions is in the
frustum and not occluded by the skyline heightfield; every POI's landmark lies inside its radius; the
index's region grid matches every region record's bounds; the static world's draw calls at the six
settlement viewpoints and the shelf ≤ 40 at `low`, breakable houses ≤ 25 more per view (Xvfb when
available); gate: every shrine, waystone, exit, green and POI centre is reachable from
`world.cp.kingsgate_shelf` on the titan layer with the mask of its required stage (road graph +
per-chunk paths), sealed places through their seals, and the Needle side by a stage-3 walking test.

**Test time:** default ≤ 0.3 s; slow 30 s; gate ≤ 3 min. **Acceptance:** [M7] the world loads at the
Kingsgate shelf, can be seen to its edge and walked everywhere it should be; the M7 content rule
holds; budgets held; the rebuild-twice check passes. **Size:** ~3,500 lines (layout JSON ~800, data
~700).

### 3.9 P26 — Growth stages 4–6 and size gates; the Valley's exits, revisits and the Citadel

- **Wave / lane:** W15, B, parallel with P24b. **Depends on:** P20, P24a. **Milestone:** M7.
- **Goal:** the giant grows to 18.9 m with every system following, in both camera modes; the world
  can gate routes by size; weapons can carry stage movesets; the Valley opens north after the crown,
  its Citadel can be breached at stage 4, and no big giant is ever sent where the Valley is too narrow.

**Owned paths**
- `data/growth/growth_0{4,5,6}.json`, edits of `growth_0{1,2,3}.json` (`size_gate_mask`)
- `scripts/world/size_gate.gd`, `tools/builders/world_props2.gd` and its scenes (`kings_door`,
  `citadel_hoard`, `size_gate_*` visuals, `rockfall`, `titan_tree`, `toppled_statue`,
  `palisade_trample`, `great_pine`)
- `data/props/{kings_door,rockfall,titan_tree,toppled_statue,palisade_trample,great_pine}.json`, data
  of the abilities' stage scaling (`heavy_footfall`, `thunder_roar`, `boulder_hurl`)
- `tests/integration/{test_growth_456,test_size_gates,test_trample,test_valley_exits,test_stage_movesets_field}.gd`,
  `tests/slow/{test_growth_route_456,test_citadel_breach,test_valley_revisits}.gd`

**Hotspot edits:** `scripts/actors/player/player_growth.gd` (size-gate mask, titan query mask, nav
fallback, stages 4–6 messages), `player_motor.gd` (trample contacts), `player_attack.gd`
(`range_by_stage_m`), `player_equipment.gd` (`stage_movesets`), `scripts/world/breakable_prop.gd`
(`trample_stage`, the `trample` hit, `heave`, house trampling as a faction offence through
FactionState, `indestructible`), `scripts/world/shrine.gd` + `shrine_schema.gd` (anchor P26:
`growth_requires_conditions`), `scripts/core/schemas/{growth_profile,action,prop,weapon}_schema.gd`
(anchors P26), `scripts/core/game_data.gd` (anchor P26: profile chain 1–6 consistent, size masks
match stages), `scripts/presentation/camera_rig.gd` (anchor P26: arms up to 32 m; never under terrain
via the existing sweep), `project.godot` (layer names 7–9), `data/weapons/{club,sword,hammer}_reinforced.json`
(`fit_max_stage` 6; `stage_movesets` keys pointing at P31's records, absent records falling back to
today's moveset until W18), `data/world/level_valley.json` (`player_nav_fallback` 4),
`tools/data/valley_layout.json` + `tools/builders/valley.gd` (the Kings' Door in the Barrow's north
cliff, the Citadel hall cut into the citadel block with the hoard and the stair exit, the Barrow's
sealed vault behind a heave rockfall, the new checkpoint `valley.cp.kings_door`, every checkpoint's
measured `max_stage`; the Valley index regenerated), `ui/screens/end_screen.gd` ("Prologue complete",
Continue). The Valley's shrine records stay as they are (`max_stage` ≤ 3).

**Design:** §2.9; §5.6 (the Valley's exits, revisits and the Citadel); §5.14 (what stages 4–6
change). Growth beyond stage 3 needs a world shrine with `max_stage` ≥ the target (Valley shrines stay
at 3). The Kings' Door is a structural, `indestructible` prop opened by `slice.completed`
(`open_when_flag`) with a `LevelExit` in front of it; the Citadel's hall (17 × 50 m, 30 m tall) holds
the hoard pickups (titan iron ×2, the Kings' Annals lore item) and the `valley.exit.citadel_stair`
exit to `world.exit.broken_stair`. Trample: `PlayerMotor` checks its slide collisions each tick against
`breakables` with `trample_stage ≤ stage` and sends one `trample` hit (category `melee`, 9,999 damage;
an offence only for faction-owned houses, decision 31).

**Tests to add:** growth 1 → 6 with capsule, camera, lock range, weapon geometry, hurtboxes and
resources following (debug grow) and refusals for missing conditions; the size mask and titan mask
per stage; a stage-3 capsule stopped by a `size_gate_4` wall with the message and the gate's cue, a
stage-4 one passing; trample at stage 4 and not 3, a faction house trampled is an offence and a fence
is not; heave at 5 and not 4; Footfall, Roar and Hurl values per stage; lights 1–2 and the heavy land
from contact to 0.9 × reach at stages 4–6 on a soldier and a wolf (a fixture weapon with
`fit_max_stage` 6), and `stage_movesets` swaps the moveset at its stage; first person at stages 4–6:
the eye anchor and the hidden head parts follow the merged rig, and a downward light and heavy hit a
soldier at the giant's feet; the Kings' Door locked before the crown and an exit after; the Citadel
gate breached at 4 and refused at 3 with the message; the hoard; the stair exit; the vault opens to a
stage-5 heave; slow: the 3-size route extended to stages 4–6 on P24a's test world in third and first
person (seams, ramps, clearance); a stage-4 walk from the Kings' Door to the Citadel with capsule
clearance samples; **Valley revisits**: a stage-4, -5 and -6 giant respawned at every Valley
checkpoint has a clear capsule and a camera that does not clip, and a path (capsule-swept along the
giant-layer path) or a fast-travel route to an exit; each checkpoint's `max_stage` is the highest stage
that passes, written into the layout and the index; the Hollow→Grove, Hollow→Thornwick and
Thornwick→Kingsfall overlap sampling at stage 4 is recorded.

**Test time:** default ≤ 0.7 s; slow 35 s; gate 0. **Acceptance:** [M7] stages 4–6 work everywhere,
in both camera modes; the Valley's two exits work; Valley checkpoints carry measured limits; the end
screen continues. **Size:** ~3,300 lines. **Cross-lane symbols:** none (P24b's navigation is not
needed: the Valley's own navmesh serves the stage-4 walk).

### 3.10 P27 — Open-world UX: map, compass, pins, discovery, fast travel, the tracked quest, the journal, sealed places

- **Wave / lane:** W17, A, parallel with P28. **Depends on:** P20, P24a, P25. **Milestone:** M7.
- **Goal:** the player always knows where they are, what is worth going to, where things are, what
  they cannot do yet, and how to get there.

**Owned paths**
- `ui/screens/{map_screen,journal_screen}.gd`, `ui/hud/{compass,region_banner,discovery_toast}.gd`,
  `scripts/world/discovery.gd`
- `data/tutorial/{map,compass,fast_travel,discovery,size_gate,sealed_place}.json`
- Tests: `tests/integration/{test_map_screen,test_compass,test_discovery,test_fast_travel,test_tracked_quest,test_journal}.gd`
  (built on stub indexes and widgets, no level loads)

**Hotspot edits:** `ui/hud.gd` (HUD layout of §2.14; the lock line from `lock_label()`),
`tests/integration/test_hud_layout.gd`, `scripts/quests/quests.gd` and `quest_conditions.gd` (anchor
P27: tracked quest saved as `progress.tracked_quest`, multi-marker objectives, `discovered`,
`region_entered`), `scripts/world/level_root.gd` (anchor P27: `Discovery` lookup),
`data/input/default_bindings.json` + `scripts/adapters/input_bindings.gd` (`map`, `journal`,
`track_next`, `map_pin`, labels, glyphs, the help overlay), `docs/USABILITY_SCRIPT.md` (a world
section: finding the way, the map, pins, fast travel, sealed places).

**Design**
1. **Discovery** (the runtime node `Discovery` in both campaign levels): every 30 ticks, POIs within
   their radius of the player set `discovered.<poi>`, award `xp` once (`xp_award_requested`), emit
   `poi_discovered`; a discovered `vista` sets `discovered` on the POIs within its `reveals_m`
   (shown on the map, no XP); a `secret` within 60 m sets `sealed.<poi>.seen`; entering a chunk sets
   `map.seen.<chunk>`; region changes set `region.<short>.entered` and show the banner (with
   "Recommended stage" in the warning colour when below); `checkpoint_reached` sets `visited.<id>`.
2. **Map screen** (pausing): the index's picture (or the Valley's vector map: districts and roads),
   fog per unseen chunk, icons for discovered POIs, sealed places (a lock and their stage), shrines and
   waystones, exits, the pin, the player and its facing, the tracked objective (every marker of a
   multi-marker stage); pan, zoom (3 levels), pad and keyboard focus over icons; "Pin here" / "Clear
   pin"; "Travel" on a waystone or shrine that is visited and whose `requires_flags` hold (any campaign
   level) → `travel_requested(level, id, "fast_travel")`, refused with GameSession's reason (aware
   enemy within 40 m, dead, grabbed, holding, a `max_stage` below the stage).
3. **Compass** (top centre, §2.14): heading strip, N/E/S/W, the tracked objective's diamonds, up to 6
   nearest discovered POIs within 600 m (unscaled), up to 3 oath leads, the pin, "?" for undiscovered
   POIs by the rules of §2.14; hidden in the title and when the HUD is off.
4. **Tracked quest**: `Quests.tracked_quest_id` (saved), `track_next()` (T / D-pad Left) cycles active
   quests; the objective marker, compass and tracker follow it; the journal lists active quests (stage,
   objective text, region), waiting ones with their `waiting_text`, completed quests, oath outcomes,
   sealed places and each region's M7 note while it exists; "Track" from the journal.

**Tests to add:** discovery once per POI with its XP, flags saved and restored; a vista reveals its
neighbours; fog flags; the map's travel refused with a reason while an aware enemy is near, for an
unvisited waystone and for a `max_stage` below the stage, and accepted otherwise (to a test level pair
and the Valley index); the compass bearings for objects in the four quadrants, its 6-POI cap, the
"?" rule and the pin; a multi-marker stage shows three diamonds; track cycling and the marker
following the tracked quest; the tracked quest survives a save and a fast travel; the journal's lists;
the HUD layout at five resolutions; pad navigation of both screens.

**Test time:** default ≤ 0.7 s; slow 0; gate 0. **Acceptance:** [M7] map, compass, pins, discovery,
fast travel, tracked quest, journal and sealed places. **Size:** ~3,300 lines.

### 3.11 P28 — World audio: region and place music and ambience, the sounds of the new peoples, creatures, engines and formations

- **Wave / lane:** W17, B, parallel with P27. **Depends on:** P19, P21, P23, P25, P30. **Milestone:**
  M7 (M8's creatures use it).
- **Goal:** the five regions and their main places sound different by data; the world reacts to the
  giant's size; formations, engines and water are audible as what they are; every enemy, engine,
  ability and UI event that M7–M9 add has its cues before it exists, named by the conventions of §2.5
  so the router finds them.

**Owned paths**
- `tools/audio/gen_{world_music,world_ambience,world_sfx}.py`, `assets/audio/{music,ambience,sfx}/world/**`
- `data/audio/{music_world_*,ambience_world_*,region_world_*,bank_world_*}.json`, additions to
  `mix_default.json` (voices for `enemy.troll`, `enemy.dire_wolf`, `enemy.cavalry`, `enemy.pikeman`,
  `enemy.shieldman`, `enemy.bannerman`, `enemy.siege_crew`, `enemy.rival_giant`, the bosses; materials
  for the new props; surfaces for the world's regions)
- Tests: `tests/integration/{test_world_audio_coverage,test_world_threat_cues}.gd`, `tests/slow/test_world_music_loops.gd`

**Hotspot edits:** `scripts/audio/cue_router.gd` and `scripts/audio/{music_director,ambience_director}.gd`
(single owner in W17): the formation aggregation (one wall cue per brace cycle), the incoming whistle
at the landing circle, the cavalry swell, the formation march emitters (at most 2, priority 75), water
footfalls and splashes from `water_at`, the diegetic gate cues, the flush reaction, the
friendly-settlement arrival (a crowd gasp and a bell once per visit for a stage ≥ 4 giant), the rout
stinger on `formation_changed(routed)`; each change recorded in the system doc.

**Design:** §4.3 (world sets with three melody variants, region combat intros, boss sets in their own
frames, place beds and overrides by POI), §4.1 (rows marked M7–M9), §4.5 (≤ 5.5 MB more). Cues for ids
that do not exist yet are validated by name only; P29–P37's coverage tests (their records resolve to
these cues) close the loop.

**Tests to add:** every region and every place POI of §4.3 resolves its set and ambience; region and
place changes in the world cross-fade; every planned voice id of §4.1's M7–M9 rows resolves; a braced
formation of 10 pikes logs one wall cue per brace cycle; a catapult shot logs its launch at the engine
and the incoming whistle at the landing circle; a stage-6 giant among fleeing soldiers keeps the music
at explore and plays no sting; wading logs `wade` footfalls and a splash; a stomp near birds flushes
them; the world loops are seamless (slow); the budget and the world's registered seconds ≤ 170.

**Test time:** default ≤ 0.3 s; slow 10 s; gate 0. **Acceptance:** [M7] the world's regions and places
have music and ambience; the M8 sound list exists. **Size:** ~3,000 lines.

### 3.12 P29 — The Crownmarch: the Kingsgate shelf and beacon, Brannock, Millford, the oaths opening, settlements and factions by data, the Crownmarch's formation fights

- **Wave / lane:** W18, A, parallel with P31. **Depends on:** P22, P25, P26, P27, P30. **Milestone:**
  M7.
- **Goal:** the first region with full content: the arrival on the shelf, the beacon, stage 4, the
  three oath leads opening together, `quest.world_main`'s stages 1–4, the sealed-Citadel quest, Brannock's
  oath with its three resolutions, the Crownmarch's side quests, encounters that threaten a stage-4
  giant (formations at the toll fort and in the Raiders' Hollow), sealed places, the toll-riders and
  Aldmere as separate factions, and the XP and equipment budgets.

**Owned paths**
- `tools/data/world/crownmarch.json` (settlements with greens, props with `faction` and
  `visible_when_flag`, markers, safe markers, triggers, patrols, signs, scenery, secrets)
- `data/world/encounter_crownmarch_*.json`, `data/world/faction_{brannock,millford,toll_riders,aldmere}.json`,
  `data/loot/{beacon_cache,oath_reward}.json`, the Kingsgate anvil's forge record
- `data/quests/{quest_world_main,quest_oath_march,quest_sealed_citadel,quest_kingsroad_toll,quest_barrow_fields,quest_millrace,quest_watch_beacon}.json`
  (the main quest's `oaths` stage names all three oath leads as `markers`; P35 and P36 ship the wood's
  and the crown's oath quests), `data/dialogue/{dialogue_edda,dialogue_reeve_tamsin,dialogue_toll_captain}.json`
- `data/tutorial/{world_arrival,stage4_humans,formations}.json`
- `data/shrines/shrine_world_*.json` (adds the `growth_requires_conditions` of §5.4 to the five world
  shrines: Kingsgate `world.kingsgate.lit`; the three stage-5 shrines a `count` of one oath flag; the
  Standing Stones a `count` of two)
- Tests: `tests/integration/{test_crownmarch_content,test_factions_world}.gd`,
  `tests/unit/{test_world_xp_budget,test_world_equipment_budget}.gd` and their helpers
  `tests/support/{world_xp,world_items}.gd` (the worst-case quest XP and the guaranteed items of a
  declared resolution path), `tests/gate/test_crownmarch_walkthrough.gd`

**Hotspot edits:** `scripts/world/faction_state.gd` (W18: the respawn blocker for hostile guards within
120 m), `scripts/world/encounter_director.gd` (anchor P29: `stand_down_when`),
`scripts/quests/quests.gd` and `quest_conditions.gd` (anchor P29: `near`),
`scripts/core/schemas/{faction,quest,dialogue}_schema.gd` (refinements at P29's anchors),
`scripts/core/game_data.gd` (anchor P29: every oath quest present has a resolution whose conditions
hold for a first oath at stage 4).

**Design:** §5.4 (the Crownmarch), §5.7 (the main thread's opening and the oaths), §5.8 (XP and
equipment budgets), §5.9, §5.10 (encounters, factions). The toll fort's pike formation and the
Raiders' Hollow's shield wall appear at stage ≥ 4; the Barrow Fields gain an ogre pair at stage ≥ 4.
Hostile settlement guards leash inside their walls.

**Tests to add:** every Crownmarch quest stage reachable and completing; at stage 4 the `oaths` stage
shows three leads (the map's three oath icons, the compass's three bearings) and Brannock's oath starts; faction
warnings, hostility, reconciliation and give-way per record; Thornwick's texts unchanged (regression);
Edda, Tamsin and the toll captain reachable at stage 6 on their greens without damage or trapping; a
respawn at `world.cp.brannock` while Brannock is hostile moves to the nearest safe checkpoint; the XP
budget (L7 at the beacon, the march oath's contribution, ≥ 50 XP of margin); the equipment budget for
every march and toll path; every encounter has a leash and its chunk; every quest marker is in the
index; every cluster of encounters within 150 m fits 12 individuals and the formation cap on both
platforms; the viewpoint draw calls after the rebuild; gate: the walkthrough (teleport-assisted) for
each of the three march resolutions.

**Test time:** default ≤ 0.4 s; slow 20 s; gate ≤ 4 min. **Acceptance:** [M7] from the crown to
Brannock's oath, every path; two formation fights at stage 4; the budgets. **Size:** ~3,500 lines.

### 3.13 P30 — Formations: the target provider, formations as lock groups, banners, the group brace, pikes and shields, the crowd renderer

- **Wave / lane:** W16, B, parallel with P25. **Depends on:** P22, P24b. **Milestone:** M7 (M8
  content).
- **Goal:** decisions 19 and 20: organised human groups that stay dangerous to stage 4–6 giants,
  read as one threat, can be broken by their banner, rout without jamming, fit the web's caps and stay
  inside the draw-call budget; and enemies that can fight people and props.

**Owned paths**
- `scripts/ai/formation.gd`, `scripts/presentation/crowd_renderer.gd`
- `data/enemies/{pikeman,shieldman,bannerman}.json`, `data/abilities/{formation_brace_pike,pike_thrust,shield_bash,banner_rally,formation_brace_shield}.json`
- `tools/builders/formations.gd`, `scenes/enemies/{pikeman,shieldman,bannerman}.tscn`, `scenes/test/formation_test.tscn`,
  `data/test/{level_formation_test,encounter_formation_test_*}.json`
- `scripts/debug/stress_scenario.gd` (W16 only: the `--stress-formations` option, 40 members on the
  formation test level)
- Tests: `tests/unit/test_formation.gd`, `tests/integration/{test_formations,test_group_lock,test_target_provider,test_crowd_renderer}.gd`,
  `tests/slow/{test_formation_perf,test_formation_rout_gate}.gd`

**Hotspot edits:** `scripts/actors/enemy_actor.gd`, `scripts/ai/enemy_brain.gd` (anchor P30: target
provider, formation slots, banner morale, roles, joining, fan-out routs), `scripts/world/encounter_director.gd`
(anchor P30: formations, `max_formation_members`, `web_formation_scale`), `scripts/actors/player/player_targeting.gd`
(anchor P30: group fold, the banner candidate, focus member, `lock_label()`),
`scripts/presentation/camera_rig.gd` (anchor P30: frame a formation's anchor),
`scripts/presentation/telegraph_visuals.gd` (anchor P30: the band telegraph),
`scripts/core/schemas/{enemy,encounter,growth_profile}_schema.gd` (anchors P30: `targets`, `role`,
`formations`, `target_rules`), `scripts/core/schemas/prop_schema.gd` (anchor P30: `prop_tags`, the
tags a target provider can name, such as `house`, `wall`, `engine`), `scripts/core/game_data.gd`
(anchor P30: formation slots and banners exist in their encounter; every encounter cluster fits the
caps on both platforms), `data/growth/growth_0{4,5,6}.json` (`target_rules: {"formation_lock": true}`),
and `scripts/actors/attack_runner.gd` (anchor P30: the `band_pulse` hit shape).

**Design:** §2.10 (target provider, formations, the banner candidate and visual, the group brace,
fan-out routs, joining, crowd renderer, web compositions); numbers in §5.11. Formation members count
against `max_formation_members` and not the 12; a formation is one encounter member list with slots;
ad-hoc lines (`_line_slot`) stay for non-formation soldiers. Morale: banner halves losses, formation
units start at 90, regroup to slots above 45 while the banner lives. Members steer to slot offsets
from the formation's one pivot path (one `NavQuery` per formation per repath).

**Tests to add:** slot grid and facing turn; banner death breaks morale for members only and emits
`banner_fell`; a braced front rank of five files applies at most one hit per brace pulse to a stage-4
giant's legs, holds one melee token and shows one band telegraph; shields block lights and break on
heavies, stomps and sweeps; group lock: one candidate per formation plus the banner, focus member is
the nearest living, release when all are dead or routed, switching from the group to the banner, a
heavy kills the banner through one rank; `lock_label()` texts; an outmatched soldier joins a formation
with a free slot within 40 m and flees otherwise; the target provider (raiders attack a house prop and
a villager, then the player when it comes); the crowd renderer's instance counts and promotions; web
scaling keeps the front rank and the banner; slow: 40 members at tier 0 (desktop budget) cost CPU p95
≤ 5 ms headless; rendered draw calls for 40 members ≤ 120 (Xvfb when available); 10 members routing
through a breached gate all clear it within 8 s.

**Test time:** default ≤ 0.7 s; slow 25 s; gate 0. **Acceptance:** [M7] formations as lock groups with
banners and group braces on the test level within budgets, ready for P29's placements. **Size:**
~3,500 lines.

### 3.14 Notes on W12–W18 pairing

Every pair above has disjoint owned paths; their shared hotspots are separated by anchors (§1.5) or by
§1.6's insertion points. P23 and P24a meet only in the web tools: P22 shipped the launcher's argument
pass-through and the `Web (test)` preset in W13, P23 owns the launcher and `build_web.sh` in W14, and
P24a only adds its own `tools/web/stream_check.mjs`. P24b and P26 meet nowhere (P26's walking tests
need only P24a's terrain; P24b edits the streamer and WorldRoot, P26 the player and the Valley). P25
and P30 meet only in `game_data.gd` (separate anchors). P27 and P28 meet nowhere (P27 owns `ui/hud.gd`,
P28 the audio scripts). P29 and P31 meet nowhere (P29 places formations and data; P31 owns the weapons'
movesets, the player's attack and motor, and the progression scripts).

### 3.15 P31 — Abilities and weapons: stage movesets, stage evolutions, talent and ancestry abilities, axes, the great pine, titanforging

- **Wave / lane:** W18, B, parallel with P29. **Depends on:** P26. **Milestone:** M8 (merged before the
  M7 gate: its stage 4–5 evolutions and stage movesets ship in the M7 play link).
- **Goal:** every weapon the player can reach lands from the giant's feet to its reach at stages 4–6,
  the library reaches 24 actives and the ultimate (decision 23), and the forge chain goes to
  titanforged.

**Owned paths**
- The stage movesets of the three Valley families (`data/abilities/{club,sword,hammer}_great_light_{1,2,3}.json`,
  `…_great_heavy.json`; the hammer's chain has two lights), the axe's
  (`axe_light_{1,2,3}.json`, `axe_heavy.json`, `axe_great_*`), the great pine's
  (`pine_light_{1,2}.json`, `pine_heavy.json`)
- `data/abilities/{titan_stomp,earthquake,crag_hurl,formation_sweep,titan_roar,shoulder_charge,cleave_of_ages,bulwark,stonewall_stance,rune_lance,primal_regrowth,storm_call,bedrock_ward,thunderhead,wild_surge}.json`,
  `data/statuses/{bulwark,stonewall,bedrock_ward,wild_surge,burning,regrowth}.json`
- `data/weapons/{axe,axe_titan,club_titan,sword_titan,hammer_titan,tree_pine}.json`, the reinforced
  weapons' `stage_movesets` and refit chains, `data/items/{titan_iron,kings_annals}.json`
- Tests: `tests/integration/{test_evolutions,test_new_abilities,test_titan_weapons,test_refit_chains}.gd`,
  `tests/slow/test_stage_reach_bands.gd`

**Hotspot edits:** `scripts/progression/progression.gd` and `scripts/actors/player/player_progression.gd`
(evolutions: learn on reaching `unlock_stage`, replace in slot, `ability_evolved`; refit chains and
forge tiers; the one-step rule lifted), `scripts/actors/player/player_attack.gd` (the `above_target`
projectile spawn for Storm Call), `scripts/actors/player/player_motor.gd` (W18: a scripted ability
`motion` for the player, Shoulder Charge's 12 m dash with a body sweep), `scripts/actors/attack_runner.gd`
(anchor P31: `line_pulse` — a row of cylinder pulses along the facing, one pulse id each, for
Earthquake), `scripts/world/projectile_system.gd` (anchor P31: `rune_lance`, `storm_bolt` visuals),
`scripts/presentation/telegraph_visuals.gd` (anchor P31: Earthquake's ground crack, Storm Call's
circle), `scripts/world/forge.gd` (`tier`), `scripts/presentation/weapon_visuals.gd` (axe and pine
meshes), `scripts/core/schemas/{action,weapon,item}_schema.gd` (anchors P31: `evolves_from`,
`granted_by`, `radius_scale`, refit steps with `forge_tier`, `perk`, visual shapes `axe`, `pine`),
`scripts/core/game_data.gd` (anchor P31: evolution chains acyclic, the base exists, an evolution's slot
equals its base's; refit chains fit-monotonic; every reachable weapon has stage movesets for 4–6),
`data/progression/progression_default.json` (the library), `data/growth/growth_0{4,5,6}.json`
(`unlocks`).

**Design:** §5.12 (the schedule and every number), decisions 23 and 24, §2.11. The stage movesets keep
the families' lights 1–2 and heavy (they land with the profile tilts, `growth_extension.md` §2.3) and
replace light 3 with a low cross-body sweep whose band starts at the capsule's contact distance;
per-stage `arc_pitch_offsets_deg` tune each band. The great pine scales with growth from stage 4
(`fit` 4–6) and is uprooted from the Greywood's great pines (P35 makes them uprootable). Axes carry
`flat_penetration` 15 and cleave a 140° arc. Titanforged perks: club — heavies deal +25 % poise to
formation members; sword — light 3 pierces a second target in line; hammer — the heavy adds a 3 m
shockwave; axe — +10 flat penetration. Thunderhead's stun is a 1.5 s stagger on humans (the existing
fixed-length stagger). Primal Regrowth (Primordial tier 3) heals over 6 s and clears slows.

**Tests to add:** each evolution learned at its stage replaces its base in the same slot and keeps a
separate cooldown; Earthquake's pulses hit along a line in order with distinct pulse ids; Rune Lance
reaches 60 m; Storm Call lands on the lock target after its telegraph; Shoulder Charge's dash moves
12 m and sweeps; slow: every reachable weapon (the reinforced club, sword and hammer, the axe, the
great pine and every titanforged form) lands lights 1–3 and the heavy on a soldier and a wolf from
contact + 0.3 m to 0.9 × reach at stages 4–6 (the M7 gate's weapon check); refit chains: base →
reinforced at an iron forge, reinforced → titanforged at a titan forge, refused with a reason
otherwise; perks apply; axes ignore 15 armour; the library has 24 actives and the ultimate.

**Test time:** default ≤ 0.6 s; slow 25 s; gate 0. **Acceptance:** [M7 for the movesets and the stage
4–5 evolutions; M8 for the rest] stage 4–6 combat lands with every reachable weapon; the library is
complete. **Size:** ~3,400 lines.

### 3.16 P32 — Siege engines, cavalry and fists: ballistae, catapults, crews, the size override, siege disruption, Rampart Grip

- **Wave / lane:** W19, A, parallel with P33. **Depends on:** P30, P31. **Milestone:** M8.
- **Goal:** the threats of a stage 5–6 giant: engines that can stagger it, crews that serve them,
  cavalry that harass its legs, and the grab family's stage 4–6 forms: the stage-6 unlock of grabbing
  and throwing engines (siege disruption, Rampart Grip) and the fists, whose third light is a grab
  finisher.

**Owned paths**
- `scripts/world/siege_engine.gd`, `scripts/actors/cavalry_enemy.gd`, `scripts/ai/cavalry_brain.gd`
- `data/props/{siege_ballista,siege_catapult}.json`, `data/enemies/{siege_crew,cavalry}.json`,
  `data/abilities/{ballista_bolt,catapult_stone,cavalry_charge,crew_reload,rampart_grip,fists_light_1,fists_light_2,fists_light_3,fists_heavy}.json`,
  `data/weapons/{fists,fists_titan}.json`
- `tools/builders/siege.gd`, `scenes/world/{siege_ballista,siege_catapult}.tscn`,
  `scenes/enemies/{siege_crew,cavalry}.tscn`, `scenes/test/siege_test.tscn`, `data/test/{level_siege_test,encounter_siege_test_*}.json`
- Tests: `tests/integration/{test_siege_engine,test_size_override,test_cavalry,test_siege_disruption,test_fists}.gd`,
  `tests/slow/test_siege_battery.gd`

**Hotspot edits:** `scripts/combat/hit_factory.gd` (anchor P32: `attacker_height_override_m`),
`scripts/actors/attack_runner.gd` (anchor P32: engine launches), `scripts/actors/enemy_actor.gd` and
`scripts/ai/enemy_brain.gd` (anchor P32: the `crew` role and the `charge` behaviour; the siege
morale debounce), `scripts/world/encounter_director.gd` (anchor P32: an encounter's `engines` list
assigns crews to engines by world id), `scripts/actors/player/player_grab.gd` (W19: the prop grab path
for `siege_disruption`, Rampart Grip's engine grab, the fists' finisher on a staggered target),
`scripts/world/projectile_system.gd` (anchor P32: `ballista_bolt`, `catapult_stone`, `engine`
visuals), `scripts/presentation/telegraph_visuals.gd` (anchor P32: the landing circle with its timer),
`scripts/presentation/weapon_visuals.gd` (W19: the fists' mesh), `scripts/core/schemas/{action,enemy,prop,weapon}_schema.gd`
(anchors P32: the override, `engine`, roles, the `fists` visual shape). The enum values it needs were
declared by P20.

**Design:** §2.10 and §5.11. Engines take the ranged tokens and launch slots; their telegraphs follow
decision 25 of M2–M5; the ballista's bolt is fast and straight (aim line, 60 m/s, size override 8 m,
poise 60), the catapult's stone arcs (circle at the landing point, splash 6 m, size override 8 m).
Crews (siege-crew soldiers, role `crew`) stay within the engine's crew radius, reload, and flee when it
breaks. At stage 6 a staggered or uncrewed engine can be grabbed with two hands (2 s hold max) and
thrown (`thrown_body` with the engine visual, P40 × 1.6, splash 5 m). Rampart Grip (evolves Crushing
Grip at stage 6) grabs small and medium actors and engines. The fists fit stage 6 and their third
light grabs a staggered target in reach (spending nothing when the grab is invalid).

**Tests to add:** an engine fires only while crewed and at most once per `reload_s`; launches at one
target stay ≥ 1.0 s apart with other ranged attackers; a bolt staggers a stage-4 giant (poise ratio
from the override) while a soldier's arrow does not; destroying an engine costs every unit within 30 m
20 morale once (two engines within 2 s: once); a stage-5 grab of an engine is refused with a reason
and spends nothing, a stage-6 grab and throw works; Rampart Grip evolves at stage 6; the fists'
finisher grabs a staggered soldier and refuses an unstaggered one without cost; cavalry charges, wheels
away and re-charges, and its charge is dodgeable; crews flee when their engine breaks; slow: a battery
of two catapults, two ballistae and a shield formation against a stage-6 giant, engines thrown.

**Test time:** default ≤ 0.6 s; slow 15 s; gate 0. **Acceptance:** [M8] siege threats, siege
disruption, fists and Rampart Grip. **Size:** ~3,400 lines.

### 3.17 P33 — Talents and ancestries: three trees, passives, the ancestry choice

- **Wave / lane:** W19, B, parallel with P32. **Depends on:** P31. **Milestone:** M8.
- **Goal:** decision 22: permanent character choices that change how the giant plays.

**Owned paths**
- `data/talents/talent_*.json` (27), `data/player/ancestry_{stoneblood,stormborn,wildheart}.json`
  (`ancestry.neutral` stays for the prologue), `data/quests/quest_ancestry.json`,
  `data/tutorial/ancestry.json`
- `scripts/progression/talents.gd` (pure: availability, costs, tiers, effects), `ui/screens/shrine/{talents_tab,ancestry_tab}.gd`,
  `ui/screens/ancestry_screen.gd`
- Tests: `tests/unit/test_talents.gd`, `tests/integration/{test_passives,test_ancestry_choice,test_talent_tab}.gd`

**Hotspot edits:** `scripts/combat/combatant.gd` (`passives`, the accessors and the pre-declared
modifier keys), `scripts/actors/player/player_progression.gd` (learn talents, grants and replaces,
apply the ancestry, `talent_learned`, `ancestry_chosen`), `scripts/actors/player/player_motor.gd` (W19:
`move_speed_mult`), `scripts/progression/character_state.gd` (talents, `ancestry_chosen` normalise),
`scripts/core/schemas/{ancestry,player,talent}_schema.gd` (anchors P33), `scripts/core/game_data.gd`
(anchor P33: talent trees and tiers valid, grants exist), `data/progression/progression_default.json`
(talent tiers' level requirements).

**Design:** §5.12 (trees, tiers, every talent's effect; ancestries). The shrine screen shows Talents
(always) and Ancestry (until chosen; after the world opens). P33 also ships `quest.ancestry`
(§5.7: starts at stage 4 while no ancestry is chosen) and a tutorial prompt at the first world shrine.
Passives are rebuilt on load, on a talent, on the ancestry, and on growth.

**Tests to add:** tier and requirement rules; points spent once; a grant learns its ability and
auto-slots it by its own slot rule; passives change `armor_total`, outgoing damage and poise, damage
taken, stamina and essence costs, cooldowns, poise threshold, grab reach, fury on kill and movement
speed exactly by the record; passives survive save and load and never show as statuses; the ancestry
can be chosen once; a migrated v1 save is offered the choice; the tabs are pad-navigable.

**Test time:** default ≤ 0.6 s; slow 0; gate 0. **Acceptance:** [M8] level 12 with talents and an
ancestry. **Size:** ~2,800 lines.

### 3.18 P34 — Trolls, rival giants and the three bosses

- **Wave / lane:** W20, A, parallel with P37. **Depends on:** P30, P32, P26. **Milestone:** M8.
- **Goal:** the larger creatures that stay dangerous at stages 4–6, and three bosses with phases that
  happen exactly once per attempt, a disengage rule, a yield protocol that cannot be broken by
  accident, web compositions, and peaceful endings where §5.13 says so.

**Owned paths**
- `scripts/actors/{troll_enemy,rival_giant_enemy}.gd`, `scripts/ai/{troll_brain,rival_giant_brain,matriarch_brain,harrok_brain}.gd`,
  `scripts/world/battle_boss.gd`, `ui/screens/yield_prompt.gd`
- `data/enemies/{troll,troll_whelp,troll_matriarch,dire_wolf,rival_giant,harrok}.json`, their
  abilities (`troll_club`, `troll_stomp`, `troll_throw_whelp`, `matriarch_*`, `giant_axe_*`,
  `giant_shoulder_charge`, `giant_boulder`, `harrok_*`, `moot_stones`), `data/statuses/troll_regen.json`,
  `data/weapons/{troll_club,giant_axe}.json`, `data/enemies/{iron_guard,corvane}.json` (the warlord and
  his guard: soldiers with roles), `data/dialogue/{dialogue_yield_corvane,dialogue_yield_harrok}.json`
- `tools/builders/big.gd`, `scenes/enemies/{troll,troll_whelp,troll_matriarch,dire_wolf,rival_giant,harrok,corvane}.tscn`,
  `scenes/test/{troll_den_test,moot_test,bailey_test}.tscn`, `data/test/` level and encounter records
- `ui/hud/boss_bar.gd` (aggregate bars, "yields" state)
- Tests: `tests/integration/{test_troll,test_rival_giant,test_battle_boss,test_matriarch,test_harrok,test_yield_protocol,test_boss_disengage}.gd`,
  `tests/gate/test_bosses_seeded.gd`

**Hotspot edits:** `scripts/actors/enemy_actor.gd`, `scripts/ai/enemy_brain.gd` (anchor P34: regen
refresh and its tint, yield, immunity on yield), `scripts/actors/attack_runner.gd` (anchor P34: a
thrown whelp is a `thrown_body` launched by an enemy; arena hazards owned by a brain),
`scripts/world/projectile_system.gd` (anchor P34: the whelp and the stones), `scripts/world/encounter_director.gd`
(anchor P34: `force_activate` for battles, the attempt reset), `scripts/presentation/telegraph_visuals.gd`
(anchor P34: hazard circles), `scripts/world/boss_arena.gd` (the disengage rule, `boss_disengaged`),
`scripts/core/schemas/{enemy,action}_schema.gd` (anchors P34: `yield_at`, `phases` additions,
`arena_hazard`), `ui/hud.gd` (the target frame hides for battle bosses).

**Design:** §5.13 (each boss's arena, phases, numbers, telegraphs, peaceful ending), §2.10. The
BattleBoss owns its encounters through the director (`force_activate`), counts the health of the
members and engines that actually spawned (desktop or web composition) for the bar, changes phase once
per attempt by the aggregate fraction, and ends in `boss_yielded` (Corvane surrenders when his guard
breaks) or `boss_defeated`. The yield protocol and the disengage rule of §2.10. The Troll Matriarch is
never grabbable (the 50 % rule; spec §8); fire comes from braziers and from burning whelps or trolls
thrown into her fire pit. Harrok's phase-2 stones are arena hazards of his brain (telegraphed circles,
two at a time, credited to Harrok, with threat cues); the watching clans are neutral and never deal
damage. Harrok yields after three poise breaks (two with Wildheart's challenge) or at 25 % health.

**Tests to add:** trolls regenerate unless burning, show the regeneration tint, and are grabbable at
stage 5, not 4; a 9 m Matriarch cannot be grabbed at stage 5 (`too_tall`, nothing spent); dire wolves
harass; rival giants sweep with weapon arcs and their charges end at stone; each boss's phases happen
exactly once per attempt; leaving the arena for 5 s resets the boss and emits `boss_disengaged(left)`,
and returning starts a new attempt; the Matriarch's drive-out ending emits `boss_disengaged(fled)` and
the music leaves the boss state; the yield protocol: Earthquake's pulses still travelling and Burning
across the yield both leave the outcome at the prompt and `spared` stays possible; only "Strike"
confirmed in the prompt kills; Harrok's stones are his and the watchers deal nothing; boss bars for
aggregates, also with web compositions; gate: ten seeded runs per boss.

**Test time:** default ≤ 0.6 s; slow 20 s; gate ≤ 8 min. **Acceptance:** [M8] three bosses and two
creature families. **Size:** ~3,500 lines.

### 3.19 P35 — The Greywood and the Drowned Steps

- **Wave / lane:** W21, A, parallel with P36. **Depends on:** P29, P31, P34, P37. **Milestone:** M8.
- **Goal:** two regions of content: Hollowmere, the Needle and the Hidden Grove, the troll den and the
  oath of the wood; the Mere of Kings, its bells, the sunken vault, the Titan's Bones and the Titan
  Forge; their wander tables and sealed places.

**Owned paths**
- `tools/data/world/{greywood,drowned_steps}.json`, `tools/world/kinds/{stilt_hut,bell,brazier,nest}.gd`
  (new kinds), `data/world/encounter_{greywood,drowned}_*.json` (replacing P25's light content),
  `data/quests/{quest_oath_wood,quest_great_pine,quest_woodcutters,quest_the_needle,quest_drowned_bells,quest_titan_bones,quest_sunken_vault}.json`,
  `data/dialogue/{dialogue_sedge,dialogue_ferrywoman}.json`, `data/world/faction_woodfolk.json`,
  `data/props/{bell,brazier,brood_nest}.json`, the Titan Forge record, `data/world/wander_{greywood,drowned_steps}.json`
  and their templates `data/world/encounter_tpl_{greywood,drowned}_*.json`, `data/tutorial/troll_fire.json`
- Tests: `tests/integration/test_greywood_drowned_content.gd`, `tests/unit/test_world_budgets_wood.gd`
  (the wood oath's resolutions through P29's helpers), `tests/gate/{test_greywood_walkthrough,test_drowned_walkthrough}.gd`

**Hotspot edits:** `docs/USABILITY_SCRIPT.md` (region notes). The regions' viewpoint draw calls and pck
share go in its system doc; the W21 merge carries them into `docs/PERFORMANCE.md`.

**Design:** §5.4, §5.7, §5.10, §5.13 for these regions. A brazier or bonfire at every troll site and a
tutorial prompt at the woodcutters' camp teach fire. **Tests:** both oath resolutions (slay, drive)
complete and set their flags, each as the first oath at stage 4 (drive: the woodfolk open the wall
once the nests burn) and with the stage-5 heave shortcut; the oath quest starts at stage 4; the Needle
fits stages 3–4 and refuses 5, and the Hidden Grove opens from the north ridge to a stage-5 heave; the
bells (stage 4 wading, the island at stage 5); the sunken vault behind the causeway's rockfall; the
Titan Forge refits to titanforged; the troll den's checkpoint lies outside the arena within 80 m;
Sedge on Hollowmere's green at stage 5–6; every encounter leashed, every marker indexed, every quest's
XP and items counted in the budgets; the viewpoint draw calls after the rebuild; the rebuild-twice
check.

**Test time:** default ≤ 0.2 s; slow 10 s; gate ≤ 3 min. **Acceptance:** [M8] two regions complete.
**Size:** ~3,200 lines.

### 3.20 P36 — Aldmere, the Stonehold and the finale

- **Wave / lane:** W21, B, parallel with P35. **Depends on:** P29, P32, P33, P34, P37. **Milestone:** M8.
- **Goal:** the kingdom's march (Fort Aldmere, the war camp, the ballista ridge, the oath of the
  crown with three resolutions, Aldmere's wary peace) and the giant territories (the Ironway, Skarn and
  its siege, the Standing Stones, the Giant's Stair, the Moot battery, the Moot, Harrok, the Stone
  Throne), their wander tables and sealed places, and the main thread's end.

**Owned paths**
- `tools/data/world/{aldmere,stonehold}.json`, `tools/world/kinds/{fortress_wall,keep,longhouse,throne}.gd`,
  `data/world/encounter_{aldmere,stonehold}_*.json` (replacing P25's light content),
  `data/world/faction_{skarn,harrok_clan}.json`, `data/quests/{quest_oath_crown,quest_deserters,quest_ballista_ridge,quest_siege_of_skarn,quest_skarn_rebuild}.json`,
  `data/quests/quest_world_main.json` (stages 5–8 and the end), `data/dialogue/{dialogue_herald,dialogue_corvane,dialogue_ulfra,dialogue_harrok,dialogue_deserters}.json`,
  the Fort Aldmere battle boss configuration (with its web composition), `data/world/encounter_crownmarch_toll_fort.json`
  (the stage-5 tower ballista), `data/world/{wander_aldmere,wander_stonehold,event_siege_of_skarn}.json`
  and their templates
- Tests: `tests/integration/test_aldmere_stonehold_content.gd`, `tests/unit/test_world_budgets_crown.gd`
  (the crown oath's resolutions, the finale and every pair of oaths; a pair whose quest record is not on
  the branch yet, `quest.oath_wood` before the W21 merge, is skipped and the merged run covers it),
  `tests/gate/{test_aldmere_walkthrough,test_stonehold_walkthrough,test_main_thread_combinations}.gd`

**Hotspot edits:** `ui/screens/end_screen.gd` (the campaign's end: "The Giant King", the oath and
champion outcomes). The regions' viewpoint draw calls and pck share go in its system doc; the W21
merge carries them into `docs/PERFORMANCE.md`.
**Cross-lane symbols:** `quest.oath_wood` and its flags (P35), reached only as data in tests that skip
when the record is missing.

**Design:** §5.4, §5.7, §5.9, §5.10, §5.13 for these regions; the main thread's end (§5.7). Aldmere
(`faction.aldmere`, `initial: neutral`) is at peace until offended; the herald meets the giant at the
war camp's edge; the fort's gate garrison stands down for a giant carrying Brannock's banner
(`stand_down_when`). The Moot battery (toll-riders) holds the plateau road to the Moot at stage 6.
**Tests:** every oath resolution of the crown (breach, sabotage, parley with each of its four
conditions), each as the first oath at stage 4 where §5.7 allows; the parley path from a "help" save
takes zero damage from the fort; the siege of Skarn (started by Ulfra's plea or a stage-6 arrival, its
timer paused beyond 200 m, the rebuild errand after `burned`); the Moot battery at stage 6 and its
engines thrown; the Giant's Stair gate at 6 and its top vista; "Enter the Moot"; the champion's three
outcomes; the fort's and the Moot's checkpoints outside their arenas within 80 m; every battle fits
the caps on both platforms; `test_main_thread_combinations` (gate tier, teleport-assisted) completes
the main thread for every ordered pair of oaths (six orders, each first oath with a resolution
available at stage 4) and for all three (on P36's branch the orders with the wood oath are skipped; the
W21 merge and the M8 gate run them all).

**Test time:** default ≤ 0.2 s; slow 10 s; gate ≤ 12 min. **Acceptance:** [M8 gate] the main thread
completes in every order of every oath pair. **Size:** ~3,500 lines.

### 3.21 P37 — The living world: wandering encounters and world events that respect streaming, the Crownmarch's table, raids and the army column

- **Wave / lane:** W20, B, parallel with P34. **Depends on:** P29, P30, P32. **Milestone:** M9 (its
  framework merges before M8 so the region packages own their tables and events).
- **Goal:** decision 27: the world moves without the player — patrols, columns, packs and raiders on
  the roads, raids on settlements to defend — without ever acting on ground that is not loaded, and
  nothing farmable.

**Owned paths**
- `scripts/world/{wander_director,world_event}.gd`, `data/world/{wander_crownmarch,event_millford_raid,event_army_column}.json`,
  encounter templates `data/world/encounter_tpl_crownmarch_*.json`
- Tests: `tests/unit/test_wander_rules.gd`, `tests/integration/{test_wander_director,test_world_events,test_event_streaming}.gd`,
  `tests/gate/test_raid_millford.gd`

**Hotspot edits:** `scripts/world/encounter_director.gd` (anchor P37: instantiate templates, `xp_scale`
on members, faction standing on spawn), `scripts/actors/enemy_actor.gd` (anchor P37: a moving
formation follows a patrol path), `scripts/core/schemas/encounter_schema.gd` (anchor P37: `template`),
`scripts/quests/quest_conditions.gd` (anchor P37: `event_done`), `scripts/core/game_data.gd` (anchor
P37: tables reference templates). The respawn blocker for an active event within 120 m registers
through `GameSession.register_respawn_blocker` (no `game_session.gd` edit). Kill XP needs no
progression change: the director sets each spawned member's `xp_reward` to the record's value ×
`xp_scale`, and the existing kill-XP path reads it.

**Design:** §2.13, §5.10 (the Crownmarch's table and its two events). Spawns only on loaded, ready
chunks, at least `min_distance_m` from the player and outside the camera's view; at most `max_active`
per table and one world event at a time; outcomes persist as flags; a template's fourth and later
spawns give no kill XP; the streaming rules of §2.13 (centre chunk loaded and the player within 200 m,
timers suspended while unloaded, reset on death, abstract columns).

**Tests to add:** spawn rules (distance, view, loaded chunks, stage filters, faction standing,
cooldowns, caps); XP decay after three spawns; the Millford raid (houses targeted; the protect
objective; fail after three houses; outcome flags; every villager under attack reaches a safe marker
on loaded ground); the raid's timer suspends while Millford's chunk is unloaded and resets on the
player's death; the army column advances unloaded, spawns when its point enters a loaded chunk and
despawns when it leaves; a respawn near an active event moves to a safe checkpoint; events never
overlap.

**Test time:** default ≤ 0.4 s; slow 20 s; gate ≤ 2 min. **Acceptance:** [M9; framework at M8] the
living world. **Size:** ~2,800 lines.

### 3.22 P38 — The world bot

- **Wave / lane:** W22, A (alone). **Depends on:** P27, P35, P36, P37. **Milestone:** M9.
- **Goal:** decision 28: a bot that plays the campaign from the Valley's crown (or `--mode=world
  --new-game`, which starts from `world_start`) to the Stone Throne under oath policies in any order,
  explores, uses the map's fast travel, measures how the world plays, and checks the stability
  invariants.

**Owned paths**
- `scripts/debug/{world_bot,bot_route,world_metrics}.gd` (WorldBot reuses BotCombat, RunMetrics and
  BotDiagnosis; ValleyBot hands over at `slice.completed` with `--bot-campaign`)
- Tests: `tests/slow/test_bot_route.gd`, `tests/gate/test_world_bot_smoke.gd`

**Hotspot edits:** `scripts/debug/{valley_bot,bot_combat,run_metrics,bot_diagnosis}.gd` (stage clamps
derived from the profile; a `--bot-campaign` hand-over; world segments), `scripts/debug/autopilot.gd`
(`--scenario=world`), `scripts/core/game_session.gd` (a bot hook to fast travel without a screen, if
`travel_to` needs one), `tools/run_bots.sh` (presets `world_assisted`, `world_balance`,
`world_stability`, `world_orders`, and the long world smoke run), `tools/bot_report.py` (world
sections).

**Design:** §6.1.

**Tests to add:** the route planner (road graph A* by stage, then local legs ≤ 250 m on the titan mask;
`direct` edges; replanning across chunk loads); gate: the smoke run from `--mode=world --new-game` to
Brannock's oath (assisted, ≤ 4 minutes of wall time); invariants of §6.1 trip on injected faults.

**Test time:** default ≤ 0.1 s; slow 20 s; gate ≤ 5 min. **Acceptance:** [M9] the bot completes the
main thread assisted in the three policy presets and in every first-oath order. **Size:** ~3,300
lines.

### 3.23 P39 — Stability, balance and how it plays

- **Wave / lane:** W23, A (alone). **Depends on:** P38. **Milestone:** M9.
- **Goal:** §6.2–§6.5: the 60-minute world stability run, the balance matrix and at most three tuning
  iterations (data only, logged), the performance captures, `docs/HOW_IT_PLAYS.md` rewritten for the
  campaign (the Valley's sections kept and re-run), `docs/BALANCE_LOG.md`, `docs/PERFORMANCE.md`,
  `tools/web/world_check.mjs` (extends `stream_check.mjs`: the world in headless Chromium — boot,
  Continue a world save fixture, fast travel, walk 60 s, streaming hitches, the audio recorder), the
  usability script's world and audio sheets extended.

**Owned paths:** data tuning across `data/` (logged), `tools/data/world/*.json` nudges (logged,
rebuilt), `tools/web/world_check.mjs`, the docs above, bot fixes that correct measurement mistakes
only.

**Acceptance:** [M9 gate] stability passed; targets met or every miss reported as a miss with its
reason. **Size:** ~1,800 lines (plus tuning).

### 3.24 P40 — Ship

- **Wave / lane:** W24, A (alone). **Depends on:** P39. **Milestone:** M9 (ship).
- **Goal:** as P18 did: the final check on the final code (every scene and the world rebuilt with no
  diff, every suite in all three tiers, `--audio`, the soak), `README.md`, `ARCHITECTURE.md` and
  `DECISIONS.md` consolidated from `docs/systems/P19–P40` and §0.3 (the spec deviations of decision 4
  and §8 recorded), `docs/M6_M9_HANDOFF.md` (spec §16's handoff items, the gate table with PASS /
  PARTIAL / FAIL / NOT RUN and evidence, the owner's open decisions: the licence and the FLAC masters),
  screenshots of the world (a world tour beside the bot, the Kingsgate shelf's view first), the Linux,
  Windows and Web exports, the Chromium checks (`audio_check.mjs`, `world_check.mjs`), version
  `0.9.0-m9`, the launcher, the pull request and the merge. **Size:** ~1,500 lines.

---

## 4. The audio design

Everything here is a design target measured by tests; nobody has listened to it (the container has no
speakers). The owner's listening pass is in the usability script (P23 writes the audio sheet in W14:
loudness balance, harshness, readability of the threat cues, music fatigue, the hidden-tab mute; P39
extends it for the world).

### 4.1 The cue map: events to sounds

The router (P19) implements every row (the M7–M9 rows connect when their signals exist); P21 makes
the M6 cues, P23 the stingers and ambience, P28 the M7–M9 cues and tests their rows. A cue name with
`<…>` is resolved by the conventions of §2.5 (voice, material, surface, size class, weapon family,
short action id) with fallbacks. Families: **A** impacts, **B** swings and movement, **C** footfalls,
**D** abilities and projectiles, **E** voices, **F** threat cues, **G** world objects, **H** UI, **S**
stingers (Music bus).

| Event or source | Condition | Cue | Where | Fam. |
| --- | --- | --- | --- | --- |
| `hit_resolved` | HIT or GUARD_BROKEN on an actor | `sfx.hit.<flesh\|armor>.<light\|heavy>` (armour when the target's armour ≥ 20; heavy for heavies, abilities and projectiles over P 50) | hit point | A |
| | on a prop | `sfx.hit.<material>` (wood, stone, iron) | hit point | A |
| | `crit` | adds `sfx.hit.crit` | hit point | A |
| | BLOCKED by the player / by an enemy's guard | `sfx.block.player` / `sfx.block.guard` | defender | A |
| | PARRIED | `sfx.parry` | defender | A |
| | GUARD_BROKEN | adds `sfx.guard_break` | defender | A |
| | IMMUNE (a prop that refuses the category or the stage; a yielded boss) | `sfx.hit.immune` | hit point | A |
| | the target is the player and loses health | adds `sfx.player.hurt` (`.heavy` from 15 % of maximum health) | player | E |
| | EVADED, IGNORED | silent (the dodge has its own sound) | | |
| `attack_clanked` | | `sfx.clank.stone` | point | A |
| `ability_started` | the player's light or heavy | `sfx.swing.<blunt\|blade\|tree\|fists\|axe>.<light\|heavy>` from the weapon family | weapon pivot | B |
| | dodge (roll at stage 1, sidestep later), block raise, jump | `sfx.dodge.<roll\|sidestep>`, `sfx.block.raise`, `sfx.jump` | player | B |
| | the player's ability | `sfx.ability.<short id>.cast` → `sfx.ability.default.cast` | player | D |
| | an enemy's attack | `sfx.voice.<voice>.attack` (+ `sfx.swing.<family>.<weight>` for weapon arcs; `sfx.cavalry.charge` swell for a charge) | attacker | E, B |
| `telegraph_started` | aimed at the player | `sfx.threat.windup.<circle\|line\|cone>` at the attacker, plus `sfx.threat.sting` when off-camera or beyond 20 m × scale and not suppressed (§2.5); a formation's band brace: one `sfx.threat.windup.wall` per formation per brace cycle; an indirect projectile: `sfx.threat.incoming` at the landing circle for the flight time | attacker / landing point | F |
| aim commit (polled: a ranged attacker passes `tracking_fraction` of its windup) | aimed at the player | `sfx.threat.aim_lock` | attacker | F |
| `area_pulse` | Footfall and its evolutions, boss slams, troll stomps | `sfx.ability.<short id>.impact` → `sfx.impact.stomp` (size pitch); a giant's stomp flushes nearby birds (`amb.birds_flush`) | centre | D |
| `ability_effect` | `sector` / `roar` / `self_buff` / `cast` | `sfx.ability.<short id>.<sweep\|roar\|on\|cast>` → `sfx.voice.<voice>.roar` for roars | actor or centre | D |
| `status_applied` / `status_expired` | the player's slow; Stone Skin, Bulwark, Bedrock Ward off; Burning on a troll; a troll's regeneration (loop while it lasts) | `sfx.status.slow`, `sfx.status.<short>.off`, `sfx.status.burning`, `sfx.troll.regrow` | entity | D |
| `projectile_spawned` | by visual: `arrow`, `bolt`, `boulder`, `thrown_body`, `ballista_bolt`, `catapult_stone`, `rune_lance`, `storm_bolt`, `engine` | `sfx.projectile.<visual>.launch` | launch point | D |
| `projectile_impact` | on the world | `sfx.impact.<visual>` | point | D |
| `entity_died` | an enemy or NPC | `sfx.voice.<voice>.death` + `sfx.body.fall.<small\|large\|huge>` | entity | E |
| | the player | `mus.stinger.death` + `sfx.player.death` (music fades) | player | E, S |
| `staggered` | | `sfx.voice.<voice>.stagger` (the player: `sfx.player.stagger`) | entity | E |
| awareness edge (polled: unaware → aware) | an enemy within 70 m × scale | `sfx.voice.<voice>.alert` (at most one per encounter per 4 s) | actor | E |
| `morale_changed` | reason `awe` | `sfx.voice.<voice>.awe` | entity | E |
| `enemy_routed` | | `sfx.voice.<voice>.flee` (at most one per encounter per 2 s) | entity | E |
| `object_stage_changed` / `object_destroyed` | structural stage / destruction | `sfx.crack.<material>` / `sfx.break.<material>.<small\|large>` (large from 3 m tall) | prop | G |
| `object_opened` | gates and doors | `sfx.world.open.<material>` | prop | G |
| `grab_started` / `grab_ended` | seize; thrown, dropped, crushed | `sfx.grab.seize`; `sfx.grab.throw`, `sfx.grab.drop`, `sfx.grab.crush` | holder | D |
| `growth_changed` | the player | `mus.stinger.growth` + `sfx.world.growth` (creak and rumble) | player | S, G |
| `growth_blocked`, a refused request (`action_rejected` for the player) | | `sfx.ui.denied` (at most one per 0.5 s) | 2D | H |
| `shrine_activated` / `shrine_rested` / `checkpoint_reached` (waystone) | | `sfx.world.shrine_wake` / `sfx.world.shrine_rest` / `sfx.world.waystone` | node | G |
| `checkpoint_saved` | `ok` | `sfx.ui.saved` | 2D | H |
| `interacted` | pickup, weapon rack, forge, uproot, talker, exit, inscription | `sfx.world.interact.<pickup\|weapon\|forge\|uproot\|talk\|exit\|inscription>` | node | G |
| `upgrade_applied` | | `sfx.world.forge_upgrade` | player | G |
| `loot_awarded`, `item_added` | | `sfx.ui.loot`, `sfx.ui.item` (`.metal` for iron and titan iron, `.quest` for quest items) | 2D | H |
| `weapon_equipped` | | `sfx.ui.equip.<family>` | 2D | H |
| `level_changed` | | `mus.stinger.level_up` | 2D | S |
| `ability_learned`, `ability_evolved`, `talent_learned`, `ancestry_chosen` | | `sfx.ui.ability_learned` (`ancestry_chosen`: `mus.stinger.ancestry`) | 2D | H, S |
| `attributes_changed`, `loadout_changed` | | `sfx.ui.select` | 2D | H |
| `quest_started` / `quest_stage_changed` / `quest_completed` | | `sfx.ui.quest_new` / `mus.stinger.quest` / `mus.stinger.quest_complete` | 2D | H, S |
| `dialogue_started` / `dialogue_outcome` | greeting / `intimidate` | `sfx.voice.<npc voice>.greet` / `sfx.voice.giant.intimidate` | NPC / player | E |
| `faction_changed` | warned / hostile / stood_down / reconciled | `sfx.voice.crowd.gasp` / `sfx.world.alarm_bell` / `sfx.voice.crowd.murmur` / `sfx.voice.crowd.cheer` | nearest member | E, G |
| `tutorial_shown` | | `sfx.ui.tip` | 2D | H |
| `lock_target_changed` (the player) | locked / released | `sfx.ui.lock_on` / `sfx.ui.lock_off` | 2D | H |
| `camera_mode_changed` | | `sfx.ui.camera` | 2D | H |
| `hud_message` | kind `warn` or `bad` | `sfx.ui.warn` | 2D | H |
| `boss_engaged` / `boss_phase_changed` / `boss_defeated` / `boss_yielded` | | the boss set after its intro stinger (+ `sfx.world.gate_iron` for an arena gate) / the phase layer / `mus.stinger.victory` / `mus.stinger.yield` | | S, G |
| `slice_completed` | | `mus.stinger.prologue_end`, then the `end` context | | S |
| screens (ScreenStack open / close; viewport focus changes; `ui_accept` / `ui_cancel` while a screen is open) | | `sfx.ui.open`, `sfx.ui.close`, `sfx.ui.move`, `sfx.ui.select`, `sfx.ui.back` (the map: `sfx.ui.map_open`) | 2D | H |
| `ActorRig.footfall` | the player | `sfx.step.giant_s<stage>.<surface\|wade>` (`.cruise` after 10 s of cruising) | player | C |
| | soldiers, archers, mages, villagers / ogres, trolls, bosses, rival giants | `sfx.step.human.<surface>` / `sfx.step.heavy.<surface\|wade>` (size pitch) | actor | C |
| `QuadrupedRig.footfall` (P22) | wolves, dire wolves, cavalry | `sfx.step.<paw\|hoof>.<surface>` | actor | C |
| **M7–M9 rows (P28)** | | | | |
| `poi_discovered` | a vista / any other | `mus.stinger.world_reveal` (the Kingsgate shelf and the Stair top) / `mus.stinger.discovery` | 2D | S |
| `region_changed`, `level_leaving`, `level_entered` | | music and ambience set changes and fades; a friendly settlement entered by a stage ≥ 4 giant: `sfx.voice.crowd.gasp` + `sfx.world.town_bell` once per visit | | E, G |
| `travel_requested` (fast travel) | | `sfx.ui.travel` | 2D | H |
| `size_gate_blocked` | | the gate's cue (`sfx.gate.water`, `sfx.gate.stone`, `sfx.gate.timber`) at the contact point | gate | G |
| `trampled` | | `sfx.trample` + `sfx.break.<material>.small` | prop | G |
| water | the player or a big enemy enters water deeper than 0.5 m | `sfx.world.splash.<small\|large>` | entry point | G |
| `formation_changed` | `braced` / `broken` / `banner_fell` / `routed` | `sfx.formation.brace` / `sfx.formation.horn_broken` / `sfx.formation.banner_fall` / `sfx.voice.crowd.flee` + `mus.stinger.rout` | anchor | E, S |
| a formation advancing | at most two | the `amb.march_loop` emitter (stomps in step and a drum) at its anchor, priority 75 | anchor | G |
| `siege_engine_fired` / `siege_engine_crewed` (false) | | `sfx.siege.<ballista\|catapult>.fire` / `sfx.voice.crowd.abandon` | engine | D, E |
| `boss_disengaged` | `left` / `fled` | back to the zone set / `mus.stinger.yield` | | S |
| `world_event_started` / `world_event_ended` | | `sfx.world.horn_alarm` at the event centre / `mus.stinger.quest_complete` when the outcome is the defended one, else silent | event centre / 2D | G, S |

Deliberately silent: `area_entered` / `area_exited`, `flag_changed`, `xp_gained`,
`xp_award_requested`, `item_removed`, `ui_screen_requested` (the screen's own open cue plays),
`encounter_activated` / `encounter_cleared` / `encounter_leashed` (the music carries them),
`morale_changed` other than awe, `healed` (Mend's cast covers it), `checkpoint_loaded`,
`reload_checkpoint_requested`, `mode_change_requested`, `dialogue_requested`, `dialogue_ended`,
`tutorial_dismissed`, `quest_abandoned`, `quest_tracked`, `wander_spawned`, `world_chunk_*`,
`sandbox_reset_requested`. The coverage test (P21) lists every `Events` signal and requires it to
appear either in the router or in this silent list; P28 re-runs it with the M7–M9 signals.

**Voices** (`audio_mix.voices`): `human` (soldiers, archers, mages, crews, pikemen, shieldmen,
bannermen, villagers; pitch varies by record), `wolf`, `dire_wolf`, `ogre`, `ogre_king`, `troll`,
`matriarch`, `giant` (rival giants, Ulfra, Harrok with a lower pitch), `horse` (cavalry), `crowd`
(group reactions), `elder` and `talker` (NPC greetings). Each voice has `alert`, `attack`, `hurt`,
`stagger`, `death`, plus `awe`, `flee` for humans and `roar` for the big ones.

### 4.2 Synthesis by family (`tools/audio/`, numpy, seeded)

| Family | Technique | Parameters that vary | M6 files (≈ s each) | World adds (P28) |
| --- | --- | --- | --- | --- |
| A Impacts | A transient click, a noise burst through a modal resonator bank (wood: inharmonic partials 180–900 Hz, fast decay; iron: 1.5–6 kHz partials, long ring, 32 kHz; stone: gritty low-mid noise; flesh: a 60–120 Hz sine thump with a pitch drop under muffled noise), an exponential envelope | material, weight (length × 1.4 and pitch × 0.8 for heavy), variant seed | 32 (0.35; 6 iron) | in "world objects" |
| B Swings, movement | Band-passed noise with a swept centre and a "whoosh" envelope; blunt = low and wide, blade = high and narrow with a ring, tree = slow, huge, with leaf rustle; dodges as cloth-and-earth slides | family, weight, speed | 14 (0.45) | in "abilities" |
| C Footfalls | A sub thump (40–90 Hz sine with a fast pitch drop) + a surface layer (soft: granular crunch; hard: short clicks and grit; wade: a low slosh) + for sizes ≥ s3 a debris tail (absent in the `.cruise` variants); paws are light double taps, hooves sharper | size class (pitch, length and low end scale with height), surface | 20 (0.35) | 20 (0.4: s4–s6, cruise, wade, hoof) |
| D Abilities, projectiles | Designed layers: stomp boom (sub + rumble grains + debris), stone grind (granular), arcane (FM with a ring modulator and a shimmer), Mend (inharmonic bell chord), roar (the giant's formant voice + a thunder rumble), Surge (roar + drum hit + rising swell), bow twang (plucked string), ballista thunk, boulder rip | per ability | 24 (0.7) | 16 (0.7) |
| E Voices | Source-filter synthesis: a glottal pulse train (Rosenberg) with jitter and shimmer, aspiration noise, 3–5 formant resonators moving between vowel targets, pitch contours per call; big voices add a subharmonic and a 30–40 Hz growl modulation; wolves are shaped noise with resonant snarls | f0 (humans 120–220 Hz, ogres 60–90, the King 45–60, giants 40–70), vowel path, length | 44 (0.6) | 36 (0.6) |
| F Threat cues | Broadband transients with a rising band-pass sweep (2 → 8 kHz) and a short tick, 0.2–0.6 s, built for localisation and kept spectrally apart from impacts | shape (circle: swelling rumble; line: rushing sweep; cone: swish; wall: a low ratcheting rumble; incoming: a rising whistle), sting, aim lock (two-tone tick) | 8 (0.4) | 4 (0.6) |
| G World objects | Impacts and creaks combined: wood splinters (many small modal grains), stone cracks and falls, gate creaks (a slowly swept resonant filter on noise), shrine chimes (additive bells), forge strikes, splashes, struck bells, alarm bells, gate cues | material, size | 26 (0.8) | 16 (0.9) + siege 8 (0.8) + formation 6 (0.8) |
| H UI | Short sine and triangle blips with fast envelopes and two-note intervals; denied = a low square buzz; map = a paper rustle | none | 20 (0.15) | 6 (0.15) |
| S Stingers | Short arranged phrases with the score's instruments (§4.3) | — | 7 (≈ 4.8 s) + 3 combat intros (5 s) + 1 boss intro (2.3 s) | 7 (≈ 4 s) + 8 intros (4 s) |
| Ambience | Beds: wind (brown and pink noise through slowly moving filters), insects (granular narrow-band chirps), leaves (high-passed noise with slow amplitude motion), murmur (many far formant grains), water (filtered noise with bubbling grains); made seamless by circular cross-fade. Spots (Ogg): birds (FM chirps with pitch contours), owls, crows, creaks, hammers, pebbles, howls | per bed and spot | 4 beds (20 s), 14 spots (1.5 s), 2 emitter loops (10 s) | 5 region beds (20 s), 6 place beds (15 s), 16 spots, 5 emitter and march loops (10 s) |

Normalisation: SFX masters peak at −6 dBFS before the per-cue `volume_db`; stingers and stems at
−3 dBFS; beds at −12 dBFS RMS. A generated cue that fails its checks (clipping, DC, a silent variant,
a loop seam above −50 dB, an SFX longer than 2 s) fails the build.

### 4.3 The score and the ambience map

**Frames.** The zone sets of the Valley and the world share one frame, `zone_96`: D dorian at 96 BPM
in 4/4, every loop 12 bars (30.0 s), so their danger and combat stems are shared and transitions
always land on a bar line. Each zone set has an exploration drone (mono), **three exploration melody
variants** (mono; each written from the set's motif, three four-bar segments long), and shares `pulse`
(the danger layer: a low frame-drum pulse and a ticking shaker), `combat_drums` and `combat_brass`.
Boss sets have **their own frames** (they cross-fade in 0.5 s after a one-bar intro stinger and share
no stems): the Ogre King a driving 104 BPM in D minor (M6), the Iron Regiment a march at 112 BPM, the
Troll Matriarch a heavy 6/8 at 84 BPM, Harrok a half-time 72 BPM in D phrygian.

| Set | Stems (shared ones in italics) | Used by |
| --- | --- | --- |
| `music.title` | `drone_ancient`, `title_theme` (horn choir) | The title (context) |
| `music.valley_calm` | `drone_calm` (warm pad), `melody_calm_a/b/c` (plucked lute), *pulse*, *combat_drums*, *combat_brass* | Giant's Hollow, Thornwick and the fields; the sandbox (context) |
| `music.valley_wild` | `drone_wild` (dark pad, wind), `melody_wild_a/b/c` (low flute), shared | The Old Wood, the Raider Quarry |
| `music.valley_ancient` | `drone_ancient` (stone choir pad), `melody_ancient_a/b/c` (slow horn), shared | The Barrow, the Ruins, Kingsfall |
| `music.boss_ogre_king` | `boss_drums` (double-time taiko), `boss_theme` (low brass ostinato), phase 2: `boss_frenzy` (strings-like saw tremolo); intro `mus.stinger.boss_ogre_king` | The Ogre King (`boss: enemy.ogre_king`) |
| `music.end` | `title_theme`, `drone_calm` | The prologue's end screen (context) |
| **World sets (P28)** | | |
| `music.crownmarch` | `drone_march` (open fifths), `melody_fiddle_a/b/c` (bowed saw), shared | The Crownmarch |
| `music.greywood` | `drone_deepwood` (dark choir), `melody_reed_a/b/c` (double reed), shared | The Greywood |
| `music.drowned_steps` | `drone_water` (glassy pad), `melody_bells_a/b/c` (struck bells), shared | The Drowned Steps |
| `music.aldmere` | `drone_martial` (brass pad), `melody_fanfare_a/b/c` (trumpet calls), shared, `snare` added to combat | Aldmere |
| `music.stonehold` | `drone_high` (wide choir), `melody_horn_a/b/c` (giant horn), shared | The Stonehold |
| `music.boss_regiment`, `music.boss_matriarch`, `music.boss_harrok` | each: a drums stem, a theme stem and a phase layer (march drums and brass; wild drums and a growl drone; giant drums and a choir), in their own frames, each with an intro stinger | The three bosses (`battle.iron_regiment`, `enemy.troll_matriarch`, `enemy.harrok`) |
| `music.campaign_end` | `title_theme`, `drone_high` (no new stems) | The campaign's end screen (context `campaign_end`) |

Settlements and landmarks keep their region's music but may set a layer override in their
`audio_region` (Brannock, Hollowmere and Skarn play explore with the melody at −6 dB and longer rests;
the Moot plays the Stonehold's drone alone until Harrok engages).

**Layers by intensity** (dB; missing = silent): explore = drone 0, melody −2 (the scheduler's choice);
danger = drone 0, melody −9, pulse −3; combat = drone −4, melody −10, pulse −5, drums 0, brass −2.
Layer changes ease over 2 beats; entering combat starts on the next beat with the zone's combat-intro
stinger (`mus.stinger.combat_<region or district set>`, once per combat); leaving combat waits 6 s,
leaving danger 8 s.

**The melody scheduler** (§2.5): one or two loops with the melody (variants chosen per four-bar
segment, rests at 15 % of segments), then one to three loops of rest; no variant more than twice in a
row; no identical phrase within 60 s; after three minutes of uneventful exploration the stems fade over
8 s and the ambience plays alone for 60–120 s, re-entering on a discovery, a zone change or danger.

**Intensity** (every 0.25 s, from state; `audio_mix.intensity`): **combat** while any hostile enemy
that counts (at least 0.3 × the giant's height, or a member of a formation, an engine crew, a boss or
a rival giant) within 35 m × scale is aware and engaged (approach, attack, recover, hold, brace), or
the player dealt or took a hit from one in the last 5 s, or a boss is engaged; **danger** while any
aware hostile that counts is within 70 m × scale (capped at 150 m), any lesser aware hostile is within
an unscaled 40 m, an active encounter with living, non-fleeing hostiles that count has the player
inside its activate radius, or a telegraph was aimed at the player in the last 3 s; else **explore**.
Fleeing and routed enemies never count.

**Transitions**: a region, district or place change switches set at the next bar of the lead stem with
a 2-bar cross-fade (15 m hysteresis inside the new zone); `boss_engaged` plays the boss's intro
stinger and cross-fades in 0.5 s; `boss_phase_changed` adds the phase layer at the next bar;
`boss_defeated` plays `victory` and returns to the zone's set at its explore layer; `boss_yielded` and
`boss_disengaged(fled)` play `yield` and return; `boss_disengaged(left)` returns at once;
`level_leaving` fades everything in 1 s; `level_entered` starts the zone's set at explore; death plays
`death` and fades the stems over 1.5 s. Pausing screens duck the music −10 dB; dialogue −6 dB.

| Music director state | Enters on | Plays | Leaves on |
| --- | --- | --- | --- |
| `silent` | process start; `level_leaving`; the player's death (after the fade); registration | nothing | a context (title, end, campaign end, sandbox) or `level_entered` |
| `context` | the title screen; the end screen (`slice_completed`, `campaign.completed`); the sandbox | the context's set, explore layers, the melody scheduler | a mode change, `level_entered` |
| `zone` (intensity `explore` / `danger` / `combat`; melody playing / resting; silence window) | `level_entered`; a zone change (bar-aligned cross-fade); `boss_defeated`, `boss_yielded`, `boss_disengaged` | the zone's set, layers by intensity, the melody scheduler | `boss_engaged`, `level_leaving`, death |
| `boss` (phase 1, 2, …) | `boss_engaged` for a boss id with an `audio_region.boss` entry | the intro stinger, then the boss set, phase layers added at the next bar on `boss_phase_changed` | `boss_defeated` / `boss_yielded` / `boss_disengaged`, death, `level_leaving` |
| stinger overlay | the stinger events of §4.1 | one stinger at a time (a higher-priority one replaces it); stems ducked −8 dB | the stinger's end (+0.5 s release) |

**Stingers** (Music bus, one-shot streams, ducking the stems −8 dB for their length): `growth` 6 s,
`level_up` 3 s, `victory` 6 s, `quest` 2.5 s, `quest_complete` 4 s, `death` 4 s, `prologue_end` 8 s,
three Valley combat intros (5 s) and the Ogre King's intro (2.3 s) (M6); `discovery` 3 s,
`world_reveal` 6 s, `yield` 4 s, `ancestry` 4 s, `crowned` 10 s, `rout` 3 s, five region combat intros
and three boss intros (P28).

**Ambience map**

| Zone | Bed | Spots | Emitters |
| --- | --- | --- | --- |
| Giant's Hollow | `amb.bed_meadow` (wind, insects) | lark, cricket burst, wind gust | — |
| Old Wood | `amb.bed_forest` (leaves, low wind) | woodpecker, owl, crow, two creaks, distant howl | — |
| Thornwick and the fields | `amb.bed_village` (murmur, hens) | dog, hammer, distant voice, cart creak | the King's Bridge river (106, 0, −20), r 60 |
| Raider Quarry, Ruins, Kingsfall, Barrow | `amb.bed_stone` (cold wind, drips) | pebble falls ×2, crow, wind whistle, distant clank | the Giantforge's fire (175, 0, −104), r 25 |
| Sandbox (context) | `amb.bed_meadow` | lark, wind gust | — |
| Crownmarch (P28) | `amb.bed_farmland` | larks, cattle, mill wheel, church-less bell | the Wend at Brannock bridge, the Millrace |
| Greywood (P28) | `amb.bed_deepwood` | troll grunt far, owl, branch crack, wind in pines | Hollowmere's pond |
| Drowned Steps (P28) | `amb.bed_lake` | water birds, lapping, distant bell, gull | shore lapping (two points) |
| Aldmere (P28) | `amb.bed_grassland` (wind in grass, far drums) | horse, smithing, orders shouted, flag snap | the war camp's forges |
| Stonehold (P28) | `amb.bed_highland` (high wind) | eagle, rockfall, giant horn far, stone hum | the Highland Falls |
| **Places (POI audio regions, P28)** | | | |
| Brannock, Millford | `amb.bed_town` (murmur, carts, a smithy) | hawker, dog, shutters | the town well |
| The war camp | `amb.bed_camp` (drums, canvas, hammers) | orders, horses, a saw | the forges |
| Skarn | `amb.bed_hearth` (the giants' hearth, deep voices) | a giant's laugh, a log split | the hearth |
| The Troll Den | `amb.bed_cave` (drips, a low breath) | a whelp's mewl, a bone rattle | — |
| The Titan's Bones | `amb.bed_bones` (wind through ribs, a low hum) | creaks of old bone | the Titan Forge (when lit) |
| The Moot | `amb.bed_moot` (wind, a choir hum) | stone hum, a distant horn | — |

### 4.4 The mix

| Bus | Level | Settings key | Holds |
| --- | --- | --- | --- |
| Master | 0 dB | `volume_master` | everything |
| Music | −9 dB | `volume_music` | stems, stingers (streams) |
| Ambience | −12 dB | `volume_ambience` | beds, emitters, march loops and spots (streams) |
| SFX | −6 dB | `volume_sfx` | every 3D cue and the player's own sounds (samples on the web) |
| UI | −10 dB | `volume_ui` | 2D interface cues |

**Priorities** (a request steals the lowest-priority, oldest voice of equal or lower priority):
100 threat cues, the player's hurt and death; 95 boss attacks and siege launches aimed at the player;
90 the player's swings, abilities and impacts; 85 parries and blocks; 80 enemy windups within 15 m;
75 formation march emitters; 70 enemy voices and attacks; 60 world objects; 50 the player's
footfalls (45 while cruising); 40 others' footfalls; 20 ambience spots. **Caps**: footfalls 6 (2 the
player's), impacts 8, swings 4, a voice 3 per archetype and 6 in all, threat cues 2, stingers 1, UI 4,
spots 2, march emitters 2; retrigger guard 40–60 ms. **Ducking** (`audio_mix.duck`): stinger → Music
−8; dialogue → Music −6, Ambience −10; pause → Music −10 (SFX and ambience pause); boss engaged →
Ambience −6; combat → Ambience −4. The player's footfalls drop 5 dB and their debris tail after 10 s
of cruising (back in combat, on stopping, landings, jumps and stomps).

**Audibility classes** (logarithmic; `max_distance` fades the last part smoothly; × distance scale
for every class marked scaled, × its square root for `sqrt`):

| Class | `unit_size` / `max_distance` (m) | Scaled | Used by |
| --- | --- | --- | --- |
| `player` | 6 / 60 (× the player's own height ÷ 3.66) | own | the giant's footfalls, swings, voice |
| `human_step` | 2 / 15 | yes | human footfalls |
| `human` | 4 / 30 | yes | human voices, weapons, small impacts |
| `impact` | 5 / 40 | yes | hits, blocks, parries |
| `wolf` | 3 / 22 | yes | wolves, dire wolves |
| `big` | 8 / 60 | yes | ogres, trolls, cavalry, engines firing, march emitters |
| `giant` | 15 / 110 | yes | rival giants, gates, big breaks, bells |
| `boss` | 30 / 220 | yes | bosses, arena gates |
| `threat` | 8 / 80 | sqrt | threat cues (carry farther, stay directional) |
| `spot` | 10 / 74 | yes | ambience spots |

Far variants (`<cue>.far`, low-passed and with less transient) exist for `big`, `giant` and `boss`
cues and play when the source starts beyond half its scaled `max_distance`.

### 4.5 Formats and budget

Per-file arithmetic (what `build_audio.py --budget` prints before encoding; rates are the briefs'
measurements: QOA by its exact formula plus 370 bytes of import per file; mono Ogg at 22.05 kHz 3.0
KB/s at q0 for melodies, 3.2 for drones, 3.5 for spots and emitters, 4.0 at q1 for percussion and boss
stems, 4.6 at q2 for stingers; stereo beds 5.5 KB/s at q0; plus 3.7 KB of headers per Ogg file and 3 %
for Godot's import):

| Kind | In the repository | Imported as | Rate, channels | M6: files × s | M6 size | World adds (P28) | World size |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SFX one-shots (≤ 2 s) | 16-bit WAV masters + `.import` | QOA (default), `PLAYBACK_TYPE_DEFAULT` | 22.05 kHz mono; 32 kHz for iron | 188 files, 94.7 s | 0.93 MB | 112 files, 69.7 s | 0.68 MB |
| Ambience spots | Ogg (q0) | Ogg, STREAM | 22.05 kHz mono | 14 × 1.5 s | 0.13 MB | 16 × 1.5 s | 0.15 MB |
| Beds | Ogg (q0) | Ogg, STREAM, `loop` from the set | 22.05 kHz stereo (place beds mono) | 4 × 20 s | 0.47 MB | 5 × 20 s + 6 × 15 s | 0.93 MB |
| Emitter and march loops | Ogg (q0) | Ogg, STREAM | 22.05 kHz mono | 2 × 10 s | 0.08 MB | 5 × 10 s | 0.20 MB |
| Drones | Ogg (q0) | Ogg, STREAM | 22.05 kHz mono | 3 × 30 s | 0.31 MB | 5 × 30 s | 0.51 MB |
| Melody variants | Ogg (q0) | Ogg, STREAM | 22.05 kHz mono | 9 × 30 s | 0.87 MB | 15 × 30 s | 1.45 MB |
| Shared danger and combat stems, title theme | Ogg (q1) | Ogg, STREAM | 22.05 kHz mono | 4 × 30 s | 0.51 MB | — | — |
| Boss stems | Ogg (q1) | Ogg, STREAM | 22.05 kHz mono | 3 × 27.7 s | 0.35 MB | 9 × 28 s | 1.07 MB |
| Stingers and intros | Ogg (q2) | Ogg, STREAM, one-shot | 22.05 kHz mono | 11 files, 50.9 s | 0.28 MB | 15 files, 60 s | 0.34 MB |
| **Total** | | | | | **3.93 MB (≤ 4.0)** | | **5.34 MB (≤ 5.5; ≤ 9.5 in all)** |

Music and ambience masters are not committed; the generators are the masters (decision 4) and
`--verify` regenerates them bit-exactly on the reference toolchain. Sizes count what ships (Ogg file
size × 1.03 and the exact QOA size `8 + 24 × ceil(frames / 5120) + 8 × ceil(frames / 20)` bytes per
channel). Compressed audio ships at about 1.3× in the web pack (base64 of data that does not gzip).
**Web sample memory**: only SFX are samples; the Valley registers at most 110 s of them (about 39 MB of
browser memory as stereo float32 at 44.1 kHz) and the world at most 170 s (60 MB; the Valley-only cues
are not registered there); the asset test checks both from the manifest, and the web check measures the
peak of registered buffers plus the copies of playing voices (cap: registered + 12 MB, i.e. 16 voices ×
a 2 s copy).

### 4.6 Tests (summary)

| Check | Where | Package |
| --- | --- | --- |
| Every `Events` signal is routed or listed silent; every record resolves its cues; every level and context maps to music or is listed silent; "missing" stays 0 in the soak and the Valley pass | integration, gate | P21, P23, P28 |
| Threat cues: windup at the attacker, sting only when off-camera or far and not suppressed, aim-lock at the commit, one wall cue per formation brace, the incoming whistle at the landing circle | integration | P21, P28 |
| The router's chains, the pool's stealing, caps and retrigger, distance classes and scaling, threat-weighted intensity | unit | P19 |
| Music: intensity state machine, layers, bar-aligned set changes, the melody scheduler (repeats, phrase gaps, rests, the silence window), boss intros and phases, stingers and ducking, contexts | unit, integration | P19, P23 |
| Ambience: beds by zone and place with hysteresis, spots, flush reactions, emitters | integration | P19, P23, P28 |
| Assets: load, samplable SFX ≤ 2 s, loops exact over two periods, stems aligned to the frame, no clipping or silence, budgets, registered seconds per level | integration (offline `mix_audio`), slow | P19, P23, P28 |
| Policies: no SAMPLE playback type, no randomizer, polyphonic or playlist streams, streams on Music and Ambience (spots included), no global or Sim RNG in audio | integration | P19 |
| Settings and focus: volumes reach the buses; focus loss mutes; pause silences SFX and ducks music; the loading gate | integration | P19 |
| Determinism: the 120 s soak with and without audio, byte-identical | gate | P19 |
| Regeneration: every master and every Ogg regenerate to the manifest's hashes | `tools/check.sh --audio` | P19 |
| The web build: sound after New Game, no music hole over 50 ms in 60 s, peak live sample bytes under the cap, the multi-part pack, no console error; on the world at the M7 gate (a region border crossed) | `tools/web/audio_check.mjs`, `stream_check.mjs` | P23, P24a, the M7 gate |
| Listening (balance, harshness, readability of threats, fatigue) | the owner, with the usability script's audio sheet | NOT RUN here |

---

## 5. The open-world design

Coordinates are metres in the world level: x from −1024 (west) to +1024 (east), z from −1024 (north,
Godot −Z) to +1024 (south), y up; "(x, z)" omits the height, which the terrain gives. Content packages
may move an element up to 30 m to fit the terrain, and record it in their system doc.

### 5.1 The world map

**The Old Kingdom**: the realm the Broken Kings once ruled, now a frontier between the human kingdom
of Aldmere, the farmers of the Crownmarch, the woodfolk of the Greywood and the giant clans of the
Stonehold. The Valley of Broken Kings lies south of its mountain rim; the crown the giant claimed in
the Barrow opens the Kings' Door, whose tunnel comes out on the Kingsgate shelf, 46 m above the
Crownmarch, with the whole kingdom in view.

```
            x: −1024        −512           0            512          1024
 z −1024  ┌──────────────── mountain rim (impassable, +160 m) ─────────────────┐
          │  STONEHOLD HIGHLANDS (plateau +70–95 m)                            │
          │   Harrok's Hall ▲   Moot battery ⚑  The Moot ◎  Stone Throne        │
          │   (−560,−720)        (−190,−640)     (0,−740)        Skarn ⌂ (440,−660)│
          │        Standing Stones ⊕ (−300,−600)   Stair top ☼  Cairnlands  Ironway top │
  z −440  ├══════════════ highland wall (40 m cliffs) ══ Giant's Stair ══ Ironway ┤
          │ GREYWOOD (+24–45 m,  │ THE DROWNED STEPS     │ ALDMERE MARCH (+24 m) │
          │ old forest)          │ (the Mere of Kings)   │  Fort Aldmere ▣       │
          │ Troll Den ☗(−760,−330)│ Bell Tower  Titan's   │  (650,−170)           │
          │ Great Pines          │ Bones ☠ (220,−260)    │ Ballista Ridge (780,20)│
          │ Hollowmere ⌂(−640,−40)│ Ancestral Circle      │  War Camp (520,120)   │
          │ The Needle ‖(−430,40) │ ⊕ island (40,−90)     │ Deserters' Mill       │
          │ Woodcutters (−420,220)│ Sunken Steps ⊕        │                       │
  z +300  ├──────────────────────┴────── Wend ~~~~~~~~~┴───── Toll Fort ▣ ──────┤
          │ CROWNMARCH (farmland +10 m)      Brannock ⌂ (60,450)  (460,330)     │
          │ Barrow Fields (−650,720)  Millford ⌂ (−380,640)   ~~~~ the Wend ~~~~→│
          │                Raiders' Hollow (−120,560)      Shepherd's Watch     │
          │        Kingsgate ⊕ (−300,770)     Broken Stair (−40,890)            │
          │      Kingsgate shelf ☼ (−300,920, +46 m)                            │
 z +1024  └──────── rim ──[Kings' Door tunnel]──────[Citadel stair]─────────────┘
                              ↓ the Valley of Broken Kings (a separate level)
```

| Region (`region.*`) | Bounds (x; z) | Base height | Identity | Recommended stage | Factions |
| --- | --- | --- | --- | --- | --- |
| `crownmarch` — The Crownmarch | −896…896; 300…896 | 10 m, rolling ±6 m | Farmland and hamlets along the river Wend; the market town of Brannock; the toll-riders' fort taxing the King's Road | 3–4 | `faction.brannock`, `faction.millford`, `faction.toll_riders` (the scouts and the toll fort) |
| `greywood` — The Greywood | −896…−320; −440…300 | 24 m, ridges to 45 m | Old forest of grey pines; the woodfolk of Hollowmere; trolls and dire wolves; a slot canyon only a small giant fits | 4–5 | `faction.woodfolk` |
| `drowned_steps` — The Drowned Steps | −320…300; −440…300 | 6 m; the Mere at 4 m | The drowned capital of the giant-kings: terraces stepping into a lake, an island circle, a sunken vault, a titan's skeleton with a forge in its ribs | 4–5 | none |
| `aldmere` — The Aldmere March | 300…896; −440…300 | 24 m; the fort's hill 60 m | The kingdom's march, wary but at peace: a stone fortress, a war camp building siege engines, a ballista ridge, cavalry pickets | 4–5 | `faction.aldmere` |
| `stonehold` — The Stonehold Highlands | −896…896; −896…−440 | 70 m, rolling to 95 m | Giant territory above a 40 m wall: standing stones, giant steadings, the Moot where clans choose a king, a hired battery barring it | 5–6 | `faction.skarn`, `faction.harrok_clan`, `faction.toll_riders` (the Moot battery) |

**Why this size.** A 2 × 2 km world (64 chunks of 256 m) keeps every crossing in minutes: edge to edge
5.1 min at stage 3's walk and 3.3–4.0 min cruising at stages 4–6 (`open_world_tech.md` §8.2; sprint
averages ×1.27). Its static world draws about 24 calls per view plus the skyline's two, and its data
fits the web budget (§5.2). The walkable interior is about 1.8 × 1.8 km (3.2 km², twenty times the
Valley) with 48 points of interest (one every 260 m on average; 9 of them sealed places), six
settlements, three boss sites, 17 waystones, 5 shrines and 13 cairns. From the Kingsgate shelf the
landmarks of every region are in view (§5.3), so the world pulls the player in before it is walked. A
bigger world (stages 7–10) is a larger grid in the same record.

### 5.2 Chunk grid, streaming and budgets

Chunk `c<x>_<z>` covers x ∈ [−1024 + 256x, −768 + 256x) and z ∈ [−1024 + 256z, −768 + 256z), x and z
in 0..7. The outer half of every border chunk is the rim (no navmesh). Regions by chunk (dominant
first): rows z0–z1 Stonehold; z2 Stonehold north of −440 and the lowland regions south of it; z3–z4
Greywood (x0–x1, west part of x2), Drowned Steps (east part of x2, x3–x4, west part of x5), Aldmere
(east part of x5, x6–x7); z5 the lowlands' south edge and the Crownmarch from z 300; z6–z7 Crownmarch.
The Kings' Door exit and the shelf are in `c2_7`, the Broken Stair in `c3_7`, Kingsgate's shrine in
`c2_7`.

Loaded chunks: 9 when standing still, up to 15 while travelling (the load ring is 1, chunks unload
only at distance 3), at most 25 in the worst zigzag; the budgets below hold for 25.

| Budget (web `low`, the worst case of 25 loaded chunks) | Value | Source |
| --- | --- | --- |
| Static world draw calls per view | ≤ 40 (terrain 1 per drawn chunk within `terrain_visibility_end_m` 700 m, scenery 2–3 per visible chunk within 220 m, merged settlement meshes, props; the skyline 2–3) and ≤ 25 more for breakable houses in a settlement view | brief §4.3: 24 with 16 chunks at 300 m scenery; P25 and the region packages re-measure at the viewpoints |
| Terrain and scenery triangles per view | ≤ 150,000 at 4 m spacing, the skyline's 20,000 included | brief §4.3 |
| Actors | 12 individual combatants (director) + formation members (40 desktop / 20 web, crowd-rendered; compositions scaled by `web_formation_scale`) | decision 19 |
| Draw calls with actors | ≤ 250 in any view (12 rigs × ~7 + 2 formations × (4 + 6 promoted × 7) + statics) | P22, P30 |
| Simulation CPU per tick | p95 ≤ 8 ms desktop (container), with ≤ 8 path queries a tick, chases capped at 120 m and tier-0 repaths throttled; the web assumed 1.3–2.2× | M5 budget; P24b's unreachable-chase test |
| Streaming work | ≤ 4 ms a frame; steps sized under about 3 ms on desktop; the navmesh load and its region add in separate frames; settlements as sub-scenes of ≤ 150 nodes; one navmesh region a frame | brief §3.3–§3.5 (a navmesh `.res` load is up to 7.4 ms on the web, a step of its own) |
| Web frames while streaming **with gameplay** (headless Chromium, indicative) | worst ≤ 45 ms, p99 ≤ 25 ms | P24a's stream check, the M7 gate, P39 (the brief's 19.6 ms had 3D off and no gameplay) |
| Navigation polygons per layer map | ≤ 45,000 with 25 chunks (lean bakes; about 17,000 in a 3 × 3 ring) | brief §5.1, §8.3 |
| Loaded margin at 16 m/s | ≥ 200 m to unloaded ground | brief §3.5 (253 m measured) |
| World load behind the loading screen | ≤ 4 s headless, ≤ 8 s web (indicative), samples registered included | P24a, P39 |
| World data (64 chunks: 16-bit chunk data ≈ 20–25 KB, three lean navmeshes with gate regions ≈ 40–45 KB on walkable chunks, chunk scenes, index, map ≈ 300 KB, skyline ≈ 200 KB) | ≤ 5.0 MB, measured by P24a/P24b on the test world and extrapolated before P25; P25 reports the real total | decision 8 |
| Save size at the end of the campaign | ≤ 200 KB (about 1,500 entries) | brief §6.5 |

### 5.3 Terrain

Heights are generated offline by `tools/world/features.gd` from `tools/data/world/world.json`, sampled
at 4 m, quantised to 16 bits (−32 … +230 m). The recipe, applied in order:

1. **Base**: the region's base height, blended over 120 m between regions with a smoothstep, plus
   seeded simplex noise (FastNoiseLite, 4 octaves, frequency 1/520, amplitude 6 m; 12 m in the
   Greywood and the Stonehold).
2. **Rim**: beyond |x| or |z| = 896 the height rises to +160 m over 128 m (slopes > 55°): no navmesh,
   blocker walls (layer 6) along the walkable edge. Notches: the **Kingsgate shelf** (a flat at +46 m,
   x −335…−265, z 900…945, cut into the rim spur; the tunnel mouth at its back (−300, 940); a 30 m-wide
   ramp of at most 16° descends 120 m from (−300, 900) to Kingsgate at (−300, 12, 780)), the Broken Stair (x
   −60…−20, z 896…940, floor 14 m) and the Wend's gap (x 896…960, z 540…580, a waterfall plane and a
   blocker).
3. **Highland wall**: a cliff band z −470…−430 from x −896 to 896 rising from the lowland height to
   +70 m (slopes ≥ 60°), cut by the **Ironway** (x 690…750: a ramp from (720, 30, −400) to (720, 70,
   −540), 18° at most, 60 m wide) and the **Giant's Stair** (x −30…30, z −520…−430: a 25° ramp with stair
   visuals; a `size_gate_6` wall at its foot, z −425, and titan gate-6 regions on the ramp).
4. **The Mere of Kings**: an ellipse centred (0, −40), radii 190 (x) × 150 (z); the shallows' bed at 1 m
   under a water plane at 4 m (3 m deep: any giant wades; humans and wolves stay out — the human and
   large navmeshes exclude water deeper than 1 m); the **deep channel**, an annulus 60–110 m around the
   island centre (40, −90), bed −8 m, with `size_gate_5` walls and titan gate-5 regions; the island
   (r 55, height 8 m) holds the Ancestral Circle; the **causeway** from (20, 60) to (40, −35), 16 m wide
   at 5 m, broken at (30, 10) by a rockfall (`heave`, stage 5) that opens a stair down into the sunken
   vault (the island is reached only through the channel).
5. **The Wend**: from the Mere's south outlet (30, 150) to (50, 300), (60, 365) (Brannock Bridge),
   (250, 420), (450, 470), (700, 520), (896, 560); 28 m wide, bed −2 m under a 4 m water plane (6 m
   deep): `size_gate_4` walls on both banks and titan gate-4 regions on the riverbed, except at
   Brannock Bridge (a 12 m stone bridge, any stage, indestructible).
6. **Roads** (flattened 14–20 m wide to the smoothed terrain, grade ≤ 12 %): the **King's Road**
   the shelf ramp → Kingsgate (−300, 780) → (−220, 710) → Millford junction (−250, 640) → (−60, 560) →
   Brannock south gate (60, 515) → through the town → Brannock Bridge (60, 365) → (200, 330) → the Toll
   Fort (460, 330) → (520, 160) → the war camp (520, 120) → (600, 0) → Fort Aldmere's gate (650, −95);
   the **Woodway** Millford (−380, 640) → (−470, 420) → the Woodcutters' camp (−420, 220) → (−540, 110)
   → Hollowmere (−640, −40); the **Mere Road** Brannock Bridge (60, 365) → (40, 170) → the Sunken Steps
   (−180, 120) and east → (220, −40) → the Titan's Bones (220, −260) → the Giant's Stair (0, −430); the
   **Ironway** Fort Aldmere (650, −170) → (720, −400) → the Ironway top (720, −540) → Skarn (440, −660)
   → (100, −680) → the Moot's foot (−70, −660) → the Moot battery (−190, −640) → the Standing Stones
   (−300, −600) → Harrok's Hall (−560, −720); the **Stair Road** the Moot's foot (−70, −660) → the
   Giant's Stair top (0, −530).
7. **Flats**: settlement pads (Brannock 180 × 150 at 10 m with its green outside the south gate;
   Millford 120 × 90; Hollowmere's pond rim and green; Fort Aldmere's hill top 200 × 170 at 60 m; Skarn
   160 × 120 at 75 m; the Moot ring r 70 at 95 m; the Kingsgate shelf).
8. **Border relaxation**: walkable cells within 8 m of a chunk border are smoothed until no slope
   crossing a border exceeds 35° (the seam trap); the builder fails and names the place if it cannot.

**The view.** The depth fog runs from 400 m to 1,800 m with a maximum of 85 % (aerial perspective, not
a wall); the camera's far plane is 2,400 m in the world; beyond the drawn chunks the skyline shows the
whole world's terrain and about twelve landmark silhouettes (Fort Aldmere and its keep, the Titan's
Bones, the Standing Stones, the Moot's ring, Brannock's walls, Hollowmere's hall, the Great Pines,
Skarn's longhouses, Harrok's Hall, the Bell Tower, the highland wall's crest, the two beacon towers).
Lit beacons (Kingsgate, Shepherd's Watch) rise as unshaded, fog-free light columns. From the shelf the
player sees, left to right, the Great Pines over the Greywood, the Standing Stones on the highland
crest, the Titan's Bones over the Mere, Brannock's walls on the Wend and Fort Aldmere on its hill.

**Scenery** (MultiMeshes per chunk, `scenery` group, faded by the preset): Crownmarch: hedgerow trees,
orchards, field strips (no collision on crops); the Greywood: grey pines and firs by Poisson-disk with
a 9 m minimum trunk spacing in walkable forest (a stage-6 capsule, 7.4 m wide, slides through),
saplings without collision, deadfall logs; the Drowned Steps: reeds, columns, broken terraces; Aldmere:
grassland, scattered oaks, field fences (trample stage 4); the Stonehold: heather, boulders, scree.
Ground colours come at run time from the surface cells (soft, hard, wet) and the region tints.

### 5.4 Regions, settlements and points of interest

Every POI is a `poi` record (P25) with a landmark element; discovery gives its XP once (P27); a vista
also reveals the POIs within its `reveals_m`. Settlements are POIs of kind `settlement` with a green
for big giants. Shrines and waystones are POIs too (kind `shrine`, `waystone`) or sit inside one, and
become fast-travel destinations once visited (`visited.<checkpoint id>`) while their index
`requires_flags` hold. Sealed places are POIs of kind `secret` with the stage they need. "Cairn" is an
Old Kings' cairn (one attribute point once, §5.12).

**The Crownmarch** (P25 skeleton and light content, P29 content)

| POI | Kind | Position | Radius / XP | What is there |
| --- | --- | --- | --- | --- |
| `poi.kingsgate_shelf` | vista | (−300, 920) | 40 / 30 | The Kings' Door tunnel mouth (`world.exit.kingsgate` at (−300, 940)) on a shelf at +46 m; `world.cp.kingsgate_shelf` (−300, 915), the world's start checkpoint and the arrival from the Valley; the first view over the Old Kingdom (reveals 600 m); `mus.stinger.world_reveal` |
| `poi.kingsgate_shrine` | shrine | (−300, 770) | 30 / 0 | `world.shrine.kingsgate` (max stage 4; growth requires `world.kingsgate.lit`); the Kingsgate anvil (an iron-tier forge, (−315, 765)) |
| `poi.kingsgate_beacon` | landmark | (−255, 750) | 30 / 20 | The beacon tower (indestructible; interact to relight once the scouts are cleared); the beacon cache (1 titan iron, 2 iron) opens with it; a skyline column when lit |
| `poi.kingsgate_statue` | secret | (−345, 790) | 25 / 20 | A toppled king's statue (heave, stage 5): beneath, a cache (2 iron) and a cairn |
| `poi.broken_stair` | exit | (−40, 890) | 40 / 30 | A rubble-sealed stair (`world.exit.broken_stair`, open when `world.citadel.breached`) to the Valley's Citadel |
| `poi.millford` | settlement | (−380, 640) | 70 / 30 | 7 houses, the mill on the Millrace, three fields; Reeve Tamsin (an open hamlet: `max_inner_stage` 6); `world.cp.millford` (−350, 600); safe markers at the mill and the barn |
| `poi.raiders_hollow` | camp | (−120, 560) | 50 / 30 | A ravine camp of raiders (Brannock's help path); a raider shield wall at stage ≥ 4 |
| `poi.barrow_fields` | ruin | (−650, 720) | 80 / 40 | Grass mounds of old giant barrows, standing slabs, wolves (an ogre pair at stage ≥ 4); a cairn |
| `poi.barrow_vault` | secret | (−690, 760) | 30 / 30 | A sealed barrow behind a rockfall (heave, stage 5): a cairn, 2 iron and the barrow-king's horn (lore) |
| `poi.brannock` | settlement | (60, 450) | 90 / 40 | A walled market town (8 m walls, x −20…140, z 385…515; 16 m gates south (60, 515) and north (60, 385); a 16 m main street); Marchwarden Edda's hall (100, 430); the giants' green outside the south gate (60, 565) with a meeting stone (`max_inner_stage` 4); the town forge (10, 470; iron tier; serves any giant the town is not hostile to); 22 houses, 8 of them breakable and the town's; `world.cp.brannock` (60, 545); safe markers in the hall and the market |
| `poi.brannock_bridge` | landmark | (60, 365) | 30 / 10 | The only stage-3 crossing of the Wend (indestructible) |
| `poi.kings_road` | waystone | (300, 330) | 25 / 10 | `world.cp.kings_road`; a cache (1 iron) |
| `poi.toll_fort` | camp | (460, 330) | 60 / 30 | The toll-riders' palisade fort (60 × 50 m; a wooden fortified gate `world.crownmarch.toll_gate`, stage 4); a watchtower; a pike formation (8 + banner) at stage ≥ 4 |
| `poi.shepherds_watch` | vista | (480, 760) | 50 / 30 | A hill with an unlit watch beacon and `world.cp.shepherds_watch`; reveals 600 m once relit |
| `poi.wend_falls` | vista | (870, 560) | 60 / 20 | The Wend leaves the kingdom through the rim; a cairn |

**The Greywood** (P25 skeleton and light content, P35 content)

| POI | Kind | Position | Radius / XP | What is there |
| --- | --- | --- | --- | --- |
| `poi.hollowmere` | settlement | (−640, −40) | 70 / 40 | 9 stilt huts round a black pond; Sedge, the woodfolk's elder (green on the pond's south shore (−610, 20); `max_inner_stage` 4); `world.cp.hollowmere` (−590, 40); safe markers in the long hut |
| `poi.greywood_shrine` | shrine | (−540, 110) | 30 / 0 | `world.shrine.greywood` (max 5; one oath) |
| `poi.the_needle` | gate | (−430, 40) | 40 / 30 | A slot canyon 5.0 m wide and 60 m long through a 45 m ridge (fits stages 3–4); `world.cp.needle` (−400, 100) |
| `poi.hidden_grove` | ruin | (−480, −10) | 40 / 60 | Beyond the Needle, or through a rockfall on the north ridge at (−500, −60) (heave, stage 5): the Old Root stone (lore, titan iron ×1), a cairn. Never missable |
| `poi.woodcutters_camp` | camp | (−420, 220) | 50 / 30 | A wrecked camp, trolls, a bonfire (fire to learn on), the Bearded Axe on a rack |
| `poi.great_pines` | landmark | (−560, −260) | 60 / 30 | Three great pines (50 m; `UprootTree` at stage ≥ 4: the pine weapon); a skyline landmark |
| `poi.troll_den` | lair | (−760, −330) | 70 / 40 | A cave-mouth bowl (r 45 m) in the north-west ridge; three brood nests and their braziers; a fire pit; the Matriarch; the back wall (−790, −350); `world.cp.troll_den` (−705, −290), outside the arena |
| `poi.old_root` | secret | (−700, 120) | 30 / 30 | A hollow under a fallen titan-tree (heave, stage 5): a cairn and 2 iron |

**The Drowned Steps** (P25 skeleton and light content, P35 content)

| POI | Kind | Position | Radius / XP | What is there |
| --- | --- | --- | --- | --- |
| `poi.mere_of_kings` | vista | (0, −40) | 150 / 30 | The lake; five sunken bells (§5.7) |
| `poi.sunken_steps` | ruin | (−180, 120) | 70 / 30 | Giant terraces stepping into the water; `world.shrine.steps` (−200, 150; max 5; one oath); `world.cp.mere_south` (40, 170) |
| `poi.ancestral_circle` | ruin | (40, −90) | 55 / 60 | The island's circle (stage 5: wade the deep channel); a bell; a cairn |
| `poi.causeway` | landmark | (30, 10) | 40 / 20 | The broken causeway and its rockfall |
| `poi.sunken_vault` | secret | (20, 30) | 30 / 40 | The drowned kings' vault under the causeway (heave the rockfall, stage 5): lore, 2 iron, a cairn |
| `poi.bell_tower` | ruin | (−200, −240) | 50 / 30 | A drowned bell tower on the north-west shore; `world.cp.bell_tower` (−180, −200) |
| `poi.titans_bones` | landmark | (220, −260) | 80 / 50 | A 120 m skeleton (a skyline landmark); the Titan Forge (titan tier) in its ribs; titan iron ×2 |
| `poi.bones_shoulder` | secret | (250, −300) | 25 / 30 | A cache on the Titan's shoulder, out of reach below stage 6: a cairn and 2 iron |

**The Aldmere March** (P25 skeleton and light content, P36 content)

| POI | Kind | Position | Radius / XP | What is there |
| --- | --- | --- | --- | --- |
| `poi.fort_aldmere` | settlement | (650, −170) | 110 / 50 | A stone fortress (12 m walls, x 560…740, z −245…−95), the main gate `world.aldmere.fort_gate` (stage 4, health 3,000, armour 50) at (650, −95), the inner bailey (120 × 90 m: the battle), the keep (650, −215), four wall ballistae, the fort forge (titan tier; opens on parley or a spared Corvane); `world.cp.fort_gate` (650, −55), outside the gate. In M7 the gate is shut and indestructible |
| `poi.war_camp` | camp | (520, 120) | 80 / 30 | Thirty tents, four engines under construction, cavalry pickets; the herald meets the giant at the camp's south edge (500, 190) |
| `poi.ballista_ridge` | camp | (780, 20) | 50 / 30 | Three ballistae on a ridge over the King's Road |
| `poi.aldmere_shrine` | shrine | (420, −40) | 30 / 0 | `world.shrine.aldmere` (max 5; one oath); `world.cp.aldmere_road` (470, 60) |
| `poi.deserters_mill` | landmark | (440, 220) | 40 / 20 | A burned mill where deserters hide; a cairn |
| `poi.ironway` | gate | (720, −400) | 50 / 30 | The foot of the Ironway; `world.cp.ironway` (700, −380) |
| `poi.kings_armoury` | secret | (600, −290) | 30 / 40 | The old kings' armoury in the fort hill's flank, behind a collapsed adit (heave, stage 5): titan iron ×1, 2 iron |
| `poi.ridge_eyrie` | secret | (810, −10) | 25 / 30 | A ledge on the ridge's cliff, out of reach below stage 6: a cairn and 1 iron |

**The Stonehold Highlands** (P25 skeleton and light content, P36 content)

| POI | Kind | Position | Radius / XP | What is there |
| --- | --- | --- | --- | --- |
| `poi.ironway_top` | vista | (720, −540) | 50 / 30 | The view over the kingdom (reveals 600 m); `world.cp.ironway_top` |
| `poi.skarn` | settlement | (440, −660) | 90 / 40 | Skarn Steading: three 40 m longhouses, chief Ulfra (a friendly giant, 12 m); Skarn's hearth-forge (titan tier; opens when Skarn is saved or rebuilt); `world.cp.skarn` (400, −600) |
| `poi.standing_stones` | shrine | (−300, −600) | 50 / 40 | A ring of twelve stones (a skyline landmark); `world.shrine.stones` (max 6; two oaths); the Stones' gift (1 titan iron) on growing to stage 6 |
| `poi.cairnlands` | waystone | (120, −580) | 40 / 20 | Cairn fields; `world.cp.cairnlands`; a cairn |
| `poi.giants_stair` | gate | (0, −475) | 50 / 30 | The stair from the Mere's north shore to the plateau (stage 6); shown on the map as a shortcut once the player is at stage 6 |
| `poi.stair_top` | vista | (0, −530) | 30 / 30 | The Stair's head: a stage-6 view over the Mere (reveals 600 m); a cairn |
| `poi.harroks_hall` | settlement | (−560, −720) | 70 / 40 | The rival clan's steading |
| `poi.moot_battery` | camp | (−190, −640) | 60 / 30 | The toll-riders' siege company, hired by Harrok's clan to bar rival giants from the Moot: 2 catapults, 2 ballistae, crews and a shield formation, at stage 6 |
| `poi.the_moot` | boss | (0, −740) | 80 / 60 | The ring of giant stones (r 60 m; its gate stones at (−45, −690) are a `size_gate_6`), the Stone Throne (0, −800); `world.cp.moot_foot` (−70, −660), outside the ring |

That is 48 POIs (15 + 8 + 8 + 8 + 9), 9 of them sealed places, 5 world shrines and 17 waystones
(`world.cp.kingsgate_shelf`, `millford`, `brannock`, `kings_road`, `shepherds_watch`, `hollowmere`,
`needle`, `troll_den`, `mere_south`, `bell_tower`, `aldmere_road`, `fort_gate`, `ironway`,
`ironway_top`, `cairnlands`, `skarn`, `moot_foot`). The thirteen world cairns: Kingsgate's statue,
the Barrow Fields, the barrow vault, the Wend Falls, the Hidden Grove, the old root, the Ancestral
Circle, the sunken vault, the Titan's shoulder, the deserters' mill, the ridge eyrie, the Cairnlands,
the Stair top (eight behind size gates); the Valley's vault holds the fourteenth.

### 5.5 Routes and size gates

| Gate | Where | Kind | Who passes | Message and cue | Purpose |
| --- | --- | --- | --- | --- | --- |
| The Kings' Door | Valley, the Barrow's north cliff (−55, −186) | prop opened by `slice.completed` + `LevelExit` | everyone after the crown | "The door of the First King opens only for the one who wears his crown." (stone) | The prologue's exit |
| The Citadel Gate | Valley, (190, −60) | structural prop, `min_growth_stage` 4 (exists) | stage ≥ 4 | "Fortified gates can be breached at stage 4." | Revisit: the Citadel's hoard and the Broken Stair |
| The First King's vault | Valley, the Barrow (−80, −175) | rockfall, `heave` | stage ≥ 5 | "It will not move. Grow to stage 5." (stone) | A stage-5 Valley reward |
| The Wend's deep reach | the Wend except Brannock Bridge | `size_gate_4` walls, titan gate-4 regions | stage ≥ 4 wades | "Too deep to wade. Grow to stage 4, or cross at Brannock Bridge." (water) | A river only a big one crosses |
| The Toll Fort's gate, Fort Aldmere's gate | (460, 355), (650, −95) | structural props, stage 4 | stage ≥ 4 | as the Citadel (timber; stone) | Fortified gate breach (spec §9) |
| Fences, field walls, palisades | the Crownmarch and Aldmere | `trample_stage` 4 | stage ≥ 4 walks through | — (they break; never an offence) | The world grows small |
| The Needle | (−430, 40) | geometry (5.0 m) | stages 3–4 | "Too narrow. You have outgrown the Needle." (stage ≥ 5, an `Area3D` sign) | A pass only a small giant fits; the Hidden Grove's second key is a stage-5 rockfall |
| Rockfalls, toppled statues, the den's back wall | Kingsgate's statue, the barrow vault, the north ridge, the old root, the causeway, the kings' armoury, the den (−790, −350) | props with `requires_permission: heave` (stage 5) | stage ≥ 5 (the den's wall also opens to the woodfolk, §5.7) | "It will not move. Grow to stage 5." (stone) | Heave obstacles and sealed places |
| Ledges | the Titan's shoulder, the ridge eyrie | interactables with `requires_stage` 6 | stage 6 | "Out of reach. Grow to stage 6." | Sealed places for the biggest giant |
| The Millrace dam | (−360, 560) | structural prop, `min_growth_stage` 4 | stage ≥ 4 smashes it | "The boulder will not budge. Grow to stage 4." (stone) | A first stage-4 errand |
| The Mere's deep channel | the annulus round the island | `size_gate_5`, titan gate-5 regions | stage ≥ 5 wades | "The channel is too deep. Grow to stage 5." (water) | Island access |
| The Giant's Stair | (0, −425) | `size_gate_6` at the foot, titan gate-6 regions | stage ≥ 6 | "Each step is taller than a house. Only a giant of the old height can climb the Stair." (stone) | A cliff only a big one crosses; a shortcut from the Mere |
| The Moot's gate stones | (−45, −690) | `size_gate_6`, titan gate-6 regions | stage ≥ 6 | "The clans admit only a giant of the old height to the Moot." (stone) | The finale |
| The Ironway | (720, −400 … −540) | open road | every stage | — | The Stonehold's long way (Skarn, the Standing Stones) for stage 5 |

### 5.6 The Valley's exits, revisits and the Citadel (P26)

- **The ending changes, not the slice.** `quest.main` ends at the crown exactly as today and
  `slice.completed` is set (with the P17a completion checkpoint); the end screen becomes "Prologue
  complete — the Valley of Broken Kings" with its summary and **Continue** (default) and **Quit to
  title**. Continue closes the screen; the tracker shows `quest.world_main`'s first stage, "Step
  through the Kings' Door".
- **The Kings' Door**: a 14 m wide, indestructible door prop in the Barrow's north cliff (`barrow_n`,
  x −62…−48 cut, z −200…−186), `open_when_flag: slice.completed`; a `LevelExit`
  (`valley.exit.kings_door`, prompt "Step through the Kings' Door", radius 8) in front of it at
  (−55, 0, −182) → `world.cp.kingsgate_shelf`. A new waystone `valley.cp.kings_door` (−55, 0, −165) is
  the arrival point when the world sends the player back (the world's `world.exit.kingsgate`
  interaction).
- **The Citadel**: the citadel block (x 191…200) and the keep become a hall cut through the cliff (x
  191…208, z −85…−35, 30 m tall; the east edge cliff is moved out to x 208…218 there). Inside: the Hoard
  of the Broken Kings (pickups: titan iron ×2, `item.kings_annals`), 150 XP on entering (an area with a
  once-reward), and `valley.exit.citadel_stair` (prompt "Climb the Citadel stair") → the world's
  `world.exit.broken_stair` checkpoint. Breaching the gate sets `world.citadel.breached`, which also
  opens the world side's rubble door. `quest.sealed_citadel` (P29) starts at stage 4 and points there.
- **The First King's vault**: behind a heave rockfall in the Barrow (−80, −175), near the Kings' Door: a
  cairn, 2 iron and lore, so a stage-5 giant finds the tutorial valley smaller and changed.
- **Revisits at stages 4–6.** The Valley was built for stages 1–3: its respawn points have clearance up
  to stage 6, but its routes do not (`growth_extension.md` §2.2). P26 measures every Valley checkpoint
  at stages 4, 5 and 6 (clearance, camera, a capsule-swept path or a fast-travel route to an exit) and
  writes each one's `max_stage`; the map refuses travel to a checkpoint above its limit and a respawn
  there moves to the nearest allowed one (`valley.cp.kings_door` at any stage). Expected limits:
  `valley.cp.kings_door` 6, `valley.cp.ruins_gate` 6 (the Citadel is 70 m away), `valley.shrine.kingsfall`
  4, `valley.cp.barrow_gap` 4, the Hollow's, the Grove's, Thornwick's shrines and the forest road
  waystone 3 (the measured values replace these). In the Valley the bot paths on the giant layer
  (`player_nav_fallback` 4) and only walks the Kings' Door ↔ Citadel route at stage 4 (P26's slow test).
- **Valley encounters on revisits**: cleared encounters never respawn (as today); the boss is dead;
  uncleared ones still spawn with their own members (soldiers are awed at stage 4: they flee).

### 5.7 The main thread and the side quests

All quests keep `prototype_pacing: true`. XP below counts quest XP only (kills, discoveries and props
are extra). "Bot" is the stage's `bot` hint (P38).

**`quest.world_main` "The Crown Unclaimed"** (`start_conditions`: `slice.completed`, evaluated on
every pass, so a loaded finished save starts it; P29 writes stages 1–4, P36 stages 5–8):

| # | Stage | Objective | `complete_when` | Marker | XP | Bot |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `kings_door` | Step through the Kings' Door behind the crown altar | `level_is` `level.world` | `valley.marker.kings_door` | 100 | `travel` `valley.exit.kings_door` |
| 2 | `beacon` | Relight the Kingsgate beacon | flag `world.kingsgate.lit` (the beacon's interaction, possible once `encounter.crownmarch_kingsgate_scouts` is cleared; lighting it opens the beacon cache and a short scene names the three powers) | `world.marker.kingsgate_beacon` | 250 (`xp_floor_level` 7) | `fight_encounter`, then `interact` |
| 3 | `grow4` | Grow at the Kingsgate Shrine | `stage_at_least` 4 | `world.marker.kingsgate_shrine` | 80 | `grow` |
| 4 | `oaths` | Win the oaths of two of the three powers of the Old Kingdom | `count` n 2 of flags `oath.march.done`, `oath.wood.done`, `oath.crown.done` | `markers`: Brannock's green, Hollowmere's green and the war camp's edge (three diamonds), until an oath quest is tracked | 150 (`xp_floor_level` 11) | the oath quests in the policy's order |
| 5 | `grow6` | Grow to stage 6 at the Standing Stones | `stage_at_least` 6 | `world.marker.standing_stones` | 100 | `grow` |
| 6 | `moot` | Enter the Moot | `entered` `world.area.moot` | `world.marker.moot_gate` (the Stair shows on the map as a shortcut from the Mere) | 100 | `travel` |
| 7 | `champion` | Answer Harrok the Unbowed's challenge | flag `boss.harrok.outcome` (any) | `world.marker.moot_ring` | 300 | `duel` (policy) |
| 8 | `throne` | Take the Stone Throne | flag `world.throne.claimed` | `world.marker.stone_throne` | 200 | `interact` |

On completion `campaign.completed`, the campaign's end screen ("The Giant King": the oaths' and the
champion's outcomes, time, deaths), and free roaming continues. In the M7 build only Brannock's oath
exists, so the main thread waits at `oaths` until M8 adds the other two; the world stays open, the
other two leads point at their regions, and the journal's region notes say what M8 adds.

**`quest.ancestry` "The Blood of the Old Kings"** (P33): starts at stage 4 when no ancestry has been
chosen; one stage, "Choose your ancestry at a shrine" (`ancestry_chosen`, marker: the nearest
visited shrine, XP 30, bot `choose_ancestry`). It is not part of the main thread, so the M7 build
(which has no ancestry screen yet) never blocks on it.

**The oaths** (each starts at stage 4 in the world, completes with `oath.<x>.done` and
`oath.<x>.outcome`, gives the oath reward (1 titan iron and 2 iron) on every resolution, and carries
`xp_floor_level` 9 on its final stage; worst-case quest XP 800 each). Every oath has a resolution
available as the first oath at stage 4 (decision 26):

| Quest | Region, start | Stages and resolutions | First oath at stage 4 | XP (worst / best path) | Consequences |
| --- | --- | --- | --- | --- | --- |
| `quest.oath_march` "The Marchwarden's Peace" (P29) | Crownmarch; stage 4 | `meet` Edda (50; on the green at stage ≥ 5) → `resolve`: **help** = break the toll fort's gate and garrison (150) and clear the Raiders' Hollow (150), then return (650); **intimidate** (stage ≥ 4 dialogue) = Brannock pays tribute (750); **force** = smash Brannock's south gate (50; the town turns hostile) then the oath "by fear" (700) | all three | 800 / 1,000 | help: one free reinforcement at the town forge, Brannock's banner (`item.brannock_banner`, a parley token), guards friendly, the giant's banner on the gates; intimidate: 2 iron tribute, the tribute pile at the gate, the forge serves; force: the town hostile (forge shut, militia wanderers, its guards leash inside the walls, the south gate stays broken) until reconciled (2 iron at Edda) |
| `quest.oath_wood` "The Blight of the Greywood" (P35) | Greywood; stage 4 | `meet` Sedge (50; on the green at stage ≥ 5) → `resolve`: **slay** the Troll Matriarch (750); **drive** = burn the three brood nests (3 × 50; fire from the den's braziers, or a whelp or troll thrown into the fire pit and then at a nest) and open the den's back wall — the woodfolk pull it down 20 s after the third nest burns, or a stage-5 giant heaves it at once — then drive her below 60 % so she flees through it (600); Stormborn's bargain with Sedge has the woodfolk open the wall at once | slay, drive | 800 / 800 | slay: the woodfolk's feast (2 attribute points, once); drive: the den becomes a wander spawn for a troll pack; either: the woodfolk friendly, Hollowmere's hut lights lit |
| `quest.oath_crown` "The Warlord's Wall" (P36) | Aldmere; stage 4 | `meet` the herald at the war camp's edge (50; Aldmere at peace) → `resolve`: **breach** Fort Aldmere's gate (stage ≥ 4, 100) and break the Iron Regiment (the battle boss) — Corvane yields: spare (650) or strike (650) in the prompt; **sabotage** = wreck the war camp's four engines and the Ballista Ridge's three (2 × 150; Aldmere turns hostile) and the army withdraws (450); **parley** (needs a token: Brannock's banner, the deserters' word, Stoneblood blood or stage ≥ 5; greyed with its reason otherwise) = walk to the fort's gate, whose garrison stands down for a giant with a token once the herald has accepted, and swear the peace with Corvane (750) | breach, sabotage, parley with the deserters' word or Stoneblood | 800 / 800 | breach (spared): Corvane's garrison neutral, the fort forge opens, Aldmere's wanderers stop; breach (struck): the garrison flees, wanderers become remnants; sabotage: fewer patrols, Aldmere hostile; parley: Aldmere allied, the fort forge opens, Aldmere's flags struck at the toll fort |

**Side quests**

| Quest | Region | Start / steps | XP | Reward |
| --- | --- | --- | --- | --- |
| `quest.sealed_citadel` | Valley | stage 4 → breach the Citadel Gate → enter the hall | 150 (+150 on entering) | titan iron ×2, the Kings' Annals, the Broken Stair shortcut |
| `quest.kingsroad_toll` | Crownmarch | the toll-riders' captain demands tribute from passers: pay 1 iron, intimidate (stage ≥ 4), or breach the gate (counts for `oath_march` help) | 150 | the King's Road free; 2 iron (breach) |
| `quest.barrow_fields` | Crownmarch | Tamsin's shepherds lost sheep to wolves in the Barrow Fields: clear the pack and its barrow-warden ogre | 120 | an old giant's arm-ring (trophy), 1 iron |
| `quest.millrace` | Crownmarch | a boulder dams the Millrace: smash it aside (stage 4) | 100 | Millford's thanks (1 iron; the reeve's dialogue), Millford rest at its waystone |
| `quest.watch_beacon` | Crownmarch | relight Shepherd's Watch after clearing its squatters | 80 | the watch's view (reveals 600 m), a skyline column, a cache |
| `quest.great_pine` | Greywood | uproot a great pine (stage ≥ 4) | 100 | the pine weapon |
| `quest.woodcutters` | Greywood | clear the woodcutters' camp of trolls (the bonfire teaches fire); take the Bearded Axe | 150 | the axe |
| `quest.the_needle` | Greywood | reach the Hidden Grove (the Needle at stages 3–4, or the north ridge's rockfall at stage 5) | 100 | titan iron ×1, lore, a cairn |
| `quest.drowned_bells` | Drowned Steps | ring the five sunken bells: (−150, −60) and (130, 20) in the shallows, (−60, −170) on the north shore, (190, −120) in a deep pool (stage 4), the island's (stage 5) | 200 | the Stoneknuckle gauntlets (fists) |
| `quest.sunken_vault` | Drowned Steps | heave the causeway's rockfall (stage 5) and walk the drowned kings' vault | 100 | lore, 2 iron, a cairn |
| `quest.titan_bones` | Drowned Steps | climb into the Titan's ribs; light the Titan Forge | 150 | titan iron ×2, the Titan Forge |
| `quest.deserters` | Aldmere | deserters hide in the burned mill: spare them (they give their word for a parley, mark the war camp's engines and give 1 iron from their pay chest) or hand them to the war camp (2 iron) | 120 | a parley token and marks, or iron |
| `quest.ballista_ridge` | Aldmere | silence the ridge's three ballistae | 150 | counts for sabotage |
| `quest.siege_of_skarn` | Stonehold | Ulfra's plea at Skarn (stage ≥ 5), or arriving at Skarn at stage 6: Aldmere's siege line (the world event) shells the longhouses; break it (siege disruption at stage 6 is the intended way; engines can also be broken by blows); its fail timer pauses while the player is more than 200 m from Skarn | 300 | Ulfra's oath of support (Harrok's talk ending), titan iron ×1, Skarn's hearth-forge |
| `quest.skarn_rebuild` | Stonehold | after `burned`: lift the fallen roof beams back onto two longhouses (stage 6) | 100 | Ulfra's support (no titan iron) |

### 5.8 The XP and equipment budgets (prototype pacing; P29 writes the tests and their helpers, P35 and P36 add their oaths' tests)

Levels by cumulative XP (the existing table): L6 1,000 · L7 1,350 · L8 1,750 · L9 2,200 · L10 2,700 ·
L11 3,250 · L12 3,850. The XP test counts only quest XP of mandatory stages (without the
`xp_floor_level` lifts, which only add), the worst resolution of each oath, and the discoveries a
mandatory path cannot avoid (the POIs whose radius covers a mandatory objective's marker: the
Kingsgate shelf 30, the oath's settlement 30–40, the Standing Stones 40, the Moot 60), starting from
`world_start` (the Valley's worst outcome), and requires at least 50 XP of margin at every gate.

| Gate | Guaranteed XP (worst case) | Needed | Margin |
| --- | --- | --- | --- |
| The Valley's end (force) = `world_start` | 1,050 | L6 | — |
| `kings_door` 100, the Kingsgate shelf 30, `beacon` 250 | 1,430 | ≥ 1,350 (L7: stage 4) | 80 |
| `grow4` 80 (the ancestry quest's 30 is optional and not counted) | 1,510 | — | — |
| After any one oath (800 + its settlement's discovery ≥ 30) | 2,340 | ≥ 2,200 (L9: stage 5) | 140 |
| After any two oaths (+ 830) and the `oaths` stage (150) | 3,320 | ≥ 3,250 (L11: stage 6) | 70 |
| `grow6` 100, the Standing Stones 40, `moot` 100, the Moot 60, `champion` 300, `throne` 200 | 4,120 | ≥ 3,850 (L12) | 270 |

A typical player leaves the Valley at level 5–6 (`growth_extension.md` §5.1) and gains kill XP, side
quests and discoveries, so stages come earlier than the floor; the shrines' oath conditions keep stage
5 after the first oath and stage 6 after the second whatever the level, and the milestone floors
(`xp_floor_level`) make sure a level never holds the thread.

**The equipment budget** (`tests/unit/test_world_equipment_budget.gd`, decision 32) counts the iron and
titan iron a path guarantees (the `world_start` inventory, the beacon's cache, every oath's reward,
the Standing Stones' gift, the guaranteed resolution rewards) minus the costs a declared path pays (the
toll), for every oath-policy path and order:

| Gate | Worst path's iron / titan iron | Needed | Check |
| --- | --- | --- | --- |
| `world_start` | 1 / 0 | — | — |
| The beacon (+2 / +1) | 3 / 1 | reinforce (2 iron) at an iron forge on the path (the Kingsgate anvil) | → 1 / 1 after |
| The first oath (+2 / +1; the toll paid: −1) | 2 / 2 | titanforge one weapon (2 titan iron + 2 iron) at a titan forge reachable without a second oath (the Titan Forge, at stage 4) | → 0 / 0 after |
| The second oath (+2 / +1) and the Standing Stones (+1 titan iron) | 2 / 2 | a second titanforging | → 0 / 0 after |

Optional sources are extra and never missable: the Citadel's hoard (2 titan iron), the Titan's Bones
(2), the Hidden Grove (1), the kings' armoury (1), Skarn saved (1), the third oath (1), and the caches
and sealed places (about 20 iron). In M7 (no titan forge yet) the test checks the reinforcement only;
P35 and P36 add the titanforging rows with their forges.

### 5.9 Choices and consequences

| Choice | Peaceful options | Violent options | What changes in the world (flags and what shows on site) |
| --- | --- | --- | --- |
| Brannock's oath | help (protect the March from the toll-riders and the raiders), intimidate (stage ≥ 4: the town pays tribute) | force (break the south gate: the oath by fear) | `oath.march.outcome`; `faction.brannock.{allied,tribute,hostile,reconciled}`; the forge; Brannock's banner; militia wanderers when hostile; on site: the giant's banner on the gates (allied), a tribute pile (tribute), the broken south gate (force); cheering or murmuring crowds |
| The Greywood's oath | drive the Matriarch out (burn the nests, open the back wall) | slay her | `oath.wood.outcome`; `boss.matriarch.outcome` (`slain` / `fled`); a troll pack wander entry when she fled; Hollowmere's lights lit |
| The crown's oath | parley (a token, the herald's acceptance), sabotage (engines only are required), breach and spare Corvane | breach and strike Corvane | `oath.crown.outcome`; `boss.corvane.outcome`; Aldmere's wander entries stop (parley, spared) or thin (sabotage) or turn to remnants (struck); the fort forge (parley, spared); Aldmere's flags struck (parley) |
| The Toll Fort | pay 1 iron or intimidate | breach the gate | `faction.toll_riders` at the fort: `stood_down` or the fort broken |
| The deserters | spare (their word for a parley, the engines marked, 1 iron) | hand them over (2 iron) | `quest.deserters` outcome; the sabotage path's markers |
| The siege of Skarn | break the engines (no crews need die: engines can be thrown or smashed); rebuild after a loss | kill the column | `event.siege_of_skarn.outcome`; Ulfra's support (Harrok's talk ending), Skarn's forge; burned longhouses stay burned until rebuilt |
| Harrok | **talk** (stage 6, all three oaths, Skarn saved or rebuilt: he kneels without a fight), **honour duel** (break his poise three times or bring him to 25 %: he yields; the prompt offers Spare) | choose Strike in the prompt: he rises and fights to the death | `boss.harrok.outcome` (`yielded_talk` / `spared` / `slain`); the crowning: the clans attend (spared, talk) or the Moot is empty and Harrok's clan becomes hostile wanderers (slain) |
| Settlements anywhere | — | two offences within 30 s against a faction (blows on its people, damage to its houses by blows, abilities or trampling) turn it hostile (decision 17 of M2–M5, by faction record) | `faction.<f>.hostile`; its guards fight and leash inside its walls; its forge shuts; its waystone stays usable but a respawn there moves away while its guards are near; reconciliation (a price or an errand at its talker) sets `reconciled` and reopens it |

The end screen names every outcome. Nothing is farmable: every reward is a once-flag; repeated
dialogue grants nothing; wander spawns stop paying kill XP after their third (decision 27).

### 5.10 Encounters, scaling and the living world

**Rules.** No stat scaling by the player's stage: ordinary humans never become durable (spec §2). The
player's stage changes *who comes* (spawn entries' `min_stage` / `max_stage`) and *how they fight*
(awe, formations, engines). Every world encounter has a leash (≤ 70 m; a settlement's guards leash
inside its walls) and its chunk (§2.8). Budgets: 12 individual combatants, formation members
separately (40 desktop, 20 web; `web_formation_scale` 0.7 on every encounter with formations), and
every cluster of encounters within 150 m fits both on both platforms (a GameData test, P30 and P29).
Members of a faction spawn with its standing: Aldmere's are neutral (in HOLD, watching) until the
giant offends Aldmere; the toll-riders' are hostile.

| Encounter (`encounter.*`) | Centre | Members by stage | Leash | Owner |
| --- | --- | --- | --- | --- |
| `crownmarch_kingsgate_scouts` | (−240, 730) | 4 toll-rider soldiers + 1 archer (hostile) | 50 | P29 |
| `crownmarch_road_wolves` | (−150, 700) | 4 wolves (stage ≤ 4) | 50 | P29 |
| `crownmarch_raiders` | (−120, 560) | 5 raiders (soldiers, `loot.raider`) + 2 archers + 1 mage; stage ≥ 4: a raider shield wall (8 + banner) and an ogre instead of two raiders | 55 | P29 |
| `crownmarch_toll_fort` | (460, 330) | 6 soldiers + captain (commander) + 2 archers on the tower; stage ≥ 4: a pike formation (8 + banner); stage ≥ 5: a tower ballista (P36) | 45 | P29, P36 |
| `crownmarch_barrow_wolves` | (−650, 720) | 5 wolves + an ogre barrow-warden; stage ≥ 4: a second ogre | 55 | P29 |
| `crownmarch_watch_squatters` | (480, 760) | 3 soldiers + 1 archer | 40 | P29 |
| `crownmarch_brannock` (folk, guards) | (60, 450) | 8 villagers, Edda (talker), 6 guards + 2 wall archers (faction `brannock`, neutral; guards leash 60 m) | — (not budgeted while neutral) | P29 |
| `crownmarch_millford` | (−380, 640) | 6 villagers, Reeve Tamsin, 2 militia (faction `millford`) | — | P29 |
| **M7 light content (P25; replaced by P35 and P36 in M8)** | | | | |
| `greywood_woodway_wolves` | (−480, 380) | 4 wolves | 50 | P25 → P35 |
| `greywood_camp_bandits` | (−420, 220) | 4 soldiers + 1 archer (stage 3–4), 2 ogres (stage ≥ 5) | 50 | P25 → P35 |
| `drowned_bell_robbers` | (−200, −240) | 4 soldiers + 2 mages | 50 | P25 → P35 |
| `drowned_bones_scavengers` | (220, −260) | 2 ogres | 60 | P25 → P35 |
| `aldmere_road_wolves` | (560, 200) | 4 wolves | 50 | P25 → P36 |
| `aldmere_ridge_bandits` | (780, 20) | 4 toll-rider soldiers + 2 archers | 50 | P25 → P36 |
| `stonehold_ironway_wolves` | (720, −560) | 5 wolves | 50 | P25 → P36 |
| `stonehold_cairn_ogres` | (−100, −560) | 3 ogres | 60 | P25 → P36 |
| **M8 content** | | | | |
| `greywood_woodcutters` | (−420, 220) | 2 trolls | 50 | P35 |
| `greywood_dire_pack` | (−520, −100) | 4 dire wolves | 60 | P35 |
| `greywood_den_guard` | (−700, −280) | 2 trolls + 2 whelps | 50 | P35 |
| `greywood_troll_den` | (−760, −330) | the Troll Matriarch (`arena: true`) + 2 whelps | arena | P35 |
| `greywood_pines` | (−560, −260) | a troll + 2 whelps | 50 | P35 |
| `greywood_hollowmere` | (−640, −40) | 7 woodfolk, Sedge (faction `woodfolk`) | — | P35 |
| `drowned_bell_robbers` | (−200, −240) | 4 soldiers + 2 mages | 50 | P35 |
| `drowned_bones_scavengers` | (220, −260) | 2 ogres + a troll | 60 | P35 |
| `drowned_island_warden` | (40, −90) | a rival giant warden (9 m) + 2 dire wolves (stage ≥ 5) | 50 | P35 |
| `drowned_steps_pack` | (−180, 100) | 3 dire wolves | 50 | P35 |
| `aldmere_road_patrol` | (440, 140) | stage 3: 5 soldiers + archer; stage ≥ 4: a pike formation (8 + banner) + 2 archers (neutral until Aldmere is offended) | 60 | P36 |
| `aldmere_war_camp` | (520, 120) | a shield formation (10 + banner), 4 crews at 4 engines (2 catapults, 2 ballistae), 4 cavalry, 2 archers (neutral until offended) | 70 | P36 |
| `aldmere_ballista_ridge` | (780, 20) | 3 ballistae + 6 crews + a shield formation (8 + banner) | 50 | P36 |
| `aldmere_fort_gate` | (650, −80) | 2 wall ballistae, 4 wall archers, a pike formation (10 + banner) before the gate (stage ≥ 4); stands down for a parley token (`stand_down_when`) | 60 | P36 |
| `aldmere_iron_regiment` (the battle boss's encounters) | (650, −160) | §5.13 | arena | P34 (mechanics), P36 (data) |
| `aldmere_deserters` | (440, 220) | 4 deserters (neutral) | — | P36 |
| `stonehold_ironway_scouts` | (720, −560) | a rival giant scout + 2 dire wolves (stage ≥ 5) | 60 | P36 |
| `stonehold_cairn_trolls` | (−100, −560) | 3 trolls | 60 | P36 |
| `stonehold_moot_battery` | (−190, −640) | stage 6: 2 catapults, 2 ballistae, 6 crews, a shield formation (8 + banner) (toll-riders, hostile) | 70 | P36 |
| `stonehold_harrok_hall` | (−560, −720) | 2 rival giants (hostile until the duel's outcome; neutral after `spared`) | 60 | P36 |
| `stonehold_skarn` | (440, −660) | Ulfra (talker giant) + 3 clan giants (neutral NPCs) | — | P36 |
| `stonehold_moot` | (0, −740) | Harrok (`arena: true`) + 6 clan giants watching (neutral, never damaging) | arena | P36 |

(The Crownmarch's encounters use the archetypes that exist in W18, formations included; dire wolves,
cavalry and trolls reach its roads through the wander tables of W20–W21.)

**Wandering tables** (`max_active` 2 per region, one every 60–120 s, 120–220 m away, out of view, on
roads unless noted; xp after three spawns of an entry: 0; P37 owns the Crownmarch's, P35 and P36
their regions'):

| Table | Entries (weight; stages) |
| --- | --- |
| `wander.crownmarch` (P37) | toll-rider patrol (3; 3–4), raider band (2; 3–4), wolf pack (2; 3), dire wolf pack (2; ≥ 4), Aldmere pike column on the King's Road (2; ≥ 4; neutral while Aldmere is at peace, gone after parley or spared), cavalry pair (1; ≥ 5, while Aldmere is hostile), a toll-rider siege train (1; 6: 2 catapults with crews and a shield formation), Brannock militia (3; while `faction.brannock.hostile`) |
| `wander.greywood` (P35) | dire wolf pack (3; ≥ 4), troll pair (2; ≥ 4), troll pack (2; ≥ 5, when `boss.matriarch.outcome` = fled), woodfolk hunters (neutral, 1) |
| `wander.drowned_steps` (P35) | ruin robbers (2; 3–4), ogre pair (2; ≥ 4), dire wolves (2; ≥ 4) |
| `wander.aldmere` (P36) | pike column (3; ≥ 4), cavalry squadron (2; ≥ 4), siege train (1; ≥ 5: 2 catapults and crews, a shield formation; at stage 6 always offered), remnants (3; when Corvane was struck); all neutral while Aldmere is at peace |
| `wander.stonehold` (P36) | rival giant scout (2; ≥ 5), troll pack (2; ≥ 5), toll-rider siege train (1; 6), Harrok's clan giants (2; when Harrok was slain) |

**World events** (at most one at a time; each starts only with its centre chunk loaded and the player
within 200 m, suspends its fail rule while that chunk is unloaded, and resets on the player's death):

| Event | Trigger | What happens | Outcomes |
| --- | --- | --- | --- |
| `event.millford_raid` (P37) | stage 3–5, 10 minutes after the last raid, at most twice | 6 raiders + an archer target Millford's houses and villagers (target provider); villagers run to the mill's and the barn's safe markers; a protect objective (fails when 3 of 5 houses fall) | `defended` (100 XP the first time, villagers' thanks) / `fell` (two houses stay burned; the reeve's dialogue changes) |
| `event.army_column` (P37) | stage ≥ 4, Aldmere hostile and `oath.crown` not parley or spared, every 15 minutes | a pike formation and 4 cavalry march from the toll fort to Fort Aldmere along the King's Road and back (a path parameter while unloaded; spawned only on loaded ground) | `broken` / `passed` (no reward beyond kills) |
| `event.siege_of_skarn` (P36) | Ulfra's plea accepted (stage ≥ 5), or arriving at Skarn at stage 6 | Aldmere's siege line (3 catapults, 2 ballistae, crews, a pike and a shield formation, 4 cavalry) bombards Skarn's longhouses (target provider on props tagged `house`); the fail timer pauses beyond 200 m | `saved` (all engines broken before 2 longhouses fall) / `burned` (Ulfra's support lost until `quest.skarn_rebuild`) |

### 5.11 The new enemies' numbers (initial tuning; P39 tunes)

| Role | Height / radius | Health / armour / poise | Speed walk / run, turn | Attacks (P, windup / active / recovery; telegraph) | Morale and tactics |
| --- | --- | --- | --- | --- | --- |
| Pikeman (`role` pike) | 1.8 / 0.35 | 220 / 20 / 50 | 1.4 / 3.4, 200 | the formation's brace (one band attack per formation: 50, 0.8 / 0.15 / 0.8; a band along the front rank, 6.0 m deep; size override 5.0 → poise 45 on the legs; one hit per target per pulse; one melee token), thrust 35 (0.6 / 0.15 / 0.6) | 90 in formation; banner halves losses; holds its slot; the formation braces when the giant is within 6 m of the front rank |
| Shieldman (`role` shield) | 1.8 / 0.4 | 260 / 35 / 60 | 1.3 / 3.0, 180 | shield bash 30 (0.55 / 0.15 / 0.6); a 180° frontal guard with 80 guard stamina (lights blocked; heavies, stomps and sweeps break it); a shield wall's brace as the pikes' at 30 | as pikes; covers the pikes' flank |
| Bannerman (`role` banner) | 1.8 / 0.35 (a 7 m pole, a 2.5 × 1.8 m flag) | 260 / 20 / 50 | 1.4 / 3.4 | rally (every 10 s: +10 morale to members within 15 m) | the formation's commander, its own lock candidate; its death is `commander_died` for every member |
| Siege crew (`role` crew) | 1.8 / 0.35 | 180 / 10 / 30 | 1.6 / 3.6 | crew reload | stays within 4 m of its engine; flees when it breaks |
| Ballista (prop engine) | 3.2 tall | 900 / 30 | turn 30°/s | bolt 90 (1.6 s windup with an aim line, 60 m/s, range 20–140 m, size override 8.0, poise 60, reload 6 s) | fires only while crewed; ranged token and launch slot |
| Catapult (prop engine) | 4.0 tall | 1,100 / 25 | turn 20°/s | stone 110 (2.0 s windup, circle r 6 at the landing point with the incoming cue, arc, range 40–180 m, size override 8.0, poise 70, reload 9 s) | as the ballista |
| Cavalry | 2.6 / 0.9 | 400 / 20 / 80 | 4 / 13, 120 | charge 60 (1.0 s windup, line, a gallop swell; 14 m/s for ≤ 40 m; body sweep; size override 4.0), lance 40 (0.7 / 0.15 / 0.6) | harass: charge, wheel away 30–50 m, re-charge; flees at 25 morale |
| Dire wolf | 1.8 / 0.6 | 260 / 10 / 60 | 3.5 / 9, 480 | bite 30 (0.5 / 0.1 / 0.5), lunge 45 (0.7 / 0.25 / 0.9; line) | pack flanking; harass when outmatched |
| Troll | 5.5 / 1.4 | 1,100 / 20 / 160 (×3.5 in recovery) | 2.4 / 5.0, 90 | club smash 70 (1.1 / 0.2 / 1.2; super armour; circle r 4.5), sweep 60 (1.0 / 0.2 / 1.1; cone 130°) | regenerates 12 hp/s unless Burning (a green pulse and a wet regrowth sound while it does); ignores fear; grabbable from stage 5 (two hands); every troll site has a brazier or bonfire |
| Troll whelp | 3.5 / 0.9 | 400 / 10 / 70 | 2.6 / 5.5 | swipe 35 (0.7 / 0.15 / 0.7) | throwable by the Matriarch and by a stage ≥ 4 giant |
| Rival giant | 9–11 / 2.0–2.4 | 2,400 / 30 / 220 (×3.5) | 3 / 6.5, 120 | axe combo 60 / 70 (0.9 / 0.2 / 0.6 → 0.7 / 0.2 / 0.9; cone; blockable), overhead chop 100 (1.4 s; line 14 m; unblockable), shoulder charge 80 (1.0 s; line until stone; 2.5 s recovery against stone), boulder throw 70 (1.3 s; circle r 5) | can yield (record `yield_at`); titan mask 240; never grabbable |

### 5.12 The progression schedule

**Abilities** (24 actives and the ultimate; the slot is the base's for evolutions):

| Ability | Source | Unlock | Slot | Cost / cooldown | Effect (initial tuning) |
| --- | --- | --- | --- | --- | --- |
| Heavy Footfall, Sweeping Blow, Stone Skin, Crushing Grip, Boulder Hurl, Runic Bolt, Ancestral Mend, Thunder Roar (8 actives); Titan Surge (the ultimate) | the Valley | as today | 1–8, U | as today | stage-scaled radii and ranges of §2.9 |
| Titan Stomp | evolves Heavy Footfall | stage 4 | 1 | 24 stamina / 8 s | cylinder r = 0.9 × melee reach, P 40 × 1.5, poise 40, knocks humans down |
| Earthquake | evolves Titan Stomp | stage 6 | 1 | 35 stamina / 14 s | `line_pulse`: 6 pulses along 30 m ahead (0.12 s apart), P 40 × 1.4 each, poise 50; telegraphed for the player as a ground crack |
| Crag Hurl | evolves Boulder Hurl | stage 4 | 5 | 18 stamina / 6 s | range 45–60 m by stage, P 40 × 2.0, splash 4 m, `siege` category (breaks engines) |
| Formation Sweep | evolves Sweeping Blow | stage 5 | 2 | 24 stamina / 8 s | sector 160° at 1.2 × reach, P 40 × 1.3, poise 45, −10 morale per member hit |
| Titan Roar | evolves Thunder Roar | stage 5 | 8 | 30 essence / 14 s | r 15 m (13 at stage 5 scaled), morale −30, slow 30 % 4 s; unlocks the roar dialogue lines |
| Rampart Grip (P32) | evolves Crushing Grip | stage 6 | 4 | 25 stamina / 12 s | grabs `small`, `medium` actors and engines; crushes small ones, throws the rest |
| Shoulder Charge | Destroyer tier 2 | L8 | free slot | 22 stamina / 9 s | a 12 m dash with a body sweep, P 40 × 1.4, poise 60 |
| Cleave of Ages | Destroyer tier 4 | L10 | free slot | 30 stamina / 12 s | sector 180° at reach, P 40 × 2.2, `flat_penetration` 20 |
| Bulwark | Guardian tier 2 | L8 | free slot | 20 essence / 16 s | 5 s: frontal hits ×0.4, no knockback |
| Stonewall Stance | Guardian tier 4 | L10 | free slot | 30 essence / 22 s | 6 s: poise immune, damage taken ×0.6, speed ×0.7 |
| Rune Lance | Primordial tier 2 | L8 | free slot | 20 essence / 6 s | a 60 m piercing arcane projectile, P 40 × 1.6 (Intellect) |
| Primal Regrowth | Primordial tier 3 | L9 | free slot | 25 essence / 18 s | heals 20 % of maximum health over 6 s and clears slows |
| Storm Call | Primordial tier 4 | L10 | free slot | 40 essence / 16 s | a lightning strike on the lock target after a 1.2 s telegraph (circle r 6), P 40 × 2.4 lightning, sets Burning on trolls |
| Bedrock Ward | Stoneblood signature | on choosing it | free slot | 25 essence / 20 s | 8 s: armour +40, poise threshold +50 |
| Thunderhead | Stormborn signature | on choosing it | free slot | 30 essence / 14 s | cylinder r 8, P 40 × 1.4 lightning, a 1.5 s stagger on humans (the existing fixed-length stagger) |
| Wild Surge | Wildheart signature | on choosing it | free slot | 20 stamina / 25 s | +30 fury, speed ×1.15 for 6 s |

**Talents** (27; one point per level from level 2; tiers open at L6 / L8 / L9 / L10 / L12; the
capstone costs 2):

| Tree | Tier 1 (L6) | Tier 2 (L8) | Tier 3 (L9) | Tier 4 (L10) | Tier 5 (L12) |
| --- | --- | --- | --- | --- | --- |
| **Destroyer** (melee, grabs, stagger) | Heavy Hands: `heavy_damage_mult` 1.10, `outgoing_poise_mult` 1.05 · Iron Grip: `grab_reach_add` 1.5, `throw_damage_mult` 1.15 | Shoulder Charge (ability) · Bone Breaker: `outgoing_poise_mult` 1.10 | Relentless: `stamina_cost_mult` 0.85 · Juggernaut: `poise_damage_taken_mult` 0.85 | Cleave of Ages (ability) · Bloodied Fury: `fury_on_kill_add` 6 | Titan's Wrath: `outgoing_damage_mult` 1.08 |
| **Guardian** (protection, poise) | Stone Hide: `armor_flat` 15 · Steady Stance: `poise_threshold_add` 25 | Bulwark (ability) · Tireless: `stamina_cost_mult` 0.9 | Unyielding: `damage_taken_mult` 0.92 · Grounded: `elemental_resist_add` 0.10 | Stonewall Stance (ability) · Protector: `heal_received_mult` 1.2 | Mountain's Heart: `health_add` 250 |
| **Primordial** (magic, fury) | Runic Mind: `essence_cost_mult` 0.85 · Kindled: `fury_gain_mult` 1.2 | Rune Lance (ability) · Quick Runes: `cooldown_mult` 0.95 | Primal Regrowth (ability) · Wellspring: `essence_add` 40 | Storm Call (ability) · Regrowth: `heal_received_mult` 1.15 | Worldsong: `magic_damage_mult` 1.15 |

**Ancestries** (chosen once at a shrine after the world opens; `ancestry.neutral` stays the prologue's):

| Ancestry | Attributes | Passives | Signature | Dialogue tags |
| --- | --- | --- | --- | --- |
| Stoneblood | Constitution +3, Endurance +2 | `armor_flat` 10, `poise_threshold_add` 20 | Bedrock Ward | `stone` (the Moot's elders, Skarn, Aldmere's founding oath: a parley token) |
| Stormborn | Intellect +3, Willpower +2 | `essence_add` 30, `elemental_resist_add` 0.10, `magic_damage_mult` 1.10 | Thunderhead | `storm` (the woodfolk's druids: Sedge's bargain) |
| Wildheart | Strength +3, Dexterity +2 | `fury_gain_mult` 1.25, `stamina_add` 20, `move_speed_mult` 1.05 | Wild Surge | `wild` (Harrok's clan: the duel shortens to two poise breaks) |

**Weapons and refits** (decision 24)

| Family | Base (where; fits) | Reinforced (2 iron at an iron forge; fits 6; the stage 4–6 moveset) | Titanforged (2 titan iron + 2 iron at a titan forge; fits 6) | Notes |
| --- | --- | --- | --- | --- |
| Club | start (2) | ×1.15 | ×1.35; perk: heavies deal +25 % poise to formation members | light 3 at stages 4–6 is a low cross-body sweep from the feet |
| Sword | the ruins' armory (2) | ×1.10 | ×1.30; perk: light 3 pierces a second target in line | |
| Hammer | the quarry (2) | ×1.35 | ×1.55; perk: the heavy adds a 3 m shockwave | two lights and a heavy |
| Axe | the Woodcutters' camp (fits 6, ×1.25, with its moveset) | — | ×1.50; perk: +10 flat penetration | `flat_penetration` 15; a 140° cleave |
| Fists (Stoneknuckles, P32) | the drowned bells (fits 6, ×0.9, with its moveset) | — | ×1.10; perk: grab reach +1.5 m | the third light grabs a staggered target in reach |
| Tree | the oak (stage 3 only, ×1.4); the great pine (stages 4–6, scales, ×1.5) | — | — | `TreeWeapon` tag |

Titan iron: the beacon's cache 1, each oath 1, the Standing Stones 1 (the mandatory path: 4 with two
oaths); the Citadel's hoard 2, the Titan's Bones 2, the Hidden Grove 1, the kings' armoury 1, Skarn
saved 1, the third oath 1 (optional: up to 12 in all, six titanforgings). Forges: iron tier — the
Valley's two, the Kingsgate anvil, Brannock's (while the town is not hostile); titan tier — the Titan
Forge (lit by `quest.titan_bones`, reachable at stage 4), Fort Aldmere's (parley or a spared
Corvane), Skarn's hearth (Skarn saved or rebuilt).

### 5.13 The bosses

Every boss: phases exactly once per attempt (ten seeded runs, gate tier), no unseen instant damage,
every attack with a windup of 0.8 s or more telegraphed, threat cues, a waystone outside the arena
within 80 m of its edge, the arena's exit open before engagement, the disengage rule (leave the arena
radius + 20 m for 5 s: the boss returns home at full health and its first phase, `boss_disengaged`),
and no boss can be grabbed (spec §8, stage 7).

**1. The Iron Regiment and Warlord Corvane** (Fort Aldmere's inner bailey, 120 × 90 m; stage 4–5; a
`BattleBoss`, boss id `battle.iron_regiment`; checkpoint `world.cp.fort_gate`). The boss bar is the
aggregate health of what spawned (members, engines and Corvane: about 13,700 on desktop and about
12,300 with the web composition at the initial tuning). Entering the bailey after the gate breach
closes the inner portcullis behind the giant (a safe exit before).
- **Phase 1 "The Wall"** (100 % → 60 %): a pike regiment (10 + banner; 7 + banner on the web) and a
  shield wall (10 + banner; 7 + banner on the web) advance in step and brace (one band attack each);
  two wall ballistae fire (line telegraphs, aim lines). Lock groups make each formation one target and
  each banner another; Formation Sweep (stage 5) breaks ranks; felling a banner breaks its formation's
  morale.
- **Phase 2 "The Charge"** (≤ 60 %): six cavalry charge from the stables in pairs; all four ballistae
  fire; surviving formations regroup on their banners.
- **Phase 3 "The Last Stand"** (≤ 25 %): Corvane (2.0 m, health 600, a rally aura) and six Iron Guards
  hold the keep's steps. When the guard breaks or Corvane falls below 30 %, he **yields**
  (`boss_yielded`): the yield protocol (§2.10) — he is immune, earlier hits are discarded, the prompt
  offers Spare or Strike (`boss.corvane.outcome`).
- Each phase change happens once per attempt (`phase_entered` flags reset by a disengage), is announced
  by a horn and a music layer, and never spawns units inside the giant's footprint.

**2. The Troll Matriarch** (the Troll Den, a bowl r 45 m with three brood nests and their braziers and
a fire pit at its centre; recommended stage 5, possible at 4; checkpoint `world.cp.troll_den`). 9 m,
health 3,200, poise 220 (×3.5 in recovery), armour 25, regenerates 25 hp/s unless Burning. She cannot
be grabbed (9 m is 61 % of a stage-5 giant; spec §8).
- **Phase 1** (> 50 %): club sweep (cone 140°, P 60, 1.0 s, blockable), stomp (circle r 7, P 70,
  1.2 s, unblockable), whelp throw (a whelp as a `thrown_body` at the giant, P 40, 1.1 s, line).
- **Phase 2** (≤ 50 %): a 1.5 s roar calls three whelps; a frenzy combo (two sweeps); regeneration
  40 hp/s. Breaking a brazier within 8 m of her sets her Burning for 8 s; a whelp or troll thrown into
  the fire pit comes out Burning, and thrown at her sets her Burning for 10 s (300 damage on impact).
- **Drive-out ending**: the three nests burned and the back wall open (the woodfolk, a heave, or
  Sedge's bargain), then brought below 60 %: she flees through it (`boss.matriarch.outcome` = `fled`,
  `boss_disengaged(fled)`).

**3. Harrok the Unbowed** (the Moot's ring, r 60 m; stage 6; checkpoint `world.cp.moot_foot`). A 15 m
rival giant: health 5,000, poise 300 (×3.5 in recovery), armour 35, a giant axe.
- **Phase 1**: axe combo (two hits, cone, blockable, P 70 / 80), overhead chop (line 18 m,
  unblockable, P 120, 1.4 s), shoulder charge (line, until the ring's stones, then a 2.5 s punishable
  recovery), boulder throw (circle r 6).
- **Phase 2** (after two poise breaks or at ≤ 50 %): stones fall into the ring — arena hazards of
  Harrok's brain, credited to him (two telegraphed circles at a time, threat cues; the watching clans
  only cheer and never deal damage) — and an axe frenzy (three-hit combo).
- **Honour**: after the third poise break (the second with Wildheart's challenge) or at ≤ 25 % he
  kneels (`boss_yielded`); the yield protocol's prompt decides: Spare (`spared`, the duel won) or
  Strike (he rises and fights to the death, `slain`). The talk ending (stage 6, all three oaths, Skarn
  saved or rebuilt) skips the fight.

### 5.14 How stages 4, 5 and 6 change play (spec §2)

| Aspect | Stage 4 (10.97 m, L7) | Stage 5 (14.63 m, L9) | Stage 6 (18.90 m, L11) |
| --- | --- | --- | --- |
| Interactions | Fortified gate breach (the Citadel, the Toll Fort, Fort Aldmere); wading the Wend; trampling fences and palisades; the Millrace dam; grabbing ogres two-handed and whelps; humans awed on sight, so intimidation is the natural way with towns, whose folk now give way and whose talkers meet the giant on the green from stage 5; the pine weapon; every reachable weapon's stage moveset; Titan Stomp, Crag Hurl | Formation Sweep; heaving rockfalls, statues and the den's wall (sealed places open); wading the Mere's channel to the island; grabbing trolls (and throwing them into the Matriarch's fire pit); Titan Roar; the Needle refuses | Siege disruption: grab and throw ballistae and catapults (the Moot battery, siege trains, the siege of Skarn); climbing the Giant's Stair; entering the Moot; ledges in reach; Earthquake; Rampart Grip; the honour duel with a giant |
| Reach | Stage movesets ≈ 8.6 m with light 3 from the feet; Titan Stomp r ≈ 7.7 m; Crag Hurl 45 m; lock 55 m | ≈ 11 m; Formation Sweep 13 m wide arc; Titan Roar 13 m; lock 65 m | ≈ 13.6 m; Earthquake 30 m; Crag Hurl 60 m; lock 80 m |
| Positioning and traversal | Main roads, greens and 16 m streets; houses at the knee; the Needle still fits (4.4 m of 5.0); camera 15.5 m | Too big for the Needle (the Grove's ridge rockfall instead); forests along wide rides (9 m trunk spacing); settlements met on their greens; camera 19.5 m | Fort walls reach the hip; the Stair; camera 23.5 m; the world is small around the giant and the whole kingdom is in view from the Stair top |
| Body | +450 health, +30 stamina | +600, +40 | +800, +50 |
| Enemy tactics | Single humans flee on sight (awe at 6.1×); formations hold with banners and brace as one band at the legs; ballistae and archers keep range and take positions the camera can see; dire wolves replace wolves; trolls, half the giant's height, fight toe to toe | Formations brace in ranks and lose a banner to one sweep; outmatched soldiers join formations; siege crews switch to catapults; trolls flank in pairs; rival giant scouts fight with weapons and charges | Armies rely on engines and massed formations; humans otherwise rout (fanning out); giants are the only equals |
| Music and sound | Lone humans no longer raise combat music; formations and big creatures do | as stage 4; engines' incoming whistles mark their landing circles | Fleeing armies sound triumphant (the rout stinger); footfalls cruise softer on long walks |

### 5.15 Pacing (human targets; prototype pacing)

| # | Segment | Content | Human target (min) | Range |
| --- | --- | --- | --- | --- |
| 0 | The Valley (prologue) | unchanged, plus the Kings' Door (skippable on a later New Game) | 26 | 20–30 |
| 1 | The opening | The Kingsgate shelf's view, the scouts, the beacon, stage 4, the anvil, the ancestry, the map, compass and fast travel lessons | 10 | 7–14 |
| 2 | The first oath | Brannock (the toll fort, the Raiders' Hollow, or the assembly), or the Greywood, or Aldmere | 20 | 10–30 |
| 3 | The second oath | another power | 25 | 18–35 |
| 4 | Growth to 5, roaming | stage 5, the Drowned Steps, sealed places, side quests, optionally the third oath | 15 | 0–40 |
| 5 | The Stonehold | stage 6, the Ironway or the Stair, Skarn, the Moot battery, the Moot, Harrok, the throne | 24 | 15–32 |
| | **Main path after the Valley** | | **≈ 94** | **60–140** |
| | **With side quests and exploration** | about 16 side quests, 48 POIs, 13 cairns, 9 sealed places | **≈ 170** | |

Travel: hub to hub is 500–900 m (60–100 s cruising at stage 4); visited waystones make every hub a
loading screen away.

---

## 6. Test, balance and ship plan

### 6.1 The world bot (P38)

**Commands** (headless, `--fixed-fps 60`, deterministic streaming with navigation async off):

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --save-dir=user://bot_saves \
  --mode=world --new-game --scenario=world --autoplay=7200 \
  --bot-oaths=march:help,wood:drive,crown:parley --bot-champion=spare|slay|talk \
  --bot-skill=novice|expert [--bot-assist] [--bot-seed=N] [--bot-explore=0.3] [--bot-oath-count=2|3]
tools/gd.sh ... --mode=valley --new-game --scenario=valley --bot-campaign ...   # the whole campaign from the Valley
```

`--mode=world --new-game` starts from `world_start` (the Valley's worst outcome: level 6, 1,050 XP,
the base club, 1 iron), so every balance and stability run plays the floor the budgets protect.

**Policy presets**: `peaceful` (march help, wood drive, crown parley, Harrok talk when possible, else
spared), `conqueror` (march force, wood slay, crown breach and strike Corvane, Harrok slain), `mixed`
(march intimidate, crown sabotage, wood slay, Harrok spared). The `--bot-oaths` list is also the
order; two oaths by default (the first two of the list), three with `--bot-oath-count=3`. The
`world_orders` preset runs each oath first (march, wood, crown) with its stage-4 resolution.

**Structure.** `WorldBot` reuses `BotCombat`, `RunMetrics` and `BotDiagnosis` (made stage-generic:
the engage radius is 2.5 × the profile's melee reach; the reach band reads `PlayerAttack`), keeps its
run in statics across reloads and travel, runs `PROCESS_MODE_ALWAYS`, and calls screen-backed APIs
directly (dialogue, the yield prompt, shrine growth and rest, the ancestry and talent choices by
policy, forge refits, fast travel through `GameSession.travel_to`).

**Routing** (`bot_route.gd`): A* over the world index's road graph, using only the edges its stage
allows (`min_stage`/`max_stage`; a `direct` edge — the Needle — is walked in a straight line), from the
nearest node to the target's nearest node, then local `NavQuery` legs of at most 250 m on the titan map
with the stage's query mask (titan from stage 3 in the world); a leg waits while its chunk is not
ready; replanning every 2 s or 3 m off path; fast travel when the target is more than 600 m away and a
visited waystone or shrine lies within 200 m of it. Stuck recovery as in the Valley bot (sidestep and
jump, replan, breadcrumbs, a recorded teleport as the last resort).

**Goals.** Every 6 ticks: a fight when aware hostiles are near (formations are fought through their
lock group: sweep at stage 5, break the banner first by switching to its candidate; engines: Crag Hurl
or close in and smash, throw at stage 6; cavalry: dodge the charge then punish; trolls: braziers and
the fire pit; the Matriarch: braziers), rest when hurt and a shrine is within 150 m, reinforce and
titanforge when a forge allows it, spend attribute and talent points by policy (a fixed build per
skill), open sealed places when the stage allows and `--bot-explore` asks, then the tracked quest's
stage `bot` hint (`travel`, `fast_travel`, `discover`, `breach`, `protect`, `duel`, `choose_ancestry`,
`heave`, `burn`, plus the Valley's), with the oath order of the policy. Exploration: before each oath,
visit `--bot-explore` of the region's undiscovered POIs nearest the route.

**Watchdogs**: 300 s per main stage (600 s for a boss stage, 900 s for `oaths`), 5 deaths per stage
(unassisted), stuck. **Diagnosis** adds the index route and per-chunk path checks to `world_blocked`
versus `bot_failed`.

**Human estimate**: the Valley's formula plus 6 s per map screen, 4 s per fast-travel load, 10 s per
region entered for the first time, 5 s per POI discovered, 8 s per sealed place opened.

**Metrics** (`AUTOPILOT_RESULT`): the Valley's, plus segments of §5.15 by main-thread stage, region
times, discoveries, cairns and sealed places, the stage and level timeline, the XP floors applied,
iron and titan iron over time, oath and boss outcomes and attempts, formation stats (lock groups used,
banners felled, sweeps, routs), siege stats (engines destroyed, thrown), wander spawns and events,
streaming stats (loads, unloads, thrash, worst work frame, smallest margin), path queries per tick,
the music intensity histogram (explore / danger / combat share per stage), save size.

**Invariants** (every tick; any failure exits 3): the Valley's (no NaN, y above the terrain minus
2 m, lock alive, pending hits < 512, debris ≤ 40, tokens, once-rewards, active combatants ≤ 12, no
double registration, no pausing screen over 2 s) plus: formation members ≤ the cap; no living member
in an unloaded chunk; loaded chunks ≤ 25; every layer map's regions ≤ 25 per layer and gate bit; no
chunk reloaded within 10 s of its unload (thrash); no world event twice at once; no event timer
running while its centre chunk is unloaded; the save ≤ 200 KB.

### 6.2 Stability runs (P39)

- **World**: `tools/run_bots.sh --preset=world_stability` — assisted novice, `--bot-loop` through the
  three presets from `--mode=world --new-game`, `--autoplay=3600` (60 minutes simulated). Pass: no
  crash, no `world_blocked`, no duplicated reward, no unrecoverable targeting state, no invariant
  failure, node count after each load within 10 % of the first, 0 errors and warnings.
- **The Valley** (regression): `--preset=stability` as in M5 (30 minutes).
- **The campaign hand-over**: one assisted run from the Valley's New Game through the Kings' Door to
  Brannock's oath (`--bot-campaign`).

### 6.3 Performance capture (P24a, P24b, P30, P39)

| Run | Command | What it shows |
| --- | --- | --- |
| World walk | `--mode=world --new-game --scenario=world_walk --autoplay=900 --graphics=low` (a route through every region at stage 6 sprint, a settlement and a border walk) | streaming work p50 / p99 / max, thrash, the loaded margin, CPU per tick, path queries per tick, nodes, memory; draw calls under Xvfb |
| Unreachable chase | P24b's slow test (20 humans chasing a giant in deep water) | CPU per tick p95 with the throttle and the query budget |
| Formation stress | `--level=res://scenes/test/formation_test.tscn --scenario=stress --stress-formations` (P30 adds the option; P39 adds two engines from the siege test level) | 40 members at tier 0: CPU per tick, draw calls rendered |
| The bot batches | `--perf` on every balance run | CPU per tick p95 per region |
| The web world | `tools/web/stream_check.mjs` (P24a; the M7 gate on the real world with the audio recorder) and `world_check.mjs` (P39): boot, Continue a world save fixture, fast travel, walk 60 s across a region border with gameplay | worst frame and p99, streaming hitches, music holes, peak live sample bytes, console errors |

Budgets: §5.2. Real-PC and real-browser numbers are the owner's (`docs/PERFORMANCE.md` gains the
world rows).

### 6.4 The balance loop (P39)

1. **Matrix per iteration** (`--preset=world_balance`, 3 jobs, 1,800 s wall each): novice × {peaceful,
   conqueror, mixed} × seeds 1–3, expert × the three presets × seeds 1–3 (18 runs, about 3 hours of
   wall time; if wall time is short, the novice drops to seeds 1–2, never the expert); the
   `world_orders` preset once per oath; plus the Valley matrix (novice × 4 outcomes × seeds 1–3, the
   expert on seeds 1–3) as a regression.
2. **Targets** (novice, median over seeds):
   - completion: at least 2 of 3 seeds per preset; the expert 3 of 3 with at most 2 deaths each; every
     first-oath order completes;
   - human estimate of the main path 75–140 minutes; each §5.15 segment within its range;
   - deaths: 1–3 per boss attempt sequence, at most 2 in any other segment;
   - growth shows: lone humans flee or rout ≥ 70 % of their engaged time at stages 4–6; formations
     hold or brace ≥ 50 % of their engaged time while their banner lives; at least half of the
     player's locks at stages 4–6 are formation groups or banners when formations are present; at
     least 2 engines thrown per run that reaches stage 6;
   - readability: the off-camera share of hits taken under 20 % (the M5 target; a miss is reported as
     a miss, with the archer and mage positions behind it); the music is in `combat` for under 25 % of
     stage 4–6 time spent among only lesser enemies;
   - abilities: every slotted ability used at least once a run; none over 40 % of ability damage;
   - streaming: worst work frame ≤ 12 ms (headless desktop), margin ≥ 200 m, thrash 0; CPU per tick
     p95 ≤ 8 ms;
   - the XP and equipment budget tests still pass (margins ≥ 50 XP);
   - the Valley items of `HOW_IT_PLAYS.md` hold as P22 left them (Ogre King 1–2 tries for the novice,
     segment damage ≤ 0.6 × maximum health, the force branch within its watchdog).
3. **Adjust data only** (enemy numbers within the windup floors, encounter composition, XP, boss phase
   numbers, wander weights); log every change and its reason in `docs/BALANCE_LOG.md`; at most three
   iterations, then a confirmation matrix. Never tune by deleting gameplay behaviour (spec §16).

### 6.5 The report (P39 → `docs/HOW_IT_PLAYS.md`)

The M5 Valley report stays (re-run on the final code) and gains the campaign: runs per preset, order
and skill, segments against §5.15, deaths by region, boss and cause, the growth evidence at stages 4–6
(AI-state histograms per role, formation and siege stats), discoveries, sealed places and cairns, fast
travel use, streaming and performance, the stability run, readability with the audio caveat (cues are
proven present and directional; their effect on people is NOT RUN), the music intensity histograms,
what changed in tuning, known issues, "what to try first" (a 10-minute world tour from `--mode=world
--new-game`; the full campaign), and the NOT RUN list.

### 6.6 Exports, the web checks and the play link

At each release (M6 gate, M7 gate, optionally M8, P40): version bump (`0.6.0-m6`, `0.7.0-m7`,
`0.8.0-m8`, `0.9.0-m9`); the Linux export runs the soak and an assisted bot run headless; the Windows
export is built (not launched); `tools/build_web.sh` (without `XDG_DATA_HOME`) builds the `Web` preset
(no test content), writes the packed pck in parts of at most 15 MB and reports the shipped sizes
against decision 8 (pck ≤ 7.5 MB after M6, ≤ 21 MB after M7, ≤ 23 MB at the end; it fails over the
milestone's budget and if any part exceeds 15 MB); `audio_check.mjs` (from M6), `stream_check.mjs` on
the real world with the audio recorder (from M7: across a region border for 60 s, no music gap over
50 ms) and `world_check.mjs` (from M9) pass in headless Chromium on the release build or, for
arguments the release does not take, on the `Web (test)` build; the launcher's notes describe the
build ("sound on"; "the world opens after the Valley"; at M7, what the next build adds); the
orchestrator republishes the play link. P40 opens the pull request to `main` and merges it once the
ship gate is reported.

### 6.7 Owner tasks (NOT RUN here)

A listening pass on speakers and headphones (the audio sheet: balance, harshness, threat readability,
music fatigue, the melody rotation and the silence windows); three usability sessions (the Valley's
first 10 minutes as in M5, then 20 minutes of the world from the Kings' Door: the view, finding the
way, the map, the compass, pins, fast travel, formations at stage 4, a sealed place); a timed human run
of the Valley (its pacing, which the bot can only floor); the real browsers (load time with the
multi-part pack, streaming hitches, audio in a hidden tab); the reference PC table; a real gamepad (the
new map, journal, track and pin bindings). **Two decisions that are the owner's**: a licence for the
project and its generated assets (the provenance record leaves it open), and whether the lossless music
and ambience masters should be committed (`build_audio.py --masters-out=assets/source/audio`, about
60 MB of FLAC by the end) instead of relying on the generators (decision 4).

---

## 7. Risks and mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| 1 | The download grows (audio about 9.3 MB and world data about 5 MB, both shipping at about 1.3×) | The pck ships in parts of at most 15 MB (the launcher joins them; proven by P23 at M6 with a forced two-part build), so no host file cap is hit; budgets as tests (decision 8: audio ≤ 9.5 MB, world ≤ 5.0 MB measured before P25, pck ≤ 23 MB shipped); every world and content package reports its share. Fallbacks in order: beds at a lower rate, two melody variants per world set, the map picture at 512², the large nav layer merged into titan for trolls and cavalry |
| 2 | Main-thread stalls drop streamed music on the web | `output_latency.web` 200 (VERIFIED for 120 ms stalls); samples registered behind the loading screen (no first-play registration); streaming steps sized and split (a navmesh load and its region add in separate frames, settlement sub-scenes); loads behind loading screens; `stream_check.mjs` and `world_check.mjs` record music holes during travel |
| 3 | Navigation map rebuilds hitch real browsers | Lean bakes, one region per frame, three layers (and gate regions) instead of four, measured by P24b and P39 with gameplay; fallback: coarser human detail, fewer scenery solids |
| 4 | The seam trap (≥ 40° slopes across chunk borders) | The builder's border relaxation and its test; seam walks at every stage (P24a, P26); partial rebuilds expand to neighbours and re-check seams |
| 5 | Forests stop stage 5–6 giants | 9 m minimum trunk spacing in walkable forest, saplings without collision, rides through the Greywood, a stage-6 walk in the slow suite |
| 6 | Formations exceed draw calls or CPU on the web | The crowd renderer, merged rigs, one band attack and one path per formation, the web cap of 20 with `web_formation_scale`, P30's slow perf test, P39's capture |
| 7 | Streaming breaks determinism (bots, seeded tests) | A fixed step quota per frame in headless runs and tests (`ChunkStreamer.deterministic`) **and** navigation async iterations off on every layer map and streamed region when deterministic, with readiness by map iteration id (re-measured: 12–24 ticks of jitter with the defaults, 1 tick with both off); a gate test runs two world walks with AI and a seam chase and requires byte-identical results; the M5 soak stays byte-identical |
| 8 | The world bot cannot route reliably across chunks | The staged road graph, short local legs on the stage's mask, waiting for ready chunks, the diagnosis's per-chunk checks; a recorded teleport as the last resort; `world_blocked` versus `bot_failed` |
| 9 | Scope: 23 packages, about 71,000 lines, 13 waves | Strict acceptance per package; P24 already split. If late, cut in this order (none touches a gate): the army column event → the drowned bells → Harrok's talk ending → wander-table variety → the sealed places of the Stonehold → the Ballista Ridge. Keep the main thread, every oath's first-oath resolutions, the five regions with the M7 content rule, the skyline, stages 4–6, the bosses and all of M6 |
| 10 | A migrated save meets an old cached web build | The 0.5.0 build keeps a newer save as its rejected copy and never makes it the backup (VERIFIED in M5); fixtures prove 1 → 2 and the backup recovery |
| 11 | Nobody here can hear the audio | Spectral and loop checks, conservative levels with headroom, voice caps, every parameter in the generators and data so a listening pass's notes are quick to apply; the owner's audio sheet |
| 12 | Music fatigue over about 170 minutes | Three melody variants per set picked per four-bar segment, rests of one to three loops, silence windows after three minutes of calm, region combat intros, the melody kept under combat, place overrides and boss sets in their own tempos; tests on the scheduler's repeats and gaps; the owner's audio sheet asks about it |
| 13 | The default suite outgrows 75 s | Audio off by default, per-package caps that add up to 11 s, the slow tier, the gate tier for walkthroughs, combinations, seeded bosses and soaks; every wave merge records the times and fails above 75 s and 8 minutes |
| 14 | Merge conflicts in hotspot files | Anchors created up front by P20, §1.6's insertion points, the single-owner table, runtime nodes instead of builder edits, regeneration for every generated file |
| 15 | The world build is slow or not reproducible | `--chunks=` with neighbour expansion and seam checks; the merge rebuilds all; a rebuild-twice check (no diff) in every region package and the M7 gate; navmesh bakes from the same inputs are deterministic (M5: Valley rebuilds left no diff) |
| 16 | numpy, ffmpeg or libvorbis output differs on another machine | Float64, single-threaded synthesis; bit-exact Ogg flags; the manifest records the toolchain; `--verify` regenerates every master and Ogg and reports a toolchain mismatch apart from a content change; the committed Ogg and WAV files stay authoritative for the game |
| 17 | Stages 4–6 make fights trivial or unreadable (humans at 8–17 px) | Threats come from formations (banners as their own targets), engines, cavalry, trolls and giants; humans are a crowd (lock groups, awe); music and stings weigh threats by size; P39 tunes against the growth-evidence targets |
| 18 | The target provider makes raiders ignore the giant or attack neutrals the player cannot protect | Opt-in per record; the player wins once aware and near; tests of each case; raids are events with a fail rule, not punishments, and their villagers reach safe markers |
| 19 | A package outgrows one session (P24a/b, P25, P29, P30, P34, P36 are the largest) | Each spec is self-contained with its contracts in §2; content packages are mostly data; any package over 3,500 lines splits at its numbered design items and records it |
| 20 | Valley regressions while it gains exits | Every Valley suite stays; the Valley matrix re-runs at the M6, M7, M8 and M9 gates; the end screen's slice completion is tested both ways (Quit and Continue); `faction.village` keeps its behaviour; the Valley's paths are byte-identical through `NavQuery` |
| 21 | Hidden tabs and focus differ in real browsers | The visibility callback mutes; the pause on lost pointer lock stays; real browsers NOT RUN |
| 22 | Optional content becomes unreachable | Every sealed place and the Hidden Grove have a key at some stage; no titan iron is missable; the bot opens sealed places when its stage allows |
| 23 | The skyline pokes through or shows seams at the ring's edge | Coarse heights are the minimum of the fine ones minus 2 m; the mask hides it over drawn chunks; P24a tests both; the fog hides the rest |
| 24 | A choice blocks itself (an oath that cannot come first; a parley without a token) | Decision 26's first-oath resolutions per oath, greyed choices with reasons, waiting texts, the GameData check of P29 and the gate tier's every-order combinations |

---

## 8. Review log

Three reviews of the first draft (the owner and the spec, feasibility, design quality) were applied
in this revision. Facts the changes rest on were re-verified on 2026-11-06: in the code (the files
named below) and in scratch experiments outside the repository (a Godot 4.6.3 project measuring
navigation readiness with async iterations on and off and probing the `NavigationServer3D` API; an
ffmpeg 6.1.1 run comparing libvorbis encodes with and without the bit-exact flags; a per-file audio
budget calculation). Every item below was accepted unless it says otherwise; "changed fix" means the
problem was accepted but solved differently, with the reason.

Found while revising: `briefs/growth_extension.md` named its scratch folder by an absolute path that
`test_ship_docs`'s name check would flag once the briefs are committed; it now reads `<scratchpad>/`,
as the other two briefs do.

**Owner and spec**

| Item | Verdict | Where |
| --- | --- | --- |
| The M7 world is mostly empty; formations only on a test level; stage 5 changes numbers only | Accepted | P30 moved to W16 and P29 places two formation fights (§5.10); the M7 content rule (§0.2) with P25's light content, caches and cairns in every region; P31 merges before the M7 gate, so stage 5 brings Formation Sweep and Titan Roar besides heave, the channel and the Needle's refusal (decision 17) |
| No weapon lands light 3 at stage 4 in M7 | Accepted, changed fix | Reinforced weapons fit stage 6 and carry their family's stage 4–6 moveset (decision 24); P31 (merged before the M7 gate) ships them; P31's slow test is the M7 gate's weapon check. P26 ships the field and the engine-level proof (it had no room for twelve movesets and their tuning) |
| Iron supply against refit costs on peaceful paths | Accepted | The equipment budget (decision 32, §5.8): the beacon's cache, oath rewards on every resolution, the Standing Stones' gift, the Kingsgate anvil; P29, P35, P36 extend the test |
| The Matriarch grab breaks the 50 % rule and the deferral | Accepted (first option, adapted) | She stays 9 m and cannot be grabbed; fire comes from braziers and from whelps or trolls thrown into her pit (§5.13); P34 tests that a 9 m target cannot be grabbed at stage 5; boss grapples stay deferred |
| "Any order" is impossible for the wood's drive and the crown's parley | Accepted | Decision 26 restated per oath; drive at stage 4 (the woodfolk open the wall); parley tokens (the banner, the deserters' word, Stoneblood, stage 5); greyed choices and waiting texts; the combination suite runs every order of every pair (P36, gate tier) |
| `world_start` one level above the Valley's worst case | Accepted | `world_start` = level 6, 1,050 XP, the force outcome's guaranteed state (§2.6), tested against the Valley budget (P20); margins ≥ 50 XP with the beacon at 250 XP and the shelf's discovery (§5.8) |
| 30-second loops for about 160 minutes | Accepted | Three melody variants per set per four-bar segment, rests, silence windows, region combat intros, boss frames (decision 5, §4.3); scheduler tests (P19, P23); budgeted (§4.5) |
| Music and ambience masters not kept | Changed fix | The generators are the masters: `--verify` regenerates every master and every Ogg bit-exactly on the recorded toolchain (Ogg made reproducible with `-fflags +bitexact`, re-measured), and `--masters-out` exports FLAC on request. Committing the FLAC masters would add about 60 MB to a 19 MB repository and rewrite them on every tuning pass; the deviation is recorded (decision 4, P40 copies it into `DECISIONS.md`) and offered to the owner (§6.7) |
| CC0 chosen without the owner | Accepted | `PROVENANCE.md` records originality, generators, seeds and tool versions and leaves the licence to the owner (decision 4, §6.7, P40's handoff) |
| The off-camera target loosened to 25 % | Accepted | Back to under 20 % (§6.4); P22's ranged positioning (`front_arc_deg`, aim time) plus P21's threat cues; measured at the M6 gate's Valley matrix and at M9; a miss is reported as a miss |
| The Valley's balance items neither assigned nor deferred | Accepted | P22 tunes the Ogre King's retries, segment damage and the force branch's watchdog (two data-only iterations); the bot's pacing is deferred to a timed human run (§0.4, §6.7); P39 keeps them as regression targets |
| The expert shares seed 1 | Accepted | The expert runs seeds 1–3 in both matrices; novice seeds drop first if wall time is short (§6.4) |
| Routing soldiers jam in gates; the nav-link flake | Accepted | Routs fan out over flee points, a slow test of 10 members through a breached gate (P30); chunk gates carry nav links joined to their layer maps, tests wait for the map's iteration id (P24b); P22 fixes the Valley's flaky test the same way; agent avoidance deferred (§0.4) |
| Pike braces and the two-token rule | Accepted | The brace is one band attack of the formation, one token, one hit per target per pulse (§2.10), tested by P30 |
| Valley revisits at stages 5–6 | Accepted | Every Valley checkpoint measured at stages 4–6 and given a `max_stage`; travel refused and respawns moved above it (§5.6, P26) |
| First person at stages 4–6 | Accepted | P26's route in both modes and downward attacks; the eye anchor with P22's merged rig |
| Harrok's watchers deal damage | Accepted | The stones are arena hazards of Harrok's brain, credited to him; the watchers never damage (§5.13) |
| 23 actives, not 24; ranks undefined | Accepted | Primal Regrowth (Primordial tier 3) makes 24 actives and the ultimate; ranks are deferred (decision 23, §0.4) |
| Outmatched soldiers never join formations | Accepted | `Formation.try_join` within 40 m (§2.10, P30) |
| Civilians without safe markers in world settlements | Accepted | Safe markers in every settlement's layout and in the index (§2.6, §5.4); P37's raid test checks that villagers reach them |
| The tracked quest is lost on reload; backup recovery across the migration | Accepted | `progress.tracked_quest` (§2.6; P20 saves and restores it, P27 adds `Quests.tracked_quest_id`); P20's backup-recovery test |
| No package writes the audio sheet before the M6 checkpoint | Accepted | P23 writes it in W14; P39 extends it |
| Sandbox, loading, test levels and the campaign end have no music decision | Accepted | Sandbox context, `loading` silent by decision, a silent list, `music.campaign_end` from existing stems; P23's mapping test (§2.5, §4.3) |
| No water sounds | Accepted | `wade` footfalls from `water_at`, splashes, the Valley river's `wet` (§2.5, §4.1, P21, P28) |
| POI counts disagree; waystone eligibility undefined | Accepted | Recounted after the changes: 48 POIs (§5.1, §5.4); fast travel needs `visited.<id>` and the index `requires_flags` (§5.4, P27 tests both) |
| A returning player must replay the prologue | Accepted | The title's skip choice for a finished save (§2.6, P20) |
| No web check of world audio before M9 | Accepted | P24a's `stream_check.mjs` (with P22's launcher arguments), run on the real world with the audio recorder at the M7 gate (§1.3, §6.6) |
| Boss retries are long walks | Accepted | `world.cp.troll_den`, `world.cp.moot_foot`, `world.cp.fort_gate` within 80 m of their arenas, tested (§5.4, §5.13) |
| Brannock Bridge not protected; destructible walls not deferred | Accepted | `indestructible` quest-critical props with a GameData check (§2.7); destructible walls, towers and bridges deferred (§0.4) |
| Thunderhead's stun; `Rooted` unused | Accepted | A fixed-length stagger (an existing mechanism); `Rooted` removed (§2.15, §5.12) |

**Feasibility**

| Item | Verdict | Where |
| --- | --- | --- |
| Deterministic streaming does not make navigation deterministic (blocker) | Accepted, re-measured | 12–24 ticks of readiness jitter with the defaults, 16–23 with only the map's async off, 1 tick in 5 of 5 runs with both off; async off on every layer map and streamed region when deterministic, readiness by iteration id, a gate test of byte-identical world walks (decision 13, §2.8, P24b, risk 7) |
| Web sample memory contradicts the content (blocker) | Accepted | Caps from the content (110 s Valley, 170 s world); spots moved to Ogg streams; registration behind the loading screen before the first tick, for every level (P19's gate in `main.gd`); the web check measures peak live sample bytes (§2.5, §4.5, P23) |
| Test scenes ship in the web pck; P24 has no web harness | Accepted | Test records move to `data/test/`; the web release excludes test content; a `Web (test)` preset; the launcher's argument pass-through (P22, W13); P24a's `stream_check.mjs`; the M7 gate runs it on the real world |
| The audio budget does not add up | Accepted | §4.5 rebuilt from per-file arithmetic with headers; `--budget` prints it; caps set from the content with the variation added (M6 ≤ 4.0 MB, all ≤ 9.5 MB) |
| The world data budget and the 16 MB cap; the fallback unspiked | Accepted, changed fix | P24a and P24b measure chunk data (16-bit only) and navmesh sizes on the test world and extrapolate before P25 (budget 5.0 MB). Instead of a second resource pack loaded through engine APIs, the one pck ships in parts the launcher joins (the launcher already unpacks the gzip-and-base64 text itself), proven at M6 by a forced two-part build in Chromium; the host's per-file cap stops limiting the game and the budgets limit the download |
| No unload hysteresis; contradictory chunk invariants | Accepted | Load at distance ≤ 1, unload at ≥ 3; at most 25 loaded; budgets restated for 25; a border-walk thrash test (§2.8, §5.2, §6.1) |
| `map_get_path` cannot take the polygon limit; civilians, bots and links on the default map | Accepted, re-verified | `map_get_path(map, origin, destination, optimize, layers)` has no query parameters (on an 8,100-polygon map it stopped 467 m short; a synchronous `query_path` without a polygon limit did not); one `NavQuery` helper over `query_path` with every call site converted (civilians and the debug bots included), goals snapped on the layer map, links joined to their layer's map; the Valley keeps today's parameters and identical paths (§2.8, P24b) |
| Unthrottled unlimited-polygon repaths | Accepted | Goal snapping, tier-0 repath throttle, one pivot path per formation, a per-tick query budget, 120 m chase caps, a slow test of 20 humans chasing a giant in deep water (§2.8, P24b, P30) |
| One titan navmesh ignores size gates and the Needle; town widths unspecified | Accepted | Titan gate bits 32 / 64 / 128 and stage masks; staged road edges and a `direct` edge for the Needle; the Hidden Grove's second key makes it reachable on the titan layer; 12 m quest routes and 16 m in Brannock with a builder check (§2.2, §2.6, P25) |
| Valley revisits unverified | Accepted | §5.6 and P26's measured `max_stage`; `level_valley.player_nav_fallback` 4 |
| W18 ownership of `player_grab`, `player_motor`, `projectile_system` | Accepted | The fists and Rampart Grip moved to P32 (W19, the `player_grab.gd` owner); `player_motor.gd` single-owned per wave (P26, P31, P33); anchors in `projectile_system.gd` and `telegraph_visuals.gd` (§1.5) |
| Generated scenes need later packages' nodes; region branches conflict in binaries | Accepted | `LevelRoot.RUNTIME_NODES` (§2.6); generated outputs regenerated at merges, never merged by hand; region tests read their own index entries; the W21 merge rebuilds the world before the combinations (§1.2) |
| `--chunks` partial rebuilds break seams | Accepted | Neighbour expansion, seam checks on rebuilt chunks, rebuild-twice in every region package (§1.1) |
| The web worst-frame target is unreachable with gameplay | Accepted | ≤ 45 ms worst and p99 ≤ 25 ms measured with gameplay; navmesh load and region add in separate frames; settlement sub-scenes; a settlement-sized chunk in the test world (§5.2, P24a) |
| Unrealistic test budgets | Accepted | Audio off by default; per-package default caps adding to 11 s; per-package slow budgets; the gate tier; merges record the times (decision 34, §1.1, §3) |
| Fixtures: "no checkpoint is written when the slice completes" | Rejected in part | The code already takes one: `Quests` requests `GameSession.request_checkpoint("quest_complete", "", true)` when `quest.main` ends (P17a's completion checkpoint, `scripts/quests/quests.gd`), so finished v1 saves hold `slice.completed`; quest start conditions are evaluated on every pass, so a loaded save starts `quest.world_main`. Kept from the item: a migrated pre-crown save retakes the crown and opens the door (P20) |
| `world_start` and the margins | Accepted | As in the first review (§2.6, §5.8) |
| Shrines and waystones reactivate on chunk reload | Accepted | Activation once per level visit in `GameSession` (§2.6, P20) |
| Signals missing from the cue map | Accepted | `item_removed`, `xp_award_requested`, `ui_screen_requested` silent; `world_event_ended` and `enemy_routed` routed; `boss_disengaged` added (§4.1) |
| P38 reaches P37's APIs in the same wave | Accepted, changed fix | P37 now merges in W20, two waves before P38 (§1.3), so nothing is cross-lane |
| P24 too big for one session; the loading screen pauses the streamer | Accepted | Split into P24a (terrain, streaming, skyline, web check) and P24b (navigation, director); `PROCESS_MODE_ALWAYS` and sliced ring loading (§2.8) |
| Draw calls not re-measured after content | Accepted | Every content package re-measures its viewpoints; breakable houses budgeted apart; merged settlement elements (§5.2, P25, P29, P35, P36) |

**Design quality**

| Item | Verdict | Where |
| --- | --- | --- |
| No far view (blocker) | Accepted | The skyline (coarse terrain and landmark silhouettes), fog to 1,800 m, a 2,400 m far plane, beacon columns, the Kingsgate shelf as the arrival vista with its reveal stinger, a P25 test that every region's landmark is in view from it (decision 12, §5.3) |
| No fitting weapon at stage 4 (blocker) | Accepted, changed fix | Reach separated from crafting (decision 24) but the Valley's forge lesson kept: base weapons still fit stage 2, any reinforced weapon fits stage 6 with its stage moveset, reinforcing is on the main path at the Kingsgate anvil; titanforging adds damage and a perk |
| Aldmere hostile yet the herald waits in its camp | Accepted | Per-site factions: the toll-riders hostile, Aldmere at peace until offended; the herald at the camp's edge; the fort's garrison stands down for a parley token; the toll fort's breach does not void the parley; the villages row fixed (§2.12, §5.7, §5.9) |
| The `oaths` stage gives no lead | Accepted, changed fix | The main stage's `markers` show three leads (map icons and compass diamonds) at stage 4, and each oath quest starts at stage 4, rather than starting all three quests at once (the M7 build has one oath quest; a lead per power works in both builds); the beacon's scene names the powers |
| Hidden orderings decide whether peaceful choices exist | Accepted | §5.7's first-oath column; greyed choices, waiting texts, first-oath tests (P35, P36) |
| The siege of Skarn starts itself; stage 6 has no engines | Accepted | Started by Ulfra's plea or a stage-6 arrival, paused beyond 200 m, recoverable by a rebuild; the Moot battery on the main path at stage 6; stage-6 siege trains in the wander tables; "engines thrown ≥ 2 per run reaching stage 6" (§5.7, §5.10, §6.4) |
| M7 scope | Accepted | As the owner review's first item (the M7 content rule rather than temporary barriers, so the world stays open as the owner asked) |
| Settlements too small for big giants; towns empty; trampling free | Accepted | Greens and `max_inner_stage`, 16 m streets, give-way civilians, house damage and house trampling as offences (decision 31). One point needed no change: player area effects already never reach neutral faction members (`HitFactory.skip_candidate`) |
| World events ignore streaming; the army column resets; a death loop at Brannock | Accepted | §2.13's streaming rules; abstract columns; respawn blockers for hostile guards and active events; guards leash inside walls (P20, P29, P37) |
| Web caps below authored compositions | Accepted | `web_formation_scale`, aggregates of what spawned, a cluster test on both platforms (§2.10, §5.10, §5.13) |
| The banner cannot be locked | Accepted | The bannerman is its own lock candidate with a flag icon and a visible 7 m banner; a test of switching to it and killing it through a rank (§2.10, P30) |
| Ten pike telegraphs; catapult cues at the engine; scattered march steps | Accepted | One band telegraph and one wall cue per formation; the incoming whistle at the landing circle; march emitters; the cavalry swell (decision 7, §4.1, P28) |
| One combat sound for every region; endless exploration music; boss sets locked to the zone frame | Accepted | §4.3 (melody under combat, region intros, rests and silence, boss frames and intros) |
| Audio radii make trivial enemies epic | Accepted | Threat-weighted intensity, sting suppression, the 150 m cap, the rout stinger, the test with fleeing soldiers (decision 6, §4.3) |
| Thin stage-gated returns; the Grove missable | Accepted, changed fix | The Grove's second key; nine sealed places; the causeway now leads to the sunken vault; titan iron on the mandatory path. Cairns give an attribute point (an existing currency) rather than a talent point or health, so no new progression path is needed (decision 33, §5.4) |
| The compass shows the whole map at stage 6; no pins; no recommended stage | Accepted | §2.14 and P27 |
| Accidental betrayal of a yield | Accepted, stronger fix | The yield protocol: immunity, discarded earlier hits, and the outcome chosen in a prompt with a confirm, so no blow can decide it (§2.10) |
| No arena disengage; the fled ending never leaves boss music; the BattleBoss has no boss id | Accepted | `boss_disengaged`, `battle.iron_regiment`, `audio_region.boss` by boss id (§2.4, §2.10, §4.3) |
| XP margins of 0–80 | Accepted | Floors on milestones and ≥ 50 XP margins (§5.8) |
| Valley revisits | Accepted | As above (§5.6) |
| "Climb the Giant's Stair" for a plateau walk | Accepted | "Enter the Moot"; the Stair as a shortcut with a stage-6 vista and a cairn (§5.4, §5.7) |
| No place audio; the world does not react to size | Accepted | POI audio regions with place beds, flush reactions, the settlement arrival cue (§2.5, §4.3) |
| Footfall fatigue; a UI buzz for diegetic gates | Accepted | Cruise ducking and variants; gate cues per kind (§2.5, §2.9, §4.4) |
| Trolls' fire counter unlearnable | Accepted, changed fix | Braziers or bonfires at every troll site and a tutorial at the woodcutters' camp; burning logs were left out because carrying props before P32's prop grab would need a second grab path |
| Choices invisible on site; no way back from hostility | Accepted | `visible_when_flag` / `hidden_when_flag`, bark sets by standing, reconciliation (§2.7, §2.12, §5.9) |
