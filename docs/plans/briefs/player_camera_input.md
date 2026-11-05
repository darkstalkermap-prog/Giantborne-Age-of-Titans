# Brief: player actor, camera, input, presentation

Scope: everything a planner or implementer of M2-M5 needs to know about the player giant
without re-reading the code. Written against `main` at `e89001f`. Line numbers are for that commit.

## 1. Files and responsibilities

| File | Responsibility |
| --- | --- |
| `scripts/actors/giant_player.gd` (679 lines) | `GiantPlayer`: all player glue. It turns intents into controller requests, handles movement, sprint, facing, dodge, hit queries, lock-on and stats, and reads profile and weapon data. |
| `scripts/presentation/camera_rig.gd` | `CameraRig`: third-person and first-person camera, swept follow arm, lock-on framing, zoom, shake and head bob. |
| `scripts/presentation/actor_rig.gd` | `ActorRig`: procedural limb posing driven by `actor.get_rig_state()`. It is shared with soldiers. |
| `scripts/presentation/hit_feedback.gd` | `HitFeedback`: damage numbers, flashes, sparks, the Footfall ring, camera shake and rumble. It listens to `Events` only. |
| `scripts/adapters/input_router.gd` | `InputRouter`: raw `InputEvent` to per-tick intents (edges and holds), input contexts, pad combos, stick flicks and taps, and test injection. |
| `scripts/adapters/input_bindings.gd` | `InputBindings`: builds the `InputMap` from JSON plus overrides. It also holds the `ACTIONS` and `COMBO_ACTIONS` lists, labels and helpers. |
| `data/player/giant.json` | Player record: attributes, resources, regen, poise, crit, `growth_profile`, `weapon` and `loadout`. |
| `data/player/ancestry_neutral.json` | Placeholder ancestry with no modifiers. Nothing reads it except the validator reference. |
| `data/growth/growth_0{1,2,3}.json` | Stage profiles: capsule, speeds, reach, camera, lock, weapon pivot, arm length, permissions and `unlocks` (empty). |
| `data/weapons/club.json`, `soldier_sword.json` | Weapon records: `family`, `damage_multiplier`, `length_m` and `hit_radius_m`. |
| `data/input/default_bindings.json` | Default bindings for every action in `InputBindings.ACTIONS`, plus deadzones. |
| `tools/build_scenes.gd` `_build_giant()` (lines 218-290) | Generates `scenes/player/giant.tscn`: body, collision, entity, anchors, hurtboxes, the visual rig, the club mesh and the camera. |

## 2. Key classes and APIs

### GiantPlayer (`class_name GiantPlayer extends CharacterBody3D`)

- **Export:** `definition_id := "player.giant"`.
- **Node names the code relies on:** `$CombatEntity`, `$CameraRig` (child `Camera3D`), `$Visual` (`ActorRig`) and `$BodyShape` (a `CapsuleShape3D`). `InputRouter` is created at runtime as child `"InputRouter"`.
- **Group:** `"player"`. `HitFeedback._player_rig`, `Hud`, `main.gd` and `Autopilot` find the player with `get_first_node_in_group("player") as GiantPlayer`. The entity id is `"player"`, set in the generator. `HitFeedback` line 111 hard-codes `attacker_id == "player"`.
- **Constants:** `GRAVITY 22`, `KNOCKBACK_DECEL 28`, `OUT_OF_WORLD_Y -30` (teleport to `spawn_transform`), `SOFT_TARGET_CONE_DEG 45`.
- **Public state that tests, HUD and autopilot use. Keep these names:**
  - `router`, `controller`, `lock` (a `LockOnTracker`; tests read `lock.target_id` 15 times), `entity`, `camera_rig`;
  - `profile` (the growth record `Dictionary`; `SoldierEnemy` line 144 reads `giant.profile.capsule_radius_m`);
  - `weapon` (a `Dictionary`), `record`, `growth_stage` (`Hud` line 360 reads it), `stats`, `facing_yaw`, `sprinting`.
- **Geometry cache, filled by `_read_geometry()` only:** `weapon_pivot`, `attack_origin`, `arm_length`, `weapon_length` and `weapon_radius`.
- **`_ready()`, in this order:**
  1. load `record`, `profile` and `weapon`, and set `growth_stage`;
  2. `_read_geometry`;
  3. `_build_controller`;
  4. create the router;
  5. `_apply_profile`;
  6. `camera_rig.setup(self, profile)`;
  7. set `lock.range_m` and `half_angle_deg` from the profile;
  8. `rig.set_weapon_pivot`;
  9. connect signals;
  10. `Sim.register_actor`.
