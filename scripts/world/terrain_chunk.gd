class_name TerrainChunk
extends Node3D
## One loaded chunk of a streamed world (P24a; plan M6-M9 §2.8, decision 12): the node
## "Chunk_<x>_<z>" under WorldRoot/Chunks, built from its ChunkData by ChunkStreamer one small
## step at a time (open_world_tech.md §3.3: a started step always finishes, every step stays under
## about 3 ms on the desktop). Children, in the order the steps make them:
##   Terrain   MeshInstance3D - the heights at spacing_m, vertex colours from the surface cells and
##             the region tints, its visibility range from the render preset (group world_terrain)
##   Ground    StaticBody3D (world layer) with one HeightMapShape3D (heights / spacing, the shape
##             uniformly scaled by the spacing; the same triangles as the mesh)
##   Water     MeshInstance3D of the chunk's water rectangles (when it has any)
##   Scenery   one MultiMeshInstance3D per mesh key (shared meshes; group "scenery", so the preset's
##             scenery_visibility_end_m hides them far off)
##   Solids    StaticBody3Ds of at most SOLID_BATCH shapes each (a body is added whole, so the
##             physics server builds each compound once)
##   Props     the props sub-scenes (settlements are several, each of at most 150 nodes), one per step
##
## The steps (step() returns the name of the step it ran): "request" (ResourceLoader.
## load_threaded_request of the ChunkData), "data" (its threaded load polled - "wait" while it is
## still loading; deterministic streaming loads it in this step instead, with no worker thread to
## wait for, so headless runs stream the same way every time), "decode" (16-bit heights to
## floats, cell colours), "rows" (about ROW_VERTICES vertices of the terrain arrays a step), "mesh"
## (the ArrayMesh; the chunk joins the tree here), "ground", "water", "scenery" (one key a step),
## "solids" (one batch a step), "props_dep" (one not yet cached dependency of a sub-scene: a
## building's or a gate's scene), "props_load" and "props_add" (one sub-scene each), then "" (done).
## Navigation (P24b) adds its steps after these.

const GROUP := "world_chunks"
## LevelRoot.TERRAIN_GROUP: the preset's terrain_visibility_end_m applies to these meshes.
const TERRAIN_GROUP := "world_terrain"
## Terrain vertices filled per "rows" step (open_world_tech.md §3.3: about 2,000).
const ROW_VERTICES := 2000
## Collision shapes per Solids body (one body per step; brief §3.5: batches of 16).
const SOLID_BATCH := 16
const SCENERY_GROUP := "scenery"
## Steps that run alone in a frame (ChunkStreamer: a frame that already ran steps does not start one,
## and one ends the frame): a sub-scene's dependency, its load and its instancing.
const HEAVY_STEPS := ["props_dep", "props_load", "props_add"]
## Ground colours by surface (soft, hard, wet); a region's map_tint blends in by REGION_TINT_MIX.
const SURFACE_COLORS := [Color(0.36, 0.5, 0.26), Color(0.5, 0.49, 0.45), Color(0.34, 0.33, 0.25)]
const REGION_TINT_MIX := 0.35

enum Stage { REQUEST, DATA, DECODE, ROWS, MESH, GROUND, WATER, SCENERY, SOLIDS, PROPS_LOAD, PROPS_ADD, DONE }

var chunk_id := ""
var coords := Vector2i()
var data_path := ""
var data: ChunkData = null
var stage: int = Stage.REQUEST
var done := false
var aborted := false
## Steps run so far (progress), and the estimate of all of them once the data is known.
var steps_done := 0
var terrain: MeshInstance3D = null
var ground: StaticBody3D = null
var scenery_root: Node3D = null
var solids_root: Node3D = null
var props_root: Node3D = null
## World-space centre of the terrain mesh's AABB (the renderer's visibility-range point).
var aabb_center := Vector3.INF
var height_lo := 0.0
var height_hi := 0.0

var _streamer: Node = null
var _parent: Node3D = null
var _heights := PackedFloat32Array()
var _cell_colors: Array[Color] = []
var _arrays := {}
var _row := 0
var _scenery_keys: Array = []
var _scenery_i := 0
var _solid_i := 0
var _prop_i := 0
var _prop_packed: PackedScene = null
var _prop_deps := PackedStringArray()
var _deps_checked := false


