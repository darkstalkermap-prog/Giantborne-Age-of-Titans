extends TestSuite
## P19 (plan M6-M9 §2.5, §2.15): the five audio record types - the shipped records validate, and
## each module refuses unknown keys, bad buses, an Ogg on the SFX bus, a WAV on the Music bus,
## stems whose length is not the set's loop, a stem shared across frames, and the other mistakes
## its rules name. The audio types are registered right after "progression" (§1.6).

const BED := "res://assets/audio/placeholder/bed.ogg"
const TONE := "res://assets/audio/placeholder/tone_mid.wav"
const AUDIO_TYPES := ["audio_bank", "audio_mix", "music_set", "ambience_set", "audio_region"]


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	var r := _validate(rec)
	var refs := DataValidator.validate_references(GameData.records, r.refs)
	return "\n".join(r.errors + refs)


func _bank(cues: Dictionary) -> Dictionary:
	return {"schema_version": 1, "id": "audio_bank.test", "type": "audio_bank", "cues": cues}


func _music_set(overrides: Dictionary = {}) -> Dictionary:
	var rec := {"schema_version": 1, "id": "music.test", "type": "music_set", "bpm": 120, "beats_per_bar": 4,
		"bars": 4, "frame": "test_120", "stems": {"drone": BED, "melody_a": BED, "melody_b": BED},
		"layers": {"explore": {"drone": 0, "melody": -2}},
		"melody": {"variants": ["melody_a", "melody_b"], "segment_bars": 2, "play_loops": [1, 2],
			"rest_loops": [1, 3], "max_repeat": 2, "min_phrase_gap_s": 60},
		"silence": {"after_explore_s": 180, "length_s": [60, 120], "fade_s": 8},
		"combat_intro": "", "intro": "", "phase_layers": {}, "crossfade_bars": 2, "layer_fade_beats": 2}
	rec.merge(overrides, true)
	return rec


func test_audio_types_are_registered_after_progression() -> void:
	var keys: Array = DataValidator.SCHEMA_PATHS.keys()
	var at := keys.find("progression")
	assert_true(at >= 0, "progression is declared")
	for i in AUDIO_TYPES.size():
		assert_eq(str(keys[at + 1 + i]), AUDIO_TYPES[i], "%s follows progression (§1.6)" % AUDIO_TYPES[i])
		assert_true(DataValidator.RECORD_TYPES.has(AUDIO_TYPES[i]), "%s records can be validated" % AUDIO_TYPES[i])


func test_shipped_audio_records_validate() -> void:
	var found := 0
	for t: String in AUDIO_TYPES:
		for rec: Dictionary in GameData.records_of_type(t):
			found += 1
			assert_eq(_errors(rec), "", "%s validates" % rec.id)
	assert_true(found >= 2, "the placeholder bank and the default mix ship")
	assert_true(GameData.has_record("audio_mix.default"), "the default mix is a required record")
	assert_true(DataValidator.required_records().has("audio_mix.default"), "required by the engine")


