class_name HollowArmour
extends RefCounted
## E3: the Hollow Titan's armour, made when his model is (no file: a few tens of thousands of triangles from plain
## numbers, the same plates every time) - plates with a real thickness (an outer face, an inner face and the rolled edge
## between them), lofted from sections round an axis: a breastplate, pauldrons of three lames, a great helm with its eye
## slit, greaves, gauntlets, the Kingsword. Built in model space (the Stormcaller's frame: 34 m, facing +Z, his left +X),
## then carried into the bone each rides (HollowModel). Presentation only.
##
## The vertex colour (hollow_armour.gdshader): r = edge wear (1 on a plate's rim fading inward), g = gilt (the trims),
## b = the plate's own tone, a = 1 on an outer face, 0 on an inner face (inside the shell: near black, the knot's light).

## A builder: add shapes, then mesh().
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var tone := 0.5


## A plate lofted from `rings` - each [Vector3 centre, Vector3 u (the section's first half-axis, its length the radius
## that way), Vector3 v (the second), float gilt (0..1: a trim band at this ring)] - over the angle range a0..a1 (radians
## from u toward v; a full turn closes the loop) in `cols` steps; `thick` thick (inward). Each ring may carry a fifth
## element: a Callable(angle) -> extra radius (a ridge). `rim_gilt`: the gilt of the plate's side edges (a partial arc).
func loft(rings: Array, a0: float, a1: float, cols: int, thick: float, xf := Transform3D.IDENTITY, rim_gilt := 0.0,
		wear_w := 0.18) -> void:
	var closed := absf(a1 - a0) >= TAU - 1e-3
	var grid: Array = []
	var gilt_rows: Array = []
	for r: Array in rings:
		var c: Vector3 = r[0]
		var u: Vector3 = r[1]
		var v: Vector3 = r[2]
		var extra: Callable = r[4] if r.size() > 4 else Callable()
		var row: Array[Vector3] = []
		var n := cols if closed else cols + 1
		for k in n:
			var a := lerpf(a0, a1, float(k) / float(cols))
			var dir := u * cos(a) + v * sin(a)
			if extra.is_valid():
				dir += dir.normalized() * float(extra.call(a))
			row.append(xf * (c + dir))
		grid.append(row)
		gilt_rows.append(float(r[3]) if r.size() > 3 else 0.0)
	sheet(grid, closed, thick, gilt_rows, rim_gilt, wear_w)


