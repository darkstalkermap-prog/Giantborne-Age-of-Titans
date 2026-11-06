extends RefCounted
## Schema module for "wander_table" records (P20 pre-declares it; plan M6-M9 §2.13, decision 27):
## a region's wandering encounters, filtered by the player's stage and the world's flags. P37
## ships the framework and the Crownmarch's table; P35 and P36 their regions'.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "wander.aldmere", "type": "wander_table", "region": "region.aldmere",
##    "max_active": 2, "interval_s": [60, 120], "min_distance_m": 120, "max_distance_m": 220,
##    "anchors": "roads", "xp_full_spawns": 3,
##    "entries": [{"id": "patrol_line", "weight": 3, "min_stage": 3, "max_stage": 3,
##                 "template": "encounter.tpl_aldmere_patrol"},
##                {"id": "pike_column", "weight": 3, "min_stage": 4, "max_stage": 6,
##                 "template": "encounter.tpl_pike_column", "path": "world.patrol.kings_road",
##                 "requires_flags": [], "forbids_flags": ["oath.crown.outcome"]}]}
##
## An entry's spawns give kill XP for the first xp_full_spawns spawns only (the counter is the
## flag wander.<table short>.<entry>.spawns), so entry ids are plain words.
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## Where a table's spawns stand: road nodes, safe/objective markers or POIs of the region.
const ANCHOR_KINDS := ["roads", "markers", "pois"]
const WORD_REGEX := "^[a-z][a-z0-9_]*$"


static func fields() -> Dictionary:
	var f := {
		"region": U.ref("region", true),
		"max_active": U.int_field(1, 16),
		"interval_s": {"t": "array", "items": "number"},
		"min_distance_m": U.num(0.0),
		"max_distance_m": U.pos(),
		"anchors": U.str_field(false, ANCHOR_KINDS),
		"xp_full_spawns": U.int_field(0, 100),
		"entries": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"weight": U.pos(true),
			"min_stage": U.int_field(1, 10),
			"max_stage": U.int_field(1, 10),
			"template": U.ref("encounter", true),
			"path": U.str_field(),
			"requires_flags": {"t": "array", "items": "string"},
			"forbids_flags": {"t": "array", "items": "string"}}},
	}
	## @anchor P37

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("wander."):
		out.errors.append("%s: wander table ids start with 'wander.' (got '%s')" % [ctx, id])
	var interval: Variant = d.get("interval_s")
	if typeof(interval) == TYPE_ARRAY:
		var arr: Array = interval
		if arr.size() != 2 or (U.is_number(arr[0]) and U.is_number(arr[1]) and float(arr[0]) > float(arr[1])):
			out.errors.append("%s.interval_s: must be [shortest, longest] seconds" % ctx)
	if U.is_number(d.get("min_distance_m")) and U.is_number(d.get("max_distance_m")) \
			and float(d.min_distance_m) > float(d.max_distance_m):
		out.errors.append("%s: min_distance_m must be <= max_distance_m" % ctx)
	check_entries(d.get("entries"), ctx, out)
	## @anchor P37


static func required_ids() -> Dictionary:
	return {}


## The entries: at least one, unique plain-word ids, min_stage <= max_stage, valid path and flag ids.
static func check_entries(entries: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(entries) != TYPE_ARRAY:
		return
	if (entries as Array).is_empty():
		out.errors.append("%s: entries must list at least one entry" % ctx)
	var word := RegEx.create_from_string(WORD_REGEX)
	var seen := {}
	var i := 0
	for e: Variant in entries:
		var ectx := "%s.entries[%d]" % [ctx, i]
		i += 1
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var eid: Variant = e.get("id")
		if typeof(eid) == TYPE_STRING:
			if word.search(eid) == null:
				out.errors.append("%s.id: entry id '%s' must be a plain lowercase word" % [ectx, eid])
			if seen.has(eid):
				out.errors.append("%s.id: duplicate entry id '%s'" % [ectx, eid])
			seen[eid] = true
		if U.is_number(e.get("min_stage")) and U.is_number(e.get("max_stage")) \
				and int(e.min_stage) > int(e.max_stage):
			out.errors.append("%s: min_stage must be <= max_stage" % ectx)
		var path: Variant = e.get("path", "")
		if typeof(path) == TYPE_STRING and path != "":
			U.check_id_string(path, ectx + ".path", out)
		for key: String in ["requires_flags", "forbids_flags"]:
			var flags: Variant = e.get(key)
			if typeof(flags) == TYPE_ARRAY:
				var j := 0
				for f: Variant in flags:
					U.check_flag_id(f, "%s.%s[%d]" % [ectx, key, j], out)
					j += 1
