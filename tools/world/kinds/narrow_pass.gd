extends RefCounted
## Element kind "narrow_pass" (P35; plan M6-M9 §5.5): the sign of a pass too narrow for a big giant -
## a NarrowPass (scripts/world/narrow_pass.gd), an Area3D box `size` [width, height, length] along
## local z (the slot's length plus a little at each mouth) that tells a giant above `max_stage` it no
## longer fits ("Too narrow. You have outgrown the Needle.") with the stone gate cue. The walls that
## really stop it are the slot's rock walls (kind "rock"). Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_PASS := "res://scripts/world/narrow_pass.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var a := Area3D.new()
	a.name = str(el.get("id", "NarrowPass")).validate_node_name()
	var props := {"pass_id": str(el.get("id", "")), "max_stage": int(el.get("max_stage", 4)),
		"cue": str(el.get("cue", "sfx.gate.stone"))}
	if str(el.get("message", "")) != "":
		props["message"] = str(el.message)
	kit.scripted(a, S_PASS, props)
	a.collision_layer = 0
	a.collision_mask = SceneKit.L_ACTORS
	a.monitoring = true
	a.monitorable = false
	var s := L.size3(el, Vector3(8, 14, 70))
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = kit.box_shape(s)
	cs.position = Vector3(0, s.y * 0.5 - 1.0, 0)
	a.add_child(cs)
	return a
