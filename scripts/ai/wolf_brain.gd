class_name WolfBrain
extends EnemyBrain
## Pack hunter (spec 10, plan §3.4): the wolf circles to a flank at +/- tactics.flank_angle_deg
## from the giant's facing, lunges from its lunge band (2.5-5.5 m from a stage-1 giant's centre)
## and bites up close, holding one of the target's attack tokens - the same two-token pool every
## melee enemy shares. Counterplay: dodge the telegraphed lunge, then punish its long recovery.
##
## Outmatched (the giant at least tactics.outmatched_ratio times taller: stage 2 and up) the
## wolf harasses instead: it attacks only from behind (more than HARASS_REAR_DEG from the
## giant's facing) and backs off HARASS_RETREAT_M after every attack before it circles again.
##
## Attacks are chosen by range (ai_min_range_m / ai_max_range_m of each action, measured from
## the target's capsule surface). A pure object like EnemyBrain: the actor feeds perception.

const FLANKED_DEG := 60.0
## Without the flank after this long, a (not outmatched) wolf attacks from where it is.
const FLANK_PATIENCE_S := 3.0
## Each move along the circle around the target turns at most this far.
const ORBIT_STEP_DEG := 50.0
const HARASS_REAR_DEG := 100.0
const HARASS_FLANK_DEG := 150.0
const HARASS_RETREAT_M := 8.0
const HARASS_RETREAT_MAX_S := 3.0
const REPOSITION_S := 1.2

## Which way round the target the wolf circles (+1 counter-clockwise seen from above).
var flank_sign := 1.0
## True while a harassing wolf backs off after an attack.
var retreating := false
var _side_chosen := false


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


## Signed angle (degrees) of `from_target` (target -> wolf) from the target's facing: 0 = in
## front of it, +/-180 = right behind it.
static func angle_from_facing(target_forward: Vector3, from_target: Vector3) -> float:
	var f := Vector3(target_forward.x, 0.0, target_forward.z)
	var v := Vector3(from_target.x, 0.0, from_target.z)
	if f.length_squared() < 1e-8 or v.length_squared() < 1e-8:
		return 0.0
	return rad_to_deg(f.normalized().signed_angle_to(v.normalized(), Vector3.UP))


## The wolf's current angle around the target (see angle_from_facing), from the perception.
func flank_angle(my_position: Vector3, target_pos: Vector3) -> float:
	return angle_from_facing(perception.get("target_forward", Vector3.FORWARD), my_position - target_pos)


## Centre-to-centre distance the wolf circles at: the middle of its lunge band (the longest-
## reaching attack's band), or tactics.lunge_range_m - 1 m without range data.
func stand_off_m() -> float:
	var radius := float(perception.get("target_radius", 0.85))
	var band := _lunge_band()
	if band.y <= 0.0 or band.y == INF:
		return maxf(float(tactics.get("lunge_range_m", 5.5)) - 1.0, radius + 1.0)
	return radius + (band.x + band.y) * 0.5


## The range band (from the target's capsule surface) of the attack that reaches farthest.
func _lunge_band() -> Vector2:
	var best := Vector2(0.0, 0.0)
	for id: Variant in attacks:
		var r: Vector2 = _attack_ranges.get(str(id), Vector2(0.0, INF))
		if r.y < INF and r.y > best.y:
			best = r
	return best


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if _decide_outmatched(outmatched_behavior(), my_position, target_pos, distance, seen, memory_ok,
			target_alive, request_token, release_token):
		return
	retreating = false
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
			_hunt(my_position, target_pos, distance, seen, request_token, false)
		AIState.ATTACK:
			_attack_state(target_pos)
		AIState.RECOVER:
			face_point = target_pos
			_stop_moving()
			if now >= strike_ready_tick:
				# Hit and run: give the token back and circle for a moment, so the pack (and
				# the soldiers sharing the pool) take turns.
				_release(release_token)
				reposition_sign = flank_sign
				_set_state(AIState.REPOSITION)
		AIState.REPOSITION:
			_circle(my_position, target_pos)
			if _in_state_s() > REPOSITION_S:
				_set_state(AIState.APPROACH)
		_:
			_set_state(AIState.APPROACH)


