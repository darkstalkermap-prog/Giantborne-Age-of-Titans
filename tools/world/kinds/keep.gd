extends RefCounted
## Element kind "keep" (P36; plan M6-M9 §5.4, §5.13 boss 1): Fort Aldmere's keep - a stone block of
## `size` [w, h, d] with four corner turrets, a crenellated roof walk and a tall banner, and on its
## front (the frame's forward, local -z) a broad, shallow flight of steps where Warlord Corvane's
## guard makes the Last Stand. The steps are visual only (units and the giant stand on the bailey's
## floor through them); the block is a solid. Structures mesh.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(34, 26, 24))
	var out: Array = []
	out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x, s.y + 1, s.z), "stone"))
	for i in 4:
		var cx := (-0.5 + (i % 2)) * (s.x - 3.0)
		var cz := (-0.5 + (i / 2)) * (s.z - 3.0)
		out.append(L.part("box", Vector3(cx, -1, cz), Vector3(5.0, s.y + 6.0, 5.0), "stone_light"))
		out.append(L.part("pyramid", Vector3(cx, s.y + 5.0, cz), Vector3(6.0, 4.0, 6.0), "roof_slate"))
	var n := maxi(2, int(s.x / 3.5))
	for i in n:
		var x := -s.x * 0.5 + (i + 0.5) * s.x / n
		out.append(L.part("box", Vector3(x, s.y, -s.z * 0.5 + 0.6), Vector3(1.6, 1.4, 1.2), "stone_dark"))
		out.append(L.part("box", Vector3(x, s.y, s.z * 0.5 - 0.6), Vector3(1.6, 1.4, 1.2), "stone_dark"))
	# the great door and the banner over it
	out.append(L.part("box", Vector3(0, -0.5, -s.z * 0.5 - 0.05), Vector3(8.0, 11.0, 0.4), "timber_dark"))
	out.append(L.part("box", Vector3(0, s.y + 1.4, 0), Vector3(0.5, 12.0, 0.5), "timber_dark"))
	out.append(L.part("box", Vector3(2.4, s.y + 8.0, 0), Vector3(4.6, 3.4, 0.2), str(el.get("banner_color", "banner_blue"))))
	# the steps before the door: three broad, shallow risers (no collision)
	var steps := float(el.get("steps_m", 12.0))
	for k in 3:
		var depth := steps * (3 - k) / 3.0
		out.append(L.part("box", Vector3(0, -0.4 + k * 0.15, -s.z * 0.5 - depth * 0.5), Vector3(s.x * 0.7 - k * 3.0, 0.5, depth),
			"stone_light" if k % 2 == 0 else "stone"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(34, 26, 24))
	return [L.solid("box", Vector3(0, s.y * 0.5, 0), Vector3(s.x + 1.0, s.y + 1.0, s.z + 1.0))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Keep", parts(el, ctx))
