class_name PlayerMotor
extends PlayerComponent
## Sprint, facing, movement, dodge burst and knockback for the giant (moved unchanged from the
## M1 GiantPlayer). Reads intents and the controller, writes the actor's shared body state
## (facing_yaw, sprinting, move_velocity, knockback_velocity, dodge_direction) and moves the
## CharacterBody3D once per tick.

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 28.0

## Facing when the current attack's windup began; soft targeting turns at most
## soft_target_max_deg away from it.
var windup_base_yaw := 0.0
var sprint_locked := false
var _speed_mults: Dictionary = {}   ## StringName source -> multiplier (1.0 is never stored)
var _speed_mult := 1.0


## A named, removable multiplier on walk/run speed (e.g. &"grab" 0.6 while holding a body).
## A multiplier of 1.0 removes the source. All sources multiply.
func set_speed_mult(source: StringName, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		_speed_mults.erase(source)
	else:
		_speed_mults[source] = maxf(0.0, mult)
	_speed_mult = 1.0
	for m: float in _speed_mults.values():
		_speed_mult *= m


func speed_mult() -> float:
	return _speed_mult


func speed_mult_sources() -> Dictionary:
	return _speed_mults.duplicate()


func toggle_sprint() -> void:
	player.sprint_toggled = not player.sprint_toggled


# --------------------------------------------------------------------------- hooks

func on_action_started(action: ActionDef, _instance_id: int) -> void:
	match action.kind:
		"jump":
			player.velocity.y = float(action.param("velocity_mps", player.profile.get("jump_velocity_mps", 6.5)))
		"dodge":
			player.sprinting = false
			player.dodge_direction = dodge_direction_from_input()
		"block":
			player.facing_yaw = attack_facing_yaw()   # raise the guard toward the aim / locked target
			player.rotation.y = player.facing_yaw
		"light", "heavy", "ability", "ultimate":
			player.sprinting = false
			if action.kind == "heavy":
				player.sprint_toggled = false
			player.facing_yaw = attack_facing_yaw()
			player.rotation.y = player.facing_yaw
			windup_base_yaw = player.facing_yaw


func debug_info(out: Dictionary) -> void:
	if not _speed_mults.is_empty():
		out["speed_mults"] = _speed_mults.duplicate()


# --------------------------------------------------------------------------- directions

## Yaw that faces `point` from the actor (the current facing when the point is on top of it).
func yaw_to(point: Vector3) -> float:
	var to := point - player.global_position
	to.y = 0.0
	return player.facing_yaw if to.length_squared() < 1e-4 else TargetingRules.yaw_of(to)


## Attacks face the locked target, otherwise the aim direction (camera forward) in both modes.
func attack_facing_yaw() -> float:
	var target := player.targeting.locked_entity()
	if target != null and target.is_alive():
		return yaw_to(target.anchor_position())
	return player.camera_rig.yaw


## Movement is camera-relative; while locked it is target-relative (forward = toward the
## target), so the side-orbiting lock camera never skews strafing.
func move_dir_world(input: Vector2) -> Vector3:
	var basis_yaw := player.camera_rig.yaw
	var target := player.targeting.locked_entity()
	if target != null and target.is_alive() and not player.camera_rig.is_first_person():
		basis_yaw = yaw_to(target.anchor_position())
	return Vector3(input.x, 0.0, -input.y).rotated(Vector3.UP, basis_yaw)


func dodge_direction_from_input() -> Vector3:
	var input: Vector2 = player.last_intents.get("move", Vector2.ZERO)
	if input.length() > 0.2:
		return move_dir_world(input).normalized()
	return player.global_transform.basis.z.normalized()  # backstep when there is no input


# --------------------------------------------------------------------------- per tick

func update_sprint(intents: Dictionary, dt: float) -> void:
	var toggle_mode: bool = Settings.get_value("sprint_mode") == "toggle"
	var moving := (intents.move as Vector2).length() > 0.2
	if toggle_mode and not moving:
		player.sprint_toggled = false
	var wants: bool = player.sprint_toggled if toggle_mode else intents.sprint_held
	var pools := player.entity.combatant.pools
	var sprint_def := player.sprint_def
	var resume := float(sprint_def.param("resume_threshold", 25.0)) if sprint_def != null else 25.0
	if sprint_locked and (not wants or pools.stamina >= resume):
		sprint_locked = false
	player.sprinting = wants and moving and player.controller.state == CombatController.State.LOCOMOTION \
		and not sprint_locked and pools.stamina > 0.0
	if player.sprinting:
		var drain := float(sprint_def.param("drain_per_s", 8.0)) if sprint_def != null else 8.0
		pools.consume_stamina_up_to(drain * dt)
		if pools.stamina <= 0.0:
			player.sprinting = false
			sprint_locked = true
			player.sprint_toggled = false


func update_facing(intents: Dictionary, dt: float) -> void:
	var controller := player.controller
	if controller.state == CombatController.State.DEAD:
		return
	var target_yaw := player.facing_yaw
	var instant := false
	var target := player.targeting.locked_entity()
	var camera := player.camera_rig
	match controller.state:
		CombatController.State.LOCOMOTION:
			if target != null:
				target_yaw = yaw_to(target.anchor_position())
			elif camera.is_first_person():
				target_yaw = camera.yaw
				instant = true
			elif (intents.move as Vector2).length() > 0.1:
				target_yaw = TargetingRules.yaw_of(move_dir_world(intents.move))
		CombatController.State.BLOCKING:
			# The guard follows the aim (or the locked target), never the movement direction, so
			# backing off or strafing keeps the block facing what the player is looking at.
			target_yaw = attack_facing_yaw()
			instant = camera.is_first_person() and target == null
		CombatController.State.ATTACKING, CombatController.State.CASTING:
			if controller.phase() == ActionDef.Phase.WINDUP:
				if target != null:
					target_yaw = yaw_to(target.anchor_position())
				else:
					target_yaw = windup_base_yaw + player.targeting.soft_target_offset(windup_base_yaw)
	if controller.can_rotate():
		if instant:
			player.facing_yaw = target_yaw
		else:
			var step := deg_to_rad(float(player.profile.get("turn_rate_deg_s", 540.0))) * dt
			player.facing_yaw += clampf(TargetingRules.yaw_delta(player.facing_yaw, target_yaw), -step, step)
		player.facing_yaw = wrapf(player.facing_yaw, -PI, PI)
	player.rotation.y = player.facing_yaw


func update_movement(intents: Dictionary, dt: float) -> void:
	var controller := player.controller
	var dead := controller.state == CombatController.State.DEAD
	var input: Vector2 = Vector2.ZERO if dead else intents.move
	var walk := float(player.profile.get("walk_speed_mps", 5.0))
	var speed := walk * controller.move_speed_multiplier() * _speed_mult
	if player.sprinting and player.sprint_def != null:
		speed *= float(player.sprint_def.param("speed_mult", 1.5))
	var target_v := move_dir_world(input) * speed
	if controller.state == CombatController.State.DODGING and controller.action != null:
		player.move_velocity = player.dodge_direction * dodge_speed()
	else:
		var accel := float(player.profile.get("acceleration_mps2", 32.0)) * (1.0 if player.is_on_floor() else 0.35)
		player.move_velocity = player.move_velocity.move_toward(target_v, accel * dt)
	player.knockback_velocity = player.knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECEL * dt)
	if player.is_on_floor():
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	else:
		player.velocity.y -= GRAVITY * dt
	player.velocity.x = player.move_velocity.x + player.knockback_velocity.x
	player.velocity.z = player.move_velocity.z + player.knockback_velocity.z
	player.move_and_slide()


## Ease-out burst that covers exactly dodge_distance_m over the dodge's movement ticks.
func dodge_speed() -> float:
	var controller := player.controller
	var a := controller.action
	var ticks := maxi(1, a.active_ticks)
	if controller.elapsed >= ticks:
		return 0.0
	var distance := float(player.profile.get("dodge_distance_m", a.param("distance_m", 4.5)))
	var duration := ticks / 60.0
	var t_mid := (controller.elapsed + 0.5) / 60.0
	return 2.0 * distance / duration * (1.0 - t_mid / duration)


func apply_knockback(direction: Vector3, speed: float) -> void:
	if direction.length_squared() < 1e-6:
		return
	player.knockback_velocity = direction.normalized() * maxf(speed, player.knockback_velocity.length())
