extends RefCounted
## Element kind "ruin" (P25): old stonework of `size` [w, h, d] by style:
##   "wall"      a broken wall (stepped top)
##   "arch"      two posts under a lintel (the Kingsgate's old gate, the Hidden Grove's door)
##   "alcove"    three walls (open toward local -z): the pocket of a sealed place, its seal in the
##               opening (a rockfall, a toppled statue, a titan-tree)
##   "vault"     an alcove with thick walls and a lintel (the sunken vault, the kings' armoury adit),
##               its front narrowed to a `door_m` door when given
##   "terrace"   a low retaining wall (the Sunken Steps' risers)
##   "rubble"    a heap of stones
##   "tunnel"    the dark mouth of a tunnel in a rock face (the Kings' Door tunnel on the shelf)
##   "earthwork" a low bank (the Moot battery's lines)
## Structures mesh; the standing pieces are solids (alcove and vault walls: tall enough that no
## giant reaches over them).

const L := preload("res://tools/world/layout.gd")


static func _pieces(el: Dictionary) -> Array:
	# [[shape, pos, size, color, solid?]]
	var s := L.size3(el, Vector3(16, 8, 10))
	var t := float(el.get("thick", 2.0))
	var out: Array = []
	match str(el.get("style", "wall")):
		"arch":
			for side: float in [-1.0, 1.0]:
				out.append(["box", Vector3(side * (s.x * 0.5 - t * 0.5), -1, 0), Vector3(t, s.y + 1, t * 1.5), "stone", true])
			out.append(["box", Vector3(0, s.y, 0), Vector3(s.x + 1.0, t, t * 1.6), "stone_light", false])
		"alcove", "vault":
			var thick := t if str(el.style) == "alcove" else t * 2.0
			var c := "stone" if str(el.style) == "vault" else "rock"
			out.append(["box", Vector3(0, -1, s.z * 0.5), Vector3(s.x, s.y + 1, thick), c, true])
			for side: float in [-1.0, 1.0]:
				out.append(["box", Vector3(side * s.x * 0.5, -1, 0), Vector3(thick, s.y + 1, s.z), c, true])
			if str(el.style) == "vault":
				out.append(["box", Vector3(0, s.y, -s.z * 0.5), Vector3(s.x + thick, thick, thick), "stone_light", false])
				out.append(["box", Vector3(0, -0.6, 0), Vector3(s.x - thick, 0.8, s.z - thick), "dark", false])
				# `door_m`: the front narrows to a door that its seal (a rockfall) closes, while the
				# chamber stays wide enough for a titan's navmesh (its 4 m radius all round)
				var door := float(el.get("door_m", 0.0))
				if door > 0.0:
					var stub := (s.x - door) * 0.5
					for side: float in [-1.0, 1.0]:
						out.append(["box", Vector3(side * (s.x * 0.5 - stub * 0.5), -1, -s.z * 0.5), Vector3(stub, s.y + 1, thick), c, true])
		"terrace":
			out.append(["box", Vector3(0, -1.5, 0), Vector3(s.x, s.y + 1.5, t), "stone", false])
			for k in int(s.x / 12.0):
				out.append(["box", Vector3(-s.x * 0.5 + 6.0 + 12.0 * k, s.y, 0), Vector3(3.0, 1.0, t + 0.4), "stone_light", false])
		"rubble":
			for k in 6:
				var a := TAU * k / 6.0
				out.append(["box", Vector3(cos(a) * s.x * 0.3, -0.5, sin(a) * s.z * 0.3), Vector3(s.x * 0.35, s.y * (0.5 + 0.1 * (k % 3)), s.z * 0.35), "stone_dark" if k % 2 else "stone", true])
			out.append(["box", Vector3(0, -0.5, 0), Vector3(s.x * 0.6, s.y, s.z * 0.6), "stone", true])
		"tunnel":
			out.append(["box", Vector3(0, -1, 0.5), Vector3(s.x + 8.0, s.y + 6.0, 3.0), "rock", false])
			out.append(["box", Vector3(0, 0, -1.2), Vector3(s.x, s.y, 0.6), "dark", false])
			for side: float in [-1.0, 1.0]:
				out.append(["box", Vector3(side * (s.x * 0.5 + 0.8), -0.5, -1.6), Vector3(1.6, s.y + 1.5, 1.6), "stone_light", false])
			out.append(["box", Vector3(0, s.y, -1.6), Vector3(s.x + 3.2, 1.8, 1.8), "stone_light", false])
			out.append(["box", Vector3(0, s.y + 0.2, -2.6), Vector3(2.6, 1.0, 0.3), "rune", false])
		"earthwork":
			out.append(["wedge", Vector3(0, -0.5, 0), Vector3(s.x, s.y + 0.5, s.z), "soil", true])
		_:
			var n := maxi(2, int(s.x / 4.0))
			for k in n:
				var hh := s.y * (0.45 + 0.55 * absf(sin(k * 1.7 + s.x)))
				out.append(["box", Vector3(-s.x * 0.5 + (k + 0.5) * s.x / n, -1, 0), Vector3(s.x / n + 0.05, hh + 1, t), "stone", true])
	return out


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el):
		out.append(L.part(str(p[0]), p[1], p[2], p[3]))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	if bool(el.get("no_solids", false)):
		return []
	var out: Array = []
	for p: Array in _pieces(el):
		if bool(p[4]):
			var pos: Vector3 = p[1]
			var size: Vector3 = p[2]
			out.append(L.solid("box", pos + Vector3.UP * size.y * 0.5, size))
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Ruin", parts(el, ctx))
