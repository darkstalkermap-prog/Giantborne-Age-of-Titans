class_name EnemyActor
extends CharacterBody3D
## Base of every enemy archetype (plan §2.7.3): a CombatController with the same rules as the
## player, an EnemyBrain (made by _make_brain()), an AttackRunner for its hit queries, and the
## shared glue - perception at the record's rate (5 Hz), decisions (10 Hz), facing with
## tracking limits, NavigationAgent3D movement, hearing, ally deaths and death cleanup.
##
## Archetypes override the virtuals: _make_brain(), _sense_extra(snapshot), _is_guarding(),
## _custom_movement(dt) and _turn_rate_deg_s(); an archetype that overrides _ready() or
## _exit_tree() must call super(). Required child nodes: CombatEntity, NavAgent; Visual
## (ActorRig) is optional. Group "enemies".
##
## P04 (below its anchor): scripted `motion` (lunges, charges) in the base _custom_movement(),
## AI LOD tiers, morale, flight to reachable points and rout, formation slots, the telegraph
## announcement on WINDUP, sight through WORLD | BREAKABLE, the record's nav layers and
## awareness radii, and corpses that stop moving once settled.

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 30.0
const PATH_CHECK_S := 2.0
const DIRECT_STEER_DISTANCE := 3.0
const AWARE_ALL_AROUND_M := 8.0   ## once aware, sight is 360 degrees this close
const ALLY_DEATH_RADIUS_M := 15.0

## Stable id of this placed or spawned enemy (unique per level).
@export var entity_id := ""
@export var patrol_route: NodePath
## When false the brain neither perceives nor decides (tests, debugging); combat still runs.
@export var ai_enabled := true
## "" = always hostile. Village guards carry "village" (P11b behaviour).
@export var faction := ""
## Set by the EncounterDirector (P10a).
@export var encounter_id := ""
## When true the director records this enemy's death as a world delta (killed).
@export var persist_death := false
## Its death costs nearby allies morale; it is the encounter's leader (P04).
@export var commander := false
## Per-spawn loot table override set by the director; "" = the record's (P12 reads it).
@export var loot_table := ""

## Spawn point; the director sets it and the leash walks back to it (P10a).
var home_position := Vector3.ZERO

@onready var entity: CombatEntity = $CombatEntity
@onready var agent: NavigationAgent3D = $NavAgent
@onready var rig: ActorRig = get_node_or_null("Visual") as ActorRig

var record: Dictionary = {}
var weapon: Dictionary = {}
var controller: CombatController
var brain: EnemyBrain
var runner: AttackRunner
var facing_yaw := 0.0
var move_velocity := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
var weapon_pivot := Vector3(0.25, 1.42, 0.0)
var attack_origin := Vector3(0.0, 1.3, 0.0)
var arm_length := 0.5
var weapon_length := 0.95
var weapon_radius := 0.22
var perception_interval := 12
var decision_interval := 6
var path_failures := 0
var _phase_offset := 0
var _progress_anchor := Vector3.INF
var _progress_timer := 0.0
var _last_nav_target := Vector3.INF

## The weapon segment of the previous tick (lives in the attack runner).
var prev_segment: PackedVector3Array:
	get:
		return runner.prev_segment if runner != null else PackedVector3Array()
	set(value):
		if runner != null:
			runner.prev_segment = value


func _ready() -> void:
	add_to_group("enemies")
	# CombatEntity (a child, ready first) took our entity_id, or kept its own when ours is
	# empty; mirror the id it registered so both always agree.
	entity_id = entity.entity_id
	if home_position == Vector3.ZERO:
		home_position = global_position
	record = GameData.get_record(entity.definition_id)
	weapon = GameData.get_record(str(record.get("weapon", "")))
	var p: Array = record.get("weapon_pivot_m", [0.25, 1.42, 0.0])
	weapon_pivot = Vector3(p[0], p[1], p[2])
	var o: Array = record.get("attack_origin_m", [0.0, 1.3, 0.0])
	attack_origin = Vector3(o[0], o[1], o[2])
	arm_length = float(record.get("arm_length_m", 0.5))
	weapon_length = float(weapon.get("length_m", 0.95))
	weapon_radius = float(weapon.get("hit_radius_m", 0.22))
	controller = CombatController.new(entity.entity_id, entity.combatant)
	controller.set_instance_source(Sim.new_instance_id)
	for id: String in record.get("attacks", []):
		controller.add_action(GameData.get_action(id))
	entity.controller = controller
	controller.action_started.connect(_on_action_started)
	runner = AttackRunner.new(self, entity, controller)
	var ai: Dictionary = record.get("ai", {})
	perception_interval = maxi(1, int(roundf(60.0 / float(ai.get("perception_hz", 5.0)))))
	decision_interval = maxi(1, int(roundf(60.0 / float(ai.get("decision_hz", 10.0)))))
	_phase_offset = absi(hash(entity.entity_id)) % perception_interval
	brain = _make_brain()
	brain.patrol_points = _collect_patrol_points()
	facing_yaw = rotation.y
	agent.radius = float(record.get("capsule_radius_m", 0.35))
	agent.height = float(record.get("height_m", 1.8))
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = false
	if rig != null:
		rig.set_weapon_pivot(weapon_pivot)
	entity.hit_taken.connect(_on_hit_taken)
	Events.ability_started.connect(_on_any_ability_started)
	Events.entity_died.connect(_on_any_entity_died)
	_p04_ready()
	_p11b_ready()
	_p22_ready()
	_p24b_ready()
	_p30_ready()
	_p34_ready()   # P34: regeneration, the yield protocol, boss outcomes
	Sim.register_actor(entity.entity_id, self)


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)
	_release_formation_marker()


func _collect_patrol_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var route := get_node_or_null(patrol_route)
	if route != null:
		for child in route.get_children():
			if child is Node3D:
				out.append((child as Node3D).global_position)
	return out


# --------------------------------------------------------------------------- virtuals

## The archetype's brain. Default: the shared melee EnemyBrain.
func _make_brain() -> EnemyBrain:
	return EnemyBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


## Adds archetype-specific keys to the perception snapshot (called for every snapshot).
func _sense_extra(_snapshot: Dictionary) -> void:
	pass


## True while the archetype holds a passive guard (soldiers guard the front). Default: never.
func _is_guarding() -> bool:
	return false


## Archetype movement override for this tick. Return true when it set move_velocity itself;
## the base then skips brain steering but still applies knockback, gravity and move_and_slide.
## The base runs the current action's `motion` (P04: wolf lunge, boss charge); an override
## that adds its own movement should call super() first.
func _custom_movement(dt: float) -> bool:
	return _run_motion(dt)


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	controller.on_floor = is_on_floor()
	controller.begin_tick(tick)
	var alive := controller.state != CombatController.State.DEAD
	if not alive and _corpse_step(tick):
		return   # a settled corpse no longer decides or moves (P04)
	if ai_enabled and alive and (tick + _phase_offset) % perception_interval == 0:
		brain.perceive(tick, _sense())
	if ai_enabled and ((tick + _phase_offset) % decision_interval == 0
			or (not alive and brain.state != EnemyBrain.AIState.DEAD)):
		brain.decide(tick, controller.state, global_position, _request_token, _release_token)
	if alive and brain.attack_request != "":
		controller.request(&"attack", {"action_id": brain.attack_request})
		brain.attack_request = ""
	_update_facing(dt)
	_update_movement(dt)
	runner.run(tick)
	entity.combatant.pools.tick(dt, not is_guarding())
	entity.combatant.poise.tick(dt)


func _request_token() -> bool:
	if _should_yield_token(brain.target_id):
		return false   # P04: take turns - someone else was refused a token a moment ago
	var ok := Sim.request_token(brain.target_id, entity.entity_id,
		int(record.get("ai", {}).get("max_attackers", 2)))
	_note_token_request(brain.target_id, ok)
	return ok


func _release_token() -> void:
	Sim.release_token(brain.target_id, entity.entity_id)
	_token_released_tick = Sim.tick


func _target() -> CombatEntity:
	if _p30_has_targets():
		return _p30_target()   # P30: the record's target provider (NPCs and props besides the giant)
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER:
			return e
	return null


## Perception snapshot (5 Hz): range, view cone (360 degrees once aware and close), line of
## sight, plus what archetype tactics read about the target (its forward, size, growth stage,
## combat state) and this enemy's own health fraction.
func _sense() -> Dictionary:
	var t := _target()
	if t == null:
		var empty := {"exists": false, "self_health_frac": entity.combatant.pools.ratio("health"),
			"has_leader": _has_leader_now()}
		_sense_extra(empty)
		return empty
	var ai: Dictionary = record.get("ai", {})
	var to := t.actor.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := -global_transform.basis.z
	var facing_deg := rad_to_deg(Vector3(fwd.x, 0.0, fwd.z).signed_angle_to(to, Vector3.UP)) if dist > 0.01 else 0.0
	var in_cone := absf(facing_deg) <= float(ai.get("sight_half_angle_deg", 75.0)) \
		or (brain.aware and dist <= float(ai.get("awareness_radius_m", AWARE_ALL_AROUND_M)))
	var visible := false
	if dist <= float(ai.get("sight_range_m", 25.0)) and in_cone:
		var eye := global_position + Vector3.UP * entity.combatant.height_m * 0.92
		visible = HitQueryAdapter.line_clear(get_world_3d().direct_space_state, eye,
			t.anchor_position(), SIGHT_MASK, t.occlusion_rids)
	var radius := 0.85
	var stage := 1
	var giant := t.actor as GiantPlayer
	if giant != null:
		radius = float(giant.profile.get("capsule_radius_m", 0.85))
		stage = giant.current_growth_stage()
	var t_fwd := -t.actor.global_transform.basis.z
	t_fwd.y = 0.0
	var snapshot := {"exists": true, "target_id": t.entity_id, "alive": t.is_alive(),
		"position": t.actor.global_position, "distance": dist, "visible": visible,
		"facing_deg": facing_deg, "target_radius": radius,
		"target_forward": t_fwd.normalized() if t_fwd.length_squared() > 1e-8 else Vector3.FORWARD,
		"target_height": t.combatant.height_m, "target_stage": stage,
		"target_state": t.controller.state if t.controller != null else -1,
		"self_health_frac": entity.combatant.pools.ratio("health"), "has_leader": _has_leader_now()}
	_p30_sense(snapshot, t)   # P30: an NPC or prop target's own radius; no awe or size tactics against it
	_sense_extra(snapshot)
	return snapshot


## The global-bus handlers below return at once out of the tree (P17a: the director takes a
## despawned member out of the tree and frees it at the end of the frame; a giant's ability started
## later in the same tick reached it and read its global position).
func _on_any_ability_started(_tick: int, actor_id: String, _action_id: String, _instance: int) -> void:
	if not is_inside_tree():
		return
	var src := Sim.get_entity(actor_id)
	if src == null or src == entity or not CombatEntity.can_damage(entity.team, src.team):
		return
	var hearing := float(record.get("ai", {}).get("hearing_radius_m", 15.0))
	if global_position.distance_to(src.actor.global_position) <= hearing:
		brain.on_noise(Sim.tick, src.actor.global_position, src.entity_id, false)


func _on_hit_taken(result: HitResult) -> void:
	var src := Sim.get_entity(result.event.attacker_id)
	if src != null and src != entity:
		brain.on_noise(Sim.tick, src.actor.global_position, src.entity_id, true)


func _on_any_entity_died(tick: int, id: String, _killer: String) -> void:
	if not is_inside_tree() or id == entity.entity_id or not entity.is_alive():
		return
	if _p30_on_entity_died(tick, id):
		return   # P30: its formation's banner fell (the commander's death for its members)
	var other := Sim.get_entity(id)
	if other == null or other.team != entity.team or other.actor == null:
		return
	var near := other.actor.global_position.distance_to(global_position) \
		< float(record.get("ai", {}).get("ally_death_radius_m", ALLY_DEATH_RADIUS_M))
	if other.actor.get("commander") == true and (near or _same_encounter(other.actor)):
		brain.on_commander_died(tick)
	elif near:
		brain.on_ally_died(tick)


func _on_action_started(action: ActionDef, instance_id: int) -> void:
	Events.ability_started.emit(Sim.tick, entity.entity_id, action.id, instance_id)
	runner.reset()


# --------------------------------------------------------------------------- movement

func _update_facing(dt: float) -> void:
	var target_yaw := facing_yaw
	var turn := true
	match controller.state:
		CombatController.State.ATTACKING:
			# Track only during the early windup; committed afterwards.
			var a := controller.action
			var track_ticks := int(a.windup_ticks * a.tracking_fraction) if a != null else 0
			if controller.phase() == ActionDef.Phase.WINDUP and controller.elapsed < track_ticks \
					and brain.face_point != Vector3.INF:
				target_yaw = _yaw_to(brain.face_point)
			else:
				turn = false
		CombatController.State.LOCOMOTION:
			if brain.face_point != Vector3.INF:
				target_yaw = _yaw_to(brain.face_point)
			elif Vector2(move_velocity.x, move_velocity.z).length() > 0.3:
				target_yaw = TargetingRules.yaw_of(move_velocity)
		_:
			turn = false
	if turn:
		var step := deg_to_rad(_turn_rate_deg_s()) * dt
		facing_yaw = wrapf(facing_yaw + clampf(TargetingRules.yaw_delta(facing_yaw, target_yaw), -step, step), -PI, PI)
	rotation.y = facing_yaw


## Turn rate this tick (archetypes slow it, e.g. while guarding).
func _turn_rate_deg_s() -> float:
	return float(record.get("turn_rate_deg_s", 300.0))


func _yaw_to(point: Vector3) -> float:
	var to := point - global_position
	to.y = 0.0
	return facing_yaw if to.length_squared() < 1e-4 else TargetingRules.yaw_of(to)


func _update_movement(dt: float) -> void:
	if not _custom_movement(dt):
		_steer(dt)
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECEL * dt)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * dt
	velocity.x = move_velocity.x + knockback_velocity.x
	velocity.z = move_velocity.z + knockback_velocity.z
	move_and_slide()


## Brain-driven steering: path with the NavigationAgent beyond DIRECT_STEER_DISTANCE, steer
## straight when close (or when no navmesh answers).
func _steer(dt: float) -> void:
	var desired := Vector3.ZERO
	var mult := controller.move_speed_multiplier()
	if brain.move_target != Vector3.INF and mult > 0.0:
		var speed := float(record.get("walk_speed_mps", 1.6))
		if brain.move_speed < 0.0:
			speed = float(record.get("run_speed_mps", 3.6))
		var goal := brain.move_target
		var flat_dist := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
		var next := goal
		var reach := goal   # P24b: in a streamed world, where the path to an unreachable goal ends
		if flat_dist > DIRECT_STEER_DISTANCE:
			if _wants_repath(goal):
				agent.target_position = goal
				_last_nav_target = goal
				_note_repath()
			_p24b_level_waypoint()
			if not agent.is_navigation_finished():
				next = agent.get_next_path_position()
			reach = _p24b_reach(goal)
			if next == goal:
				next = reach   # the path is done: on to the goal, or (unreachable) to the path's end
			if Vector2(next.x - global_position.x, next.z - global_position.z).length() < 0.05:
				next = reach  # no path data (no navmesh / not synced yet): steer directly
		var dir := next - global_position
		dir.y = 0.0
		if flat_dist > 0.25 and dir.length() > 0.01:
			desired = dir.normalized() * speed * mult
		_track_progress(reach, dt)
	else:
		_progress_anchor = Vector3.INF
		_progress_timer = 0.0
	move_velocity = move_velocity.move_toward(desired, 20.0 * dt)


## No progress toward the goal for 2 s -> ask the brain for a new destination (never teleport).
func _track_progress(goal: Vector3, dt: float) -> void:
	if _progress_anchor == Vector3.INF:
		_progress_anchor = global_position
		_progress_timer = 0.0
		return
	_progress_timer += dt
	if _progress_timer >= float(record.get("ai", {}).get("path_fail_s", PATH_CHECK_S)):
		var progressed := _progress_anchor.distance_to(global_position)
		var close := Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 1.0
		if progressed < 0.3 and not close:
			path_failures += 1
			brain.on_path_failed(global_position)
			_last_nav_target = Vector3.INF
		_progress_anchor = global_position
		_progress_timer = 0.0


func apply_knockback(direction: Vector3, speed: float) -> void:
	if direction.length_squared() < 1e-6:
		return
	knockback_velocity = direction.normalized() * maxf(speed, knockback_velocity.length())


# --------------------------------------------------------------------------- attacks

func weapon_segment_global(action: ActionDef, f: float) -> PackedVector3Array:
	var ang := AttackGeometry.arc_point(action, f)
	var dir := AttackGeometry.local_direction(ang.x, ang.y)
	var seg := AttackGeometry.segment_local(weapon_pivot, dir, arm_length, arm_length + weapon_length)
	return PackedVector3Array([to_global(seg[0]), to_global(seg[1])])


func attack_origin_global() -> Vector3:
	return to_global(attack_origin)


func current_weapon() -> Dictionary:
	return weapon


func current_growth_stage() -> int:
	return 1


func weapon_hit_radius() -> float:
	return weapon_radius


# --------------------------------------------------------------------------- defence and death

func is_guarding() -> bool:
	if at_peace():
		return _guarding_at_peace()   # P11b: a neutral guard keeps its guard up, a stood-down one lowers it
	return _is_guarding()


func get_defense_state() -> DefenseState:
	var d := DefenseState.new()
	d.position = global_position
	d.forward = -global_transform.basis.z
	d.height_m = entity.combatant.height_m
	d.is_dead = controller.state == CombatController.State.DEAD
	d.blocking = is_guarding()
	d.parry_available = false
	d.block_elapsed_ticks = 1 << 20
	d.stamina = entity.combatant.pools.stamina
	d.stability = entity.combatant.stability
	d.apply_guard(record.get("guard", {}))
	_p30_defense(d)   # P30: a shield's guard breaks on the hit tags of its record
	return d


func on_entity_died(_killer_id: String) -> void:
	Sim.release_all_tokens(entity.entity_id)
	_died_tick = Sim.tick
	_release_formation_marker()
	# Corpses stop blocking the giant and stop being hit.
	set_deferred("collision_layer", 0)
	for hb in entity.hurtboxes:
		hb.set_deferred("monitorable", false)
		for child in hb.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).set_deferred("disabled", true)


# --------------------------------------------------------------------------- presentation

func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	if rig != null:
		rig.flash(strength, color)


func get_rig_state() -> Dictionary:
	return _p30_rig_state({   # P30: a braced formation member's brace pose
		"state": controller.state,
		"action": controller.action,
		"phase": controller.phase(),
		"phase_fraction": controller.phase_fraction(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"dead": controller.state == CombatController.State.DEAD,
		"staggered": controller.state == CombatController.State.STAGGERED,
		"dodging": false,
		"guarding": is_guarding(),
	})


func get_debug_info() -> Dictionary:
	return {
		"id": entity.entity_id,
		"ai": brain.state_name(),
		"combat": controller.state_name(),
		"action": controller.action_id(),
		"health": entity.combatant.pools.health,
		"poise": entity.combatant.poise.value,
		"token": brain.holds_token,
		"guard": is_guarding(),
		"stamina": entity.combatant.pools.stamina,
		"aware": brain.aware,
		"path_failures": path_failures,
		"morale": brain.morale,
		"lod": lod_tier,
		"outmatched": brain.is_outmatched(),
	}


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5): P04 motion,
# LOD tiers, morale and rout, sight mask, nav layers; P07 grab hooks; P09 aim point and ranged
# tactics; P10a leash return; P11a boss hooks; P11b factions and stand-down.

## @anchor P04
# --- motion, LOD tiers, morale, flight, formation, telegraphs, corpses (P04) -----------------

