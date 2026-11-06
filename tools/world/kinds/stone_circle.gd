extends RefCounted
## Element kind "stone_circle" (P25): `count` standing stones of `size` [w, h, t] on a ring of
## `radius` round pos, every second one capped by a lintel when style is "trilithon" (the Standing
## Stones, the Ancestral Circle); style "ring_wall" (the Moot) joins the stones with a 9 m wall so
## the ring is closed except at `gates` (bearings in degrees from +x toward +z, each `gate_m` wide),
## where the size gates stand. Structures mesh; stones and wall pieces are solids.

const L := preload("res://tools/world/layout.gd")


static func _in_gate(el: Dictionary, a: float, margin_m := 0.0) -> bool:
	var r := float(el.get("radius", 30.0))
	for g: Variant in el.get("gates", []):
		var ga := deg_to_rad(float(g))
		var half := (float(el.get("gate_m", 16.0)) * 0.5 + margin_m) / r
		if absf(angle_difference(a, ga)) <= half:
			return true
	return false


static func _build(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var c := L.pos2(el)
	var r := float(el.get("radius", 30.0))
	var n := int(el.get("count", 12))
	var s := L.size3(el, Vector3(4, 12, 2))
	var style := str(el.get("style", "ring"))
	var parts: Array = []
	var solids: Array = []
	var xf: Transform3D = ctx.frame
	var base_yaw := rad_to_deg(xf.basis.get_euler().y)
	for k in n:
		var a := TAU * k / n
		if _in_gate(el, a, s.x * 0.5):
			continue
		var p := c + Vector2(cos(a), sin(a)) * r
		var at := L.local_point(ctx, p.x, p.y, -1.0)
		var yaw := -rad_to_deg(a) - base_yaw + 90.0
		var h := s.y * (0.85 + 0.15 * absf(sin(k * 1.3)))
		parts.append(L.part("box", at, Vector3(s.x, h + 1.0, s.z), "stone_light" if k % 3 else "stone", yaw))
		solids.append(L.solid("box", at + Vector3.UP * (h + 1.0) * 0.5, Vector3(s.x, h + 1.0, s.z), yaw))
		if style == "trilithon" and k % 2 == 0:
			var a2 := TAU * (k + 0.5) / n
			var mid := c + Vector2(cos(a2), sin(a2)) * r
			var top := L.local_point(ctx, mid.x, mid.y, -1.0)
			top.y = at.y + h + 1.0
			parts.append(L.part("box", top, Vector3(TAU * r / n + s.x * 0.5, s.z, s.z * 1.2), "stone", -rad_to_deg(a2) - base_yaw + 90.0))
	if style == "ring_wall":
		var segs := maxi(24, n * 3)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var am := (a0 + a1) * 0.5
			if _in_gate(el, am):
				continue
			var p0 := c + Vector2(cos(a0), sin(a0)) * r
			var p1 := c + Vector2(cos(a1), sin(a1)) * r
			var run := L.run_boxes(ctx, p0, p1, float(el.get("wall_h", 9.0)), float(el.get("wall_t", 3.0)), "stone_dark", 1.5, 40.0)
			parts.append_array(run.parts)
			solids.append_array(run.solids)
	return {"parts": parts, "solids": solids}


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).parts


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).solids


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("StoneCircle", parts(el, ctx))
