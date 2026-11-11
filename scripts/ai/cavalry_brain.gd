class_name CavalryBrain
extends EnemyBrain
## Cavalry (enemy.cavalry, archetype cavalry; P32, plan M6-M9 §2.10, §5.11): a lancer on a warhorse
## that harasses a giant's legs with a charge cycle.
##   * Approach (APPROACH): it rides to a start point CHARGE_START_M from the target on its own side.
##     Inside the start window - from the charge's ai_min_range_m to the shorter of its ai_max_range_m
##     and the run's length less PASS_THROUGH_M, measured from the target's capsule surface, so the run
##     carries it through the giant's legs - it stops, turns to face the target and, seen, facing it
##     within ATTACK_FACING_DEG and ready, takes one of the target's attack tokens and charges.
##   * The charge (ATTACK): ability.cavalry_charge - a 1.0 s windup behind a 40 m line telegraph that
##     turns the rider onto the target for its first 70 % (tracking_fraction) and then commits, then a
##     straight run at 14 m/s for at most 40 m (EnemyActor's motion) whose hit is the horse's body sweep
##     (CavalryEnemy), once per charge, struck as a 4 m attacker. A sidestep off the line after the
##     commit, or a dodge's invulnerability, avoids it.
##   * The wheel (REPOSITION): the charge over, it gives its token back and rides on along the charge
##     line to a point tactics.wheel_min_m..wheel_max_m (30-50 m) beyond the target - wheel_resolver
##     makes it reachable within the tick's path-query budget (CavalryEnemy) - for at most WHEEL_MAX_S;
##     then, after RECHARGE_PAUSE_S, it approaches again from there: the re-charge.
## Caught close (inside the start window's near edge) it thrusts its lance when the lance fits the
## range and it faces the target (one of the target's tokens, then a pause in RECOVER), else it rides
## out to its start point. A start point it cannot reach (the actor's path check: no progress for
## ai.path_fail_s) turns its approach round the target, alternately to either side and farther each
## time (BLOCKED_TURN_DEG steps: -60, +60, -120, +120 ...), until a charge starts. Morale and flight
## are the base's (it flees at ai.flee_morale, 25).
## Outmatched (tactics.outmatched_ratio: every giant from stage 3) the cycle is its harass behaviour; it
## is the same cycle against a smaller one. A pure object like EnemyBrain: the actor feeds perception.
## M8 screenshot pass (V3): a rider rides for its start point only as far as its encounter's leash allows
## (leash_clamp, from the actor): a start point beyond the leash is brought inside it, and a rider that has
## reached that point (within LEASH_HOLD_M) holds there facing the target - and charges from there once the
## target comes within its start window. The war camp's riders, posted 60-68 m from the camp's centre
## under its 70 m leash, rode for a start point beyond it whenever the giant stood east of their pickets,
## were sent home by the leash, saw him again and rode out again: 60 leashes a minute and no charge.
## It holds only while the target stands beyond its window from there; a point inside the leash from which
## he is within the window is ridden to, and one that would leave him inside the window's near edge turns
## the approach round him to a start point the leash allows (or, with none, closes in to lance reach) - see
## _leashed_start. Held there, a rider stood beside the giant, out of lance reach and too close to
## charge, for good.

const CHARGE_TAG := "Charge"
## An approach aims at this centre distance from the target (inside the start window).
const CHARGE_START_M := 24.0
## The run should carry the rider at least this far past the target's surface.
const PASS_THROUGH_M := 12.0
## A rider inside the start window by this much stops there instead of riding to the start point.
const START_SLACK_M := 1.5
const WHEEL_ARRIVE_M := 3.0
## A wheel ends after this long even when its point was not reached (blocked, a long detour).
const WHEEL_MAX_S := 6.0
## The pause after a wheel (or a lance) before the next charge may start.
const RECHARGE_PAUSE_S := 0.8
## While the wheel point search waits for the path-query budget the rider keeps riding this far ahead.
const WHEEL_LEAD_M := 10.0
## An unreachable start point turns the approach this far round the target.
const BLOCKED_TURN_DEG := 60.0
## M8 screenshot pass (V3): a start point the leash brought inside it counts as reached this close (the
## horse runs at 13 m/s and stops within about 4 m): the rider holds there.
const LEASH_HOLD_M := 5.0
## M8 screenshot pass (V3): a start point the leash would leave too close to the target turns the approach
## round him in steps this large (see _leashed_start).
const LEASH_TURN_STEP_DEG := 30.0