## Enemy sight: world geometry and breakables (gates, barricades) block it; blockers do not.
const SIGHT_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
## Physics layer 6 (invisible movement walls, decision 21).
const LAYER_BLOCKER := 32
## LOD tier 1: perception 1 Hz, decisions 2 Hz, a re-path at most once per second and only
## after a path failure.
const TIER1_PERCEPTION_INTERVAL := 60
const TIER1_DECISION_INTERVAL := 30
const TIER1_REPATH_TICKS := 60
## Formation markers (LevelMarker kind FORMATION, P10a; plain Marker3Ds in tests) are searched
## this far from the unit.
const FORMATION_GROUP := "ai_formation_points"
const FORMATION_SEARCH_M := 25.0
const FORMATION_HOLDER_META := &"formation_holder"
## Flee directions are tried in these steps away from the threat.
const FLEE_STEP_DEG := 30.0
const FLEE_MAX_STEPS := 6
## A flee point counts as reachable when a path on the actor's nav layers ends this close to it.
const FLEE_PATH_END_M := 1.0

## 0 full rate, 1 reduced, 2 dormant (set_lod_tier).
var lod_tier := 0
## How often the navigation agent was given a new target (tests, debug).
var repath_count := 0
## Why the last motion ended: "" (running or none), "distance", "wall", "target", "phase".
var motion_end_reason := ""
var _base_perception_interval := 12
var _base_decision_interval := 6
var _base_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _pending_lod := -1
var _last_repath_tick := -1000000
var _lod_body: Node3D
var _lod_proxy: Node3D
var _died_tick := -1
var _corpse_settled := false
var _motion_instance := -1
var _motion_origin := Vector3.ZERO
var _motion_dir := Vector3.FORWARD
var _motion_started := false
var _motion_done := false
var _formation_marker: Node3D
var _line_anchor := Vector3.INF
var _encounter_had_commander := false


func _p04_ready() -> void:
	agent.navigation_layers = int(record.get("nav_layers", 1))
	_base_perception_interval = perception_interval
	_base_decision_interval = decision_interval
	_base_process_mode = process_mode
	_lod_body = get_node_or_null("Visual/Body") as Node3D
	_lod_proxy = get_node_or_null("Visual/LodProxy") as Node3D
	var tactics: Variant = record.get("tactics", {})
	var hold := str(tactics.get("hold_attack", "")) if typeof(tactics) == TYPE_DICTIONARY else ""
	if hold != "" and GameData.get_action(hold) != null and not controller.library.has(hold):
		controller.add_action(GameData.get_action(hold))
	controller.phase_entered.connect(_on_phase_entered)
	brain.flee_resolver = _resolve_flee_point
	brain.formation_resolver = _formation_slot
	brain.formation_release = _release_formation_marker
	brain.morale_changed.connect(_on_brain_morale_changed)
	brain.routed.connect(_on_brain_routed)
	if _pending_lod >= 0:
		var tier := _pending_lod
		_pending_lod = -1
		set_lod_tier(tier)


# ---- LOD

## AI level of detail (plan §2.7.3; the EncounterDirector sets it by distance, P10a): 0 full
## rate; 1 perception 1 Hz, decisions 2 Hz, a re-path at most once per second and only after
## a path failure; 2 dormant: process_mode DISABLED (Sim skips it; the body and hurtboxes
## leave physics), its attack tokens released, Visual/Body hidden and Visual/LodProxy shown.
## May be called before the actor is ready.
func set_lod_tier(tier: int) -> void:
	tier = clampi(tier, 0, 2)
	if not is_node_ready():
		_pending_lod = tier
		return
	if tier == lod_tier:
		return
	lod_tier = tier
	perception_interval = maxi(_base_perception_interval, TIER1_PERCEPTION_INTERVAL) if tier == 1 \
		else _base_perception_interval
	decision_interval = maxi(_base_decision_interval, TIER1_DECISION_INTERVAL) if tier == 1 \
		else _base_decision_interval
	_phase_offset = absi(hash(entity.entity_id)) % perception_interval
	if tier == 2:
		# A dormant actor gives its attack tokens back: it would otherwise hold one of the
		# target's two slots for as long as it sleeps.
		Sim.release_all_tokens(entity.entity_id)
		brain.holds_token = false
	# DISABLED also takes the body and its hurtboxes out of physics (CollisionObject3D
	# disable_mode REMOVE) until the tier drops again.
	process_mode = Node.PROCESS_MODE_DISABLED if tier == 2 else _base_process_mode
	if _lod_body != null:
		_lod_body.visible = tier != 2
	if _lod_proxy != null:
		_lod_proxy.visible = tier == 2


## Whether _steer gives the navigation agent a new target now. Tier 0: whenever the goal moved
## more than 0.5 m (M1). Tier 1: only when it has none (start, or after a path failure), at most
## once per TIER1_REPATH_TICKS.
func _wants_repath(goal: Vector3) -> bool:
	if _p24b_throttled():
		return _p24b_wants_repath(goal)   # P24b: a streamed world's throttle and query budget
	if lod_tier >= 1:
		return _last_nav_target == Vector3.INF and Sim.tick - _last_repath_tick >= TIER1_REPATH_TICKS
	return _last_nav_target == Vector3.INF or _last_nav_target.distance_to(goal) > 0.5


func _note_repath() -> void:
	repath_count += 1
	_last_repath_tick = Sim.tick
	if _p24b_throttled():
		NavQuery.spend(nav_level())   # P24b: the agent's query counts against the tick's budget


## Drops the agent's target, as a path failure does: the next movement tick asks for a new path
## (at tier 1 no sooner than TIER1_REPATH_TICKS after the last one).
func request_repath() -> void:
	_last_nav_target = Vector3.INF


# ---- motion

## The current action's `motion` (plan §2.8.2): during motion.phase the actor moves at
## speed_mps (times its slow multiplier) along the facing it had when that phase began, turning
## toward its target at steer_deg_s, for at most max_distance_m. stop_on_wall ends it against
## WORLD geometry and starts on_wall_action (controller.force_action); approach_stop_m ends it
## when the gap between the two capsules is that small. Returns true while it owns
## move_velocity (also while standing still for the rest of the phase once it ended).
func _run_motion(dt: float) -> bool:
	var a := controller.action
	if a == null or controller.state == CombatController.State.DEAD:
		_motion_instance = -1
		return false
	var m: Variant = a.param("motion")
	if typeof(m) != TYPE_DICTIONARY:
		return false
	if _motion_instance != controller.instance_id:
		_motion_instance = controller.instance_id
		_motion_started = false
		_motion_done = false
		motion_end_reason = ""
	if ActionDef.PHASE_NAMES[controller.phase()] != str(m.get("phase", "active")):
		if _motion_started and not _motion_done:
			_end_motion("phase")
		return false
	if not _motion_started:
		_motion_started = true
		_motion_origin = global_position
		_motion_dir = Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	if _motion_done:
		move_velocity = Vector3.ZERO
		return true
	if bool(m.get("stop_on_wall", false)) and _ran_into_wall(_motion_dir):
		_end_motion("wall")
		var wall_action := GameData.get_action(str(m.get("on_wall_action", "")))
		if wall_action != null:
			controller.force_action(wall_action)
		return true
	var t := _motion_target()
	var steer := float(m.get("steer_deg_s", 0.0))
	if steer > 0.0 and t != null:
		var step := deg_to_rad(steer) * dt
		facing_yaw = wrapf(facing_yaw + clampf(TargetingRules.yaw_delta(facing_yaw,
			_yaw_to(t.actor.global_position)), -step, step), -PI, PI)
		rotation.y = facing_yaw
		_motion_dir = Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var stop_gap := float(m.get("approach_stop_m", 0.0))
	if stop_gap > 0.0 and t != null and capsule_gap(t) <= stop_gap:
		_end_motion("target")
		return true
	var travelled := Vector2(global_position.x - _motion_origin.x, global_position.z - _motion_origin.z).length()
	var remaining := float(m.get("max_distance_m", INF)) - travelled
	if remaining <= 0.01:
		_end_motion("distance")
		return true
	var speed := minf(float(m.get("speed_mps", 0.0)) * entity.combatant.move_mult(), remaining / dt)
	move_velocity = _motion_dir * speed
	return true


func _end_motion(reason: String) -> void:
	_motion_done = true
	motion_end_reason = reason
	move_velocity = Vector3.ZERO


## True when the previous move_and_slide ran into WORLD geometry against `dir` (a wall, not the
## floor or a ramp).
func _ran_into_wall(dir: Vector3) -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as CollisionObject3D
		if body == null or (body.collision_layer & HitQueryAdapter.LAYER_WORLD) == 0:
			continue
		var n := c.get_normal()
		var flat := Vector3(n.x, 0.0, n.z)
		if absf(n.y) < 0.7 and flat.length_squared() > 1e-6 and flat.normalized().dot(dir) < -0.3:
			return true
	return false


func _motion_target() -> CombatEntity:
	var t := Sim.get_entity(brain.target_id) if brain.target_id != "" else null
	return t if t != null else _target()


## Horizontal gap between this actor's capsule and `t`'s (negative when they overlap).
func capsule_gap(t: CombatEntity) -> float:
	var d := Vector2(t.actor.global_position.x - global_position.x,
		t.actor.global_position.z - global_position.z).length()
	return d - float(record.get("capsule_radius_m", 0.35)) - entity_radius(t)


## Capsule radius of a combat entity: the giant's growth profile, otherwise its record.
static func entity_radius(t: CombatEntity) -> float:
	var giant := t.actor as GiantPlayer
	if giant != null:
		return float(giant.profile.get("capsule_radius_m", 0.85))
	return float(GameData.get_record(t.definition_id).get("capsule_radius_m", 0.4))


# ---- telegraphs

## Announces an action's telegraph when its WINDUP begins (decision 25):
## Events.telegraph_started with the brain's target. radius / length by shape: circle
## (radius_m, 0), line (width_m / 2, length_m), cone (radius_m, radius_m; arc_deg is in the
## action record). Duration = the windup.
func _on_phase_entered(action: ActionDef, instance_id: int, phase: int) -> void:
	if _p34_on_phase_entered(action, instance_id, phase):
		return   # P34: a lobbed throw's circle lies at its committed landing point
	if _p30_on_phase_entered(action, phase, instance_id):
		return   # P30: a band brace's telegraph lies along its formation's front rank; a rally strikes
	if phase != ActionDef.Phase.WINDUP or action == null:
		return
	var t: Variant = action.param("telegraph")
	if typeof(t) != TYPE_DICTIONARY:
		return
	var shape := str(t.get("shape", "line"))
	var radius := float(t.get("radius_m", 0.0))
	var length := 0.0
	match shape:
		"line":
			radius = float(t.get("width_m", 1.0)) * 0.5
			length = float(t.get("length_m", 0.0))
		"cone":
			length = radius
	Events.telegraph_started.emit(Sim.tick, entity.entity_id, action.id, brain.target_id, shape,
		global_position, facing_yaw, radius, length, float(action.windup_ticks) / Sim.TICK_RATE)


# ---- morale

## Morale damage from a hit (CombatEntity: Thunder Roar's morale_damage, x1.5 while outmatched)
## or from P11b's awe (source_id "awe"). Bosses (ignores_morale) are unaffected.
func on_morale_delta(delta: float, source_id: String) -> void:
	brain.on_morale_delta(delta, source_id, Sim.tick)


## Scripted morale events: "siege_destroyed" (-20). No slice content raises one (siege
## equipment is deferred).
func on_morale_event(event: StringName) -> void:
	if not brain.on_morale_event(event, Sim.tick):
		push_warning("EnemyActor %s: unknown morale event '%s'" % [entity.entity_id, event])


## True once the unit has routed: it stays out of the fight (the director counts it as cleared).
func is_routed() -> bool:
	return brain != null and brain.state == EnemyBrain.AIState.ROUTED


func _on_brain_morale_changed(value: float, delta: float, reason: String) -> void:
	Events.morale_changed.emit(Sim.tick, entity.entity_id, value, delta, reason)


func _on_brain_routed() -> void:
	Events.enemy_routed.emit(Sim.tick, entity.entity_id, encounter_id)


func _same_encounter(other: Node) -> bool:
	return encounter_id != "" and str(other.get("encounter_id")) == encounter_id


## Decision 26: a leader is a living commander of this unit's encounter (a living commander is
## its own leader); when the encounter never had a commander, any living ally within
## ai.leader_radius_m that is neither fleeing nor routed. Placed units outside an encounter
## share the encounter "".
func _has_leader_now() -> bool:
	if commander and entity.is_alive():
		return true
	if formation != null and formation.banner_id != "":
		return _p30_has_leader()   # P30: a formation member's leader is its banner
	var radius := float(record.get("ai", {}).get("leader_radius_m", 20.0))
	var commander_alive := false
	var ally_near := false
	for n in get_tree().get_nodes_in_group("enemies"):
		var other := n as EnemyActor
		if other == null or other == self or other.entity == null or other.entity.combatant == null \
				or other.entity.team != entity.team:
			continue
		var alive := other.entity.is_alive()
		if other.commander and other.encounter_id == encounter_id:
			_encounter_had_commander = true
			commander_alive = commander_alive or alive
		elif alive and not ally_near and other.brain != null \
				and not (other.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]) \
				and other.global_position.distance_to(global_position) <= radius:
			ally_near = true
	return commander_alive if _encounter_had_commander else ally_near


# ---- flight

## A reachable flee destination about `distance` m from `from`, away from `threat` (spec 15:
## fleeing enemies have a reachable destination). The closest point on this actor's own nav
## layer (NavQuery.closest_point, P24b: LevelRoot.nav_region(layer) when the level provides one
## (P10a), otherwise the map's region on that layer; a streamed world's own map for the layer) -
## accepted only when a path on the actor's nav layers ends within
## FLEE_PATH_END_M of it. When that point lies beyond a wall (the path stops short of it), the
## end of the path toward it is the candidate instead, checked the same way. A candidate must
## be at least half `distance` away and farther from the threat than `from`; directions are
## tried in FLEE_STEP_DEG steps from straight away. Without a navmesh: a direct point validated
## by a ray. Vector3.INF when nothing fits (cornered).
func _resolve_flee_point(from: Vector3, threat: Vector3, distance: float) -> Vector3:
	var away := from - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z)
	away = away.normalized() if away.length() > 1e-4 else Vector3.BACK
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	var use_nav := NavQuery.has_navigation(level, layers)   # P24b: every query through NavQuery
	var space := get_world_3d().direct_space_state
	var threat_dist := _flat_len(from - threat)
	for i in range(_search_start("flee") if use_nav else 0, FLEE_MAX_STEPS * 2 + 1):
		var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)   # 0, 1, -1, 2, -2, ...
		var desired := from + away.rotated(Vector3.UP, deg_to_rad(FLEE_STEP_DEG * k)) * distance
		if use_nav:
			if not _search_affords():   # M7 gate: within the tick's path-query budget (P24b section)
				_search_stop("flee", i)
				return Vector3.INF
			var q0 := NavQuery.queries_total
			var p := _reachable_point(level, from, NavQuery.closest_point(level, desired, layers), layers)
			_search_spend(q0)
			if p == Vector3.INF or _flat_len(p - from) < distance * 0.5 or _flat_len(p - threat) <= threat_dist:
				continue   # unreachable, snapped back toward us, or not away from the threat
			_search_done("flee")
			return p
		else:
			var lift := Vector3.UP * 0.5
			if HitQueryAdapter.line_clear(space, from + lift, desired + lift, SIGHT_MASK | LAYER_BLOCKER,
					entity.occlusion_rids):
				return Vector3(desired.x, from.y, desired.z)
	_search_done("flee")
	return Vector3.INF


## `p` when a path from `from` on `layers` ends within FLEE_PATH_END_M of it; otherwise the end
## of that path when the same check accepts it (p lies beyond a wall or on an unconnected
## island); otherwise Vector3.INF. P24b: the paths are NavQuery's (the level's map for the layer
## and its chase parameters; the Valley's are map_get_path's).
static func _reachable_point(level: Node, from: Vector3, p: Vector3, layers: int) -> Vector3:
	if not p.is_finite():
		return Vector3.INF
	var path := NavQuery.path(level, from, p, layers)
	if path.is_empty():
		return Vector3.INF
	var end := path[path.size() - 1]
	if end.distance_to(p) <= FLEE_PATH_END_M:
		return p
	var check := NavQuery.path(level, from, end, layers)
	if check.size() > 0 and check[check.size() - 1].distance_to(end) <= FLEE_PATH_END_M:
		return end
	return Vector3.INF


## The navigation region this actor's flee points snap to: LevelRoot.nav_region(layer) for the
## lowest of its nav layers when a level provides one, otherwise the first region of its map on
## one of those layers. An invalid RID without a navmesh.
func nav_region_for_layers() -> RID:
	var layers := int(agent.navigation_layers)
	var level := get_tree().get_first_node_in_group("level_root")
	if level != null and level.has_method("nav_region"):
		var r: Variant = level.call("nav_region", layers & -layers)
		if r is RID and (r as RID).is_valid():
			return r
	for r: RID in NavigationServer3D.map_get_regions(get_world_3d().navigation_map):
		if (NavigationServer3D.region_get_navigation_layers(r) & layers) != 0:
			return r
	return RID()


static func _flat_len(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# ---- formation

## This unit's HOLD slot (brain.formation_resolver, decision 26): the nearest free formation
## marker (group ai_formation_points, matching faction or none) within FORMATION_SEARCH_M,
## claimed for this unit; otherwise its place in an ad-hoc line, tactics.formation_spacing_m
## apart, through the encounter's centre (outside an encounter: where the unit stood when it
## began to hold), at right angles to the direction to the target.
func _formation_slot(my_position: Vector3, target_pos: Vector3) -> Vector3:
	if _formation_marker != null and is_instance_valid(_formation_marker) and _formation_marker.is_inside_tree():
		return _formation_marker.global_position
	_formation_marker = null
	var marker := _claim_formation_marker(my_position)
	if marker != null:
		return marker.global_position
	return _line_slot(my_position, target_pos)


func _claim_formation_marker(my_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := FORMATION_SEARCH_M
	for n in get_tree().get_nodes_in_group(FORMATION_GROUP):
		var m := n as Node3D
		if m == null or not m.is_inside_tree():
			continue
		var f: Variant = m.get("faction")
		if typeof(f) == TYPE_STRING and f != "" and f != faction:
			continue
		var holder := str(m.get_meta(FORMATION_HOLDER_META, ""))
		if holder != "" and holder != entity.entity_id:
			var h := Sim.get_entity(holder)
			if h != null and h.is_alive():
				continue
		var d := m.global_position.distance_to(my_position)
		if d <= best_d:
			best = m
			best_d = d
	if best != null:
		best.set_meta(FORMATION_HOLDER_META, entity.entity_id)
		_formation_marker = best
	return best


## Gives a claimed formation marker back (brain.formation_release; also on death and exit).
func _release_formation_marker() -> void:
	if _formation_marker != null and is_instance_valid(_formation_marker) and entity != null \
			and str(_formation_marker.get_meta(FORMATION_HOLDER_META, "")) == entity.entity_id:
		_formation_marker.remove_meta(FORMATION_HOLDER_META)
	_formation_marker = null
	_line_anchor = Vector3.INF


## The formation marker this unit holds (null when none).
func formation_marker() -> Node3D:
	return _formation_marker if _formation_marker != null and is_instance_valid(_formation_marker) else null


func _line_slot(my_position: Vector3, target_pos: Vector3) -> Vector3:
	var members := _line_members()
	var centre := Vector3.INF
	if encounter_id != "" and members.size() > 1:
		centre = _encounter_centre(members)
	else:
		if _line_anchor == Vector3.INF:
			_line_anchor = my_position
		centre = _line_anchor
		members = [self]
	var to_target := target_pos - centre
	to_target.y = 0.0
	if to_target.length() < 0.1:
		to_target = -global_transform.basis.z
		to_target.y = 0.0
	var dir := to_target.normalized() if to_target.length() > 1e-4 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	# Slots go to members in the order of their home positions along the line (ties by id), so
	# nobody crosses the others to reach its place; every member computes the same order.
	members.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		var da := (a.home_position - centre).dot(side)
		var db := (b.home_position - centre).dot(side)
		return da < db if not is_equal_approx(da, db) else a.entity_id < b.entity_id)
	var spacing := float((record.get("tactics", {}) as Dictionary).get("formation_spacing_m", 3.0))
	var offset := (float(members.find(self)) - float(members.size() - 1) * 0.5) * spacing
	var slot := centre + side * offset
	slot.y = my_position.y
	return slot


## The living members of this unit's encounter that form ad-hoc lines (outmatched behaviour
## "formation", not holding a marker), sorted by entity id (this unit included).
func _line_members() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var other := n as EnemyActor
		if other == null or other.entity == null or other.entity.combatant == null:
			continue
		if other != self and (other.encounter_id != encounter_id or not other.entity.is_alive()
				or other.entity.team != entity.team or other.formation_marker() != null
				or other.formation != null):   # P30: a formation's members hold its slots, not a line
			continue
		var t: Variant = other.record.get("tactics", {})
		if other == self or (typeof(t) == TYPE_DICTIONARY and str(t.get("outmatched_behavior", "")) == "formation"):
			out.append(other)
	out.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool: return a.entity_id < b.entity_id)
	return out


