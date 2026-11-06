extends TestSuite
## Save schema 2 (P20; plan M6-M9 §2.6, decision 16): SaveSlots.migrate() brings every schema 1 save
## up to 2 - the five fixtures written by the Valley bot (the four completions and a save before
## the crown, tests/fixtures/saves/) migrate, validate and Continue into the character they held
## plus the new defaults (talents [], ancestry_chosen false), the progress block and the respawn's
## position from the Valley's index; a schema 2 save round-trips (the tracked quest included); a
## schema 3 save is refused and kept aside; a damaged main file with a schema 1 backup loads the
## migrated backup and says so; an older valid main file still becomes the backup.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const FIXTURES := ["v1_force_complete", "v1_help_cache_complete", "v1_help_ogre_complete",
	"v1_intimidate_complete", "v1_pre_crown"]
const RESPAWN := "valley.cp.barrow_gap"


func before_each() -> void:
	WorldState.clear()


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	WorldState.clear()


func _fixture(fixture_name: String) -> Dictionary:
	var r := JsonIO.read_file(FIXTURE_DIR + fixture_name + ".json")
	assert_true(r.ok, "fixture %s reads" % fixture_name)
	return r.data if r.ok else {}


func _fixture_text(fixture_name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURE_DIR + fixture_name + ".json")


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _valley_index() -> WorldIndex:
	var idx := WorldIndex.for_level("level.valley")
	assert_true(idx != null, "the Valley has its world index")
	return idx


# --------------------------------------------------------------------------- the fixtures

func test_the_fixtures_are_the_bot_runs_schema_1_saves() -> void:
	for f: String in FIXTURES:
		var doc := _fixture(f)
		assert_eq(int(doc.get("schema_version", 0)), 1, "%s is a schema 1 save" % f)
		assert_eq(str(doc.get("level", "")), "level.valley", "%s is in the Valley" % f)
		assert_false(doc.has("progress"), "%s has no progress block yet" % f)
		assert_false((doc.character as Dictionary).has("talents"), "%s's character has no talents yet" % f)
		var complete := f != "v1_pre_crown"
		assert_eq(QuestConditions.truthy((doc.world.flags as Dictionary).get("slice.completed")), complete,
			"%s %s the slice" % [f, "completed" if complete else "did not complete"])


func test_every_fixture_migrates_and_validates_with_the_new_defaults() -> void:
	var idx := _valley_index()
	var spawn := idx.spawn_transform(RESPAWN)
	assert_true(spawn.origin.is_finite(), "the index knows the fixtures' respawn")
	for f: String in FIXTURES:
		var doc := _fixture(f)
		var before := doc.duplicate(true)
		var m := SaveSlots.migrate(doc)
		assert_eq(doc, before, "%s: migrate works on a copy" % f)
		assert_eq(int(m.schema_version), 2, "%s: schema 2" % f)
		assert_eq(SaveSlots.validate(m), PackedStringArray(), "%s: the migrated save validates" % f)
		assert_true(SaveSlots.loads(doc), "%s: SaveSlots.loads accepts the schema 1 file" % f)
		var expected: Dictionary = (doc.character as Dictionary).duplicate(true)
		expected["talents"] = []
		expected["ancestry_chosen"] = false
		assert_eq(m.character, expected, "%s: the character is the original plus talents [] and ancestry_chosen false" % f)
		assert_eq(m.world, doc.world, "%s: the world block is untouched (already its own schema 2)" % f)
		var complete := QuestConditions.truthy((doc.world.flags as Dictionary).get("slice.completed"))
		assert_eq(m.progress, {"prologue_complete": complete, "world_entered": false,
			"levels_visited": ["level.valley"], "tracked_quest": ""}, "%s: the progress block" % f)
		var cp: Dictionary = m.checkpoint
		assert_eq(str(cp.respawn), RESPAWN, "%s: the respawn is kept" % f)
		assert_true(cp.has("position") and cp.has("yaw"), "%s: the respawn's position and yaw from the index" % f)
		if cp.has("position"):
			var p := Vector3(float(cp.position[0]), float(cp.position[1]), float(cp.position[2]))
			assert_true(p.is_equal_approx(spawn.origin), "%s: at the index position %s (got %s)" % [f, spawn.origin, p])
			assert_near(float(cp.yaw), spawn.basis.get_euler().y, 1e-4, "%s: facing the index yaw" % f)
	# A save whose ancestry was chosen keeps that fact.
	var chosen := _fixture("v1_force_complete")
	chosen.character.ancestry = "ancestry.chosen_in_a_later_build"
	assert_true(bool(SaveSlots.migrate(chosen).character.ancestry_chosen), "a non-neutral ancestry counts as chosen")


