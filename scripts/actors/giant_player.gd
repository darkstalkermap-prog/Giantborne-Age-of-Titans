class_name GiantPlayer
extends CharacterBody3D
## The player-controlled giant (stage 1: 12 ft / 3.66 m).
##
## Glue only: input intents -> CombatController requests; controller state -> movement
## (CharacterBody3D), weapon sweeps and pulses (HitQueryAdapter), lock-on (LockOnTracker),
## camera (CameraRig) and the procedural rig. Stepped by Sim at 60 Hz via sim_step().

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 28.0
const OUT_OF_WORLD_Y := -30.0
const SOFT_TARGET_CONE_DEG := 45.0

@export var definition_id := "player.giant"

@onready var entity: CombatEntity = $CombatEntity
@onready var camera_rig: CameraRig = $CameraRig
@onready var rig: ActorRig = $Visual
@onready var body_shape: CollisionShape3D = $BodyShape

var router: InputRouter
var controller: CombatController
var lock := LockOnTracker.new()
var record: Dictionary = {}
var profile: Dictionary = {}
var weapon: Dictionary = {}
var sprint_def: ActionDef
var growth_stage := 1
var facing_yaw := 0.0
var sprinting := false
var sprint_toggled := false
var sprint_locked := false
var move_velocity := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
var dodge_direction := Vector3.ZERO
var windup_base_yaw := 0.0
var prev_segment := PackedVector3Array()
var clanked_instance := -1
var last_intents: Dictionary = {}
var spawn_transform := Transform3D.IDENTITY
var weapon_pivot := Vector3(0.82, 2.9, 0.0)
var attack_origin := Vector3(0.0, 2.6, 0.0)
var arm_length := 1.5
var weapon_length := 1.85
var weapon_radius := 0.45
var stats := {"attacks": 0, "hits_landed": 0, "deaths": 0, "parries": 0, "kills": 0}


func _ready() -> void:
	add_to_group("player")
	record = GameData.get_record(definition_id)
	profile = GameData.get_record(str(record.get("growth_profile", "growth.01")))
	weapon = GameData.get_record(str(record.get("weapon", "weapon.club")))
	growth_stage = int(profile.get("stage", 1))
	_read_geometry()
	_build_controller()
	router = InputRouter.new()
	router.name = "InputRouter"
	add_child(router)
	_apply_profile()
	facing_yaw = rotation.y
	camera_rig.yaw = facing_yaw
	camera_rig.setup(self, profile)
	lock.range_m = float(profile.get("lock_range_m", 35.0))
	lock.half_angle_deg = float(profile.get("lock_half_angle_deg", 60.0))
	rig.set_weapon_pivot(weapon_pivot)
	spawn_transform = global_transform
	entity.hit_landed.connect(_on_hit_landed)
	entity.hit_taken.connect(_on_hit_taken)
	Events.entity_died.connect(_on_any_entity_died)
	Sim.register_actor(entity.entity_id, self)


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)


func _read_geometry() -> void:
	var p: Array = profile.get("weapon_pivot_m", [0.82, 2.9, 0.0])
	weapon_pivot = Vector3(p[0], p[1], p[2])
	var o: Array = profile.get("attack_origin_m", [0.0, 2.6, 0.0])
	attack_origin = Vector3(o[0], o[1], o[2])
	arm_length = float(profile.get("arm_length_m", 1.5))
	weapon_length = float(weapon.get("length_m", 1.85))
	weapon_radius = float(weapon.get("hit_radius_m", 0.45))


func _build_controller() -> void:
	controller = CombatController.new(entity.entity_id, entity.combatant)
	controller.growth_stage = growth_stage
	controller.set_instance_source(Sim.new_instance_id)
	var lo: Dictionary = record.get("loadout", {})
	controller.loadout = {
		"light": str(lo.get("light_chain", "")), "heavy": str(lo.get("heavy", "")),
		"dodge": str(lo.get("dodge", "")), "block": str(lo.get("block", "")),
		"jump": str(lo.get("jump", "")), "ultimate": str(lo.get("ultimate", "")),
	}
	var slots: Array = lo.get("slots", [])
	for i in 8:
		controller.loadout["slot_%d" % (i + 1)] = str(slots[i]) if i < slots.size() else ""
	for id: String in controller.loadout.values():
		_add_action_chain(id)
	sprint_def = GameData.get_action(str(lo.get("sprint", "action.sprint")))
	controller.block_def = GameData.get_action(str(lo.get("block", "action.block")))
	entity.controller = controller
	controller.action_started.connect(_on_action_started)
	controller.request_rejected.connect(_on_request_rejected)


