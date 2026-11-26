extends RefCounted
## Element kind "haul_source" (C4): where a settlement's loads lie (scripts/world/haul_source.gd: E takes one up) -
## `load` (the settlement records' load id), `load_name` (its words), `radius`, `requires_stage` (default 6). Draws
## nothing: the place's own stone or timber is the layout's (the toppled pier's drums, the Windfall's pines).

const SCRIPTED := true
const S_SOURCE := "res://scripts/world/haul_source.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_SOURCE, {"world_id": str(el.id), "load_id": str(el.get("load", "")),
		"load_name": str(el.get("load_name", el.get("load", ""))), "radius_m": float(el.get("radius", 16.0)),
		"requires_stage": int(el.get("requires_stage", 6))})
	return n
