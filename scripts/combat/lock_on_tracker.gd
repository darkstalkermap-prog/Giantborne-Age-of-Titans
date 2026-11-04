class_name LockOnTracker
extends RefCounted
## Hard lock-on state (spec section 5). Pure logic: the owner supplies candidate snapshots
## gathered with engine queries (visibility rays, screen projection).
##
## Candidate snapshot: {"id", "direction" (from aim origin), "distance", "threat",
##                      "visible", "alive", "lockable", "screen" (Vector2, optional)}

const RELEASE_RANGE_FACTOR := 1.25
const OBSTRUCTION_RELEASE_S := 0.75
const SWITCH_DEBOUNCE_S := 0.20

var target_id := ""
var obstructed_s := 0.0
var range_m := 35.0
var half_angle_deg := 60.0
var _last_switch_s := -1000.0


func is_locked() -> bool:
	return target_id != ""


func eligible(c: Dictionary, aim: Vector3) -> bool:
	return c.get("alive", false) and c.get("lockable", false) and c.get("visible", false) \
		and float(c.get("distance", INF)) <= range_m \
		and TargetingRules.in_cone(aim, c.get("direction", Vector3.ZERO), half_angle_deg)


## Picks the best eligible candidate by Q score. Returns its id or "".
func best_candidate(candidates: Array, aim: Vector3) -> String:
	var best_id := ""
	var best_q := -1.0
	for c: Dictionary in candidates:
		if not eligible(c, aim):
			continue
		var q := TargetingRules.score(TargetingRules.flat(aim), TargetingRules.flat(c.direction),
			float(c.distance), range_m, float(c.get("threat", 0.0)))
		if q > best_q + 1e-9 or (absf(q - best_q) <= 1e-9 and str(c.id) < best_id):
			best_q = q
			best_id = str(c.id)
	return best_id


func acquire(candidates: Array, aim: Vector3) -> String:
	target_id = best_candidate(candidates, aim)
	obstructed_s = 0.0
	return target_id


func release() -> void:
	target_id = ""
	obstructed_s = 0.0


## Per-tick maintenance. info describes the current target (same keys as a candidate,
## plus "exists"). Returns a release reason, or "" if the lock holds.
func update(dt: float, info: Dictionary) -> String:
	if target_id == "":
		return ""
	if not info.get("exists", false):
		release()
		return "invalid"
	if not info.get("alive", false):
		release()
		return "target_died"
	if not info.get("lockable", false):
		release()
		return "invalid"
	if float(info.get("distance", INF)) > range_m * RELEASE_RANGE_FACTOR:
		release()
		return "out_of_range"
	if info.get("visible", false):
		obstructed_s = 0.0
	else:
		obstructed_s += dt
		if obstructed_s > OBSTRUCTION_RELEASE_S + 1e-6:
			release()
			return "obstructed"
	return ""


## Directional switch: nearest visible candidate on the requested screen side of the current
## target. direction: -1 = left, +1 = right. Debounced to one switch per 0.20 s.
func switch_target(direction: int, candidates: Array, current_screen: Vector2, aim: Vector3,
		time_s: float) -> bool:
	if target_id == "" or time_s - _last_switch_s < SWITCH_DEBOUNCE_S - 1e-6:
		return false
	var best_id := ""
	var best_dist := INF
	for c: Dictionary in candidates:
		if str(c.id) == target_id or not c.has("screen"):
			continue
		if not (c.get("alive", false) and c.get("lockable", false) and c.get("visible", false)):
			continue
		if float(c.get("distance", INF)) > range_m:
			continue
		var screen: Vector2 = c.screen
		var dx := screen.x - current_screen.x
		if (direction < 0 and dx >= 0.0) or (direction > 0 and dx <= 0.0):
			continue
		var d := screen.distance_to(current_screen)
		if d < best_dist - 1e-6 or (absf(d - best_dist) <= 1e-6 and str(c.id) < best_id):
			best_dist = d
			best_id = str(c.id)
	if best_id == "":
		return false
	target_id = best_id
	obstructed_s = 0.0
	_last_switch_s = time_s
	return true
