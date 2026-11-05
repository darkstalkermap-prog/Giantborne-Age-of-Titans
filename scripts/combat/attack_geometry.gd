class_name AttackGeometry
extends RefCounted
## Shared attack geometry. The hit sweep (gameplay) and the procedural arm animation
## (presentation) both call these functions, so the swing the player sees is the swing that
## is tested for hits. Angles: yaw > 0 turns toward the actor's right, pitch > 0 points up.

const MAX_PITCH_DEG := 80.0


## Actor-local unit direction (Godot convention: forward is -Z, right is +X, up is +Y).
static func local_direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(clampf(pitch_deg, -89.0, 89.0))
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## (yaw, pitch) along the active arc, f in 0..1. Yaw is linear in f. Pitch is linear from
## pitch_start_deg to pitch_end_deg, unless the arc has pitch_mid_deg: then it follows the
## quadratic through the start, pitch_mid_deg at f = 0.5 and the end, so a swing can dip through
## the front (where a small target stands at the giant's feet) and rise again toward its far
## end (where a tall target stands farther from the shoulder).
static func arc_point(action: ActionDef, f: float) -> Vector2:
	var arc := action.arc
	var p0 := float(arc.get("pitch_start_deg", 0.0))
	var p1 := float(arc.get("pitch_end_deg", 0.0))
	var pitch := lerpf(p0, p1, f)
	if arc.has("pitch_mid_deg"):
		var pm := float(arc.pitch_mid_deg)
		pitch = p0 * (1.0 - f) * (1.0 - 2.0 * f) + pm * 4.0 * f * (1.0 - f) + p1 * f * (2.0 * f - 1.0)
	return Vector2(lerpf(float(arc.get("yaw_start_deg", 0.0)), float(arc.get("yaw_end_deg", 0.0)), f), pitch)


## Arm pose for presentation at any point of an action's timeline.
static func pose_for(action: ActionDef, phase: int, phase_fraction: float, idle: Vector2) -> Vector2:
	if action == null or action.arc.is_empty():
		return idle
	var arc := action.arc
	var windup := Vector2(float(arc.windup_yaw_deg), float(arc.windup_pitch_deg))
	var start := Vector2(float(arc.yaw_start_deg), float(arc.pitch_start_deg))
	var finish := Vector2(float(arc.yaw_end_deg), float(arc.pitch_end_deg))
	var f := clampf(phase_fraction, 0.0, 1.0)
	match phase:
		ActionDef.Phase.WINDUP:
			if f < 0.75:
				var t := f / 0.75
				return idle.lerp(windup, 1.0 - (1.0 - t) * (1.0 - t))
			return windup.lerp(start, (f - 0.75) / 0.25)
		ActionDef.Phase.ACTIVE:
			return arc_point(action, f)
		ActionDef.Phase.RECOVERY:
			return finish.lerp(idle, smoothstep(0.0, 1.0, f))
	return idle


## Weapon segment in actor-local space: from r0 to r1 metres along `direction` from `pivot`.
static func segment_local(pivot: Vector3, direction: Vector3, r0: float, r1: float) -> PackedVector3Array:
	return PackedVector3Array([pivot + direction * r0, pivot + direction * r1])


static func closest_point_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-10:
		return a
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t
