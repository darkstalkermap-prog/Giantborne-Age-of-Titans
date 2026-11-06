# Follow-ups from milestone reviews

Minor findings that a milestone review confirmed but did not fix. Each one names the package
that owns the files involved. That package fixes its items (with a regression test) as part of
its own work and reports it.

## From the M2 gate review (wave 1)

| Item | Owner | Notes |
| --- | --- | --- |
| ~~Runic Bolt locked onto a target beyond 25 m fizzles, while the hotbar shows it as ready and names the target. The hotbar should show "Out of range" (or the cast should not be accepted).~~ **Fixed in P16.** | P16 (UX pass) | `scripts/actors/player/player_attack.gd`, the hotbar's `preview_reason` path |
| ~~Titan Surge's +25% poise damage does not apply to the poise damage that the player's parry deals.~~ **Fixed in P11a** (regression test: 40 rising to 50 poise). | P11a | `scripts/combat/combat_entity.gd` |
| ~~Wolves never show status tints (for example Thunder Roar's slow), because `QuadrupedRig` is not an `ActorRig` and HitFeedback only tints `ActorRig`s.~~ **Fixed in P09** (regression test in test_telegraphs). | P09 | `scripts/presentation/hit_feedback.gd`, `scripts/presentation/quadruped_rig.gd` |

## From the M3 gate review (wave 3)

| Item | Owner | Notes |
| --- | --- | --- |
| ~~Crushing Grip spends 20 stamina and starts its 10 s cooldown when the grab fails the recheck at attachment. Spec §15 says invalid grabs spend nothing: refund (or never charge) a grab that fails the attachment recheck.~~ **Fixed in P16.** | P16 | `scripts/actors/player/player_grab.gd` |
| ~~The growth clearance check ignores the actors layer, so the new capsule can grow into a static dummy or a nearby enemy. Include actors (or push them clear) and keep "blocked growth changes nothing".~~ **Fixed in P16.** | P16 | `scripts/actors/player/player_growth.gd` |
| ~~The growth "combat" gate counts only hits from the last 10 s, so an aware enemy closing in does not block growth although the refusal text says "Enemies are near". Gate on aware enemies within the shrine radius as well.~~ **Fixed in P16.** | P16 | `scripts/actors/player/player_growth.gd` |
| ~~A schema-valid but otherwise invalid main save is copied over the only valid backup on the next checkpoint. Only back up a main file that fully loads.~~ **Fixed in P16.** | P16 | `scripts/core/save_io.gd`, `scripts/core/save_slots.gd` |
| ~~`--mode=valley --new-game` overwrites a newer build's save without keeping the rejected copy (the title screen path keeps it).~~ **Fixed in P16.** | P16 | `scripts/core/game_session.gd` |
| ~~Loading a checkpoint from the pause menu (or F9) while dead skips the death floor (60% health, full stamina).~~ **Fixed in P16.** | P16 | `scripts/core/game_session.gd` |
| ~~Quit to title keeps `level_override` from a Continue, so Sandbox and New Game then load the saved test level.~~ **Fixed in P16.** | P16 | `scripts/core/game_session.gd` |

## From the wave 6 merge

| Item | Owner | Notes |
| --- | --- | --- |
| ~~The boss bar (P11a, top centre, x -320..320, y 14..58) overlaps the quest tracker region (P13, x -356..-16, y 14..132) by 36 px at 1280 px width. Lay them out so neither covers the other at 1280x720 and larger.~~ **Fixed in P16.** | P16 | `ui/hud/boss_bar.gd`, `ui/hud/quest_tracker.gd` |
| ~~`tests/test_runner.gd` stalls instead of failing when a suite has a parse error (it calls `new()` on the broken script); only check.sh's time limit ends it. Make a suite that fails to load count as a failure.~~ **Fixed in P17a.** | P17a | `tests/test_runner.gd` |
| ~~P10b's slow `test_valley_walk.test_forest_encounters_spawn_from_data` checks the navmesh 3 ticks after load and may flake under load. Make it wait with `ValleyProbe.wait_for_navigation`.~~ **Fixed in P15.** | P15 | `tests/slow/test_valley_walk.gd` |

## From the wave 7 merge (P14 measurements)

| Item | Owner | Notes |
| --- | --- | --- |
| ~~Valley draw calls are far over the §5.4 budget of 250 per view: low preset p50 493 / max 1,084, medium p50 657 / max 1,398 (stress arena p50 860). Batch static props and scenery per district (MultiMesh or merged meshes), and cut or drop shadows at the low preset. P15 must not add unbatched dressing; P17b owns the reduction.~~ **Static world fixed in P17b**: every prop merged into one mesh per material (`SceneKit.merge_meshes`), two shadow splits, no sun shadows at `low`; the static world draws at most 93 calls per view at `low`, 221 at `medium` (regression test in `test_followup_fixes_p17b`). The actors are the rest: see the next row. | P17b (P15: do not make it worse) | `tools/builders/valley.gd`, `data/world/level_valley.json`, `docs/PERFORMANCE.md` |
| ~~With enemies in view the Valley still passes 250 draw calls: each full-rig enemy costs about 33 (its rig's boxes and its weapon), so five or more in view do (the Valley walk at `low`: p50 256, largest view 656; the stress arena p50 295). Give rigs a visual level of detail by distance: the renderer's `visibility_range_end` on a rig's parts and `visibility_range_begin` on its one-box proxy from about 45 m, with `EnemyActor.set_lod_tier` leaving the proxy to the renderer at tiers 0 and 1 (`docs/PERFORMANCE.md`, "Draw calls after P17b").~~ **Deferred by P18 to the next milestone, documented as a known limitation** (README, `docs/M2_M5_HANDOFF.md`, `docs/PERFORMANCE.md`). The fix is not small: it changes three actor files, needs a range per archetype (the 8.5 m Ogre King must not turn into a box across its own 80 m arena), and can only be judged rendered; and it would not bring the dense fights under 250 (the courtyard's eight enemies are all within 45 m). A view stays under 250 with up to about four full-rig enemies. **Largely fixed in P22** (decision 9): every rig is one vertex-coloured mesh per animated pivot plus its weapon with one material per actor (the stress arena's twelve combatants 221 -> 77 draw calls, `tests/slow/test_rig_draw_calls.gd`), and a distance level of detail by record (`render_lod_m`: the renderer swaps a rig for its one-box proxy from 40-70 m; none on the Ogre King; `tests/integration/test_render_lod.gd`). The Valley walk at `low`: p50 201, p95 251, max 268 (was 256 / 653 / 656; `docs/PERFORMANCE.md`): the largest view of each district is now 238-268, at the budget rather than under it (Thornwick's square with thirteen people within 45 m is the largest); the stress arena's whole view p50 295 -> 227. | P22 | `scripts/actors/enemy_actor.gd`, `scripts/presentation/actor_rig.gd`, `scripts/presentation/quadruped_rig.gd` |
| ~~Encounter activation causes a 13-25 ms tick, and the first load of an archetype's scene costs about 100-150 ms (one forced activation of four kinds took 387 ms). Preload every archetype scene the level's encounters use at level load, and spread spawns over several ticks.~~ **Fixed in P17a.** | P17a | `scripts/world/encounter_director.gd`, `scripts/world/level_root.gd` |

## From the M4 gate review (wave 8)

| Item | Owner | Notes |
| --- | --- | --- |
| ~~Taking the crown while enemies are aware defers the slice-completion checkpoint; choosing "Quit to title" on the end screen then loses that save. Take (or force) the completion checkpoint before the end screen can quit.~~ **Fixed in P17a.** | P17a | `scripts/quests/quests.gd`, `scripts/core/game_session.gd` |
| ~~Pad A on the death screen confirms at once, so a player mashing jump or LT+A (Heavy Footfall) skips the death screen. Ignore confirm input for a short delay after death (or require a fresh press).~~ **Fixed in P17a.** | P17a | `scripts/main.gd` |
| ~~The force branch's return leg puts 16 hostile combatants around the giant (guards turned hostile plus the ambush), above the 12-active budget. Bring it within budget or make the budget hold for faction members.~~ **Fixed in P17b**: a hostile faction's armed members count toward the budget and wait for room (regression tests in `test_followup_fixes_p17b`; the balance matrices' peak is 12 hostiles within 40 m). | P17b | `data/world/encounter_village_guards.json`, `scripts/world/encounter_director.gd` |

## For shipping

| Item | Owner | Notes |
| --- | --- | --- |
| ~~The play link (artifact version 3) shows a Valley screenshot as its poster, but `tools/build_web.sh` still copies the M1 sandbox shot `docs/screenshots/01_spawn_third_person.jpg` to `poster.jpg`. Refresh `docs/screenshots/` with Valley shots and point the build script at the new poster.~~ **Fixed in P18**: `docs/screenshots/` holds Valley shots rendered by `tools/valley_tour.gd` beside the bot (the M1 shots moved to `docs/screenshots/sandbox_m1/`), and `tools/build_web.sh` copies `01_hollow_start.jpg`. | P18 | `tools/build_web.sh`, `docs/screenshots/` |
| ~~Web performance is unmeasured on real hardware. In this container the Valley renders at about 1.7 fps through Chromium's software WebGL (SwiftShader) with the CPU shared with other work, which says nothing about a real GPU. Record the web checklist in `docs/PERFORMANCE.md` as NOT RUN unless a real browser is available.~~ **Recorded in P18**: `docs/PERFORMANCE.md`'s web checklist has what headless Chromium can show (the packed sizes, booting, New Game, the save surviving a reload, the forced `low` preset, the mouse capture from the title, console errors) and keeps real-browser frame times and load times **NOT RUN** (no real browser or GPU here). | P18 | `docs/PERFORMANCE.md` |

## From the ship package (P18)

| Item | Owner | Notes |
| --- | --- | --- |
| ~~Seen once in P18's rendered tour (help_cache, assisted novice bot, real-time stepping): fighting the return patrol at the barricade after the boss, the stage-3 giant's blows struck the village guards standing at their posts beside it (the "Thornwick's people cower" warning, then hostility about 1.5 s later), so Thornwick turned hostile on a help path and its ambush waited in the square. Decision 17 makes a direct hit on a village member an offence; the trouble is the posts (guard posts 3 and 4 at (88, -26) / (88, -14), the captain at (94, -23.5)) inside the reach of the bridge fight. Keep the guards out of that fight (posts farther from the barricade, or neutral guards stepping back from a fight near them), then check with the bot that no help or intimidate run turns the village hostile.~~ **Fixed in P22**: guard posts 3 and 4 at (73.5, -30) / (73.5, -10) and the captain at (74, -20), each at least 22 m from the barricade, and a guard at peace steps back 10 m from an enemy within 12 m of it (`FactionState`); `tests/slow/test_thornwick_help_path.gd` fights the return patrol at the barricade with every AI on and no offence; the bot's help and intimidate runs end with `faction_hostile` false (`docs/systems/P22.md`). | P22 | `data/world/encounter_village_guards.json`, `tools/data/valley_layout.json`, `scripts/world/faction_state.gd` |

## From P22 (wave 13)

| Item | Owner | Notes |
| --- | --- | --- |
| `data/audio/mix_default.json` names `level.stress_arena` and `level.director_test` in its surfaces; P22 moved those test-only records to `data/test/`, which the Web release leaves out, so the release's data fails `DataValidator` (`tools/build_web.sh` prints a WARNING from `tools/release_data_check.gd`) and the released game would stop at its data error screen. Drop the two surface keys (or move them into a test-only mix record under `data/test/`). | The W13 merge (P21's file) | `data/audio/mix_default.json` |
| `docs/HOW_IT_PLAYS.md` "Known issues" still lists the village yard's navmesh pocket, Thornwick on the help paths and the draw calls with many enemies in view, which P22 fixed, and the off-camera share and the Valley's balance items with M5's numbers (P22's are in `docs/BALANCE_LOG.md` and `docs/systems/P22.md`). | The M6 gate review | `docs/HOW_IT_PLAYS.md` |
| Two Valley bot runs on P22's build (intimidate novice seed 3 at the Grove; help_cache novice seed 2 in the village, iteration 1) crashed with SIGSEGV in the audio mixing thread (`AudioDriverDummy`'s thread loop -> `AudioDriver::audio_server_process`; identified from the stripped binary's disassembly; the log's "propagate_notification() ... caller thread" error is the crash handler's own `NOTIFICATION_CRASH` from that thread). Both ran while the container was oversubscribed (load 7-9 on 4 cores); neither reproduced when the same seed ran again; 0 of the 24 runs at P22's base crashed. P22 makes `QuadrupedRig` emit `footfall`, which P19's `CueRouter` already connects to (wolves' paw steps: more voice starts), but a stress-arena soak with six times the wolves' footfall cues (3 x 150 s) did not crash. Find the race in the audio path (the voice pool's `set_stream` on a recycled 3D player while the mixer runs, the exit release, or the engine's mixer) before M6 ships. | The audio owner (P21 in W13, P23) | `scripts/audio/voice_pool.gd`, `scripts/audio/audio_director.gd`, `scripts/audio/cue_router.gd` |
