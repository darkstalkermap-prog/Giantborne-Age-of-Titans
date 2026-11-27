extends RefCounted
## Element kind "trophy" (D1): a titan's piece set up where folk can see it (scripts/presentation/trophy_display.gd:
## TrophyDisplay - `creature` whose asset, `piece` its node name, `align`, `rotation` degrees) on a dry-stone plinth
## of `size` [w, h] - Last Hearth's Heart-ice by its beacon once Maera has heard the Frostbound has fallen. FLAG_WRAP:
## a flagged trophy is built whole inside its FlagVisibility. The piece is drawn where the people are (a display).

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const FLAG_WRAP := true
const S_TROPHY := "res://scripts/presentation/trophy_display.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(5, 2, 5))
	return [L.solid("cyl", Vector3(0, s.y * 0.5, 0), Vector3(s.x, s.y, s.x))]


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var s := L.size3(el, Vector3(5, 2, 5))
	var plinth: Array = []
	var stones := 9
	for k in stones:
		var a := TAU * float(k) / float(stones)
		plinth.append(L.part("box", Vector3(cos(a) * s.x * 0.38, 0, sin(a) * s.x * 0.38),
			Vector3(s.x * 0.34, s.y * (0.85 + 0.1 * float(k % 3)), s.x * 0.22), "stone_dark", rad_to_deg(-a)))
	plinth.append(L.part("cyl", Vector3(0, 0, 0), Vector3(s.x * 0.8, s.y, s.x * 0.8), "stone"))
	n.add_child(L.parts_node("Plinth", plinth))
	var d := Node3D.new()
	d.name = "Trophy"
	var rot: Array = el.get("rotation", [0, 0, 0])
	kit.scripted(d, S_TROPHY, {"creature": str(el.get("creature", "ogre_king")), "piece": str(el.get("piece", "")),
		"align": str(el.get("align", "none")), "piece_rotation_deg": Vector3(float(rot[0]), float(rot[1]), float(rot[2]))})
	d.position = Vector3(0, s.y + float(el.get("lift", 1.5)), 0)
	n.add_child(d)
	return n
