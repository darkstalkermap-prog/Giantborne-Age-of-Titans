class_name PlayerMotor
extends PlayerComponent
## Sprint, facing, movement, dodge burst and knockback for the giant (moved unchanged from the
## M1 GiantPlayer). Reads intents and the controller, writes the actor's shared body state
## (facing_yaw, sprinting, move_velocity, knockback_velocity, dodge_direction) and moves the
## CharacterBody3D once per tick.
##
## Trampling (P26, plan M6-M9 §2.9): after each move, every BreakableProp the body slid against that
## the giant's stage tramples (its record's trample_stage) gets one trample hit and breaks - fences
## and palisades under a stage-4 giant's feet; the next tick walks on through.
##
## P31 (plan M6-M9 §2.11, §5.12): the scripted `motion` of an ability whose hit is a body sweep
## (Shoulder Charge's 12 m dash; the sweep is PlayerAttack's) moves the giant during motion.phase
## along the facing it had when the phase began, at speed_mps (times its slows) for at most
## max_distance_m; its body passes through other actors while it dashes (the sweep throws them
## aside), and stop_on_wall ends it against a wall, an untrampled prop or a blocker. Statuses scale walk and run speed by their
## move_speed_mult (product: Stonewall Stance 0.7, Wild Surge 1.15), and a status tagged Barrier
## (Bulwark) takes no knockback.

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
	var speed := walk * controller.move_speed_multiplier() * _speed_mult * status_speed_mult()   # P31: statuses
	if player.sprinting and player.sprint_def != null:
		speed *= float(player.sprint_def.param("speed_mult", 1.5))
	var target_v := move_dir_world(input) * speed
	var dashing := run_motion(dt)   # P31: a scripted ability motion (Shoulder Charge) owns move_velocity
	if controller.state == CombatController.State.DODGING and controller.action != null:
		player.move_velocity = player.dodge_direction * dodge_speed()
	elif not dashing:
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
	if not dead:
		trample_contacts()


## P26: one trample hit on each prop the body slid against this tick that its stage tramples.
## Returns how many it trampled.
func trample_contacts() -> int:
	var count := 0
	var stage := player.growth_stage
	for i in player.get_slide_collision_count():
		var prop := player.get_slide_collision(i).get_collider() as BreakableProp
		if prop != null and prop.can_trample(stage) and prop.trample(player):
			count += 1
	return count


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
	if direction.length_squared() < 1e-6 or has_barrier():   # P31: Bulwark takes no knockback
		return
	player.knockback_velocity = direction.normalized() * maxf(speed, player.knockback_velocity.length())


# --------------------------------------------------------------------------- P31: ability motion, status speed, barrier

## What stops a dash with stop_on_wall: world geometry, breakable props (unless trampled underfoot),
## blockers and the size gates.
const MOTION_WALL_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE | 32 \
	| PlayerGrowth.ALL_SIZE_GATES

## Why the last dash ended: "" (running or none), "distance", "wall", "phase" (its phase ended
## first), "interrupted".
var motion_end_reason := ""
## Where the last dash began and how far it has carried the giant (horizontal metres).
var motion_origin := Vector3.ZERO
var motion_travelled := 0.0
var _motion_instance := -1
var _motion_dir := Vector3.FORWARD
var _motion_started := false
var _motion_done := false
var _motion_through_actors := false


