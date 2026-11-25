extends RefCounted
## Element kind "colossal" (C1): the old giant kings' works beyond the rim, built at the colossi's scale
## (a 24-29 m giant beside them reads as a man beside a cathedral's ruin), `scale` x their default size,
## by style:
##   "fallen_king"   the Fallen King - a giant-king's statue that stood about 90 m: its plinth and the
##                   stumps of its legs where it stood, its torso, crowned head and arm fallen beside them
##                   along local +z, rubble between
##   "chain_anchor"  a chain anchor of the Worldbreaker's binding: an iron-banded stone bollard as tall as
##                   a tower, a ring on its crown and a chain of links each taller than a house running
##                   from it along local -z, down into the ground (toward the mountains)
##   "pier"          a pier of the Kings' Causeway: two pillars and a cracked lintel, paving under them
##   "breach_jaws"   the Breach's mouth: leaning slabs of the split rim on both sides and a snapped chain
##                   lying across (the size gate's wall stands behind them in the layout)
##   "rimstone"      the Rimstone: one standing stone about 64 m tall with its rune band, six lesser
##                   stones leaning round it
##   "split_cairn"   a heap of giant-cut blocks
## Structures mesh (one draw with the chunk's other works); the standing pieces are solids.

const L := preload("res://tools/world/layout.gd")


static func _k(el: Dictionary) -> float:
	return float(el.get("scale", 1.0))


