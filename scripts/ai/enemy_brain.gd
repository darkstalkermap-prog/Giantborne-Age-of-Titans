class_name EnemyBrain
extends RefCounted
## Finite-state AI shared by every enemy archetype (spec section 10, plan §2.7.3).
##
## Perception runs at 5 Hz and tactical decisions at 10 Hz (driven by the owning EnemyActor);
## movement is applied every tick by the actor. The brain only decides: a move target and
## speed, a point to face, and which attack to request. Engine queries (line of sight,
## distances) arrive as a perception snapshot from the actor, so a brain is a pure object
## that unit tests can drive directly.
##
## The base handles the life cycle every archetype shares - idle, patrol, noticing and
## investigating, fleeing, stagger and death - and delegates the engaged states (approach,
## attack, recover, reposition) to _decide_engaged(), whose default is the melee approach:
## close to the target's legs, take one of the target's attack tokens, strike, pause, repeat;
## without a token, circle. Archetype brains override _decide_engaged() and _choose_attack().
## Losing sight leads to investigating the last known position for memory_s, then patrol.

## The first ten keep their M1 indices (SoldierBrain.AIState.* still resolves); later states
## are appended: HOLD (P04 formations), STAND_DOWN (P11b), RETURN (P10a leash), ROUTED (P04).
enum AIState { IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION, FLEE, STAGGERED, DEAD,
	HOLD, STAND_DOWN, RETURN, ROUTED }
const STATE_NAMES := ["Idle", "Patrol", "Alert", "Approach", "Attack", "Recover", "Reposition",
	"Flee", "Staggered", "Dead", "Hold", "Stand down", "Return", "Routed"]
const TICK_RATE := 60
const ATTACK_FACING_DEG := 35.0

var state: int = AIState.IDLE
var state_tick := 0
var now := 0
var ai: Dictionary = {}
var attacks: Array = []
var attack_weights: Array = []
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var perception: Dictionary = {}
## True while the brain knows where its target is; GameSession (P06) checks it to defer
## checkpoints while enemies nearby are aware of the player.
var aware := false
var investigating := false
var last_known := Vector3.ZERO
var last_seen_tick := -100000
var strike_ready_tick := 0
var holds_token := false
var target_id := ""
var morale := 70.0
var reposition_sign := 1.0
var rng := RandomNumberGenerator.new()
var actor_id := ""
## The actor's CombatController.State at the last decide().
var controller_state: int = CombatController.State.LOCOMOTION

# Outputs, read by the actor every tick.
var move_target := Vector3.INF
var move_speed := 0.0
var face_point := Vector3.INF
var attack_request := ""


## seed_value: the actor passes Sim.DEFAULT_SEED ^ hash(entity_id), so every brain has its own
## deterministic stream and never draws from Sim.rng (which the crit rolls own).
func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	actor_id = p_actor_id
	ai = record.get("ai", {})
	attacks = record.get("attacks", [])
	attack_weights = record.get("attack_weights", [])
	morale = float(record.get("morale", 70.0))
	rng.seed = seed_value


func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else "State %d" % state


func _ticks(seconds: float) -> int:
	return int(roundf(seconds * TICK_RATE))


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_tick = now


func _in_state_s() -> float:
	return float(now - state_tick) / TICK_RATE


# --------------------------------------------------------------------------- perception

## snapshot: {"exists", "target_id", "alive", "position", "distance", "visible", "facing_deg",
## "target_radius", "target_forward", "target_height", "target_stage", "target_state",
## "self_health_frac"} (see EnemyActor._sense).
func perceive(tick: int, snapshot: Dictionary) -> void:
	now = tick
	perception = snapshot
	if snapshot.get("exists", false) and snapshot.get("alive", false) and snapshot.get("visible", false):
		target_id = snapshot.target_id
		last_known = snapshot.position
		last_seen_tick = tick
		if not aware:
			aware = true
			if state in [AIState.IDLE, AIState.PATROL]:
				_set_state(AIState.ALERT)
		investigating = false


