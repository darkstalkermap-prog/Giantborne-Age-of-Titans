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
| Sim CPU per tick | p95 <= 8 ms in the stress route and the Valley | Container (indicative) and PC | Container: 4.88 ms (stress), 3.37 ms (Valley walk): **met**; after P17b 3.72 ms (stress), at most 6.37 ms in every run of the final balance matrix (three runs at once) and 5.77 ms over the 30-minute run: **met** |
| Draw calls | <= 250 in any Valley view | PerfProbe, `--scenario=valley_walk`, rendered; `tools/draw_call_probe.tscn` (the static world) | P17b (container, software GL): the static world at most 93 per view at `low` and 221 at `medium` (was 402 / 584): **met**; with enemies in view the walk's p50 is 256 and its largest view 656 at `low` (was 608 / 1,354): **not met** while about five or more full-rig enemies are in view (about 33 draw calls each; see "Draw calls after P17b") |
| Distant actors | Tier 2 shows a one-box proxy | P04 test; the Valley walk's LOD comparison | Met: every distant member shows its proxy at tier 2 |
| Active combatants | <= 12 (the director's budget) | P10a tests; P17a bot invariant | 12 in the stress route (its own spawner) and in the Valley walk |
| Valley load | <= 3 s headless, <= 6 s web | P10b slow test; P18 browser | Headless about 0.3 s (P10b); web **NOT RUN** (P18) |
| Navmesh files | <= 100 KB each | P10b test | Met (15-19 KB) |
| Web `.pck` | <= 4 MB packed | P18 | **NOT RUN** (P18) |

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
exported builds (only `tests/` and `tools/` are excluded), so the stress arena loads there.

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
2. **Draw calls (P17b: the static world is within budget; the actors are not).** See "Draw calls
   after P17b": the props are merged and faded with the scenery and `low` has no sun shadows, so a
   static view costs at most 93 draw calls at `low` and 221 at `medium`; the walk is at p50 256,
   max 656 at `low`. Views with about five or more full-rig enemies exceed 250 (about 33 each).
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

## Web build checklist (P18; NOT RUN here)

The play link is the single-threaded web export (`tools/build_web.sh`, `web_nothreads_release`).

- [ ] The build runs the `low` preset whatever the saved setting says: the Settings page shows
      "Graphics preset: Low", disabled, with "The web build always uses the Low preset."
- [ ] AI tier 1 starts at 30 m (`level.valley` `web_overrides.ai_tier1_m`).
- [ ] The Valley loads in at most 6 s behind the "Loading..." frame (plan §5.4).
- [ ] Walk the Cradle -> forest trail -> Grove and the village square with the browser's frame meter
      (Chrome DevTools > Rendering > Frame rendering stats): note the frame time and any hitches,
      especially when an encounter first appears (see the spawn hitch below).
- [ ] The packed `.pck` is at most 4 MB (plan §5.4).
- [ ] No errors in the browser console during 5 minutes of play.
- [ ] Record the browser, the machine and the numbers in this file.
