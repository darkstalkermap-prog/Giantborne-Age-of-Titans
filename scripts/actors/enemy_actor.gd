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
	_sense_extra(snapshot)
	return snapshot


func _on_any_ability_started(_tick: int, actor_id: String, _action_id: String, _instance: int) -> void:
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
	if id == entity.entity_id or not entity.is_alive():
		return
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
		if flat_dist > DIRECT_STEER_DISTANCE:
			if _wants_repath(goal):
				agent.target_position = goal
				_last_nav_target = goal
				_note_repath()
			if not agent.is_navigation_finished():
				next = agent.get_next_path_position()
			if Vector2(next.x - global_position.x, next.z - global_position.z).length() < 0.05:
				next = goal  # no path data (no navmesh / not synced yet): steer directly
		var dir := next - global_position
		dir.y = 0.0
		if flat_dist > 0.25 and dir.length() > 0.01:
			desired = dir.normalized() * speed * mult
		_track_progress(goal, dt)
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
	return {
		"state": controller.state,
		"action": controller.action,
		"phase": controller.phase(),
		"phase_fraction": controller.phase_fraction(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"dead": controller.state == CombatController.State.DEAD,
		"staggered": controller.state == CombatController.State.STAGGERED,
		"dodging": false,
		"guarding": is_guarding(),
	}


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
	if lod_tier >= 1:
		return _last_nav_target == Vector3.INF and Sim.tick - _last_repath_tick >= TIER1_REPATH_TICKS
	return _last_nav_target == Vector3.INF or _last_nav_target.distance_to(goal) > 0.5


func _note_repath() -> void:
	repath_count += 1
	_last_repath_tick = Sim.tick


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
func _on_phase_entered(action: ActionDef, _instance_id: int, phase: int) -> void:
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
## layer - LevelRoot.nav_region(layer) when the level provides one (P10a), otherwise the map's
## region on that layer - accepted only when a path on the actor's nav layers ends within
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
	var map := get_world_3d().navigation_map
	var region := nav_region_for_layers()
	var use_nav := region.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0
	var layers := int(agent.navigation_layers)
	var space := get_world_3d().direct_space_state
	var threat_dist := _flat_len(from - threat)
	for i in FLEE_MAX_STEPS * 2 + 1:
		var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)   # 0, 1, -1, 2, -2, ...
		var desired := from + away.rotated(Vector3.UP, deg_to_rad(FLEE_STEP_DEG * k)) * distance
		if use_nav:
			var p := _reachable_point(map, from, NavigationServer3D.region_get_closest_point(region, desired), layers)
			if p == Vector3.INF or _flat_len(p - from) < distance * 0.5 or _flat_len(p - threat) <= threat_dist:
				continue   # unreachable, snapped back toward us, or not away from the threat
			return p
		else:
			var lift := Vector3.UP * 0.5
			if HitQueryAdapter.line_clear(space, from + lift, desired + lift, SIGHT_MASK | LAYER_BLOCKER,
					entity.occlusion_rids):
				return Vector3(desired.x, from.y, desired.z)
	return Vector3.INF


## `p` when a path from `from` on `layers` ends within FLEE_PATH_END_M of it; otherwise the end
## of that path when the same check accepts it (p lies beyond a wall or on an unconnected
## island); otherwise Vector3.INF.
static func _reachable_point(map: RID, from: Vector3, p: Vector3, layers: int) -> Vector3:
	var path := NavigationServer3D.map_get_path(map, from, p, true, layers)
	if path.is_empty():
		return Vector3.INF
	var end := path[path.size() - 1]
	if end.distance_to(p) <= FLEE_PATH_END_M:
		return p
	var check := NavigationServer3D.map_get_path(map, from, end, true, layers)
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
				or other.entity.team != entity.team or other.formation_marker() != null):
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
## @anchor P09
## @anchor P10a
## @anchor P11a
## @anchor P11b