## A surface from a grid of outer points (rows along the loft, columns round it; `closed`: the columns wrap), given a
## thickness: its outer face, its inner face `thick` in along the normals, and the edge strips that join them on every
## open border. Wear fades in from each border over `wear_w` of the grid (its share of rows / columns); `gilt_rows` a
## gilt per row, `rim_gilt` on the side borders of an open plate.
func sheet(grid: Array, closed: bool, thick: float, gilt_rows: Array = [], rim_gilt := 0.0, wear_w := 0.18) -> void:
	var rows := grid.size()
	if rows < 2:
		return
	var cols := (grid[0] as Array).size()
	var normals: Array = []
	for i in rows:
		var nrow: Array[Vector3] = []
		for k in cols:
			var ip := mini(i + 1, rows - 1)
			var im := maxi(i - 1, 0)
			var kp := (k + 1) % cols if closed else mini(k + 1, cols - 1)
			var km := (k - 1 + cols) % cols if closed else maxi(k - 1, 0)
			var du: Vector3 = (grid[ip] as Array)[k] - (grid[im] as Array)[k]
			var dv: Vector3 = (grid[i] as Array)[kp] - (grid[i] as Array)[km]
			var n := dv.cross(du)
			nrow.append(n.normalized() if n.length() > 1e-6 else Vector3.UP)
		normals.append(nrow)
	# which way is out: the normals should point away from the grid's middle on average
	var mid := Vector3.ZERO
	for i in rows:
		for k in cols:
			mid += (grid[i] as Array)[k]
	mid /= float(rows * cols)
	var score := 0.0
	for i in rows:
		for k in cols:
			score += ((normals[i] as Array)[k] as Vector3).dot((grid[i] as Array)[k] - mid)
	var flip := score < 0.0
	if flip:
		for i in rows:
			for k in cols:
				(normals[i] as Array)[k] = -((normals[i] as Array)[k] as Vector3)
	var outer := _grid_verts(grid, normals, rows, cols, closed, gilt_rows, rim_gilt, wear_w, 0.0, 1.0)
	var inner_grid: Array = []
	for i in rows:
		var row: Array[Vector3] = []
		for k in cols:
			row.append((grid[i] as Array)[k] - ((normals[i] as Array)[k] as Vector3) * thick)
		inner_grid.append(row)
	var inner_normals: Array = []
	for i in rows:
		var nrow: Array[Vector3] = []
		for k in cols:
			nrow.append(-((normals[i] as Array)[k] as Vector3))
		inner_normals.append(nrow)
	var inner := _grid_verts(inner_grid, inner_normals, rows, cols, closed, gilt_rows, 0.0, wear_w, 0.0, 0.0)
	var kc := cols if closed else cols - 1
	for i in rows - 1:
		for k in kc:
			var k1 := (k + 1) % cols
			_quad_out(outer[i][k], outer[i + 1][k], outer[i + 1][k1], outer[i][k1], normals[i][k])
			_quad_out(inner[i][k1], inner[i + 1][k1], inner[i + 1][k], inner[i][k], inner_normals[i][k])
	# the edges between the faces: the first and last rows, and (an open plate) the first and last columns
	var borders: Array = [[0, -1], [rows - 1, 1]]
	for b: Array in borders:
		var i: int = b[0]
		var side: float = b[1]
		for k in kc:
			var k1 := (k + 1) % cols
			var along: Vector3 = (grid[mini(i + 1, rows - 1)] as Array)[k] - (grid[maxi(i - 1, 0)] as Array)[k]
			var out := along.normalized() * side
			_edge(grid[i][k], grid[i][k1], inner_grid[i][k1], inner_grid[i][k], out, float(gilt_rows[i]) if i < gilt_rows.size() else 0.0)
	if not closed:
		for b: Array in [[0, -1], [cols - 1, 1]]:
			var k: int = b[0]
			var side: float = b[1]
			for i in rows - 1:
				var across: Vector3 = (grid[i] as Array)[mini(k + 1, cols - 1)] - (grid[i] as Array)[maxi(k - 1, 0)]
				_edge(grid[i + 1][k], grid[i][k], inner_grid[i][k], inner_grid[i + 1][k], across.normalized() * side, rim_gilt)


func _grid_verts(grid: Array, normals: Array, rows: int, cols: int, closed: bool, gilt_rows: Array, rim_gilt: float,
		wear_w: float, _unused: float, outside: float) -> Array:
	var out: Array = []
	for i in rows:
		var row: Array[int] = []
		var fi := float(i) / float(rows - 1)
		var edge_r := minf(fi, 1.0 - fi)
		for k in cols:
			var fk := float(k) / float(maxi(cols - 1, 1))
			var edge := edge_r
			if not closed:
				edge = minf(edge, minf(fk, 1.0 - fk))
			var wear := 1.0 - clampf(edge / maxf(wear_w, 1e-3), 0.0, 1.0)
			var g := float(gilt_rows[i]) if i < gilt_rows.size() else 0.0
			if not closed and minf(fk, 1.0 - fk) < 0.06:
				g = maxf(g, rim_gilt)
			row.append(_vert((grid[i] as Array)[k], (normals[i] as Array)[k], Color(wear * wear, g, tone, outside)))
		out.append(row)
	return out


func _vert(p: Vector3, n: Vector3, c: Color) -> int:
	_verts.append(p)
	_norms.append(n)
	_cols.append(c)
	return _verts.size() - 1