- **Methods:**
  - `_build_controller()`: builds `CombatController`, sets `controller.growth_stage`, and maps `loadout` keys `light`, `heavy`, `dodge`, `block`, `jump`, `ultimate` and `slot_1..slot_8`. It then fills `controller.library` with `_add_action_chain(id)`, which follows `chain_next`, and sets `sprint_def` and `controller.block_def`.
  - `_apply_profile()`: duplicates the capsule, sets its radius and height, sets `body_shape.position.y = height/2`, `floor_snap_length = max(0.3, step_height_m)` and `floor_max_angle = 46°`.
  - `sim_step(tick, dt)`: the 60 Hz entry point. It runs `router.consume()`, then sets `controller.on_floor` and `block_held`, then `begin_tick`, then `_handle_meta` and `_handle_actions` (unless dead), then `resume_held_block`, `_update_sprint`, `_update_facing`, `_update_movement`, `_run_hit_queries`, the pools and poise ticks, `_maintain_lock`, and finally the out-of-world reset.
  - `_handle_meta(intents)`: handles the edges `camera_toggle`, `lock_press` and `lock_release`, `target_left` and `target_right` (switch target while locked, otherwise `camera_rig.zoom(±1)`), `stick_flick_*` (third-person lock), `stick_tap_*` (first-person lock), `sprint_press` (toggle) and **`interact`, which is a stub that only posts a HUD message (line 191)**.
  - `_handle_actions(intents)`: maps edges `light`, `heavy`, `dodge`, `jump`, `block_press`, `block_release` and `ultimate`, plus `slot_N`, to `controller.request(&"slot", {"slot": N})`.
  - `_on_action_started(action, iid)`: emits `Events.ability_started`, then handles side effects by `action.kind`:
    - jump sets `velocity.y`;
    - dodge picks `dodge_direction`;
    - block snaps facing;
    - attacks snap facing to `_attack_facing_yaw()` and set `windup_base_yaw`.
  - `_on_request_rejected(kind, id, reason)`: emits `Events.action_rejected` and a HUD text for `stamina`, `cooldown`, `empty_slot` and `locked`.
  - `_move_dir_world(input)`: movement relative to the camera yaw, or to the target while locked in third person.
  - `_update_sprint`: hold and toggle modes, `drain_per_s`, a lockout until `resume_threshold`.
  - `_update_facing`: turns at `turn_rate_deg_s`. It turns instantly in first person, and it rotates only when `controller.can_rotate()`.
  - `_soft_target_offset()`: during windup it nudges facing up to `action.soft_target_max_deg` (10°) toward the best visible enemy. Candidates must lie within `melee_reach_m + 1.5` and a 45° cone. Visibility uses `HitQueryAdapter.line_clear`.
  - `_update_movement`: speed is `walk_speed_mps × controller.move_speed_multiplier() × sprint speed_mult`. Acceleration comes from the profile, at ×0.35 in the air. Gravity applies, knockback decays, then `move_and_slide()`.
  - `_dodge_speed()`: an ease-out curve covering `profile.dodge_distance_m` over `action.active_ticks`.
  - `apply_knockback(dir, speed)`, `get_defense_state() -> DefenseState`, `on_entity_died(killer)` and `flash(strength, color)`: the combat entity contract.
  - `weapon_segment_global(action, f)`: uses `AttackGeometry.arc_point/local_direction/segment_local(weapon_pivot, dir, arm_length, arm_length+weapon_length)`.
  - `_run_hit_queries(tick)`: `"weapon_arc"` runs a capsule sweep from the previous segment to the current one (`HitQueryAdapter.sweep_capsule`), plus a one-shot wall clank. `"cylinder_pulse"` runs once on the first active tick: centre at `height_m/2`, `a.radius_m`, `a.height_m`, occlusion origin at `pos + 0.8 up`, `pulse_id 1`, then `Events.area_pulse`.
  - `_queue_hits(cands, a, pulse_id, tick)`: sorts the candidates deterministically, dedups them through `hit_registry`, and builds a `HitEvent`. The event uses `weapon.damage_multiplier` when `a.uses_weapon`, `intellect` for magic and `strength` otherwise, `c.height_m`, and `attacker_growth_stage = growth_stage`. It then calls `Sim.queue_hit`.
  - **Lock-on:** `locked_entity()`, `_eye()` (height × `eye_height_ratio`), `_yaw_to`, `_visible` (a ray from the eye against `LAYER_WORLD`), `_gather_candidates(with_screen)`, `_try_lock()`, `_switch_target(dir)`, `_release_lock(reason)`, `_sync_lock(id, reason)` (sets `camera_rig.lock_target` and emits `Events.lock_target_changed`), `_maintain_lock(dt)` and `_on_any_entity_died`.
  - `get_rig_state() -> Dictionary`: returns `state`, `action`, `phase`, `phase_fraction`, `speed`, `dead`, `staggered`, `dodging` and `dodge_local`. `get_debug_info()` feeds the F3 panel.

