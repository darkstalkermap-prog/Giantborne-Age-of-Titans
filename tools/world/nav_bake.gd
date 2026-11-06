class_name NavBake
extends RefCounted
## Offline navigation for streamed worlds (P24b; plan M6-M9 §2.2, decision 13; open_world_tech.md
## §5.2): one lean navmesh per chunk and nav layer, baked from the chunk's terrain (the HeightField a
## world builder made) with its own and its eight neighbours' obstacles, so tiles of neighbouring
## chunks meet exactly and merge on their layer's map without edge connections. Tools only
## (tools/ is never exported); nothing bakes at run time.
##
## The three fixes of the brief, each found by a failing experiment there:
##   1. the bake AABB is the chunk grown by border_size (radius + 2 cells, whole cells) on every
##      side - Godot 4.6.3 cuts the border from inside filter_baking_aabb - and the source geometry
##      reaches TERRAIN_MARGIN_M beyond the chunk, so the navmesh ends exactly on the chunk edge,
##      uneroded;
##   2. the voxel grid's y origin is floored to a world-wide multiple of the layer's cell height,
##      so neighbouring tiles quantise heights alike;
##   3. one navigation map per layer at run time (NavMaps; this file only bakes).
## Lean settings (brief §5.1: about half the polygons): edge_max_error 2 cells, detail sample
## distance 24 cells, detail sample error 4 cell heights.
##
## Layers (plan §2.2): human (1), large (2) and titan (16). Water deeper than MAX_WADE_M is left
## out of the human and large meshes (a projected obstruction over every deep cell). The titan mesh
## keeps the water bed walkable, and its polygons that touch gated ground (the builder's gate_at:
## world x, z -> 0 or a gate bit, 32 / 64 / 128 for stages 4 / 5 / 6, sampled over each polygon by
## split_gates) become separate gate navmeshes: one bake, split by polygon, so a gate region shares
## its border vertices with the titan region exactly and the map joins them, while a query whose
## mask lacks the bit cannot cross. Each navmesh is moved down by its layer's `lower_m` (the height
## Recast leaves its mesh above flat ground less the layer's `above_m`, as the Valley builder lowers
## its regions), so the same shift applies to every tile of a layer and seams stay exact.

## The baked layers: bit, file name, agent radius / height / climb, cell size and height, the
## walkable slope, whether deep water is cut out (wade_limit), how far the mesh is moved down after
## the bake (lower_m: Recast leaves a lean mesh two cell heights over flat ground - 0.5 m human,
## 1.0 m large and titan, measured on the test world's town pad) and where that leaves it over flat
## ground (above_m: the Valley's heights, human 0.35, large 0.15, the giant layers 0; a chunk's nav
## links stand at it).
const LAYERS := [
	{"layer": 1, "name": "human", "radius": 0.75, "height": 2.0, "climb": 0.25, "cell": 0.25, "cell_height": 0.25,
		"slope": 40.0, "wade_limit": true, "lower_m": 0.15, "above_m": 0.35},
	{"layer": 2, "name": "large", "radius": 1.5, "height": 6.0, "climb": 0.5, "cell": 0.5, "cell_height": 0.5,
		"slope": 40.0, "wade_limit": true, "lower_m": 0.85, "above_m": 0.15},
	{"layer": 16, "name": "titan", "radius": 4.0, "height": 19.0, "climb": 2.0, "cell": 1.0, "cell_height": 0.5,
		"slope": 40.0, "wade_limit": false, "lower_m": 1.0, "above_m": 0.0},
]
const TITAN_LAYER := 16
## Gate bits (titan gate regions) and their file names: stage 4, 5 and 6.
const GATE_NAMES := {32: "gate4", 64: "gate5", 128: "gate6"}
const EDGE_MAX_ERROR := 2.0
const DETAIL_SAMPLE_DISTANCE := 24.0
const DETAIL_SAMPLE_MAX_ERROR := 4.0
## Islands smaller than this many cells squared are dropped (Recast's min region area).
const REGION_MIN_SIZE := 8.0
## The terrain source reaches this far beyond the chunk (at least the largest border, 6 m).
const TERRAIN_MARGIN_M := 8.0
## The bake AABB's floor lies this far under the chunk's lowest ground (then floored to the grid)...
const AABB_FLOOR_DROP_M := 2.0
## ... and its top this far over the highest (a titan is 19 m tall).
const AABB_HEADROOM_M := 24.0
## Human and large agents do not wade water deeper than this.
const MAX_WADE_M := 1.0
## Deep water is found on a grid of this many metres.
const WATER_CELL_M := 2.0
## Sides of a cylinder obstacle's outline.
const CYL_SIDES := 8
## A polygon's edges are sampled this often for gated ground (split_gates).
const GATE_SAMPLE_M := 2.0