## Prepares the loader: the chunk `id`, its ChunkData file, the streamer that owns the shared
## meshes and materials and the node the chunk will join.
func begin(id: String, path: String, streamer: Node, parent: Node3D) -> void:
	chunk_id = id
	coords = ChunkData.coords_for(id)
	data_path = path
	_streamer = streamer
	_parent = parent
	name = "Chunk_%d_%d" % [coords.x, coords.y]
	add_to_group(GROUP)


## True when the streamer runs deterministically (the threaded load is taken at once).
func _deterministic() -> bool:
	return _streamer != null and bool(_streamer.get("deterministic"))


## The estimated number of steps of the whole load (exact once the data is loaded).
func total_steps() -> int:
	if data == null:
		return maxi(steps_done + 1, 12)
	var m := data.inner()
	var rows := int(ceil(float(m) / float(maxi(1, ROW_VERTICES / m))))
	var solids := int(ceil(float(data.solids.size() / ChunkData.SOLID_STRIDE) / float(SOLID_BATCH)))
	return 5 + rows + 1 + data.scenery.size() + solids + 2 * data.props_scenes.size()


## 0..1 of the load.
func progress() -> float:
	if done:
		return 1.0
	return clampf(float(steps_done) / float(maxi(1, total_steps())), 0.0, 0.99)


## True when the next step is a heavy one (HEAVY_STEPS).
func next_is_heavy() -> bool:
	if done or aborted or data == null:
		return false
	return (stage == Stage.PROPS_LOAD and _prop_i < data.props_scenes.size()) or stage == Stage.PROPS_ADD


## Runs the next step and returns its name: "" when there is nothing left (done), "wait" while the
## threaded load of the data or of a props scene has not finished (the streamer moves on).
func step() -> String:
	if done or aborted:
		return ""
	var what := _step()
	if what != "wait" and what != "":
		steps_done += 1
	return what


