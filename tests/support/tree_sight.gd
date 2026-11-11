class_name TreeSight
extends RefCounted
## Tests' measure of trees hiding the giant from the camera (M8 screenshot pass, V1): sight lines from
## the camera to points on a body, and the first tree surface each one meets - the real triangles of the
## shared tree meshes (Mesh.get_faces) at every tree instance of the loaded chunks (their ChunkData
## scenery buffers, as TerrainChunk draws them) or of the Valley's districts (their Scenery
## MultiMeshes). A line "is hidden" when that first tree surface is drawn there with less than
## VISIBLE_FADE of its pixels faded out (the tree material's fade, SceneryFade.fade_at_now, read through
## the material actually drawn: a material that does not fade fades nothing).

const WORLD_TREE_KEYS := ["tree_pine", "tree_broadleaf"]
const FADE_SHADER := "res://assets/shaders/scenery_fade.gdshader"
const FADE_SCRIPT := "res://scripts/presentation/scenery_fade.gd"
## A sight line whose first tree surface is faded at least this much is clear (the dither leaves less
## than half of that tree's pixels there).
const VISIBLE_FADE := 0.5

static var _faces := {}


## Every tree of the loaded, finished chunks under `root`'s tree: [{"xform": Transform3D (world),
## "key": mesh key, "mesh": Mesh, "material": the material it is drawn with}].
static func world_trees(root: Node) -> Array:
	var out: Array = []
	for n in root.get_tree().get_nodes_in_group(TerrainChunk.GROUP):
		var c := n as TerrainChunk
		if c == null or not c.is_inside_tree() or c.data == null or not c.done:
			continue
		for path: String in c.data.scenery:
			var key := path.get_file().get_basename()
			if not WORLD_TREE_KEYS.has(key):
				continue
			var mesh := load(path) as Mesh
			if mesh == null:
				continue
			var mat := _drawn_material(c, key, mesh)
			for t: Transform3D in ChunkWriter.buffer_xforms(c.data.scenery[path]):
				out.append({"xform": c.global_transform * t, "key": key, "mesh": mesh, "material": mat})
	return out


## The material the chunk's MultiMeshInstance3D of `key` draws with (its override, else the mesh's).
static func _drawn_material(c: TerrainChunk, key: String, mesh: Mesh) -> Material:
	if c.scenery_root != null:
		var mmi := c.scenery_root.get_node_or_null(NodePath(key.to_pascal_case())) as MultiMeshInstance3D
		if mmi != null and mmi.material_override != null:
			return mmi.material_override
	return mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null


## Every tree part of the Valley's district Scenery MultiMeshes under `root` (trunks and crowns):
## [{"xform", "key", "mesh", "material"}].
static func valley_trees(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if mmi.get_parent() == null or mmi.get_parent().name != "Scenery" or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var mat := mmi.material_override
		for t: Transform3D in ChunkWriter.buffer_xforms(mm.buffer):
			out.append({"xform": mmi.global_transform * t, "key": str(mmi.name), "mesh": mm.mesh, "material": mat})
	return out


static func faces_of(mesh: Mesh) -> PackedVector3Array:
	var id := mesh.get_instance_id()
	if not _faces.has(id):
		_faces[id] = mesh.get_faces()
	return _faces[id]


## The first tree surface the segment from -> to meets: {"tree": index in `trees`, "point": world
## point, "distance": m from `from`}, or {} when it meets none.
static func first_tree_hit(from: Vector3, to: Vector3, trees: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for i in trees.size():
		var tr: Dictionary = trees[i]
		var xf: Transform3D = tr.xform
		var mesh: Mesh = tr.mesh
		var box: AABB = xf * mesh.get_aabb()
		if not box.grow(0.1).intersects_segment(from, to):
			continue
		var inv := xf.affine_inverse()
		var a := inv * from
		var b := inv * to
		var faces := faces_of(mesh)
		for k in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, faces[k], faces[k + 1], faces[k + 2])
			if hit == null:
				continue
			var wp: Vector3 = xf * (hit as Vector3)
			var d := from.distance_to(wp)
			if d < best_d:
				best_d = d
				best = {"tree": i, "point": wp, "distance": d}
	return best


## Points on a standing body (feet at `base`, `height` tall, `radius` wide) as a camera at `eye` sees
## it: four heights (25-95 % of the height) by three across (the centre and +-60 % of the radius,
## sideways to the view).
static func body_points(base: Vector3, height: float, radius: float, eye: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var view := base - eye
	view.y = 0.0
	var side := Vector3.UP.cross(view).normalized() if view.length() > 0.01 else Vector3.RIGHT
	for h: float in [0.25, 0.5, 0.75, 0.95]:
		for s: float in [-0.6, 0.0, 0.6]:
			out.append(base + Vector3.UP * height * h + side * radius * s)
	return out


## The fade `material` draws at world point `p` now (0 = the surface is drawn whole): the scenery
## fade's rule (SceneryFade.fade_at, with the parameters the camera last set) when the material is
## the fade shader's, else 0.
static func fade_of(material: Material, p: Vector3) -> float:
	var sm := material as ShaderMaterial
	if sm == null or sm.shader == null or sm.shader.resource_path != FADE_SHADER:
		return 0.0
	if not ResourceLoader.exists(FADE_SCRIPT):
		return 0.0
	var script := load(FADE_SCRIPT) as Script
	return float(script.call("fade_at_now", p))


## The sight lines from `eye` to `points` that a tree hides: [{"to", "point", "tree": its key at its
## place, "fade"}], each line's first tree surface drawn with less than VISIBLE_FADE faded.
static func hidden_lines(eye: Vector3, points: PackedVector3Array, trees: Array) -> Array:
	var out: Array = []
	for q: Vector3 in points:
		var hit := first_tree_hit(eye, q, trees)
		if hit.is_empty():
			continue
		var tr: Dictionary = trees[int(hit.tree)]
		var f := fade_of(tr.material, hit.point)
		if f < VISIBLE_FADE:
			out.append({"to": q, "point": hit.point, "tree": "%s at %s" % [tr.key, (tr.xform as Transform3D).origin.snapped(Vector3.ONE * 0.1)],
				"fade": f, "distance": hit.distance})
	return out
