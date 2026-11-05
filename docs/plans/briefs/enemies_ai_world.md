# Brief: enemies, AI and world (M2-M5 planning input)

Scope: `scripts/actors/soldier_enemy.gd` (406 lines), `scripts/ai/soldier_brain.gd` (306),
`scripts/actors/practice_dummy.gd` (81), `scripts/world/{breakable_prop,debris_pool,sandbox_arena}.gd`,
`scripts/core/world_state.gd`, the matching data records, and the soldier/fence/dummy/arena
builders in `tools/build_scenes.gd`. Line numbers refer to the code at the time of writing (M1 merged).

## 1. Files and responsibilities

| File | Responsibility |
| --- | --- |
| `scripts/actors/soldier_enemy.gd` (`SoldierEnemy`, CharacterBody3D) | Glue: senses (5 Hz), calls the brain (10 Hz), requests attacks, turns, moves (NavAgent or direct steer), runs weapon-arc hit queries, frontal guard, death cleanup. |
| `scripts/ai/soldier_brain.gd` (`SoldierBrain`, RefCounted) | Pure 10-state FSM. Inputs: perception snapshot, noise, ally death, path failure. Outputs: `move_target`, `move_speed`, `face_point`, `attack_request`. No engine queries. |
| `scripts/actors/practice_dummy.gd` (`PracticeDummy`, StaticBody3D) | Unkillable target, refills health `reset_after_s` after last hit, wobble/flash only. |
| `scripts/world/breakable_prop.gd` (`BreakableProp`, StaticBody3D) | Persistent breakable: category/stage permission, intact->broken swap, detach `Block*` shapes, one `object_destroyed`, loot once, spawns debris. |
| `scripts/world/debris_pool.gd` (`DebrisPool`, Node3D) | 40 pre-made RigidBody3D slabs; 5 s lifetime / 1 s off-screen; recycles oldest. |
| `scripts/world/sandbox_arena.gd` (`SandboxArena`, Node3D) | Duplicates and bakes the navmesh at load (sync), re-bakes async on any `object_destroyed`. `player_spawn()`. |
| `scripts/core/world_state.gd` (autoload `WorldState`) | Deltas keyed by world id (`destroyed`, `damage_stage`, `loot_awarded`) + minimal inventory; versioned `to_save_dict/from_save_dict`. |
| `data/enemies/soldier.json` | All soldier tuning incl. `guard` and `ai` blocks (validated strictly). |
| `data/props/fence_wood.json`, `practice_dummy.json` | Prop health/armor, `accepted_attack_categories`, `min_growth_stage`, `loot`, `debris_count`, `unkillable`, `reset_after_s`. |
| `data/items/wood_scrap.json` | The only item (placeholder loot). |
| `tools/build_scenes.gd` | `_build_soldier` (293-356), `_build_dummy` (361-394), `_build_fence` (397-430), `_build_arena` (435-584). Generates `.tscn`; never hand-edit outputs. |

Related, read-only for this subsystem: `scripts/core/sim.gd` (tick driver, entity registry, attack
tokens), `scripts/combat/combat_entity.gd` (hit application, death), `scripts/core/data_validator.gd`
(enemy/prop schemas, lines 276-357), `scripts/core/game_data.gd` (`REQUIRED_RECORDS`).

## 2. Key classes and APIs

### SoldierEnemy (`class_name SoldierEnemy extends CharacterBody3D`)
- Exports: `entity_id := "soldier_01"` (copied into `CombatEntity.entity_id` by CombatEntity._ready),
  `patrol_route: NodePath` (parent of Node3D children = patrol points), `ai_enabled := true`
  (false: no perceive/decide, combat still runs; every integration test sets it).
- Required child node names: `$CombatEntity`, `$NavAgent` (NavigationAgent3D), `$Visual` (ActorRig).
  Scene also has `BodyShape`, `Anchors/Torso`, `Hurtboxes/{Head,Torso,Legs}`.
