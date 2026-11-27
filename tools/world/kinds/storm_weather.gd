extends RefCounted
## Element kind "storm_weather" (D2): the storm over the Drowned Steps as the giant sees it near
## (scripts/world/storm_weather.gd: StormWeather) - the light going dark, the fog, the rain, the lightning walking in it,
## strongest within `radius` m of `pos` and gone by `radius` + `fade` m; `active_flag` (it came with act two) and
## `calm_flag` (it clears once the Stormcaller has fallen). No parts, no solids: its look is its own.

const SCRIPTED := true
const S_WEATHER := "res://scripts/world/storm_weather.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_WEATHER, {"radius_m": float(el.get("radius", 260.0)), "fade_m": float(el.get("fade", 220.0)),
		"active_flag": str(el.get("active_flag", "")), "calm_flag": str(el.get("calm_flag", ""))})
	return n
