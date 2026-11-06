class_name SkylineWriter
extends RefCounted
## Writes a streamed world's skyline (P24a; plan M6-M9 §2.8, §5.3, decision 12): the coarse
## terrain of the whole world, drawn by scripts/world/skyline.gd wherever no chunk's own terrain is,
## and the merged landmark silhouettes.
##
## coarse(): one vertex every COARSE_M metres, each the lowest fine height within COARSE_M of it
## (the square of the four coarse cells around it) minus DROP_M - so the coarse surface, linear
## between its vertices, stays under the fine one everywhere and never pokes through a drawn chunk
## at its edge (risk 23). terrain_mesh(): that grid as one vertex-coloured mesh (the colour from a
## Callable: the region's skyline_tint). landmarks_mesh(): boxes, cylinders and cones merged into one
## vertex-coloured mesh. Tools only (tools/ is never exported).

const COARSE_M := 32.0
const DROP_M := 2.0
const CYLINDER_SIDES := 8


## The coarse grid over the world rectangle `rect` (x, z): {"origin": Vector2 (x, z of vertex 0),
## "spacing": coarse_m, "size": Vector2i, "h": PackedFloat32Array}.
static func coarse(field: HeightField, rect: Rect2, coarse_m := COARSE_M, drop_m := DROP_M) -> Dictionary:
	var nx := int(roundf(rect.size.x / coarse_m)) + 1
	var nz := int(roundf(rect.size.y / coarse_m)) + 1
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var reach := int(ceil(coarse_m / field.spacing))
	for j in nz:
		var z := rect.position.y + j * coarse_m
		var fj := int(roundf((z - field.origin.y) / field.spacing))
		for i in nx:
			var x := rect.position.x + i * coarse_m
			var fi := int(roundf((x - field.origin.x) / field.spacing))
			var lo := INF
			for dj in range(-reach, reach + 1):
				for di in range(-reach, reach + 1):
					lo = minf(lo, field.at(fi + di, fj + dj))
			out[j * nx + i] = lo - drop_m
	return {"origin": rect.position, "spacing": coarse_m, "size": Vector2i(nx, nz), "h": out}


## The height of the coarse surface at world (x, z): the triangle the mesh draws there (each coarse
## cell split along its (i, j) - (i + 1, j + 1) diagonal). NaN outside the grid.
static func coarse_height(c: Dictionary, x: float, z: float) -> float:
	var sz: Vector2i = c.size
	var o: Vector2 = c.origin
	var s := float(c.spacing)
	var fx := (x - o.x) / s
	var fz := (z - o.y) / s
	if fx < 0.0 or fz < 0.0 or fx > sz.x - 1 or fz > sz.y - 1:
		return NAN
	var i := mini(int(fx), sz.x - 2)
	var j := mini(int(fz), sz.y - 2)
	var tx := fx - i
	var tz := fz - j
	var hh: PackedFloat32Array = c.h
	var h00 := hh[j * sz.x + i]
	var h10 := hh[j * sz.x + i + 1]
	var h01 := hh[(j + 1) * sz.x + i]
	var h11 := hh[(j + 1) * sz.x + i + 1]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h01 - h00) * tz + (h11 - h01) * tx


## The coarse grid as one mesh (world coordinates), coloured by color_at.call(x, z) -> Color.
static func terrain_mesh(c: Dictionary, color_at: Callable) -> ArrayMesh:
	var sz: Vector2i = c.size
	var o: Vector2 = c.origin
	var s := float(c.spacing)
	var hh: PackedFloat32Array = c.h
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for j in sz.y:
		for i in sz.x:
			var x := o.x + i * s
			var z := o.y + j * s
			v.append(Vector3(x, hh[j * sz.x + i], z))
			var hl := hh[j * sz.x + maxi(i - 1, 0)]
			var hr := hh[j * sz.x + mini(i + 1, sz.x - 1)]
			var hu := hh[maxi(j - 1, 0) * sz.x + i]
			var hd := hh[mini(j + 1, sz.y - 1) * sz.x + i]
			nrm.append(Vector3((hl - hr) / (2.0 * s), 1.0, (hu - hd) / (2.0 * s)).normalized())
			col.append(color_at.call(x, z) as Color)
	for j in sz.y - 1:
		for i in sz.x - 1:
			var k := j * sz.x + i
			idx.append_array([k, k + 1, k + sz.x + 1, k, k + sz.x + 1, k + sz.x])
	return _mesh(v, nrm, col, idx)


## Landmark silhouettes as one mesh: shapes [{"shape": "box" | "cylinder" | "cone", "position":
## Vector3 (the base centre), "size": Vector3 (box size; cylinder / cone: diameter, height,
## unused), "yaw": radians, "color": Color}].
static func landmarks_mesh(shapes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Dictionary in shapes:
		var pos: Vector3 = s.position
		var size: Vector3 = s.size
		var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0)))
		st.set_color(s.get("color", Color(0.4, 0.4, 0.42)) as Color)
		match str(s.shape):
			"box":
				_box(st, Transform3D(basis, pos + Vector3.UP * size.y * 0.5), size)
			"cylinder":
				_cone(st, pos, size.x * 0.5, size.x * 0.5, size.y)
			"cone":
				_cone(st, pos, size.x * 0.5, 0.0, size.y)
	st.generate_normals()
	return st.commit()


static func _box(st: SurfaceTool, t: Transform3D, size: Vector3) -> void:
	var hx := size * 0.5
	var c: Array[Vector3] = []
	for p: Vector3 in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
			Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		c.append(t * (p * hx))
	# faces (clockwise seen from outside: Godot's front faces)
	for q: Array in [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for k: int in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(c[k])


static func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, height: float) -> void:
	for k in CYLINDER_SIDES:
		var a := TAU * float(k) / CYLINDER_SIDES
		var b := TAU * float(k + 1) / CYLINDER_SIDES
		var p0 := base + Vector3(cos(a) * r0, 0.0, sin(a) * r0)
		var p1 := base + Vector3(cos(b) * r0, 0.0, sin(b) * r0)
		var q0 := base + Vector3(cos(a) * r1, height, sin(a) * r1)
		var q1 := base + Vector3(cos(b) * r1, height, sin(b) * r1)
		if r1 <= 0.0:
			for v: Vector3 in [p0, p1, q1]:
				st.add_vertex(v)
			continue
		for v: Vector3 in [p0, p1, q1, p0, q1, q0]:
			st.add_vertex(v)
		var top := base + Vector3.UP * height
		for v: Vector3 in [top, q0, q1]:
			st.add_vertex(v)


static func _mesh(v: PackedVector3Array, nrm: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = nrm
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh
