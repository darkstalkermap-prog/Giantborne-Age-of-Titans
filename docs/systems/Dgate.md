# Dgate - Milestone D's gate: what was broken, what was fixed, what is left

The gate reviewed milestone D (D1 the Frostbound Titan, D2 the Stormcaller, D3 stage 9, merged on the released
`0.16.0-m16`, `b83d269`; the diff `git diff b83d269..43d5992`) on `pkg/dgate` from the D3 merge (`43d5992`), as the last
check before the owner's checkpoint. The version is prepared as **0.17.0-m17** (not shipped: the owner approves); the
save stays **schema 3** and no restore shrinks or lowers a giant. Every suspicion was run before it was called a finding -
the real open world headless and under Xvfb with the compatibility renderer (the capture tours, their stills from the
gameplay camera), the titans' arenas, the test tiers - and every fix has a test that fails before it. The decisions are
in `docs/DECISIONS.md` §3.12 (DG-1..DG-10); the numbers in `docs/BALANCE_LOG.md`, "Dgate"; what is left in
`docs/plans/FOLLOWUPS.md`, "From the milestone D gate". Evidence outside the repository (stills, logs) is in the
hand-back's folder.

## Findings

| # | Severity | Finding | How confirmed | Fix | Test |
| --- | --- | --- | --- | --- | --- |
| DG-1 | major (progression) | **The XP curve left milestones E-F no levels.** On the spec's 100 + 50 x (L - 1) all the way, the Frostbound's kill (3,600 XP) took the guaranteed path from level 15 to 19 and the Stormcaller's fall to the cap. | D3's path test, printed level by level (below). | Levels 1-15 keep the spec's costs; from 15 the colossus levels cost 2,500, 4,000, 6,000, 7,500 and 9,000 (about a titan each). No reward changed. A restored 0.16 giant of level 16 or more keeps his level and his share of the way through it on the new costs (`Progression.lifted_xp`: never less XP). | `test_progression_rules`, `test_d3_growth` |
| DG-2 | major (look) | **The Stormstair's pools read as flat dark-blue discs with a hard, stepped edge from the gameplay camera, no rain on them; the Rimeglass tarn as a flat disc with a hard round edge**, frozen or thawed. D3's pools were a flat 48-gon 4 cm over the chunk's water: its edge where it cut the terrain was a pixel-stepped line, its rain rings 2.6 m cells too fine to read at 50-70 m. | Stills from the gameplay camera at stage 8, storm and calm, tarn frozen and thawed (`--d3-beats=dgate`). | The pools are drawn to their shores (`StormWater.shore_mesh`: a ring grid on the water inside the shoreline and draped over the bank beyond it, the water's depth at each vertex from the world's ground; `storm_water_shore.gdshader`: the bed's colour in the shallows, the waterline in the bank's colour, a wet bank fading out within a wandering 0.4-1 m of height, the sky in broad patches, the rain's rings with bright crests in 3.2 m cells; drawn after the chunks' water and writing its depth). The tarn's water is the same shore water over its flat hollow; its ice fades into snow over its last metres; its shoreline has broad lobes (`IceSheet.shore_lobe`, 0.88-1.0 of the radius). No texture. | `test_d3_growth` (the shore mesh), `test_d2_storm` (the lobes) |
| DG-3 | minor (look) | **A Stormstair loaded after the Stormcaller's fall played up to 14 s of rain** (a Continue, a fast travel, a walk back): StormWeather counted its clearing from its node's birth. | The capture's reload beat: rain in the still at 0.7 s; the node's clearing 0.00 and intensity rising. | Only a storm the giant can see when he falls clears over 14 s; one not showing when the fall is known is clear at once (`StormWeather.advance`). After: clearing 1.00, intensity 0.00, the still clear. | `test_d2_storm` |
| DG-4 | minor (tooling, robustness) | **The capture tours logged `duplicate entity_id` errors** at their start. Cause: two streaming foci in one frame (a camera's ring, then the giant's, both loaded synchronously by the harness): a chunk unloaded and loaded again within that frame came in under another name (`@Node3D@n`) while the queue-freed one's props were still registered. Not in real play: one focus a frame, and every travel, Continue and death reloads the scene (`GameSession._reload_scene`). | The D3 tour's beats `refusal,growth` on the D3 code: 2 errors (3 lines); a streamer test in one frame: the reloaded chunk named `@Node3D@473`. | The streamer takes an unloaded chunk and its props out of the tree before their free (`TerrainChunk.leave_tree`), so any same-frame reload is clean (the harness needs no change). After: 0 errors. | `test_chunk_streamer` |
| DG-5 | minor (HUD) | **The frost and water meters were not HUD layout regions** (the overlap test never saw them) and were laid out 28 px tall while they drew 32. | `test_hud_layout` with the two added: drawn 32 px in a 28 px region. | 32 px each (frost -232..-200, water -268..-236); both are regions now: no overlap at 1280x720 or any supported size. | `test_hud_layout` |
| DG-6 | minor (test health) | **D3's "pools drawn with the storm's water" test asserted two constants** (`WORLD_SCALE > 1`, `WORLD_LIFT_M > 0`) - nothing about what is drawn. | Read; every D test scanned for tests with one assertion or none. | Replaced by DG-2's shore-mesh test (depth per vertex, water flat, bank draped, normals up, none while unloaded, the real pools reach past their basins' shores). | `test_d3_growth` |
| DG-7 | minor (words) | **The launcher's "What to try" still said Maera's trials grow a giant to 96 ft**; since D3 that is the Frostbound's fall. | Read. | The route says what each stage waits for and adds the two titans (with the 0.17 notes). | `test_launcher_notes` |
| DG-8 | known item (time) | **The slow tier at 442.6 s of its 480.** | The tier alone: 432.8 s; ten rendered suites each block on one child Godot under Xvfb (about 80 s, three CPUs idle). | The rendered suites' children run ahead in the background, one at a time, while the suites before them run (`ChildRuns.prefetch`/`execute`: the same executable, arguments and output; none beside a suite that measures time - a `BudgetRule` suite, or one whose own child compares frame or load times). No suite moved, skipped or weakened. The tier alone: 432.8 -> 369.6 s. | the tier's own checks |
| DG-9 | known item (balance check) | **Stage 9 next to the titans** (116 ft over the 28 m Frostbound, level with the 34 m Stormcaller): may a stage-7/8 fight break at stage 9? | Each arena at stage 9. | Nothing broke; nothing changed: the lock takes him from 60 m, the aim indicator names him and a plate and the swing strikes it, a press is a swing (never the stamp: a titan has plates), a blow takes 0.17-0.56 % of his health, his blows still hurt (25 s: the Frostbound 12 blows for 646 of 2,360 health, the Stormcaller 5 for 451). | `test_dgate_stage9_titans` (slow) |