- Groups: `"enemies"` (debug panel and autopilot cast members to `SoldierEnemy`).
- State: `record`, `weapon`, `controller: CombatController`, `brain: SoldierBrain`, `facing_yaw`,
  `move_velocity`, `knockback_velocity`, `perception_interval` (60/perception_hz = 12),
  `decision_interval` (60/decision_hz = 6), `_phase_offset = abs(hash(entity_id)) % perception_interval`,
  `path_failures`.
- `sim_step(tick, dt)` (95): `controller.begin_tick` -> perceive if `(tick+offset) % 12 == 0` ->
  decide if `% 6 == 0` (or every tick when dead) with token callables -> consume
  `brain.attack_request` via `controller.request(&"attack", {"action_id": id})` -> `_update_facing`
  -> `_update_movement` -> `_run_hit_queries` -> pools/poise tick (stamina regen only while not guarding).
- `_target()` (116): first `Sim.entities()` entry with `team == PLAYER` (linear scan every call).
- `_sense() -> Dictionary` (124): `{exists, target_id, alive, position, distance (flat), visible,
  facing_deg, target_radius}`. Cone = `sight_half_angle_deg`, or 360 deg once `brain.aware` and
  within 8 m (hard-coded). LOS ray from eye (92% height) to `t.anchor_position()` with mask
  `LAYER_WORLD` only (breakables do NOT block sight).
- Hearing: `_on_any_ability_started` (150) listens to `Events.ability_started`; hostile actor within
  `hearing_radius_m` -> `brain.on_noise(..., certain=false)`. Being hit (`entity.hit_taken`) -> `certain=true`.
- Morale input: `_on_any_entity_died` (165): same-team death within 15 m -> `brain.on_ally_died()` (-10).
- `_update_facing(dt)` (180): tracks `brain.face_point` only in LOCOMOTION, or during the first
  `windup_ticks * tracking_fraction` of an attack; committed afterwards. Turn rate
  `turn_rate_deg_s` (300) or `guard.turn_rate_deg_s` (140) while guarding.
- `_update_movement(dt)` (215): speed = walk if `brain.move_speed >= 0`, run if `< 0`; times
  `controller.move_speed_multiplier()`. Beyond `DIRECT_STEER_DISTANCE` (3 m) it sets
  `agent.target_position` (only when goal moved > 0.5 m) and steers to `get_next_path_position()`;
  falls back to direct steering when the next point is ~at its feet (no navmesh). Avoidance off.
  Gravity 22, knockback decel 30. `_track_progress` (254): < 0.3 m progress in `path_fail_s` (2 s)
  and not within 1 m -> `brain.on_path_failed()`, `path_failures += 1`. Never teleports.
- `apply_knockback(direction, speed)` (271), `weapon_segment_global(action, f)` (279).
- `_run_hit_queries(tick)` (286): ONLY `hit_shape == "weapon_arc"`; capsule sweep via
  `HitQueryAdapter.sweep_capsule`, stable sort, `hit_registry.try_register(instance, 0, ...)`,
  builds `HitEvent` (strength stat, weapon damage multiplier, no `attacker_growth_stage`, no
  `pulse_id`, no clank event), `Sim.queue_hit`.
- `is_guarding()` (338): guard record non-empty AND controller LOCOMOTION AND `brain.aware` AND brain
  state in {ALERT, APPROACH, RECOVER, REPOSITION} AND stamina >= `guard.min_stamina`.
- `get_defense_state() -> DefenseState` (348): `blocking = is_guarding()`, no parry, `apply_guard(record.guard)`.
- `on_entity_died(killer_id)` (363): `Sim.release_all_tokens`, collision_layer 0, hurtboxes off
  (deferred). The corpse stays in the tree and keeps getting `sim_step`.
- Presentation: `flash()`, `get_rig_state()`, `get_debug_info()` (keys used by `ui/debug_panel.gd`).

### SoldierBrain (`class_name SoldierBrain extends RefCounted`)
- `enum AIState { IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION, FLEE, STAGGERED, DEAD }`, `STATE_NAMES`.
- Consts: `TICK_RATE 60`, `ATTACK_FACING_DEG 35`.
- `_init(actor_id, record, seed)`: reads `record.ai`, `attacks`, `attack_weights`, `morale`; own RNG
  seeded `Sim.DEFAULT_SEED ^ hash(entity_id)` (not `Sim.rng`).
