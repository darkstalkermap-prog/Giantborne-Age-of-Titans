# Brief: open-world technology (M7-M9 planning input)

The owner's direction: "add sound and music and continue to build the game", then "I like the
beginning as a tutorial but it needs to open up to an open world to explore". The Valley of Broken
Kings stays as the opening tutorial (prologue); after it the game opens into an open world. This
overrides the spec's deferral of open-world streaming (spec §11 "Full-game open-world streaming is
a later technical milestone"; plan §0.4).

This brief answers, with experiments, how to build that world so it runs on Windows desktop and in
the single-threaded web export (the play link): streaming, terrain, navigation across chunks,
persistence and AI across streaming, the open-world UX the game lacks, and a world size with its
budgets. It ends with a recommended architecture (§9) and the experiments' numbers (§10).

**How facts are marked.** Every fact carries one of two marks:

- **VERIFIED** - measured in an experiment of this brief, or read in the repository's code, data or
  docs (the evidence is named).
- **ASSUMED** - an estimate, extrapolation or design judgement that was not measured.

Recommendations are labelled as such; the facts inside them carry their own marks.

**Where the numbers come from.** A development container: Linux, 4 shared CPU cores, no GPU, 16 GB.
Desktop numbers come from a **release export** (Linux, `linux_release.x86_64` template of Godot
4.6.3-stable `7d41c59c4`) run headless (CPU) or under Xvfb with Mesa llvmpipe (draw calls). Web
numbers come from the **single-threaded web release export** (`web_nothreads_release`, the play
link's variant), served by `python3 -m http.server` and run in headless Chromium 153 (Playwright
1.63) with SwiftShader WebGL; the page reports 2 cores and `threads: false`. For CPU tests the web
runs disable 3D rendering (`Viewport.disable_3d`) so SwiftShader does not drown the timings. All of
this is VERIFIED; web numbers are indicative of a slow browser, not of a real PC (a real browser on
a real CPU is ASSUMED to be faster). Exports were built without `XDG_DATA_HOME`, as the task asks.

---

## 0. The answer in brief

1. **Stream 256 m chunks in a 3 x 3 ring** (unload at Chebyshev distance 2), each chunk split into
   small resources that are loaded and instanced over several frames within a 4 ms budget. While
   moving at 16 m/s (a stage-6 sprint) the player never came within 252 m of unloaded ground, on
   desktop or web (VERIFIED, §3.5). Do **not** count on `ResourceLoader.load_threaded_request` on
   the web: on the no-threads build the whole load happens inside the request call (VERIFIED, §3.2).
2. **Terrain without plugins works**: a 16-bit heightfield per chunk, a runtime-built `ArrayMesh`
   (4 m spacing) and one `HeightMapShape3D` per chunk. The real giant at stages 1-6 (3.7-18.9 m)
   walks it across chunk seams at 98.6-99.6 % of its walk speed, near the origin and 4 km out
   (VERIFIED, §4.4). One trap: a slope of 40° or more that crosses a chunk border stops the giant at the
   border (VERIFIED); keep border slopes at 35° or less.
3. **Navigation across chunks works**, with three fixes found by the experiments (all VERIFIED,
   §5): grow the bake AABB by `border_size` (Godot 4.6.3 cuts the border from inside it), align the
   voxel grid's y origin on a world-wide multiple of the cell height, and put **each nav layer on
   its own `NavigationServer3D` map** (one map holding four overlapping layers made thousands of
   cross-layer edge connections and was still not ready after 9.3 s). With those, tiles merge exactly,
   edge connections can be switched off, random paths across chunk borders succeed 40 of 40 on all
   four layers, and a real wolf and ogre chase the giant across a border. Bound every query with
   `path_search_max_polygons = 0` plus `path_search_max_distance` (no P10b error, about 1-3 ms).
4. **On the web, navigation is the main streaming cost**: every region add or remove rebuilds its
   layer's map synchronously. Lean bakes (half the polygons) plus at most one region per frame bring
   the worst streaming frame from 60 ms to 20 ms in headless Chromium (VERIFIED, §3.5).
5. **Persistence needs no new idea**: world deltas are keyed by stable ids, not chunks (VERIFIED,
   §6). What must change: respawn points, objective markers and encounter lookups must not depend
   on nodes being loaded (a world index), and the director must despawn members before their chunk
   unloads. **No floating origin** is needed for a world of a few kilometres (physics identical to the
   millimetre at 0, 2, 4, 8 and 16 km, desktop and web, VERIFIED).
6. **A 2 x 2 km world** (64 chunks) crosses in 3.3-5.1 min edge to edge and 4.6-7.3 min corner to
   corner at stages 3-6 (VERIFIED arithmetic on data speeds; stage 4-6 speeds ASSUMED). Its static
   world draws at most 24 draw calls per view with 16 chunks loaded (VERIFIED), well inside the
   250 budget that actors already strain.

---

## 1. The current level framework (what the open world builds on)

### 1.1 Levels, sessions and saves

- `LevelRoot` is the root of one level scene. It builds its lookups (markers, checkpoints, area
  triggers) from groups at `_ready` and **rebuilds them when an id misses**, so nodes added later
  are found - VERIFIED (`scripts/world/level_root.gd` `_lookup`, `rebuild_lookups`).
- `LevelRoot.nav_region(layer)` returns the single region `Navigation/<Human|Large|Giant|SmallGiant>`
  and `nav_map()` the world's default map - VERIFIED (`level_root.gd`). `EnemyActor` paths with its
  `NavigationAgent3D` on the default map and calls `map_get_path` on `get_world_3d().navigation_map`
  for flee and reachability checks, snapping flee points to the one region `LevelRoot.nav_region()`
  returns - VERIFIED (`scripts/actors/enemy_actor.gd`, lines about 825-880).
- `GameSession` knows three modes (title, sandbox, Valley). Every mode change, reset and checkpoint
  reload is a reload of `scenes/main.tscn`, which builds the level - VERIFIED
  (`scripts/core/game_session.gd`, `scripts/main.gd`). Checkpoints and save writes are gated by
  `is_valley()` - VERIFIED (`checkpoints_enabled`, `_writes_enabled`).
- The save document already names its level (`"level": "level.valley"`) and resolves it through
  the level record (`scene_for_level`, `save_level_available`), so a second level is a small step -
  VERIFIED (`game_session.gd`, `docs/systems/P06.md`).
- A respawn point is a node: `find_checkpoint(id)` looks up the `CheckpointMarker` (shrine spawn
  point, waystone) in the loaded tree - VERIFIED (`game_session.gd`). A `Waystone` is a checkpoint
  marker reached by standing within its radius, once per load - VERIFIED (`scripts/world/waystone.gd`).