## Harass (outmatched): strike only from behind, back off HARASS_RETREAT_M after each attack.
func _decide_harass(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	if not target_alive or not memory_ok:
		retreating = false
		return false   # the normal rules handle a lost or dead target
	match state:
		AIState.ATTACK:
			if _attack_state(target_pos):
				_release(release_token)
				retreating = true
				_set_state(AIState.REPOSITION)
			return true
		AIState.REPOSITION, AIState.RECOVER:
			if not retreating:
				_set_state(AIState.APPROACH)
			else:
				_retreat(my_position, target_pos, distance)
				return true
	if state != AIState.APPROACH:
		_set_state(AIState.APPROACH)
	_hunt(my_position, target_pos, distance, seen, request_token, true)
	return true


## ATTACK: hold still, facing the target, until the attack is over; then a pause in RECOVER.
## Returns true on the decision the attack ended.
func _attack_state(target_pos: Vector3) -> bool:
	face_point = target_pos
	_stop_moving()
	if _attack_finished() and _in_state_s() > 0.05:
		strike_ready_tick = now + _ticks(rng.randf_range(float(ai.get("strike_pause_min_s", 0.6)),
			float(ai.get("strike_pause_max_s", 1.2))))
		_set_state(AIState.RECOVER)
		return true
	return false


## Circle to the flank (harass: to the rear), then strike with a token when an attack fits the
## range: the lunge from its band, the bite up close.
func _hunt(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		request_token: Callable, harass: bool) -> void:
	var angle := flank_angle(my_position, target_pos)
	if not _side_chosen:
		flank_sign = 1.0 if angle >= 0.0 else -1.0
		_side_chosen = true
	var needed := HARASS_REAR_DEG if harass else FLANKED_DEG
	var flanked := absf(angle) > needed
	var impatient := not harass and _in_state_s() >= FLANK_PATIENCE_S
	var edge := distance - float(perception.get("target_radius", 0.85))
	var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
	if seen and (flanked or impatient) and now >= strike_ready_tick:
		var id := choose_attack_in_range(edge)
		if id != "":
			face_point = target_pos
			if not facing_ok:
				_stop_moving()
				return
			if holds_token or request_token.call():
				holds_token = true
				attack_request = id
				_set_state(AIState.ATTACK)
			else:
				reposition_sign = flank_sign
				_set_state(AIState.REPOSITION)
			return
	var want := float(tactics.get("flank_angle_deg", 100.0))
	if harass:
		want = maxf(want, HARASS_FLANK_DEG)
	if flanked or impatient:
		# In position (or out of patience) but no attack fits the range: beyond the lunge band
		# close in to it; between the bite and the lunge bands step in to bite.
		face_point = target_pos
		var bearing := Vector3(my_position.x - target_pos.x, 0.0, my_position.z - target_pos.z)
		if bearing.length() < 0.1:
			bearing = Vector3.BACK
		var keep := stand_off_m() if edge > _lunge_band().y else \
			float(perception.get("target_radius", 0.85)) + float(ai.get("engage_distance_m", 0.5))
		move_target = target_pos + bearing.normalized() * keep
		move_speed = -1.0
		return
	# Orbit toward the flank in steps, so the path never cuts through the target's body.
	var goal := clampf(want * flank_sign - angle, -ORBIT_STEP_DEG, ORBIT_STEP_DEG) + angle
	var fwd: Vector3 = perception.get("target_forward", Vector3.FORWARD)
	move_target = target_pos + Vector3(fwd.x, 0.0, fwd.z).normalized().rotated(Vector3.UP, deg_to_rad(goal)) \
		* stand_off_m()
	move_speed = -1.0
	face_point = Vector3.INF


## Without a token: circle at the reposition radius, facing the target.
func _circle(my_position: Vector3, target_pos: Vector3) -> void:
	face_point = target_pos
	var offset := my_position - target_pos
	offset.y = 0.0
	if offset.length() < 0.1:
		offset = Vector3.FORWARD
	var radius := float(ai.get("reposition_radius_m", 6.0))
	move_target = target_pos + offset.normalized().rotated(Vector3.UP, 0.6 * reposition_sign) * radius
	move_speed = -1.0


## Harass retreat: run HARASS_RETREAT_M clear of the target (at most HARASS_RETREAT_MAX_S), then
## circle back in.
func _retreat(my_position: Vector3, target_pos: Vector3, distance: float) -> void:
	face_point = Vector3.INF
	var away := my_position - target_pos
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	var radius := float(perception.get("target_radius", 0.85))
	move_target = target_pos + away.normalized() * (HARASS_RETREAT_M + radius)
	move_speed = -1.0
	if distance >= HARASS_RETREAT_M + radius - 0.5 or _in_state_s() >= HARASS_RETREAT_MAX_S:
		retreating = false
		_side_chosen = false
		_set_state(AIState.APPROACH)


## Attacks by range: the weighted pick among those that fit; otherwise the closest-range one.
func _choose_attack() -> String:
	var edge := float(perception.get("distance", 0.0)) - float(perception.get("target_radius", 0.85))
	var id := choose_attack_in_range(edge)
	return id if id != "" else super()