- Public vars read/written by actor and tests: `state`, `aware`, `last_known`, `last_seen_tick`,
  `holds_token`, `target_id`, `morale`, `patrol_points`, outputs `move_target` (`Vector3.INF` = stand),
  `move_speed` (0 walk, -1 run), `face_point` (`INF` = face movement), `attack_request`.
- `perceive(tick, snapshot)`, `on_noise(tick, position, source_id, certain)`, `on_ally_died()`,
  `decide(tick, controller_state, my_position, request_token: Callable, release_token: Callable)`,
  `on_path_failed(my_position)`, `state_name()`.
- FSM summary (decide, 117-245): DEAD/STAGGERED override from controller state (release token).
  Morale < `flee_morale` while aware -> FLEE. IDLE -patrol_wait_s-> PATROL -> point reached -> IDLE.
  ALERT: stand `notice_s`, then APPROACH if aware+memory ok, else investigate `last_known` (8 s cap) -> PATROL.
  APPROACH: lose memory -> ALERT; within `attack_range_m + target_radius` and seen, facing <= 35 deg,
  after `strike_ready_tick`: token -> ATTACK (`_choose_attack` weighted) else REPOSITION. Otherwise run to
  `_engage_point` (`engage_distance_m + target_radius` from target, own side).
  ATTACK -> RECOVER when controller leaves ATTACKING; RECOVER backs off, waits random
  `strike_pause_*`, releases token -> APPROACH. REPOSITION orbits at `reposition_radius_m` for 1.5 s.
  FLEE: run 8 m directly away from target, after >= 4 s and morale > `regroup_morale` -> APPROACH
  (morale never rises, so in practice a fleeing soldier never regroups).

### BreakableProp (`class_name BreakableProp extends StaticBody3D`)
- Export `world_id` (also becomes the CombatEntity id; empty -> push_error). Groups: `"breakables"`.
- Required children: `$CombatEntity`, `$Intact`, `$Broken`, any `CollisionShape3D` whose name starts
  with `"Block"` (removed on break), `Hurtboxes/...`.
- `accepts_hit(hit) -> bool` (32): not destroyed, `hit.category in accepted_attack_categories`,
  `hit.attacker_growth_stage >= min_growth_stage`. Rejection -> `HitResult.IMMUNE` "not_permitted".
- `on_entity_died(killer_id)` (41): `_apply_broken_state(true)`, `WorldState.record_destroyed(world_id)`,
  `Events.object_destroyed`, then loot via `WorldState.try_award_loot` + `add_item` + `Events.loot_awarded`.
- `_ready`: if `WorldState.is_destroyed(world_id)` -> broken without debris, `combatant.dead = true`.
- `_apply_broken_state(spawn_debris)` (55): Block shapes disabled + `remove_child` + `queue_free`
  immediately (so a same-frame bake never sees them); hurtboxes off (deferred).
- `_spawn_debris()` (75): first node in group `"debris_pool"`; deterministic RNG `hash(world_id)`;
  layout hard-coded for an 8 m fence along local X.

### DebrisPool, SandboxArena, WorldState, PracticeDummy
- `DebrisPool`: consts `MAX_ACTIVE 40`, `LIFETIME_S 5.0`, `OFFSCREEN_GRACE_S 1.0`; `spawn(transforms:
  Array[Transform3D], velocities: Array[Vector3])`, `active_count()`, `clear_all()`, `spawned_total`.
  Group `"debris_pool"`. Layer `LAYER_DEBRIS (8)`, mask world only. Single fixed plank mesh.
- `SandboxArena`: `nav_region = $Navigation`, `bake_count`, group `"sandbox"`, `player_spawn()` reads
  `Spawns/PlayerSpawn`. `_ready` duplicates the NavigationMesh then `bake_navigation_mesh(false)`
  (synchronous); `_on_object_destroyed` awaits one frame and calls `bake_navigation_mesh(true)` unless already baking.
