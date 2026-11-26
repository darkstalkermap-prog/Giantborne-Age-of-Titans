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
## move_speed_mult (product: Stonewall Stance 0.7, Wild Surge 1.15; P33: with the passives', Wildheart
## 1.05), and a status tagged Barrier (Bulwark) takes no knockback.
##
## P33 (plan M6-M9 §5.12): the sprint's stamina drain follows the giant's stamina_cost_mult like every
## action's cost (Relentless, Tireless: "everything you do costs less stamina").
##
## C1 (decisions C1-5, C1-7): a colossus (the "stride" permission, stage 7 and up) walks through the scenery's
## trunks as through grass (collision exceptions with the chunks' trunk bodies, TerrainChunk.TRUNKS_GROUP), and an
## action's `vault` (Colossus Stride) carries the giant on an arc over a wall no taller than half its height onto
## open ground ahead (run_vault, plan_vault).

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 28.0

## Facing when the current attack's windup began; soft targeting turns at most
## soft_target_max_deg away from it.
var windup_base_yaw := 0.0
var sprint_locked := false
## C3 (decision C3-7): the facing's turning speed now (rad/s), eased toward the turn's need; the swing turning into
## its blow (instance id, -1 = none).
var _turn_rate := 0.0
var _turn_into := -1
## C3: the facing eases out over the last stretch of a turn (rad/s per rad left) and its speed builds at this many
## times the stage's turn rate a second (a giant leans into a turn, then settles; no constant-rate stop).
const TURN_EASE_PER_S := 7.0
const TURN_ACCEL_FACTOR := 6.0
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
			var want := swing_facing_yaw(action, _instance_id)
			windup_base_yaw = want
			_turn_into = -1
			if _turns_into_swing(action):
				# C3 (decision C3-7): an unlocked weapon swing turns into its blow through the windup - the hips and
				# shoulders lead, the weapon follows - instead of snapping round in one frame; it faces the blow's
				# way by the windup's last tick (turn_into_swing), so the arc strikes where the plan says
				_turn_into = _instance_id
			else:
				player.facing_yaw = want
				player.rotation.y = player.facing_yaw
			_turn_rate = 0.0


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


## C3: a weapon swing faces where its plan aims (PlayerAttack.swing_plan_for: the lock, else what is under the
## cursor, else the camera's yaw - the soft target's nudge comes during the windup, as before); every other
## action faces attack_facing_yaw().
func swing_facing_yaw(action: ActionDef, instance_id: int) -> float:
	if player.attack == null or not _planned_strike(action):
		return attack_facing_yaw()
	var plan: Dictionary = player.attack.swing_plan_for(action, instance_id)
	if str(plan.get("source", "none")) == "cursor" or _is_stamp(action):
		return float(plan.yaw)   # (C3b: a stamp faces where its foot comes down, whatever picked its target)
	return attack_facing_yaw()


## A strike the swing plan aims (PlayerAttack.swing_plan): a weapon arc, or C3b's stamp and stomp.
static func _planned_strike(action: ActionDef) -> bool:
	return action != null and ((action.hit_shape == "weapon_arc" and not action.arc.is_empty()) or _is_stamp(action))


static func _is_stamp(action: ActionDef) -> bool:
	return action != null and action.hit_shape == PlayerAttack.FOOT_STAMP


## True while the running swing aims at what was under the cursor (its facing holds through the windup).
func _cursor_swing() -> bool:
	var c := player.controller
	if c.action == null or player.attack == null:
		return false
	var plan: Dictionary = player.attack.swing_plan_for(c.action, c.instance_id)
	return str(plan.get("source", "none")) == "cursor" or (_is_stamp(c.action) and str(plan.get("source", "none")) != "lock")


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
		pools.consume_stamina_up_to(drain * dt * player.entity.combatant.stamina_cost_mult())
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
				elif _cursor_swing():
					target_yaw = windup_base_yaw   # C3: the swing keeps facing what the cursor picked
				else:
					target_yaw = windup_base_yaw + player.targeting.soft_target_offset(windup_base_yaw)
	if controller.can_rotate():
		if instant:
			player.facing_yaw = target_yaw
			_turn_rate = 0.0
		elif _turn_into >= 0 and controller.instance_id == _turn_into and controller.phase() == ActionDef.Phase.WINDUP:
			player.facing_yaw = turn_into_swing(player.facing_yaw, target_yaw, controller.ticks_in_phase(),
				controller.action.windup_ticks, deg_to_rad(float(player.profile.get("turn_rate_deg_s", 540.0))), dt)
		elif controller.state == CombatController.State.LOCOMOTION and (player.attack == null or player.attack.cursor_aim):
			var max_rate := deg_to_rad(float(player.profile.get("turn_rate_deg_s", 540.0)))
			var delta := TargetingRules.yaw_delta(player.facing_yaw, target_yaw)
			var r := eased_turn(_turn_rate, delta, max_rate, dt)
			_turn_rate = r
			player.facing_yaw += clampf(r * dt * signf(delta), -absf(delta), absf(delta))
		else:
			# (a guard, a windup's tracking and the bots' turns keep the constant rate the duels were tuned with)
			var step := deg_to_rad(float(player.profile.get("turn_rate_deg_s", 540.0))) * dt
			player.facing_yaw += clampf(TargetingRules.yaw_delta(player.facing_yaw, target_yaw), -step, step)
			_turn_rate = 0.0
		player.facing_yaw = wrapf(player.facing_yaw, -PI, PI)
	player.rotation.y = player.facing_yaw