func _add_action_chain(id: String) -> void:
	var guard := 0
	while id != "" and not controller.library.has(id) and guard < 16:
		var def := GameData.get_action(id)
		if def == null:
			return
		controller.add_action(def)
		id = def.chain_next
		guard += 1


func _apply_profile() -> void:
	var capsule := (body_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = float(profile.get("capsule_radius_m", 0.85))
	capsule.height = float(profile.get("capsule_total_height_m", 3.66))
	body_shape.shape = capsule
	body_shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	floor_snap_length = maxf(0.3, float(profile.get("step_height_m", 0.45)))
	floor_max_angle = deg_to_rad(46.0)


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	var intents := router.consume()
	last_intents = intents
	controller.on_floor = is_on_floor()
	controller.block_held = intents.block_held
	controller.begin_tick(tick)
	if controller.state != CombatController.State.DEAD:
		_handle_meta(intents)
		_handle_actions(intents)
		if intents.block_held:
			controller.resume_held_block()
	_update_sprint(intents, dt)
	_update_facing(intents, dt)
	_update_movement(intents, dt)
	_run_hit_queries(tick)
	entity.combatant.pools.tick(dt, controller.stamina_regen_allowed(sprinting))
	entity.combatant.poise.tick(dt)
	_maintain_lock(dt)
	if global_position.y < OUT_OF_WORLD_Y:
		global_transform = spawn_transform
		velocity = Vector3.ZERO
		move_velocity = Vector3.ZERO


func _handle_meta(intents: Dictionary) -> void:
	var hold_lock: bool = Settings.get_value("lock_mode") == "hold"
	for e: StringName in intents.edges:
		match e:
			&"camera_toggle":
				camera_rig.toggle_mode()
			&"lock_press":
				if lock.is_locked() and not hold_lock:
					_release_lock("manual")
				else:
					_try_lock()
			&"lock_release":
				if hold_lock and lock.is_locked():
					_release_lock("manual")
			&"target_left":
				if lock.is_locked():
					_switch_target(-1)
				else:
					camera_rig.zoom(-1)
			&"target_right":
				if lock.is_locked():
					_switch_target(1)
				else:
					camera_rig.zoom(1)
			# Right stick: in third-person lock the stick does not look, so a fast flick switches
			# at once; in first-person lock it also looks, so only a flick-and-release ("tap") does.
			&"stick_flick_left", &"stick_flick_right":
				if lock.is_locked() and not camera_rig.is_first_person():
					_switch_target(-1 if e == &"stick_flick_left" else 1)
			&"stick_tap_left", &"stick_tap_right":
				if lock.is_locked() and camera_rig.is_first_person():
					_switch_target(-1 if e == &"stick_tap_left" else 1)
			&"sprint_press":
				sprint_toggled = not sprint_toggled
			&"interact":
				Events.hud_message.emit("Nothing to grab here yet (grabs arrive in M3)", "info")
	# Hold mode follows the polled key state, not only release edges: a release that happened
	# while paused or unfocused (no edge delivered) still ends the lock.
	if hold_lock and lock.is_locked() and not intents.lock_held:
		_release_lock("manual")


func _handle_actions(intents: Dictionary) -> void:
	for e: StringName in intents.edges:
		match e:
			&"light":
				controller.request(&"light")
			&"heavy":
				controller.request(&"heavy")
			&"dodge":
				controller.request(&"dodge")
			&"jump":
				controller.request(&"jump")
			&"block_press":
				controller.request(&"block")
			&"block_release":
				controller.request(&"block_release")
			&"ultimate":
				controller.request(&"ultimate")
			_:
				var s := String(e)
				if s.begins_with("slot_"):
					controller.request(&"slot", {"slot": int(s.substr(5))})


func _on_action_started(action: ActionDef, instance_id: int) -> void:
	Events.ability_started.emit(Sim.tick, entity.entity_id, action.id, instance_id)
	match action.kind:
		"jump":
			velocity.y = float(action.param("velocity_mps", profile.get("jump_velocity_mps", 6.5)))
		"dodge":
			sprinting = false
			dodge_direction = _dodge_direction()
		"block":
			facing_yaw = _attack_facing_yaw()   # raise the guard toward the aim / locked target
			rotation.y = facing_yaw
		"light", "heavy", "ability", "ultimate":
			sprinting = false
			if action.kind == "heavy":
				sprint_toggled = false
			facing_yaw = _attack_facing_yaw()
			rotation.y = facing_yaw
			windup_base_yaw = facing_yaw
			prev_segment = PackedVector3Array()
			stats.attacks += 1


## Attacks face the locked target, otherwise the aim direction (camera forward) in both modes.
func _attack_facing_yaw() -> float:
	var target := locked_entity()
	if target != null and target.is_alive():
		return _yaw_to(target.anchor_position())
	return camera_rig.yaw


func _on_request_rejected(kind: StringName, action_id: String, reason: String) -> void:
	Events.action_rejected.emit(Sim.tick, entity.entity_id, action_id, reason)
	var def := GameData.get_action(action_id)
	var label := def.display_name if def != null else String(kind).capitalize()
	match reason:
		"stamina":
			Events.hud_message.emit("Not enough stamina for %s" % label, "warn")
		"cooldown":
			Events.hud_message.emit("%s is recovering (%.1f s)" % [label,
				controller.cooldowns.remaining_s(action_id, Sim.tick)], "warn")
		"empty_slot":
			if kind == &"ultimate":
				Events.hud_message.emit("No ultimate equipped yet (roadmap)", "info")
			else:
				Events.hud_message.emit("That ability slot is empty", "info")
		"locked":
			Events.hud_message.emit("%s unlocks at a later growth stage" % label, "warn")


# --------------------------------------------------------------------------- movement

## Movement is camera-relative; while locked it is target-relative (forward = toward the
## target), so the side-orbiting lock camera never skews strafing.
func _move_dir_world(input: Vector2) -> Vector3:
	var basis_yaw := camera_rig.yaw
	var target := locked_entity()
	if target != null and target.is_alive() and not camera_rig.is_first_person():
		basis_yaw = _yaw_to(target.anchor_position())
	return Vector3(input.x, 0.0, -input.y).rotated(Vector3.UP, basis_yaw)


func _dodge_direction() -> Vector3:
	var input: Vector2 = last_intents.get("move", Vector2.ZERO)
	if input.length() > 0.2:
		return _move_dir_world(input).normalized()
	return global_transform.basis.z.normalized()  # backstep when there is no input


func _update_sprint(intents: Dictionary, dt: float) -> void:
	var toggle_mode: bool = Settings.get_value("sprint_mode") == "toggle"
	var moving := (intents.move as Vector2).length() > 0.2
	if toggle_mode and not moving:
		sprint_toggled = false
	var wants: bool = sprint_toggled if toggle_mode else intents.sprint_held
	var pools := entity.combatant.pools
	var resume := float(sprint_def.param("resume_threshold", 25.0)) if sprint_def != null else 25.0
	if sprint_locked and (not wants or pools.stamina >= resume):
		sprint_locked = false
	sprinting = wants and moving and controller.state == CombatController.State.LOCOMOTION \
		and not sprint_locked and pools.stamina > 0.0
	if sprinting:
		var drain := float(sprint_def.param("drain_per_s", 8.0)) if sprint_def != null else 8.0
		pools.consume_stamina_up_to(drain * dt)
		if pools.stamina <= 0.0:
			sprinting = false
			sprint_locked = true
			sprint_toggled = false


func _update_facing(intents: Dictionary, dt: float) -> void:
	if controller.state == CombatController.State.DEAD:
		return
	var target_yaw := facing_yaw
	var instant := false
	var target := locked_entity()
	match controller.state:
		CombatController.State.LOCOMOTION:
			if target != null:
				target_yaw = _yaw_to(target.anchor_position())
			elif camera_rig.is_first_person():
				target_yaw = camera_rig.yaw
				instant = true
			elif (intents.move as Vector2).length() > 0.1:
				target_yaw = TargetingRules.yaw_of(_move_dir_world(intents.move))
		CombatController.State.BLOCKING:
			# The guard follows the aim (or the locked target), never the movement direction, so
			# backing off or strafing keeps the block facing what the player is looking at.
			target_yaw = _attack_facing_yaw()
			instant = camera_rig.is_first_person() and target == null
		CombatController.State.ATTACKING, CombatController.State.CASTING:
			if controller.phase() == ActionDef.Phase.WINDUP:
				if target != null:
					target_yaw = _yaw_to(target.anchor_position())
				else:
					target_yaw = windup_base_yaw + _soft_target_offset()
	if controller.can_rotate():
		if instant:
			facing_yaw = target_yaw
		else:
			var step := deg_to_rad(float(profile.get("turn_rate_deg_s", 540.0))) * dt
			facing_yaw += clampf(TargetingRules.yaw_delta(facing_yaw, target_yaw), -step, step)
		facing_yaw = wrapf(facing_yaw, -PI, PI)
	rotation.y = facing_yaw


## Soft targeting: during windup, turn at most soft_target_max_deg (10) toward the best
## enemy in front - never toward one hidden behind a wall.
func _soft_target_offset() -> float:
	var action := controller.action
	if action == null or action.soft_target_max_deg <= 0.0:
		return 0.0
	var max_rad := deg_to_rad(action.soft_target_max_deg)
	var reach := float(profile.get("melee_reach_m", 3.5)) + 1.5
	var base_dir := Vector3(-sin(windup_base_yaw), 0.0, -cos(windup_base_yaw))
	var best_score := -1.0
	var best_offset := 0.0
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * attack_origin.y
	for e: CombatEntity in Sim.entities():
		if e == entity or not e.is_alive() or not CombatEntity.can_damage(entity.team, e.team):
			continue
		if not e.combatant.lockable:
			continue
		var to := e.actor.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > reach or dist < 0.01:
			continue
		var delta := TargetingRules.yaw_delta(windup_base_yaw, TargetingRules.yaw_of(to))
		if absf(rad_to_deg(delta)) > SOFT_TARGET_CONE_DEG:
			continue
		if not HitQueryAdapter.line_clear(space, eye, e.anchor_position(), HitQueryAdapter.OCCLUDER_MASK, e.occlusion_rids):
			continue
		var q := TargetingRules.score(base_dir, to, dist, reach, e.combatant.threat)
		if q > best_score:
			best_score = q
			best_offset = clampf(delta, -max_rad, max_rad)
	return best_offset


func _update_movement(intents: Dictionary, dt: float) -> void:
	var dead := controller.state == CombatController.State.DEAD
	var input: Vector2 = Vector2.ZERO if dead else intents.move
	var walk := float(profile.get("walk_speed_mps", 5.0))
	var speed := walk * controller.move_speed_multiplier()
	if sprinting and sprint_def != null:
		speed *= float(sprint_def.param("speed_mult", 1.5))
	var target_v := _move_dir_world(input) * speed
	if controller.state == CombatController.State.DODGING and controller.action != null:
		move_velocity = dodge_direction * _dodge_speed()
	else:
		var accel := float(profile.get("acceleration_mps2", 32.0)) * (1.0 if is_on_floor() else 0.35)
		move_velocity = move_velocity.move_toward(target_v, accel * dt)
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECEL * dt)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * dt
	velocity.x = move_velocity.x + knockback_velocity.x
	velocity.z = move_velocity.z + knockback_velocity.z
	move_and_slide()


