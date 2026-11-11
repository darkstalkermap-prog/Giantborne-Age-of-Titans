extends RefCounted
## Schema module for "region" records (P20 pre-declares it for M7; plan M6-M9 §2.7): one of the
## world's regions - its bounds, surface, discovery XP, faction, tints, wander table, the journal's
## note on it (journal_note, M8 gate F22) and the M7 rule's note while its content is still to come
## (m7_note). P25 ships the first records.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "region.greywood", "type": "region", "display_name": "The Greywood",
##    "level": "level.world", "tier": 2, "recommended_stage": [4, 5],
##    "bounds_m": [[-896, -440], [-320, 300]], "surface": "soft", "discover_xp": 40,
##    "faction": "faction.woodfolk", "map_tint": [0.33, 0.47, 0.33], "fog_color": [0.52, 0.6, 0.55],
##    "skyline_tint": [0.22, 0.33, 0.24], "wander_table": "wander.greywood",
##    "journal_note": "The woodfolk's wood: Hollowmere on its black pond...",
##    "m7_note": "The woodfolk and their troubles come with the next build."}
##
## bounds_m is [[min_x, min_z], [max_x, max_z]] in level space. faction and wander_table are
## record references (a region may leave them out until their records ship). Colours are RGB in
## 0..1.
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## Ground types WorldRoot.surface_at answers (plan §2.8).
const SURFACES := ["soft", "hard", "wet"]


static func fields() -> Dictionary:
	var f := {
		"level": U.ref("level", true),
		# Difficulty tier (1 the Crownmarch ... 5 the Stonehold).
		"tier": U.int_field(1, 10),
		# [lowest, highest] growth stage the region is tuned for (the map warns below it).
		"recommended_stage": {"t": "array", "items": "int"},
		"bounds_m": {"t": "array", "req": true},
		"surface": U.str_field(false, SURFACES),
		# XP for entering the region the first time (Discovery, P27).
		"discover_xp": U.int_field(0, 10000),
		"faction": U.ref("faction", false, true),
		"map_tint": U.vec3(),
		"fog_color": U.vec3(),
		"skyline_tint": U.vec3(),
		"wander_table": U.ref("wander_table", false, true),
		# M8 gate (F22): what the journal's Regions section says of the region (every region has one).
		"journal_note": U.str_field(),
		# The M7 rule's marker: the region's content is still to come (its package not yet shipped);
		# tests/integration/test_m7_content_rule.gd reads it. No region of the M8 build has one.
		"m7_note": U.str_field(),
	}
	## @anchor P25

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("region."):
		out.errors.append("%s: region ids start with 'region.' (got '%s')" % [ctx, id])
	var rs: Variant = d.get("recommended_stage")
	if typeof(rs) == TYPE_ARRAY:
		var arr: Array = rs
		if arr.size() != 2:
			out.errors.append("%s.recommended_stage: must be [lowest, highest]" % ctx)
		elif U.is_number(arr[0]) and U.is_number(arr[1]):
			if int(arr[0]) < 1 or int(arr[1]) > 10 or int(arr[0]) > int(arr[1]):
				out.errors.append("%s.recommended_stage: stages 1-10 with lowest <= highest (got %s)" % [ctx, arr])
	var b: Variant = d.get("bounds_m")
	if typeof(b) == TYPE_ARRAY and not bounds_ok(b):
		out.errors.append("%s.bounds_m: must be [[min_x, min_z], [max_x, max_z]] with min < max" % ctx)
	for key: String in ["map_tint", "fog_color", "skyline_tint"]:
		check_color(d.get(key), "%s.%s" % [ctx, key], out)
	## @anchor P25


static func required_ids() -> Dictionary:
	return {}


## True for [[min_x, min_z], [max_x, max_z]] with numbers and min < max on both axes.
static func bounds_ok(b: Variant) -> bool:
	if typeof(b) != TYPE_ARRAY or (b as Array).size() != 2:
		return false
	for corner: Variant in b:
		if typeof(corner) != TYPE_ARRAY or (corner as Array).size() != 2:
			return false
		for v: Variant in corner:
			if not U.is_number(v):
				return false
	return float(b[0][0]) < float(b[1][0]) and float(b[0][1]) < float(b[1][1])


## An RGB colour: three numbers in 0..1 (nothing to check when absent).
static func check_color(v: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return
	for c: Variant in v:
		if U.is_number(c) and (float(c) < 0.0 or float(c) > 1.0):
			out.errors.append("%s: colour components must lie in 0..1 (got %s)" % [ctx, v])
			return
