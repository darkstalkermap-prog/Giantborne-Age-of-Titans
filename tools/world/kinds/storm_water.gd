extends RefCounted
## Element kind "storm_water" (D2): the Stormstair's pools as the Stormcaller's lightning sees them
## (scripts/world/storm_water.gd: StormWater) - `pools`: [[x, z, rx, rz], ...] in world metres, each an ellipse of a
## basin feature the terrain already carved and filled (world.json: its water is the chunks' to draw); each pool's
## surface is the world's water there (WorldFeatures.water_surface_at at its middle). The node stands at `pos` at
## height 0 (`y` 0 in the element), so its pools are kept in world heights. `calm_flag`: once set (the Stormcaller
## fallen) the water is only water. No parts, no solids.

const SCRIPTED := true
const S_WATER := "res://scripts/world/storm_water.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var at := WorldLayout.pos2(el)
	var field: HeightField = ctx.get("field")
	var feats: WorldFeatures = ctx.get("feats")
	var pools: Array = []
	for p: Variant in el.get("pools", []):
		var a := p as Array
		var x := float(a[0])
		var z := float(a[1])
		var surface := float(a[4]) if a.size() > 4 else NAN
		if is_nan(surface) and field != null and feats != null:
			surface = feats.water_surface_at(field, x, z)
		if is_nan(surface):
			push_error("storm_water %s: no water at %s" % [str(el.id), str(Vector2(x, z))])
			continue
		pools.append([x - at.x, z - at.y, float(a[2]), float(a[3]), snappedf(surface, 0.01)])
	kit.scripted(n, S_WATER, {"water_id": str(el.id), "pools": pools, "calm_flag": str(el.get("calm_flag", "")),
		"draw": false})
	return n
