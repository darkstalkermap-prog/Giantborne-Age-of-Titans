extends TestSuite
## P23 (plan M6-M9 §3.5 tests, §2.5, §4.3): where the Valley's music and ambience come from.
## Every district of the Valley maps to exactly one audio region and so to a zone set and an
## ambience set (the mapping of §4.3); the title, the end screen, the campaign's end and the
## sandbox map to their sets and `loading` is silent; every level record maps to an audio region
## or is silent by decision (the silent list, data/audio/region_silent.json, or test content under
## data/test); the Ogre King has his set; and at run time Audio.region_at() finds each district's
## region at its centre and nothing outside the Valley's districts.

const VALLEY := "level.valley"
## §4.3: the district -> [music set, ambience set] of the Valley.
const DISTRICTS := {
	"hollow": ["music.valley_calm", "ambience.meadow"],
	"village": ["music.valley_calm", "ambience.village"],
	"forest": ["music.valley_wild", "ambience.forest"],
	"quarry": ["music.valley_wild", "ambience.stone"],
	"barrow": ["music.valley_ancient", "ambience.stone"],
	"ruins": ["music.valley_ancient", "ambience.stone"],
	"kingsfall": ["music.valley_ancient", "ambience.stone"],
}
## Context -> [music set, ambience set] ("" = none); `loading` is silent by decision.
const CONTEXTS := {
	"title": ["music.title", ""],
	"end": ["music.end", ""],
	"campaign_end": ["music.campaign_end", ""],
	"sandbox": ["music.valley_calm", "ambience.sandbox"],
}
const SILENT_CONTEXTS := ["loading"]
const RegionSchema := preload("res://scripts/core/schemas/audio_region_schema.gd")


func after_each() -> void:
	Audio.enable_for_tests(false)


## The zone regions (no context, no boss, no silent list) of a level whose districts name `district`.
static func regions_for(level: String, district: String) -> Array:
	var out: Array = []
	for rec: Dictionary in GameData.records_of_type("audio_region"):
		if str(rec.get("level", "")) != level or str(rec.get("context", "")) != "" or str(rec.get("boss", "")) != "":
			continue
		if (rec.get("districts", []) as Array).has(district):
			out.append(rec)
	return out


static func _is_type(id: String, type: String) -> bool:
	return str(GameData.get_record(id).get("type", "")) == type


func test_every_valley_district_maps_to_its_sets() -> void:
	var level := GameData.get_record(VALLEY)
	var districts: Array = level.get("districts", [])
	assert_eq(districts.size(), DISTRICTS.size(), "the Valley's seven districts")
	for d: Dictionary in districts:
		var id := str(d.id)
		var found := regions_for(VALLEY, id)
		assert_eq(found.size(), 1, "%s is in exactly one audio region (%d)" % [id, found.size()])
		if found.is_empty() or not DISTRICTS.has(id):
			assert_true(DISTRICTS.has(id), "%s is a district of the plan's table" % id)
			continue
		var rec: Dictionary = found[0]
		assert_eq(str(rec.music), str(DISTRICTS[id][0]), "%s plays %s" % [id, DISTRICTS[id][0]])
		assert_eq(str(rec.ambience), str(DISTRICTS[id][1]), "%s sounds like %s" % [id, DISTRICTS[id][1]])
		assert_true(_is_type(str(rec.music), "music_set"), "%s is a music set" % rec.music)
		assert_true(_is_type(str(rec.ambience), "ambience_set"), "%s is an ambience set" % rec.ambience)
	# each zone set has three melody variants and the region's combat intro
	for set_id: String in ["music.valley_calm", "music.valley_wild", "music.valley_ancient"]:
		var rec := GameData.get_record(set_id)
		assert_eq(((rec.get("melody", {}) as Dictionary).get("variants", []) as Array).size(), 3,
			"%s rotates three melody variants" % set_id)
		var intro := str(rec.get("combat_intro", ""))
		assert_true(intro.begins_with("mus.stinger.combat_"), "%s has its combat intro (%s)" % [set_id, intro])
		assert_true(_bank_has(intro), "%s is a cue" % intro)
		for stem: String in ["pulse", "drums", "brass"]:
			assert_true((rec.stems as Dictionary).has(stem), "%s shares the %s stem" % [set_id, stem])


static func _bank_has(cue_id: String) -> bool:
	for bank: Dictionary in GameData.records_of_type("audio_bank"):
		if (bank.get("cues", {}) as Dictionary).has(cue_id):
			return true
	return false


