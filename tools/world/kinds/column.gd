extends RefCounted
## Element kind "column" (P25): a group of standing pieces at `points` ([[x, z], ...] in world
## space; or `count` round `pos` within `radius`): style "column" (drowned colonnades, some broken),
## "slab" (the Barrow Fields' standing slabs), "cairn_stack" (the Cairnlands' stacked stones),
## "stump" (the causeway's broken piers), "nest" (low rings of branches). `size` [diameter, height].
## Structures mesh; each piece is a solid unless `no_solids`.

const L := preload("res://tools/world/layout.gd")


## The pieces' centres in world space (x, z) and a per-piece height factor.
static func spots(el: Dictionary) -> Array:
	var out: Array = []
	var pts := L.points_of(el)
	if not pts.is_empty():
		for k in pts.size():
			out.append([pts[k], 0.55 + 0.45 * absf(sin(k * 2.3 + 0.7))])
		return out
	var c := L.pos2(el)
	var n := int(el.get("count", 6))
	var r := float(el.get("radius", 10.0))
	for k in n:
		var a := TAU * k / maxf(1.0, n) + 0.4
		var rr := r * (0.55 + 0.45 * absf(sin(k * 1.9)))
		out.append([c + Vector2(cos(a), sin(a)) * rr, 0.55 + 0.45 * absf(sin(k * 2.3 + 0.7))])
	return out


static func _pieces(el: Dictionary, ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(2.4, 8, 0))
	var style := str(el.get("style", "column"))
	var out: Array = []
	for sp: Array in spots(el):
		var p: Vector2 = sp[0]
		var f := float(sp[1])
		var at := L.local_point(ctx, p.x, p.y, -0.8)
		match style:
			"slab":
				out.append(["box", at, Vector3(s.x, s.y * f + 0.8, s.x * 0.45), "stone_light", 23.0 * p.x, true])
			"cairn_stack":
				var y := 0.0
				for k in 4:
					var w := s.x * (1.0 - 0.18 * k)
					out.append(["box", at + Vector3(0, y, 0), Vector3(w, s.y * 0.25, w), "rock" if k % 2 == 0 else "stone_dark", 31.0 * k + p.y, k == 0])
					y += s.y * 0.25
			"stump":
				out.append(["cyl", at, Vector3(s.x, s.y * f * 0.5 + 0.8, 0), "stone", 0.0, true])
			"nest":
				out.append(["frustum", at, Vector3(s.x, s.y * 0.3, s.x * 0.7), "timber_dark", 0.0, false])
			_:
				var h := s.y * f + 0.8
				out.append(["cyl", at, Vector3(s.x, h, 0), "stone_light", 0.0, true])
				if f > 0.85:
					out.append(["box", at + Vector3(0, h, 0), Vector3(s.x * 1.4, 0.7, s.x * 1.4), "stone", 0.0, false])
	return out


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4])))
	return out


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	if bool(el.get("no_solids", false)):
		return []
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		if not bool(p[5]):
			continue
		var pos: Vector3 = p[1]
		var size: Vector3 = p[2]
		if str(p[0]) == "box":
			out.append(L.solid("box", pos + Vector3.UP * size.y * 0.5, size, float(p[4])))
		else:
			out.append(L.solid("cyl", pos + Vector3.UP * size.y * 0.5, Vector3(size.x, size.y, size.x)))
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Columns", parts(el, ctx))
