extends RefCounted
## Element kind "engine" (P36; plan M6-M9 §2.10, §5.10, §5.13): a placed siege engine - P32's
## ballista or catapult (style "ballista" | "catapult": scenes/world/siege_<style>.tscn, a SiegeEngine)
## with the element's world id (a catapult's id says "catapult": the audio router plays the catapult's
## release for an engine whose id does), its `faction` (a faction's short name: at peace with the
## giant the engine is neutral and never shoots; "" = always hostile) and, for a siege line, the
## props it bombards while the giant is out of its reach (`prop_targets`, world ids), only while the
## giant stands within `bombard_within_m` of the target (the siege's clock pauses while the giant is
## away), and its `siege_group` (when the group's last engine falls the line breaks: its soldiers
## rout). An encounter's `engines` list names it with its crew. y_off (or "y") lifts it onto a bastion
## or a tower. With `appears_when` (a quest condition) it is placed as a ConditionSpawn
## (scripts/world/condition_spawn.gd) that instances the engine only once the condition holds - the
## siege line before Skarn arrives with the siege, the toll fort's tower ballista with a stage-5 giant -
## so it costs the settlements' views nothing before (plan §3.8's 40 draw calls a view). Its chunk's
## props sub-scene holds it; the index lists an engine placed outright as a prop.

const SCRIPTED := true
const SCENES := {"ballista": "res://scenes/world/siege_ballista.tscn", "catapult": "res://scenes/world/siege_catapult.tscn"}
const S_SPAWN := "res://scripts/world/condition_spawn.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func scene_for(el: Dictionary) -> String:
	return str(SCENES.get(str(el.get("style", "ballista")), SCENES.ballista))


## The engine's own properties (its SiegeEngine exports) from the element.
static func engine_props(el: Dictionary) -> Dictionary:
	var props := {"world_id": str(el.id), "faction": str(el.get("faction", ""))}
	if el.has("prop_targets"):
		props["prop_targets"] = PackedStringArray(el.prop_targets)
	if el.has("bombard_within_m"):
		props["bombard_within_m"] = float(el.bombard_within_m)
	if el.has("siege_group"):
		props["siege_group"] = str(el.siege_group)
	return props


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var props := engine_props(el)
	if typeof(el.get("appears_when")) == TYPE_DICTIONARY:
		var spawn := Node3D.new()
		spawn.name = str(el.id).validate_node_name()
		kit.scripted(spawn, S_SPAWN, {"scene": scene_for(el), "props": props, "when": el.appears_when as Dictionary,
			"child_name": str(el.id).validate_node_name()})
		return spawn
	var e := kit.instance(scene_for(el)) as Node3D
	if e == null:
		return null
	e.name = str(el.id).validate_node_name()
	for key: String in props:
		if key in e:
			e.set(key, props[key])
	return e
