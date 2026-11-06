extends RefCounted
## Element kind "pier" (P25): a timber pier of `size` [w, length] running along local -z from the
## shore into the water, its deck `deck_m` above the water at pos (Hollowmere's pond, the Mere's
## landings). Visual only (a giant wades beside it).

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(4, 24, 0))
	var deck := float(el.get("deck_m", 1.2))
	var out: Array = []
	out.append(L.part("box", Vector3(0, deck, -s.y * 0.5), Vector3(s.x, 0.4, s.y), "timber"))
	var n := maxi(2, int(s.y / 6.0))
	for k in n + 1:
		for side: float in [-0.45, 0.45]:
			out.append(L.part("box", Vector3(s.x * side, -3.0, -k * s.y / n), Vector3(0.5, deck + 3.2, 0.5), "timber_dark"))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Pier", parts(el, ctx))
