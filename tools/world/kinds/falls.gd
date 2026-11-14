extends RefCounted
## Element kind "falls" (P25): a waterfall - a sheet of falling water `size` [w, h] across local x,
## the spray at its foot and the dark rock behind it (the Wend Falls, where the river leaves the
## kingdom through the rim). Visual only.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(36, 30, 0))
	return [
		L.part("box", Vector3(0, -s.y, 2.0), Vector3(s.x + 10.0, s.y * 2.0, 3.0), "rock"),
		L.part("box", Vector3(0, -s.y, 0), Vector3(s.x, s.y * 2.0 - 1.0, 0.8), "water"),
		L.part("box", Vector3(0, -s.y, -3.0), Vector3(s.x + 6.0, 1.6, 6.0), "stone_light"),
	]


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Falls", parts(el, ctx))