## The encounter's centre: its record's center_m when an encounter record exists (P10a),
## otherwise the mean home position of `members`.
func _encounter_centre(members: Array) -> Vector3:
	var rec: Dictionary = GameData.get_record(encounter_id)
	var c: Variant = rec.get("center_m")
	if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3:
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	var sum := Vector3.ZERO
	for m: EnemyActor in members:
		sum += m.home_position
	return sum / float(maxi(1, members.size()))


# ---- corpses

## Bookkeeping while dead: frees the corpse after ai.corpse_linger_s (0 = never; an
## EncounterDirector frees its own), and returns true once the corpse has settled (on the floor,
## no knockback, still, its brain DEAD): from then on it neither decides nor moves.
func _corpse_step(tick: int) -> bool:
	if _died_tick < 0:
		_died_tick = tick
	var linger := float(record.get("ai", {}).get("corpse_linger_s", 0.0))
	if linger > 0.0 and tick - _died_tick >= ActionDef.seconds_to_ticks(linger):
		queue_free()
		return true
	if _corpse_settled:
		return true
	if is_on_floor() and knockback_velocity.length_squared() < 0.0025 \
			and Vector2(velocity.x, velocity.z).length_squared() < 0.0025 \
			and (brain.state == EnemyBrain.AIState.DEAD or not ai_enabled):
		_corpse_settled = true
		velocity = Vector3.ZERO
		move_velocity = Vector3.ZERO
		return true
	return false


## True once the corpse has settled and stopped moving.
func is_corpse_settled() -> bool:
	return _corpse_settled


# ---- taking turns with attack tokens

## A unit that gave its token back less than TOKEN_YIELD_S ago lets another one have it when
## that one was refused a token in the last TOKEN_WAIT_S (spec 10: attackers take turns; without
## this the two first holders would re-take their tokens forever). The refusals are kept on the
## target's CombatEntity (meta TOKEN_WAITERS_META: holder id -> tick), so they go with it.
const TOKEN_YIELD_S := 1.0
const TOKEN_WAIT_S := 2.0
const TOKEN_WAITERS_META := &"token_waiters"

var _token_released_tick := -1000000


func _should_yield_token(target_id: String) -> bool:
	if Sim.tick - _token_released_tick >= ActionDef.seconds_to_ticks(TOKEN_YIELD_S):
		return false
	var target := Sim.get_entity(target_id)
	if target == null or not target.has_meta(TOKEN_WAITERS_META):
		return false
	var waiters: Dictionary = target.get_meta(TOKEN_WAITERS_META)
	var holders := Sim.token_holders(target_id)
	for id: String in waiters:
		if id == entity.entity_id or holders.has(id):
			continue
		if Sim.tick - int(waiters[id]) > ActionDef.seconds_to_ticks(TOKEN_WAIT_S):
			continue
		var other := Sim.get_entity(id)
		if other != null and other.is_alive():
			return true
	return false


func _note_token_request(target_id: String, granted: bool) -> void:
	var target := Sim.get_entity(target_id)
	if target == null:
		return
	var waiters: Dictionary = target.get_meta(TOKEN_WAITERS_META, {})
	if granted:
		waiters.erase(entity.entity_id)
	else:
		waiters[entity.entity_id] = Sim.tick
	for id: String in waiters.keys():
		if Sim.tick - int(waiters[id]) > ActionDef.seconds_to_ticks(TOKEN_WAIT_S):
			waiters.erase(id)
	target.set_meta(TOKEN_WAITERS_META, waiters)
## @anchor P07
# --- grabs (P07) --------------------------------------------------------------------------------
# A giant holds this enemy (PlayerGrab, plan §3.7): on_grabbed() takes it out of the simulation
# (process mode DISABLED: Sim skips it, so no AI and no movement, and its body and hurtboxes leave
# physics, so nothing collides with or hits the held body), the holder places it every tick with
# carry() so that its Anchors/Grab sits in the hand, and on_released() sets it down upright at a
# validated spot and hands it back to its controller (GRABBED -> STAGGERED RELEASE_RECOVERY_S).
# A thrown body is carried the same way by the projectile system until it comes down. Its rig
# keeps animating while held (Visual is PAUSABLE meanwhile).

## Where the holder's hand grips the enemy (the scene's marker; plan §2.12).
const GRAB_ANCHOR_PATH := "Anchors/Grab"
## Stagger after a release (thrown, dropped, crushed, interrupted, timeout ...).
const RELEASE_RECOVERY_S := 0.6
## A release spot must fit the record's capsule, lifted this far off its floor, clear of
## RELEASE_MASK (world, actors, breakables and blockers).
const RELEASE_LIFT_M := 0.05
const RELEASE_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_ACTORS \
	| HitQueryAdapter.LAYER_BREAKABLE | LAYER_BLOCKER
## The floor under a release spot is searched this far down.
const RELEASE_FLOOR_SEARCH_M := 30.0

## Who holds (or threw) this enemy; "" when it is free. Kept through a throw until it lands, and
## through its death in the hand (controller.held_by is cleared by kill()).
var grab_holder_id := ""
var _grab_saved: Dictionary = {}


## The record's attachment profile (decision 16): torso_fist, scruff, two_hand, or none (it
## cannot be held at all).
func grab_attach() -> String:
	return str(record.get("grab_attach", "none"))


## False while dead, already held or flying, dormant (LOD tier 2) or outside the tree. The other
## grab rules (reach, sight, size, mass, immunity, attachment, broken poise) are the holder's
## (PlayerGrab.check_target). Archetypes override this for scripted moments.
func can_be_grabbed() -> bool:
	return is_inside_tree() and entity != null and entity.is_alive() and grab_holder_id == "" \
		and controller != null and controller.state != CombatController.State.GRABBED \
		and lod_tier < 2 and process_mode != Node.PROCESS_MODE_DISABLED


## True from on_grabbed() until on_released() (also while it flies after a throw).
func is_held() -> bool:
	return grab_holder_id != ""


## The grab point in this actor's own space: Anchors/Grab, else the torso anchor, else 60 % of
## its height.
func grab_anchor_local() -> Vector3:
	if _grab_saved.has("anchor"):
		return _grab_saved.anchor
	var a := get_node_or_null(GRAB_ANCHOR_PATH) as Node3D
	if a == null:
		a = get_node_or_null("Anchors/Torso") as Node3D
	if a != null:
		return to_local(a.global_position)
	return Vector3.UP * float(record.get("height_m", 1.8)) * 0.6


## The middle of the body in this actor's own space (a thrown body rides its projectile there).
func body_centre_local() -> Vector3:
	return Vector3.UP * float(record.get("height_m", 1.8)) * 0.5


## `holder_id` grabbed this enemy; its controller is already GRABBED (enter_grabbed). Until
## on_released() it is out of the simulation: Sim skips it (no perception, decisions or
## movement), its body and hurtboxes leave physics, its attack tokens go back and it cannot be
## locked. Only carry() moves it.
func on_grabbed(holder_id: String) -> void:
	if grab_holder_id != "":
		return
	var anchor := grab_anchor_local()
	grab_holder_id = holder_id
	var vis := get_node_or_null("Visual")
	_grab_saved = {"lockable": entity.combatant.lockable,
		"visual_mode": vis.process_mode if vis != null else Node.PROCESS_MODE_INHERIT, "anchor": anchor}
	Sim.release_all_tokens(entity.entity_id)
	if brain != null:
		brain.holds_token = false
		brain.attack_request = ""
	entity.combatant.lockable = false
	velocity = Vector3.ZERO
	move_velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	_motion_instance = -1
	process_mode = Node.PROCESS_MODE_DISABLED
	if vis != null:
		vis.process_mode = Node.PROCESS_MODE_PAUSABLE   # the rig keeps animating in the hand


## Places the held (or flying) body: the point `local_point` of this actor's own space (e.g.
## grab_anchor_local() or body_centre_local()) lands on `point`, the actor oriented by `basis`.
## While it is held it stays out of the simulation even if its AI LOD tier changed meanwhile
## (set_lod_tier would put it back).
func carry(point: Vector3, basis: Basis, local_point: Vector3) -> void:
	if grab_holder_id != "" and process_mode != Node.PROCESS_MODE_DISABLED:
		process_mode = Node.PROCESS_MODE_DISABLED
	global_transform = Transform3D(basis, point - basis * local_point)


## The holder let go (reason: thrown, dropped, crushed, interrupted, holder_died, target_died,
## timeout, unloaded). The body is set down upright, facing where it faced, at
## release_position(where it is, fallbacks), is back in the simulation, and its controller goes
## GRABBED -> STAGGERED RELEASE_RECOVERY_S (a dead body only drops). Nothing happens unless it
## is held.
func on_released(reason: String, fallbacks: Array = []) -> void:
	if grab_holder_id == "":
		return
	# A level unloading takes its children out of the tree first: then only the state is restored.
	var inside := is_inside_tree()
	var yaw := global_transform.basis.get_euler().y if inside else rotation.y
	if inside:
		var spot := release_position(global_position, fallbacks)
		global_transform = Transform3D(Basis(Vector3.UP, yaw), spot)
	_restore_after_grab()
	grab_holder_id = ""
	facing_yaw = wrapf(yaw, -PI, PI)
	velocity = Vector3.ZERO
	move_velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	request_repath()
	controller.release_grabbed(reason, RELEASE_RECOVERY_S)


## Where a released body goes: the first of `desired` (its root, i.e. its feet, possibly in the
## air) and then `fallbacks` whose floor leaves room for its capsule (is_free_spot). From a free
## spot in the air it drops onto that floor by itself; a blocked one is set onto the floor of
## the next candidate. When nothing fits, the last fallback (the holder's own position, outside
## every wall) on its floor, else `desired`.
func release_position(desired: Vector3, fallbacks: Array) -> Vector3:
	var candidates: Array = [desired]
	candidates.append_array(fallbacks)
	for c: Vector3 in candidates:
		var floor_pos := floor_below(c)
		if floor_pos == Vector3.INF or not is_free_spot(floor_pos):
			continue
		if c.y > floor_pos.y + 0.02 and is_free_spot(c):
			return c
		return floor_pos
	if not fallbacks.is_empty():
		var last: Vector3 = fallbacks.back()
		var f := floor_below(last)
		return f if f != Vector3.INF else last
	return desired


## The floor under `point`: a ray from 0.75 x this enemy's height above it down
## RELEASE_FLOOR_SEARCH_M (world and breakables). Vector3.INF when there is none.
func floor_below(point: Vector3) -> Vector3:
	var h := float(record.get("height_m", 1.8))
	var from := point + Vector3.UP * (h * 0.75)
	var q := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * RELEASE_FLOOR_SEARCH_M,
		HitQueryAdapter.OCCLUDER_MASK, [get_rid()])
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


## True when this enemy's capsule (record radius and height) standing at `feet`, lifted
## RELEASE_LIFT_M, overlaps nothing on RELEASE_MASK (its own body excluded).
func is_free_spot(feet: Vector3) -> bool:
	var r := float(record.get("capsule_radius_m", 0.35))
	var h := maxf(float(record.get("height_m", 1.8)), 2.0 * r)
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), feet + Vector3.UP * (h * 0.5 + RELEASE_LIFT_M))
	q.collision_mask = RELEASE_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Back into the simulation as its AI LOD tier says (dormant stays DISABLED).
func _restore_after_grab() -> void:
	if _grab_saved.is_empty():
		return
	process_mode = Node.PROCESS_MODE_DISABLED if lod_tier >= 2 else _base_process_mode
	if entity != null and entity.combatant != null:
		entity.combatant.lockable = bool(_grab_saved.lockable)
	var vis := get_node_or_null("Visual")
	if vis != null:
		vis.process_mode = _grab_saved.visual_mode
	_grab_saved = {}
## @anchor P09
# --- committed aim and ranged fighting (P09) ------------------------------------------------------
# Decision 24: a ranged actor tracks its target only during the first tracking_fraction of a
# projectile action's windup. At that tick (aim_lock_tick) it stores the target's anchor in
# runner.aim_point and stops turning; the projectile flies to the stored point (P03's aim
# "target"), so a sidestep after the lock dodges it. current_aim_point() is what the aim line
# shows: the live anchor before the lock, the stored point after it.
# Ranged archetypes (ArcherEnemy, MageEnemy) call update_ranged_aim() from their _update_facing()
# and install_ranged_helpers() on their brain (EnemyBrain's P09 section): the ranged token pool
# (decision 25: at most MAX_RANGED_HOLDERS ranged attackers per target, separate from the two
# melee tokens), staggered launch slots, and the firing-point search (elevation, then cover
# markers in the band with line of sight to the target, spread from the other ranged allies;
# otherwise a point on a ring around the target). apply_ally_cast() lands a targets_ally cast
# (the mage's barrier) on the ally the brain picked.

const RANGED_GROUP := "ranged_enemies"
const ELEVATION_GROUP := "ai_elevation_points"
const COVER_GROUP := "ai_cover_points"
## Ranged tokens live under target_id + this suffix in Sim's token table (plan §2.5).
const RANGED_TOKEN_SUFFIX := ":ranged"
const MAX_RANGED_HOLDERS := 2
## Other ranged enemies this close are the allies a firing point keeps its spread from; the list
## is refreshed once per second.
const RANGED_ALLY_RADIUS_M := 40.0
const RANGED_ALLY_REFRESH_TICKS := 60
## A marker a ranged unit fires from carries this meta (its entity id) while it holds it.
const FIRING_POINT_META := &"firing_point_holder"
## Ring points sit this far inside the band, and are turned in these steps (each way) until one
## is reachable, sees the target and keeps the spread.
const RING_BAND_MARGIN_M := 1.0
const RING_STEP_DEG := 20.0
const RING_STEPS := 4

## The firing point this unit holds (Vector3.INF when none); ranged allies keep their spread from
## it as well as from the unit itself.
var firing_point := Vector3.INF
var _firing_marker: Node3D
var _aim_instance := -1
var _aim_locked_point := Vector3.INF
var _ranged_token_key := ""
var _ranged_allies: Array = []
var _ranged_allies_tick := -1000000


## Installs this actor's engine-side ranged helpers on brain `b` (ranged archetypes call it from
## _make_brain()): ranged tokens, launch slots, the firing-point search, action readiness.
func install_ranged_helpers(b: EnemyBrain) -> void:
	b.ranged_token_request = _request_ranged_token
	b.ranged_token_release = _release_ranged_token
	b.launch_slot_request = _request_launch_slot
	b.firing_point_resolver = _resolve_firing_point
	b.firing_point_release = release_firing_point
	b.action_ready = action_ready


## The tick of `a`'s windup (controller.elapsed) at which a ranged actor commits its aim: the
## same tracking_fraction x windup at which every enemy stops turning.
static func aim_lock_tick(a: ActionDef) -> int:
	return int(a.windup_ticks * a.tracking_fraction)


## The point a drawn shot will fly to (plan §2.7.3; Vector3.INF when none): while a projectile
## action is in its windup or active phase, the target's live anchor until the aim lock and the
## stored point after it.
func current_aim_point() -> Vector3:
	if controller == null or controller.action == null or controller.action.hit_shape != "projectile":
		return Vector3.INF
	var phase := controller.phase()
	if phase != ActionDef.Phase.WINDUP and phase != ActionDef.Phase.ACTIVE:
		return Vector3.INF
	if _aim_instance == controller.instance_id and _aim_locked_point != Vector3.INF:
		return _aim_locked_point
	var t := _aim_target()
	return t.anchor_position() if t != null else Vector3.INF


## True once the running projectile action's aim is committed.
func aim_locked() -> bool:
	return controller != null and controller.action != null and _aim_instance == controller.instance_id \
		and _aim_locked_point != Vector3.INF


## Where a projectile action of this actor starts (the aim line starts there): launch_offset_m in
## the actor's own space, else its attack origin (as AttackRunner.default_launch does).
func launch_point_global(a: ActionDef) -> Vector3:
	var offset: Vector3 = Projectile.spec_for(a).launch_offset
	return to_global(offset) if offset != Vector3.INF else attack_origin_global()


## Facing and the aim lock of a ranged archetype for this tick (its _update_facing calls it):
## during a projectile action's windup it turns toward its target until aim_lock_tick, stores the
## target's anchor in runner.aim_point there and stops turning; it never turns in the active and
## recovery phases (committed). Returns false when no projectile action runs, so the base facing
## applies.
func update_ranged_aim(dt: float) -> bool:
	var a := controller.action
	if a == null or a.hit_shape != "projectile" \
			or not (controller.state in [CombatController.State.ATTACKING, CombatController.State.CASTING]):
		return false
	if _aim_instance != controller.instance_id:
		_aim_instance = controller.instance_id
		_aim_locked_point = Vector3.INF
	if controller.phase() == ActionDef.Phase.WINDUP and _aim_locked_point == Vector3.INF:
		var t := _aim_target()
		if t != null and controller.elapsed >= aim_lock_tick(a):
			_aim_locked_point = t.anchor_position()
			runner.aim_point = _aim_locked_point
		elif t != null:
			var step := deg_to_rad(_turn_rate_deg_s()) * dt
			facing_yaw = wrapf(facing_yaw + clampf(TargetingRules.yaw_delta(facing_yaw,
				_yaw_to(t.actor.global_position)), -step, step), -PI, PI)
	rotation.y = facing_yaw
	return true


## The entity a ranged actor aims at: its brain's target, else the first PLAYER-team entity.
func _aim_target() -> CombatEntity:
	var t: CombatEntity = null
	if brain != null and brain.target_id != "":
		t = Sim.get_entity(brain.target_id)
	if t == null or not is_instance_valid(t.actor):
		t = _target()
	return t


## Whether `action_id` could start now as far as its cooldown and costs go (brain.action_ready).
func action_ready(action_id: String) -> bool:
	var a := GameData.get_action(action_id)
	if a == null or controller == null or not controller.library.has(action_id):
		return false
	var pools := entity.combatant.pools
	return controller.cooldowns.is_ready(action_id, Sim.tick) and pools.can_spend_stamina(a.stamina_cost) \
		and a.essence_cost <= pools.essence + 1e-6 and a.fury_cost <= pools.fury + 1e-6


# ---- ranged tokens and launch slots

## The ranged token key of a target: target_id + RANGED_TOKEN_SUFFIX (plan §2.5).
static func ranged_token_key(target_id: String) -> String:
	return target_id + RANGED_TOKEN_SUFFIX


func _request_ranged_token() -> bool:
	if brain == null or brain.target_id == "":
		return false
	var key := ranged_token_key(brain.target_id)
	if _ranged_token_key != "" and _ranged_token_key != key:
		_release_ranged_token()
	var ok := Sim.request_token(key, entity.entity_id, MAX_RANGED_HOLDERS)
	if ok:
		_ranged_token_key = key
	return ok


func _release_ranged_token() -> void:
	if _ranged_token_key != "":
		Sim.release_token(_ranged_token_key, entity.entity_id)
		_ranged_token_key = ""


## A launch slot at the brain's target for `action_id` (Sim.request_launch_slot; spec 10's
## staggered launches): granted when launch_gap_ticks(action_id) passed since the last one.
func _request_launch_slot(action_id: String) -> bool:
	if brain == null or brain.target_id == "":
		return false
	return Sim.request_launch_slot(brain.target_id, entity.entity_id, launch_gap_ticks(action_id))


