extends RefCounted
## Element kind "beacon" (P25): a beacon tower - a square stone tower of `size` [w, h] with a
## brazier platform on top (the Kingsgate beacon, 31 m; Shepherd's Watch's watch beacon, 15 m).
## Indestructible by construction (a static structure: no hit reaches it) and a quest target by its
## world id; the skyline draws its fog-free light column while its flag is set (world.json
## "beacons"). Its interaction (relighting it) comes with the Crownmarch's package (P29).

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(8, 31, 8))
	var w := s.x
	var h := s.y
	var out: Array = []
	out.append(L.part("box", Vector3(0, -1.0, 0), Vector3(w + 2.0, 4.0, w + 2.0), "stone_dark"))
	out.append(L.part("box", Vector3(0, 2.5, 0), Vector3(w, h - 4.0, w), "stone"))
	out.append(L.part("box", Vector3(0, h - 1.5, 0), Vector3(w + 1.6, 1.2, w + 1.6), "stone_light"))
	for i in 4:
		var cx := (-0.5 + (i % 2)) * (w + 0.6)
		var cz := (-0.5 + (i / 2)) * (w + 0.6)
		out.append(L.part("box", Vector3(cx, h - 0.3, cz), Vector3(1.2, 2.0, 1.2), "stone_dark"))
	out.append(L.part("frustum", Vector3(0, h - 0.3, 0), Vector3(w * 0.35, 1.6, w * 0.6), "iron"))
	out.append(L.part("cone", Vector3(0, h + 1.2, 0), Vector3(w * 0.4, 1.4, 0), "black"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(8, 31, 8))
	return [L.solid("box", Vector3(0, s.y * 0.5, 0), Vector3(s.x + 2.0, s.y, s.x + 2.0))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Beacon", parts(el, ctx))