## The layer spec of bit `layer` ({} when it is not a baked layer).
static func spec_for(layer: int) -> Dictionary:
	for s: Dictionary in LAYERS:
		if int(s.layer) == layer:
			return s
	return {}


## The border of a layer's bake: its agent radius plus two cells (a whole number of cells).
static func border_for(spec: Dictionary) -> float:
	return float(spec.radius) + 2.0 * float(spec.cell)


## The file name part of a navmesh bit: "human", "large", "titan", "gate4" ...
static func bit_name(bit: int) -> String:
	if GATE_NAMES.has(bit):
		return str(GATE_NAMES[bit])
	var s := spec_for(bit)
	return str(s.get("name", "layer%d" % bit))


## The navmesh file of chunk `chunk_id` and bit `bit` in `dir` ("<dir>/<chunk>_<name>.res").
static func nav_path(dir: String, chunk_id: String, bit: int) -> String:
	return dir.path_join("%s_%s.res" % [chunk_id, bit_name(bit)])


## An empty NavigationMesh with a layer's bake settings (also the settings of its split parts: a
## map refuses a region whose cell size differs from its own).
static func new_mesh(spec: Dictionary) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = float(spec.radius)
	nm.agent_height = float(spec.height)
	nm.agent_max_climb = float(spec.climb)
	nm.agent_max_slope = float(spec.slope)
	nm.cell_size = float(spec.cell)
	nm.cell_height = float(spec.cell_height)
	nm.region_min_size = REGION_MIN_SIZE
	nm.edge_max_error = EDGE_MAX_ERROR
	nm.detail_sample_distance = DETAIL_SAMPLE_DISTANCE
	nm.detail_sample_max_error = DETAIL_SAMPLE_MAX_ERROR
	return nm


# --------------------------------------------------------------------------- the source geometry

## The terrain of a chunk and TERRAIN_MARGIN_M around it as triangles in chunk-local coordinates
## (the chunk's min corner at x = z = 0, y absolute), from the field's samples, split along the
## (i, j) - (i + 1, j + 1) diagonal like the terrain mesh and the ground body, wound clockwise
## seen from above (Godot's front faces; add_faces expects them so). With `walkable`
## (Callable(world_x, world_z) -> bool) the cells whose centre it refuses are left out: no navmesh
## there (the rim: its steep faces also crowd a map's edge rasteriser).
static func terrain_faces(field: HeightField, origin: Vector3, size: float, margin := TERRAIN_MARGIN_M,
		walkable := Callable()) -> PackedVector3Array:
	var sp := field.spacing
	var steps := int(roundf(margin / sp))
	var i0 := int(roundf((origin.x - field.origin.x) / sp)) - steps
	var j0 := int(roundf((origin.z - field.origin.y) / sp)) - steps
	var n := int(roundf(size / sp)) + 2 * steps
	var out := PackedVector3Array()
	out.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var x0 := field.world_x(i0 + i) - origin.x
			var z0 := field.world_z(j0 + j) - origin.z
			if walkable.is_valid() and not bool(walkable.call(x0 + origin.x + sp * 0.5, z0 + origin.z + sp * 0.5)):
				continue
			var p00 := Vector3(x0, field.at(i0 + i, j0 + j), z0)
			var p10 := Vector3(x0 + sp, field.at(i0 + i + 1, j0 + j), z0)
			var p01 := Vector3(x0, field.at(i0 + i, j0 + j + 1), z0 + sp)
			var p11 := Vector3(x0 + sp, field.at(i0 + i + 1, j0 + j + 1), z0 + sp)
			out[k] = p00
			out[k + 1] = p10
			out[k + 2] = p11
			out[k + 3] = p00
			out[k + 4] = p11
			out[k + 5] = p01
			k += 6
	out.resize(k)
	return out


