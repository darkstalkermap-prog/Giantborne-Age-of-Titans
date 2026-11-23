extends RefCounted
## Element kind "grove" (B3): the Rootwarden's grove in the deep Greywood - a hollow ringed by colossal trees,
## entered under a root arch, its floor scattered with the dead trees he tears up and a dark pool. Structures mesh
## (the world's flat-shaded parts); each standing piece a solid unless `no_solids`. Styles (size [diameter or span,
## height, thickness]):
##   trunk     a colossal living tree: a flared base, buttress roots running out over the ground, a trunk tapering
##             high over the giant, broken limbs and a dark crown (`points`: several; size [diameter, height])
##   root_arch a root grown up out of the ground and back down into it, arched over the way in (size [span, height,
##             thickness], turned by `yaw`)
##   dead      a standing dead tree, silvered, its top broken off, a few dead limbs (`points`; size [diameter, height])
##   fallen    a fallen trunk lying on the ground, its root plate up (`points`, `yaw`; size [diameter, length])
##   pool      a dark pool of still water on the hollow's floor, its edge of mossed stones (size [diameter])
##   stumps    the stumps of trees he has torn up, with their earth (`points`; size [diameter, height])
##   saplings  young trees and moss where the dead ones stood (the grove greening after his rest; `points`)
## The grove's other pieces are the world's own kinds: the braziers round his spot (brazier), his territory (arena,
## style titan), the green the hollow becomes after his fall (FlagVisibility on this kind's `visible_when_flag`).

const L := preload("res://tools/world/layout.gd")


static func _spots(el: Dictionary) -> Array:
	var pts := L.points_of(el)
	if pts.is_empty():
		pts.append(L.pos2(el))
	return pts


static func _h(k: int, a: float) -> float:
	return absf(sin(float(k) * 2.31 + a))


