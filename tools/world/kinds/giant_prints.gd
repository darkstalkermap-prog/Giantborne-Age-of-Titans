extends RefCounted
## Element kind "giant_prints" (E3): the tracks a walking colossus leaves in frozen turf - a print of `size` [length,
## width] (default 7 x 3.2 m, a 40 m giant's sabaton) every `step` m (default 13) along `points` ([[x, z], ...] in world
## space), left and right of the path by `gauge` m in turn: each a shallow, dark-edged hollow in the ground pressed
## toward the path's way. The Hollow Titan's tracks from the Empty Stand west into the Kingsward.
## Structures mesh (one draw call with the chunk's); no solids.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(7, 3.2, 0))
	var step := float(el.get("step", 13.0))
	var gauge := float(el.get("gauge", 3.2))
	var pts := L.points_of(el)
	var out: Array = []
	if pts.size() < 2:
		return out
	var xf: Transform3D = ctx.frame
	var walked := 0.0
	var k := 0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		while walked <= seg:
			var p := a + dir * walked + side * gauge * (1.0 if k % 2 == 0 else -1.0)
			var at := L.local_point(ctx, p.x, p.y, -0.25)
			var yaw := rad_to_deg(atan2(dir.x, dir.y)) - rad_to_deg(xf.basis.get_euler().y)
			out.append(L.part("sphere", at, Vector3(s.y, 0.6, s.x), "stone_dark" if k % 3 else "black", yaw))
			k += 1
			walked += step
		walked -= seg
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("GiantPrints", parts(el, ctx))
