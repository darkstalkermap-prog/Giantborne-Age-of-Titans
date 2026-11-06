extends RefCounted
## Element kind "hall" (P25): a great building of `size` [w, h, d]: style "hall" (a timber hall on
## a stone footing with a steep roof: Edda's hall, Hollowmere's long hut), "longhouse" (a giants'
## 40 m longhouse with a turf roof: Skarn, Harrok's Hall), "keep" (a stone keep with crenels and a
## corner turret: Fort Aldmere's), "mill" (a mill house with its wheel). Structures mesh; solid body.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(30, 10, 14))
	var out: Array = []
	match str(el.get("style", "hall")):
		"keep":
			out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x, s.y + 1, s.z), "stone"))
			for i in 4:
				var cx := (-0.5 + (i % 2)) * (s.x - 2.0)
				var cz := (-0.5 + (i / 2)) * (s.z - 2.0)
				out.append(L.part("box", Vector3(cx, s.y, cz), Vector3(2.4, 2.2, 2.4), "stone_dark"))
			out.append(L.part("cyl", Vector3(s.x * 0.35, s.y, -s.z * 0.3), Vector3(s.x * 0.3, s.y * 0.45, 0), "stone_light"))
			out.append(L.part("cone", Vector3(s.x * 0.35, s.y * 1.45, -s.z * 0.3), Vector3(s.x * 0.36, s.y * 0.35, 0), "roof_slate"))
			out.append(L.part("box", Vector3(0, s.y + 2.2, 0), Vector3(0.4, 8.0, 0.4), "timber_dark"))
			out.append(L.part("box", Vector3(1.6, s.y + 7.4, 0), Vector3(3.0, 2.0, 0.2), "banner_blue"))
		"longhouse":
			out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x, s.y * 0.45 + 1, s.z), "timber_dark"))
			out.append(L.part("roof", Vector3(0, s.y * 0.45, 0), Vector3(s.x + 2.0, s.y * 0.55, s.z + 3.0), "moss"))
			for k in 3:
				out.append(L.part("box", Vector3(-s.x * 0.5 + 2.0 + k * (s.x - 4.0) * 0.5, s.y * 0.85, 0), Vector3(1.6, s.y * 0.3, 1.6), "stone_dark"))
		"mill":
			out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x, s.y + 1, s.z), "stone"))
			out.append(L.part("roof", Vector3(0, s.y, 0), Vector3(s.x + 1.0, s.y * 0.5, s.z + 1.0), "thatch"))
			var wheel := L.part("cyl", Vector3(s.x * 0.5 + 0.8, s.y * 0.4, 0), Vector3(s.y * 0.9, 1.4, 0), "timber", 0.0, Vector3(0, 0, 90))
			out.append(wheel)
		_:
			out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x + 0.6, 2.4, s.z + 0.6), "stone_dark"))
			out.append(L.part("box", Vector3(0, 1.4, 0), Vector3(s.x, s.y * 0.55, s.z), "timber"))
			out.append(L.part("roof", Vector3(0, 1.4 + s.y * 0.55, 0), Vector3(s.x + 1.4, s.y * 0.65, s.z + 1.6), "thatch"))
			out.append(L.part("box", Vector3(0, 1.4, s.z * 0.5 + 0.1), Vector3(3.0, 4.0, 0.3), "timber_dark"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(30, 10, 14))
	var h := s.y * (0.6 if str(el.get("style", "hall")) == "longhouse" else 1.0)
	return [L.solid("box", Vector3(0, h * 0.5 - 0.5, 0), Vector3(s.x, h + 1.0, s.z))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Hall", parts(el, ctx))
