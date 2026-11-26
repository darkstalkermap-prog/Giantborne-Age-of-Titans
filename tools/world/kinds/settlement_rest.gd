extends RefCounted
## Element kind "settlement_rest" (C4): a settlement's fire the giant rests by once its tier gives it
## (scripts/world/settlement_rest.gd) - `requires_flag`, `display_name` ("the hall's fire"), `respawn` (the
## checkpoint a rest makes his respawn), `radius`. Draws nothing: the fire is the layout's.

const SCRIPTED := true
const S_REST := "res://scripts/world/settlement_rest.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_REST, {"world_id": str(el.id), "requires_flag": str(el.get("requires_flag", "")),
		"display_name": str(el.get("display_name", "fire")), "respawn_checkpoint": str(el.get("respawn", "")),
		"radius_m": float(el.get("radius", 12.0))})
	return n
