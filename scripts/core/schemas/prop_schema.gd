extends RefCounted
## Schema module for "prop" records (cosmetic, breakable, structural, training targets).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"category": U.str_field(true, DataValidator.PROP_CATEGORIES),
		"height_m": U.pos(true),
		"health": U.pos(true),
		"armor": U.num(0.0),
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(-0.5, 0.75)},
		"immunities": {"t": "array", "items": "string", "items_enum": DataValidator.DAMAGE_TYPES + DataValidator.TAGS},
		"accepted_attack_categories": {"t": "array", "req": true, "items": "string",
			"items_enum": DataValidator.ATTACK_CATEGORIES},
		"min_growth_stage": U.int_field(1, 10),
		"loot": {"t": "array", "items": "dict", "item_fields": {
			"item": U.ref("item", true), "count": U.int_field(1, null, true)}},
		"debris_count": U.int_field(0, 40),
		"unkillable": {"t": "bool"},
		"reset_after_s": U.num(0.0),
		"lockable": {"t": "bool"},
		"grants_fury": {"t": "bool"},
		"threat": U.num(0.0, 1.0),
		"stability": U.pos(),
	}
	## @anchor P08

	## @anchor P12

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	## @anchor P08

	## @anchor P12

	pass


static func required_ids() -> Dictionary:
	return {"prop.fence_wood": "prop", "prop.practice_dummy": "prop"}