## C3 (decision C3-7): the turning speed for a turn with `delta` (rad) left: it builds toward the stage's `max_rate`
## at TURN_ACCEL_FACTOR x max_rate a second and eases out as the turn closes (at most TURN_EASE_PER_S x what is left),
## so a turn starts with weight and settles instead of stopping dead.
static func eased_turn(rate: float, delta: float, max_rate: float, dt: float) -> float:
	var want := minf(max_rate, absf(delta) * TURN_EASE_PER_S)
	return move_toward(absf(rate), want, max_rate * TURN_ACCEL_FACTOR * dt) if want > absf(rate) else want


## C3 (decision C3-7): the facing a swing turning into its blow has after this tick: the stage's turn rate twice over,
## or faster if that is what it takes to face `target_yaw` by the windup's last tick (`elapsed` of `windup_ticks`).
static func turn_into_swing(yaw: float, target_yaw: float, elapsed: int, windup_ticks: int, turn_rate: float,
		dt: float) -> float:
	var delta := TargetingRules.yaw_delta(yaw, target_yaw)
	var left := maxi(1, windup_ticks - elapsed - 1)
	var step := maxf(turn_rate * 2.0 * dt, absf(delta) / float(left))
	return yaw + clampf(delta, -step, step)


## C3: a swing that turns into its blow (rather than snapping): a weapon arc with a windup, swung with no lock (a
## locked swing faces its target at once, as the titans' duels were tuned for).
func _turns_into_swing(action: ActionDef) -> bool:
	if not _planned_strike(action) or action.windup_ticks < 3 \
			or (player.attack != null and not player.attack.cursor_aim):
		return false
	var target := player.targeting.locked_entity() if player.targeting != null else null
	return target == null or not target.is_alive()


func update_movement(intents: Dictionary, dt: float) -> void:
	var controller := player.controller
	var dead := controller.state == CombatController.State.DEAD
	var input: Vector2 = Vector2.ZERO if dead else intents.move
	var walk := float(player.profile.get("walk_speed_mps", 5.0))
	var speed := walk * controller.move_speed_multiplier() * _speed_mult * status_speed_mult()   # P31: statuses
	if player.sprinting and player.sprint_def != null:
		speed *= float(player.sprint_def.param("speed_mult", 1.5))
	var target_v := move_dir_world(input) * speed
	sync_trunk_passes()   # C1: a colossus strides through the scenery's trunks
	if run_vault(dt):   # C1: Colossus Stride carries the giant on its arc (no slide while it flies)
		return
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
## Surge 1.15) and (P33) the passives' (Wildheart 1.05): Combatant.move_speed_mult, applied once here.
func status_speed_mult() -> float:
	if player.entity == null or player.entity.combatant == null:
		return 1.0
	return player.entity.combatant.move_speed_mult()


## True while a status tagged Barrier protects the giant (Bulwark: no knockback).
func has_barrier() -> bool:
	if player.entity == null or player.entity.combatant == null:
		return false
	for id in player.entity.combatant.statuses.active_ids():
		var def := GameData.get_status(id)
		if def != null and def.has_tag("Barrier"):
			return true
	return false


# --------------------------------------------------------------------------- C1: the colossi's stride

