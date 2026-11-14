extends RefCounted
## Element kind "palisade" (P25): a stake wall along `points` (a closed ring repeats its first
## point), `height` m tall, with `gaps` like a wall's: the toll-riders' fort, the war camp's lines.
## The stakes are drawn as a sharpened run; each piece is a solid. (A palisade a stage-4 giant
## tramples is P26's palisade_trample prop, placed by the region packages.)

const L := preload("res://tools/world/layout.gd")
const WALL := preload("res://tools/world/kinds/wall.gd")


static func _build(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var h := float(el.get("height", 5.0))
	var parts: Array = []
	var solids: Array = []
	for r: Array in WALL.runs(el):
		var run := L.run_boxes(ctx, r[0], r[1], h, 0.8, "timber", 0.6, 12.0)
		parts.append_array(run.parts)
		solids.append_array(run.solids)
		for p: Dictionary in run.parts:
			var size: Vector3 = p.size
			var n := maxi(1, int(size.x / 1.6))
			var basis := Basis(Vector3.UP, deg_to_rad(float(p.yaw)))
			for i in n:
				var off := basis * Vector3(-size.x * 0.5 + (i + 0.5) * size.x / n, size.y, 0)
				parts.append(L.part("cone", (p.pos as Vector3) + off, Vector3(0.9, 1.0, 0), "timber_dark"))
	return {"parts": parts, "solids": solids}


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).parts


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	return _build(el, ctx).solids


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Palisade", parts(el, ctx))
