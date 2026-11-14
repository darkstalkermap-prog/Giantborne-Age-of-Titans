# Architecture

How the build is put together: the layers, the autoloads and the simulation tick, each area of the
game - the combat core, the giant, the enemies, the two campaign levels and the streamed world, the
world builder, quests, the campaign and its saves, bosses, the living world, the UI, presentation and
audio - and the tools, the bots and the tests. It consolidates the system documents of the M2-M5
packages (`docs/systems/P01.md` ... `P18.md`) and the M6-M9 packages (`P19.md` ...
`P40.md`), which keep every public API and
detail; §22 says which document holds what. The interpretations behind it are in
[DECISIONS.md](DECISIONS.md) (decisions 1-30 from the M2-M5 plan, 31-64 from the M6-M9 plan).

## 1. Layers

Three practical layers, as the spec asks (section 12): **rules and data**, **engine adapters** and
**presentation**, plus actor scripts that glue them together. Nothing in presentation, audio or UI
spends resources or changes combat state; listeners of `Events` never do either.

```
data/**/*.json ──► GameData (schema registry, validation, post-pass) ──► ActionDef / StatusDef / records
                                                   │
 input ─► InputRouter ─► intents ─► GiantPlayer components ─► CombatController (validate → commit → timeline)
 AI ─► EnemyBrain (perceive / decide), Formation ─► EnemyActor, SiegeEngine ┘   │
                                                   AttackRunner (arcs, pulses, bands, projectiles, grabs, hazards)
                                                                             │
                              HitFactory ─► HitEvent ─► Sim (stable order) ─► CombatEntity ─► DamageResolver (pure)
                                                                             │
       Events (90 signals: hits, deaths, telegraphs, quests, saves, screens, travel, regions, formations, ...)
                                                                             │
   Quests · GameSession (checkpoints, travel) · EncounterDirector · WanderDirector · FactionState · Discovery ·
   BossArena / BattleBoss · HUD widgets · HitFeedback · TelegraphVisuals · CameraRig · rigs · Audio · the bots

 the streamed world: WorldRoot ─► ChunkStreamer ─► TerrainChunk (ChunkData) · NavMaps ─► NavQuery · Skyline
```

## 2. Autoloads and the tick

Autoloads, in order (`project.godot`): `Events` (every signal, declared up front with one anchor per
package; P20 declared the M7-M9 block), `GameData` (loads and validates `data/`), `Settings`,
`WorldState` (flags, world deltas, inventory), `GameSession` (modes, the campaign across levels,
character state, checkpoints, travel, saves), `Quests` (quests, dialogue, tutorial prompts, the
tracked quest, the ends of the prologue and the campaign), `Sim` (the 60 Hz driver) and `Audio` (last:
presentation only, P19).

`Sim.step()`, once per physics tick:

1. `tick += 1`.
2. **PRE_ACTORS hooks**: the EncounterDirector's activation, leash and AI LOD (order 10); the leash
   return of members sent home (12); the WanderDirector's tables and events (12, world only).
3. **Actors** in entity-id order: the player's `sim_step` (input edges offered to its components,
   movement, hit queries) and each enemy's (perceive at 5 Hz, decide at 10 Hz, scripted motion,
   steering, hit queries); siege engines; props and dummies.
4. **POST_ACTORS hooks**: the ProjectileSystem (order 100) moves projectiles, thrown bodies and thrown
   engines.
5. **Hit resolution** in a stable order (attacker, instance, pulse, sub-step, distance, target);
   hits from an attacker that died earlier in the pass are dropped unless they come from a
   projectile.
6. **The status pass**: every entity ticks its statuses (expiry, healing over time).
7. **POST_RESOLVE hooks**, in order: shrine activation (50), size gates (60) and the Needle's pass
   (61), Quests (100), boss arenas and battles (120), the yield step (125), the den's back wall (135),
   FactionState (150), Discovery (160), waystones (190), GameSession's deferred checkpoint (200),
   cosmetic props (220).

Randomness: crits use the seeded `Sim.rng` in hit order (pinned by the worked-example tests); every
other consumer draws from a generator of its own, so none shifts the crit sequence: loot, wander
rolls and the bots from `Sim.rng_for("<stream>")` ("loot", "wander", "bot"), each enemy brain's AI
picks from a private generator seeded with `Sim.DEFAULT_SEED ^ hash(entity_id)`, debris from one
seeded with its prop's world id, and the autopilot's soak and the stress scenario from private ones
with fixed seeds; the audio engine owns private generators and never touches `Sim.rng` or a stream.
Launch slots (`request_launch_slot`) space ranged launches - siege engines' included - at a target.
Presentation runs in `_process` and only reads state.

## 3. Data and validation

- `data/` holds every number and every piece of content as one JSON record per file
  (`schema_version`, a dotted `id`, SI units): 651 records in 21 folders at W23 - abilities and
  actions, statuses, the player and ancestries, growth profiles 1-6, enemies, NPCs, props, weapons,
  items, loot tables, shrines, talents, the progression table, quests, dialogue, tutorial prompts,
  the world's records (levels, regions, POIs, encounters and templates, factions, wander tables, world
  events), audio (banks, the mix, music and ambience sets, audio regions), input bindings. Test-only
  records live in `data/test/`, which the web release leaves out.
- `DataValidator` (`scripts/core/data_validator.gd`) holds the shared enums and the **schema
  registry**: one module per record type in `scripts/core/schemas/` (`fields()`, `semantic()`,
  `required_ids()`), loaded only when its file exists; P19 added the five audio types and P20 the six
  M7-M9 types (`region`, `poi`, `faction`, `talent`, `wander_table`, `world_event`). A module's
  `semantic()` holds a record's own rules: for example, a level's `preload` paths must be res://
  resources that exist, each listed once (the level schema). Unknown keys are errors; ticks that are
  not whole warn; references are checked by type.
- `GameData` merges every module's required ids and runs a **post-pass** for rules that span
  records: an untelegraphed long enemy windup, encounters, the forge's upgrade rule, the progression
  table, the growth profile chain (`PlayerGrowth.profile_chain_errors`), evolution chains and stage
  movesets (`Progression.evolution_errors`, `stage_moveset_errors`), the talent trees and ancestry
  signatures (`Talents.data_errors`), the formation caps around every cluster (`FormationRules`),
  siege engines (`SiegeRules`), boss yields, broods and hazards (`BossRules`), the first-oath
  resolutions and reconciliations (`OathRules`), world events and templates
  (`WorldEvent.data_problems`), every POI's region and landmark, quest-critical props being
  indestructible, every chunk file of a streamed level, and the leash of every streamed encounter. The
  pure rule modules load without the actors. Any error stops the game at a screen that lists them all;
  `override_record` / `restore_record` serve the tests.

## 4. Combat core (`scripts/combat/`)

- `CombatController`: the action state machine (locomotion, attacking, casting, executing, blocking,
  dodging, staggered, grabbed, dead), costs and cooldowns, the 0.15 s input buffer, level and stage
  gating (`preview_reason` gives the HUD the same answer a request would get), `force_action` for
  scripted follow-ups, super armour through windup and active.
