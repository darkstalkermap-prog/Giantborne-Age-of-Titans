class_name CameraRig
extends Node3D
## Third-person and first-person camera for the player (spec section 5).
##
## One player entity owns both modes; switching never touches gameplay state. Third person
## uses a collision-tested follow arm: a sphere is swept from the pivot to the shoulder point
## and on to the desired camera position; the arm retracts instantly at obstacles and
## restores smoothly. First person sits at 92% of the giant's height with the head hidden
## (render layer 2 is culled). Shake and head bob are independently scalable in Settings.
##
## Growth (P05): apply_profile() switches to another stage's profile, keeping the zoom fraction
## between the stage's zoom limits and never snapping the arm (it restores at RESTORE_SPEED).
## The lock orbit distances scale with the profile's camera_orbit_scale. In third person the
## camera also hides render layer 2 (head, chest, belt) while the arm is retracted so far that
## the giant's own head would cover the screen centre (hides_head()).

enum Mode { THIRD_PERSON, FIRST_PERSON }

const TP_PITCH_MIN := -70.0
const TP_PITCH_MAX := 40.0
const FP_PITCH_MIN := -85.0
const FP_PITCH_MAX := 85.0
const COLLISION_RADIUS := 0.35
const RESTORE_SPEED := 6.0          ## m/s the arm extends back after an obstruction clears
const LOCK_PITCH_MIN := -35.0       ## lock framing never looks steeply up at big targets
const LOCK_PITCH_MAX := 8.0
const LOCK_SMALL_PITCH_MIN := -48.0 ## small targets at the giant's feet may be viewed from above
const LOCK_ORBIT_DEG := 32.0        ## side orbit so a small, close target is not hidden by the giant
const FP_ASSIST_DEG_S := 20.0
const FP_ASSIST_CONE_DEG := 25.0
const FP_HIDDEN_LAYER := 2           ## render layer bit for head geometry
const LOCK_ORBIT_FAR_M := 12.0       ## the lock orbit ramps in between these target distances,
const LOCK_ORBIT_NEAR_M := 3.0       ## times the profile's camera_orbit_scale
## Third person hides layer 2 while the arm is shorter than this times the capsule radius (a
## wall right behind the giant) ...
const HEAD_HIDE_ARM_RADII := 1.2
## ... or while the screen-centre ray passes closer than this times the capsule radius beside
## the pivot (the camera is pressed close behind the head, e.g. under a low ceiling).
const HEAD_CLEAR_RADII := 0.5
const CULL_ALL := 0xFFFFF
const CULL_NO_HEAD := 0xFFFFF & ~(1 << (FP_HIDDEN_LAYER - 1))

var mode: int = Mode.THIRD_PERSON
var yaw := 0.0                       ## radians, Godot convention (0 faces -Z)
var pitch := deg_to_rad(-18.0)
var player: Node3D = null
var profile: Dictionary = {}
var desired_distance := 6.5
var current_distance := 6.5
var lock_target: CombatEntity = null
var obstructed := false
## True while third person hides render layer 2 (see hides_head()); always false in first
## person, where layer 2 is hidden anyway.
var head_hidden := false
var _shake := 0.0
var _time := 0.0
var _bob_phase := 0.0
var _sphere := SphereShape3D.new()

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	top_level = true
	process_priority = -10  # update before the HUD projects markers with this camera
	_sphere.radius = COLLISION_RADIUS
	Settings.changed.connect(_on_settings_changed)


func setup(p_player: Node3D, p_profile: Dictionary) -> void:
	player = p_player
	profile = p_profile
	desired_distance = float(profile.get("camera_distance_m", 6.5))
	current_distance = desired_distance
	camera.fov = float(Settings.get_value("fov_deg"))
	camera.near = 0.05
	camera.far = level_far_plane_m()   # P24a: the level's camera_far_m (800 m unless its preset says)
	camera.current = true
	set_mode(int(Settings.session.get("camera_mode", Mode.THIRD_PERSON)), false)
	_update_transform(0.0)


func toggle_mode() -> void:
	set_mode(Mode.FIRST_PERSON if mode == Mode.THIRD_PERSON else Mode.THIRD_PERSON)