static func _pieces(el: Dictionary, ctx: Dictionary) -> Array:
	var style := str(el.get("style", "trunk"))
	var s := L.size3(el, Vector3(4.0, 34.0, 1.6))
	var out: Array = []   # [shape, pos, size, colour, yaw, tilt, solid]
	var k := 0
	match style:
		"trunk":
			for p: Vector2 in _spots(el):
				var at := L.local_point(ctx, p.x, p.y, -0.6)
				var d := s.x * (0.85 + 0.3 * _h(k, 0.3))
				var h := s.y * (0.8 + 0.25 * _h(k, 1.1))
				var yaw := 37.0 * k + 11.0 * p.x
				out.append(["frustum", at, Vector3(d * 1.9, h * 0.07, d * 1.05), "bark", yaw, Vector3.ZERO, false])
				out.append(["frustum", at + Vector3(0, h * 0.06, 0), Vector3(d * 1.05, h * 0.62, d * 0.72), "bark", yaw,
					Vector3.ZERO, true])
				out.append(["frustum", at + Vector3(0, h * 0.66, 0), Vector3(d * 0.72, h * 0.30, d * 0.40), "timber_dark",
					yaw, Vector3(2.0, 0, -3.0), false])
				for r in 5:
					var a := deg_to_rad(yaw + 72.0 * r + 13.0 * _h(k + r, 0.7))
					var dir := Vector3(cos(a), 0, sin(a))
					out.append(["cone", at + dir * d * 0.45 + Vector3(0, d * 0.25, 0), Vector3(d * 0.55, d * 1.7, 0),
						"bark", 180.0 - rad_to_deg(a), Vector3(0, 0, 74.0), false])
				for b in 3:
					var a := deg_to_rad(yaw + 120.0 * b + 40.0)
					var y := h * (0.52 + 0.12 * b)
					out.append(["cyl", at + Vector3(cos(a), 0, sin(a)) * d * 0.25 + Vector3(0, y, 0),
						Vector3(d * 0.22, h * 0.22, 0), "timber_dark", 180.0 - rad_to_deg(a), Vector3(0, 0, 58.0), false])
				for c in 4:
					var a := deg_to_rad(yaw + 90.0 * c + 25.0)
					var r := d * (0.9 + 0.5 * _h(k + c, 2.0))
					out.append(["sphere", at + Vector3(cos(a) * r, h * (0.82 + 0.06 * c), sin(a) * r),
						Vector3(h * 0.20, h * 0.15, h * 0.20), "pine" if (k + c) % 2 == 0 else "leaves", 0.0, Vector3.ZERO,
						false])
				k += 1
		"dead":
			for p: Vector2 in _spots(el):
				var at := L.local_point(ctx, p.x, p.y, -0.5)
				var d := s.x * (0.8 + 0.4 * _h(k, 0.9))
				var h := s.y * (0.7 + 0.35 * _h(k, 0.2))
				var yaw := 51.0 * k + 7.0 * p.y
				out.append(["frustum", at, Vector3(d * 1.4, h * 0.08, d), "bone_dark", yaw, Vector3.ZERO, false])
				out.append(["frustum", at + Vector3(0, h * 0.07, 0), Vector3(d, h * 0.93, d * 0.45), "bone_dark", yaw,
					Vector3(3.0 * sin(k), 0, 4.0 * cos(k)), true])
				for b in 2:
					var a := deg_to_rad(yaw + 150.0 * b + 30.0)
					out.append(["cone", at + Vector3(cos(a), 0, sin(a)) * d * 0.2 + Vector3(0, h * (0.45 + 0.2 * b), 0),
						Vector3(d * 0.3, h * 0.28, 0), "bone_dark", 180.0 - rad_to_deg(a), Vector3(0, 0, 55.0), false])
				k += 1
		"fallen":
			var yaw := float(el.get("yaw", 0.0))
			for p: Vector2 in _spots(el):
				var at := L.local_point(ctx, p.x, p.y, -0.2)
				var d := s.x
				var ln := s.y
				out.append(["cyl", at + Vector3(0, d * 0.45, 0), Vector3(d, ln, 0), "bone_dark", yaw + 31.0 * k,
					Vector3(0, 0, 88.0), true])
				out.append(["sphere", at + Vector3(0, d * 0.2, 0), Vector3(d * 2.6, d * 2.2, d * 1.0), "soil", yaw + 31.0 * k,
					Vector3.ZERO, false])
				k += 1
		"root_arch":
			var span := s.x
			var rise := s.y
			var t := s.z
			var segs := 7
			for i in segs:
				var a0 := PI * float(i) / segs
				var a1 := PI * float(i + 1) / segs
				var p0 := Vector3(-cos(a0) * span * 0.5, sin(a0) * rise, 0)
				var p1 := Vector3(-cos(a1) * span * 0.5, sin(a1) * rise, 0)
				var mid := (p0 + p1) * 0.5
				var seg := p1 - p0
				var tilt := rad_to_deg(atan2(seg.x, seg.y))
				var w := t * (1.25 - 0.35 * sin(PI * (float(i) + 0.5) / segs))
				out.append(["cyl", mid - seg.normalized() * seg.length() * 0.5 + Vector3(0, -0.4, 0),
					Vector3(w, seg.length() + w * 0.6, 0), "bark", 0.0, Vector3(0, 0, -tilt), i == 0 or i == segs - 1])
			out.append(["sphere", Vector3(-span * 0.5, 0, 0), Vector3(t * 2.6, t * 1.4, t * 2.2), "moss", 0.0,
				Vector3.ZERO, false])
			out.append(["sphere", Vector3(span * 0.5, 0, 0), Vector3(t * 2.6, t * 1.4, t * 2.2), "moss", 0.0,
				Vector3.ZERO, false])
		"pool":
			var at := L.local_point(ctx, L.pos2(el).x, L.pos2(el).y, -0.35)
			out.append(["cyl", at, Vector3(s.x, 0.4, 0), "dark", 0.0, Vector3.ZERO, false])
			out.append(["cyl", at + Vector3(0, 0.25, 0), Vector3(s.x * 0.92, 0.12, 0), "water", 0.0, Vector3.ZERO, false])
			for r in 9:
				var a := TAU * float(r) / 9.0 + 0.3
				out.append(["sphere", at + Vector3(cos(a), 0, sin(a)) * s.x * 0.5, Vector3(2.2, 1.0, 1.8),
					"moss" if r % 2 == 0 else "rock", rad_to_deg(a), Vector3.ZERO, false])
		"saplings":
			for p: Vector2 in _spots(el):
				var at := L.local_point(ctx, p.x, p.y, -0.2)
				var hh := s.y * (0.7 + 0.5 * _h(k, 0.4))
				out.append(["cyl", at, Vector3(s.x * 0.3, hh * 0.5, 0), "bark", 0.0, Vector3.ZERO, false])
				out.append(["cone", at + Vector3(0, hh * 0.3, 0), Vector3(s.x * 2.4, hh * 0.8, 0), "leaves", 0.0, Vector3.ZERO,
					false])
				out.append(["sphere", at + Vector3(0, -0.2, 0), Vector3(s.x * 3.0, 0.8, s.x * 3.0), "moss", 0.0, Vector3.ZERO,
					false])
				k += 1
		"stumps":
			for p: Vector2 in _spots(el):
				var at := L.local_point(ctx, p.x, p.y, -0.4)
				out.append(["cyl", at, Vector3(s.x, s.y, 0), "bone_dark", 0.0, Vector3.ZERO, false])
				out.append(["sphere", at, Vector3(s.x * 2.2, s.y * 0.5, s.x * 2.0), "soil", 17.0 * k, Vector3.ZERO, false])
				k += 1
	return out


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4]), p[5]))
	return out


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	if bool(el.get("no_solids", false)):
		return []
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		if not bool(p[6]):
			continue
		var pos: Vector3 = p[1]
		var size: Vector3 = p[2]
		var d := maxf(size.x, size.z) if str(p[0]) == "frustum" else size.x
		out.append(L.solid("cyl", pos + Vector3.UP * size.y * 0.5, Vector3(d, size.y, d)))
	return out
