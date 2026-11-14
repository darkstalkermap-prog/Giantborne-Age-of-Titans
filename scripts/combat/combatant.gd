class_name Combatant
extends RefCounted
## Stats and live combat state for one damageable entity (player, enemy, prop).
## Built from a data record; attributes above 10 add the spec section 9 bonuses.
##
## Statuses (spec section 8) never mutate the base stats: armor_total(), the outgoing / taken
## multipliers, move_mult() and fury_gain_mult() fold the active StatusSet over them. Growth and
## attribute changes go through set_attributes() / growth_bonus + recompute_derived(), which
## keep the current resource fractions.
##
## Passives (P33, plan M6-M9 §2.11, decision 22): the character's talents and ancestry are lasting
## modifiers (`passives`, STATUS_MODIFIERS keys; set_passives), never statuses (statuses expire and
## show on the HUD). modifier(key) folds the active statuses and the passives together - "_mult" keys
## multiply, the others add - and every accessor reads it: armor_total, the outgoing damage and
## poise multipliers (plus heavy_damage_mult, throw_damage_mult and magic_damage_mult for the action
## being performed, action_damage_mult), damage_taken_mult, fury_gain_mult, resistance()
## (elemental_resist_add and the ancestry's resistances), the maxima (health_add, stamina_add,
## essence_add), the poise threshold (poise_threshold_add), and the keys the giant's components and
## this class's pools and poise meter read: stamina_cost_mult, essence_cost_mult and cooldown_mult
## (PlayerProgression), heal_received_mult (the pools' heal), poise_damage_taken_mult (the poise
## meter's add), grab_reach_add (PlayerProgression: the giant's profile), fury_on_kill_add
## (fury_gain["kill"]) and move_speed_mult (PlayerMotor). Without passives or statuses every
## accessor returns exactly what it did before (products of 1.0, sums of 0.0).

const ATTRIBUTE_KEYS := ["strength", "endurance", "dexterity", "intellect", "willpower", "constitution"]
## P33: the keys whose change rescales the maxima or reconfigures the poise threshold.
const DERIVED_KEYS := ["health_add", "stamina_add", "essence_add", "poise_threshold_add"]

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
## P33: a ResourcePool whose heals follow heal_received_mult, and a PoiseMeter whose damage
## follows poise_damage_taken_mult (both 1.0 unless a passive or a status says otherwise).
var pools: ResourcePool = PassivePools.new()
var poise: PoiseMeter = PassivePoise.new()
var dead := false

var statuses := StatusSet.new()
var status_immunities := PackedStringArray()   ## status tags ("Fear", "Slow"), kept apart from immunities
var mass_class := "small"                      ## small < medium < large < immovable
var xp_reward := 0
var base_record: Dictionary = {}               ## the record this combatant was built from (read-only)
var growth_bonus: Dictionary = {}              ## extra maxima from growth, e.g. {"health": 150, "stamina": 10}

var _base_resources: Dictionary = {}           ## record maxima before attribute and growth bonuses
var _poise_config: Dictionary = {}

## P33: the lasting modifiers of the character's talents and ancestry (STATUS_MODIFIERS key ->
## value; "_mult" keys are products, the others sums). Empty for everyone but the giant.
var passives: Dictionary = {}
## P33: resistance added per damage type by the ancestry.
var passive_resistances: Dictionary = {}
## P33: the owner's CombatController (weak), so the per-action multipliers (heavy, throw, magic)
## reach the action being performed. null: no per-action multipliers.
var action_source: WeakRef = null
var _base_fury_gain: Dictionary = {}           ## fury_gain as set from outside (the record), before fury_on_kill_add
var _fury_gain_written: Dictionary = {}        ## the fury_gain this class wrote last (is_same: not replaced since)
var _derived_inputs: Dictionary = {}           ## DERIVED_KEYS -> value when the maxima were last computed


## P33: the pools heal by heal_received_mult (kept in step by the Combatant, as ResourcePool's
## fury_gain_mult is).
class PassivePools extends ResourcePool:
	var heal_mult := 1.0

	func heal(amount: float) -> void:
		super(amount * heal_mult)


## P33: poise damage taken is scaled by poise_damage_taken_mult (Juggernaut 0.85; Stonewall Stance
## 0: none at all).
class PassivePoise extends PoiseMeter:
	var taken_mult := 1.0

	func add(amount: float) -> bool:
		return super(amount * taken_mult)


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