func set_mode(new_mode: int, announce := true) -> void:
	mode = new_mode
	Settings.session["camera_mode"] = mode
	head_hidden = false
	if mode == Mode.FIRST_PERSON:
		camera.cull_mask = CULL_NO_HEAD
		pitch = clampf(pitch, deg_to_rad(FP_PITCH_MIN), deg_to_rad(FP_PITCH_MAX))
	else:
		camera.cull_mask = CULL_ALL
		pitch = clampf(pitch, deg_to_rad(TP_PITCH_MIN), deg_to_rad(TP_PITCH_MAX))
		current_distance = 0.5  # grow out smoothly instead of popping through geometry
	if announce:
		Events.camera_mode_changed.emit(mode)


func zoom(step: int) -> void:
	var lo := float(profile.get("camera_zoom_min_m", desired_distance))
	var hi := float(profile.get("camera_zoom_max_m", desired_distance))
	desired_distance = clampf(desired_distance + 0.75 * step, lo, hi)


## Switches to another growth stage's profile (P05). The zoom keeps its fraction between the
## old and the new stage's zoom limits; current_distance is never snapped: the arm grows out
## (or is cut by the next sweep) on its own. Everything else is read from the profile live.
func apply_profile(new_profile: Dictionary) -> void:
	desired_distance = zoomed_distance(profile, new_profile, desired_distance)
	profile = new_profile


## The camera distance on `to` that keeps the zoom fraction `distance` has between the zoom
## limits of `from` (an empty or degenerate `from` uses `to`'s camera_distance_m).
static func zoomed_distance(from: Dictionary, to: Dictionary, distance: float) -> float:
	var to_default := float(to.get("camera_distance_m", distance))
	var lo := float(to.get("camera_zoom_min_m", to_default))
	var hi := float(to.get("camera_zoom_max_m", to_default))
	if from.is_empty():
		return clampf(to_default, minf(lo, hi), maxf(lo, hi))
	var from_lo := float(from.get("camera_zoom_min_m", distance))
	var from_hi := float(from.get("camera_zoom_max_m", distance))
	if from_hi - from_lo < 1e-6:
		return clampf(to_default, minf(lo, hi), maxf(lo, hi))
	var t := clampf((distance - from_lo) / (from_hi - from_lo), 0.0, 1.0)
	return lerpf(lo, hi, t)


## The side orbit (radians) of the third-person lock on a small target `dist` metres away: none
## beyond LOCK_ORBIT_FAR_M x orbit_scale, LOCK_ORBIT_DEG within LOCK_ORBIT_NEAR_M x orbit_scale
## (the profile's camera_orbit_scale, so a bigger giant starts orbiting farther out).
static func lock_orbit_rad(dist: float, orbit_scale: float) -> float:
	var s := maxf(orbit_scale, 0.01)
	return deg_to_rad(LOCK_ORBIT_DEG) * clampf(inverse_lerp(LOCK_ORBIT_FAR_M * s, LOCK_ORBIT_NEAR_M * s, dist), 0.0, 1.0)


## Third person: hide render layer 2 (head, chest, belt) while the arm is shorter than
## HEAD_HIDE_ARM_RADII x the capsule radius, or while the screen-centre ray passes closer than
## HEAD_CLEAR_RADII x the capsule radius beside the pivot. The camera always looks along the
## arm's backward axis, so its centre ray passes the pivot's height at a sideways distance of
## shoulder_offset x arm / full_arm; the pivot sits in the head, so below that distance the
## back of the head covers the crosshair.
static func hides_head(arm_m: float, full_arm_m: float, shoulder_offset_m: float,
		capsule_radius_m: float) -> bool:
	if arm_m < HEAD_HIDE_ARM_RADII * capsule_radius_m:
		return true
	if full_arm_m < 1e-6:
		return false
	return absf(shoulder_offset_m) * arm_m / full_arm_m < HEAD_CLEAR_RADII * capsule_radius_m


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


## World-space aim direction (camera forward).
func aim_forward() -> Vector3:
	return -camera.global_transform.basis.z


func is_first_person() -> bool:
	return mode == Mode.FIRST_PERSON


func _on_settings_changed(key: String) -> void:
	if key == "fov_deg" and camera != null:
		camera.fov = float(Settings.get_value("fov_deg"))


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_time += delta
	_apply_look(delta)
	_update_transform(delta)