## Hearing (an attack within hearing range) or being hit reveals the position.
func on_noise(tick: int, position: Vector3, source_id: String, certain: bool) -> void:
	now = tick
	if state in [AIState.DEAD, AIState.FLEE]:
		return
	last_known = position
	target_id = source_id
	if certain:
		last_seen_tick = tick
		aware = true
	if state in [AIState.IDLE, AIState.PATROL]:
		investigating = not certain
		_set_state(AIState.ALERT)


func on_ally_died() -> void:
	morale = maxf(0.0, morale - 10.0)


# --------------------------------------------------------------------------- decisions

## controller_state: CombatController.State of the actor. request_token() -> bool asks Sim for
## one of the target's attack tokens; release_token() gives it back.
func decide(tick: int, p_controller_state: int, my_position: Vector3, request_token: Callable,
		release_token: Callable) -> void:
	now = tick
	controller_state = p_controller_state
	attack_request = ""
	if controller_state == CombatController.State.DEAD:
		_release(release_token)
		_set_state(AIState.DEAD)
		_stop()
		return
	if controller_state == CombatController.State.STAGGERED:
		_release(release_token)
		_set_state(AIState.STAGGERED)
		_stop()
		return
	if state == AIState.STAGGERED:
		_set_state(AIState.APPROACH if aware else AIState.PATROL)
	if state != AIState.FLEE and morale < float(ai.get("flee_morale", 25.0)) and aware:
		_release(release_token)
		_set_state(AIState.FLEE)
	var memory_ok := (now - last_seen_tick) <= _ticks(float(ai.get("memory_s", 3.0)))
	var target_alive: bool = perception.get("alive", false)
	# Only what the enemy can see is used: while the target is hidden the brain works from the
	# last known position (memory), never from the target's live position.
	var seen: bool = perception.get("visible", false)
	var target_pos: Vector3 = perception.get("position", last_known) if seen else last_known
	var distance: float = perception.get("distance", INF) if seen else _flat_distance(my_position, last_known)
	match state:
		AIState.IDLE:
			_stop()
			if _in_state_s() >= float(ai.get("patrol_wait_s", 1.5)) and not patrol_points.is_empty():
				_set_state(AIState.PATROL)
		AIState.PATROL:
			face_point = Vector3.INF
			if patrol_points.is_empty():
				_set_state(AIState.IDLE)
				return
			var p := patrol_points[patrol_index % patrol_points.size()]
			move_target = p
			move_speed = 0.0  # actor maps 0 -> walk speed
			if _flat_distance(my_position, p) < 0.8:
				patrol_index = (patrol_index + 1) % patrol_points.size()
				_set_state(AIState.IDLE)
		AIState.ALERT:
			face_point = last_known
			if _in_state_s() < float(ai.get("notice_s", 0.6)):
				_stop_moving()
				return
			if aware and memory_ok and target_alive:
				_set_state(AIState.APPROACH)
				return
			# Investigate the last known position, then give up and patrol.
			move_target = last_known
			move_speed = 0.0
			if _flat_distance(my_position, last_known) < 1.5 or _in_state_s() > 8.0:
				aware = false
				investigating = false
				_set_state(AIState.PATROL)
		AIState.FLEE:
			_release(release_token)
			var flee_dir := my_position - target_pos
			flee_dir.y = 0.0
			move_target = my_position + (flee_dir.normalized() if flee_dir.length() > 0.1 else Vector3.BACK) * 8.0
			move_speed = -1.0
			face_point = Vector3.INF
			if _in_state_s() >= 4.0 and morale > float(ai.get("regroup_morale", 45.0)):
				_set_state(AIState.APPROACH)
		AIState.DEAD:
			_stop()
		_:
			_decide_engaged(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)