## Ticks between two launch slots at one target for `action_id`: tactics.launch_gap_s, plus how
## much shorter this action's windup is than the longest ranged windup any enemy uses. A slot is
## taken when the draw starts and the launch comes one windup later, so with mixed windups
## (archer 0.9 s, mage 1.0 s) the launches themselves stay at least launch_gap_s apart.
func launch_gap_ticks(action_id: String) -> int:
	var gap := ActionDef.seconds_to_ticks(float(_tactics().get("launch_gap_s", 1.0)))
	var a := GameData.get_action(action_id)
	var own := a.windup_ticks if a != null else 0
	return gap + maxi(0, max_ranged_windup_ticks() - own)


## The longest windup of a projectile attack in any enemy record (archer 54, mage 60 ticks).
static func max_ranged_windup_ticks() -> int:
	var most := 0
	for rec: Dictionary in GameData.records_of_type("enemy"):
		if _p34_own_launch(rec):
			continue   # P34: a troll's whelp and a giant's boulder are lobs, not volleys
		for id: Variant in rec.get("attacks", []):
			var a := GameData.get_action(str(id))
			if a != null and a.hit_shape == "projectile":
				most = maxi(most, a.windup_ticks)
	return most


func _tactics() -> Dictionary:
	var t: Variant = record.get("tactics", {})
	return t if typeof(t) == TYPE_DICTIONARY else {}


# ---- firing points

## The other living ranged enemies of this team within RANGED_ALLY_RADIUS_M (group
## ranged_enemies), cached for RANGED_ALLY_REFRESH_TICKS.
func ranged_allies() -> Array:
	if Sim.tick - _ranged_allies_tick < RANGED_ALLY_REFRESH_TICKS:
		return _ranged_allies
	_ranged_allies_tick = Sim.tick
	_ranged_allies = []
	for n in get_tree().get_nodes_in_group(RANGED_GROUP):
		var other := n as EnemyActor
		if other == null or other == self or other.entity == null or other.entity.combatant == null:
			continue
		if other.entity.team != entity.team or not other.entity.is_alive():
			continue
		if other.global_position.distance_to(global_position) <= RANGED_ALLY_RADIUS_M:
			_ranged_allies.append(other)
	return _ranged_allies


## brain.firing_point_resolver (plan §3.9): the nearest free elevation marker (group
## ai_elevation_points), else cover marker (ai_cover_points), within
## tactics.cover_search_radius_m of the unit, whose flat distance to the target lies in `band`,
## that sees the target and lies at least `spread_m` from every other ranged ally and the point
## it holds; the marker is claimed. Otherwise a point on a ring around the target - at the unit's
## own distance clamped into the band, or at the band's far edge when `far` (kiting) - in the
## unit's own direction, turned in RING_STEP_DEG steps until it is reachable, sees the target and
## keeps the spread (the first reachable one when none does).
func _resolve_firing_point(my_position: Vector3, target_pos: Vector3, band: Vector2, spread_m: float,
		far: bool) -> Vector3:
	var post := _post_firing_step()   # M7 polish: a unit on its post holds it (the posts below)
	if post != 0:
		return firing_point if post > 0 else Vector3.INF
	_release_firing_marker()
	if target_out_of_reach(my_position, target_pos, band):
		firing_point = Vector3.INF   # M7 gate: nothing it could hold reaches the target (P24b section)
		return firing_point
	var target := _aim_target()
	var allies := ranged_allies()
	var marker := _pick_firing_marker(my_position, target_pos, band, spread_m, target, allies)
	if marker != null:
		marker.set_meta(FIRING_POINT_META, entity.entity_id)
		_firing_marker = marker
		firing_point = marker.global_position
	else:
		firing_point = _ring_firing_point(my_position, target_pos, band, spread_m, far, target, allies)
	return firing_point


## Gives up the held firing point and its marker (brain.firing_point_release; death, exit).
func release_firing_point() -> void:
	_release_firing_marker()
	firing_point = Vector3.INF


## The marker this unit fires from (null when it holds none).
func firing_marker() -> Node3D:
	return _firing_marker if _firing_marker != null and is_instance_valid(_firing_marker) else null


## Everything a ranged unit holds for a target - tokens, its marker and point - goes back (death,
## scene exit).
func release_ranged_claims() -> void:
	if entity != null:
		Sim.release_all_tokens(entity.entity_id)
	_ranged_token_key = ""
	release_firing_point()


func _release_firing_marker() -> void:
	if _firing_marker != null and is_instance_valid(_firing_marker) and entity != null \
			and str(_firing_marker.get_meta(FIRING_POINT_META, "")) == entity.entity_id:
		_firing_marker.remove_meta(FIRING_POINT_META)
	_firing_marker = null


func _pick_firing_marker(my_position: Vector3, target_pos: Vector3, band: Vector2, spread_m: float,
		target: CombatEntity, allies: Array) -> Node3D:
	var search := float(_tactics().get("cover_search_radius_m", 25.0))
	for group: String in [ELEVATION_GROUP, COVER_GROUP]:
		var best: Node3D = null
		var best_d := INF
		for n in get_tree().get_nodes_in_group(group):
			var m := n as Node3D
			if m == null or not m.is_inside_tree() or not _marker_free(m):
				continue
			var f: Variant = m.get("faction")
			if typeof(f) == TYPE_STRING and f != "" and f != faction:
				continue
			var p := m.global_position
			var d := _flat_len(p - my_position)
			var td := _flat_len(p - target_pos)
			if d > search or d >= best_d or td < band.x or td > band.y:
				continue
			if _crowded(p, spread_m, allies) or not _sees_target_from(p, target):
				continue
			best = m
			best_d = d
		if best != null:
			return best
	return null


func _marker_free(m: Node) -> bool:
	var holder := str(m.get_meta(FIRING_POINT_META, ""))
	if holder == "" or (entity != null and holder == entity.entity_id):
		return true
	var h := Sim.get_entity(holder)
	return h == null or not h.is_alive()


## True when `p` is closer than `spread_m` (flat) to a living ranged ally or the point it holds.
func _crowded(p: Vector3, spread_m: float, allies: Array) -> bool:
	if spread_m <= 0.0:
		return false
	for a: Variant in allies:
		var other := a as EnemyActor
		if other == null or not is_instance_valid(other) or not other.is_inside_tree() \
				or other.entity == null or not other.entity.is_alive():
			continue
		if _flat_len(other.global_position - p) < spread_m:
			return true
		if other.firing_point != Vector3.INF and _flat_len(other.firing_point - p) < spread_m:
			return true
	return false


## Whether a unit standing at `p` could shoot `target` from there: the line from its shot's
## launch height (the lowest launch offset of its projectile attacks; its eye without one) to the
## target's anchor is clear of SIGHT_MASK, so cover it stands behind is lower than its bow. True
## without a target.
func _sees_target_from(p: Vector3, target: CombatEntity) -> bool:
	if target == null or not is_instance_valid(target.actor):
		return true
	var from := p + Vector3.UP * _shot_height()
	return HitQueryAdapter.line_clear(get_world_3d().direct_space_state, from, target.anchor_position(),
		SIGHT_MASK, target.occlusion_rids)


## The height above its feet a ranged unit's shots leave from (see _sees_target_from).
func _shot_height() -> float:
	var h := entity.combatant.height_m * 0.92
	for id: Variant in record.get("attacks", []):
		var a := GameData.get_action(str(id))
		if a != null and a.hit_shape == "projectile":
			var off: Vector3 = Projectile.spec_for(a).launch_offset
			if off != Vector3.INF:
				h = minf(h, off.y)
	return h


func _ring_firing_point(my_position: Vector3, target_pos: Vector3, band: Vector2, spread_m: float,
		far: bool, target: CombatEntity, allies: Array) -> Vector3:
	var away := my_position - target_pos
	away.y = 0.0
	var dist := away.length()
	if dist < 0.1:
		away = Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z)
	away = away.normalized() if away.length() > 1e-4 else Vector3.BACK
	var lo := band.x + RING_BAND_MARGIN_M
	var hi := maxf(lo, band.y - RING_BAND_MARGIN_M)
	var r := hi if far else clampf(dist, lo, hi)
	var start := _search_start("firing_ring")
	var fallback := _search_fallback if start > 0 else Vector3.INF
	for i in range(start, RING_STEPS * 2 + 1):
		var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)   # 0, 1, -1, 2, -2, ...
		var desired := target_pos + away.rotated(Vector3.UP, deg_to_rad(RING_STEP_DEG * k)) * r
		desired.y = my_position.y
		if not _search_affords():   # M7 gate: within the tick's path-query budget (P24b section)
			_search_fallback = fallback
			_search_stop("firing_ring", i)
			return Vector3.INF
		var q0 := NavQuery.queries_total
		var p := _walkable_point(my_position, desired)
		_search_spend(q0)
		if p == Vector3.INF:
			continue
		var td := _flat_len(p - target_pos)
		if td < band.x or td > band.y:
			continue   # the navmesh snapped it out of the band
		if fallback == Vector3.INF:
			fallback = p
		if _crowded(p, spread_m, allies) or not _sees_target_from(p, target):
			continue
		_search_done("firing_ring")
		return p
	_search_done("firing_ring")
	if fallback != Vector3.INF:
		return fallback
	if _p24b_throttled():
		return Vector3.INF   # M7 gate: no candidate is walkable - hold, and search again after FIRING_REPICK_S
	return Vector3(target_pos.x + away.x * r, my_position.y, target_pos.z + away.z * r)


## Firing-point resolvers' first step (P22's wrapper and _resolve_firing_point; M7 polish, the posts
## below): 1 when this unit holds a post - firing_point is the post, its marker claimed - 0 when it
## holds none (the searches run), -1 while that is not decided yet (it waits for the path-query budget:
## brain.nav_search_pending).
func _post_firing_step() -> int:
	var s := _post_state()
	if s < 0:
		if brain != null:
			brain.nav_search_pending = true
		return -1
	if s == 0:
		return 0
	if _firing_marker != _post:
		_release_firing_marker()
	_post.set_meta(FIRING_POINT_META, entity.entity_id)
	_firing_marker = _post
	firing_point = _post.global_position
	return 1


# ---- posts (M7 polish)
# A ranged unit that spawned on an elevation marker its navigation layer does not reach - the top of a
# world tower: the bake gives an obstacle's top no navmesh - holds that marker as its post. Its firing
# point is always the post (no search, no path query), it shoots from there at whatever its shot
# reaches (brain.post_band: 0 to the shot's range, centre to centre), it never kicks, a flight leaves
# it cowering there and a faction's step-back does not move it. Walking to any other point would only
# drop it off the tower: an agent standing off the navmesh paths from the ground below. (The toll
# fort's watchtower archers came down, stood behind the closed gate, aware, and never fired: the M7
# gate review's follow-up.) The check costs one closest-point query, once, within the tick's budget;
# a unit spawned on no elevation marker - every unit but a tower's - costs none. Elevation markers the
# navmesh reaches (the Valley's ledges, wall walks and its watchtower's top) are firing points as before.

## The spawn lies this close (flat) to an elevation marker, and this close in height, to stand on it.
const POST_SNAP_M := 1.5
const POST_HEIGHT_M := 1.5
## The marker is a post when its layer's nearest navmesh lies this far from it or more.
const POST_CLEAR_M := 3.0
## A unit this far below its post fell off it: it gives the post up and fights as any other.
const POST_LOST_M := 4.0

var _post: Node3D = null
## -1: not decided yet; 0: no post; 1: a post (_post).
var _post_decided := -1


## True while this unit holds a post (see the section notes); decides it first if needed.
func holds_post() -> bool:
	return _post_state() > 0


## The post this unit holds (null when none).
func post_marker() -> Node3D:
	return _post if _post_state() > 0 else null


## 1: holds a post; 0: none; -1: not decided yet (the closest-point query waits for the budget).
func _post_state() -> int:
	if _post_decided == 1:
		if _post == null or not is_instance_valid(_post) or not _post.is_inside_tree() \
				or global_position.y < _post.global_position.y - POST_LOST_M:
			_lose_post()   # its tower went with its chunk, or it fell off
		return _post_decided
	if _post_decided == 0:
		return 0
	var reach := _shot_reach()
	var marker := _spawn_marker() if reach < INF else null   # a post is for a unit that shoots
	if marker == null:
		_post_decided = 0
		return 0
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	if not NavQuery.has_regions(level, layers):
		_post_decided = 0   # no navigation at all (a bare test floor): the ray rules apply, as before
		return 0
	if not NavQuery.is_synced(level, layers):
		return -1   # its navigation is not in yet: decided once it is
	if _p24b_throttled() and NavQuery.budget_left(level) < 1:
		return -1
	var near := NavQuery.closest_point(level, marker.global_position, layers)
	if near.is_finite() and near.distance_to(marker.global_position) < POST_CLEAR_M:
		_post_decided = 0   # the navmesh reaches it: an ordinary firing point
		return 0
	_post = marker
	_post_decided = 1
	if brain != null:
		brain.post_band = Vector2(0.0, reach)
	return 1


## The free elevation marker (this unit's faction or none) this unit spawned on (null when none).
func _spawn_marker() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := POST_SNAP_M
	for n in get_tree().get_nodes_in_group(ELEVATION_GROUP):
		var m := n as Node3D
		if m == null or not m.is_inside_tree() or not _marker_free(m):
			continue
		var f: Variant = m.get("faction")
		if typeof(f) == TYPE_STRING and f != "" and f != faction:
			continue
		var d := _flat_len(m.global_position - home_position)
		if d <= best_d and absf(m.global_position.y - home_position.y) <= POST_HEIGHT_M:
			best = m
			best_d = d
	return best


## A unit that lost its post (it fell, or the post left the tree) fights as any other from now on: it
## looks for a firing point afresh.
func _lose_post() -> void:
	if _firing_marker != null and (not is_instance_valid(_firing_marker) or _firing_marker == _post):
		_release_firing_marker()
		firing_point = Vector3.INF
	_post = null
	_post_decided = 0
	if brain != null:
		brain.post_band = Vector2.ZERO
		brain.firing_point = Vector3.INF


## How far this unit's shots reach (flat, centre to centre): the shortest of its projectile attacks'
## ai_max_range_m and projectile range_m; INF for a unit without one (it holds no post).
func _shot_reach() -> float:
	var reach := INF
	for id: Variant in record.get("attacks", []):
		var a := GameData.get_action(str(id))
		if a == null or a.hit_shape != "projectile":
			continue
		var r := minf(float(a.params.get("ai_max_range_m", INF)), float(Projectile.spec_for(a).range_m))
		reach = minf(reach, r)
	return reach


## `desired` made walkable: on a navmesh, its closest point on this actor's layer when a path
## reaches it (the flee rules, P04); without one, `desired` when a ray from the actor reaches it
## past walls and blockers. Vector3.INF when it cannot be reached.
func _walkable_point(from: Vector3, desired: Vector3) -> Vector3:
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	if NavQuery.has_navigation(level, layers):   # P24b: through NavQuery
		return _reachable_point(level, from, NavQuery.closest_point(level, desired, layers), layers)
	var lift := Vector3.UP * 0.5
	if HitQueryAdapter.line_clear(get_world_3d().direct_space_state, from + lift, desired + lift,
			SIGHT_MASK | LAYER_BLOCKER, entity.occlusion_rids):
		return desired
	return Vector3.INF


# ---- casts on allies

## A targets_ally cast entering ACTIVE (the mage's barrier): its on_hit_statuses land on
## brain.ally_target_id when that ally is alive, of this team and within 1.5 x
## tactics.barrier_range_m (it may have moved during the cast), otherwise on the caster itself.
## ability_effect "self_buff" shows it at the receiver. Returns the receiver (null when nothing
## was applied).
func apply_ally_cast(a: ActionDef) -> CombatEntity:
	var receiver := entity
	var id := brain.ally_target_id if brain != null else ""
	if id != "" and id != entity.entity_id:
		var e := Sim.get_entity(id)
		var reach := float(_tactics().get("barrier_range_m", 12.0)) * 1.5
		if e != null and e.is_alive() and is_instance_valid(e.actor) and e.team == entity.team \
				and e.actor.global_position.distance_to(global_position) <= reach:
			receiver = e
	var applied := false
	var list: Variant = a.param("on_hit_statuses", [])
	if typeof(list) == TYPE_ARRAY:
		for entry: Variant in list:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if receiver.apply_status(str(entry.get("status", "")), float(entry.get("magnitude", NAN)),
					float(entry.get("duration_s", -1.0)), entity.entity_id):
				applied = true
	if not applied:
		return null
	Events.ability_effect.emit(Sim.tick, entity.entity_id, a.id, "self_buff", receiver.actor.global_position,
		0.0, facing_yaw, 0.0)
	return receiver
## @anchor P10a
# --- leash return (P10a) ------------------------------------------------------------------------
# The EncounterDirector calls begin_leash_return() on a member that strayed farther than its
# encounter's leash radius from the centre (plan §3.10). The member drops its target and runs
# back to home_position, ignoring the player on the way: the brain is in RETURN and its
# perception and decisions are paused (ai_enabled false until it is home - EnemyBrain.decide()
# hands states it does not know to the archetype's _decide_engaged(), so RETURN is driven from
# here, by a Sim PRE_ACTORS hook of its own, right after the director's). What it hears or is
# hit by on the way is forgotten at once (handlers connected after the base ones). LEASH_HEAL_S
# after the leash it is back at full health (stamina and poise reset too); once home (or dead)
# the return ends and its AI resumes from IDLE, so it can engage again.

## Seconds after the leash began until the member is back at full health.
const LEASH_HEAL_S := 6.0
## The return ends this close to home_position (horizontal metres).
const LEASH_ARRIVE_M := 1.5
## PRE_ACTORS hook order of the return (after the EncounterDirector's 10).
const LEASH_HOOK_ORDER := 12

## Tick the current leash return began (-1 when it is not returning).
var leash_started_tick := -1
## How many leash returns this actor began (tests, debug).
var leash_count := 0
var _leash_returning := false
var _leash_healed := false
var _leash_ai_was_enabled := true
var _leash_hook_owner: RefCounted = null


## Starts the leash return (plan §2.7.3): drop the target and its attack tokens, run home to
## home_position ignoring the player, regain full health LEASH_HEAL_S later, then resume the AI
## at home. Nothing happens while dead or already returning.
func begin_leash_return() -> void:
	if _leash_returning or entity == null or not entity.is_alive() or brain == null:
		return
	_leash_returning = true
	_leash_healed = false
	leash_started_tick = Sim.tick
	leash_count += 1
	_leash_ai_was_enabled = ai_enabled
	ai_enabled = false   # no perception, no decisions: it ignores targets until it is home
	Sim.release_all_tokens(entity.entity_id)
	_release_formation_marker()
	brain.begin_return(Sim.tick)
	request_repath()
	_leash_hook_owner = RefCounted.new()
	Sim.add_hook(Sim.Hook.PRE_ACTORS, _leash_hook_owner, _leash_step, LEASH_HOOK_ORDER)
	# Run after _on_hit_taken / _on_any_ability_started (connected in _ready): undo what they
	# taught the brain while it walks home.
	if not entity.hit_taken.is_connected(_on_hit_while_returning):
		entity.hit_taken.connect(_on_hit_while_returning)
	if not Events.ability_started.is_connected(_on_noise_while_returning):
		Events.ability_started.connect(_on_noise_while_returning)
	_leash_step(Sim.tick)


## True from begin_leash_return() until the member is home (or dead).
func is_returning() -> bool:
	return _leash_returning


func _leash_step(tick: int) -> void:
	if not _leash_returning:
		return
	if not is_inside_tree() or entity == null or entity.combatant == null:
		_end_leash_return(false)   # despawned or unloaded: nothing left to walk home
		return
	if not entity.is_alive():
		_end_leash_return(true)
		return
	if is_held():
		return   # a giant holds it (P07): the return waits until it is put down
	if not _leash_healed and tick - leash_started_tick >= ActionDef.seconds_to_ticks(LEASH_HEAL_S):
		_leash_heal()
	var to_home := Vector2(home_position.x - global_position.x, home_position.z - global_position.z)
	if to_home.length() <= LEASH_ARRIVE_M:
		_end_leash_return(true)
		return
	brain.return_step(tick, home_position)