func test_every_fixture_continues_into_its_character() -> void:
	GameSession.persist = true
	for f: String in FIXTURES:
		var doc := _fixture(f)
		_write_text(SaveSlots.path(), _fixture_text(f))
		var r := GameSession.continue_valley()
		assert_true(r.ok, "%s: Continue works (%s)" % [f, r.message])
		assert_eq(str(r.message), "", "%s: nothing dropped, nothing recovered" % f)
		assert_eq(GameSession.level_id, "level.valley", "%s: in the Valley" % f)
		assert_eq(GameSession.respawn_id, RESPAWN, "%s: at its waystone" % f)
		assert_eq(GameSession.scene_reloads.back(), "continue", "%s: a reload into the save" % f)
		var c: Dictionary = GameSession.character
		var original: Dictionary = doc.character
		for key: String in original:
			assert_true(c.has(key), "%s: the character keeps %s" % [f, key])
		assert_eq(c.size(), original.size() + 2, "%s: plus exactly the two new keys" % f)
		assert_eq(c, CharacterState.normalize(original), "%s: the loaded character is the original's" % f)
		assert_eq(c.get("talents"), [], "%s: no talents" % f)
		assert_eq(c.get("ancestry_chosen"), false, "%s: no ancestry chosen" % f)
		for key: String in ["level", "xp", "growth_stage", "unspent_attribute_points", "talent_points"]:
			assert_eq(int(c[key]), int(original[key]), "%s: %s" % [f, key])
		assert_eq(c.loadout.slots, original.loadout.slots, "%s: the loadout" % f)
		assert_eq(c.resources, original.resources, "%s: the resources exactly (a Continue has no floor)" % f)
		assert_eq(CharacterState.validate(c), PackedStringArray(), "%s: a valid character" % f)
		for item: String in (doc.world.inventory as Dictionary):
			assert_eq(WorldState.count_of(item), int(doc.world.inventory[item]), "%s: %s in the inventory" % [f, item])
		assert_eq(GameSession.progress.prologue_complete, f != "v1_pre_crown", "%s: the prologue's state" % f)
		SaveSlots.delete_slot()


# --------------------------------------------------------------------------- schema 2

func test_a_schema_2_save_round_trips_with_its_tracked_quest() -> void:
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = "level.valley"
	GameSession.character = CharacterState.new_game(GameData.get_record("progression.default"),
		GameData.get_record("player.giant"))
	GameSession.respawn_id = "valley.shrine.grove"
	GameSession.progress = GameSession.default_progress()
	GameSession.progress.tracked_quest = "quest.village"
	GameSession.progress.levels_visited = ["level.valley"]
	WorldState.set_flag("test.p20.round_trip", 7)
	WorldState.add_item("item.iron_ingot", 2, "test")
	var doc := GameSession.snapshot_document("test")
	assert_eq(int(doc.schema_version), 2, "a checkpoint document is schema 2")
	assert_eq(str(doc.progress.tracked_quest), "quest.village", "it holds the tracked quest")
	var grove := _valley_index().spawn_transform("valley.shrine.grove")
	var pos := Vector3(float(doc.checkpoint.position[0]), float(doc.checkpoint.position[1]), float(doc.checkpoint.position[2]))
	assert_true(pos.is_equal_approx(grove.origin), "and the respawn's index position")
	assert_true(SaveSlots.write(doc).ok, "written")
	assert_true(FileAccess.get_file_as_string(SaveSlots.path()).contains("\"schema_version\": 2"),
		"schema 2 on disk")
	var r := SaveSlots.read()
	assert_true(r.ok and str(r.source) == "main", "read back from the main file")
	assert_eq(r.data.progress, doc.progress, "the progress block round-trips")
	assert_eq(r.data.character, doc.character, "the character round-trips")
	assert_eq(str(r.data.checkpoint.respawn), "valley.shrine.grove", "the respawn")
	assert_near(float(r.data.checkpoint.yaw), float(doc.checkpoint.yaw), 1e-6, "the yaw")
	WorldState.clear()
	GameSession.progress = {}
	GameSession.respawn_id = ""
	GameSession.persist = true
	var c := GameSession.continue_valley()
	assert_true(c.ok, "Continue: %s" % c.message)
	assert_eq(str(GameSession.progress.tracked_quest), "quest.village", "the tracked quest is back")
	assert_eq(GameSession.progress.levels_visited, ["level.valley"], "and the levels visited")
	assert_eq(int(WorldState.get_flag("test.p20.round_trip")), 7, "the flags")
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "the inventory")
	assert_eq(GameSession.respawn_id, "valley.shrine.grove", "the respawn")
	assert_eq(SaveSlots.migrate(r.data), r.data, "a schema 2 document migrates to itself")


