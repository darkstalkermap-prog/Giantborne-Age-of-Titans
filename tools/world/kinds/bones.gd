extends RefCounted
## Element kind "bones" (P25): the Titan's Bones - the skeleton of a giant of the old kind lying
## along local x, `length` metres (120): a spine of vertebrae, ribs arching up to about a quarter of
## its length, the skull at +x, the pelvis and the bones of an arm and a leg. Structures mesh; the
## skull, the pelvis, the vertebrae and the ribs' feet are solids (the ribs themselves arch over a
## giant: the Titan Forge stands in them, P35).

const L := preload("res://tools/world/layout.gd")


static func _pieces(el: Dictionary) -> Array:
	var length := float(el.get("length", 120.0))
	var u := length / 120.0
	var out: Array = []
	# the spine: vertebrae along x
	for k in 14:
		var x := (-48.0 + k * 6.5) * u
		out.append(["box", Vector3(x, -1.0, 0), Vector3(4.2 * u, 5.0 * u, 5.0 * u), "bone", 0.0, Vector3(0, 0, 8.0 * sin(k)), true])
	# ribs: three tilted pieces per side making an arch
	for k in 9:
		var x := (-6.0 + k * 5.8) * u
		var rh := (26.0 - absf(k - 4.0) * 2.4) * u
		for side: float in [-1.0, 1.0]:
			out.append(["box", Vector3(x, 0.5 * u, side * 3.5 * u), Vector3(1.6 * u, rh * 0.55, 1.6 * u), "bone_dark", 0.0, Vector3(side * 28.0, 0, 0), true])
			out.append(["box", Vector3(x, rh * 0.45, side * (3.5 + rh * 0.27) * u), Vector3(1.4 * u, rh * 0.5, 1.4 * u), "bone", 0.0, Vector3(side * -10.0, 0, 0), false])
	# the skull and its jaw
	out.append(["sphere", Vector3(56.0 * u, -2.0, 2.0 * u), Vector3(16.0 * u, 13.0 * u, 13.0 * u), "bone", 15.0, Vector3.ZERO, true])
	out.append(["box", Vector3(66.0 * u, -1.5, 4.0 * u), Vector3(10.0 * u, 3.0 * u, 8.0 * u), "bone_dark", 30.0, Vector3(0, 0, -12.0), false])
	out.append(["box", Vector3(55.0 * u, 4.0 * u, 5.0 * u), Vector3(3.0 * u, 3.0 * u, 2.0 * u), "black", 15.0, Vector3.ZERO, false])
	# the pelvis, a leg and an arm thrown out
	out.append(["box", Vector3(-52.0 * u, -1.0, 0), Vector3(10.0 * u, 7.0 * u, 16.0 * u), "bone", 0.0, Vector3(0, 0, -6.0), true])
	out.append(["box", Vector3(-62.0 * u, -0.5, 10.0 * u), Vector3(26.0 * u, 3.0 * u, 3.0 * u), "bone_dark", -25.0, Vector3.ZERO, true])
	out.append(["box", Vector3(30.0 * u, -0.5, -18.0 * u), Vector3(24.0 * u, 2.6 * u, 2.6 * u), "bone_dark", 40.0, Vector3.ZERO, true])
	return out


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4]), p[5]))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el):
		if not bool(p[6]):
			continue
		var pos: Vector3 = p[1]
		var size: Vector3 = p[2]
		var tilt: Vector3 = p[5]
		if tilt != Vector3.ZERO and str(p[0]) == "box" and size.y > size.x * 3.0:
			# a tilted rib foot: a short upright box at its base
			out.append(L.solid("box", pos + Vector3.UP * 2.0, Vector3(size.x, 4.0, size.z), float(p[4])))
			continue
		out.append(L.solid("box", pos + Vector3.UP * size.y * 0.5, size, float(p[4])))
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Bones", parts(el, ctx))