## [[shape, pos, size, color, yaw, tilt, solid]] in the element's frame.
static func _pieces(el: Dictionary) -> Array:
	var k := _k(el)
	var out: Array = []
	match str(el.get("style", "fallen_king")):
		"fallen_king":
			# the plinth and the stumps of the legs
			out.append(["box", Vector3(0, -2, 0) * k, Vector3(44, 12, 30) * k, "stone_dark", 0.0, Vector3.ZERO, true])
			out.append(["box", Vector3(-9, 10, 0) * k, Vector3(10, 26, 11) * k, "stone_light", 0.0, Vector3(0, 0, 3), true])
			out.append(["box", Vector3(9, 10, 1) * k, Vector3(10, 17, 11) * k, "stone_light", 4.0, Vector3(0, 0, -5), true])
			out.append(["box", Vector3(-9, 35, 0) * k, Vector3(10.4, 2.0, 11.4) * k, "stone", 12.0, Vector3(18, 0, 9), false])
			# the torso fallen face down along +z, broken at the waist
			out.append(["box", Vector3(-4, -2, 34) * k, Vector3(30, 15, 38) * k, "stone_light", 6.0, Vector3(4, 0, -6), true])
			out.append(["box", Vector3(-6, 11, 34) * k, Vector3(22, 5, 30) * k, "stone", 6.0, Vector3(4, 0, -6), false])
			# the head on its side, its crown broken off beside it
			out.append(["sphere", Vector3(10, -1, 66) * k, Vector3(17, 19, 18) * k, "stone_light", 20.0, Vector3(0, 0, 70), true])
			out.append(["box", Vector3(9, -2, 66) * k, Vector3(9, 8, 14) * k, "stone_light", 20.0, Vector3(0, 0, 70), false])
			for c in 5:
				var a := deg_to_rad(-40.0 + c * 22.0)
				out.append(["cone", Vector3(26 + cos(a) * 9, -1, 70 + sin(a) * 9) * k, Vector3(4, 9, 4) * k, "gold", 0.0,
					Vector3(70 + c * 6, 0, 20), false])
			out.append(["cyl", Vector3(26, -1.5, 70) * k, Vector3(18, 3, 0) * k, "gold", 0.0, Vector3(80, 0, 10), false])
			# the arm, its fist half sunk in the ground
			out.append(["box", Vector3(-26, -1, 46) * k, Vector3(8, 8, 42) * k, "stone_light", -28.0, Vector3(-3, 0, 0), true])
			out.append(["sphere", Vector3(-38, -3, 70) * k, Vector3(12, 11, 12) * k, "stone", 0.0, Vector3.ZERO, true])
			# rubble
			for r in 9:
				var a := TAU * r / 9.0
				var rad := 22.0 + 6.0 * sin(r * 2.3)
				out.append(["box", Vector3(cos(a) * rad, -1.0, 30.0 + sin(a) * rad * 1.5) * k,
					Vector3(4.5 + (r % 3) * 2.0, 3.0 + (r % 2) * 3.0, 4.0 + (r % 4)) * k, "stone" if r % 2 else "stone_dark",
					r * 23.0, Vector3((r % 3) * 7.0, 0, (r % 2) * 9.0), false])
		"chain_anchor":
			# the bollard: a battered stone drum in iron bands
			out.append(["frustum", Vector3(0, -3, 0) * k, Vector3(26, 40, 19) * k, "stone_dark", 0.0, Vector3.ZERO, true])
			for b in 3:
				out.append(["cyl", Vector3(0, 4 + b * 11, 0) * k, Vector3(25.5 - b * 2.2, 2.6, 0) * k, "iron", 0.0, Vector3.ZERO, false])
			out.append(["frustum", Vector3(0, 37, 0) * k, Vector3(19, 4, 14) * k, "stone", 0.0, Vector3.ZERO, false])
			# the ring on its crown (eight bars in the plane facing the chain)
			for r in 8:
				var a := TAU * r / 8.0
				out.append(["box", Vector3(0, 52 + sin(a) * 9, cos(a) * 9) * k, Vector3(3.2, 3.2, 7.6) * k, "iron", 0.0,
					Vector3(-rad_to_deg(a) + 90.0, 0, 0), false])
			# the chain: links alternately flat and on edge, descending along -z into the ground
			var n := int(el.get("links", 9))
			var drop := float(el.get("drop_m", 60.0))
			for c in n:
				var t := float(c) / float(maxi(1, n - 1))
				var z := -(12.0 + c * 8.2)
				var y := 44.0 - t * (44.0 + drop * 0.25) - t * t * drop * 0.6
				var slope := rad_to_deg(atan2(44.0 + drop, 8.2 * n)) * (0.6 + 0.8 * t)
				if c % 2 == 0:
					out.append(["box", Vector3(0, y, z) * k, Vector3(7.0, 2.0, 10.0) * k, "iron", 0.0, Vector3(-slope, 0, 0), false])
				else:
					out.append(["box", Vector3(0, y - 3.0, z) * k, Vector3(2.0, 7.0, 10.0) * k, "iron", 0.0, Vector3(-slope, 0, 0), false])
			# where the chain goes under: a heap of broken rock
			var under := -(12.0 + n * 8.2)
			out.append(["box", Vector3(0, -2, under) * k, Vector3(16, 6, 12) * k, "rock", 12.0, Vector3(0, 0, 6), false])
		"pier":
			for side: float in [-1.0, 1.0]:
				out.append(["box", Vector3(side * 14, -2, 0) * k, Vector3(7, 34, 7) * k, "stone_light", 0.0, Vector3.ZERO, true])
				out.append(["box", Vector3(side * 14, 31, 0) * k, Vector3(9, 3, 9) * k, "stone", 0.0, Vector3.ZERO, false])
			out.append(["box", Vector3(-6, 34, 0) * k, Vector3(20, 5, 8) * k, "stone_light", 0.0, Vector3(0, 0, -3), false])
			out.append(["box", Vector3(12, 33.5, 0) * k, Vector3(9, 5, 8) * k, "stone", 0.0, Vector3(0, 0, 14), false])
			out.append(["box", Vector3(0, -0.6, 0) * k, Vector3(36, 1.0, 14) * k, "stone_dark", 0.0, Vector3.ZERO, false])
		"breach_jaws":
			for side: float in [-1.0, 1.0]:
				for s in 4:
					out.append(["box", Vector3(side * (34 + s * 7), -4, -8 + s * 9) * k, Vector3(12, 38 + s * 9, 10) * k,
						"rock" if s % 2 else "stone_dark", side * (8.0 + s * 5.0), Vector3(-6 + s * 4, 0, -side * (10 + s * 3)), s < 2])
			# the snapped chain across the mouth
			for c in 7:
				var x := -28.0 + c * 8.5
				if c % 2 == 0:
					out.append(["box", Vector3(x, -0.6, 4) * k, Vector3(10, 2, 7) * k, "iron", 90.0, Vector3(0, 0, (c - 3) * 3.0), false])
				else:
					out.append(["box", Vector3(x, -2.2, 4) * k, Vector3(10, 7, 2) * k, "iron", 90.0, Vector3(0, 0, (c - 3) * 3.0), false])
		"rimstone":
			out.append(["box", Vector3(0, -3, 0) * k, Vector3(13, 67, 8) * k, "stone_dark", 0.0, Vector3(0, 0, 2), true])
			out.append(["box", Vector3(0, 40, 4.05) * k, Vector3(6, 14, 0.4) * k, "rune", 0.0, Vector3(0, 0, 2), false])
			out.append(["box", Vector3(0, 40, -4.05) * k, Vector3(6, 14, 0.4) * k, "rune", 0.0, Vector3(0, 0, 2), false])
			for s in 6:
				var a := TAU * s / 6.0 + 0.3
				out.append(["box", Vector3(cos(a) * 36, -2, sin(a) * 36) * k, Vector3(7, 24 + (s % 3) * 6, 4) * k, "stone_light",
					-rad_to_deg(a) + 90.0, Vector3(0, 0, 8 + (s % 2) * 6), true])
		"split_cairn":
			for s in 7:
				var a := TAU * s / 7.0
				out.append(["box", Vector3(cos(a) * 7, -1 + (s % 3) * 4, sin(a) * 7) * k, Vector3(9, 7, 8) * k,
					"stone_light" if s % 2 else "stone", s * 31.0, Vector3((s % 2) * 8.0, 0, 0), s < 4])
	return out


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4]), p[5]))
	return out


## The standing pieces as solids (their tilt is left out: a box upright round the piece's middle).
static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	if bool(el.get("no_solids", false)):
		return []
	var out: Array = []
	for p: Array in _pieces(el):
		if not bool(p[6]):
			continue
		var pos: Vector3 = p[1]
		var size: Vector3 = p[2]
		var shape := str(p[0])
		if shape == "frustum" or shape == "cyl":
			out.append(L.solid("cyl", pos + Vector3.UP * size.y * 0.5, Vector3(maxf(size.x, size.z), size.y, 0.0), float(p[4])))
		else:
			out.append(L.solid("box", pos + Vector3.UP * size.y * 0.5, size, float(p[4])))
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Colossal", parts(el, ctx))