### CameraRig (`class_name CameraRig extends Node3D`, `top_level = true`, `process_priority -10`)

- **Fields:** `mode` (`Mode.THIRD_PERSON` or `FIRST_PERSON`), `yaw`, `pitch`, `player`, `profile`, `desired_distance`, `current_distance`, `lock_target: CombatEntity` and `obstructed`. Tests read `yaw`, `pitch`, `camera`, `obstructed`, `current_distance`, `aim_forward()` and `is_first_person()`.
- **Constants:** pitch clamps (third person −70..40, first person −85..85), `COLLISION_RADIUS 0.35`, `RESTORE_SPEED 6`, lock pitch −35..8 (−48 for small targets), `LOCK_ORBIT_DEG 32` (orbit ramps between 12 m and 3 m), `FP_ASSIST_*` and `FP_HIDDEN_LAYER 2`.
- **API:**
  - `setup(player, profile)`: sets `desired_distance = current_distance = camera_distance_m`, the FOV and `current`, and restores the mode from `Settings.session["camera_mode"]`.
  - `toggle_mode()`, and `set_mode(m, announce)`: sets the cull mask, stores the mode in the session, emits `Events.camera_mode_changed`, and resets `current_distance` to 0.5 when entering third person.
  - `zoom(step)`: ±0.75 m within `camera_zoom_min_m..max_m`.
  - `add_shake(a)`, `aim_forward()` and `is_first_person()`.
- **Per frame (`_process`):**
  - `_apply_look`: mouse input from `player.router.take_look_delta()`, stick input from `Input.get_vector("look_*")`. A third-person lock calls `_frame_lock_target` instead.
  - `_update_transform`:
    - first person: eye = position + height_m × eye_ratio, plus 0.18 m forward, plus head bob;
    - third person: one rigid arm from the pivot (`camera_pivot_height_m`) to `pivot + right×camera_shoulder_offset_m + back×desired_distance`, swept with a sphere (`_sweep`, `OCCLUDER_MASK`). It retracts instantly and restores at 6 m/s.
- **Profile keys read live each frame:** `height_m`, `eye_height_ratio`, `camera_pivot_height_m`, `camera_shoulder_offset_m`, and zoom min/max (in `zoom`). `camera_distance_m` is read only in `setup()`.

### ActorRig (`class_name ActorRig extends Node3D`)

- **Exports:** `weapon_arm_path`, `off_arm_path`, `leg_left_path`, `leg_right_path`, `torso_path`, `body_path`, idle, block and off poses, `stride_length_m` and `leg_swing_rad`.
- **API:**
  - `set_weapon_pivot(local)`: places `ShoulderR` at the pivot and mirrors it onto `ShoulderL`.
  - `flash(strength, color)`.
  - `_process`: poses `weapon_arc` attacks exactly through `AttackGeometry.pose_for`, so the visible swing matches the hit sweep during ACTIVE. It hard-codes raise-and-slam poses for `cylinder_pulse`, and also poses block (or `s.guarding`), dodge, walk swing, death fall and stagger wobble.
- It duplicates every `material_override` at `_ready` so flashes stay per actor.

### HitFeedback

- Pooled 24 `Label3D`s, 6 sparks and one torus ring.
- Handlers: `_on_hit_resolved`, `_on_clank` and `_on_area_pulse`. `_on_area_pulse` scales the ring to the pulse `radius` and adds shake 0.55.
- `_rumble(weak, strong, s)`.
- Purely presentational.

### InputRouter (`class_name InputRouter extends Node`)

- **Context:** `static var context` (`GAMEPLAY`, `MENU` or `TEXT`), shared globally, with `set_context()`.
- **`consume() -> {edges: Array[StringName], move: Vector2, block_held, sprint_held, lock_held}`:** called once per tick by the player. It also detects flicks and taps (`FLICK_ON 0.75`, `FLICK_OFF 0.35`, `FLICK_MAX_TICKS 6`, `TAP_RETURN_TICKS 15`).
- **Edge vocabulary:**
  - attacks and defence: `light`, `heavy` (`heavy_modifier`+light, or `attack_heavy`), `block_press`, `block_release`, `dodge`, `jump`;
  - targeting: `lock_press`, `lock_release`, `target_left`, `target_right`, `stick_flick_{left,right}`, `stick_tap_{left,right}`;
  - other: `interact`, `sprint_press`, `camera_toggle`, `slot_1..slot_8`, `ultimate`.