## Ends the return: the hook goes, a living member is healed (if the 6 s had not passed yet) and
## its AI resumes from IDLE at home; a dead one's brain becomes DEAD. in_world: still in the
## level (false when it left the tree: only the state is reset).
func _end_leash_return(in_world: bool) -> void:
	_leash_returning = false
	leash_started_tick = -1
	if _leash_hook_owner != null:
		Sim.remove_hooks(_leash_hook_owner)
		_leash_hook_owner = null
	if entity != null and entity.hit_taken.is_connected(_on_hit_while_returning):
		entity.hit_taken.disconnect(_on_hit_while_returning)
	if Events.ability_started.is_connected(_on_noise_while_returning):
		Events.ability_started.disconnect(_on_noise_while_returning)
	var alive := entity != null and entity.combatant != null and entity.is_alive()
	if in_world and alive and not _leash_healed:
		_leash_heal()
	ai_enabled = _leash_ai_was_enabled
	if brain != null:
		brain.end_return(Sim.tick, alive)


func _on_hit_while_returning(_result: HitResult) -> void:
	if _leash_returning and brain != null:
		brain.return_step(Sim.tick, home_position)


func _on_noise_while_returning(_tick: int, _actor_id: String, _action_id: String, _instance: int) -> void:
	if _leash_returning and brain != null and is_inside_tree():
		brain.return_step(Sim.tick, home_position)


## Full health (through CombatEntity.heal, so Events.healed shows it), full stamina, no poise
## damage.
func _leash_heal() -> void:
	_leash_healed = true
	if entity == null or not entity.is_alive():
		return
	var pools := entity.combatant.pools
	entity.heal(pools.health_max - pools.health, "leash")
	pools.restore({"stamina": pools.stamina_max})
	if not entity.combatant.poise.locked:
		entity.combatant.poise.value = 0.0
## @anchor P11a
# --- boss phases and attack chains (P11a) --------------------------------------------------------
# A boss archetype (OgreBoss) wires these from its own _ready() and sim_step() (plan §3.12):
# install_boss_hooks() connects the brain's boss_phase_entered, so each new phase is announced
# once (Events.boss_phase_changed) and its enter_action is forced (controller.force_action: the
# Ogre King's roar); update_boss_phase() feeds the brain the health fraction every tick;
# queue_chain_next() lets an enemy action with chain_next run straight into its follow-up (the
# boss's two-hit combo): during the action's recovery the follow-up is requested every tick, so
# the controller's input buffer starts it on the very tick the action ends, while a stagger, a
# death or a forced action (each clears the buffer) cancels it.

## How many boss phases this actor announced (tests, debug).
var phase_changes := 0


## Connects the brain's boss phases to this actor and adds every phase action (attacks,
## sequence, enter_action) to the controller's library.
func install_boss_hooks() -> void:
	if brain == null or controller == null:
		return
	if not brain.boss_phase_entered.is_connected(_on_boss_phase_entered):
		brain.boss_phase_entered.connect(_on_boss_phase_entered)
	for p: Dictionary in brain.boss_phases:
		var ids: Array = (p.get("attacks", []) as Array) + (p.get("sequence", []) as Array)
		ids.append(str(p.get("enter_action", "")))
		for id: Variant in ids:
			var def := GameData.get_action(str(id))
			if def != null and not controller.library.has(def.id):
				controller.add_action(def)


## Feeds the brain this actor's health fraction (a boss phase may begin). Living actors only.
func update_boss_phase() -> void:
	if brain == null or not brain.has_boss_phases() or entity == null or not entity.is_alive():
		return
	brain.update_boss_phase(entity.combatant.pools.ratio("health"), Sim.tick)


func _on_boss_phase_entered(phase: int, _phase_id: String, enter_action: String) -> void:
	phase_changes += 1
	Events.boss_phase_changed.emit(Sim.tick, entity.entity_id, phase)
	var def := GameData.get_action(enter_action)
	if def != null and entity.is_alive():
		controller.force_action(def)


## Requests the running action's chain_next during its recovery (see above). Call it once per
## tick, after sim_step's own work.
func queue_chain_next() -> void:
	var a := controller.action if controller != null else null
	if a == null or a.chain_next == "" or controller.phase() != ActionDef.Phase.RECOVERY:
		return
	if controller.state != CombatController.State.ATTACKING and controller.state != CombatController.State.CASTING:
		return
	if controller.library.has(a.chain_next):
		controller.request(&"attack", {"action_id": a.chain_next})
## @anchor P11b
# --- faction members: standing, posts, guard (P11b) ----------------------------------------------
# Plan §3.13 designs 2 and 3, decision 17. An enemy with a `faction` (Thornwick's guards and tower
# archer: "village") follows its faction's standing (FactionState: WorldState flags, announced as
# Events.faction_changed). Read once when it enters the tree - so a member spawned after the village
# turned hostile spawns hostile - and again on every faction_changed of its faction:
#   neutral / warned  team NEUTRAL (TargetingRules: not lockable, area effects skip it, it cannot
#                     hurt the player), brain mode "neutral": HOLD at its post, guard up while it
#                     watches the giant, no attacks, never aware;
#   stood_down        team NEUTRAL, brain mode "stood_down": walks to its post, guard down;
#   hostile           team ENEMY (lockable), the normal AI - and, when it turns hostile in front of
#                     the giant, it is told where the giant is at once (a certain noise).
# Its post is the nearest free formation marker of its own faction within FACTION_POST_RADIUS_M of
# its home (claimed with P04's formation_holder meta, so a hostile member's formation keeps it),
# else its home; it faces the way it faced when it entered the tree. An actor without a faction
# is unchanged (faction_standing "").

## A member's post is a formation marker of its faction this close to its home position.
const FACTION_POST_RADIUS_M := 6.0

## "" (no faction) or the standing it acts on: "neutral", "warned", "stood_down", "hostile".
var faction_standing := ""
var _home_yaw := 0.0


func _p11b_ready() -> void:
	_home_yaw = rotation.y
	if faction == "" or brain == null:
		return
	brain.post_resolver = faction_post
	if not Events.faction_changed.is_connected(_on_faction_changed):
		Events.faction_changed.connect(_on_faction_changed)
	FactionState.hub()
	_apply_standing(FactionState.standing(faction), false)


## True while this actor is a faction member at peace (neutral, warned or stood down).
func at_peace() -> bool:
	return faction_standing in ["neutral", "warned", "stood_down"]


func _on_faction_changed(_tick: int, changed_faction: String, _state: String) -> void:
	if not is_inside_tree() or changed_faction != faction or entity == null or entity.combatant == null or brain == null:
		return
	_apply_standing(FactionState.standing(faction), true)


## Applies a standing (see the section notes). alert: a member that turns hostile now is told
## where the giant is.
func _apply_standing(standing: String, alert: bool) -> void:
	if standing == faction_standing:
		return
	faction_standing = standing
	if standing == "hostile":
		entity.team = CombatEntity.Team.ENEMY
		brain.set_faction_mode("", Sim.tick)
		if alert and entity.is_alive() and not is_returning():
			var t := _target()
			if t != null and t.is_alive() and is_instance_valid(t.actor):
				brain.on_noise(Sim.tick, t.actor.global_position, t.entity_id, true)
		return
	entity.team = CombatEntity.Team.NEUTRAL
	Sim.release_all_tokens(entity.entity_id)
	brain.set_faction_mode("stood_down" if standing == "stood_down" else "neutral", Sim.tick)


## brain.post_resolver: where this member stands at peace - its claimed formation marker of its
## own faction near home, else home - and a point to face there (along its home facing).
func faction_post() -> Dictionary:
	var post := home_position
	var m := formation_marker()
	if m == null or not m.is_inside_tree() or not _is_own_post(m):
		if m != null:
			_release_formation_marker()
		m = _claim_faction_post()
	if m != null:
		post = m.global_position
	var forward := Vector3(-sin(_home_yaw), 0.0, -cos(_home_yaw))
	return {"post": post, "face": post + forward * 10.0}


func _is_own_post(m: Node3D) -> bool:
	var f: Variant = m.get("faction")
	return typeof(f) == TYPE_STRING and f == faction \
		and _flat_len(m.global_position - home_position) <= FACTION_POST_RADIUS_M + 1e-3


## The nearest free formation marker of this actor's faction (not "") within
## FACTION_POST_RADIUS_M of home, claimed; null when there is none.
func _claim_faction_post() -> Node3D:
	var best: Node3D = null
	var best_d := FACTION_POST_RADIUS_M + 1e-3
	for n in get_tree().get_nodes_in_group(FORMATION_GROUP):
		var m := n as Node3D
		if m == null or not m.is_inside_tree() or not _is_own_post(m):
			continue
		var holder := str(m.get_meta(FORMATION_HOLDER_META, ""))
		if holder != "" and holder != entity.entity_id:
			var h := Sim.get_entity(holder)
			if h != null and h.is_alive():
				continue
		var d := _flat_len(m.global_position - home_position)
		if d < best_d:
			best = m
			best_d = d
	if best != null:
		best.set_meta(FORMATION_HOLDER_META, entity.entity_id)
		_formation_marker = best
	return best


## A member at peace: a neutral (or warned) one keeps its guard up while it watches the giant
## (HOLD, not acting, a guard record and the stamina for it); a stood-down one lowers it.
func _guarding_at_peace() -> bool:
	if faction_standing == "stood_down" or controller == null or brain == null:
		return false
	var guard: Dictionary = record.get("guard", {})
	if guard.is_empty() or controller.state != CombatController.State.LOCOMOTION \
			or brain.state != EnemyBrain.AIState.HOLD:
		return false
	if Sim.tick - brain.last_seen_tick > ActionDef.seconds_to_ticks(float(record.get("ai", {}).get("memory_s", 3.0))):
		return false
	return entity.combatant.pools.stamina >= float(guard.get("min_stamina", 0.0))


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P22
# --- the distance LOD, a guard's step-back and ranged positioning (P22) --------------------------
# Plan M6-M9 §3.4 designs 2, 4 and 8.
#   * Distance LOD (decision 9): the record's render_lod_m goes to the rig (ActorRig, or the wolf's
#     QuadrupedRig): at AI LOD tiers 0 and 1 the renderer swaps the rig for a copy of its one-box
#     proxy under Visual/Body by distance (RigPaint). set_lod_tier is unchanged: tier 2 still hides
#     Visual/Body and shows Visual/LodProxy.
#   * A faction member at peace steps back STEP_BACK_M from an enemy that comes within
#     FactionState.STEP_BACK_TRIGGER_M of it (FactionState's hook calls faction_step_back), so a
#     fight beside Thornwick's guards does not put them under the giant's blows; it walks back to
#     its post once no enemy has been near for STEP_BACK_HOLD_S.
#   * Ranged units (tactics.front_arc_deg): a new firing point is taken in front of the giant's
#     camera when one exists - a marker, else a ring point, whose bearing from the target lies
#     within front_arc_deg / 2 of the camera's yaw - before the P09 search; and a shot drawn from
#     outside the camera's view (in_camera_view: the horizontal field of view, as RunMetrics counts
#     the off-camera share) runs a copy of the shot whose windup is at least
#     tactics.off_camera_aim_s (the threat cue leads it).

const STEP_BACK_M := 10.0
const STEP_BACK_HOLD_S := 2.0
## A ranged unit's camera checks fall back to this half field of view when the camera reports none.
const CAMERA_FALLBACK_HALF_FOV_DEG := 55.0

## Where a member at peace stands back from a nearby fight (Vector3.INF = not stepping back).
var step_back_point := Vector3.INF
var _step_back_from := Vector3.INF
var _step_back_tick := -1000000
var _p22_post_resolver := Callable()


func _p22_ready() -> void:
	var visual := get_node_or_null("Visual")
	if visual != null and visual.has_method("set_render_lod"):
		visual.call("set_render_lod", float(record.get("render_lod_m", 0.0)))
	if brain == null:
		return
	if brain.post_resolver.is_valid():
		_p22_post_resolver = brain.post_resolver
		brain.post_resolver = _p22_faction_post
	if brain.firing_point_resolver.is_valid():
		var p09_resolver := brain.firing_point_resolver
		brain.firing_point_resolver = func(my_position: Vector3, target_pos: Vector3, band: Vector2,
				spread_m: float, far: bool) -> Vector3:
			var post := _post_firing_step()   # M7 polish: a unit on its post holds it (P09 section)
			if post != 0:
				return firing_point if post > 0 else Vector3.INF
			# M7 gate: while P09's ring search resumes, the front arc already ended with nothing
			if not search_resuming("firing_ring"):
				var p := front_arc_firing_point(my_position, target_pos, band, spread_m, far)
				if p != Vector3.INF or brain.nav_search_pending:
					return p   # M7 gate: a front-arc search waiting for the budget resumes next decision
			return p09_resolver.call(my_position, target_pos, band, spread_m, far)
		brain.view_probe = camera_view
		brain.shot_preparer = prepare_shot
		if brain.flee_resolver.is_valid():
			var p04_flee := brain.flee_resolver
			brain.flee_resolver = func(from: Vector3, threat: Vector3, distance: float) -> Vector3:
				var post := _post_state()   # M7 polish: on its post a fleeing unit cowers there (P09 section)
				if post != 0:
					if post < 0:
						brain.nav_search_pending = true   # decided once the tick's budget allows
					return Vector3.INF
				return p04_flee.call(from, threat, distance)


## The record's render_lod_m (0 = never).
func render_lod_m() -> float:
	return float(record.get("render_lod_m", 0.0))


# ---- the camera

## The giant's camera (its CameraRig's Camera3D), or null.
func _player_camera() -> Camera3D:
	var p := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if p == null:
		return null
	var rig: Variant = p.get("camera_rig")
	if not (rig is Node) or not is_instance_valid(rig):
		return null
	var cam: Variant = (rig as Node).get("camera")
	return cam as Camera3D if cam is Camera3D and (cam as Camera3D).is_inside_tree() else null


## The giant's camera as ranged positioning sees it (brain.view_probe): {"yaw": its horizontal
## facing (Godot yaw, 0 = -Z), "on_camera": this unit inside its horizontal field of view}; {}
## without a camera.
func camera_view() -> Dictionary:
	var cam := _player_camera()
	if cam == null:
		return {}
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return {}
	return {"yaw": TargetingRules.yaw_of(fwd), "on_camera": in_camera_view(cam, global_position)}


## True when `pos` lies inside `cam`'s horizontal field of view (flat; the half angle from its fov
## and the viewport's aspect, else CAMERA_FALLBACK_HALF_FOV_DEG). RunMetrics counts a hit as
## "off camera" with the same test.
static func in_camera_view(cam: Camera3D, pos: Vector3) -> bool:
	if cam == null:
		return true
	var to := pos - cam.global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return true
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return true
	var half := deg_to_rad(CAMERA_FALLBACK_HALF_FOV_DEG)
	if cam.fov > 1.0:
		var aspect := 16.0 / 9.0
		var vp := cam.get_viewport()
		if vp != null:
			var size := vp.get_visible_rect().size
			if size.y > 1.0:
				aspect = size.x / size.y
		half = atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect)
	return absf(fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)) <= half


# ---- ranged positioning

## A firing point in front of the camera (see the section notes): the nearest free elevation, then
## cover marker within tactics.cover_search_radius_m that lies in the band and the front arc, sees
## the target and keeps the spread (claimed); else a ring point in the arc - at this unit's own
## distance clamped into the band, or the band's far edge when `far` - starting from the arc
## direction nearest this unit's bearing and turning in RING_STEP_DEG steps inside the arc.
## Vector3.INF when the record has no front_arc_deg, there is no camera, or nothing in the arc
## works (the P09 search then runs).
func front_arc_firing_point(my_position: Vector3, target_pos: Vector3, band: Vector2, spread_m: float,
		far: bool) -> Vector3:
	var arc := float(_tactics().get("front_arc_deg", 0.0))
	var view := camera_view()
	if arc <= 0.0 or view.is_empty():
		return Vector3.INF
	if target_out_of_reach(my_position, target_pos, band):
		return Vector3.INF   # M7 gate: nothing it could hold reaches the target (P24b section)
	var yaw := float(view.yaw)
	_release_firing_marker()
	var target := _aim_target()
	var allies := ranged_allies()
	var search := float(_tactics().get("cover_search_radius_m", 25.0))
	for group: String in [ELEVATION_GROUP, COVER_GROUP]:
		var best: Node3D = null
		var best_d := INF
		for n in get_tree().get_nodes_in_group(group):
			var m := n as Node3D
			if m == null or not m.is_inside_tree() or not _marker_free(m):
				continue
			var f: Variant = m.get("faction")
			if typeof(f) == TYPE_STRING and f != "" and f != faction:
				continue
			var p := m.global_position
			var d := _flat_len(p - my_position)
			var td := _flat_len(p - target_pos)
			if d > search or d >= best_d or td < band.x or td > band.y:
				continue
			if not EnemyBrain.in_front_arc(p, target_pos, yaw, arc) or _crowded(p, spread_m, allies) \
					or not _sees_target_from(p, target):
				continue
			best = m
			best_d = d
		if best != null:
			best.set_meta(FIRING_POINT_META, entity.entity_id)
			_firing_marker = best
			firing_point = best.global_position
			return firing_point
	var away := my_position - target_pos
	away.y = 0.0
	var dist := away.length()
	var half := deg_to_rad(arc) * 0.5
	var own_yaw := TargetingRules.yaw_of(away) if dist > 0.1 else yaw
	var start := yaw + clampf(angle_difference(yaw, own_yaw), -half, half)
	var lo := band.x + RING_BAND_MARGIN_M
	var hi := maxf(lo, band.y - RING_BAND_MARGIN_M)
	var r := hi if far else clampf(dist, lo, hi)
	var steps := int(floor(rad_to_deg(half) * 2.0 / RING_STEP_DEG))
	for i in range(_search_start("firing_arc"), steps * 2 + 1):
		var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)   # 0, 1, -1, 2, -2, ...
		var a := start + deg_to_rad(RING_STEP_DEG * k)
		if absf(angle_difference(yaw, a)) > half + 1e-4:
			continue
		var desired := target_pos + Vector3(-sin(a), 0.0, -cos(a)) * r
		desired.y = my_position.y
		if not _search_affords():   # M7 gate: within the tick's path-query budget (P24b section)
			_search_stop("firing_arc", i)
			return Vector3.INF
		var q0 := NavQuery.queries_total
		var p := _walkable_point(my_position, desired)
		_search_spend(q0)
		if p == Vector3.INF:
			continue
		var td := _flat_len(p - target_pos)
		if td < band.x or td > band.y or not EnemyBrain.in_front_arc(p, target_pos, yaw, arc):
			continue
		if _crowded(p, spread_m, allies) or not _sees_target_from(p, target):
			continue
		_search_done("firing_arc")
		firing_point = p
		return p
	_search_done("firing_arc")
	return Vector3.INF


## Before a shot starts (brain.shot_preparer): drawn from outside the camera's view, the controller
## runs a copy of `shot_id` whose windup is at least tactics.off_camera_aim_s (the aim still locks
## at its tracking_fraction); otherwise the record's own. The action id stays the same (cooldowns,
## cues, metrics).
func prepare_shot(shot_id: String, off_camera: bool) -> void:
	if controller == null or not controller.library.has(shot_id):
		return
	var base := GameData.get_action(shot_id)
	if base == null:
		return
	var aim_s := float(_tactics().get("off_camera_aim_s", 0.0))
	var windup_s := float(base.params.get("windup_s", 0.0))
	if not off_camera or aim_s <= windup_s + 1e-6:
		controller.library[shot_id] = base
		return
	var rec: Dictionary = base.params.duplicate(true)
	rec["windup_s"] = aim_s
	controller.library[shot_id] = ActionDef.from_dict(rec)


# ---- a member at peace steps back from a fight

