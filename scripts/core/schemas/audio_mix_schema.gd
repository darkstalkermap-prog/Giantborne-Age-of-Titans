extends RefCounted
## Schema module for "audio_mix" records (P19; plan M6-M9 §2.5, §4.4): the mix the Audio autoload
## runs - bus levels, the voice pool, the audibility classes, ducking, the material, voice, step
## and surface maps, the music's intensity weights, the threat sting's suppression and the
## footfall cruise rule. The shipped record is audio_mix.default (data/audio/mix_default.json).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "audio_mix.default", "type": "audio_mix",
##    "bus_db": {"Music": -9, "Ambience": -12, "SFX": -6, "UI": -10},
##    "pool": {"voices_3d": 24, "web_voices_3d": 16, "spot_voices": 2, "voices_2d": 8, "starts_per_frame": 16,
##             "web_starts_per_frame": 8, "min_level_db": -45, "register_ms_per_frame": 12},
##    "classes": {"impact": {"unit_m": 5, "max_m": 40, "scaled": true}, "threat": {"unit_m": 8, "max_m": 80, "scaled": "sqrt"},
##                "alert": {"unit_m": 20, "max_m": 200, "scaled": true, "floor_db": 0}},
##    "duck": {"stinger": {"Music": -8}, "pause": {"Music": -10}},
##    "materials": {"prop.fence_wood": "wood"}, "voices": {"enemy.wolf": "wolf"}, "steps": {"enemy.wolf": "paw"},
##    "surfaces": {"level.valley": {"hollow": "soft", "quarry": "hard"}},
##    "intensity": {...}, "sting": {"min_damage_fraction": 0.03, "skip_at_poise_floor": true},
##    "footfall": {"cruise_after_s": 10, "cruise_duck_db": -5}, "threat": {...}}
##
## The audio enums live here (plan §1.6: not in data_validator.gd); the other audio schema
## modules and the Audio autoload read them from this module.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## The buses the Audio autoload makes at run time (all send to Master, no effects; decision 3).
const BUSES := ["Music", "Ambience", "SFX", "UI"]
## Audibility classes (§4.4): unit_size / max_distance per class, scaled with the player. M6 gate:
## "alert" - the threat alerts (the sting, the aim lock), scaled like far_m and held up by a level
## floor (floor_db) so a far or off-camera threat is heard over the combat layer.
const CLASSES := ["player", "human_step", "human", "impact", "wolf", "big", "giant", "boss", "threat", "alert", "spot"]
## How a class follows the player's size: true (x distance scale), false, "sqrt" (x its square
## root), "own" (x the player's own height / 3.6576: the giant's own sounds).
const SCALED_VALUES := [true, false, "sqrt", "own"]
const MATERIALS := ["wood", "stone", "iron", "foliage", "cloth"]
## Voices (§4.1): "none" is a voiceless body (a sparring post) whose voice cues stay silent.
const VOICES := ["human", "wolf", "dire_wolf", "ogre", "ogre_king", "troll", "matriarch", "giant", "horse",
	"crowd", "elder", "talker", "none"]
## Footfall size classes of everything but the player (whose class is giant_s<stage>).
const STEPS := ["human", "paw", "hoof", "heavy"]
const SURFACES := ["soft", "hard", "wet"]
const DUCK_REASONS := ["stinger", "dialogue", "pause", "boss", "combat"]
## Record types a voices / steps key may name, by its id's first part.
const ACTOR_TYPES := {"enemy": "enemy", "npc": "npc", "player": "player"}
## The level key of the sandbox (it has no level record).
const SANDBOX_LEVEL := "sandbox"


