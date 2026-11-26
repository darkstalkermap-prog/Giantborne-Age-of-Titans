extends RefCounted
## Element kind "garrison" (C4): a settlement's garrison (scripts/world/settlement_garrison.gd: its posts loose at
## what comes for the place) - `settlement`, `posts` [{"pos": [x, y, z] in the element's frame, "member", "min_tier",
## "range_m", "interval_s", "power", "kind"}]. Draws nothing (its archers are its garrison encounter's people).

const SCRIPTED := true
const S_GARRISON := "res://scripts/world/settlement_garrison.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_GARRISON, {"world_id": str(el.id), "settlement_id": str(el.get("settlement", "")),
		"posts": (el.get("posts", []) as Array).duplicate(true)})
	return n
