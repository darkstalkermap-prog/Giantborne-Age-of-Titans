extends RefCounted
## Schema module for "armour_perk" records (B1): one perk a forge's Reforge tab may set on an armour piece (its
## authored list: the armour record's "perks"). Chosen, never rolled. Its modifiers are STATUS_MODIFIERS keys and
## its resistances added shares by damage type (the passives' machinery: Combatant.set_passives).
##
##   {"schema_version": 1, "id": "armour_perk.steady", "type": "armour_perk", "display_name": "Steady",
##    "text": "Poise +12", "modifiers": {"poise_threshold_add": 12}, "resistances": {}}

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"text": U.str_field(true),
		"modifiers": {"t": "dict", "keys_enum": DataValidator.STATUS_MODIFIERS, "values": U.num(0.0)},
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(0.0, 0.3)},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var m: Variant = d.get("modifiers", {})
	var r: Variant = d.get("resistances", {})
	if (typeof(m) != TYPE_DICTIONARY or (m as Dictionary).is_empty()) and (typeof(r) != TYPE_DICTIONARY or (r as Dictionary).is_empty()):
		out.errors.append("%s: a perk needs modifiers or resistances" % ctx)


static func required_ids() -> Dictionary:
	return {}
