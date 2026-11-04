extends RefCounted
## Schema module for "enemy" records.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"archetype": U.str_field(true, DataValidator.ARCHETYPES),
		"height_m": U.pos(true),
		"capsule_radius_m": U.pos(true),
		"health": U.pos(true),
		"stamina": U.pos(),
		"guard": {"t": "dict", "fields": {
			"coverage_deg": U.num(0.0, 360.0, true),
			"min_stamina": U.num(0.0, null, true),
			"turn_rate_deg_s": U.pos(true),
			"physical_reduction": U.num(0.0, 1.0, true),
			"elemental_reduction": U.num(0.0, 1.0, true),
			"impact_stamina_factor": U.num(0.0, null, true),
			"guard_break_damage_fraction": U.num(0.0, 1.0, true),
			"guard_break_stagger_s": U.num(0.0, null, true)}},
		"armor": U.num(0.0),
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(-0.5, 0.75)},
		"immunities": {"t": "array", "items": "string", "items_enum": DataValidator.DAMAGE_TYPES + DataValidator.TAGS},
		"attributes": {"t": "dict", "keys_enum": DataValidator.ATTRIBUTES, "values": U.num(0.0)},
		"poise": {"t": "dict", "req": true, "fields": U.poise_fields()},
		"stability": U.pos(),
		"walk_speed_mps": U.pos(true),
		"run_speed_mps": U.pos(true),
		"turn_rate_deg_s": U.pos(true),
		"weapon": U.ref("weapon", true),
		"weapon_pivot_m": {"t": "vec3", "req": true},
		"attack_origin_m": {"t": "vec3", "req": true},
		"arm_length_m": U.pos(true),
		"attacks": {"t": "array", "req": true, "items": "string", "items_ref": "action"},
		"attack_weights": {"t": "array", "items": "number"},
		"ai": {"t": "dict", "req": true, "fields": {
			"sight_range_m": U.pos(true),
			"sight_half_angle_deg": {"t": "number", "gt": 0.0, "max": 180.0, "req": true},
			"hearing_radius_m": U.num(0.0, null, true),
			"memory_s": U.num(0.0, null, true),
			"perception_hz": U.pos(true),
			"decision_hz": U.pos(true),
			"notice_s": U.num(0.0, null, true),
			"attack_range_m": U.pos(true),
			"engage_distance_m": U.pos(true),
			"reposition_radius_m": U.pos(true),
			"strike_pause_min_s": U.num(0.0, null, true),
			"strike_pause_max_s": U.num(0.0, null, true),
			"path_fail_s": U.pos(true),
			"patrol_wait_s": U.num(0.0, null, true),
			"max_attackers": U.int_field(1, null, true),
			"flee_morale": U.num(0.0, 100.0, true),
			"regroup_morale": U.num(0.0, 100.0, true)}},
		"morale": U.num(0.0, 100.0),
		"threat": U.num(0.0, 1.0),
		"lockable": {"t": "bool"},
		"grants_fury": {"t": "bool"},
		"crit_chance": U.num(0.0, 1.0),
		# Experience awarded for a kill (PlayerProgression, P12).
		"xp_reward": U.int_field(0),
	}
	## @anchor P04

	## @anchor P07

	## @anchor P09

	## @anchor P10a

	## @anchor P11a

	## @anchor P11b

	## @anchor P12

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if typeof(d.get("attacks")) == TYPE_ARRAY and (d.attacks as Array).is_empty():
		out.errors.append("%s: attacks must list at least one action" % ctx)
	if typeof(d.get("attack_weights")) == TYPE_ARRAY and typeof(d.get("attacks")) == TYPE_ARRAY:
		if (d.attack_weights as Array).size() != (d.attacks as Array).size():
			out.errors.append("%s: attack_weights must have one entry per attack" % ctx)
	var ai: Variant = d.get("ai")
	if typeof(ai) == TYPE_DICTIONARY and U.is_number(ai.get("strike_pause_min_s")) \
			and U.is_number(ai.get("strike_pause_max_s")):
		if float(ai.strike_pause_min_s) > float(ai.strike_pause_max_s):
			out.errors.append("%s: ai.strike_pause_min_s must be <= ai.strike_pause_max_s" % ctx)
	## @anchor P04

	## @anchor P07

	## @anchor P09

	## @anchor P10a

	## @anchor P11a

	## @anchor P11b

	## @anchor P12


static func required_ids() -> Dictionary:
	return {"enemy.soldier": "enemy"}
