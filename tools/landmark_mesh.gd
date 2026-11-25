class_name LandmarkMesh
extends RefCounted
## C3: the mesh kit of the waystones and forges (tools/builders/forge.gd builds them with it; offline): rough-hewn
## shapes as faceted triangles with their colour in the vertex colour and what they are made of in its alpha
## (assets/shaders/landmark.gdshader: 1 stone, 0.75 wood, 0.5 iron, 0.3 leather or earth, 0.15 glowing). Every
## shape is cut from rings of points pushed in and out at random (a seeded generator: two builds write the same
## bytes), so no face is a flat box: stone has its chisel facets, a log its bark ridges.

const STONE := 1.0
const WOOD := 0.75
const IRON := 0.5
const LEATHER := 0.3
const GLOW := 0.15

var _st := SurfaceTool.new()
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


static func col(c: Color, kind: float) -> Color:
	return Color(c.r, c.g, c.b, kind)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_st.set_color(color)
	_st.add_vertex(a)
	_st.set_color(color)
	_st.add_vertex(b)
	_st.set_color(color)
	_st.add_vertex(c)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(a, b, c, color)
	_tri(a, c, d, color)


## A rough prism: `sides` around, `rings` + 1 levels from `base` up `h` (along `axis`, default up), its section an
## ellipse of half widths r0 at the foot to r1 at the top, each point pushed out or in by up to `jitter` of the
## radius, the whole turned `yaw` about its axis and leaning by `lean` (a shift of the top). Shaded by `shade`
## (each face a little lighter or darker: chisel facets). Capped at both ends.
func prism(base: Vector3, r0: Vector2, r1: Vector2, h: float, color: Color, sides := 6, rings := 3, jitter := 0.12,
		yaw := 0.0, lean := Vector3.ZERO, shade := 0.08) -> void:
	var lv: Array = []
	for k in rings + 1:
		var t := float(k) / float(rings)
		var r := r0.lerp(r1, t)
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides) + yaw + PI / float(sides)
			var j := 1.0 + _rng.randf_range(-jitter, jitter)
			var p := Vector3(cos(a) * r.x * j, t * h + _rng.randf_range(-jitter, jitter) * 0.15 * h / float(rings + 1),
				sin(a) * r.y * j)
			p.y = clampf(p.y, 0.0, h) if k == 0 or k == rings else p.y
			if k == 0:
				p.y = 0.0
			if k == rings:
				p.y = h
			ring.append(base + p + lean * t)
		lv.append(ring)
	for k in rings:
		var lo: PackedVector3Array = lv[k]
		var hi: PackedVector3Array = lv[k + 1]
		for i in sides:
			var i2 := (i + 1) % sides
			var c := _shaded(color, shade)
			_quad(lo[i], hi[i], hi[i2], lo[i2], c)
	var top: PackedVector3Array = lv[rings]
	var bot: PackedVector3Array = lv[0]
	var ct := Vector3.ZERO
	var cb := Vector3.ZERO
	for i in sides:
		ct += top[i]
		cb += bot[i]
	ct /= float(sides)
	cb /= float(sides)
	var cap := _shaded(color, shade)
	for i in sides:
		var i2 := (i + 1) % sides
		_tri(ct, top[i2], top[i], cap)
		_tri(cb, bot[i], bot[i2], cap)


## A rough block (a four-sided prism with its corners where a box's are): `size` x, y, z, its foot at `base`.
func block(base: Vector3, size: Vector3, color: Color, jitter := 0.06, yaw := 0.0, taper := 1.0, shade := 0.07) -> void:
	var r := Vector2(size.x, size.z) * 0.5 * sqrt(2.0)
	prism(base, r, r * taper, size.y, color, 4, 2, jitter, yaw + PI * 0.25 - PI * 0.25, Vector3.ZERO, shade)


## A rough log or post from `a` to `b` of radius `r` (8 sides, its bark ridged by `jitter`).
func log_between(a: Vector3, b: Vector3, r: float, color: Color, sides := 8, jitter := 0.12) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 1e-4:
		return
	var basis := _basis_y_to(axis / len)
	var lv: Array = []
	for k in 2:
		var ring := PackedVector3Array()
		for i in sides:
			var ang := TAU * float(i) / float(sides)
			var j := 1.0 + _rng.randf_range(-jitter, jitter)
			ring.append(a + basis * Vector3(cos(ang) * r * j, len * float(k), sin(ang) * r * j))
		lv.append(ring)
	for i in sides:
		var i2 := (i + 1) % sides
		_quad(lv[0][i], lv[1][i], lv[1][i2], lv[0][i2], _shaded(color, 0.05))
	for k in 2:
		var ring: PackedVector3Array = lv[k]
		var cc := a if k == 0 else b
		for i in sides:
			var i2 := (i + 1) % sides
			if k == 1:
				_tri(cc, ring[i2], ring[i], color.darkened(0.15))
			else:
				_tri(cc, ring[i], ring[i2], color.darkened(0.15))


## A cone of `sides` from a ring of radius `r` at `base` to a tip `h` above it, leaning by `lean` (flames, a roof).
func cone(base: Vector3, r: float, h: float, color: Color, sides := 6, lean := Vector3.ZERO, jitter := 0.15) -> void:
	var tip := base + Vector3(0, h, 0) + lean
	var ring := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var j := 1.0 + _rng.randf_range(-jitter, jitter)
		ring.append(base + Vector3(cos(a) * r * j, 0.0, sin(a) * r * j))
	for i in sides:
		var i2 := (i + 1) % sides
		_tri(ring[i], tip, ring[i2], _shaded(color, 0.05))
		_tri(base, ring[i2], ring[i], color)


## A flat quad slab (a roof's boards, a trough's water): corners in order, `thick` below them.
func slab(corners: Array, thick: float, color: Color) -> void:
	var down := Vector3(0, -thick, 0)
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var d: Vector3 = corners[3]
	_quad(a, b, c, d, _shaded(color, 0.04))
	_quad(d + down, c + down, b + down, a + down, color.darkened(0.2))
	for pair: Array in [[a, b], [b, c], [c, d], [d, a]]:
		var p: Vector3 = pair[0]
		var q: Vector3 = pair[1]
		_quad(p, p + down, q + down, q, color.darkened(0.1))


func _shaded(c: Color, amount: float) -> Color:
	var f := 1.0 + _rng.randf_range(-amount, amount)
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## The mesh so far (flat-shaded: every face its own normal).
func commit() -> ArrayMesh:
	_st.generate_normals()
	return _st.commit()
