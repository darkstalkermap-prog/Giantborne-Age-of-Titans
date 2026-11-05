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
| `tests/test_runner.gd` stalls instead of failing when a suite has a parse error (it calls `new()` on the broken script); only check.sh's time limit ends it. Make a suite that fails to load count as a failure. | P17a | `tests/test_runner.gd` |
| ~~P10b's slow `test_valley_walk.test_forest_encounters_spawn_from_data` checks the navmesh 3 ticks after load and may flake under load. Make it wait with `ValleyProbe.wait_for_navigation`.~~ **Fixed in P15.** | P15 | `tests/slow/test_valley_walk.gd` |

## From the wave 7 merge (P14 measurements)

| Item | Owner | Notes |
| --- | --- | --- |
| Valley draw calls are far over the §5.4 budget of 250 per view: low preset p50 493 / max 1,084, medium p50 657 / max 1,398 (stress arena p50 860). Batch static props and scenery per district (MultiMesh or merged meshes), and cut or drop shadows at the low preset. P15 must not add unbatched dressing; P17b owns the reduction. | P17b (P15: do not make it worse) | `tools/builders/valley.gd`, `data/world/level_valley.json`, `docs/PERFORMANCE.md` |
| Encounter activation causes a 13-25 ms tick, and the first load of an archetype's scene costs about 100-150 ms (one forced activation of four kinds took 387 ms). Preload every archetype scene the level's encounters use at level load, and spread spawns over several ticks. | P17a | `scripts/world/encounter_director.gd`, `scripts/world/level_root.gd` |

## From the M4 gate review (wave 8)

| Item | Owner | Notes |
| --- | --- | --- |
| Taking the crown while enemies are aware defers the slice-completion checkpoint; choosing "Quit to title" on the end screen then loses that save. Take (or force) the completion checkpoint before the end screen can quit. | P17a | `scripts/quests/quests.gd`, `scripts/core/game_session.gd` |
| Pad A on the death screen confirms at once, so a player mashing jump or LT+A (Heavy Footfall) skips the death screen. Ignore confirm input for a short delay after death (or require a fresh press). | P17a | `scripts/main.gd` |
| The force branch's return leg puts 16 hostile combatants around the giant (guards turned hostile plus the ambush), above the 12-active budget. Bring it within budget or make the budget hold for faction members. | P17b | `data/world/encounter_village_guards.json`, `scripts/world/encounter_director.gd` |

## For shipping

| Item | Owner | Notes |
| --- | --- | --- |
| The play link (artifact version 3) shows a Valley screenshot as its poster, but `tools/build_web.sh` still copies the M1 sandbox shot `docs/screenshots/01_spawn_third_person.jpg` to `poster.jpg`. Refresh `docs/screenshots/` with Valley shots and point the build script at the new poster. | P18 | `tools/build_web.sh`, `docs/screenshots/` |
| Web performance is unmeasured on real hardware. In this container the Valley renders at about 1.7 fps through Chromium's software WebGL (SwiftShader) with the CPU shared with other work, which says nothing about a real GPU. Record the web checklist in `docs/PERFORMANCE.md` as NOT RUN unless a real browser is available. | P18 | `docs/PERFORMANCE.md` |
