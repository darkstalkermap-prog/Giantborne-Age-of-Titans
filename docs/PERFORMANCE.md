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
| Sim CPU per tick | p95 <= 8 ms in the stress route and the Valley | Container (indicative) and PC | Container: 4.88 ms (stress), 3.37 ms (Valley walk): **met**; after P17b 3.72 ms (stress), at most 6.37 ms in every run of the final balance matrix (three runs at once) and 5.77 ms over the 30-minute run: **met**; P18 on the final code 3.69 ms (stress) and 5.40 ms over the 30-minute run: **met**; P24b's unreachable chase (20 humans chasing a giant in deep water, the throttle and the query budget) 3.9 ms: **met** |
| Draw calls | <= 250 in any Valley view | PerfProbe, `--scenario=valley_walk`, rendered; `tools/draw_call_probe.tscn` (the static world) | P17b (container, software GL): the static world at most 93 per view at `low` and 221 at `medium` (was 402 / 584): **met**; with enemies in view the walk's p50 is 256 and its largest view 656 at `low` (was 608 / 1,354): **not met** while about five or more full-rig enemies are in view (about 33 draw calls each; see "Draw calls after P17b"). After P22, re-measured at the M6 gate: the walk's p50 201, p95 251, max 268; the largest view of five districts 253-268: **not met by 4-18 draw calls** (a measured miss: "Draw calls at the M6 gate"). After P27 (the HUD batched: about 10 draw calls a view instead of about 120): the walk's p50 93, p95 143, max 154, every view at least 96 under: **met** ("Draw calls after P27") |
| Distant actors | Tier 2 shows a one-box proxy | P04 test; the Valley walk's LOD comparison | Met: every distant member shows its proxy at tier 2 |
| Active combatants | <= 12 (the director's budget) | P10a tests; P17a bot invariant | 12 in the stress route (its own spawner) and in the Valley walk |
| Valley load | <= 3 s headless, <= 6 s web | P10b slow test; P18 browser | Headless about 0.3 s (P10b); web in a real browser **NOT RUN**. P18, Chromium with software WebGL on the container's shared CPU (indicative only): New Game to the first checkpoint stored in IndexedDB 14.2 s |
| Navmesh files | <= 100 KB each | P10b test | Met (15-19 KB); the streamed test world's (P24b) 0.9-16 KB each |
| Path queries (P24b) | <= 8 a tick per level (`nav_query.queries_per_tick`); chases capped at 120 m, the bot and the director at 300 m, unlimited polygons; tier-0 re-paths at least 6 ticks apart and only after the goal moved 2 m (plan §2.8) | `tests/slow/test_unreachable_chase.gd` | At most 8 re-paths in a tick (twenty asking at once served 8, 8, 4), never two of one agent closer than 6 ticks without a failure: **met** |
| Navigation readiness (P24b) | Deterministic runs: a chunk ready one tick after its last region add; world walks with AI identical run to run (decision 13) | `tests/integration/test_nav_maps.gd`; `tests/gate/test_world_determinism.gd` | One tick in every run; two traced world walks identical (with async iterations on they part by two ticks): **met** |
| Web `.pck` | <= 4 MB packed | P18 | **Met**: `index.pck` 2,356,808 bytes, 1,260,098 gzipped, 1,680,132 as shipped (gzip + base64) |
| Streaming work (P24a) | <= 4 ms a frame, every step under about 3 ms (plan §5.3) | `--scenario=world_walk` on the test world (`tests/slow/test_world_walk.gd`); the web stream check | Desktop at 16 m/s: p50 0.9, p99 3.5-3.9 ms (up to 6.5 while another agent's runs loaded the cores), max 4.4 ms; the heaviest steps 3.2 ms (the terrain mesh) and 3.5 ms (a town part): **met** (container, indicative). Web: p99 9.2 ms walking and 17.9 ms at 16 m/s (Chromium with software WebGL on loaded shared cores; every step's mean is under 3 ms, the peaks are the main thread preempted): **not met in this container**; real browsers **NOT RUN** |
| Loaded margin, thrash, chunks (P24a) | >= 200 m to unloaded ground at 16 m/s; 0 reloads walking a border; <= 25 loaded | the same | 254.9 m, 0 thrash, at most 15 loaded (16 m/s, 2.9 km); 20 border walks load each chunk once: **met** |
| Static world draw calls, streamed (P24a) | <= 40 per view at web `low`, and <= 25 more for breakable houses in a settlement view (plan §5.3) | Xvfb viewpoints on the test world | At most 35 static plus the 8 breakable houses at `low` (`medium`: at most 127 with shadows): **met** on the test world; P25 and the region packages re-measure the real one |
| Web frames while streaming, with gameplay (P24a) | worst <= 45 ms, p99 <= 25 ms (indicative) | `tools/web/stream_check.mjs` on the `Web (test)` build | Chromium with software WebGL on the loaded container: page frames p50 433 / p99 1,733 / worst 4,350 ms walking at 1280 x 720 (250 / 1,683 / 3,633 ms at 640 x 360, 16 m/s): **not met (software rendering)**; the walks finished with 251.6 m and 246.9 m of margin, 0 thrash and 0 console errors while running. Real browsers **NOT RUN** |
| World data (P24a, P24b) | <= 5.0 MB: chunks, navmeshes, index, map, skyline, chunk scenes (decision 8) | the test world's files, extrapolated to 64 chunks | Without navmeshes (P24a): the test world 308,965 bytes; extrapolated to 64 chunks about 1.1 MB (chunks 0.91 MB with the border chunks at their share). The navmeshes (P24b: three lean layers and the gate regions, 29.2 KB a chunk): 467,751 bytes for the test world, about 1.55 MB for 64 chunks (the border chunks' rim halves have none). Together about 2.65 MB, about 3.0 MB with P25's map image: **on track** |
| World data (P25: the real world) | <= 5.0 MB (decision 8) | `tests/integration/test_world_data.gd` (the files) | **2,390,369 bytes: met** (chunk data 0.83 MB, navmeshes 0.93 MB, structures 0.14 MB, props scenes 0.19 MB, skyline 0.15 MB, index 68 KB, map 52 KB); the release pck's world share 2.37 MB (24.6 %) |
| Map picture (P25) | <= 300 KB, 1,024 x 1,024 (plan §3.8) | `tests/integration/test_world_data.gd` | 52,433 bytes: **met** |
| Static world draw calls, the real world (P25) | <= 40 per view at `low` at the Kingsgate shelf and the six settlements (plan §3.8) | `tests/slow/test_world_build.gd` (Xvfb, `tests/support/world_draw_probe.gd`) | At most 33 (Skarn; the shelf 30, Hollowmere 31, Brannock 28, Millford 27, Fort Aldmere 23, Harrok's Hall 19), with the giant in view 8 more: **met**; the breakable houses' share comes with P29 |

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
the 35-degree plateau, the pond), or `--route=x:z;x:z;...` - sprinting with the stick, or carried at
`--walk-speed=M` m/s (16: the stage-6 sprint, the streaming budget's case). It sets off once the
starting ring is loaded and records, per tick, the margin to unloaded ground (the distance to the
nearest chunk of the grid that is not loaded), the most chunks loaded, seam crossings, region
changes and (walking) ticks with the feet under the ground; the streamer's statistics (loads,
unloads, thrash, work per frame p50 / p99 / max, steps by kind) are reset when it sets off. The
PerfProbe's sections are the chunks. `AUTOPILOT_RESULT`'s `world_walk` key is the report, with its
check failures (margin under 200 m, thrash, more than 25 chunks, ticks under the terrain, the route
not finished). Headless and `--fixed-fps` runs stream deterministically (a fixed step quota).

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
its arguments) and `--audio` records the game's music during the walk with `audio_check.mjs`'s
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
engine's own frames sat at their 133 ms cap.

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

