class_name StormWeather
extends Node3D
## D2 (decision D2-5): the storm over the Drowned Steps - the Stormcaller's - as the giant sees it near: the light
## going dark and grey-green, the fog closing in, rain driven slant by the wind, lightning walking in it (a far bolt and
## its flash every few seconds, its thunder after it by the distance) and, over the Stormstair's water, the rain's rings.
## Strongest within radius_m of the node, gone by radius_m + fade_m (the camera's distance); only while active_flag is
## set (the storm came with act two), never once calm_flag is (the Stormcaller fallen: it clears over CLEAR_S, the light
## coming back - the world's answer to his fall).
##
## Presentation only: it reads the flags and the camera and writes the WorldEnvironment's light, fog and colour (each
## restored as it fades), the sun's energy, its rain's particles and its bolts; nothing in the simulation reads it. The
## far storm's clouds are the world's (world.json "storms", hidden by the same flag). Cheap for the Web: one CPU
## particle system of streaks (unshaded, additive - no dark quads), one light at a flash, no screen reads.

const GROUP := "storm_weather"
const CLEAR_S := 14.0
const RAIN_AMOUNT := 900
const RAIN_BOX := Vector3(140.0, 70.0, 140.0)
const FLASH_S := 0.22
const SOUND_MPS := 340.0
## The storm's light at full: the environment's background, ambient and fog colours, the sun's share.
const DARK_BG := Color(0.24, 0.27, 0.29)
const DARK_AMBIENT := Color(0.34, 0.38, 0.42)
const DARK_FOG := Color(0.33, 0.37, 0.40)
const SUN_SHARE := 0.38
const FOG_DENSITY := 0.0045

@export var radius_m := 260.0
@export var fade_m := 220.0
@export var active_flag := ""
@export var calm_flag := ""
## Far bolts: one every this many seconds (a range), struck this far from the camera at least.
@export var bolt_every_s := Vector2(5.0, 11.0)
@export var bolt_near_m := 70.0

var intensity := 0.0
var clearing := 0.0
var bolts := 0
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _base := {}
var _rain: CPUParticles3D = null
var _rain_mat: StandardMaterial3D = null
var _next_bolt := 3.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()
var _thunder: Array = []


func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = hash(str(get_path()))
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--skin"):
		set_process(false)
		return
	_build_rain()


func _exit_tree() -> void:
	_apply(0.0)


## Whether the storm stands over the Steps now (its flags).
func active() -> bool:
	if active_flag != "" and not bool(WorldState.get_flag(active_flag, false)):
		return false
	return true


func calm() -> bool:
	return calm_flag != "" and bool(WorldState.get_flag(calm_flag, false))


## The storm's strength at a viewer at `p` (0..1): full within radius_m, none beyond radius_m + fade_m.
func strength_at(p: Vector3) -> float:
	if not active():
		return 0.0
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return 1.0 - smoothstep(radius_m, radius_m + fade_m, d)


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _process(delta: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	var want := strength_at(cam.global_position)
	if calm():
		clearing = minf(1.0, clearing + delta / CLEAR_S)
	else:
		clearing = 0.0
	want *= 1.0 - smoothstep(0.0, 1.0, clearing)
	intensity = move_toward(intensity, want, delta * 0.5)
	_flash = maxf(0.0, _flash - delta / FLASH_S)
	_apply(intensity)
	_rain_step(cam)
	_bolt_step(cam, delta)
	_thunder_step(cam, delta)


## The environment's light toward the storm's by `k` (its values on first touch kept and given back at 0).
func _apply(k: float) -> void:
	if _env == null:
		var we := get_tree().root.find_children("*", "WorldEnvironment", true, false) if is_inside_tree() else []
		if we.is_empty():
			return
		_env = (we[0] as WorldEnvironment).environment
		var suns := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		_sun = suns[0] as DirectionalLight3D if not suns.is_empty() else null
		if _env == null:
			return
		_base = {"bg": _env.background_color, "amb": _env.ambient_light_color, "amb_e": _env.ambient_light_energy,
			"fog": _env.fog_light_color, "fog_d": _env.fog_density, "fog_on": _env.fog_enabled,
			"sun": _sun.light_energy if _sun != null else 1.0}
	if _base.is_empty():
		return
	var f := clampf(_flash, 0.0, 1.0) * k
	_env.background_color = (_base.bg as Color).lerp(DARK_BG, k).lerp(Color(0.80, 0.84, 0.92), f * 0.6)
	_env.ambient_light_color = (_base.amb as Color).lerp(DARK_AMBIENT, k)
	_env.ambient_light_energy = float(_base.amb_e) * lerpf(1.0, 0.85, k) + 1.6 * f
	_env.fog_light_color = (_base.fog as Color).lerp(DARK_FOG, k)
	if bool(_base.fog_on):
		_env.fog_density = lerpf(float(_base.fog_d), maxf(float(_base.fog_d), FOG_DENSITY), k)
	if _sun != null:
		_sun.light_energy = float(_base.sun) * lerpf(1.0, SUN_SHARE, k)


# --------------------------------------------------------------------------- the rain

func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.top_level = true
	_rain.amount = RAIN_AMOUNT
	_rain.lifetime = 1.2
	_rain.preprocess = 1.2
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = RAIN_BOX * 0.5
	_rain.direction = Vector3(0.35, -1.0, 0.15)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 55.0
	_rain.initial_velocity_max = 70.0
	_rain.gravity = Vector3.ZERO
	_rain.particle_flag_align_y = true
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 2.6)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_mat.albedo_color = Color(0.55, 0.60, 0.66, 0.0)
	q.material = _rain_mat
	_rain.mesh = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false
	add_child(_rain)


func _rain_step(cam: Camera3D) -> void:
	if _rain == null:
		return
	var on := intensity > 0.03
	if _rain.emitting != on:
		_rain.emitting = on
	_rain_mat.albedo_color = Color(0.55, 0.60, 0.66, 0.32 * intensity)
	_rain.global_position = cam.global_position + Vector3(0.0, 18.0, 0.0) - cam.global_transform.basis.z * 30.0


# --------------------------------------------------------------------------- lightning

func _bolt_step(cam: Camera3D, delta: float) -> void:
	if intensity < 0.25:
		return
	_next_bolt -= delta
	if _next_bolt > 0.0:
		return
	_next_bolt = _rng.randf_range(bolt_every_s.x, bolt_every_s.y) / maxf(intensity, 0.3)
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(bolt_near_m, radius_m + fade_m * 0.5)
	var at := global_position + Vector3(sin(a), 0.0, cos(a)) * r
	at.y = cam.global_position.y - 40.0
	var world := get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot
	if world != null:
		var h := world.height_at(at)
		if not is_nan(h):
			at.y = h
	strike(at)


## A far bolt at `at`: its light, the flash on the land, its thunder after it by the distance (presentation).
func strike(at: Vector3) -> void:
	bolts += 1
	StormFx.bolt(self, at + Vector3(_rng.randf_range(-40, 40), 220.0, _rng.randf_range(-40, 40)), at,
		_rng.randi(), 0.3, 0.0, 3.0)
	_flash = 1.0
	var cam := _camera()
	var d := cam.global_position.distance_to(at) if cam != null else 300.0
	_thunder.append([d / SOUND_MPS, at])


func _thunder_step(_cam: Camera3D, delta: float) -> void:
	for t: Array in _thunder.duplicate():
		t[0] = float(t[0]) - delta
		if float(t[0]) <= 0.0:
			_thunder.erase(t)
			Events.storm_thunder.emit(Sim.tick, t[1] as Vector3)
