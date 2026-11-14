extends RefCounted
## Element kind "forge_fire" (P35; plan M6-M9 §5.4, quest.titan_bones): the fire of the Titan Forge -
## a ForgeFire (scripts/world/forge_fire.gd: a BeaconFire that offers "Light the Titan Forge" and steps
## aside once lit) on a great hearth of stone and bone (its Hearth mesh and a WORLD body), the flames
## (Fire) shown while `flag` is set. Fields as beacon_fire's: `flag`, `requires_flags`,
## `locked_message`, `loot` (paid once when it is lit: the Titan's Bones' titan iron), `lit_message`,
## `display_name`, `fire_y`, `radius`. The forge itself is a forge_site element beside it whose
## requires_flags wait for the flag. Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_FORGE_FIRE := "res://scripts/world/forge_fire.gd"


static func hearth() -> Array:
	var out: Array = [L.part("frustum", Vector3(0, -0.6, 0), Vector3(9.0, 2.4, 7.6), "stone_dark")]
	for k in 8:
		var a := TAU * k / 8.0
		out.append(L.part("box", Vector3(cos(a) * 3.9, 1.6, sin(a) * 3.9), Vector3(1.4, 1.8, 1.4), "bone", rad_to_deg(-a)))
	out.append(L.part("box", Vector3(0, 1.7, -4.6), Vector3(3.2, 9.0, 2.2), "bone_dark"))
	out.append(L.part("box", Vector3(0, 10.4, -4.6), Vector3(4.4, 1.2, 3.0), "stone_dark"))
	out.append(L.part("cyl", Vector3(0, 1.75, 0), Vector3(6.2, 0.2, 0), "black"))
	return out


static func flames() -> Array:
	return [
		L.part("cone", Vector3(0, 0, 0), Vector3(4.6, 5.4, 0), "fire"),
		L.part("cone", Vector3(1.2, 0, 0.8), Vector3(2.8, 3.8, 0), "gold", 0.0, Vector3(6, 0, -5)),
		L.part("cone", Vector3(-1.1, 0, -0.9), Vector3(2.6, 3.4, 0), "fire", 0.0, Vector3(-5, 0, 6)),
	]


## The map draws the hearth (a scripted kind: nothing is merged).
static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return hearth()


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_FORGE_FIRE, {"world_id": str(el.id), "interact_id": str(el.id),
		"display_name": str(el.get("display_name", "forge")), "lit_flag": str(el.get("flag", "")),
		"requires_flags": PackedStringArray(el.get("requires_flags", [])),
		"locked_message": str(el.get("locked_message", "The forge is cold.")),
		"loot_table": str(el.get("loot", "")), "reveal_m": float(el.get("reveal_m", 0.0)),
		"lit_message": str(el.get("lit_message", "")), "scene_dialogue": str(el.get("scene", "")),
		"radius_m": float(el.get("radius", 9.0))})
	var body := StaticBody3D.new()
	body.name = "Hearth"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = kit.box_shape(Vector3(8.0, 2.2, 8.0))
	cs.position = Vector3(0, 0.5, 0)
	body.add_child(cs)
	var mesh := L.parts_node("Mesh", hearth(), ctx.get("mat"))
	mesh.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	body.add_child(mesh)
	n.add_child(body)
	var fire := L.parts_node("Fire", flames(), ctx.get("mat"))
	fire.position = Vector3(0, float(el.get("fire_y", 1.8)), 0)
	fire.visible = false
	fire.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	n.add_child(fire)
	return n