## Web build checklist (P18: Chromium with software WebGL; real browsers NOT RUN)

The play link is the single-threaded web export (`tools/build_web.sh`, `web_nothreads_release`).
P18 served `builds/web/` locally and drove `play.html` with Playwright's Chromium 153 using
SwiftShader (software WebGL) on the container's shared CPU: headless for the boot, New Game, the
save and Continue, headed under Xvfb for the mouse capture. Frame times and load times there say
nothing about a real GPU; they are listed only to show the build works.

| Check | P18 in the container | Real browser |
| --- | --- | --- |
| The page fits without a sideways scroll | Met at 1280 px (scroll width = client width) | NOT RUN |
| Play downloads, unpacks and starts the engine | Met: the engine started 5.7 s after Play (4.6 s after a reload); about 14 MB to download | NOT RUN |
| The title screen, then New Game into the Valley | Met: the title shows build 0.5.0-m5; New Game reaches the Hollow, its first checkpoint stored after 14.2 s | NOT RUN |
| The Valley loads in at most 6 s behind the "Loading..." frame (plan §5.4) | Not judged (software rendering; 14.2 s includes the storage sync) | NOT RUN |
| The save survives a page reload (IndexedDB) | Met: `/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json` is in IndexedDB before and after the reload; the title then offers Continue ("Saved game: level 1, stage 1 ...") and Continue loads the Valley at the Hollow Shrine | NOT RUN |
| The title's button that starts a mode takes the mouse (pointer lock inside the click) | Met (headed): no lock on the title or after a click on Settings; locked after the New Game click and in the Valley; Esc releases it | NOT RUN |
| The build runs the `low` preset whatever the saved setting says | Met: the Valley renders without sun shadows (the `low` preset); `test_graphics_quality` covers the web forcing `low` over a `medium` setting (the Settings row's lock is tested under `--graphics`) | NOT RUN |
| AI tier 1 starts at 30 m (`level.valley` `web_overrides.ai_tier1_m`) | Covered by `test_graphics_quality` (forced web) | NOT RUN |
| The packed `.pck` is at most 4 MB (plan §5.4) | Met: 1.26 MB gzipped, 1.68 MB as shipped | - |
| No errors in the browser console | Met headless (0 through boot, New Game, walking, reload and Continue); headed: one "404 (File not found)" with no failed request of the page itself (most likely the browser's own favicon request) | NOT RUN |
| Walk the Cradle -> forest trail -> Grove and the village square with the browser's frame meter (Chrome DevTools > Rendering > Frame rendering stats): frame time and hitches, especially when an encounter first appears | NOT RUN (software WebGL here: about 2 frames a second) | NOT RUN |
| A gamepad inside the page (browsers expose a pad after its first button press) | NOT RUN | NOT RUN |
| Record the browser, the machine and the numbers in this file | Above | Owner |
| **M6: the web audio check's criterion** - no silent run over 50 ms in 60 s of the Hollow's music (`node tools/web/audio_check.mjs --strict`; P23) | **Not met here** (software WebGL: every run has 166-213 holes over 50 ms, the longest 241-618 ms, each placed on the main thread drawing a frame while the no-threads build's mixer waits; the default form passes those, under load it fails as well, and of the gate's last two runs on its final release one failed it on a single 78 ms hole placed 1.7 ms past the tolerance); the report now prints the criterion's verdict and a failed run keeps its trace (`tools/web/test_audio_check.mjs`) | **NOT RUN** (a machine with a GPU: the owner, before M6 is declared passed) |
| **M7: the world's music across a region border** - no silent run over 50 ms in 60 s of the world's music across a region border, on the release build (`node tools/web/stream_check.mjs --world --audio --strict`; the M7 gate) | **Not met here** (software WebGL: the gate's route had 98.5 s of music across three borders and 301 holes over 50 ms, the longest 281.5 ms, every one placed on the main thread drawing a frame while the no-threads build's mixer waited; the default form passes those; "The world's music on the web (the M7 gate)"); the recorder's verdicts are tested on a stub launcher (`tools/web/test_stream_check.mjs`) | **NOT RUN** (a machine with a GPU: the owner, before M7 is declared passed) |
