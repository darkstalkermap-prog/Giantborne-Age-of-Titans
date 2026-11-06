extends RefCounted
## Element kind "tower" (P25): a tower of `size` [diameter or width, height]: style "round" (stone,
## a conical roof), "square" (stone, a pyramid roof), "watch" (a timber watchtower on legs: the toll
## fort's), "bell" (the drowned bell tower: an open belfry with its bell, leaning a little).
## Structures mesh; its footing is a solid.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 30, 10))
	var d := s.x
	var h := s.y
	var out: Array = []
	match str(el.get("style", "round")):
		"square":
			out.append(L.part("box", Vector3(0, -1, 0), Vector3(d, h + 1, d), "stone"))
			out.append(L.part("pyramid", Vector3(0, h, 0), Vector3(d + 1.5, d * 0.8, d + 1.5), "roof_slate"))
		"watch":
			for sx: float in [-0.5, 0.5]:
				for sz: float in [-0.5, 0.5]:
					out.append(L.part("box", Vector3(d * sx, -0.5, d * sz), Vector3(0.7, h + 0.5, 0.7), "timber_dark"))
			out.append(L.part("box", Vector3(0, h, 0), Vector3(d + 2.0, 0.6, d + 2.0), "timber"))
			out.append(L.part("box", Vector3(0, h + 0.6, 0), Vector3(d + 2.0, 1.4, d + 2.0), "timber_dark"))
			out.append(L.part("pyramid", Vector3(0, h + 3.4, 0), Vector3(d + 3.0, 3.0, d + 3.0), "thatch"))
		"bell":
			var lean := Vector3(4, 0, -3)
			out.append(L.part("box", Vector3(0, -2, 0), Vector3(d, h * 0.7 + 2, d), "stone", 0.0, lean))
			for sx: float in [-0.4, 0.4]:
				for sz: float in [-0.4, 0.4]:
					out.append(L.part("box", Vector3(d * sx + 1.5, h * 0.7, d * sz - 1.1), Vector3(1.4, h * 0.22, 1.4), "stone_light", 0.0, lean))
			out.append(L.part("pyramid", Vector3(2.0, h * 0.92, -1.5), Vector3(d + 1.0, h * 0.18, d + 1.0), "roof_slate", 0.0, lean))
			out.append(L.part("frustum", Vector3(1.6, h * 0.74, -1.2), Vector3(d * 0.5, d * 0.45, d * 0.2), "gold", 0.0, lean))
		_:
			out.append(L.part("cyl", Vector3(0, -1, 0), Vector3(d, h + 1, 0), "stone"))
			out.append(L.part("cone", Vector3(0, h, 0), Vector3(d + 2.0, d * 0.75, 0), "roof_slate"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 30, 10))
	match str(el.get("style", "round")):
		"watch":
			return [L.solid("box", Vector3(0, s.y * 0.5, 0), Vector3(s.x + 0.7, s.y, s.x + 0.7))]
		"square", "bell":
			return [L.solid("box", Vector3(0, s.y * 0.35, 0), Vector3(s.x, s.y * 0.7, s.x))]
	return [L.solid("cyl", Vector3(0, s.y * 0.5, 0), Vector3(s.x, s.y + 1, s.x))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Tower", parts(el, ctx))
