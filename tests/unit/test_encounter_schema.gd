extends TestSuite
## P10a: the `encounter` and `level` record types (plan §2.8.3): the plan's examples validate,
## every field and semantic rule rejects bad values, and the GameData post-pass reports a spawn
## entity_id used by two encounters ("Duplicate spawn entity_id '…'"), a definition that is not
## an enemy or npc record, and a district its level does not have.

const TMP_DATA := "user://test_tmp_encounter_schema"
const TEST_SCENE := "res://scenes/test/director_test.tscn"

var _loaded_tmp := false


func after_each() -> void:
	_rm_tree(TMP_DATA)
	if _loaded_tmp:
		_loaded_tmp = false
		GameData.load_all(GameData.DATA_ROOT)


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


## The plan's encounter example (§2.8.3), pointed at records that exist on this branch.
func _encounter() -> Dictionary:
	return {"schema_version": 1, "id": "encounter.forest_wolves_a", "type": "encounter",
		"level": "level.director_test", "district": "west",
		"center_m": [-142, 0, 55], "activate_radius_m": 55, "deactivate_radius_m": 110, "leash_radius_m": 50,
		"alert_group": true, "requires_flags": [], "forbids_flags": [], "counts_toward_budget": true,
		"spawns": [{"entity_id": "valley.forest.wolf_a1", "definition": "enemy.wolf", "position_m": [-150, 0, 50],
			"yaw_deg": 90, "patrol": "valley.patrol.wolves_a", "faction": "", "commander": false,
			"ai_enabled": true, "persist_death": true, "loot_table": ""}]}


## The plan's level example (§2.8.3) with a scene that exists on this branch.
func _level() -> Dictionary:
	return {"schema_version": 1, "id": "level.valley", "type": "level", "display_name": "Valley of Broken Kings",
		"scene": TEST_SCENE, "start_checkpoint": "valley.shrine.hollow", "max_active_enemies": 12,
		"lod": {"near_m": 40, "mid_m": 90, "check_ticks": 30, "corpse_free_s": 6},
		"render": {"low": {"shadow_distance_m": 60, "scenery_visibility_end_m": 160, "msaa": 0},
			"medium": {"shadow_distance_m": 120, "scenery_visibility_end_m": 220, "msaa": 2}},
		"web_overrides": {"quality": "low", "ai_tier1_m": 30},
		"districts": [{"id": "hollow", "display_name": "Giant's Hollow", "min_m": [-200, 0, 100], "max_m": [-90, 0, 200]}]}


# --------------------------------------------------------------------------- examples

func test_the_plan_examples_validate() -> void:
	assert_true(DataValidator.RECORD_TYPES.has("encounter"), "encounter is a record type")
	assert_true(DataValidator.RECORD_TYPES.has("level"), "level is a record type")
	var r := _validate(_encounter())
	assert_eq(r.errors.size(), 0, "the encounter example validates: %s" % "\n".join(r.errors))
	var refs := (r.refs as Array).map(func(x: Dictionary) -> String: return "%s:%s" % [x.type, x.id])
	assert_true(refs.has("level:level.director_test"), "level is a reference to a level record")
	r = _validate(_level())
	assert_eq(r.errors.size(), 0, "the level example validates: %s" % "\n".join(r.errors))
	var minimal := {"schema_version": 1, "id": "level.minimal", "type": "level", "scene": TEST_SCENE,
		"start_checkpoint": "test.cp_a"}
	assert_eq(_validate(minimal).errors.size(), 0, "scene and start_checkpoint are all a level needs")
	var enc := {"schema_version": 1, "id": "encounter.minimal", "type": "encounter", "level": "level.x",
		"center_m": [0, 0, 0], "activate_radius_m": 10, "deactivate_radius_m": 20,
		"spawns": [{"entity_id": "test.min.a", "definition": "enemy.wolf", "position_m": [0, 0, 0]}]}
	assert_eq(_validate(enc).errors.size(), 0, "an encounter needs level, centre, two radii and spawns")
	for id in ["level.director_test", "encounter.director_test_wolves", "encounter.director_test_soldiers",
			"encounter.director_test_budget"]:
		assert_true(GameData.has_record(id), "shipped: %s" % id)