### Suspicions run and rejected

| Suspicion | What was run | Result |
| --- | --- | --- |
| Kill a titan, save, quit, Continue | Read: a boss's defeat requests a checkpoint (`GameSession._on_boss_defeated`); D1/D2/D3's fixtures with him slain restore; the Web check's Continue at stage 9 (below) | Kept: the kill, the thaw, the calm, the growth |
| Die mid-fight | Read: a death reloads the scene; the titan's new attempt resets the ice (`TitanEnemy._p34_reset_extra` -> `IceSheet.reset`); D1's slow suite | No stuck ice or storm |
| Fast travel mid-fight | `GameSession.travel_blockers` ("Not while enemies are close") | Refused; no half-fought titan behind |
| The Elder Colossus quest stuck for a save already at stage 9 | `quest.elder_colossus`'s stage completes on `stage_at_least` 9 (a condition, not an event) | Completes on load |
| Growth requirement edge cases: a 0.16 giant grown to 96 ft on the trials with the Frostbound alive; a slain titan with the level short | D3's suites (`test_d3_growth`, `test_d3_stage9`), the 0.16 fixtures | The stage kept, stage 9 asked of the Stormcaller; the refusal names the level |
| Old fixtures under DG-1 | Every save fixture's level and XP against both curves | Only the 0.16 stage-9 fixture (level 17, 7,700 XP) is lifted (13,116); every other is as saved |
| The stomp rule one-shotting a titan at stage 9 | `PlayerAttack._wants_low`: a body with plates is never a low strike's; DG-9's test | Never a stamp or stomp; a heavy 0.41-0.56 % of his health |
| Real-play duplicate entities (DG-4) | Every ring load in the game's code: one focus a frame (the loading slice and the cutscene are the only other foci, never in the same frame as the player's) | Harness only; fixed in the streamer anyway |
| HUD overlaps at 1280x720 with the D meters, the 10-line loot panel, the boss bar | `test_hud_layout` with the meters as regions | None after DG-5 |
| Errors in the log during play | The capture runs (the tour's start, the pools, the tarn, the reload), the final check's soak, the Web checks | 0 errors after DG-4 |
| Duels drift with DG-1 | No combat number reads XP: a stage's level is its profile's (13/15/17) and the attributes are 3 a level, as before; `TitanDuel.prepare` reaches it from the record's table | The titans' tier re-ran every duel: see BALANCE_LOG "Dgate" |

## The XP (DG-1)

`data/progression/progression_default.json`: levels 1-15 as before (5,950 XP at 15); 15 -> 16 2,500, 16 -> 17 4,000,
17 -> 18 6,000, 18 -> 19 7,500, 19 -> 20 9,000 (level 20 at 34,950). The guaranteed path (D3's: the trials' floor, the
Rimeglass, the Frostbound's quest and kill, Maera, the growth to stage 8, the Hoarwatch, the look south, the
Stormcaller's quest and kill with D3's floor 17, Maera, the Elder Colossus, the Harrok lead):

| After | XP | Level before | Level after |
| --- | --- | --- | --- |
| the trials' floor | 5,950 | 15 | 15 |
| the Rimeglass, the Frostbound's quest reached | 6,150 | 15 | 15 |
| the Frostbound slain (600 + 3,600) | 10,350 | 19 | **16** |
| Maera, growth to stage 8, the Hoarwatch, the look south, the Stormcaller's quest reached | 11,290 | 20 | **16** |
| the Stormcaller slain (700 + 4,600; floor 17) | 16,590 | 20 | **17** |
| Maera, the Elder Colossus, the Harrok lead | 17,280 | 20 | **17** (1,170 short of 18) |

Milestones E-F then have 17,670 XP of the guaranteed path's to give for levels 18-20 - about four titans at the
Frostbound's and the Stormcaller's rates. A giant who also fights every placed fight of the Hoarfell (about 4,700 XP:
the rimkin pairs, the trolls, the dire wolves, the warband) and takes the optional leads reaches level 18 in milestone D,
not 19. The wandering bands still give XP without end, as every land's do.

## The look (DG-2, DG-3)

Before and after, from the gameplay camera at stage 8, in the hand-back's folder: the pools in the storm (the Bellmere,
the two lower pools), the tarn frozen and thawed, the Stormstair loaded after his fall, the pools calm.

