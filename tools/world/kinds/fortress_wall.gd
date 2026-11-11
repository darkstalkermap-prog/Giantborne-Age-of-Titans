extends RefCounted
## Element kind "fortress_wall" (P36; plan M6-M9 §5.4, §5.13 boss 1): Fort Aldmere's curtain wall -
## a ring along `points` ([[x, z], ...]; a closed ring repeats its first point) `height` m tall and
## `thick` m deep, cut into ground-following pieces with crenels, a square tower (`tower_m` wide,
## `tower_rise_m` over the wall) at every corner and, at each `gate` ([x, z, gap width]), two
## flat-topped bastions (`bastion` [width, height]) flanking the gateway. The bastions' platforms are
## the gate garrison's: its wall archers stand on elevation markers and its ballistae (kind "engine")
## at the bastion's height (y_off). The gate prop that closes the gap is its own element. Structures
## mesh; every piece, tower and bastion is a solid (a navigation obstacle too).

const L := preload("res://tools/world/layout.gd")
const WALL := preload("res://tools/world/kinds/wall.gd")


## The gates as wall gaps ([x, z, width]) for wall.gd's runs().
static func _as_wall(el: Dictionary) -> Dictionary:
	var w := el.duplicate()
	w["gaps"] = el.get("gates", [])
	return w


## The unit direction of the ring's segment nearest (x, z).
static func _dir_at(el: Dictionary, p: Vector2) -> Vector2:
	var pts := L.points_of(el)
	var best := INF
	var dir := Vector2.RIGHT
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		if ab.length_squared() < 1e-6:
			continue
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			dir = ab.normalized()
	return dir


## The bastions' centres and their yaw (degrees, the wall's direction): [[Vector2, yaw], ...].
static func bastions(el: Dictionary) -> Array:
	var out: Array = []
	var bw := float((el.get("bastion", [10, 16]) as Array)[0])
	for g: Array in el.get("gates", []):
		var c := Vector2(float(g[0]), float(g[1]))
		var dir := _dir_at(el, c)
		var off := float(g[2]) * 0.5 + bw * 0.5
		var yaw := rad_to_deg(atan2(-dir.y, dir.x))
		out.append([c - dir * off, yaw])
		out.append([c + dir * off, yaw])
	return out


static func _build(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var h := float(el.get("height", 12.0))
	var t := float(el.get("thick", 3.0))
	var parts: Array = []
	var solids: Array = []
	var frame_yaw := rad_to_deg((ctx.frame as Transform3D).basis.get_euler().y)
	for r: Array in WALL.runs(_as_wall(el)):
		var run := L.run_boxes(ctx, r[0], r[1], h, t, "stone", 1.0, 16.0)
		parts.append_array(run.parts)
		solids.append_array(run.solids)
		for p: Dictionary in run.parts:
			var size: Vector3 = p.size
			var n := maxi(1, int(size.x / 4.0))
			var basis := Basis(Vector3.UP, deg_to_rad(float(p.yaw)))
			for i in n:
				var off := basis * Vector3(-size.x * 0.5 + (i + 0.5) * size.x / n, size.y, 0)
				parts.append(L.part("box", (p.pos as Vector3) + off, Vector3(1.6, 1.3, t + 0.2), "stone_dark", float(p.yaw)))
	# square corner towers with a crenel cap
	var tw := float(el.get("tower_m", 9.0))
	var rise := float(el.get("tower_rise_m", 4.0))
	var pts := L.points_of(el)
	for k in pts.size():
		if k == pts.size() - 1 and pts[k] == pts[0]:
			continue
		var c := L.local_point(ctx, pts[k].x, pts[k].y, -1.0)
		parts.append(L.part("box", c, Vector3(tw, h + rise + 1.0, tw), "stone_light"))
		parts.append(L.part("box", c + Vector3.UP * (h + rise + 1.0), Vector3(tw + 0.8, 1.4, tw + 0.8), "stone_dark"))
		solids.append(L.solid("box", c + Vector3.UP * (h + rise + 1.0) * 0.5, Vector3(tw, h + rise + 1.0, tw)))
	# the gate bastions: flat platforms (a low parapet on the outer edges) for the garrison
	var bs: Array = el.get("bastion", [10, 16])
	var bw := float(bs[0])
	var bh := float(bs[1])
	for b: Array in bastions(el):
		var at: Vector2 = b[0]
		var yaw := float(b[1]) - frame_yaw
		var c := L.local_point(ctx, at.x, at.y, -1.0)
		parts.append(L.part("box", c, Vector3(bw, bh + 1.0, bw), "stone_light", yaw))
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		for side: float in [-1.0, 1.0]:
			parts.append(L.part("box", c + basis * Vector3(0, bh + 1.0, side * (bw * 0.5 - 0.3)), Vector3(bw, 1.1, 0.6),
				"stone_dark", yaw))
		parts.append(L.part("box", c + basis * Vector3(0, bh + 1.0, 0) + Vector3.UP * 1.1, Vector3(0.3, 7.0, 0.3), "timber_dark", yaw))
		parts.append(L.part("box", c + basis * Vector3(1.4, bh + 1.0, 0) + Vector3.UP * 5.2, Vector3(2.6, 1.8, 0.12),
			str(el.get("banner_color", "banner_blue")), yaw))
		solids.append(L.solid("box", c + Vector3.UP * (bh + 1.0) * 0.5, Vector3(bw, bh + 1.0, bw), yaw))
	return {"parts": parts, "solids": solids}


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).parts


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).solids


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("FortressWall", parts(el, ctx))