- **Pad combos:** while `ability_modifier` (LT) is held, the pad bindings of `COMBO_ACTIONS` fire `slot_N` or `ultimate` and swallow the event.
- **Injection, for tests and autopilot:** `use_injection`, `inject_edge(e)`, `inject_light_attack()`, `set_injected_hold(key, held)` (keys `&"block"`, `&"sprint"`, `&"heavy_modifier"`, `&"lock"`), `set_injected_move(v)`, `take_look_delta()` and `clear()`.

### InputBindings (static)

- `ACTIONS` (the master list), `COMBO_ACTIONS`, `LABELS`, and the button and axis tables.
- Methods: `validate_event_dict`, `event_from_dict`, `event_to_dict`, `apply(defaults, overrides)`, `current_events`, `describe_action` and `short_pad_label`.

### Neighbouring APIs the player depends on

- **`CombatController`:**
  - `state` (enum `LOCOMOTION, ATTACKING, BLOCKING, DODGING, CASTING, STAGGERED, GRABBED, EXECUTING, DEAD`), `growth_stage`, `loadout`, `library`, `block_def` and `recovery_scale`;
  - `request(kind, params)`, `begin_tick`, `can_rotate`, `move_speed_multiplier`, `phase`, `active_fraction` and `resume_held_block`;
  - signals `action_started`, `request_rejected`, `action_ended`, `state_changed` and `staggered`.
  - The `"locked"` rejection is `def.unlock_stage > growth_stage` (line 262).
- **`Combatant.from_record`** derives `height_m`, the Endurance and Intellect pool bonuses, and the Constitution poise threshold **once**.
- **`CombatEntity._ready`** reads `height_m` from `record.growth_profile` (combat_entity.gd lines 60-62).
- **`Events.growth_changed(tick, entity_id, old, new)`** already exists, but **nothing emits it**.

## 3. Data flow and invariants

1. **Sim ownership.** All gameplay mutation happens in `sim_step` at 60 Hz, in entity-id order. `CameraRig`, `ActorRig`, `HitFeedback` and the HUD run in `_process` and must never mutate combat state. One exception: the camera writes its own `yaw` and `pitch`, which the player reads as aim.
2. **Visible swing equals tested swing.** `ActorRig` uses the same `AttackGeometry` with the same `weapon_pivot`. During ACTIVE, `_arm` is set exactly, not lerped. Any change to arm length or weapon length must keep the mesh (shoulder → hand at local z −1.5 → club 1.85 m) consistent with `arm_length` and `weapon_length`.
3. **Deterministic hits.** Candidates are sorted by sub-step, then distance, then entity id. Crits use only `Sim.rng`. `HitRegistry` dedups per `(instance, pulse, target)`.
4. **Costs are committed once** in `CombatController._accept`. Rejected requests spend nothing. The player only reacts in `_on_action_started`.
5. **Lock state is mirrored.** `lock` is the source of truth. `camera_rig.lock_target` and `Events.lock_target_changed` are updated only through `_sync_lock`.
6. **Camera never penetrates.** `current_distance` is always at most the swept safe length. Entering third person starts at 0.5 m and grows out.
7. **Context gating.** No edges flow when `context != GAMEPLAY`, and hold mode re-reads the polled key state.
8. **Data is validated strictly** (`DataValidator`). Unknown keys are errors. `growth_profile` requires most fields, and `weapon_pivot_m` is required. `interaction_permissions` must come from `INTERACTION_PERMISSIONS`. `unlocks` must reference actions. Weapon `family` must be in `WEAPON_FAMILIES = club, sword, hammer, axe, fists`, which has **no "tree"**. Player `loadout.slots` must have exactly 8 entries.
9. **What tests rely on (15 suites, 1133 checks):**
   - `integration_suite.spawn_player()` instantiates `scenes/player/giant.tscn`, then sets `p.router.use_injection` and `p.camera_rig.yaw`.
   - Tests use `p.router` about 68 times, plus `p.controller.{state, elapsed, instance_id, action_id, parry_available, cooldowns}`, `p.entity.combatant`, `p.lock.target_id`, and `p.camera_rig.{yaw, pitch, camera, obstructed, current_distance, aim_forward, is_first_person}`.
   - `test_camera_review_fixes.gd` lines 30-33 hard-code the node paths `Visual/Body/Torso/{Chest,Belt,Head}` and `Visual/Body/ShoulderR/Forearm`.
   - The worked damage numbers (light 37, heavy 66, Footfall 44 against armor 25) assume stage-1 height 3.6576 m (`M_size = 1`), Strength 10 and the club multiplier 1.0.

## 4. Extension points: how to add the M2-M5 features

### 4.1 Runtime growth, stages 1-3

Today only the stage named in `giant.json.growth_profile` (`growth.01`) is ever loaded. Stage values are applied once in `_ready`.

**Read from the profile at load** (these will follow a profile swap if each consumer is re-applied):