## wheel_resolver(from: Vector3, threat: Vector3, dir: Vector3, distance: float) -> Vector3: a reachable
## point `distance` m from `threat` along `dir` (or near it); Vector3.INF when none - or, with
## nav_search_pending set, when the search waits for the path-query budget.
var wheel_resolver := Callable()
## M8 screenshot pass (V3): leash_clamp(point: Vector3) -> Vector3 - `point` brought inside the rider's
## encounter leash (unchanged where it has none); invalid = no leash (tests).
var leash_clamp := Callable()
## True while the leash keeps the approach short of its start point (tests, debug).
var held_by_leash := false
## Degrees the leash turned the approach round the target this decision (0: not turned; tests, debug).
var leash_turn_deg := 0.0
## "approach" | "charge" | "lance" | "wheel" (tests, debug).
var cycle := "approach"
## Where the current wheel rides to (Vector3.INF until chosen).
var wheel_point := Vector3.INF
## Charges requested and wheels finished (tests, debug).
var charges := 0
var wheels := 0
var _charge_dir := Vector3.ZERO
var _wheel_distance := 0.0
var _charge_id := ""
var _lance_id := ""
## Degrees the approach is turned round the target after blocked start points (0 once a charge starts),
## and how many start points were blocked since the last charge.
var _start_turn_deg := 0.0
var _blocked_starts := 0


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	for id: Variant in attacks:
		var a := GameData.get_action(str(id))
		if a == null:
			continue
		if a.has_tag(CHARGE_TAG):
			_charge_id = a.id
		elif _lance_id == "":
			_lance_id = a.id


## The charge's action id ("" when the record has none).
func charge_id() -> String:
	return _charge_id


## The start window (from the target's capsule surface): [the charge's ai_min_range_m, the shorter of its
## ai_max_range_m and its run's length less PASS_THROUGH_M].
func start_window() -> Vector2:
	var band: Vector2 = _attack_ranges.get(_charge_id, Vector2(8.0, 38.0))
	var run := 40.0
	var a := GameData.get_action(_charge_id)
	if a != null and typeof(a.param("motion")) == TYPE_DICTIONARY:
		run = float((a.param("motion") as Dictionary).get("max_distance_m", run))
	return Vector2(band.x, minf(band.y if band.y < INF else run, run - PASS_THROUGH_M))


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if not target_alive and perception.get("exists", false):
		_end_cycle(release_token)
		aware = false
		_set_state(AIState.PATROL)
		return
	if not memory_ok:
		_end_cycle(release_token)
		investigating = true
		aware = false
		_set_state(AIState.ALERT)
		return
	if _decide_outmatched(outmatched_behavior(), my_position, target_pos, distance, seen, memory_ok,
			target_alive, request_token, release_token):
		return
	_charge_cycle(my_position, target_pos, distance, seen, request_token, release_token)


