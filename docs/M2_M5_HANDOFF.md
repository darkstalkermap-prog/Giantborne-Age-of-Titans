# M2-M5 handoff: the Valley of Broken Kings

Spec §16 lists what every milestone handoff must contain: changed files and a runnable project, the
exact engine version, launch and export instructions, controls, implemented versus deferred
features, test results with measured evidence, known bugs, and the next smallest milestone. This
document provides each for milestones M2 to M5 (the M0/M1 handoff is
[M1_HANDOFF.md](M1_HANDOFF.md)), with the gate table of spec §15 and §16.

**In one paragraph.** The Valley of Broken Kings is playable from New Game to the crown in all four
village outcomes, on top of the M1 combat sandbox (which is still there). A bot that plays the whole
slice finishes it: the assisted novice in every outcome, the unassisted novice in 17 of 18 runs and
the expert in 4 of 4; a 30-minute run had no crash, softlock, duplicated reward or stuck targeting.
The final check rebuilds every scene (no diff) and passes 103 suites with 13,617 checks and 0
failures, then a 120 s soak with 0 errors. Everything was measured in a Linux container without a
GPU, a gamepad, a Windows PC or a human player, so the usability, real-controller, reference-PC and
real-browser gates are **NOT RUN**: their scripts and commands are ready for the owner (§5).

## 1. Engine, build and environment

| Item | Value |
| --- | --- |
| Engine | **Godot 4.6.3-stable, official build `7d41c59c4`** (standard build, GDScript) |
| Project version | `0.5.0-m5` (`project.godot`; shown on the title screen and in the pause menu; written into saves) |
| Renderer / physics | Compatibility (OpenGL 3.3, WebGL 2 on the web), Jolt Physics, 60 physics ticks per second |
| Branch | The M2-M5 integration branch, from `main` @ `e89001f` (M0 + M1) |
| Where it was built and tested | A Linux container with 4 shared CPU cores: headless runs (tests, bots, stress), real rendering through Xvfb and Mesa llvmpipe (software OpenGL), Chromium (Playwright) with SwiftShader (software WebGL) for the web build |
| Not available here | A Windows PC, a real GPU, a gamepad, human players, real desktop browsers |

**What was actually run for this handoff** (not only code-reviewed): the whole check sequence with
every scene rebuilt and the slow suites; the default suite alone (for its time budget); on the final
code, an assisted novice Valley run, the 30-minute run and the stress route; the Linux, Windows and
Web release exports; the Linux export headless (the 120 s soak and a whole assisted Valley run); a
rendered screenshot tour of the Valley beside the bot; the web build in Chromium (boot, title, New
Game, the save across a page reload, Continue, the mouse capture from the title). The balance
matrices were run by P17a and P17b on the same game code (§6.4).

## 2. Changed files and the runnable project

The project opens as it is in Godot 4.6.3 (`project.godot`); README §2 has the steps. Exports are
built locally into `builds/` (git-ignored; README §7).