| Profile key | Consumer |
| --- | --- |
| capsule | `_apply_profile` |
| walk, acceleration, turn rate, dodge distance, melee reach | read live from `profile` on every use |
| lock range and angle | copied into `lock` in `_ready` |
| camera | `setup`, plus live reads |
| weapon pivot, attack origin, arm length | `_read_geometry` cache |

**Hard-coded to stage 1:**
- **The generator** (`_build_giant`): capsule 0.85 / 3.66, `Anchors/Torso` at y 2.3, hurtboxes `Legs`, `Torso` and `Head` at sizes and positions for 3.66 m, all visual meshes, shoulders at (±0.82, 2.9), and the club mesh length 1.85.
- **`Combatant.height_m`**, set once at entity `_ready`. It drives `M_size`, poise scale, `_eye()`, the `HitEvent.attacker_height_m` and `DefenseState.height_m`.
- **`jump.json` `velocity_mps: 6.5`.** `_on_action_started` uses `action.param("velocity_mps", profile.jump_velocity_mps)`, so **the action param always wins** and the stage jump values (6.0 / 5.5) are ignored.
- **Fallback literals** in `_read_geometry` and `camera_rig`: 3.66, 3.3 and 0.85.
- **Camera constants:** `COLLISION_RADIUS 0.35`, the 0.18 m first-person forward offset, the orbit distances (12 m to 3 m) and the bob amplitude.
- **Heavy Footfall** `radius_m 3.0` and `height_m 2.6`, which do not scale with stage.
- **`ActorRig.stride_length_m 1.6`.**

**Proposed implementation.** Add a new component, `scripts/actors/player_growth.gd` (`class_name PlayerGrowth`, a `RefCounted` or child `Node`). Give `GiantPlayer` a single `apply_growth_profile(new_profile: Dictionary) -> bool` that it delegates to. The function runs these steps:

1. **Gate.** Allow it only when `controller.state == LOCOMOTION`, out of combat (`not pools.in_combat()`), and at a shrine. A debug path is separate and logged, and both paths call the same apply function.
2. **Clearance test before touching anything.**
   - Build a candidate `CapsuleShape3D(radius, height)`.
   - Run a `PhysicsShapeQueryParameters3D` with `transform = global_transform.translated(Vector3.UP * (h/2 + 0.05))` and `collision_mask = L_WORLD | L_BREAKABLE`. Exclude `[get_rid()]` and use `space.intersect_shape(q, 1)`.
   - Add an upward ray or `cast_motion` from the current head to the new head height.
   - On failure, emit `Events.hud_message("Not enough room to grow here", "warn")`, change **nothing**, and return false.
3. **Preserve percentages.** Record `health/health_max`, `stamina/stamina_max` and `essence/essence_max` (fury is absolute). `ResourcePool.configure()` resets every pool to full, so it must **not** be reused. Add `ResourcePool.rescale(new_max: Dictionary)` that keeps the ratios. That prevents healing by switching profiles.
4. **Swap and re-apply, all in one tick:**
   - `profile = new_profile` and `growth_stage`;
   - `controller.growth_stage`, which re-evaluates `unlock_stage` gating;
   - `entity.combatant.height_m = height_m`;
   - `_read_geometry()`;
   - `_apply_profile()` (capsule and snap);
   - `lock.range_m` and `lock.half_angle_deg`;
   - `rig.set_weapon_pivot()`, plus the visual scale (below);
   - `camera_rig.apply_profile(profile)`, a new method: keep the zoom fraction between min and max, and do **not** snap `current_distance`, because the arm restores smoothly;
   - anchors and hurtboxes: scale `$Anchors` and `$Hurtboxes` by `height_m / 3.6576`. Hurtbox `CollisionShape3D` scaling is uniform, so that is fine for boxes. Alternatively, generate per-stage shapes.
5. **Unlocks.** Add `profile.unlocks` ids to `controller.library` with `_add_action_chain`, and optionally place them into empty slots. Abilities use `unlock_stage` (Boulder Hurl `unlock_stage: 2`).
6. **Navigation profile.** The player has no `NavigationAgent3D`. "Nav profile" matters for the autopilot (which steers directly) and for authored giant corridors. Add an optional `nav_layers` field to the growth schema in `DataValidator`, and set it on any agent. Soldiers already read `giant.profile.capsule_radius_m` live, so their engage distance updates automatically.
7. **Announce.** Emit `Events.growth_changed(Sim.tick, entity.entity_id, old, new)`. HUD and debug already show `growth_stage`.

