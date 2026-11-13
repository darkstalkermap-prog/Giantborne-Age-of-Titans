# M6-M9 handoff: sound and music, then the open world

Spec §16 lists what every milestone handoff must contain: changed files and a runnable project, the
exact engine version, launch and export instructions, controls, implemented versus deferred
features, test results with measured evidence, known bugs, and the next smallest milestone. This
document provides each for milestones M6 to M9 of `docs/plans/M6_M9_PLAN.md` (the M2-M5 handoff is
[M2_M5_HANDOFF.md](M2_M5_HANDOFF.md), the M0/M1 one [M1_HANDOFF.md](M1_HANDOFF.md)), with the gate
table of the plan's §0.2 and §1.3 and of spec §15 and §16, the owner's tasks and the owner's two open
decisions.

| Spec §16 item | Where |
| --- | --- |
| Changed files and a runnable project | §2 |
| The exact engine version | §1 |
| Launch and export instructions; controls | §3 (README §2, §3 and §7) |
| Implemented versus deferred features | §4 |
| Test results with measured evidence | §5 (the gates), §6 (the checks and runs), §7 (the exports and the web checks) |
| Known bugs | §8 |
| The next smallest milestone | §11, after the owner's tasks (§9) and decisions (§10) |
| A debug panel; debug cheats off in exported play | §5.6 |

**In one paragraph.** The Valley of Broken Kings now has complete original sound - effects for every
event, an ambience for every district, an adaptive score with melody variants, rests and silences -
and it is the prologue of a campaign: the crown opens the Kings' Door onto the Old Kingdom, a
streamed 2 x 2 km world of five regions with a far view, a map, a compass, fast travel, sealed places,
growth to stage 6 (62 ft), talents and ancestries, 24 abilities and an ultimate, formations, siege
engines, cavalry, trolls, rival giants, three bosses, three oaths each won more than one way and in
any order, settlements that react to a giant, and a living world of wanderers, raids, a column and a
siege, ending on the Stone Throne. A world bot plays the whole campaign. Everything was measured in a
Linux container without a GPU, speakers, a gamepad, a Windows PC, a real browser or a human player,
so the usability, listening, real-controller, reference-PC and real-browser gates are **NOT RUN** and
their sheets and commands are ready for the owner (§9). The numbers in this document name their
source; numbers of the W23 confirmation (the merged `wave-23` code with commit `a7da72d`, 13 November)
are that confirmation's, and the M9 gate's fixes followed it. ⟦SHIP: one sentence with the final
result - the M9 gate's verdict (stability, the bot's acceptance, the balance targets met and missed)
and the ship gate's final check (suites, checks, failures), from §5.4 and §6.1 once filled⟧

## 1. Engine, build and environment

