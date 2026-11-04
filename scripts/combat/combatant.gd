class_name Combatant
extends RefCounted
## Stats and live combat state for one damageable entity (player, enemy, prop).
## Built from a data record; attributes above 10 add the spec section 9 bonuses.

const ATTRIBUTE_KEYS := ["strength", "endurance", "dexterity", "intellect", "willpower", "constitution"]

var entity_id := ""
var definition_id := ""
var display_name := ""
var height_m := 1.8
var attributes: Dictionary = {}
var armor := 0.0
var resistances: Dictionary = {}
var immunities := PackedStringArray()
var crit_chance := 0.0
var crit_multiplier := 1.5
var stability := 1.0
var threat := 0.5
var lockable := false
var grants_fury := false
var unkillable := false
var fury_gain: Dictionary = {"basic_attack": 0.0, "parry": 0.0, "kill": 0.0}
var pools := ResourcePool.new()
var poise := PoiseMeter.new()
var dead := false


static func from_record(p_entity_id: String, rec: Dictionary, height_override := -1.0) -> Combatant:
	var c := Combatant.new()
	c.entity_id = p_entity_id
	c.definition_id = str(rec.get("id", ""))
	c.display_name = str(rec.get("display_name", c.definition_id))
	for key: String in ATTRIBUTE_KEYS:
		c.attributes[key] = float((rec.get("attributes", {}) as Dictionary).get(key, 10.0))
	c.armor = float(rec.get("armor", 0.0))
	c.resistances = rec.get("resistances", {})
	c.immunities = PackedStringArray(rec.get("immunities", []))
	c.crit_chance = float(rec.get("crit_chance", 0.0))
	c.crit_multiplier = float(rec.get("crit_multiplier", 1.5))
	c.stability = float(rec.get("stability", 1.0))
	c.threat = float(rec.get("threat", 0.5))
	c.lockable = bool(rec.get("lockable", false))
	c.grants_fury = bool(rec.get("grants_fury", false))
	c.unkillable = bool(rec.get("unkillable", false))
	c.fury_gain = rec.get("fury_gain", c.fury_gain)
	c.height_m = float(rec.get("height_m", 1.8))
	if height_override > 0.0:
		c.height_m = height_override
	var endurance_bonus := maxf(0.0, c.attribute("endurance") - 10.0)
	var intellect_bonus := maxf(0.0, c.attribute("intellect") - 10.0)
	var resources: Dictionary
	if rec.has("resources"):
		resources = (rec.resources as Dictionary).duplicate()
	else:
		resources = {"health": float(rec.get("health", 100.0)), "stamina": float(rec.get("stamina", 100.0)),
			"essence": 0.0, "fury_max": 100.0}
	resources["health"] = float(resources.get("health", 100.0)) + 15.0 * endurance_bonus
	resources["stamina"] = float(resources.get("stamina", 100.0)) + 2.0 * endurance_bonus
	resources["essence"] = float(resources.get("essence", 0.0)) + 2.0 * intellect_bonus
	c.pools.configure(resources, rec.get("regen", {}))
	c.poise.configure(rec.get("poise", {"threshold": 9999.0}), c.attribute("constitution"))
	return c


func attribute(key: String) -> float:
	return float(attributes.get(key, 10.0))


func recovery_scale() -> float:
	return CombatRules.recovery_scale(attribute("dexterity"))


func resistance(damage_type: String) -> float:
	var base := float(resistances.get(damage_type, 0.0))
	if damage_type != "physical":
		base += CombatRules.willpower_resistance_bonus(attribute("willpower"))
	return CombatRules.clamp_resistance(base)


## Immunity entries may name damage types ("fire") or attack tags ("Grab").
func is_immune_to(type_or_tag: String) -> bool:
	return immunities.has(type_or_tag)