**Visual scaling.** Scale `$Visual/Body` uniformly by `k = height_m / 3.6576`. The data is already consistent with this: stage-3 pivot (1.78, 6.28) ≈ 2.17 × (0.82, 2.9), and arm 3.25 ≈ 2.17 × 1.5.
- **Pitfall:** `set_weapon_pivot` writes local positions in `Body` space. After scaling, pass `pivot / k`.
- **Pitfall:** the club mesh lives under `ShoulderR` and would scale too (1.85 → 4.0 m visually), while the sweep still uses `weapon_length` 1.85. Either un-scale the weapon node (`scale = 1/k`, length from data), or move the weapon visual out of the scaled branch.
- **Reach gap:** with the club, the arm plus weapon reaches about 4.1 m (stage 2) or 5.1 m (stage 3) from the pivot, versus `melee_reach_m` 4.8 and 6.5. `melee_reach_m` is used **only** for soft-target range. Decide whether weapons scale per stage (Giantforge) or tune `arm_length_m`.

### 4.2 Grab, throw and Crushing Grip

- **Input.** The `interact` edge exists (E, or pad X). Replace the stub at `giant_player.gd` line 191 with `grab.on_interact_pressed()`.
- **Permissions.** Use `profile.interaction_permissions` (`grab_small`, `throw_boulder`, `tree_weapon`). Nothing reads them yet.
- **New component `PlayerGrab`** (`scripts/actors/player_grab.gd`):
  - `find_candidate()`: distance within `arm_length + weapon reach`, or a new `grab_reach_m`; `HitQueryAdapter.line_clear` from `_eye()`; target `height_m <= 0.5 × player height`; mass class and no `grab` immunity (`Combatant.is_immune_to("grab")`); living targets need broken poise (`controller.state == STAGGERED`).
  - `attach(target)`: recheck eligibility; hold one target; the target controller enters `GRABBED`, which already exists and rejects requests as busy; suspend its `sim_step` movement; parent its visual to a `Hand` marker or follow it each tick.
  - `release(reason)`: covers death, stagger, the scene `_exit_tree` and growth.
  - `throw()`: a swept projectile that queues ordinary `HitEvent`s through `Sim.queue_hit`.
- **Crushing Grip** is a new `data/abilities/crushing_grip.json` (`kind: "ability"`, 20 stamina, 10 s, `ability_multiplier 1.5`, `hit_shape` `"none"` or a new `"grab"`). It goes in a slot.
  - Problem: costs commit in `_accept` before eligibility is checked. Invalid grabs must spend nothing, so the eligibility check must run **before** `controller.request`. Either add a pre-validation hook (`controller.request(&"slot", {..., "precheck": Callable})`), or check in `_handle_actions` and emit a `request_rejected`-style message.
  - On `action_started` with the grip id, apply the hit to the held target on the first active tick, then release.
- **ActorRig** needs a pose for holding, grabbing and throwing. Add `"holding": bool` to `get_rig_state()` and a branch in `ActorRig._process`, beside the existing `cylinder_pulse` branch.
- **HUD:** the hotbar reason uses `last_reject_reason`. Add text for a `"no_grab_target"` reason in `_on_request_rejected`.

### 4.3 Tree weapon at stage 3, and weapon swaps (club, sword, hammer, tree)

- Today `weapon` is loaded once from `record.weapon`. Only `length_m`, `hit_radius_m` and `damage_multiplier` are used. Light and heavy arcs come from `loadout.light_chain` and `heavy`, not from the weapon.
- **Add `GiantPlayer.equip_weapon(weapon_id: String)`.** It sets `weapon = GameData.get_record(id)`, runs `_read_geometry()` and rebuilds the weapon visual.
  - Do it only in LOCOMOTION, never mid-swing: `prev_segment` and `weapon_length` must not change during ACTIVE.
- **Weapon-specific move sets.** Add optional `light_chain` and `heavy` fields to the weapon schema (`DataValidator` lines 352-357). On equip, set `controller.loadout.light` and `heavy`, and call `_add_action_chain`. A sword gets faster arcs. A hammer gets more power and a `cylinder_pulse` heavy.
- **Tree:** add `"tree"` to `WEAPON_FAMILIES` (line 24), or model it as family `club` with id `weapon.tree`. Add `required_permission: "tree_weapon"` and check it against `profile.interaction_permissions`. Pickup goes through `interact` near a tree prop, a `BreakableProp`-like node with a `world_id`, and persists through `WorldState`.
- **Weapon visual.** It is generated statically as `ShoulderR/Club` (a cylinder, top radius 0.24, bottom 0.11, length 1.85, at z −2.425). Make a small presentation helper, `ActorRig.set_weapon_visual(weapon: Dictionary)`, that frees the old mesh and builds a `CylinderMesh` or box from `length_m` and `hit_radius_m` at z = −(1.5 + length/2). This must account for the Body scale `k`.
- **Damage:** `weapon.damage_multiplier` feeds `HitEvent.weapon_multiplier` only when `a.uses_weapon` (`_queue_hits` line 486).