## The slow tier (DG-8)

`tests/support/child_runs.gd` (prefetch, pump, quiet, settle, execute) and the runner (`tests/test_runner.gd`: a tier's
suites that name `prefetch_children()` are queued as it starts; `ChildRuns.quiet()` before a suite whose text uses
`BudgetRule.`). Prefetched: `test_build_render`, `test_giant_shaders`,
`test_giant_shadow_proxy`, `test_people_render`, `test_rig_draw_calls`, `test_skin_world_render`,
`test_skinned_rig_render`, `test_townsfolk_render`, `test_wardrobe_render`. Kept quiet - no background child beside
them, their own children not prefetched: the `BudgetRule` suites (`test_formation_perf`, `test_m7_gate_world`,
`test_unreachable_chase`, `test_valley_smoke`) and the suites whose child compares times (a static `quiet_children()`:
`test_creator_thumbnails`, its frames while the pictures are made against after; `test_giant_parts_render`, each part's
read and bind under 50 ms). The first final check failed `test_creator_thumbnails` (272 against 180 ms: a prefetched child
ran beside it) before that rule. The budget-judged suites start with the load average about 2 (formation_perf: 2.01; on
the D3 code 1.07). The tier alone on the 4-CPU machine: 432.8 s -> 369.6 s; in the final check: see Verification.

## Release preparation (0.17.0-m17, not shipped; DG-10)

