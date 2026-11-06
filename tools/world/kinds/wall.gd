extends RefCounted
## Element kind "wall" (P25): a wall along `points` ([[x, z], ...]: a closed ring repeats its
## first point) of `height` and `thick` metres, cut into pieces that follow the ground; `gaps`
## ([[x, z, width], ...]) leave openings (gateways, where a gate prop stands); style "stone" adds
## crenels and corner towers (`towers`: true), "timber" is a plank wall. Structures mesh; every
## piece is a solid (a navigation obstacle too).

const L := preload("res://tools/world/layout.gd")


## The wall's runs after cutting out the gaps: [[a, b], ...] (world x, z).
static func runs(el: Dictionary) -> Array:
	var pts := L.points_of(el)
	var out: Array = []
	for k in pts.size() - 1:
		var segs: Array = [[pts[k], pts[k + 1]]]
		for g: Array in el.get("gaps", []):
			var gc := Vector2(float(g[0]), float(g[1]))
			var half := float(g[2]) * 0.5
			var next: Array = []
			for sg: Array in segs:
				var a: Vector2 = sg[0]
				var b: Vector2 = sg[1]
				var ab := b - a
				var t := clampf((gc - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
				var on := a + ab * t
				if on.distance_to(gc) > 2.0 or ab.length() < 0.01:
					next.append(sg)
					continue
				var dir := ab.normalized()
				var c0 := on - dir * half
				var c1 := on + dir * half
				if (c0 - a).dot(dir) > 0.5:
					next.append([a, c0])
				if (b - c1).dot(dir) > 0.5:
					next.append([c1, b])
			segs = next
		out.append_array(segs)
	return out


static func _build(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var h := float(el.get("height", 8.0))
	var t := float(el.get("thick", 2.0))
	var stone := str(el.get("style", "stone")) == "stone"
	var color := "stone" if stone else "timber"
	var parts: Array = []
	var solids: Array = []
	for r: Array in runs(el):
		var run := L.run_boxes(ctx, r[0], r[1], h, t, color, 1.0, 16.0)
		parts.append_array(run.parts)
		solids.append_array(run.solids)
		if stone:
			# crenels along the top of each piece
			for p: Dictionary in run.parts:
				var size: Vector3 = p.size
				var n := maxi(1, int(size.x / 4.0))
				var basis := Basis(Vector3.UP, deg_to_rad(float(p.yaw)))
				for i in n:
					var off := basis * Vector3(-size.x * 0.5 + (i + 0.5) * size.x / n, size.y, 0)
					parts.append(L.part("box", (p.pos as Vector3) + off, Vector3(1.6, 1.2, t + 0.2), "stone_dark", float(p.yaw)))
	if bool(el.get("towers", false)):
		var pts := L.points_of(el)
		for k in pts.size():
			if k == pts.size() - 1 and pts[k] == pts[0]:
				continue
			var c := L.local_point(ctx, pts[k].x, pts[k].y, -1.0)
			var d := float(el.get("tower_d", t * 3.0))
			parts.append(L.part("cyl", c, Vector3(d, h + 5.0, 0), "stone_light"))
			parts.append(L.part("cone", c + Vector3.UP * (h + 5.0), Vector3(d + 1.0, 4.0, 0), "roof_slate"))
			solids.append(L.solid("cyl", c + Vector3.UP * (h + 5.0) * 0.5, Vector3(d, h + 5.0, d)))
	return {"parts": parts, "solids": solids}


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).parts


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).solids


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Wall", parts(el, ctx))