func test_bank_rules() -> void:
	var good := {"files": [TONE], "bus": "UI", "spatial": false, "volume_db": -6.0, "priority": 50}
	assert_eq(_errors(_bank({"sfx.ui.test": good})), "", "a valid cue")
	var unknown := good.duplicate()
	unknown["loudness"] = 3
	assert_true(_errors(_bank({"sfx.ui.test": unknown})).contains("unknown key 'loudness'"), "unknown keys")
	var bad_bus := good.duplicate()
	bad_bus["bus"] = "Voices"
	assert_true(_errors(_bank({"sfx.ui.test": bad_bus})).contains("unknown value 'Voices'"), "bad buses")
	var ogg_sfx := {"files": [BED], "bus": "SFX"}
	assert_true(_errors(_bank({"sfx.hit.test": ogg_sfx})).contains("must be a WAV"), "an Ogg on the SFX bus")
	var wav_music := {"files": [TONE], "bus": "Music", "spatial": false}
	assert_true(_errors(_bank({"mus.stinger.test": wav_music})).contains("must be an Ogg"), "a WAV on the Music bus")
	assert_true(_errors(_bank({"sfx.hit.test": {"files": [TONE], "bus": "Music"}})).contains("a sfx. cue plays on"),
		"an sfx. cue on the Music bus")
	assert_true(_errors(_bank({"hit.test": good})).contains("must look like"), "cue ids start with sfx., amb. or mus.")
	assert_true(_errors(_bank({"sfx.ui.test": {"files": [TONE, TONE, TONE, TONE, TONE], "bus": "UI"}})).contains("1 to 4 variants"),
		"at most four variants")
	assert_true(_errors(_bank({"sfx.ui.test": {"files": [], "bus": "UI"}})).contains("1 to 4 variants"), "at least one")
	assert_true(_errors(_bank({"sfx.ui.test": {"files": ["res://assets/audio/none.wav"], "bus": "UI"}})).contains("does not exist"),
		"missing files")
	assert_true(_errors(_bank({"sfx.hit.test": {"files": [TONE], "class": "huge"}})).contains("unknown value 'huge'"),
		"classes come from the mix")
	assert_true(_errors(_bank({"sfx.hit.test": {"files": [TONE], "far": "sfx.hit.test"}})).contains("own far variant"),
		"a cue is not its own far variant")
	assert_true(_errors(_bank({"sfx.hit.test": {"files": [TONE], "levels": ["level.nowhere"]}})).contains("missing reference 'level.nowhere'"),
		"levels name level records")
	assert_eq(_errors(_bank({"sfx.hit.test": {"files": [TONE], "levels": ["sandbox", "level.valley"]}})), "",
		"or the sandbox")


func test_mix_rules() -> void:
	var mix: Dictionary = GameData.get_record("audio_mix.default").duplicate(true)
	assert_eq(_errors(mix), "", "the shipped mix")
	var no_class := mix.duplicate(true)
	(no_class.classes as Dictionary).erase("threat")
	assert_true(_errors(no_class).contains("missing class 'threat'"), "every class is defined")
	var bad_scaled := mix.duplicate(true)
	bad_scaled.classes.impact.scaled = "half"
	assert_true(_errors(bad_scaled).contains("must be true, false"), "scaled is a bool, sqrt or own")
	var bad_range := mix.duplicate(true)
	bad_range.classes.impact.max_m = 2
	assert_true(_errors(bad_range).contains("must be larger than unit_m"), "max beyond unit")
	var bad_material := mix.duplicate(true)
	bad_material.materials["prop.nowhere"] = "wood"
	assert_true(_errors(bad_material).contains("missing reference 'prop.nowhere'"), "materials name props")
	var bad_voice := mix.duplicate(true)
	bad_voice.voices["weapon.club"] = "human"
	assert_true(_errors(bad_voice).contains("must name an enemy, npc or player record"), "voices name actors")
	var bad_voice_value := mix.duplicate(true)
	bad_voice_value.voices["enemy.wolf"] = "dragon"
	assert_true(_errors(bad_voice_value).contains("unknown value 'dragon'"), "voices from the list of §4.1")
	var bad_surface := mix.duplicate(true)
	bad_surface.surfaces["level.valley"]["hollow"] = "lava"
	assert_true(_errors(bad_surface).contains("unknown value 'lava'"), "surfaces from the list")
	var bad_bus := mix.duplicate(true)
	bad_bus.bus_db["Voices"] = -3
	assert_true(_errors(bad_bus).contains("unknown key 'Voices'"), "bus levels name the four buses")