## Ease-out burst that covers exactly dodge_distance_m over the dodge's movement ticks.
func _dodge_speed() -> float:
	var a := controller.action
	var ticks := maxi(1, a.active_ticks)
	if controller.elapsed >= ticks:
		return 0.0
	var distance := float(profile.get("dodge_distance_m", a.param("distance_m", 4.5)))
	var duration := ticks / 60.0
	var t_mid := (controller.elapsed + 0.5) / 60.0
	return 2.0 * distance / duration * (1.0 - t_mid / duration)


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


func _run_hit_queries(tick: int) -> void:
	var a := controller.action
	if a == null or controller.phase() != ActionDef.Phase.ACTIVE:
		prev_segment = PackedVector3Array()
		return
	var space := get_world_3d().direct_space_state
	var origin := to_global(attack_origin)
	match a.hit_shape:
		"weapon_arc":
			var cur := weapon_segment_global(a, controller.active_fraction())
			var prev := prev_segment
			if prev.size() != 2:
				prev = weapon_segment_global(a, controller.active_fraction_prev())
			var cands := HitQueryAdapter.sweep_capsule(space, entity, origin, prev[0], prev[1],
				cur[0], cur[1], weapon_radius)
			prev_segment = cur
			_queue_hits(cands, a, 0, tick)
			if clanked_instance != controller.instance_id:
				var wall := HitQueryAdapter.first_world_hit(space, origin, cur[1], [])
				if not wall.is_empty():
					clanked_instance = controller.instance_id
					Events.attack_clanked.emit(tick, entity.entity_id, controller.instance_id, wall.position)
		"cylinder_pulse":
			if controller.is_first_active_tick():
				var center := global_position + Vector3.UP * (a.height_m * 0.5)
				var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, a.radius_m,
					a.height_m, global_position + Vector3.UP * 0.8)
				_queue_hits(cands, a, 1, tick)
				Events.area_pulse.emit(tick, entity.entity_id, a.id, global_position, a.radius_m)