- `WorldState`: `SCHEMA_VERSION 1`, `deltas`, `inventory`; `get_delta`, `is_destroyed`,
  `record_destroyed(world_id, damage_stage := 1)`, `try_award_loot(world_id) -> bool` (true once),
  `add_item`, `clear()` (debug reset + test `before_each`), `to_save_dict`, `from_save_dict` (rejects other versions).
- `PracticeDummy`: export `entity_id`, group `"dummies"`, children `$CombatEntity`, `$Visual`.

### Engine contract (CombatEntity / Sim) this subsystem relies on
- `CombatEntity` exports `entity_id`, `definition_id`, `team` (0 NEUTRAL, 1 PLAYER, 2 ENEMY),
  `anchor_path`. Enemies can only damage the PLAYER team (`can_damage`), so enemy attacks never hit
  props or allies. Optional actor hooks: `get_defense_state`, `accepts_hit`, `apply_knockback`, `on_entity_died`.
- `Sim.register_actor(id, node)` in `_ready`, `unregister_actor` in `_exit_tree`; actors stepped in
  sorted-id order, skipped when `not node.can_process()`. Tokens: `request_token(target, holder, max)`,
  `release_token`, `release_all_tokens`, `token_holders`.
- Physics layers (`HitQueryAdapter`): WORLD 1, ACTORS 2, HURTBOX 4, DEBRIS 8, BREAKABLE 16.

## 3. Data flow and invariants

1. Data: `soldier.json` -> `GameData` -> `Combatant.from_record` (in CombatEntity) and `record` (actor).
   The validator rejects unknown keys and requires every `ai.*` field listed in
   `data_validator.gd` 307-326, plus `weapon`, `weapon_pivot_m`, `attack_origin_m`, `arm_length_m`,
   `attacks` (non-empty), `poise`. `archetype` must be one of `soldier, archer, mage, wolf, ogre, boss`.
   `attack_weights` length must equal `attacks`.
2. Tick: Sim -> actor `sim_step` -> brain (pure) -> controller -> movement -> `Sim.queue_hit` ->
   sorted resolution -> `CombatEntity._apply` -> `Events.hit_resolved` / `entity_died` /
   `on_entity_died` hook -> BreakableProp -> `WorldState` + `Events.object_destroyed` -> SandboxArena re-bake.
3. Invariants tests rely on:
   - Determinism: brain RNG seeded from entity id; perception phase offset from id hash; no use of
     wall-clock time. Tests: `test_attack_tokens_limit_attackers` (3 soldiers, <= 2 holders),
     `test_soldier_engages_with_readable_attacks` (attack within 10 s, strafe tracking limit).
   - Hidden target -> brain uses `last_known`, never live position (`test_brain_uses_last_known_position_when_target_hidden`
     constructs `SoldierBrain.new("soldier_x", record, 7)` and sets `brain.state` directly).
   - Guard: `s.brain.aware = true; s.brain.state = RECOVER` -> `s.is_guarding()`; front BLOCKED, back
     HIT, worn guard + heavy -> GUARD_BROKEN and `controller.state == STAGGERED`.
   - Breakables: `test_fence_breaks_once_and_loot_once` (destroy once, loot once, a new instance with the
     same `world_id` loads broken and gives no loot); `test_destroyed_breakable_at_load_is_not_a_nav_obstacle`
     (pre-destroyed `sandbox.fence_01`, path from (10,0,34) to (14,0,34) < 5 m).
   - Debris: `test_debris_pool_caps_and_cleans_up` (`DebrisPool.new()`, `active_count() <= MAX_ACTIVE`, gone after `LIFETIME_S`).
   - Scene/node names: arena children `Soldier01`, `Player`, `PatrolRoute`, `Spawns/PlayerSpawn`,
     `Navigation`, `DebrisPool`; ids `soldier_01`, `sandbox.fence_01`, `dummy_01`, `dummy_behind_wall`
     (`test_obstacle_route.gd`, `autopilot.gd` 273-288, `test_ai_and_world_fixes.gd`).
   - `tests/integration_suite.gd` helpers `spawn_soldier(pos, yaw, id, ai)` / `spawn_fence(pos, world_id, yaw)`
     set `entity_id` / `world_id` / `ai_enabled` before `add_child`; keep those exports.
   - `GameData.REQUIRED_RECORDS` includes `enemy.soldier`, `prop.fence_wood`, `prop.practice_dummy`.