## C1: why the last vault ended or was refused: "" (none yet, or flying), "landed", "too_high" (something on the
## way above max_height_ratio x the height), "gate" (a size gate for a greater stage, or a blocker: the world's
## edge), "no_ground" (nothing to land on, or too great a drop), "no_room" (the landing overlaps the world or an
## actor), "interrupted" (the action ended in the air: the giant is set down where it is).
var vault_end_reason := ""
## The last vault's take-off and landing points and the arc's peak above the higher of them (tests, the tour).
var vault_from := Vector3.INF
var vault_to := Vector3.INF
var vault_peak_m := 0.0
## Vaults that landed this session (tests, the bots).
var vaults_landed := 0
## C1: set by the first vault that lands (quest.rim_colossus's first stage).
const STRIDE_DONE_FLAG := "player.stride.done"
const VAULT_REFUSALS := {
	"too_high": "Too high to stride over: half your height clears a wall, no more.",
	"gate": "Something greater than you guards the way: you cannot stride past it.",
	"no_ground": "There is no ground to stride onto there.",
	"no_room": "There is no room to land there.",
}
## The landing may lie at most this many of the giant's heights below the take-off.
const VAULT_MAX_DROP_RATIO := 1.5
## Samples along the vault's line (one every VAULT_SAMPLE_M).
const VAULT_SAMPLE_M := 2.0
const VAULT_WORLD_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
var _vault_instance := -1
var _vault_state := 0   # 0 not begun, 1 flying, 2 landed or refused
var _vault_e0 := 0
var _vault_e1 := 1
var _vault_mask := -1
var _trunks_excepted := {}   # instance id -> true
var _trunks_check_tick := -1000


## The current action's vault block when it has one ({} otherwise).
func _vault_block() -> Dictionary:
	var a := player.controller.action
	var v: Variant = a.param("vault") if a != null else null
	return v if typeof(v) == TYPE_DICTIONARY else {}


## True while a vault carries the giant (it then owns the body's position: no slide this tick).
func run_vault(_dt: float) -> bool:
	var c := player.controller
	var v := _vault_block()
	if v.is_empty() or c.state == CombatController.State.DEAD or c.instance_id != _vault_instance:
		if _vault_state == 1:
			_vault_land("interrupted")
		if v.is_empty() or c.state == CombatController.State.DEAD:
			_vault_instance = -1
			return false
		_vault_instance = c.instance_id
		_vault_state = 0
		vault_end_reason = ""
	var phase: String = ActionDef.PHASE_NAMES[c.phase()]
	if _vault_state == 0:
		if phase != str(v.get("phase", "windup")):
			return false
		var plan := plan_vault(v)
		if not bool(plan.ok):
			_vault_state = 2
			vault_end_reason = str(plan.reason)
			Events.hud_message.emit(str(VAULT_REFUSALS.get(plan.reason, "You cannot stride there.")), "warn")
			return false
		vault_from = player.global_position
		vault_to = plan.land
		vault_peak_m = float(plan.peak)
		_vault_e0 = c.elapsed
		_vault_e1 = _phase_end_elapsed(str(v.get("phase", "windup")))
		_vault_state = 1
		_vault_mask = player.collision_mask
		player.collision_mask = 0
	if _vault_state != 1:
		return false
	if phase != str(v.get("phase", "windup")):
		_vault_land("landed")
		return false
	var t := clampf(float(c.elapsed - _vault_e0 + 1) / float(maxi(1, _vault_e1 - _vault_e0)), 0.0, 1.0)
	var top := maxf(vault_from.y, vault_to.y) + vault_peak_m
	var base := vault_from.lerp(vault_to, t)
	# a smooth rise and fall over the higher end: y follows the base line plus the arc's bulge to `top`
	var bulge := 4.0 * t * (1.0 - t)
	var y := lerpf(base.y, top, bulge)
	player.global_position = Vector3(base.x, y, base.z)
	player.velocity = Vector3.ZERO
	player.move_velocity = Vector3.ZERO
	player.knockback_velocity = Vector3.ZERO
	if t >= 1.0:
		_vault_land("landed")
	return true


## The elapsed tick at which the current action's `phase` ends.
func _phase_end_elapsed(phase: String) -> int:
	var a := player.controller.action
	match phase:
		"windup":
			return a.windup_ticks
		"active":
			return a.windup_ticks + a.active_ticks
	return a.windup_ticks + a.active_ticks + a.recovery_ticks


func _vault_land(reason: String) -> void:
	if _vault_state == 1 and reason == "landed":
		player.global_position = vault_to
		vaults_landed += 1
		WorldState.try_set_flag(STRIDE_DONE_FLAG, true)
	_vault_state = 2
	vault_end_reason = reason
	if _vault_mask >= 0:
		player.collision_mask = _vault_mask
		_vault_mask = -1
	player.velocity = Vector3.ZERO


