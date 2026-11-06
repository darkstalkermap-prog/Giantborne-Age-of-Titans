extends RefCounted
## Schema module for "audio_bank" records (P19; plan M6-M9 §2.5): a named group of cues. The Audio
## autoload merges every bank into one cue catalogue (a cue id may appear in one bank only;
## Audio.catalog_problems() reports a duplicate). P19 ships the placeholder bank; P21 (effects),
## P23 (stingers and ambience cues) and P28 (the world) add theirs.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "audio_bank.combat", "type": "audio_bank", "display_name": "Combat",
##    "cues": {"sfx.hit.flesh.light": {"files": ["res://assets/audio/sfx/combat/hit_flesh_light_1.wav"],
##      "bus": "SFX", "spatial": true, "class": "impact", "volume_db": -3.0, "pitch": 1.0,
##      "pitch_jitter": 0.06, "size_pitch": true, "max_voices": 8, "retrigger_ms": 45, "priority": 80,
##      "far": "", "levels": []}}}
##
## A cue: `files` 1-4 variants (WAV on the SFX and UI buses, each at most 2.0 s; Ogg on Music and
## Ambience - loops, stingers, ambience spots; decision 2), picked by the director's own RNG and
## never the same twice in a row; `class` an audibility class of the mix (spatial cues);
## `size_pitch` lowers bigger bodies (pitch x (3.6576 / height)^0.25, clamped 0.6-1.25); `far` a
## cue played instead beyond half the class's scaled max_m; `levels` the levels whose loading
## registers its samples ([] = every level; "sandbox" names the sandbox). Cue ids start with sfx.,
## amb. or mus. (§2.3); mus. cues play on Music, amb. cues on Ambience, sfx. cues on SFX or UI.
##
## Defaults (Audio applies them when a key is absent): bus SFX, spatial true, class impact,
## volume_db 0, pitch 1, pitch_jitter 0, size_pitch false, max_voices 4, retrigger_ms 40,
## priority 50, far "", levels [].

const U := preload("res://scripts/core/schemas/schema_util.gd")
const MIX := preload("res://scripts/core/schemas/audio_mix_schema.gd")

const CUE_ID_REGEX := "^(sfx|amb|mus)(\\.[a-z0-9_]+)+$"
const MAX_FILES := 4
const SFX_MAX_S := 2.0
## The buses each cue prefix may use.
const PREFIX_BUSES := {"sfx": ["SFX", "UI"], "amb": ["Ambience"], "mus": ["Music"]}
const SAMPLE_BUSES := ["SFX", "UI"]
const DEFAULTS := {"bus": "SFX", "spatial": true, "class": "impact", "volume_db": 0.0, "pitch": 1.0,
	"pitch_jitter": 0.0, "size_pitch": false, "max_voices": 4, "retrigger_ms": 40, "priority": 50,
	"far": "", "levels": []}


static func cue_fields() -> Dictionary:
	return {
		"files": {"t": "array", "req": true, "items": "string"},
		"bus": U.str_field(false, MIX.BUSES),
		"spatial": U.bool_field(),
		"class": U.str_field(false, MIX.CLASSES),
		"volume_db": U.num(-60.0, 12.0),
		"pitch": U.num(0.25, 4.0),
		"pitch_jitter": U.num(0.0, 0.5),
		"size_pitch": U.bool_field(),
		"max_voices": U.int_field(1, 32),
		"retrigger_ms": U.int_field(0, 10000),
		"priority": U.int_field(0, 100),
		"far": U.str_field(),
		"levels": {"t": "array", "items": "string"},
	}


static func fields() -> Dictionary:
	return {
		# cue id -> cue (checked cue by cue in semantic()).
		"cues": {"t": "dict", "req": true},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var cues: Variant = d.get("cues")
	if typeof(cues) != TYPE_DICTIONARY:
		return
	var re := RegEx.create_from_string(CUE_ID_REGEX)
	var spec := cue_fields()
	for cue_id: Variant in cues:
		var cctx := "%s.cues.%s" % [ctx, cue_id]
		if typeof(cue_id) != TYPE_STRING or re.search(cue_id) == null:
			out.errors.append("%s.cues: cue id '%s' must look like sfx.hit.flesh.light (sfx., amb. or mus.)" % [ctx, cue_id])
			continue
		var c: Variant = cues[cue_id]
		if typeof(c) != TYPE_DICTIONARY:
			out.errors.append("%s: expected an object, got %s" % [cctx, type_string(typeof(c))])
			continue
		U.check_fields(c, spec, cctx, out)
		check_cue(cue_id, c, cctx, out)


## The cross-field rules of one cue (also used by tests on single cues).
static func check_cue(cue_id: String, c: Dictionary, cctx: String, out: Dictionary) -> void:
	var bus := str(c.get("bus", DEFAULTS.bus))
	var prefix := cue_id.get_slice(".", 0)
	var allowed: Array = PREFIX_BUSES.get(prefix, [])
	if MIX.BUSES.has(bus) and not allowed.has(bus):
		out.errors.append("%s.bus: a %s. cue plays on %s, not %s" % [cctx, prefix, " or ".join(PackedStringArray(allowed)), bus])
	var files: Variant = c.get("files")
	if typeof(files) == TYPE_ARRAY:
		var arr: Array = files
		if arr.is_empty() or arr.size() > MAX_FILES:
			out.errors.append("%s.files: 1 to %d variants (got %d)" % [cctx, MAX_FILES, arr.size()])
		var i := 0
		for f: Variant in arr:
			var fctx := "%s.files[%d]" % [cctx, i]
			i += 1
			if typeof(f) != TYPE_STRING:
				continue
			var path: String = f
			var want := ".wav" if SAMPLE_BUSES.has(bus) else ".ogg"
			if not path.begins_with("res://"):
				out.errors.append("%s: '%s' must be a res:// path" % [fctx, path])
			elif not path.ends_with(want):
				out.errors.append("%s: '%s' on the %s bus must be %s (decision 2: WAV samples on SFX and UI, Ogg streams on Music and Ambience)" % [
					fctx, path, bus, "a WAV" if want == ".wav" else "an Ogg"])
			elif not ResourceLoader.exists(path):
				out.errors.append("%s: file '%s' does not exist" % [fctx, path])
			elif want == ".wav":
				var e := AudioMath.manifest_entry(path)
				if not e.is_empty() and float(e.get("seconds", 0.0)) > SFX_MAX_S + 1e-6:
					out.errors.append("%s: '%s' is %.2f s, over the %.1f s of a sound effect (decision 2)" % [
						fctx, path, float(e.seconds), SFX_MAX_S])
	var far: Variant = c.get("far", "")
	if typeof(far) == TYPE_STRING and far != "":
		if RegEx.create_from_string(CUE_ID_REGEX).search(far) == null:
			out.errors.append("%s.far: '%s' is not a cue id" % [cctx, far])
		elif far == cue_id:
			out.errors.append("%s.far: a cue cannot be its own far variant" % cctx)
	var levels: Variant = c.get("levels")
	if typeof(levels) == TYPE_ARRAY:
		for lv: Variant in levels:
			if typeof(lv) == TYPE_STRING and lv != MIX.SANDBOX_LEVEL:
				out.refs.append({"ctx": cctx + ".levels", "id": lv, "type": "level"})


static func required_ids() -> Dictionary:
	return {}
