extends RefCounted
## Schema module for "ambience_set" records (P19; plan M6-M9 §2.5, §4.3): the ambience of a zone -
## looping beds, random one-shot spots, positioned emitters and reactions (birds fall silent when a
## giant stamps nearby). Beds, spots and emitters name amb. cues of the banks (Ogg streams on the
## Ambience bus; decision 2). P23 ships the Valley's sets, P28 the world's.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "ambience.forest", "type": "ambience_set", "display_name": "Old Wood",
##    "beds": [{"cue": "amb.bed_forest", "volume_db": 0}],
##    "spots": [{"cue": "amb.bird_a", "weight": 3, "flush": true}, {"cue": "amb.creak", "weight": 2}],
##    "spot_interval_s": [4, 12], "spot_distance_m": [15, 40],
##    "emitters": [{"cue": "amb.river_loop", "level": "level.valley", "position_m": [106, 0, -20], "radius_m": 60}],
##    "reactions": {"flush_radius_m": 40, "flush_s": 8, "flush_cue": "amb.birds_flush"}}
##
## Spots play through the two spot voices at a random bearing and distance (x the distance
## scale) every spot_interval_s; a `flush` spot is silent for flush_s after a giant's footfall or
## stomp within flush_radius_m x the distance scale, which plays flush_cue once. Of the emitters,
## the nearest two within their radius play. Defaults: spot_interval_s [6, 14], spot_distance_m
## [15, 40], weight 1, flush false, volume_db 0.

const U := preload("res://scripts/core/schemas/schema_util.gd")

const CUE_ID_REGEX := "^amb(\\.[a-z0-9_]+)+$"


static func fields() -> Dictionary:
	return {
		"beds": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"cue": U.str_field(true),
			"volume_db": U.num(-60.0, 12.0)}},
		"spots": {"t": "array", "items": "dict", "item_fields": {
			"cue": U.str_field(true),
			"weight": U.pos(),
			"flush": U.bool_field(),
			"volume_db": U.num(-60.0, 12.0)}},
		"spot_interval_s": {"t": "array", "items": "number"},
		"spot_distance_m": {"t": "array", "items": "number"},
		"emitters": {"t": "array", "items": "dict", "item_fields": {
			"cue": U.str_field(true),
			"level": U.ref("level", true),
			"position_m": U.vec3(true),
			"radius_m": U.pos(true),
			"volume_db": U.num(-60.0, 12.0)}},
		"reactions": {"t": "dict", "fields": {
			"flush_radius_m": U.pos(true),
			"flush_s": U.pos(true),
			"flush_cue": U.str_field()}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var re := RegEx.create_from_string(CUE_ID_REGEX)
	for list_key: String in ["beds", "spots", "emitters"]:
		var list: Variant = d.get(list_key)
		if typeof(list) != TYPE_ARRAY:
			continue
		var i := 0
		for item: Variant in list:
			if typeof(item) == TYPE_DICTIONARY and typeof(item.get("cue")) == TYPE_STRING \
					and re.search(item.cue) == null:
				out.errors.append("%s.%s[%d].cue: '%s' is not an amb. cue id" % [ctx, list_key, i, item.cue])
			i += 1
	for key: String in ["spot_interval_s", "spot_distance_m"]:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_ARRAY:
			continue
		var a: Array = v
		if a.size() != 2:
			out.errors.append("%s.%s: expected [min, max]" % [ctx, key])
		elif U.is_number(a[0]) and U.is_number(a[1]) and (float(a[0]) <= 0.0 or float(a[1]) < float(a[0])):
			out.errors.append("%s.%s: needs 0 < min <= max (got %s)" % [ctx, key, a])
	var reactions: Variant = d.get("reactions")
	if typeof(reactions) == TYPE_DICTIONARY:
		var cue: Variant = reactions.get("flush_cue", "")
		if typeof(cue) == TYPE_STRING and cue != "" and re.search(cue) == null:
			out.errors.append("%s.reactions.flush_cue: '%s' is not an amb. cue id" % [ctx, cue])


static func required_ids() -> Dictionary:
	return {}
