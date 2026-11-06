extends RefCounted
## Element kind "house" (P25): a cottage of `size` [w, h, d] - plastered walls and a thatched gable
## roof; style "stilt" raises it on posts (Hollowmere), "burned" leaves a blackened shell, "stone"
## a slate-roofed stone house. Merged into its chunk's structures mesh; its body is a solid.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 6, 8))
	var style := str(el.get("style", "cottage"))
	var out: Array = []
	var base := 0.0
	if style == "stilt":
		base = 2.6
		for sx: float in [-0.4, 0.4]:
			for sz: float in [-0.4, 0.4]:
				out.append(L.part("box", Vector3(s.x * sx, -1.0, s.z * sz), Vector3(0.6, base + 1.0, 0.6), "timber_dark"))
		out.append(L.part("box", Vector3(0, base - 0.4, 0), Vector3(s.x + 1.6, 0.4, s.z + 1.6), "timber"))
	var wall := "plaster"
	var roof := "thatch"
	match style:
		"stone":
			wall = "stone"
			roof = "roof_slate"
		"burned":
			wall = "stone_dark"
			roof = ""
		"stilt":
			wall = "timber"
	out.append(L.part("box", Vector3(0, base - 0.5, 0), Vector3(s.x, s.y + 0.5, s.z), wall))
	if roof != "":
		out.append(L.part("roof", Vector3(0, base + s.y, 0), Vector3(s.x + 0.8, s.y * 0.6, s.z + 0.8), roof))
	else:
		out.append(L.part("box", Vector3(s.x * 0.2, base + s.y, 0), Vector3(1.2, 2.0, 1.2), "black"))
	out.append(L.part("box", Vector3(0, base, s.z * 0.5 + 0.05), Vector3(1.4, 2.4, 0.2), "timber_dark"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 6, 8))
	var base := 2.6 if str(el.get("style", "")) == "stilt" else 0.0
	return [L.solid("box", Vector3(0, (base + s.y) * 0.5 - 0.25, 0), Vector3(s.x, base + s.y + 0.5, s.z))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("House", parts(el, ctx))