## FactionState's hook: an enemy at `threat` is within its trigger distance of this member at
## peace. It steps STEP_BACK_M away from it (a reachable point, P04's flee search), re-aimed when
## the threat moved more than 3 m, and the post it holds becomes that point.
func faction_step_back(threat: Vector3) -> void:
	if _post_decided == 1:
		return   # M7 polish: a unit on its post stays there (P09 section)
	_step_back_tick = Sim.tick
	if step_back_point != Vector3.INF and _step_back_from != Vector3.INF \
			and _flat_len(threat - _step_back_from) < 3.0:
		return
	var p := _resolve_flee_point(global_position, threat, STEP_BACK_M)
	if p == Vector3.INF:
		return
	step_back_point = p
	_step_back_from = threat
	if brain != null:
		brain.refresh_post()


## FactionState's hook: no enemy is near; after STEP_BACK_HOLD_S the member walks back to its post.
func faction_step_back_clear() -> void:
	if step_back_point == Vector3.INF:
		return
	if Sim.tick - _step_back_tick < ActionDef.seconds_to_ticks(STEP_BACK_HOLD_S):
		return
	step_back_point = Vector3.INF
	_step_back_from = Vector3.INF
	if brain != null:
		brain.refresh_post()


## True while this actor is a faction member that is not hostile: at peace (neutral, warned, stood
## down) or reconciled (P22: FactionState's "reconciled" standing, which members treat as neutral).
func member_at_peace() -> bool:
	return faction != "" and faction_standing != "" and faction_standing != "hostile"


## brain.post_resolver while at peace: the step-back point (facing the fight) while stepping back,
## else the P11b post.
func _p22_faction_post() -> Dictionary:
	if step_back_point != Vector3.INF and member_at_peace():
		return {"post": step_back_point, "face": _step_back_from}
	return _p22_post_resolver.call() if _p22_post_resolver.is_valid() else {}

## @anchor P24b
# --- navigation through NavQuery, the repath throttle, the chase goal (P24b) ----------------------
# Plan M6-M9 §2.8, decision 13. Every navigation question goes through NavQuery on the level's map
# for this actor's layer (nav_level(): the level root, else this actor's own world): flight and
# reachability (_reachable_point, _walkable_point, flee points snapped with NavQuery.closest_point).
# In a level with nav_query settings (a streamed world) also:
#   * the agent paths on its layer's own map (NavigationAgent3D.set_navigation_map) with unlimited
#     polygons and the chase distance cap;
#   * tier-0 re-paths are throttled - at least repath_min_ticks apart and only when the goal moved
#     repath_min_move_m - and wait for the tick's query budget (NavQuery.budget_left; each one is
#     spent); a path failure still asks at once (within the budget);
#   * the chase goal is snapped to the layer: the agent's query ends at the layer's point nearest the
#     goal, and when that end lies more than REACH_SLACK_M from the goal (a giant wading deep water,
#     out of the human layer) the actor stops there instead of steering on into the water, and its
#     progress is measured to it (standing on the bank is not a path failure).
# Without settings (the Valley, test levels) nothing changes: the default map, today's re-path rule
# and parameters, the raw goal.

## A path ending this far (horizontally) from its goal did not reach it: the actor stops at its end.
const REACH_SLACK_M := 2.0

var _p24b_level_ref: WeakRef = null
var _p24b_settings := {}


func _p24b_ready() -> void:
	var level := nav_level()
	_p24b_settings = NavQuery.settings(level)
	if _p24b_settings.is_empty():
		return
	var layers := int(agent.navigation_layers)
	var m := NavQuery.map_for(level, layers)
	if m.is_valid():
		agent.set_navigation_map(m)
	var p := NavQuery.params_for(level, NavQuery.PURPOSE_CHASE)
	agent.path_search_max_polygons = int(p.max_polygons)
	agent.path_search_max_distance = float(p.max_distance)


## The level this actor asks for navigation: the level root of the tree (as LevelRoot.nav_region
## was found before), else the actor itself (a bare test world: its world's default map).
func nav_level() -> Node:
	if _p24b_level_ref != null:
		var n := _p24b_level_ref.get_ref() as Node
		if n != null and n.is_inside_tree():
			return n
	_p24b_level_ref = null
	var level := get_tree().get_first_node_in_group("level_root") if is_inside_tree() else null
	if level == null:
		return self
	_p24b_level_ref = weakref(level)
	return level


## True in a level with nav_query settings (the throttle, the budget and the chase goal apply).
func _p24b_throttled() -> bool:
	return not _p24b_settings.is_empty()


## The streamed world's re-path rule (see the section notes). Tier 1 keeps P04's rule, within the
## budget.
func _p24b_wants_repath(goal: Vector3) -> bool:
	if NavQuery.budget_left(nav_level()) <= 0:
		return false
	if lod_tier >= 1:
		return _last_nav_target == Vector3.INF and Sim.tick - _last_repath_tick >= TIER1_REPATH_TICKS
	if _last_nav_target == Vector3.INF:
		return true
	return Sim.tick - _last_repath_tick >= int(_p24b_settings.get("repath_min_ticks", 6)) \
		and _last_nav_target.distance_to(goal) >= float(_p24b_settings.get("repath_min_move_m", 2.0))


## Streamed world: the agent's waypoint check is horizontal (NavQuery.level_waypoint - a lean
## navmesh lies up to 1.3 m off the terrain, more than the agent's 0.6 m waypoint distance).
func _p24b_level_waypoint() -> void:
	if _p24b_throttled():
		NavQuery.level_waypoint(agent, global_position)


## Where steering and the progress check aim for `goal`: the goal itself, unless (streamed world)
## the agent's path ends more than REACH_SLACK_M from it - then that end (the bank).
func _p24b_reach(goal: Vector3) -> Vector3:
	if not _p24b_throttled():
		return goal
	var res := agent.get_current_navigation_result()
	if res == null or res.path.is_empty():
		return goal
	var end := agent.get_final_position()
	if Vector2(end.x - goal.x, end.z - goal.z).length() > REACH_SLACK_M:
		return end
	return goal


# ---- searches within the path-query budget (M7 gate)
# A firing-point search (P09's ring, P22's front arc), a flee search (P04) and a rout point (P30) try
# candidates - each a closest point and up to two paths (_walkable_point / _reachable_point). In a
# streamed world (nav_query settings) they spend NavQuery's per-tick budget like a re-path does: a
# candidate is tried only while the level's budget_left() and this actor's own share of the tick
# (SEARCH_QUERIES_PER_TICK) allow it; otherwise the search stops where it is, brain.nav_search_pending
# says so, and the brain's next decision resumes it at that candidate (within SEARCH_RESUME_TICKS).
# The searches used to run every candidate at once: a raider archer or mage spent 32-34 queries in
# one tick (17-27 ms) on a target 200 m away. Without settings (the Valley, test levels) the searches
# run as before.

## One candidate's path queries (its closest point and up to two paths), and the most one actor's
## searches spend in a tick: one candidate a tick.
const SEARCH_CANDIDATE_QUERIES := 3
const SEARCH_QUERIES_PER_TICK := 3
## A search stopped for the budget resumes at its candidate when it is asked again within this many
## ticks (the brain asks at its next decision); later it starts anew.
const SEARCH_RESUME_TICKS := 30

var _search_key := ""
var _search_next := 0
var _search_stop_tick := -1000000
var _search_spent_tick := -1
var _search_spent := 0
## The ring search's in-band fallback found before it stopped for the budget.
var _search_fallback := Vector3.INF
## The most path queries this actor's searches spent in one tick (tests, measurements).
var search_queries_peak := 0


## The candidate search `key` ("firing_arc", "firing_ring", "flee", "rout") starts from: the one it
## stopped at when asked again soon, else the first.
func _search_start(key: String) -> int:
	return _search_next if search_resuming(key) else 0


## True while search `key` waits to resume (it stopped for the budget at most SEARCH_RESUME_TICKS
## ago). A resolver that chains searches skips the stages before it meanwhile: they ended without a
## point in this round, and searching them again would spend the tick's share and overwrite where
## `key` stopped, so it would never end (P22's front arc before P09's ring; P30's rout point before
## P04's flight, see _p30_rout_failed).
func search_resuming(key: String) -> bool:
	return _search_key == key and Sim.tick - _search_stop_tick <= SEARCH_RESUME_TICKS


## True when one more candidate fits this tick: always without nav_query settings; in a streamed
## world when the level's budget has SEARCH_CANDIDATE_QUERIES left and this actor's searches spent
## at most SEARCH_QUERIES_PER_TICK - SEARCH_CANDIDATE_QUERIES this tick.
func _search_affords() -> bool:
	if not _p24b_throttled():
		return true
	_search_roll()
	return _search_spent + SEARCH_CANDIDATE_QUERIES <= SEARCH_QUERIES_PER_TICK \
		and NavQuery.budget_left(nav_level()) >= SEARCH_CANDIDATE_QUERIES


## Counts what a candidate spent (NavQuery.queries_total when it began).
func _search_spend(queries_before: int) -> void:
	_search_roll()
	_search_spent += NavQuery.queries_total - queries_before
	search_queries_peak = maxi(search_queries_peak, _search_spent)


func _search_roll() -> void:
	if _search_spent_tick != Sim.tick:
		_search_spent_tick = Sim.tick
		_search_spent = 0


## Search `key` stops at candidate `next` for the budget: brain.nav_search_pending, and it resumes there.
func _search_stop(key: String, next: int) -> void:
	_search_key = key
	_search_next = next
	_search_stop_tick = Sim.tick
	if brain != null:
		brain.nav_search_pending = true


## Search `key` ended (found a point or tried every candidate): the next one starts anew.
func _search_done(key: String) -> void:
	if _search_key == key:
		_search_key = ""
		_search_next = 0


## M7 gate: true in a streamed world when no firing point this unit could hold would have the target
## in `band`: the target lies farther than the chase distance (the path cap: no candidate around it
## can be reached) beyond the band from the unit, or farther than the band beyond the unit's
## encounter leash (it would walk out of its leash and be sent home). The firing search is then
## skipped - not a query - and the brain holds where it stands and asks again after FIRING_REPICK_S.
func target_out_of_reach(my_position: Vector3, target_pos: Vector3, band: Vector2) -> bool:
	if not _p24b_throttled():
		return false
	var chase := float(NavQuery.params_for(nav_level(), NavQuery.PURPOSE_CHASE).max_distance)
	if chase > 0.0 and _flat_len(target_pos - my_position) - band.y > chase:
		return true
	if encounter_id == "":
		return false
	var rec := GameData.get_record(encounter_id)
	var leash := float(rec.get("leash_radius_m", 0.0))
	var c: Variant = rec.get("center_m")
	if leash <= 0.0 or typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
		return false
	var centre := Vector3(float(c[0]), target_pos.y, float(c[2]))
	return _flat_len(target_pos - centre) - leash > band.y + EnemyBrain.BAND_TOLERANCE_M

## @anchor P30
# --- formations, the banner, shields and the target provider (P30) --------------------------------
# Plan M6-M9 §2.10, decisions 19 and 20. Hook lines elsewhere in this file: _ready (_p30_ready),
# _target (the provider), _sense (_p30_sense), _on_any_entity_died, get_defense_state, get_rig_state,
# _on_phase_entered, _has_leader_now and _line_members.
#   * A formation member (Formation.add_member -> p30_join_formation) has `formation`, `formation_id`
#     (the music director counts formation members as threats) and `formation_slot` (-1: its banner).
#     Its brain holds the slot the formation gives (formation_slot_resolver), faces the giant, and
#     never strikes on its own while the formation is intact: the formation's brace runs through
#     p30_run_action on its striker. While the banner lives the member loses half the morale of awe
#     and ally deaths and regroups to its slot (its leader is the banner: _p30_has_leader); the
#     banner's death is its commander's death (_p30_on_entity_died). Routed members run to the
#     formation's flee points or fan (_p30_rout_point), so a breached gate does not jam. A braced
#     member shows the brace pose (get_rig_state's pose_override).
#   * The banner's record `rally` (role banner) runs every interval_s (Formation._rally_step); when
#     its action strikes, the members within radius_m gain morale (p30_rally).
#   * A shield (guard.breaks_on_tags): a guarded hit carrying one of those tags (heavies, stomps,
#     sweeps) breaks the guard whatever its stamina - accepts_hit() notes every incoming hit for
#     get_defense_state().
#   * Joining: an outmatched soldier (behaviour "formation") outside a formation takes the free slot
#     of the nearest intact formation of its faction within Formation.JOIN_RADIUS_M while the
#     director's formation cap allows (_p30_try_join, asked by the brain); without one, a giant of
#     stage JOIN_OR_FLEE_STAGE or more makes it flee (EnemyBrain), a smaller one leaves it P04's line.
#   * The target provider (record `targets`): _target() is the giant while it is seen (or this unit is
#     aware of it) within aggro_player_m, else the nearest living NPC of the listed factions or intact
#     prop with a listed prop tag within sight range and in sight. The runner makes that NPC or prop
#     hittable during this unit's hit queries (AttackRunner.provider_target: the M1 team rule lets an
#     enemy hit only the player); the perception gives it its own radius and no size (no awe, no
#     outmatched tactics against a house). Without `targets` nothing changes.

## At this stage or more, an outmatched soldier that finds no formation to join flees (plan §5.14:
## at stage 4 single humans flee; smaller giants keep P04's lines).
const JOIN_OR_FLEE_STAGE := 4
## Arm poses (yaw, pitch in degrees: weapon arm, off arm) of a braced member, by role: the pike
## levelled at the giant's legs (the pike lies along the weapon arm), the shield raised, a line's
## blades low. The crowd renderer's brace meshes are built from the same table
## (tools/builders/formations.gd).
const BRACE_POSES := {
	"pike": [Vector2(0.0, -8.0), Vector2(-14.0, -20.0)],
	"shield": [Vector2(18.0, -35.0), Vector2(4.0, 6.0)],
	"line": [Vector2(-8.0, -24.0), Vector2(-12.0, -70.0)],
}

## The formation this unit belongs to (null when none), its id ("" = none: the music director's
## test) and its slot (Formation.BANNER_SLOT for the banner, -2 when none).
var formation: Formation = null
var formation_id := ""
var formation_slot := -2
## The last formation it belonged to (its flee points serve a rout after the formation dissolved).
var _p30_last_formation: Formation = null
var _p30_incoming: HitEvent = null
var _p30_target_tick := -1
var _p30_target_ref: WeakRef = null
var _p30_extents := {}   # entity id -> Vector3 (half extents of its hurtboxes in its own frame)
## M7 gate: the band a running band_pulse strikes, taken when its windup began - the band its
## telegraph shows ({"instance": the action's instance id, "band": the band}; {} when none).
var _p30_frozen_band := {}
## M7 gate: the rout point's last try found nowhere reachable, so the flee resolver fell back to P04's
## flight; while that search resumes for the budget (search_resuming("flee")) the rout point is not
## tried again - it would spend the tick's share before the flight's next candidate every time.
var _p30_rout_failed := false


func _p30_ready() -> void:
	if brain == null:
		return
	brain.formation_slot_resolver = _p30_slot_point
	brain.formation_face_resolver = _p30_face_point
	brain.formation_joiner = _p30_try_join
	var p04_flee := brain.flee_resolver
	brain.flee_resolver = func(from: Vector3, threat: Vector3, distance: float) -> Vector3:
		if not (_p30_rout_failed and search_resuming("flee")):   # M7 gate: see _p30_rout_failed
			var p := _p30_rout_point(from, threat)
			if p != Vector3.INF or brain.nav_search_pending:
				return p   # M7 gate: a rout point waiting for the budget is asked for again next decision
		return p04_flee.call(from, threat, distance) if p04_flee.is_valid() else Vector3.INF
	brain.routed.connect(_p30_on_routed)
	var rally: Variant = record.get("rally")
	if typeof(rally) == TYPE_DICTIONARY:
		_p30_add_action(str(rally.get("action", "")))
	if _p30_has_targets():
		runner.provider_target = _p30_provider_target


func _p30_add_action(action_id: String) -> void:
	var a := GameData.get_action(action_id)
	if a != null and controller != null and not controller.library.has(a.id):
		controller.add_action(a)


## The record's role ("" = none).
func role() -> String:
	return str(record.get("role", ""))


# ---- formation membership (Formation calls these)

## `f` takes this unit into `slot` (Formation.BANNER_SLOT: its banner). `fresh`: it joins as it
## spawns (its morale becomes the formation's morale_start); a soldier joining mid-fight keeps its
## morale (it rises to morale_start as it recovers).
func p30_join_formation(f: Formation, slot: int, fresh := true) -> void:
	formation = f
	formation_id = f.id
	formation_slot = slot
	_p30_last_formation = f
	_release_formation_marker()
	if f.brace_action != "":
		_p30_add_action(f.brace_action)
	if brain == null:
		return
	brain.join_formation(f.id, slot == Formation.BANNER_SLOT, f.morale_start, fresh, Sim.tick)
	p30_formation_update(f)


## `f` lets this unit go (its encounter deactivated, or it left for good).
func p30_leave_formation(f: Formation) -> void:
	if formation != f:
		return
	formation = null
	formation_id = ""
	formation_slot = -2
	if brain != null:
		brain.leave_formation()


## Every formation update: what the brain needs to know (intact, braced, the banner alive).
func p30_formation_update(f: Formation) -> void:
	if brain == null or formation != f:
		return
	brain.formation_hold = f.is_intact()
	brain.formation_braced = f.state == "braced"
	brain.banner_alive = f.banner_alive()


## Starts `action_id` now (the formation's brace on its striker, the banner's rally): true when the
## controller took it.
func p30_run_action(action_id: String) -> bool:
	if controller == null or entity == null or not entity.is_alive() or not controller.library.has(action_id):
		return false
	if controller.state != CombatController.State.LOCOMOTION:
		return false
	controller.request(&"attack", {"action_id": action_id})
	return controller.action != null and controller.action.id == action_id


## True when this unit can start a formation action now: alive, free (locomotion), awake (AI LOD
## tier below 2), not held, not walking home.
func p30_can_act() -> bool:
	return entity != null and entity.is_alive() and controller != null \
		and controller.state == CombatController.State.LOCOMOTION and not is_held() and lod_tier < 2 \
		and not is_returning() and process_mode != Node.PROCESS_MODE_DISABLED and is_inside_tree()


## The band a band_pulse of this unit strikes (AttackRunner): the band its telegraph showed when the
## running action's windup began (M7 gate: the brace's tracking_fraction is 0 - the band no longer
## turns and walks with the formation between the telegraph and the strike, so a giant that steps
## out of the drawn band is not struck); else its formation's front band, else a band in front of
## the unit as wide as three files and as deep as the running action's radius.
func p30_brace_band() -> Dictionary:
	if not _p30_frozen_band.is_empty() and controller != null and controller.action != null \
			and controller.instance_id == int(_p30_frozen_band.instance):
		return _p30_frozen_band.band
	return _p30_live_band()


## The band as the formation (or this unit) stands now (p30_brace_band without the freeze).
func _p30_live_band() -> Dictionary:
	if formation != null:
		return formation.front_band()
	var depth := 6.0
	if controller != null and controller.action != null and controller.action.radius_m > 0.0:
		depth = controller.action.radius_m
	var fwd := Formation.forward_of(facing_yaw)
	return {"center": global_position + fwd * (depth * 0.5), "near": global_position, "half_width": 2.4,
		"depth": depth, "yaw": facing_yaw}


## The height a band_pulse of this unit strikes as (poise and knockback): its formation's
## brace_height_m, else Formation.DEFAULT_BRACE_HEIGHT_M.
func p30_brace_height() -> float:
	return formation.brace_height_m if formation != null else Formation.DEFAULT_BRACE_HEIGHT_M


## The banner's rally strikes: +morale to the members of its formation within the radius (record
## `rally`). Returns how many it reached.
func p30_rally() -> int:
	var rally: Variant = record.get("rally")
	if formation == null or typeof(rally) != TYPE_DICTIONARY:
		return 0
	var n := formation.rally(global_position, float(rally.get("morale", 10.0)), float(rally.get("radius_m", 15.0)))
	Events.ability_effect.emit(Sim.tick, entity.entity_id, str(rally.get("action", "")), "cast",
		global_position, float(rally.get("radius_m", 15.0)), facing_yaw, 0.0)
	return n