func _step() -> String:
	match stage:
		Stage.REQUEST:
			if not ResourceLoader.exists(data_path):
				push_error("TerrainChunk: %s has no chunk data (%s)" % [chunk_id, data_path])
				aborted = true
				return ""
			if not _deterministic():
				var err := ResourceLoader.load_threaded_request(data_path, "", false, ResourceLoader.CACHE_MODE_REUSE)
				if err != OK:
					push_error("TerrainChunk: cannot request %s (error %d)" % [data_path, err])
					aborted = true
					return ""
			stage = Stage.DATA
			return "request"
		Stage.DATA:
			if _deterministic():
				# Deterministic streaming takes the load in this step (no worker thread to wait for).
				data = ResourceLoader.load(data_path, "", ResourceLoader.CACHE_MODE_REUSE) as ChunkData
			else:
				if ResourceLoader.load_threaded_get_status(data_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					return "wait"
				data = ResourceLoader.load_threaded_get(data_path) as ChunkData
			if data == null:
				push_error("TerrainChunk: %s is not a ChunkData resource" % data_path)
				aborted = true
				return ""
			stage = Stage.DECODE
			return "data"
		Stage.DECODE:
			_decode()
			stage = Stage.ROWS
			return "decode"
		Stage.ROWS:
			var m := data.inner()
			var to := mini(m, _row + maxi(1, ROW_VERTICES / m))
			fill_rows(_arrays, _heights, data.samples, data.spacing_m, _row, to, _cell_colors)
			_row = to
			if _row >= m:
				stage = Stage.MESH
			return "rows"
		Stage.MESH:
			_make_mesh()
			stage = Stage.GROUND
			return "mesh"
		Stage.GROUND:
			_make_ground()
			stage = Stage.WATER
			return "ground"
		Stage.WATER:
			_make_water()
			stage = Stage.SCENERY
			_scenery_keys = data.scenery.keys()
			_scenery_keys.sort()
			return "water"
		Stage.SCENERY:
			if _scenery_i >= _scenery_keys.size():
				stage = Stage.SOLIDS
				return _step()
			_make_scenery(str(_scenery_keys[_scenery_i]))
			_scenery_i += 1
			if _scenery_i >= _scenery_keys.size():
				stage = Stage.SOLIDS
			return "scenery"
		Stage.SOLIDS:
			var n := data.solids.size() / ChunkData.SOLID_STRIDE
			if _solid_i >= n:
				stage = Stage.PROPS_LOAD
				return _step()
			_make_solids_batch(_solid_i, mini(n, _solid_i + SOLID_BATCH))
			_solid_i = mini(n, _solid_i + SOLID_BATCH)
			if _solid_i >= n:
				stage = Stage.PROPS_LOAD
			return "solids"
		Stage.PROPS_LOAD:
			if _prop_i >= data.props_scenes.size():
				stage = Stage.DONE
				done = true
				return ""
			var path := data.props_scenes[_prop_i]
			if not _deps_checked:
				_deps_checked = true
				_prop_deps = missing_dependencies(path)
			if not _prop_deps.is_empty():
				# One dependency of the part a step (a building or gate scene, a script), kept by the
				# streamer for the level's life, so the part itself then loads in a fraction of the time.
				var dep := _prop_deps[0]
				var res: Resource = null
				if _deterministic():
					res = ResourceLoader.load(dep, "", ResourceLoader.CACHE_MODE_REUSE)
				else:
					var dstatus := ResourceLoader.load_threaded_get_status(dep)
					if dstatus == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
						ResourceLoader.load_threaded_request(dep, "", false, ResourceLoader.CACHE_MODE_REUSE)
						dstatus = ResourceLoader.load_threaded_get_status(dep)
					if dstatus == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
						return "wait"
					res = ResourceLoader.load_threaded_get(dep)
				if _streamer != null and res != null:
					_streamer.call("keep_resource", dep, res)
				_prop_deps.remove_at(0)
				return "props_dep"
			if _prop_packed == null:
				if not ResourceLoader.exists(path):
					push_error("TerrainChunk: %s names a missing props scene %s" % [chunk_id, path])
					_prop_i += 1
					return "props_load"
				if _deterministic():
					_prop_packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
				else:
					var status := ResourceLoader.load_threaded_get_status(path)
					if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
						ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
						status = ResourceLoader.load_threaded_get_status(path)
					if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
						return "wait"
					_prop_packed = ResourceLoader.load_threaded_get(path) as PackedScene
			stage = Stage.PROPS_ADD
			return "props_load"
		Stage.PROPS_ADD:
			if props_root == null:
				props_root = Node3D.new()
				props_root.name = "Props"
				add_child(props_root)
			if _prop_packed != null:
				var inst := _prop_packed.instantiate()
				if inst is Node3D:
					props_root.add_child(inst)
				elif inst != null:
					inst.free()
			_prop_packed = null
			_prop_i += 1
			_deps_checked = false
			stage = Stage.PROPS_LOAD
			if _prop_i >= data.props_scenes.size():
				stage = Stage.DONE
				done = true
			return "props_add"
	return ""


## The res:// dependencies of a props scene that are not in the resource cache yet (scenes it
## instances, scripts, materials), in the order ResourceLoader lists them.
static func missing_dependencies(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in ResourceLoader.get_dependencies(path):
		var dep := d.get_slice("::", d.get_slice_count("::") - 1) if d.contains("::") else d
		if dep.begins_with("res://") and not ResourceLoader.has_cached(dep) and not out.has(dep):
			out.append(dep)
	return out


## Stops a load in progress (the chunk left the ring): frees what was made.
func abort() -> void:
	aborted = true
	_prop_packed = null
	if is_inside_tree():
		queue_free()
	elif not is_queued_for_deletion():
		free()


# --------------------------------------------------------------------------- the steps

func _decode() -> void:
	_heights = data.decode_heights()
	var m := data.inner()
	var lo := INF
	var hi := -INF
	for j in m:
		var row := (j + 1) * data.samples + 1
		for i in m:
			var h := _heights[row + i]
			if h < lo:
				lo = h
			if h > hi:
				hi = h
	height_lo = lo if lo != INF else 0.0
	height_hi = hi if hi != -INF else 0.0
	_arrays = new_terrain_arrays(data.inner())
	_cell_colors = cell_colors(data, _region_tints())
	position = data.origin
	var half := data.size_m * 0.5
	aabb_center = data.origin + Vector3(half, (height_lo + height_hi) * 0.5, half)


## Region tints: the level's region list (the streamer's region_ids) -> each region record's
## map_tint ({index (1-based) -> Color}; regions without a record or a tint are left out).
func _region_tints() -> Dictionary:
	var out := {}
	var ids: Variant = _streamer.get("region_ids") if _streamer != null else null
	if typeof(ids) != TYPE_PACKED_STRING_ARRAY:
		return out
	for k in (ids as PackedStringArray).size():
		var rec := GameData.get_record((ids as PackedStringArray)[k])
		var tint: Variant = rec.get("map_tint")
		if typeof(tint) == TYPE_ARRAY and (tint as Array).size() == 3:
			out[k + 1] = Color(float(tint[0]), float(tint[1]), float(tint[2]))
	return out


func _make_mesh() -> void:
	var material: Material = _streamer.call("terrain_material") if _streamer != null else null
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh_from_arrays(_arrays, material)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vis := float(_streamer.get("terrain_visibility_end_m")) if _streamer != null else 0.0
	terrain.visibility_range_end = maxf(vis, 0.0)
	terrain.add_to_group(TERRAIN_GROUP)
	add_child(terrain)
	_arrays = {}
	if _parent != null and not is_inside_tree():
		_parent.add_child(self)


func _make_ground() -> void:
	ground = StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = height_shape(_heights, data.samples, data.spacing_m)
	cs.transform = height_shape_transform(data.inner(), data.spacing_m)
	ground.add_child(cs)
	add_child(ground)


func _make_water() -> void:
	var n := data.water.size() / ChunkData.WATER_STRIDE
	if n == 0:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in n:
		var o := k * ChunkData.WATER_STRIDE
		var y := data.water[o + 4]
		var a := Vector3(data.water[o], y, data.water[o + 1])
		var b := Vector3(data.water[o + 2], y, data.water[o + 1])
		var c := Vector3(data.water[o + 2], y, data.water[o + 3])
		var d := Vector3(data.water[o], y, data.water[o + 3])
		for v: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	var mat: Variant = _streamer.call("water_material") if _streamer != null else null
	if mat is Material:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _make_scenery(key: String) -> void:
	if scenery_root == null:
		scenery_root = Node3D.new()
		scenery_root.name = "Scenery"
		add_child(scenery_root)
	var buf: PackedFloat32Array = data.scenery[key]
	var count := buf.size() / ChunkData.SCENERY_STRIDE
	var mesh: Mesh = _streamer.call("shared_mesh", key) if _streamer != null else null
	if count == 0 or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = key.get_file().get_basename().to_pascal_case()
	mmi.multimesh = mm
	var vis := float(_streamer.get("scenery_visibility_end_m")) if _streamer != null else 0.0
	mmi.visibility_range_end = maxf(vis, 0.0)
	mmi.add_to_group(SCENERY_GROUP)
	scenery_root.add_child(mmi)


func _make_solids_batch(from: int, to: int) -> void:
	if solids_root == null:
		solids_root = Node3D.new()
		solids_root.name = "Solids"
		add_child(solids_root)
	var body := StaticBody3D.new()
	body.name = "Batch%d" % (from / SOLID_BATCH)
	body.collision_layer = 1
	body.collision_mask = 0
	var s := data.solids
	for i in range(from, to):
		var o := i * ChunkData.SOLID_STRIDE
		var cs := CollisionShape3D.new()
		if int(s[o]) == ChunkData.SOLID_CYLINDER:
			var cyl := CylinderShape3D.new()
			cyl.radius = s[o + 4] * 0.5
			cyl.height = s[o + 5]
			cs.shape = cyl
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(s[o + 4], s[o + 5], s[o + 6])
			cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, s[o + 7]), Vector3(s[o + 1], s[o + 2], s[o + 3]))
		body.add_child(cs)
	solids_root.add_child(body)


