class_name TargetingRules
extends RefCounted
## Pure lock-on math (spec section 5).

const W_ALIGNMENT := 0.55
const W_PROXIMITY := 0.30
const W_THREAT := 0.15


## Q = 0.55 * alignment + 0.30 * proximity + 0.15 * threat, each term in 0..1.
## alignment = max(0, dot(aim, direction)); proximity = 1 - clamp(distance / range, 0, 1).
static func score(aim: Vector3, direction: Vector3, distance: float, range_m: float,
		threat: float) -> float:
	var alignment := 0.0
	if aim.length_squared() > 1e-8 and direction.length_squared() > 1e-8:
		alignment = maxf(0.0, aim.normalized().dot(direction.normalized()))
	var proximity := 1.0 - clampf(distance / maxf(range_m, 0.001), 0.0, 1.0)
	return W_ALIGNMENT * alignment + W_PROXIMITY * proximity + W_THREAT * clampf(threat, 0.0, 1.0)


## Horizontal cone test (pitch is ignored so a giant looking down still locks nearby targets).
static func in_cone(aim: Vector3, direction: Vector3, half_angle_deg: float) -> bool:
	var a := Vector3(aim.x, 0.0, aim.z)
	var d := Vector3(direction.x, 0.0, direction.z)
	if d.length_squared() < 1e-8:
		return true
	if a.length_squared() < 1e-8:
		return false
	return rad_to_deg(a.angle_to(d)) <= half_angle_deg + 1e-4


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Signed yaw difference (radians, -PI..PI) from `from_yaw` to `to_yaw`.
static func yaw_delta(from_yaw: float, to_yaw: float) -> float:
	return wrapf(to_yaw - from_yaw, -PI, PI)


## Yaw (radians) that faces `direction`, using Godot's convention that yaw 0 faces -Z.
static func yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