func test_music_set_rules() -> void:
	assert_eq(_errors(_music_set()), "", "a valid set: the 8 s bed is 4 bars at 120 BPM")
	assert_true(_errors(_music_set({"bars": 2})).contains("but the set's loop is"), "unequal stem lengths")
	assert_true(_errors(_music_set({"frame": "zone_96"})).contains("belongs to the frame test_120"),
		"a stem shared across frames")
	var bad_layer := _music_set()
	bad_layer.layers["combat"] = {"drums": 0}
	assert_true(_errors(bad_layer).contains("'drums' is not a stem"), "layers name stems")
	var by_name := _music_set()
	by_name.layers.explore["melody_a"] = 0
	assert_true(_errors(by_name).contains("plays through the 'melody' key"), "variants play through 'melody'")
	var bad_variant := _music_set()
	bad_variant.melody.variants = ["melody_a", "melody_z"]
	assert_true(_errors(bad_variant).contains("'melody_z' is not a stem"), "variants are stems")
	assert_true(_errors(_music_set({"stems": {"drone": "res://assets/audio/placeholder/tone_low.wav"}})).contains("res:// Ogg"),
		"stems are Ogg")
	var bad_segment := _music_set()
	bad_segment.melody.segment_bars = 3
	assert_true(_errors(bad_segment).contains("does not divide"), "segments divide the loop")
	var bad_rest := _music_set()
	bad_rest.melody.rest_loops = [3, 1]
	assert_true(_errors(bad_rest).contains("below min"), "ranges are [min, max]")
	assert_true(_errors(_music_set({"phase_layers": {"1": {"drone": 0}}})).contains("a phase number from 2 up"), "phase layers")
	assert_true(_errors(_music_set({"intro": "sfx.hit.x"})).contains("is not a mus. cue id"), "stingers are mus. cues")
	var no_explore := _music_set()
	no_explore.layers = {"combat": {"drone": 0}}
	assert_true(_errors(no_explore).contains("explore layer is required"), "explore is required")


func test_ambience_set_rules() -> void:
	var rec := {"schema_version": 1, "id": "ambience.test", "type": "ambience_set",
		"beds": [{"cue": "amb.bed_test", "volume_db": 0}], "spots": [{"cue": "amb.bird_a", "weight": 3, "flush": true}],
		"spot_interval_s": [4, 12], "spot_distance_m": [15, 40],
		"emitters": [{"cue": "amb.river", "level": "level.valley", "position_m": [106, 0, -20], "radius_m": 60}],
		"reactions": {"flush_radius_m": 40, "flush_s": 8, "flush_cue": "amb.birds_flush"}}
	assert_eq(_errors(rec), "", "a valid ambience set")
	var bad_cue := rec.duplicate(true)
	bad_cue.beds[0].cue = "sfx.hit.wood"
	assert_true(_errors(bad_cue).contains("is not an amb. cue id"), "beds are amb. cues")
	var bad_interval := rec.duplicate(true)
	bad_interval.spot_interval_s = [12, 4]
	assert_true(_errors(bad_interval).contains("needs 0 < min <= max"), "intervals")
	var bad_level := rec.duplicate(true)
	bad_level.emitters[0].level = "level.nowhere"
	assert_true(_errors(bad_level).contains("missing reference 'level.nowhere'"), "emitters name levels")
	var unknown := rec.duplicate(true)
	unknown["weather"] = "rain"
	assert_true(_errors(unknown).contains("unknown key 'weather'"), "unknown keys")


func test_audio_region_rules() -> void:
	var rec := {"schema_version": 1, "id": "audio_region.test", "type": "audio_region", "level": "level.valley",
		"districts": ["forest"], "regions": [], "pois": [], "context": "", "boss": "", "music": "", "ambience": "",
		"priority": 0}
	assert_true(_errors(rec).contains("names neither music nor ambience"), "a region plays something")
	var title := {"schema_version": 1, "id": "audio_region.title", "type": "audio_region", "context": "title",
		"level": "level.valley", "music": "music.nowhere"}
	var e := _errors(title)
	assert_true(e.contains("names no level, zone or boss"), "a context record is not tied to a level")
	assert_true(e.contains("missing reference 'music.nowhere'"), "music names a music_set")
	var no_level := {"schema_version": 1, "id": "audio_region.x", "type": "audio_region", "districts": ["forest"],
		"ambience": "ambience.nowhere"}
	assert_true(_errors(no_level).contains("needs a level"), "a zone record needs its level")
	var bad_context := {"schema_version": 1, "id": "audio_region.y", "type": "audio_region", "context": "menu",
		"music": "music.nowhere"}
	assert_true(_errors(bad_context).contains("unknown value 'menu'"), "contexts are title, end, campaign_end, sandbox")
	var boss := {"schema_version": 1, "id": "audio_region.boss", "type": "audio_region", "boss": "enemy.ogre_king",
		"music": "music.nowhere"}
	assert_false(_errors(boss).contains("needs a level"), "a boss record needs no zone")
	var bad_district := rec.duplicate(true)
	bad_district.districts = ["Old Wood"]
	bad_district.music = "music.nowhere"
	assert_true(_errors(bad_district).contains("must be a plain word"), "district ids")