func _queue_hits(cands: Array, a: ActionDef, pulse_id: int, tick: int) -> void:
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.substep != y.substep:
			return x.substep < y.substep
		if not is_equal_approx(x.distance, y.distance):
			return x.distance < y.distance
		return (x.entity as CombatEntity).entity_id < (y.entity as CombatEntity).entity_id)
	var c := entity.combatant
	for cand: Dictionary in cands:
		var target: CombatEntity = cand.entity
		if not controller.hit_registry.try_register(controller.instance_id, pulse_id,
				target.entity_id, a.max_hits_per_target):
			continue
		var e := HitEvent.new()
		e.tick = tick
		e.instance_id = controller.instance_id
		e.pulse_id = pulse_id
		e.attacker_id = entity.entity_id
		e.target_id = target.entity_id
		e.action_id = a.id
		e.power = a.power
		e.ability_multiplier = a.ability_multiplier
		e.weapon_multiplier = float(weapon.get("damage_multiplier", 1.0)) if a.uses_weapon else 1.0
		e.attacker_stat = c.attribute("intellect") if a.category == "magic" else c.attribute("strength")
		e.attacker_height_m = c.height_m
		e.size_policy = a.size_policy
		e.damage_split = a.damage_split
		e.poise_damage = a.poise_damage
		e.tags = a.tags
		e.crit = a.crit_eligible and Sim.rng.randf() < c.crit_chance
		e.crit_multiplier = c.crit_multiplier
		e.weak_point = cand.weak_point
		e.flat_penetration = a.flat_penetration
		e.knockback_impulse = a.knockback_impulse
		e.knockback_max_speed = a.knockback_max_speed
		e.attacker_position = global_position
		e.hit_point = cand.point
		e.substep = cand.substep
		e.distance = cand.distance
		e.category = a.category
		e.attacker_growth_stage = growth_stage
		Sim.queue_hit(e)