## The record's resistance to `damage_type`; elemental types add Willpower's bonus and (P33) the
## elemental_resist_add passives and statuses; the ancestry's resistances add to their type.
func resistance(damage_type: String) -> float:
	var base := float(resistances.get(damage_type, 0.0))
	if damage_type != "physical":
		base += CombatRules.willpower_resistance_bonus(attribute("willpower"))
		base += elemental_resist_add()
	base += float(passive_resistances.get(damage_type, 0.0))
	return CombatRules.clamp_resistance(base)


## Immunity entries may name damage types ("fire") or attack tags ("Grab").
func is_immune_to(type_or_tag: String) -> bool:
	return immunities.has(type_or_tag)


# --------------------------------------------------------------------------- statuses

## Armor used for physical mitigation: base armor plus every active "armor_flat" (Stone Skin) and
## (P33) the armour of the passives (Stone Hide, Stoneblood). `armor` itself is never changed.
func armor_total() -> float:
	return armor + modifier("armor_flat")


## Outgoing damage: the statuses' and passives' outgoing_damage_mult (Titan Surge, Titan's Wrath)
## times the per-action multipliers of the action being performed (P33, action_damage_mult).
func outgoing_damage_mult() -> float:
	return modifier("outgoing_damage_mult") * action_damage_mult(acting_action())


func outgoing_poise_mult() -> float:
	return modifier("outgoing_poise_mult")


## Multiplies both typed damage portions before blocking and rounding (barrier, bot assist).
func damage_taken_mult() -> float:
	return modifier("damage_taken_mult")


## Movement multiplier from slows: 1 - clamp(strongest slow_fraction, 0, 0.9).
func move_mult() -> float:
	return 1.0 - clampf(statuses.modifier_max("slow_fraction"), 0.0, 0.9)


## Multiplier on every fury gain (Titan Surge = 0); mirrored into pools.fury_gain_mult.
func fury_gain_mult() -> float:
	return modifier("fury_gain_mult")


func _on_statuses_changed() -> void:
	_refresh_modifier_effects()


# --------------------------------------------------------------------------- passives (P33)

## The combined value of a STATUS_MODIFIERS key over the active statuses and the passives: a
## product for the "_mult" keys (1.0 when none), a sum for the others (0.0 when none).
func modifier(key: String) -> float:
	if key.ends_with("_mult"):
		return statuses.modifier_product(key) * float(passives.get(key, 1.0))
	return statuses.modifier_sum(key) + float(passives.get(key, 0.0))


## Replaces the passives ({key: value}, already combined: Talents.passives_for) and the ancestry's
## resistances, then brings everything that follows them up to date: the pools' fury gain and heal
## multipliers, the poise meter's damage multiplier, fury on kill, and - when health_add,
## stamina_add, essence_add or poise_threshold_add changed - the maxima (fractions kept) and the
## poise threshold (the accumulated poise kept).
func set_passives(mods: Dictionary, res: Dictionary = {}) -> void:
	passives = mods.duplicate()
	passive_resistances = res.duplicate()
	_refresh_modifier_effects()


func heal_received_mult() -> float:
	return modifier("heal_received_mult")


func stamina_cost_mult() -> float:
	return modifier("stamina_cost_mult")


func essence_cost_mult() -> float:
	return modifier("essence_cost_mult")


func cooldown_mult() -> float:
	return modifier("cooldown_mult")


func poise_threshold_add() -> float:
	return modifier("poise_threshold_add")


func poise_damage_taken_mult() -> float:
	return modifier("poise_damage_taken_mult")


func grab_reach_add() -> float:
	return modifier("grab_reach_add")


func fury_on_kill_add() -> float:
	return modifier("fury_on_kill_add")


## Walking and running speed multiplier of statuses and passives (Stonewall Stance 0.7, Wild Surge
## 1.15, Wildheart 1.05); PlayerMotor applies it. Slows are move_mult().
func move_speed_mult() -> float:
	return maxf(0.0, modifier("move_speed_mult"))


func elemental_resist_add() -> float:
	return modifier("elemental_resist_add")


## The per-action damage multipliers for action `a`: heavy_damage_mult for heavy attacks,
## throw_damage_mult for actions tagged Throw, magic_damage_mult for magic (category or tag). 1.0
## for null.
func action_damage_mult(a: ActionDef) -> float:
	if a == null:
		return 1.0
	var m := 1.0
	if a.kind == "heavy":
		m *= modifier("heavy_damage_mult")
	if a.has_tag("Throw"):
		m *= modifier("throw_damage_mult")
	if a.category == "magic" or a.has_tag("Magic"):
		m *= modifier("magic_damage_mult")
	return m


