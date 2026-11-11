extends RefCounted
## Element kind "throne" (P36; plan M6-M9 §5.4, §5.7): the Stone Throne of the Moot - a great seat of
## stacked slabs (statue.gd's throne shape) on a WORLD body, and the StoneThrone interaction
## (scripts/world/stone_throne.gd): "Take the Stone Throne" once the clans' champion is settled
## (`requires_flag`, boss.harrok.outcome), setting `claim_flag` (world.throne.claimed); the campaign's
## end screen opens from it when the main quest completes. `size` [w, h]; the interaction reaches
## `radius` m from the giant's capsule. Its chunk's props sub-scene holds it; the index lists it.

const L := preload("res://tools/world/layout.gd")
const STATUE := preload("res://tools/world/kinds/statue.gd")
const SCRIPTED := true
const S_THRONE := "res://scripts/world/stone_throne.gd"


## The throne's parts: the map's footprint (its node has its own mesh).
static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	return STATUE.parts(shape_el(el), ctx)


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func shape_el(el: Dictionary) -> Dictionary:
	var e := el.duplicate()
	e["style"] = "throne"
	return e


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var props := {"world_id": str(el.id), "radius_m": float(el.get("radius", 14.0)), "priority": 30}
	for key: String in ["claim_flag", "requires_flag", "blocked_message", "claimed_message"]:
		if el.has(key):
			props[key] = str(el[key])
	kit.scripted(n, S_THRONE, props)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	var k := 0
	for s: Dictionary in STATUE.solids(shape_el(el), ctx):
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % k
		cs.shape = kit.box_shape(s.size)
		cs.position = s.center
		body.add_child(cs)
		k += 1
	body.add_child(L.parts_node("Throne", STATUE.parts(shape_el(el), ctx), ctx.get("mat")))
	n.add_child(body)
	return n
