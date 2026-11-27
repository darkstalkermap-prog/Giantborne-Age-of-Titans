extends RefCounted
## Element kind "serac" (D1): a block of glacier ice standing where the glacier dropped it - leaning, split, its faces
## blue-white, snow on its top (static: one vertex-coloured mesh with the chunk's structures). `size` [w, h, d]; `seed`
## varies its blocks. Solid (the titan and the giant go round it).

const L := preload("res://tools/world/layout.gd")
const ICE := Color(0.66, 0.76, 0.84)
const ICE_DEEP := Color(0.46, 0.60, 0.72)
const SNOW := Color(0.90, 0.92, 0.94)


static func _pieces(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 16, 8))
	var seed := int(el.get("seed", 1))
	var out: Array = []
	# the main block, leaning; a split-off slab; a fallen chunk at its foot; snow on the main block's top
	var lean := 6.0 + 4.0 * float(seed % 3)
	out.append(L.part("frustum", Vector3(0, -1.5, 0), Vector3(s.x, s.y + 1.5, s.z), ICE, 10.0 * float(seed),
		Vector3(lean, 0, -lean * 0.5)))
	out.append(L.part("box", Vector3(s.x * 0.42, -1.0, s.z * 0.1), Vector3(s.x * 0.35, s.y * 0.72, s.z * 0.8), ICE_DEEP,
		25.0 + 7.0 * float(seed), Vector3(-lean * 1.4, 0, lean)))
	out.append(L.part("box", Vector3(-s.x * 0.55, -0.6, s.z * 0.45), Vector3(s.x * 0.4, s.y * 0.22, s.z * 0.5), ICE,
		40.0 * float(seed), Vector3(18, 0, 12)))
	out.append(L.part("pyramid", Vector3(0, s.y * 0.96, 0), Vector3(s.x * 0.82, s.y * 0.1, s.z * 0.82), SNOW,
		10.0 * float(seed), Vector3(lean, 0, -lean * 0.5)))
	return out


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return _pieces(el)


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 16, 8))
	return [L.solid("box", Vector3(0, s.y * 0.5 - 1.0, 0), Vector3(s.x * 0.9, s.y + 2.0, s.z * 0.9))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Serac", parts(el, ctx))