### 4.4 Attribute effects

| Attribute | Where it applies today | Live? |
| --- | --- | --- |
| Strength | `_queue_hits`: `attacker_stat = c.attribute("strength")` | Live |
| Intellect (magic power) | `_queue_hits`, for `category == "magic"` | Live |
| Intellect (essence max) | `Combatant.from_record`: +2 essence | Cached at load |
| Endurance | `from_record`: +15 health and +2 stamina per point above 10 | Cached at load |
| Constitution | `PoiseMeter.configure(cfg, constitution)`: +3 threshold | Cached at load |
| Dexterity | `CombatController.recovery_scale`, set in `_init` | Cached at load |
| Willpower | `Combatant.resistance()` | Live |

On level-up, add `Combatant.recompute_derived(rec)`. It updates the maximums through `ResourcePool.rescale` (percentage-preserving, or add the delta), calls `poise.configure` again while keeping the current value, and sets `controller.recovery_scale = combatant.recovery_scale()`. Attribute points live in a progression/save record, not in `giant.json`.

### 4.5 Ability slots, hotbar and loadout

- The loadout is `controller.loadout["slot_1".."slot_8"]` and `"ultimate"`, holding action ids. The library must contain every id, including `chain_next` ids.
- The HUD reads `c.loadout` and `c.library` every frame (`hud.gd` lines 403-420), so runtime changes show up immediately. Labels refresh only when `_labels_dirty`.
- To change the loadout at rest, add `GiantPlayer.set_slot(i, id)`: call `_add_action_chain(id)`, then `controller.loadout["slot_%d" % i] = id`.
- Heavy Footfall flow: `slot_1` edge → `request(&"slot", {slot:1})` → CASTING → pulse on the first active tick → `area_pulse` → ring and shake. Its JSON `unlock_stage` is 1.
- New hit shapes (projectile for Boulder Hurl and Runic Bolt, a 120° arc for Sweeping Blow) need a new `match a.hit_shape` branch in `_run_hit_queries`, a `HIT_SHAPES` entry in the validator, and a pose branch in `ActorRig`.

## 5. Hotspots and how to avoid edit conflicts

Many features would all edit the same places:

- **`giant_player.gd` `_ready()` and `_build_controller()`:** growth, weapons, loadout, attributes and save/load all touch them.
- **`_handle_meta()`:** grab and interact, tree pickup, shrine interaction, camera.
- **`_handle_actions()` and `_on_action_started()`:** every new ability kind (grip, hurl, roar, mend, Titan Surge).
- **`_run_hit_queries()`:** projectiles, the sweep arc, grip.
- **`_queue_hits()`:** Titan Surge `outgoing_damage_mult`, weapon, attributes and status effects.
- **`_read_geometry()` and `_apply_profile()`:** growth and weapon.
- **`get_rig_state()` and `ActorRig._process`:** grab pose, throw, new abilities, weapon families.
- **`tools/build_scenes.gd` `_build_giant()`:** hurtboxes, anchors, the hand marker, the weapon node.
- **`DataValidator` schema blocks:** every new JSON field.
- **`InputBindings.ACTIONS` and `default_bindings.json`:** any new input.

**Proposal.** Do one small refactor PR **first**, with no behaviour change and all 1133 checks still passing, before parallel feature work:

1. Split `giant_player.gd` into components. Each one is a `RefCounted`, owned by `GiantPlayer` and given a back-reference.
   - `PlayerMotor`: `_update_sprint`, `_update_facing`, `_update_movement`, `_dodge_speed`, `apply_knockback`, `_move_dir_world` and `_soft_target_offset`.
   - `PlayerTargeting`: all of the lock-on section, plus `_eye`, `_visible` and `_gather_candidates`.
   - `PlayerAttack`: `weapon_segment_global`, `_run_hit_queries` and `_queue_hits`. Each hit shape becomes a handler registered in a dictionary `hit_shape -> Callable`, so a new shape adds a function instead of editing a `match`.
   - `PlayerGrowth`: profile apply, clearance and rescale.
   - `PlayerEquipment`: weapon and loadout.
   - `PlayerGrab`.
   - Keep the **public field names** on `GiantPlayer`, because tests and the HUD use them: `router`, `controller`, `lock`, `entity`, `camera_rig`, `profile`, `weapon`, `growth_stage`, `stats` and `locked_entity()`. Forward them as properties if they move.