4. Enemy attacks are ordinary `ActionDef`s (`kind: "enemy_attack"`, `category`, `hit_shape: weapon_arc`,
   `tracking_fraction`, `interrupt_policy`, `movement` multipliers). The controller validates and
   commits them; the actor only draws the sweep. Spec floor: windup >= 0.45 s, major >= 0.8 s.

## 4. Extension points: how to add M2-M5 content

### 4.1 Reusable enemy base (do this first, one package, before any archetype)
Split `SoldierEnemy` into:
- `scripts/actors/enemy_actor.gd` `class_name EnemyActor extends CharacterBody3D`: everything in
  SoldierEnemy except guard and brain construction. Keep `entity_id`, `patrol_route`, `ai_enabled`,
  `brain`, `controller`, `record`, `get_debug_info()`, group `"enemies"`. Virtual hooks:
  `_make_brain() -> EnemyBrain`, `_sense_extra(snapshot)`, `_is_guarding() -> bool` (default false),
  `_custom_movement(dt) -> bool` (lunge/charge override), `_on_hit_query_shape(a)` dispatch.
  Generalize `_run_hit_queries` to a `match a.hit_shape` like `giant_player.gd` 433-463
  (`weapon_arc`, `cylinder_pulse`, plus new `projectile`), and factor HitEvent building into
  `_build_hit(a, cand, pulse_id, tick)`.
- `scripts/ai/enemy_brain.gd` `class_name EnemyBrain extends RefCounted`: today's perception/memory,
  `on_noise`, morale, token helpers, `_set_state`, `_ticks`, outputs. Archetype brains override
  `_decide_engaged(...)` and `_choose_attack()`. Keep the AIState enum shared so the debug panel works.
- `SoldierEnemy extends EnemyActor` and `SoldierBrain extends EnemyBrain` keep their class names,
  public fields and `AIState` so existing tests pass unchanged.
- Change `ui/debug_panel.gd` 68-75 and `autopilot.gd` `_alive_soldier` to cast to `EnemyActor`.
- Validator: move archetype-specific keys into an optional `"tactics": {}` dict per archetype in
  `data_validator.gd` (e.g. `tactics.preferred_range_m`), and make `guard`, `weapon_pivot_m`,
  `arm_length_m` optional for non-melee. Civilians do not fit the `enemy` type: add record type
  `"npc"` (or `"civilian"`) to `RECORD_TYPES` and `schema_for`.
- Scenes: add a generic `_build_humanoid(name, script, def_id, dims, palette)` in
  `tools/build_scenes.gd` and call it per archetype; ogre/boss use a scaled variant.

