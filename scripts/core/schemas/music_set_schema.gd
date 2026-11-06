extends RefCounted
## Schema module for "music_set" records (P19; plan M6-M9 §2.5, §4.3): one adaptive score - stems
## played together as streams, the layers each intensity hears, the melody scheduler's rules,
## the silence window, the combat-intro stinger, and for a boss set its intro stinger and phase
## layers. P23 ships the Valley's sets, P28 the world's.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "music.valley_wild", "type": "music_set", "display_name": "The Old Wood",
##    "bpm": 96, "beats_per_bar": 4, "bars": 12, "frame": "zone_96",
##    "stems": {"drone": "res://assets/audio/music/drone_wild.ogg", "melody_a": "...", "pulse": "..."},
##    "layers": {"explore": {"drone": 0, "melody": -2}, "danger": {...}, "combat": {...}},
##    "melody": {"variants": ["melody_a", "melody_b", "melody_c"], "segment_bars": 4, "play_loops": [1, 2],
##               "rest_loops": [1, 3], "max_repeat": 2, "min_phrase_gap_s": 60},
##    "silence": {"after_explore_s": 180, "length_s": [60, 120], "fade_s": 8},
##    "combat_intro": "mus.stinger.combat_wild", "intro": "", "phase_layers": {}, "crossfade_bars": 2,
##    "layer_fade_beats": 2}
##
## The first key of `stems` is the lead stem: bar and segment boundaries are computed from its
## playback position. A stem missing from a layer is silent; the layer key `melody` means "the
## variant the melody scheduler chose for this segment". Every stem lasts exactly bars x
## beats_per_bar x 60 / bpm seconds, and sets that share a stem share a `frame` (tempo, metre and
## loop length): both are checked against assets/audio/manifest.json, which records each Ogg's
## frames, rate and frame name (a stem in a frame other than its set's is an error, so two sets of
## different frames can never share it). Boss sets carry their own frame, an `intro` stinger and
## `phase_layers` ({"2": {"frenzy": 0}}: the layer added from that boss phase on).

const U := preload("res://scripts/core/schemas/schema_util.gd")

const INTENSITIES := ["explore", "danger", "combat"]
const MELODY_KEY := "melody"
const STEM_NAME_REGEX := "^[a-z][a-z0-9_]*$"
const CUE_ID_REGEX := "^mus(\\.[a-z0-9_]+)+$"
## A stem may differ from the loop length by at most this many frames (rounding).
const LENGTH_TOLERANCE_FRAMES := 1


static func fields() -> Dictionary:
	return {
		"bpm": U.num(20.0, 300.0, true),
		"beats_per_bar": U.int_field(1, 16, true),
		"bars": U.int_field(1, 512, true),
		"frame": U.str_field(true),
		"stems": {"t": "dict", "req": true, "values": U.str_field()},
		"layers": {"t": "dict", "req": true, "keys_enum": INTENSITIES, "values": {"t": "dict",
			"values": U.num(-80.0, 12.0)}},
		"melody": {"t": "dict", "fields": {
			"variants": {"t": "array", "req": true, "items": "string"},
			"segment_bars": U.int_field(1, 64, true),
			"play_loops": {"t": "array", "req": true, "items": "int"},
			"rest_loops": {"t": "array", "req": true, "items": "int"},
			"max_repeat": U.int_field(1, 16, true),
			"min_phrase_gap_s": U.num(0.0, 3600.0, true),
			"rest_weight": U.num(0.0, 1.0)}},
		"silence": {"t": "dict", "fields": {
			"after_explore_s": U.pos(true),
			"length_s": {"t": "array", "req": true, "items": "number"},
			"fade_s": U.num(0.0, 120.0, true)}},
		"combat_intro": U.str_field(),
		"intro": U.str_field(),
		"phase_layers": {"t": "dict", "values": {"t": "dict", "values": U.num(-80.0, 12.0)}},
		"crossfade_bars": U.int_field(0, 64),
		"layer_fade_beats": U.num(0.0, 64.0),
	}