## The lowest and highest ground of the chunk and its margin (x, y).
static func height_range(field: HeightField, origin: Vector3, size: float, margin := TERRAIN_MARGIN_M) -> Vector2:
	var sp := field.spacing
	var steps := int(roundf(margin / sp))
	var i0 := int(roundf((origin.x - field.origin.x) / sp)) - steps
	var j0 := int(roundf((origin.z - field.origin.y) / sp)) - steps
	var n := int(roundf(size / sp)) + 2 * steps + 1
	var lo := INF
	var hi := -INF
	for j in n:
		for i in n:
			var h := field.at(i0 + i, j0 + j)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## An obstacle from a ChunkData solid ([kind, x, y, z, sx, sy, sz, yaw] at `o`), in world space.
static func solid_obstacle(solids: PackedFloat32Array, o: int, chunk_origin: Vector3) -> Dictionary:
	var centre := chunk_origin + Vector3(solids[o + 1], solids[o + 2], solids[o + 3])
	var xform := Transform3D(Basis(Vector3.UP, solids[o + 7]), centre)
	if int(solids[o]) == ChunkData.SOLID_CYLINDER:
		return {"shape": "cyl", "xform": xform, "size": Vector3(solids[o + 4], solids[o + 5], solids[o + 4])}
	return {"shape": "box", "xform": xform, "size": Vector3(solids[o + 4], solids[o + 5], solids[o + 6])}


## Every solid of a chunk as an obstacle (world space).
static func chunk_obstacles(d: ChunkData) -> Array:
	var out: Array = []
	for k in d.solids.size() / ChunkData.SOLID_STRIDE:
		out.append(solid_obstacle(d.solids, k * ChunkData.SOLID_STRIDE, d.origin))
	return out


## The collision shapes of every StaticBody3D below `node` (a props element: a breakable house, a
## gate, a fence, a landmark) as obstacles in the space `xform` puts `node` in (world space when it
## is the node's world transform). Area3D shapes (hurtboxes) are not obstacles.
static func static_shapes(node: Node, xform: Transform3D, out: Array) -> void:
	for child in node.get_children():
		var t := xform * (child as Node3D).transform if child is Node3D else xform
		if child is CollisionShape3D and node is StaticBody3D and not (child as CollisionShape3D).disabled:
			var s := (child as CollisionShape3D).shape
			if s is BoxShape3D:
				out.append({"shape": "box", "xform": t, "size": (s as BoxShape3D).size})
			elif s is CylinderShape3D:
				var cy := s as CylinderShape3D
				out.append({"shape": "cyl", "xform": t, "size": Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0)})
			elif s is CapsuleShape3D:
				var cp := s as CapsuleShape3D
				out.append({"shape": "cyl", "xform": t, "size": Vector3(cp.radius * 2.0, cp.height, cp.radius * 2.0)})
			elif s != null:
				var aabb := s.get_debug_mesh().get_aabb()
				out.append({"shape": "box", "xform": t * Transform3D(Basis(), aabb.get_center()), "size": aabb.size})
		static_shapes(child, t, out)


