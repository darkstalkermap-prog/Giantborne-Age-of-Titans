extends RefCounted
## Element kind "condition_forge" (P36; plan M6-M9 §5.7, §5.9, §5.12): a forge a deed opens - a
## ConditionForge (scripts/world/condition_forge.gd: P12's Forge with an `open_when` quest condition)
## with the element's world id, `display_name`, `tier` (iron | titan), `open_when` and
## `closed_message` (and M8 gate, F16: `faction` and `hostile_message` - shut while that settlement is
## hostile): Fort Aldmere's (open on the crown's parley or a spared Corvane) and Skarn's
## hearth-forge (open once Skarn is saved or rebuilt). A titan's forge, built here at a giant's scale
## (a stone hearth with its chimney and glowing coals, a great anvil) as one mesh of the world's
## vertex-coloured material - one draw call where forge.tscn's three materials cost three in the
## settlements' views (plan §3.8's 40 a view) - with the hearth's and the anvil's solids. Its chunk's
## props sub-scene holds it; the index lists it as a prop.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_FORGE := "res://scripts/world/condition_forge.gd"


## The forge's parts (also the map's footprint): the hearth along local -z, the anvil before it.
static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	out.append(L.part("box", Vector3(0, -0.5, -2.5), Vector3(7.0, 3.5, 4.5), "stone_dark"))
	out.append(L.part("box", Vector3(0, 3.0, -2.5), Vector3(5.0, 0.6, 3.5), "stone"))
	out.append(L.part("box", Vector3(0, 2.6, -0.4), Vector3(4.0, 0.5, 0.4), "fire"))
	out.append(L.part("frustum", Vector3(0, 3.6, -3.2), Vector3(3.6, 9.0, 2.4), "stone_dark"))
	out.append(L.part("box", Vector3(0, 0.0, 3.0), Vector3(3.6, 2.0, 2.0), "iron"))
	out.append(L.part("box", Vector3(0, 2.0, 3.0), Vector3(5.2, 0.9, 2.2), "iron"))
	out.append(L.part("box", Vector3(-3.2, 0.0, 3.4), Vector3(1.6, 1.4, 1.6), "timber_dark"))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The solids of the hearth, its chimney and the anvil: [name, centre, size] in the forge's frame.
static func bodies() -> Array:
	return [["Hearth", Vector3(0, 1.4, -2.5), Vector3(7.0, 3.8, 4.5)], ["Chimney", Vector3(0, 8.1, -3.2), Vector3(3.0, 9.0, 3.0)],
		["Anvil", Vector3(0, 1.45, 3.0), Vector3(5.2, 2.9, 2.2)]]


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var f := Node3D.new()
	f.name = str(el.id).validate_node_name()
	var props := {"world_id": str(el.id), "display_name": str(el.get("display_name", "forge")), "prompt": "Reforge",
		"radius_m": float(el.get("radius", 9.0)), "priority": 45, "tier": str(el.get("tier", "titan")),
		"open_when": el.get("open_when", {}) as Dictionary}
	if str(el.get("closed_message", "")) != "":
		props["closed_message"] = str(el.closed_message)
	if str(el.get("faction", "")) != "":   # M8 gate (F16): shut while its settlement is hostile
		props["faction"] = str(el.faction)
		if str(el.get("hostile_message", "")) != "":
			props["hostile_message"] = str(el.hostile_message)
	kit.scripted(f, S_FORGE, props)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	for b: Array in bodies():
		var cs := CollisionShape3D.new()
		cs.name = str(b[0])
		cs.shape = kit.box_shape(b[2])
		cs.position = b[1]
		body.add_child(cs)
	f.add_child(body)
	var mesh := L.parts_node("Mesh", parts(el, ctx), ctx.get("mat"))
	mesh.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	f.add_child(mesh)
	return f