func test_contexts_and_the_boss_map_to_their_sets() -> void:
	for context: String in CONTEXTS:
		var rec: Dictionary = Audio.context_region(context)
		assert_false(rec.is_empty(), "the %s context has an audio region" % context)
		assert_eq(str(rec.get("music", "")), str(CONTEXTS[context][0]), "%s plays %s" % [context, CONTEXTS[context][0]])
		assert_eq(str(rec.get("ambience", "")), str(CONTEXTS[context][1]), "%s's ambience" % context)
		assert_true(_is_type(str(rec.music), "music_set"), "%s is a music set" % rec.music)
	for context: String in SILENT_CONTEXTS:
		assert_true(Audio.context_region(context).is_empty(), "%s maps to nothing" % context)
		assert_true(Audio.silent_contexts().has(context), "%s is silent by decision" % context)
	var king: Dictionary = Audio.boss_region("enemy.ogre_king")
	assert_eq(str(king.get("music", "")), "music.boss_ogre_king", "the Ogre King has his set")
	var boss_set := GameData.get_record("music.boss_ogre_king")
	assert_eq(str(boss_set.get("frame", "")), "boss_104", "in its own frame")
	assert_eq(str(boss_set.get("intro", "")), "mus.stinger.boss_ogre_king", "after its intro stinger")
	assert_true(_bank_has("mus.stinger.boss_ogre_king"), "the intro is a cue")
	assert_true((boss_set.get("phase_layers", {}) as Dictionary).has("2"), "phase 2 adds a layer")
	assert_eq(int(boss_set.get("bpm", 0)), 104, "104 BPM")
	# every stinger the Valley can play by name is a cue (yield, rout, discovery and the world's
	# stingers come with the world's packages: none of their events fires in the Valley)
	for name: String in ["victory", "death", "prologue_end", "growth", "level_up", "quest", "quest_complete"]:
		assert_true(_bank_has("mus.stinger." + name), "mus.stinger.%s is a cue" % name)


func test_every_level_maps_to_a_region_or_is_silent() -> void:
	var silent_list := GameData.get_record("audio_region.silent")
	assert_eq(str(silent_list.get("type", "")), "audio_region", "the silent list is a record")
	assert_true(RegionSchema.is_silent_list(silent_list), "carrying the silent lists")
	for lv: String in Audio.SILENT_LEVELS:
		assert_true((silent_list.get("silent_levels", []) as Array).has(lv), "%s is in the silent list" % lv)
	var levels := GameData.records_of_type("level")
	assert_true(levels.size() >= 3, "the Valley and the test levels (%d)" % levels.size())
	for rec: Dictionary in levels:
		var id := str(rec.id)
		var mapped := false
		for region: Dictionary in GameData.records_of_type("audio_region"):
			if str(region.get("level", "")) == id:
				mapped = true
				break
		var silent := Audio.is_silent_level(id)
		assert_true(mapped != silent, "%s maps to an audio region or is silent by decision (mapped %s, silent %s)" % [
			id, mapped, silent])
		if str(GameData.record_paths.get(id, "")).begins_with(AudioDirector.TEST_DATA_DIR):
			assert_true(silent, "%s is test content and silent" % id)
	assert_false(Audio.is_silent_level(VALLEY), "the Valley is not silent")


func test_region_at_finds_each_districts_region_at_run_time() -> void:
	Audio.enable_for_tests()
	var lv := LevelRoot.new()
	lv.name = "ValleyZones"
	lv.level_id = VALLEY
	add_child(lv)
	Audio.is_ready()   # detects the level (its samples queue; nothing here needs them)
	assert_eq(Audio.level_id, VALLEY, "the Valley is the level")
	for d: Dictionary in GameData.get_record(VALLEY).districts:
		var lo := Vector3(float(d.min_m[0]), 0.0, float(d.min_m[2]))
		var hi := Vector3(float(d.max_m[0]), 0.0, float(d.max_m[2]))
		var centre := (lo + hi) * 0.5
		var rec := Audio.region_at(centre)
		assert_eq(str(rec.get("music", "")), str(DISTRICTS[str(d.id)][0]), "the centre of %s plays its set" % d.id)
		assert_eq(str(rec.get("ambience", "")), str(DISTRICTS[str(d.id)][1]), "and has its ambience")
	assert_true(Audio.region_at(Vector3(5000, 0, 5000)).is_empty(), "nothing outside the districts")
	lv.queue_free()
	await get_tree().process_frame