## The current action's `motion` (plan §2.8.2; P31 for the giant) when its hit is a body_sweep (the
## grab family's motion is PlayerGrab's lunge): during motion.phase the giant moves at speed_mps
## (times its slows) along the facing it had when that phase began, for at most max_distance_m;
## stop_on_wall ends it against MOTION_WALL_MASK geometry. Returns true while it owns move_velocity
## (also while standing still for the rest of the phase once it ended). The body passes through
## other actors while the dash runs.
func run_motion(dt: float) -> bool:
	var controller := player.controller
	var a := controller.action
	# Only a dash with a body sweep: the grab family's motion is PlayerGrab's lunge.
	var m: Variant = a.param("motion") if a != null and a.hit_shape == "body_sweep" else null
	if a == null or typeof(m) != TYPE_DICTIONARY or controller.state == CombatController.State.DEAD \
			or _motion_instance != controller.instance_id:
		if _motion_started and not _motion_done:
			_end_motion("interrupted")
		_restore_actor_collisions()
		if a == null or typeof(m) != TYPE_DICTIONARY or controller.state == CombatController.State.DEAD:
			_motion_instance = -1
			return false
		_motion_instance = controller.instance_id
		_motion_started = false
		_motion_done = false
		motion_end_reason = ""
		motion_travelled = 0.0
	if ActionDef.PHASE_NAMES[controller.phase()] != str((m as Dictionary).get("phase", "active")):
		if _motion_started and not _motion_done:
			_end_motion("phase")
		_restore_actor_collisions()
		return false
	if not _motion_started:
		_motion_started = true
		motion_origin = player.global_position
		_motion_dir = Vector3(-sin(player.facing_yaw), 0.0, -cos(player.facing_yaw))
		_pass_through_actors()
	motion_travelled = Vector2(player.global_position.x - motion_origin.x,
		player.global_position.z - motion_origin.z).length()
	if _motion_done:
		player.move_velocity = Vector3.ZERO
		return true
	if bool((m as Dictionary).get("stop_on_wall", false)) and ran_into_wall(_motion_dir):
		_end_motion("wall")
		return true
	var remaining := float((m as Dictionary).get("max_distance_m", INF)) - motion_travelled
	if remaining <= 0.01:
		_end_motion("distance")
		return true
	var speed := minf(float((m as Dictionary).get("speed_mps", 0.0)) * player.entity.combatant.move_mult(),
		remaining / dt)
	player.move_velocity = _motion_dir * speed
	player.knockback_velocity = Vector3.ZERO
	return true


## True while a scripted motion moves the giant.
func is_dashing() -> bool:
	return _motion_started and not _motion_done


func _end_motion(reason: String) -> void:
	_motion_done = true
	motion_end_reason = reason
	player.move_velocity = Vector3.ZERO
	_restore_actor_collisions()


func _pass_through_actors() -> void:
	if (player.collision_mask & HitQueryAdapter.LAYER_ACTORS) != 0:
		player.collision_mask &= ~HitQueryAdapter.LAYER_ACTORS
		_motion_through_actors = true


func _restore_actor_collisions() -> void:
	if _motion_through_actors:
		player.collision_mask |= HitQueryAdapter.LAYER_ACTORS
		_motion_through_actors = false


## True when the previous move_and_slide ran into MOTION_WALL_MASK geometry against `dir` (a wall,
## not the floor or a ramp); a prop being trampled underfoot is no wall.
func ran_into_wall(dir: Vector3) -> bool:
	for i in player.get_slide_collision_count():
		var c := player.get_slide_collision(i)
		var body := c.get_collider() as CollisionObject3D
		if body == null or (body.collision_layer & MOTION_WALL_MASK) == 0:
			continue
		var prop := body as BreakableProp
		if prop != null and (prop.destroyed or prop.special_hit_pending()):
			continue
		var n := c.get_normal()
		var flat := Vector3(n.x, 0.0, n.z)
		if absf(n.y) < 0.7 and flat.length_squared() > 1e-6 and flat.normalized().dot(dir) < -0.3:
			return true
	return false


## The product of the active statuses' move_speed_mult (1 when none: Stonewall Stance 0.7, Wild
## Surge 1.15).
func status_speed_mult() -> float:
	if player.entity == null or player.entity.combatant == null:
		return 1.0
	return maxf(0.0, player.entity.combatant.statuses.modifier_product("move_speed_mult"))


## True while a status tagged Barrier protects the giant (Bulwark: no knockback).
func has_barrier() -> bool:
	if player.entity == null or player.entity.combatant == null:
		return false
	for id in player.entity.combatant.statuses.active_ids():
		var def := GameData.get_status(id)
		if def != null and def.has_tag("Barrier"):
			return true
	return false