- `Combatant`, `ResourcePool` (health, stamina, essence, fury; rescaled on growth), `PoiseMeter`
  (recovery punish multiplier, longer stagger against a twice-taller attacker), and statuses
  (`StatusDef`, `StatusSet`). Since P33 the combatant also carries **passives** (talents, the
  ancestry: lasting modifiers that are never statuses), read by the pools, the poise meter, costs,
  cooldowns and the resolver.
- `CombatEntity` (on every damageable node): receives hits through `DamageResolver` (pure; spec §7
  formulas), applies on-hit statuses and morale damage, emits the events, carries the faction and
  the lock anchors; a yielded boss accepts no hit but the confirmed strike (P34).
- `HitFactory` / `AttackContext`: the one place that builds a `HitEvent` for every source. Since P32
  an action's `attacker_height_override_m` sets the hit's attacker height, so a ballista bolt staggers
  a big giant like an 8 m attacker (decision 51). `skip_candidate` keeps the player's area effects
  off neutral faction members.
- `AttackRunner` (`scripts/actors/attack_runner.gd`): dispatches an action's hit shape -
  `weapon_arc`, `cylinder_pulse`, `sector_pulse`, `line_pulse` (cylinder pulses one after another
  along the facing the strike began with: Earthquake, P31; the rival giants' and Harrok's overhead
  chops, P34), `band_pulse` (a formation's brace: one box along its front rank, P30), `projectile`
  (with `indirect` lobs that commit a landing circle, P34), `grab`, `body_sweep` - and self statuses.
  An action's `arena_hazard` block (Harrok's falling stones, P34) is not a shape: that action is a
  `cylinder_pulse`, and each stone strikes as one at a point Harrok's brain places
  (`p34_hazard_pulse`, called by his actor). The **target provider** (P30) lets a unit whose record
  names `targets` strike NPCs and props (raiders burn houses, siege lines bombard longhouses).
- `ProjectileSystem` (one per level): exact ballistic steps, sphere casts, splash, committed aim
  points, thrown bodies and, since P32, thrown siege engines that smash where they land.
- `TargetingRules` / `LockOnTracker`: lockable means team ENEMY or faction-less NEUTRAL; a lock
  acquires the best-scoring visible target within a range that grows with the stage (35 m at stage 1
  to 80 m at stage 6) and a horizontal cone that narrows (half-angle 60° at stage 1 to 40° at stage
  6), both set from the growth profile (`lock_range_m`, `lock_half_angle_deg`). Once held, the lock
  ignores the cone and lets go on its own only when the target dies or becomes unlockable, stays
  hidden for over 0.75 s, or is beyond 1.25 × the range.

## 5. The giant (`scripts/actors/giant_player.gd`, `scripts/actors/player/`)

`GiantPlayer` is glue over a registry of `PlayerComponent`s, each with hooks for input edges,
pre-action logic, post-movement work, saves, the rig and the debug panel:

