extends RefCounted
## Element kind "warning_post" (B1; the milestone A gate's row "the Woodway's margin to his sight is thin"): the quarry
## folk's warning on a road before a titan's ground - a weathered timber post a giant's height, its crossbar hung with a
## cracked slab of the titan's own stone (its face scored with a hand's warning), a great skull of an old giant at its
## foot among rubble. Structures mesh (one draw call with the chunk's), the post and the skull solids. Facing local +z
## (the road it warns). `size` [h]: the post's height (default 9 m: over a stage-4 giant's knee, at a stage-3's chest).

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var h := float(L.size3(el, Vector3(9, 0, 0)).x)
	var out: Array = []
	out.append(L.part("box", Vector3(0, -0.8, 0), Vector3(0.9, h + 0.8, 0.9), "timber_dark", 0.0, Vector3(0, 0, 3.0)))
	out.append(L.part("box", Vector3(0, h - 1.4, 0.1), Vector3(4.6, 0.6, 0.6), "timber_dark", 0.0, Vector3(0, 0, -4.0)))
	# the slab, cracked across: two halves hung from the crossbar on iron, the lower a little askew
	out.append(L.part("box", Vector3(-0.15, h - 3.2, 0.5), Vector3(3.4, 1.7, 0.45), "stone_light", 0.0, Vector3(0, 0, 2.0)))
	out.append(L.part("box", Vector3(0.1, h - 4.85, 0.52), Vector3(3.2, 1.5, 0.45), "stone", 0.0, Vector3(0, 0, -6.0)))
	out.append(L.part("box", Vector3(-0.9, h - 3.0, 0.76), Vector3(0.25, 1.1, 0.06), "canvas_red", 0.0, Vector3(0, 0, 25.0)))
	out.append(L.part("box", Vector3(0.3, h - 3.2, 0.76), Vector3(1.5, 0.22, 0.06), "canvas_red", 0.0, Vector3(0, 0, -15.0)))
	out.append(L.part("box", Vector3(0.6, h - 4.7, 0.78), Vector3(0.22, 1.0, 0.06), "canvas_red", 0.0, Vector3(0, 0, -30.0)))
	for x: float in [-1.4, 1.2]:
		out.append(L.part("box", Vector3(x, h - 2.1, 0.45), Vector3(0.1, 0.9, 0.1), "iron"))
	# the skull at its foot, half sunk among the rubble, its brow cracked; rubble and a broken cart wheel
	out.append(L.part("sphere", Vector3(1.9, 0.6, 1.4), Vector3(2.8, 2.3, 2.6), "bone", 20.0))
	out.append(L.part("box", Vector3(2.5, 0.75, 2.45), Vector3(0.55, 0.5, 0.2), "black", 20.0))
	out.append(L.part("box", Vector3(1.55, 0.75, 2.55), Vector3(0.55, 0.5, 0.2), "black", 20.0))
	out.append(L.part("box", Vector3(2.2, -0.1, 2.3), Vector3(1.8, 0.7, 1.0), "bone_dark", 20.0))
	for k in 6:
		var a := 0.9 * k
		out.append(L.part("box", Vector3(cos(a) * (1.6 + 0.3 * k), -0.3, sin(a) * 1.4 - 0.6), Vector3(1.2 - 0.1 * k,
			0.8 + 0.1 * (k % 3), 1.0), "rock" if k % 2 == 0 else "stone_dark", 31.0 * k))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var h := float(L.size3(el, Vector3(9, 0, 0)).x)
	return [L.solid("box", Vector3(0, h * 0.5, 0), Vector3(1.0, h, 1.0)),
		L.solid("box", Vector3(1.9, 0.6, 1.4), Vector3(2.6, 2.0, 2.4), 20.0)]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("WarningPost", parts(el, ctx))