## Plans a vault from where the giant stands along its facing (pure physics queries; changes nothing):
## {ok, reason, land: Vector3 (the landing's floor), peak (m above the higher end), top (the highest thing on the
## way, m above the take-off)}.
func plan_vault(v: Dictionary) -> Dictionary:
	var h := float(player.profile.get("height_m", 3.66))
	var dist := float(v.get("distance_height_ratio", 1.3)) * h
	var max_h := float(v.get("max_height_ratio", 0.5)) * h
	var clear := float(v.get("clear_m", 1.5))
	var from := player.global_position
	var dir := Vector3(-sin(player.facing_yaw), 0.0, -cos(player.facing_yaw))
	var space := player.get_world_3d().direct_space_state
	var out := {"ok": false, "reason": "", "land": Vector3.INF, "peak": 0.0, "top": 0.0}
	var exclude := [player.get_rid()]
	# a greater stage's size gate or a blocker anywhere across the line, at three heights
	var guard_mask: int = 32 | int(player.growth.size_gate_mask())
	for frac: float in [0.1, 0.5, 0.95]:
		var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * h * frac, from + dir * dist + Vector3.UP * h * frac,
			guard_mask, exclude)
		q.hit_from_inside = true
		if not space.intersect_ray(q).is_empty():
			out.reason = "gate"
			return out
	# the highest thing on the way (the world and breakables), sampled straight down from above the clearance
	var n := maxi(2, int(ceil(dist / VAULT_SAMPLE_M)))
	var top := 0.0
	for k in range(1, n):
		var p := from + dir * (dist * float(k) / float(n))
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, from.y + max_h + clear + 0.5, p.z),
			Vector3(p.x, from.y - h, p.z), VAULT_WORLD_MASK, exclude)
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var y := float((hit.position as Vector3).y) - from.y
		if (hit.position as Vector3).y >= from.y + max_h + clear + 0.49:
			out.reason = "too_high"   # the ray began inside something taller than the vault clears
			return out
		top = maxf(top, y)
	if top > max_h:
		out.reason = "too_high"
		return out
	# the landing: the first floor straight down at the far end
	var land_xz := from + dir * dist
	var lq := PhysicsRayQueryParameters3D.create(Vector3(land_xz.x, from.y + max_h + clear + 0.5, land_xz.z),
		Vector3(land_xz.x, from.y - h * VAULT_MAX_DROP_RATIO, land_xz.z), VAULT_WORLD_MASK, exclude)
	var land_hit := space.intersect_ray(lq)
	if land_hit.is_empty() or (land_hit.normal as Vector3).y < 0.7:
		out.reason = "no_ground"
		return out
	var land: Vector3 = land_hit.position
	if land.y - from.y > max_h:
		out.reason = "too_high"
		return out
	# room for the body where it lands
	var cap := CapsuleShape3D.new()
	cap.radius = float(player.profile.get("capsule_radius_m", 1.0))
	cap.height = float(player.profile.get("capsule_total_height_m", h))
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis(), land + Vector3.UP * (cap.height * 0.5 + 0.3))
	sq.collision_mask = VAULT_WORLD_MASK | 32 | HitQueryAdapter.LAYER_ACTORS
	sq.exclude = exclude
	if not space.intersect_shape(sq, 1).is_empty():
		out.reason = "no_room"
		return out
	out.ok = true
	out.land = land
	out.top = top
	out.peak = maxf(top - maxf(0.0, land.y - from.y), 0.0) + clear + 0.06 * dist
	return out


## C1 (decision C1-7): a giant with the "stride" permission passes through every loaded trunk body (exceptions
## added as chunks bring them, checked every TRUNK_CHECK_TICKS); a smaller one has none.
const TRUNK_CHECK_TICKS := 30


func strides_through_trees() -> bool:
	var perms: Variant = player.profile.get("interaction_permissions", [])
	return typeof(perms) == TYPE_ARRAY and (perms as Array).has("stride")


func sync_trunk_passes() -> void:
	var want := strides_through_trees()
	if not want and _trunks_excepted.is_empty():
		return
	if want and Sim.tick - _trunks_check_tick < TRUNK_CHECK_TICKS:
		return
	_trunks_check_tick = Sim.tick
	if not want:
		for id: int in _trunks_excepted:
			var b := instance_from_id(id) as PhysicsBody3D
			if b != null and is_instance_valid(b):
				player.remove_collision_exception_with(b)
		_trunks_excepted.clear()
		return
	if not player.is_inside_tree():
		return
	for n in player.get_tree().get_nodes_in_group(TerrainChunk.TRUNKS_GROUP):
		var body := n as PhysicsBody3D
		if body != null and not _trunks_excepted.has(body.get_instance_id()):
			player.add_collision_exception_with(body)
			_trunks_excepted[body.get_instance_id()] = true