## A quad of existing vertices whose face points along `want` (its winding set for Godot's front faces).
func _quad_out(a: int, b: int, c: int, d: int, want: Vector3) -> void:
	var n := (_verts[b] - _verts[a]).cross(_verts[c] - _verts[a])
	if n.dot(want) < 0.0:
		_idx.append_array([a, b, c, a, c, d])
	else:
		_idx.append_array([a, c, b, a, d, c])


## An edge strip between the outer and inner faces (worn bright, its own normal `out`).
func _edge(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, gilt: float) -> void:
	var col := Color(1.0, gilt, tone, 1.0)
	var ia := _vert(a, out, col)
	var ib := _vert(b, out, col)
	var ic := _vert(c, out, col)
	var id := _vert(d, out, col)
	_quad_out(ia, ib, ic, id, out)


## A ring of `count` links of chain along a path of points (each link a flattened torus, turned 90 degrees to the last).
func chain(points: PackedVector3Array, link_len: float, link_r: float, wire: float, xf := Transform3D.IDENTITY) -> void:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var n := maxi(1, int(total / (link_len * 0.78)))
	var flip := false
	for j in n:
		var at := (float(j) + 0.5) / float(n) * total
		var acc := 0.0
		for i in points.size() - 1:
			var seg := points[i].distance_to(points[i + 1])
			if acc + seg >= at or i == points.size() - 2:
				var t := clampf((at - acc) / maxf(seg, 1e-4), 0.0, 1.0)
				var c := points[i].lerp(points[i + 1], t)
				var d := (points[i + 1] - points[i]).normalized()
				link(c, d, link_len, link_r, wire, flip, xf)
				break
			acc += seg
		flip = not flip


## One link: an oval ring round `centre`, long along `dir`, its plane turned by `flip`.
func link(centre: Vector3, dir: Vector3, length: float, width: float, wire: float, flip := false,
		xf := Transform3D.IDENTITY) -> void:
	var side := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	if flip:
		side = dir.cross(side).normalized()
	var seg := 14
	var tube := 6
	var ring: Array = []
	for s in seg:
		var a := TAU * float(s) / float(seg)
		var p := centre + dir * cos(a) * (length * 0.5 - wire) + side * sin(a) * (width * 0.5 - wire)
		var t := (-dir * sin(a) * (length * 0.5 - wire) + side * cos(a) * (width * 0.5 - wire)).normalized()
		var b1 := t.cross(dir.cross(side).normalized()).normalized()
		var b2 := dir.cross(side).normalized()
		var row: Array[int] = []
		for k in tube:
			var q := TAU * float(k) / float(tube)
			var nrm := b1 * cos(q) + b2 * sin(q)
			row.append(_vert(xf * (p + nrm * wire), (xf.basis * nrm).normalized(), Color(0.7, 0.0, tone, 1.0)))
		ring.append(row)
	for s in seg:
		var s1 := (s + 1) % seg
		for k in tube:
			var k1 := (k + 1) % tube
			var want := _norms[ring[s][k]]
			_quad_out(ring[s][k], ring[s1][k], ring[s1][k1], ring[s][k1], want)


## A spike (a crown's tine, a rivet's head): a cone from `base` along `dir`, `length`, `radius` at its foot, `sides` round.
func spike(base: Vector3, dir: Vector3, length: float, radius: float, gilt := 1.0, sides := 8,
		xf := Transform3D.IDENTITY) -> void:
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var tip := xf * (base + dir * length)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		var p0 := xf * (base + n0 * radius)
		var p1 := xf * (base + n1 * radius)
		var slope := radius / maxf(length, 1e-3)
		var nn0 := (xf.basis * (n0 + dir * slope)).normalized()
		var nn1 := (xf.basis * (n1 + dir * slope)).normalized()
		var c := Color(0.5, gilt, tone, 1.0)
		var i0 := _vert(p0, nn0, c)
		var i1 := _vert(p1, nn1, c)
		var it := _vert(tip, (nn0 + nn1).normalized(), Color(1.0, gilt, tone, 1.0))
		var n := (p1 - p0).cross(tip - p0)
		if n.dot(nn0 + nn1) < 0.0:
			_idx.append_array([i0, i1, it])
		else:
			_idx.append_array([i0, it, i1])


