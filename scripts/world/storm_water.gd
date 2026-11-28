class_name StormWater
extends Node3D
## D2 (decision D2-3): the water the Stormcaller's lightning runs through - the flooded pools of the Stormstair, the top
## of the Drowned Steps, where he stands calling the storm.
##
## A set of pools (`pools`: [centre x, centre z, radius x, radius z, surface y] in the node's space - ellipses): the
## water stands at its surface over whatever ground is under it, so how deep a body stands in it is the surface less
## the body's feet (depth_at). The world builder carves the pools' beds (basins) and lays this node over them; the
## test arena's floor is flat, so its pools are water standing that deep over the floor and drawn here (draw).
##
## What the pools are for (TitanEnemy's `storm`, PlayerStorm): a bolt of his that strikes water sends the shock out
## through it - every body standing in water within its reach takes it, by how much of the body is under water (a
## bigger giant stands higher out of the same pool); a titan standing deep in it is grounded by it (down on a knee).
## A pure lookup: nothing here steps. After his fall (calm_flag) the storm has gone out of the water: no shock runs.

const GROUP := "storm_water"
const SHADER := "res://assets/shaders/storm_water.gdshader"

@export var water_id := "storm_water"
## [cx, cz, rx, rz, surface_y] ellipses in the node's space.
@export var pools: Array = []
## Once this world flag is set (the Stormcaller fallen) the water is only water.
@export var calm_flag := ""
## E2: water that is there only once this world flag is set ("" always): the Ashfell's dammed water, held back by the
## dam the giant threw down (world.ashfell.dammed). Not there, it is neither deep nor drawn; as the flag is set in play
## the drawn water rises to its surface over FILL_S (the depth is the surface's at once).
@export var show_flag := ""
## Draw the pools' water (the test arena's flat floor); the world's chunks draw their own water.
@export var draw := false
## The rain on the drawn water (0..1) and the wind's direction over it (the look).
@export var rain := 1.0
## D3: in the world (draw off) the pools are drawn too, with the storm's own water (its ripples and the rain's rings), a
## hand's breadth over the chunk's flat water. Dgate: drawn to their shores - each pool's mesh (shore_mesh) reaches
## SHORE_OUT_U of the basin's ellipse out, lies on the water inside the shoreline and draped over the bank beyond it
## (BANK_LIFT_M over the ground), and carries the water's depth at each vertex: storm_water_shore.gdshader shades the
## shallows, the wet line and a wet bank fading out above it, so no flat disc's edge or polygon shows where the water
## meets the land. The ground is the world's (WorldRoot.height_at): a pool whose chunks are not all loaded yet is drawn
## when they are.
const WORLD_LIFT_M := 0.04
const BANK_LIFT_M := 0.25
const SHORE_OUT_U := 1.45
const SHORE_RINGS := 26
const SHORE_SEGMENTS := 72
const SHORE_SHADER := "res://assets/shaders/storm_water_shore.gdshader"
## How fast the rain's rings fade off the water once he has fallen (per second).
const CALM_FADE_PER_S := 0.1
## The world's pools' colours (the chunks' water, ChunkStreamer.WATER_COLOR, a shade deeper) and the sky they mirror.
const WORLD_DEEP := Color(0.15, 0.25, 0.31)
const WORLD_SKY := Color(0.62, 0.68, 0.74)
## Drawn after the chunks' own transparent water (priority 0), so it covers it.
const SHORE_PRIORITY := 1

var _mat: ShaderMaterial = null
var _rain_now := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_build_look()
	if show_flag != "":
		_fill = 1.0 if present() else 0.0
		_show_fill()
		if not Events.flag_changed.is_connected(_on_flag_changed):
			Events.flag_changed.connect(_on_flag_changed)


## E2: how far the drawn water has risen (0 dry .. 1 at its surface) and how far down its bed lies under it.
const FILL_S := 6.0
const FILL_DROP_M := 6.0
var _fill := 1.0
var _filling := false


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if flag_id != show_flag:
		return
	_filling = present() and _fill < 1.0
	if not present():
		_fill = 0.0
	_show_fill()


func _show_fill() -> void:
	visible = _fill > 0.0
	for c in get_children():
		if c is Node3D:
			(c as Node3D).position.y = (c as Node3D).get_meta("base_y", (c as Node3D).position.y) - FILL_DROP_M * (1.0 - _fill)


func calm() -> bool:
	return calm_flag != "" and bool(WorldState.get_flag(calm_flag, false))


## E2: whether this water is there (its show_flag set, or none).
func present() -> bool:
	return show_flag == "" or bool(WorldState.get_flag(show_flag, false))


## The depth of this node's water at world point `p` (its feet): 0 outside every pool or above the water.
func depth_here(p: Vector3) -> float:
	var l := to_local(p)
	var best := 0.0
	for pool: Variant in pools:
		var a := pool as Array
		if a == null or a.size() < 5:
			continue
		var dx := (l.x - float(a[0])) / maxf(0.01, float(a[2]))
		var dz := (l.z - float(a[1])) / maxf(0.01, float(a[3]))
		if dx * dx + dz * dz > 1.0:
			continue
		best = maxf(best, float(a[4]) - l.y)
	return maxf(0.0, best)


## The surface's height (world) of the pool over `p`, NAN where there is none.
func surface_here(p: Vector3) -> float:
	var l := to_local(p)
	var out := NAN
	for pool: Variant in pools:
		var a := pool as Array
		if a == null or a.size() < 5:
			continue
		var dx := (l.x - float(a[0])) / maxf(0.01, float(a[2]))
		var dz := (l.z - float(a[1])) / maxf(0.01, float(a[3]))
		if dx * dx + dz * dz <= 1.0:
			var y := to_global(Vector3(l.x, float(a[4]), l.z)).y
			out = y if is_nan(out) else maxf(out, y)
	return out


## How deep the storm's water stands at world point `p` (the deepest of every live StormWater over it): 0 when dry.
static func depth_at(tree: SceneTree, p: Vector3) -> float:
	if tree == null:
		return 0.0
	var best := 0.0
	for node in tree.get_nodes_in_group(GROUP):
		var w := node as StormWater
		if w == null or not w.is_inside_tree() or w.calm() or not w.present():
			continue
		best = maxf(best, w.depth_here(p))
	return best


## The share of a body `height_m` tall standing at `p` that is under the storm's water (0..1).
static func wet_share(tree: SceneTree, p: Vector3, height_m: float) -> float:
	if height_m <= 0.0:
		return 0.0
	return clampf(depth_at(tree, p) / height_m, 0.0, 1.0)


# --------------------------------------------------------------------------- the look

func _build_look() -> void:
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--skin"):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER if draw else SHORE_SHADER)
	_rain_now = 0.0 if calm() else rain
	mat.set_shader_parameter(&"rain", _rain_now)
	_mat = mat
	if not draw:
		# (the world's pools in the world water's colour, a little deeper: the arena's slate grey-green read as a black
		# hole from a giant's height under the Steps' light)
		mat.set_shader_parameter(&"deep", WORLD_DEEP)
		mat.set_shader_parameter(&"sky", WORLD_SKY)
		mat.render_priority = SHORE_PRIORITY
		_shores_left = range(pools.size())
		_build_shores()
		return
	var i := 0
	for pool: Variant in pools:
		var a := pool as Array
		var mi := MeshInstance3D.new()
		mi.name = "Pool%d" % i
		var w := CylinderMesh.new()
		w.top_radius = 1.0
		w.bottom_radius = 1.0
		w.height = 0.02
		w.radial_segments = 48
		w.rings = 1
		w.cap_bottom = false
		mi.mesh = w
		mi.material_override = mat
		mi.scale = Vector3(float(a[2]), 1.0, float(a[3]))
		mi.position = Vector3(float(a[0]), float(a[4]), float(a[1]))
		mi.set_meta("base_y", mi.position.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		i += 1


var _shores_left: Array = []


## Dgate: each pool not drawn yet whose ground is loaded, drawn to its shore; waits for the next chunk otherwise.
func _build_shores() -> void:
	var world := get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot if is_inside_tree() else null
	if world == null:
		return
	var ground := func(x: float, z: float) -> float:
		var g := to_global(Vector3(x, 0.0, z))
		var h := world.height_at(g)
		return NAN if is_nan(h) else to_local(Vector3(g.x, h, g.z)).y
	for i: int in _shores_left.duplicate():
		var mesh := shore_mesh(pools[i] as Array, ground)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Pool%d" % i
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("base_y", 0.0)
		add_child(mi)
		_shores_left.erase(i)
		if show_flag != "":
			_show_fill()
	var waiting := not _shores_left.is_empty()
	if waiting and not Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.connect(_on_chunk_loaded)
	elif not waiting and Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.disconnect(_on_chunk_loaded)


func _on_chunk_loaded(_chunk_id: String) -> void:
	_build_shores()


func _exit_tree() -> void:
	if Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.disconnect(_on_chunk_loaded)
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)


## Dgate: a pool's water drawn to its shore: a ring grid over its ellipse `pool` ([cx, cz, rx, rz, surface] in the
## node's space) out to `out_u` of it (rings closer together toward the shore), each vertex on the water where the
## ground `ground(x, z)` (the node's space; NAN where unknown) lies under the surface, else draped over the bank
## BANK_LIFT_M above it; UV.x the water's depth there (negative on the bank), UV.y how far out (1 at the ellipse).
## Null while any of its ground is unknown.
static func shore_mesh(pool: Array, ground: Callable, out_u := SHORE_OUT_U, rings := SHORE_RINGS,
		segments := SHORE_SEGMENTS, lift := WORLD_LIFT_M) -> ArrayMesh:
	if pool.size() < 5:
		return null
	var cx := float(pool[0])
	var cz := float(pool[1])
	var rx := float(pool[2])
	var rz := float(pool[3])
	var surface := float(pool[4])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings + 1:
		var u := out_u * pow(float(r) / float(rings), 0.75)
		for k in segments:
			var a := TAU * float(k) / float(segments)
			var x := cx + rx * u * cos(a)
			var z := cz + rz * u * sin(a)
			var g: float = ground.call(x, z)
			if is_nan(g):
				return null
			var depth := surface - g
			var y := surface + lift if depth > 0.0 else g + BANK_LIFT_M
			st.set_uv(Vector2(depth, u))
			st.add_vertex(Vector3(x, y, z))
	for r in rings:
		for k in segments:
			var a0 := r * segments + k
			var a1 := r * segments + (k + 1) % segments
			var b0 := a0 + segments
			var b1 := a1 + segments
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a1)
			st.add_index(a1)
			st.add_index(b0)
			st.add_index(b1)
	st.generate_normals()
	return st.commit()


## D3: once he has fallen the rain's rings fade off the drawn water (the storm clears over the Steps).
func _process(delta: float) -> void:
	if _filling:
		_fill = minf(1.0, _fill + delta / FILL_S)
		_filling = _fill < 1.0
		_show_fill()
	if _mat == null or _rain_now <= 0.0 or not calm():
		return
	_rain_now = maxf(0.0, _rain_now - CALM_FADE_PER_S * delta)
	_mat.set_shader_parameter(&"rain", _rain_now)