`config/version` 0.17.0-m17 (the description's milestones M0-M17); the Web budget's -m17 rows (the caps as at -m16:
56 MB, the giant's 15.0 MiB, the people's 19.5 MiB); the launcher's "Build 0.17.0-m17" paragraph (the 0.16 paragraph is
"New in 0.16.0-m16"), its route and "The next build"; `tests/fixtures/saves/v3_m17_dgate_stage9.json` (D3's stage-9 save
at 0.17 with the guaranteed path's XP); README, HOW_IT_PLAYS, ARCHITECTURE, PERFORMANCE. The launcher's BUILD line and
download size are the final build's.

## Verification

- `nice -n 10 tools/check.sh --build --slow --gate --people --giant --web-tools --require`, alone, on the gate's final code:
  **CHECK PASSED**, no budget warning - every builder (no committed file changed; the world's seams 64 chunks, 112
  seams), the giant regenerated bit-exact (`GIANT_ESTIMATE` 14.73 of 15.0 MiB), the people bit-exact (93 files; 18.78 of
  19.5), the Web tools' tests; **446 suites, 94,430 checks, 0 failures** and the titans' **12 suites, 345 checks, 0
  failures; TIMES: default 63.7 s | slow 375.5 s | gate 2,243.7 s | titans 1,389.4 s** (D3's: 62.0 | 442.6 | 2,364.6 |
  1,408.1); the soak: 37 attacks, 32 hits, 4 kills, 2 fence breaks, 7,201 frames, 0 errors. The first final check had
  failed one check (`test_creator_thumbnails`, DG-8's rule before the timing suites were kept quiet); fixed, the whole
  check ran again.
- `tools/build_web.sh` (the release preset, on the same code; the launcher's BUILD line is this build's): the pack
  **54.82 MB** shipped of 56 (57,478,352 bytes, four parts; D3: 54.80 MB, 57,465,280: +13,072 bytes - the shore shader and
  its include, the code), `GIANT_SHARE` **14.42 MiB** (cap 15.0), `PEOPLE_SHARE` **19.11 MiB** (cap 19.5), audio 9.54 MB of
  the pack; the page downloads **70,007,052 bytes** (D3: 69,993,980; the engine 12,528,700 packed, the pack 57,478,352) -
  "about 70 MB", as the gate note says. No cap or budget was raised.
- The Web checks on it (headless Chromium, software WebGL, `low`, 1280x720, nothing else running):
  `world_start_check` **OK** (both starts, the intro skipped; 0 console errors; renderer peak 1,260 MB);
  `world_check --config=tools/web/world_check_d3.json` (D3's 0.16 stage-9 fixture - its XP lifted by DG-1 on load -,
  Continue at the Rimstone, the fast travel, the walk to Last Hearth and back) **OK**: Continue at stage 9 in 19.3 s, the
  fast travel in 10.9 s, 810.1 m in 67.9 s of game time, 0 stuck, streaming work p99 11.5 / max 12.0 ms, 0 thrash, margin
  234.9 m, draw calls p50 67 / max 98, 0 console errors (the engine's one start-up warning, the ring not ready after
  8 s, as D3's); the plan's audio criterion not met on software WebGL (510 holes, every one on the main thread, as at every
  release on this machine); `sfx_check` **OK** (16 swings, 14 hits sounded; 0 console errors; renderer peak 757 MB).

## What still falls short (bluntly)

Judged from the stills (the hand-back's folder), the tests and the logs:

- **The pools are neat ovals.** Drawn to their shores now - shallows, a wet waterline, a wet bank, the rain's rings
  readable at gameplay distance, a lighter sky-tinted surface once calm - they read as water, but from a giant's height
  the three are still the basins' clean ellipses, ringed by an even dark halo of wet bank; there is no reflection of the
  land or the giant, and on steep banks the terrain can show through the draped band.
- **The tarn is better, not real.** Its outline is lobed and its ice fades into snow, but the frozen ice is still one
  pale sheet with a soft white rim, the thawed tarn's floes are its 9 m cells (square-ish blocks), and the hollow round it
  is flat; the lobes are the look only (an edge cell can be ice to the rules where only ground is drawn).
- **The levels are a measure, not a feel.** DG-1 is on the guaranteed path and the shipped data; no person has played
  levels 15-17 at the new costs; a giant who fights everything in the Hoarfell reaches 18 in milestone D; a 0.16 giant
  already at level 20 gains nothing from E-F.
- **Stage 9 outgrows both titans by design** - under 1 % of their health a blow; a person may find them trivial then.
- **The slow tier's win is from scheduling**: the rendered children run beside other suites; a suite that measures time
  must say so (`quiet_children()`) or a background child can skew it - the first final check caught one that had not.
- **Software rendering only, no human playtest.** Every still is llvmpipe at `low`; nobody has looked at the water, the
  ice or the storm on a GPU or in a person's hands.

## Tests

| Suite | Tier | What |
| --- | --- | --- |
| `tests/unit/test_progression_rules.gd` | default | DG-1: the table, the lift |
| `tests/integration/test_d3_growth.gd` | default | DG-1: the path's levels, the 0.16 fixture lifted, the 0.17 fixture as saved; DG-2/DG-6: the shore mesh |
| `tests/integration/test_d2_storm.gd` | default | DG-3: a storm loaded after his fall is clear; DG-2: the tarn's lobes |
| `tests/integration/test_chunk_streamer.gd` | default | DG-4: a chunk loaded again in the same frame is one node under its own name |
| `tests/integration/test_launcher_notes.gd` | default | DG-7 and the 0.17 notes |
| `tests/slow/test_hud_layout.gd` | slow | DG-5: the meters as regions |
| `tests/slow/test_dgate_stage9_titans.gd` | slow | DG-9 |
| changed | - | `test_build_web_budget`, `test_giant_tooling` (the -m17 rows); the ten rendered slow suites (DG-8: their child's arguments named once, `ChildRuns.execute` in OS.execute's place) |
| evidence | - | `scripts/debug/capture_d3.gd`'s `--d3-beats=dgate` |