### 1.2 Encounters and AI

- `EncounterDirector` reads **every** `encounter` record of its level at level load, preloads their
  scenes into a static cache, and walks all encounters in id order every 30 ticks - VERIFIED
  (`scripts/world/encounter_director.gd` `reload_encounters`, `_update`).
- Activation and deactivation use horizontal distance to the encounter centre; an active encounter
  deactivates only when the player is beyond its deactivate radius **and no member has been aware
  for 10 s**; deactivated members are freed (not killed) and return home at full health - VERIFIED
  (code, `docs/systems/P10a.md`).
- Valley data: 15 encounters, 58 members; activate radius at most 100 m, deactivate at most 160 m,
  leash at most 55 m; three encounters have no leash (the boss, the village folk, the sparring post)
  - VERIFIED (`data/world/encounter_*.json`).
- Budget 12 active combatants; AI LOD tier 0 within 40 m (30 m on the web), tier 1 within 90 m,
  tier 2 (a one-box proxy) beyond - VERIFIED (`data/world/level_valley.json`, code).

### 1.3 Persistence

- `WorldState` stores deltas keyed by stable world or entity ids (`destroyed`, `damage_stage`,
  `health`, `loot_awarded`, `killed`, `opened`), flags and inventory - VERIFIED
  (`scripts/core/world_state.gd`).
- A `BreakableProp` restores itself from its delta in `_ready`, so a freed and re-instanced prop
  comes back in its saved state: `test_save_load_world` (74 checks, including
  `test_partial_fence_damage_is_persisted`, which frees a fence and re-instances it with the same
  `world_id`) passes - VERIFIED (run in the lab copy for this brief).

### 1.4 Quests and markers

- An objective's position is its marker's, else the first of its targets found **in the loaded
  tree** (a living entity, an area trigger, a breakable prop); positions are cached per level and a
  miss is retried once a second - VERIFIED (`scripts/quests/quests.gd` `objective_position`,
  `_cached_position`).
- The HUD's objective marker shows **one** objective (`Quests.current_objective()`: the main quest
  first) with its distance; the tracker shows the main quest and one side quest - VERIFIED
  (`ui/hud/objective_marker.gd`, `docs/systems/P13.md`). There is no map, compass, point-of-interest
  discovery or fast travel; the plan deferred them - VERIFIED (`docs/plans/M2_M5_PLAN.md` §0.4).

### 1.5 Navigation, rendering and performance today

- The Valley (400 x 400 m) has four offline-baked navmeshes, one per layer: 1,659-1,991 polygons and
  15-19 KB each, regions at four heights, edge connections off - VERIFIED (`docs/systems/P10b.md`).
- Godot 4.6.3's path search has a 4,096-polygon default (`path_search_max_polygons`) and P10b hit an
  engine error ("It's not expect to not find the most reachable polygons") when a search exhausted
  it - VERIFIED (P10b; the default re-checked in an empty project for this brief).
- Static Valley views draw at most 93 draw calls at `low`; each full-rig enemy adds about 33; CPU per
  tick p95 5.40 ms over the 30-minute run - VERIFIED (`docs/PERFORMANCE.md`, `docs/M2_M5_HANDOFF.md`).
- Growth profiles exist for stages 1-3 only (3.66 / 5.49 / 7.92 m, walk 5.0 / 5.8 / 6.5 m/s) and
  sprint multiplies speed by **1.5**, not 2 - VERIFIED (`data/growth/*.json`,
  `data/actions/sprint.json`). The spec's table gives stages 4-6 as 10.97 / 14.63 / 18.90 m -
  VERIFIED (`docs/GIANTBORN_SPEC_V2.md` §9).

---

## 2. The lab (scratch only, not committed)

Everything below was built in the session's scratchpad folder, `<scratchpad>/ow_lab/` (a copy of
the game in `game/`, a minimal bench project in `bench/`, exports in `exports/`, logs in `logs/`);
no tracked file of the repository was changed - VERIFIED (`git status` clean).

- **World function** (`lab/ow_world.gd`): `FastNoiseLite` simplex FBM, 5 octaves, frequency 1/800,
  amplitude 40 m. Over the 1 km² sampled, 99.1 % of the ground is under 15° and 0.9 % between 15°
  and 25°; heights -26 to +25 m - VERIFIED (builder statistics). This is gentle, rolling ground;
  steep cases were tested separately (§4.4).
- **Chunk content** per 256 m chunk: 151 trees (trunk and crown MultiMeshes), 39 rocks, a hamlet
  of 8 houses (one merged mesh), 198 collision solids - VERIFIED. Shared meshes and materials are
  external resources loaded once.
- **Chunk sets** (builder `lab/ow_build.gd`, offline, like `tools/builders/valley.gd`): 128 m
  (8 x 8), 256 m (4 x 4) and 512 m (2 x 2) chunks at 2 m height spacing, 256 m at 4 m spacing, and a
  256 m set with a lean navmesh bake. Each chunk exists twice: a monolithic `.scn` (mesh and shapes
  embedded) and compact data (`OwChunkData` resource: heights, MultiMesh buffers, a solid list) - both
  with four external navmesh `.res` files - VERIFIED.
- **Nav layers** as the Valley's (radius / height / climb): human 0.75 / 2.0 / 0.25 (cell 0.25),
  large 1.5 / 4.0 / 0.5 (0.5), giant 2.0 / 8.5 / 0.75 (0.5), small giant 1.0 / 3.75 / 0.5 (0.25).
  The human and small-giant radii were raised from 0.6 / 0.9 m to whole 0.25 m cells; cells of 0.25
  and 0.5 m divide every chunk size - VERIFIED (Godot warns and ceils non-whole radii).
- **Bench** (`lab/ow_bench.gd`, the same code on desktop and web): streaming, terrain generation,
  baking, navigation, save documents, precision far from the origin, draw calls and a streaming walk;
  it prints one JSON line per result.
- **Game-level tests** in the lab copy (`tests/slow/test_ow_terrain.gd`, `test_ow_ai.gd`): the real
  `GiantPlayer` and real `EnemyActor`s on lab terrain; lab growth profiles for stages 4-6 scaled from
  stage 3 (heights 10.97 / 14.63 / 18.90 m, capsule radii 2.29 / 3.05 / 3.94 m, walk 7.0 / 7.5 /
  8.0 m/s, step 1.25 / 1.66 / 2.15 m, camera arms 16.6 / 22.2 / 28.6 m). Data validation passes with
  them (0 errors) and an assisted Valley bot run completed the slice in that copy (0 errors) -
  VERIFIED. The stage 4-6 numbers themselves are ASSUMED (no design exists yet).

---

## 3. World streaming

