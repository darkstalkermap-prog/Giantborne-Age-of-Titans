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


static func required_ids() -> Dictionary:
	return {}
