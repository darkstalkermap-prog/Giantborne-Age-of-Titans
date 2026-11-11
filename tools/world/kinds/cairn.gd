extends RefCounted
## Element kind "cairn" (P25; plan M6-M9 decision 33): an Old Kings' cairn - an Inscription
## (scripts/world/inscription.gd) whose dialogue, dialogue.cairn_<name>, gives one attribute point
## once (its once_flag reward.cairn.<name>), standing on its stacked stones (a WORLD body). The
## element's id is the cairn's world id; `dialogue` names its dialogue record. Its chunk's props
## sub-scene holds it; the index lists it as a prop (and as its POI's landmark when it is one).
## P35: `requires_stage` (a cairn on a ledge only a big giant reaches: the Titan's shoulder) and
## `ledge_m` (its stones stand that far up, on the ledge; the reading stays at the foot).

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_INSCRIPTION := "res://scripts/world/inscription.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func stones() -> Array:
	var out: Array = []
	var sizes := [Vector3(3.0, 1.1, 2.8), Vector3(2.4, 1.0, 2.3), Vector3(1.9, 0.9, 1.8), Vector3(1.3, 0.8, 1.2), Vector3(0.8, 0.6, 0.8)]
	var y := -0.4
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		out.append(L.part("box", Vector3(0.08 * (i % 2), y, -0.06 * (i % 3)), s, "rock" if i % 2 == 0 else "stone_dark", 23.0 * i))
		y += s.y
	out.append(L.part("box", Vector3(0, 1.4, 1.42), Vector3(0.8, 0.6, 0.12), "rune"))
	return out


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_INSCRIPTION, {"npc_id": str(el.id), "dialogue_id": str(el.dialogue), "prompt": "Read the cairn",
		"radius_m": 4.0, "priority": 45, "requires_stage": int(el.get("requires_stage", 0))})
	# P36: a sealed cairn on a ledge (the ridge eyrie, y_off up its cliff) is read only by a giant tall
	# enough to reach it (`requires_stage`, `stage_message`; the reach from the ground below, `radius`).
	# W21: a cairn whose reading stays at its foot (P35's `ledge_m`) keeps the 4 m reach.
	if int(el.get("requires_stage", 0)) > 0:
		n.set("requires_stage", int(el.requires_stage))
		n.set("radius_m", float(el.get("radius", 8.0 if float(el.get("y_off", 0.0)) > 0.0 else 4.0)))
		if str(el.get("stage_message", "")) != "":
			n.set("stage_message", str(el.stage_message))
	var base := StaticBody3D.new()
	base.name = "Base"
	base.collision_layer = SceneKit.L_WORLD
	base.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = kit.box_shape(Vector3(3.0, 4.0, 3.0))
	cs.position = Vector3(0, 1.6, 0)
	base.add_child(cs)
	base.add_child(L.parts_node("Stones", stones(), ctx.get("mat")))
	base.position = Vector3(0, float(el.get("ledge_m", 0.0)), 0)
	n.add_child(base)
	return n