func _apply_look(delta: float) -> void:
	var router: InputRouter = player.get("router")
	var mouse := router.take_look_delta() if router != null else Vector2.ZERO
	var stick := Vector2.ZERO
	if InputRouter.context == InputRouter.Context.GAMEPLAY:
		stick = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var locked := lock_target != null and is_instance_valid(lock_target) and lock_target.is_alive()
	if locked and mode == Mode.THIRD_PERSON:
		_frame_lock_target(delta)
		return
	var sens := deg_to_rad(float(Settings.get_value("mouse_sensitivity")))
	var stick_speed := deg_to_rad(float(Settings.get_value("stick_look_speed_deg_s")))
	var invert := -1.0 if Settings.get_value("invert_y") else 1.0
	yaw -= mouse.x * sens + stick.x * stick_speed * delta
	pitch -= (mouse.y * sens + stick.y * stick_speed * delta) * invert
	if mode == Mode.FIRST_PERSON:
		pitch = clampf(pitch, deg_to_rad(FP_PITCH_MIN), deg_to_rad(FP_PITCH_MAX))
		if locked and Settings.get_value("fp_aim_assist"):
			_fp_aim_assist(delta)
	else:
		pitch = clampf(pitch, deg_to_rad(TP_PITCH_MIN), deg_to_rad(TP_PITCH_MAX))
	yaw = wrapf(yaw, -PI, PI)


## Third-person lock: keep player and target framed, aiming at lock_focus_point() - the
## target's torso, or a knee of a target much taller than the giant (P11a), so the camera never
## looks steeply up at a large target's head. A target much smaller than the giant and close to
## it would hide behind the giant's own body, so the camera orbits to the shoulder side and may
## look further down.
func _frame_lock_target(delta: float) -> void:
	var anchor := lock_focus_point()
	var to_target := anchor - player.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var small := lock_target.combatant.height_m < float(profile.get("height_m", 3.66)) * 0.7
	var orbit := lock_orbit_rad(dist, float(profile.get("camera_orbit_scale", 1.0))) if small else 0.0
	if dist > 0.1:
		var want_yaw := TargetingRules.yaw_of(to_target) + orbit
		yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-8.0 * delta))
	var pivot := player.global_position + Vector3.UP * float(profile.get("camera_pivot_height_m", 3.3))
	var focus := pivot.lerp(anchor, 0.6)
	var flat := Vector2(focus.x - pivot.x, focus.z - pivot.z).length()
	var min_pitch := LOCK_SMALL_PITCH_MIN if small else LOCK_PITCH_MIN
	var want_pitch := clampf(atan2(focus.y - pivot.y, maxf(flat, 0.5)) - deg_to_rad(10.0),
		deg_to_rad(min_pitch), deg_to_rad(LOCK_PITCH_MAX))
	pitch = lerp_angle(pitch, want_pitch, 1.0 - exp(-6.0 * delta))


## The point the lock frames on lock_target (P11a): CombatEntity.lock_anchor_position for this
## profile's height - a knee anchor of a target at least 1.3 x the giant's height (the Ogre King
## at stages 1 and 2), otherwise its torso. Vector3.INF without a lock target.
func lock_focus_point() -> Vector3:
	if lock_target == null or not is_instance_valid(lock_target) or lock_target.combatant == null:
		return Vector3.INF
	return lock_target.lock_anchor_position(float(profile.get("height_m", 3.66)))


## Optional gentle first-person drift toward a locked target (never forced rotation).
func _fp_aim_assist(delta: float) -> void:
	var to_target := lock_focus_point() - camera.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	var want := TargetingRules.yaw_of(to_target)
	var diff := TargetingRules.yaw_delta(yaw, want)
	if absf(rad_to_deg(diff)) <= FP_ASSIST_CONE_DEG:
		yaw += clampf(diff, -deg_to_rad(FP_ASSIST_DEG_S) * delta, deg_to_rad(FP_ASSIST_DEG_S) * delta)


