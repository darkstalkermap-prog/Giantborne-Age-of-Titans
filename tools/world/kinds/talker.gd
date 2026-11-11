extends RefCounted
## Element kind "talker" (P36; plan M6-M9 §2.12, §5.7): a conversation placed in the world on its own -
## an NpcTalker (scripts/world/npc_talker.gd) with `npc_id` (the speaker's entity id: a talker beside a
## spawned actor - Ulfra, a giant of Skarn - names it, so the talk ends with the actor's death; else the
## element's id), `dialogue` (its dialogue record), `prompt` ("" = "Talk to <speaker>"), `radius`
## (metres from the giant's capsule) and `requires_stage`. Style "horn" stands a horn post with a
## banner where it is (Fort Aldmere's gate: "Hail Warlord Corvane" - the warlord answers from his
## wall), "stone" a speaking stone (the Moot's gate: Harrok's challenge), "none" nothing (an actor
## stands there). Its chunk's props sub-scene holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_TALKER := "res://scripts/world/npc_talker.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func figure(el: Dictionary) -> Array:
	var out: Array = []
	match str(el.get("style", "none")):
		"horn":
			out.append(L.part("cyl", Vector3(0, -0.5, 0), Vector3(0.5, 9.0, 0), "timber_dark"))
			out.append(L.part("box", Vector3(1.3, 5.5, 0), Vector3(2.4, 3.0, 0.15), str(el.get("color", "banner_blue"))))
			out.append(L.part("frustum", Vector3(0, 3.2, 0.4), Vector3(0.9, 1.6, 0.25), "bone", 0.0, Vector3(80, 0, 0)))
		"stone":
			out.append(L.part("box", Vector3(0, -0.6, 0), Vector3(3.6, 7.0, 1.6), "stone_dark", 0.0, Vector3(0, 0, 4)))
			out.append(L.part("box", Vector3(0, 3.6, 0.82), Vector3(1.4, 2.0, 0.1), "rune"))
	return out


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var props := {"npc_id": str(el.get("npc_id", el.id)), "dialogue_id": str(el.get("dialogue", "")),
		"radius_m": float(el.get("radius", 6.0)), "priority": int(el.get("priority", 40))}
	if str(el.get("prompt", "")) != "":
		props["prompt"] = str(el.prompt)
	if int(el.get("requires_stage", 0)) > 0:
		props["requires_stage"] = int(el.requires_stage)
		if str(el.get("stage_message", "")) != "":
			props["stage_message"] = str(el.stage_message)
	kit.scripted(n, S_TALKER, props)
	var parts := figure(el)
	if not parts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = SceneKit.L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = kit.box_shape(Vector3(1.2, 6.0, 1.2))
		cs.position = Vector3(0, 3.0, 0)
		body.add_child(cs)
		body.add_child(L.parts_node("Figure", parts, ctx.get("mat")))
		n.add_child(body)
	return n
