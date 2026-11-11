extends RefCounted
## Element kind "rack" (P35; plan M6-M9 §5.7, §5.12): a weapon on a rack in the world - P08's
## weapon_rack.tscn (a WeaponRack: E takes the weapon and equips it, once per world id) with the
## element's world id and `weapon`. Style "reward" makes it a RewardRack
## (scripts/world/reward_rack.gd): it waits for every `requires_flags` flag and says `locked_message`
## until then (the Stoneknuckles kept for the giant who rings the five bells). Its chunk's props part
## holds it; the index lists it as a prop.

const SCRIPTED := true
const RACK := "res://scenes/world/weapon_rack.tscn"
const S_REWARD := "res://scripts/world/reward_rack.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var r := kit.instance(RACK) as Node3D
	if r == null:
		return null
	if str(el.get("style", "")) == "reward":
		r.set_script(load(S_REWARD))
		r.set("requires_flags", PackedStringArray(el.get("requires_flags", [])))
		r.set("locked_message", str(el.get("locked_message", "It is not yours to take yet.")))
	r.name = str(el.id).validate_node_name()
	r.set("world_id", str(el.id))
	r.set("weapon_id", str(el.get("weapon", "weapon.axe")))
	r.set("radius_m", float(el.get("radius", 6.0)))
	r.set("priority", 45)
	return r
