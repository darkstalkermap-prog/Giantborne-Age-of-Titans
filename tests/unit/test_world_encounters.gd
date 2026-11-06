extends TestSuite
## P24b (plan M6-M9 §2.8, decision 15): the encounter data of a streamed world - every encounter of a
## streamed level needs a leash unless it is an arena boss's (GameData's post-pass), a spawn entry's
## stage range (min_stage / max_stage: validated, and EncounterDirector.stage_allows), and the test
## world's own encounters keeping the rule.

const LEVEL := "level.test_world"


func _encounter(id: String, extra: Dictionary) -> Dictionary:
	var rec := {"schema_version": 1, "id": id, "type": "encounter", "level": LEVEL, "center_m": [0, 0, 0],
		"activate_radius_m": 40, "deactivate_radius_m": 80,
		"spawns": [{"entity_id": id.replace("encounter.", "p24b_unit.") + ".a", "definition": "enemy.soldier",
			"position_m": [0, 0, 0]}]}
	rec.merge(extra, true)
	return rec


## GameData's post-pass errors for the records as they are now (GameData.errors is put back).
func _post_pass_errors() -> PackedStringArray:
	var saved := GameData.errors.duplicate()
	GameData.errors.clear()
	GameData.call("_post_pass")
	var out := GameData.errors.duplicate()
	GameData.errors = saved
	return out


func _mentions(errors: PackedStringArray, id: String) -> bool:
	for e in errors:
		if e.contains(id) and e.contains("leash"):
			return true
	return false


func test_a_streamed_level_needs_leashed_encounters() -> void:
	assert_false(_mentions(_post_pass_errors(), "encounter.test_world"), "the test world's encounters all have leashes")
	TestFixtures.record_override("encounter.p24b_unit_no_leash", _encounter("encounter.p24b_unit_no_leash", {}))
	TestFixtures.record_override("encounter.p24b_unit_arena", _encounter("encounter.p24b_unit_arena", {"arena": true}))
	TestFixtures.record_override("encounter.p24b_unit_leashed", _encounter("encounter.p24b_unit_leashed", {"leash_radius_m": 40}))
	var valley := _encounter("encounter.p24b_unit_valley", {})
	valley["level"] = "level.valley"
	TestFixtures.record_override("encounter.p24b_unit_valley", valley)
	var errors := _post_pass_errors()
	assert_true(_mentions(errors, "encounter.p24b_unit_no_leash"), "a world encounter without a leash is an error")
	assert_false(_mentions(errors, "encounter.p24b_unit_arena"), "an arena boss's encounter needs none")
	assert_false(_mentions(errors, "encounter.p24b_unit_leashed"), "a leashed one is fine")
	assert_false(_mentions(errors, "encounter.p24b_unit_valley"), "the Valley is not streamed: no rule there")
	TestFixtures.restore_all()


func test_a_spawns_stage_range() -> void:
	var good := _encounter("encounter.p24b_unit_range", {"leash_radius_m": 40})
	(good.spawns[0] as Dictionary).merge({"min_stage": 3, "max_stage": 4})
	var r := DataValidator.validate_record(good, "unit")
	assert_eq(r.errors.size(), 0, "min_stage 3, max_stage 4 validates: %s" % [r.errors])
	var bad := _encounter("encounter.p24b_unit_range", {"leash_radius_m": 40, "arena": "yes"})
	(bad.spawns[0] as Dictionary).merge({"min_stage": 5, "max_stage": 4})
	r = DataValidator.validate_record(bad, "unit")
	var text := "\n".join(r.errors)
	assert_true(text.contains("min_stage"), "min_stage above max_stage is an error: %s" % text)
	assert_true(text.contains("arena"), "arena is a bool: %s" % text)
	var range_bad := _encounter("encounter.p24b_unit_range", {"leash_radius_m": 40})
	(range_bad.spawns[0] as Dictionary).merge({"max_stage": 11})
	assert_true("\n".join(DataValidator.validate_record(range_bad, "unit").errors).contains("max_stage"),
		"stages run 0-10")


func test_stage_allows() -> void:
	assert_true(EncounterDirector.stage_allows({}, 3), "no range: any stage")
	assert_true(EncounterDirector.stage_allows({"min_stage": 3}, 3), "at min_stage")
	assert_false(EncounterDirector.stage_allows({"min_stage": 3}, 2), "below it")
	assert_true(EncounterDirector.stage_allows({"max_stage": 2}, 2), "at max_stage")
	assert_false(EncounterDirector.stage_allows({"max_stage": 2}, 3), "above it")
	assert_true(EncounterDirector.stage_allows({"min_stage": 4, "max_stage": 6}, 5), "inside a range")
	assert_true(EncounterDirector.stage_allows({"min_stage": 4}, 0), "no player (stage 0): nothing is filtered")
	var wolves := GameData.get_record("encounter.test_world_wolves")
	var band := GameData.get_record("encounter.test_world_soldiers")
	assert_eq(int((wolves.spawns as Array)[4].get("max_stage", 0)), 2, "the wolf runt runs with stages 1-2 only")
	assert_eq(int((band.spawns as Array)[4].get("min_stage", 0)), 3, "the sergeant joins from stage 3")