func test_encounter_field_errors() -> void:
	var e := _encounter()
	e["bogus"] = 1
	assert_true(_errors(e).contains("unknown key 'bogus'"), "unknown top-level key")
	e = _encounter()
	(e.spawns[0] as Dictionary)["hp"] = 5
	assert_true(_errors(e).contains("spawns[0]: unknown key 'hp'"), "unknown spawn key")
	for key in ["level", "center_m", "activate_radius_m", "deactivate_radius_m", "spawns"]:
		e = _encounter()
		e.erase(key)
		assert_true(_errors(e).contains("missing required key '%s'" % key), "%s is required" % key)
	for key in ["entity_id", "definition", "position_m"]:
		e = _encounter()
		(e.spawns[0] as Dictionary).erase(key)
		assert_true(_errors(e).contains("missing required key '%s'" % key), "spawn %s is required" % key)
	e = _encounter()
	e["activate_radius_m"] = 0
	assert_true(_errors(e).contains("activate_radius_m: must be > 0"), "activate radius > 0")
	e = _encounter()
	e["leash_radius_m"] = -1
	assert_true(_errors(e).contains("leash_radius_m: must be >= 0"), "leash >= 0 (0 = no leash)")
	e = _encounter()
	e["center_m"] = [1, 2]
	assert_true(_errors(e).contains("center_m: expected [x, y, z]"), "centre is a vector")
	e = _encounter()
	(e.spawns[0] as Dictionary)["yaw_deg"] = 400
	assert_true(_errors(e).contains("yaw_deg: must be <= 360"), "yaw range")
	e = _encounter()
	(e.spawns[0] as Dictionary)["commander"] = "yes"
	assert_true(_errors(e).contains("commander: expected true/false"), "commander is a bool")
	e = _encounter()
	(e.spawns[0] as Dictionary)["loot_table"] = "loot.raider"
	var refs := (_validate(e).refs as Array).map(func(x: Dictionary) -> String: return "%s:%s" % [x.type, x.id])
	assert_true(refs.has("loot_table:loot.raider"), "a loot_table is a reference to a loot_table record")


func test_encounter_semantic_errors() -> void:
	var e := _encounter()
	e["deactivate_radius_m"] = 55
	assert_true(_errors(e).contains("deactivate_radius_m must be greater than activate_radius_m"),
		"deactivate must exceed activate")
	e = _encounter()
	e["requires_flags"] = ["Bad Flag"]
	assert_true(_errors(e).contains("flag id 'Bad Flag' must be lowercase dotted form"), "requires_flags ids")
	e = _encounter()
	e["forbids_flags"] = ["world"]
	assert_true(_errors(e).contains("forbids_flags[0]: flag id 'world'"), "forbids_flags ids")
	e = _encounter()
	e["spawns"] = []
	assert_true(_errors(e).contains("spawns must list at least one member"), "at least one spawn")
	e = _encounter()
	(e.spawns[0] as Dictionary)["entity_id"] = "Wolf A1"
	assert_true(_errors(e).contains("id 'Wolf A1' must be lowercase dotted form"), "entity ids are dotted ids")
	e = _encounter()
	(e.spawns as Array).append((e.spawns[0] as Dictionary).duplicate(true))
	assert_true(_errors(e).contains("duplicate spawn entity_id 'valley.forest.wolf_a1' in this encounter"),
		"entity ids are unique within an encounter")
	e = _encounter()
	(e.spawns[0] as Dictionary)["patrol"] = "wolves a"
	assert_true(_errors(e).contains("spawns[0].patrol: id 'wolves a'"), "patrol route ids are dotted ids")
	e = _encounter()
	e["district"] = "Old Wood"
	assert_true(_errors(e).contains("district: 'Old Wood' must be a plain lowercase district id"), "district ids")


func test_level_errors() -> void:
	var l := _level()
	l.erase("scene")
	assert_true(_errors(l).contains("missing required key 'scene'"), "scene is required")
	l = _level()
	l["scene"] = "res://levels/valley.tscn"
	assert_true(_errors(l).contains("must be a res://scenes/....tscn path"), "scene path form")
	l = _level()
	l["scene"] = "res://scenes/world/no_such_level.tscn"
	assert_true(_errors(l).contains("does not exist (run tools/build_scenes)"), "the scene must exist")
	l = _level()
	l["start_checkpoint"] = "Start"
	assert_true(_errors(l).contains("start_checkpoint: id 'Start'"), "start checkpoint id")
	l = _level()
	(l.lod as Dictionary)["near_m"] = 100
	assert_true(_errors(l).contains("lod.near_m must be <= lod.mid_m"), "near <= mid")
	l = _level()
	(l.lod as Dictionary).erase("check_ticks")
	assert_true(_errors(l).contains("missing required key 'check_ticks'"), "lod keys are required")
	l = _level()
	(l.render as Dictionary)["ultra"] = {"msaa": 0}
	assert_true(_errors(l).contains("unknown key 'ultra'"), "only the low and medium presets")
	l = _level()
	((l.render as Dictionary).low as Dictionary)["msaa"] = 3
	assert_true(_errors(l).contains("render.low.msaa: must be one of"), "msaa 0, 2, 4 or 8")
	l = _level()
	(l.web_overrides as Dictionary)["quality"] = "high"
	assert_true(_errors(l).contains("unknown value 'high'"), "web quality enum")
	l = _level()
	l["max_active_enemies"] = 0
	assert_true(_errors(l).contains("max_active_enemies: must be >= 1"), "a budget of at least one")
	l = _level()
	(l.districts as Array).append({"id": "hollow", "min_m": [0, 0, 0], "max_m": [1, 0, 1]})
	assert_true(_errors(l).contains("duplicate district id 'hollow'"), "district ids are unique")
	l = _level()
	((l.districts as Array)[0] as Dictionary)["max_m"] = [-300, 0, 200]
	assert_true(_errors(l).contains("min_m must not exceed max_m"), "district rectangles are ordered")
	l = _level()
	((l.districts as Array)[0] as Dictionary)["id"] = "giants.hollow"
	assert_true(_errors(l).contains("must be a plain lowercase word"), "district ids are plain words")