func _on_hit_landed(result: HitResult) -> void:
	if result.dealt_damage():
		stats.hits_landed += 1
	if result.killed:
		stats.kills += 1


func _on_hit_taken(result: HitResult) -> void:
	if result.outcome == HitResult.Outcome.PARRIED:
		stats.parries += 1
		Events.hud_message.emit("Parry!", "good")
	elif result.outcome == HitResult.Outcome.GUARD_BROKEN:
		Events.hud_message.emit("Guard broken!", "bad")


func get_defense_state() -> DefenseState:
	var d := DefenseState.new()
	d.position = global_position
	d.forward = -global_transform.basis.z
	d.height_m = entity.combatant.height_m
	d.is_dead = controller.state == CombatController.State.DEAD
	d.blocking = controller.state == CombatController.State.BLOCKING
	d.block_elapsed_ticks = controller.block_elapsed_ticks()
	d.parry_available = controller.parry_available
	d.invulnerable = controller.is_invulnerable()
	d.stamina = entity.combatant.pools.stamina
	d.stability = entity.combatant.stability
	d.apply_block_def(controller.block_def)
	return d


func on_entity_died(_killer_id: String) -> void:
	stats.deaths += 1
	sprinting = false
	if lock.is_locked():
		_release_lock("player_died")
	Events.hud_message.emit("You were defeated", "bad")


# --------------------------------------------------------------------------- lock-on

func locked_entity() -> CombatEntity:
	if not lock.is_locked():
		return null
	return Sim.get_entity(lock.target_id)


func _eye() -> Vector3:
	return global_position + Vector3.UP * entity.combatant.height_m * float(profile.get("eye_height_ratio", 0.92))