## Frees the props sub-scenes now (an unload's first step: the director has despawned its members
## on chunk_unloading; the props go before the rest of the chunk).
func free_props() -> void:
	if props_root != null and is_instance_valid(props_root):
		props_root.queue_free()
		props_root = null


# --------------------------------------------------------------------------- terrain building (static)

## Empty terrain arrays for an m x m vertex grid.
static func new_terrain_arrays(m: int) -> Dictionary:
	var v := PackedVector3Array()
	v.resize(m * m)
	var nrm := PackedVector3Array()
	nrm.resize(m * m)
	var col := PackedColorArray()
	col.resize(m * m)
	var idx := PackedInt32Array()
	idx.resize((m - 1) * (m - 1) * 6)
	return {"v": v, "nrm": nrm, "col": col, "idx": idx}


## The colour of each surface cell (16 x 16): the surface's colour, blended with the region's tint.
static func cell_colors(d: ChunkData, region_tints: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	var n := ChunkData.SURFACE_CELLS
	var rn := ChunkData.REGION_CELLS
	var per := n / rn
	var surf := d.surface_cells
	var regs := d.region_cells
	var has_surf := surf.size() >= n * n
	var has_regs := regs.size() >= rn * rn and not region_tints.is_empty()
	out.resize(n * n)
	for j in n:
		for i in n:
			var s := mini(int(surf[j * n + i]), SURFACE_COLORS.size() - 1) if has_surf else 0
			var c: Color = SURFACE_COLORS[s]
			if has_regs:
				var r := int(regs[(j / per) * rn + i / per])
				if region_tints.has(r):
					c = c.lerp(region_tints[r], REGION_TINT_MIX)
			out[j * n + i] = c
	return out


## Fills vertex rows [row_from, row_to) of the terrain arrays from the apron grid `h` (samples x
## samples floats): positions at spacing d, normals from the neighbours (the apron gives the border
## its neighbour's slope), colours from the cell colours, and the two triangles of every cell
## (split along the (i, j) - (i + 1, j + 1) diagonal, as the ground body's height field).
static func fill_rows(arrays: Dictionary, h: PackedFloat32Array, samples: int, d: float, row_from: int,
		row_to: int, colors: Array[Color]) -> void:
	var m := samples - 2
	var v: PackedVector3Array = arrays.v
	var nrm: PackedVector3Array = arrays.nrm
	var col: PackedColorArray = arrays.col
	var idx: PackedInt32Array = arrays.idx
	var inv2d := 1.0 / (2.0 * d)
	var cells := ChunkData.SURFACE_CELLS
	var cell_div := float(m - 1) / float(cells)
	var fallback := SURFACE_COLORS[0] as Color
	for j in range(row_from, row_to):
		var cj := mini(int(float(j) / cell_div), cells - 1)
		for i in m:
			var a := (j + 1) * samples + i + 1
			var y := h[a]
			var k := j * m + i
			v[k] = Vector3(i * d, y, j * d)
			nrm[k] = Vector3((h[a - 1] - h[a + 1]) * inv2d, 1.0, (h[a - samples] - h[a + samples]) * inv2d).normalized()
			var ci := mini(int(float(i) / cell_div), cells - 1)
			col[k] = colors[cj * cells + ci] if colors.size() == cells * cells else fallback
			if j < m - 1 and i < m - 1:
				var q := (j * (m - 1) + i) * 6
				idx[q] = k
				idx[q + 1] = k + 1
				idx[q + 2] = k + m + 1
				idx[q + 3] = k
				idx[q + 4] = k + m + 1
				idx[q + 5] = k + m
	arrays.v = v
	arrays.nrm = nrm
	arrays.col = col
	arrays.idx = idx


static func mesh_from_arrays(arrays: Dictionary, material: Material) -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = arrays.v
	a[Mesh.ARRAY_NORMAL] = arrays.nrm
	a[Mesh.ARRAY_COLOR] = arrays.col
	a[Mesh.ARRAY_INDEX] = arrays.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


## The HeightMapShape3D of the inner samples of the apron grid `h`, its heights divided by the
## spacing (the CollisionShape3D is scaled uniformly by it: height_shape_transform).
static func height_shape(h: PackedFloat32Array, samples: int, d: float) -> HeightMapShape3D:
	var m := samples - 2
	var s := HeightMapShape3D.new()
	s.map_width = m
	s.map_depth = m
	var map := PackedFloat32Array()
	map.resize(m * m)
	var inv := 1.0 / d
	for j in m:
		var row := (j + 1) * samples + 1
		for i in m:
			map[j * m + i] = h[row + i] * inv
	s.map_data = map
	return s


## The CollisionShape3D transform of height_shape(): uniformly scaled by the spacing and centred
## on the chunk (the height field spans -(m - 1) / 2 .. (m - 1) / 2 cells around its origin).
static func height_shape_transform(m: int, d: float) -> Transform3D:
	var half := (m - 1) * d * 0.5
	return Transform3D(Basis().scaled(Vector3(d, d, d)), Vector3(half, 0.0, half))
