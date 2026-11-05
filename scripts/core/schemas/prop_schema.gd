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
	# World props (P08, plan §2.8.2): debris layout, gating (required tags, interaction
	# permission, protected) and its player-facing message, rewards and world flags, force-open,
	# the authored damage stages of structural props and the reach of cosmetic props.
	f.merge({
		"debris_length_m": U.pos(),
		"debris_layout": U.str_field(false, ["line", "pile"]),
		"required_tags": U.enum_array(DataValidator.TAGS),
		"locked_message": U.str_field(),
		"protected": U.bool_field(),
		"xp_reward": U.int_field(0),
		"uproot_weapon": U.ref("weapon"),
		"requires_permission": U.str_field(false, DataValidator.INTERACTION_PERMISSIONS),
		# flag id -> bool / number / string (keys and values are checked in semantic()).
		"on_destroyed_flags": {"t": "dict"},
		"open_when_flag": U.str_field(),
		"damage_stages": {"t": "array", "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"at_or_below_frac": U.num(0.0, 1.0, true),
			"visual": U.str_field(true),
			"removes_collision": U.bool_field(),
			"enables_nav_links": U.bool_field()}},
		"react_radius_m": U.pos(),
	})

	## @anchor P12
	# A loot table rolled once per world id when the prop breaks (P12), beside the inline `loot`;
	# a placed prop's own loot_table (BreakableProp.loot_table) overrides it.
	f.merge({"loot_table": U.ref("loot_table", false, true)})

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	## @anchor P08
	var p08_category := str(d.get("category", ""))
	var p08_flags: Variant = d.get("on_destroyed_flags")
	if typeof(p08_flags) == TYPE_DICTIONARY:
		for p08_flag: Variant in p08_flags:
			if U.check_flag_id(p08_flag, ctx + ".on_destroyed_flags", out):
				var p08_value: Variant = p08_flags[p08_flag]
				if typeof(p08_value) != TYPE_BOOL and typeof(p08_value) != TYPE_STRING and not U.is_number(p08_value):
					out.errors.append("%s.on_destroyed_flags.%s: expected true/false, a number or a string" % [ctx, p08_flag])
	if d.has("open_when_flag"):
		U.check_flag_id(d.open_when_flag, ctx + ".open_when_flag", out)
	if d.has("react_radius_m") and p08_category != "cosmetic":
		out.errors.append("%s: react_radius_m is only for cosmetic props" % ctx)
	if p08_category == "structural":
		U.require(d, ["damage_stages"], ctx, out, "category 'structural'")
	elif d.has("damage_stages"):
		out.errors.append("%s: damage_stages are only for structural props" % ctx)
	var p08_stages: Variant = d.get("damage_stages")
	if p08_category == "structural" and typeof(p08_stages) == TYPE_ARRAY:
		var p08_list: Array = p08_stages
		if p08_list.size() < 2:
			out.errors.append("%s.damage_stages: needs at least two stages (intact at 1.0, the last at 0.0)" % ctx)
		var p08_prev := INF
		var p08_ids := {}
		for p08_i in p08_list.size():
			var p08_s: Variant = p08_list[p08_i]
			if typeof(p08_s) != TYPE_DICTIONARY or not U.is_number(p08_s.get("at_or_below_frac")):
				continue
			var p08_frac := float(p08_s.at_or_below_frac)
			if p08_frac >= p08_prev:
				out.errors.append("%s.damage_stages[%d]: at_or_below_frac must be lower than the stage before it (sorted by descending fraction)" % [ctx, p08_i])
			p08_prev = p08_frac
			var p08_id := str(p08_s.get("id", ""))
			if p08_ids.has(p08_id):
				out.errors.append("%s.damage_stages[%d]: duplicate stage id '%s'" % [ctx, p08_i, p08_id])
			p08_ids[p08_id] = true
		if p08_list.size() >= 2 and typeof(p08_list[0]) == TYPE_DICTIONARY and typeof(p08_list[-1]) == TYPE_DICTIONARY:
			if not is_equal_approx(float(p08_list[0].get("at_or_below_frac", -1.0)), 1.0):
				out.errors.append("%s.damage_stages[0]: the first stage must be at 1.0 (intact)" % ctx)
			var p08_last: Dictionary = p08_list[-1]
			if not is_zero_approx(float(p08_last.get("at_or_below_frac", -1.0))):
				out.errors.append("%s.damage_stages[%d]: the last stage must be at 0.0 (the destruction)" % [ctx, p08_list.size() - 1])
			if not bool(p08_last.get("removes_collision", false)):
				out.errors.append("%s.damage_stages[%d]: the last stage must remove the collision" % [ctx, p08_list.size() - 1])

	## @anchor P12
	if str(d.get("loot_table", "")) != "" and p08_category == "cosmetic":
		out.errors.append("%s: loot_table is not for cosmetic props (they never break)" % ctx)

	pass


static func required_ids() -> Dictionary:
	return {"prop.fence_wood": "prop", "prop.practice_dummy": "prop"}
