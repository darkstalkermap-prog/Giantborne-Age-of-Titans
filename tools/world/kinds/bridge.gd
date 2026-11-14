extends RefCounted
## Element kind "bridge" (P25): the stone bridge over a river - its deck is the terrain (the
## world table's bridge ramp, so every nav layer and every giant crosses it), this kind draws the
## rest along local z (the crossing): parapets on both sides, arches with dark openings on both
## faces, piers standing in the water. `size` [deck width, length]. Visual only: no solids (the
## parapets would trip a giant's step).

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(12, 52, 0))
	var w := s.x
	var length := s.y
	var drop := float(el.get("drop_m", 8.0))
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 + 0.4)
		out.append(L.part("box", Vector3(x, -drop, 0), Vector3(1.6, drop + 1.3, length), "stone"))
		out.append(L.part("box", Vector3(x, 1.0, 0), Vector3(1.8, 0.4, length), "stone_light"))
		for a in 3:
			var z := (-1.0 + a) * length * 0.27
			out.append(L.part("box", Vector3(x + side * 0.3, -drop + 0.3, z), Vector3(0.4, drop - 2.0, length * 0.16), "dark"))
	for a in 2:
		var z := (-0.5 + a) * length * 0.27
		out.append(L.part("box", Vector3(0, -drop - 2.0, z), Vector3(w + 3.0, drop - 1.0, 3.0), "stone_dark"))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Bridge", parts(el, ctx))
