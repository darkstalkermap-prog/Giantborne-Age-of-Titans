# Architecture

How the build is put together: the layers, the autoloads and the simulation tick, each area of the
game - the combat core, the giant, the enemies, the two campaign levels and the streamed world, the
world builder, quests, the campaign and its saves, bosses, the living world, the UI, presentation and
audio - and the tools, the bots and the tests, since M10 the realistic giant and the character
creator (§23), since M11's first part the giant refined: his motion, hair, skin and eyes (§24), and since
M11's second part more customization: the look's record v2, clothing and armour by slot, the creator II,
the catalogue II and the reproportioned body (§25), and since M11's third part realistic people and creatures:
the people pipeline, `PersonRig` and the crowd, the riders, the rival giants on the giant's body, the brutes and
the wolves (§26). It
consolidates the system documents of the M2-M5
packages (`docs/systems/P01.md` ... `P18.md`), the M6-M9 packages (`P19.md` ...
`P40.md`), the M10 packages (`P41.md` ... `P46.md`), M11's Part A (`P48.md` ... `P51.md`), Part B
(`P53.md` ... `P57.md`, the W33 lanes `W33look.md` ... `W33look5.md` and `W33body.md`, `GATE_B.md`) and Part C
(`P59.md` ... `P65d.md`, Gate C's lanes `P64c.md` and `P65d.md`), which keep
every public API and detail; §22 says which document holds what. The interpretations behind it are in
[DECISIONS.md](DECISIONS.md) (decisions 1-30 from the M2-M5 plan, 31-64 from the M6-M9 plan, 65-85
from the M10 plan, 86-106 from the M11 plan).

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
       Events (91 signals: hits, deaths, telegraphs, quests, saves, screens, travel, regions, formations, ...)
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
| `PlayerAppearance` (M10, P42) | The giant's look: the character's record, else the `--appearance=` preset, else the default; `set_record` (the creator's Keep: applies it and emits `appearance_changed`), `restore_record` (Cancel), the line's mark on `ancestry_chosen`. It has no simulation hook (§23.8) |

Growth profiles 1-6 are data (3.66 / 5.49 / 7.92 / 10.97 / 14.63 / 18.90 m). Each profile names the
size-gate layers its body still collides with (`size_gate_mask`) and the titan navigation bits its
paths may use (`nav_query_mask`), and the interaction permissions it grants (stage 4 `trample`, 5
`formation_sweep` and `heave`, 6 `siege_disruption`). `apply_character_state` /
`capture_character_state` move the whole character (stage, level, XP, attributes, talents, ancestry,
loadout, weapons, resources, and since M10 the look when it has one) in and out of the save document.
Since M10 the giant's body is the realistic skinned model (§23); every gameplay shape named here - the
capsule, the hurtboxes, the lock anchor, the attack origin, the grab sockets, the camera's geometry -
is unchanged, and a growth still scales `Visual/Body` uniformly.

## 6. Enemies, NPCs and factions (`scripts/actors/`, `scripts/ai/`)

- `EnemyActor` (a `CharacterBody3D`) senses, moves (navigation through `NavQuery` on the record's
  layer, scripted lunges and charges), runs its `AttackRunner`, announces telegraphs, takes attack
  tokens (2 melee, 2 ranged per target), switches AI LOD tiers (tier 2 sleeps behind a one-box
  proxy), handles morale, flight and rout, grabs, the leash return (round a body in its way since
  W23; outside its leash a return never ends early: it waits off the body on its post and answers a blow (M9 gate, `docs/systems/P39f.md`, "M9 gate (lane review)"); a ranged member's firing points stay inside its leash and only a hostile holder keeps a member off it: M9 gate, final round; since W32 a return held pressed into a giant's body - within `LEASH_CONTACT_M`, 0.05 m, of it - for `LEASH_CONTACT_WAY_S`, 1 s, begins its wait at once instead of at its second path failure, a gameplay change kept at Gate B: `DECISIONS.md` §3.6),
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
- **Save schema 3** (A4; `SaveSlots.SCHEMA_VERSION` 3): `_migrate_2_to_3` adds the expansion's own fields
  (`ExpansionState`, `scripts/core/expansion_state.gd`): `act`, `titans` (each signature titan's state, best
  plates broken, kills, first sighting and drops), `equipment` (the seven armour slots milestone B fills, all
  empty), `settlements` (each settlement's development; today the world flags it mirrors) and
  `cinematics_seen`, filled from the flags A3 wrote, which stay. `GameSession.expansion` is the live copy
  (snapshots write it, a Continue and a checkpoint reload read it); each key is optional in `validate` and a
  titan this build does not know is dropped. A schema 4 file is refused and kept aside as every newer one.
- **The look** (M10, P42) is the optional `character.appearance`, with a version of its own; schema 2
  is kept, an absent key is the default look, and a repaired look adds its notes to the load message
  (§23.8). A look kept at a shrine is a shrine choice (the F15 list), so its checkpoint is taken again
  at once.
- Every mode change, reset, reload and travel is a reload of `scenes/main.tscn`; `main.gd` builds the
  level with the tree paused, holds it behind "Loading... N%" until the audio has registered the
  level's samples, the navigation map has synced and, in the world, the starting ring is ready (at
  most 8 s, then a warning), then calls `GameSession.on_level_ready`. Since the M10 gate the gate ends
  with `hold_until_drawn`: with a display the camera is put on the giant (`frame_camera_on_player`) and
  the finished level drawn three times behind "Loading..." with the tree still paused, so the first
  frame of play after a Continue does not draw the giant's surroundings for the first time (no tick
  passes: a seeded run is the same; headless nothing waits).

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
  skip-prologue choice, the save line by name; since M10 every New Game path opens the creator, and
  with a display a warm-up draws the giant once behind "Preparing..."), shrine (Rest, Grow, Loadout,
  Attributes, Talents, Ancestry and, since M10, Appearance tabs; the open tab marked), **creator**
  (`CreatorScreen`, M10: §23.7), dialogue (locked choices greyed with their reason), inventory,
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
  32 m zoomed), lock framing (a formation's anchor), head culling, the far plane from the level. Since
  M10 its cull masks follow the realistic giant's three render layers (§16, §23.2); its geometry is
  unchanged.
- **Rigs**: `ActorRig` and `QuadrupedRig` pose procedurally from the same `AttackGeometry` as the hit
  sweep. Since M10 the player's rig is `SkinnedRig`, an `ActorRig` whose pose brain drives the
  realistic skinned body (§23.4; since M11 with more sources for the legs, flinches, secondary motion
  and the eyes' look, §24.3-§24.5): the brain's pivots stay, without meshes. Every other actor keeps
  the stylized rig described here. Since P22 each rig is one vertex-coloured mesh per animated pivot plus its weapon with one
  material per actor (`SceneKit.merge_rig`), and `RigPaint` paints hit flashes as emission and status
  tints as albedo and runs the distance level of detail: the renderer swaps a rig for its one-box
  proxy beyond its record's `render_lod_m`, and at `low` (P30) for a merged rest-pose mesh from
  0.45 x that distance while the actor is idle. `QuadrupedRig.footfall` drives the paw and hoof steps.
- `CrowdRenderer` (P30): a formation's rank and file as one MultiMesh per pose, members within reach
  or acting promoted to their own rigs (at most six), the banner's flag.
- `HitFeedback`, `TelegraphVisuals` (filling decals, aim lines, a formation's band, a catapult's
  landing circle through the stone's flight, the Moot's stones), `WeaponVisuals` (the stage 4-6
  weapons, the axe, the great pine, the fists), `SceneryFade` with `assets/shaders/scenery_fade.gdshader`
  (trees between the camera and the giant fade, M8 screenshot pass). Materials are flat colours, but
  for the giant's (`GiantLook` and the four `giant_*` shaders, §23.3).

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

Render layers of the giant since M10 (plan M10 decision 8; before it, layer 2 `first_person_hidden`
held the head, chest and belt and the tree weapon's canopy): layer 1 the limbs and the garments' limb
parts, layer 2 (`CameraRig.TORSO_LAYER`) the torso and the garments' core parts, layer 3
(`HEAD_LAYER`) the head, the eyes, the hair and the beard, and the tree's canopy and the pine's
needles. First person culls layers 2 and 3 (`CULL_FIRST_PERSON`); third person with the arm pressed
close culls layer 3 only (`CULL_NO_HEAD`; `PRESSED_CULLS_TORSO` is false, decided on a render of the
growth course's low passage). Since M11 the giant's shadow proxy (shadows only) is on layer 1, because the
renderer culls shadow casters by the camera's mask too and first person must keep the body's shadow; and
first person no longer draws the legs (a shader discard by body region, §24.6), though their layer stays
1. Navigation layers: 1 human
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
dependency order (`giant_model` (M10: the realistic model and its index, from `assets/giant/`), `player`, `soldier`, `wolf`, `props`, `shrine`, `growth_course`, `test_levels`,
`world_props`, `world_props2`, `ranged`, `test_director`, `forge`, `heavy`, `npcs`, `formations`,
`siege`, `big`, `sandbox`, `valley`, `stress`, `test_world`, `world`, `main`); `-- --only=<names>`
rebuilds a few and `--chunks=` a part of the world. `SceneKit` (`tools/scene_kit.gd`) holds the
palette, the node helpers, the layer constants, `save()` (stable resource ids, so a rebuild changes
only what changed), `merge_meshes` and `merge_rig`. Scenes: the giant (`scenes/player/giant.tscn`, which since M10 instances
`scenes/player/giant_model.tscn` with its edit state, so the saved scene keeps the instance alone), the enemy and NPC scenes (with
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
- **M10's tools**: `tools/giant/` (the asset pipeline, §23.1); `check.sh --giant`, `--giant-full`,
  `--require` (a skipped check fails) and `--strict-times` (a tier over its budget runs once more and
  the faster run decides); `tools/giant_suites.py` (the suites that load the giant and their time in
  a test log); `CaptureM10` (`--scenario=capture_m10`: the skinned giant through 38 beats, one frame
  each, P43); `--skin-stats` (a `SKIN_STATS {json}` line beside `AUTOPILOT_RESULT`: what the skinned
  layers ran); `UiProbe` (`scripts/debug/ui_probe.gd`, made only with `--ui-probe`: `UI_PROBE` state,
  stall and bench lines for the web checks, and the native tours `new_game`, `shrine`, `level` and
  `continue`, P45); `tools/character_sheet.tscn` (the owner's sheets, P44); the fifth web check
  `tools/web/creator_check.mjs` with its stub test, and `tools/web/memory_guard.mjs`, which stops any
  of the five checks when its page's renderer passes 3,072 MB (the M10 gate);
  `tools/pck_files.py --giant-share` and `build_web.sh`'s `GIANT_SHARE` line and `--version=`.

## 19. Tests (`tests/`)

- Three tiers (decision 64): `tests/unit` and `tests/integration` (the default tier: pure objects,
  real scenes, real ticks, real input events; silent; 75 s of wall time), `tests/slow` (only with
  `--slow`; 8 minutes) and `tests/gate` (only with `--gate`: the walkthroughs of every region, every
  order of the oaths, seeded boss runs, the battles' reloads, determinism soaks with and without audio,
  the world bot's smoke run, the living world on the real world; 50 minutes).
  330 suites (62 unit, 163 integration, 73 slow, 32 gate) on the M10 gate's code (`m10-gate`; the gate merge's check, `docs/M10_HANDOFF.md` §6.1; the `test_*.gd` files directly in each tier's folder);
  291 suites (55 unit, 154 integration, 53 slow, 29 gate) on the `0.9.0-m9` release (`docs/M6_M9_HANDOFF.md` §6.1);
  282 at W23 (`docs/systems/P39.md`, "Tests and the full check"; by tier, the suite files at
  `wave-23`, `f851b0d`: 55 unit, 154 integration, 49 slow, 24 gate).
- The runner (`tests/run_tests.tscn`) reseeds `Sim`, runs `ResetHooks` around every test (session,
  quests, record overrides, open screens, the audio engine, the world index cache), turns any logged
  engine or script error into a failure, fails a suite that does not compile, and prints one `TIMES`
  line with each tier's wall time (default, slow, gate). `tests/support/` holds the helpers
  (`TestWait`, `TestSpawn`, `TestFixtures`, `ValleyProbe`, `CrosshairProbe`, the tiny streamed world,
  living-world fixtures, the draw-call probes, the shader rule, the anchor table);
  `tests/fixtures/saves/` holds schema 1 and 2 saves.
- `test_anchors` checks the package anchors; since A2 the slow tier's `test_scripts_compile` compiles every script in
  the project, because `--import` does not (it was 14-16 s of the default tier); A2 also moved five default suites to
  the slow tier and two slow ones to the gate to keep the budgets (`docs/systems/A2.md`, "Tests").
  `test_ship_docs` holds the documentation to its rules.
- M10's rendered suites draw the real giant under `xvfb-run` and skip with a note without it
  (a failure with `check.sh --require`): the shaders (`test_giant_shaders`), the option check
  (`test_appearance_render`: 176 tiles, every option of the catalogue above its set's floor, every
  design category readable from behind or in first person), the skinned rig's frames
  (`test_skinned_rig_render`, gate `test_skinned_rig_stages`) and first person looking down
  (`test_first_person_shoulders`). The gate's `test_giant_determinism` proves that the skin and the
  look never reach the simulation (§21), `test_skin_rules` and `test_appearance_rules` hold the code
  rules behind it, and `test_predeclared_m10` the M10 registries and anchors.

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
- **A look option** (M10): a colour or a cut is data alone - an option in a `data/appearance/set_*.json`
  (a palette's `#rrggbb`; a hair or beard option's `length` over an existing mesh), a preset a
  `data/appearance/preset_*.json`. A new hair or beard style, garment or design is drawn by the kit
  (`tools/giant/kit/giant_hair.py` `STYLES`, `giant_garment.py`, `designs.py`), regenerated with
  `build_giant.py --hair`, `--garments` or `--designs` (seconds; the manifest and the index follow),
  then `tools/check.sh --only=giant_model --giant` and the option naming its mesh, garment or design
  id; `test_giant_look_real` lists any id the data names and the index lacks, and the rendered option
  check (`tests/slow/test_appearance_render.gd`) holds its floor. The body mesh, the skeleton, the
  regions and the landmarks are frozen (decision 73).

## 21. Determinism

Fixed ticks, seeded streams, stable iteration and hit order. Run tests and bots with
`--fixed-fps 60` for exact stepping. Headless and `--fixed-fps` runs stream deterministically: a fixed
step quota with synchronous loads, and every navigation map and streamed region with async iterations
off, so a chunk is ready one tick after its last region add (`test_world_determinism` runs two world
walks with AI and requires byte-identical results). The loading gate waits for the samples and the
navigation map, so seeded runs are identical with audio on and off (`test_audio_determinism`,
`test_valley_audio_determinism`). A bot run is repeatable for a seed on one machine, with small
differences across machines (physics), which is why balance is judged over several seeds.
The realistic giant is outside all of it (M10, decisions 68-70): the skinned layers and the look
write only under `Visual/Body` (and a held body's `Visual` offset), draw no number from `Sim.rng` and
emit no event the simulation hears. The gate's `test_giant_determinism` runs three seeded 120 s soaks
(no skin; the skin with one look; with another) and a seeded Valley bot run that grabs and throws
with and without the skin, and requires byte-identical results, with positive controls in
`SKIN_STATS` that the skin and the look really ran; the M10 gate also found the soak's result
byte-identical on `0.9.0-m9` and on the candidate, and the world bot's smoke run identical once
wall-time, node-count and memory fields are removed (`docs/M10_HANDOFF.md` §5.1).

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
| M10: the giant's asset pipeline (the venv, the vendored CC0 subset and its audit, the kit, the export, the bakes, the designs, the pack, the manifest, `--verify`, `--budget`), `GiantModel` and its index | P41 |
| M10: the look - `Appearance` (the record, sanitize, `to_look`, Randomize), the appearance data and schemas, the saves, `PlayerAppearance`, the session's `--appearance=` and `--creator`, the four giant shaders, `GiantLook`, `TipMatching`, the M10 pre-declarations | P42 |
| M10: the skinned giant - the clips, `SkinnedRig`, `PoseBrainModifier`, the player's scene, the camera's layers, the capture tour, the determinism gate | P43 |
| M10: the creator - `CreatorScreen`, `OptionRows`, `GiantPreview`, the title's flows and warm-up, the shrine's Appearance tab, the rendered option check, the character sheets | P44 |
| M10: the Web build at 26 MB with the 1024 px maps, the launcher's world start, `UiProbe`, `creator_check.mjs`, the stall and memory measures | P45 |
| M10: the look pass - the hair's second pass, the cut and the sway, the target catalogue's styles, designs, garments and presets, the second scar layer | P46 |
| M11: the body pipeline II - leaf bones and the cards' weights, build weights, the grip and side landmarks, parts on demand, the shadow proxy, the free cape, the clips II, the freeze test | P48 |
| M11: the Web, tools and performance debts - the launcher's one-stream unpacking, the staged budgets and `PEOPLE_SHARE`, the shadow proxy's path in `RigPaint`, reproducible exports, the checks' flakiness, the starved browser's memory, the preview's warm-up on `--continue`, the Part A pre-declarations and headroom | P49 |
| M11: the giant's motion - the grip through the fist, the legs' new sources, flinches, `SecondaryMotion`, the reach past a weapon's fit stage, first person, `capture_m11.gd`; Gate A (the skin's CPU, the arms' limit, the eyes' look) and Gate A2 (the flinches, first person's rest and legs) | P50 |
| M11: the look pass II - hair shading, shells, braids as tubes, loose strands, the skin's grade and subsurface lookup with its curvature map, the eyes, scars and cloth; Gate A (the skin in the world's light, the proxy's layer, the cloth's rim) and Gate A2 (the shells in the world's light) | P51 |
| M11: the look record v2 - `Appearance` at `v` 2 (slots, accessories, dyes by material, build and face sliders, beads), `migrate` and `sanitize`, the M10 oracle, `GiantLook` by slot (garments as `{mesh, dye, kind}`, the build push, face keys), the shadow proxy's push, the migration note and its flag | P53 |
| M11: the wardrobe - the slots' shells and layering, 25 garments and 8 accessories as parts, 12 outfits and 14 dyes, the index v2, the layering and z-fighting checks | P54 |
| M11: the creator II - eleven categories, slot rows, `OptionGrid` (pages, the name filter, material buttons), `ThumbnailCache`, signed sliders, Randomize by slot, the pad's steps | P55 |
| M11: the catalogue II - nine hair and beard styles, beads by anchor, the four new scars and other designs, the six face keys, the fourteen presets | P56 |
| M11: Web and performance for the wardrobe - the look's skip-unchanged plan, names instead of pictures on the Web, the creator's first frame, the pad's row jumps, the tour's part B, the wardrobe sheet, the stack check | P57 |
| M11: the five look lanes before and after checkpoint B (layering by what is worn, mail and scale, far levels, trophies and rings, skirts and braies, paint and scars, cloaks, beards, the crop, dyes) | `W33look.md` ... `W33look5.md` |
| M11: the body's proportions (checkpoint B, decision 4) and the creator's framings on the new body | `W33body.md` (with its "W33frame" section) |
| M11: the people pipeline - the 23 bones, a person from the CC0 data, the outfit, the cull, the merge, the decimation and the atlas, the variants, the crowd poses and far meshes, the clips, the gear, the manifest, `--verify`, `--budget`; the first look pass | P59, P59b |
| M11: `PersonRig`, `PersonLook`, `PersonModel`, the person shaders, the crowd renderer, the soldiers, `PEOPLE_STATS` | P60 |
| M11: the quadruped kit and the horse; the rival giants' garments and looks | P61 |
| M11: the townsfolk and the named characters, `SkinnedQuadrupedRig` and the rider, the rival giant and Harrok on `SkinnedRig` | P62 |
| M11: the brutes (ogre, troll, whelp, the bosses' gear) and the wolf with its fur | P63 |
| M11: `BruteRig`, `SkinnedWolfRig` and the fur shell, `CreatureSlots`, the people's warm-up, `people_check.mjs`, the people sheet; the creatures' cost, the brutes' sweep, the gallop, the rider's fall, the tour's part C | P64, P64b |
| M11: the people's and creatures' look passes (the wolf, the brutes, the saddle cloth, the faces, the gallop, the rival giants, the women and the elders, the mail, the grips, the faction colours at 60 m) | P65a, P65b, P65c, P65d |
| The M11 Gate C fixes (the poses keyed on the action, the dead, the held and the thrown; the assets) | `DECISIONS.md` §3.7 in short; the detail in `docs/systems/P64c.md` and `P65d.md` |
| M11: the 0.13.0-m13 release | P66 |
| The M11 Gate B fixes | `DECISIONS.md` §3.6 in short; the detail in `docs/systems/GATE_B.md` |
| The M11 Gate A and Gate A2 fixes | `DECISIONS.md` §3.5 in short; the detail in `docs/systems/P50.md` and `P51.md`, "Gate A" and "Gate A2", and `docs/PERFORMANCE.md`, "M11 Gate A: the merged measurements" |
| The M10 gate's fixes | `DECISIONS.md` §3.3 and §3.4 in short; the detail in `docs/systems/P44.md`, "The M10 gate's fixes (lane ui)", `docs/systems/P46.md`, "The M10 gate (lane look)", `docs/systems/P43.md` and `P45.md`, "After the M10 gate (lane web)", and `docs/PERFORMANCE.md`, "The M10 gate, lane web" |
| The gate reviews' fixes | `DECISIONS.md` §3.2 in short; the detail in the M6 gate's inline "M6 gate" notes (P04, P17b, P19, P21, P23), each package's "M7 gate", "M7 polish", "M8 gate", "M8 screenshot pass" and "M8 release" sections, and the M9 gate's sections: `docs/systems/P39.md`, "The M9 gate (lane aldmere)", "The M9 gate (lane ironreg)", "M9 gate (lane "balance")", "M9 gate (integration)", "M9 gate (catch-up)", "M9 gate (final)" and "M9 gate (the final round)", and `docs/systems/P39f.md`, "M9 gate (lane review)" |

## 23. The realistic giant and the character creator (M10; P41-P46)

The player's giant is a skinned, textured body generated from CC0 data, driven by the same pose brain
as before, with a look the player chooses. It is presentation only: nothing in §2-§12 reads it
(decisions 68-70, §21). This section describes it as M10 built it, revised where M11's first part
changed a contract; §24 describes what M11 added (the parts, the bones and the motion, the hair, the
skin and the eyes). The pieces, in the order the data flows:

```
tools/giant/mpfb2 (CC0 data) ─► tools/giant/kit (bpy, numpy) ─► assets/giant/*.glb, *.png + manifest.json (the index)
                                                                        │
   tools/builders/giant_model.gd ─► scenes/player/giant_model.tscn (GiantModel + index) ─► giant.tscn (Visual/Body/Model)
                                                                        │
 data/appearance/*.json ─► Appearance (record ─► sanitize ─► to_look) ─► GiantLook (materials, uniforms, visibility)
        ▲                          ▲                                    │
 CreatorScreen ─ OptionRows        PlayerAppearance ◄─ character.appearance (the save)
        │                                                               │
 GiantPreview (own world)      ActorRig's pose brain ─► SkinnedRig (clips, AnimationTree) ─► PoseBrainModifier (TipMatching)
```

### 23.1 The asset pipeline (`tools/giant/`, P41; offline, not exported)

- **The toolchain** lives outside every worktree, in one venv all worktrees share: `GIANT_VENV` (fifteen
  pinned wheels with their sha256 in `tools/giant/requirements.txt`, installed by `setup_venv.sh`:
  Blender 5.3 as the `bpy` 5.3.0 module on Python 3.13, numpy, scipy, Pillow, OpenEXR) and
  `GIANT_CACHE` (the bake cache, keyed by a hash of each bake group's inputs, and the audited data
  wheel). Neither is needed to build, export or play the game.
- **The inputs** are `tools/giant/mpfb2/`: 133 files (137 since M11's four build targets, §24.1) of MakeHuman/MPFB2 data under CC0 - the hm08 base
  mesh, 122 morph targets, the modifier table, the "game_engine" rig and its weights, six region mask
  images, the licence - copied as data from one wheel, with `FILES.sha256` and `SOURCE.md`;
  `fetch_mpfb2.py` audits the copy against the wheel. An empty `.gdignore` keeps Godot's importer out
  of the folder, and `test_ship_docs` skips it. Nothing else enters the pipeline, and the kit's code is
  the project's own (`assets/giant/PROVENANCE.md`, `CREDITS.md`).
- **The kit** (`tools/giant/kit/`): `mh_data` (the MakeHuman formats), `giant_body` (the morphed body at
  the stage-1 height of 3.6576 m on the rig, its masks and landmarks), `split` (the three body parts,
  the 16 regions, the cut loops and their caps), `giant_garment` (ten garments as shells cut from the
  body by bone-weight regions), `giant_hair` (strand growth and cards for five hair and four beard
  meshes, braids as cards, the hairline's fringe), `giant_skin` and `skin_textures` (the procedural
  skin the bakes read), `export_game` (the glTF), `bake` (Cycles, 1024 px, seed 0, two threads: the
  cheap passes - albedo at a neutral tone, roughness, tangent normal, masks, the region map, the rest
  position and normal - and the expensive ones, AO and thickness), `designs` (tattoos, war paint,
  scars and marks as distance fields in 3D on the rest pose, quantized to the S3TC block's levels),
  `pack` (the two texture tiers, the hair atlas, three tileable cloth detail maps) and `clips` (§23.6).
- **`build_giant.py`** runs the steps (`--body`, `--garments`, `--hair`, `--bake`, `--designs`, `--pack`,
  `--clips`, `--all`), writes each output's `.import` settings and records everything in
  **`assets/giant/manifest.json`**: for each of the 13 generated files (38 since M11: the 21 part files and
  four more maps, §24.1) its step, the hash of that step's
  inputs, its sha256 and size and whether Cycles pixels reach it; the toolchain (versions and a CPU
  fingerprint); the hashes of the vendored files and the kit's sources; the bake settings; the clips'
  measurements; the body's hash; and **the giant index** (§23.2). `--verify` regenerates every file
  into a temporary folder and compares it with the manifest and the committed files: bit-exact on the
  reference toolchain but for the bake's own jitter (a Cycles map may differ in at most 64 texels by
  1/255: `TOLERATED`), a stated tolerance for Cycles pixels on another CPU, and `TOOLCHAIN DIFFERS`
  kept apart from `CONTENT DIFFERS` and `SHIPPED FILE`. It never reads the bake cache. `--skip-bake`
  re-bakes the cheap passes and reads AO and thickness back from the committed `tex_hi/orm.png`, so any
  fresh worktree verifies in about a minute; `--budget` estimates the giant's share of the Web pack.
  `tools/check.sh --giant` runs the pipeline's own tests, `--verify --skip-bake` and `--budget`;
  `--giant-full` verifies with every bake pass.
- **The outputs** (`assets/giant/`, generated and committed, never edited by hand): `giant.glb` (every
  mesh on one 53-bone skeleton, imported with LODs, shadow meshes and tangents), `giant_clips.glb` (an
  animation library), `tex/` (albedo, normal, ORM and masks at 512 px), `tex_hi/` (normal and ORM at
  1024 px), `designs.png` (six 512 px RGBA layers stacked, imported as a 2D texture array),
  `hair_atlas.png` and `cloth_weave.png`, `cloth_leather.png`, `cloth_fur.png` (128 px), all
  VRAM-compressed with mipmaps. **The body mesh, the skeleton, the region ids and the landmarks were
  frozen in W25** (decision 73) and **unfrozen once in M11's W29** (decision 91): 18 leaf bones, build
  weights, more landmarks and the parts were added, while the body's positions, UVs, region ids and
  weights, its 53 bones and M10's clips stay bit-identical, which `tools/giant/freeze.py` proves at every
  regeneration (§24.1). Hair, garments, designs, clips and textures regenerate freely.

### 23.2 `GiantModel` and the index (`scripts/presentation/giant_model.gd`, P41)

`scenes/player/giant_model.tscn` is a `GiantModel` root holding the glTF instance, turned 180° about Y
(the glTF faces +Z, every actor faces -Z), and the exported **index**, a dictionary copied from the
manifest by the model's builder. A scene saved by SceneKit keeps nothing set inside an instance, so
`_ready()` applies every mesh's render layer and the default visibility from the index and joins the
group `giant_models`.

- **The index**: `meshes` (25: `Body_Head`, `Body_Torso`, `Body_Limbs`, `Eyes`, five hair and four
  beard meshes, twelve garment meshes; since M11 the hair, beard and garment meshes are parts loaded on
  demand, with `part_path` and their spring `chains`, §24.1; each with its node, category, render layer, triangle count,
  and for garments the dye slot, the detail kind, the body regions it `covers` and its `coverage` per
  region), `garments` (ten; the braies and the tunic are a `_core` and a `_limbs` mesh each), `designs`
  (29: 16 tattoos, 4 war paints, 6 scars, 3 ancestry marks, each a layer and a channel of the array),
  `regions` (16 body regions), `design_regions` (face, chest, back, arms), `landmarks` (the joints and
  the two reaches at stage 1), `defaults.shown`, `tiers` and `textures`.
- **The meshes**: the body is three meshes cut at the neck, the shoulders and the hips - the head on
  render layer 3 with the eyes, the hair and the beard, the torso on layer 2 with the garments' core
  parts, the limbs on layer 1 - and every cut loop is capped on both sides, so no limb is hollow from
  inside (§16 has the camera's masks). A vertex's region id rides in its colour (`COLOR.r x 16`), which
  is how one skin shader picks a design per region and sinks the skin under a garment.
- `skeleton()`, `mesh(id)`, `meshes(category)`, `landmarks()`, `hand_transform(right)`, `pose_relaxed()`,
  `pose_rest()` and `play_idle()` (a run-time `AnimationPlayer` looping the idle clip on a model that
  stands by itself, the creator's preview; never on the player's model, which has the rig's tree).

### 23.3 `GiantLook` and the shaders (`scripts/presentation/giant_look.gd`, `assets/shaders/giant_*.gdshader`; P42, P46)

`GiantLook` is static and stateless but for a texture cache: it turns a *look* (the dictionary
`Appearance.to_look` returns: colours as values, mesh, garment and design ids) into materials, uniforms
and visibility on one model.

- `build_materials(root, index, tier)`: one `ShaderMaterial` per mesh and per instance, never shared
  (so two giants, or a giant and the creator's preview, never paint each other), of its category's
  shader, with the tier's textures. Tiers: "web" (the 512 px maps), "hi" (the 1024 px normal and ORM,
  each falling back to the 512 px file when missing) and "auto" (hi when `tex_hi/normal.png` is in the
  pack); `--giant-tier=web|hi` forces one. Materials are built only where something is drawn.
- `apply(root, index, look)` shows the look's hair, beard and garment meshes, hides the others and
  sets every uniform; headless it only sets visibility and stores the look. `validate()` lists unknown
  ids, a sampler whose texture did not load and every uniform name the shader does not declare (a
  headless material stores a misspelled name without complaint), and never raises an engine error.
- **`giant_skin`**: the baked albedo scaled by the chosen tone against `bake_tone` (the default tone,
  so the default look draws the albedo as baked: the M10 gate's OR-1), normal, ORM and mask maps; the
  hair's colour on stubble, scalp and brows; the **design array** (`sampler2DArray`) read through three
  16-entry region tables (`region_tattoo`, `region_paint`, `region_mark`: a layer and a channel for each
  body region, 0 for none) with ink, paint and mark colours and the mark's glow; scars on two layers
  of their own; `hidden_regions`, a bitmask of regions that sink under the garment covering them; wrap
  lighting with a thickness-driven transmission term in place of subsurface scattering.
- **`giant_hair`** (cards, depth pre-pass, both faces): the strand atlas, colour, lighter tips, grey,
  `length` (a cut of the same mesh: an option can ship a shorter style at no pack cost), feathered
  sides and roots, softened card-on-card shadow, `tip_thin` on the full and the forked beard,
  `back_fade` (a beard fades out as the camera comes round behind the head) and `head_motion`:
  `GiantLook.sway` eases the head bone's motion each drawn frame and lags the cards' tips by at most
  0.09 m at stage 1, a shader offset and not physics.
- **`giant_eye`** (procedural iris, colour and glow) and **`giant_cloth`** (a detail map per kind -
  weave, leather, fur - two dyes, and a screen-door `fade` the creator uses to show what a garment
  hides). Every giant shader declares `tint` and `flash`, which `RigPaint.paint_shaders` drives, so hit
  flashes and status tints reach the realistic body as they reach every other rig.
- **`giant_first_person.gdshaderinc`** (the M10 gate's LC-3), included by the skin and the cloth: while
  the camera stands inside the head, limb fragments inside a box round the shoulders are discarded with
  a dithered edge, so first person looking down never shows the arms' shoulder caps. The box is fixed
  in the model's own space, so it is the same at every stage; a shadow pass keeps the shoulders. Since
  M11 it also discards the pelvis, the legs, the feet and the caps by body region (§24.6), and the skin's
  `light()` reads a subsurface lookup (§24.5).

### 23.4 `SkinnedRig` and `PoseBrainModifier` on the pose brain (`scripts/presentation/`, P43)

The pose brain did not change: `ActorRig._process` still computes every pose of the player on the
frame clock, and its stylized pivots (`HipL`, `HipR`, `Torso`, `ShoulderL`, `ShoulderR` and their
`Hand` markers) stay in `Visual/Body`, without meshes. `SkinnedRig extends ActorRig` is `Visual`'s
script, so every `is ActorRig` reader, the footfall audio and the camera shake work as before; it adds
the realistic body beside the pivots: `Visual/Body/Model` (the `GiantModel`) and
`Visual/Body/WeaponSocket`.

- **Where the layers run** (decision 70): with a display, with `--skin`, or after
  `SkinnedRig.enable_for_tests()`; never with `--no-skin`. Headless (the default test tier, the bots)
  the run-time nodes are not made, the skeleton rests, `GiantLook` only shows and hides meshes and the
  weapon hangs at the brain's hand, so node paths exist everywhere and nothing is paid for.
- **The run-time nodes** (never saved): an `AnimationPlayer` with the clip library, an `AnimationTree`
  whose blend tree is built in code and advanced by hand from the rig's `_process`, and the
  `PoseBrainModifier` under the skeleton.
- **The legs** come from the clips, chosen by what the brain is doing, in this order: *dead* (the death
  clip seeked by the brain's fall fraction; the idle stops, so the corpse does not breathe), *airborne*
  (off the floor for more than two frames: the airborne pose), *motion* (an action that moves the giant
  in this phase, Shoulder Charge's dash or the grab's lunge: the run clip on a clock of its own),
  *walking* (idle, walk and run blended by speed, their time taken from the brain's walk phase so that
  a heel strikes on every brain footfall) and otherwise the *stance* (the idle's legs under the body's
  lean: dodges, staggers, knockbacks, standing actions). So no stride freezes in a glide and no leg
  steps in the air. M11 added landing, the stomp, the roar, the sprint, turning and bracing, and placed
  every source under a balanced, gated blend tree (§24.3).
- **`PoseBrainModifier`** (a `SkeletonModifier3D`) runs inside the skeleton's update, after the clips:
  the brain's torso twist over the three spine bones; **the weapon arm by tip matching during a weapon
  arc** (§23.5) and by a generic mapping of the brain's arm pose otherwise, crossing over without a
  jump; the off arm on the brain's off pose while an action, a block or a dodge runs; during a hold
  the off palm on the grab socket (the clavicle protracted, the arm straight when the socket is out of
  reach); the fists closed on the weapon and on a held body. Every arm is an analytic two-bone solve,
  solved again until the wrist bends at most 45°.
- **The held body**: the simulation holds a grabbed body at the stylized arm's socket. After the
  modifier, the rig moves the held body's `Visual` by the gap to the visible palm (at most 0.33 x the
  growth scale) and puts it back on every release path; its collision and grab point never move. That
  offset and the rig's own nodes are the only things the skinned layers write.
- **The look and paint**: `apply_look(look)` (called by `PlayerAppearance`) is `GiantLook.apply` on the
  model; `flash()` and `set_status_tint()` reach every surface's shader and the weapon.
  `skin_stats()` and the static `run_stats()` count posed frames, modifier runs, footfalls and
  held-visual writes: the `SKIN_STATS` line the determinism gate uses as its positive control.
- **Growth** is a uniform scale of `Visual/Body` by height / 3.6576, as before; there are no per-stage
  proportions.

### 23.5 Tip matching (`scripts/presentation/tip_matching.gd`, P42; pure)

The stylized rig drew the tested swing exactly; a body of real proportions cannot, because the
gameplay's grip point is beyond the real arm's reach in almost every sample. So the contract changed
(decision 67, replacing the M0/M1 rule in `DECISIONS.md` §5): the hand takes a grip the real arm can
reach and the visible weapon **aims at the tested segment's tip**. `TipMatching` computes it from the
weapon data and the model's landmarks: `swing_geometry` gives the tested segment in body space,
`match_swing` the grip (the natural grip moved onto the weapon-length sphere round the tip and
projected into reach), the hand's axis (41° off the weapon), and the wrist and elbow of a two-bone
solve. The contract, checked over every player weapon arc at stages 1, 3, 4 and 6 on the exported
landmarks (`test_tip_matching`): the weapon's outer half stays inside the tested capsule and the
weapon within 15° of the tested direction (measured: median 7.1°, worst 12.9°), for every weapon that
fits its stage. A weapon carried past the stage it fits keeps its short length while the arm grows, so
it points at the tested tip and falls short of it; the HUD already says such a weapon is too small.
The gameplay geometry - pivots, arm lengths, reach bands - is untouched.

### 23.6 The clips (`tools/giant/kit/clips.py` ─► `assets/giant/giant_clips.glb`, P43)

Computed keyframes, no hand animation and no outside motion data: `idle` (a 2 s breathing loop), `walk`
and `run` (one two-step cycle each on the brain's 3.2 m stride, the feet planted), `airborne` and four
one-frame hand poses (`grip_r`, `grip_l`, `open_r`, `open_l`), and `death` (the knees buckle and the
torso slumps). They are written by Blender in the same pipeline, listed in the manifest and verified
with the other outputs, and imported as an animation library whose loops are set in code. M11 added 19
clips (28 in all), each keyed only on the bones it moves (§24.3).

### 23.7 The creator (`ui/screens/creator/`, `ui/screens/shrine/appearance_tab.gd`, the title; P44)

- **`CreatorScreen`** (`ScreenStack.SCREENS["creator"]`) has three doors: the title's New Game paths
  (after the replace-the-save confirm and the prologue-or-skip choice), `--creator` (the launcher's
  world start: `GameSession.creator_start`) and the shrine's tab. It closes with the record and
  `begin` (Begin calls `start_game` from the button's own handler, in the same call stack, which is
  what keeps the browser's pointer lock), with the record alone (Keep this look) or cancelled. It
  holds the record being edited, an undo history of 64 records, its own random generator for Randomize
  (never `Sim.rng`), the discard question, and the framing each category wants. While it is on top the
  root viewport's 3D is off. A record a later build wrote is never edited in place: the screen starts
  from the default look, and only a kept change replaces that record (the M10 gate's LB-1).
- **`OptionRows`** builds each category's rows from the appearance sets - swatch rows, cyclers,
  sliders, toggles, the preset list - with the record path each row reads and writes, a locked
  option's reason and "Hidden by your clothing" from the index's garment coverage.
- **`GiantPreview`** is a `SubViewportContainer` with a world of its own: a second `GiantModel` with
  `GiantLook`'s materials, the idle clip, a studio (a key and a rim light on a rig that turns with the
  camera, so the side the camera sees is always lit), and the world's light for **Game view** (the
  stage's real third-person camera and scale, a soldier beside the giant) and for first person. Its
  framings (full, face, hair, back, arms, chest, hand, eyes, game, first person) serve the creator, the
  rendered option check and the character sheets. On desktop it draws one viewport pixel per window
  pixel up to 2x; on the Web at the canvas's size.
- **The title** warms the giant's shaders up: with a display it draws the default look in a hidden
  64 x 64 viewport under both lights and holds New Game and Continue behind "Preparing..." until that
  is done (at most 6 s).
- **The shrine's Appearance tab** (the seventh of `ShrineScreen.TABS`) shows the look in words
  (`Appearance.summary_lines`) and opens the creator over the paused shrine. Keep calls
  `player.appearance.set_record`: the live giant changes, `Events.appearance_changed` fires once and
  `GameSession` takes the shrine's checkpoint again; Cancel restores the look in memory and writes
  nothing.

### 23.8 The appearance record and its saves (`scripts/progression/appearance.gd`, P42)

`character.appearance` is optional and carries its own version (`"v": 1`); save schema 2 is kept
(decision 78). It names options by id (`<set>.<key>`): a preset, the skin, the eyes, hair and beard
(style, colour, grey), a tattoo for each of four regions and their ink, a war paint and its colour, up
to four scars, the mark's mode (`"auto"` or `"none"`) and the outfit with two dyes. The options are
data: thirteen `appearance_set` records (`data/appearance/set_*.json`, 99 options) and eight
`appearance_preset` records, validated by their schemas and a post-pass at startup.

- `Appearance` is pure. `resolve(character)` is the character's record, else the `--appearance=`
  preset, else the default (the Wanderer). `sanitize(record, ancestry)` never fails: unknown ids fall
  back to the default's and are listed, options locked to another line are reset, a broken record
  becomes the default, each with a note; **a record from a later build (`v` above 1) is kept
  untouched** and drawn as the default. `to_look(record, ancestry)` resolves palettes to colours, the
  mark's `"auto"` to the line's mark, and the outfit to garments. `random_record` is the creator's
  Randomize; `covered_regions` says what the outfit hides.
- **Saves**: `CharacterState.sanitize` repairs a look for the character's line and passes its notes up;
  `SaveSlots.read` joins them into the load message. A broken look is never a reason to refuse a file
  or to fall back to the backup; absent stays absent, so every older save, fixture and bot run is
  byte-for-byte what it was. (Since `0.12.0-m12` the record is at `v` 2 and a `v` 1 record is migrated
  when it loads: §25.1.) A Continue of a save without a look sets `appearance.legacy_save`, which
  brings up the one-time prompt at the next shrine; `appearance.mark_shown` brings up the other when a
  line's mark first shows on a look of the player's own.
- **`PlayerAppearance`** (the giant's component, §5) holds the record in play and calls
  `rig.apply_look`. The code rule (`test_appearance_rules`, `test_skin_rules`): nothing in combat, AI,
  the world, quests, `sim.gd` or the other player components names the skeleton, the model, the look
  or the skin.

### 23.9 The Web tiers and budgets (P41, P45)

Both texture tiers ship everywhere. W25 and W26 excluded `tex_hi/` from the Web presets to keep the
23 MB pack; the owner then raised the Web budget to 26 MB so that the browser keeps the 1024 px maps,
and since P45 the Web presets leave out only `assets/giant/manifest.json`, `GiantLook`'s "auto" tier
picks "hi" on the Web as on the desktop, and `tools/build_web.sh` judges a `-m10` (or later) version
against 26 MB in parts of at most 15 MB (`-m11` too; 32 MB from `-m12` and 44 from `-m13`, decision 87). Its `GIANT_SHARE` line weighs M10's files in the shipped pack
(everything under `assets/giant/`, the giant's shaders and scenes) and fails over its cap, the budget
less 18.4 MB: 7.6. The model's budgets and what the M10 gate measured against them - draw calls and
primitives, texture and mesh memory, the skin's CPU a frame, the first-frame stalls - are in
`docs/PERFORMANCE.md` ("Budgets"; "The M10 Web build and its budgets (P45, W27)"; "The W27 merge";
"The M10 gate, lane web") and summarized in `docs/M10_HANDOFF.md` §6.

## 24. The giant refined (M11 Part A; P48-P51, Gate A and Gate A2)

M11's first part (`0.11.0-m11`) kept everything of §23 and refined the giant: the body pipeline was
reopened once for bones, build weights, landmarks and parts; the rig gained new sources for the legs,
grips, flinches, secondary motion, a longer reach, the eyes' look and a first person of its own; the
shaders gained shells, braids as tubes, a subsurface term and better eyes. It is still presentation only
(decisions 88, 89): the simulation, the soak and the bots did not change. The data flow of §23 holds, with
the parts and the springs added:

```
tools/giant/kit (+ giant_parts, freeze) ─► giant.glb (71 bones, body, eyes, ShadowProxy) + parts/<mesh>.glb (21) + giant_clips.glb (28 clips)
                                                          │ index: part_path, chains, build_max_m, shadow_proxy, landmarks II
GiantModel ─ ensure_part / release_unused (shown parts only; a shared, weak table and a recent list)
                                                          │
GiantLook.apply ─► materials; shells stacked at load (12 layers desktop, 6 Web); eyes' look
                                                          │
ActorRig's pose brain ─► SkinnedRig: balanced gated blend tree (legs' sources, grips, flinches, fp_rest)
                         └► Skeleton3D modifiers: PoseBrainModifier (fist, reach, arm limit) ─► SpringBoneSimulator3D ─► SecondaryMotion (limits)
```

### 24.1 The body pipeline II (`tools/giant/`, P48)

- **The freeze test first.** `tools/giant/freeze.py` reduces a glTF to order-free hashes (per body mesh:
  positions, normals, UVs, region ids, weights by bone name, triangles; per bone its rest and inverse
  bind; per clip its tracks). `fixtures/m10_freeze.json` was written once from the `0.10.0-m10` files and
  `test_giant_tools.py` compares every regeneration with it: the three body meshes, the 53 body bones and
  M10's clips are bit-identical, so no bake input changed and M10's clips still play.
- **Leaf bones** (`kit/giant_parts.py`): 18 bones added after the body was built - `hair_01`-`03` behind
  the head, `hair_l_*` and `hair_r_*` at its sides, `beard_01`-`02` under the chin (all under `head`) and
  `cape_c`, `cape_l`, `cape_r` (three bones each, under `spine_03`): 71 bones. Hair and beard cards are
  re-weighted along the chain beside them, a card's root wholly on `head`; a chain no vertex hangs on by
  half is folded back into `head`, so the crop and the short beard have none. The index's `chains` holds
  each chain's parent, bones, kind, rest root, length and the springs' starting values.
- **Build weights**: `COLOR.g` (brawn) and `COLOR.b` (girth) hold two MakeHuman targets' displacement
  along the normal, smoothed, mirrored, zero on the head and normalized by `build_max_m` (0.099 m). Garments
  take the skin's under them, cards the skin's they grew from, the proxy the nearest skin's. Nothing pushes
  them yet: the sliders are Part B's (decision 92). Four more CC0 targets were vendored for the two
  directions (137 files).
- **Landmarks**: `grip_r`, `grip_l` (the closed fist's centre), `grip_local_*` and `grip_axis_*` (the same
  in the hand bone's space and the handle's line through the fist), `knuckle_*`, `toe_*`; every design has a
  `side`.
- **Parts on demand** (`GiantModel`): `giant.glb` holds the skeleton, the three body meshes, the eyes and
  the shadow proxy; each hair, beard and garment mesh is `assets/giant/parts/<id>.glb` on the same armature
  (one `Skin` serves all). The model puts an empty node for every part under the skeleton at once (so
  every finder by node name works), loads a part's mesh when its node is shown or by `ensure_part(id)`,
  and lets it go on hide or `release_unused(shown)`; loaded meshes are shared through a weak table and
  the last ones let go stay in a recent list (6 parts, 1 MB). The fullest look holds 2.60 MB of mesh
  buffers, the default 2.15 (every part: 5.28; the budget 4.5).
- **`ShadowProxy`**: the whole body decimated to 2,500 triangles, 12 mm inside the skin, shadows only;
  `RigPaint.use_shadow_proxy` (P49) stops every other mesh of the model casting, so a cascade draws the
  giant once instead of 9-12 times (the free cape keeps its own). Since Gate A it is on render layer 1
  (§16).
- **The free cape** hangs straight from the shoulder blades with a flared, folded hem, weighted below the
  shoulders to the three cape chains.
- **The clips II** (`kit/clips.py`; 28 clips): `sprint`, `turn_l`, `turn_r` (90 degrees in two steps),
  `stomp_r` (lift, hold, plant), `land`, `brace`, `roar`, `flinch_f`, `_b`, `_l`, `_r` (the spine, neck,
  head and clavicles only, additive), six grips by weapon family (`grip_club` ... `grip_tree`),
  `carry_two_hand` (not wired) and `fp_rest`. A clip that keys a few bones is written with those tracks
  only (`clips.strip_tracks`).
- **The outputs**: 38 files in the manifest (M10's 13, the 21 parts, `tex/curvature.png`,
  `tex/skin_lut.png`, `shell_strands.png` and `cloth_metal.png`), all bit-exact under `--verify`
  (`tools/check.sh --giant`, `--giant-full`).

### 24.2 The Web and the tools (P49)

The launcher unpacks the pack as one stream, a network chunk at a time, into one `DecompressionStream`
(probe 9). `tools/build_web.sh` stages the budget by milestone (26, 32, 44 MiB), prints `PEOPLE_SHARE`
(0 until Part C) and `PCK_SHA256`; exports are reproducible because the builders write stable node ids
(`SceneKit.stable_node_id`) and `tools/normalize_imports.gd` gives the imported glTF scenes stable ones
before an export, which also empties `.godot/exported/` first: two checkouts of one commit build the
same pack. The Web checks wait for the title's warm-up, map the audio clock piecewise, and stop on a
renderer over 3 GB. The loading screen warms the creator's preview for a `--continue` start.

### 24.3 The rig's sources, grips and the balanced blend tree (`skinned_rig.gd`, `pose_brain_modifier.gd`; P50)

- **The legs' sources**, first match wins: dead; airborne (after one frame off the ground); **landing**
  (0.25 s after at least 0.2 s in the air); **stomp** (an action whose hit is a cylinder pulse without
  morale damage - Heavy Footfall, Titan Stomp: `stomp_r`'s windup seeked so the foot is planted as the
  ACTIVE phase starts); **roar**; motion (the run, or the sprint clip above 0.8 of the sprint's speed);
  walking (idle, walk, run and **sprint** by speed, timed by the brain's walk phase); **turning** (the yaw
  changing faster than 60 degrees a second while the brain does not walk: `turn_l` or `turn_r` on the yaw
  travelled); **bracing** (blocking or guarding, standing); the stance. Their weights are a chain from the
  stance to the death (`SOURCE_CHAIN`), eased at the rates of `docs/systems/P50.md` (0.12-0.37 s to 95 %).
- **The balanced, gated blend tree** (Gate A): a `Blend2` evaluates a branch at a weight of 0 (about a
  microsecond a node), so the sources sit under a balanced tree of `Blend2` nodes in the chain's leaf order
  (`SOURCE_LEAVES`; each node's amount its right half's share, so every clip weighs what the chain gave
  it), with **gates** (`GATE_NAMES`: a `Transition` to the empty clip `_gate_off`) before every branch that
  is often at no weight - the turn, the gait and each gait, the charge, the stomp and roar, the fall, the
  upper sources, the left fist, first person's arms - and the four flinches under one gated `Add2`. Every
  amount and gate is a fixed slot (`SLOT_PARAMS`), written only on a change. The picture is unchanged (every
  bone within 0.000005 m of the ungated tree) and the giant's CPU a frame with secondary motion is
  0.136-0.144 ms natively (budget 0.15 since the owner's checkpoint A, decision in `DECISIONS.md` §1.7),
  0.23-0.25 ms on the Web (0.45).
- **Grips**: `PoseBrainModifier` places the weapon hand by its **fist** (`grip_local_r`), the socket on the
  fist's centre and the weapon along the grip's line, so the handle passes through the closed fist in
  every pose; tip matching is built for the fist (`TipMatching.for_fist`) and keeps its contract. In the
  generic poses the hand turns toward laying the fist's axis along the handle within the wrist's 45
  degrees. The right fist closes by the weapon family's grip clip; the off hand rests open with a little of
  `grip_l`.
- **The arms' limit** (Gate A): outside a tested swing each arm's upper arm, forearm and hand move at most
  `ARM_STEP_DEG_S` (1,200 degrees a second) from the last frame, so a block's start or end no longer pops
  the arm (81 to 20 degrees a frame); a teleport or respawn forgets the last frame.
- **The reach past a weapon's fit stage** (`TipMatching.match_swing_reach`): when the visible weapon's outer
  half would lie beyond 0.95 of the capsule's radius, the drawn clavicle protracts, then the spine leans,
  then the pelvis shifts, each by the least that brings it within reach (the feet put back by a leg solve).
  A weapon that fits never moves the body.

### 24.4 Flinches and the eyes (P50, Gate A, Gate A2)

- **Flinches**: `HitFeedback` hands the rig the hit's side with the flash's strength; `SkinnedRig.flinch()`
  adds `flinch_f`, `_b`, `_l` or `_r` (named by the side the hit came from) at up to `FLINCH_GAIN` (2.5)
  times over 0.5 s, so the head moves 0.31-0.44 m **away** from the hit and the chest turns 22-28 degrees
  (Gate A2: the side clips had leaned toward it). None during an attack's ACTIVE phase; nothing reads it
  back.
- **The eyes' look** (Gate A): `SkinnedRig._look_eyes` writes `giant_eye`'s `look` through
  `GiantLook.set_param`: toward the camera's lock focus point, else along the camera's level facing, in the
  head's rest frame, clamped to 0.25 of the iris's radius (about 7.6 degrees) and eased. The creator's
  preview does not turn them yet.

### 24.5 Secondary motion and the shaders II (P50, P51)

- **`SecondaryMotion`** (`scripts/presentation/secondary_motion.gd`): the engine's `SpringBoneSimulator3D`
  runs only the chains the shown meshes hang on (`SecondaryMotion.chains_for`: none for the crop, the
  short beard and no cape), one setting a chain, after `PoseBrainModifier`; then `SecondaryMotion`, a
  `SkeletonModifier3D`, holds every joint within its chain's limit of its parent's pose, a cape joint at
  most 6 degrees toward the front, and every joint at most 720 degrees a second (so a dash's stop does not
  whip a braid). Colliders: a sphere on the head, a capsule across the chest. Reset on a look change,
  growth, a teleport and a respawn. Hair, braids, beards and the cape swing as he moves and settle about
  a quarter of a second after he stops; the hair's shader sway of M10 (`GiantLook.sway_step`, now run by the
  rig) adds a little on the cards.
- **Hair** (`giant_hair.gdshader`): head-centred volume normals baked into the cards and blended per card,
  two highlights along the strands (a white one toward the tip, a tinted, broader one toward the root),
  softer card-on-card shadow. **Shells** (`giant_shell.gdshader`): the crop and the short beard are the
  skin under the style's mask lifted off the skin; `GiantLook.shell_stack` copies it into
  `shell_layers()` layers in one surface at load time - **12 on the desktop, 6 on the Web**
  (`SHELL_LAYERS`, `SHELL_LAYERS_WEB`) - one draw call a style, no shipped bytes for the layers, never a
  shadow; the shader keeps a strand of `shell_strands.png` per layer, combs the tips and, since Gate A2,
  takes the grey and the light as the cards do, with a sky sheen. **Braids** are seven-sided tubes with a
  plait's three strands and two bead rings (one draw call with the style). **Loose strands** at the
  hairline of the four long styles; a row of cards under the jaw so a full or forked beard exists from
  behind.
- **The skin** (`giant_skin.gdshader`, `kit/pack.py`): the albedo graded in the pack step; a **subsurface
  term**: `tex/skin_lut.png` (64 x 64, a skin profile pre-integrated over a light wrapped per channel,
  `SKIN_WRAP`, since Gate A) read in `light()` by (N.L, curvature), the curvature from **`tex/curvature.png`**,
  a 256 px map of its own (the mask map's alpha spoiled the masks under VRAM compression). A tone away
  from the default keeps its hue and takes back the bake's saturation by its distance, so pale and dark
  tones are not grey. In the world's sun the skin is warm; in the creator's light the default chest reads
  (220, 160, 131), which the owner accepted (`DECISIONS.md` §1.7). The swatches show the colour drawn
  (`GiantLook.drawn_tone`).
- **Eyes** (`giant_eye.gdshader`): `look`, a limbal ring, a lid shadow, a painted catch-light on the iris,
  a duller sclera. **Cloth** (`giant_cloth.gdshader`): 256 px detail maps, a rim light for fur only (Gate
  A), a metal kind for Part B, the darkest dyes lifted. **Scars**: the three thinnest widened.

### 24.6 First person (P50, Gate A, Gate A2)

- **At rest** the arms take `fp_rest`: the forearm raised and turned 75 degrees about its own line (Gate A2),
  so the weapon lies low in the lower right corner with the fist in view at every stage; it fades out as
  the view turns down from -30 to -48 degrees. A block raises both forearms into view.
- **Looking down** (`giant_first_person.gdshaderinc`, included by the skin and the cloth): while the camera
  stands inside the head (`fp_in_head`), the limbs fade out in the box round the shoulders (M10), and every
  vertex of the **pelvis, thigh, knee, shin, foot or a cut's cap** (regions 7 and 11-15, read from
  `COLOR.r`, which every garment also carries for the skin under it) is discarded (`fp_region_shown`,
  Gate A2). First person therefore shows the arms, the weapon and the body's shadow, never the legs or the
  hips' caps; the shadow pass's camera is the light, so the whole body still casts. A third-person camera
  pressed into the head box hides the same.

### 24.7 The capture tour and the measures

`scripts/debug/capture_m11.gd` (`--scenario=capture_m11 --part=a --skin`, `--capture-dir=`,
`--capture-beats=a,b`): 43 beats and 163 frames from the side, the front and three-quarters - idle, walk,
run, sprint, the stop, the turns, a jump and landing, every weapon's light and heavy, the stomp (lifted,
held, planted), the roar, a buff, a block, the dodges, Shoulder Charge, a grab and throw, four flinches,
stages 4 and 6, the reach past fit, first person at rest, blocking and looking down, the death. Headless
it still runs every beat and its measures. The budgets and what Part A met are in `docs/PERFORMANCE.md`
("M11 W29", "M11 W30", "M11 Gate A", "The 0.11.0-m11 release") and summarized in `docs/M11_HANDOFF.md` §6.

## 25. More customization (M11 Part B; P53-P57, the W33 lanes, W33body, Gate B)

M11's second part (`0.12.0-m12`) kept §23 and §24 and made the look a record of pieces: ten garment slots
and three accessory slots, dyes by material, two build sliders and six face sliders, beads, and a creator
that holds about 190 options. It is still presentation only (decisions 88, 89) with one exception, the
leash's contact rule (§6; `DECISIONS.md` §3.6): the seeded soak is unchanged (41 attacks, 33 hits resolved,
4 enemy kills, 2 fence breaks, 7,201 frames). The flow of §24 holds, with the record v2 in front of it:

```
character.appearance (v 1 or 2) ─► Appearance.sanitize (migrate v1 ─► v2; a later v kept untouched)
                                     │ Appearance.to_look: garments [{mesh, dye, kind}] by slot, accessories, beads, build, face
tools/giant/kit (+ giant_garment Wardrobe, giant_hair, designs) ─► giant.glb + parts/<mesh>.glb (69) ; index v2 (slot, shell, material, hides_hair, hair_cut)
                                     │
GiantLook.apply (a plan per root and index; skips a material whose values did not change) ─► the build push, garment pushes, face keys, bead mask
                                     │
CreatorScreen (eleven categories) ─ OptionRows ─ OptionGrid (pages, filter, materials) ─ ThumbnailCache (pictures natively, names on the Web)
```

### 25.1 The record v2 and its migration (`scripts/progression/appearance.gd`, P53)

`RECORD_VERSION` is 2 (save schema 2 is kept; decision 96). The record names the preset, skin, eyes, hair
and beard (each with beads), tattoos for five regions (the legs new), a face and a body war paint with one
colour, up to six scars, the mark, `outfit.slots` (ten: head, shoulders, chest, armour, arms, waist, legs,
shins, feet, cape) and `outfit.accessories` (neck, arm ring, belt) with the cloth, leather and metal dyes and
a dye per slot, `build` (brawn, girth) and `face` (jaw, chin, nose, brow, cheeks, age), each -1 to 1.
`migrate` is the one pure step from `v` 1: an outfit's garments go to the slots M10's outfit gives them, its
two dyes become the cloth and leather dyes, the one war paint goes to its place. `sanitize` keeps a later
version untouched (`NOTE_FUTURE`), makes a broken record the default (`NOTE_BROKEN`), takes off an unknown
or wrong-slot piece, and adds `NOTE_MIGRATED` once ("Your giant's clothing is now worn piece by piece;
nothing was changed."; the world flag `appearance.slots_seen` keeps it once). A v1 record is rewritten as v2
only at a kept look or the next checkpoint. The proof: `tests/support/appearance_v1_oracle.gd` (M10's
`Appearance`, copied whole) draws every M10 preset, every option and 360 random M10 records as the migrated
record draws them (`test_appearance_migration`, slow `test_appearance_migration_matrix`), and the release's
cross-version run (`docs/M12_HANDOFF.md` §5.4). **A record at `v` 2 is a later build's to `0.10.0-m10` and
`0.11.0-m11`**: they keep it untouched in the save and draw the default look until it is changed there.

### 25.2 The wardrobe and the index v2 (`tools/giant/kit/giant_garment.py`, P54, the W33 look lanes)

Every garment belongs to a slot, and the slots are built in `LAYER_ORDER` (legs, chest, shins, arms, feet,
waist, armour, cape, shoulders, head) as shells over the skin with each slot's least standoff. A shell's
vertex carries the weights and the normal of the skin vertex it stands on, so the build push moves every
layer as the skin under it. Since the first W33 look lane a garment's mesh is its place over nothing, and
the cloth shader pushes it out only as far as the garments worn under it need (the index's layering table;
`GiantLook.garment_pushes`), so an outer piece no longer balloons over the loosest inner candidate. The
index v2 gives each garment mesh its `slot`, `shell`, `material`, `hides_hair` and `hair_cut`, each accessory
its `slot`, `bone` and `color`; `data/appearance/set_garment.json` (35 garments, a garment's own `dye`
optional), `set_accessory.json` (8), `set_outfit.json` (12 outfits as starting points) and `set_dye.json`
(14) / `set_metal.json` (5) are the data. Every piece is a part on demand (69 parts in all); far levels
switch by pixels (`tools/giant/far_lods.gd`, W33look2). The layering check (`test_wardrobe_render`) and the
gate's stack check with its positive control (`test_wardrobe_stack_render`, P57) prove no two shown pieces
intersect or z-fight.

### 25.3 `GiantLook` by slot (`scripts/presentation/giant_look.gd`; P53, P57, Gate B)

`to_look` gives `garments` as `{mesh, dye, kind}` in slot order (a slot's own dye over the garment's own over
the outfit's dye of its material; fur keeps its colour), the accessories' meshes, the beads' mesh and the
build and face values. The skin and cloth shaders push `VERTEX` along the normal by the build weights in
`COLOR.gb` (`build`, `build_max_m`); the shadow proxy takes the same push once a build leaves zero
(`GiantModel.apply_build`). Face sliders drive blend shapes named as `Appearance.FACE_KEYS` on the head,
the beards and the bead sets. `apply` walks a plan made once per root and index and skips a material whose
compared values did not change (`_put`, `META_LAST`: a whole look about 0.33 ms); since Gate B a hidden
piece's build and push are part of its own compared values, so a piece shown again is never drawn with old
ones. A raw `set_shader_parameter` outside `GiantLook` calls `forget_applied(root)` first.

### 25.4 The creator II (`ui/screens/creator/`, P55, P57, Gate B)

Eleven categories (Presets, Body, Face, Hair, Beard, Tattoos, War paint, Scars, Clothing, Accessories,
Colours; `OptionRows.row_specs`, built from the sets). A grid row opens an `OptionGrid` in the options
panel: pages of twelve cells, a name filter (the first letter typed puts the focus in the box; "/" for a
name that starts with Q, E, R, V or F), material buttons; moving over a cell puts the piece on, one grid
opening is one undo step. `ThumbnailCache` draws each cell's picture on the giant at the cell's pixel size
(at most `MAX_PICTURES` 200, the least recently shown going first; keyed by the dye a piece is drawn in); on
the Web a picture's read-back is over the stall rule, so the grids show names there
(`ThumbnailCache.pictures_wanted()`, `--creator-pictures=on` overrides). Signed sliders step by 0.1 and the
build sliders stop at `BUILD_LIMIT` 0.6 (the record keeps -1 to 1). LT / RT with no grid open jump five
rows; the right stick's up and down zoom. Randomize dresses by slot (`random_clothing`: never an armour over
a bare chest unless the outfit it started from wore one).

### 25.5 The catalogue II (`tools/giant/kit/giant_hair.py`, `designs.py`, `export_game.py`; P56)

Twelve hair styles and eleven beard options (none included); beads as three sets, each one part with a bead
on every anchor of every anchored style, the shown styles' beads picked by the cloth shader's `bead_mask`;
28 tattoos over five regions, eight war paints in two places, ten scars (six at once); the six face keys as
morph targets with their tangents rebuilt in the shaders (the renderer's blend shapes lose the tangent's
sign: `giant_skin.gdshader` `TSIGN_FLIP`); fourteen presets at `v` 2.

### 25.6 The body reproportioned (W33body, W33frame; checkpoint B, decision 4)

The owner lifted the M10 body freeze for one lane: `giant_body.PROPORTIONS` and `proportioned()` reshape the
morphed mesh before the joints are read (the legs x1.30, the torso x0.85, the neck 7 cm longer, the head
x1.12, the deltoids drawn in, the arms x1.10 with the hands x0.8), so the giant is 7.94 heads tall (8.35),
his legs 47 % of his height (40 %). Every stage keeps its height and is the same body scaled uniformly;
gameplay data (capsules, reach bands, grips' ranges, the stride) is unchanged and the landmarks follow the
mesh. `BUILD_SHOULDER_EASE` takes most of the build push off the shoulders. `tools/giant/fixtures/
m10_freeze.json` was taken again, so `freeze.py` now holds the new body, its 53 bones and nine clips. The
creator's close-up framings follow the new landmarks (W33frame). Saves are unchanged: a slider's value is a
share of the push, which lands on the new body.

### 25.7 Budgets and measures

`tools/build_web.sh` judges `-m12` against 32 MiB in parts of at most 15 MB and the giant's share against
13.6 MiB (decision 87); `0.12.0-m12` ships 30.28 MiB in three parts, 13.13 MiB of it the giant
(`docs/M12_HANDOFF.md` §6). The capture tour's part B (`--scenario=capture_m11 --part=b --skin`) films
every preset, the fullest look standing, walking, running, at stage 4 and in first person, and the build
sliders at the creator's ends; `tools/character_sheet.tscn -- --sheet=b` draws the wardrobe sheet. The
budgets and what Part B met are in `docs/PERFORMANCE.md` ("M11 W33: Web and performance for the wardrobe
(P57)", "The 0.12.0-m12 release") and summarized in `docs/M12_HANDOFF.md` §6.

## 26. Realistic people and creatures (M11 Part C; P59-P65d, Gate C)

M11's third part (`0.13.0-m13`) replaced every body that was still a box rig - the soldiers and the formations, the
townsfolk and the named characters, the riders and their horses, the rival giants and Harrok, the brutes and the
bosses, the wolves - with a realistic, skinned body made by the committed pipeline. It is presentation only
(decisions 88, 89): every scene keeps its capsule, hurtboxes, anchors, sockets and the pose brain's pivots (hidden),
no gameplay script reads a model, and the seeded soak, `test_people_determinism` (people on and off) and
`test_bosses_seeded_people` read every gameplay event the same. Headless, nothing of it is made (decision 104);
`--skin` / `--no-skin` switch it as they switch the giant, and `body.rig: "box"` keeps a record's low-poly rig.

```
tools/giant/build_people.py (kit: people_roles, people_body, people_outfit, people_bake, quadruped, brute)
    ─► assets/people/<role>.glb (variants, crowd poses, far mesh) + atlases, people_clips.glb, gear.glb ; assets/creatures/ (horse, ogre, troll, wolf)
data/people/role_*.json (asset_role, variants, palette, factions) + actor record's body {role|creature, variant, palette, gear, rig}
    │ PersonLook (variant, palette row, faction colour, height: the entity id's hash, no random stream)
EnemyActor / NpcActor ─► pose brain (pivots, unchanged) ─► PersonRig ─┬► skinned: pooled PersonModel (clips on the brain's clock, arms solved, tip matching, gear)
                                                                     ├► crowd: CrowdRenderer (one MultiMesh a role, pose and level; palette and flash per instance)
                                                                     └► far / LodProxy
                       BruteRig · SkinnedWolfRig (fur shell) · SkinnedQuadrupedRig (horse + rider) ─► CreatureSlots (at most 8 skinned)
                       SkinnedRig (the rival giant, Harrok: the player's model, a look from the record's appearance)
```

### 26.1 The people pipeline (`tools/giant/build_people.py`, `tools/giant/kit/people_*.py`; P59, P59b)

A person is built from the giant's CC0 data and code (the hm08 mesh, MakeHuman's macro and detail targets with their
natural proportions, the women's targets of the same release) on the 23 bones of the giant's skeleton less the
fingers (decision 99), dressed slot by slot by the giant's own `Wardrobe`, culled where covered, merged, decimated to
at most 5,000 triangles and mapped onto one 512 px atlas a role (decision 97); each variant adds its own pieces in
128 px tiles. The atlas's ORM blue channel carries the palette bands (skin, hair, cloth, the faction's surcoat), so
the colours are the record's. Every role also has five crowd poses and a far mesh, and one set of computed clips
(`people_clips.glb`: idle, walk, run, flee, brace, held, tumble, cower, seated, death, ...) poses every variant,
because each variant's pelvis and rest orientations are the reference man's. Eight roles (soldier, archer, mage,
crew, villager, elder, notable, rider) and 29 variants; `assets/people/manifest.json` records every file and
`--verify` regenerates them bit-exact (`check.sh --people`, `--people-full`).

### 26.2 `PersonRig`, `PersonLook` and the crowd (`scripts/presentation/person_*.gd`, `crowd_renderer.gd`; P60, P62, P64c)

`PersonLook` picks a variant, a palette row and the faction colour from the record and the entity id's hash.
`PersonRig` (an `ActorRig`) decides every person's level every second frame: the held, the striking, the staggered
and the falling first, then the nearest the giant within 40 m, up to `MAX_SKINNED` 16 (`--people-cap=N`), the rest a
crowd instance to their far distance (`render_lod_m` x the square root of the giant's distance scale) and a far
instance beyond (decision 98). A skinned person is a pooled `PersonModel`: the clip seeks on the brain's own clocks
(the walk on its walk phase, so no foot slides), the arms go where the brain's poses point by a two-bone solve
(`solve_arm`), a weapon arc is exact by tip matching, and since Gate C each strike and brace is keyed on its action's
own phase (`STRIKE_KEYS`: the pike's thrust and brace with its butt on the ground, the shield's bash and brace, the
archer's kick, the staff, the lance) and the dead drop their gear flat on the ground (`corpse_gear`), turn to one of
seven yaws (`corpse_yaw`) and hand over to a corpse instance in the same place. The held soldier's weapon hangs away
from the giant; a thrown one is knocked down and gets up within its stagger (`knockdown_time`). `CrowdRenderer` draws
a formation's members and one shared renderer the loners: one MultiMesh per role, pose and level and per piece of
gear, each instance with its palette row, flash and faction row (`person_crowd.gdshader`). `PEOPLE_STATS`
(`--skin-stats`) counts it all.

### 26.3 The riders, the rival giants and Harrok (`skinned_quadruped_rig.gd`, `skinned_rig.gd`; P61, P62)

`SkinnedQuadrupedRig` shows the creatures' tacked horse with no clip: each hoof is in stance or swing in the world (a
planted hoof never slides), the walk, trot and gallop blend by speed, the legs are solved, the body bobs, pitches and
leans; the rider is a pooled `PersonModel` on the saddle's seat that lowers the lance through the charge's telegraph
and thrusts it in the lance attack. The rival giant and Harrok are the player's own `giant_model.tscn` under
`SkinnedRig` (decision 100), their looks from the record's `appearance` (npc presets whose garments and beads the
creator never offers), their two-handed axe chop and strokes keyed by `PoseBrainModifier.CHOP_KEYS` and `ARC_KEYS`
(Gate C).

### 26.4 Brutes and wolves (`brute_rig.gd`, `skinned_wolf_rig.gd`, `creature_slots.gd`; P63, P64, P64b)

The ogre, the troll and the whelp (the troll's variant) are morphs of the CC0 body on the 23 bones (decision 101),
the Ogre King and the Troll Matriarch with their gear on the same skeleton. `BruteRig` plays their clips on the
brain's clock (the walk by the distance walked; the slam and the roar from the action's phase), puts the arms where
the brain's poses point for the sweeps and throws, and lays a dead ogre's club on the ground. `SkinnedWolfRig` is the
wolf and the dire wolf (the same mesh at twice the size), driven with no clip by its own gait plan (decision 102),
the jaw opened in the bite's wind-up; its fur is twelve stacked shells in one draw call (`fur_shell.gdshader`), off at
`low`. `CreatureSlots` keeps at most 8 brutes and wolves skinned (the bosses always), the rest their far meshes.

A1 (the open world's first titan, no fight yet): **Stoneback**, 16.8 m, built by `tools/giant/kit/stoneback.py`
(`build_people.py --stoneback`) on the brutes' code: his body and hide kilt, and as separate skinned meshes on the same
23 bones eight stone plates (the shoulders', the back's and the brow's over the weak points a later package exposes;
the forearms' and the shins'), the shackles, the trunk-club (rigid on the right hand) and the throw's boulder; his
clips add the wind-ups `overhead`, `charge` and `throw`. `StonebackRig` (`scripts/presentation/stoneback_rig.gd`,
`scenes/creatures/stoneback.tscn`) shows him with no actor: `pose(clip, t)`, `pose_windup(clip)`,
`set_plate_visible(plate, on)`; the plates, the boulder and the club take `assets/shaders/stone_plate.gdshader` on
tileable detail textures. `tools/character_sheet.tscn -- --sheet=d` draws him (pages d1-d3). See `docs/systems/A1.md`.
A1b (his look round): each plate is cut slabs with its iron bands in its own mesh (the vertex colour's alpha: 1 stone,
0 iron, 0.5 the club's earth, read by `stone_plate.gdshader`); the version is 0.14.0-m14, the expansion's working
build, with a 46 MB Web budget and a 14.0 MiB people's share (`tools/build_web.sh`).

### 26.5 Budgets and measures

`tools/build_web.sh` judges `-m13` against 44 MiB, the giant's 13.6 MiB share and `PEOPLE_SHARE` (`assets/people/`,
`assets/creatures/`, their shaders and scenes) against 12.0 MiB; `0.13.0-m13` ships 41.87 MiB in three parts, 13.27
of it the giant and 11.25 the people and creatures (`docs/M13_HANDOFF.md` §6). `PeopleWarmUp` makes the people's and
creatures' shader variants behind the loading screen; `tools/web/people_check.mjs` measures a formation of forty, a
wolf pack and a town in the browser. The capture tour's part C (`--scenario=capture_m11 --part=c --skin`) films every
role's strike, the brutes' and bosses' attacks, the riders, the held, the thrown and the dead; `tools/character_sheet
.tscn -- --sheet=c` draws the people sheet (pages c1-c5). The budgets and what Part C met are in
`docs/PERFORMANCE.md` (from "The people's assets (P59)" to "The 0.13.0-m13 release") and summarized in
`docs/M13_HANDOFF.md` §6.

## 27. The signature titans (the open-world expansion; A2, A3)

A titan is an enemy of archetype `titan` (`TitanEnemy`, `scripts/actors/titan_enemy.gd`, on `RivalGiantEnemy` and
`OgreBoss`: the boss framework's phases and sequences, chained strikes, the committed charge and its body sweep, the
lobbed boulder, attempts, the disengage rule) with a `TitanBrain` (`scripts/ai/titan_brain.gd`). The first is
**Stoneback** (`enemy.stoneback`, 17.7 m since A3; `scenes/enemies/stoneback.tscn`), in his quarry beside Millford
(A3) and in the quarry test arena (`scenes/test/quarry_test.tscn`). `docs/systems/A2.md` and `A3.md` have the details.

- **Breakable plates over weak points** (data-driven, every titan): the record's `plates[]` (`id`, `region` - the
  hurtbox's -, `piece` - the rig's mesh -, `anchor`, `breakable`, `health`, `reduction`, `poise_reduction`,
  `weak_multiplier`, `heavy_multiplier`, `break` {stagger_s, debris, cue}) and `plate_default_region`.
  `PlateRules` (pure) and `PlateSet` (the state: each plate's stone, the break order) on `CombatEntity.plates`:
  `prepare()` before `DamageResolver` sets the hit's `plate_id`, `plate_state` ("armoured", "weak", "") and its
  region multipliers, which the resolver applies after armour (1.0 for everything else); `absorb()` after takes the
  stone and breaks the plate at 0 (`HitResult.plate`, `CombatEntity.plate_struck`). `TitanEnemy` answers a break:
  `Events.plate_broken`, a forced stagger, the phase rule (`enter_on_plates_broken`). Armour-only entries (no
  stone) are the titan's hide and limb plates.
- **The struck region** (`HitFactory.pick_titan_regions`, decision A2-1): one hurtbox a titan a pulse, by the
  attacker's lock point, then contact; aimed swings wait three ticks for their plate. The hit's `region` is the
  struck hurtbox's for every hit (read only by titans).
- **Lock points** (`TitanEnemy.titan_lock_point` through `CombatEntity.lock_anchor_position`): the nearest reachable
  breakable plate anchor (`Anchors/Plate*`), a broken one first; a giant too small to reach any frames his knee as
  for every tall boss. `PlayerAttack.a2_plate_offset` tilts a swing at a titan toward that point (up to 40 degrees).
- **His blows** carry `versus_size_exponent` (`CombatRules.versus_size_multiplier`: his height over the target's to
  that power, clamped 0.5-3). The smash is a `titan_shock` (TitanEnemy: line pulses sharing one pulse id - one hit
  a target for the whole shock line). His charge tramples the props his `growth_stage` tramples and reels against
  WORLD geometry (`on_wall_action`).
- **TitanBrain**: a phase's `strike_pause_scale` (faster chains), and the sweep answers a target held on his flank
  (55-115 degrees) for 1 s, at most every 9 s; behind him nothing answers but his slow turn.
- **Presentation**: `TitanRig` (`scripts/presentation/titan_rig.gd`, the Visual) loads `StonebackRig` where the people
  are drawn and plays his clips from the actor's state - each attack's A1 wind-up over the first share of its
  windup, its strike so that the blow lands on the first active tick (`stoneback_moves.py`'s smash, sweep, rip,
  release, charge_run, reel, death) -, hides broken plates and throws grey stone from them (`DebrisPool.spawn`'s
  colour); `HitFeedback` writes ARMOURED / WEAK POINT / PLATE BROKEN; the router rings stone on a plate and breaks
  stone large at a break (`CueRouter._on_plate_broken`).
- **Debug**: the arena's `--titan-stage=N` (`TitanArenaTest`, `TitanDuel.prepare`: the stage's required level, the
  bots' attribute spending, the campaign's weapon), `--scenario=capture_titan` (`CaptureTitan`: the fight's stills and
  movie), `TitanDuelBot` (BotCombat against a titan, for the balance runs) and sheet D's page d4.
- **In the world (A3)**: a titan's ground is a `TitanTerritory` (`scripts/world/titan_territory.gd`, a gateless
  `BossArena`; the layout's `arena` element of style `titan`, in its chunk's props): he engages a giant he sees
  (`territory_m`, `region_id`), is told where it is every second while engaged, the disengage rule (from the
  territory's centre) ends the hunt with the boss framework's new attempt (whole, walking home), and once he is dead
  and the giant has gone beyond his line its `reopened_flag` shows the settlement's change. His encounter is an arena
  encounter (no leash) with the director's A3 fields: `lod_near_m` (his AI at the near tier within that distance) and
  `reserve_seat` (his seat held in the combatant budget while the giant is near: `p34_reserve`, `p34_make_room`).
  The quarry's ground is the world builder's feature `quarry` (a floor and benches behind cut faces; hard ground, a
  pad) and its works the element kind `quarry` (`tools/world/kinds/quarry.gd`: terrace faces, monoliths, cranes,
  sheds, blocks, carts, spoil).
- **Down on a knee (A4)**: a plate's `on_break` names its effect (`stagger`, or `topple`: the titan down on a knee
  for `down_s`, again after `again_damage` more to the broken region; the record's `topple` block holds the
  kneel's and rise's lengths, the bonus every blow and a Heavy takes while he is down, the daze after). TitanEnemy
  staggers him for the whole down (reason `topple`) and lerps every hurtbox and lock anchor toward its
  `kneel_position` meta (the builder carries each with its bone from the idle to the kneel clip's last frame:
  `KNEEL_FOLLOW`, the creatures' manifest's `checks.kneel`); `Events.titan_toppled` / `titan_rose`; TitanRig plays
  `kneel` and `rise`. The lock adds each plate's `lock_bias_m`, counts an anchor above 0.9 of the viewer's height
  12 m farther and skips a topple plate while he is down; a swing may tilt 30 degrees below its default at a low
  plate. `TitanDuelBot` strikes his shins and his downs (`_down_rule`, `_low_target`).
- **The roster** (A4): `data/titans/titan_roster.json` (type `titan_roster`) lists the ten signature titans in the
  story's order with the ids and flags the save's titan records and the Character menu's Titans tab read.
- **Presentation (A3)**: `StonebackRig.set_plate_crack` (each breakable plate its own `stone_plate` material, the
  shader's `crack`), TitanRig's dust (`DustBurst`, CPU particles), camera shake by distance on the smash and the
  footfalls, the trunk falling from his fist. `--scenario=capture_quarry` (`CaptureQuarry`, a `CaptureTitan` in the
  real world) films him there.

## 28. The Character menu and the cutscenes (A4)

- **The Character menu** (`ui/screens/character_screen.gd`, ScreenStack `SCREENS["character"]`, the `character`
  action: C / pad Y, and the pause menu's Character entry): five read-only tabs (Giant, Attributes, Equipment,
  Titans, Materials) built from static content functions over the player, `GameSession.expansion`, the growth
  profiles, the shrines, the roster and `WorldState`; the creator's `GiantPreview` beside the Giant tab where a
  display draws it.
- **The cutscene player** (`ui/screens/cutscene_screen.gd`, `SCREENS["cutscene"]`; the pure timeline
  `scripts/presentation/cutscene_rules.gd`; records of type `cutscene` in `data/cutscenes/`): a shot list in ticks
  - camera travels, actors (`stoneback`, `giant` in the session's look, `villager`), subtitles, cue ids, shakes,
  dust, fades, a title card - played one tick a physics frame as a pausing screen whose footer is the skip hint;
  its camera and actors live under the level and are freed at its end; the world streams round its `focus` first.
  `GameSession` opens the intro (`cutscene.intro`) on the world's first entry of a New Game (`_check_intro`, then
  `level_entered`), records it in `expansion.cinematics_seen`, and runs the title's Watch the intro / `--cinematic=`
  as a world New Game that saves nothing (`cinematic_only`). `tools/export_cinematic.sh` renders one through
  `--write-movie` to an mp4. Off for tool runs, headless and `--no-cutscenes`.


## 29. Functional armour, crafting and reforging (milestone B; B1)

- **The records** (`data/armour/`, `data/recipes/`; schemas `armour`, `armour_set`, `armour_perk`, `recipe` in
  `scripts/core/schemas/`): a piece names its slot (the seven of save schema 3), its set, its defence by damage type
  (physical: armour points; the elemental types: resistance shares), poise, weight, its own modifiers, its authored
  perks and its look (the wardrobe's garments it shows, or the giant index's modelled pieces and the cosmetic slots
  they empty); a set its pieces, its bonuses by pieces worn, its refit steps (P31's forge tiers and the material
  trait a forge must work) and its perk cost; a recipe what it makes (an armour piece or a weapon), its cost, its
  forge tier, the trait it needs (`works`: titan stone) and the flag it waits for (`requires_flag`).
- **The rules** (`scripts/progression/armour.gd`, pure): `GameSession.expansion.equipment` -
  `{"slots", "pieces": {id: {"tier", "perk"}}, "hidden"}` - is the live state (schema 3's reserved block; written by
  the Character menu and the forge, saved with every checkpoint). `Armour.modifiers` turns the worn pieces into
  passives (STATUS_MODIFIERS keys; `stamina_regen_mult` is B1's, the pools' stamina recovery) that
  `PlayerProgression.rebuild_passives` merges with the talents' and the ancestry's into `Combatant.set_passives`
  - never statuses; unarmoured, nothing at all. `Armour.look_of` draws the shown pieces over the creator's record
  (`PlayerAppearance.refresh`, the Character menu's preview, the stills tool), never into it.
- **The forge** (`scripts/world/forge.gd`): the weapon's reforge (P12, P31) and B1's `craft` (a recipe), `refit` (a
  piece to its next tier) and `set_perk` (one of the piece's own perks), each with its `can_*` verdict and
  `Events.armour_changed`; `works` (from the world layout) is the material traits a forge works beyond iron and hide
  - Millford's quarry forge works titan stone. The forge screen (`ui/screens/forge_screen.gd`) has Weapons, Armour
  and Reforge tabs; the Character menu's Equipment tab puts armour on and off out of combat (`Armour.change_blocked`).
- **The looks** (`tools/giant/kit/giant_garment.py`): the Iron set's nasal helm is a garment of the wardrobe
  (built after the npc garments, over the envelope inside its slot, so every earlier file is bit-identical); the
  Quarry set's stone is modelled (`ARMOUR_RIGID`, `rigid_slab`, `rigid_band`): flat-topped slabs whose feet hug the
  skin, iron straps, each part rigid on its skin vertex's weights, built on the bare skin and over its inner slots
  (its push in the layering table, as a ring's), in the index's category `armour`; the cloth shader's kind 5 is cut
  stone with its iron in the mesh's band mask (UV2.y).
- **The world** (`tools/data/world/crownmarch.json`): Millford's forge's `works`, the reopened quarry's piles
  (ItemPickup's `requires_flag`), the warning posts before Stoneback's ground (`warning_post` kind, their areas and
  prompts); `TitanTerritory.sees` is by line of sight over the ground (`sight_clear`).

## 30. The Ogre King as a signature titan; the armour look pass (B2)

- **His asset** (`tools/giant/kit/ogre_king.py`, `ogre_king_moves.py`; `build_people.py --ogre_king`, the creatures'
  manifest): the brutes' body modules with his own proportions and reshape, his trophies as separately named meshes
  (`trophy_crown`, `trophy_bell`, `trophy_wheel_l`/`_r`, `trophy_keg`, `chain_belt`, `ram`), each its own material,
  an oak texture for their wood, and his clips solved on Stoneback's key machinery (`stoneback.export_clips`), with
  each strike's keys in the manifest (`clip_keys`). `OgreKingModel` loads it (the cutscene's actor and the stills
  tool use it alone); `OgreKingRig` (an `ActorRig`) drives it from his brain and shows each trophy's cracks, its fall
  (a static copy tumbling from where it was) and its splinters.
- **His fight** (`data/enemies/ogre_king.json`, `tools/builders/titans.gd` `build_ogre_king`): a `TitanEnemy` on P11a's
  `OgreBoss` - its phases, sequences and arena unchanged - whose trophies are `PlateRules` plates (each a hurtbox and
  a lock anchor following his kneel). B2's generic additions: the `unbalance` break (`on_break.poise_mult`, into
  `PlateSet.poise_taken_mult`), `PlateRules.trophy_cues` (the cue router's break sounds), the enemy record's
  `lock_comfortable_only` (a small giant's lock frames only what it reaches comfortably unless the player switches)
  and `ai.corpse_keep_s` (`EncounterDirector.corpse_keep_s_of`).
- **Around it**: `GameSession.TITAN_INTROS` plays a titan's intro once on `boss_engaged` (`titan_intro_due`); a
  cutscene record may name its `level` (`GameSession.cinematic_level`: `--cinematic=` builds that level's session);
  the `titan_toppled` tutorial event; the Valley layout's `aftermath` block (a FlagVisibility of `TrophyDisplay`s,
  `tools/builders/valley.gd` `_aftermath`); `ExpansionState.SETTLEMENT_FLAGS` mirrors Thornwick's change; forges'
  `works: ["ogre_trophy"]` and the Kingsfall set's recipes.
- **The armour look pass** (`tools/giant/kit/giant_garment.py`, `export_game.py`): modelled pieces conform to the skin
  by rays cast outward from inside the body (`conform_plate`), carry their iron as straps and rings on them
  (`shackle_ring`), ride the skin under their own points (`add(follow=...)`, stiffened), and a piece made to sit over
  its own set's garments is built over them (`base_cover`) instead of pushed by the layering table; metal and leather
  pieces are smooth-shaded with box UVs, their iron in the cloth shader's band mask (`band_mask`, from the index
  entry's `band`).