static func fields() -> Dictionary:
	return {
		"bus_db": {"t": "dict", "req": true, "keys_enum": BUSES, "values": U.num(-80.0, 12.0)},
		"pool": {"t": "dict", "req": true, "fields": {
			"voices_3d": U.int_field(1, 128, true),
			"web_voices_3d": U.int_field(1, 128, true),
			"spot_voices": U.int_field(1, 8, true),
			"voices_2d": U.int_field(1, 64, true),
			"starts_per_frame": U.int_field(1, 128, true),
			"web_starts_per_frame": U.int_field(1, 128, true),
			"min_level_db": U.num(-120.0, 0.0, true),
			"register_ms_per_frame": U.num(1.0, 200.0, true)}},
		# class -> {"unit_m", "max_m", "scaled"}; checked in semantic() (scaled is a bool or a word).
		"classes": {"t": "dict", "req": true},
		"duck": {"t": "dict", "keys_enum": DUCK_REASONS, "values": {"t": "dict", "keys_enum": BUSES,
			"values": U.num(-80.0, 0.0)}},
		"materials": {"t": "dict", "values": U.str_field(false, MATERIALS)},
		"voices": {"t": "dict", "values": U.str_field(false, VOICES)},
		"steps": {"t": "dict", "values": U.str_field(false, STEPS)},
		"surfaces": {"t": "dict", "values": {"t": "dict", "values": U.str_field(false, SURFACES)}},
		"intensity": {"t": "dict", "req": true, "fields": {
			"combat_radius_m": U.pos(true),
			"danger_radius_m": U.pos(true),
			"danger_cap_m": U.pos(true),
			"lesser_danger_m": U.pos(true),
			"lesser_height_ratio": U.num(0.0, 10.0, true),
			"combat_hold_s": U.num(0.0, 120.0, true),
			"danger_hold_s": U.num(0.0, 120.0, true),
			"hit_recent_s": U.num(0.0, 120.0, true),
			"telegraph_recent_s": U.num(0.0, 120.0, true),
			"poll_s": U.pos(true)}},
		"sting": {"t": "dict", "fields": {
			"min_damage_fraction": U.num(0.0, 1.0, true),
			"skip_at_poise_floor": U.bool_field(true)}},
		"footfall": {"t": "dict", "fields": {
			"cruise_after_s": U.pos(true),
			"cruise_duck_db": U.num(-60.0, 0.0, true),
			# A footfall later than this after the previous one starts a new walk (the giant stopped).
			"stop_gap_s": U.pos()}},
		# Threat cues (§4.1, decision 7): the sting plays when the attacker is outside
		# offscreen_fov_factor x the camera's field of view or beyond far_m x the distance scale;
		# windups within windup_near_m (scaled) take priority 80; awareness barks within
		# alert_radius_m (scaled), at most one per encounter per alert_gap_s; flee barks one per
		# encounter per flee_gap_s; a formation's band brace merges within wall_merge_s.
		"threat": {"t": "dict", "fields": {
			"offscreen_fov_factor": U.num(0.1, 2.0),
			"far_m": U.pos(),
			"windup_near_m": U.pos(),
			"alert_radius_m": U.pos(),
			"alert_gap_s": U.num(0.0, 60.0),
			"flee_gap_s": U.num(0.0, 60.0),
			"wall_merge_s": U.num(0.0, 10.0),
			"denied_gap_s": U.num(0.0, 10.0)}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var classes: Variant = d.get("classes")
	if typeof(classes) == TYPE_DICTIONARY:
		for k: Variant in classes:
			var cctx := "%s.classes.%s" % [ctx, k]
			if not CLASSES.has(k):
				out.errors.append("%s.classes: unknown key '%s' (allowed: %s)" % [ctx, k, CLASSES])
				continue
			var c: Variant = classes[k]
			if typeof(c) != TYPE_DICTIONARY:
				out.errors.append("%s: expected an object, got %s" % [cctx, type_string(typeof(c))])
				continue
			for key: Variant in c:
				if not (key in ["unit_m", "max_m", "scaled", "floor_db"]):
					out.errors.append("%s: unknown key '%s'" % [cctx, key])
			# M6 gate: the most distance may take off a cue of the class (AudioMath.floored_volume).
			if c.has("floor_db"):
				U.check_value(c.floor_db, U.num(-60.0, 0.0), "%s.floor_db" % cctx, out)
			for key: String in ["unit_m", "max_m"]:
				if c.has(key):
					U.check_value(c[key], U.pos(true), "%s.%s" % [cctx, key], out)
				else:
					out.errors.append("%s: missing required key '%s'" % [cctx, key])
			if c.has("scaled") and not _scaled_ok(c.scaled):
				out.errors.append("%s.scaled: must be true, false, \"sqrt\" or \"own\" (got %s)" % [cctx, c.scaled])
			if U.is_number(c.get("unit_m")) and U.is_number(c.get("max_m")) and float(c.max_m) <= float(c.unit_m):
				out.errors.append("%s: max_m (%s) must be larger than unit_m (%s)" % [cctx, c.max_m, c.unit_m])
		for k: String in CLASSES:
			if not classes.has(k):
				out.errors.append("%s.classes: missing class '%s'" % [ctx, k])
	for map_key: String in ["materials"]:
		var m: Variant = d.get(map_key)
		if typeof(m) == TYPE_DICTIONARY:
			for k: Variant in m:
				out.refs.append({"ctx": "%s.%s" % [ctx, map_key], "id": str(k), "type": "prop"})
	for map_key: String in ["voices", "steps"]:
		var m: Variant = d.get(map_key)
		if typeof(m) != TYPE_DICTIONARY:
			continue
		for k: Variant in m:
			var kind := str(k).get_slice(".", 0)
			if not ACTOR_TYPES.has(kind):
				out.errors.append("%s.%s: key '%s' must name an enemy, npc or player record" % [ctx, map_key, k])
			else:
				out.refs.append({"ctx": "%s.%s" % [ctx, map_key], "id": str(k), "type": ACTOR_TYPES[kind]})
	var surfaces: Variant = d.get("surfaces")
	if typeof(surfaces) == TYPE_DICTIONARY:
		for k: Variant in surfaces:
			if str(k) != SANDBOX_LEVEL:
				out.refs.append({"ctx": "%s.surfaces" % ctx, "id": str(k), "type": "level"})
	var intensity: Variant = d.get("intensity")
	if typeof(intensity) == TYPE_DICTIONARY and U.is_number(intensity.get("danger_radius_m")) \
			and U.is_number(intensity.get("combat_radius_m")) \
			and float(intensity.danger_radius_m) < float(intensity.combat_radius_m):
		out.errors.append("%s.intensity: danger_radius_m must be at least combat_radius_m" % ctx)


static func _scaled_ok(v: Variant) -> bool:
	if typeof(v) == TYPE_BOOL:
		return true
	return typeof(v) == TYPE_STRING and (v == "sqrt" or v == "own")


static func required_ids() -> Dictionary:
	return {"audio_mix.default": "audio_mix"}
