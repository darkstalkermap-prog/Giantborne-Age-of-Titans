class_name CinderGear
extends RefCounted
## E2: the Cinder Titan's own gear, made when his model is (no file: a few thousand triangles from a seeded RNG, so the
## same horns every time) - the slag horns of his crown, the spines along his back and shoulders, the Cinder-brand's
## haft and head. Each a mesh of bent, tapering, jagged cones or a lumpy ball, its UV in metres (cinder_plate.gdshader
## maps Stoneback's stone normal and its seams on it). Built in model space (the Stormcaller's frame: 34 m, facing +Z),
## then carried into the bone each rides (CinderModel). Presentation only.

## A builder: add shapes, then mesh().
var _st := SurfaceTool.new()
var _rng := RandomNumberGenerator.new()
var _any := false


func _init(seed_value := 7) -> void:
	_rng.seed = seed_value
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func rng() -> RandomNumberGenerator:
	return _rng


## A horn or a spike from `base` along `dir` (unit), `length` long, `radius` at its foot tapering to a point, bending
## toward `bend` (a direction) by its tip; `sides` round, `segs` along, its surface jittered by `jag` of its radius.
func spike(base: Vector3, dir: Vector3, length: float, radius: float, bend := Vector3.ZERO, sides := 7, segs := 6,
		jag := 0.18, xf := Transform3D.IDENTITY) -> void:
	dir = dir.normalized()
	var rings: Array = []
	var centres: Array[Vector3] = []
	var p := base
	var d := dir
	var step := length / float(segs)
	for s in segs + 1:
		var t := float(s) / float(segs)
		centres.append(p)
		var side := d.cross(Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(d).normalized()
		var r := radius * pow(1.0 - t, 0.85) + 0.02 * radius
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var j := 1.0 + _rng.randf_range(-jag, jag) * (1.0 - t * 0.5)
			ring.append(p + (side * cos(a) + up * sin(a)) * r * j)
		rings.append(ring)
		if bend != Vector3.ZERO:
			d = d.slerp(bend.normalized(), 1.0 / float(segs) * 0.9).normalized()
		p += d * step
	var v := 0.0
	for s in segs:
		var a0: Array[Vector3] = rings[s]
		var a1: Array[Vector3] = rings[s + 1]
		var dv := (centres[s + 1] - centres[s]).length()
		for k in sides:
			var k1 := (k + 1) % sides
			var u0 := float(k) / float(sides) * TAU * radius
			var u1 := float(k + 1) / float(sides) * TAU * radius
			_quad(xf * a0[k], xf * a0[k1], xf * a1[k1], xf * a1[k], Vector2(u0, v), Vector2(u1, v),
				Vector2(u1, v + dv), Vector2(u0, v + dv))
		v += dv
	# the foot's cap (seen where it stands proud of the skin)
	var c0 := xf * base
	var r0: Array[Vector3] = rings[0]
	for k in sides:
		_tri(c0, xf * r0[(k + 1) % sides], xf * r0[k], Vector2(0, 0), Vector2(0.3, 0), Vector2(0, 0.3))
	_any = true


## A lumpy ball of slag at `centre`, `radii` its half-sizes (x, y, z in `basis`'s frame), its surface jittered by `jag`.
func lump(centre: Vector3, radii: Vector3, basis := Basis.IDENTITY, jag := 0.22, rows := 9, cols := 14,
		xf := Transform3D.IDENTITY) -> void:
	var pts: Array = []
	var phase := Vector3(_rng.randf() * 10.0, _rng.randf() * 10.0, _rng.randf() * 10.0)
	for i in rows + 1:
		var th := PI * float(i) / float(rows)
		var row: Array[Vector3] = []
		for j in cols:
			var ph := TAU * float(j) / float(cols)
			var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var w := 1.0 + jag * (sin(n.x * 3.1 + phase.x) * sin(n.y * 2.7 + phase.y) + 0.6 * sin(n.z * 4.3 + phase.z)) \
				+ _rng.randf_range(-jag, jag) * 0.35
			row.append(centre + basis * (n * radii * w))
		pts.append(row)
	var circ := TAU * maxf(radii.x, radii.z)
	for i in rows:
		var a0: Array[Vector3] = pts[i]
		var a1: Array[Vector3] = pts[i + 1]
		for j in cols:
			var j1 := (j + 1) % cols
			var u0 := float(j) / float(cols) * circ
			var u1 := float(j + 1) / float(cols) * circ
			var v0 := float(i) / float(rows) * PI * radii.y
			var v1 := float(i + 1) / float(rows) * PI * radii.y
			_quad(xf * a0[j], xf * a1[j], xf * a1[j1], xf * a0[j1], Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1),
				Vector2(u1, v0))
	_any = true


## A round bar from `a` to `b` (a haft), radius `ra` at a and `rb` at b, `sides` round.
func bar(a: Vector3, b: Vector3, ra: float, rb: float, sides := 8, segs := 4, xf := Transform3D.IDENTITY) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(d).normalized()
	var len := (b - a).length()
	for s in segs:
		var t0 := float(s) / float(segs)
		var t1 := float(s + 1) / float(segs)
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		var r0 := lerpf(ra, rb, t0)
		var r1 := lerpf(ra, rb, t1)
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var n0 := side * cos(a0) + up * sin(a0)
			var n1 := side * cos(a1) + up * sin(a1)
			var u0 := a0 * ra
			var u1 := a1 * ra
			_quad(xf * (p0 + n0 * r0), xf * (p0 + n1 * r0), xf * (p1 + n1 * r1), xf * (p1 + n0 * r1), Vector2(u0, t0 * len),
				Vector2(u1, t0 * len), Vector2(u1, t1 * len), Vector2(u0, t1 * len))
	_any = true


func mesh() -> ArrayMesh:
	if not _any:
		return null
	_st.generate_normals()
	_st.generate_tangents()
	return _st.commit()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(a, b, c, ua, ub, uc)
	_tri(a, c, d, ua, uc, ud)


func _tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# (Godot's front faces wind clockwise: the outward faces as built here wind the other way)
	_st.set_uv(ua)
	_st.add_vertex(a)
	_st.set_uv(uc)
	_st.add_vertex(c)
	_st.set_uv(ub)
	_st.add_vertex(b)