### 3.1 One chunk loaded in one go (monolithic `.scn`)

Mean of 2-4 chunks per row; "busy" is the physics and navigation work of the next frames (from
`physics_frame` to `process_frame`, which includes the navigation map sync). All VERIFIED.

| Chunk | Desktop load / instantiate / add (ms) | Desktop worst frame (load+inst+add) | Desktop busy after | Web load / inst / add (ms) | Web worst frame | Web busy after |
| --- | --- | --- | --- | --- | --- | --- |
| 128 m, 2 m spacing | 3.4 / 0.3 / 0.4 | 4.5 | 0.9 | 7.7 / 1.0 / 0.7 | 13.8 | 15.8 |
| 256 m, 4 m spacing | 8.7 / 0.7 / 0.6 | 11.3 | 3.5 | 13.4 / 1.1 / 0.9 | 17.0 | 17.0 |
| 256 m, 2 m spacing | 9.7 / 0.8 / 1.2 | 17.3 | 4.3 | 14.5 / 2.8 / 1.8 | 20.0 | 10.3 |
| 512 m, 2 m spacing | 31.8 / 2.4 / 4.5 | 44.4 | 7.4 | 49.5 / 5.0 / 8.8 | 69.4 | 53.2 |

- A 512 m chunk costs a 70 ms load frame plus a 53 ms navigation frame on the web: too big - VERIFIED.
- On the desktop the navigation map rebuild runs on a worker thread (async iterations, the 4.6.3
  default); on the web it runs in the frame - VERIFIED (busy columns; `navigation/world/
  map_use_async_iterations` is true by default, read from project settings).
- The first chunk ever loaded also pays first-use costs (31 ms load, 17.5 ms instance on the web) -
  VERIFIED (warm-up row); load something under the loading screen first.

### 3.2 `load_threaded_request` versus plain `load`

| Platform | 256 m chunk: time inside `load_threaded_request` | Frames until LOADED | Then instantiate + add | 512 m chunk: inside the request |
| --- | --- | --- | --- | --- |
| Desktop (threads) | 0.05-0.12 ms | 1-2 frames (8-14 ms of wall time) | 2.6-4.9 ms | 0.05 ms (5-7 frames) |
| Web (no threads) | **15.3-15.8 ms** | **0** (LOADED at once) | 3.0-3.8 ms | **40-62 ms** |

- On the no-threads web build the whole load happens **inside** the request call; the status is
  `THREAD_LOAD_LOADED` on the first poll. Threaded loading hides nothing there - VERIFIED.
- On the desktop the load leaves the main thread; only instantiate and add remain - VERIFIED.
- Consequence: one code path for both platforms is "request, poll each frame, instance in slices";
  on the desktop it overlaps loading with play, on the web it degenerates to small synchronous loads,
  which is fine only if every resource is small - ASSUMED (design), backed by §3.3.

### 3.3 Time-sliced loading from compact data (the "split" loader)

The loader does one step at a time until a per-frame budget is spent: load the data resource, fill
terrain rows (about 2,000 vertices a slice), create the mesh, create the `HeightMapShape3D` body and
add the chunk, three MultiMeshes, collision solids in batches, then one navmesh region at a time.
A step that starts always finishes. All VERIFIED.

| Chunk | Budget | Desktop: frames / worst frame work / total | Web: frames / worst frame work / total | Web worst busy (nav sync) |
| --- | --- | --- | --- | --- |
| 128 m, 2 m | 4 ms | 2.0 / 4.5 / 6.7 ms | 3.3 / 7.5 / 15.1 ms | 4.5 ms |
| 256 m, 4 m | 4 ms | 4.0 / 8.1 / 18.9 ms | 6.3 / 10.0 / 33.4 ms | 8.7 ms |
| 256 m, 2 m | 4 ms | 6.3 / 7.4 / 27.7 ms | 7.7 / 12.6 / 41.7 ms | 12.4 ms |
| 256 m, 2 m | 2 ms | 9.7 / 6.3 / 27.8 ms | 12.3 / 7.9 / 46.7 ms | 11.6 ms |

- The frames over budget are single atomic steps: 64 collision shapes in one batch (up to 15 ms on
  the web), the ground body plus the first `add_child` (up to 6.4 ms), loading one navmesh `.res`
  (up to 7.4 ms) - VERIFIED (per-step maxima). Batches of 16 shapes fix the first (§3.5).
- Total work per 256 m chunk: 17-28 ms desktop, 27-51 ms web (over the 2, 4 and 8 ms budgets); the
  web costs 1.3-2.2 times the desktop for the same work (load 1.5x, mesh fill 2.2x, navmesh bake
  1.5x, JSON 1.3-1.4x) - VERIFIED.

### 3.4 Generating terrain at runtime

| Step (one 256 m chunk) | 2 m spacing (16,641 vertices, 32,768 triangles) desktop / web | 4 m spacing (4,225 / 8,192) desktop / web |
| --- | --- | --- |
| Fill vertex, normal, colour and index arrays (GDScript) | 6.0 / 13.2 ms | 1.5 / 2.3 ms |
| `add_surface_from_arrays` | 0.7 / 1.2 ms | 0.17 / 0.4 ms |
| `HeightMapShape3D` from the heights | 1.1 / 1.7 ms | 0.3 / 0.4 ms |
| Static body with the shape into the space | 0.9 / 1.0 ms | 0.3 / 0.3 ms |
| Sampling the noise function for the heights | 6.1 / 13.5 ms | 1.8 / 2.5 ms |

All VERIFIED. Store heights; do not evaluate noise at runtime (ASSUMED recommendation).

### 3.5 Walking across the world while streaming

A point moves 16 m/s (one tick per frame) diagonally across 1,075 m of the lab world; chunks within
the ring load nearest first with the split loader (4 ms budget), chunks beyond ring + 1 are freed;
the starting ring is loaded behind a "loading screen". "Margin" is the closest the point came to
ground that was not loaded. All VERIFIED.

| Setup | Platform | Loads | Streaming work p99 / max | Work + physics/nav busy p99 / max | Frame p99 / max | Margin |
| --- | --- | --- | --- | --- | --- | --- |
| 256 m, ring 1 (3 x 3), dense nav | desktop | 11 | 4.4 / 7.7 ms | 4.6 / 12.6 ms | 7.6 / 19.5 ms | 254 m |
| 256 m, ring 1, dense nav | web | 11 | 4.9 / 10.1 ms | 6.6 / **59.9 ms** | 19.8 / 71.6 ms | 253 m |
| 256 m, ring 1, lean nav | web | 11 | 5.1 / 14.1 ms | 6.0 / 32.7 ms | 20.1 / 41.6 ms | 253 m |
| 256 m, ring 1, lean nav, 1 region per frame, 16-shape batches | web | 11 | 4.7 / 10.5 ms | 5.9 / **19.6 ms** | 19.6 / 36.3 ms | 253 m |
| same | desktop | 11 | 4.2 / 8.4 ms | 4.3 / 9.6 ms | 9.9 / 14.0 ms | 253 m |
| 128 m, ring 2 (5 x 5), dense nav | desktop | 40 | 4.1 / 5.2 ms | 4.2 / 17.5 ms | 8.0 / 29.5 ms | 256 m |
| 128 m, ring 2, dense nav | web | 40 | 4.3 / 8.4 ms | 11.5 / 34.3 ms | 24.8 / 63.5 ms | 255 m |

