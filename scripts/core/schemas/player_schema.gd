extends RefCounted
## Schema module for "player" records (the giant's base definition).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"ancestry": U.ref("ancestry"),
		"growth_profile": U.ref("growth_profile", true),
		"weapon": U.ref("weapon", true),
		"attributes": {"t": "dict", "req": true, "keys_enum": DataValidator.ATTRIBUTES, "values": U.num(0.0)},
		"resources": {"t": "dict", "req": true, "fields": {
			"health": U.pos(true), "stamina": U.pos(true), "essence": U.num(0.0, null, true),
			"fury_max": U.pos(true)}},
		"regen": {"t": "dict", "req": true, "fields": {
			"stamina_per_s": U.num(0.0, null, true), "stamina_delay_s": U.num(0.0, null, true),
			"essence_per_s": U.num(0.0, null, true), "essence_delay_s": U.num(0.0, null, true),
			"fury_decay_per_s": U.num(0.0, null, true), "fury_decay_delay_s": U.num(0.0, null, true)}},
		"fury_gain": {"t": "dict", "req": true, "fields": {
			"basic_attack": U.num(0.0, null, true), "parry": U.num(0.0, null, true),
			"kill": U.num(0.0, null, true)}},
		"poise": {"t": "dict", "req": true, "fields": U.poise_fields()},
		"armor": U.num(0.0),
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(-0.5, 0.75)},
		"immunities": {"t": "array", "items": "string", "items_enum": DataValidator.DAMAGE_TYPES + DataValidator.TAGS},
		"crit_chance": U.num(0.0, 1.0),
		"crit_multiplier": U.num(1.0),
		"stability": U.pos(),
		"loadout": {"t": "dict", "req": true, "fields": {
			"light_chain": U.ref("action", true),
			"heavy": U.ref("action", true),
			"dodge": U.ref("action", true),
			"block": U.ref("action", true),
			"jump": U.ref("action", true),
			"sprint": U.ref("action", true),
			"slots": {"t": "array", "req": true, "items": "string", "items_ref": "action",
				"items_ref_allow_empty": true},
			"ultimate": U.ref("action", false, true)}},
	}
	## @anchor P05
	# P05: the giant's mass class [large] (grabs and throws compare mass classes) and the status
	# tags it is immune to.
	f.merge({
		"mass_class": U.str_field(false, DataValidator.MASS_CLASSES),
		"status_immunities": U.enum_array(DataValidator.STATUS_TAGS),
	})

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var loadout: Variant = d.get("loadout")
	if typeof(loadout) == TYPE_DICTIONARY and typeof(loadout.get("slots")) == TYPE_ARRAY:
		if (loadout.slots as Array).size() != 8:
			out.errors.append("%s: loadout.slots must have exactly 8 entries (empty string = empty slot)" % ctx)
	## @anchor P05


static func required_ids() -> Dictionary:
	return {"player.giant": "player"}
