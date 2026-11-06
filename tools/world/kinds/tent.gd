extends RefCounted
## Element kind "tent" (P25): a camp of `count` tents round pos within `radius` (or at `points`):
## style "camp" (canvas ridge tents), "war" (red-trimmed rows: Aldmere's war camp, with a few
## engine frames' timbers), "raiders" (patched tents and lean-tos). `size` [w, h, d] of one tent.
## Structures mesh; each tent is a solid.

const L := preload("res://tools/world/layout.gd")
const COLUMN := preload("res://tools/world/kinds/column.gd")


static func _pieces(el: Dictionary, ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(5, 3.5, 6))
	var style := str(el.get("style", "camp"))
	var out: Array = []
	var k := 0
	for sp: Array in COLUMN.spots(el):
		var p: Vector2 = sp[0]
		var at := L.local_point(ctx, p.x, p.y, -0.3)
		var yaw := 37.0 * k + p.x * 0.3
		var color := "canvas_red" if style == "war" and k % 3 == 0 else ("soil" if style == "raiders" and k % 2 else "canvas")
		out.append(["roof", at, Vector3(s.z, s.y, s.x), color, yaw, true])
		k += 1
	if style == "war":
		for e in int(el.get("engines", 0)):
			var a := TAU * e / maxf(1.0, float(el.get("engines", 1))) + 0.7
			var p := L.pos2(el) + Vector2(cos(a), sin(a)) * float(el.get("radius", 30.0)) * 0.45
			var at := L.local_point(ctx, p.x, p.y, -0.3)
			out.append(["box", at, Vector3(6.0, 1.0, 3.0), "timber", rad_to_deg(a), true])
			out.append(["box", at + Vector3(0, 1.0, 0), Vector3(0.6, 6.0, 0.6), "timber_dark", rad_to_deg(a), false])
	return out


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4])))
	return out


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el, ctx):
		if bool(p[5]):
			var pos: Vector3 = p[1]
			var size: Vector3 = p[2]
			out.append(L.solid("box", pos + Vector3.UP * size.y * 0.4, Vector3(size.x, size.y * 0.8, size.z), float(p[4])))
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Tents", parts(el, ctx))