## The horizontal footprint of an obstacle (world or local, as its xform): a convex polygon.
static func footprint(s: Dictionary) -> PackedVector2Array:
	var xf: Transform3D = s.xform
	var size: Vector3 = s.size
	var pts := PackedVector2Array()
	if str(s.shape) == "cyl":
		var r := size.x * 0.5
		for i in CYL_SIDES:
			var a := TAU * float(i) / CYL_SIDES
			pts.append(Vector2(xf.origin.x + cos(a) * r, xf.origin.z + sin(a) * r))
		return pts
	var b := xf.basis.orthonormalized()
	var h := size * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := xf.origin + b * Vector3(h.x * sx, 0.0, h.z * sz)
			pts.append(Vector2(p.x, p.z))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)   # convex_hull repeats the first point
	return hull


## True when the obstacle's footprint reaches into the rectangle (world x, z).
static func touches(s: Dictionary, rect: Rect2) -> bool:
	var fp := footprint(s)
	if fp.is_empty():
		return false
	var lo := fp[0]
	var hi := fp[0]
	for p in fp:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo).grow(0.01).intersects(rect)


## The side faces of an obstacle (no top: nothing walks on it), clockwise seen from outside, moved
## by `shift` (world -> chunk-local).
static func obstacle_faces(s: Dictionary, shift: Vector3) -> PackedVector3Array:
	var xf: Transform3D = s.xform
	var size: Vector3 = s.size
	var out := PackedVector3Array()
	var y0 := xf.origin.y - size.y * 0.5 + shift.y
	var y1 := xf.origin.y + size.y * 0.5 + shift.y
	var fp := footprint(s)
	var n := fp.size()
	# The footprint as convex_hull returns it runs counter-clockwise in (x, z); the outward side face
	# of edge a -> b seen from outside is then a0, a1, b1, b0 reversed for Godot's clockwise front.
	for i in n:
		var a := fp[i] + Vector2(shift.x, shift.z)
		var b := fp[(i + 1) % n] + Vector2(shift.x, shift.z)
		var a0 := Vector3(a.x, y0, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var a1 := Vector3(a.x, y1, a.y)
		var b1 := Vector3(b.x, y1, b.y)
		out.append_array([a0, a1, b1, a0, b1, b0])
	return out


## The obstacle as a projected obstruction (its footprint, from just under its base to its top):
## no navmesh island is left inside or on it.
static func add_obstacle(src: NavigationMeshSourceGeometryData3D, s: Dictionary, shift: Vector3) -> void:
	src.add_faces(obstacle_faces(s, shift), Transform3D.IDENTITY)
	var xf: Transform3D = s.xform
	var size: Vector3 = s.size
	var outline := PackedVector3Array()
	for p in footprint(s):
		outline.append(Vector3(p.x + shift.x, 0.0, p.y + shift.z))
	var base := xf.origin.y - size.y * 0.5 + shift.y
	src.add_projected_obstruction(outline, base - 0.25, size.y + 0.5, false)


## Rectangles (world x, z) covering the cells of `water` ([{"rect": Rect2, "surface_y"}]) inside
## `area` whose water is deeper than `limit` over the field's ground, merged along x per row of
## WATER_CELL_M cells: [{"rect", "floor_y", "surface_y"}].
static func deep_water(field: HeightField, water: Array, area: Rect2, limit := MAX_WADE_M) -> Array:
	var out: Array = []
	for w: Dictionary in water:
		var r: Rect2 = (w.rect as Rect2).intersection(area)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		var surface := float(w.surface_y)
		var c := WATER_CELL_M
		var x0 := floorf(r.position.x / c) * c
		var z0 := floorf(r.position.y / c) * c
		var nx := int(ceilf((r.end.x - x0) / c))
		var nz := int(ceilf((r.end.y - z0) / c))
		for j in nz:
			var z := z0 + j * c
			var run_start := -1
			var run_floor := INF
			for i in nx + 1:
				var deep := false
				var ground := INF
				if i < nx:
					var x := x0 + i * c
					ground = field.sample(x + c * 0.5, z + c * 0.5)
					deep = surface - ground > limit
				if deep:
					if run_start < 0:
						run_start = i
						run_floor = ground
					run_floor = minf(run_floor, ground)
				elif run_start >= 0:
					out.append({"rect": Rect2(x0 + run_start * c, z, (i - run_start) * c, c), "floor_y": run_floor,
						"surface_y": surface})
					run_start = -1
					run_floor = INF
	return out


## The navigation source of one chunk for one layer, in chunk-local coordinates: its terrain and
## margin (where `walkable` allows), every obstacle in `obstacles` (world space; this chunk's and its neighbours')
## that reaches into the bake area, and (layers with wade_limit) every deep-water cell of `water`
## (world rectangles with their surface) as an obstruction.
static func source_for(spec: Dictionary, field: HeightField, origin: Vector3, size: float, obstacles: Array,
		water: Array, walkable := Callable()) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(terrain_faces(field, origin, size, TERRAIN_MARGIN_M, walkable), Transform3D.IDENTITY)
	var reach := border_for(spec) + 1.0
	var area := Rect2(origin.x - reach, origin.z - reach, size + 2.0 * reach, size + 2.0 * reach)
	var shift := Vector3(-origin.x, 0.0, -origin.z)
	for s: Dictionary in obstacles:
		if touches(s, area):
			add_obstacle(src, s, shift)
	if bool(spec.get("wade_limit", false)):
		for cell: Dictionary in deep_water(field, water, area):
			var r: Rect2 = cell.rect
			var outline := PackedVector3Array([Vector3(r.position.x + shift.x, 0.0, r.position.y + shift.z),
				Vector3(r.end.x + shift.x, 0.0, r.position.y + shift.z), Vector3(r.end.x + shift.x, 0.0, r.end.y + shift.z),
				Vector3(r.position.x + shift.x, 0.0, r.end.y + shift.z)])
			var bottom := float(cell.floor_y) - 1.0
			src.add_projected_obstruction(outline, bottom, float(cell.surface_y) + 2.0 - bottom, false)
	return src


# --------------------------------------------------------------------------- baking

## Bakes one layer of a chunk from its source (chunk-local): the AABB grown by the border, its y
## origin on the world-wide grid of the layer's cell height; then every vertex moved down by the
## layer's lower_m.
static func bake_layer(spec: Dictionary, src: NavigationMeshSourceGeometryData3D, size: float, ground: Vector2) -> NavigationMesh:
	var nm := new_mesh(spec)
	var border := border_for(spec)
	var ch := float(spec.cell_height)
	var y0 := floorf((ground.x - AABB_FLOOR_DROP_M) / ch) * ch
	var y1 := ceilf((ground.y + AABB_HEADROOM_M) / ch) * ch
	nm.border_size = border
	nm.filter_baking_aabb = AABB(Vector3(-border, y0, -border), Vector3(size + 2.0 * border, y1 - y0, size + 2.0 * border))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var lower := float(spec.get("lower_m", 0.0))
	if lower != 0.0:
		var v := nm.get_vertices()
		for i in v.size():
			v[i].y -= lower
		nm.set_vertices(v)
	return nm


## The polygons of `nm` split by gate: a polygon belongs to a gate region when gate_at
## (Callable(world_x, world_z) -> int: 0, or a gate bit) marks any of its sample points - its centre,
## its corners and points every GATE_SAMPLE_M along its edges (chunk-local + origin) - the highest
## bit found wins. So every polygon that touches gated ground is gated: Recast's long thin polygons
## along a tile border reach from a bank into the water, and one left in the ungated part would let
## a query without the bit cross. Returns {bit: NavigationMesh} with the ungated part under
## `base_bit`; parts without polygons are left out. Every part keeps the bake settings and its own
## copy of the vertices it uses (shared border vertices stay identical).
static func split_gates(nm: NavigationMesh, spec: Dictionary, origin: Vector3, gate_at: Callable, base_bit: int) -> Dictionary:
	var verts := nm.get_vertices()
	var groups := {}   # bit -> Array of polygons (PackedInt32Array)
	for p in nm.get_polygon_count():
		var poly := nm.get_polygon(p)
		var bit := polygon_gate(verts, poly, origin, gate_at) if gate_at.is_valid() else 0
		var key := bit if bit > 0 else base_bit
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(poly)
	var out := {}
	var keys := groups.keys()
	keys.sort()
	for key: int in keys:
		var part := new_mesh(spec)
		part.border_size = nm.border_size
		part.filter_baking_aabb = nm.filter_baking_aabb
		var remap := {}
		var pv := PackedVector3Array()
		for poly: PackedInt32Array in groups[key]:
			var np := PackedInt32Array()
			for idx in poly:
				if not remap.has(idx):
					remap[idx] = pv.size()
					pv.append(verts[idx])
				np.append(int(remap[idx]))
			part.add_polygon(np)
		part.set_vertices(pv)
		out[key] = part
	return out


## The highest gate bit gate_at marks at a polygon's sample points (see split_gates); 0 for none.
static func polygon_gate(verts: PackedVector3Array, poly: PackedInt32Array, origin: Vector3, gate_at: Callable) -> int:
	var best := 0
	var c := Vector3.ZERO
	for k in poly.size():
		var a := verts[poly[k]]
		var b := verts[poly[(k + 1) % poly.size()]]
		c += a
		var steps := maxi(1, int(ceilf(Vector2(b.x - a.x, b.z - a.z).length() / GATE_SAMPLE_M)))
		for i in steps:
			var q := a.lerp(b, float(i) / float(steps))
			best = maxi(best, int(gate_at.call(q.x + origin.x, q.z + origin.z)))
	c /= maxf(1.0, float(poly.size()))
	return maxi(best, int(gate_at.call(c.x + origin.x, c.z + origin.z)))


## Every navmesh of one chunk: {bit: NavigationMesh} for the human (1), large (2) and titan (16)
## layers and the titan gate regions (32 / 64 / 128) gate_at marks. `obstacles` and `water` are in
## world space (water: [{"rect": Rect2 world x, z, "surface_y"}]); `walkable` (Callable(world_x,
## world_z) -> bool) leaves the terrain it refuses out. Layers without a polygon are left out.
static func bake_chunk(field: HeightField, origin: Vector3, size: float, obstacles: Array, water: Array,
		gate_at := Callable(), walkable := Callable()) -> Dictionary:
	var out := {}
	var ground := height_range(field, origin, size)
	for spec: Dictionary in LAYERS:
		var src := source_for(spec, field, origin, size, obstacles, water, walkable)
		var nm := bake_layer(spec, src, size, ground)
		if nm.get_polygon_count() == 0:
			continue
		if int(spec.layer) == TITAN_LAYER:
			var parts := split_gates(nm, spec, origin, gate_at, TITAN_LAYER)
			for bit: int in parts:
				out[bit] = parts[bit]
		else:
			out[int(spec.layer)] = nm
	return out


## Saves a chunk's navmeshes (compressed) under `dir` (a res:// folder, mapped through `to_disk`
## when the builder writes elsewhere) and returns {bit: res:// path}, the ChunkData's `nav`.
static func save_chunk(meshes: Dictionary, dir: String, chunk_id: String, to_disk := Callable()) -> Dictionary:
	var out := {}
	var bits := meshes.keys()
	bits.sort()
	for bit: int in bits:
		var path := nav_path(dir, chunk_id, bit)
		var disk := str(to_disk.call(path)) if to_disk.is_valid() else path
		DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
		var err := ResourceSaver.save(meshes[bit], disk, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("NavBake: could not save %s (error %d)" % [disk, err])
			continue
		out[bit] = path
	return out


## Polygon and vertex counts of a chunk's navmeshes: {bit: {"polygons", "vertices"}}.
static func counts(meshes: Dictionary) -> Dictionary:
	var out := {}
	for bit: int in meshes:
		var nm := meshes[bit] as NavigationMesh
		out[bit] = {"polygons": nm.get_polygon_count(), "vertices": nm.get_vertices().size()}
	return out
