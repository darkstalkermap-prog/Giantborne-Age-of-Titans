extends RefCounted
## Schema module for "growth_profile" records (one per growth stage).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"stage": U.int_field(1, 10, true),
		"required_level": U.int_field(1, 20, true),
		"height_m": U.pos(true),
		"capsule_radius_m": U.pos(true),
		"capsule_total_height_m": U.pos(true),
		"walk_speed_mps": U.pos(true),
		"melee_reach_m": U.pos(true),
		"camera_distance_m": U.pos(true),
		"camera_zoom_min_m": U.pos(true),
		"camera_zoom_max_m": U.pos(true),
		"camera_pivot_height_m": U.pos(true),
		"camera_shoulder_offset_m": U.num(null, null, true),
		"eye_height_ratio": {"t": "number", "gt": 0.0, "max": 1.0, "req": true},
		"acceleration_mps2": U.pos(true),
		"turn_rate_deg_s": U.pos(true),
		"step_height_m": U.num(0.0, null, true),
		"jump_velocity_mps": U.num(0.0, null, true),
		"dodge_distance_m": U.pos(true),
		"lock_range_m": U.pos(true),
		"lock_half_angle_deg": {"t": "number", "gt": 0.0, "max": 180.0, "req": true},
		"weapon_pivot_m": {"t": "vec3", "req": true},
		"attack_origin_m": {"t": "vec3", "req": true},
		"arm_length_m": U.pos(true),
		"interaction_permissions": {"t": "array", "items": "string", "items_enum": DataValidator.INTERACTION_PERMISSIONS},
		"unlocks": {"t": "array", "items": "string", "items_ref": "action"},
	}
	## @anchor P05
	# Growth stages 1-3 (plan §2.8.2, values in §4.8). All optional; code defaults in brackets.
	f.merge({
		# Scale of the weapon's length and hit radius at this stage [1]; P08 caps it at the
		# weapon's fit stage.
		"weapon_scale": U.pos(),
		# Grab reach (melee reach + 0.5 m) and the lunge of the grab windup [0] (P07 uses them).
		"grab_reach_m": U.pos(),
		"grab_lunge_m": U.num(0.0),
		# The heaviest mass class this stage can grab [small] and the attachment profiles it
		# supports [torso_fist, scruff].
		"grab_capacity": U.str_field(false, DataValidator.MASS_CLASSES),
		"grab_attach": U.enum_array(DataValidator.GRAB_ATTACH),
		# Extra maxima over the player record's resources, e.g. {"health": 150, "stamina": 10}.
		"resource_bonus": {"t": "dict", "keys_enum": ["health", "stamina", "essence"], "values": U.num(0.0)},
		# Downward tilt of the player's weapon arcs, in both the sweep and the rig [0] ...
		"arc_pitch_offset_deg": U.num(-30.0, 0.0),
		# ... and per-action exceptions, {action id: degrees -30..0}, e.g. a horizontal sweep
		# that must dip further to reach a wolf at a big giant's feet while an overhead chop
		# keeps the base tilt (its reach shrinks the deeper it ends).
		"arc_pitch_offsets_deg": {"t": "dict", "values": U.num(-30.0, 0.0)},
		# roll (stage 1) or sidestep (a slower lateral rig pose; same timing) [roll].
		"dodge_style": U.str_field(false, DataValidator.DODGE_STYLES),
		# Multiplies the lock-on camera's orbit distances [1].
		"camera_orbit_scale": U.pos(),
		# Navigation layers of this stage: 8 small giant (4 m alleys), 4 giant [4].
		"nav_layers": U.int_field(1, 255),
		# Camera shake added on each footfall, scaled by the camera_shake setting [0].
		"footstep_shake": U.num(0.0, 1.0),
	})

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if U.is_number(d.get("capsule_total_height_m")) and U.is_number(d.get("capsule_radius_m")):
		if float(d.capsule_total_height_m) < 2.0 * float(d.capsule_radius_m):
			out.errors.append("%s: capsule_total_height_m must be at least twice capsule_radius_m" % ctx)
	if U.is_number(d.get("camera_zoom_min_m")) and U.is_number(d.get("camera_zoom_max_m")) \
			and U.is_number(d.get("camera_distance_m")):
		if not (float(d.camera_zoom_min_m) <= float(d.camera_distance_m)
				and float(d.camera_distance_m) <= float(d.camera_zoom_max_m)):
			out.errors.append("%s: camera_distance_m must lie between camera_zoom_min_m and camera_zoom_max_m" % ctx)
	## @anchor P05
	var per_action: Variant = d.get("arc_pitch_offsets_deg")
	if typeof(per_action) == TYPE_DICTIONARY:
		for key: Variant in per_action:
			# The keys are action ids: checked against the loaded records like any reference.
			out.refs.append({"ctx": "%s.arc_pitch_offsets_deg" % ctx, "id": str(key), "type": "action"})


static func required_ids() -> Dictionary:
	return {}
