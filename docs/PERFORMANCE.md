# Performance: budgets, tools and results

Giantborn's performance budgets (spec section 16, plan §5.4), the tools that measure them (P14),
the numbers measured in the development container, and the runs only the owner can do. Container
numbers are **indicative only**: the container has no GPU, its CPU is shared with other work, and
it runs debug builds. Real frame times and GPU times are **NOT RUN** until the owner runs the
reference-PC commands below.

## Budgets

| Budget | Value | Where it is measured | Status |
| --- | --- | --- | --- |
| Frame time | p95 <= 16.7 ms, p99 < 33.3 ms at 1080p, `--graphics=low` (spec) | Reference PC, exported build: owner | **NOT RUN** |
| GPU render time | Reported separately from CPU (spec §16) | Reference PC: owner. The container has no GPU (software rendering only) | **NOT RUN** |
| Sim CPU per tick | p95 <= 8 ms in the stress route and the Valley | Container (indicative) and PC | Container: 4.88 ms (stress), 3.37 ms (Valley walk): **met**; after P17b 3.72 ms (stress), at most 6.37 ms in every run of the final balance matrix (three runs at once) and 5.77 ms over the 30-minute run: **met**; P18 on the final code 3.69 ms (stress) and 5.40 ms over the 30-minute run: **met**; P24b's unreachable chase (20 humans chasing a giant in deep water, the throttle and the query budget) 3.9 ms: **met**; P39 (M9, plan §6.3; "The M9 performance captures (P39)", nothing else running): the world walk through every region at stage 6 5.81 ms headless, the formation stress with its two engines 4.58 ms, the unreachable chase again 3.20-4.44 ms: **met**; the novice's nine campaign runs (two at a time) 6.0-9.6 ms a run, by region at most 7.3 ms in the Crownmarch, 6.0 in the Greywood and 7.0 in the Stonehold (**met**) and in the Aldmere March 10.8-11.3 ms in the war camp's sabotage and 9.3 ms in the Iron Regiment's battle (**not met**); the M9 confirmation on the merged code (W23, "The M9 confirmation"): the walk 5.89 ms, the formation stress 4.39 ms, the chase 3.32-3.33 ms (**met**), the matrix's 21 runs (three at a time) 6.4-10.6 ms a run, by region the median run 7.5 ms in the Crownmarch, 6.0 in the Greywood, 7.7 in the Stonehold (**met**) and 9.8 ms in the Aldmere March, the war camp's sabotage 11.2-12.5 ms (**not met**) |
| Draw calls | <= 250 in any Valley view | PerfProbe, `--scenario=valley_walk`, rendered; `tools/draw_call_probe.tscn` (the static world) | P17b (container, software GL): the static world at most 93 per view at `low` and 221 at `medium` (was 402 / 584): **met**; with enemies in view the walk's p50 is 256 and its largest view 656 at `low` (was 608 / 1,354): **not met** while about five or more full-rig enemies are in view (about 33 draw calls each; see "Draw calls after P17b"). After P22, re-measured at the M6 gate: the walk's p50 201, p95 251, max 268; the largest view of five districts 253-268: **not met by 4-18 draw calls** (a measured miss: "Draw calls at the M6 gate"). After P27 (the HUD batched: about 10 draw calls a view instead of about 120): the walk's p50 93, p95 143, max 154, every view at least 96 under: **met** ("Draw calls after P27"). P39 (M9, the world, `low`): the world walk through every region at stage 6 p50 40, p95 63, max 91; the formation stress (40 members, two engines and their crews) p50 63, max 100 (the same in both capture sets): **met** |
| Distant actors | Tier 2 shows a one-box proxy | P04 test; the Valley walk's LOD comparison | Met: every distant member shows its proxy at tier 2 |
| Active combatants | <= 12 (the director's budget) | P10a tests; P17a bot invariant | 12 in the stress route (its own spawner) and in the Valley walk; the M9 confirmation's world matrix: at most 12 in 14 of 21 runs; 13-17 for at most 0.35 s in the six conqueror runs and 16 for 43.6 s in one mixed run, when a faction turned hostile with its members already in the world (the director's rule; no counted member spawned at the cap) |
| Valley load | <= 3 s headless, <= 6 s web | P10b slow test; P18 browser | Headless about 0.3 s (P10b); web in a real browser **NOT RUN**. P18, Chromium with software WebGL on the container's shared CPU (indicative only): New Game to the first checkpoint stored in IndexedDB 14.2 s |
| Navmesh files | <= 100 KB each | P10b test | Met (15-19 KB); the streamed test world's (P24b) 0.9-16 KB each |
| Path queries (P24b) | <= 8 a tick per level (`nav_query.queries_per_tick`); chases capped at 120 m, the bot and the director at 300 m, unlimited polygons; tier-0 re-paths at least 6 ticks apart and only after the goal moved 2 m (plan §2.8) | `tests/slow/test_unreachable_chase.gd` | At most 8 re-paths in a tick (twenty asking at once served 8, 8, 4), never two of one agent closer than 6 ticks without a failure: **met**. P39: the same test three times, at most 8 a tick; the world walk through every region (AI on) p95 1, at most 4 a tick; the novice's nine campaign runs p95 1, at most 6-8 a tick: **met** |
| Navigation readiness (P24b) | Deterministic runs: a chunk ready one tick after its last region add; world walks with AI identical run to run (decision 13) | `tests/integration/test_nav_maps.gd`; `tests/gate/test_world_determinism.gd` | One tick in every run; two traced world walks identical (with async iterations on they part by two ticks): **met** |
| Web `.pck` | <= 4 MB packed at P18; since decision 8 the milestone's budget for the shipped pck (7.5 MB to M6, 21 MB at M7, 23 MB from M8), in parts of at most 15 MB | P18; `tools/build_web.sh` (fails over the budget since the M7 polish) | P18 **met**: `index.pck` 2,356,808 bytes, 1,260,098 gzipped, 1,680,132 as shipped (gzip + base64). The 0.8.0-m8 release (its patch, lane m8r) **met**: 17,457,348 bytes, 12,998,617 gzipped, 17,331,492 as shipped (16.53 MB of 23 MB) in two parts of 8,665,746 ("The 0.8.0-m8 release"). The M9 confirmation's release build (the merged W23) **met**: 17,567,168 bytes, 13,106,092 gzipped, 17,474,792 as shipped (16.67 MB of 23 MB) in two parts of 8,737,396 ("The M9 confirmation") |
| Streaming work (P24a) | <= 4 ms a frame, every step under about 3 ms (plan §5.3) | `--scenario=world_walk` on the test world (`tests/slow/test_world_walk.gd`); the web stream check | Desktop at 16 m/s: p50 0.9, p99 3.5-3.9 ms (up to 6.5 while another agent's runs loaded the cores), max 4.4 ms; the heaviest steps 3.2 ms (the terrain mesh) and 3.5 ms (a town part): **met** (container, indicative). Web: p99 9.2 ms walking and 17.9 ms at 16 m/s (Chromium with software WebGL on loaded shared cores; every step's mean is under 3 ms, the peaks are the main thread preempted): **not met in this container**; real browsers **NOT RUN** |
| Loaded margin, thrash, chunks (P24a) | >= 200 m to unloaded ground at 16 m/s; 0 reloads walking a border; <= 25 loaded | the same | 254.9 m, 0 thrash, at most 15 loaded (16 m/s, 2.9 km); 20 border walks load each chunk once: **met**. P39, the real world's tour (5,555 m at 16 m/s, every region, 25 seams): 250.3 m, 0 thrash, at most 16 loaded; the novice's nine campaign runs 253.9-254.9 m, 0 thrash: **met**; the M9 confirmation (the merged code): the tour 250.3 m, 0 thrash, at most 16 loaded; the matrix's 21 runs 252.7-255.3 m, 0 thrash: **met** |
| Static world draw calls, streamed (P24a) | <= 40 per view at web `low`, and <= 25 more for breakable houses in a settlement view (plan §5.3) | Xvfb viewpoints on the test world | At most 35 static plus the 8 breakable houses at `low` (`medium`: at most 127 with shadows): **met** on the test world; P25 and the region packages re-measure the real one |
| Web frames while streaming, with gameplay (P24a) | worst <= 45 ms, p99 <= 25 ms (indicative) | `tools/web/stream_check.mjs` on the `Web (test)` build | Chromium with software WebGL on the loaded container: page frames p50 433 / p99 1,733 / worst 4,350 ms walking at 1280 x 720 (250 / 1,683 / 3,633 ms at 640 x 360, 16 m/s): **not met (software rendering)**; the walks finished with 251.6 m and 246.9 m of margin, 0 thrash and 0 console errors while running. Real browsers **NOT RUN** |
| World data (P24a, P24b) | <= 5.0 MB: chunks, navmeshes, index, map, skyline, chunk scenes (decision 8) | the test world's files, extrapolated to 64 chunks | Without navmeshes (P24a): the test world 308,965 bytes; extrapolated to 64 chunks about 1.1 MB (chunks 0.91 MB with the border chunks at their share). The navmeshes (P24b: three lean layers and the gate regions, 29.2 KB a chunk): 467,751 bytes for the test world, about 1.55 MB for 64 chunks (the border chunks' rim halves have none). Together about 2.65 MB, about 3.0 MB with P25's map image: **on track** |
| World data (P25: the real world) | <= 5.0 MB (decision 8) | `tests/integration/test_world_data.gd` (the files) | **2,390,369 bytes: met** (chunk data 0.83 MB, navmeshes 0.93 MB, structures 0.14 MB, props scenes 0.19 MB, skyline 0.15 MB, index 68 KB, map 52 KB); the release pck's world share 2.37 MB (24.6 %) |
| Map picture (P25) | <= 300 KB, 1,024 x 1,024 (plan §3.8) | `tests/integration/test_world_data.gd` | 52,433 bytes: **met** |
| Static world draw calls, the real world (P25; M8 gate, F27) | <= 40 per view at `low` (plan §5.2: any view - "P25 and the region packages re-measure at the viewpoints"; §3.8: the shelf and the settlements) | `tests/slow/test_world_build.gd` (Xvfb, `tests/support/world_draw_probe.gd`: the shelf, the six settlements and, since the M8 gate, the M8 regions' ten places) | P25: at most 33 (Skarn; the shelf 30, Hollowmere 31, Brannock 28, Millford 27, Fort Aldmere 23, Harrok's Hall 19), with the giant in view 8 more: **met**. The M8 gate's review found the M8 places at up to 59 (nine of ten over 40; P35 had recorded its own as a known gap, P36 none), **not met**; after the gate's merge pass (lane m8p) all seventeen views draw at most 40 - the great pines, the sunken vault and the Mere of Kings at 40 exactly, Ballista Ridge 30, the war camp 26 -: **met** ("The M8 gate, lane m8p") |
| Streaming work, the real world (M8 gate, F26) | <= 4 ms a frame, every step under about 3 ms (plan §5.2); P39's worst work frame <= 12 ms headless (§6.4) | the review's stage-6 walk from Aldmere to the Stonehold, carried at 16 m/s (headless, deterministic streaming); `stream_check.mjs --world` on its route at 8 m/s (the release build) | Before the gate: `props_dep` steps (a chunk's first load of a script or shared scene its props need) of 10.3-17.6 ms headless and 41.7 ms on the web, the worst work frame the same: **not met**. Since lane m8p the world's preload list loads them behind the loading screen (155-187 ms headless): no `props_dep` step during play, the worst work frame 4.0-4.6 ms headless (the heaviest step a props part's load, 2.4-3.1 ms): P39's 12 ms **met**, the 4 ms a frame within 0.6 ms; on the web (the review's Stonehold route, SwiftShader, indicative) no `props_dep` step either and the worst work frame 6.6 ms (was 41.7; the heaviest step a props part's instancing) ("The M8 gate, lane m8p"). P39's tour through every region at stage 6 ("The M9 performance captures (P39)"): headless p50 0.52 / p99 6.91 / max 12.48 ms (the first set 17.72), the max a `props_load` (a large text props part's parse; exports ship binary scenes): P39's 12 ms **not met headless** (by 0.5 ms), 4 ms not met; rendered, with the loads on the loader thread, p99 4.24 / max 6.77 ms (the first set 4.60): **not met** (4 ms). The novice's nine campaign runs: worst work frames 19.0-41.0 ms headless (two runs at a time): **not met**. The M9 confirmation (the merged code, "The M9 confirmation"): the tour headless p50 0.51 / p99 6.97 / max 12.19 ms (a `props_load`): 12 ms **not met** by 0.2 ms; rendered p99 4.12 / max 4.77 ms: **not met** (4 ms); the matrix's runs (three at a time) 17.9-33.9 ms: **not met** |

## The tools

### PerfProbe (`scripts/debug/perf_probe.gd`)

A node that samples every simulation tick and every rendered frame, then prints one line
`PERF_RESULT {json}` with, per metric, `n`, `p50`, `p95`, `p99` (nearest rank), `min`, `max` and
`mean`. The first 60 ticks (level start-up) are left out.

| Metric | Per | What it is |
| --- | --- | --- |
| `cpu_tick_ms` | tick | The whole physics tick, timed from inside: from the probe's own physics callback (it runs first, before `Sim`) to the next one or to the start of the frame's idle step: `Sim.step` (actors, hooks, hit resolution, statuses), every other physics callback (movement, the debris pool) and the physics server step (Jolt). **This is the "Sim CPU per tick" of the budget.** |
| `sim_ms` | tick | `Sim.step` alone. |
| `idle_ms` | frame | The frame's `_process` callbacks (HUD, camera, presentation). |
| `frame_ms` | frame | The real frame delta; `N/A` under `--fixed-fps` (every delta is the same). |
| `gpu_render_ms`, `cpu_render_ms` | frame | `RenderingServer.viewport_get_measured_render_time_gpu` / `_cpu` of the main viewport; `N/A` headless. |
| `draw_calls`, `render_objects`, `primitives` | frame | The frame's totals (shadow passes included); `N/A` headless. |
| `nodes`, `objects`, `orphan_nodes`, `memory_static_mb` | frame | Performance monitors (static memory is `N/A` in release builds). |
| `active_combatants`, `debris` | tick | The director's active count (or the living, non-routed `enemies`), the debris pool's active pieces. |

It also reports `cpu_tick_spikes` (the five slowest ticks, with their tick and section),
`sections` (the same summaries per section: the Valley walk files samples under the district the
giant stands in and under its LOD phases), `counters.hits_resolved`, and `budgets` (the verdicts of
the table above, or `N/A` when the run cannot measure one).

Why not `Performance.TIME_PHYSICS_PROCESS` per tick: Godot 4.6 refreshes the `TIME_*` monitors
once per second of wall time with the largest value of that second (checked in the container: 600
headless frames, one refresh). The probe reports their largest values as `engine_physics_max_ms`
and `engine_process_max_ms` only.

### Scenarios and options (after `--` on the command line)

| Option | What it does |
| --- | --- |
| `--scenario=stress` | The stress route on `scenes/test/stress_arena.tscn` (needs `--level=res://scenes/test/stress_arena.tscn`). |
| `--stress-stage=N` | The giant's growth stage for the stress bot (default 2). |
| `--scenario=valley_walk` | The Valley walk (needs `--mode=valley --new-game`); the run ends when the walk does. |
| `--walk-teleport` | The walk teleports between its stops (views and the LOD comparison only): for slow software-rendered captures. |
| `--perf` | Adds the PerfProbe to any other autoplay run (the sandbox soak, P17a's bot). |
| `--graphics=low` / `--graphics=medium` | Fixes the graphics preset for the run (not saved). |
| `--autoplay=S` | The run's length in seconds (a hard limit for the Valley walk). |

Exit codes: 0 passed; 1 an engine or script error was logged (P02's error counter); 2 a scenario's
own check failed (`scenario_failures` in `AUTOPILOT_RESULT`).

### The stress route (`--scenario=stress`)

`scenes/test/stress_arena.tscn` (built by `tools/builders/stress.gd`): a walled 160 x 160 m floor
with an 8-stop rectangular route (40 x 28 m), 20 breakables in clusters at six of the stops
(8 fences, 6 pines, 4 crates, 2 practice gates; each of the two dense corners breaks into exactly
40 debris pieces, the pool's cap), and 12 combatants (4 soldiers, 3 wolves, 2 archers, 1 mage,
2 ogres) that respawn at their spawn points 5 s after they die or rout, so 12 stay active. The
ogres path on a large-agent navmesh baked into the scene, the others on a human one. The arena has
no encounter director: every combatant runs AI tier 0, the worst case.

The bot (`StressScenario`) grows the giant to stage 2, then laps the route: at each stop it uses
Heavy Footfall when it catches two or more of the cluster's breakables, a heavy on each breakable
(a light when a light finishes it or stamina is short), swings at an enemy in its path, and uses
Footfall when three or more enemies crowd it. After a lap the broken breakables come back, so the
debris pool keeps refilling for the whole run.

**The player carries the hidden `status.debug_invulnerable` (damage taken x 0) for the whole run**,
so it survives twelve attackers; hits, poise and knockback still land. The numbers below are taken
with this status. Its own checks: the giant never dies, debris never above 40, at least 10 active
combatants on average, and from 60 s every breakable broken at least once.

### The Valley walk (`--scenario=valley_walk`)

From the Cradle it first compares the AI LOD tiers: every far, dormant encounter (no boss) is
force-activated, so its members (12, the budget) spawn at tier 2 (dormant, one-box proxy); the
camera faces them for 80 ticks at tier 2, then 80 at tier 1 (reduced AI rates, full rig), then 80 at
tier 0 (full rates), and the director's distances are put back. Then a stage-1 giant walks 16 legs
through every district on its own navigation layer, sprinting, with the encounter director running;
legs behind the Deadfall, the cart barricade and the practice gate are teleported (the Barrow, the
bridge, the courtyard). Each leg ends with a full turn of the camera. The giant carries the same
hidden invulnerability.

### The world walk (`--scenario=world_walk`, P24a)

On a streamed world (the test world: `--level=res://scenes/test/test_world.tscn`; the real one from
P25: `--mode=world --new-game`) the giant follows a route - by default the level's `Markers/Route`
(the test world's 2.9 km loop: four seam crossings round (-256, -256), the town's street, the east,
the 35-degree plateau, the pond; since the M7 polish the real world's, `tools/data/world/world.json`'s
`walk_route`: about 400 m from (-200, 360) in the Crownmarch north into the Drowned Steps, west to
the Greywood's edge and back, four region changes and three seams), or `--route=x:z;x:z;...` - a
level with neither is a usage error (the walk's only check failure, `usage_error` in its report) -
sprinting with the stick, or carried at
`--walk-speed=M` m/s (16: the stage-6 sprint, the streaming budget's case). It sets off once the
starting ring is loaded and records, per tick, the margin to unloaded ground (the distance to the
nearest chunk of the grid that is not loaded), the most chunks loaded, seam crossings, region
changes and (walking) ticks with the feet under the ground; the streamer's statistics (loads,
unloads, thrash, work per frame p50 / p99 / max, steps by kind) are reset when it sets off. The
PerfProbe's sections are the chunks. `AUTOPILOT_RESULT`'s `world_walk` key is the report, with its
check failures (margin under 200 m, thrash, more than 25 chunks, ticks under the terrain, the route
not finished). Headless and `--fixed-fps` runs stream deterministically (a fixed step quota).
`--walk-stage=N` grows the giant before it sets off (since the M8 gate the growth is asked again every
15 ticks while the giant stands on the floor, for 600 ticks at most, and the walk does not set off at
another stage: a giant that never reaches stage N fails it with "stage N not reached (...)",
`stage_error`, alone in its check failures); `WORLD_WALK_START` and the report name the stage walked at.

### The web stream check (`tools/web/stream_check.mjs`, P24a)

Serves a `Web (test)` build (`tools/build_web.sh --preset="Web (test)"`), opens
`play.html?args=...` in headless Chromium (Playwright, software WebGL), presses Play and waits for
the world walk's `AUTOPILOT_RESULT`. Frame times are the page's `requestAnimationFrame` intervals
between the walk's `WORLD_WALK_START` and `WORLD_WALK_END` lines (the engine's own frame delta is
capped at 8 physics ticks, 133 ms, so it cannot show a slower frame; it is reported beside them);
it also reports the streaming numbers, the rendered draw calls, the console errors (0 wanted) and the
failed requests. Exit code 0 when the walk finished without check failures and the console stayed
clean; `--strict` also fails on the indicative frame budget.

Since the M7 gate, `--world` walks the real world (`--mode=world --new-game`; the release build takes
its arguments; since the M7 polish its default route, so no `--route` is needed - a walk without a
route exits 2, a usage error) and `--audio` records the game's music during the walk with `audio_check.mjs`'s
recorder (`tools/web/audio_recorder.mjs`, shared by both checks): it arms at the walk's start once
zone music plays and disarms at its end, then reports the seconds of music recorded (at least
`--music-s`, 60), the region borders crossed while recording (the music sets that followed one
another, at least `--min-borders`, 1), every silent run over 50 ms placed on the main thread's clock
(a hole the main thread explains passes the default form, `--strict` fails every one) and the peak
live sample bytes against the level's registered seconds x 353 KB + 12 MB (`level.world` 167.81 s).
The report prints the plan's criterion (no silent run over 50 ms in 60 s of music across a region
border) as MET, NOT MET or NOT MEASURED, a default pass with holes ends "OK (the plan's audio
criterion NOT MET ...)", and `--json` keeps the recording's trace for `audio_check.mjs --replay`.
`--walk-stage=N` grows the giant before the walk. `tools/web/test_stream_check.mjs` tests the
recorder's verdicts on a stub launcher (a border crossed in music; three slow frames; no border; no
music).

Since W23 (lane P39f) `tools/web/world_check.mjs` measures the world as a returning player meets it, on
the release build: a world save (`tools/web/world_check.json`'s fixture, a save the world bot wrote)
written into the page's IndexedDB, Continue from the title, a fast travel to the King's Road waystone
(the world walk's `--walk-travel`), then a walk of at least 60 s of game time across region borders with
the AI on. It reports what the stream check reports for its walk, and the Continue's and the travel's
load times, the streaming hitches (frames whose streaming work passed the streamer's 4 ms budget) with
the heaviest steps, and the engine's warnings apart from its errors (only `--strict` fails on warnings,
as on the frame budget and on every music hole over 50 ms). A hole that runs to the recording's end with
no driver read inside it is placed on the main thread too (the recorder's rule, for all three checks): an
allowance W23 added, so every default verdict since then - `audio_check.mjs`, `stream_check.mjs --world
--audio` and `world_check.mjs` alike - includes it (`holes_cut_at_disarm`, reported on its own line;
`--strict` fails such a hole as before). In this container the default verdict is indicative and
load-dependent: with the machine starved, the browser's audio clock runs unevenly against the page's and
holes can land outside the main thread's stalls - a `world_check.mjs` run at a load average of 8-9 failed
on 50 of them, where the lane's own run at about 9.5 had passed. The run that counts for the gate is the
owner's `--strict` run on a machine with a GPU (`docs/USABILITY_SCRIPT.md` §11).
`tools/web/test_world_check.mjs` tests its verdicts on a stub launcher; its runs are in
`docs/systems/P39f.md` ("Part web").

### Graphics presets (`--graphics`, Settings, LevelRoot)

The level record's `render` presets, applied by `LevelRoot` at load and on every change of the
setting (Settings page: "Graphics preset"):

| Preset | Sun shadow distance | Scenery visible to | MSAA | Used by |
| --- | --- | --- | --- | --- |
| `low` | 60 m (the Valley and the stress arena: off since P17b) | 160 m | off | `--graphics=low`; always on the web |
| `medium` | 120 m | 220 m | 2x | the desktop default |

On the web (`OS.has_feature("web")`) the record's `web_overrides` force `low` and run AI LOD tier 1
from 30 m instead of 40 m. A preset's `shadow_distance_m` of 0 switches the sun's shadows off: since
P17b the Valley's and the stress arena's `low` preset do (they doubled every view's draw calls), so
the web build has no sun shadows; the director test level keeps 60 m. The props' merged meshes are
in the `scenery` group (P17b), so the preset's scenery distance hides them far off too. The
sandbox (not a `LevelRoot` level) has no presets.

## Commands

All commands run from the repository root; `tools/gd.sh` gives the worktree its own `user://`.

Container, CPU per tick (headless, fixed 60 Hz):

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --mode=valley --new-game --scenario=valley_walk --autoplay=900 --graphics=low
```

Container, draw calls (software OpenGL under Xvfb; render times are the CPU's, not a GPU's); the
last command (P17b) is the static world alone - the Valley without its director and its giant,
seen from the walk's stops in eight directions, with each group hidden in turn:

```
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --fixed-fps 60 --resolution 640x360 \
  --audio-driver Dummy -- --no-user-settings --mode=valley --new-game --scenario=valley_walk \
  --walk-teleport --graphics=low --autoplay=900
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --fixed-fps 60 --resolution 640x360 \
  --audio-driver Dummy -- --no-user-settings --level=res://scenes/test/stress_arena.tscn \
  --scenario=stress --graphics=low --autoplay=45
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --resolution 640x360 \
  --audio-driver Dummy res://tools/draw_call_probe.tscn -- --no-user-settings --q=low
```

Reference PC (owner), the exported Windows build, **without** `--fixed-fps` so frame times are
real. Run each twice: once as is (the frame pacing a player sees, V-Sync on) and once with
`--disable-vsync` (the true cost per frame, the headroom):

```
Giantborn.console.exe --resolution 1920x1080 -- --no-user-settings ^
  --level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low
Giantborn.console.exe --resolution 1920x1080 -- --no-user-settings ^
  --mode=valley --new-game --scenario=valley_walk --autoplay=900 --graphics=low

rem the same two runs for the true cost per frame:
Giantborn.console.exe --disable-vsync --resolution 1920x1080 -- --no-user-settings ^
  --level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low
Giantborn.console.exe --disable-vsync --resolution 1920x1080 -- --no-user-settings ^
  --mode=valley --new-game --scenario=valley_walk --autoplay=900 --graphics=low
```

On a real GPU `gpu_render_ms` is the GPU time (spec §16 asks for it separately); `frame_ms` is the
frame time the budget judges; `cpu_tick_ms` is the simulation's share. The stress run takes 300 s;
the Valley walk ends on its own after about 3 minutes.

Copy the `PERF_RESULT` lines (and `AUTOPILOT_RESULT`) into the table below. `scenes/test/` ships in
the desktop exports (only `tests/` and `tools/` are excluded), so the stress arena loads there; the
Web release leaves the test content out since P22 (`--preset="Web (test)"` of `tools/build_web.sh`
keeps it).

The streamed world (P24a): the world walk on the test world, headless (the streaming numbers) and
under Xvfb (draw calls), and the web stream check (build the `Web (test)` export without
`XDG_DATA_HOME`, so it finds the export templates):

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --level=res://scenes/test/test_world.tscn --scenario=world_walk --autoplay=900 --graphics=low --walk-speed=16
xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --fixed-fps 60 --resolution 1280x720 \
  --audio-driver Dummy -- --no-user-settings --level=res://scenes/test/test_world.tscn \
  --scenario=world_walk --graphics=low --autoplay=900 --walk-speed=16
tools/build_web.sh --preset="Web (test)"
node tools/web/stream_check.mjs --json=builds/stream_check.json
```

The real world's music on the web (the M7 gate; the release build, without `XDG_DATA_HOME`): a walk
from New Game's start on the Kingsgate shelf south into the Drowned Steps, west into the Greywood and
north back into the Crownmarch, three region borders in about 100 s of music:

```
tools/build_web.sh --preset=Web --out=builds/web_m7
node tools/web/stream_check.mjs --build=builds/web_m7 --world --audio --autoplay=1200 --timeout-s=1500 \
  "--route=-200:360;-210:280;-250:220;-380:220;-452:300;-470:420" --json=builds/stream_audio_m7.json
```

On a machine with a GPU, add `--strict` (every hole over 50 ms fails).

The real world's default route (M7 polish: `walk_route`, written into `scenes/world/world.tscn` as
`Markers/Route`): the world walk and the web stream check need no `--route`. The headless walk (about
50 s of simulated time, so `--autoplay=60` is enough) and the web check with the music recorder:

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --mode=world --new-game \
  --scenario=world_walk --autoplay=60
tools/build_web.sh --preset=Web --out=builds/web_m7
node tools/web/stream_check.mjs --build=builds/web_m7 --world --audio --autoplay=1200 --timeout-s=1500 \
  --json=builds/stream_audio_m7.json
```

The M8 gate (lane m8p): the review's stage-6 walk from Aldmere into the Stonehold, headless (the steps by
kind are `AUTOPILOT_RESULT`'s `world_walk.streaming.steps_by_kind`), its route on the web (the release
build, without `XDG_DATA_HOME`), and the seventeen viewpoints' static draw calls under Xvfb (the slow
tier's `test_world_build` runs the same probe):

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --mode=world --new-game \
  --scenario=world_walk --walk-stage=6 --walk-speed=16 \
  "--route=650:-260;560:-450;470:-620;300:-640;100:-660;-60:-650;-150:-645;-230:-640" --autoplay=400 --perf
tools/build_web.sh --preset=Web --out=builds/web_m8p
node tools/web/stream_check.mjs --build=builds/web_m8p --world --audio --walk-stage=6 --walk-speed=8 \
  "--route=600:-380;470:-600;440:-645;480:-665;440:-645;480:-665;440:-645;300:-640;-60:-650;-130:-645;-160:-645" \
  --autoplay=1800 --timeout-s=2400 --json=builds/stream_stonehold.json
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --resolution 640x360 --audio-driver Dummy \
  -s res://tests/support/world_draw_probe.gd -- --no-user-settings
```

The launcher's two start buttons (the 0.8.0-m8 release; the release build, without `XDG_DATA_HOME`):
Play opens the title, which writes no save, and Enter there starts the Valley; one press of "Start in the
open world" only arms it, it disarms after 6 s, and two presses start the engine with `--mode=world`,
whose first save holds `"level": "level.world"`; 0 console errors. Each part runs in a fresh browser
profile; `--shots=DIR` also saves the title and the open world as PNGs:

```
tools/build_web.sh
node tools/web/world_start_check.mjs --build=builds/web --json=builds/world_start_check.json
```

The M9 captures (P39, plan §6.3; results in "The M9 performance captures (P39)"): the world walk's tour through every
region at stage 6, headless and under Xvfb (draw calls); the unreachable chase (P24b's slow suite); the formation
stress with its two engines, headless and under Xvfb; the bot batches' CPU per tick by region:

```
TOUR="-300:902;-300:780;-220:712;-250:640;-150:638;-60:582;60:565;60:528;60:450;60:380;60:330;60:270;120:330;\
120:262;180:322;180:262;86:212;62:172;30:150;-60:152;-128:150;-180:192;-250:220;-345:216;-420:222;-478:162;\
-540:112;-604:28;-400:-120;-200:-240;20:-250;220:-260;400:-180;560:-50;650:-55;700:-66;792:-118;792:-300;\
720:-392;720:-556;600:-602;520:-632;440:-640;300:-668;100:-680;-70:-660;-190:-640;-300:-662;-430:-672;-560:-700"
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --mode=world --new-game \
  --scenario=world_walk --autoplay=900 --graphics=low --walk-stage=6 --walk-speed=16 "--route=$TOUR"
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --fixed-fps 60 --resolution 640x360 \
  --audio-driver Dummy -- --no-user-settings --mode=world --new-game --scenario=world_walk --graphics=low \
  --autoplay=900 --walk-stage=6 --walk-speed=16 "--route=$TOUR"
tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings --no-audio \
  --slow --filter=test_unreachable_chase
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --level=res://scenes/test/formation_test.tscn --scenario=stress --stress-formations --autoplay=60 --graphics=low
xvfb-run -a -s "-screen 0 640x360x24" tools/gd.sh --path . --fixed-fps 60 --resolution 640x360 \
  --audio-driver Dummy -- --no-user-settings --level=res://scenes/test/formation_test.tscn --scenario=stress \
  --stress-formations --autoplay=60 --graphics=low
tools/run_bots.sh w.peaceful:novice:1 w.conqueror:novice:1 ... --jobs=2 --timeout=3600 --tag=<batch>
python3 tools/bot_report.py ".userdata/godot/app_userdata/Giantborn- Age of Titans/bot_runs/<batch>" world_perf
```

## Container results

Machine: the development container, Linux, 4 shared CPU cores, no GPU; Godot 4.6.3 run from the
project (a debug build, not an export). CPU numbers come from headless runs (dummy renderer); draw
calls from runs under Xvfb with Mesa llvmpipe (software OpenGL 4.5, the same `gl_compatibility`
renderer the game ships with). Every run used `--fixed-fps 60` (one tick per frame: frame times are
`N/A`). Software render times (40-60 ms) are the CPU's, not a GPU's, and are not reported.

### Stress route, 300 s, `--graphics=low` (headless)

| Metric | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| CPU per tick (ms) | 2.81 | 4.88 | 6.91 | 26.5 |
| `Sim.step` (ms) | 1.93 | 3.44 | 4.83 | 25.4 |
| Idle callbacks per frame (ms) | 1.72 | 2.85 | 3.91 | 15.2 |

Active combatants: mean 11.82 (min 9, max 12; a slot is empty for 5 s after a death or rout).
Debris: max 40, p95 35, mean 8.2 pieces. Nodes 1431-1455 (no growth over the run), static memory
97-100 MB, no orphan nodes. 7 laps (lap ends at 42.4, 85.5, 129.8, 170.0, 210.7, 254.8, 297.1 s),
140 breakables broken, 11 combatants respawned, 409 hits resolved, 0 errors, the giant never died.
The slowest tick (26.5 ms at tick 2794) is one of the few above 16 ms.

### Stress route after P17b, 300 s, `--graphics=low` (headless)

The same command on P17b's final build (merged props, the swing's vertical aim, the faction budget,
the tuned data):

| Metric | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| CPU per tick (ms) | 2.27 | 3.72 | 5.12 | 32.1 |
| `Sim.step` (ms) | 1.55 | 2.63 | 3.67 | 31.2 |
| Idle callbacks per frame (ms) | 1.46 | 2.44 | 3.18 | 45.8 |

Active combatants: mean 11.79 (min 9, max 12). Debris: max 40, p95 32. Nodes 1,220-1,245 (fewer:
the merged props), static memory 101-104 MB, no orphan nodes. 138 breakables broken, 97 loot
awards, 419 hits resolved, 0 errors. The two slowest ticks (32.1 and 26.7 ms) are the only ones above
16 ms.

### Stress route, rendered (Xvfb, `--graphics=low`, 45 s)

Draw calls p50 860, p95 1,319, max 1,515 (render objects p50 1,455; primitives p50 56,800): twelve
full-detail enemies, 20 multi-part breakables, the giant, up to 40 debris pieces and their shadows.
CPU per tick p95 5.5 ms (the software renderer shares the CPU). One lap took 42.4 s; debris peaked
at 38; 12 combatants active throughout; 0 errors.

### Valley walk, `--graphics=low` (headless)

171 s simulated: 13 legs walked (827 m, sprinting), 3 teleported (the Barrow, the bridge, the
courtyard: behind the Deadfall, the barricade and the practice gate at stage 1), no stuck
waypoint, every district visited, 0 errors.

| Metric | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| CPU per tick (ms) | 1.60 | 3.37 | 4.55 | 386.8 (see the spawn hitch) |
| `Sim.step` (ms) | 0.99 | 2.31 | 3.21 | 41.7 |
| Idle callbacks per frame (ms) | 1.21 | 2.14 | 2.81 | 52.0 |

CPU per tick p95 by district: Hollow 2.37, Old Wood 4.11 (wolves, hunters and the ogre engage the
giant), Thornwick and the fields 2.66, Quarry 2.23, Barrow 2.00, Ruins 2.21, Kingsfall 1.86 ms.
Nodes 1,685-2,191 (the encounters spawning and leaving), static memory 105-108 MB, active
combatants up to 12 (the LOD comparison) and up to 9 while walking.

### AI LOD tiers: 12 distant members (the Valley walk's comparison, from the Cradle)

| Tier | CPU per tick mean / p95 (headless) | `Sim.step` mean | Draw calls (Xvfb, low) |
| --- | --- | --- | --- |
| 2: dormant, one-box proxy | 1.54 / 2.48 ms | 0.99 ms | 595 |
| 1: perception 1 Hz, decisions 2 Hz, full rig | 3.03 / 4.28 ms | 1.89 ms | 849 |
| 0: full rate, full rig | 2.79 / 5.21 ms | 1.85 ms | 846 |

Every member showed its proxy at tier 2 and its body at tiers 1 and 0. The proxy saves about
1.3 ms per tick and 251 draw calls at `low` (about 21 per member; 449 at `medium`, whose longer
shadows also draw the rigs' shadows) for these twelve.

### Valley draw calls (Xvfb; the teleport walk: every stop and a full turn of the camera)

| Preset | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| `low` | 493 | 849 | 957 | 1,084 |
| `medium` | 657 | 1,135 | 1,236 | 1,398 |

Largest view per district (`low`): Old Wood 1,084, Barrow 908, Kingsfall 874, Ruins 845, Thornwick
780, Quarry 762, Hollow 745. `medium` (shadows to 120 m, scenery to 220 m) costs about a third more
than `low`. (The twelve members of the LOD comparison stay spawned during most of this short
capture, so these views include distant enemies.)

What the draw calls are made of, at six viewpoints with no actors (`low` shadow distance, 60 m):

| View | All | Sun shadows off | Props hidden | Scenery trees hidden | District geometry hidden | District geometry only |
| --- | --- | --- | --- | --- | --- | --- |
| Hollow | 504 | 280 | 185 | 465 | 436 | 126 |
| Forest road | 434 | 204 | 125 | 410 | 364 | 94 |
| Grove | 337 | 172 | 116 | 316 | 272 | 90 |
| Thornwick | 399 | 133 | 110 | 382 | 326 | 94 |
| Courtyard | 263 | 69 | 71 | 260 | 206 | 60 |
| Kingsfall | 112 | 36 | 84 | 88 | 86 | 62 |

### Draw calls after P17b (FOLLOWUPS: batch the props and scenery, cut shadows at `low`)

P17b's changes (all builders and data; no game code):

- **Props merged.** Every prop builder (`world_props.gd`, the fence in `props.gd`, `shrine.gd`,
  `forge.gd`) merges each visual group of its scene - a breakable's `Intact` / `Broken`, the practice
  gate's `Frame` / `Intact` / `Cracked` / `Broken`, a `Visual`, a static body's meshes - into one
  mesh with one surface per material (`SceneKit.merge_meshes`); the groups still show and hide as
  before. The practice gate went from 42 mesh nodes to 4, a pine from 7 to 2. The arena gate's
  eleven iron bars are one mesh. The practice dummy keeps its parts (it flashes each material).
- **Props are scenery.** The merged meshes are in the `scenery` group, so the level's preset hides
  them beyond its scenery distance (160 m `low`, 220 m `medium`), as it does the trees.
- **No sun shadows at `low`** (`render.low.shadow_distance_m` 0 in `level.valley` and
  `level.stress_arena`): they doubled every view.
- **Two shadow splits** for the Valley's sun (was four): every caster is drawn once per split it
  touches (this only matters at `medium`).

The static world alone (`tools/draw_call_probe.tscn`: no director, no giant, no HUD; the largest of
eight directions at each of the walk's 16 stops), at the base of P17b and after it:

| Preset | Before (largest / smallest stop) | After (largest / smallest stop) |
| --- | --- | --- |
| `low` | 402 / 284 | 93 / 68 |
| `medium` | 584 / 416 | 221 / 156 |

What remains at `low` in the largest view (the Barrow's crown, 93): the district geometry about 47,
the props in range about 21, shrines, waystones, signs and the dummies a few each.

The Valley walk (P14's tool, `--walk-teleport`, all of it: the views include the encounters the walk
passes and, during the LOD comparison, twelve distant members), before and after:

| Preset | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| `low` before | 608 | 1,027 | 1,171 | 1,354 |
| `low` after | 256 | 653 | 656 | 656 |
| `medium` before | 718 | 1,290 | 1,624 | 1,847 |
| `medium` after | 449 | 821 | 1,012 | 1,164 |

(The "before" walks are on this branch's base, with P15's encounters, so they are higher than P14's
first numbers above.) Largest view per district after, `low`: Hollow 249, Old Wood 349, Thornwick
485, Quarry 464, Barrow 483, Ruins 577, Kingsfall 483; the LOD comparison's twelve members at tier
2 (one-box proxies) 262, at tiers 1 and 0 (full rigs) 653. In steps at `low` (walk p50 / max):
merged props 481 / 1,191, then no sun shadows 275 / 732, then props as scenery 256 / 656.

The stress arena rendered, `low`, 45 s: p50 295, p95 396, max 449 (was 860 / 1,319 / 1,515).

**What is left is the actors.** A full-rig enemy costs about 33 draw calls at `low` and 37 at
`medium` (a rig is 15-30 mesh parts; the LOD comparison: twelve rigs 653 against twelve proxies 262),
the giant about the same. With the static world under 100 at `low`, a view stays under 250 with up
to about four enemies in full rig; the quarry raiders, the courtyard garrison or the return patrol
in one view exceed it. The rigs are animated per part and tint and flash per material, so they
were not merged. The next step (for P18 or later): a visual level of detail by distance for rigs -
the renderer's `visibility_range_end` on a rig's parts and `visibility_range_begin` on a one-box
proxy, from about 45 m - which needs `EnemyActor.set_lod_tier` to leave the proxy to the renderer at
tiers 0 and 1.

P18 left this for the next milestone and records it as a known limitation (`docs/M2_M5_HANDOFF.md`
§7): it changes three actor files, needs a distance per archetype (the 8.5 m Ogre King must not turn
into a box inside its own arena), can only be judged rendered, and would not help the dense fights,
whose enemies are all close; for those a rig must cost fewer draw calls itself (its parts are
animated, tinted and flashed one by one today).

### Draw calls after P22 (merged rigs and the distance LOD)

P22 (plan M6-M9 §3.4 designs 1 and 2, decision 9) did what the paragraph above asks for:

- **Merged rigs.** Every rig is one vertex-coloured mesh per animated pivot plus its weapon, all
  with one material per actor (a flash is its emission, a tint multiplies its albedo):
  `SceneKit.merge_rig`. Meshes under `Visual/Body`: soldier 16 -> 6, wolf 19 -> 7, archer 19 -> 6,
  mage 16 -> 7, ogre 23 -> 6, Ogre King 31 -> 6, villager 12 -> 5, elder 14 -> 5, the giant
  19 -> 8 (its chest, belt and head stay apart for first person).
- **A distance level of detail by record** (`render_lod_m`: soldier, archer, mage and people 45 m,
  wolf 40 m, ogre 70 m, the Ogre King never): beyond it the renderer draws a copy of the actor's
  one-box proxy instead of its rig (`visibility_range_end` / `_begin` with a 10 m overlap), at AI
  LOD tiers 0 and 1; tier 2 is unchanged.

The stress arena's twelve combatants (4 soldiers, 3 wolves, 2 archers, a mage, 2 ogres) all in view
at full detail, `low`'s look, measured by `tests/support/rig_draw_probe.gd` (the slow suite
`test_rig_draw_calls` runs it under Xvfb):

| Build | Draw calls for the twelve | Per combatant |
| --- | --- | --- |
| Base of P22 (`ae6e143`) | 221 | 18.4 |
| P22 | 77 | 6.4 |

The same commands as above (Xvfb, `--fixed-fps 60`, 640 x 360), base and P22 in one session:

| Run | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| Valley walk, `low`, base | 256 | 653 | 656 | 656 |
| Valley walk, `low`, P22 | 201 | 251 | 258 | 268 |
| Valley walk, `medium`, base | 449 | 821 | 1,012 | 1,164 |
| Valley walk, `medium`, P22 | 317 | 412 | 443 | 473 |
| Stress arena, `low`, 45 s, base | 295 | 396 | - | 449 |
| Stress arena, `low`, 45 s, P22 | 227 | 281 | - | 317 |

Largest view per district after P22, `low`: Hollow 238, Old Wood 253, Thornwick 268, Quarry 259,
Barrow 263, Ruins 254, Kingsfall 249 (base: 249, 349, 485, 464, 483, 577, 483). The LOD comparison's
twelve dormant members (beyond the director's 90 m) now cost the same at every tier: 248 at tiers 0
and 1, 251 at tier 2 (base 653 / 653 / 262): at that distance the renderer draws their boxes anyway.

- **The Valley at `low` is at the 250 budget**: half the walk's views under 201, 95 % under 251; the
  largest is Thornwick's square (268), where the six villagers, the elder, the four guards, the
  captain and the tower archer stand within 45 m together. CPU per tick p95 on the rendered walk
  4.3 ms (base 4.1 ms; the software renderer shares the CPU).
- **The stress arena's p50 drops 23 %, not the plan's 40 %**: its twelve rigs drop 65 % (above), but
  they are a minority of its view - twenty multi-part breakables, up to 40 debris pieces, the giant
  and the floor make the rest.
- `medium` costs about a half more than `low` (shadows to 120 m, scenery to 220 m).

### Draw calls at the M6 gate (a measured miss)

The M6 gate asks for "rigs within the draw-call budget with five enemies in view" (P22's acceptance:
"views with five enemies under 250"). The rendered walk at `low` on the gate's code (`9162ca1`; Xvfb
640 x 360, `--walk-teleport --graphics=low --autoplay=900`; 2,182 frames, 0 errors) measures what P22
did: p50 201, p95 251, p99 258, **max 268**. The largest view per district:

| District | Largest view | What stands in it |
| --- | --- | --- |
| Thornwick | 268 | the guards, the captain, the tower archer and the folk: thirteen within 45 m |
| Barrow | 263 | the wardens (the ogre and three wolves) beside the giant |
| Quarry | 259 | the six raiders |
| Ruins | 254 | the courtyard's five |
| Old Wood | 253 | the hunters and the wolves |
| Kingsfall | 249 | |
| Hollow | 238 | |

**Every actor's `render_lod_m` at 0.6 x on `low`** (tried at the gate, not kept): Thornwick 245, the Old
Wood 248, the ruins 244 - but the Quarry 260 and the Barrow 263, whose enemies stand within the
shorter distance anyway; the max stays 263 and people beyond 27 m become boxes. The views with five
enemies close need cheaper near rigs (the weapon merged into its arm's mesh, a merged rest-pose mesh
between the near and the box distance, or the crowd renderer's one MultiMesh per pose for humans not
striking) or a cheaper HUD; `docs/plans/FOLLOWUPS.md` ("From the M6 gate review") hands it to P30, and
P39's capture re-measures it.

### Draw calls after P30 (the mid distance; formations)

FOLLOWUPS' M6-gate row ("Valley views at `low` still pass 250 draw calls") went to P30. At `low` a
rig now draws as one merged mesh of its rest pose from 0.45 x `render_lod_m` to `render_lod_m`
(`RigPaint`'s `MidProxy`: a soldier costs one draw call from 20 m instead of six) and as its full rig
again while it acts (an action, staggered, dead or held). The rendered Valley walk at `low` (Xvfb
640 x 360, `--walk-teleport --graphics=low --autoplay=900`, 2,182 frames, 0 errors), the largest view
by section, on P30's base and with the mid distance:

| Section | P30's base | With the mid distance |
| --- | --- | --- |
| Thornwick | 270 | 245 |
| Ruins | 256 | 246 |
| Old Wood | 257 | 252 |
| Quarry | 259 | 257 |
| Barrow | 266 | 266 |
| Kingsfall | 252 | 252 |
| Hollow | 242 | 242 |
| LOD comparison (25 members, all encounters forced, one fixed view) | 252-255 | 252-255 |
| All frames | max 270, p50 205, p95 255 | max 266, p50 203, p95 255 |

0.3 x `render_lod_m` (tried, not kept) gave the Quarry 251 and changed nothing else of note. **Still
over the budget**: the Barrow (the wardens close beside the giant and acting, so on their full rigs),
the Quarry, the Old Wood, Kingsfall and the LOD comparison's view, where the 25 members are 25
one-box far proxies. A decomposition at P30's base put the HUD at about 117-120 draw calls of every
view, nearly half of the 250: a cheaper HUD (P27's, W17) and the far proxies batched into one
MultiMesh per archetype (about 20 fewer in the LOD view) are the next steps; P39's capture
re-measures.

**Formations** (`tests/slow/test_formation_perf.gd`; Xvfb 640 x 360, llvmpipe, the `low` look): the
formation stress case's 40 members (two pike regiments of nineteen and a banner each) cost 90 draw
calls seen from a stage-4 giant 9 m away with the twelve nearest promoted to their own rigs (at
stage 4 everyone is within the 60 m promotion radius), 10 with nobody promoted (the two crowds and
the two banners), and 244 drawn as forty rigs. Headless, the same 40 at AI tier 0 cost 3.5-4.3 ms
per tick at p95 (budget 5 ms); the `--stress-formations` scenario, 40 s: p95 3.69 ms.

**The load rule of the slow tier's CPU cases** (M9 gate, lane review): the two headless cases of
`tests/slow/test_formation_perf.gd` (the 40 members, 5 ms; with P39's two engines, 8 ms) time real ticks
on a machine shared with other work, so they are load-sensitive: at a load average of 8-9 on 4 CPUs the
engine case read 10.41 ms from its one window and the 40 members 10.94 and 11.54 ms from their two (the
review's run), on an idle machine 4.3-4.4 ms. Both now take the better of two windows when the first is
over budget, print the 1-minute load average at the measurement's start (`/proc/loadavg`) and the CPU
count beside their numbers, and, over budget when that load average is above the CPU count, print the
measurement as a WARNING instead of failing. The budgets are unchanged and a quiet machine (load at or
below the CPU count, or no load average to read) still fails a real regression. At the gate's check
(load 2.96 on 4 CPUs): 4.28 ms with the engines, 3.80 ms without. A second window only measures time
(the lane's fix-up 1): everything else a case asserts is taken from its first run, before any second
window. The engine case first read the stress scenario's own checks after it - the bot had then run
23 s instead of 15 and the scenario's 20 s brace check had turned on ("formation_test_stress.left never
braced"), so every second window failed the case on exactly the loaded machine the rule is for (the
verifier's forced second window: before, that failure; after, 0 failures). One helper
(`_second_window`) serves both cases, and the suite's own test forces a second window in every slow run.

### Draw calls after P27 (the HUD)

FOLLOWUPS' row ("Valley views at `low` still pass 250 draw calls") went on to P27 for the HUD, about
117-120 draw calls of every view at P30's base. Measured under Xvfb with llvmpipe, Godot 4.6's
Compatibility canvas renderer draws a run of the same kind of command with the same texture as one
batch: a `StyleBoxFlat` (a triangle array), `draw_circle` and coloured polygons never batch, a
Label's outline glyphs use another texture than its fill glyphs, each font size has its own glyph
texture, and a clip rectangle starts a new batch, while plain rectangles (rotated too) and shadowed
text without an outline batch. P27's `HudKit` (`ui/hud/hud_kit.gd`, `docs/systems/P27.md`) draws
every panel, bar and shape as rectangles and every text with a drop shadow in one of four sizes, never
clips, and sorts the HUD into absolute z layers (all rectangles, then each text size, then the edge
overlays, the death and the help overlays), so a view's HUD is one batch of rectangles plus one per
text size on screen; `tests/integration/test_hud_layout.gd` checks the rules on the live HUD
(`HudKit.batch_breakers`). The rendered Valley walk at `low` (Xvfb 640 x 360,
`--walk-teleport --graphics=low --autoplay=900`, 2,182 frames, 0 errors), the largest view by section:

| Section | P27's base (P30 merged) | After P27 | After P27, the HUD hidden (measurement only) |
| --- | --- | --- | --- |
| Barrow | 266 | **154** | 144 |
| Quarry | 257 | **148** | 138 |
| Kingsfall | 252 | **143** | 129 |
| Old Wood | 252 | **142** | 132 |
| Ruins | 246 | **137** | 127 |
| Thornwick | 245 | **135** | 125 |
| Hollow | 242 | **133** | 123 |
| LOD comparison (25 members, all encounters forced, one fixed view) | 252-255 | **143-147** | 133 |
| All frames | max 266, p50 203, p95 255 | **max 154, p50 93, p95 143** | max 144, p50 82, p95 133 |

The HUD now costs about 10 draw calls a view (14 with the most text sizes on screen), so every view
of the walk is under the 250 budget by at least 96: **met** in the container. The far proxies
(25 one-box proxies in the LOD view) and P39's capture on real hardware remain as they were.

### The streamed test world (P24a)

The generated 4 x 4 test world (`tools/builders/test_world.gd`, 256 m chunks at 4 m), debug build.

**The streaming walk, headless** (`--fixed-fps 60`, deterministic: 6 steps a frame), the default
route (2.9 km): carried at 16 m/s, 180.7 s, 16 loads, 12 unloads, **0 thrash**, at most **15 chunks**
loaded, the least margin to unloaded ground **254.9 m**, work per frame p50 0.9 / p99 3.9 / max
4.4 ms. Walking it with the stick, AI on (the gate guards): 2,858 m in 452 s of game time, the same 16 loads
and 12 unloads, 0 thrash, the least margin 255.5 m, 16 seam crossings, 0 stuck teleports, no tick
with the feet under the ground (the worst 5.7 cm), 0 errors, work p99 5.3 ms and CPU per tick p95
2.2 ms (both while another agent's runs loaded the 4 cores; the carried walk's p99 ranged from 3.5
to 6.5 ms over repeated runs, so the slow test judges the better of two walks when the first is
over 6 ms). Walking a border 20 times back and forth loads each of the 12 chunks of the two
rings once (`unload_at` 2 instead of 3 would reload them: thrash in 3 walks). A zigzag through the
6 x 6 tiny world keeps at most 25 loaded.

**Steps by kind** (the most one step took; Xvfb, threaded loads, the town's chunk among them): the
chunk data's load 0.07 ms (polled; the load runs on a worker thread), decode 0.79, a third of the
terrain rows 1.44, the terrain mesh 3.18, the ground shape 1.10, the water 0.93, a scenery MultiMesh
0.91, 16 solids 0.65, a props dependency 0.99, a props part's load 0.49 and its instancing 3.49 (a
town part of 8 breakable houses and two gates).

**Static draw calls** (Xvfb 1280 x 720, no director, no HUD, the giant's 8 included):

| Viewpoint | `low` (terrain / scenery / props / skyline) | `medium` (shadows), before -> after |
| --- | --- | --- |
| West of the town, looking in | 51 (4 / 7 / 30 incl. 8 breakable houses / 2) | 170 -> 127 |
| The 35-degree ramp | 24 (6 / 7 / 1 / 2) | 76 -> 64 |
| The seam loop, the town 600 m off | 38 (8 / 11 / 8 / 2, water 1) | 117 -> 69 |
| High over the south-west corner | 24 (7 / 5 / 9 / 2, water 1) | 65 -> 27 |

The "before" is the first build (one material per colour, a tree as trunk and crown, a house as body
and roof, the props drawn at any distance); after: one vertex-coloured material, every shared mesh
one surface, the town's merged houses and walls as far scenery (drawn to the terrain's 700 m), the
props' scenery meshes faded at the scenery distance, a square of four fences and four crates. The
rendered world walk (the HUD and the three gate guards in view) runs at 160-207 draw calls at `low`
(p50 169).

**World data** (decision 8: <= 5.0 MB with the navmeshes, the map and the index):

| Item | The test world (4 x 4 chunks) | Extrapolated to the world's 64 chunks (8 x 8) |
| --- | --- | --- |
| Chunk data (`chunks/c<x>_<z>.res`) | 16 files, 257,471 bytes: 16,092 a chunk on average (13,727 the flat town chunk to 17,107); the 16-bit heights alone 7,465 on average (4,573-8,501 compressed, 8,978 raw: 67 x 67 x 2), the scenery, solids and cells the rest | 36 inner chunks at 16,092 and the 28 border chunks at their share (their outer half is the rim: all the heights, half the rest, 11,779): **909,110 bytes**; all 64 at the average: 1,029,888 |
| Skyline (`skyline.res`, `skyline_landmarks.res`) | 22,206 + 1,144 bytes (33 x 33 vertices; two landmarks) | about 86,000 (65 x 65 vertices) + about 7,000 (twelve landmarks) |
| Shared meshes and the material (`shared/`) | 13,205 bytes (eight meshes) | grows with P25's species and buildings, not with the chunks |
| World index (`index.res`) | 4,261 bytes | grows with the markers and points of interest (P25) |
| Props sub-scenes | 10,678 bytes (the town 6,316 in two parts, the two landmarks, the breakable house) | about 50,000 for eight settlements |
| **Total without navmeshes and the map image** | **308,965 bytes** | **about 1.1 MB**, leaving about 3.9 MB of the 5.0 MB for P24b's navmeshes (three layers a chunk) and P25's map image |

**The web stream check** (the `Web (test)` export, `index.pck` 4,463,048 bytes, 3,721,508 as
shipped; headless Chromium 153 (Playwright 1.63) with SwiftShader on the container's shared CPU, indicative only):

| Run | Wall time (Play to the walk) | Page frames while walking p50 / p99 / worst | Margin, thrash, most loaded | Streaming work p50 / p99 / max | Draw calls p50 / max | Console errors |
| --- | --- | --- | --- | --- | --- | --- |
| Walking with the stick, AI on: the default route, 2,858 m in 452 s of game time, 1280 x 720 | 1,788 s (18.8 s) | 433 / 1,733 / 4,350 ms (**missed**, indicative) | 251.6 m, 0, 15 | 4.1 / 9.2 / 9.7 ms | 159 / 210 | 0 while running; 1 at exit (below) |
| Carried at 16 m/s: 2,890 m in 181 s, 640 x 360 | 461 s (18.4 s) | 250 / 1,683 / 3,633 ms (**missed**) | 246.9 m, 0, 15 | 4.2 / 17.9 / 27.8 ms | 156 / 207 | 0 |

Both walks finished with no check failure, no tick under the terrain and 0 errors counted by the
game, 16 seam crossings each. The frame times are SwiftShader rasterising on the CPU (about 2-4
frames a second; the engine's own frame delta stays at its 133 ms cap), measured while another
agent's bot runs kept the container's 4 cores loaded (load average 10-14): they say nothing about a
GPU, and the budget stays **NOT RUN** in a real browser. Most of a page frame is the fill: halving
the canvas's width and height took the median from 433 to 250 ms. The streaming steps on the web
(the 16 m/s run; mean / largest): the chunk data's load in its request step (a single-threaded web
build loads it there) 2.6 / 17.5 ms, the terrain mesh 1.3 / 8.4, a props part's instancing 2.1 /
5.8, the ground shape 1.1 / 5.1, the rows 1.05 / 3.8, a scenery MultiMesh 0.48 / 14.2, 16 solids
0.46 / 24.7: the step means stay under 3 ms, and the largest values are the main thread losing its
core for a moment. The error at exit is the engine's audio teardown after the autopilot quits it
("Cannot read properties of null (reading 'currentTime')"); a player never quits the engine on the
web, so the check lists such lines apart. The rendered walk's draw calls include the HUD and the
gate guards.

### Navigation in the streamed test world (P24b)

Per-layer maps over the test world's lean per-chunk navmeshes (`tools/world/nav_bake.gd`; details in
`docs/systems/P24b.md`). Container, headless, `--fixed-fps 60`, debug build (indicative).

**Navmeshes** (16 chunks, 50 files, 467,751 bytes):

| Layer | Polygons a chunk (mean, min-max) | Bytes a chunk (mean, min-max) |
| --- | --- | --- |
| human (1) | 1,318 (1,229-1,746) | 12,542 (11,641-16,010) |
| large (2) | 1,019 (966-1,326) | 9,415 (8,923-11,657) |
| titan (16) | 764 (582-886) | 7,164 (5,743-8,178) |
| gate 4 (32: the ford, two chunks) | 37-39 | 875-936 |
| **A chunk, all layers** | **3,106** | **29,234 (27,320-33,903; the town chunk the largest)** |

**World data with the navmeshes** (decision 8): the table above (P24a) extrapolated about 1.1 MB without
them; the navmeshes add 36 inner chunks at their mean of 31,025 bytes and the 28 border chunks at half
(the rim, their outer half, has none): about 1.55 MB (2.0 MB with every chunk at the inner mean). The
total is **about 2.65 MB**, about 3.0 MB with P25's map image (about 0.3 MB): **on track** for 5.0 MB.
The test world's own files now: chunks 257,380, navmeshes 467,751, skyline 23,291, shared meshes
13,205, index 4,630, props sub-scenes 11,776 bytes: 778,033 in all.

**Path queries** (every chunk loaded; 40 seeded cross-chunk pairs per layer up to 150 m apart, the paths
131-152 m long on average; ms a call, mean / max): `NavQuery.path` with the far cap (300 m) 1.48 / 2.32
(human), 1.02 / 1.85 (large), 0.80 / 1.16 (titan); with the chase cap (120 m) 1.41 / 1.70, 0.98 / 1.25,
0.75 / 1.09; `map_get_path`'s defaults 1.32 / 2.07, 0.90 / 1.72, 0.67 / 0.96; `closest_point` 1.72 /
2.30, 1.21 / 1.35, 0.95 / 1.49. Corner to corner (about 1.1 km): the caps stop the search at 124-133 m
(chase) and 320-326 m (far) in 1.0-2.2 ms; `map_get_path` ends 291-497 m short (its 4,096 polygons) in
3.3-4.2 ms; unlimited polygons without a cap reach the goal in 3.7-6.7 ms.

**Readiness and streaming**: a chunk is ready one tick after its last region add (async iterations off,
every run); its three navmesh loads and three region adds run one a frame. The carried world walk at
16 m/s (2,890 m) with them: streaming work per frame p50 0.63 / p99 3.62 / max 4.0 ms, 16 loads, 12
unloads, 0 thrash, the least margin 253.3 m; a navmesh load 0.61 ms mean (1.02 max), a region add 0.05
ms (0.08 max).

The default route walked with the stick, AI on (the wolf pack, the band and the pond watch meet it:
on average 6.2 active combatants, at most 12): 2,858.6 m in 452.3 s of game time, 16 loads, 12
unloads, 0 thrash, at most 15 loaded, the least margin 254.5 m, 16 seam crossings, no stuck teleport,
no tick under the terrain; streaming work p50 0.62 / p99 2.87 / max 3.58 ms; CPU per tick p50 1.06 /
p95 1.78 / p99 2.96 / max 19.4 ms (an encounter spawning its members in one tick); 0 errors, 0
warnings.

**On the web** (the `Web (test)` build, `tools/web/stream_check.mjs` on the gate test's chase route
at 640 x 360; headless Chromium with SwiftShader on the container's shared CPU, indicative only): 326 m
in 53.2 s of game time with the pack chasing, 5 loads, 0 thrash, the least margin 242.8 m, 0 console
errors; streaming work p50 0.8 / p99 6.0 / max 7.4 ms; a navmesh's request step (the single-threaded
web build loads it there) 1.5 ms mean / 6.0 max, taking it 0.05 / 0.2, a region add 0.07 / 0.2; CPU per
tick p50 1.2 / p95 3.2 / p99 6.1 / max 28.8 ms; page frames p50 100 / p99 183 / worst 267 ms (software
rendering: they say nothing of a GPU; real browsers **NOT RUN**).

**The unreachable chase** (`tests/slow/test_unreachable_chase.gd`: 20 soldiers chasing a giant that
wades in the pond's 5 m deep water for 20 s): CPU per tick p50 2.3 / p95 **3.9** / p99 5.1 / max 8.5 ms
(the budget p95 <= 8 ms met); 228 re-paths, at most 8 in a tick (twenty at once: 8, 8, 4), one agent's
never closer than 6 ticks without a failure; the soldiers stood on the bank (the deepest 1.15 m of
water). The tick that served eight re-paths at once took 8.5 ms: a full budget of eight human-layer
queries costs about 6-12 ms, so the budget bounds the count, not the worst tick (P30 and P39 watch it).

**Determinism** (`tests/gate/test_world_determinism.gd`): two world walks with AI on in two processes
(the wolf pack chasing the giant over the x = -256 seam, six chunks with twenty navmeshes streaming in
over x = 0) give identical AUTOPILOT_RESULT lines (timings aside) and 107 identical AI trace lines;
with async iterations on, the walks part by two ticks.

### The real world (P25)

Built by `tools/builders/world.gd` in 38-42 s (64 chunks; `--chunks=c2_6` with its neighbours 18 s);
two builds write the same bytes. Container, indicative.

| Item | Bytes | Notes |
| --- | --- | --- |
| Chunk data (`assets/world/chunks/`) | 831,880 | 64 files, 7.2-23.5 KB (the Greywood's dense chunks the largest) |
| Navmeshes (`assets/world/nav/`) | 933,444 | 206 files: human 38,153, large 28,218, titan 22,487 polygons; gate regions 542; at most 4,305 polygons in a chunk (c2_2, the Greywood) |
| Structures (`assets/world/structures/`) | 143,236 | 35 merged vertex-coloured meshes, 14,720 triangles |
| Props scenes (`scenes/world/chunks/`) | 193,634 | 36 parts of at most 150 nodes |
| Skyline, landmarks, index, map, shared, root scene | 288,175 | 86,117 + 66,831 + 68,144 + 52,433 + 9,078 + 5,572 |
| **Total** | **2,390,369** | the 5.0 MB budget: met |

The release web export (`tools/build_web.sh`, preset Web): `index.pck` 9,781,704 bytes, 7,355,066
gzipped, 9.35 MB as shipped; the world's generated files (`assets/world/`, the chunk parts and
`world.tscn` as exported, the map's texture) are 2,365,395 bytes of its 9,601,570 bytes of packed
files (24.6 %), the audio 43 %.
The shipped pck is over the 7.5 MB M6 budget the script still applies (the M7 budget is 21 MB).

**Static draw calls** (Xvfb 640 x 360, `low`, no director, the stage-3 camera turned through four
directions at each viewpoint, the most of the four; `tests/support/world_draw_probe.gd`):

| Viewpoint | Static world | With the giant |
| --- | --- | --- |
| The Kingsgate shelf | 30 | 38 |
| Millford's green | 27 | 35 |
| Brannock's green | 28 | 36 |
| Hollowmere's green | 31 | 39 |
| Fort Aldmere's gate | 23 | 31 |
| Skarn's green | 33 | 41 |
| Harrok's Hall | 19 | 27 |

**World walk** (carried at 16 m/s along the King's Road from the shelf to Fort Aldmere, headless,
`--mode=world --new-game --scenario=world_walk`): 1,842 m, 0 errors, at most 15 chunks loaded, 251 m
of loaded ground ahead at the least, 0 thrash, streaming work per frame p50 0.42 / p99 3.3 / max 9.5
ms (the max is the first load of a props dependency, the shrine scene), CPU per tick p95 1.8 ms.

### The world's music on the web (the M7 gate)

The release build of the gate's fixes (`tools/build_web.sh --preset=Web --out=builds/web_m7`:
`index.pck` 16,172,712 bytes, 16,682,352 as shipped in two parts, the audio 60 % of its files) and
`stream_check.mjs --world --audio` (the command under "Commands"), headless Chromium with SwiftShader
on the container's 4 cores, alone in the container. Indicative: software WebGL.

| Route (walked with the stick, AI on, 1280 x 720) | Music recorded, borders | Holes over 50 ms (longest) | Placed on the main thread | Page frames p50 / p99 / worst | Margin, thrash, most loaded | Streaming work max | Draw calls p50 / max | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **The gate's**: -200:360, -210:280, -250:220, -380:220, -452:300, -470:420 (506 m in 61 s of game time, 127 s of wall time; Play to the walk 28.5 s) | 98.5 s, 3 (Crownmarch -> Drowned Steps -> Greywood -> Crownmarch) | 301 (281.5 ms) | all 301 (458 long tasks, the longest 440 ms) | 217 / 317 / 450 ms | 223.7 m, 0, 16 | 5.3 ms | 39 / 57 | OK; the criterion NOT MET |
| -200:360, -200:200, -380:200 (278 m in 28 s) | 42.5 s, 1 | 130 (261.2 ms) | all 130 | 200 / 267 / 383 ms | **199.9 m**, 0, 16 | 10.9 ms | 38 / 47 | failed: too short, and the margin |
| The same, back north to -380:360 and -200:360 (674 m in 69 s) | 125.8 s, 3 | 397 (394.7 ms) | all 397 | 233 / 367 / 433 ms | **199.9 m**, 0, 16 | 4.6 ms | 40 / 52 | failed: the margin |
| **M7 polish, the world's default route** (no `--route`: `walk_route`, -200:360, -210:280, -250:220, -345:216, -295:300, -280:360; 397 m in 47.4 s of game time, 106 s of wall time; Play to the walk 30.2 s; the polish's release build, 15.92 MB shipped in two parts) | 75.3 s, 4 (Crownmarch -> Drowned Steps -> Greywood -> Drowned Steps -> Crownmarch) | 207 (330.9 ms) | all 207 (357 long tasks, the longest 379 ms) | 200 / 300 / 383 ms | 225.4 m, 0, 16 | 9.0 ms | 40 / 47 | OK; the criterion NOT MET |

The music played across every border with no hole the main thread does not explain: every silent run
over 50 ms lies where the main thread was drawing a frame of 100-450 ms and the no-threads build's
mixer waited for it, as on the Valley's (M6, `docs/systems/P23.md`). The default form therefore
passes, and the plan's criterion (no silent run over 50 ms) is **NOT MET in this container**; the
`--strict` form is for a machine with a GPU (**NOT RUN**, the owner's; `docs/plans/FOLLOWUPS.md`).
The peak live sample bytes stayed at 57.2 MB of the world's 67.9 MB cap (167.81 registered seconds
x 353 KB + 12 MB). The console stayed clean while the game ran (0 errors; the line at exit is the
engine's audio teardown, as above). The other two routes came 199.9 m from unloaded ground (the
walk check wants 200 m) after the walk's stuck-walk teleports (two on each, the same headless): a
miss of the route, not of the music or the streaming work; the gate's route keeps 223.7 m. The
engine's own frames sat at their 133 ms cap. The M7 polish's default route (the last row) has no
stuck-walk teleport (headless the gate's route has one, where its third leg runs into a trunk at
(-346, 221)) and keeps
225.4 m; its peak live sample bytes 57.0 MB, 0 console errors while the game ran.

The gate's searches within the path-query budget (`docs/systems/P24b.md`, "M7 gate") are on the
desktop side: the reviewer's world walk at stage 4 past the Raiders' Hollow to Brannock (headless)
went from `cpu_tick_ms` max 36.1 to 10.4-14.0 ms (two runs) and p99 7.4 to 5.6-5.7 ms.

### The M7 polish (lane B): civilians within the path-query budget

A town's folk fleeing at once (`docs/systems/P24b.md`, "M7 polish"): Brannock turned hostile with a
stage-4 giant on its street and all eight villagers deciding in the same tick (the worst their
decision phases allow), headless, the slow suite's measurement
(`tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings
--no-audio --slow --filter=test_m7_polish_world`):

| | Path queries in the worst tick | Ticks over the budget of 8 | The actors' phase, worst tick | Every villager in shelter |
| --- | --- | --- | --- | --- |
| Before (two runs) | 16 counted by NavQuery + 8 agent paths it did not count (24) | 1 | 7.9-8.4 ms | yes, the last after 16.7 s |
| After (three runs) | 8, the agent paths counted | 0 | 3.6-8.4 ms (noisy: the container) | yes, the last after 16.7 s |

With the villagers' natural decision phases the same flight spent at most 6 counted queries a tick
before the change. P37's Millford raid and P39's performance capture re-measure with raiders in the
town.

### The M7 polish (lane B): the human map's edge merge

Every chunk's navmeshes of a layer on one map, as `NavMaps` sets it up (`docs/systems/P24b.md`, "M7
polish"), the navigation server's own counts after one sync: the human map 70,832 edges, 45,015
merged, 455 connections between regions and 16 edge errors (c4_1, c4_2, c5_2 and c6_6, four each)
before the explicit merge scale; 70,840, 45,023, 455 and 0 after. The large (53,251 / 32,408 / 355)
and titan maps (43,909 / 25,796 / 572, gate regions included) are the same either way, as are the
test world's three. (Counted with the toll fort's tower on its new place, lane B's c5_5 rebuild; before
it the human map had 70,841 / 45,021 edges with the default scale, 70,849 / 45,029 with the explicit
one, the large map 53,249 / 32,407.) A carried walk at 16 m/s through the four chunks printed four edge-error warnings
before (one per region sync) and none after:

```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --no-audio --mode=world --new-game \
  --scenario=world_walk --graphics=low --autoplay=1200 --walk-speed=16 \
  "--route=-300:780;60:450;120:-350;150:-650;380:-400;620:600;200:330"
```

### The 0.7.0-m7 release (the M7 gate and its polish)

The play link's build after the M7 polish merge (`tools/build_web.sh`, preset `Web`, no test content;
every record validates without `data/test`), checked in headless Chromium with SwiftShader on the
container's 4 cores (indicative: software WebGL). The merge's own check (`tools/check.sh --build
--slow --gate --audio`): 205 suites, 37,537 checks, 0 failures (default 48.3 s, slow 165.8 s, gate
267.4 s), the seams (64 chunks, 112 seams), 441 audio files bit-exact, the 120 s soak with 0 errors.

| Item | Result |
| --- | --- |
| `index.wasm` | 37,700,666 bytes; 12,528,700 as shipped (gzip, base64) |
| `index.pck` | 16,188,664 bytes (12,522,869 gzipped); 16,697,160 as shipped in two parts of 8,348,580 bytes: 15.92 MB of the M7 budget of 21 MB; the audio 61 % of its files |
| The page's download | about 29.2 MB (the engine 12.5 MB, the pck 16.7 MB) |
| `stream_check.mjs --world --audio` (the world's default route, no `--route`) | OK in its default form: 396.9 m in 47.4 s of game time (124.5 s of wall time), 4 region borders (Crownmarch, Drowned Steps, Greywood, Drowned Steps, Crownmarch), 0 thrash, at most 16 chunks loaded, 223.6 m of margin, streaming work max 7.7 ms, draw calls p50 40 / max 47, 0 console errors; 86.7 s of music with 283 holes over 50 ms (the longest 322.2 ms), every one placed on the main thread; peak live samples 57.0 MB of the 67.9 MB cap. The plan's criterion NOT MET here (the strict form is the owner's, on a GPU) |
| `audio_check.mjs` (the Valley) | OK in its default form: sound 0.3 s after the Hollow's music begins, 60.2 s of music with 179 holes over 50 ms (the longest 168.3 ms), every one placed on the main thread; peak live samples 37.0 MB of the 48.0 MB cap; 0 console errors. Criterion NOT MET here, as at M6 |
| The launcher's open-world start | One press arms the button ("Press again to start a new game in the open world"; the game does not start); the second starts the engine (5.9 s) with `--mode=world`; the first save, 21.6 s later, holds `"level": "level.world"`, respawn `world.cp.kingsgate_shelf`, stage 3, level 6; 0 console errors. Play still opens the title |
| Linux export (`builds/linux/Giantborn.x86_64`, 88,530,232 bytes) | The 120 s soak headless: 0 errors (fence breaks 2, loot 2, debris 10). An assisted novice Valley run (`--scenario=valley --bot-village=intimidate --bot-skill=novice --bot-seed=1 --bot-assist`): completed in 446.4 s of simulated time, 0 deaths, 0 breaches, 0 invariant failures, 0 errors, 0 warnings, CPU per tick p95 3.5 ms |
| Windows export (`builds/windows/Giantborn.exe`, 122,113,832 bytes, and `Giantborn.console.exe`) | Built; not launched (no Windows here) |

### The W21 merge (P35 and P36): the four regions' content

The Greywood and the Drowned Steps (P35) and the Aldmere March and the Stonehold (P36) replaced P25's
light content; their measurements, from `docs/systems/P35.md` and `docs/systems/P36.md` (plan §3.19,
§3.20), carried here at the merge.

**Static draw calls at `low`** (Xvfb, llvmpipe, `tests/support/world_draw_probe.gd`'s method: the
static world, the camera turned through four directions, the most of the four; with the giant in view
8 more each). Each package measured on its own branch. On the merged build the slow tier's
`tests/slow/test_world_build` (the settlements' budget of 40) read the Kingsgate shelf 33, Millford 35,
Brannock 40, Hollowmere 37, Fort Aldmere 40, Skarn 36 and Harrok's Hall 19 (with the giant 8 more each):
every settlement within 40.

| Viewpoint | Before (W20) | After | Package |
| --- | --- | --- | --- |
| Hollowmere's green (a settlement: budget 40) | 30 | 36 | P35 |
| The den's waystone | 34 | 39 | P35 |
| The Troll Den | 34 | 41 | P35 |
| The woodcutters' camp | 41 | 57 | P35 |
| The Needle | 37 | 36 | P35 |
| The great pines | 37 | 51 | P35 |
| The Hidden Grove | 38 | 38 | P35 |
| The Mere, south | 38 | 53 | P35 |
| The ferry landing | 40 | 42 | P35 |
| The drowned bell tower | 38 | 54 | P35 |
| The Titan's Bones | 34 | 52 | P35 |
| The sunken vault | 40 | 56 | P35 |
| The Kingsgate shelf | | 33 | P36 |
| Millford | | 35 | P36 |
| Brannock | | 40 | P36 |
| Fort Aldmere | | 40 | P36 |
| Skarn | | 35 | P36 |
| Harrok's Hall | | 19 | P36 |

The rise at P35's places (about 15 at the Mere and the camp) is its new breakables, each an intact mesh
and a frame or rack mesh within 220 m; every settlement holds the 40 budget. P36's engines are not drawn
beyond 300 m and the siege of Skarn's line exists only while the siege runs (before those, Skarn read 55
and Fort Aldmere 41).

**The web pck** (the release, `tools/build_web.sh --preset=Web`, no test content, every record
validating without `data/test`):

| Build | `index.pck` raw | As shipped | Share against W20 (a9f4cc0) |
| --- | --- | --- | --- |
| W20's merge (a9f4cc0) | 16,830,716 | 16.26 MB | |
| P35's branch | 17,142,508 | 16.38 MB in 2 parts | +311,792 raw, about +0.12 MB shipped (the chunks' props parts, the regions' data, scripts) |
| P36's branch | 17,078,996 | 16.34 MB in 2 parts | +248,280 raw, +82,148 shipped (0.08 MB) |
| **The W21 merge** (`--out=builds/web_w21`) | **17,390,820** (12,944,810 gzipped) | **17,259,748 bytes, 16.46 MB in 2 parts of 8,629,874** | +560,104 raw, about +0.20 MB shipped; the audio 56 % of its files |

16.46 MB of the 21 MB budget. The merge's check (`tools/check.sh --build --slow --audio --gate`): the
world rebuilt from both regions' layouts (a second build leaves the tree unchanged), the seams (64
chunks, 112 seams), 441 audio files bit-exact, 239 suites, 42,683 checks, 0 failures (default 56.2 s,
slow 201.0 s, gate 376.8 s), the 120 s soak with 0 errors.

### The M8 gate, lane m8y (boss actors and the yield prompt): the suites

The lane added five suites and one test (`docs/systems/P34.md`, "M8 gate"): `test_yield_prompt_input`
(0.10 s), `test_boss_no_grab` (0.19 s) and the F11 test in `test_yield_protocol` (0.15 s in all) in the
default tier; `test_yield_prompt_mashing` (1.3 s), `test_yield_prompt_wall_clock` (9.7 s: the review's
mashes in real time, by design) and `test_boss_sight` (3.3 s) in the slow tier. The lane's check
(`tools/check.sh --slow --gate --audio`, on wave 21 with the lane's commits): 244 suites, 44,445 checks,
0 failures; default 59.5 s (W21's merge: 56.2 s; budget 75 s), slow 221.7 s (201.0 s; 8 minutes), gate
380.3 s (376.8 s; 50 minutes); the 120 s soak with 0 errors. No frame-time or draw-call measurement
changes: the AI change (F36) acts only while a target in reach is hidden, and the 30 seeded boss runs
never meet that case.

### The M8 gate, lane m8b (battles and the encounter director): the suites

The lane added six suites and one test (`docs/systems/P30.md`, `P32.md`, `P34.md`, `P36.md`, "M8 gate"):
`test_formation_freed_members` (0.13 s), `test_battle_caps` (0.16 s), `test_battle_kill_xp` (0.19 s),
`test_condition_forge_factions` (0.04 s) and the F33 test in `test_boss_disengage` (0.30 s in all) in the
default tier; `test_iron_regiment_world` (8.9 s: the real world three times - the bailey's corners on
the desktop, the web battle with the gate garrison alive and come from Ballista Ridge) and
`test_fort_gate_world` (11.7 s: the banner and the parley with Aldmere at war, the road up from the war
camp) in the gate tier. The lane's check (`tools/check.sh --only=world,big --build-args=--chunks=c6_3,c5_1
--slow --gate`, on the round-1 merge with the lane's commits): the two chunks and the big builder's
scenes rebuilt (no committed file changes), the seam check (16 chunks, 23 seams), 254 suites, 44,950
checks, 0 failures; default 57.9 s (budget 75 s), slow 210.7 s (8 minutes), gate 415.0 s (50 minutes;
the lane's two gate suites are 20.6 s of it); the 120 s soak with 0 errors (2 fences broken, 2 loot
awards, the debris pool at 10). Path queries: a formation's re-path is one of NavQuery's eight queries
a tick, not two (F25). The battle's room (`EncounterDirector.p34_reserve`, `p34_make_room`) walks the
battle's planned units (about 40) only while a battle is engaged; no frame-time or draw-call
measurement changes.

### The M8 gate, lane m8s (saves, shrines, the HUD message line and world layout): the suites

The lane added seven suites, one test and two rows ("M8 gate" in `docs/systems/P13.md`, `P20.md`,
`P27.md`, `P33.md` and `P35.md`). In the default tier: `test_shrine_choices_saved` (F15, 0.51 s),
`test_shrine_panel_fit` (F17, 0.39 s), `test_hud_messages` (F30, 0.14 s: all 109 shipped refusal,
size-gate and notice texts on the message line at 1280 x 720), the drive-out rows of
`test_checkpoint_triggers` (F38; 0.32 s in all) and the F5 test of `test_npc_talker` (0.07 s in all).
In the slow tier: `test_world_talkers` (F5, 0.08 s). In the gate tier: `test_den_checkpoints` (F38,
1.7 s), `test_world_shrine_pads` (F4, 0.74 s) and `test_bell_reach` (F45, 1.0 s);
`test_drowned_walkthrough` now rings its bells with real light swings (4.3 s in all).

The lane's check (`tools/check.sh --slow --gate --only=world --build-args=--chunks=c1_4,c4_4`, run on
round 1's merge (46bce55) with the lane's commits):
- The world rebuilt c1_4 and c4_4 with their neighbours (18 chunks, 21.7 s) and left the tree
  unchanged. The seams held (18 chunks, 27 seams).
- 255 suites, 44,833 checks, 0 failures. Default 55.1 s (lane m8y: 59.5 s; budget 75 s), slow
  214.5 s (221.7 s; budget 8 minutes), gate 398.0 s (380.3 s; budget 50 minutes).
- The 120 s soak had 0 errors. The whole check took 12 min 7 s.

No frame-time or draw-call measurement changes, and none was re-measured:
- A wrapped message is still one label, and the message labels keep the HUD's batching rules
  (`test_hud_layout`).
- The turned Greywood shrine and the lowered fourth bell (3 m lower) add no mesh.

### The M8 gate, lane m8q (quests, dialogue and tutorials): the suites

Lane m8p owned this file in round 3, so the round's merge records lane m8q's suites from the lane's check
("M8 gate" in `docs/systems/P13.md`, `P27.md`, `P29.md`, `P32.md`, `P35.md` and `P36.md`). In the default
tier: `test_m8_gate_quests` (new; F39, F6, F22, F29, F34, F42, F46: 111 checks, 0.68 s), three F28 and
F32 tests in `test_tutorial` (123 checks, 4.55 s in all; 1.10 s on the base) and the F22 test in
`test_journal` (0.08 s in all). In the slow tier: `test_m8_gate_tutorials` (new; F28, F32: main.tscn, a
New Game in the world and the Kings' Door, 35 checks, 17.4 s). In the gate tier:
`test_main_thread_combinations` rewritten for F3 (eight orders through the deeds' own writers, a
checkpoint and reload after every stage: 876 checks, 10.7 s; 207 checks and 2.9 s on the base), three F39
and F6 tests in `test_aldmere_walkthrough` (237 checks, 4.6 s in all; 4.3 s on the base), and
`test_drowned_walkthrough` (F42, 4.6 s) and `test_stonehold_walkthrough` (F29, 23.0 s) with their new
checks.

The lane's check (`tools/check.sh --slow --gate --only=world --build-args=--chunks=c4_2,c3_1`, on round
2's merge (29ec501) with the lane's commits, e3efe26): the world rebuilt c4_2 and c3_1 with their
neighbours and left the tree unchanged; the seams held (14 chunks, 20 seams); 263 suites, 45,819 checks,
0 failures; default 60.9 s (the base 56.4 s; budget 75 s), slow 229.1 s (211.8 s; 8 minutes), gate
445.2 s (424.1 s; 50 minutes); the 120 s soak with 0 errors (2 fences broken, 2 loot awards, the debris
pool at 10). The whole check took 13 min 16 s. The lane re-measured no frame time or draw calls: the size
gates' longer messages are text in two props parts (c4_2, c3_1), and the other fixes are data and quest
and tutorial logic.

### The M8 gate, lane m8p (streaming steps, draw calls and the 0.8.0-m8 text)

**F26: the props dependencies load behind the loading screen.** A chunk's props sub-scenes depend on the
world's runtime scripts (FortBattle, StoneThrone, ForgeFire, ConditionForge, BeaconFire, ...) and shared
scenes (the siege engines, the rockfall, the toppled statue, the crate, the shrine, ...); TerrainChunk loaded
each the first time a chunk that uses it streamed in, one `props_dep` step each, synchronously in
deterministic streaming (headless) and on the web (no loader thread). `level.world`'s `preload` list (the
44 dependencies) is now loaded by `WorldRoot` at `_ready`, inside the level build behind the loading screen,
and kept for the process's life (`docs/systems/P24a.md`, "M8 gate").

The review's stage-6 walk (headless, deterministic streaming, carried at 16 m/s from Aldmere into the
Stonehold, 1,111 m; the command below), two runs each on the round-2 merge (29ec501) and on the lane:

| | `props_dep` steps (the walk) | `props_dep` max | Worst work frame | Work p99 | Heaviest other step |
| --- | --- | --- | --- | --- | --- |
| The review (56d5242, three machines' loads) | 5 | 9.8-17.6 ms | 9.9-17.6 ms | | |
| Before (29ec501) | 5 | 11.06 / 10.33 ms | 11.07 / 10.34 ms | 5.53 / 7.23 ms | `props_load` 2.35 / 2.40 ms |
| After (lane m8p) | 0 | - | 4.58 / 4.00 ms | 3.60 / 2.62 ms | `props_load` 3.10 / 2.42 ms |

The first-time loads of the run (the review's timing patch on the base: the starting ring's and the first
point's, then the walk's five - moot_arena.gd, forge_fire.gd, size_gate.gd, stone_throne.gd,
siege_catapult.tscn): fort_battle.gd 18.8 ms, forge_fire.gd 14.0, stone_throne.gd 11.6, beacon_fire.gd
10.1, rockfall.tscn 9.5, condition_forge.gd 8.9, toppled_statue.tscn 8.8, size_gate.gd 5.9,
siege_catapult.tscn 4.4 (and smaller ones). The preload costs
155-187 ms headless on the first world load of a run (44 paths; 0 later: the cache outlives the level), and
static memory about +0.9 MB (the walk's peak 201.7 -> 202.6 MB). Streaming every chunk that has props, one
after another (`tests/slow/test_world_preload.gd`): before, 21 `props_dep` steps, max 20.5 ms, 155 ms in
all; after, none. Its heaviest steps after are the largest props parts' loads from the source tree's text
scenes: `c1_2_0.tscn` (78 KB) 10.0 ms, `c2_6_0` (68 KB) 8.7 ms, `c4_5_0` (59 KB) 7.5 ms, `c0_2_0` (50 KB)
7.0 ms (headless from the project folder; exports ship the scenes in binary form, and the web's
`props_load` measured below). The walk's CPU per tick: p95 4.2-4.3 ms (budget 8); its slowest ticks
12-19 ms are encounters spawning (the c6_2 tick that read 29 ms before reads 12-17 ms).

On the web (the release build of the lane, `tools/build_web.sh --out=builds/web_m8p`; `stream_check.mjs
--world --audio` on the review's Stonehold route at 8 m/s, stage 6; headless Chromium with SwiftShader on
the container's four shared cores, indicative; the review's run on 56d5242 is the before):

| | The review (56d5242) | Lane m8p |
| --- | --- | --- |
| `props_dep` steps | 5, max 41.7 ms (93.3 ms in all) | 0 |
| Streaming work p50 / p99 / max | 0.8 / 17.0 / 41.7 ms | 0.6 / 5.5 / 6.6 ms |
| The heaviest other steps | `rows` 11.1, `scenery` 7.7, `nav_add` 6.9, `props_add` 5.6 ms | `props_add` 6.6 (a props part's instancing), `ground` and `scenery` 2.4-2.5, `props_load` 1.7 ms |
| Page frames p50 / p99 / worst (walking) | 416.7 / 649.9 / 1,066.7 ms | 266.7 / 383.4 / 549.9 ms |
| Draw calls (rendered, actors in view) p50 / max | 51 / 141 | 42 / 126 |
| Play to the walk | 51.1 s | 42.4 s (the preload included) |
| The walk | 1,101.6 m, 11 loads, 7 unloads, 0 thrash, 236.2 m of margin | the same, 233.8 m of margin |
| Console errors while running | 0 | 0 |
| Music | criterion NOT MET (1,019 holes, every one on the main thread) | NOT MET (969 holes, every one on the main thread; the default form OK) |

The frames are software WebGL's on loaded shared cores (the frame budget is the owner's on a GPU); the
streaming steps are what the fix changes: no `props_dep` step during play on the web either.

**F27: the merge pass.** Plan §5.2's 40 static draw calls a view at `low` hold at every viewpoint, not
only the settlements. Attributing each view's calls to its nodes showed what the M8 places drew: the two
reward racks' weapons on display (six and seven parts) at any distance, every siege engine as four calls
(one per material), every framed prop (the bells, the den's wall) as two, and the waystones (two each),
the cairns and the ledge chests at any distance. Since the lane: WeaponRack's weapon fades with its rack
(P08.md), the siege builder merges an engine into one vertex-coloured mesh a state (P32.md), the breakable
kit draws a frame in its Intact and Broken meshes (P35.md), and the waystones, the cairns and the ledge
chests fade with the scenery (P25.md). Gameplay, collision and navigation are unchanged; the world rebuilt
25 chunk props parts and nothing else (`docs/systems/P25.md`, "M8 gate").

`tests/support/world_draw_probe.gd` (Xvfb 640 x 360, llvmpipe, `low`, no director, the stage-3 camera
turned through four directions, the most of the four; the M8 places after the shelf and the settlements,
so earlier views' chunks stay loaded as in play, up to 25):

| Viewpoint | The review (its own order) | Before (29ec501) | After (lane m8p) | With the giant |
| --- | --- | --- | --- | --- |
| The Kingsgate shelf | | 33 | 31 | 39 |
| Millford's green | | 35 | 33 | 41 |
| Brannock's green | | 40 | 38 | 46 |
| Hollowmere's green | | 37 | 29 | 37 |
| Fort Aldmere's gate | | 40 | 28 | 36 |
| Skarn's green | | 36 | 28 | 36 |
| Harrok's Hall | | 19 | 19 | 27 |
| The woodcutters' camp | 49 | 53 | 39 | 47 |
| The great pines | 59 | 59 | 40 | 48 |
| The bell tower | 50 | 50 | 30 | 38 |
| The Titan's Bones | 50 | 50 | 31 | 39 |
| The sunken vault | 59 | 59 | 40 | 48 |
| The Mere of Kings | 47 | 47 | 40 | 48 |
| The troll den | 48 | 48 | 36 | 44 |
| The war camp | 46 | 46 | 26 | 34 |
| The Moot battery | 38 | 38 | 27 | 35 |
| Ballista Ridge | 45 | 45 | 30 | 38 |

The great pines, the sunken vault and the Mere sit at 40 exactly; what is left there is terrain (8-11
calls), water (3-6), scenery and the structures meshes (12-14), the skyline (2) and props within 220 m
(the supply crates and the rockfalls two calls each, the great pines two, a bell, a cairn). Their next
levers, for whoever adds a prop there: one vertex-coloured mesh for the crate (P08's world_props
builder), the rockfall and the great pine (P26's world_props2), each one call fewer. With actors in view
the total stays within 250 (the review's battles peaked at 150 at `low`, before the HUD's about 10, with
the engines' four calls each; they are one each now).

**F31.** `config/version` 0.8.0-m8: `tools/build_web.sh` applies the 23 MB budget; the release build
ships `index.pck` 17,417,588 bytes (12,970,337 gzipped), 17,293,784 bytes as shipped, 16.49 MB in two
parts of 8,646,892 (the audio 57 % of its files); the page's download about 29.0 MB with the engine (12.5
MB), so the launcher's "About 30 MB" holds.

**The lane's suites:** `test_world_preload` (19 ms), `test_world_draw_merge` (52-180 ms) and
`test_launcher_notes` (7 ms) in the default tier; `test_world_preload` (slow, 1.1-1.7 s: the world built
and every chunk with props streamed); `test_world_build` renders seventeen views now (19.2 s, 774
checks; it was 10.6 s with seven on the base). `tools/check.sh --only=siege,world --slow --gate` on the
lane's code (13.5 minutes): the siege and world builders wrote the same bytes as the committed outputs
(a second build), the seam check passed (64 chunks, 112 seams), 265 suites and 45,329 checks with 0
failures - default 59.0 s (the base 56.4), slow 227.5 s (211.8), gate 443.6 s (424.1) - and the 120 s
autoplay had 0 errors.

### The M8 gate, fix-up round 1 (lane m8-fixup-1): the suites and the merge's check

The audit's fix-up lane left this file to the merge (its merge notes), so the merge records its suites from
the merge's check, against round 3's merge (f231b95). The fixes and their tests are in the "M8 gate" and
"Fix-up 1" notes of `docs/systems/P05.md`, `P11b.md`, `P13.md`, `P20.md`, `P34.md`, `P35.md`, `P36.md`
and `P37.md`.

- **Default tier:** `test_world_quest_saves` (new; N4.1, N4.2: 50 checks, 0.48 s) and the lane's tests in
  eight suites - `test_checkpoint_triggers` (F38), `test_world_events` (N4.4, N4.8; F2's test now steps
  past the director's own check), `test_m8_gate_quests` (N2.3, N3.2), `test_yield_prompt_input` (N3.1),
  `test_wander_director` (N3.3), `test_civilians_factions` (N4.7), `test_boss_disengage` (N4.5, N4.6) and
  `test_shrine` (F4): 171 checks and about 0.7 s more (3.25 s in all; the eight took 2.53 s on the base).
- **Gate tier:** `test_den_checkpoints` (F38 with the whelps aware: 51 checks, 3.8 s; 22 checks and 1.8 s
  on the base), `test_world_shrine_pads` (F4: 14 checks, 1.9 s; 7 and 0.8 s), `test_stonehold_walkthrough`
  (N4.6: 95 checks, 24.6 s; 87 and 22.9 s) and `test_drowned_walkthrough` (N2.2: 50 checks, 4.4 s; 48 and
  4.5 s): 46 checks and about 4.8 s more. No slow suite changed.

The lane's check (`tools/check.sh --slow --gate` on its head, f5c6e4f, with another lane's check running on
the machine): 268 suites, 46,260 checks, 0 failures; default 64.0 s, slow 235.0 s, gate 432.2 s; the 120 s
soak with 0 errors.

The merge's check (`tools/check.sh --build --slow --audio --gate` on the merge, 520a7c0, after an import,
a full build and an import of its own): both full builds (every builder, the world included) wrote the
committed outputs byte for byte, so nothing was regenerated; the seam check passed (64 chunks, 112 seams);
the audio pipeline's 35 tests passed and its 441 files regenerated bit-exact; 268 suites, 46,260 checks
(round 3's merge: 267 and 46,042), 0 failures; default 58.1 s (round 3's merge: 59.8 s; budget 75 s), slow
238.0 s (236.1 s; 8 minutes), gate 468.4 s (436.0 s; 50 minutes: `test_valley_audio_determinism`, which the
lane did not touch, took 12.6 s more, the lane's gate suites 4.8 s); the 120 s soak with 0 errors (2 fences
broken, 2 loot awards, the debris pool at 10). The whole check took 17 min 29 s. No frame time or draw
calls were re-measured: the lane changed no builder, layout, chunk, generated output or audio.

### The M8 gate, fix-up round 2 (lane m8-fixup-2): the suites and the merge's check

The re-audit's fix-up lane left this file to the merge (its merge notes), as round 1's did, so the merge
records its suites from the merge's check, against fix-up round 1's merge (e3aa0ea). The fixes and their
tests are in the "M8 gate" notes of `docs/systems/P27.md`, `P34.md`, `P36.md` and `P37.md` (N4.4: a world
event left behind leads nothing after the campaign; N4.6: the way out to Harrok's challenge stone is the
fight's ground).

- **Default tier:** `test_world_events` (N4.4: 125 checks, 0.46 s; 105 and 0.33 s on the base) and
  `test_boss_disengage` (N4.6: 53 checks, 0.91 s; 42 and 0.35 s): 31 checks and about 0.7 s more.
- **Gate tier:** `test_stonehold_walkthrough` (N4.6, the walk from the ring to the challenge stone and
  back: 104 checks, 21.9 s, and 22.1 s in the lane's check; 95 checks and 24.6 s in fix-up round 1's
  merge's check): 9 checks more. No slow suite changed.

The lane's check (`tools/check.sh --slow --gate` on its head, d05f9e9): 268 suites, 46,300 checks, 0
failures; default 60.2 s, slow 239.8 s, gate 425.6 s; the 120 s soak with 0 errors (2 fences broken, 2 loot
awards, the debris pool at 10).

The merge's check (`tools/check.sh --build --slow --audio --gate` on the merge, 241bf80, after an import,
a full build and an import of its own): both full builds (every builder, the world included) wrote the
committed outputs byte for byte, so nothing was regenerated; the seam check passed (64 chunks, 112 seams);
the audio pipeline's 35 tests passed and its 441 files regenerated bit-exact; 268 suites, 46,300 checks
(fix-up round 1's merge: 268 and 46,260), 0 failures; default 65.0 s (fix-up round 1's merge: 58.1 s;
budget 75 s: the merge's tree is the lane's head's, whose own check took 60.2 s, and the difference is
spread over the suites, the most in `test_ship_docs`, 1.9 s against 0.4 s), slow 238.7 s (238.0 s; 8
minutes), gate 414.5 s (468.4 s; 50 minutes); the 120 s soak with 0 errors (2 fences broken, 2 loot awards,
the debris pool at 10). The whole check took 16 min 38 s. No frame time or draw calls were re-measured: the
lane changed no builder, layout, chunk, generated output or audio.

### The M8 screenshot pass, lane m8v (trees that fade, the lock line, the riders)

**V1: the trees' fade** (`docs/systems/P25.md`, "M8 screenshot pass"). The world's two tree meshes and
the Valley's tree MultiMeshes are drawn with `assets/shaders/scenery_fade.gdshader` instead of the vertex
material: the same MultiMeshes and the same number of draw calls (another material, no node more), a
world position per vertex, and per fragment two cone tests and, inside a cone or near the camera, an
ordered-dither discard. Its cost, measured in one process with the trees switched between the fade and
the old material every 40 frames (six rounds, 240 frames each; Xvfb 1280 x 720, llvmpipe on the
container's shared cores, `low`; the viewport's measured render time, which on llvmpipe is the CPU's
rasterising - indicative, the frame budget is the owner's on a GPU):

| Place (stage 4, the arm at 15.5 m) | Render p50 / mean, the fade | The old material | Frame p50 / mean, the fade | The old material |
| --- | --- | --- | --- | --- |
| The Hollowmere waystone (the Greywood's pines all round, several in the cones) | 185.6 / 188.4 ms | 172.4 / 181.7 ms | 206.2 / 211.5 ms | 197.7 / 207.6 ms |
| The way into the Matriarch's den | 128.7 / 130.5 ms | 128.5 / 130.1 ms | 160.2 / 161.4 ms | 158.9 / 161.4 ms |

At most about 4 % of a frame (the render mean +3.7 % among the densest pines; nothing at the den), from
the fragments of the trees on screen. The draw calls the before and after captures counted at the same
views: Hollowmere 83 and 83, the den approach 121 and 121. The web build (`tools/build_web.sh
--out=builds/web_m8v`, the release preset) ships `index.pck` 17,441,828 bytes (12,982,854 gzipped),
17,310,472 as shipped, 16.51 MB in two parts of the 23 MB budget; the shader and its four materials
are a few kilobytes. `node tools/web/stream_check.mjs --build=builds/web_m8v --world` (headless
Chromium, SwiftShader, the world's default 397 m route across four region borders): OK - console errors
0 (the shader compiles in WebGL2), failed requests 0; streaming work p50 0.8 / p99 5.7 / max 9.3 ms, 6
loads, 3 unloads, no thrash, 224.1 m of margin; draw calls p50 38, max 54; page frames p50 266.7, p99
400.0 ms (software WebGL, indicative); Play to the walk 45.0 s.

**The lane's suites** ("M8 screenshot pass" in `docs/systems/P25.md`, `P26.md`, `P27.md`, `P32.md`,
`P34.md` and the others it names). In the default tier: `test_scenery_fade` (new; V1: 110 checks,
0.11 s), V2's test in `test_hud_layout` (0.40 s in all), V3's in `test_battle_boss` (0.41 s in all) and
`test_cavalry` (0.10 s in all). In the slow tier: `test_tree_fade_world` (new; V1: four places on the
real world and the Valley, 38 checks, 4.2 s) and `test_world_cavalry` (new; V3: Fort Aldmere's Charge and
the war camp on the real world, 19 checks, 10.6 s). No gate suite changed; `test_bosses_seeded`,
`test_iron_regiment_world` and `test_world_events_real` pass with the battle's alert and the riders'
leash. `tools/check.sh --slow --gate --only=valley,world` on the lane's code (09377c3, 13.9 minutes): the
valley and world builders wrote the same bytes as the committed outputs, the seam check passed (64
chunks, 112 seams), 270 suites and 46,249 checks with 0 failures - default 64.1 s (budget 75 s), slow
253.4 s (8 minutes), gate 439.0 s (50 minutes) - and the 120 s autoplay had 0 errors (2 fences broken, 2
loot awards, the debris pool at 10).

**The fix-up** (the verifier's two findings: "M8 screenshot pass" in `docs/systems/P32.md`, `P10a.md` and
`P25.md`). In the default tier: `test_scenery_fade` gains the shader's own rule run against `SceneryFade`
(`tests/support/shader_rule.gd`; 150 checks, 0.25 s in all), `test_cavalry` a rider beside the giant at
its leash's edge (42 checks, 0.12 s in all) and `test_encounter_director` an alert group's freshest
knowledge (1.10 s in all). In the slow tier: `test_world_cavalry` gains the giant among the war camp's
pickets (23 checks, 15.4 s in all). No frame cost to speak of: the leash's turn tries at most eleven
bearings, and only when the leash's edge would leave the giant inside a rider's charge window; the alert
share reads every member of an active alert group each tick (it read until the first aware one); the
shader is unchanged. `tools/check.sh --slow --gate --only=valley,world` on 24be0e3 (about 14 minutes): the
valley and world builders wrote the same bytes as the committed outputs, the seam check passed (64 chunks,
112 seams), 270 suites and 46,305 checks with 0 failures - default 58.0 s (budget 75 s), slow 250.5 s (8
minutes), gate 427.7 s (50 minutes) - and the 120 s autoplay had 0 errors (2 fences broken, 2 loot awards,
the debris pool at 10).

**The merge's check** (`tools/check.sh --build --slow --audio --gate` on the merge with the FOLLOWUPS rows
after it, 9a47f2d, after an import, a full build and an import of its own): both full builds (every
builder, the world with the lane's tree materials included) wrote the committed outputs byte for byte, so
nothing was regenerated (the rebuild-twice check); the seam check passed (64 chunks, 112 seams); the audio
pipeline's 35 tests passed and its 441 files regenerated bit-exact; 271 suites, 46,563 checks (fix-up round
2's merge: 268 and 46,300), 0 failures; default 63.3 s (fix-up round 2's merge: 65.0 s; budget 75 s), slow
256.5 s (238.7 s; 8 minutes: the lane's two new slow suites), gate 423.8 s (414.5 s; 50 minutes); the 120 s
soak with 0 errors (2 fences broken, 2 loot awards, the debris pool at 10). The whole check took 17 min 6 s.

### The 0.8.0-m8 release (the M8 gate, its fixes and the release patch)

The play link's build after the M8 gate, its fix-up rounds and the screenshot pass's lane m8v
(`tools/build_web.sh`, preset `Web`, no test content: `pck_files.py` finds none of the 2,746 packed files
in `scenes/test/`, `assets/test_world/` or `data/test/`; every record validates without `data/test`),
checked in headless Chromium with SwiftShader on the container's 4 cores, which another agent's checks
shared (indicative: software WebGL). The merge's own check (`tools/check.sh --build --slow --audio --gate`
on 9a47f2d; the release's base, 47a2fe8, adds only that check's record, above): 271 suites, 46,563 checks,
0 failures (default 63.3 s, slow 256.5 s, gate 423.8 s), both full builds byte for byte, the seams (64
chunks, 112 seams), 441 audio files bit-exact, the 120 s soak with 0 errors. The release's own
`tools/check.sh` (the default tier, with the launcher's notes, the new check tool and this record): 204
suites, 36,577 checks, 0 failures - default 88.4 s, over its 75 s budget only under another agent's Godot
runs on the 4 cores (load average 6-8; the merge's check took 63.3 s) -, the 120 s soak with 0 errors (2
fences broken, 2 loot awards, the debris pool at 10), 2 min 22 s in all. The launcher's notes (lane m8p's)
gained the trees that fade between the camera and the giant, Fort Aldmere's portcullis, which holds the
giant in the bailey until the Iron Regiment is beaten (the one arena he cannot walk out of), and what the
scripted runs cover (every pair of oaths in either order).

**The release patch (lane m8r).** The release check of the candidate (5e8e972) found a blocker, R1: a
checkpoint request held back before Fort Aldmere's battle by aware enemies was committed mid-battle the moment
the Wall's last unit fell, and after a death, or a quit and Continue, the next attempt shut the giant in the
bailey with a Wall the director never brought back (Wall 0/24, the battle stuck engaged, the crown's breach
lost for that save). Lane m8r fixed it, with two smaller items (`docs/systems/P34.md`, `P06.md`, `P36.md`,
`P19.md` and `P20.md`, "M8 release"):

- **R1.** No checkpoint is committed while a boss fight or a battle is engaged (GameSession's fight blocker:
  ordinary and completion requests and travel wait for the fight's end, its reset or a disengage, and a death
  drops them with the attempt); the fight's own end is still checkpointed. A battle starts every attempt
  afresh, repairs a save written mid-battle as it loads (the portcullis open, the Wall whole), and never waits
  on units that will never come. Harrok's talk ending chosen mid-duel ends the duel without a victory
  (`boss_disengaged` "yielded_talk": the yield stinger and the end checkpoint `boss_yielded_talk`, no
  defeated flag). New suites: `test_battle_reload` (default, 83 checks, 1.07 s), `test_fight_checkpoints`
  (default, 62 checks, 0.23 s) and `test_iron_regiment_reload` (gate, the real fort, 87 checks, 2.9 s); more
  checks in `test_checkpoint_triggers`, `test_audio_director` and `test_title_checkpoint_names`. Each new
  test fails on the candidate.
- **R2.** The title's saved-game line names where Continue wakes the giant (an m7 save after the Brannock
  force: "at the Kingsgate shelf waystone").
- **R3.** `docs/plans/FOLLOWUPS.md` ("From the M8 release check"): the novice bot does not win the Iron
  Regiment unassisted at stage 4 or 5; its difficulty is left for P39's balance pass.

The merge's check (`tools/check.sh --build --slow --audio --gate` on the merge, a0d59b7, after an import, a
full build and an import of its own): both full builds (every builder, the world included) wrote the committed
outputs byte for byte, so nothing was regenerated; the seam check passed (64 chunks, 112 seams); the audio
pipeline's 35 tests passed and its 441 files regenerated bit-exact; 274 suites, 46,823 checks (the release's
merge, 9a47f2d: 271 and 46,563), 0 failures; default 64.9 s (budget 75 s), slow 249.0 s (8 minutes), gate
423.5 s (50 minutes); the 120 s soak with 0 errors and 0 warnings (2 fences broken, 2 loot awards, the debris
pool at 10). The whole check took about 17 min. The web release was rebuilt from the merge
(`tools/build_web.sh`, preset `Web`; still no test content in the 2,746 packed files, every record valid
without `data/test`) and checked again in headless Chromium (the machine otherwise idle, load average under
1.5); the table gives the patch's numbers, with the candidate's where they differ. No frame time or draw
calls were re-measured natively: the lane changed no builder, layout, chunk, generated output or audio.

| Item | Result |
| --- | --- |
| `index.wasm` | 37,700,666 bytes; 12,528,700 as shipped (gzip, base64), as at 0.7.0-m7 |
| `index.pck` | 17,457,348 bytes (12,998,617 gzipped); 17,331,492 as shipped in two parts of 8,665,746 bytes (the host's cap is 15 MB a part): 16.53 MB of the M8 budget of 23 MB; the audio 9.28 MB, 56.6 % of its files (the candidate: 17,452,804 bytes, 17,326,012 as shipped in two parts of 8,663,006, 16.52 MB) |
| The page's download | about 29.9 MB (the engine 12.5 MB, the pck 17.3 MB; 28.5 MB on the launcher's meter, which counts in MiB), so its "About 30 MB" holds |
| `stream_check.mjs --world --audio` (the world's default route, no `--route`) | The patch: OK in its default form: 396.9 m in 47.4 s of game time (124.5 s of wall time; Play to the walk 36.7 s), 4 region borders, 3 seams, 6 loads, 3 unloads, 0 thrash, at most 16 chunks loaded, 226.3 m of margin, streaming work p50 0.8 / p99 6.1 / max 13.2 ms, draw calls p50 38 / max 58, 0 console errors while the game ran (the one at exit is the engine's audio teardown), 0 failed requests; 86.7 s of music with 279 holes over 50 ms (the longest 403.4 ms), every one placed on the main thread (357 long tasks, the longest 458 ms); peak live samples 57.1 MB of the 67.9 MB cap; page frames p50 233.4 / p99 333.4 / worst 449.9 ms. The candidate: OK in its default form: 396.9 m in 47.4 s of game time (160.4 s of wall time; Play to the walk 47.8 s), 4 region borders (Crownmarch, Drowned Steps, Greywood, Drowned Steps, Crownmarch), 3 seams, 6 loads, 3 unloads, 0 thrash, at most 16 chunks loaded, 225.1 m of margin, streaming work p50 0.8 / p99 6.1 / max 7.0 ms, draw calls p50 38 / max 58, 0 console errors while the game ran (the one at exit is the engine's audio teardown, as at M7), 0 failed requests; 111.9 s of music with 354 holes over 50 ms (the longest 478.9 ms), every one placed on the main thread (355 long tasks, the longest 499 ms); peak live samples 57.1 MB of the 67.9 MB cap; page frames p50 300.0 / p99 466.6 / worst 516.6 ms. The plan's criterion NOT MET here (the strict form is the owner's, on a GPU) |
| `audio_check.mjs` (the Valley) | The patch: OK in its default form: Play to the title's music 5.5 s, New Game to the Hollow 6.8 s, sound 0.34 s after the Hollow's music begins, 60.2 s of music with 153 holes over 50 ms (the longest 246.7 ms), every one placed on the main thread (432 long tasks, the longest 315 ms); peak live samples 37.0 MB of the 48.0 MB cap; 0 console errors, 0 failed requests. The candidate: OK in its default form: Play to the title's music 5.3 s, New Game to the Hollow 8.4 s, sound 0.28 s after the Hollow's music begins, 60.3 s of music with 241 holes over 50 ms (the longest 409.3 ms), every one placed on the main thread (302 long tasks, the longest 471 ms); peak live samples 37.0 MB of the 48.0 MB cap; 0 console errors, 0 failed requests. Criterion NOT MET here, as at M6 and M7 |
| The launcher's two starts (`tools/web/world_start_check.mjs`, new) | The patch: OK. Play starts the engine (6.0 s) with no game arguments, no save at the title, and Enter writes the Valley's first save 18.9 s later; one press of "Start in the open world" only arms it (nothing of the engine fetched) and it disarms 6 s later; two presses start the engine (6.9 s) with `['--', '--mode=world']`, and the first save, 7.3 s later, holds `"level": "level.world"`, respawn `world.cp.kingsgate_shelf`, stage 3, level 6; 0 console errors and 0 failed requests in both. The candidate: OK. Play starts the engine (5.9 s) with no game arguments; the title writes no save, and Enter (New Game) writes the Valley's first save 30.1 s later (`"level": "level.valley"`, respawn `valley.shrine.hollow`). One press of "Start in the open world" only arms it ("Press again to start a new game in the open world"; the gate stays and nothing of the engine is fetched), and it disarms 6 s later; two presses start the engine (7.1 s) with `['--', '--mode=world']`, and the first save, 7.7 s later, holds `"level": "level.world"`, respawn `world.cp.kingsgate_shelf`, stage 3, level 6. 0 console errors and 0 failed requests in both |
| Linux export (`builds/linux/Giantborn.x86_64`, 89,896,096 bytes) | The candidate's (not rebuilt for the patch). The 120 s soak headless: 0 errors, 0 warnings (fence breaks 2, loot 2, debris 10). An assisted novice Valley run (`--scenario=valley --bot-village=intimidate --bot-skill=novice --bot-seed=1 --bot-assist --perf`): completed in 446.4 s of simulated time, as at 0.7.0-m7, 0 deaths, 0 breaches, 0 invariant failures, 0 errors, 0 warnings (one stuck moment on the causeway, cleared by a side-step jump; no teleport); CPU per tick p50 2.7 / p95 9.4 ms with another agent's Godot runs on the 4 cores (load average 6-8; 3.5 ms p95 at 0.7.0-m7) |
| Windows export (`builds/windows/Giantborn.exe`, 123,479,696 bytes, and `Giantborn.console.exe`, 188,928 bytes) | The candidate's (not rebuilt for the patch). Built; not launched (no Windows here) |

### The M9 performance captures (P39, plan §6.3)

Plan M6-M9 §6.3's captures that need no merged code, on the measurement lane's branch (`pkg/P39`: `wave-22` with
P39's tuning, its bot fixes and the measurements below; the game code of commit `00a2bad`). The container as above: 4
shared CPU cores, no GPU, a debug build from the project folder (text scenes). **Two sets, both indicative.** The
numbers below are the second set, taken on 13 November after a container restart, one process at a time with nothing
else running on the machine (the other W23 lane, P39f, had finished; the first runs after the restart read the
game's files from a cold cache). The first set, taken on 12 November while lane P39f worked beside them and, for
the rendered captures and the chase, two of P39's own bot runs shared the cores (load average 3-4; the headless
walk and the headless formation stress on an idle machine), is given in brackets where it differs. The confirmation
phase repeats them on the merged code. The web world (`world_check.mjs`, `stream_check.mjs --world --audio`) is lane
P39f's (`docs/systems/P39f.md`).

**The world walk** (§6.3: "a route through every region at stage 6 sprint, a settlement and a border walk"). The
world's default route (`walk_route`, about 400 m) is the web checks', so the capture gives its tour with `--route`:
from the Kingsgate shelf down the King's Road through Brannock's green, a border walk across the Crownmarch and the
Drowned Steps east of Brannock, the Drowned Steps' Mere road west into the Greywood to Hollowmere, back east past the
bell tower and the Titan's Bones, Fort Aldmere's gate and the Ironway, up the ramp to Skarn and along the high
Ironway past the Moot battery to Harrok's Hall: 50 points, 5,555 m, every region (the Crownmarch, the Drowned Steps,
the Greywood, the Drowned Steps again, Aldmere, the Stonehold), 25 seams, carried at 16 m/s (the stage-6 sprint) at
stage 6, AI on (the encounters on the way engage the invulnerable giant). The command is under "Commands" below.

| | Headless (deterministic streaming: every step on the main thread) | Rendered (Xvfb 640 x 360, llvmpipe, `low`; threaded resource loads) |
| --- | --- | --- |
| Walk | 5,555.3 m in 342.6 s, finished, 0 errors, 0 warnings, no check failure | the same, 5,555.7 m |
| Streaming | 62 loads, 56 unloads, 0 thrash, at most 16 chunks loaded, the least margin 250.3 m; work per frame p50 0.52 / p99 6.91 / max 12.48 ms [0.63 / 7.50 / 17.72]; the heaviest step a `props_load` 12.47 ms (43 loads, 155.1 ms in all: a props part's text scene parsed, P39f's finding) [17.71 ms; and a `data` step of 13.82 ms, 0.41 ms now]; `nav_load` at most 1.53 ms | 0 thrash, the least margin 248.7 m; work per frame p50 0.10 / p99 4.24 / max 6.77 ms [0.08 / 4.14 / 4.60] (the resource loads off the main thread: `nav_request` steps) |
| CPU per tick | p50 2.79 / p95 5.81 / p99 7.87 / max 22.5 ms [2.57 / 5.32 / 7.18 / 19.3] (the slowest ticks in the Drowned Steps' c3_3 and the Greywood's c1_4 and c1_3: encounters spawning); `sim_ms` p95 4.74 | p50 4.30 / p95 7.83 / p99 10.0 / max 41.4 ms [3.17 / 6.13 / 8.09 / 31.7, two bot runs beside it]: llvmpipe renders on the same four cores, so the headless column is the budget's |
| Path queries per tick | p50 0 / p95 1 / max 4 (20,552 ticks) | the same |
| Active combatants | mean 6.3, at most 12 | mean 6.2, at most 12 |
| Nodes, objects | nodes p50 2,886 / max 3,599, objects p50 8,110 / max 9,483; orphans at most 1 | the same within 0.1 % |
| Static memory | p50 259.5 / max 280.3 MB | p50 267.0 / max 287.7 MB |
| Draw calls (`low`, the HUD included) | - | p50 40 / p95 63 / p99 79 / max 91 (both sets: c6_1, the top of the Ironway ramp east of Skarn); primitives at most 121,460; render objects at most 1,734 |
| Per chunk (the probe's sections) | CPU per tick p95 at most 7.33 ms (c4_1, the high Ironway east of the Giant's Stair) and 7.27 ms (c5_1, Skarn) | draw calls at most 91 (c6_1), 86 (c5_1, Skarn), 74 (c3_1, the Moot battery) |

Against §5.2's budgets: CPU per tick p95 under 8 ms, the margin over 200 m, no thrash, at most 25 chunks, draw calls
far under 250 - **met**; the streaming work's 4 ms a frame is **not met** in either form: rendered, with the loads on
the loader thread, p99 4.2 ms and the worst frame 6.8 ms (the first set's 4.6), and in deterministic headless
streaming, where one `props_load` (the parse of a large text props part) takes up to 12.5 ms (the first set's 17.7) -
just over §6.4's 12 ms for the headless work frame. Exports ship the props parts as binary scenes, whose parse is about
a tenth of the text's (`docs/systems/P39f.md`, "The heaviest streaming step").

**The unreachable chase** (P24b's slow test, `tests/slow/test_unreachable_chase.gd`: 20 soldiers chasing a giant that
wades in the test world's pond for 20 s), three runs:

| Run | CPU per tick p50 / p95 / p99 / max (ms) | [first set, beside the rendered walk] | Re-paths |
| --- | --- | --- | --- |
| 1 | 2.38 / 4.44 / 5.89 / 11.7 (the first Godot run after the bot runs) | [2.16 / 4.57 / 6.61 / 8.16] | 228; at most 8 in a tick (twenty asking at once served 8, 8, 4); 1 path failure |
| 2 | 2.02 / 3.20 / 3.97 / 6.12 | [2.10 / 4.31 / 5.99 / 9.08] | the same |
| 3 | 2.20 / 3.55 / 4.85 / 9.51 | [2.14 / 4.73 / 6.85 / 9.14] | the same |

The budget's p95 8 ms: **met** (P24b measured 3.9 ms on an idle machine).

**The formation stress with two engines** (`--level=res://scenes/test/formation_test.tscn --scenario=stress
--stress-formations --autoplay=60 --graphics=low`). P39 adds two of the siege test level's engines to the stress case
(plan §6.3): the stress bot places its west ballista and west catapult (the same scenes, `StressScenario.P39_ENGINES`)
31 m and 49 m behind the giant's walk along the regiments' front and activates their three crews
(`encounter.formation_test_engines`), so the 40 members at tier 0 are measured with two crewed engines turning, aiming,
shooting and reloading. 60 s, both runs: the 40 members spawned, every sample at tier 0 (4,800), 12 promoted, both
regiments braced 3 times, the ballista shot 7 times and the catapult 5, both crewed the whole minute, 3 counted
combatants (the crews), the giant never dead, 0 errors - in all four runs alike.

| | Headless | Rendered (Xvfb, llvmpipe, `low`) |
| --- | --- | --- |
| CPU per tick p50 / p95 / p99 / max | 2.97 / 4.58 / 5.98 / 100.1 ms [2.78 / 4.21 / 5.38 / 10.8, an idle machine]: the 100 ms is one tick, tick 462, the same tick as the first set's third slowest (8.9 ms); no other tick over 10.4 ms | 3.44 / 5.07 / 6.41 / 15.0 ms [3.20 / 5.92 / 8.07 / 15.2, a bot run and the rendered walk beside it] |
| Draw calls p50 / p95 / max | - | 63 / 94 / 100 (both sets) |
| Nodes | 1,894-1,900 | the same |

P30's stress case without the engines: 3.69 ms p95 over 40 s. The budget's p95 8 ms and 250 draw calls: **met**.

**The bot batches by region** (§6.3: "`--perf` on every balance run: CPU per tick p95 per region"). Since this part
the world bot's probe files its samples under the region the giant stands in and the result keeps them
(`perf.sections`; `python3 tools/bot_report.py <batch> world_perf`). The matrix's novice half (the novice on seeds 1-2
of the three presets and the three first-oath orders, tag `p39_rep_world`, on 13 November: two streams of one run
each and nothing else on the machine; the two conqueror novices made again the same way after the report's review,
`p39_fx1_world`, on `331d3b4`), CPU per tick p95 in ms by the region the giant stood in, with the seconds it spent
there:

| Run | The Crownmarch | The Greywood | The Aldmere March | The Stonehold | Whole run |
| --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | 6.14 (807 s) | 5.23 (236 s) | 6.93 (103 s) | 5.80 (349 s) | 6.03 |
| w_peaceful_novice_2 | 6.36 (725 s) | 5.23 (237 s) | 6.59 (104 s) | 5.79 (451 s) | 6.08 |
| w_conqueror_novice_1 | 7.33 (395 s) | 6.00 (487 s) | - | - | 6.80 |
| w_conqueror_novice_2 | 7.10 (337 s) | 5.72 (460 s) | - | - | 6.50 |
| w_mixed_novice_1 | 6.07 (216 s) | - | 11.27 (377 s) | 7.02 (444 s) | 9.61 |
| w_mixed_novice_2 | 6.32 (192 s) | - | 10.84 (437 s) | 7.02 (446 s) | 9.50 |
| w_order_march_novice_1 | 6.95 (622 s) | - | 7.46 (262 s) | 6.67 (499 s) | 6.98 |
| w_order_wood_novice_1 | 6.87 (421 s) | 5.84 (325 s) | 7.62 (118 s) | 6.93 (412 s) | 6.81 |
| w_order_crown_novice_1 | 5.80 (220 s) | - | 9.27 (1,054 s) | - | 8.99 |
| **Median of the runs (largest)** | 6.36 (7.33) | 5.72 (6.00) | 7.62 (11.27) | 6.80 (7.02) | 6.81 (9.61) |

The Drowned Steps have no column: the main path only crosses them (the world walk above measures them). Against the
budget's p95 8 ms: the Crownmarch, the Greywood and the Stonehold **met** in every run; the Aldmere March **met** on
the way through (6.6-7.6 ms) and **not met** in its two big fights - the war camp's sabotage in the mixed runs (10.8
and 11.3 ms; the two runs were in the camp at the same time, on the same four cores) and the Iron Regiment's battle
(9.3 ms over 1,054 s: the bailey's four formations, the wall's crews and ballistae and the riders). Each run's worst
streaming work frame was 19.0-41.0 ms (its heaviest single steps a props part's load, up to 14.3 ms, as on the world
walk), the loaded margin 253.9-254.9 m with no thrash, path queries a tick p95 1 and at most 6-8, at most 12 counted
combatants. The expert's runs (iteration 3's, on the code before the region sections) read 5.9-11.5 ms for the whole
run, beside the other lane's checks.

### The M9 confirmation (W23, the merged code; plan §6.3)

The captures above again on the merged W23 code - `wave-23` (lane P39's tuning and bot, lane P39f's fixes and its rebuilt
world) with the Iron Regiment's threshold fix (commit `a7da72d`; `docs/BALANCE_LOG.md`, "M9 confirmation") - on 13
November, one process at a time with nothing else running on the machine, before the confirmation matrix. The container
as above (4 shared CPU cores, no GPU, a debug build, text scenes): indicative. The commands are P39's ("Commands"); the
logs are in the confirmation phase's evidence folder (`m9_w23/confirm/perf/`, `web/`). P39's quiet set on `pkg/P39` in
the right-hand column.

| Capture | The merged code (W23 confirmation) | P39's quiet set (`pkg/P39`) |
| --- | --- | --- |
| World walk, headless: the walk | 5,530.5 m in 342.6 s on the same 50 points (the rebuilt world's ground), finished; 25 seams, every region; 0 errors, 0 warnings | 5,555.3 m |
| World walk, headless: streaming | 62 loads, 56 unloads, 0 thrash, at most 16 chunks loaded, the least margin 250.3 m; work per frame p50 0.51 / p99 6.97 / max 12.19 ms, 19 work frames over 4 ms; the heaviest step a `props_load` 12.18 ms (43 of them, 158.9 ms in all), then `props_add` 2.86 and `nav_load` 1.49 ms | the same counts; work 0.52 / 6.91 / 12.48 ms, `props_load` 12.47 ms |
| World walk, headless: CPU per tick | p50 2.89 / p95 5.89 / p99 8.00 / max 30.5 ms (the slowest ticks in the Drowned Steps' c3_3: encounters spawning); by chunk at most 7.22 ms (c4_1, the high Ironway) and 7.20 ms (c5_1, Skarn) | 2.79 / 5.81 / 7.87 / 22.5 ms |
| World walk, headless: the rest | path queries a tick p50 0 / p95 1 / max 4 (20,552 ticks); active combatants mean 6.3, at most 12; nodes p50 2,843 / max 3,490, objects max 9,257, orphans at most 1; static memory p50 259.6 / max 278.3 MB | the same within 3 % |
| World walk, rendered (Xvfb 640 x 360, llvmpipe, `low`) | draw calls p50 39 / p95 63 / p99 79 / max 91 (c6_1; c5_1 86, c3_1 73); work per frame p99 4.12 / max 4.77 ms (the loads on the loader thread); CPU per tick p95 7.69 ms (llvmpipe shares the cores); the least margin 249.0 m; 0 errors | draw calls 40 / 63 / 79 / 91; work 4.24 / 6.77 ms; CPU 7.83 ms |
| Unreachable chase (P24b's slow test, three runs) | CPU per tick p95 3.32 / 3.33 / 3.32 ms (max 7.2-10.9); 228 re-paths, at most 8 a tick (twenty asking at once served 8, 8, 4) | 4.44 / 3.20 / 3.55 ms |
| Formation stress with two engines | headless CPU per tick p50 2.93 / p95 4.39 / max 12.9 ms; rendered p95 5.47 ms, draw calls p50 63 / p95 94 / max 100; the 40 members at tier 0 in all 4,800 samples, both regiments braced 3 times, both engines crewed the whole minute (7 bolts, 5 stones), 0 errors | 4.58 ms headless (one 100 ms tick), 5.07 rendered; draw calls 63 / 94 / 100 |

Against §5.2 and §6.4: CPU per tick p95 under 8 ms headless, the margin over 200 m, no thrash, at most 25 chunks loaded,
draw calls far under 250 - **met**; the streaming work's 4 ms a frame **not met** (rendered p99 4.1 ms, the worst frame
4.8 ms; deterministic headless the worst frame 12.19 ms, one `props_load` - the parse of a large text props part, which
exports ship binary - so §6.4's 12 ms is **not met** by 0.2 ms).

**The web** (plan §6.3, §6.6): the release build (`env -u XDG_DATA_HOME tools/build_web.sh --out=builds/confirm_web`, no
test content) in headless Chromium with software WebGL, one check at a time:

| Check | Result |
| --- | --- |
| The pck | 17,567,168 bytes (13,106,092 gzipped), shipped 17,474,792 bytes = **16.67 MB of the 23 MB budget**, in 2 parts of 8,737,396 bytes (at most 15 MB each: met); 2,752 packed files, no test content, every record valid without `data/test`; the audio 9.28 MB of the pck's 16.75 MB (55 %); the engine 37,700,666 bytes (12,528,700 shipped) |
| `audio_check.mjs` | OK in its default form: Play to the title's music 6.2 s, New Game to the Hollow 6.5 s, sound 0.34 s after the Hollow's music; 60.3 s of `music.valley_calm` with **204 holes over 50 ms** (the longest 226.4 ms), every one while the main thread left the mixer unserved (page frames p50 150 ms); peak live samples 37.0 of 48.0 MB; 0 console errors. The plan's criterion: **NOT MET here** |
| `stream_check.mjs --world --audio` | OK in its default form: a 397.5 m walk across four region borders, 95.3 s of music with **322 holes over 50 ms** (the longest 388.9 ms), every one on the main thread; page frames p50 250 / p99 383 / worst 450 ms (the indicative 25 / 45 ms: missed); streaming work max 5.6 ms, the least margin 225.8 m, 0 thrash; draw calls max 58; peak live samples 57.1 of 67.9 MB; 0 console errors (one page error after the result, at exit). The criterion: **NOT MET here** |
| `world_check.mjs` (first run) | **FAILED** in its default form on one hole the recorder did not place on the main thread (403.4 ms at 103.2 s of the page; the other 604 holes over 50 ms were the main thread's, one of them cut by the walk's end); otherwise as lane P39f's runs: the fixture Continued with one Enter (11.5 s to control), the fast travel to the King's Road waystone 5 s with no refusal, a 787.7 m walk across three region changes in 80.7 s of game time, 0 stuck; page frames p50 433 / p99 683 / worst 1,017 ms; streaming work max 16.3 ms (22 of 145 work frames over 4 ms; the heaviest steps `scenery` 13.8, `rows` 13.3, `nav_request` 13.2 ms), the least margin 211.8 m, 0 thrash; peak live samples 57.3 of 67.9 MB; 0 console errors, no engine warning (neither load reached the 8 s ring warning). The load average was 5.6-6.7 during it (Chromium's own threads) |
| `world_check.mjs` (again, after the bot runs, nothing else running) | **OK** in its default form (alone, once the bot runs had ended; 5 min 40 s of wall): the fixture Continued with one Enter (14.4 s to control), the fast travel to the King's Road waystone 6.8 s with no refusal, the same 787.7 m walk in 80.7 s of game time across three region changes, 0 stuck; page frames p50 483 / p99 850 / worst 933 ms; streaming work max 26.6 ms (31 of 147 work frames over 4 ms; the heaviest steps `scenery` 26.0, `decode` 15.1, `rows` 8.2 and `props_load` 7.5 ms), the least margin 210.4 m, 0 thrash; 300 s of music with **605 holes over 50 ms** (the longest 882.4 ms), every one placed on the main thread; peak live samples 57.3 of 67.9 MB; 0 console errors, no engine warning, the game's own count 0 errors and 0 warnings. The first run's one unplaced hole did not come back: the default verdict depends on the machine's load (lane P39f's note, "The default form is load-dependent here"). The plan's criterion: **NOT MET here** |

The strict forms (no hole at all; `--strict` on all three checks) are the owner's on a machine with a GPU
(`docs/USABILITY_SCRIPT.md` §11): **NOT RUN**.

**The bot batches by region** (§6.3: "`--perf` on every balance run"): the confirmation's world matrix (`confirm_world`,
21 runs: the novice and the expert on seeds 1-3 of the three presets and the three first-oath orders; three Godot
processes at a time with nothing else on the machine), CPU per tick p95 in ms by the region the giant stood in, with the
seconds it spent there (`python3 tools/bot_report.py <batch> world_perf`):

| Run | The Crownmarch | The Greywood | The Aldmere March | The Stonehold | Whole run |
| --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | 6.89 (980 s) | 5.92 (250 s) | 8.30 (125 s) | 6.66 (560 s) | 6.86 |
| w_peaceful_novice_2 | 7.06 (964 s) | 6.01 (253 s) | 7.77 (125 s) | 6.64 (478 s) | 6.92 |
| w_peaceful_novice_3 | 6.68 (1,066 s) | 6.04 (282 s) | 8.45 (127 s) | 6.54 (470 s) | 6.77 |
| w_conqueror_novice_1 | 7.98 (403 s) | 6.59 (451 s) | - | - | 7.40 |
| w_conqueror_novice_2 | 8.10 (508 s) | 6.95 (451 s) | - | - | 7.65 |
| w_conqueror_novice_3 | 8.02 (385 s) | 7.21 (462 s) | - | - | 7.61 |
| w_mixed_novice_1 | 8.33 (341 s) | - | 11.77 (437 s) | 7.83 (516 s) | 10.18 |
| w_mixed_novice_2 | 7.78 (378 s) | - | 11.63 (444 s) | 7.91 (546 s) | 10.03 |
| w_mixed_novice_3 | 7.99 (406 s) | - | 12.54 (509 s) | 7.75 (586 s) | 10.64 |
| w_order_march_novice_1 | 6.75 (802 s) | - | 8.39 (180 s) | 6.77 (285 s) | 7.08 |
| w_order_wood_novice_1 | 6.80 (491 s) | 5.79 (282 s) | 8.48 (136 s) | 6.18 (306 s) | 6.83 |
| w_order_crown_novice_1 | 6.66 (368 s) | - | 8.82 (259 s) | - | 7.92 |
| w_peaceful_expert_1 | 9.99 (1,464 s) | 7.64 (540 s) | 9.88 (117 s) | 8.50 (675 s) | 9.45 |
| w_peaceful_expert_2 | 9.65 (1,346 s) | 7.28 (321 s) | 9.79 (125 s) | 9.03 (352 s) | 9.33 |
| w_peaceful_expert_3 | 9.15 (1,840 s) | - | - | - | 9.15 |
| w_conqueror_expert_1 | 7.25 (584 s) | 5.31 (785 s) | - | - | 6.44 |
| w_conqueror_expert_2 | 7.49 (618 s) | 5.55 (665 s) | 8.47 (113 s) | 6.78 (938 s) | 6.91 |
| w_conqueror_expert_3 | 7.14 (616 s) | 5.43 (785 s) | - | - | 6.47 |
| w_mixed_expert_1 | 7.91 (609 s) | - | 11.35 (953 s) | 8.43 (563 s) | 10.19 |
| w_mixed_expert_2 | 7.00 (348 s) | - | 11.21 (462 s) | 7.68 (640 s) | 9.51 |
| w_mixed_expert_3 | 7.54 (467 s) | - | 12.16 (660 s) | 8.23 (738 s) | 10.40 |
| **Median of the runs (largest)** | 7.54 (9.99) | 6.02 (7.64) | 9.79 (12.54) | 7.71 (9.03) | 7.65 (10.64) |

The Drowned Steps have no column (the main path only crosses them; the world walk measures them). Against the budget's
p95 8 ms: the Greywood **met** in every run (5.3-7.6 ms); the Crownmarch and the Stonehold in most runs - not in the
Crownmarch for two conqueror novices (8.02 and 8.10 ms), the first mixed novice (8.33) and the peaceful experts' long
fights at the toll fort (9.15-9.99), nor in the Stonehold for four experts (8.23-9.03); the Aldmere March **not met** in
the war camp's sabotage (11.2-12.5 ms in the six mixed runs) and on the way through in all but one run (7.77-9.88 ms).
Three runs at a time on the four cores read higher than lane P39's
two at a time (its novice runs above: the Crownmarch's median 6.36 ms, the same seeds' peaceful novices 6.14-6.36 against
6.89-7.06 here): indicative, the reference PC is the measure. Each run's worst streaming work frame was 17.9-33.9 ms (a
props part's load), the loaded margin 252.7-255.3 m with no thrash, path queries a tick p95 at most 1 and at most 4-8.
The director's counted combatants stayed at 12 or fewer in 14 runs; in the six conqueror runs they reached 13-17 for
0.02-0.35 s (the Crownmarch turning hostile at the march's force) and in `w_mixed_novice_3` 16 for 43.6 s (the war camp
turning hostile in the sabotage): members already in the world when their faction turns count, and new spawns wait for
room (the director's rule: `docs/systems/P39f.md`, "The war camp's 16 counted combatants"); no counted member spawned at
the cap (the bot's budget invariant held in every run). Lane P39's set: 12 in every run.

## Reference PC results (owner: NOT RUN)

| Run | Machine (CPU, GPU, driver) | Frame ms p50 / p95 / p99 | GPU ms p50 / p95 | CPU render ms p95 | Sim CPU per tick p95 / p99 | Draw calls max | Exit code |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Stress, low, V-Sync on | | | | | | | |
| Stress, low, `--disable-vsync` | | | | | | | |
| Valley walk, low, V-Sync on | | | | | | | |
| Valley walk, low, `--disable-vsync` | | | | | | | |

## Findings and recommendations

1. **Sim CPU per tick is within its budget** in the container: p95 4.88 ms in the stress route
   (twelve engaged combatants, debris at its cap) and 3.37 ms on the Valley walk, against 8 ms, in a
   debug build. Real-PC numbers: NOT RUN.
2. **Draw calls (P27: the HUD batched; P22: the actors are merged and fade to boxes by distance).**
   See "Draw calls after P27": the HUD costs about 10 draw calls a view instead of about 120, and the
   Valley walk at `low` is at p50 93, p95 143, max 154 - under the budget everywhere. Before it, "Draw
   calls after P22": a rig costs about 6 draw calls, and beyond its record's distance one; the Valley
   walk at `low` was at p50 201, p95 251, max 268 (Thornwick's square with thirteen people). Before P22 (P17b):
   the props are merged and faded with the scenery and `low` has no sun shadows, so a
   static view costs at most 93 draw calls at `low` and 221 at `medium`; the walk was at p50 256,
   max 656 at `low`, views with about five or more full-rig enemies over 250 (about 33 each).
   P14's original finding follows. **Draw calls were 2-4 times over the 250 budget** in the Valley
   (p50 493, max 1,084 at `low`) and the stress arena (p50 860). Draw calls do not depend on the
   GPU, so this holds on the reference PC.
   What makes them: the props (each prop scene is several meshes: posts, rails, leaves, stones,
   frames) and the sun's shadows, which roughly double every view; the scenery trees (MultiMeshes)
   and the district geometry are small. Twelve full enemy rigs add about 250. Recommendations, in
   order of effect, for the owners of the presets (P17b, P18) and the builders (P08's props, P15's
   dressing):
   - turn the sun's shadows off in the `low` preset: `render.low.shadow_distance_m: 0` in the level
     records (supported since P14; it changes the look, so it is the tuning owner's call) - **done
     in P17b**;
   - build each prop's visuals as one mesh per material and stage (merge the boxes of fences, gates,
     carts and houses) or as MultiMeshes for repeated props - **done in P17b** (one mesh per group);
   - switch `cast_shadow` off on small props and decor, and give small props a visibility range -
     P17b gave every prop the scenery's range instead (its shadows go with the `low` preset).
3. **Encounter spawn hitch.** An encounter activation instances its members in one tick: 13-25 ms per
   activation in the container, and the first spawn of an enemy kind also loads its scene during play
   (loading alone: wolf 124, soldier 104, archer 135, mage 105, ogre 97, Ogre King 152 ms); the walk's
   forced activation of five encounters at once took 387 ms. Recommendation (the director's owner):
   load the level's enemy scenes with the level (behind the "Loading..." frame) and spread a spawn
   over a few ticks.
4. **AI LOD.** Tier 2 is where the savings are (above). Tier 1 costs about what tier 0 costs for
   idle members, which still move and collide every tick; it pays off only for pursuing members
   (fewer sight rays and re-paths), and engaged members always run tier 0. So the web override that
   starts tier 1 at 30 m changes little; a nearer tier 2 on the web (for example from 70 m) would
   save more, but needs a `web_overrides` field the `level` schema does not have yet. The tuning pass
   changed no constant: near 40 m, mid 90 m, a 30-tick check, a budget of 12 (CPU per tick stays well
   inside its budget with all twelve engaged).
5. **Debris** reaches its cap of 40 in bursts (a dense corner breaking) and averages 8 pieces; with
   twelve combatants the stress route stays at 4.88 ms p95.
6. **Measuring.** `Performance.TIME_PHYSICS_PROCESS` and `TIME_PROCESS` are per-second maxima in
   Godot 4.6, not per-frame values (see PerfProbe); compare runs by `cpu_tick_ms`.
7. **The world (P39, M9; "The M9 performance captures (P39)").** On the container the world stays inside its CPU
   budget on the tour through every region (p95 5.8 ms headless) and in the campaign everywhere but Fort Aldmere's
   two big fights: the war camp's sabotage (p95 10.8-11.3 ms in the mixed runs) and the Iron Regiment's battle (9.3
   ms) - the places with the most formations, crews and engines at once. Recommendations for whoever measures the
   merged code next: run the confirmation matrix's Aldmere fights with the probe's sections (they come with the bot
   run) on a quiet machine before deciding anything, and on a real PC (NOT RUN). The streaming work frame is
   the text props parts' parse (12.5-17.7 ms headless on the tour, 19-33 ms frames in the campaign runs): measure
   it on an export, whose binary scenes parse in about a tenth of the time, before splitting the parts further.

## Web build checklist (P18: Chromium with software WebGL; real browsers NOT RUN)

The play link is the single-threaded web export (`tools/build_web.sh`, `web_nothreads_release`).
P18 served `builds/web/` locally and drove `play.html` with Playwright's Chromium 153 using
SwiftShader (software WebGL) on the container's shared CPU: headless for the boot, New Game, the
save and Continue, headed under Xvfb for the mouse capture. Frame times and load times there say
nothing about a real GPU; they are listed only to show the build works.

| Check | P18 in the container | Real browser |
| --- | --- | --- |
| The page fits without a sideways scroll | Met at 1280 px (scroll width = client width) | NOT RUN |
| Play downloads, unpacks and starts the engine | Met: the engine started 5.7 s after Play (4.6 s after a reload); about 14 MB to download. Now (the 0.8.0-m8 release, its patch): about 29.9 MB to download (the engine 12.5 MB, the pck 17.3 MB in two parts); the engine started 6.0 s after Play | NOT RUN |
| The title screen, then New Game into the Valley | Met: the title shows build 0.5.0-m5; New Game reaches the Hollow, its first checkpoint stored after 14.2 s | NOT RUN |
| The Valley loads in at most 6 s behind the "Loading..." frame (plan §5.4) | Not judged (software rendering; 14.2 s includes the storage sync) | NOT RUN |
| The save survives a page reload (IndexedDB) | Met: `/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json` is in IndexedDB before and after the reload; the title then offers Continue ("Saved game: level 1, stage 1 ...") and Continue loads the Valley at the Hollow Shrine | NOT RUN |
| The title's button that starts a mode takes the mouse (pointer lock inside the click) | Met (headed): no lock on the title or after a click on Settings; locked after the New Game click and in the Valley; Esc releases it | NOT RUN |
| The build runs the `low` preset whatever the saved setting says | Met: the Valley renders without sun shadows (the `low` preset); `test_graphics_quality` covers the web forcing `low` over a `medium` setting (the Settings row's lock is tested under `--graphics`) | NOT RUN |
| AI tier 1 starts at 30 m (`level.valley` `web_overrides.ai_tier1_m`) | Covered by `test_graphics_quality` (forced web) | NOT RUN |
| The packed `.pck` is at most 4 MB (plan §5.4; since decision 8 the milestone's budget, 23 MB from M8, in parts of at most 15 MB) | Met: 1.26 MB gzipped, 1.68 MB as shipped. Now (the 0.8.0-m8 release, its patch): 12.40 MB gzipped, 16.53 MB as shipped in two parts of 8,665,746 bytes, of 23 MB | - |
| No errors in the browser console | Met headless (0 through boot, New Game, walking, reload and Continue); headed: one "404 (File not found)" with no failed request of the page itself (most likely the browser's own favicon request) | NOT RUN |
| Walk the Cradle -> forest trail -> Grove and the village square with the browser's frame meter (Chrome DevTools > Rendering > Frame rendering stats): frame time and hitches, especially when an encounter first appears | NOT RUN (software WebGL here: about 2 frames a second) | NOT RUN |
| A gamepad inside the page (browsers expose a pad after its first button press) | NOT RUN | NOT RUN |
| Record the browser, the machine and the numbers in this file | Above | Owner |
| **M6: the web audio check's criterion** - no silent run over 50 ms in 60 s of the Hollow's music (`node tools/web/audio_check.mjs --strict`; P23) | **Not met here** (software WebGL: every run has 166-213 holes over 50 ms, the longest 241-618 ms, each placed on the main thread drawing a frame while the no-threads build's mixer waits; the default form passes those, under load it fails as well, and of the gate's last two runs on its final release one failed it on a single 78 ms hole placed 1.7 ms past the tolerance); the report now prints the criterion's verdict and a failed run keeps its trace (`tools/web/test_audio_check.mjs`); since W23 the default form also passes a hole the recording's end cut short with no driver read inside it (`holes_cut_at_disarm`, reported apart) | **NOT RUN** (a machine with a GPU: the owner, before M6 is declared passed) |
| **M7: the world's music across a region border** - no silent run over 50 ms in 60 s of the world's music across a region border, on the release build (`node tools/web/stream_check.mjs --world --audio --strict`; the M7 gate) | **Not met here** (software WebGL: the gate's route had 98.5 s of music across three borders and 301 holes over 50 ms, the longest 281.5 ms, every one placed on the main thread drawing a frame while the no-threads build's mixer waited; the default form passes those; "The world's music on the web (the M7 gate)"); the recorder's verdicts are tested on a stub launcher (`tools/web/test_stream_check.mjs`); since W23 the default form also passes a hole the recording's end cut short with no driver read inside it (`holes_cut_at_disarm`, reported apart) | **NOT RUN** (a machine with a GPU: the owner, before M7 is declared passed) |
| **M9: the world as a returning player meets it** - a world save Continued from the title, a fast travel, 60 s of walking across region borders; the frames, streaming hitches, music holes over 50 ms, peak live samples and console errors (`node tools/web/world_check.mjs --strict`; W23, lane P39f) | **Not met here** (software WebGL, the machine shared: the Continue and the travel load and the walk finishes - 787.7 m, 3 region changes, 211 m of margin, 0 thrash, 57.3 of 67.9 MB of samples, 0 console errors - but the page's frames run 1.7 s at p50 and the music has 608 holes over 50 ms, the longest 4,377 ms, every one placed on the main thread; the default form passes those, one of them cut short at the recording's end (`holes_cut_at_disarm`: an allowance W23 added to all three checks' default forms); under load the default form fails too - the verifier's run at a load average of 8-9 FAILED on 50 holes the placement missed; both loads end on the starting ring's 8 s warning; `docs/systems/P39f.md`, "Part web") | **NOT RUN** (the owner: `docs/USABILITY_SCRIPT.md` §11; that strict run is the one that counts) |