## The action the owner performs now (its controller's, through action_source), else null.
func acting_action() -> ActionDef:
	if action_source == null:
		return null
	var c := action_source.get_ref() as CombatController
	return c.action if c != null else null


## Brings what follows the statuses and passives up to date (status changes and set_passives).
func _refresh_modifier_effects() -> void:
	pools.fury_gain_mult = fury_gain_mult()
	if pools is PassivePools:
		(pools as PassivePools).heal_mult = maxf(0.0, heal_received_mult())
	if poise is PassivePoise:
		(poise as PassivePoise).taken_mult = maxf(0.0, poise_damage_taken_mult())
	_refresh_fury_on_kill()
	var inputs := {}
	for key: String in DERIVED_KEYS:
		inputs[key] = modifier(key)
	if inputs != _derived_inputs:
		var first := _derived_inputs.is_empty()
		_derived_inputs = inputs
		var neutral := true
		for key: String in DERIVED_KEYS:
			neutral = neutral and inputs[key] == 0.0
		if not (first and neutral):
			recompute_derived()


## fury_gain["kill"] carries fury_on_kill_add (Bloodied Fury: CombatEntity reads fury_gain when the
## owner kills). The dictionary set from outside (the record, a test) is the base the addition is
## made on - never changed itself - and fury_gain is exactly that base while nothing adds.
func _refresh_fury_on_kill() -> void:
	if not is_same(fury_gain, _fury_gain_written):
		_base_fury_gain = fury_gain
	var add := fury_on_kill_add()
	if add == 0.0:
		fury_gain = _base_fury_gain
	else:
		var fg := _base_fury_gain.duplicate()
		fg["kill"] = float(fg.get("kill", 0.0)) + add
		fury_gain = fg
	_fury_gain_written = fury_gain


# --------------------------------------------------------------------------- derived values

## Replaces the given attributes (unknown keys ignored, missing keys kept), then recomputes the
## derived maxima, poise threshold and recovery scale.
func set_attributes(attrs: Dictionary) -> void:
	for key: String in ATTRIBUTE_KEYS:
		if attrs.has(key):
			attributes[key] = float(attrs[key])
	recompute_derived()


## Maxima = base resources + Endurance/Intellect bonuses + growth_bonus (+ P33's health_add,
## stamina_add and essence_add); the pools keep their current fractions (ResourcePool.rescale). The
## poise threshold follows Constitution (+ P33's poise_threshold_add; the accumulated value is
## kept). Emits derived_changed so CombatEntity can push the Dexterity recovery_scale to the
## controller.
func recompute_derived() -> void:
	pools.rescale(_derived_maxima())
	poise.reconfigure(_poise_config_now(), attribute("constitution"), true)
	derived_changed.emit()


## The record's poise block with the passives' and statuses' poise_threshold_add (P33) on its
## threshold (the record's block itself when there is none).
func _poise_config_now() -> Dictionary:
	var add := poise_threshold_add()
	if add == 0.0:
		return _poise_config
	var cfg := _poise_config.duplicate()
	cfg["threshold"] = float(cfg.get("threshold", 100.0)) + add
	return cfg


func set_height(p_height_m: float) -> void:
	if p_height_m > 0.0:
		height_m = p_height_m


## Endurance adds 15 health and 2 stamina per point above 10, Intellect 2 essence per point; P33's
## health_add, stamina_add and essence_add (Mountain's Heart, Wildheart, Wellspring, Stormborn)
## add theirs.
func _derived_maxima() -> Dictionary:
	var endurance_bonus := maxf(0.0, attribute("endurance") - 10.0)
	var intellect_bonus := maxf(0.0, attribute("intellect") - 10.0)
	var out := _base_resources.duplicate()
	out["health"] = float(out.get("health", 100.0)) + 15.0 * endurance_bonus \
		+ float(growth_bonus.get("health", 0.0)) + modifier("health_add")
	out["stamina"] = float(out.get("stamina", 100.0)) + 2.0 * endurance_bonus \
		+ float(growth_bonus.get("stamina", 0.0)) + modifier("stamina_add")
	out["essence"] = float(out.get("essence", 0.0)) + 2.0 * intellect_bonus \
		+ float(growth_bonus.get("essence", 0.0)) + modifier("essence_add")
	return out
