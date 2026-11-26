extends RefCounted
## Element kind "settlement_site" (C4): the place a settlement's project is built (scripts/world/settlement_site.gd:
## loads set down here, the work raised here). `id` is the project's `site` in its settlement record, `settlement`
## that record, `radius` the reach from the giant's capsule. Draws nothing itself: the hauled loads' stacks and the
## work are the layout's flagged elements round it. Its chunk's props sub-scene holds it.

const SCRIPTED := true
const S_SITE := "res://scripts/world/settlement_site.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_SITE, {"world_id": str(el.id), "settlement_id": str(el.get("settlement", "")),
		"radius_m": float(el.get("radius", 14.0))})
	return n
