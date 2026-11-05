class_name Combatant
extends RefCounted
## Stats and live combat state for one damageable entity (player, enemy, prop).
## Built from a data record; attributes above 10 add the spec section 9 bonuses.
##
## Statuses (spec section 8) never mutate the base stats: armor_total(), the outgoing / taken
## multipliers, move_mult() and fury_gain_mult() fold the active StatusSet over them. Growth and
## attribute changes go through set_attributes() / growth_bonus + recompute_derived(), which
## keep the current resource fractions.

const ATTRIBUTE_KEYS := ["strength", "endurance", "dexterity", "intellect", "willpower", "constitution"]

## Emitted by recompute_derived() (attributes or growth changed). CombatEntity pushes the new
## Dexterity recovery_scale to the controller.
signal derived_changed

var entity_id := ""
var definition_id := ""
var display_name := ""
var height_m := 1.8
var attributes: Dictionary = {}
var armor := 0.0
var resistances: Dictionary = {}
var immunities := PackedStringArray()   ## damage types and attack tags ("fire", "Grab")
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

var statuses := StatusSet.new()
var status_immunities := PackedStringArray()   ## status tags ("Fear", "Slow"), kept apart from immunities
var mass_class := "small"                      ## small < medium < large < immovable
var xp_reward := 0
var base_record: Dictionary = {}               ## the record this combatant was built from (read-only)
var growth_bonus: Dictionary = {}              ## extra maxima from growth, e.g. {"health": 150, "stamina": 10}

var _base_resources: Dictionary = {}           ## record maxima before attribute and growth bonuses
var _poise_config: Dictionary = {}


func _init() -> void:
	statuses.changed.connect(_on_statuses_changed)


static func from_record(p_entity_id: String, rec: Dictionary, height_override := -1.0) -> Combatant:
	var c := Combatant.new()
	c.entity_id = p_entity_id
	c.base_record = rec
	c.definition_id = str(rec.get("id", ""))
	c.display_name = str(rec.get("display_name", c.definition_id))
	for key: String in ATTRIBUTE_KEYS:
		c.attributes[key] = float((rec.get("attributes", {}) as Dictionary).get(key, 10.0))
	c.armor = float(rec.get("armor", 0.0))
	c.resistances = rec.get("resistances", {})
	c.immunities = PackedStringArray(rec.get("immunities", []))
	c.status_immunities = PackedStringArray(rec.get("status_immunities", []))
	c.mass_class = str(rec.get("mass_class", "small"))
	c.xp_reward = int(rec.get("xp_reward", 0))
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
	if rec.has("resources"):
		c._base_resources = (rec.resources as Dictionary).duplicate()
	else:
		# Enemies and props: flat fields; essence (casters) and regen are optional.
		c._base_resources = {"health": float(rec.get("health", 100.0)),
			"stamina": float(rec.get("stamina", 100.0)), "essence": float(rec.get("essence", 0.0)),
			"fury_max": 100.0}
	c.pools.configure(c._derived_maxima(), rec.get("regen", {}))
	c._poise_config = rec.get("poise", {"threshold": 9999.0})
	c.poise.configure(c._poise_config, c.attribute("constitution"))
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


# --------------------------------------------------------------------------- statuses

## Armor used for physical mitigation: base armor plus every active "armor_flat" (Stone Skin).
## `armor` itself is never changed by statuses.
func armor_total() -> float:
	return armor + statuses.modifier_sum("armor_flat")


func outgoing_damage_mult() -> float:
	return statuses.modifier_product("outgoing_damage_mult")


func outgoing_poise_mult() -> float:
	return statuses.modifier_product("outgoing_poise_mult")


## Multiplies both typed damage portions before blocking and rounding (barrier, bot assist).
func damage_taken_mult() -> float:
	return statuses.modifier_product("damage_taken_mult")


## Movement multiplier from slows: 1 - clamp(strongest slow_fraction, 0, 0.9).
func move_mult() -> float:
	return 1.0 - clampf(statuses.modifier_max("slow_fraction"), 0.0, 0.9)


## Multiplier on every fury gain (Titan Surge = 0); mirrored into pools.fury_gain_mult.
func fury_gain_mult() -> float:
	return statuses.modifier_product("fury_gain_mult")


func _on_statuses_changed() -> void:
	pools.fury_gain_mult = fury_gain_mult()


# --------------------------------------------------------------------------- derived values

## Replaces the given attributes (unknown keys ignored, missing keys kept), then recomputes the
## derived maxima, poise threshold and recovery scale.
func set_attributes(attrs: Dictionary) -> void:
	for key: String in ATTRIBUTE_KEYS:
		if attrs.has(key):
			attributes[key] = float(attrs[key])
	recompute_derived()


## Maxima = base resources + Endurance/Intellect bonuses + growth_bonus; the pools keep their
## current fractions (ResourcePool.rescale). The poise threshold follows Constitution (the
## accumulated value is kept). Emits derived_changed so CombatEntity can push the Dexterity
## recovery_scale to the controller.
func recompute_derived() -> void:
	pools.rescale(_derived_maxima())
	poise.reconfigure(_poise_config, attribute("constitution"), true)
	derived_changed.emit()


func set_height(p_height_m: float) -> void:
	if p_height_m > 0.0:
		height_m = p_height_m


## Endurance adds 15 health and 2 stamina per point above 10, Intellect 2 essence per point.
func _derived_maxima() -> Dictionary:
	var endurance_bonus := maxf(0.0, attribute("endurance") - 10.0)
	var intellect_bonus := maxf(0.0, attribute("intellect") - 10.0)
	var out := _base_resources.duplicate()
	out["health"] = float(out.get("health", 100.0)) + 15.0 * endurance_bonus \
		+ float(growth_bonus.get("health", 0.0))
	out["stamina"] = float(out.get("stamina", 100.0)) + 2.0 * endurance_bonus \
		+ float(growth_bonus.get("stamina", 0.0))
	out["essence"] = float(out.get("essence", 0.0)) + 2.0 * intellect_bonus \
		+ float(growth_bonus.get("essence", 0.0))
	return out