## Routs now (tests, scripted events): flight, then the rout, to the formation's flee points.
func p30_force_rout() -> void:
	if brain == null or entity == null or not entity.is_alive():
		return
	Sim.release_all_tokens(entity.entity_id)
	brain.force_rout(Sim.tick)


func _p30_slot_point() -> Vector3:
	return formation.slot_position(formation_slot) if formation != null else Vector3.INF


## What a member faces: the threat while the formation knows it, else straight ahead of its slot.
func _p30_face_point() -> Vector3:
	if formation == null:
		return Vector3.INF
	if formation.threat_pos != Vector3.INF:
		return formation.threat_pos
	return formation.slot_position(formation_slot) + Formation.forward_of(formation.facing_yaw) * 10.0


## A formation member's leader is its banner (the banner leads itself). Its formation must have one.
func _p30_has_leader() -> bool:
	if formation_slot == Formation.BANNER_SLOT:
		return entity.is_alive()
	return formation.banner_alive()


## Events.entity_died: this member's banner fell - its commander's death (-25, x1.5 while
## outmatched, debounced like P04's). True when handled (the base adds no ally death on top).
func _p30_on_entity_died(tick: int, id: String) -> bool:
	if formation == null or formation.banner_id == "" or id != formation.banner_id \
			or formation_slot == Formation.BANNER_SLOT or brain == null:
		return false
	brain.on_commander_died(tick)
	return true


## The nearest intact formation of this unit's faction within JOIN_RADIUS_M with a free slot takes
## it, while the level's director allows another formation member (brain.formation_joiner).
func _p30_try_join() -> bool:
	if formation != null:
		return true
	if entity == null or not entity.is_alive() or not is_inside_tree():
		return false
	var director := get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector
	if director != null and not director.p30_formation_room():
		return false
	var best: Formation = null
	var best_d := Formation.JOIN_RADIUS_M
	for f in Formation.live():
		if not f.is_intact() or f.faction != faction or f.free_slots().is_empty():
			continue
		var d := _flat_len(f.anchor() - global_position)
		if d <= best_d:
			best = f
			best_d = d
	return best != null and best.try_join(self)


## brain.routed: a member of a formation runs to its formation's flee point (or fan).
func _p30_on_routed() -> void:
	if brain == null:
		return
	var p := _p30_rout_point(global_position, brain.last_known)
	if p != Vector3.INF:
		brain.flee_point = p


## Where a routed member of a formation runs (brain.flee_resolver while routed): the formation's
## flee point or fan point of its slot (Formation.rout_point), made reachable on its navigation
## layer. Vector3.INF for anyone else (P04's flight applies).
func _p30_rout_point(from: Vector3, threat: Vector3) -> Vector3:
	_p30_rout_failed = false
	var f := formation if formation != null else _p30_last_formation
	if f == null or brain == null or brain.state != EnemyBrain.AIState.ROUTED:
		return Vector3.INF
	var index := formation_slot if formation_slot >= 0 else absi(hash(entity.entity_id))
	var p := f.rout_point(from, threat, index)
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	if NavQuery.has_navigation(level, layers):
		if not _search_affords():   # M7 gate: within the tick's path-query budget (P24b section)
			_search_stop("rout", 0)
			return Vector3.INF
		var q0 := NavQuery.queries_total
		var r := _reachable_point(level, from, NavQuery.closest_point(level, p, layers), layers)
		_search_spend(q0)
		_p30_rout_failed = r == Vector3.INF
		return r
	return Vector3(p.x, from.y, p.z)


# ---- the brace's telegraph, the rally, the pose

## controller.phase_entered: a band_pulse's windup announces one telegraph along the band (a line
## telegraph from the front rank's centre, as wide as the rank, as deep as the band) instead of
## the base's at the striker (returns true), and keeps that band for the strike (p30_brace_band);
## a rally action's strike rallies.
func _p30_on_phase_entered(action: ActionDef, phase: int, instance_id: int = -1) -> bool:
	if action == null:
		return false
	if action.hit_shape == "band_pulse":
		if phase == ActionDef.Phase.WINDUP:
			var band := _p30_live_band()
			_p30_frozen_band = {"instance": instance_id if instance_id >= 0 else controller.instance_id,
				"band": band.duplicate()}
			Events.telegraph_started.emit(Sim.tick, entity.entity_id, action.id, brain.target_id if brain != null else "",
				"line", band.near, float(band.yaw), float(band.half_width), float(band.depth),
				float(action.windup_ticks) / Sim.TICK_RATE)
		return true
	var rally: Variant = record.get("rally")
	if phase == ActionDef.Phase.ACTIVE and typeof(rally) == TYPE_DICTIONARY and action.id == str(rally.get("action", "")):
		p30_rally()
	return false


## get_rig_state: a member of an intact formation that is braced (or running the brace) shows its
## role's brace pose.
func _p30_rig_state(s: Dictionary) -> Dictionary:
	if formation == null or formation_slot == Formation.BANNER_SLOT or not formation.is_intact():
		return s
	if bool(s.get("dead", false)) or bool(s.get("staggered", false)):
		return s
	var a := controller.action if controller != null else null
	if (a == null and formation.state == "braced") or (a != null and a.hit_shape == "band_pulse"):
		var pose: Variant = BRACE_POSES.get(role() if BRACE_POSES.has(role()) else "line")
		s["pose_override"] = {"arm": pose[0], "off": pose[1], "exact": false}
	return s


# ---- shields

## CombatEntity.receive_hit asks before resolving: every hit is accepted; the shield rule reads it
## (receive_hit builds the defence state right after this, in the same call).
func accepts_hit(hit: HitEvent) -> bool:
	if not _p34_accepts(hit):
		return false   # P34: a yielded boss is IMMUNE to all but the confirmed strike
	_p30_incoming = hit
	return true


## get_defense_state: a guarded hit that carries one of guard.breaks_on_tags breaks the guard (the
## defence's stamina is 0 for it, so any impact is a guard break). The hit is used once.
func _p30_defense(d: DefenseState) -> void:
	var hit := _p30_incoming
	_p30_incoming = null
	var tags: Variant = (record.get("guard", {}) as Dictionary).get("breaks_on_tags")
	if hit == null or not d.blocking or typeof(tags) != TYPE_ARRAY:
		return
	for tag: Variant in tags:
		if hit.has_tag(str(tag)):
			d.stamina = 0.0
			return


# ---- the target provider

func _p30_has_targets() -> bool:
	return typeof(record.get("targets")) == TYPE_DICTIONARY


## The provider's choice this tick (see the section notes; once per tick). A changed choice gives
## back the attack tokens held on the old one.
func _p30_target() -> CombatEntity:
	var cached: CombatEntity = _p30_target_ref.get_ref() as CombatEntity if _p30_target_ref != null else null
	if _p30_target_tick == Sim.tick and cached != null and is_instance_valid(cached):
		return cached
	_p30_target_tick = Sim.tick
	var t: Dictionary = record.targets
	var teams: Array = t.get("teams", ["player"])
	var player: CombatEntity = null
	if teams.has("player"):
		for e: CombatEntity in Sim.entities():
			if e.team == CombatEntity.Team.PLAYER:
				player = e
				break
	var pick: CombatEntity = null
	if player != null and player.is_alive() and _p30_player_engaged(player, t):
		pick = player
	else:
		pick = _p30_nearest_target(t)
		if pick == null:
			pick = player
	if pick != cached and cached != null and entity != null:
		Sim.release_all_tokens(entity.entity_id)
		if brain != null:
			brain.holds_token = false
	_p30_target_ref = weakref(pick) if pick != null else null
	return pick


## True when the giant comes first: within aggro_player_m (when set) and either this unit is aware
## of it or sees it now (sight range, its view cone or the aware radius, a clear line).
func _p30_player_engaged(player: CombatEntity, t: Dictionary) -> bool:
	var to := player.actor.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if t.has("aggro_player_m") and dist > float(t.aggro_player_m):
		return false
	if brain != null and brain.aware and brain.target_id == player.entity_id:
		return true
	var ai: Dictionary = record.get("ai", {})
	if dist > float(ai.get("sight_range_m", 25.0)):
		return false
	var fwd := -global_transform.basis.z
	var facing_deg := rad_to_deg(Vector3(fwd.x, 0.0, fwd.z).signed_angle_to(to, Vector3.UP)) if dist > 0.01 else 0.0
	if absf(facing_deg) > float(ai.get("sight_half_angle_deg", 75.0)) \
			and dist > float(ai.get("awareness_radius_m", AWARE_ALL_AROUND_M)):
		return false
	var eye := global_position + Vector3.UP * entity.combatant.height_m * 0.92
	return HitQueryAdapter.line_clear(get_world_3d().direct_space_state, eye, player.anchor_position(), SIGHT_MASK,
		player.occlusion_rids)


## The nearest living NPC of the record's factions or intact prop with one of its prop_tags,
## within sight range and in sight; null when none.
func _p30_nearest_target(t: Dictionary) -> CombatEntity:
	var range_m := float((record.get("ai", {}) as Dictionary).get("sight_range_m", 25.0))
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * entity.combatant.height_m * 0.92
	var best: CombatEntity = null
	var best_d := range_m
	for e: CombatEntity in Sim.entities():
		if e == entity or e.team != CombatEntity.Team.NEUTRAL or not e.is_alive() or not is_instance_valid(e.actor):
			continue
		if not _p30_allowed(e, t):
			continue
		var d := _flat_len(e.actor.global_position - global_position)
		if d > best_d:
			continue
		if not HitQueryAdapter.line_clear(space, eye, e.anchor_position(), SIGHT_MASK, e.occlusion_rids):
			continue
		best = e
		best_d = d
	return best


## True when `e` (a NEUTRAL entity) is one the record's targets name: a member of a listed faction
## (record ids "faction.<short>"; members carry the short name) or a prop with a listed tag.
func _p30_allowed(e: CombatEntity, t: Dictionary) -> bool:
	if e.faction != "":
		for f: Variant in t.get("factions", []):
			if str(f).trim_prefix("faction.") == e.faction:
				return true
		return false
	var tags := FactionState.prop_tags(e)
	for tag: Variant in t.get("prop_tags", []):
		if tags.has(str(tag)):
			return true
	return false


## AttackRunner.provider_target: the NPC or prop this unit fights now (its brain's target when the
## provider allows it), else null.
func _p30_provider_target() -> CombatEntity:
	if brain == null or brain.target_id == "" or not _p30_has_targets():
		return null
	var e := Sim.get_entity(brain.target_id)
	if e == null or e.team != CombatEntity.Team.NEUTRAL or not e.is_alive():
		return null
	return e if _p30_allowed(e, record.targets) else null


## _sense: a target that is not the giant gets its own radius toward this unit and no size (the
## brain's awe and outmatched tactics are for giants).
func _p30_sense(snapshot: Dictionary, t: CombatEntity) -> void:
	if t == null or t.team == CombatEntity.Team.PLAYER:
		return
	snapshot["target_radius"] = _p30_target_radius(t)
	snapshot["target_height"] = float(record.get("height_m", 1.8))
	snapshot["target_stage"] = 0


## How far from `t`'s origin its edge lies toward this unit: an actor's capsule radius; a prop's
## hurtbox box (in its own frame) along the direction to this unit.
func _p30_target_radius(t: CombatEntity) -> float:
	var rec := GameData.get_record(t.definition_id)
	if str(rec.get("type", "")) != "prop":
		return float(rec.get("capsule_radius_m", 0.4))
	var half: Vector3 = _p30_extents.get(t.entity_id, Vector3.INF)
	if half == Vector3.INF:
		half = _p30_half_extents(t)
		_p30_extents[t.entity_id] = half
	var local := t.actor.global_transform.basis.inverse() * (global_position - t.actor.global_position)
	var d := Vector2(local.x, local.z)
	if d.length() < 1e-3:
		return maxf(half.x, half.z)
	d = d.normalized()
	var rx := half.x / absf(d.x) if absf(d.x) > 1e-4 else INF
	var rz := half.z / absf(d.y) if absf(d.y) > 1e-4 else INF
	return clampf(minf(rx, rz), 0.2, 30.0)


## Half extents (x, y, z in the prop's own frame) of the union of `t`'s hurtbox shapes, about its
## origin (0.5 m each way without any).
static func _p30_half_extents(t: CombatEntity) -> Vector3:
	var box := AABB()
	var first := true
	var inv := t.actor.global_transform.affine_inverse()
	for hb in t.hurtboxes:
		if not is_instance_valid(hb):
			continue
		for child in hb.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var aabb := cs.shape.get_debug_mesh().get_aabb()
			var xf := inv * cs.global_transform
			var local := xf * aabb
			box = local if first else box.merge(local)
			first = false
	if first:
		return Vector3(0.5, 0.5, 0.5)
	var far := Vector3(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.y), absf(box.end.y)),
		maxf(absf(box.position.z), absf(box.end.z)))
	return far

## @anchor P32
# --- siege crews: a place beside an engine, the haul, the engine's loss (P32) ---------------------
# Plan M6-M9 §2.10, §3.16, §5.11. An encounter's `engines` list gives a crew member its engine
# (EncounterDirector -> SiegeEngine.add_crew -> p32_assign_engine). The brain (EnemyBrain's P32
# section) then holds the member's place beside the engine (crew_slot_resolver: SiegeEngine.crew_slot,
# inside its crew radius), facing the giant while it knows where it is, else the engine's front
# (crew_face_resolver), and never fights. While the engine reloads it asks one member at a time to haul
# (p32_crew_reload: the record's crew action, a pose without a hit). engine_id names the engine: the
# music director counts an engine crew as a threat whatever its height (MusicDirector.is_special). When
# the engine breaks, a giant seizes it or it leaves the tree, the member gives up its place, runs and
# routs (p32_engine_lost; the brain notices a vanished engine itself through crew_engine_check).

## The world id of the engine this crew member serves ("" = none).
var engine_id := ""
var _p32_engine_ref: WeakRef = null


## SiegeEngine.add_crew: `engine` takes this unit into its crew.
func p32_assign_engine(engine: Node) -> void:
	if engine == null or not is_instance_valid(engine):
		return
	_p32_engine_ref = weakref(engine)
	engine_id = str(engine.call("engine_id")) if engine.has_method("engine_id") else ""
	if brain == null:
		return
	brain.crew_slot_resolver = _p32_crew_slot
	brain.crew_face_resolver = _p32_crew_face
	brain.crew_engine_check = func() -> bool: return p32_engine() != null
	brain.crew_engine_assigned(Sim.tick)


## The engine this unit serves (null when none, or once it was freed or left the tree).
func p32_engine() -> Node3D:
	var e: Node3D = _p32_engine_ref.get_ref() as Node3D if _p32_engine_ref != null else null
	return e if e != null and e.is_inside_tree() else null


## `engine` broke or a giant seized it (SiegeEngine), or (null) it vanished: this unit gives up its
## place, runs and routs. Another engine's loss is ignored.
func p32_engine_lost(engine: Node = null) -> void:
	var mine: Object = _p32_engine_ref.get_ref() if _p32_engine_ref != null else null
	if engine != null and mine != null and mine != engine:
		return
	_p32_engine_ref = null
	engine_id = ""
	if brain == null or entity == null or not entity.is_alive():
		return
	Sim.release_all_tokens(entity.entity_id)
	if brain.crew_serving or not brain.crew_lost:
		brain.crew_engine_lost(Sim.tick)


## SiegeEngine's haul: this member runs its crew action (ability.crew_reload: a pose, no hit) when it
## stands free at its place. True when it started.
func p32_crew_reload() -> bool:
	var id := _p32_crew_action()
	if id == "" or brain == null or not brain.crew_at_slot(global_position) or not p30_can_act():
		return false
	controller.request(&"attack", {"action_id": id})
	return controller.action != null and controller.action.id == id


## The record's crew action (its first attack), "" when it has none.
func _p32_crew_action() -> String:
	var attacks: Array = record.get("attacks", [])
	return str(attacks[0]) if not attacks.is_empty() else ""


func _p32_crew_slot() -> Vector3:
	var e := p32_engine()
	return e.call("crew_slot", self) if e != null and e.has_method("crew_slot") else Vector3.INF


## Where a crew member looks while it does not know where the giant is: 10 m before its engine.
func _p32_crew_face() -> Vector3:
	var e := p32_engine()
	if e == null:
		return Vector3.INF
	var fwd := -e.global_transform.basis.z
	fwd.y = 0.0
	return e.global_position + (fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD) * 10.0

## @anchor P34
# --- the larger creatures and the bosses: regeneration and fire, the yield protocol, lobbed throws,
# --- attempts (P34) --------------------------------------------------------------------------------
# Plan M6-M9 §2.10, §5.13. The hooks outside this section are one line each: _ready() calls
# _p34_ready(); _on_phase_entered() asks _p34_on_phase_entered() first; accepts_hit() asks
# _p34_accepts() first; max_ranged_windup_ticks() skips _p34_own_launch() records.
#
# Regeneration (record.regeneration; TrollEnemy calls p34_regen_step() every tick): every interval_s a
# living, hurt troll that carries no status tagged one of blocked_by_tags (default Burning) heals
# hp_per_s x interval_s (phase_hp_per_s by its boss phase) through CombatEntity.heal and refreshes its
# marker status (status.troll_regen, tag Regeneration: the cue router's wet regrowth, the green pulse
# TrollEnemy paints). Burning stops both; the marker runs out 1.5 s later. Fire: a prop tagged "fire"
# (a brazier) broken within brazier_radius_m sets Burning for brazier_burn_s.
#
# The yield protocol (record.yield_at: Corvane, Harrok; §2.10). While a yield is armed the boss is
# unkillable and every hit that takes its health to health_frac or below is held at that floor and
# makes it yield ("health"); poise_breaks (or challenge_poise_breaks while challenge_conditions hold,
# Wildheart's challenge) poise breaks make it yield too ("honour"); BattleBoss yields Corvane when his
# guard breaks. p34_yield(): at once IMMUNE (accepts_hit refuses every hit, so whatever was swung,
# thrown, pulsed or set burning before it lands on nothing) and non-hostile (AI off, the running action
# cancelled, tokens back, its own projectiles and hazards discarded, not lockable, the player's lock on
# it released); Events.boss_yielded(boss id) and the yield prompt (the dialogue of yield_at in
# ScreenStack "yield", reopened while undecided). Only the prompt's outcome decides
# (Events.dialogue_outcome, or p34_decide() for the bot and tests): "spare" leaves it kneeling, immune,
# for good (outcome flag "spared"); "strike" (a confirm node first) either queues one killing blow from
# the giant - the only hit it accepts (on_strike "kill") - or lets it rise to fight to the death
# without a second yield (on_strike "fight"). Any death of a record with boss_outcome writes "slain"
# (first write wins: a spared or fled boss keeps its outcome).
#
# Lobbed throws (an action with `indirect`: the rival giants' boulders): when the windup begins the
# landing point is committed at the target's feet - the runner aims there and the circle telegraph is
# announced there (P32's landing circle and P28's incoming whistle follow it).
#
# Attempts (§2.10 the disengage rule): p34_reset_attempt() (BossArena, BattleBoss) starts a new attempt
# - the first phase again (each phase happens once per attempt: attempt_phases), full health, no
# statuses, no poise breaks, the archetype's own reset (_p34_reset_extra) - and walks the boss home.

## Archetypes whose projectile attacks are lobs, not volleys: they never set the launch gap of the
## archers and mages (max_ranged_windup_ticks; the troll's whelp and the giants' boulders are slower).
const P34_OWN_LAUNCH_ARCHETYPES := ["troll", "rival_giant"]
const P34_YIELD_HOOK_ORDER := 125
## An undecided yield's prompt opens again this long after it closed.
const P34_PROMPT_RETRY_S := 1.0
## The strike's power (it always kills: armour and resistances cannot save it).
const P34_STRIKE_POWER := 1.0e7
const P34_BURNING := "status.burning"

