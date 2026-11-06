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
	f.merge({
		# Sector pulse: a cylinder pulse kept to |yaw delta| <= sector_deg / 2 of the facing.
		"sector_deg": {"t": "number", "gt": 0.0, "max": 360.0},
		# Pulse radius: "fixed" (radius_m / radius_by_stage_m) or the profile's melee_reach_m.
		"radius_from": U.str_field(false, ["fixed", "melee_reach"]),
		# Pulse radius per growth stage (index = stage - 1; the last entry beyond the list).
		"radius_by_stage_m": {"t": "array", "items": "number"},
		# Statuses the actor gives itself when the action enters ACTIVE.
		"self_statuses": {"t": "array", "items": "dict", "item_fields": {
			"status": U.ref("status_effect", true),
			"magnitude": U.num(),
			"duration_s": U.pos(),
		}},
		# Statuses a HIT applies (on BLOCKED only the entries with on_blocked).
		"on_hit_statuses": {"t": "array", "items": "dict", "item_fields": {
			"status": U.ref("status_effect", true),
			"magnitude": U.num(),
			"duration_s": U.pos(),
			"on_blocked": U.bool_field(),
		}},
		# Morale the defender loses on HIT or BLOCKED (actor.on_morale_delta).
		"morale_damage": U.num(0.0),
		# Required for hit_shape "projectile". launch_offset_m is stage-1 local (scaled by k).
		"projectile": {"t": "dict", "fields": {
			"speed_mps": U.pos(true),
			"radius_m": U.pos(true),
			"range_m": U.pos(true),
			"gravity_mps2": U.num(0.0),
			"aim": U.str_field(false, DataValidator.AIM_MODES),
			"arc_to_target": U.bool_field(),
			"launch_offset_m": U.vec3(),
			"visual": U.str_field(false, DataValidator.PROJECTILE_VISUALS),
			"impact_radius_m": U.num(0.0),
			"impact_height_m": U.pos(),
			"pierce": U.bool_field(),
		}},
	})

	## @anchor P04
	# Scripted actor motion during one phase (wolf lunge, boss charge, grab lunge), the
	# telegraph EnemyActor announces on WINDUP, and the range band brains pick attacks by
	# (measured from the target's capsule surface).
	f.merge({
		"motion": {"t": "dict", "fields": {
			"phase": U.str_field(true, DataValidator.PHASES),
			"speed_mps": U.pos(true),
			"max_distance_m": U.pos(),
			"stop_on_wall": U.bool_field(),
			"on_wall_action": U.ref("action", false, true),
			"steer_deg_s": U.num(0.0),
			"approach_stop_m": U.num(0.0)}},
		"telegraph": {"t": "dict", "fields": {
			"shape": U.str_field(true, DataValidator.TELEGRAPH_SHAPES),
			"radius_m": U.pos(),
			"length_m": U.pos(),
			"width_m": U.pos(),
			"arc_deg": {"t": "number", "gt": 0.0, "max": 360.0}}},
		"ai_min_range_m": U.num(0.0),
		"ai_max_range_m": U.pos(),
	})
	# M2 gate: the pitch at the middle of a weapon arc (AttackGeometry.arc_point: the quadratic
	# through start, middle and end), so the stage-1 light chain dips low enough for a wolf at
	# the giant's feet while its far ends still reach a soldier.
	(f.arc.fields as Dictionary)["pitch_mid_deg"] = U.num(-89.0, 89.0)

	## @anchor P07
	# Grab actions (hit_shape "grab", run in EXECUTING; PlayerGrab): "hold" lifts the target,
	# "crush" also squeezes it with the action's hit, then lets go when release_after is set.
	# max_mass caps what this action works on below the stage's grab_capacity (Crushing Grip:
	# small, so a stage-3 giant can lift an ogre but not crush it).
	f.merge({
		"grab": {"t": "dict", "fields": {
			"mode": U.str_field(true, ["hold", "crush"]),
			"release_after": U.bool_field(),
			"max_mass": U.str_field(false, DataValidator.MASS_CLASSES)}},
	})

	## @anchor P09
	# A cast on an ally (the mage's barrier, plan §3.9): it has no hit (hit_shape "none"); when it
	# enters ACTIVE its on_hit_statuses land on the ally the caster's brain picked, or on the
	# caster itself (EnemyActor.apply_ally_cast).
	f.merge({"targets_ally": U.bool_field()})

	## @anchor P11a

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26
	# P26 (plan M6-M9 §2.9): a projectile's range per growth stage (index = stage - 1; the last entry
	# beyond the list), in place of projectile.range_m: Boulder Hurl reaches 25 m at stages 1-3 and
	# 32 / 38 / 44 m at stages 4-6 (PlayerAttack's range check and launch).
	f.merge({"range_by_stage_m": {"t": "array", "items": "number"}})

	## @anchor P31

	## @anchor P32

	## @anchor P34

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
	var p03_shape: String = str(d.get("hit_shape", ""))
	if p03_shape == "sector_pulse":
		U.require(d, ["sector_deg"], ctx, out, "hit_shape 'sector_pulse'")
		if str(d.get("radius_from", "fixed")) == "fixed" and not d.has("radius_m") \
				and not d.has("radius_by_stage_m"):
			out.errors.append("%s: hit_shape 'sector_pulse' needs 'radius_m', 'radius_by_stage_m' or radius_from 'melee_reach'" % ctx)
	if p03_shape == "projectile":
		U.require(d, ["projectile"], ctx, out, "hit_shape 'projectile'")
	if typeof(d.get("radius_by_stage_m")) == TYPE_ARRAY:
		var p03_radii: Array = d.radius_by_stage_m
		if p03_radii.is_empty():
			out.errors.append("%s.radius_by_stage_m: must list at least one radius" % ctx)
		for p03_i in p03_radii.size():
			if U.is_number(p03_radii[p03_i]) and float(p03_radii[p03_i]) <= 0.0:
				out.errors.append("%s.radius_by_stage_m[%d]: must be > 0 (got %s)" % [ctx, p03_i, p03_radii[p03_i]])

	## @anchor P04
	if str(d.get("hit_shape", "")) == "body_sweep" and not d.has("motion"):
		out.errors.append("%s: hit_shape 'body_sweep' requires a 'motion'" % ctx)
	var telegraph: Variant = d.get("telegraph")
	if typeof(telegraph) == TYPE_DICTIONARY:
		match str(telegraph.get("shape", "")):
			"line":
				U.require(telegraph, ["length_m"], ctx + ".telegraph", out, "a line telegraph")
			"circle":
				U.require(telegraph, ["radius_m"], ctx + ".telegraph", out, "a circle telegraph")
			"cone":
				U.require(telegraph, ["radius_m", "arc_deg"], ctx + ".telegraph", out, "a cone telegraph")
	if U.is_number(d.get("ai_min_range_m")) and U.is_number(d.get("ai_max_range_m")) \
			and float(d.ai_min_range_m) > float(d.ai_max_range_m):
		out.errors.append("%s: ai_min_range_m must be <= ai_max_range_m" % ctx)

	## @anchor P07
	if str(d.get("hit_shape", "")) == "grab":
		U.require(d, ["grab"], ctx, out, "hit_shape 'grab'")
	elif d.has("grab"):
		out.errors.append("%s: a 'grab' block needs hit_shape 'grab'" % ctx)

	## @anchor P09
	if is_same(d.get("targets_ally", false), true):
		if str(d.get("hit_shape", "none")) != "none":
			out.errors.append("%s: a targets_ally cast has no hit: hit_shape must be 'none'" % ctx)
		var p09_statuses: Variant = d.get("on_hit_statuses")
		if typeof(p09_statuses) != TYPE_ARRAY or (p09_statuses as Array).is_empty():
			out.errors.append("%s: a targets_ally cast needs on_hit_statuses (what lands on the ally)" % ctx)

	## @anchor P11a

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26
	var p26_ranges: Variant = d.get("range_by_stage_m")
	if typeof(p26_ranges) == TYPE_ARRAY:
		var p26_list: Array = p26_ranges
		if p26_list.is_empty():
			out.errors.append("%s.range_by_stage_m: must list at least one range" % ctx)
		for p26_i in p26_list.size():
			if U.is_number(p26_list[p26_i]) and float(p26_list[p26_i]) <= 0.0:
				out.errors.append("%s.range_by_stage_m[%d]: must be > 0 (got %s)" % [ctx, p26_i, p26_list[p26_i]])
		if str(d.get("hit_shape", "")) != "projectile":
			out.errors.append("%s: range_by_stage_m is for projectiles (hit_shape 'projectile')" % ctx)

	## @anchor P31

	## @anchor P32

	## @anchor P34


static func required_ids() -> Dictionary:
	return {"action.block": "action"}
