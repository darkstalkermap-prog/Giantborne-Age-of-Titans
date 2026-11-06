extends RefCounted
## Element kind "stair_visual" (P25): the steps carved into a ramp from `from` [x, z] to `to`
## [x, z], `width` metres wide: `steps` stone treads following the terrain (the ramp itself is the
## ground that every giant and every nav layer uses), each riser `riser_m` tall - "taller than a
## house" on the Giant's Stair. Visual only (no solids).

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var a := WorldFeatures.v2(el.from)
	var b := WorldFeatures.v2(el.to)
	var n := int(el.get("steps", 10))
	var w := float(el.get("width", 30.0))
	var riser := float(el.get("riser_m", 3.0))
	var dir := (b - a)
	var length := dir.length()
	var xf: Transform3D = ctx.frame
	var yaw := rad_to_deg(atan2(-dir.y, dir.x)) - rad_to_deg(xf.basis.get_euler().y)
	var out: Array = []
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n)
		var at := L.local_point(ctx, p.x, p.y, -riser * 0.6)
		out.append(L.part("box", at, Vector3(length / n * 0.55, riser, w), "stone" if k % 2 else "stone_light", yaw))
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var p := a.lerp(b, (k + 0.5) / 3.0)
			var off := Vector2(-dir.y, dir.x).normalized() * (w * 0.5 + 1.5) * side
			var at := L.local_point(ctx, p.x + off.x, p.y + off.y, -1.0)
			out.append(L.part("box", at, Vector3(3.0, 6.0, 3.0), "stone_dark", yaw))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Stair", parts(el, ctx))