## A blade from `hilt` along `dir`: `length` long, `width` wide at the guard tapering to `tip_w` (a point), `thick` at
## its spine, flat in the plane of `flat` (its edge direction), a fuller down its middle.
func blade(hilt: Vector3, dir: Vector3, flat: Vector3, length: float, width: float, tip_w: float, thick: float,
		xf := Transform3D.IDENTITY) -> void:
	dir = dir.normalized()
	var edge := (flat - dir * flat.dot(dir)).normalized()
	var face := dir.cross(edge).normalized()
	var segs := 10
	var grid: Array = []
	for s in segs + 1:
		var t := float(s) / float(segs)
		var w := lerpf(width, tip_w, pow(t, 1.4)) * 0.5
		if s == segs:
			w = 0.02
		var c := hilt + dir * length * t
		var th := thick * 0.5 * (1.0 - 0.75 * t)
		# a lozenge section: edge, spine, edge, spine
		var row: Array[Vector3] = [c + edge * w, c + face * th * 0.6 + edge * w * 0.3, c + face * th,
			c + face * th * 0.6 - edge * w * 0.3, c - edge * w, c - face * th * 0.6 - edge * w * 0.3, c - face * th,
			c - face * th * 0.6 + edge * w * 0.3]
		var xrow: Array[Vector3] = []
		for p in row:
			xrow.append(xf * p)
		grid.append(xrow)
	var rows := grid.size()
	var cols := 8
	for i in rows - 1:
		for k in cols:
			var k1 := (k + 1) % cols
			var a: Vector3 = grid[i][k]
			var b: Vector3 = grid[i + 1][k]
			var c2: Vector3 = grid[i + 1][k1]
			var d: Vector3 = grid[i][k1]
			var mid := (xf * (hilt + dir * length * (float(i) + 0.5) / float(segs)))
			var n := ((a + b + c2 + d) * 0.25 - mid).normalized()
			var wear := 1.0 if k == 0 or k == 4 else 0.15
			var col := Color(wear, 0.0, tone, 1.0)
			_quad_out(_vert(a, n, col), _vert(b, n, col), _vert(c2, n, col), _vert(d, n, col), n)


## A closed box (a guard's bar, a gauntlet's knuckles) from its centre and half-axes.
func box(centre: Vector3, ax: Vector3, ay: Vector3, az: Vector3, gilt := 0.0, xf := Transform3D.IDENTITY) -> void:
	var faces := [[ax, ay, az], [-ax, ay, -az], [ay, az, ax], [-ay, az, -ax], [az, ax, ay], [-az, ax, -ay]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := centre + n
		var nn := (xf.basis * n).normalized()
		var col := Color(0.6, gilt, tone, 1.0)
		var i0 := _vert(xf * (c - u - v), nn, col)
		var i1 := _vert(xf * (c + u - v), nn, col)
		var i2 := _vert(xf * (c + u + v), nn, col)
		var i3 := _vert(xf * (c - u + v), nn, col)
		_quad_out(i0, i1, i2, i3, nn)


func is_empty() -> bool:
	return _idx.is_empty()


func triangles() -> int:
	return _idx.size() / 3


func mesh() -> ArrayMesh:
	if _idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_NORMAL] = _norms
	arr[Mesh.ARRAY_COLOR] = _cols
	arr[Mesh.ARRAY_INDEX] = _idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A section ring for loft(): at `centre`, radii `rx` (along `x`) and `rz` (along `z`), its gilt.
static func ring(centre: Vector3, x: Vector3, z: Vector3, rx: float, rz: float, gilt := 0.0, extra := Callable()) -> Array:
	var r: Array = [centre, x.normalized() * rx, z.normalized() * rz, gilt]
	if extra.is_valid():
		r.append(extra)
	return r
