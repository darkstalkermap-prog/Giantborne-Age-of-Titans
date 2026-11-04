class_name EnemyActor
extends CharacterBody3D
## Base of every enemy archetype (plan §2.7.3): a CombatController with the same rules as the
## player, an EnemyBrain (made by _make_brain()), an AttackRunner for its hit queries, and the
## shared glue - perception at the record's rate (5 Hz), decisions (10 Hz), facing with
## tracking limits, NavigationAgent3D movement, hearing, ally deaths and death cleanup.
##
## Archetypes override the virtuals: _make_brain(), _sense_extra(snapshot), _is_guarding()
## and _custom_movement(dt). Required child nodes: CombatEntity, NavAgent; Visual (ActorRig)
## is optional. Group "enemies".

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
	Sim.register_actor(entity.entity_id, self)


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)


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


## Archetype movement override for this tick (lunges, charges). Return true when it set
## move_velocity itself; the base then skips brain steering but still applies knockback,
## gravity and move_and_slide.
func _custom_movement(_dt: float) -> bool:
	return false


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	controller.on_floor = is_on_floor()
	controller.begin_tick(tick)
	var alive := controller.state != CombatController.State.DEAD
	if ai_enabled and alive and (tick + _phase_offset) % perception_interval == 0:
		brain.perceive(tick, _sense())
	if ai_enabled and ((tick + _phase_offset) % decision_interval == 0 or not alive):
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
	return Sim.request_token(brain.target_id, entity.entity_id,
		int(record.get("ai", {}).get("max_attackers", 2)))


func _release_token() -> void:
	Sim.release_token(brain.target_id, entity.entity_id)


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
		var empty := {"exists": false, "self_health_frac": entity.combatant.pools.ratio("health")}
		_sense_extra(empty)
		return empty
	var ai: Dictionary = record.get("ai", {})
	var to := t.actor.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := -global_transform.basis.z
	var facing_deg := rad_to_deg(Vector3(fwd.x, 0.0, fwd.z).signed_angle_to(to, Vector3.UP)) if dist > 0.01 else 0.0
	var in_cone := absf(facing_deg) <= float(ai.get("sight_half_angle_deg", 75.0)) \
		or (brain.aware and dist <= AWARE_ALL_AROUND_M)
	var visible := false
	if dist <= float(ai.get("sight_range_m", 25.0)) and in_cone:
		var eye := global_position + Vector3.UP * entity.combatant.height_m * 0.92
		visible = HitQueryAdapter.line_clear(get_world_3d().direct_space_state, eye,
			t.anchor_position(), HitQueryAdapter.LAYER_WORLD, t.occlusion_rids)
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
		"self_health_frac": entity.combatant.pools.ratio("health")}
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


func _on_any_entity_died(_tick: int, id: String, _killer: String) -> void:
	if id == entity.entity_id:
		return
	var other := Sim.get_entity(id)
	if other != null and other.team == entity.team \
			and other.actor.global_position.distance_to(global_position) < ALLY_DEATH_RADIUS_M:
		brain.on_ally_died()


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
			if _last_nav_target == Vector3.INF or _last_nav_target.distance_to(goal) > 0.5:
				agent.target_position = goal
				_last_nav_target = goal
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
	}


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5): P04 motion,
# LOD tiers, morale and rout, sight mask, nav layers; P07 grab hooks; P09 aim point and ranged
# tactics; P10a leash return; P11a boss hooks; P11b factions and stand-down.

## @anchor P04
## @anchor P07
## @anchor P09
## @anchor P10a
## @anchor P11a
## @anchor P11b
