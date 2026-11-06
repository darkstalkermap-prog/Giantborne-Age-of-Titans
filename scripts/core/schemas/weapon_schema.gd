extends RefCounted
## Schema module for "weapon" records.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"family": U.str_field(true, DataValidator.WEAPON_FAMILIES),
		"damage_multiplier": U.pos(true),
		"length_m": U.pos(true),
		"hit_radius_m": U.pos(true),
	}
	## @anchor P08
	# Weapons with fit stages (P08, plan §2.8.2, decision 3): a weapon follows the giant's growth
	# up to fit_max_stage (10 = never capped); scales_with_growth false = a fixed real size (the
	# tree). light_chain / heavy are the moveset it puts into the loadout; upgrade is what a
	# forge (P12) reforges it into.
	f.merge({
		"scales_with_growth": U.bool_field(),
		"fit_max_stage": U.int_field(1, 10),
		"light_chain": U.ref("action"),
		"heavy": U.ref("action"),
		"required_stage": U.int_field(1, 10),
		"required_permission": U.str_field(false, DataValidator.INTERACTION_PERMISSIONS),
		"tags": U.enum_array(DataValidator.TAGS),
		"visual_shape": U.str_field(false, ["club", "sword", "hammer", "tree", "bow", "staff", "none"]),
		"upgrade": {"t": "dict", "fields": {
			"to": U.ref("weapon", true),
			"cost": {"t": "array", "req": true, "items": "dict", "item_fields": {
				"item": U.ref("item", true), "count": U.int_field(1, null, true)}}}},
	})

	## @anchor P12

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26

	## @anchor P31

	## @anchor P32

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	## @anchor P08
	# The cross-record rule (an upgrade.to weapon fits at least as high as its source) needs both
	# records: PlayerEquipment.upgrade_problems(records) checks it (test_weapons runs it on the
	# shipped data); P12 can call it from the GameData post-pass at its anchor.
	var p08_upgrade: Variant = d.get("upgrade")
	if typeof(p08_upgrade) == TYPE_DICTIONARY and str(p08_upgrade.get("to", "")) == str(d.get("id", "")) \
			and str(d.get("id", "")) != "":
		out.errors.append("%s.upgrade.to: a weapon cannot upgrade into itself" % ctx)
	if U.is_number(d.get("required_stage")) and U.is_number(d.get("fit_max_stage")) \
			and bool(d.get("scales_with_growth", true)) and int(d.required_stage) > int(d.fit_max_stage):
		out.errors.append("%s: required_stage %d is above fit_max_stage %d (it would never fit)" % [
			ctx, int(d.required_stage), int(d.fit_max_stage)])

	## @anchor P12
	# The forge's one upgrade interaction (P12) always costs something. The cross-record rules
	# (the upgraded weapon fits at least as high and has no upgrade of its own) run in the
	# GameData post-pass (Progression.data_errors).
	if typeof(p08_upgrade) == TYPE_DICTIONARY and typeof(p08_upgrade.get("cost")) == TYPE_ARRAY \
			and (p08_upgrade.cost as Array).is_empty():
		out.errors.append("%s.upgrade.cost: must list at least one item" % ctx)

	pass

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26

	## @anchor P31

	## @anchor P32


static func required_ids() -> Dictionary:
	return {}