- Loading always stayed ahead: a chunk takes 0.05-0.2 s of frames; the next ring is needed 16 s
  later at 16 m/s - VERIFIED.
- The web's worst frames are navigation map rebuilds, not loading; lean bakes and one region per
  frame cut the worst from 60 to 20 ms - VERIFIED. (The web frame p50 is the 16.7 ms page cadence.)
- 128 m chunks in a 5 x 5 ring load 3.6 times as often per kilometre and rebuild the navigation maps
  as often; they did not beat 256 m chunks on the web - VERIFIED (rows above).

---

## 4. Terrain without plugins

### 4.1 Representation

- Per chunk: heights on a regular grid with a one-sample apron (for seamless normals), the mesh
  built from them in chunk-local coordinates, and one `HeightMapShape3D` (heights divided by the
  spacing, the `CollisionShape3D` uniformly scaled by the spacing and centred) - VERIFIED (builder;
  every walking test stands on these shapes).
- The physics surface matches the generated surface: the real giant's feet sank at most 0.7 cm
  (2 m spacing) and 3.2 cm (4 m) below the terrain function - VERIFIED. A bare capsule on 4 m facets
  stood on average 0.003-0.017 m and at most 0.47 m off the smooth function (facets plus the capsule's
  rounding on slopes) - VERIFIED.
- Seams: neighbouring chunks share their border samples, so border vertices have identical heights
  and the apron gives identical normals - VERIFIED by construction (same samples). No crack was
  looked for by eye - ASSUMED (no screenshot inspection).

### 4.2 Sizes per chunk (compressed `.res` / `.scn`, all VERIFIED)

| Chunk | Monolithic `.scn` (mesh embedded) | Compact data (float32 + 16-bit heights, buffers, solids) | 16-bit heights alone (raw) | Navmeshes, 4 layers |
| --- | --- | --- | --- | --- |
| 128 m, 2 m | 111 KB | 26 KB | 8.8 KB | 32 KB |
| 256 m, 4 m | 128 KB | 36 KB | 8.8 KB | 118 KB |
| 256 m, 2 m | 435 KB | 98 KB | 33.5 KB | 116 KB (lean bake: 62 KB) |
| 512 m, 2 m | 1,563 KB | 389 KB | 131 KB | 459 KB |

The compact data could drop its float32 heights (half of it) - ASSUMED (not built).

### 4.3 Rendering cost

