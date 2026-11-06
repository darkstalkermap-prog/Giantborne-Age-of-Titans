class_name ChunkWriter
extends RefCounted
## Writes the chunks of a streamed world (P24a; plan M6-M9 §2.7, decision 12): the offline half of
## ChunkData. A world builder (P24a's test world, P25's world) calls it per chunk:
##   chunk_from_field()  the heights of one chunk cut from a HeightField with their one-sample apron
##                       (so neighbours share their border samples) and quantised to 16 bits
##   cells()             the 16 x 16 surface cells or the 4 x 4 region cells from a classifier
##   xform_buffer()      scenery instance transforms -> a MultiMesh buffer (12 floats each)
##   add_solid()         a box or cylinder into the solids list (collision and, later, navigation
##                       obstacles from the same list)
##   add_water()         a water rectangle
##   split_parts() / part_scene()   the chunk's props split into sub-scenes of at most
##                       MAX_PART_NODES nodes (a settlement is several), each rooted at
##                       Chunk_<x>_<z>_<part> with the containers of §2.15
##   save()              the ChunkData as a compressed binary resource
## Tools only (tools/ is never exported).

const MAX_PART_NODES := 150
## A chunk scene's containers (plan §2.15), in this order under every part's root.
const CONTAINERS := ["Props", "Shrines", "Waystones", "Markers", "Triggers", "Exits", "SizeGates", "Landmarks", "NavLinks"]


## The ChunkData of chunk `c` of a grid of chunk_size-metre chunks whose chunk (0, 0) starts at
## world `origin` (y 0): its heights cut from `field` (field sample `first` is world (origin.x,
## origin.z); the chunk takes chunk_size / spacing + 1 inner samples plus the apron), quantised.
static func chunk_from_field(field: HeightField, c: Vector2i, chunk_size: float, origin: Vector3,
		first: Vector2i) -> ChunkData:
	var cells := int(roundf(chunk_size / field.spacing))
	var m := cells + 1
	var samples := m + 2
	var d := ChunkData.new()
	d.chunk_id = ChunkData.id_for(c)
	d.coords = c
	d.origin = origin + Vector3(c.x * chunk_size, 0.0, c.y * chunk_size)
	d.size_m = chunk_size
	d.spacing_m = field.spacing
	d.samples = samples
	d.height_min = HeightField.QUANT_MIN_M
	d.height_step = HeightField.QUANT_STEP_M
	var values := PackedFloat32Array()
	values.resize(samples * samples)
	var i0 := first.x + c.x * cells - 1
	var j0 := first.y + c.y * cells - 1
	for j in samples:
		for i in samples:
			values[j * samples + i] = field.at(i0 + i, j0 + j)
	d.heights = HeightField.encode(values, d.height_min, d.height_step)
	return d


## An n x n grid of cell values over the chunk from classify.call(world_x, world_z) at each cell's
## centre (n = ChunkData.SURFACE_CELLS for surfaces, REGION_CELLS for regions).
static func cells(d: ChunkData, n: int, classify: Callable) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n)
	var cell := d.size_m / n
	for j in n:
		for i in n:
			out[j * n + i] = clampi(int(classify.call(d.origin.x + (i + 0.5) * cell, d.origin.z + (j + 0.5) * cell)), 0, 255)
	return out


## A MultiMesh buffer (12 floats per instance: the basis rows with the origin) of chunk-local
## transforms.
static func xform_buffer(xforms: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * ChunkData.SCENERY_STRIDE)
	var k := 0
	for t: Transform3D in xforms:
		var b := t.basis
		var o := t.origin
		for v: float in [b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]:
			buf[k] = v
			k += 1
	return buf


## The chunk-local transforms of a MultiMesh buffer (tests).
static func buffer_xforms(buf: PackedFloat32Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for k in buf.size() / ChunkData.SCENERY_STRIDE:
		var o := k * ChunkData.SCENERY_STRIDE
		out.append(Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
			Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), Vector3(buf[o + 3], buf[o + 7], buf[o + 11])))
	return out