### 4.2 Archetypes (new files each: `data/enemies/<x>.json`, `data/abilities/<x>_*.json`, `scripts/actors/<x>_enemy.gd`, `scripts/ai/<x>_brain.gd`, a builder fn)
- **Wolf** (`archetype: wolf`, team ENEMY, low height ~0.9 m, `max_attackers` shared token pool):
  brain picks a flank point at +/-70-110 deg from `perception.facing_deg` of the giant (needs the
  giant's forward in the snapshot: add `"target_forward"` in `_sense`). Lunge = `enemy_attack` with
  >= 0.45 s windup and a forward dash during ACTIVE. Movement today is `move_speed_multiplier() *` a
  speed toward `brain.move_target`, and the brain clears `move_target` in ATTACK, so add an action
  param (e.g. `"lunge": {"speed_mps": 9, "phase": "active"}`; validator schema needed) and apply it in
  the actor's `_custom_movement`. Dodge-then-punish: long recovery (>= 0.8 s).
- **Archer** (`archetype: archer`): keep 12-20 m. Brain state REPOSITION targets the nearest
  `"cover_point"` / `"elevation_point"` marker (group, authored in district scenes) inside the band
  with LOS; fall back to a ring point. Needs a projectile system (none exists: only the
  `"projectile"` category and `Projectile` tag): add `scripts/combat/projectile_pool.gd` (pooled, stepped
  from Sim or by the shooter, sphere-cast each tick, queues `HitEvent` with `category: "projectile"`).
  Staggered launches: a second token kind in Sim, e.g. `request_launch_slot(target, holder, min_gap_ticks)`
  (global per-target cooldown so two archers never release on the same tick).
- **Mage**: `category: "magic"` actions (attacker_stat = intellect as in the giant's `_queue_hits`);
  telegraph = long windup + an `Events` signal for a ground marker (presentation only). Slow = needs a
  status-effect hook on the player (spec 8; does not exist yet). Barrier = an ally buff (temporary
  armor or block flag on an ally's DefenseState). Casting states: if the action `kind` is `ability`
  the controller enters CASTING, not ATTACKING; see pitfall 6.
- **Ogre**: high `poise.threshold`, `interrupt_policy: "super_armor"` on its strikes (supported by
  `CombatController.apply_stagger`, unused so far), slow `turn_rate_deg_s`, windups >= 0.8 s,
  long recovery. No guard block. Larger capsule -> needs its own nav profile (4.4).
- **Ogre boss** (`archetype: boss`, health 1500, poise 150): `scripts/ai/ogre_boss_brain.gd` with a
  `phase := 1` and `_phase_changed := false`; in `decide`, `if not _phase_changed and health <= 0.5 * max:`
  set phase 2 once and emit a new `Events.boss_phase_changed(tick, id, phase)`. The brain needs health
  in the snapshot (add `"self_health_frac"` in `_sense_extra`). Phase 1 alternates a two-hit melee
  (`chain` of two enemy_attacks) and a telegraphed `cylinder_pulse` slam. Phase 2 adds a charge:
  `_custom_movement` drives a straight run; detect the wall with `HitQueryAdapter.first_world_hit`
  or `get_slide_collision` against LAYER_WORLD and then force a long recovery action
  (`boss_wall_recover`, e.g. 2.5 s, `movement` 0) = the punish window. Ignore morale (`flee_morale: 0`).
  Test: drop health below 50% twice / heal back, assert the phase event fires exactly once.
- **Civilians** (`scripts/actors/civilian.gd`, team NEUTRAL, not lockable, no controller attacks):
  tiny state machine IDLE -> FLEE -> SAFE. On noise/giant within N m, pick the nearest node in group
  `"safe_marker"` once, call `agent.target_position` once (and only re-path on path failure), walk the
  stored path; at the marker, disable processing (`process_mode = DISABLED`, Sim then skips it).
  Spec acceptance: every flee destination must be reachable (assert with `NavigationServer3D.map_get_path`).

### 4.3 Size tactics
Add to `_sense`: `"target_height"` (from `giant.profile.height_m`) and the giant's growth stage. In
`EnemyBrain`, compute `size_ratio = target_height / own height_m`. Data per record:
`tactics.outmatched_ratio` (e.g. 4.0). Outmatched infantry: instead of APPROACH, retreat to the
nearest `"formation_point"` marker and hold guard (morale damage stays as is). Ranged units: when
choosing a position, reject candidates within `tactics.spread_m` (e.g. 6 m) of another ranged ally
(iterate a cached per-encounter list, not `get_nodes_in_group` every decision).

### 4.4 Navigation for a 400 x 400 m valley (single-threaded web)
- Do not bake at load. The sandbox bakes 120 m at `cell_size 0.25` synchronously in `_ready`; a
  400 m valley at that resolution is ~11x the area and the web export has no worker threads, so any
  bake (including `bake_navigation_mesh(true)`) costs main-thread time. Bake offline in
  `tools/build_scenes.gd` (call `NavigationServer3D.bake_from_source_geometry_data` or
  `nav.bake_navigation_mesh(false)` in the tool, then save the NavigationMesh as `.tres`) and ship it.
- Use one NavigationRegion3D per district (e.g. 100 x 100 m tiles) with `cell_size` 0.3-0.5; keep
  `agent_radius 0.5 / height 2.0` for humans. Ogre/boss get a second baked mesh (radius ~1.2,
  height ~3.5) on `navigation_layers` bit 2, and their NavAgent uses that layer.
- Breakables that open paths: never re-bake in the valley. Bake with the blocker present and add an
  authored `NavigationLink3D` (or a small passage NavigationRegion3D) across the opening, disabled
  until broken; enable it in `BreakableProp._apply_broken_state` (also on load). Make
  `SandboxArena`'s re-bake opt-in (sandbox only).
- AI LOD: an `EncounterDirector` (or per-actor tiering every 30 ticks): near (< 40 m or in the active
  encounter) full rate; mid (40-90 m) perception 1 Hz, decisions 2 Hz, no re-path; far / outside the
  district: `process_mode = PROCESS_MODE_DISABLED` (Sim's `can_process()` check skips `sim_step`; the
  CharacterBody stops moving). Keep the tier choice deterministic (distance only). Also free or disable
  corpses after a few seconds (they currently run `move_and_slide` forever).

### 4.5 Persistent gates, trees, tree-weapon obstacle
- Practice gate: `data/props/gate_practice.json` (`category: breakable`, `min_growth_stage: 1`,
  `accepted_attack_categories: ["melee","ability","siege"]`) + `_build_gate_practice()`; same
  `BreakableProp` script, `BlockShape*` children, NavigationLink as above.
- Fortified gate: `category: "structural"`, `min_growth_stage: 4` (works today through `accepts_hit`).
  For "gate_breach" interaction add a check on hit tags (e.g. `Siege`) in a subclass
  `StructuralProp extends BreakableProp` that also supports multiple `damage_stages` (health
  thresholds -> `Stage1/Stage2...` visuals) and calls `WorldState.record_destroyed(id, stage)` / a new
  `WorldState.record_stage(id, stage)`; give the player feedback for IMMUNE "not_permitted" hits
  (HUD message "Too small to breach").
- Trees: `prop.tree_*` breakable whose broken state leaves a log `Pickup` (the tree weapon,
  `interaction_permissions: tree_weapon`, stage 3). Debris layout must come from data, see pitfall 8.
- Tree-weapon obstacle (the "revisit earlier obstacle"): a `BreakableProp` with
  `accepted_attack_categories` limited to a new category or tag carried only by tree-weapon attacks
  (add to `ATTACK_CATEGORIES` or check a `TreeWeapon` tag in a subclass `accepts_hit`).
- Saves: `WorldState.to_save_dict` already carries `destroyed/damage_stage/loot_awarded`; M3/M4
  checkpoints must write it through `SaveIO` and stop `main.gd` 168 from clearing deltas on a
  normal (non-debug) restart in the Valley.

## 5. Hotspots and conflict avoidance

| Hotspot | Why many features touch it |
| --- | --- |
| `tools/build_scenes.gd` `_ready` + `_build_arena` | Every new scene/archetype/prop/district adds a builder and a `_save` line. |
| `scripts/core/data_validator.gd` `schema_for` (enemy 276-330, prop 331-357), `ARCHETYPES`, `ATTACK_CATEGORIES`, `TAGS` | Every new data key. |
| `scripts/actors/soldier_enemy.gd` `sim_step`/`_sense`/`_run_hit_queries` | Every archetype wants a variant. |
| `scripts/ai/soldier_brain.gd` `decide` | Every tactic. |
| `scripts/core/events.gd` | New signals (boss phase, telegraphs, gate breach). |
| `scripts/core/sim.gd` tokens | Launch slots, LOD. |
| `GameData.REQUIRED_RECORDS`, `ui/debug_panel.gd`, `scripts/debug/autopilot.gd` | New required ids, casts to SoldierEnemy. |

Proposal: (1) land the EnemyActor/EnemyBrain refactor plus validator `tactics`/`npc` support plus a
`hit_shape` dispatcher as one serial package before archetypes start. (2) Split `build_scenes.gd`
into `tools/builders/{actors,props,valley_*}.gd` static functions with a registry array in
`build_scenes.gd`, so each package appends one line. (3) Each archetype owns its own files and
data; shared files are edited only by the base package. (4) Add new `Events` signals in one
up-front commit. (5) Keep the sandbox (`sandbox_arena.tscn`, `Soldier01`, `sandbox.fence_01`)
untouched; the Valley is a new scene, so existing tests stay valid.

## 6. Pitfalls and gotchas

1. `_target()` returns the first PLAYER-team entity; `_sense` scans `Sim.entities()` each call (O(n) per
   enemy at 5 Hz). Cache the player for large encounters.
2. Sight LOS uses `LAYER_WORLD` only: enemies see through intact fences/gates (layer 16). Decide
   whether gates should block sight; then add `LAYER_BREAKABLE` to the mask.
3. 360-degree awareness radius (8 m) and ally-death radius (15 m) are hard-coded, not data.
4. Morale: -10 per nearby death with no 2 s debounce, no commander rule, never recovers, so FLEE never
   regroups (`regroup_morale 45` unreachable after dropping below 25). FLEE target is "8 m straight
   away" with no reachability check; spec requires a reachable destination. `on_noise` ignores FLEE.
5. Token release: tokens are released on STAGGERED/DEAD/FLEE/RECOVER end, but a brain whose
   `ai_enabled` is toggled off keeps `holds_token`. `Sim.clear_pending()` also clears tokens.
6. Brain ATTACK -> RECOVER triggers when controller state != ATTACKING after 0.05 s. An enemy action
   of `kind: "ability"`/`"ultimate"` puts the controller in CASTING, so the brain would leave ATTACK
   immediately and `_update_facing` would stop turning. Use `kind: "enemy_attack"` or extend the check.
7. Soldier hit queries handle only `weapon_arc`; a `cylinder_pulse` enemy action silently hits
   nothing. Enemy HitEvents never set `pulse_id`, `attacker_growth_stage`, `weak_point`,
   `flat_penetration`, and use strength even for magic.
8. Debris layout in `BreakableProp._spawn_debris` is fence-specific (8 m along local X, fixed plank
   mesh in DebrisPool). Gates/trees need `debris_length_m`/shape in data.
9. Breakable health is not persisted; only `destroyed`/`damage_stage` (always 1)/`loot_awarded`.
   `record_destroyed` and `try_award_loot` both create the delta; a delta with only
   `loot_awarded` is impossible today but `is_destroyed` would read false.
10. Breakables have no controller, so `CombatEntity.stagger` on them is a no-op; their
    `combatant.dead` is set manually on load-broken.
11. Only shapes named `Block*` are removed on break. A builder that names the shape `Shape` keeps
    blocking forever. The removal is immediate (not deferred) on purpose.
12. `SandboxArena` re-bakes on every `object_destroyed`, even for objects outside the navmesh, and
    skips the re-bake if one is in progress (a second break during a bake is lost). Nav mesh
    `geometry_collision_mask` includes ACTORS: static dummies are baked as holes; `PARSED_GEOMETRY_STATIC_COLLIDERS`
    means only StaticBody children of `Navigation` count (actors placed outside it are ignored).
13. The NavigationMesh sub-resource is shared between instances; `_ready` duplicates it. Any new
    region scene must do the same or bake offline.
14. Direct steering within 3 m and avoidance off: enemies bump physically (mask includes ACTORS) and
    can clump; with 12 combatants consider NavigationAgent avoidance or a separation term.
15. Corpses stay in the tree, registered with Sim, run `sim_step` (decide runs every tick when dead).
16. Validator: unknown keys are errors and every `ai.*` field is required, so new archetype keys must
    be added to the schema in the same change or the game shows the data-error screen.
17. `build_scenes.gd` overwrites `.tscn` files; the arena sets `world_id`/`entity_id` on instances
    via `set()`; duplicate ids trigger `Sim: duplicate entity_id` push_errors and the second entity is not registered.
18. Debug resets (`main.gd` 168) and every integration test call `WorldState.clear()`; Valley
    checkpoint restore must not.