| Item | Value |
| --- | --- |
| Engine | **Godot 4.6.3-stable, official build `7d41c59c4`** (standard build, GDScript) |
| Project version | `0.9.0-m9` (`project.godot`'s `config/version`; shown on the title screen and in the pause menu; written into saves; it sets `tools/build_web.sh`'s budget) ⟦SHIP: the commit that sets config/version to 0.9.0-m9 (the ship step's version bump; it read 0.8.0-m8 through W23)⟧ |
| Renderer / physics | Compatibility (OpenGL 3.3, WebGL 2 on the web), Jolt Physics, 60 physics ticks per second |
| Branch | The M6-M9 integration branch, from `main` @ `c9434e5` (M0-M5, `0.5.0-m5`); 13 waves (W12-W24) of two lanes, with gate reviews after W14 (M6), W18 (M7), W21 (M8), W23 (M9) and the Ship gate in W24 |
| Where it was built and tested | A Linux container with 4 shared CPU cores: headless runs (tests, bots, the world walk), real rendering through Xvfb and Mesa llvmpipe (software OpenGL), Chromium (Playwright) with SwiftShader (software WebGL) for the web build; Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1 and libvorbis 1.3.7 for the audio pipeline (`assets/audio/manifest.json`) |
| Not available here | A Windows PC, a real GPU, speakers or headphones, a gamepad, human players, real desktop browsers |

**What was actually run for this handoff** (not only code-reviewed): ⟦SHIP: the ship step's own runs on the final code, as a list - the final check (`tools/check.sh --build --slow --gate --audio`), the Linux, Windows and Web exports, the Linux export headless (the soak and an assisted bot run), the world tour's screenshots beside the bot, the Chromium checks (audio_check.mjs, world_check.mjs, stream_check.mjs --world --audio, world_start_check.mjs) - and which runs the M9 gate made on its final code (its matrix, its stability runs)⟧. Before it, the W23 confirmation ran on the merged W23 code (`a7da72d`): the performance captures and the web checks alone on the machine, then the world matrix (21 runs), the crown order's battles, the three stability runs, the Valley matrix (30 runs) and P38's acceptance orders, three Godot processes at a time (`docs/BALANCE_LOG.md`, "M9 confirmation"; `docs/PERFORMANCE.md`, "The M9 confirmation").

## 2. Changed files and the runnable project

The project opens as it is in Godot 4.6.3 (`project.godot`); README §2 has the steps. Exports are
built locally into `builds/` (git-ignored; README §7). Building or playing never needs Python, ffmpeg
or Node; the audio pipeline and the web checks do (README §1).

From `c9434e5` (M5) to W23 (`f851b0d`), in 23 packages (P19-P39 with P24 split in two, and the W23
fixes lane P39f) and the gate lanes: 2,845 files changed, 188,638 lines added and 3,462 removed, in
402 commits (generated scenes, chunks and navmeshes included; `git diff --shortstat c9434e5 f851b0d`).
⟦SHIP: the same three numbers and the commit count from c9434e5 to the final merge commit (git diff --shortstat, git rev-list --count)⟧

| Area | At M5 (`c9434e5`) | At W23 (`f851b0d`) | What is there now |
| --- | --- | --- | --- |
| `scripts/` | 132 GDScript files, 33,325 lines | 205 files, 68,745 lines | Besides M5's: the audio engine (`scripts/audio/`), the streamed world (WorldRoot, ChunkStreamer, TerrainChunk, Skyline, NavMaps, NavQuery), the campaign and save schema 2, size gates, formations, siege engines, cavalry, trolls, rival giants, bosses and battles, talents and ancestries, the living world, the world bot |
| `ui/` | 34 files, 5,595 lines | 44 files, 9,746 lines | The HUD batched by `HudKit` with the compass, the region banner and the discovery toast; the map, journal, ancestry and yield screens; the shrine's Talents and Ancestry tabs |
| `data/` | 152 records | 651 records in 21 folders | Audio (banks, the mix, music and ambience sets, audio regions), the world (levels, 5 regions, 48 POIs, encounters and templates, 8 factions, 5 wander tables, 3 world events), 27 talents, 3 ancestries, growth 4-6, the new enemies, abilities, weapons, quests and dialogue |
| `scenes/` | 44 scenes | 123 scenes | The new actors (pikes, shields, banners, crews, riders, trolls, rival giants, bosses), siege engines, the Kings' Door and the Citadel hall, the world's root scene and its chunks' prop parts, the streamed test world and new test levels |
| `assets/` | materials, shaders, the Valley's navmeshes | + the world and the audio | 441 generated sound files with their manifest and provenance; the world's 64 chunks, navmeshes, structures, skyline, index and map (2,390,369 bytes, P25) |
| `tools/` | 28 files, 6,040 lines | 123 files, 30,522 lines | The world builder library (`tools/world/`) and its layout tables (`tools/data/world/`), the audio pipeline (`tools/audio/`), the web checks (`tools/web/`), more builders, `pck_files.py`, `release_data_check.gd` |
| `tests/` | 119 files, 28,144 lines (104 suites) | 313 files, 68,893 lines (282 suites: 55 unit, 154 integration, 49 slow, 24 gate) | The gate tier (walkthroughs, oath combinations, seeded bosses, determinism soaks, the bot's smoke run), fixtures of schema 1 and 2 saves |
| `docs/` | | | This handoff; README, ARCHITECTURE and DECISIONS consolidated; HOW_IT_PLAYS rewritten for the campaign; PERFORMANCE, USABILITY_SCRIPT (the world, audio and browser sheets) and BALANCE_LOG extended; the M6-M9 plan and its three briefs; one system document per package (`docs/systems/P19.md` ... `P39f.md`) |
| `web/launcher.html` | | | The play link's page: the two start buttons ("Play in browser", "Start in the open world"), the notes, the multi-part loader |

⟦SHIP: refresh the W23 column's counts on the final tree as a "final" column, with the commands used here (find scripts -name '*.gd' | wc -l and its lines; the same for ui, tests, tools; find data -name '*.json'; find scenes -name '*.tscn')⟧

What each package built, its public APIs, data, decisions and tests: `docs/systems/P19.md` ...
`P39f.md`; consolidated in [ARCHITECTURE.md](ARCHITECTURE.md) and [DECISIONS.md](DECISIONS.md).

## 3. Launch, export and controls

- **Run:** README §2: the editor (F5) or `godot --path .`; the title screen (New Game, Continue,
  Sandbox, Settings, Controls; a finished prologue offers "Skip to the Old Kingdom"); command-line
  shortcuts, among them `--mode=world --new-game` (a new game on the Kingsgate shelf as the Valley's
  worst outcome leaves the giant) and `--mode=world --continue`.
- **Controls:** README §3, taken from `data/input/default_bindings.json` (every binding can be changed
  in the game; F1 / H shows the current loadout's controls). New since M5: the map (M / D-pad down),
  the journal (J / D-pad right), track the next quest (T / D-pad left), pin a place (P or a right
  click on the map / Y), and the yield prompt's held confirm.
- **Tests, bots, measurements, the audio pipeline:** README §6; `docs/PERFORMANCE.md` for every
  performance command.
- **Export:** README §7 (Windows, Linux, Web; the `Web (test)` preset; `tools/build_web.sh` writes the
  play link's files, the pck in parts of at most 15 MB, and fails over the milestone's budget).
- **The play link:** <https://claude.ai/artifact/2UYupKVL1xE6pttiZ6NLqe> (served from
  `web/launcher.html` and the files `tools/build_web.sh` writes; republished at `0.6.0-m6`,
  `0.7.0-m7` and `0.8.0-m8`). Its "Start in the open world" button does what `--mode=world --new-game`
  does. ⟦SHIP: the play link's URL as republished with 0.9.0-m9 (the orchestrator's republish), and the BUILD line it serves⟧

## 4. Implemented versus deferred

### 4.1 Against the plan's goals (plan §0.1)

| Goal | Status |
| --- | --- |
| **M6:** sound effects for every combat, ability, enemy, world-object, UI and progression event | Done (P21: 209 masters, 215 cues; P28 adds the world's: 98 masters, 199 cues). Every event is routed or listed as deliberately silent |
| An ambience for every Valley district; an adaptive score (title, districts at three intensities, the Ogre King's two phases, growth, level-up, victory and death stingers, the end screen) that varies its melodies and rests | Done (P23): 7 music sets, 5 ambience sets, 11 stingers |
| Audio settings, mute on focus loss, spatial cues for off-camera threats | Done (P19, P21); the hidden-tab mute in a real browser NOT RUN |
| Generated by committed tools with provenance; regions and places get music and ambience by data; verified in the web export within a size budget | Done (P19, P23, P28; 441 files regenerated bit-exact); the web's strict audio criterion NOT RUN (§5.1) |
| The M5 limitations: enemy rigs' draw calls, Thornwick on a help path, the title's checkpoint id, the off-camera share, the yard pocket, the nav-link flake, the Valley balance items | Done but two: the off-camera share was a miss at the M6 gate (20.4 %) and 19 % in the W23 confirmation; of the Valley balance items, the novice's tries at the Ogre King and the forest's and ruins' damage still miss (§5.1, §8) |
| **M7-M9:** the Valley kept as the prologue, opening into a streamed world of five regions seen from the Kings' Door to the far highlands | Done (P20, P24a, P24b, P25, P26) |
| Free roaming, places, sealed places, a map, a compass, fast travel | Done (P25, P27); the bots never needed fast travel on the main path |
| A non-linear main thread: three oaths, each first, each with a peaceful and a violent resolution | Done (P29, P35, P36; the gate tier runs every order of every pair); the bot's crown-first order at stage 4 did not complete in the W23 confirmation (§5.4) |
| Settlements that treat a giant as a neighbour or a threat | Done (P22, P29, P36) |
| Wandering encounters and world events | Done (P37, P35, P36), except the siege trains of the wander tables (§4.2) |
| Growth stages 4-6; level 12 with three talent trees and three ancestries; 24 actives and an ultimate; stage movesets, axes, fists and Giantforge refits | Done (P26, P31, P32, P33) |
| Formations, siege crews, cavalry, trolls, rival giants and three bosses | Done (P30, P32, P34, P35, P36) |
| Region and place music and ambience | Done (P28) |
| Persistence and save migration | Done (P20: schema 2; M8 gate and release fixes) |
| A world bot, a stability run, a balance pass, an updated report | Done (P38, P39; the W23 confirmation); the final results are the M9 gate's (§5.4) |
| The exports, the play link and the merge | ⟦SHIP: done or not, with the commits (§5.7)⟧ |

### 4.2 Deferred, and planned but not built

**Deferred by plan (§0.4):** growth stages 7-10 and what they unlock (large-monster grapple windows,
the colossal shockwave, titan executions, Worldbreaker) and the traversal spike they need; dragons and
flight, primordial titans, continent-scale worlds, a seamless Valley-to-world embedding, per-region
download packs, runtime navmesh baking, a floating origin; boss grapples (no boss can be grabbed, the
Troll Matriarch included), enemy grabs of the player, limb poise; ability ranks; day and night,
weather, seasons, mounts, swimming; a crafting economy beyond refits, shops and currency, inventory
weight or loss, several save slots, cloud saves; voice acting, localization, cinematic dialogue,
generative live music; destructible walls, towers and bridges, building collapse, terrain destruction;
crowd avoidance (routs fan out over several flee points instead); the Unreal engine spike; physics
interpolation; the Valley's pacing against a timed human run; choosing a licence (the owner's, §10);
human playtests, a real reference PC, a real gamepad and real browsers (NOT RUN: §9).

**Planned but not built:**
- **The siege trains of the wander tables** (plan §5.10: the toll-riders' at stage 6, Aldmere's at
  stage 5, the Stonehold's at stage 6): an engine is a placed prop keyed by its world id, so a wander
  copy cannot bring one along without engine copies with a once-only reward; P37, P36 and P39f left
  it as a framework change (`docs/plans/FOLLOWUPS.md`, "From P37", "From P36").
- **Bulwark's frontal rule** (plan §5.12: frontal hits x0.4): Bulwark takes x0.4 from every side
  (P31, P33).
- **A horn at a battle's phase change, the watching clans' cheers** (P34's known gaps).
- **Sealed places and cairns for the bots** (`--bot-explore` visits places only; P38).

**Against the spec:** the deviations of §13 (the lossless music and ambience masters not committed;
no licence chosen) and the scope read from the owner's direction (the open world as a second streamed
level; growth to stage 6 of ten) are recorded in [DECISIONS.md](DECISIONS.md) §1.3.

## 5. The gates

Legend: **PASS** = verified by running the game or engine here. **PARTIAL** = verified here, with a
part that only a real PC, pad, browser or person can confirm, or with part of the requirement met.
**FAIL** = measured and not met. **NOT RUN** = needs hardware or people that are not available here.
A result that the M9 gate or the ship step settles is a ⟦SHIP⟧ placeholder until then. The M6-M8 gates
are final; their evidence is the gate's own record (`docs/BALANCE_LOG.md`, `docs/PERFORMANCE.md`,
`docs/plans/FOLLOWUPS.md`, the system documents' gate sections) or a later run where the row says so.
Test names are in `tests/` (`unit/`, `integration/`, `slow/`, `gate/`).

### 5.1 M6: sound and music (gate after W14; release `0.6.0-m6`)

| Gate item (plan §0.2, §1.3) | Result | Evidence |
| --- | --- | --- |
| Every event that exists today has a sound or is listed as deliberately silent | **PASS** | `test_sfx_coverage` reads `CueRouter.ROUTED_SIGNALS` and `SILENT_SIGNALS`; the gate's `test_sfx_valley_pass` (the seeded soak and the Valley's walkthrough with sound) resolves every request with no missing cue (P21); the world's events: `test_world_audio_coverage` (P28) |
| Ambience in every Valley district | **PASS** | `test_ambience_valley`, `test_audio_zones` (P23: six Valley audio regions, four beds, 18 spots) |
| Adaptive music: explore, danger and combat layers, melody variants, rests and silence windows, the boss's two phases, the stingers | **PASS** (measured; heard by nobody: the listening pass is NOT RUN, §5.6) | `test_melody_scheduler`, `test_music_state` (P19); `test_music_valley` (P23); slow `test_music_loops`: every loop seamless, every stem aligned to its frame |
| Every level and context has music or is listed silent | **PASS** | `test_audio_zones` (P23: the contexts and `audio_region.silent`; P28 took `level.world` off the silent list) |
| Audio settings and focus mute | **PASS** (desktop) | The settings page's Audio section and `mute_when_unfocused` (P19, `test_audio_director`); the web's hidden-tab mute is a real-browser check (§5.6) |
| Directional threat cues | **PASS** (present and directional; their effect on people NOT RUN) | `test_threat_cues` (P21); M6 gate: the sting and the aim lock in the `alert` class, slow `test_threat_audibility` (a far sting 4.8 dB under the combat layer's median and 5 dB over it above 4 kHz at every stage) |
| Generated by committed tools with provenance; bit-exact regeneration on the reference toolchain | **PASS** | `assets/audio/manifest.json`, `assets/audio/PROVENANCE.md`; `build_audio.py --verify`: 263 files bit-exact at P23, all 441 since P28, the last in P39f's final check (`22ced89`, `docs/systems/P39f.md`) |
| Audio has no effect on the simulation | **PASS** | gate `test_audio_determinism` (the seeded soak with and without audio, byte for byte; P19) and `test_valley_audio_determinism` (seeded Valley bot runs; the M6 gate's fix) |
| The web export plays it within its size and memory budgets, shipped as a multi-part pack | **PASS** (Chromium with software WebGL) | P23: the release's pck 6.43 MB shipped of 7.5, the M6 audio 3.93 MB of 4.0, a forced two-part build boots and plays, peak live samples 33.8 MB of the 44.7 MB cap, 0 console errors; the M6 gate's release 6.52 MB shipped in one part (commit `aaf3844`) |
| The web audio criterion: no silent run over 50 ms in 60 s of the Hollow's music (`audio_check.mjs --strict`) | **NOT RUN** where it can pass (NOT MET in this container) | Every run here has 153-241 holes over 50 ms, all placed on the main thread's long frames (software WebGL; the no-threads build mixes on the main thread) but one 78 ms hole in the M6 gate's second run, 1.7 ms past the placement tolerance, which failed that run's default form: the gate's runs, `0.7.0-m7`, `0.8.0-m8`, the W23 confirmation (204 holes; `docs/PERFORMANCE.md`). The owner's run on a GPU: `docs/USABILITY_SCRIPT.md` §11 (`docs/plans/FOLLOWUPS.md`, "From the M6 gate review") |
| Rigs within the draw-call budget with five enemies in view | **PASS** (a FAIL at the M6 gate, fixed in P30 and P27) | The M6 gate: the Valley walk at `low` max 268, five districts 253-268 (`docs/PERFORMANCE.md`, "Draw calls at the M6 gate"); after P27's batched HUD: max 154, p50 93, p95 143, every view at least 96 under 250 ("Draw calls after P27") |
| Thornwick stays calm on the help paths | **PASS** | slow `test_thornwick_help_path` (P22); `faction_hostile` false at the end of every help and intimidate run: the M6 gate's 18 unassisted and 2 assisted runs (`docs/BALANCE_LOG.md`, "M6 gate"), the W23 confirmation's 24 |
| The title names checkpoints, not ids | **PASS** | `test_title_checkpoint_names` (P20; since the M8 release it names where Continue wakes the giant) |
| The yard pocket | **PASS** | P22: the yard filled on the blockers layer, the navmeshes rebaked without the island |
| The nav-link test flake | **PASS** | P22: `test_world_props` waits for the map's iteration id instead of a fixed 3 s |
| The off-camera share of the hits taken under 20 % in the Valley matrix, or reported as a miss | **FAIL** at the M6 gate (20.4 %, reported as a miss, as the gate allows) | `docs/BALANCE_LOG.md`, "M6 gate" (24 runs on `013dd9c`; P22 had 16 %); later readings: 19 % in lane P39's iteration 0 and in the W23 confirmation (30 runs); the M9 gate's: §5.4 |
| The Valley balance items (P22) | **PARTIAL** | The M6 gate (`docs/BALANCE_LOG.md`, "The plan's Valley items"): the force branch's return leg 3 of 3 for both skills, the expert 12 of 12 on seeds 1-3 with no death, Thornwick never hostile (met); the novice's tries at the Ogre King (no death in 12 runs; target 1-2) and the forest's and ruins' damage (1.23 and 1.00 of maximum health; target 0.6) (missed) |
| The release `0.6.0-m6` and the play link | **PASS** | Commits `aaf3844` (the gate's release build and its web runs) and `c5ef282` ("Release 0.6.0-m6") |

### 5.2 M7: the world opens (gate after W18; release `0.7.0-m7` after the M7 polish)

| Gate item (plan §0.2, §1.3) | Result | Evidence |
| --- | --- | --- |
| Leave the Valley after the crown onto the Kingsgate shelf: from a finished save, a migrated pre-crown save and New Game | **PASS** | `test_valley_exits` (P26: the Kings' Door opens with the crown, the end screen continues), `test_campaign_travel`, `test_save_migration` (five schema 1 fixtures Continued; M7 polish: a migrated save keeps the stones it reached), gate `test_barrow_crown` (the migrated pre-crown fixture Continued and the crown claimed); the campaign hand-over runs from New Game (P38's, and the W23 confirmation's `confirm_campaign`: the Valley's New Game to the Stone Throne) |
| The far view from the Kings' Door | **PASS** | `test_skyline_view` (a landmark of each region in view from the shelf, no ridge of the skyline hiding it), `test_skyline` (P24a, P25); known: faint seams in the distant haze (§8) |
| A streamed world: determinism | **PASS** | gate `test_world_determinism`: two world walks with AI give byte-identical results (P24b) |
| A streamed world: hysteresis | **PASS** | P24a's border walks load each chunk once; no thrash on the stage-6 tour and in every bot run of the W23 confirmation (`docs/PERFORMANCE.md`) |
| Streaming budgets on the desktop (work at most 4 ms a frame, margin at least 200 m, at most 25 chunks) | **PARTIAL** | The margin (at least 250 m), no thrash and the chunk count (at most 16) are met; the work per frame is not: at the gate the real world's first walk read p99 3.3 / max 9.5 ms headless (P25; the max a props dependency's first load, which the M8 gate's preload list removed, F26), and the W23 confirmation's stage-6 tour p99 4.12 / max 4.77 ms rendered and max 12.19 ms headless (a large props part's text scene parse; exports ship binary scenes, parsed in about a tenth of the time) |
| Worst frames measured with gameplay on the web build | **PARTIAL** | Measured in headless Chromium with software WebGL on the real world (`stream_check.mjs --world`): page frames p50 217 / worst 450 ms at the gate (`docs/PERFORMANCE.md`, "The world's music on the web"), so the indicative 45 / 25 ms are not met here; real browsers NOT RUN (§5.6) |
| Terrain; seams and slopes | **PASS** | P24a, P25: no walkable face within 8 m of a chunk border over 35°; `tools/world/seam_check.gd` after every world build (64 chunks, 112 seams) |
| Navigation across chunks with size-gated masks; deterministic cross-chunk paths | **PASS** | `test_nav_maps` (P24b), gate `test_world_reachability` (P25: 119 places at the stage each needs), slow `test_unreachable_chase` |
| The Crownmarch with content, including two formation fights that threaten a stage-4 giant | **PASS** (after the gate's fixes) | P29; the M7 gate's fixes (P30, P29): slow `test_m7_gate_world` - a defied toll fort's pikes come down the road, brace twice and hit a stage-4 giant twice for 114 in about 10 s; the Raiders' wall braces twice |
| Every other region with light content (the M7 content rule) | **PASS** | `test_m7_content_rule` (P25); replaced by the regions' M8 content |
| POIs, sealed places, map, compass, pins, fast travel | **PASS** | `test_discovery`, `test_map_screen`, `test_compass`, `test_fast_travel`, `test_journal`, `test_tracked_quest` (P27); the M7 gate's fix: fast travel refuses a stone its respawn blockers refuse (`test_m7_gate_fixes`) |
| Stages 4-5 with their evolutions; every reachable weapon's stage-4 moveset | **PASS** | slow `test_growth_route_456` (P26; both cameras, first-person downward attacks), slow `test_stage_reach_bands` and `test_evolutions` (P31) |
| The Citadel breach | **PASS** | slow `test_citadel_breach` (P26: a stage-4 giant from the Kings' Door into the hall) |
| Size gates | **PASS** | P26's size-gate, trample and heave tests; P25's gate regions (a stage-5 giant goes round by the Ironway) |
| World and place audio | **PASS** (measured; heard by nobody) | `test_world_audio_coverage`, `test_world_threat_cues`, slow `test_world_music_loops` (P28) |
| The equipment and XP budgets | **PASS** | `test_world_xp_budget`, `test_world_equipment_budget` (P29), later with `test_world_budgets_wood` and `test_world_budgets_crown` (P35, P36) |
| Valley revisits at stages 4-6 | **PASS** | slow `test_valley_revisits` (P26: every Valley checkpoint measures `max_stage` 6) |
| The world's music across a region border on the web: no gap over 50 ms in 60 s (`stream_check.mjs --world --audio --strict`) | **NOT RUN** where it can pass (NOT MET in this container) | The gate's run: 98.5 s of music across three borders, 301 holes over 50 ms, every one on the main thread's long frames (`docs/PERFORMANCE.md`, "The world's music on the web"); the same at `0.7.0-m7`, `0.8.0-m8` and in the W23 confirmation (322 holes). The owner's run on a GPU (`docs/plans/FOLLOWUPS.md`, "From the M7 gate review") |
| The release `0.7.0-m7` and the play link | **PASS** | Commits `772067b` and `bf6e916`; `docs/PERFORMANCE.md`, "The 0.7.0-m7 release": the pck 15.92 MB shipped in two parts (budget 21 MB), the merge's check 205 suites, 37,537 checks, 0 failures |

### 5.3 M8: armies and giants (gate after W21; release `0.8.0-m8` with its patch)

| Gate item (plan §0.2, §1.3) | Result | Evidence |
| --- | --- | --- |
| Stage 6 and its unlocks; siege disruption with engines on the main path | **PASS** | P26 (stage 6), P31 (Earthquake), P32 (`test_siege_disruption`, slow `test_siege_battery`: seize and throw), P36 (the Moot battery on the way to the Moot); the M8 gate's F34 (the stage-6 Grow summary names it) |
| Level 12 | **PASS** | `test_talents` (P33: the last tier at level 12; the throne's level in the XP budget) |
| Talents and ancestries, saved and migrated | **PASS** | `test_talents`, `test_talent_tab`, `test_ancestry_choice` (P33); `test_shrine_choices_saved` (the M8 gate's F15: saved when made); a migrated save is offered the choice (P20, P33) |
| The 24 actives and the ultimate | **PASS** | P31 and P32: `progression_default.json`'s library of 25; `test_evolutions` |
| Refits | **PASS** | `test_titan_weapons`, `test_inventory_forge_loot` (P31: reinforce and titanforge, forge tiers) |
| Pike and shield formations, cavalry, siege crews, trolls, rival giants | **PASS** | `test_formation`, `test_formations`, slow `test_formation_perf` and `test_formation_rout_gate` (P30); `test_cavalry`, `test_siege_engine`, slow `test_world_cavalry` (P32); `test_troll`, `test_rival_giant` (P34) |
| The three bosses' phases exactly once per attempt | **PASS** | `test_matriarch`, `test_harrok`, `test_battle_boss` (P34); gate `test_bosses_seeded` |
| The disengage and yield protocols | **PASS** | `test_boss_disengage`, `test_yield_protocol`, `test_boss_no_grab`; the M8 gate's F7 and N3.1 (`test_yield_prompt_input`, slow `test_yield_prompt_mashing`) |
| All five regions with settlements, quests, peaceful options and sealed places | **PASS** | P29, P35, P36; gate walkthroughs `test_crownmarch_walkthrough`, `test_greywood_walkthrough`, `test_drowned_walkthrough`, `test_aldmere_walkthrough`, `test_stonehold_walkthrough` |
| The main thread completable in every order of every oath pair (gate tier) | **PASS** | gate `test_main_thread_combinations` (P36; the M8 gate's F3: every oath won through its resolution's own writer) |
| Budgets with formations and siege in view | **PASS** | The M8 gate's F27: every view of the world at 40 static draw calls or fewer at `low`; the formation stress with two crewed engines: draw calls max 100, CPU per tick p95 4.39 ms (the W23 confirmation, `docs/PERFORMANCE.md`) |
| The web compositions of every battle | **PASS** | The M8 gate's F9 (the web battle fits the caps with the gate garrison alive); `test_aldmere_stonehold_content` checks every battle on both compositions (W23: every phase begins once the phases before it fall) |
| The release `0.8.0-m8` and the play link (optional) | **PASS** | Commits `257113c`, `3c94c99` and `f90d3c9`; `docs/PERFORMANCE.md`, "The 0.8.0-m8 release": the release check's blocker R1 fixed in the patch (lane m8r), the pck 16.53 MB shipped in two parts (budget 23 MB), the merge's check 274 suites, 46,823 checks, 0 failures |

### 5.4 M9: a living world, shipped (W22-W23 and the M9 gate)

The W23 confirmation measured every item below on the merged code (`a7da72d`); the M9 gate's fixes
followed, so each result is the M9 gate's to give.

| Gate item (plan §0.2, §1.3, §3.22, §3.23, §6.2, §6.4) | Result | Evidence |
| --- | --- | --- |
| Wandering encounters and world events that respect streaming | ⟦SHIP: the M9 gate's verdict - its final check's living-world suites and its bot runs' invariants⟧ | P37's tests, gate `test_world_events_real`, `test_raid_millford`, `test_wander_anchors`; the bot's invariants (one event at a time, no event timer running while its chunk is unloaded, no member in an unloaded chunk) held in every run of the W23 confirmation |
| The bot completes the main thread assisted in the three policy presets and in every first-oath order (P38's acceptance) | ⟦SHIP: the M9 gate's world_assisted and world_orders runs (docs/BALANCE_LOG.md, the M9 gate's section)⟧ | W22 (P38, `e117ab9`): all six completed; the W23 confirmation (`confirm_world_orders`): the march-first and wood-first orders completed with no death, the crown-first stopped on the crown oath's 1,320 s after dying twice in the Iron Regiment's Last Stand |
| Stability: the world, 60 minutes (`--preset=world_stability`) | ⟦SHIP: the M9 gate's run, or "the W23 confirmation's pass stands" if the gate did not run it again⟧ | The W23 confirmation (`confirm_world_stability`): passed - two campaigns back to back and a third under way, no crash, no `world_blocked`, no duplicated reward, no invariant failure, nodes after each load within 0.6 %, 0 errors and 0 warnings in the run's own count |
| Stability: the Valley, 30 minutes (regression) | ⟦SHIP: as the row above⟧ | The W23 confirmation (`confirm_valley_stability`): passed, three slices and a fourth under way, nodes within 0.5 % |
| Stability: the campaign's hand-over (the Valley's New Game through the Kings' Door) | ⟦SHIP: as the row above⟧ | The W23 confirmation (`confirm_campaign`): passed, to the Stone Throne |
| A balance pass: at most three data iterations, logged; then a confirmation matrix | ⟦SHIP: PASS if the M9 gate's tuning is logged in docs/BALANCE_LOG.md with its reasons; its section's name⟧ | P39's three iterations (`docs/BALANCE_LOG.md`, "M9 (P39), iteration 1" to "iteration 3"): Harrok's chop and health, the Matriarch's regeneration and summon, the ballista bolt and the catapult stone; the W23 confirmation tuned nothing and fixed one layout defect (the Iron Regiment's thresholds) |
| Targets met, or every miss reported as a miss with its reason (P39's acceptance) | ⟦SHIP: the M9 gate's verdict - every target row below filled, each miss with its FOLLOWUPS row⟧ | The W23 confirmation reported every miss with its reason (`docs/BALANCE_LOG.md`, "Every target of plan §6.4 and §6.2"; `docs/plans/FOLLOWUPS.md`, "From the M9 confirmation") |
| Completion: the novice at least 2 of 3 seeds per preset | ⟦SHIP: the M9 gate's world matrix (bot_report.py world_targets)⟧ | W23: peaceful 3 / 3, conqueror 0 / 3 (the Matriarch's slay), mixed 2 / 3 |
| Completion: the expert 3 of 3, at most 2 deaths each | ⟦SHIP: as above⟧ | W23: peaceful 2 / 3, conqueror 0 / 3, mixed 3 / 3; deaths up to 10 |
| Every first-oath order completes | ⟦SHIP: as above⟧ | W23: the march first and the wood first yes, the crown first no (the Iron Regiment at stage 4; the gate garrison in Fort Aldmere's gateway) |
| The main path's human estimate 75-140 minutes (the novice's median) | ⟦SHIP: as above⟧ | W23: 41.3 minutes (the bot walks from objective to objective; a timed human run is the measure, NOT RUN) |
| Each segment of plan §5.15 in its range | ⟦SHIP: as above⟧ | W23: the first oath (12.3 minutes) and the roaming in range; the opening, the second oath and the Stonehold under |
| Deaths 1-3 per boss attempt sequence | ⟦SHIP: as above⟧ | W23: Harrok spared with a median of 2.5 (met); the Matriarch driven out with none, not slain; the battle not won |
| At most 2 deaths in any other segment | ⟦SHIP: as above⟧ | W23: at most 2 (met) |
| Lone humans flee or rout at least 70 % of their engaged time at stages 4-6 | ⟦SHIP: as above⟧ | W23: 4 % (the lone soldier's awe leaves it above its flee threshold) |
| Formations hold or brace at least 50 % of their engaged time while their banner lives | ⟦SHIP: as above⟧ | W23: 79 % (met) |
| At least half of the locks with a formation engaged are group or banner locks | ⟦SHIP: as above⟧ | W23: 89 % (met) |
| At least 2 engines thrown per run that reaches stage 6 | ⟦SHIP: as above⟧ | W23: 11 of 12 preset runs (the walk to the Moot passes the battery just beyond the bot's siege reach) |
| The off-camera share of the hits taken under 20 % | ⟦SHIP: as above, and the M9 gate's Valley matrix⟧ | W23: the world 16 %, the Valley 19 % (met) |
| The music in `combat` under 25 % of stage 4-6 time among only lesser enemies | ⟦SHIP: as above⟧ | W23: 43 % |
| Every slotted ability used at least once a run; none over 40 % of the ability damage | ⟦SHIP: as above⟧ | W23: Rampart Grip unused in 12 of 18 preset runs, Formation Sweep 11, Titan Stomp 9; the largest share 98 % |
| The worst streaming work frame at most 12 ms headless; the margin at least 200 m; no thrash | ⟦SHIP: the M9 gate's captures if re-run (docs/PERFORMANCE.md), else PARTIAL on the W23 numbers named as W23's⟧ | W23: the world walk 12.19 ms (a props part's text parse), the bot runs 17.9-33.9 ms three at a time; the margin 250.3 m and more, no thrash (met) |
| CPU per tick p95 at most 8 ms | ⟦SHIP: as the row above⟧ | W23: the world walk 5.89, the formation stress with two engines 4.39, the unreachable chase 3.32 ms (met); in the bot runs, the median run 8.40 ms and the war camp's sabotage 11.2-12.5 ms (three Godot processes on four shared CPUs) |
| The XP and equipment budget tests pass (margins at least 50 XP) | ⟦SHIP: the final check's budget suites⟧ | W23: the five budget suites pass, the smallest margin 70 XP (met) |
| The Valley's items hold as P22 left them | ⟦SHIP: the M9 gate's Valley matrix⟧ | W23 (`confirm_valley`, 30 runs): no item moved; the items that missed still miss (the stage-3 flee share 38 % on seeds 1-3 against 50 %, the expert's force run on seed 2 out of the Deadfall's watchdog, the segment damage over 0.6, no novice death at the Ogre King) |
| The report (`docs/HOW_IT_PLAYS.md`, plan §6.5) | ⟦SHIP: PASS once HOW_IT_PLAYS reports the M9 gate's final runs, or names which numbers stay the W23 confirmation's⟧ | Rewritten for the campaign from the W23 confirmation's runs (P39): runs per preset, order and skill, segments, deaths, bosses, growth evidence, discoveries, music, streaming, stability, readability with the audio caveat, tuning, known issues, what to try first, the NOT RUN list |
| The performance captures (plan §6.3) | ⟦SHIP: PASS if docs/PERFORMANCE.md holds the captures on the final code, else the W23 confirmation's stand as the latest⟧ | W23: `docs/PERFORMANCE.md`, "The M9 confirmation" (the world walk headless and rendered, the unreachable chase, the formation stress with two engines, the web, the bot runs by region) |
| The web world check (`world_check.mjs`: a Continue, a fast travel, a walk across borders) | ⟦SHIP: the ship step's Chromium run on the release build (§7)⟧ | W23 confirmation: its default form failed on one hole the recorder did not place on the main thread, then passed alone on the machine; the strict form is the owner's (NOT RUN) |

### 5.5 Spec §15 rules still holding (plan §0.2)

| Check | Result | Evidence |
| --- | --- | --- |
| Every M2-M5 check of spec §15 (combat correctness, camera and growth, abilities, AI and world) still passes | ⟦SHIP: the final check's result (§6.1)⟧ | Every suite of `docs/M2_M5_HANDOFF.md` §5.2-§5.5 is in the default and slow tiers; the W23 confirmation's check: 282 suites, 49,265 checks, 0 failures |
| The growth route at stages 4-6 in both camera modes, with first-person downward attacks | **PASS** | slow `test_growth_route_456` (P26) |
| Invalid grabs of engines and of a too-tall boss spend nothing | **PASS** | P32 (an engine's refusal goes through the controller: nothing spent, the reason on the HUD); `test_boss_no_grab` (the M8 gate's F13: at stages 4-6 every grab refuses a staggered Corvane and spends nothing; Harrok and the Matriarch are immune to grabs too) |
| Boss phases exactly once per attempt | **PASS** | `test_matriarch`, `test_harrok`, `test_battle_boss`; gate `test_bosses_seeded` |
| Fleeing units have reachable destinations on streamed ground | **PASS** | P24b (flight points snapped and accepted only when a path reaches them), slow `test_formation_rout_gate` (P30: routs through a breached gate), the M7 gate's budgeted searches (`test_m7_gate_world`) |
| No invalid spawn at any Valley checkpoint for any stage | **PASS** | slow `test_valley_revisits` (P26) |

### 5.6 Spec §16: performance, stability, usability and handoff

| Check | Result | Evidence |
| --- | --- | --- |
| A real reference PC recorded | **NOT RUN** | The owner's hardware is unknown; `docs/PERFORMANCE.md` has the blank table |
| 1080p `low`: frame time p95 ≤ 16.7 ms, p99 < 33.3 ms, exported build | **NOT RUN** | Needs a real GPU; the commands are in `docs/PERFORMANCE.md` ("Commands") |
| GPU and CPU profiled separately | **PARTIAL** | PerfProbe reports GPU and CPU render times apart (N/A here: no GPU) and the simulation's CPU per tick, by district, chunk or region |
| The stress route: 12 combatants, 20 breakables, ≤ 40 debris | **PASS** (frame time NOT RUN) | slow `test_stress_smoke` (60 s of the stress bot in every slow-tier run); the 300 s route last measured at M5 (`docs/M2_M5_HANDOFF.md` §6.2); the 40-member formation stress with two engines in the W23 confirmation (CPU per tick p95 4.39 ms, draw calls max 100) |
| Simulation CPU per tick p95 ≤ 8 ms (container, indicative) | ⟦SHIP: the M9 gate's reading if it re-measured (docs/PERFORMANCE.md), else PARTIAL on the W23 numbers⟧ | W23: met on the captures (the world walk 5.89, the formation stress 4.39, the unreachable chase 3.32 ms) and the Valley's runs (median 5.65 ms); not in the Aldmere March's big fights of the bot runs (11.2-12.5 ms three at a time); the reference PC is the measure |
| Draw calls ≤ 250 in any view | **PASS** (container, software OpenGL) | The Valley walk at `low` max 154 after P27; the world's stage-6 tour at `low` max 91 and the formation stress max 100 in the W23 confirmation; every static view of the world at most 40 (the M8 gate's F27) |
| Distant actors drawn as a low-detail representation | **PASS** | AI tier 2's one-box proxy, the renderer's distance level of detail (P22), the mid-distance merged mesh at `low` and the crowd renderer (P30) |
| A visible active-enemy budget | **PARTIAL** | 12 combatants (the director); no counted member spawns at the cap (the bot's invariant held in every W23 run), but members already in the world when their faction turns hostile count, so the count passed 12 in seven W23 runs (13-17 for at most 0.35 s; 16 for 43.6 s in one) (`docs/PERFORMANCE.md`, "The M9 confirmation"; FOLLOWUPS) ⟦SHIP: the M9 gate's reading of the counted combatants if it changed⟧ |
| Loads: the world's starting ring behind the loading screen | **PASS** headless; web **NOT RUN** in a real browser | `WorldRoot.is_ready()` holds the giant until the ring and its navigation are ready (at most 8 s, then a warning); in Chromium with software WebGL here both loads end on the 8 s warning (FOLLOWUPS, "From W23 (lane P39f, the web part)") |
| A long session with no crash, softlock, duplicated reward or unrecoverable targeting state | ⟦SHIP: the M9 gate's stability runs (§5.4)⟧ | The W23 confirmation's 60-minute world run and 30-minute Valley run passed (bot); a human session NOT RUN |
| Usability: three new players (the Valley's first 10 minutes; 20 minutes of the world from the Kings' Door) | **NOT RUN** | Needs people. `docs/USABILITY_SCRIPT.md` §3 (Parts A-C), §4-§5, §10 |
| The listening pass on speakers and headphones (balance, harshness, threat readability, music fatigue) | **NOT RUN** | Nobody can listen in the container; `docs/USABILITY_SCRIPT.md` §8 (§8.5 and §8.7 the world's) |
| Menus usable with a controller | **PARTIAL** | Every screen by synthetic pad events (`test_ui_focus`), the map's and journal's pad bindings (`test_map_screen`, `test_journal`, `test_tracked_quest`); a real pad NOT RUN (`docs/USABILITY_SCRIPT.md` §6, rows 16-21 for the map, pin, journal and track) |
| HUD readable at common resolutions | **PASS** | `test_hud_layout` at five resolutions (P27's batching rules, P39f's wrapped and backed lines), `test_shrine_panel_fit` (1280 x 720) |
| Real desktop browsers (load time with the multi-part pack, streaming hitches, audio in a hidden tab, the strict audio checks) | **NOT RUN** | `docs/USABILITY_SCRIPT.md` §11 with the three strict commands; `docs/PERFORMANCE.md`, "Web build checklist" |
| A debug panel for state, stage, stamina, attack id, target, frame time and AI state | **PASS** | F3 in debug builds (`ui/debug_panel.gd`), with every `debug_info_providers` node (the audio engine among them) |
| Debug cheats disabled in exported play | **PASS** | Gated by `OS.is_debug_build()`; the shipped exports are release builds (§7) |

### 5.7 The Ship gate (plan §3.24, §6.6)

| Item | Result | Evidence |
| --- | --- | --- |
| The final check on the final code: every scene and the world rebuilt with no diff, every suite in all three tiers, `--audio`, the soak | ⟦SHIP: PASS or FAIL from tools/check.sh --build --slow --gate --audio on the final commit (its hash, suites, checks, failures, the three tier times, the soak)⟧ | §6.1 |
| README, ARCHITECTURE and DECISIONS consolidated; this handoff | ⟦SHIP: PASS once every ⟦SHIP placeholder is filled and test_ship_docs passes on the final documents⟧ | README.md, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, this document; `tests/unit/test_ship_docs.gd` |
| Screenshots of the world: a world tour beside the bot, the Kingsgate shelf's view first | ⟦SHIP: the tour's command, its run, and the shots added to docs/screenshots/ and the README's gallery⟧ | |
| The Linux export: the soak and an assisted bot run, headless | ⟦SHIP: §7's Linux row⟧ | §7 |
| The Windows export built (not launched) | ⟦SHIP: §7's Windows row⟧ | §7 |
| The Web export: `tools/build_web.sh` within 23 MB, every part at most 15 MB, no test content | ⟦SHIP: §7's Web row⟧ | §7 |
| The Chromium checks: `audio_check.mjs` and `world_check.mjs` pass in their default form | ⟦SHIP: §7's web-check rows (default verdicts; the strict criterion stays NOT RUN, §5.1, §5.2)⟧ | §7 |
| Version `0.9.0-m9`; the launcher's notes describe the build | ⟦SHIP: the version commit and the launcher's notes (test_launcher_notes passes)⟧ | |
| The play link republished | ⟦SHIP: the orchestrator's republish of the play link with 0.9.0-m9 (§3)⟧ | |
| The pull request and the merge to `main` | ⟦SHIP: the pull request and the merge commit⟧ | |

## 6. Test results with measured evidence

### 6.1 The final check

⟦SHIP: `tools/check.sh --build --slow --gate --audio` on the final commit: the commit, CHECK PASSED or the failure, the rebuild (every scene and the world byte-identical, the seam check's chunks and seams), the audio pipeline (its tests, the files regenerated bit-exact, the budget line: imported MB of 9.5, the Valley's and the world's registered seconds), the suites (N suites, N checks, 0 failures; default, slow and gate seconds against 75 s, 8 and 50 minutes), the 120 s soak (errors, warnings, fences, loot), the whole check's wall time; and the default tier alone for its 75 s budget⟧

The checks on the way, each on its own code (so none is the final one):

| Check | Code | Suites, checks, failures | Default / slow / gate | Rebuild, audio, soak |
| --- | --- | --- | --- | --- |
| P23's package check (M6) | `pkg/P23` | 138 suites, 26,682 checks, 0 failures | 49.3 / 69.6 / 50.4 s | 263 audio files bit-exact; the soak 0 errors |
| The M7 polish merge (`0.7.0-m7`) | the merge | 205 suites, 37,537 checks, 0 failures | 48.3 / 165.8 / 267.4 s | the seams (64 chunks, 112 seams), 441 audio files bit-exact, the soak 0 errors |
| The `0.8.0-m8` release patch's merge | `a0d59b7` | 274 suites, 46,823 checks, 0 failures | 64.9 / 249.0 / 423.5 s | both full builds byte for byte, the seams, 441 files bit-exact, the soak 0 errors and 0 warnings |
| P39f's final check (W23) | `22ced89` | 281 suites, 48,121 checks, 0 failures | 61.7 / 263.4 / 543.0 s | every scene rebuilt byte for byte, the seams, 441 files bit-exact, the audio 9.229 MB of 9.5, the soak 0 errors |
| The W23 confirmation's check | `a7da72d` (with its gate test and report tool) | 282 suites, 49,265 checks, 0 failures | 71.0 / 313.3 / 660.1 s | no rebuild or `--audio` in this run; the soak 0 errors |

Sources: `docs/systems/P23.md` ("Runtime added to the suites"), `docs/PERFORMANCE.md` ("The 0.7.0-m7
release", "The 0.8.0-m8 release"), `docs/systems/P39f.md` ("Part web", "Tests"), `docs/systems/P39.md`
("Tests and the full check"). The default tier stayed within its 75 s budget in each (decision 64).

### 6.2 Bot runs and the stability runs

⟦SHIP: the M9 gate's final bot runs on the final code - the world matrix (runs per preset, order and skill: completed, human estimate, deaths), P38's acceptance runs assisted, the three stability runs (passed or not, with nodes, errors and warnings), the Valley matrix - each with its batch tag and commit, from docs/BALANCE_LOG.md's M9 gate section and docs/HOW_IT_PLAYS.md⟧

The W23 confirmation's runs (on `a7da72d`, before the M9 gate's fixes; `docs/BALANCE_LOG.md`, "M9
confirmation"; `docs/HOW_IT_PLAYS.md`):

| Batch | What | Result (W23 confirmation) |
| --- | --- | --- |
| `confirm_world` | the world matrix: the novice and the expert on seeds 1-3 of the three presets, each first-oath order once (21 runs, unassisted) | 12 reach the Stone Throne; no crash, invariant failure, error, warning or duplicated reward; no stop diagnosed `world_blocked` |
| `confirm_ir4`, `confirm_ir5` | the crown order's battle at stage 4 and at stage 5 | stage 4: six attempts at 0.78-0.91 of the bar, six deaths, no Charge; stage 5: stopped on a stuck in Fort Aldmere's gateway |
| `confirm_world_orders` | P38's acceptance orders, assisted | march first and wood first completed with no death; crown first stopped on the oath's time |
| `confirm_world_stability` | 60 minutes of the world, assisted, three presets in a loop | passed: two campaigns and a third under way, nodes within 0.6 %, 0 errors and 0 warnings in the run's count, CPU per tick p95 6.93 ms |
| `confirm_valley_stability` | 30 minutes of the Valley | passed: three slices and a fourth under way, nodes within 0.5 %, CPU per tick p95 6.52 ms |
| `confirm_campaign` | the Valley's New Game through the Kings' Door to the Stone Throne, assisted | passed: the throne at 1,972 s simulated, no death |
| `confirm_valley` | the Valley matrix (30 runs) | every novice run complete, the expert 11 of 12; the off-camera share 19 % |

Godot prints an exit report of resources still held by process-lifetime caches after a run that
completed a whole campaign (523 resources, 96 Jolt shapes, 163 meshes): it follows each run's result,
counts no error, and the same fixed set every time (not a leak during play; `docs/systems/P39f.md`).

## 7. The exports and the web checks

⟦SHIP: the ship step's exports from the final code and their checks, as the table below for `0.8.0-m8`: Linux (`builds/linux/Giantborn.x86_64`, bytes; the 120 s soak headless with errors and warnings; an assisted novice bot run headless - command, completed or not, simulated time, deaths, invariant failures, errors), Windows (`Giantborn.exe` and `Giantborn.console.exe` bytes; built, not launched), Web (`index.wasm` and `index.pck` bytes raw, gzipped and as shipped, the number of parts and the largest, against 23 MB; no test content; the data valid without data/test), and the Chromium checks on that release build - audio_check.mjs, stream_check.mjs --world --audio, world_check.mjs, world_start_check.mjs - each with its default verdict, holes over 50 ms and the longest, peak live samples against the cap, console errors⟧

The releases on the way (none is the final build):

| Build | Linux export | Windows export | Web: shipped `index.pck` | Web checks (Chromium, software WebGL) |
| --- | --- | --- | --- | --- |
| `0.6.0-m6` (the M6 gate's release, `aaf3844`) | not recorded | not recorded | 6.52 MB in one part (budget 7.5 MB) | `audio_check.mjs`: two runs, 200 and 166 holes over 50 ms; the first OK in its default form, the second FAILED on one 78 ms hole placed 1.7 ms past the tolerance |
| `0.7.0-m7` (after the M7 polish) | 88,530,232 bytes; the 120 s soak 0 errors; an assisted novice Valley run completed in 446.4 s, 0 errors | 122,113,832 bytes, built, not launched | 16,697,160 bytes = 15.92 MB in two parts (budget 21 MB) | `stream_check.mjs --world --audio` OK (default; 283 holes, all on the main thread), `audio_check.mjs` OK (default), the launcher's open-world start; 0 console errors |
| `0.8.0-m8` (with the release patch) | 89,896,096 bytes (the candidate's); the soak 0 errors, 0 warnings; an assisted novice Valley run completed in 446.4 s, 0 errors | 123,479,696 bytes and `Giantborn.console.exe` 188,928, built, not launched | 17,331,492 bytes = 16.53 MB in two parts of 8,665,746 (budget 23 MB) | `stream_check.mjs --world --audio` OK (default; 279 holes), `audio_check.mjs` OK (default; 153 holes), `world_start_check.mjs` OK; 0 console errors |
| W23 confirmation (`a7da72d`) | not built | not built | 17,474,792 bytes = 16.67 MB in two parts of 8,737,396; 2,752 packed files, no test content | `audio_check.mjs` OK (default; 204 holes), `stream_check.mjs --world --audio` OK (default; 322 holes), `world_check.mjs` FAILED its first run on one unplaced hole, OK run again alone (605 holes); 0 console errors |

Sources: commit `aaf3844`; `docs/PERFORMANCE.md`, "The 0.7.0-m7 release", "The 0.8.0-m8 release" and
"The M9 confirmation". The engine (`index.wasm`) is 37,700,666 bytes, 12,528,700 as shipped, since
M5. Every hole over 50 ms counted above was placed on the main thread's long frames of software WebGL
but the ones named; the plan's strict criterion (no hole at all) is the owner's to run on a GPU
(§5.1, §5.2, §9).

## 8. Known bugs and limitations

From `docs/HOW_IT_PLAYS.md` ("Known issues") and the open rows of `docs/plans/FOLLOWUPS.md`, as the W23
confirmation left them. ⟦SHIP: strike or update each row the M9 gate fixed or changed (its FOLLOWUPS strikes and HOW_IT_PLAYS' known issues after the M9 gate) and add every row it opened; a row then names the M9 gate's state, not W23's⟧

| Item | Kind | State in the W23 confirmation | Where |
| --- | --- | --- | --- |
| The conqueror's slay of the Troll Matriarch: no novice and no expert slew her (the novice down to 9-14 % of her health, six deaths each; the expert's brazier lure no longer pays on the cleared den) | Balance | open | FOLLOWUPS, "From the M8 gate review" and "From the M9 confirmation" |
| The Iron Regiment at stage 4 (the crown first): not won; the fort's ballistae 74 % of the damage taken; assisted, the Last Stand reached and lost | Balance | open | FOLLOWUPS, "From the M8 release check" |
| Fort Aldmere's gateway: the gate garrison's pike formation leaves about 5 m beside each flank, less than a stage-4 or stage-5 giant needs; two crown runs of three stopped there | Layout / bot | open | FOLLOWUPS, "From the M9 confirmation" |
| The war camp's shield wall stands across the King's Road at the camp's entrance: a giant at peace presses against it (30 stuck moments) | Layout | open | the same |
| The bot fights the Raiders' Hollow from the King's Road (its leg passes the wall at 23 m) | Bot | open (the world is right) | the same |
| The walk to the Moot passes the Moot battery beyond the bot's siege reach: one run of 14 threw no engine | Bot | open | the same |
| The peaceful experts die to the toll fort's tower archers on the march's help | Bot | open | `docs/HOW_IT_PLAYS.md`, "Known issues" |
| The siege of Skarn at stage 5 (Ulfra's plea before stage 6) does not end while the novice fights the line | Balance | open (measured in lane P39's targeted run; not repeated) | FOLLOWUPS, "From the M8 gate review" |
| Lone humans do not flee a stage-4 giant (4 % of their engaged time against 70 %) | Balance | open | FOLLOWUPS, "From the M9 confirmation" |
| The music is in `combat` 43 % of the stage 4-6 time among only lesser enemies (target under 25 %) | Audio data | open | the same |
| Abilities: Rampart Grip, Formation Sweep and Titan Stomp unused in half the runs or more; one ability over 40 % of the ability damage | Bot policy | open | the same |
| The pace: the main path about 41 minutes played straight by the bot (target 75-140) | Measure | the owner's timed run | the same |
| The Valley: the stage-3 flee share 38 % (target 50 %); the expert's force run on seed 2 out of the Deadfall's watchdog; segment damage over 0.6; no novice death at the Ogre King; 14.5 minutes of human estimate (target 20-30) | Balance | open | FOLLOWUPS, "From the M6 gate review" and "From the M9 confirmation" |
| The director's counted combatants pass 12 when a faction turns hostile with its members in the world | Performance rule | open (a decision) | the same |
| CPU per tick over 8 ms in the Aldmere March's big fights (three runs at a time on four CPUs) | Performance | the reference PC is the measure | the same |
| The worst streaming work frame headless is a large props part's text scene parse (12.19 ms; exports ship binary scenes) | Performance | open (the world builder's, if it must hold headless) | FOLLOWUPS, "From W23 (lane P39f, the web part)" |
| The off-camera threat sting is muted for siege engines and cavalry charges against big giants (the router weighs the attacker's own height, not the action's override) | Audio | open | FOLLOWUPS, "From P32" |
| The siege trains of the wander tables are not shipped | Content | open (a framework change) | FOLLOWUPS, "From P37", "From P36" |
| The world bot's lock invariant fails for one tick when a locked formation's last member routs | Bot | open | FOLLOWUPS, "From W23 (lane P39f, the web part)" |
| On a slow web client the world's starting ring is not ready in 8 s (the giant enters with a warning while the rest streams) | Web | the owner's real-browser pass | the same |
| Raiders waiting their turn at a house give it up | AI | open (the raid's pace) | FOLLOWUPS, "From W23 (lane P39f, fix-up round 1)" |
| Far people and giants are plain boxes (the distance LOD's proxy); faint seams in the distant haze; the war camp's riders do not sally beyond their leash (by design) | Visual / content | left | FOLLOWUPS, "From the M8 screenshot pass" |
| Godot's exit-time report after a completed campaign (process-lifetime caches; no leak during play) | Engine report | recorded, not fixed | `docs/systems/P39f.md` |
| Bulwark takes x0.4 from every side (plan: frontal hits) | Ability | not built | P31, P33 |
| The Citadel gate's lintel visual: a stage-5 or stage-6 giant's head passes through it | Cosmetic | open | P26 |
| The music's audio criteria on the web (§5.1, §5.2) | Web | NOT RUN where they can pass | FOLLOWUPS, "From the M6 gate review", "From the M7 gate review" |
| Placeholder art, text button glyphs, physics interpolation off, soldiers fleeing together through a gate can jam | By design | | README §9 |
| Human, listening, real-pad, reference-PC and real-browser gates | | NOT RUN | §5.6, §9 |

## 9. The owner's tasks (plan §6.7; NOT RUN here)

1. **A listening pass** on speakers and headphones: the balance, harshness, threat readability, music
   fatigue, the melody rotation and the silence windows (`docs/USABILITY_SCRIPT.md` §8; the world's
   §8.5 and §8.7; the hidden-tab mute §8.6).
2. **Three usability sessions**: the Valley's first 10 minutes as in M5, then 20 minutes of the world
   from the Kings' Door - the view, finding the way, the map, the compass, pins, fast travel,
   formations at stage 4, a sealed place (`docs/USABILITY_SCRIPT.md` §2-§5, §3.5 Part C, §10).
3. **A timed human run** of the Valley (its pacing, which the bot can only floor) and of the world's
   main path (each §5.15 segment).
4. **Real browsers**: load time with the multi-part pack, a Continue and a fast travel, streaming
   hitches, frame rate, audio in a hidden tab, memory over a session, saves, a pad - and the three
   strict audio checks on a machine with a GPU, the runs that count for the M6, M7 and M9 web rows:
   `node tools/web/audio_check.mjs --strict`, `node tools/web/stream_check.mjs --world --audio
   --strict`, `node tools/web/world_check.mjs --strict` (`docs/USABILITY_SCRIPT.md` §11).
5. **The reference PC table**: the Windows export's measurement commands, V-Sync on and off
   (`docs/PERFORMANCE.md`, "Commands" and "Reference PC results").
6. **A real gamepad**: the new map, journal, track and pin bindings and the web build's pad
   (`docs/USABILITY_SCRIPT.md` §6, rows 16-21).

## 10. The owner's two open decisions

1. **A licence for the project and its generated assets.** Nothing is licensed yet:
   `assets/audio/PROVENANCE.md` records that every sound is original and generated by the committed
   tools, with no recordings or third-party samples, and leaves the licence as "the project's licence;
   the owner chooses it" (DECISIONS.md §1.3). Choosing one is a `LICENSE` file at the root and that
   line of the provenance record.
2. **Whether to commit the lossless music and ambience masters.** Today the generators are the
   masters: the effects' WAV masters are committed, the music and ambience ship as Ogg only, and
   `build_audio.py --verify` proves that every master and every Ogg regenerates bit-exact on the
   recorded toolchain (a deviation from spec §13's "keep audio masters"; DECISIONS.md decision 34 and
   §1.3). Committing them adds about 60 MB of FLAC (plan §6.7), rewritten on every tuning pass:
   `python3 tools/audio/build_audio.py --masters-out=assets/source/audio`. ⟦SHIP: the FLAC masters' size measured on the final audio (python3 tools/audio/build_audio.py --masters-out=<a scratch folder>, then du -sh), or delete this placeholder and keep the plan's estimate⟧

## 11. Next milestone

**M10: the realistic giant, with a character creator.** It follows `0.9.0-m9`; no plan for it is in the
repository yet. Spec §16 asks that recurring failures be fixed before content is added, so the
smallest next step is the owner's sign-off of this build:

1. The owner's tasks of §9 - the usability sessions, the listening pass, the timed runs, real browsers
   with the strict audio checks, the reference PC and a real gamepad - and the two decisions of §10.
2. What they find becomes data and tuning first, then the open engineering rows of §8 that recur in
   play.
3. Then M10's plan: the realistic giant and the character creator, on the systems this build
   consolidates (`docs/ARCHITECTURE.md`); stages 7-10 and the rest of the deferred list (§4.2) stay
   open for later milestones.
