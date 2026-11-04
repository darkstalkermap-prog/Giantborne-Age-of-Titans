class_name CameraRig
extends Node3D
## Third-person and first-person camera for the player (spec section 5).
##
## One player entity owns both modes; switching never touches gameplay state. Third person
## uses a collision-tested follow arm: a sphere is swept from the pivot to the shoulder point
## and on to the desired camera position; the arm retracts instantly at obstacles and
## restores smoothly. First person sits at 92% of the giant's height with the head hidden
## (render layer 2 is culled). Shake and head bob are independently scalable in Settings.

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

var mode: int = Mode.THIRD_PERSON
var yaw := 0.0                       ## radians, Godot convention (0 faces -Z)
var pitch := deg_to_rad(-18.0)
var player: Node3D = null
var profile: Dictionary = {}
var desired_distance := 6.5
var current_distance := 6.5
var lock_target: CombatEntity = null
var obstructed := false
var _shake := 0.0
var _time := 0.0
var _bob_phase := 0.0
var _sphere := SphereShape3D.new()

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	top_level = true
	_sphere.radius = COLLISION_RADIUS
	Settings.changed.connect(_on_settings_changed)


func setup(p_player: Node3D, p_profile: Dictionary) -> void:
	player = p_player
	profile = p_profile
	desired_distance = float(profile.get("camera_distance_m", 6.5))
	current_distance = desired_distance
	camera.fov = float(Settings.get_value("fov_deg"))
	camera.near = 0.05
	camera.far = 800.0
	camera.current = true
	set_mode(int(Settings.session.get("camera_mode", Mode.THIRD_PERSON)), false)
	_update_transform(0.0)


func toggle_mode() -> void:
	set_mode(Mode.FIRST_PERSON if mode == Mode.THIRD_PERSON else Mode.THIRD_PERSON)


func set_mode(new_mode: int, announce := true) -> void:
	mode = new_mode
	Settings.session["camera_mode"] = mode
	if mode == Mode.FIRST_PERSON:
		camera.cull_mask = 0xFFFFF & ~(1 << (FP_HIDDEN_LAYER - 1))
		pitch = clampf(pitch, deg_to_rad(FP_PITCH_MIN), deg_to_rad(FP_PITCH_MAX))
	else:
		camera.cull_mask = 0xFFFFF
		pitch = clampf(pitch, deg_to_rad(TP_PITCH_MIN), deg_to_rad(TP_PITCH_MAX))
		current_distance = 0.5  # grow out smoothly instead of popping through geometry
	if announce:
		Events.camera_mode_changed.emit(mode)


func zoom(step: int) -> void:
	var lo := float(profile.get("camera_zoom_min_m", desired_distance))
	var hi := float(profile.get("camera_zoom_max_m", desired_distance))
	desired_distance = clampf(desired_distance + 0.75 * step, lo, hi)


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


## Third-person lock: keep player and target framed, aiming at the target's torso anchor
## (never steeply up at a large target's head). A target much smaller than the giant and
## close to it would hide behind the giant's own body, so the camera orbits to the shoulder
## side and may look further down.
func _frame_lock_target(delta: float) -> void:
	var anchor := lock_target.anchor_position()
	var to_target := anchor - player.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var small := lock_target.combatant.height_m < float(profile.get("height_m", 3.66)) * 0.7
	var orbit := 0.0
	if small:
		orbit = deg_to_rad(LOCK_ORBIT_DEG) * clampf(inverse_lerp(12.0, 3.0, dist), 0.0, 1.0)
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


## Optional gentle first-person drift toward a locked target (never forced rotation).
func _fp_aim_assist(delta: float) -> void:
	var to_target := lock_target.anchor_position() - camera.global_position
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
		var pivot := player.global_position + Vector3.UP * float(profile.get("camera_pivot_height_m", 3.3))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var shoulder := pivot + right * float(profile.get("camera_shoulder_offset_m", 0.85))
		var space := player.get_world_3d().direct_space_state
		var shoulder_safe := pivot.lerp(shoulder, _sweep(space, pivot, shoulder))
		var back := basis.z * desired_distance
		var safe_distance := desired_distance * _sweep(space, shoulder_safe, shoulder_safe + back)
		obstructed = safe_distance < desired_distance - 0.01
		if safe_distance < current_distance or delta <= 0.0:
			current_distance = safe_distance
		else:
			current_distance = move_toward(current_distance, safe_distance, RESTORE_SPEED * delta)
		global_transform = Transform3D(basis, shoulder_safe + basis.z * current_distance)
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
