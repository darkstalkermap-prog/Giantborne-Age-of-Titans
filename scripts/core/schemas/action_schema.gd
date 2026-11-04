extends RefCounted
## Schema module for "action" records (attacks, abilities, dodge, block, jump, sprint).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"kind": U.str_field(true, DataValidator.ACTION_KINDS),
		"hotbar_label": U.str_field(),
		"power": U.num(0.0),
		"damage_type": U.str_field(false, DataValidator.DAMAGE_TYPES),
		"damage_split": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(0.0, 1.0)},
		"ability_multiplier": U.num(0.0),
		"stamina_cost": U.num(0.0),
		"essence_cost": U.num(0.0),
		"fury_cost": U.num(0.0),
		"cooldown_s": U.num(0.0),
		"windup_s": U.num(0.0),
		"active_s": U.num(0.0),
		"recovery_s": U.num(0.0),
		"poise_damage": U.num(0.0),
		"max_hits_per_target": U.int_field(1),
		"tags": {"t": "array", "items": "string", "items_enum": DataValidator.TAGS},
		"category": U.str_field(false, DataValidator.ATTACK_CATEGORIES),
		"uses_weapon": {"t": "bool"},
		"crit_eligible": {"t": "bool"},
		"size_policy": U.str_field(false, DataValidator.SIZE_POLICIES),
		"flat_penetration": U.num(0.0),
		"chain_next": U.ref("action", false, true),
		"chain_window_s": U.num(0.0),
		"hit_shape": U.str_field(false, DataValidator.HIT_SHAPES),
		"radius_m": U.pos(),
		"height_m": U.pos(),
		"arc": {"t": "dict", "fields": {
			"windup_yaw_deg": U.num(-180.0, 180.0, true),
			"windup_pitch_deg": U.num(-89.0, 89.0, true),
			"yaw_start_deg": U.num(-180.0, 180.0, true),
			"yaw_end_deg": U.num(-180.0, 180.0, true),
			"pitch_start_deg": U.num(-89.0, 89.0, true),
			"pitch_end_deg": U.num(-89.0, 89.0, true),
		}},
		"cancels": {"t": "array", "items": "dict", "item_fields": {
			"into": {"t": "array", "req": true, "items": "string", "items_enum": DataValidator.CANCEL_INTO},
			"phase": U.str_field(true, DataValidator.PHASES),
			"after_s": U.num(0.0),
		}},
		"movement": {"t": "dict", "fields": {
			"windup_speed_mult": U.num(0.0),
			"active_speed_mult": U.num(0.0),
			"recovery_speed_mult": U.num(0.0),
		}},
		"knockback_impulse": U.num(0.0),
		"knockback_max_speed": U.num(0.0),
		"tracking_fraction": U.num(0.0, 1.0),
		"soft_target_max_deg": U.num(0.0, 45.0),
		"unlock_stage": U.int_field(1, 10),
		# Character level needed to use the action (CombatController.level; 99 = gating off).
		"unlock_level": U.int_field(1, 20),
		"interrupt_policy": U.str_field(false, DataValidator.INTERRUPT_POLICIES),
		"duration_s": U.pos(),
		"move_s": U.pos(),
		"iframe_start_s": U.num(0.0),
		"iframe_end_s": U.num(0.0),
		"distance_m": U.num(0.0),
		"parry_window_s": U.pos(),
		"parry_extra_stamina": U.num(0.0),
		"parry_poise_damage": U.num(0.0),
		"coverage_deg": U.num(0.0, 360.0),
		"physical_reduction": U.num(0.0, 1.0),
		"elemental_reduction": U.num(0.0, 1.0),
		"impact_stamina_factor": U.num(0.0),
		"guard_break_damage_fraction": U.num(0.0, 1.0),
		"guard_break_stagger_s": U.num(0.0),
		"move_speed_mult": U.num(0.0),
		"velocity_mps": U.num(0.0),
		"drain_per_s": U.num(0.0),
		"speed_mult": U.pos(),
		"resume_threshold": U.num(0.0),
	}
	## @anchor P03

	## @anchor P04

	## @anchor P07

	## @anchor P09

	## @anchor P11a

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var kind: String = str(d.get("kind", ""))
	U.check_tick_multiple(d, ["windup_s", "active_s", "recovery_s", "duration_s", "move_s",
		"iframe_start_s", "iframe_end_s", "parry_window_s", "chain_window_s"], ctx, out)
	if DataValidator.ATTACK_KINDS.has(kind):
		U.require(d, ["power", "damage_type", "ability_multiplier", "stamina_cost", "cooldown_s",
			"windup_s", "active_s", "recovery_s", "poise_damage", "max_hits_per_target", "tags",
			"hit_shape"], ctx, out, "attack kind '%s'" % kind)
		if U.is_number(d.get("active_s")) and float(d.active_s) <= 0.0:
			out.errors.append("%s: invalid timing: active_s must be > 0 for attacks" % ctx)
		var shape: String = str(d.get("hit_shape", ""))
		if shape == "weapon_arc" and not d.has("arc"):
			out.errors.append("%s: hit_shape 'weapon_arc' requires an 'arc'" % ctx)
		if shape == "cylinder_pulse":
			U.require(d, ["radius_m", "height_m"], ctx, out, "hit_shape 'cylinder_pulse'")
		if kind == "heavy" and typeof(d.get("cancels")) == TYPE_ARRAY:
			for rule: Variant in d.cancels:
				if typeof(rule) == TYPE_DICTIONARY and rule.get("phase") == "active":
					out.errors.append("%s: heavy attacks cannot be cancelled during their active strike" % ctx)
		if d.has("damage_split") and typeof(d.damage_split) == TYPE_DICTIONARY:
			var total := 0.0
			for k: Variant in d.damage_split:
				if U.is_number(d.damage_split[k]):
					total += float(d.damage_split[k])
			if absf(total - 1.0) > 0.001:
				out.errors.append("%s: damage_split portions must sum to 1.0 (got %s)" % [ctx, total])
	# Spec section 7: fury is gained by BasicAttack hits, so a light/heavy without the tag never
	# builds fury. Allowed (a deliberate design choice), but almost always a data mistake.
	if (kind == "light" or kind == "heavy") and typeof(d.get("tags")) == TYPE_ARRAY \
			and not (d.tags as Array).has("BasicAttack"):
		out.warnings.append("%s: %s action without the 'BasicAttack' tag never builds fury (spec 7)" % [ctx, kind])
	match kind:
		"dodge":
			U.require(d, ["stamina_cost", "duration_s", "move_s", "iframe_start_s", "iframe_end_s",
				"distance_m"], ctx, out, "dodge")
			if U.is_number(d.get("iframe_start_s")) and U.is_number(d.get("iframe_end_s")):
				if float(d.iframe_start_s) >= float(d.iframe_end_s):
					out.errors.append("%s: invalid timing: iframe_start_s must be < iframe_end_s" % ctx)
				if U.is_number(d.get("duration_s")) and float(d.iframe_end_s) > float(d.duration_s):
					out.errors.append("%s: invalid timing: iframe_end_s exceeds duration_s" % ctx)
			if U.is_number(d.get("move_s")) and U.is_number(d.get("duration_s")) \
					and float(d.move_s) > float(d.duration_s):
				out.errors.append("%s: invalid timing: move_s exceeds duration_s" % ctx)
		"block":
			U.require(d, ["stamina_cost", "parry_window_s", "parry_extra_stamina", "parry_poise_damage",
				"coverage_deg", "physical_reduction", "elemental_reduction", "impact_stamina_factor",
				"guard_break_damage_fraction", "guard_break_stagger_s", "move_speed_mult"], ctx, out, "block")
		"jump":
			U.require(d, ["velocity_mps"], ctx, out, "jump")
		"sprint":
			U.require(d, ["drain_per_s", "speed_mult", "resume_threshold"], ctx, out, "sprint")
	## @anchor P03

	## @anchor P04

	## @anchor P07

	## @anchor P09

	## @anchor P11a


static func required_ids() -> Dictionary:
	return {"action.block": "action"}
