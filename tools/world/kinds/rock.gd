extends RefCounted
## Element kind "rock" (P25): living rock - style "wall" (a sheer rock wall of `size` [length, h,
## thick] along local x: the Needle's slot is two of them 5.0 m apart), "spire" (a rock needle of
## `size` [w, h]: the eyrie's ledge, the Titan's shoulder stone), "boulder" (a rough block). Solids.

const L := preload("res://tools/world/layout.gd")


static func _pieces(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(20, 20, 6))
	match str(el.get("style", "wall")):
		"spire":
			return [["frustum", Vector3(0, -2, 0), Vector3(s.x, s.y + 2, s.x * 0.45), "rock", 0.0],
				["box", Vector3(-s.x * 0.2, s.y * 0.75, -s.x * 0.2), Vector3(s.x * 0.6, 1.0, s.x * 0.6), "stone_dark", 20.0]]
		"boulder":
			return [["sphere", Vector3(0, -s.y * 0.2, 0), Vector3(s.x, s.y, s.z), "rock", 0.0]]
	var out: Array = [["box", Vector3(0, -2, 0), Vector3(s.x, s.y + 2, s.z), "rock", 0.0]]
	var n := maxi(1, int(s.x / 8.0))
	for k in n:
		out.append(["box", Vector3(-s.x * 0.5 + (k + 0.5) * s.x / n, s.y, 0), Vector3(s.x / n * 0.7, 2.0 + 2.0 * (k % 2), s.z * 0.8), "stone_dark", 0.0])
	return out


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	for p: Array in _pieces(el):
		out.append(L.part(str(p[0]), p[1], p[2], p[3], float(p[4])))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(20, 20, 6))
	match str(el.get("style", "wall")):
		"spire":
			return [L.solid("cyl", Vector3(0, s.y * 0.5, 0), Vector3(s.x * 0.8, s.y, s.x * 0.8))]
		"boulder":
			return [L.solid("box", Vector3(0, s.y * 0.3, 0), s * 0.8)]
	return [L.solid("box", Vector3(0, s.y * 0.5 - 1.0, 0), Vector3(s.x, s.y + 2.0, s.z))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Rock", parts(el, ctx))
