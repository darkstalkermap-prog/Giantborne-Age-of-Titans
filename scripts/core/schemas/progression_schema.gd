extends RefCounted
## Schema module for "progression" records (progression.default: XP table, level-up points,
## the new-game character and the death-reload resource floor).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"level_cap": U.int_field(1, 20, true),
		# XP needed to go from level L to L + 1, for L = 1 .. level_cap - 1.
		"xp_to_next": {"t": "array", "req": true, "items": "int"},
		"attribute_points_per_level": U.int_field(0, null, true),
		"talent_points_per_level": U.int_field(0, null, true),
		# Shown by the HUD and docs while quest XP is accelerated (decision 7).
		"prototype_xp_label": U.str_field(),
		# Minimum resource fractions after a death reload (health 0.6, stamina 1.0, essence 0.5).
		"death_reload_floor": {"t": "dict", "fields": {
			"health": U.num(0.0, 1.0, true), "stamina": U.num(0.0, 1.0, true),
			"essence": U.num(0.0, 1.0, true)}},
		# Every ability the character can ever learn (later packages append theirs).
		"ability_library": U.ref_array("action"),
		"new_game": {"t": "dict", "req": true, "fields": {
			"level": U.int_field(1, 20, true),
			"growth_profile": U.ref("growth_profile", true),
			"weapon": U.ref("weapon", true),
			"ancestry": U.ref("ancestry", true),
			"slots": U.ref_array("action", true, true),
			"ultimate": U.ref("action", false, true),
			"known_abilities": U.ref_array("action"),
		}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var xp: Variant = d.get("xp_to_next")
	if typeof(xp) == TYPE_ARRAY:
		var arr: Array = xp
		if U.is_number(d.get("level_cap")):
			var expected := int(d.level_cap) - 1
			if arr.size() != expected:
				out.errors.append("%s: xp_to_next must have level_cap - 1 = %d entries (got %d)" % [
					ctx, expected, arr.size()])
		for i in range(1, arr.size()):
			if U.is_number(arr[i]) and U.is_number(arr[i - 1]) and float(arr[i]) < float(arr[i - 1]):
				out.errors.append("%s: xp_to_next must be non-decreasing (entry %d: %s < %s)" % [
					ctx, i, arr[i], arr[i - 1]])
	var new_game: Variant = d.get("new_game")
	if typeof(new_game) == TYPE_DICTIONARY and typeof(new_game.get("slots")) == TYPE_ARRAY:
		if (new_game.slots as Array).size() != 8:
			out.errors.append("%s: new_game.slots must have exactly 8 entries (empty string = empty slot)" % ctx)


static func required_ids() -> Dictionary:
	return {"progression.default": "progression"}