## Seconds of one loop of the set (every stem has this length).
static func loop_seconds(d: Dictionary) -> float:
	if not (U.is_number(d.get("bpm")) and U.is_number(d.get("beats_per_bar")) and U.is_number(d.get("bars"))):
		return 0.0
	return float(d.bars) * float(d.beats_per_bar) * 60.0 / maxf(float(d.bpm), 1e-6)


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var stems: Variant = d.get("stems")
	var names: Array = []
	if typeof(stems) == TYPE_DICTIONARY:
		names = (stems as Dictionary).keys()
		if names.is_empty():
			out.errors.append("%s.stems: a set needs at least one stem (the first is the lead)" % ctx)
		var re := RegEx.create_from_string(STEM_NAME_REGEX)
		for k: Variant in names:
			if re.search(str(k)) == null or str(k) == MELODY_KEY:
				out.errors.append("%s.stems: stem name '%s' must be a lowercase word other than 'melody'" % [ctx, k])
		_check_stem_files(d, stems, ctx, out)
	var melody: Variant = d.get("melody")
	var variants: Array = []
	if typeof(melody) == TYPE_DICTIONARY:
		variants = melody.get("variants", []) if typeof(melody.get("variants")) == TYPE_ARRAY else []
		if variants.is_empty():
			out.errors.append("%s.melody.variants: at least one variant stem" % ctx)
		for v: Variant in variants:
			if not names.has(v):
				out.errors.append("%s.melody.variants: '%s' is not a stem of this set" % [ctx, v])
		for key: String in ["play_loops", "rest_loops"]:
			_check_range(melody.get(key), "%s.melody.%s" % [ctx, key], 1, out)
		if U.is_number(melody.get("segment_bars")) and U.is_number(d.get("bars")) \
				and int(d.bars) % maxi(1, int(melody.segment_bars)) != 0:
			out.errors.append("%s.melody.segment_bars: %s does not divide the loop's %s bars" % [ctx, melody.segment_bars, d.bars])
	var layers: Variant = d.get("layers")
	if typeof(layers) == TYPE_DICTIONARY:
		for intensity: Variant in layers:
			var layer: Variant = layers[intensity]
			if typeof(layer) != TYPE_DICTIONARY:
				continue
			for stem: Variant in layer:
				var lctx := "%s.layers.%s" % [ctx, intensity]
				if stem == MELODY_KEY:
					if typeof(melody) != TYPE_DICTIONARY:
						out.errors.append("%s: 'melody' needs the set's melody block" % lctx)
				elif not names.has(stem):
					out.errors.append("%s: '%s' is not a stem of this set" % [lctx, stem])
				elif variants.has(stem):
					out.errors.append("%s: the melody variant '%s' plays through the 'melody' key, not by name" % [lctx, stem])
		if not layers.has("explore"):
			out.errors.append("%s.layers: the explore layer is required" % ctx)
	var phases: Variant = d.get("phase_layers")
	if typeof(phases) == TYPE_DICTIONARY:
		for p: Variant in phases:
			var pctx := "%s.phase_layers.%s" % [ctx, p]
			if not str(p).is_valid_int() or int(str(p)) < 2:
				out.errors.append("%s: a phase number from 2 up" % pctx)
			if typeof(phases[p]) == TYPE_DICTIONARY:
				for stem: Variant in phases[p]:
					if not names.has(stem):
						out.errors.append("%s: '%s' is not a stem of this set" % [pctx, stem])
	var silence: Variant = d.get("silence")
	if typeof(silence) == TYPE_DICTIONARY:
		_check_range(silence.get("length_s"), ctx + ".silence.length_s", 0, out)
	for key: String in ["combat_intro", "intro"]:
		var cue: Variant = d.get(key, "")
		if typeof(cue) == TYPE_STRING and cue != "" and RegEx.create_from_string(CUE_ID_REGEX).search(cue) == null:
			out.errors.append("%s.%s: '%s' is not a mus. cue id" % [ctx, key, cue])


## Stem files: Ogg; when the manifest knows them, exactly one loop long and of this set's frame.
static func _check_stem_files(d: Dictionary, stems: Dictionary, ctx: String, out: Dictionary) -> void:
	var want_s := loop_seconds(d)
	var frame := str(d.get("frame", ""))
	for name: Variant in stems:
		var path: Variant = stems[name]
		var sctx := "%s.stems.%s" % [ctx, name]
		if typeof(path) != TYPE_STRING:
			continue
		if not str(path).begins_with("res://") or not str(path).ends_with(".ogg"):
			out.errors.append("%s: '%s' must be a res:// Ogg file (decision 2)" % [sctx, path])
			continue
		if not ResourceLoader.exists(path):
			out.errors.append("%s: file '%s' does not exist" % [sctx, path])
			continue
		var e := AudioMath.manifest_entry(path)
		if e.is_empty():
			continue
		var rate := float(e.get("rate", 0.0))
		var frames := int(e.get("frames", 0))
		if rate > 0.0 and want_s > 0.0 and absf(frames - want_s * rate) > LENGTH_TOLERANCE_FRAMES:
			out.errors.append("%s: '%s' is %.4f s, but the set's loop is %.4f s (%s bars of %s beats at %s bpm)" % [
				sctx, path, frames / rate, want_s, d.get("bars"), d.get("beats_per_bar"), d.get("bpm")])
		var stem_frame := str(e.get("frame", ""))
		if stem_frame != "" and frame != "" and stem_frame != frame:
			out.errors.append("%s: '%s' belongs to the frame %s, not this set's %s (sets that share a stem share a frame)" % [
				sctx, path, stem_frame, frame])


static func _check_range(v: Variant, ctx: String, min_v: int, out: Dictionary) -> void:
	if typeof(v) != TYPE_ARRAY:
		return
	var a: Array = v
	if a.size() != 2:
		out.errors.append("%s: expected [min, max]" % ctx)
		return
	if not (U.is_number(a[0]) and U.is_number(a[1])):
		return
	if float(a[0]) < min_v:
		out.errors.append("%s: the minimum must be at least %d" % [ctx, min_v])
	if float(a[1]) < float(a[0]):
		out.errors.append("%s: max %s is below min %s" % [ctx, a[1], a[0]])


static func required_ids() -> Dictionary:
	return {}
