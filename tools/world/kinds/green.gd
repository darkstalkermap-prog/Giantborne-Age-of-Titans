extends RefCounted
## Element kind "green" (P25; plan M6-M9 §2.12, decision 31): a settlement's green for big giants
## - a flat round sward of `radius` m ringed with low stones, and its meeting stone, where a talker
## meets a giant too big for the settlement's streets (the POI's green_m). The meeting stone is a
## solid; the rest is the structures mesh.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var r := float(el.get("radius", 24.0))
	var out: Array = [L.part("cyl", Vector3(0, -0.4, 0), Vector3(2.0 * r, 0.55, 0), "grass")]
	for k in 12:
		var a := TAU * k / 12.0
		out.append(L.part("box", Vector3(cos(a) * r, -0.3, sin(a) * r), Vector3(1.2, 0.9, 1.0), "stone", rad_to_deg(a)))
	out.append(L.part("box", Vector3(0, -0.5, -r * 0.4), Vector3(3.0, 4.2, 1.8), "stone_light", 8.0))
	out.append(L.part("box", Vector3(0, 2.2, -r * 0.4 + 0.92), Vector3(0.9, 0.9, 0.1), "rune", 8.0))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var r := float(el.get("radius", 24.0))
	return [L.solid("box", Vector3(0, 1.6, -r * 0.4), Vector3(3.0, 4.2, 1.8), 8.0)]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Green", parts(el, ctx))
