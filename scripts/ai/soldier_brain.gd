class_name SoldierBrain
extends RefCounted
## Finite-state AI for the melee Soldier archetype (spec section 10).
##
## States: Idle, Patrol, Alert, Approach, Attack, Recover, Reposition, Flee, Staggered, Dead.
## Perception runs at 5 Hz, tactical decisions at 10 Hz (driven by the owning actor);
## movement is applied every tick by the actor. The brain only decides: a move target and
## speed, a point to face, and which attack to request. Engine queries (line of sight,
## distances) arrive as a perception snapshot from the actor.
##
## Soldier tactics: guard the front, approach the giant's legs, pause between strikes. At
## most `max_attackers` enemies hold attack tokens on one target; the rest reposition.
## Losing sight leads to investigating the last known position for `memory_s`, then patrol.

enum AIState { IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION, FLEE, STAGGERED, DEAD }
const STATE_NAMES := ["Idle", "Patrol", "Alert", "Approach", "Attack", "Recover", "Reposition",
	"Flee", "Staggered", "Dead"]
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

# Outputs, read by the actor every tick.
var move_target := Vector3.INF
var move_speed := 0.0
var face_point := Vector3.INF
var attack_request := ""


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	actor_id = p_actor_id
	ai = record.get("ai", {})
	attacks = record.get("attacks", [])
	attack_weights = record.get("attack_weights", [])
	morale = float(record.get("morale", 70.0))
	rng.seed = seed_value


func state_name() -> String:
	return STATE_NAMES[state]


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

## snapshot: {"exists", "target_id", "alive", "position", "distance", "visible", "facing_deg"}
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

## controller_state: CombatController.State of the actor. Returns true when the attack token
## should be released (the actor talks to Sim).
func decide(tick: int, controller_state: int, my_position: Vector3, request_token: Callable,
		release_token: Callable) -> void:
	now = tick
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
	var distance: float = perception.get("distance", INF)
	var target_pos: Vector3 = perception.get("position", last_known)
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
				if now >= strike_ready_tick and facing_ok:
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
			if controller_state != CombatController.State.ATTACKING and _in_state_s() > 0.05:
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


## Called by the actor when a path makes no progress for path_fail_s: pick a new destination.
func on_path_failed(my_position: Vector3) -> void:
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


## Approach the giant's legs from the side we are already on.
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