func _yaw_to(point: Vector3) -> float:
	var to := point - global_position
	to.y = 0.0
	return facing_yaw if to.length_squared() < 1e-4 else TargetingRules.yaw_of(to)


func _visible(target: CombatEntity) -> bool:
	var space := get_world_3d().direct_space_state
	return HitQueryAdapter.line_clear(space, _eye(), target.anchor_position(),
		HitQueryAdapter.LAYER_WORLD, target.occlusion_rids)


func _gather_candidates(with_screen: bool) -> Array:
	var out: Array = []
	var eye := _eye()
	var cam := camera_rig.camera
	for e: CombatEntity in Sim.entities():
		if e == entity or not CombatEntity.can_damage(entity.team, e.team) or not e.combatant.lockable:
			continue
		var anchor := e.anchor_position()
		var c := {"id": e.entity_id, "direction": anchor - eye, "distance": eye.distance_to(anchor),
			"threat": e.combatant.threat, "alive": e.is_alive(), "lockable": e.combatant.lockable,
			"visible": _visible(e)}
		if with_screen and cam != null and not cam.is_position_behind(anchor):
			c["screen"] = cam.unproject_position(anchor)
		out.append(c)
	return out


func _try_lock() -> void:
	var id := lock.acquire(_gather_candidates(false), camera_rig.aim_forward())
	if id == "":
		Events.hud_message.emit("No target in range", "info")
	_sync_lock(id, "acquired")


func _switch_target(direction: int) -> void:
	var current := locked_entity()
	if current == null:
		return
	var cam := camera_rig.camera
	# If the current target is behind the camera (first-person free look), switch relative to
	# the screen centre instead of doing nothing.
	var screen := cam.get_viewport().get_visible_rect().size * 0.5
	if not cam.is_position_behind(current.anchor_position()):
		screen = cam.unproject_position(current.anchor_position())
	if lock.switch_target(direction, _gather_candidates(true), screen, camera_rig.aim_forward(), Sim.tick / 60.0):
		_sync_lock(lock.target_id, "switched")


func _release_lock(reason: String) -> void:
	lock.release()
	_sync_lock("", reason)


func _sync_lock(id: String, reason: String) -> void:
	camera_rig.lock_target = Sim.get_entity(id) if id != "" else null
	Events.lock_target_changed.emit(entity.entity_id, id, reason)


func _maintain_lock(dt: float) -> void:
	if not lock.is_locked():
		return
	var t := Sim.get_entity(lock.target_id)
	var info := {"exists": t != null}
	if t != null:
		info["alive"] = t.is_alive()
		info["lockable"] = t.combatant.lockable
		info["distance"] = _eye().distance_to(t.anchor_position())
		info["visible"] = _visible(t)
	var reason := lock.update(dt, info)
	if reason != "":
		_sync_lock("", reason)


func _on_any_entity_died(_tick: int, id: String, _killer: String) -> void:
	if id == lock.target_id:
		_release_lock("target_died")


# --------------------------------------------------------------------------- presentation

func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	rig.flash(strength, color)


func get_rig_state() -> Dictionary:
	var local_dodge := global_transform.basis.inverse() * dodge_direction
	return {
		"state": controller.state,
		"action": controller.action,
		"phase": controller.phase(),
		"phase_fraction": controller.phase_fraction(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"dead": controller.state == CombatController.State.DEAD,
		"staggered": controller.state == CombatController.State.STAGGERED,
		"dodging": controller.state == CombatController.State.DODGING,
		"dodge_local": local_dodge,
	}


func get_debug_info() -> Dictionary:
	var pools := entity.combatant.pools
	return {
		"state": controller.state_name(),
		"phase": ActionDef.PHASE_NAMES[controller.phase()],
		"action": controller.action_id(),
		"instance": controller.instance_id,
		"elapsed": controller.elapsed,
		"queued": String(controller.buffer.kind),
		"stage": growth_stage,
		"health": pools.health, "stamina": pools.stamina, "essence": pools.essence, "fury": pools.fury,
		"poise": entity.combatant.poise.value,
		"sprinting": sprinting,
		"target": lock.target_id,
		"camera": "first person" if camera_rig.is_first_person() else "third person",
		"position": global_position,
		"invulnerable": controller.is_invulnerable(),
		"parry_window": controller.state == CombatController.State.BLOCKING
			and controller.block_elapsed_ticks() < ActionDef.seconds_to_ticks(0.2) and controller.parry_available,
	}
