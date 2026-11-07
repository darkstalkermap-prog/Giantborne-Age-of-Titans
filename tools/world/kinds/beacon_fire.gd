extends RefCounted
## Element kind "beacon_fire" (P29; plan M6-M9 §5.4, §5.7): the interaction that relights a beacon
## tower (a static `beacon` element of P25 at the same place) - a BeaconFire
## (scripts/world/beacon_fire.gd) at the tower's foot with its Fire (the flames on the tower's top,
## `fire_y` m up, shown while `flag` is set). Fields: `flag` (the lit flag), `requires_flags` (the
## hill cleared), `locked_message`, `loot` (its cache's loot table), `reveal_m`, `lit_message`,
## `scene` (a dialogue played after lighting), `display_name`. Its chunk's props sub-scene holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_BEACON_FIRE := "res://scripts/world/beacon_fire.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func flames() -> Array:
	return [
		L.part("cone", Vector3(0, 0, 0), Vector3(3.2, 4.2, 0), "fire"),
		L.part("cone", Vector3(0.9, 0, 0.5), Vector3(2.0, 3.0, 0), "gold", 0.0, Vector3(6, 0, -5)),
		L.part("cone", Vector3(-0.8, 0, -0.6), Vector3(1.8, 2.6, 0), "fire", 0.0, Vector3(-5, 0, 6)),
	]


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_BEACON_FIRE, {"world_id": str(el.id), "interact_id": str(el.id),
		"display_name": str(el.get("display_name", "beacon")), "lit_flag": str(el.get("flag", "")),
		"requires_flags": PackedStringArray(el.get("requires_flags", [])),
		"locked_message": str(el.get("locked_message", "The beacon's hill is not yet yours.")),
		"loot_table": str(el.get("loot", "")), "reveal_m": float(el.get("reveal_m", 0.0)),
		"lit_message": str(el.get("lit_message", "")), "scene_dialogue": str(el.get("scene", "")),
		"radius_m": float(el.get("radius", 9.0))})
	var fire := L.parts_node("Fire", flames(), ctx.get("mat"))
	fire.position = Vector3(0, float(el.get("fire_y", 30.0)), 0)
	fire.visible = false
	n.add_child(fire)
	return n