16 chunks of 256 m loaded (1 km²), camera at the centre at eye heights 3.4 / 7.3 / 17.4 / 40 m,
eight directions each, fog from 150 to 320 m, no sun shadows (the web's `low`), Xvfb llvmpipe - all
VERIFIED:

| Spacing, scenery visible to | Draw calls max (mean) | Triangles max |
| --- | --- | --- |
| 2 m, 160 m | 12 (9-10) | 328,000 |
| 2 m, 300 m | 24 (20-21) | 372,000 |
| 2 m, 300 m, far terrain chunks hidden beyond 500 m | 22 | 306,000 |
| 4 m, 160 m | 12 | 82,000 |
| 4 m, 300 m | 24 | 126,000 |
| 4 m, 300 m, far terrain hidden | 22 | 110,000 |

- A chunk in view costs about two draw calls (terrain, trunks, crowns, rocks, houses as one mesh
  with two surfaces, culled per instance) - VERIFIED. 4 m spacing quarters the triangles - VERIFIED.
- Video memory reported for the 16 chunks: 22.7 MB (2 m) and 15.9 MB (4 m) - VERIFIED (llvmpipe's
  accounting).

### 4.4 Giants 3.7-19 m walking on it (the real `GiantPlayer`)

The real giant (its motor, camera rig and growth) walked a 400 m loop through four chunks that
crosses the x and z seams twice each; also the same loop 4 km from the origin, hillier ground
(heights x 2.2; its steepest slopes are ASSUMED to reach about 45°, from the base terrain's 25°),
4 m spacing, and ramps. The table is VERIFIED.

| Run | Stages | Completed | Mean speed / walk speed | Off-floor ticks | Feet below terrain (max) | Camera under terrain | Stuck (2 s) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Rolling, 2 m, near and at 4 km | 1-6 (12 runs) | 12 / 12 | 98.6-99.6 % | 0 | 0.6-0.7 cm | 0 ticks | 0 |
| Hilly (x 2.2) | 1, 3, 6 | 3 / 3 | 97.9-98.8 % | 0 | 1.3 cm | 0 | 0 |
| Rolling, 4 m spacing | 1, 3, 6 | 3 / 3 | 98.6-99.6 % | 0 | 3.2 cm | 0 | 0 |
| Ramp 20° across a seam | 1, 3, 6 | 3 / 3 | 95-96 % | 0 | 0 | 0 | 0 |
| Ramp 35° across a seam | 1, 3, 6 | 3 / 3 | 87-88 % | 0 | 0 | 0 | 0 |
| Ramp 40° inside one chunk | 1, 6 | 2 / 2 | 81-82 % | 0 | 0 | 0 | 0 |
| Ramp 40° **across a seam** | 1, 3, 6 | **stage 1 stopped at the seam**; stages 3 (one-body run) and 6 passed | - | 0 | 0 | 0 | 11 |
| Ramp 44° inside one chunk | 1, 6 | 2 / 2 | 77 % | 0 | 0 | 0 | 0 |
| Ramp 44° **across a seam** | 1, 3, 6 | **all stopped at the seam** (x 253-255 of 256) | - | 0 | 0 | 0 | 10-14 |
| Ramp 44°, seam at its foot | 1, 6 | 2 / 2 | 79-80 % | 0 | 0 | 0 | 0 |
| Ramp 50° | 1, 3, 6 | stopped at its foot (over the 46° floor limit) | - | - | - | 0 | 14-16 |

- **Seam trap**: a slope of 40° or more crossing a border between two `HeightMapShape3D`s stops the
  giant at the border; putting every chunk's shape in one static body (a compound) behaves the same -
  VERIFIED. At 35° and below, and where the border meets the slope at its foot, there is no effect -
  VERIFIED. Overlapping neighbouring shapes by a cell was not tried - ASSUMED untested.
- Big giants "float" a little on slopes (the rounded capsule bottom): up to 0.23 m at stage 6 on hilly
  ground, 1.5 m on a 44° ramp - VERIFIED; it is geometry, not error.
- The stage-6 camera arm (28.6 m) never ended under the terrain on these routes - VERIFIED.
- A bare 18.9 m capsule without the giant's step logic stalled against the chunk's trees and rocks
  after 22 m in every precision run (§6.4) - VERIFIED; whether the real stage-5/6 giant passes a forest
  of 151 trees per chunk was **not tested** - ASSUMED risk (§8.4).

---

## 5. Navigation across chunks

### 5.1 Polygons per chunk

Godot's navmesh polygons are Recast's detail-mesh triangles, so rolling terrain multiplies them
(the whole flat Valley has 1,659-1,991 per layer). Per chunk, mean of the set, all VERIFIED:

| Chunk / bake | Human | Large | Giant | Small giant | Bake time, human / giant (desktop) |
| --- | --- | --- | --- | --- | --- |
| 128 m, default detail | 887 | 687 | 677 | 882 | 82 / 20 ms |
| 256 m, default (edge error 1.0, detail 6 / 1) | 3,445 | 2,680 | 2,651 | 3,428 | 382 / 91 ms |
| 256 m, **lean** (edge error 2.0, detail distance 24, detail error 4) | 1,815 | 1,397 | 1,434 | 1,865 | 348 / 81 ms |
| 512 m, default | 13,497 | 10,430 | 10,306 | 13,341 | 1,647 / 372 ms |

- The navmesh lies on average 0.41-0.46 m above the terrain; its worst polygon centre is 0.97 m off
  (default) and 1.3 m (lean) - VERIFIED. Agents coped (§5.6).
- A 3 x 3 block of 256 m chunks holds 31,221 human polygons (default) or 16,309 (lean) - VERIFIED.

### 5.2 Three fixes for tile-aligned chunks (each found by a failing experiment)

1. **`border_size` is cut from inside `filter_baking_aabb`.** With the AABB equal to the chunk, the
   navmesh came out shrunk by the border on every side (1.25-254.75 m human, 3-253 m giant), leaving
   2.5-6 m gaps between chunks - VERIFIED. Grow the AABB by `border_size` (a whole number of cells,
   at least the agent radius) and give the bake source geometry beyond it; the navmesh then ends
   exactly on the chunk edge, uneroded - VERIFIED.
2. **Align the voxel grid's y origin.** With the AABB's bottom at each chunk's own lowest height,
   neighbouring tiles quantised heights differently and cross-chunk paths stopped short at borders.
   Flooring it to a world-wide multiple of the cell height (0.25 m) fixed it: 40 of 40 random
   cross-chunk paths on every layer - VERIFIED.
3. **One navigation map per layer.** In one map, the four overlapping layer regions' border edges
   connect to each other: 2,228 (human) and 6,899 (small giant) edge connections for 9 lean chunks,
   and the maps were still not all ready after 9.3 s on the desktop's worker thread (an earlier
   single-map run of the dense set, before fixes 1 and 2, had not built after 10 s) - VERIFIED. With
   a map per layer (`NavigationServer3D.map_create()`, regions' `set_navigation_map()`, agents'
   `NavigationAgent3D.set_navigation_map()`) and edge connections off (below), every layer is ready
   in 4-14 frames on the desktop - VERIFIED.

With the three fixes, **edge connections are unnecessary**: aligned tiles merge their shared border
edges exactly. With `use_edge_connections` off: 40 / 40 cross-chunk and 40 / 40 same-chunk random
paths on all four layers, lean and dense, desktop and web; maps ready in 9-10 frames instead of
118-207 with them on - VERIFIED.

Recast settings that produced aligned tiles (VERIFIED in the lab builder):

```gdscript
var border := agent_radius + 2.0 * cell_size              # whole cells
nm.border_size = border
var y0 := floorf((chunk_min_height - 2.0) / 0.25) * 0.25  # world-wide y grid (cell_height 0.25)
nm.filter_baking_aabb = AABB(Vector3(-border, y0, -border),
	Vector3(chunk_size + 2.0 * border, chunk_max_height + 14.0 - y0, chunk_size + 2.0 * border))
# source geometry: the terrain over the chunk plus 6 m, and the obstacles of the 8 neighbours too
```

### 5.3 The path-search limit (P10b) in an open world

- With the default 4,096 polygons, a 700 m query across a dense 3 x 3 block ended 58-234 m short of
  its target (the search was cut off); on lean blocks straight 700 m targets were reached, but a
  diagonal one ended 35-53 m short on the human and small-giant layers - VERIFIED.
- The P10b engine error came back (a 2-point path plus the error) in 4 of the 16 queries that had a
  polygon limit - an isolated dense chunk with the default 4,096, also with a 300 m distance cap; an
  isolated lean chunk with 2,000; a lean 3 x 3 block with 20,000 (target: an unreachable 6 m island) -
  and in none of the 8 queries with no polygon limit, identically on desktop and web - VERIFIED. A
  distance cap alone does not avoid it.
- **`path_search_max_polygons = 0` with `path_search_max_distance = 300`** never produced the error
  and cost 0.8-3.2 ms (desktop) and 1.5-3.0 ms (web); unlimited without a distance cap cost up to
  26-29 ms on a dense block - VERIFIED. Both properties exist on `NavigationAgent3D` and
  `NavigationPathQueryParameters3D` in 4.6.3 (defaults 4,096 and 0) - VERIFIED.
- Agents only need local paths (activation at most 100 m, leash at most 55 m) - VERIFIED (data); a
  300 m search distance is ASSUMED enough for every agent and director query.

### 5.4 Navigation while chunks stream

- With 9 chunks loaded and ready, one chunk was added in the east and one removed in the west while
  a path inside the centre chunk was queried on every layer every frame for 240 frames: **0 failed
  or short answers**, the new chunk reachable from the centre - VERIFIED (desktop and web).
- Main-thread cost of those map rebuilds: desktop 7-9.5 ms worst frame (async); web **16 ms (lean)
  and 28 ms (dense)**; the first sync of 9 chunks at once 41 ms (lean) and 89 ms (dense) on the web -
  VERIFIED.
- A chunk removed: a path into it ends at the loaded edge (128 m short for a target at its centre);
  paths through it detour round the hole; re-adding it restores the paths - VERIFIED.
- Baking at runtime is not an option for the web: 489 ms (human) and 125 ms (giant) for one lean
  256 m chunk in the web build, 329 / 68 ms on the desktop - VERIFIED.
- Region syncs log "edge error" warnings (1-22 per region) from dense detail polygons; they did not
  break any path test; lowering `merge_rasterizer_cell_scale` to 0.1 made them more frequent (31
  against 3) - VERIFIED. Their absence of harm beyond these tests - ASSUMED.

### 5.5 Size and download

- Navmeshes per 256 m chunk, four layers: 116 KB default, 62 KB lean - VERIFIED. A 64-chunk world:
  about 7.4 MB default or 4.0 MB lean - ASSUMED (extrapolation). Dropping the small-giant layer in
  the open world (the player is stage 3 or more there; the bot paths stage 2-3 on the giant layer)
  would save about 30 % - VERIFIED (layer sizes) / ASSUMED (that it is not needed).

### 5.6 Real enemies across a border

A wolf (human layer, run 8 m/s) and an ogre (large layer, 4.5 m/s), real `EnemyActor`s with their
brains, aware of the giant 30 m beyond a chunk border, their agents on the layer maps - VERIFIED:

| Navmesh | Wolf: crossed / reached the giant | Ogre: crossed / reached | Path failures | Largest waypoint height offset |
| --- | --- | --- | --- | --- |
| lean | 3.9 s / 7.4 s | 8.0 s / 14.5 s | 0 | 0.84 / 0.75 m |
| dense | 3.9 s / 7.4 s | 8.0 s / 14.5 s | 0 | 1.40 / 0.94 m |
| lean, regions lowered 0.45 m (as the Valley does) | 5.8 s / 9.0 s | - | 0 | 0.66 m |

All ended in ATTACK. `EnemyActor` needs its agent's map set to its layer's map, its own
`map_get_path` calls (flee, reachability) must use that map too, and flee points must snap with
`map_get_closest_point` on that map instead of the one region `LevelRoot.nav_region()` returns
(a chunked world has a region per chunk) - VERIFIED (code) / the change itself is ASSUMED small.

---

## 6. Persistence and AI across streaming

### 6.1 World deltas

Deltas are keyed by world and entity ids, never nodes or chunks, and props restore themselves when
instanced (§1.3) - VERIFIED. A chunk that unloads and reloads therefore comes back as it was, with
no new code, as long as every persistent object keeps a stable id that does not depend on the chunk
it is in - ASSUMED (design rule; ids like `world.<region>.<name>` work).

### 6.2 Encounters and the director

- Members never spawn on unloaded ground: activation needs the player within at most 100 m, and the
  loaded margin never fell below 252 m - VERIFIED (data and §3.5).
- **Risk**: the director keeps an encounter active while any member is aware (10 s grace) and three
  encounter kinds have no leash, so an aware member can follow the player into ground that is about
  to unload - VERIFIED (code and data); the fall through the world that follows was not reproduced -
  ASSUMED. Fix: before a chunk unloads, `despawn()` every member standing in it (they return home at
  full health on the next activation; `despawn` exists) - ASSUMED design.
- The director iterates every encounter of its level every 30 ticks - VERIFIED; with a few hundred
  encounters this is cheap but grows with the world, and their scenes all preload at level load -
  ASSUMED cost. Index encounters by chunk and only update those of loaded chunks - ASSUMED design.

### 6.3 Quests, respawns and markers

- Objective positions, respawn points and waystones are found in the loaded tree (§1.1, §1.4) -
  VERIFIED. In a streamed world a marker in an unloaded chunk would hide the objective marker, and a
  respawn at an unloaded waystone would find no node - ASSUMED consequence. Fix: the world builder
  writes a **world index** (ids to positions: markers, areas, waystones, shrines, POIs, encounter
  centres, props that are quest targets) that `Quests.objective_position` and the respawn path fall
  back to - ASSUMED design.
- Area-based quest conditions keep working: the area's chunk is loaded whenever the player stands
  in it - ASSUMED (follows from the ring).

### 6.4 A floating origin is not needed at 2-4 km

- A bare `CharacterBody3D` capsule (3.66, 7.92 and 18.9 m tall) walking 200 m on a terrain chunk
  placed at 0, 2, 4, 8 and 16 km: the same distance travelled to within 0.9 m (sliding round the same
  obstacles), the same largest height deviation (0.467-0.478 m) and the same vertical jitter
  (0.040-0.047 m per tick) at every offset; the web run gave the same numbers to the millimetre -
  VERIFIED.
- The real giant's 400 m loop at 4 km matched the run at the origin (speed, sink, float, seams)
  at all six stages - VERIFIED (§4.4).
- Float32 resolution is 0.24 mm at 2 km and 0.49 mm at 4 km - VERIFIED (arithmetic). Rendering
  jitter at those distances was not looked at - ASSUMED invisible. Navigation queries far from the
  origin were not run - ASSUMED fine (0.5 mm against a 0.25 m cell).

### 6.5 Save size

- A real save at the end of the Valley (assisted bot, help_cache, the crown taken): **6,960 bytes**
  (5,586 compact), 36 deltas, 76 flags, 4 items; the world part 4,324 bytes, about 37 bytes per
  entry - VERIFIED (lab bot run, 485 s simulated, 0 errors).
- Synthetic world documents (deltas, cleared flags, discovery flags), all VERIFIED:

| Entries | JSON compact | gzip | Stringify + parse desktop | Stringify + parse web | Write web |
| --- | --- | --- | --- | --- | --- |
| 500 | 33 KB | 3.4 KB | 1.9 ms | 2.6 ms | 2.5 ms |
| 2,000 | 131 KB | 12.3 KB | 8.9 ms | 11.3 ms | 1.9 ms |
| 8,000 | 522 KB | 42 KB | 41.6 ms | 35.1 ms | 4.3 ms |

- A 4 km² world with 1,000-3,000 entries saves 40-120 KB, a checkpoint costing under 15 ms of JSON
  work on the web - ASSUMED (extrapolation). `SaveIO` writes, verifies and backs up, so its real cost
  is a few times the table's - ASSUMED. Keep the one-file save; no format change is needed - ASSUMED.

---

## 7. The open-world UX the game lacks

What exists is VERIFIED in §1.4; everything below is design - ASSUMED unless marked.

- **World map screen** (`UiScreen`, pausing, in `ScreenStack.SCREENS`): a picture of the world
  rendered by the world builder from the same heightfield (a hillshade with water, roads and
  settlements: one texture of about 1024 x 1024), discovered POIs, waystones, the tracked quest and
  the player. Fog of war per chunk (a discovered bitset in `WorldState` flags). No runtime rendering.
- **Compass** (`HudWidget`): a strip along the top with N/E/S/W, the tracked objective, discovered
  POIs within about 500 m and the nearest waystone; it complements the edge-clamped objective marker.
- **Discovery**: `poi` records (id, position, radius, kind, display name) in the world index;
  standing within the radius sets `discovered.<id>`, shows a HUD message, may award XP once (the
  existing once-flag pattern).
- **Fast travel** between discovered waystones from the map, refused when the checkpoint rules
  would refuse a checkpoint (dead, grabbed, holding, a screen, an aware enemy within 40 m; VERIFIED
  that `checkpoint_blockers()` encodes these). It is a checkpoint at the destination plus a reload:
  the 3 x 3 ring behind the loading screen costs 89-120 ms of chunk loading plus 41-89 ms of
  navigation sync in the web build (65-86 ms and under 9 ms on the desktop) - VERIFIED (9-chunk loads
  and first syncs, §5.4, §10).
- **Non-linear quests**: `Quests.objectives()` already lists every active quest's objective -
  VERIFIED. Add a tracked quest (cycled with a key; the marker and compass follow it), a journal
  screen listing the others, and the world-index fallback for positions (§6.3).
- **Leaving the Valley**: keep the Valley a separate level (its tests, bot and navmeshes stay as
  they are) and add an exit after the crown that loads the world level behind a loading screen; the
  save already names its level - VERIFIED (§1.1). Revisiting the Valley is a transition back.
  Embedding the Valley seamlessly in the world would need its 1,394-node scene (VERIFIED, P10b)
  split into streamable pieces - ASSUMED cost.

---

## 8. World size and budgets

### 8.1 Speeds

- Walk speeds 5.0 / 5.8 / 6.5 m/s at stages 1-3 (VERIFIED); 7.0 / 7.5 / 8.0 m/s at stages 4-6
  (ASSUMED, within the task's 5-8 m/s).
- Sprint is x1.5 for 8 stamina/s; stamina regenerates at 15/s after 1 s; after running dry, sprint
  waits for 25 stamina - VERIFIED (data, DECISIONS). Sustained, that is 3.1 s of sprint per 5.8 s, an
  average of **x1.27** the walk - VERIFIED (arithmetic). The task's "about 2x" is not what the data
  says.

### 8.2 Crossing times (minutes, edge / corner to corner)

VERIFIED arithmetic on the speeds above (stage 4 and 6 rows rest on ASSUMED speeds):

| World | Chunks of 256 m | Stage 3 walk | Stage 3 cruise (x1.27) | Stage 4 cruise | Stage 6 cruise |
| --- | --- | --- | --- | --- | --- |
| 1.5 x 1.5 km | 36 | 3.8 / 5.4 | 3.0 / 4.3 | 2.8 / 4.0 | 2.5 / 3.5 |
| **2 x 2 km** | **64** | **5.1 / 7.3** | **4.0 / 5.7** | **3.8 / 5.3** | **3.3 / 4.6** |
| 3 x 3 km | 144 | 7.7 / 10.9 | 6.1 / 8.6 | 5.6 / 8.0 | 4.9 / 7.0 |
| 4 x 4 km | 256 | 10.3 / 14.5 | 8.1 / 11.4 | 7.5 / 10.6 | 6.6 / 9.3 |

2 x 2 km keeps every crossing in minutes, not tens of minutes - VERIFIED (table). Content for it:
the Valley holds 7 districts in 0.16 km² (VERIFIED); 4 km² at that density is far beyond a prototype,
so the world should be sparser, roughly a POI every 300-400 m (25-40 POIs), 3-5 settlements and 2-3
boss sites - ASSUMED.

### 8.3 Per-loaded-area budgets on the web (recommended)

- Loaded area: 3 x 3 chunks of 256 m = 0.59 km² (VERIFIED arithmetic); fog by 320 m.
- Static world draw calls at most about 25 per view (VERIFIED: 24 with 16 chunks loaded, scenery to
  300 m), leaving about 225 of the 250 budget for props, actors (about 33 each, VERIFIED) and effects.
- Terrain at 4 m spacing: at most about 130,000 triangles per view for terrain and scenery (VERIFIED:
  126,000 with 16 chunks loaded).
- Streaming: at most 4 ms of loading work a frame, atomic steps under about 3 ms, one navmesh
  region a frame (VERIFIED as achievable: p99 under 6 ms, worst 20 ms on the slow web runner).
- Navigation: lean bakes, at most about 17,000 polygons per layer map in the ring (VERIFIED: 16,309
  for a lean human 3 x 3), every query distance-bounded.
- Simulation: the existing 12-combatant budget and CPU per tick p95 under 8 ms (VERIFIED on the
  desktop, 5.40 ms); the web's simulation cost was not measured - ASSUMED 1.3-2.2 times the desktop's
  (the measured ratio for other work).
- Download: about 25-36 KB of compact data plus 62 KB of lean navmeshes per chunk, about 5.6-6.3 MB
  for 64 chunks, on top of today's 14 MB - ASSUMED (extrapolated from VERIFIED per-chunk sizes).

### 8.4 Risks

- The seam trap (§4.4) - VERIFIED; mitigated by a border-slope rule in the world builder (ASSUMED).
- Forests against stage 5-6 giants (3-4 m capsule radius) - ASSUMED risk; trees should be
  breakable or non-blocking for big giants, or spaced for them.
- Web hitches from navigation rebuilds (§3.5) - VERIFIED; budgeted above.
- Real browsers and a real Windows PC were not run - ASSUMED faster than this container; the owner's
  checks in `docs/PERFORMANCE.md` still apply.

---

## 9. Recommended architecture

1. **Two levels.** `level.valley` stays the prologue as it is. A new `level.world` (2 x 2 km, a grid
   of 8 x 8 chunks of 256 m, bounded by impassable mountains or water) is entered through an exit
   that opens after the crown, behind a loading screen. `GameSession`'s Valley mode becomes a
   campaign mode that checkpoints and writes on both levels; the save's `level` field picks the level
   on Continue.
2. **`WorldRoot`** (a `LevelRoot`) with a `ChunkStreamer`: a 3 x 3 ring around the player's chunk,
   unloading at Chebyshev distance 2, nearest chunks first, a 4 ms per-frame budget. The same code on
   both platforms: request resources with `load_threaded_request`, poll, then instance in slices
   (terrain rows, the mesh, the ground body, MultiMeshes, solids in batches of 16, one navmesh region
   a frame). The starting ring and fast travel load behind the loading screen.
3. **Chunk data, built offline** by a world builder (like `tools/builders/valley.gd`, from a layout
   table plus a heightmap): 16-bit heights at 4 m spacing with an apron; MultiMesh buffers for
   scenery; a solid list; per-layer lean navmeshes; and an optional small authored scene for the
   chunk's props, shrines and POIs (persistent props keep stable world ids). Shared meshes and
   materials load once with the level. The builder enforces slopes of 35° or less within a few
   metres of chunk borders.
4. **Terrain**: mesh and `HeightMapShape3D` per chunk from the heights, built at runtime in slices;
   no plugins.
5. **Navigation**: one `NavigationServer3D` map per nav layer, owned by the world root; chunk
   regions join their layer's map; `use_edge_connections` off; tiles baked with the grown AABB,
   whole-cell borders and the aligned y grid; lean detail settings. `EnemyActor` agents and
   `map_get_path` calls use their layer's map (`LevelRoot.nav_map(layer)`); every query sets
   `path_search_max_polygons = 0` and `path_search_max_distance` of about 300 m. Consider dropping
   the small-giant layer in the world.
6. **Director**: encounters indexed by chunk; only loaded chunks' encounters are updated; members in a
   chunk that is about to unload are despawned first. The 12-combatant budget and LOD tiers stay.
7. **World index** (a builder-written resource): positions of markers, areas, waystones, shrines,
   POIs and quest-target props by id, used by quests, the map, the compass, fast travel and respawns
   when the node is not loaded.
8. **UX**: map screen with a pre-rendered map and fog of war per chunk, compass widget, POI discovery
   flags, fast travel between discovered waystones, a tracked quest and a journal.
9. **No floating origin.** Revisit only if the world grows past about 8 km.
10. **Tests to carry over** from this lab into the suites: tile-aligned bakes (border, y grid),
    cross-chunk paths on every layer, an enemy chasing across a border, the giant crossing seams at
    every stage, streaming continuity, the path-search limit, and a streaming walk with a per-frame
    budget check.

---

## 10. The experiments' numbers

Desktop = Linux release export, 4 shared cores; Web = no-threads web release export in headless
Chromium 153 with SwiftShader, 3D off for CPU tests. All rows VERIFIED unless marked.

| Experiment | Desktop | Web |
| --- | --- | --- |
| 256 m chunk (2 m), monolithic: load / inst / add | 9.7 / 0.8 / 1.2 ms | 14.5 / 2.8 / 1.8 ms |
| 512 m chunk, monolithic: worst frame / nav busy after | 44.4 / 7.4 ms | 69.4 / 53.2 ms |
| 128 m chunk, monolithic: worst frame / nav busy after | 4.5 / 0.9 ms | 13.8 / 15.8 ms |
| `load_threaded_request` of a 256 m chunk: time in the call | 0.05-0.12 ms | 15.3-15.8 ms (loads in the call) |
| Split loader, 256 m (2 m), 4 ms budget: frames / total work | 6.3 / 27.7 ms | 7.7 / 41.7 ms |
| Split loader, 256 m (4 m), 4 ms budget: frames / total work | 4.0 / 18.9 ms | 6.3 / 33.4 ms |
| Streaming walk, 256 m ring 1, lean nav, staggered: work+busy p99 / max | 4.3 / 9.6 ms | 5.9 / 19.6 ms |
| Streaming walk: closest approach to unloaded ground at 16 m/s | 253 m | 253 m |
| Terrain mesh arrays, 256 m at 2 m / 4 m | 6.0 / 1.5 ms | 13.2 / 2.3 ms |
| `HeightMapShape3D` creation, 2 m / 4 m | 1.1 / 0.3 ms | 1.7 / 0.4 ms |
| Runtime navmesh bake, 256 m lean, human / giant | 329 / 68 ms | 489 / 125 ms |
| Load 9 chunks (3 x 3) at once, lean / dense | 65 / 86 ms | 89 / 120 ms |
| First nav sync of 9 chunks, main thread, lean / dense | 0.5 / 8.6 ms | 40.8 / 88.5 ms |
| Nav rebuild during streaming (one in, one out), worst frame, lean / dense | 7.1 / 9.5 ms | 16.2 / 27.6 ms |
| Failed or short path answers during that streaming (240 frames x 4 layers) | 0 | 0 |
| Random cross-chunk paths, 4 layers, lean and dense, layer maps, no edge connections | 40 / 40 each | 40 / 40 each |
| Single map with all 4 layers (lean): edge connections, human / small giant | 2,228 / 6,899; ready after 9.3 s | not run |
| Path to an unreachable island, unlimited + 300 m distance cap | 0.8-3.2 ms, no error | 1.5-3.0 ms, no error |
| Same, unlimited without a cap, dense 3 x 3 | 26 ms | 26.5 ms |
| P10b error reproduced: queries with a polygon limit / without | 4 of 16 / 0 of 8 | 4 of 16 / 0 of 8 |
| Navmesh polygons per 256 m chunk, human, default / lean | 3,445 / 1,815 | same files |
| Navmesh files per 256 m chunk, 4 layers, default / lean | 116 / 62 KB | same files |
| Draw calls per view, 16 chunks loaded, scenery to 300 m | max 24 | not run (same renderer, ASSUMED equal) |
| Terrain triangles per view, 2 m / 4 m spacing | 372,000 / 126,000 | - |
| Real giant, stages 1-6, 400 m loop with 4 seam crossings, near and at 4 km | 12 / 12 at 98.6-99.6 % of walk speed | - |
| Seam trap: ramp of 40° / 44° across a chunk border | stage 1 stops / every stage stops | - |
| Wolf / ogre chasing across a border: reached the giant | 7.4 s / 14.5 s, 0 path failures | - |
| Capsule precision at 0, 2, 4, 8, 16 km | identical within 0.9 m of 200 m and 1 mm of height deviation | identical to desktop |
| Valley completion save | 6,960 bytes (36 deltas, 76 flags) | - |
| Synthetic save, 2,000 entries: size / stringify+parse | 131 KB (12.3 KB gzip) / 8.9 ms | 131 KB / 11.3 ms |
| Crossing a 2 x 2 km world, stages 3-6, cruising | edge 3.3-4.0 min, corner 4.6-5.7 min | - |

Reproduction (scratch, not committed): the lab's builder `game/lab/ow_build.gd`
(`--size= --spacing= --grid= [--edge= --ddist= --derr= --tag=]`), the bench `game/lab/ow_bench.gd`
(`-- --only=sync+threaded+split+gen+bake+nav+navpairs+navbug+navcont+save+float+walk+walklean+draw`,
on the web `?args=--no3d,--only=...`), the web driver `web_driver/run_web.js` and the game-level
suites `game/tests/slow/test_ow_terrain.gd` and `test_ow_ai.gd`, all under the session's scratchpad
folder (`<scratchpad>/ow_lab/`), with every run's log in its `logs/` folder.
