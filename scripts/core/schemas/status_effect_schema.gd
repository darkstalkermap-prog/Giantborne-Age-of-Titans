extends RefCounted
## Schema module for "status_effect" records (data/statuses/*.json; StatusDef is the typed view).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Example (plan section 2.8.3):
##   {"schema_version":1,"id":"status.slow","type":"status_effect","display_name":"Slowed",
##    "hud_label":"SLOW","stacking":"strongest_wins","duration_s":3.0,"tick_s":0,
##    "magnitude_key":"slow_fraction","default_magnitude":0.3,"modifiers":{"slow_fraction":0.3},
##    "tags":["Debuff","Slow"],"hidden":false}

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"hud_label": U.str_field(),
		"stacking": U.str_field(true, DataValidator.STATUS_STACKING),
		"duration_s": U.pos(true),
		# Period of the periodic effect (heal_per_tick); 0 = no periodic effect.
		"tick_s": U.num(0.0),
		# "" or one modifiers key whose value is replaced by the application's magnitude.
		"magnitude_key": U.str_field(),
		"default_magnitude": U.num(),
		"modifiers": {"t": "dict", "keys_enum": DataValidator.STATUS_MODIFIERS, "values": U.num(0.0)},
		"tags": U.enum_array(DataValidator.STATUS_TAGS),
		# Hidden statuses (bot assist, debug invulnerability) never show in the HUD status row.
		"hidden": U.bool_field(),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	U.check_tick_multiple(d, ["duration_s", "tick_s"], ctx, out)
	var modifiers: Dictionary = d.get("modifiers", {}) if typeof(d.get("modifiers")) == TYPE_DICTIONARY else {}
	var key: Variant = d.get("magnitude_key", "")
	if typeof(key) == TYPE_STRING and key != "":
		if not DataValidator.STATUS_MODIFIERS.has(key):
			out.errors.append("%s.magnitude_key: unknown value '%s' (allowed: %s)" % [ctx, key, DataValidator.STATUS_MODIFIERS])
		elif not modifiers.has(key):
			out.errors.append("%s: magnitude_key '%s' must also be listed in modifiers" % [ctx, key])
	if modifiers.has("heal_per_tick"):
		var tick_s: Variant = d.get("tick_s", 0.0)
		if not (U.is_number(tick_s) and float(tick_s) > 0.0):
			out.errors.append("%s: modifier 'heal_per_tick' needs tick_s > 0" % ctx)


static func required_ids() -> Dictionary:
	return {}