## Harass (outmatched): the charge cycle.
func _decide_harass(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		_memory_ok: bool, _target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	_charge_cycle(my_position, target_pos, distance, seen, request_token, release_token)
	return true


func _charge_cycle(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		request_token: Callable, release_token: Callable) -> void:
	match state:
		AIState.ATTACK:
			_attacking(my_position, target_pos, release_token)
		AIState.REPOSITION:
			_wheeling(my_position, target_pos)
		AIState.RECOVER:
			face_point = target_pos
			_stop_moving()
			if now >= strike_ready_tick:
				_set_state(AIState.APPROACH)
		_:
			_approach(my_position, target_pos, distance, seen, request_token)


func _approach(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool, request_token: Callable) -> void:
	if state != AIState.APPROACH:
		_set_state(AIState.APPROACH)
	cycle = "approach"
	face_point = target_pos
	var radius := float(perception.get("target_radius", 0.85))
	var edge := distance - radius
	var window := start_window()
	var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
	var ready := seen and now >= strike_ready_tick and facing_ok
	var lance_band: Vector2 = _attack_ranges.get(_lance_id, Vector2(0.0, -1.0))
	if _lance_id != "" and edge <= lance_band.y and ready:
		_stop_moving()
		if holds_token or request_token.call():
			holds_token = true
			attack_request = _lance_id
			cycle = "lance"
			_set_state(AIState.ATTACK)
		return
	if _charge_id != "" and edge >= window.x and edge <= window.y:
		if ready:
			if holds_token or request_token.call():
				holds_token = true
				attack_request = _charge_id
				_charge_dir = Vector3(target_pos.x - my_position.x, 0.0, target_pos.z - my_position.z)
				_charge_dir = _charge_dir.normalized() if _charge_dir.length_squared() > 1e-6 else Vector3.FORWARD
				cycle = "charge"
				charges += 1
				_start_turn_deg = 0.0
				_blocked_starts = 0
				_set_state(AIState.ATTACK)
				_stop_moving()
				return
		if edge >= window.x + START_SLACK_M and edge <= window.y - START_SLACK_M:
			_stop_moving()   # in the window: turn to face it (or wait for a token) where it stands
			return
	var away := Vector3(my_position.x - target_pos.x, 0.0, my_position.z - target_pos.z)
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	if _start_turn_deg != 0.0:
		away = away.rotated(Vector3.UP, deg_to_rad(_start_turn_deg))
	var start := clampf(CHARGE_START_M, radius + window.x + START_SLACK_M, radius + window.y - START_SLACK_M)
	var point := target_pos + away.normalized() * start
	held_by_leash = false
	leash_turn_deg = 0.0
	if leash_clamp.is_valid():
		point = _leashed_start(my_position, target_pos, away.normalized(), start, radius, window, lance_band.y)
		if point == Vector3.INF:
			_stop_moving()   # at the leash's edge: it holds, facing the target, until he comes within its window
			return
	move_target = point
	move_speed = -1.0


## M8 screenshot pass (V3): where an approach rides when its encounter has a leash (leash_clamp); its start
## point is `start` m from the target on bearing `dir`. Vector3.INF = hold where it stands.
##   * A start point inside the leash: it, unchanged.
##   * Else the start point brought inside the leash, when the target is within the window from there (by
##     START_SLACK_M): it rides there, and on to it (it never holds short of it).
##   * Else, when the target stands beyond the window from there: it rides there and, once there (within
##     LEASH_HOLD_M), holds, facing him, until he comes within its window.
##   * Else - the target would be inside the window's near edge from there (he stands near the leash's edge
##     on this side; the rider was sent home past him) - it turns its approach round him to the nearest
##     bearing, alternately to either side and farther each time (LEASH_TURN_STEP_DEG; the side with more
##     room first), whose start point, brought inside the leash, is within the window; with none (a leash too
##     small for a charge) it closes in to lance reach. A rider held there stood beside the giant, facing
##     him, out of lance reach and too close to charge, for good (the M8 screenshot pass's fix-up).
func _leashed_start(my_position: Vector3, target_pos: Vector3, dir: Vector3, start: float, radius: float,
		window: Vector2, lance_reach_m: float) -> Vector3:
	var point := target_pos + dir * start
	var inside: Vector3 = leash_clamp.call(point)
	if _flat_distance(inside, point) <= 0.01:
		return point
	held_by_leash = true
	var near_m := radius + window.x + START_SLACK_M
	var far_m := radius + window.y - START_SLACK_M
	var reach := _flat_distance(inside, target_pos)
	if reach > far_m:
		return Vector3.INF if _flat_distance(my_position, inside) <= LEASH_HOLD_M else inside
	if reach >= near_m:
		return inside
	var steps := int(round(180.0 / LEASH_TURN_STEP_DEG))
	for k in range(1, steps + 1):
		var best := Vector3.INF
		var best_reach := -1.0
		for side: float in ([-1.0, 1.0] if k < steps else [1.0]):
			var deg := side * k * LEASH_TURN_STEP_DEG
			var q: Vector3 = leash_clamp.call(target_pos + dir.rotated(Vector3.UP, deg_to_rad(deg)) * start)
			var r := _flat_distance(q, target_pos)
			if r >= near_m and r <= far_m and r > best_reach + 0.01:
				best = q
				best_reach = r
				leash_turn_deg = deg
		if best != Vector3.INF:
			return best
	leash_turn_deg = 0.0
	return leash_clamp.call(target_pos + dir * (radius + maxf(lance_reach_m, 0.0) * 0.5))


## ATTACK: the charge or the lance runs (the actor turns during its tracked windup); once it is over
## the token goes back and the rider wheels (after a charge) or pauses (after the lance).
func _attacking(my_position: Vector3, target_pos: Vector3, release_token: Callable) -> void:
	face_point = target_pos
	_stop_moving()
	if not _attack_finished() or _in_state_s() <= 0.05:
		return
	_release(release_token)
	if cycle == "charge":
		_begin_wheel(my_position, target_pos)
		return
	cycle = "approach"
	strike_ready_tick = now + _ticks(rng.randf_range(float(ai.get("strike_pause_min_s", 0.6)),
		float(ai.get("strike_pause_max_s", 1.2))))
	_set_state(AIState.RECOVER)


func _begin_wheel(my_position: Vector3, target_pos: Vector3) -> void:
	cycle = "wheel"
	wheel_point = Vector3.INF
	_wheel_distance = rng.randf_range(float(tactics.get("wheel_min_m", 30.0)), float(tactics.get("wheel_max_m", 50.0)))
	if _charge_dir.length_squared() < 1e-6:
		var away := Vector3(my_position.x - target_pos.x, 0.0, my_position.z - target_pos.z)
		_charge_dir = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
	_set_state(AIState.REPOSITION)


## REPOSITION: ride on to the wheel point (asking wheel_resolver for it first), then turn back.
func _wheeling(my_position: Vector3, target_pos: Vector3) -> void:
	face_point = Vector3.INF
	if wheel_point == Vector3.INF:
		var want := target_pos + _charge_dir * _wheel_distance
		if wheel_resolver.is_valid():
			nav_search_pending = false
			wheel_point = wheel_resolver.call(my_position, target_pos, _charge_dir, _wheel_distance)
			if wheel_point == Vector3.INF and nav_search_pending:
				move_target = my_position + _charge_dir * WHEEL_LEAD_M   # the search waits: ride on
				move_speed = -1.0
				return
			if wheel_point == Vector3.INF:
				wheel_point = my_position   # nowhere to ride on to: turn back here
		else:
			wheel_point = want
	move_target = wheel_point
	move_speed = -1.0
	if _flat_distance(my_position, wheel_point) <= WHEEL_ARRIVE_M or _in_state_s() >= WHEEL_MAX_S:
		wheels += 1
		cycle = "approach"
		wheel_point = Vector3.INF
		strike_ready_tick = now + _ticks(RECHARGE_PAUSE_S)
		_set_state(AIState.APPROACH)


func _end_cycle(release_token: Callable) -> void:
	_release(release_token)
	cycle = "approach"
	wheel_point = Vector3.INF


func on_path_failed(my_position: Vector3) -> void:
	match state:
		AIState.REPOSITION:
			_in_wheel_blocked(my_position)
			return
		AIState.APPROACH:
			# The start point is out of reach: try another bearing, alternately to either side and
			# farther round each time (-60, +60, -120, +120 ...; the base's answer, a REPOSITION, is this
			# brain's wheel).
			_blocked_starts += 1
			var k := _blocked_starts
			_start_turn_deg = wrapf(BLOCKED_TURN_DEG * ((k + 1) >> 1) * (-1.0 if k % 2 == 1 else 1.0), -180.0, 180.0)
			return
	super(my_position)


## A wheel that makes no progress ends where the rider stands: it turns back from there.
func _in_wheel_blocked(my_position: Vector3) -> void:
	wheel_point = my_position