## The engaged states (APPROACH, ATTACK, RECOVER, REPOSITION, and any state the base does not
## handle itself). Default: the melee approach - run to the engage point beside the target,
## strike with a token when in range and facing it, pause between strikes, circle without one.
func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	match state:
		AIState.APPROACH:
			if not target_alive and perception.get("exists", false):
				_release(release_token)
				aware = false
				_set_state(AIState.PATROL)
				return
			if not memory_ok:
				_release(release_token)
				investigating = true
				aware = false
				_set_state(AIState.ALERT)
				return
			face_point = target_pos
			var attack_range := float(ai.get("attack_range_m", 1.2)) + float(perception.get("target_radius", 0.85))
			var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
			if distance <= attack_range:
				_stop_moving()
				if seen and now >= strike_ready_tick and facing_ok:
					if holds_token or request_token.call():
						holds_token = true
						attack_request = _choose_attack()
						_set_state(AIState.ATTACK)
					else:
						reposition_sign = 1.0 if rng.randf() < 0.5 else -1.0
						_set_state(AIState.REPOSITION)
			else:
				move_target = _engage_point(my_position, target_pos)
				move_speed = -1.0  # actor maps -1 -> run speed
		AIState.ATTACK:
			face_point = target_pos
			_stop_moving()
			if _attack_finished() and _in_state_s() > 0.05:
				var pause := rng.randf_range(float(ai.get("strike_pause_min_s", 0.8)),
					float(ai.get("strike_pause_max_s", 1.4)))
				strike_ready_tick = now + _ticks(pause)
				_set_state(AIState.RECOVER)
		AIState.RECOVER:
			# Pause between strikes; give ground slightly so the giant can punish or step in.
			face_point = target_pos
			var away := my_position - target_pos
			away.y = 0.0
			if away.length() < float(ai.get("attack_range_m", 1.2)) + float(perception.get("target_radius", 0.85)) - 0.2 and away.length() > 0.01:
				move_target = my_position + away.normalized() * 1.0
				move_speed = 0.0
			else:
				_stop_moving()
			if now >= strike_ready_tick:
				_release(release_token)
				_set_state(AIState.APPROACH)
		AIState.REPOSITION:
			face_point = target_pos
			var offset := my_position - target_pos
			offset.y = 0.0
			if offset.length() < 0.1:
				offset = Vector3.FORWARD
			var radius := float(ai.get("reposition_radius_m", 5.0))
			var tangent := offset.normalized().rotated(Vector3.UP, 0.6 * reposition_sign)
			move_target = target_pos + tangent * radius
			move_speed = 0.0
			if _in_state_s() > 1.5:
				_set_state(AIState.APPROACH)


## True once the requested attack is over (the controller left ATTACKING). Archetypes may widen
## the check (P04: abilities run in CASTING).
func _attack_finished() -> bool:
	return controller_state != CombatController.State.ATTACKING


## Called by the actor when a path makes no progress for path_fail_s: pick a new destination.
func on_path_failed(_my_position: Vector3) -> void:
	match state:
		AIState.PATROL:
			patrol_index = (patrol_index + 1) % maxi(1, patrol_points.size())
		AIState.APPROACH, AIState.REPOSITION:
			reposition_sign = -reposition_sign
			_set_state(AIState.REPOSITION)
		AIState.ALERT:
			aware = false
			_set_state(AIState.PATROL)
		_:
			_stop_moving()


## Weighted pick from the record's attacks (own RNG). Archetypes override to choose by range.
func _choose_attack() -> String:
	if attacks.is_empty():
		return ""
	if attack_weights.size() != attacks.size():
		return str(attacks[0])
	var total := 0.0
	for w: float in attack_weights:
		total += w
	var roll := rng.randf() * total
	for i in attacks.size():
		roll -= float(attack_weights[i])
		if roll <= 0.0:
			return str(attacks[i])
	return str(attacks[attacks.size() - 1])


## Approach the target's legs from the side we are already on.
func _engage_point(my_position: Vector3, target_pos: Vector3) -> Vector3:
	var from_target := my_position - target_pos
	from_target.y = 0.0
	if from_target.length() < 0.1:
		from_target = Vector3.FORWARD
	var r := float(ai.get("engage_distance_m", 1.0)) + float(perception.get("target_radius", 0.85))
	return target_pos + from_target.normalized() * r


func _release(release_token: Callable) -> void:
	if holds_token:
		holds_token = false
		release_token.call()


func _stop_moving() -> void:
	move_target = Vector3.INF
	move_speed = 0.0


func _stop() -> void:
	_stop_moving()
	face_point = Vector3.INF


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5).

## @anchor P04
## @anchor P07
## @anchor P09
## @anchor P10a
## @anchor P11a
## @anchor P11b
