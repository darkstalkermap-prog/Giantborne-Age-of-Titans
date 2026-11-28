class_name CinderFx
extends Node3D
## E2: the Cinder Titan's fire, drawn cheaply enough for the Web build (presentation only; nothing in the simulation
## reads it). One CinderFx holds:
##   Flames  every flame of the fight in one MultiMesh (cinder_flame.gdshader: upright billboards, added light, their
##           tongues from scrolling noise) - one draw call however many patches burn;
##   Scorch  every patch of burnt ground in one MultiMesh of flat discs (cinder_ground.gdshader: char, ash and glowing
##           embers, a ragged edge) - one draw call.
## Flames and discs are slots (a fixed capacity; a free slot is scaled to nothing). The rig (CinderRig) and the world's
## fires (CinderRoad) ask for slots and set them; the one-shots - smoke, steam, sparks - are DustBurst puffs and short
## CPUParticles3D bursts that free themselves.

const FLAME_SHADER := "res://assets/shaders/cinder_flame.gdshader"
const GROUND_SHADER := "res://assets/shaders/cinder_ground.gdshader"
const SMOKE := Color(0.13, 0.12, 0.115, 0.85)
const STEAM := Color(0.88, 0.89, 0.9, 0.8)
const ASH := Color(0.34, 0.33, 0.31, 0.75)

var flame_cap := 320
var disc_cap := 64
var flames: MultiMeshInstance3D = null
var scorch: MultiMeshInstance3D = null
var _free_flames: Array[int] = []
var _free_discs: Array[int] = []
static var _flame_mat: ShaderMaterial = null
static var _ground_mat: ShaderMaterial = null
static var _spark_mat: StandardMaterial3D = null


func _init(p_flames := 320, p_discs := 64) -> void:
	flame_cap = p_flames
	disc_cap = p_discs


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if flames == null:
		_make()


func _make() -> void:
	flames = MultiMeshInstance3D.new()
	flames.name = "Flames"
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.center_offset = Vector3(0.0, 0.5, 0.0)
	fm.mesh = q
	fm.instance_count = flame_cap
	for i in flame_cap:
		fm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -1000, 0)))
		fm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	flames.multimesh = fm
	flames.material_override = flame_material()
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.custom_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 2000, 8000))
	add_child(flames)
	scorch = MultiMeshInstance3D.new()
	scorch.name = "Scorch"
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	var p := PlaneMesh.new()
	p.size = Vector2(2.0, 2.0)
	sm.mesh = p
	sm.instance_count = disc_cap
	for i in disc_cap:
		sm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -1000, 0)))
		sm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	scorch.multimesh = sm
	scorch.material_override = ground_material()
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scorch.custom_aabb = flames.custom_aabb
	add_child(scorch)
	_free_flames.clear()
	for i in range(flame_cap - 1, -1, -1):
		_free_flames.append(i)
	_free_discs.clear()
	for i in range(disc_cap - 1, -1, -1):
		_free_discs.append(i)


static func flame_material() -> ShaderMaterial:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load(FLAME_SHADER)
	return _flame_mat


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = load(GROUND_SHADER)
		_ground_mat.set_shader_parameter(&"disc", true)
	return _ground_mat


# --------------------------------------------------------------------------- slots

func flame_slots_free() -> int:
	return _free_flames.size()


## A flame `height` m tall and `width` wide standing at `at`; its slot (-1 when none is free).
func add_flame(at: Vector3, height: float, width: float, seed_value: float, strength := 1.0, rise := 0.5) -> int:
	if flames == null:
		_make()
	if _free_flames.is_empty():
		return -1
	var i: int = _free_flames.pop_back()
	set_flame(i, at, height, width, seed_value, strength, rise)
	return i


func set_flame(i: int, at: Vector3, height: float, width: float, seed_value: float, strength := 1.0, rise := 0.5) -> void:
	if i < 0 or flames == null:
		return
	flames.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(width, height, width)), at))
	flames.multimesh.set_instance_custom_data(i, Color(fposmod(seed_value, 1.0), clampf(strength, 0.0, 2.0), rise, 0.0))


func set_flame_strength(i: int, strength: float) -> void:
	if i < 0 or flames == null:
		return
	var c := flames.multimesh.get_instance_custom_data(i)
	c.g = clampf(strength, 0.0, 2.0)
	flames.multimesh.set_instance_custom_data(i, c)


func free_flame(i: int) -> void:
	if i < 0 or flames == null or _free_flames.has(i):
		return
	flames.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -1000, 0)))
	flames.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_free_flames.append(i)


## A disc of burnt ground `radius` m round `at`; its slot (-1 when none is free).
func add_disc(at: Vector3, radius: float, seed_value: float, ember := 1.0) -> int:
	if scorch == null:
		_make()
	if _free_discs.is_empty():
		return -1
	var i: int = _free_discs.pop_back()
	scorch.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)),
		at + Vector3.UP * 0.18))
	scorch.multimesh.set_instance_custom_data(i, Color(fposmod(seed_value, 1.0), ember, 1.0, 0.0))
	return i


## A disc's embers (0 out .. 1) and how much of it shows (`fade`, 0 gone .. 1).
func set_disc(i: int, ember: float, fade: float) -> void:
	if i < 0 or scorch == null:
		return
	var c := scorch.multimesh.get_instance_custom_data(i)
	c.g = clampf(ember, 0.0, 1.0)
	c.b = clampf(fade, 0.0, 1.0)
	scorch.multimesh.set_instance_custom_data(i, c)


func free_disc(i: int) -> void:
	if i < 0 or scorch == null or _free_discs.has(i):
		return
	scorch.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -1000, 0)))
	scorch.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_free_discs.append(i)


# --------------------------------------------------------------------------- one-shots

## Sparks thrown up from `at` (added light; short-lived; frees itself).
static func sparks(parent: Node, at: Vector3, size := 6.0, count := 40, speed := 14.0) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = maxi(count, 1)
	p.lifetime = 1.6
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35) * maxf(size / 6.0, 0.5)
	p.mesh = q
	p.material_override = _sparks_material()
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	g.set_color(1, Color(0.8, 0.15, 0.0, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func _sparks_material() -> StandardMaterial3D:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_color = Color(1, 1, 1, 1)
	return _spark_mat


static func smoke(parent: Node, at: Vector3, size := 10.0, count := 16, speed := 4.0) -> void:
	DustBurst.puff(parent, at, size, count, speed, SMOKE)


static func steam(parent: Node, at: Vector3, size := 12.0, count := 26, speed := 8.0) -> void:
	DustBurst.puff(parent, at, size, count, speed, STEAM)