## Appends a solid: a box of `size` or (cylinder) a cylinder of diameter size.x and height size.y,
## centred at chunk-local `center`, turned by `yaw` (radians).
static func add_solid(solids: PackedFloat32Array, cylinder: bool, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	solids.append_array([float(ChunkData.SOLID_CYLINDER if cylinder else ChunkData.SOLID_BOX), center.x, center.y,
		center.z, size.x, size.y, size.z, yaw])


## Appends a water rectangle (chunk-local) with its surface height.
static func add_water(water: PackedFloat32Array, rect: Rect2, surface_y: float) -> void:
	water.append_array([rect.position.x, rect.position.y, rect.end.x, rect.end.y, surface_y])


# --------------------------------------------------------------------------- props sub-scenes

## The nodes of a subtree, itself included.
static func node_count(n: Node) -> int:
	var total := 1
	for child in n.get_children():
		total += node_count(child)
	return total


## The nodes a part costs on top of its elements: its root and its containers.
static func part_overhead() -> int:
	return 1 + CONTAINERS.size()


## Packs `elements` ([{"node": Node3D, "container": one of CONTAINERS (a "Markers/<kind>" path
## for markers)}], in order) into parts of at most max_nodes nodes each (root and containers
## included, a Markers/<kind> folder counting once per part): [[element, ...], ...]. An element too
## big for an empty part fails: {"ok": false, "message"}; else {"ok": true, "parts": [...]}.
static func split_parts(elements: Array, max_nodes := MAX_PART_NODES) -> Dictionary:
	var parts: Array = []
	var current: Array = []
	var used := part_overhead()
	var folders := {}
	for e: Dictionary in elements:
		var n := node_count(e.node as Node)
		var folder := str(e.container)
		var extra := 1 if folder.contains("/") and not folders.has(folder) else 0
		if part_overhead() + n + (1 if folder.contains("/") else 0) > max_nodes:
			return {"ok": false, "message": "%s has %d nodes: more than a part of %d can hold" % [
				(e.node as Node).name, n, max_nodes]}
		if used + n + extra > max_nodes and not current.is_empty():
			parts.append(current)
			current = []
			used = part_overhead()
			folders = {}
			extra = 1 if folder.contains("/") else 0
		current.append(e)
		used += n + extra
		if folder.contains("/"):
			folders[folder] = true
	if not current.is_empty():
		parts.append(current)
	return {"ok": true, "parts": parts}


## The root of a chunk's props part: Chunk_<x>_<z>_<part> (or Chunk_<x>_<z> for part -1) with every
## container, the elements moved under theirs (a "Markers/<kind>" container makes the kind folder).
static func part_scene(c: Vector2i, part: int, elements: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y] if part < 0 else "Chunk_%d_%d_%d" % [c.x, c.y, part]
	for container: String in CONTAINERS:
		var n := Node3D.new()
		n.name = container
		root.add_child(n)
	for e: Dictionary in elements:
		var path := str(e.container)
		var parent := root.get_node(NodePath(path.get_slice("/", 0))) as Node3D
		if path.contains("/"):
			var kind := path.get_slice("/", 1)
			var folder := parent.get_node_or_null(NodePath(kind)) as Node3D
			if folder == null:
				folder = Node3D.new()
				folder.name = kind
				parent.add_child(folder)
			parent = folder
		var node := e.node as Node
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		parent.add_child(node)
	return root


## The path of part `part` of chunk `c` under `dir` ("<dir>c<x>_<z>_<part>.tscn").
static func part_path(dir: String, c: Vector2i, part: int) -> String:
	return dir.path_join("c%d_%d_%d.tscn" % [c.x, c.y, part])


## Saves a ChunkData (compressed binary). Returns the error code.
static func save(d: ChunkData, path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return ResourceSaver.save(d, path, ResourceSaver.FLAG_COMPRESS)
