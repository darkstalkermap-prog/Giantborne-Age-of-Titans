extends RefCounted
## Element kind "platform" (P36; plan M6-M9 §5.10): an open timber gun tower - four legs with their
## braces, a plank deck `size` [w, h] (w m square, its top h m over the ground), a railing round the
## deck's edges and a ladder at its back (local +z) - for an engine placed on its deck (kind "engine"
## at the deck's height: the toll fort's stage-5 tower ballista). Unlike the watchtower (a closed cabin
## under a roof) the deck is open, so the engine on it is seen. Structures mesh (no draw call of its
## own); the deck's block is a solid (a navigation obstacle too).

const L := preload("res://tools/world/layout.gd")


static func _size(el: Dictionary) -> Vector2:
	var s: Array = el.get("size", [8, 10])
	return Vector2(float(s[0]), float(s[1]))


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := _size(el)
	var w := s.x
	var h := s.y
	var out: Array = []
	var leg := w * 0.5 - 0.4
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			out.append(L.part("box", Vector3(sx * leg, -0.5, sz * leg), Vector3(0.8, h + 0.5, 0.8), "timber_dark"))
	for k in 2:
		var y := h * (0.3 + k * 0.35)
		for side: float in [-1.0, 1.0]:
			out.append(L.part("box", Vector3(0, y, side * leg), Vector3(w - 0.4, 0.35, 0.35), "timber"))
			out.append(L.part("box", Vector3(side * leg, y, 0), Vector3(0.35, 0.35, w - 0.4), "timber"))
	out.append(L.part("box", Vector3(0, h - 0.5, 0), Vector3(w + 0.6, 0.5, w + 0.6), "timber"))
	var edge := w * 0.5 + 0.15
	for side: float in [-1.0, 1.0]:
		out.append(L.part("box", Vector3(0, h + 0.9, side * edge), Vector3(w + 0.6, 0.2, 0.2), "timber_dark"))
		out.append(L.part("box", Vector3(side * edge, h + 0.9, 0), Vector3(0.2, 0.2, w + 0.6), "timber_dark"))
		for k in 3:
			var t := -w * 0.5 + k * w * 0.5
			out.append(L.part("box", Vector3(t, h, side * edge), Vector3(0.2, 1.0, 0.2), "timber_dark"))
			out.append(L.part("box", Vector3(side * edge, h, t), Vector3(0.2, 1.0, 0.2), "timber_dark"))
	for side: float in [-1.0, 1.0]:
		out.append(L.part("box", Vector3(side * 0.6, -0.5, edge + 0.3), Vector3(0.2, h + 0.5, 0.2), "timber"))
	var rungs := int(h / 0.8)
	for k in rungs:
		out.append(L.part("box", Vector3(0, 0.4 + k * 0.8, edge + 0.3), Vector3(1.4, 0.12, 0.12), "timber"))
	if str(el.get("banner_color", "")) != "":
		out.append(L.part("box", Vector3(-edge, h, -edge), Vector3(0.2, 5.0, 0.2), "timber_dark"))
		out.append(L.part("box", Vector3(-edge + 0.9, h + 3.4, -edge), Vector3(1.6, 1.4, 0.1), str(el.banner_color)))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := _size(el)
	return [L.solid("box", Vector3(0, s.y * 0.5, 0), Vector3(s.x, s.y, s.x))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Platform", parts(el, ctx))