## Regeneration heals given and the health they restored (tests, debug).
var regen_heals := 0
var regen_healed := 0.0
## Poise breaks taken in this attempt (Harrok's honour and his second phase).
var poise_breaks := 0
## The yield protocol: true from p34_yield() on (a spared boss stays yielded).
var yielded := false
var yield_tick := -1
var yield_reason := ""
## "" until the prompt decides: "spare" | "strike".
var yield_decided := ""
## True once a boss stood down with its battle (BattleBoss): immune and still, like a spared one.
var stood_down := false
## The attempt this boss fights (1 at spawn; p34_reset_attempt starts the next).
var attempt := 1
## The boss phases (1-based) entered in this attempt, in order.
var attempt_phases: Array[int] = []
var _p34_regen: Dictionary = {}
var _p34_yield: Dictionary = {}
var _p34_regen_next := 0
var _p34_fight_to_death := false
var _p34_strike_instance := -1
var _p34_prompt_tick := -1
var _p34_ai_before := true
var _p34_hook_owner: RefCounted = null
var _p34_phase_due := -1


func _p34_ready() -> void:
	var regen: Variant = record.get("regeneration")
	_p34_regen = regen if typeof(regen) == TYPE_DICTIONARY else {}
	var y: Variant = record.get("yield_at")
	_p34_yield = y if typeof(y) == TYPE_DICTIONARY else {}
	var outcome := typeof(record.get("boss_outcome")) == TYPE_DICTIONARY
	if outcome and not is_in_group("bosses"):
		add_to_group("bosses")
	if not _p34_yield.is_empty() or _p34_poise_phases():
		entity.hit_taken.connect(_p34_on_hit_taken)
	if outcome:
		entity.died.connect(_p34_on_died)
	if not _p34_yield.is_empty():
		entity.combatant.unkillable = true   # the floor: _p34_on_hit_taken holds health there
		Events.dialogue_outcome.connect(_p34_on_dialogue_outcome)
		_p34_hook_owner = RefCounted.new()
		Sim.add_hook(Sim.Hook.POST_RESOLVE, _p34_hook_owner, _p34_yield_step, P34_YIELD_HOOK_ORDER)
	if float(_p34_regen.get("brazier_radius_m", 0.0)) > 0.0:
		Events.object_destroyed.connect(_p34_on_object_destroyed)
	if brain != null:
		brain.boss_phase_entered.connect(_p34_on_boss_phase)


## True for a record whose projectile attacks must not set the launch gap (P34_OWN_LAUNCH_ARCHETYPES).
static func _p34_own_launch(rec: Dictionary) -> bool:
	return P34_OWN_LAUNCH_ARCHETYPES.has(str(rec.get("archetype", "")))


## The boss id of this actor's yield and outcome (yield_at.boss_id, else its entity id).
func yield_boss_id() -> String:
	var id := str(_p34_yield.get("boss_id", ""))
	return id if id != "" else entity.entity_id


func _p34_poise_phases() -> bool:
	var boss: Variant = record.get("boss")
	if typeof(boss) != TYPE_DICTIONARY:
		return false
	for ph: Variant in boss.get("phases", []):
		if typeof(ph) == TYPE_DICTIONARY and int(ph.get("enter_on_poise_breaks", 0)) > 0:
			return true
	return false


func _p34_on_boss_phase(phase: int, _phase_id: String, _enter_action: String) -> void:
	attempt_phases.append(phase)


# ---- regeneration and fire

## One regeneration step (TrollEnemy, every tick; it acts every interval_s).
func p34_regen_step(tick: int) -> void:
	if _p34_regen.is_empty() or entity == null or not entity.is_alive() or tick < _p34_regen_next:
		return
	var interval := maxi(1, ActionDef.seconds_to_ticks(float(_p34_regen.get("interval_s", 1.0))))
	_p34_regen_next = tick + interval
	var pools := entity.combatant.pools
	if p34_regen_blocked() or pools.health >= pools.health_max - 1e-3:
		return
	var before := pools.health
	entity.heal(p34_regen_rate() * float(interval) / float(Sim.TICK_RATE), "regeneration")
	regen_heals += 1
	regen_healed += pools.health - before
	entity.apply_status(str(_p34_regen.get("status", "")), NAN, -1.0, entity.entity_id)


## True while a status tagged one of regeneration.blocked_by_tags (Burning) stops the regeneration.
func p34_regen_blocked() -> bool:
	for tag: Variant in _p34_regen.get("blocked_by_tags", ["Burning"]):
		if p34_has_status_tag(str(tag)):
			return true
	return false


## Health per second now: phase_hp_per_s of the current boss phase, else hp_per_s (0 without).
func p34_regen_rate() -> float:
	var by_phase: Variant = _p34_regen.get("phase_hp_per_s")
	if typeof(by_phase) == TYPE_DICTIONARY and brain != null and brain.has_boss_phases():
		var key := str(brain.boss_phase())
		if (by_phase as Dictionary).has(key):
			return float(by_phase[key])
	return float(_p34_regen.get("hp_per_s", 0.0))


## True while the regeneration's marker status (tag Regeneration) is on.
func p34_regenerating() -> bool:
	return not _p34_regen.is_empty() and entity != null \
		and entity.combatant.statuses.has(str(_p34_regen.get("status", "")))


## True while a status with `tag` is active.
func p34_has_status_tag(tag: String) -> bool:
	if entity == null or entity.combatant == null:
		return false
	for id: String in entity.combatant.statuses.active_ids():
		var def := GameData.get_status(id)
		if def != null and def.has_tag(tag):
			return true
	return false


## Sets Burning for `seconds` (fire from a brazier, the pit or a burning body).
func p34_ignite(seconds: float, source_id: String = "") -> bool:
	if entity == null or not entity.is_alive():
		return false
	return entity.apply_status(P34_BURNING, NAN, seconds, source_id)


## A prop tagged "fire" broken within brazier_radius_m sets Burning (brazier_burn_s).
func _p34_on_object_destroyed(_tick: int, world_id: String, killer_id: String) -> void:
	if not is_inside_tree() or entity == null or not entity.is_alive():
		return
	for n in get_tree().get_nodes_in_group("breakables"):
		if not (n is Node3D) or str(n.get("world_id")) != world_id:
			continue
		var rec: Variant = n.get("record")
		var tags: Array = (rec as Dictionary).get("prop_tags", []) if typeof(rec) == TYPE_DICTIONARY else []
		var reach := float(_p34_regen.get("brazier_radius_m", 0.0))
		if tags.has("fire") and (n as Node3D).global_position.distance_to(global_position) <= reach + 1e-3:
			p34_ignite(float(_p34_regen.get("brazier_burn_s", 8.0)), killer_id)
		return


# ---- the yield protocol

func _p34_on_hit_taken(result: HitResult) -> void:
	if entity == null or not entity.is_alive():
		return
	if result.poise_broken and not yielded:
		poise_breaks += 1
		_p34_check_poise_phase()
	if _p34_yield.is_empty() or yielded or _p34_fight_to_death:
		return
	var pools := entity.combatant.pools
	var floor_hp := pools.health_max * float(_p34_yield.get("health_frac", 0.0))
	if floor_hp > 0.0 and pools.health <= floor_hp + 1e-6:
		pools.health = maxf(pools.health, floor_hp)
		p34_yield("health")
		return
	var need := p34_yield_poise_breaks()
	if need > 0 and poise_breaks >= need:
		p34_yield("honour")


## Poise breaks that make this boss yield now (0 = none): challenge_poise_breaks while every
## challenge condition holds (Wildheart's challenge), else poise_breaks.
func p34_yield_poise_breaks() -> int:
	var need := int(_p34_yield.get("poise_breaks", 0))
	var conds: Variant = _p34_yield.get("challenge_conditions")
	if typeof(conds) == TYPE_ARRAY and not (conds as Array).is_empty() \
			and int(_p34_yield.get("challenge_poise_breaks", 0)) > 0 \
			and QuestConditions.all_hold(conds, Quests.condition_context()):
		need = int(_p34_yield.challenge_poise_breaks)
	return need


## A later phase with enter_on_poise_breaks begins once that many breaks were taken - at the next step
## the boss is not staggered (TrollEnemy / RivalGiantEnemy call p34_boss_step), so its roar never
## cuts the stagger short.
func _p34_check_poise_phase() -> void:
	if brain == null or not brain.has_boss_phases():
		return
	for i in range(brain.phase_index + 1, brain.boss_phases.size()):
		var need := int((brain.boss_phases[i] as Dictionary).get("enter_on_poise_breaks", 0))
		if need > 0 and poise_breaks >= need:
			_p34_phase_due = i
			return


## The boss archetypes' per-tick step before their own (phases by poise breaks).
func p34_boss_step(_tick: int) -> void:
	if _p34_phase_due < 0 or brain == null or yielded or not entity.is_alive():
		return
	if controller.state == CombatController.State.STAGGERED or _p34_phase_due <= brain.phase_index:
		if _p34_phase_due <= brain.phase_index:
			_p34_phase_due = -1
		return
	var frac := float((brain.boss_phases[_p34_phase_due] as Dictionary).get("health_frac_below", 0.0))
	_p34_phase_due = -1
	brain.update_boss_phase(frac, Sim.tick)


## Yields now (see the section notes). Nothing happens without yield_at, once yielded, while fighting
## to the death, or dead.
func p34_yield(reason: String) -> void:
	if yielded or _p34_yield.is_empty() or _p34_fight_to_death or entity == null or not entity.is_alive():
		return
	yielded = true
	yield_tick = Sim.tick
	yield_reason = reason
	yield_decided = ""
	_p34_still(true)
	Events.boss_yielded.emit(Sim.tick, yield_boss_id())
	_p34_open_prompt()


## Makes this actor harmless at once: AI off, its action and buffer gone, tokens back, its shots and
## hazards discarded, unlockable, the player's lock on it released (yield, stand-down).
func _p34_still(remember_ai: bool) -> void:
	if remember_ai:
		_p34_ai_before = ai_enabled
	ai_enabled = false
	if controller.action != null:
		controller.call("_finish_action", true)
	controller.buffer.clear()
	if brain != null:
		brain.attack_request = ""
		brain.holds_token = false
		brain.move_target = Vector3.INF
		brain.face_point = Vector3.INF
	move_velocity = Vector3.ZERO
	release_ranged_claims()
	entity.combatant.lockable = false
	_p34_discard_own_shots()
	if brain != null and brain.has_method("p34_clear_hazards"):
		brain.call("p34_clear_hazards")
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	if p != null and p.targeting != null and p.lock.is_locked() and p.lock.target_id == entity.entity_id:
		p.targeting.release_lock("boss_yielded")


## Ends every projectile this actor launched that is still in the air.
func _p34_discard_own_shots() -> void:
	var system := ProjectileSystem.instance(get_tree())
	if system == null:
		return
	for pr: Projectile in system.projectiles():
		if not pr.ended and pr.owner_id == entity.entity_id:
			system.discard(pr.id)


## A battle's surrender (BattleBoss): immune and still for good, like a spared boss.
func p34_stand_down() -> void:
	if stood_down or entity == null or not entity.is_alive():
		return
	stood_down = true
	_p34_still(false)


func _p34_open_prompt() -> void:
	_p34_prompt_tick = Sim.tick
	var dlg := str(_p34_yield.get("dialogue", ""))
	var s := Quests.start_dialogue(dlg, entity.entity_id)
	if s != null:
		Events.ui_screen_requested.emit("yield", {"session": s, "dialogue_id": dlg, "npc_id": entity.entity_id,
			"boss_id": yield_boss_id(), "name": entity.display_name()})


## POST_RESOLVE while yielded: keeps the boss still and reopens an undecided prompt that closed.
func _p34_yield_step(tick: int) -> void:
	if not yielded or not is_inside_tree() or entity == null or not entity.is_alive():
		return
	if ai_enabled:
		ai_enabled = false
	if yield_decided != "":
		return
	var open := Quests.dialogue != null and Quests.dialogue.is_active() \
		and str(Quests.dialogue.dialogue_id) == str(_p34_yield.get("dialogue", ""))
	if open:
		_p34_prompt_tick = tick
	elif tick - _p34_prompt_tick >= ActionDef.seconds_to_ticks(P34_PROMPT_RETRY_S):
		_p34_open_prompt()


func _p34_on_dialogue_outcome(_tick: int, dialogue_id: String, outcome: String) -> void:
	if yielded and yield_decided == "" and dialogue_id == str(_p34_yield.get("dialogue", "")):
		p34_decide(outcome)


## The prompt's decision ("spare" | "strike"); false when it cannot decide now (not yielded, decided,
## or another outcome).
func p34_decide(outcome: String) -> bool:
	if not yielded or yield_decided != "" or not (outcome in ["spare", "strike"]) or not entity.is_alive():
		return false
	yield_decided = outcome
	if outcome == "spare":
		_p34_write_outcome("spared")
	elif str(_p34_yield.get("on_strike", "kill")) == "fight":
		yielded = false
		_p34_fight_to_death = true
		entity.combatant.unkillable = false
		entity.combatant.lockable = true
		ai_enabled = _p34_ai_before
		var p := get_tree().get_first_node_in_group("player") as GiantPlayer
		if p != null and brain != null:
			brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
		# M8 gate (F11): the fight is on again under the id the yield ended it with - the boss bar
		# drops its "yields", the boss music comes back (CueRouter: in the boss's current phase).
		Events.boss_engaged.emit(Sim.tick, yield_boss_id())
	else:
		_p34_strike()
	get_tree().call_group(BossArena.GROUP, "p34_on_yield_decided", entity.entity_id, outcome)
	return true


## The confirmed Strike: one killing blow from the giant, the only hit a yielded boss accepts.
func _p34_strike() -> void:
	entity.combatant.unkillable = false
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = p.entity.entity_id if p != null else ""
	h.target_id = entity.entity_id
	h.action_id = "yield.strike"
	h.power = P34_STRIKE_POWER
	h.attacker_stat = 10.0
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = p.global_position if p != null else global_position - global_transform.basis.z
	_p34_strike_instance = h.instance_id
	Sim.queue_hit(h)


## accepts_hit: a yielded or stood-down actor refuses every hit but the confirmed strike.
func _p34_accepts(hit: HitEvent) -> bool:
	if not yielded and not stood_down:
		return true
	return _p34_strike_instance >= 0 and hit.instance_id == _p34_strike_instance


func _p34_on_died(_killer_id: String) -> void:
	_p34_write_outcome("slain")


## The outcome flag (first write wins) and the defeated flag of record.boss_outcome.
func _p34_write_outcome(value: String) -> void:
	var bo: Variant = record.get("boss_outcome")
	if typeof(bo) != TYPE_DICTIONARY:
		return
	WorldState.try_set_flag(str(bo.get("flag", "")), value)
	if str(bo.get("defeated_flag", "")) != "":
		WorldState.try_set_flag(str(bo.defeated_flag), true)


# ---- lobbed throws

## _on_phase_entered: an indirect action's windup commits its landing point (the runner aims there)
## and announces its circle there. True when it announced the telegraph.
func _p34_on_phase_entered(action: ActionDef, _instance_id: int, phase: int) -> bool:
	if phase != ActionDef.Phase.WINDUP or action == null or not bool(action.param("indirect", false)):
		return false
	var t := Sim.get_entity(brain.target_id) if brain != null and brain.target_id != "" else _target()
	var point := t.actor.global_position if t != null and is_instance_valid(t.actor) \
		else global_position - global_transform.basis.z * 20.0
	runner.aim_point = point
	var tel: Variant = action.param("telegraph")
	var radius := float((tel as Dictionary).get("radius_m", 4.0)) if typeof(tel) == TYPE_DICTIONARY else 4.0
	Events.telegraph_started.emit(Sim.tick, entity.entity_id, action.id, t.entity_id if t != null else "",
		"circle", point, facing_yaw, radius, 0.0, float(action.windup_ticks) / Sim.TICK_RATE)
	return true


# ---- attempts

## A new attempt (the disengage rule): the first phase, full health and poise, no statuses or poise
## breaks, the archetype's own reset, and the walk home. Not while yielded, stood down or dead.
func p34_reset_attempt() -> void:
	if entity == null or not entity.is_alive() or yielded or stood_down:
		return
	attempt += 1
	attempt_phases.clear()
	poise_breaks = 0
	_p34_phase_due = -1
	if controller.action != null:
		controller.call("_finish_action", true)
	controller.buffer.clear()
	if brain != null and brain.has_boss_phases():
		brain.init_boss_phases(record)
	for id: String in entity.combatant.statuses.active_ids():
		entity.combatant.statuses.remove(id)
		Events.status_expired.emit(Sim.tick, entity.entity_id, id)
	var pools := entity.combatant.pools
	entity.heal(pools.health_max - pools.health, "attempt")
	if not entity.combatant.poise.locked:
		entity.combatant.poise.value = 0.0
	_p34_reset_extra()
	begin_leash_return()


## The archetype's own part of a new attempt (summons, hazards, a carried whelp).
func _p34_reset_extra() -> void:
	pass


## A new attempt engaged while the boss still walks home: it stops there and fights (full health).
func p34_stop_return() -> void:
	if is_returning():
		_end_leash_return(true)


## @anchor P37
# --- wanderers and world events: a spawn's own targets, a marching column (P37) ----------------------
# Plan M6-M9 §2.13, decision 27. The EncounterDirector's P37 section calls these on a copy of a template:
#   * p37_set_targets(targets): this unit's target provider (P30) takes `targets` instead of its record's
#     (a raid's raiders burn the settlement's houses and hunt its folk while the giant is not in their way);
#   * p37_join_march(target): this unit walks with a moving column - target() -> {"point", "yaw"} is its
#     place in the column now (its formation slot while its formation stands, else its offset from the
#     column's centre). At peace (a neutral column walking past a giant at peace with its faction) the
#     post it holds is that place, a little ahead of it so it keeps walking with the column instead of
#     stopping and starting at each refresh of its post (EnemyBrain's POST_REFRESH_S); hostile, its
#     formation slot (P30) or the escort's patrol point the director keeps ahead of the column does it.

## How far ahead of its place in a marching column a member at peace makes for (its post is asked for
## again every second; the column marches about a metre a second).
const P37_POST_LEAD_M := 1.5

## target() -> {"point": Vector3, "yaw": float} of this unit's place in a marching column; unset = none.
var p37_march_target := Callable()


## This unit's target provider takes `targets` (the shape of an enemy record's `targets`, P30) from now on.
func p37_set_targets(targets: Dictionary) -> void:
	if targets.is_empty():
		return
	record = record.duplicate()
	record["targets"] = targets.duplicate(true)
	_p30_target_tick = -1
	_p30_target_ref = null
	if runner != null:
		runner.provider_target = _p30_provider_target


## This unit walks with a marching column (see the section notes).
func p37_join_march(target: Callable) -> void:
	p37_march_target = target
	if brain != null:
		brain.post_resolver = _p37_post


## This unit leaves its column: it holds its own post again (P11b).
func p37_leave_march() -> void:
	p37_march_target = Callable()
	if brain != null and faction != "":
		brain.post_resolver = faction_post


## Where this unit keeps to in its column now (Vector3.INF when it walks with none): its formation slot
## while its formation stands, else its place from target().
func p37_march_point() -> Vector3:
	if formation != null and formation.is_intact():
		return formation.slot_position(formation_slot)
	if not p37_march_target.is_valid():
		return Vector3.INF
	var t: Variant = p37_march_target.call()
	return (t as Dictionary).get("point", Vector3.INF) if typeof(t) == TYPE_DICTIONARY else Vector3.INF


## brain.post_resolver while marching: the column's place for this unit, a little ahead, facing the way
## the column goes; its own post (P11b) when the column gives none.
func _p37_post() -> Dictionary:
	var t: Variant = p37_march_target.call() if p37_march_target.is_valid() else null
	var p := p37_march_point()
	if typeof(t) != TYPE_DICTIONARY or not p.is_finite():
		return faction_post()
	var fwd := Formation.forward_of(float((t as Dictionary).get("yaw", 0.0)))
	return {"post": p + fwd * P37_POST_LEAD_M, "face": p + fwd * 10.0}