From `e89001f` (M1) to this branch, in 21 packages and 12 waves (plan `docs/plans/M2_M5_PLAN.md`):
about 840 files changed, about 96,500 lines added and 3,800 removed, in about 210 commits
(counting this handoff's).

| Area | What is there now |
| --- | --- |
| `scripts/` | 132 GDScript files, about 33,300 lines (M1: about 7,400 with `ui/`): the combat core with statuses, projectiles and grabs; the giant as eight components; seven enemy and NPC archetypes with their brains; the level framework, encounter director and boss arena; props, interactables, shrines, forges; progression, loot, quests, dialogue and tutorials; session, saves and checkpoints; the Valley bot, metrics, diagnosis and perf probe |
| `ui/` | 34 files, about 5,600 lines: the HUD and its ten widgets, the screen stack and its eight screens (title, pause, shrine, dialogue, inventory, attributes, forge, end), pad and keyboard navigation |
| `data/` | 152 validated JSON records in 18 folders (M1: 23) |
| `scenes/` | 44 generated scenes: the giant, 7 enemies, 2 NPCs, 16 world props and the sandbox, the Valley and its 8 districts, 7 test levels; `assets/nav/` holds the Valley's 4 navmeshes |
| `tools/` | 17 scene builders, `SceneKit`, the Valley layout table, `gd.sh`, `check.sh`, `run_tests.sh`, `run_bots.sh`, `bot_report.py`, `build_web.sh`, the screenshot tours, the draw-call probe |
| `tests/` | 103 suites (31 unit, 59 integration, 13 slow), about 27,900 lines, and their support helpers (M1: 15 suites) |
| `docs/` | This handoff, README, ARCHITECTURE, DECISIONS, HOW_IT_PLAYS, PERFORMANCE, USABILITY_SCRIPT, BALANCE_LOG, the plan, its follow-ups, one system doc per package, screenshots |
| `web/launcher.html` | The play link's page |

What each package built, its public APIs, data, decisions and tests: `docs/systems/P01.md` ...
`P18.md`; consolidated in [ARCHITECTURE.md](ARCHITECTURE.md) and [DECISIONS.md](DECISIONS.md).

## 3. Launch, export and controls

- **Run:** README §2 (editor F5 or `godot --path .`; the title screen; command-line shortcuts).
- **Controls:** README §3, taken from `data/input/default_bindings.json` (every binding can be changed
  in the game; F1 / H shows the current loadout's controls).
- **Tests, bots, measurements:** README §6; `docs/PERFORMANCE.md` for every performance command.
- **Export:** README §7 (Windows, Linux, Web); `tools/build_web.sh` for the play link's files.
- **The play link:** <https://claude.ai/artifact/2UYupKVL1xE6pttiZ6NLqe> (served from
  `web/launcher.html` and the files `tools/build_web.sh` writes).

## 4. Implemented versus deferred

| Spec §14 Valley scope | Status |
| --- | --- |
| About 400 x 400 m | Done: seven districts and the impassable hills, cliffs round the edge, a river with one bridge |
| One ancestry | Done (neutral; saved and shown; no modifiers) |
| Three growth profiles, growth at shrines | Done: 3.66 / 5.49 / 7.92 m; growth only at shrines, refused safely when blocked (spec §15) |
| Five enemy archetypes | Done: soldier, wolf, archer, mage, ogre; plus the Ogre King, the sparring post and the village's civilians |
| Eight abilities | Done: Heavy Footfall, Sweeping Blow, Stone Skin, Crushing Grip, Boulder Hurl, Runic Bolt, Ancestral Mend, Thunder Roar, plus the Titan Surge ultimate |
| Three simple weapons | Done: club, sword, hammer (each with a reforged variant), plus the uprooted tree |
| A small village, forest, ruined fortress, boss | Done: Thornwick (guards, villagers, the elder, a forge), the Old Wood, the ruins of the Broken Kings, the Ogre King at Kingsfall |
| Checkpoint saves, minimal quest and inventory flow | Done: one save slot with backup; the main quest's 16 stages, the optional tutorial, the village quest and its two branches; inventory, attributes, loot, one forge upgrade |
| The §14 sequence | Done in order: the Hollow (both cameras), wolves and an ogre, level 3 and stage 2, Boulder Hurl, the village (help, intimidate or force), the practice gate, the boss, level 5 and stage 3, the tree against the Deadfall |
| Peaceful option, intimidation without kill XP, rewards that cannot be farmed | Done: help (cache or ogre), intimidation (guards stand down), once-flags for every reward |
| Death reloads the last checkpoint; no saving during a grab or execution | Done: at least 60 % health, nothing lost; checkpoints wait for a stable state |
| Accelerated quest XP labelled as prototype pacing | Done (HUD, the Hollow's sign, the progression record) |
| 20-30 minutes | Measured by the bot's human estimate at about 15 minutes (§6.4); a human run is NOT RUN |

**Deferred, by plan (§0.4):** growth stages 4-10 (stage 4 shows only as the locked Citadel Gate);
dragons, rival giants, trolls, titans and siege crews; siege equipment and its morale event (the hook
exists); open-world streaming and a 1 km² map; the 24-ability library, ability upgrades, talent trees
(points accrue), more ancestries and the Worldbreaker ultimate; formations as lock groups, limb
poise, executions and boss grapples; building collapse and terrain destruction beyond the authored
practice gate; crafting beyond the one forge upgrade, inventory weight and loss; dispel, damage over
time and status combinations; multiplayer, crowds, cinematic dialogue, localization, several save
slots, cloud saves, fast travel and a map; production art, animation and audio; physics
interpolation; the Unreal engine spike. **Also not built:** the Hollow's optional cottage arch (a
stage-1 shortcut; the village's alleys show the same idea); a distance level of detail for enemy
rigs (§7).

## 5. The gates

Legend: **PASS** = verified by running the game or engine here. **PARTIAL** = verified here, with a
part that only a real PC, pad, browser or person can confirm. **FAIL** = measured and not met.
**NOT RUN** = needs hardware or people that are not available here. Test names are in `tests/`
(`unit/`, `integration/`, `slow/`).

### 5.1 Milestone exit gates (spec §15)

| Gate | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| M0 Setup | Project opens, arena runs, version pinned, export launches | PASS (Windows: PARTIAL) | `--import` clean; every scene loads in the suites; 4.6.3 pinned in `project.godot`, README and here; the Linux release export ran headless (§6.3); the Windows `.exe` and `.console.exe` were exported but **not launched** (no Windows here) |
| M1 Combat sandbox | Controls, both cameras, one enemy, damage and defence, breakable | PASS | `M1_HANDOFF.md`; all its tests still pass; the 120 s soak breaks fences and awards loot (§6.1) |
| M2 Combat depth | Targeting, three-hit combo, four abilities, two enemy roles | PASS | `test_abilities_m2` (Footfall, Sweeping Blow, Stone Skin, Runic Bolt, plus Mend, Roar and Titan Surge: costs, cooldowns, statuses), `test_hostile_targeting`, `test_wolf` (lunge, flank, pack target switching, the light chain on a wolf at the giant's feet), the M1 combo and lock tests; the M2 review's two findings fixed |
| M3 Scale proof | Three profiles, safe growth, grab/throw, persistent gate | PASS | `test_growth` (blocked growth changes nothing, no invalid spawn), `test_growth_route` (slow: the route at 3 sizes x 2 cameras), `test_grab_throw`, `test_boulder_hurl`, `test_save_load_world` (a cracked practice gate reloads cracked); the M3 review's finding fixed |
| M4 Playable Valley | Complete loop, five roles, eight abilities, boss, save/load | PASS | `test_valley_walkthrough` (slow: the quest line for all four outcomes); the assisted novice bot completes all four outcomes (P17a) and this package's assisted help_cache run on the final code (§6.2); `test_boss`, `test_boss_arena`, `test_valley_boss`; `test_session_flow` (Continue restores the save exactly), `test_checkpoint_triggers`; the M4 review's two findings fixed |
| M5 Test and tune | Usability, performance, controller and stability gates pass | PARTIAL | Stability **PASS** (30-minute run); performance **PARTIAL** (simulation CPU met; draw calls not met with five or more enemies in view; frame and GPU times NOT RUN); controller **PARTIAL** (every menu by synthetic pad events; a real pad NOT RUN); usability **NOT RUN** (script delivered). Details below. |

### 5.2 First-delivery minimum pass (spec §15, still holding)

| Check | Result | Evidence |
| --- | --- | --- |
| Launch without missing dependencies; move and attack; switch perspective; fight one enemy; block, parry, dodge; die and reset; break a fence | PASS | The M1 suites (all passing) and the 120 s soak (§6.1): attacks, blocks, dodges, camera toggles, kills, a reset, fence breaks, loot |
| No crashes in a 10-minute run | PASS | 30 minutes of Valley play with 0 errors on the final code (§6.2; P17b's run before it too); a 451 s Valley run on the Linux release export (§6.3) |
| Inputs give feedback on the next physics tick | PASS | `test_input_feedback_on_next_tick` |

### 5.3 Combat correctness (spec §15)

| Check | Result | Evidence |
| --- | --- | --- |
| Worked example: 37 unblocked, 9 blocked; heavy 66 | PASS | `test_damage_resolver`, `test_dummy_shows_worked_example_numbers` |
| Stamina never below zero | PASS | `test_resources_poise` (randomised), `test_stamina_never_negative_in_play` |
| One sweep over three colliders = one hit; two enemies each hit once | PASS | `test_one_sweep_three_hurtboxes_one_hit`, `test_two_enemies_each_hit_once`; dedup per projectile in `test_abilities_m2` |
| Walls stop attacks | PASS | `test_wall_stops_attack`; a wall stops a bolt (`test_abilities_m2`) |
| 100 activations charge cost and cooldown once each | PASS | `test_hundred_activations_charge_once_each`, `test_cooldown_spam_spends_once_per_cooldown` (the six M2 abilities) |
| Dodge and parry boundaries | PASS | `test_dodge_invulnerability_boundaries`, `test_parry_window_boundaries`; `test_dexterity_windows` (Dexterity never moves them) |
| Queue expires after 0.15 s | PASS | `test_input_buffer_expires_after_015s` |
| Releasing lock on death leaves no stale target | PASS | `test_lock_releases_on_death_same_tick`; the bot's lock invariant in every run |

### 5.4 Camera and growth (spec §15)

| Check | Result | Evidence |
| --- | --- | --- |
| A fixed obstacle route in all three sizes and both modes (doors, slopes, ceilings, a wall) | PASS | `test_growth_route` (slow, six runs on the growth course: doorway, low passage, ramps, wall lane) and the M1 route `test_obstacle_route` (slow) |
| No persistent camera penetration or obscured crosshair | PASS | The same route checks the camera and a centre-ray crosshair probe every tick; `test_first_person_while_holding_never_covers_the_crosshair`, `test_first_person_light_chains_keep_the_crosshair_clear_at_stage_3`. Comfort needs people: NOT RUN |
| No invalid spawn after growth; blocked growth leaves everything intact | PASS | `test_no_invalid_spawn_after_growth`, `test_blocked_growth_in_the_trap_changes_nothing`, `test_growth_clearance_counts_actors_and_a_refusal_changes_nothing` |
| Camera switches preserve position, resources, target and attack timing | PASS | `test_camera_switch_preserves_state` |
| First-person downward attacks against humans | PASS | `test_first_person_downward_attacks_hit_a_human`; stages 2-3 against a soldier and a wolf in both cameras (`test_growth_targeting`) |

### 5.5 Abilities, AI and world (spec §15)

| Check | Result | Evidence |
| --- | --- | --- |
| Invalid grabs spend nothing; interrupted grabs release both | PASS | `test_invalid_grabs_spend_nothing_and_name_their_reason`, `test_an_interrupted_grab_releases_both`, `test_a_crushing_grip_that_closes_on_nothing_gives_back_its_stamina_and_cooldown` |
| Cooldowns prevent repeated activation | PASS | `test_cooldown_spam_spends_once_per_cooldown`, `test_stone_skin_recast_at_5_s_is_rejected_by_the_real_cooldown` |
| Target death during casting is handled | PASS | `test_target_death_mid_cast_leaves_no_stale_hits`, `test_target_death_mid_cast_is_handled` (mage) |
| Fleeing enemies have a reachable destination | PASS | `test_valley_flee` (slow: the return patrol and the courtyard in the Valley), `test_flee_destinations_are_reachable_on_the_sandbox_navmesh` |
| Boss phases occur exactly once | PASS | `test_phases_happen_exactly_once`; `test_ten_seeded_phase_2_charges_end_against_stone` |
| Save/load restores character, loadout, quest flags and gate state | PASS | `test_a_cracked_gate_growth_sword_loadout_and_flags_survive_save_and_load`, `test_continue_from_the_title_restores_the_save_exactly`; the boss checkpoint in `test_valley_walkthrough` |
| Destroyed objects never award loot twice | PASS | `test_fence_breaks_once_and_loot_once`, `test_crates_roll_their_loot_table_once_per_world_id`, `test_a_raider_drops_its_loot_table_once_even_after_a_reload`; the bot's "no reward twice" invariant in every run |
| Corrupt newest save → backup recovery with a clear message | PASS | `test_corrupt_main_recovers_from_the_backup`, `test_invalid_content_also_falls_back_to_the_backup`, `test_an_invalid_main_save_never_replaces_the_backup`, `test_future_version_is_rejected_kept_and_never_becomes_the_backup` |

### 5.6 Performance (spec §16, plan §5.4)

| Check | Result | Evidence |
| --- | --- | --- |
| A real reference PC recorded | NOT RUN | The owner's hardware is unknown; `docs/PERFORMANCE.md` has the blank table |
| 1080p `low`: frame time p95 ≤ 16.7 ms, p99 < 33.3 ms, exported build | NOT RUN | Needs a real GPU; the commands are in `docs/PERFORMANCE.md` ("Commands": `Giantborn.console.exe`, the stress route and the Valley walk) |
| GPU and CPU profiled separately | PARTIAL | PerfProbe reports GPU and CPU render times apart (N/A here: no GPU) and the simulation's CPU per tick (measured) |
| Stress route: 12 combatants, 20 breakables, ≤ 40 debris, 5 minutes | PASS (frame time NOT RUN) | 300 s, `low`, headless, on the final code (§6.2): 12 active (mean 11.8), all 20 breakables broken (138 breaks), debris up to 40, 0 deaths, 0 errors, 0 warnings; CPU per tick p50 2.22 / p95 3.69 / p99 5.13 ms (P17b's run: 2.27 / 3.72 / 5.12) |
| Simulation CPU per tick p95 ≤ 8 ms (container, indicative) | PASS | On the final code (§6.2): stress 3.69 ms, 5.40 ms over the 30-minute run, 6.01 ms in the help_cache run; at most 6.37 ms in every run of P17b's final balance matrix (three runs at once) |
| Distant actors drawn as a low-detail representation | PASS | AI tier 2 shows a one-box proxy (`test_blockers_lod`; the Valley walk's comparison: 12 proxies 262 draw calls, 12 rigs 653) |
| A visible active-enemy budget | PASS | 12 (the director); at most 12 active and 12 hostiles within 40 m in every bot run (invariant) |
| Draw calls ≤ 250 in any Valley view | **FAIL** with five or more enemies in view | The static world draws at most 93 per view at `low` (221 at `medium`); each full-rig enemy adds about 33, so the Valley walk peaks at 656 (p50 256) at `low`. Deferred (§7) |
| Valley load ≤ 3 s headless, ≤ 6 s web | PASS headless; web NOT RUN | Headless about 0.3 s (P10b's slow test). Web, indicative only (Chromium with software WebGL here): New Game → the first checkpoint in IndexedDB after 14.2 s; NOT RUN in a real browser |
| Navmeshes ≤ 100 KB each | PASS | 15-19 KB (`test_valley_smoke`) |
| Web `.pck` ≤ 4 MB packed | PASS | `index.pck` 2,356,808 bytes; 1,260,098 gzipped; 1,680,132 as shipped (gzip + base64) |

### 5.7 Usability, controller and the 30-minute session (spec §16)

| Check | Result | Evidence |
| --- | --- | --- |
| Three new players complete the tutorial encounter (2 of 3 unaided, naming heavy attacks, blocking and dodge timing); confusion, camera discomfort, accidental ability use and time to defeat recorded | NOT RUN | Needs people. `docs/USABILITY_SCRIPT.md`: the protocol (5 minutes of Sandbox, the first 10 Valley minutes), the observation sheet, the questionnaire |
| A 30-minute Valley session with no crash, softlock, duplicated reward or unrecoverable targeting state | PASS (bot) | `tools/run_bots.sh --preset=stability` on the final code (§6.2): 1,800 s simulated, three slices completed in a row (help_cache, help_ogre, intimidate), the fourth (force) started; 0 errors, 0 warnings, 0 breaches, 0 invariant failures, 0 duplicated rewards, 0 teleports, 0 deaths; node count 5 s after each of the 4 loads 1,404 every time. P17b's run before it had the same result. A human session: NOT RUN |
| Menus usable with a controller | PARTIAL | Every screen by synthetic pad events (`test_ui_focus`: title, pause, shrine, dialogue, inventory, attributes, forge, end); a real pad: NOT RUN (`docs/USABILITY_SCRIPT.md` §6 checklist) |
| HUD readable at common resolutions | PASS | `test_hud_layout` at 1280 x 720 up to 2560 x 1440 (no overlapping panels; edge warnings clear of every panel) |

### 5.8 Handoff, debug and shipping (spec §16, plan §3.21)

| Check | Result | Evidence |
| --- | --- | --- |
| A debug panel for state, stage, stamina, attack id, target, frame time and AI state | PASS | F3 in debug builds (`ui/debug_panel.gd`), with every enemy and every `debug_info_providers` node |
| Debug cheats disabled in exported play | PASS | Gated by `OS.is_debug_build()` (the router's debug edges F6-F8, F5 and F9 in `main.gd`, the panel); the shipped exports are release builds |
| Windows export | PARTIAL | Exported (`Giantborn.exe` 107 MB, `Giantborn.console.exe`); not launched (no Windows) |
| Linux export runs headless with the bot | PASS | §6.3 |
| A rendered screenshot tour of the Valley | PASS | `tools/valley_tour.gd` beside the bot: 107 shots of a help_cache run to the end screen; ten in `docs/screenshots/` |
| Web build: boots, title, New Game, `.pck` size, the save survives a page reload, the title click takes the mouse | PASS (Chromium, software WebGL) | §6.5 |
| Web build in real desktop browsers (Chrome, Edge, Firefox, Safari on a real GPU), the play link in its hosting frame, a gamepad in the browser | NOT RUN | Needs a real computer; the play link is republished by the orchestrator after the merge |

## 6. Test results with measured evidence

### 6.1 The check sequence on the final code

`tools/check.sh --build --slow` on the tree of commit `400e974` (every change to the game is in or
before it; the later commits change documentation and one comment in a tool script): **CHECK
PASSED** in 2 min 58 s of wall time.

- Import, then **every scene rebuilt** by the 17 builders (44 scenes and the four navmeshes): the
  rebuild left every committed file byte-identical (no diff), then import again.
- **103 suites, 13,617 checks, 0 failures**: the default suite 90 suites, 11,072 checks, 58.7 s
  summed; the slow suites 13 suites, 2,545 checks, 73.5 s summed (the walkthrough of all four
  outcomes 18.0 s, the 3-size route, the Valley boss, flee, clearance, stress and bot smoke tests).
- **The 120 s soak** (`--autoplay=120`, seeded): exit 0, **0 errors, 0 warnings**; attacks 41, hits
  resolved 33, enemy kills 4, fence breaks 2, debris max 10, loot awards 2, resets 1.

**The default suite alone** on the final code (commit `28496a1`, for the plan's 75 s budget): 90
suites, 11,072 checks, 0 failures, 58.4 s summed, **60.2 s of wall time**. The first full run of
this package (on a fresh import) had one failure, `test_world_props.test_a_broken_gate_opens_its_nav_link`
(§7); it passed in the four full runs since (this check and the default suite alone included) and
in six runs of its suite alone.

### 6.2 Bot runs, the 30-minute run and the stress route on the final code

One assisted novice run of the help_cache outcome on the final code (`tools/run_bots.sh
help_cache:novice:1:assist`, headless, `--fixed-fps 60`, 182 s of wall time):

| Completed | Simulated | Human estimate | Deaths | Breaches | Invariant failures | Duplicated rewards | Teleports | Errors / warnings | Peak active / hostiles within 40 m | CPU per tick p50 / p95 / p99 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| yes (help_cache) | 520 s | 810 s (13.5 min) | 0 | 0 | 0 | 0 | 0 | 0 / 0 | 11 / 7 | 3.08 / 6.01 / 7.90 ms |

Segments (raw minutes): the Hollow 0.5, the forest 1.3, the Grove 0.2, the village 2.2 (the quarry
detour), the ruins 1.9, the boss 0.8, the return 1.7. The Linux export's run of the intimidate
outcome is in §6.3; the rendered tour's help_cache run in §6.6.

**The 30-minute run** (`tools/run_bots.sh --preset=stability`: `--bot-loop --bot-assist`, novice,
help_cache first, `--autoplay=1800`; headless, 586 s of wall time): **passed**, exit 0.

| Slice | Outcome | Simulated | Human estimate | Deaths | Duplicated rewards | Stuck events (all recovered) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | help_cache, completed | 520 s | 810 s | 0 | 0 | 0 |
| 2 | help_ogre, completed | 519 s | 797 s | 0 | 0 | 2 |
| 3 | intimidate, completed | 515 s | 754 s | 0 | 0 | 1 |
| 4 | force, started (in the ruins' courtyard when the 1,800 s ran out) | 245 s | 389 s so far | 0 | 0 | 1 |

Over the whole run: 1,800 s simulated, 4 level loads, **0 errors, 0 warnings, 0 breaches, 0
invariant failures, 0 duplicated rewards, 0 teleports**; node count 5 s after each load 1,404 every
time (no growth); every 60 s 1,411-2,187 as encounters spawn and despawn; static memory 113-135 MB
(part of it the run's own per-tick samples); at most 12 active enemies; CPU per tick p50 2.92 /
p95 5.40 / p99 7.16 ms, max 50.2 ms (a level load).

**The stress route** (`docs/PERFORMANCE.md`, "Commands": `--level=res://scenes/test/stress_arena.tscn
--scenario=stress --autoplay=300 --graphics=low`, headless, 79 s of wall time): exit 0, the
scenario's own checks all passed. 300 s at stage 2, six laps; 12 combatants active (mean 11.8, never
below 9; 12 respawns), all 20 breakables broken at least once (138 breaks), debris up to 40, 419
hits resolved, 0 deaths, **0 errors, 0 warnings**; CPU per tick p50 2.22 / p95 3.69 / p99 5.13 ms
(max 23.3 ms), the simulation alone p95 2.62 ms; nodes 1,220-1,245; static memory 101-104 MB.

### 6.3 The exports

- **Linux** (`builds/linux/Giantborn.x86_64`, 73 MB, release): headless `--fixed-fps 60 --
  --no-user-settings --autoplay=120` exits 0: attacks 41, hits resolved 33, enemy kills 4, fence
  breaks 2, debris max 10, loot awards 2, **0 errors, 0 warnings** (15 s of wall time). A whole
  assisted novice Valley run on the export (`--mode=valley --new-game --scenario=valley --bot-assist
  --bot-village=intimidate`): **completed** in 451 s simulated (690 s human estimate) and 2 minutes
  of wall time, 0 deaths, 0 breaches, 0 invariant failures, 0 duplicated rewards, 0 teleports,
  **0 errors**; CPU per tick p50 2.33 / p95 4.76 / p99 7.31 ms (a release build).
- **Windows** (`builds/windows/Giantborn.exe`, 107 MB, and `Giantborn.console.exe`): exported,
  **not run**.
- **Web** (`builds/web/`): `index.wasm` 37,700,666 bytes (12,528,700 packed), `index.pck` 2,356,808
  (1,680,132 packed); about 14 MB to download in all.

### 6.4 Earlier measurements on the same game code (P17a, P17b)

The game's code and data at this handoff are those P17b measured, plus one HUD message text (§7):

- **Balance** (P17b's `final` batch: 22 unassisted runs, plan §5.6): the novice completes 17 of 18
  (every help_cache, help_ogre and intimidate seed; two of three force seeds), median 1 death; the
  expert 4 of 4 with 0-1 deaths; human estimate about 15 minutes (target 20-30), raw about 10;
  most deaths in the ruins' courtyard (10 of 19) and the forest (5). Every run: 0 errors, 0
  invariant failures, 0 teleports. Full tables: [HOW_IT_PLAYS.md](HOW_IT_PLAYS.md).
- **Growth changes the fights** (median of the novice runs): soldiers hold formation 0 % of their
  engaged time at stage 1 and 58 % at stage 2, flee or rout 55 % at stage 3; a stage-2 soldier dies
  in 0.54 of the stage-1 time.
- **Assisted runs** (P17a, the M4 complete-loop gate): all four outcomes completed, 0 deaths,
  14-16 minutes of human estimate.
- **The 30-minute run and the stress route** (P17b): both passed, as this package's runs on the
  final code did (§6.2): three slices in a row with 0 errors and 1,404 nodes after every load; the
  stress route at CPU per tick p95 3.72 ms.

### 6.5 The web build in Chromium

`tools/build_web.sh` (run without `XDG_DATA_HOME`, so it finds the export templates) wrote
`builds/web/`; it was served locally and driven with Playwright's Chromium 153 using SwiftShader
(software WebGL) on the container's shared CPU. Numbers below are indicative only.

| Check | Result |
| --- | --- |
| The launcher page | Fits at 1280 px without a sideways scroll; the poster is the Valley at New Game |
| Play: download, unpack, start the engine | The engine started 5.7 s after Play (4.6 s after a reload) |
| The title screen | "Prototype 0.5.0-m5 - Godot 4.6.3-stable (official)", no saved game yet, New Game focused, no Quit |
| New Game | The Valley's Hollow with its HUD, tracker and first prompt; the first checkpoint was in IndexedDB 14.2 s after the key press (`/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json`) |
| Walking | W moves the giant; about 2 frames a second with software WebGL (meaningless for a real GPU) |
| The save survives a page reload | After the reload the file is still in IndexedDB, the title offers Continue (focused) with "Saved game: level 1, stage 1, at valley.shrine.hollow", and Continue loads the Valley at the Hollow Shrine |
| The `low` preset | The Valley renders without sun shadows (the desktop's `medium` has them) |
| The mouse (headed Chromium under Xvfb) | Not captured on the title or after clicking Settings; captured by the New Game click and still captured in the Valley; Esc gives it back |
| Console errors | None in the headless run (boot, New Game, walking, reload, Continue); one "404 (File not found)" in the headed run with no failed request of the page itself, most likely the browser's own favicon request |
| Sizes | `index.wasm` 37,700,666 bytes (12,528,700 packed), `index.pck` 2,356,808 (1,260,098 gzipped, 1,680,132 packed); about 14 MB to download |

### 6.6 What the rendered tour showed

The tour (help_cache, the assisted novice bot, real-time stepping under Xvfb, `medium`) finished the
slice in 10:16 of game time with 0 deaths at level 8. Its shots showed two problems no headless run
had: the HUD's "Destroyed" message named the district instead of the prop (fixed, with a regression
test), and on the return leg the stage-3 giant's blows struck the village guards beside the bridge
fight and turned Thornwick hostile on a help path (recorded for the next milestone, §7).

## 7. Known bugs and limitations

| Item | Severity | Notes |
| --- | --- | --- |
| Draw calls with five or more full-rig enemies in view exceed 250 | Performance | About 33 per enemy rig; the static world is within budget. A distance LOD for rigs would help distant crowds only (the courtyard's fight is within 45 m); close fights need rigs that cost fewer draw calls themselves. `docs/PERFORMANCE.md`, FOLLOWUPS. |
| Thornwick can turn hostile on a help path's return leg | Gameplay | The guards' posts stand beside the return patrol's fight at the barricade; two stray blows within 30 s are an offence by design (decision 17). Seen once (the tour). Move the posts back or keep guards out of nearby fights; FOLLOWUPS. |
| Pacing short for the bot (about 15 minutes against 20-30) | Balance | The estimate counts no exploring or learning; a timed human run decides. |
| The novice rarely needs a second try at the Ogre King; segment damage over target in the forest and courtyard; about a fifth to a quarter of hits come from off camera (target under 20 %) | Balance | `docs/HOW_IT_PLAYS.md` "Known issues" |
| A yard north of Thornwick's square is outside the giant's navigation | Minor | The bot backs out along its breadcrumbs; a player can walk out (P17a) |
| Soldiers fleeing together through an opened gate can jam on its narrow path | Minor | No agent avoidance (P15) |
| The title's save line names the checkpoint by its id ("at valley.shrine.hollow") | Cosmetic | Seen in the web check |
| `test_world_props.test_a_broken_gate_opens_its_nav_link` failed once | Test flake | In the first full run on this branch (a fresh import): the path never crossed the opened link within 3 s (Godot's asynchronous navigation map). It passed in the four full runs since (the final check included) and in six runs of its suite alone. P08 records the same race (its decision 17). |
| Placeholder art, no audio, physics interpolation off, text button glyphs | By design | README §9 |
| Human, real-pad, reference-PC and real-browser gates | NOT RUN | §5 |

## 8. Next smallest milestone

**M5 sign-off by the owner, then fix what it finds.**

1. Run the three usability sessions with `docs/USABILITY_SCRIPT.md` (the Sandbox, then the first 10
   Valley minutes) and the real-controller checklist (§6 of the script).
2. Record the reference PC and run the Windows export's measurement commands in
   `docs/PERFORMANCE.md` (the stress route and the Valley walk, V-Sync on and off): frame time p95 /
   p99, GPU time, draw calls.
3. Open the play link in Chrome or Edge and Firefox on a real computer: load time, frame time in
   the village, the save across a reload, a gamepad.
4. Fix what recurs (spec §16): data and tuning first; then the two known engineering items - a
   distance LOD (or merged parts) for enemy rigs, and the guards beside the bridge fight.

After that, the next content step is a design decision for the owner: deepen the Valley (stage 4
and the Citadel, more of the 24-ability library, talent trees) or run the optional engine spike
(spec §15).
