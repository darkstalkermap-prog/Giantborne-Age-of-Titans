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
		# P33 (plan M6-M9 §5.12): the character level at which talent tiers 1-5 open (6, 8, 9, 10, 12);
		# Talents.data_errors checks them against the talents and the level cap.
		"talent_tier_levels": {"t": "array", "items": "int"},
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
		# P20 (plan M6-M9 §2.6): the character, inventory and flags of a campaign started in the
		# world (--mode=world, the title's "Skip to the Old Kingdom", tests, the world bot): the
		# Valley's worst guaranteed outcome (force). CharacterState.world_start builds on new_game.
		"world_start": {"t": "dict", "fields": {
			"level": U.int_field(1, 20, true),
			"xp": U.int_field(0, null, true),
			"unspent_attribute_points": U.int_field(0),
			"talent_points": U.int_field(0),
			"attributes": {"t": "dict", "keys_enum": DataValidator.ATTRIBUTES, "values": U.num(0.0)},
			"growth_profile": U.ref("growth_profile", true),
			"weapon": U.ref("weapon", true),
			"weapons_owned": U.ref_array("weapon"),
			"ancestry": U.ref("ancestry"),
			"slots": U.ref_array("action", true, true),
			"ultimate": U.ref("action", false, true),
			"known_abilities": U.ref_array("action"),
			"inventory": {"t": "array", "items": "dict", "item_fields": {
				"item": U.ref("item", true), "count": U.int_field(1, 999, true)}},
			"flags": {"t": "dict"},
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
	var ws: Variant = d.get("world_start")
	if typeof(ws) == TYPE_DICTIONARY:
		if typeof(ws.get("slots")) == TYPE_ARRAY and (ws.slots as Array).size() != 8:
			out.errors.append("%s: world_start.slots must have exactly 8 entries (empty string = empty slot)" % ctx)
		var flags: Variant = ws.get("flags")
		if typeof(flags) == TYPE_DICTIONARY:
			for k: Variant in flags:
				U.check_flag_id(k, "%s.world_start.flags.%s" % [ctx, k], out)
				var t := typeof(flags[k])
				if t != TYPE_BOOL and t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_STRING:
					out.errors.append("%s.world_start.flags.%s: a flag value must be true/false, a number or a string" % [ctx, k])


static func required_ids() -> Dictionary:
	return {"progression.default": "progression"}
