extends RefCounted
## Schema module for "audio_region" records (P19; plan M6-M9 §2.5): which music set and ambience
## set play where. A record matches a level's districts (the Valley, LevelRoot.district_at), its
## regions (the world, WorldRoot.region_at), its POIs (by their radius; P28), a context (title,
## end, campaign_end, sandbox: music outside a level) or a boss (an enemy record id such as
## enemy.ogre_king, or a battle id such as battle.iron_regiment: its boss_engaged switches to this
## record's music). The highest priority match wins (POIs 10, districts and regions 0); zones are
## matched with 15 m hysteresis. P23 ships the Valley's records, P28 the world's.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "audio_region.valley_wood", "type": "audio_region", "level": "level.valley",
##    "districts": ["forest", "barrow"], "regions": [], "pois": [], "context": "", "boss": "",
##    "music": "music.valley_wild", "ambience": "ambience.forest", "priority": 0}
##
## Optional overrides for a place inside a region (P28: settlements keep their region's music with
## the melody quieter and longer rests): `layers` (intensity -> stem or "melody" -> dB, merged over
## the set's layers) and `melody` (keys of the set's melody block, e.g. {"rest_loops": [2, 4]}).
## Every level record and every context maps to a record or is silent by decision (P23's coverage
## test): the silent list is a record of its own, data/audio/region_silent.json, carrying only
## `silent_levels` (level ids) and `silent_contexts` (context names such as "loading"); every level
## whose record lives under data/test (test content) is silent too (Audio.is_silent_level).

const U := preload("res://scripts/core/schemas/schema_util.gd")
const MUSIC := preload("res://scripts/core/schemas/music_set_schema.gd")

const CONTEXTS := ["", "title", "end", "campaign_end", "sandbox"]
const ZONE_REGEX := "^[a-z][a-z0-9_]*$"


static func fields() -> Dictionary:
	return {
		"level": U.ref("level", false, true),
		"districts": {"t": "array", "items": "string"},
		"regions": {"t": "array", "items": "string"},
		"pois": {"t": "array", "items": "string"},
		"context": U.str_field(false, CONTEXTS),
		"boss": U.str_field(),
		"music": U.ref("music_set", false, true),
		"ambience": U.ref("ambience_set", false, true),
		"priority": U.int_field(-100, 100),
		"layers": {"t": "dict", "keys_enum": MUSIC.INTENSITIES, "values": {"t": "dict", "values": U.num(-80.0, 12.0)}},
		"silent_levels": {"t": "array", "items": "string"},
		"silent_contexts": {"t": "array", "items": "string"},
		"melody": {"t": "dict", "fields": {
			"play_loops": {"t": "array", "items": "int"},
			"rest_loops": {"t": "array", "items": "int"},
			"max_repeat": U.int_field(1, 16),
			"min_phrase_gap_s": U.num(0.0, 3600.0),
			"rest_weight": U.num(0.0, 1.0)}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var context := str(d.get("context", ""))
	var level := str(d.get("level", ""))
	var boss := str(d.get("boss", ""))
	if is_silent_list(d):
		for key: String in ["music", "ambience", "level", "context", "boss"]:
			if str(d.get(key, "")) != "":
				out.errors.append("%s: a silent list (silent_levels / silent_contexts) names no %s" % [ctx, key])
		for key: String in ["districts", "regions", "pois"]:
			if typeof(d.get(key)) == TYPE_ARRAY and not (d.get(key) as Array).is_empty():
				out.errors.append("%s: a silent list names no %s" % [ctx, key])
		var re := RegEx.create_from_string(ZONE_REGEX)
		for c: Variant in d.get("silent_contexts", []):
			if typeof(c) != TYPE_STRING or re.search(c) == null:
				out.errors.append("%s.silent_contexts: '%s' must be a plain word like 'loading'" % [ctx, c])
		for lv: Variant in d.get("silent_levels", []):
			if typeof(lv) == TYPE_STRING:
				U.check_id_string(lv, ctx + ".silent_levels", out)
		return
	if str(d.get("music", "")) == "" and str(d.get("ambience", "")) == "":
		out.errors.append("%s: names neither music nor ambience" % ctx)
	var zones := 0
	for key: String in ["districts", "regions", "pois"]:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_ARRAY:
			continue
		zones += (v as Array).size()
		var i := 0
		for z: Variant in v:
			var zctx := "%s.%s[%d]" % [ctx, key, i]
			i += 1
			if typeof(z) != TYPE_STRING:
				out.errors.append("%s: expected a string" % zctx)
			elif key == "districts" and RegEx.create_from_string(ZONE_REGEX).search(z) == null:
				out.errors.append("%s: district '%s' must be a plain word like 'forest'" % [zctx, z])
			elif key != "districts":
				U.check_id_string(z, zctx, out)
	if context != "":
		if level != "" or zones > 0 or boss != "":
			out.errors.append("%s: a context record (%s) names no level, zone or boss" % [ctx, context])
	elif boss != "":
		U.check_id_string(boss, ctx + ".boss", out)
	elif level == "":
		out.errors.append("%s: needs a level (or a context, or a boss)" % ctx)
	var melody: Variant = d.get("melody")
	if typeof(melody) == TYPE_DICTIONARY:
		for key: String in ["play_loops", "rest_loops"]:
			var r: Variant = melody.get(key)
			if typeof(r) != TYPE_ARRAY:
				continue
			var a: Array = r
			if a.size() != 2 or not (U.is_number(a[0]) and U.is_number(a[1])) \
					or float(a[1]) < float(a[0]) or float(a[0]) < 1.0:
				out.errors.append("%s.melody.%s: expected [min, max] with 1 <= min <= max" % [ctx, key])


## True for the silent list record (it carries silent_levels or silent_contexts).
static func is_silent_list(d: Dictionary) -> bool:
	return d.has("silent_levels") or d.has("silent_contexts")


static func required_ids() -> Dictionary:
	return {}