func _update_transform(delta: float) -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var height := float(profile.get("height_m", 3.66))
	if mode == Mode.FIRST_PERSON:
		var eye := player.global_position + Vector3.UP * height * float(profile.get("eye_height_ratio", 0.92))
		var flat_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		eye += flat_fwd * 0.18
		var speed := Vector2(player.velocity.x, player.velocity.z).length() if "velocity" in player else 0.0
		var bob_amount := float(Settings.get_value("head_bob"))
		if speed > 0.5 and bob_amount > 0.0:
			_bob_phase += delta * (1.4 + speed * 0.12) * TAU
			eye.y += sin(_bob_phase) * 0.06 * bob_amount * clampf(speed / 5.0, 0.0, 1.5)
		global_transform = Transform3D(basis, eye)
		obstructed = false
	else:
		# One rigid arm from the pivot to the over-the-shoulder camera point, swept as a sphere.
		# (A separate lateral leg could end touching a door jamb and collapse the back leg to 0.)
		# current_distance is the arm length: it retracts instantly and restores smoothly, and it
		# never exceeds the swept safe length, so the camera cannot enter geometry.
		var pivot := player.global_position + Vector3.UP * float(profile.get("camera_pivot_height_m", 3.3))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var shoulder := float(profile.get("camera_shoulder_offset_m", 0.85))
		var desired := pivot + right * shoulder + basis.z * desired_distance
		var arm := desired - pivot
		var arm_length := arm.length()
		var space := player.get_world_3d().direct_space_state
		var safe_length := arm_length * _sweep(space, pivot, desired)
		obstructed = safe_length < arm_length - 0.01
		if safe_length < current_distance or delta <= 0.0:
			current_distance = safe_length
		else:
			current_distance = move_toward(current_distance, safe_length, restore_speed() * delta)   # P26
		global_transform = Transform3D(basis, pivot + arm / maxf(arm_length, 0.001) * current_distance)
		var hide := hides_head(current_distance, arm_length, shoulder, float(profile.get("capsule_radius_m", 0.85)))
		if hide != head_hidden:
			head_hidden = hide
			camera.cull_mask = CULL_NO_HEAD if hide else CULL_ALL
	_apply_shake(delta)


## Fraction (0..1) of the segment a camera-sized sphere can travel without touching the world.
func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	if from.distance_squared_to(to) < 1e-6:
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	q.collision_mask = HitQueryAdapter.OCCLUDER_MASK
	q.collide_with_areas = false
	var result := space.cast_motion(q)
	if result.is_empty():
		return 1.0
	return clampf(result[0], 0.0, 1.0)


func _apply_shake(delta: float) -> void:
	var amount := _shake * _shake * float(Settings.get_value("camera_shake"))
	if amount > 0.0001:
		var n := Vector3(sin(_time * 47.0), sin(_time * 39.0 + 1.3), sin(_time * 53.0 + 2.1))
		camera.transform = Transform3D(Basis.from_euler(n * 0.035 * amount), Vector3.ZERO)
	else:
		camera.transform = Transform3D.IDENTITY
	_shake = maxf(0.0, _shake - delta * 1.8)


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P24a
# The far plane follows the level (P24a, plan M6-M9 §2.7, decision 12): 2,400 m in the world, so its
# fog and skyline reach the edge; DEFAULT_FAR_M (800 m) where the level's preset names none.

const DEFAULT_FAR_M := 800.0


## The far plane of the level the giant stands in: the camera_far_m() of its nearest LevelRoot
## ancestor (the render preset in effect), else DEFAULT_FAR_M.
func level_far_plane_m() -> float:
	var n: Node = player.get_parent() if player != null else get_parent()
	while n != null:
		if n.has_method("camera_far_m"):
			return float(n.call("camera_far_m"))
		n = n.get_parent()
	return DEFAULT_FAR_M


## Sets the camera's far plane (LevelRoot.apply_graphics, also on a graphics setting change).
func set_far_plane(far_m: float) -> void:
	if camera != null:
		camera.far = maxf(far_m, camera.near + 1.0)

## @anchor P26
# Stages 4-6 (P26, plan M6-M9 §2.9): the third-person arm reaches 32 m (stage 6's zoom limit). The
# existing sphere sweep keeps every length out of the world, the streamed terrain included (its
# height-map bodies are on the world layer: a camera pitched up behind a stage-6 giant stops at the
# ground instead of going under it). An arm that long restores faster: restore_speed() scales
# RESTORE_SPEED with the wanted arm beyond RESTORE_REFERENCE_ARM_M (stage 3's zoom limit), so stages
# 1-3 are unchanged and a 23.5 m stage-6 arm comes back in about two seconds instead of four.

const RESTORE_REFERENCE_ARM_M := 16.0
const MAX_ARM_M := 32.0


## The speed (m/s) the arm extends back at after an obstruction clears or the mode changes.
func restore_speed() -> float:
	return RESTORE_SPEED * maxf(1.0, desired_distance / RESTORE_REFERENCE_ARM_M)

## @anchor P30