| Component | Owns |
| --- | --- |
| `PlayerMotor` | Walk, sprint, facing, dodge, knockback, speed multipliers; trampling (props with a `trample_stage` break when the giant walks into them, P26) |
| `PlayerTargeting` | Hard lock, soft target, switching, lock anchors; at stages 4-6 a formation is one lock candidate and its banner another (P30) |
| `PlayerAttack` | Weapon geometry (scaled by stage and fit), the vertical aim, launch points, ability ranges by stage, hit queries through AttackRunner |
| `PlayerInteract` | The E candidate (shrines, NPCs, pickups, racks, forges, heave points, grabs) and its prompt; stage refusals ("Out of reach. Grow to stage N.") |
| `PlayerGrowth` | Stages 1-6: checks (clearance, combat, flags, shrine conditions), applying a growth in one tick (capsule, resources, the body's size-gate mask, the navigation layer and query mask, weapon, camera, rig) |
| `PlayerEquipment` | Owned weapons, equipping, the fit cap, the stage movesets of a reinforced weapon (`moveset_for(rec, stage)`, P26/P31), the weapon mesh |
| `PlayerGrab` | Grab, hold, throw, put down, Crushing Grip, every release path; at stage 6 siege engines and Rampart Grip (P32); no boss can be grabbed |
| `PlayerProgression` | XP, levels, attributes, ability learning, evolutions (P31), talents and the ancestry with their passives (P33), kill loot |

Growth profiles 1-6 are data (3.66 / 5.49 / 7.92 / 10.97 / 14.63 / 18.90 m). Each profile names the
size-gate layers its body still collides with (`size_gate_mask`) and the titan navigation bits its
paths may use (`nav_query_mask`), and the interaction permissions it grants (stage 4 `trample`, 5
`formation_sweep` and `heave`, 6 `siege_disruption`). `apply_character_state` /
`capture_character_state` move the whole character (stage, level, XP, attributes, talents, ancestry,
loadout, weapons, resources) in and out of the save document.

## 6. Enemies, NPCs and factions (`scripts/actors/`, `scripts/ai/`)

- `EnemyActor` (a `CharacterBody3D`) senses, moves (navigation through `NavQuery` on the record's
  layer, scripted lunges and charges), runs its `AttackRunner`, announces telegraphs, takes attack
  tokens (2 melee, 2 ranged per target), switches AI LOD tiers (tier 2 sleeps behind a one-box
  proxy), handles morale, flight and rout, grabs, the leash return (round a body in its way since
  W23; outside its leash a return never ends early: it waits off the body on its post and answers a blow (M9 gate, `docs/systems/P39f.md`, "M9 gate (lane review)"); a ranged member's firing points stay inside its leash and only a hostile holder keeps a member off it: M9 gate, final round),
  factions, awe, ranged posts and the front-arc positioning (P22), the target provider (P30),
  crews (P32), regeneration and the yield protocol (P34) and march columns (P37) - each package's code
  under its own anchor.
- `EnemyBrain` (pure state machine): IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION,
  FLEE, STAGGERED, DEAD, HOLD, STAND_DOWN, RETURN, ROUTED; outmatched tactics (formation and brace,
  harass, spread, kite); boss phases and attack sequences. Searches for firing points, flight and
  rout points spend the level's per-tick path-query budget and resume where they stopped (M7 gate).
- Archetypes of the Valley: `SoldierEnemy`, `WolfEnemy` (`QuadrupedRig`), `ArcherEnemy`, `MageEnemy`,
  `OgreEnemy`, `OgreBoss` (the Ogre King), `SparringPost`, `Civilian` (flees to reachable shelters,
  or, in a town at peace with the giant, gives way and watches).
- **Formations** (P30; `scripts/ai/formation.gd`, `formation_rules.gd`): ranks x files of slots round
  one pivot; states formed, advancing, braced, broken, routed; one brace pulse per cycle along the
  front band with one melee token; a banner that halves awe and ally-death losses and rallies; routs
  that fan out over flee points; outmatched soldiers joining within 40 m; caps of 40 members on the
  desktop and 20 on the web (the level's `max_formation_members` and its `web_overrides` value; on
  the web an encounter's `web_formation_scale` thins its formations so that every cluster fits, which
  `FormationRules` checks). Pikemen, shieldmen and bannermen are records.
- **Siege engines and crews** (P32; `scripts/world/siege_engine.gd`): a `SiegeEngine` is a
  `BreakableProp` with its own controller and runner; it shoots while crewed
  and while its battle does not hold its fire until its phase (`SiegeEngine.set_fire_held`, `fire_held`; `BattleBoss.engine_phase`: M9 gate, lane aldmere)
  (ballista bolts along an aim line, catapult stones into a landing circle), takes ranged tokens and
  launch slots, raises the −20 siege morale event when it breaks, can be seized and thrown at stage
  6, and since P36 can bombard props (`prop_targets`, the siege of Skarn).
- **Cavalry** (`cavalry_enemy.gd`, `cavalry_brain.gd`): ride to a start point, charge through the
  giant's legs along a line, wheel 30-50 m beyond and come again.
- **Trolls and rival giants** (P34): `TrollEnemy` (regeneration stopped by Burning; fire from braziers,
  bonfires and the fire pit), the Troll Matriarch (`MatriarchBrain`: whelp throws, the drive-out),
  dire wolves, `RivalGiantEnemy` and `HarrokBrain` (the Moot's stones).
- **Factions by record** (P22, P29; `scripts/world/faction_state.gd`): `faction.<name>` records hold the
  texts, offences to hostility, initial standing, give-way distance and respawn guard; standings
  neutral, warned, stood down, hostile, reconciled; a blow on a member or on a faction's house or
  engine is an offence; `reconcile` by a dialogue choice and its price; an encounter's
  `stand_down_when` condition; a hostile faction's armed members near a checkpoint refuse it as a
  respawn.

## 7. The levels: the Valley and the streamed world (`scripts/world/`)

- **Levels.** `LevelRoot` names its `level` record and answers lookups (markers, checkpoints, areas,
  patrol routes, districts, its world index, its navigation maps); it applies the record's graphics
  presets, far plane and web overrides, and makes the record's runtime nodes (`RUNTIME_NODES`:
  `Discovery` in both campaign levels, `WanderDirector` in the world). `LevelExit` is a door to
  another level. `AreaTrigger` reports the giant entering and leaving named areas (quests, tutorial
  prompts, arenas); `LevelMarker`s are objective, cover, elevation, formation, safe, patrol and
  bot-route points.
- **Encounters.** `EncounterDirector` (one per level) spawns `encounter` records near the giant
  (their scenes load with the level; at most 2 spawns a tick from the Sim hook). It persists kills
  (`persist_death`). Once the giant has left an encounter and no member has been aware of it for
  10 s, it deactivates the encounter: the living members are freed, not killed, and come back at
  home at full health. It keeps the budget of 12 counted combatants (`max_active_enemies`): members
  of budgeted encounters whose definition is an enemy, and a hostile faction's armed members, those
  already in the world included, while new spawns wait. NPCs never count, and formation members count
  toward the formation cap instead. It sets AI LOD tiers by distance, leashes, alerts groups and
  clears encounters (`encounter.<id>.cleared`). It also runs encounters' formations (P30), gives the
  placed siege engines named in an encounter's `engines` list their crews and stands them down with
  it (P32), and runs template copies (P37).
- **The world index** (`WorldIndex`, `scripts/world/world_index.gd`; P20, P25; decision 44): a
  resource the builders write for each level (`assets/world/index_valley.res`,
  `assets/world/index_world.res`; the level record's `index` names it). It answers by id for whatever
  is not loaded: every checkpoint (position, yaw, display name, kind, chunk, fast travel,
  `requires_flags`, region, district, `max_stage`), marker, area, POI, exit, encounter centre and prop
  (quest targets, landmarks, cairns), plus the Valley's districts, the staged road graph, the world's
  region grid and its map picture. `WorldIndex.for_level()` (`LevelRoot.index()`) loads it once per
  level, and `ResetHooks` clears the cache. When a node is not loaded, the following fall back to it:
  quests' objective positions, the map, the compass, fast travel's refusals, respawns, save
  migration, the title's save line, the checkpoint toast, FactionState's respawn guard and the
  director's formation markers. `WorldRoot.region_at` reads its region grid, and the WanderDirector
  and the bots (`BotRoute`) plan on its road graph.
- **Discovery** (`scripts/world/discovery.gd`; P27; decision 63): a runtime node of both campaign
  levels. Every 30 ticks (POST_RESOLVE, order 160) it turns where the giant stands into WorldState
  flags:
  - `discovered.<poi short>` once the giant is within a POI's radius at its `min_stage` (a sealed
    place only once its seal is open). This pays the POI's XP once and emits `Events.poi_discovered`.
  - A found vista marks the other non-secret POIs within its `reveals_m` as `"revealed"` (shown on
    the map and the compass, no XP until visited) and clears those chunks' fog. The radius is 400 m
    by default and 600 m from the Kingsgate Shelf, Shepherd's Watch, the Stair's Head and the
    Ironway Top.
  - `sealed.<poi short>.seen` within 60 m.
  - `map.seen.<chunk>` (the map's fog).
  - On `Events.region_changed`, `region.<short>.entered`, paying the region's `discover_xp` once.
- **The Valley** (`scenes/world/valley.tscn`, 400 x 400 m) is generated from
  `tools/data/valley_layout.json` by `tools/builders/valley.gd`: eight district sub-scenes, four
  offline navmeshes in `assets/nav/`, props, shrines, waystones, forges, markers, triggers, patrol
  routes, the boss arena and, since P26, the Kings' Door, the Citadel hall and the First King's vault.
  Its index (`assets/world/index_valley.res`) names its checkpoints and their `max_stage`.
- **The world** (`scenes/world/world.tscn`: 2,048 x 2,048 m, 8 x 8 chunks of 256 m, origin at the
  centre, walkable inside ±896 m; P24a, P25):
  - `WorldRoot` (extends LevelRoot) configures the streamer from the level's `world` block, sets the
    depth fog, focuses the streamer on the giant, keeps the skyline's mask, follows the region the
    giant stands in (`Events.region_changed`, 15 m hysteresis) and answers `height_at`, `surface_at`,
    `water_at`, `region_at` and `is_ready()` (the ring round the respawn) for the loading screen; at
    `_ready` it loads the level's `preload` list (the scripts and shared scenes of the chunks' props)
    behind the loading screen (M8 gate F26).
  - `ChunkStreamer` loads chunks within Chebyshev distance 1 of the giant's chunk, nearest first, and
    unloads them at distance 3 or more (at most 25 loaded; a border walk never reloads one); per frame
    it runs steps until 4 ms are spent, or, deterministic (headless, `--fixed-fps`, tests), a fixed
    quota with synchronous loads; heavy steps (a props part's load or instancing, a navmesh's load,
    its region's add) run alone in a frame. It emits `chunk_unloading` while every node is whole (the
    director despawns the chunk's members first) and keeps statistics (loads, thrash, work per frame,
    steps by kind). `TerrainChunk` builds one chunk a step at a time from its `ChunkData` (16-bit
    heights at 4 m with an apron, scenery buffers, solids, water, region and surface cells, navmeshes,
    props sub-scenes).
  - `Skyline` (`skyline.gd`, `assets/shaders/skyline.gdshader`) draws the whole world's coarse terrain
    and the landmarks' silhouettes wherever no chunk is drawn, and the lit beacons as columns that
    ignore the fog; fog runs 400-1,800 m and the far plane is 2,400 m.
  - **Navigation**: `NavMaps` keeps one `NavigationServer3D` map per layer (human 1, large 2, titan 16;
    the titan gate regions 32 / 64 / 128 on the titan map) and adds and removes each chunk's regions;
    with deterministic streaming every map and region runs with async iterations off, and a chunk is
    ready once every map it changed has passed its last change's iteration id. `NavQuery` is the only
    way to ask for a path (`NavQuery.path()`, which runs `NavigationServer3D.query_path` with
    unlimited polygons and a distance cap by purpose: `chase` 120 m for enemies' chases and the
    formations' pivots, `far` 300 m for the bots and the civilians, both their agents' paths and their
    safe-point checks; a per-tick budget of 8 queries, read with `budget_left()` by callers that can
    wait: an agent's re-path, a formation's pivot, the wander director's spawn check; `closest_point`
    for flee and safe points; horizontal waypoints in the world); the Valley keeps its own parameters,
    so its paths did not change. Nothing bakes at run time (P24b).
  - **The director in a streamed world** (P24b): an encounter updates only while its centre chunk is
    loaded and ready, its members spawn only on ready ground and are despawned (never killed) before
    their chunk unloads, spawns are filtered by the giant's stage (`min_stage` / `max_stage`), and every
    world encounter needs a leash unless it is an arena boss's.
- **Size gates** (P26): `SizeGate` walls on physics layers 7-9 stop giants below stage 4, 5 or 6 (the
  same ground is a titan gate region, so paths agree), props with `min_growth_stage`, heave props
  (`HeavePoint`: rockfalls, the fallen titan-tree, the toppled statue), trampled palisades, narrow
  passes (`NarrowPass`, the Needle, P35); each refusal names the stage it needs and plays its
  material's cue at the contact point.
- **Props.** `BreakableProp` covers breakable and structural props (damage stages, saved health,
  debris layouts, nav links that open, locked messages, XP, flags, loot tables; indestructible
  placements, trample and heave since P26; `SiegeEngine` extends it). `CosmeticProp` and
  `CosmeticField` only react. `DebrisPool` caps debris at 40 pieces.
- **Interactables.** `Interactable` (the E prompt; `requires_stage` since P26) and its subclasses:
  `Shrine` (activation once per visit, Rest, growth; its screen adds Loadout, Attributes, Talents and
  Ancestry), `Forge` (the reforge chain by forge tier), `UprootTree`, `WeaponRack`, `ItemPickup` and
  `NpcTalker`. `Waystone` is a `CheckpointMarker`, not an interactable: standing near it reaches its
  checkpoint, and once visited it is a fast-travel point.
- **Props and interactables added in M7-M9**: `BeaconFire` (P29), `TownForge` (P29) and
  `ConditionForge` (P36) (forges with a tier, shut to a hostile town or until a condition holds),
  `ForgeFire`, `GreatPineTree` (stage 4 uproots a great pine) and `RewardRack` (P35), `RewardArea`
  (P26), `Inscription` (P25; the Old Kings' cairns), `FlagVisibility` (P25; an element shown or
  hidden by a flag), `BroodNest` and `DenWall` (P35: the Matriarch's brood nests, which only fire
  destroys, and the den's back wall), `RebuildPoint`, `ConditionSpawn` (a placed scene that appears
  once a condition holds: the siege line, the tower ballista) and `StoneThrone` (P36).

## 8. The world builder (`tools/world/`, `tools/builders/world.gd`; offline, not exported)

- **Layout tables** (`tools/data/world/world.json` and one table per region): the frame, the
  regions, the terrain features, roads, beacons, the index's extra edges, and per region its
  elements, shrines, waystones, checkpoints, exits, size gates, sealed places, caches, cairns,
  markers, areas and scenery rules.
- **The library**: `WorldFeatures` (`features.gd`: the terrain recipe and the queries the builder and
  tests use - `walkable`, `gate_at`, `slope_deg`...), `HeightField` (`heights.gd`: the 16-bit field,
  `relax_borders`), `ChunkWriter`, `SkylineWriter`, `WorldLayout` (`layout.gd`), the element kinds
  (`kinds/*.gd`: houses, walls, towers, gates, bridges, fortress walls, engines, arenas, talkers,
  forges, cairns, braziers, nests...), `NavBake` (`nav_bake.gd`: lean per-chunk navmeshes on the three
  layers with the grown bake box, the aligned y grid and the neighbours' obstacles, split into gate
  regions), `WorldIndexWriter` (`index_writer.gd`), `WorldMapRender` (`map_render.gd`: the 1,024 px
  map) and `seam_check.gd`.
- **The build**: the field (borders softened and relaxed so no walkable face within 8 m of a chunk
  border is steeper than 35°, then quantised), per chunk its data, scenery, merged structures and
  props sub-scenes of at most 150 nodes, then navigation, the link ends snapped onto the baked meshes,
  the skyline, the map picture, the index (`assets/world/index_world.res`: checkpoints, POIs, props,
  encounters, the region grid and the staged road graph) and the root scene. `--chunks=c2_6` rebuilds
  those chunks and their eight neighbours; two builds write the same bytes; `tools/check.sh` runs the
  seam check after a world build, and the gate suite `test_world_reachability` checks every place is
  reachable at the stage it needs.

## 9. Quests, dialogue, oaths and tutorials (`scripts/quests/`)

`Quests` runs data-driven quests whose stages complete on world state, grants once-only rewards,
offers objectives (with the bots' hint) to the HUD, hosts the `DialogueSession` and the
`TutorialDirector`, and ends the prologue (`slice_completed`) and the campaign
(`campaign.completed`). Since M7: the main quest is `quest.world_main` once the world's thread starts
(P29); multi-marker stages (the oaths stage's three leads), `markers_done_when`, `xp_floor_level`
(a milestone pays at least the XP that reaches the next stage's level), `waiting_text`, an objective
on another level leading to this level's door (`objective_route`); the tracked quest
(`tracked_quest_id`, saved; `track_next`) and up to three leads for the compass (P27); a running
world event's objective among the quests (P37). `QuestConditions` is the pure evaluator, with the
M7-M9 shapes `count`, `quest_done`, `level_is`, `discovered`, `region_entered`, `ancestry_is`,
`ancestry_chosen`, `event_done` and `near`. Dialogue choices whose conditions fail can show greyed
with their reason (`locked_text`); `attribute_points` is a once-gated reward. `OathRules` (pure,
GameData's post-pass) proves every oath has a resolution that can be won first at stage 4 and every
faction a reconciliation.

## 10. The campaign, session and saves

- **The campaign** (P20): `GameSession.Mode.VALLEY` is the campaign across `level.valley` and
  `level.world` (`is_campaign()`); `level_id` is the level played and the save's `level`, which
  Continue loads. `travel_to(level, checkpoint, reason)` (an exit, fast travel, debug, the bots)
  commits a checkpoint at the destination and reloads `scenes/main.tscn`; it is refused with a reason
  by the checkpoint blockers, an unknown checkpoint, a `max_stage` below the giant's stage, an
  unvisited stone (`visited.<id>`) and, since the M7 gate, a stone its respawn blockers refuse.
  `respawn_checkpoint()` moves a refused respawn (a hostile town's guards, a running world event) to
  the nearest visited one and says why. Shrines and waystones activate once per level visit.
  `--mode=world` starts a new game from `progression.world_start` (level 6, 1,050 XP, stage 3, the
  base club; the Valley's worst outcome).
- **Checkpoints** are requested by shrines, waystones, growth, quest stages, oaths, shrine choices
  (talents, ancestry, attributes, loadout: M8 gate F15) and a boss's end (defeated, fled, yielded),
  and taken in POST_RESOLVE when nothing blocks them (dead, grabbed, holding, a screen open, an aware
  enemy within 40 m). Completion requests (the prologue's and the campaign's end, a boss's end, the
  world's main-thread stages)
  ignore aware enemies. No checkpoint is taken while a boss fight or a battle is engaged (M8 release
  R1).
- **Save schema 2** (`SaveSlots.SCHEMA_VERSION` 2): `SaveSlots.migrate()` runs after the read and
  before `validate()`, one pure step per version; `_migrate_1_to_2` adds `character.talents`,
  `character.ancestry_chosen`, the `progress` block (`prologue_complete`, `world_entered`,
  `levels_visited`, `tracked_quest`), the respawn's position and yaw from the level's index and the
  `visited.<id>` flags the save's progress proves. A damaged main file falls back to its migrated
  backup; a newer build's file is refused and kept as `valley_1.schemaN.rejected.json`; the slot
  (`user://saves/valley_1.json`) and the project name stay, so desktop and web saves carry over.
  `SaveIO` writes it (temp file, verify, backup, replace); `CharacterState` builds and normalises the
  character. `TitleScreen.describe_save` names where Continue wakes the giant (M8 release R2).
- Every mode change, reset, reload and travel is a reload of `scenes/main.tscn`; `main.gd` builds the
  level with the tree paused, holds it behind "Loading... N%" until the audio has registered the
  level's samples, the navigation map has synced and, in the world, the starting ring is ready (at
  most 8 s, then a warning), then calls `GameSession.on_level_ready`.

## 11. Bosses and battles (P34; `scripts/world/boss_arena.gd`, `battle_boss.gd`)

- `BossArena` closes its gate behind the giant and opens it at the boss's end. **The disengage rule**:
  a giant beyond the arena's inner radius + 20 m for 5 s ends the attempt (`boss_disengaged(left)`,
  the boss starts again at full health, the music returns to the zone; the screen warns first).
- **The yield protocol**: a boss with `yield_at` cannot die while armed; at its yield (a health floor,
  poise breaks, or Corvane's guard broken) it is immune and harmless at once - earlier blows,
  projectiles and hazards land on nothing - and only the yield prompt decides, with a held confirm:
  Spare (`spared`), Strike (one blow, `slain`) or a fight to the death. `Events.boss_yielded`; the
  outcome is a flag (`boss.<name>.outcome`).
- `BattleBoss` makes a battle a boss: phases over several encounters, each begun at a fraction of
  `BattleBoss.phase_fraction` - the planned units' current health with every engine counted at its
  full health (a routed unit counts as fallen too since the M9 gate's final round, `55a56db`), while
  the bar the giant sees still counts what the engines have left and its notches follow the phases
  (M9 gate, lane ironreg, `docs/systems/P39.md`, "The M9 gate (lane ironreg)"; the final round's
  `55a56db`) - or when every unit of the phases so far has fallen; Corvane's yield ends it.
  `FortBattle` is the Iron Regiment in Fort Aldmere's bailey (its portcullis holds the giant in until
  the battle ends; a parley leaves the bailey at peace); `MootArena` is Harrok's ring (the talk
  ending, `yielded_talk`); the Matriarch's den is a `BossArena` with the drive-out
  (`boss_disengaged(fled)`). A battle starts every attempt afresh and repairs a save written
  mid-battle (M8 release R1). The Iron Regiment's phases begin at 0.70 and 0.50 of that fraction
  (`tools/data/world/aldmere.json`; the thresholds since the W23 confirmation, `a7da72d`).
  An engine of the battle that a later phase's encounter names in its `engines` list holds its fire
  until that phase begins (`engine_phase`, `held_engines`, `SiegeEngine.set_fire_held`; a reset, a win or
  the node leaving the tree frees every hold), and the HUD says which engines shoot now and which join
  later (`engines_line`, `phase_engines_line`) (`docs/systems/P39.md`, "The M9 gate (lane aldmere)").

## 12. The living world (P37; `scripts/world/wander_director.gd`, `world_event.gd`)

- **Templates and copies**: an encounter record with `template: true` is never active by itself;
  `EncounterDirector.p37_copy_record` makes a copy (ids `<template>.<n>`) placed and turned at an
  anchor on loaded ground, persisting nothing and dropping no loot, whose kill XP falls to zero after
  an entry's third spawn. A copy is a first-class encounter for the budget, the formation cap, the
  leash, LOD, streaming, formations, stand-downs and crews.
- **WanderDirector** (a runtime node of `level.world`, campaign only): per region's `wander_table`,
  every 60-120 s a copy of an entry allowed by the giant's stage, flags and faction standings, placed
  120-220 m away on a road, out of the camera's view, clear of settlements, placed encounters and
  other copies; columns walk a route of the road graph and leave out of view.
- **World events** (`world_event` records: the Millford raid, the army column, the siege of Skarn):
  at most one runs; one starts only when its centre chunk is loaded and ready and the giant is within
  200 m; its objective shows in the tracker, journal, compass and map; it is suspended while its chunk
  is unloaded (abandoned after 600 s with no outcome), resets on the giant's death, ends on its protect
  objective, its fail timer, every copy defeated or a column home, and pays its outcome once. A moving
  column is an abstract point on its route while its ground is not loaded. A running event refuses
  respawns within 120 m of it and survives reloads; only a tracker the director took is given back.

## 13. UI (`ui/`)

- `Hud` with a registry of `HudWidget`s: interact prompt, status row, checkpoint toast, XP bar,
  ability notice, boss bar (a battle's aggregate bar with its phase notches since P34), quest tracker
  (wrapping steps), tutorial prompt, and since P27 the **compass** (top centre: the tracked objective's
  diamonds, up to three leads, known places, "?" for places near, the pin), the **region banner**
  ("Recommended stage N-M") and the **discovery toast**; the objective marker and threat arrows draw
  over every panel and keep clear of them. Since P27 the HUD is drawn by `HudKit`'s batching rules
  (rectangles and shadowed text in four sizes, no clipping, absolute z layers: about 10 draw calls a
  view instead of about 120; `test_hud_layout` checks the rules), and since W23 it hides while any
  screen is open. The layout test checks every region at five resolutions.
- `ScreenStack` and `UiScreen`s: pause (Settings with the Audio section, Controls), title (the
  skip-prologue choice, the save line by name), shrine (Rest, Grow, Loadout, Attributes, Talents,
  Ancestry tabs; the open tab marked), dialogue (locked choices greyed with their reason), inventory,
  attributes, forge (reinforce, titanforge), end (the prologue's and the campaign's), and since M7
  **map** (`map_screen.gd`: the world's picture or the Valley's vector map, fog by chunk, places by
  what is known, the panel's details, fast travel, pins, level tabs, labels laid out so none overlap),
  **journal** (`journal_screen.gd`: quests with Track, waiting quests, oaths, sealed places, region
  notes), **ancestry** (the one choice) and **yield** (`yield_prompt.gd`: armed only once every button
  has been let go for 0.75 s, a held confirm). A pausing screen pauses the tree and switches input to
  the menu context; `UiNav` wires focus for pad and keyboard; `ScreenStack.HOTKEYS` opens the map (M)
  and the journal (J).
- `InputRouter` (contexts, modifiers, injection for bots and tests) and `InputBindings` (the
  InputMap from data, user overrides, last-device glyphs). `DebugPanel` (F3, debug builds) shows
  state, stage, stamina, attack id, target, frame time, AI state, and every `debug_info_providers`
  node's lines (the audio engine's among them).

## 14. Presentation (`scripts/presentation/`)

- `CameraRig`: third and first person, a collision-swept arm scaled by stage (to 23.5 m at stage 6,
  32 m zoomed), lock framing (a formation's anchor), head culling, the far plane from the level.
- **Rigs**: `ActorRig` and `QuadrupedRig` pose procedurally from the same `AttackGeometry` as the hit
  sweep. Since P22 each rig is one vertex-coloured mesh per animated pivot plus its weapon with one
  material per actor (`SceneKit.merge_rig`), and `RigPaint` paints hit flashes as emission and status
  tints as albedo and runs the distance level of detail: the renderer swaps a rig for its one-box
  proxy beyond its record's `render_lod_m`, and at `low` (P30) for a merged rest-pose mesh from
  0.45 x that distance while the actor is idle. `QuadrupedRig.footfall` drives the paw and hoof steps.
- `CrowdRenderer` (P30): a formation's rank and file as one MultiMesh per pose, members within reach
  or acting promoted to their own rigs (at most six), the banner's flag.
- `HitFeedback`, `TelegraphVisuals` (filling decals, aim lines, a formation's band, a catapult's
  landing circle through the stone's flight, the Moot's stones), `WeaponVisuals` (the stage 4-6
  weapons, the axe, the great pine, the fists), `SceneryFade` with `assets/shaders/scenery_fade.gdshader`
  (trees between the camera and the giant fade, M8 screenshot pass). Materials are flat colours.

## 15. Audio (`scripts/audio/`, `tools/audio/`; P19, P21, P23, P28)

- **`Audio`** (`audio_director.gd`, the last autoload) is presentation only: it listens to `Events`
  and to rig footfalls, reads state in `_process`, never emits a gameplay signal, spends nothing and
  owns its random generators. Enabled, it makes the buses Music, Ambience, SFX and UI at run time (no
  effects), builds the voice pool from `audio_mix.default`, loads the cue catalogue from every
  `audio_bank` record and puts the listener at the giant's chest, turned with the camera. Every
  frame it first passes a mixing barrier (`AudioServer.lock()` and `unlock()`), which closes a race in
  Godot 4.6.3 between a replaced bus-detail block and the mixing thread (P23). `--no-audio` keeps it
  off; the test runner keeps it off unless `--with-audio`.
- **The loading gate**: a level's SFX samples are registered (`AudioServer.register_stream_as_sample`)
  in 12 ms slices behind the loading screen before its first tick, so no `play()` ever registers;
  paused frames run no tick, so a seeded run's timeline is the same with audio on or off.
- **One playback policy for both platforms**: effects are WAV masters imported as QOA, played as
  samples on the web; everything on the Music and Ambience buses, ambience spots included, is Ogg
  Vorbis played as a stream. `VoicePool` holds 24 3D voices (16 on the web), two spot voices and eight
  2D voices, steals by priority and age, and starts at most 16 a frame (8 on the web).
- **`CueRouter`**: one handler per signal of the cue map and per footfall source, each queueing a
  request (the cue's candidates, most specific first: material, voice, size class, surface; the
  position; the source's height) that the autoload drains. `ROUTED_SIGNALS` and `SILENT_SIGNALS` list
  every signal. Distances scale with the giant's height. Threat cues: an attack aimed at the giant
  plays its windup at the attacker, and a broadband sting when the attacker is off camera or far,
  unless its expected damage is under 3 % of the giant's health or its poise ratio sits at the floor;
  a formation's brace plays one wall cue per cycle; an engine's stone a rising whistle at its landing
  circle from launch to landing.
- **`MusicDirector`** plays a set as one deck of stream players started in one frame, bars from the
  lead stem's position; states silent, context (title, end, campaign end, sandbox), zone (the winning
  `audio_region`'s set with explore / danger / combat layers) and boss (intro stinger, phase layers,
  the victory or yield stinger). Intensity weighs threats against the giant's height
  and caps the combat radius at 40 m (`combat_cap_m`) for a giant at least 10 m tall (`combat_cap_min_height_m`: stages 4-6; M9 gate, lane balance), and a hostile crewed engine's landed shot counts as its crew's hit (M9 gate, final round).
  The **`MelodyScheduler`** picks a variant or a rest for each four-bar segment (no variant more
  than twice in a row, no phrase repeated within 60 s) and, after three minutes of quiet exploration,
  a silence window. **`AmbienceDirector`** cross-fades beds by zone, places weighted spots, flushes
  birds at a giant's step and keeps the nearest two emitters. `AudioMath` holds the pure rules.
- **Data**: `audio_bank` (cues: files, bus, class, volume, pitch, caps, far variants, levels),
  `audio_mix` (buses, the pool, classes, ducks, materials, voices, steps, surfaces, intensity, sting
  and threat thresholds), `music_set`, `ambience_set` and `audio_region` (a level's districts, regions
  and places, contexts and bosses; the silent list). Settings: five volumes and "Mute when the window
  loses focus"; on the web a hidden tab mutes.
- **The pipeline** (`tools/audio/`, Python 3 and numpy, seeded, float64, single-threaded; never
  needed to build or play): the synthesis library (`synth/core.py`, `fx.py`, `instruments.py`,
  `voices.py`, `music.py`, `ambience.py`), one generator per family (`gen_<family>.py`: combat,
  abilities, steps, voices, threat, world, ui, music, stingers, ambience, world_music,
  world_ambience, world_sfx), `build_audio.py` (render and check every master, write the WAVs, encode
  the Oggs with libvorbis's bit-exact flags, rewrite `assets/audio/manifest.json`; `--verify`
  regenerates all 441 files and compares every hash; `--budget`; `--masters-out` writes the music and
  ambience masters as FLAC), `encode.py`, `manifest.py` and `test_synth.py`. `tools/check.sh --audio`
  runs the tests and the verification.

## 16. Physics, render and navigation layers; groups

| Physics layer (value) | Name | Used by |
| --- | --- | --- |
| 1 (1) | world | Terrain, walls, cliffs, houses, pillars; occludes attacks, camera and sight |
| 2 (2) | actors | Player, enemies, NPCs, dummies |
| 3 (4) | hurtboxes | Damageable volumes (queried, never collide) |
| 4 (8) | debris | Pooled debris (collides with the world only) |
| 5 (16) | breakables | Intact breakables and siege engines; block movement, attacks and enemy sight |
| 6 (32) | blockers | Invisible movement walls (river banks, bridge rails, the world's bounds); actors only (`ACTOR_MASK` 51) |
| 7-9 (64, 128, 256) | size_gate_4, size_gate_5, size_gate_6 | Size-gate walls; only the giant's body collides with them, and only below their stage (P26) |

Render layer 2 (`first_person_hidden`) holds the head, chest and belt (culled in first person and
when the third-person arm is pressed close) and the tree weapon's canopy. Navigation layers: 1 human
(soldiers and their formations, crews, archers, mages, wolves and dire wolves, civilians), 2 large
(ogres, trolls and whelps, riders), 4 giant (stages 2-3 in the Valley, the Ogre King), 8 small giant
(stage 1, with the Valley's 4 m alleys), 16 titan (the giant at stages 4-6, and at stage 3 in the
world through the level record's `player_nav_fallback`; the Troll Matriarch; the bots) with the titan
gate bits 32 / 64 / 128 (stages 4 / 5 / 6) that the giant's `nav_query_mask` adds by stage; rival
giants and Harrok path on all four titan bits. Groups name
the things systems look for: `player`, `enemies`, `breakables`, `interactables`, `checkpoints`,
`shrines`, `waystones`, `level_root`, `world_root`, `chunk_streamer`, `encounter_director`,
`area_triggers`, `level_markers` and the marker kinds, `ranged_enemies`, `bosses`, `npcs`,
`civilians`, `size_gates`, `siege_engines`, `beacons`, `fire_pits`, `crowd_renderers`,
`level_exits`, `inscriptions`, `screen_stack`, `debug_info_providers`, `scenery`, `boss_arenas`
(every BossArena, BattleBoss and MootArena among them: GameSession's `engaged_fights()`, which holds
checkpoints (M8 release R1), the yield's decision, the boss music's gate cue, the bots),
`battle_bosses` (the boss bar, the music's phase), `discovery`, `wander_director`.

## 17. Scenes and builders

Every scene is generated: `tools/build_scenes.tscn` runs the builders of `tools/builders/` in
dependency order (`player`, `soldier`, `wolf`, `props`, `shrine`, `growth_course`, `test_levels`,
`world_props`, `world_props2`, `ranged`, `test_director`, `forge`, `heavy`, `npcs`, `formations`,
`siege`, `big`, `sandbox`, `valley`, `stress`, `test_world`, `world`, `main`); `-- --only=<names>`
rebuilds a few and `--chunks=` a part of the world. `SceneKit` (`tools/scene_kit.gd`) holds the
palette, the node helpers, the layer constants, `save()` (stable resource ids, so a rebuild changes
only what changed), `merge_meshes` and `merge_rig`. Scenes: the giant, the enemy and NPC scenes (with
pikemen, shieldmen, bannermen, crews, riders, trolls, rival giants and the bosses), the world props,
the siege engines, the sandbox arena, the Valley and its districts, the world's root scene and its
chunks' prop parts, and the test levels (`scenes/test/`: growth course, flow test, ranged playground,
director test, boss arena, village test, stress arena, the streamed test world, the formation and
siege test levels, and P34's troll den, Moot's ring and bailey test).

## 18. Debug tools and the bots (`scripts/debug/`, `tools/`)

- `Autopilot` (`--autoplay=S`, `--scenario=...`): the M1 sandbox soak, and the dispatcher for `stress`
  (12 combatants, 20 breakables, 40 debris; `--stress-formations` for 40 formation members and two
  crewed engines), `valley_walk`, `world_walk` (`WorldWalk`: a route through the streamed world,
  walked or carried at `--walk-speed`, at `--walk-stage`, with `--walk-travel`; the margin to unloaded
  ground, thrash, seams, region changes, path queries), `valley` (the Valley bot) and `world` (the
  world bot). It prints one `AUTOPILOT_RESULT {json}` line; `ErrorCounter` makes any engine or script
  error a non-zero exit.
- **The Valley bot** (`ValleyBot` + `BotCombat` + `RunMetrics` + `BotDiagnosis`, P17a): a goal-driven
  player of the prologue under a village policy, novice or expert, optionally assisted; per-segment
  metrics; watchdogs, the `world_blocked` / `bot_failed` diagnosis and invariants every tick.
- **The world bot** (P38; `WorldBot` extends ValleyBot, `BotRoute`, `WorldMetrics`): plays the campaign
  from `--mode=world --new-game` (or, with `--bot-campaign`, from the Valley's New Game through the
  Kings' Door) to the Stone Throne under a preset (`peaceful`, `conqueror`, `mixed`) or an oath order.
  `BotRoute` plans by A* over the world index's road graph with the edges the giant's stage allows,
  then local `NavQuery` legs of at most 250 m on the titan mask, waiting for chunks that are not ready.
  The bot answers yield prompts through `p34_decide`, fights formations through their lock group,
  breaks and throws engines, uses braziers, rests, refits, spends points by a fixed build, and checks
  the world's invariants every tick (members in unloaded chunks, loaded chunks ≤ 25, regions per layer,
  thrash, events, the save's size; the director's budget rule). P39 added measurement fixes and rules
  of play (`docs/systems/P38.md`, "P39 (W23)")
  and the M9 gate's (`docs/BALANCE_LOG.md`, "M9 gate (lane "balance": ...)", "The bot (measurement
  fixes, plan §3.23)"): each slotted ability the run has not used is tried at the first free tick it
  fits, an engine that shot at the giant in the last 20 s is sought from 90 m, formations off the way
  are passed by, Rampart Grip counts as ready only with something to seize (`73dad1c`); the expert's
  dodge reserve and the lock invariant's rout tick (`36d7938`); a placed member whose AI is off is
  walked past (`41fddb0`),
  which shape the ability and boss numbers it reports.
- `PerfProbe`: CPU per tick, frame and render times, draw calls, nodes and memory, sections by
  district, chunk or region, with budget verdicts (`PERF_RESULT {json}`).
- `tools/`: `gd.sh`, `check.sh` (the definition-of-done sequence: imports, builds, the seam check, the
  audio pipeline, the three tiers, the soak), `run_tests.sh`, `run_bots.sh` (bot batches and presets)
  and `bot_report.py` (their tables), `build_web.sh` (the play link's files, the pck in parts, the
  budget), `pck_files.py`, `release_data_check.gd`, the web checks in `tools/web/` (`audio_check.mjs`,
  `stream_check.mjs` and `world_check.mjs`, each with its stub test, and `world_start_check.mjs`),
  `capture_tour.sh` and `valley_tour.gd` (screenshots)
  `world_tour.gd` with `world_tour.sh` (the world tour beside the world bot, P40: `docs/systems/P40.md`),
  `draw_call_probe.tscn`.

## 19. Tests (`tests/`)

- Three tiers (decision 64): `tests/unit` and `tests/integration` (the default tier: pure objects,
  real scenes, real ticks, real input events; silent; 75 s of wall time), `tests/slow` (only with
  `--slow`; 8 minutes) and `tests/gate` (only with `--gate`: the walkthroughs of every region, every
  order of the oaths, seeded boss runs, the battles' reloads, determinism soaks with and without audio,
  the world bot's smoke run, the living world on the real world; 50 minutes).
  291 suites (55 unit, 154 integration, 53 slow, 29 gate) on the final commit (the final check's RESULT line, `docs/M6_M9_HANDOFF.md` §6.1; the `test_*.gd` files directly in each tier's folder);
  282 at W23 (`docs/systems/P39.md`, "Tests and the full check"; by tier, the suite files at
  `wave-23`, `f851b0d`: 55 unit, 154 integration, 49 slow, 24 gate).
- The runner (`tests/run_tests.tscn`) reseeds `Sim`, runs `ResetHooks` around every test (session,
  quests, record overrides, open screens, the audio engine, the world index cache), turns any logged
  engine or script error into a failure, fails a suite that does not compile, and prints one `TIMES`
  line with each tier's wall time (default, slow, gate). `tests/support/` holds the helpers
  (`TestWait`, `TestSpawn`, `TestFixtures`, `ValleyProbe`, `CrosshairProbe`, the tiny streamed world,
  living-world fixtures, the draw-call probes, the shader rule, the anchor table);
  `tests/fixtures/saves/` holds schema 1 and 2 saves.
- `test_anchors` also compiles every script in the project, because `--import` does not.
  `test_ship_docs` holds the documentation to its rules.

## 20. Adding content

- **An attack or ability:** a record in `data/abilities/` (copy a similar one); add it to the
  progression library and a slot, a weapon's moveset, a growth profile's unlocks or an evolution
  (`evolves_from`, `unlock_stage`). The validator reports what is missing.
- **An enemy:** a record in `data/enemies/` (stats, attacks, AI, tactics, nav layer, `render_lod_m`,
  its voice and step class in `audio_mix.default`), a builder for its scene, and an encounter.
- **A prop:** a record in `data/props/` (with its material in the mix) and a scene from a builder;
  place it in the Valley's layout or a world region's table with a unique `world_id`.
- **A quest stage, dialogue or prompt:** records in `data/quests/`, `data/dialogue/`, `data/tutorial/`;
  markers and triggers in the layout tables.
- **World content:** a region's table in `tools/data/world/` (elements, places, size gates, sealed
  places, caches, cairns, markers), its records in `data/world/` (POIs, encounters with leashes,
  templates, the region's wander table and events), then `tools/check.sh --only=world
  --build-args=--chunks=<chunks>` (the seam check runs after it) and the gate tier's walkthroughs and
  reachability.
- **A sound, a music set or an ambience:** a generator entry in `tools/audio/gen_<family>.py`, then
  `build_audio.py --only=<family>`, the bank or set records in `data/audio/`, and an `audio_region` for
  a new place (or the silent list).
- **The Valley's geometry:** edit `tools/data/valley_layout.json`, then `tools/check.sh --only=valley`.

## 21. Determinism

Fixed ticks, seeded streams, stable iteration and hit order. Run tests and bots with
`--fixed-fps 60` for exact stepping. Headless and `--fixed-fps` runs stream deterministically: a fixed
step quota with synchronous loads, and every navigation map and streamed region with async iterations
off, so a chunk is ready one tick after its last region add (`test_world_determinism` runs two world
walks with AI and requires byte-identical results). The loading gate waits for the samples and the
navigation map, so seeded runs are identical with audio on and off (`test_audio_determinism`,
`test_valley_audio_determinism`). A bot run is repeatable for a seed on one machine, with small
differences across machines (physics), which is why balance is judged over several seeds.

## 22. Where the details are

| Area | System documents (`docs/systems/`) |
| --- | --- |
| The validator registry, GameData, Events, the Sim tick, WorldState (flags, deltas, inventory), the combat core (CombatController, Combatant, CombatEntity, DamageResolver, TargetingRules) and statuses; the actor seams (player components, the enemy base, shared hits, interactables, the HUD registry, test support); the Valley's abilities, projectiles, hostile-only targeting, hotbar and screen stack | P01; P02; P03 |
| SceneKit, the wolf, morale; growth 1-3 and shrines; grabs; props and weapons; archers, mages and readability | P04, P05, P07, P08, P09 |
| Session, saves and checkpoints (M2-M5); the campaign, save schema 2 and migration, travel, the world index, `world_start` | P06; P20 |
| The level framework and director; the Valley | P10a; P10b |
| The Ogre King; civilians and factions; progression; quests and dialogue; performance tools; content; UX and controller | P11a; P11b; P12; P13; P14; P15; P16 |
| The Valley bot and balance; the M5 ship | P17a, P17b; P18 |
| The audio engine (Audio, the loading gate, VoicePool, CueRouter, the directors, the pipeline) | P19 |
| Sound effects (the synthesis library, banks, threat cues) | P21 |
| Merged rigs and the distance LOD; Thornwick; factions by record; the web release without test content; ranged positioning | P22 |
| The Valley's score and ambience, the audio-thread race, the multi-part pack, `audio_check.mjs` | P23 |
| Terrain and streaming (ChunkData, TerrainChunk, ChunkStreamer, WorldRoot, Skyline, the loading screen, the test world, `stream_check.mjs`) | P24a |
| Navigation across chunks (NavBake, NavMaps, NavQuery) and the director in a streamed world | P24b |
| The world builder and geography (layout tables, the library, the index, the map, light content) | P25 |
| Growth 4-6, size gates, trample and heave, the Kings' Door, the Citadel, the vault | P26 |
| Discovery, the tracked quest, the HUD's batching, the compass, the map, the journal, fast travel | P27 |
| World audio (regions, places, bosses, the new creatures' and engines' sounds) | P28 |
| The Crownmarch, settlements and factions by data, `OathRules`, beacons, the formation fights | P29 |
| Formations, the target provider, group lock, the crowd renderer | P30 |
| Stage movesets, evolutions, talent and ancestry abilities, the axe, the great pine, titanforging | P31 |
| Siege engines, crews, cavalry, the size override, siege disruption, Rampart Grip, the fists | P32 |
| Talents and ancestries | P33 |
| Trolls, rival giants, the three bosses, BattleBoss, the yield protocol, the disengage rule | P34 |
| The Greywood and the Drowned Steps (NarrowPass and the Needle, BroodNest, DenWall, RewardRack, ForgeFire, GreatPineTree) | P35 |
| Aldmere, the Stonehold and the finale (FortBattle, MootArena, the siege of Skarn, ConditionForge, ConditionSpawn, RebuildPoint, the Stone Throne) | P36 |
| The living world (templates, the WanderDirector, world events, columns) | P37 |
| The world bot (BotRoute, WorldBot, WorldMetrics, invariants, the acceptance runs) | P38 |
| Stability, balance and the report; the M9 confirmation | P39 |
| The W23 fixes and polish (the HUD and map, raiders, the world rebuilt, placed fights, the web world check) | P39f |
| The M9 ship (the final check, the world tour, the exports and web checks, these documents) | P40 |
| The gate reviews' fixes | `DECISIONS.md` §3.2 in short; the detail in the M6 gate's inline "M6 gate" notes (P04, P17b, P19, P21, P23), each package's "M7 gate", "M7 polish", "M8 gate", "M8 screenshot pass" and "M8 release" sections, and the M9 gate's sections: `docs/systems/P39.md`, "The M9 gate (lane aldmere)", "The M9 gate (lane ironreg)", "M9 gate (lane "balance")", "M9 gate (integration)", "M9 gate (catch-up)", "M9 gate (final)" and "M9 gate (the final round)", and `docs/systems/P39f.md`, "M9 gate (lane review)" |