# --------------------------------------------------------------------------- cross-record checks

func test_cross_record_checks() -> void:
	var module: Variant = DataValidator.SCHEMAS["encounter"]
	var level := _level()
	level["id"] = "level.test"
	var a := _encounter()
	a["id"] = "encounter.test_a"
	a["level"] = "level.test"
	a["district"] = "hollow"
	var b := _encounter()
	b["id"] = "encounter.test_b"
	b["level"] = "level.test"
	b["district"] = "barrow"
	(b.spawns as Array).append({"entity_id": "valley.forest.sword", "definition": "weapon.club", "position_m": [0, 0, 0]})
	(b.spawns as Array).append({"entity_id": "valley.forest.ghost", "definition": "enemy.ghost", "position_m": [0, 0, 0]})
	var records := {"level.test": level, "encounter.test_a": a, "encounter.test_b": b,
		"enemy.wolf": GameData.get_record("enemy.wolf"), "weapon.club": GameData.get_record("weapon.club")}
	var errs := "\n".join(module.cross_record_errors(records, {"encounter.test_b": "b.json"}))
	assert_true(errs.contains("b.json (encounter.test_b).spawns[0]: Duplicate spawn entity_id 'valley.forest.wolf_a1' (also spawned by encounter.test_a)"),
		"a spawn id in two encounters: %s" % errs)
	assert_true(errs.contains("'weapon.club' is a weapon, expected an enemy or npc record"), "a weapon is no definition")
	assert_true(errs.contains("missing reference 'enemy.ghost' (expected an enemy or npc record)"), "a missing definition")
	assert_true(errs.contains("district 'barrow' is not a district of level.test"), "an unknown district")
	assert_false(errs.contains("encounter.test_a (encounter.test_a)"), "the first encounter is fine")
	var clean := {"level.test": level, "encounter.test_a": a, "enemy.wolf": GameData.get_record("enemy.wolf")}
	assert_eq(module.cross_record_errors(clean).size(), 0, "a valid set has no errors")


func test_post_pass_reports_duplicates_and_bad_definitions() -> void:
	_rm_tree(TMP_DATA)
	for id in ["level.director_test", "enemy.wolf", "weapon.wolf_jaws", "ability.wolf_bite", "ability.wolf_lunge",
			"item.wood_scrap", "encounter.director_test_wolves"]:
		_write(id.replace(".", "_") + ".json", GameData.get_record(id))
	var copy: Dictionary = (GameData.get_record("encounter.director_test_wolves") as Dictionary).duplicate(true)
	copy["id"] = "encounter.director_test_copy"
	(copy.spawns[1] as Dictionary)["definition"] = "item.wood_scrap"
	(copy.spawns[2] as Dictionary)["entity_id"] = "test.director.wolf_9"
	_write("copy.json", copy)
	_loaded_tmp = true
	GameData.load_all(TMP_DATA, false)
	var errs := "\n".join(GameData.errors)
	assert_true(errs.contains("Duplicate spawn entity_id 'test.director.wolf_1'"), "the post-pass reports a shared id")
	assert_true(errs.contains("Duplicate spawn entity_id 'test.director.wolf_2'"), "every shared id")
	assert_false(errs.contains("'test.director.wolf_9'"), "not the unique one")
	assert_true(errs.contains("'item.wood_scrap' is a item, expected an enemy or npc record"), "and the bad definition")
	assert_eq(GameData.errors.size(), 3, "nothing else: %s" % errs)
	assert_false(GameData.is_valid(), "the game would refuse to start")


func _write(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DATA)
	var f := FileAccess.open(TMP_DATA.path_join(file_name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for sub in dir.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
