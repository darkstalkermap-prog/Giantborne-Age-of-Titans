class_name Skyline
extends Node3D
## The world seen to its edge (P24a; plan M6-M9 §2.8, §5.3, decision 12): the node "Skyline" of
## WorldRoot draws the level's skyline mesh (the whole world's terrain at 32 m spacing, each vertex
## the lowest fine height within 32 m minus 2 m, vertex-coloured by the regions' skyline tints) and
## its landmark silhouettes (one merged mesh) with assets/shaders/skyline.gdshader, which discards
## the fragments over chunks whose own terrain is drawn. WorldRoot keeps that mask (one byte per
## chunk: set_mask) in the global shader parameters world_loaded_mask, world_grid_origin and
## world_chunk_size, which ensure_globals() registers at run time (no project setting needed).
## visible_at() is the shader's rule on the CPU (tests, debug).
##
## Lit beacons (decision 12): unshaded, fog-free light columns, one MultiMesh instance per beacon
## whose flag is truthy (beacon_positions[i] / beacon_flags[i], set by the world builder), updated
## on Events.flag_changed. Two or three draw calls in all, no shadows.

const SHADER_PATH := "res://assets/shaders/skyline.gdshader"
const PARAM_MASK := &"world_loaded_mask"
const PARAM_ORIGIN := &"world_grid_origin"
const PARAM_CHUNK := &"world_chunk_size"
const BEACON_COLOR := Color(1.0, 0.74, 0.36)
const MASK_DRAWN := 255

## Where lit beacons stand (their columns rise from here) and the flag that lights each.
@export var beacon_positions := PackedVector3Array()
@export var beacon_flags := PackedStringArray()
@export var beacon_height_m := 400.0
@export var beacon_radius_m := 3.0

var grid := Vector2i(1, 1)
var grid_origin := Vector2.ZERO
var chunk_size := 256.0
## One byte per chunk, row-major (MASK_DRAWN = its own terrain is drawn: the skyline hides there).
var mask := PackedByteArray()
var terrain: MeshInstance3D = null
var landmarks: MeshInstance3D = null
var beacons: MultiMeshInstance3D = null
var material: ShaderMaterial = null

var _image: Image = null
var _texture: ImageTexture = null


func _ready() -> void:
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	update_beacons()


## Registers the three global shader parameters when missing (before the shader is first loaded).
static func ensure_globals() -> void:
	var have := RenderingServer.global_shader_parameter_get_list()
	if not have.has(PARAM_MASK):
		var img := Image.create(1, 1, false, Image.FORMAT_R8)
		RenderingServer.global_shader_parameter_add(PARAM_MASK, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,
			ImageTexture.create_from_image(img))
	if not have.has(PARAM_ORIGIN):
		RenderingServer.global_shader_parameter_add(PARAM_ORIGIN, RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2.ZERO)
	if not have.has(PARAM_CHUNK):
		RenderingServer.global_shader_parameter_add(PARAM_CHUNK, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 256.0)


## Builds the drawn meshes (either may be null) for a grid of `p_grid` chunks of `p_chunk` metres
## whose chunk (0, 0) starts at `p_origin` (x, z).
func setup(terrain_mesh: Mesh, landmarks_mesh: Mesh, p_grid: Vector2i, p_origin: Vector2, p_chunk: float) -> void:
	grid = Vector2i(maxi(1, p_grid.x), maxi(1, p_grid.y))
	grid_origin = p_origin
	chunk_size = maxf(1.0, p_chunk)
	mask = PackedByteArray()
	mask.resize(grid.x * grid.y)
	ensure_globals()
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	_image = Image.create(grid.x, grid.y, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set(PARAM_MASK, _texture)
	RenderingServer.global_shader_parameter_set(PARAM_ORIGIN, grid_origin)
	RenderingServer.global_shader_parameter_set(PARAM_CHUNK, chunk_size)
	terrain = _mesh_node("Terrain", terrain_mesh)
	landmarks = _mesh_node("Landmarks", landmarks_mesh)


func _mesh_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var old := get_node_or_null(node_name)
	if old != null:
		old.free()
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Sets the mask (one byte per chunk, row-major; non-zero = drawn by its chunk). Returns true when
## it changed (the texture is only updated then).
func set_mask(bits: PackedByteArray) -> bool:
	var next := PackedByteArray()
	next.resize(grid.x * grid.y)
	for k in mini(bits.size(), next.size()):
		next[k] = MASK_DRAWN if bits[k] != 0 else 0
	if next == mask:
		return false
	mask = next
	if _image != null:
		_image.set_data(grid.x, grid.y, false, Image.FORMAT_R8, mask)
		_texture.update(_image)
		RenderingServer.global_shader_parameter_set(PARAM_MASK, _texture)
	return true


## The cell of the mask holding `pos` ((-1, -1) outside the grid).
func mask_cell(pos: Vector3) -> Vector2i:
	var c := Vector2i(int(floor((pos.x - grid_origin.x) / chunk_size)), int(floor((pos.z - grid_origin.y) / chunk_size)))
	if c.x < 0 or c.y < 0 or c.x >= grid.x or c.y >= grid.y:
		return Vector2i(-1, -1)
	return c


## The shader's rule: the skyline shows at `pos` unless its chunk is drawn.
func visible_at(pos: Vector3) -> bool:
	var c := mask_cell(pos)
	if c.x < 0 or mask.size() != grid.x * grid.y:
		return true
	return mask[c.y * grid.x + c.x] == 0


# --------------------------------------------------------------------------- beacons

## The positions of the beacons whose flags are truthy now.
func lit_beacons() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in mini(beacon_positions.size(), beacon_flags.size()):
		if BreakableProp.flag_truthy(WorldState.get_flag(beacon_flags[i])):
			out.append(beacon_positions[i])
	return out


## Shows one light column per lit beacon (none: the node is hidden).
func update_beacons() -> void:
	var lit := lit_beacons()
	if beacons == null:
		if lit.is_empty():
			return
		beacons = MultiMeshInstance3D.new()
		beacons.name = "Beacons"
		beacons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = beacon_radius_m
		cyl.bottom_radius = beacon_radius_m
		cyl.height = beacon_height_m
		cyl.radial_segments = 8
		cyl.rings = 1
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_fog = true
		mat.albedo_color = BEACON_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cyl.material = mat
		mm.mesh = cyl
		beacons.multimesh = mm
		add_child(beacons)
	var mm2 := beacons.multimesh
	mm2.instance_count = lit.size()
	for i in lit.size():
		mm2.set_instance_transform(i, Transform3D(Basis(), lit[i] + Vector3.UP * beacon_height_m * 0.5))
	beacons.visible = not lit.is_empty()


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if beacon_flags.has(flag_id):
		update_beacons()