func test_a_schema_3_save_is_refused_and_kept() -> void:
	var future := _fixture("v1_force_complete")
	future.schema_version = 3
	future["a_later_key"] = {"from": "a newer build"}
	var text := JSON.stringify(future, "\t")
	_write_text(SaveSlots.path(), text)
	var r := SaveSlots.read()
	assert_false(r.ok, "a schema 3 save does not load in this build")
	assert_eq(int(r.future_version), 3, "its version is reported")
	assert_true(str(r.message).contains("newer version"), "with a clear message: %s" % r.message)
	var kept := SaveSlots.rejected_path(3)
	assert_true(FileAccess.file_exists(kept), "it is kept as %s" % kept.get_file())
	assert_eq(FileAccess.get_file_as_string(kept), text, "unchanged")
	assert_true(FileAccess.file_exists(SaveSlots.path()), "the main file is not deleted")
	assert_eq(SaveSlots.migrate(future), future, "migrate leaves a newer document alone")
	# With a schema 1 backup, the backup loads (migrated) and the newer file stays kept.
	_write_text(SaveSlots.path() + ".bak", _fixture_text("v1_pre_crown"))
	r = SaveSlots.read()
	assert_true(r.ok and str(r.source) == "backup", "the backup loads")
	assert_eq(int(r.data.schema_version), 2, "migrated to schema 2")
	assert_false(str(r.message).begins_with(SaveSlots.RECOVERED_TEXT), "a newer file is not called damaged: %s" % r.message)
	assert_true(str(r.message).contains("newer version") and str(r.message).contains(kept.get_file()),
		"the message says what happened: %s" % r.message)


func test_a_damaged_schema_2_main_file_falls_back_to_the_migrated_schema_1_backup() -> void:
	GameSession.persist = true
	_write_text(SaveSlots.path() + ".bak", _fixture_text("v1_help_cache_complete"))
	# 1. A main file that is not JSON at all (a write cut short).
	_write_text(SaveSlots.path(), "{\"schema_version\": 2, \"level\": \"level.val")
	var r := SaveSlots.read()
	assert_true(r.ok, "the backup loads")
	assert_eq(str(r.source), "backup", "from the backup")
	assert_eq(int(r.data.schema_version), 2, "migrated")
	assert_eq(r.data.character.talents, [], "with the new character keys")
	assert_true(bool(r.data.progress.prologue_complete), "and its progress")
	assert_true(str(r.message).begins_with(SaveSlots.RECOVERED_TEXT), "the message leads with the recovery: %s" % r.message)
	assert_true(str(r.message).contains("corrupt"), "and says why: %s" % r.message)
	# 2. A main file that parses but is not a valid save (its character is gone).
	var broken := SaveSlots.migrate(_fixture("v1_force_complete"))
	broken.erase("character")
	_write_text(SaveSlots.path(), JSON.stringify(broken))
	r = SaveSlots.read()
	assert_true(r.ok and str(r.source) == "backup", "the schema 1 backup again")
	assert_true(str(r.message).begins_with(SaveSlots.RECOVERED_TEXT) and str(r.message).contains("invalid"),
		"an invalid main file is named: %s" % r.message)
	var c := GameSession.continue_valley()
	assert_true(c.ok, "Continue uses the recovered save")
	assert_true(GameSession.last_load_message.begins_with(SaveSlots.RECOVERED_TEXT),
		"and keeps the message for the title and the HUD: %s" % GameSession.last_load_message)
	assert_eq(int(GameSession.character.xp), int(_fixture("v1_help_cache_complete").character.xp),
		"the backup's character")


func test_an_older_valid_main_file_becomes_the_backup() -> void:
	_write_text(SaveSlots.path(), _fixture_text("v1_pre_crown"))
	var doc := SaveSlots.migrate(_fixture("v1_force_complete"))
	assert_true(SaveSlots.write(doc).ok, "a schema 2 checkpoint over a schema 1 main file")
	var bak := JsonIO.read_file(SaveSlots.path() + ".bak")
	assert_true(bak.ok, "the backup exists")
	assert_eq(int(bak.data.get("schema_version", 0)) if bak.ok else 0, 1,
		"the valid schema 1 file became the backup unchanged (it migrates when it is read)")
	var r := SaveSlots.read()
	assert_true(r.ok and str(r.source) == "main", "the new main file loads")
	assert_true(bool(r.data.progress.prologue_complete), "it is the completed save")
