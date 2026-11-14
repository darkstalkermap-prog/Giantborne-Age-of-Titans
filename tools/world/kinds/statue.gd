extends RefCounted
## Element kind "statue" (P25): a giant-king carved in stone, `size` [w, h] - style "standing" (a
## crowned king on a plinth, facing local +z), "throne" (the Stone Throne of the Moot: a great seat
## of stacked slabs). The toppled statue that seals Kingsgate's hollow is P26's heave prop, placed
## as a secret's seal. Structures mesh; plinth and body are solids.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(6, 18, 0))
	var w := s.x
	var h := s.y
	var out: Array = []
	if str(el.get("style", "standing")) == "throne":
		out.append(L.part("box", Vector3(0, -1.0, 0), Vector3(w * 2.4, 3.0, w * 2.0), "stone_dark"))
		out.append(L.part("box", Vector3(0, 2.0, 0.2 * w), Vector3(w * 1.8, h * 0.25, w * 1.2), "stone"))
		out.append(L.part("box", Vector3(0, 2.0, -0.6 * w), Vector3(w * 1.8, h, w * 0.5), "stone_light"))
		for side: float in [-1.0, 1.0]:
			out.append(L.part("box", Vector3(side * w * 0.95, 2.0, 0), Vector3(w * 0.3, h * 0.42, w * 1.6), "stone"))
		out.append(L.part("box", Vector3(0, 2.0 + h, -0.6 * w), Vector3(w * 1.2, h * 0.12, w * 0.6), "gold"))
		return out
	out.append(L.part("box", Vector3(0, -1.0, 0), Vector3(w * 1.4, h * 0.18 + 1.0, w * 1.2), "stone_dark"))
	var b := h * 0.18
	out.append(L.part("box", Vector3(0, b, 0), Vector3(w * 0.8, h * 0.42, w * 0.5), "stone_light"))
	out.append(L.part("box", Vector3(0, b + h * 0.42, 0), Vector3(w, h * 0.2, w * 0.55), "stone_light"))
	out.append(L.part("sphere", Vector3(0, b + h * 0.62, 0), Vector3(w * 0.42, w * 0.46, w * 0.42), "stone_light"))
	out.append(L.part("box", Vector3(0, b + h * 0.62 + w * 0.44, 0), Vector3(w * 0.45, w * 0.18, w * 0.45), "gold"))
	out.append(L.part("box", Vector3(w * 0.55, b + h * 0.2, w * 0.15), Vector3(w * 0.22, h * 0.48, w * 0.22), "stone"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(6, 18, 0))
	if str(el.get("style", "standing")) == "throne":
		return [L.solid("box", Vector3(0, s.y * 0.4, -0.2 * s.x), Vector3(s.x * 2.4, s.y * 0.9, s.x * 2.0))]
	return [L.solid("box", Vector3(0, s.y * 0.45, 0), Vector3(s.x * 1.4, s.y * 0.9, s.x * 1.2))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Statue", parts(el, ctx))
