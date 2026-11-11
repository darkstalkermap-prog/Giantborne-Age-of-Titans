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

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26
	# Size gates (P26, plan M6-M9 §2.9): the stage whose giant tramples the prop by walking into it
	# (0 = never; fences and palisades 4), and props no hit breaks (quest-critical: the Kings' Door,
	# Brannock Bridge, the beacons - a placement can also set BreakableProp.indestructible).
	f.merge({
		"trample_stage": U.int_field(0, 10),
		"indestructible": U.bool_field(),
	})

	## @anchor P30
	# P30 (plan M6-M9 §2.10, decision 20): what the prop is, for the target providers of enemy records
	# (targets.prop_tags: raiders attack props tagged "house") and for FactionState's offences (P22:
	# damage to a faction's "house" or "engine"): plain lowercase words - house, wall, engine, fence.
	f["prop_tags"] = {"t": "array", "items": "string"}

	## @anchor P32
	# P32 (plan M6-M9 §2.10, §5.11): a siege engine (SiegeEngine): its `engine` block - the projectile
	# `action` it shoots, `crew_radius_m` (a crew member farther than this from it does not serve it),
	# `min_crew` (how many must serve it for it to shoot), `reload_s` (crewed reloading between shots),
	# `range_m` [min, max] (flat, to the giant), `turn_deg_s`, `morale_event_radius_m` (its fall is the
	# siege_destroyed morale event of every soldier this close), `grab_stage` (the giant's stage that may
	# seize it: siege disruption), `muzzle_m` (the launch point in its own frame) and `throw_action` (what
	# a giant hurls it with). An engine's `poise` (its stagger: a staggered engine stops shooting and may
	# be seized), `mass_class` and `grab_attach` are a grab's rules, as an enemy's are.
	f.merge({
		"engine": {"t": "dict", "fields": {
			"action": U.ref("action", true),
			"crew_radius_m": U.pos(true),
			"min_crew": U.int_field(0, 16),
			"reload_s": U.pos(true),
			"range_m": {"t": "array", "req": true, "items": "number"},
			"turn_deg_s": U.pos(),
			"morale_event_radius_m": U.num(0.0),
			"grab_stage": U.int_field(1, 10),
			"muzzle_m": U.vec3(),
			"throw_action": U.ref("action")}},
		"poise": {"t": "dict", "fields": U.poise_fields()},
		"mass_class": U.str_field(false, DataValidator.MASS_CLASSES),
		"grab_attach": U.str_field(false, DataValidator.GRAB_ATTACH),
	})

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

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26
	if int(d.get("trample_stage", 0)) > 0 and not p08_category in ["breakable", "structural"]:
		out.errors.append("%s: trample_stage is for breakable and structural props" % ctx)
	if int(d.get("trample_stage", 0)) > 0 and bool(d.get("indestructible", false)):
		out.errors.append("%s: an indestructible prop cannot be trampled" % ctx)
	if int(d.get("trample_stage", 0)) > 0 and typeof(d.get("accepted_attack_categories")) == TYPE_ARRAY \
			and not (d.accepted_attack_categories as Array).has("melee"):
		out.errors.append("%s: a trampled prop must accept the melee category (the trample hit)" % ctx)
	if str(d.get("requires_permission", "")) == "heave" and typeof(d.get("accepted_attack_categories")) == TYPE_ARRAY \
			and not (d.accepted_attack_categories as Array).has("melee"):
		out.errors.append("%s: a heaved prop must accept the melee category (the heave hit)" % ctx)

	## @anchor P30
	var p30_tags: Variant = d.get("prop_tags")
	if typeof(p30_tags) == TYPE_ARRAY:
		for p30_tag: Variant in p30_tags:
			if typeof(p30_tag) != TYPE_STRING or RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(p30_tag) == null:
				out.errors.append("%s.prop_tags: '%s' must be a plain lowercase word like 'house'" % [ctx, p30_tag])

	## @anchor P32
	# P32: an engine breaks (breakable or structural), carries the "engine" prop tag (FactionState's
	# offences, target providers), and its range is [min, max] with 0 <= min < max.
	var p32_engine: Variant = d.get("engine")
	if typeof(p32_engine) == TYPE_DICTIONARY:
		if not p08_category in ["breakable", "structural"]:
			out.errors.append("%s: a siege engine (engine block) is a breakable or structural prop" % ctx)
		var p32_tags: Variant = d.get("prop_tags", [])
		if typeof(p32_tags) != TYPE_ARRAY or not (p32_tags as Array).has("engine"):
			out.errors.append("%s: a siege engine carries the prop tag 'engine'" % ctx)
		var p32_range: Variant = p32_engine.get("range_m")
		if typeof(p32_range) == TYPE_ARRAY:
			var p32_r: Array = p32_range
			if p32_r.size() != 2 or not U.is_number(p32_r[0]) or not U.is_number(p32_r[1]) \
					or float(p32_r[0]) < 0.0 or float(p32_r[0]) >= float(p32_r[1]):
				out.errors.append("%s.engine.range_m: expected [min, max] with 0 <= min < max" % ctx)


static func required_ids() -> Dictionary:
	return {"prop.fence_wood": "prop", "prop.practice_dummy": "prop"}