2. Make the action side effects table-driven. `_on_action_started` dispatches to `on_action_started_handlers[action.kind]` or `[action.id]`. Components register handlers in `_ready`.
3. Make meta edges table-driven. Use `edge_handlers: Dictionary[StringName, Callable]` so `interact` can be claimed by grab, shrine or pickup through a priority list of "interactables", not one function.
4. Add an `apply_profile(profile)` method to each consumer (`CameraRig`, `ActorRig`, `LockOnTracker` setup, `PlayerAttack`), so growth only calls them and never edits their internals.
5. Generator: factor `_build_giant` into `_giant_hurtboxes()`, `_giant_visual()` and `_giant_weapon()`. Add named markers now (`Visual/Body/ShoulderR/Hand`, `Anchors/Head`) so later features don't all touch the generator.
6. Validator: one owner per schema block. Coordinate new growth and weapon fields in a single early data PR (`nav_layers`, `grab_reach_m`, `grab_capacity`, weapon `light_chain`/`heavy`/`required_permission`, family `tree`).

## 6. Pitfalls and gotchas

- **Never hand-edit `.tscn` files.** Re-run `godot --headless --path . res://tools/build_scenes.tscn`. Gameplay numbers belong in JSON. The generator literals (capsule 0.85/3.66, shoulder 0.82/2.9) duplicate `growth_01.json`, and `_apply_profile` overrides the capsule at runtime.
- **`jump.json` overrides the profile.** Its `velocity_mps` beats the per-stage `jump_velocity_mps`. Dodge is the opposite: `profile.dodge_distance_m` beats `action.distance_m`.
- **`step_height_m` is not a step-up.** It only sets `floor_snap_length`. `CharacterBody3D` does not climb steps, so larger stages climb only by slope (`floor_max_angle` 46°).
- **`ResourcePool.configure()` refills every pool.** Using it for growth or level-up would heal the player. Write a `rescale`.
- **`Combatant.height_m`** is set once from `record.growth_profile` in `CombatEntity._ready`. Growth must update it, or `M_size`, poise scaling and lock eye height stay at stage 1. The camera uses `profile.height_m`, while `_eye()` uses `combatant.height_m`. Keep both in sync.
- **`camera_distance_m`** is read only in `CameraRig.setup()`. `set_mode(THIRD_PERSON)` resets `current_distance` to 0.5 on purpose. `Settings.session.camera_mode` persists the mode across scene reloads.
- **Camera tuning constants don't scale with size:** the 0.35 sphere radius, the lock orbit distances 12 m to 3 m, the small-target test (< 70% of height), the 0.18 m first-person forward offset and the `camera.near` of 0.05. At stage 3 the orbit range will likely need to scale by `k`.
- **First-person hidden geometry** is render layer 2 (`FP_HIDDEN`) on the Chest, Belt, Neck, Head, Hair, Brow and Eye meshes. Any new head or chest mesh must use that layer, or it will block the first-person view.
- **`InputRouter.context` is static and global.** Tests must reset it. Injection mode bypasses `Input` for holds and move, but edges still come from `_edges`.
- **Pad combos and plain pad buttons share keys.** Ability pad bindings (A, B, X, Y, D-pad) are also jump, dodge, interact and camera. They are disambiguated only by the LT modifier in `_unhandled_input`. Any new pad action must be added to `ACTIONS` (and `LABELS`), and to `COMBO_ACTIONS` if it is a combo, or `apply()` will not create it.
- **Shift is double-bound.** It is `sprint` and also `heavy_modifier`. Shift+click gives one heavy and stops sprint (documented). Don't bind a new action to Shift.
- **`target_prev` and `target_next` are overloaded.** They switch targets while locked and zoom the camera otherwise.
- **Interact is a stub.** It posts "Nothing to grab here yet (grabs arrive in M3)".
- **`interaction_permissions` and `unlocks` are validated but unused.** `Events.growth_changed` is declared but never emitted.
- **Costs commit on accept.** Any eligibility the controller doesn't know about (grab target, projectile aim) must be checked before `request`, or the controller needs a precheck hook. Otherwise the spec rule "invalid grabs spend nothing" fails.
- **The Footfall pulse radius is fixed by data (3 m).** The ring visual reads the radius from the event, so per-stage scaling is a data or param change. The occlusion origin is fixed at 0.8 m above the feet.
- **`HitFeedback` assumes the player's entity id is `"player"`** and that the player is a `GiantPlayer` in group `"player"`.
- **`_switch_target` uses `cam.unproject_position`.** It needs a current camera, and the headless tests rely on this.
- **`_add_action_chain` stops after 16 links** and silently ignores unknown ids. The validator catches bad refs at startup.
- **Mid-swing changes break the sweep.** Changing `weapon_pivot`, `arm_length` or `weapon_length` mid-swing makes `prev_segment` inconsistent and can cause tunnelling or false hits. Apply growth and equipment only in LOCOMOTION, and clear `prev_segment`.
- **Scaling the shoulders would leave the club out of step.** If `Visual/Body` is scaled, the generated club mesh scales with it, but `weapon_length` does not.
