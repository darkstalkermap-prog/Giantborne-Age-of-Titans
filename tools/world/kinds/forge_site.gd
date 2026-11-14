extends RefCounted
## Element kind "forge_site" (P29; plan M6-M9 §5.4, §5.12): a forge placed in the world - P12's
## forge.tscn (the Forge interactable with its hearth and anvil) with the element's world id,
## `display_name` and `requires_flags`. Style "anvil" (the Kingsgate anvil: always open) keeps the
## Forge script; style "town" (Brannock's smithy) gives it TownForge (scripts/world/town_forge.gd),
## shut while the element's `faction` is hostile. Every world forge here is of the iron tier (P31's
## `tier`, set when the script has it). Its chunk's props sub-scene holds it.

const SCRIPTED := true
const FORGE := "res://scenes/world/forge.tscn"
const S_TOWN_FORGE := "res://scripts/world/town_forge.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var f := kit.instance(FORGE) as Node3D
	if f == null:
		return null
	if str(el.get("style", "anvil")) == "town":
		f.set_script(load(S_TOWN_FORGE))
		f.set("faction", str(el.get("faction", "")))
		if str(el.get("hostile_message", "")) != "":
			f.set("hostile_message", str(el.hostile_message))
	f.name = str(el.id).validate_node_name()
	f.set("world_id", str(el.id))
	f.set("display_name", str(el.get("display_name", "forge")))
	f.set("prompt", "Reforge")
	f.set("radius_m", float(el.get("radius", 6.0)))
	f.set("priority", 45)
	f.set("requires_flags", PackedStringArray(el.get("requires_flags", [])))
	if str(el.get("closed_message", "")) != "":
		f.set("closed_message", str(el.closed_message))
	if "tier" in f:
		f.set("tier", str(el.get("tier", "iron")))
	return f
