extends TestSuite
## SaveSlots (plan §2.9, §15 "corrupt save -> backup with a message"): the round trip keeps types
## (ints are ints, ancestry and level_exempt kept), a corrupt or invalid main file falls back to
## the backup with a clear message, a newer-version file is refused and kept aside without ever
## becoming the backup, unknown ids are dropped with a message, and validate() names problems.
## Every test works in user://test_saves/ (GameSession.reset_for_tests points SaveSlots there).

const TEST_PATH := "user://test_saves/valley_1.json"


func before_each() -> void:
	SaveSlots.path_override = TEST_PATH
	SaveSlots.delete_slot(true)


func after_each() -> void:
	SaveSlots.delete_slot(true)
	SaveSlots.path_override = TEST_PATH


## A complete save document as GameSession writes it.
func _doc(health := 695.0, respawn := "valley.shrine.grove") -> Dictionary:
	var c := CharacterState.new_game(GameData.get_record("progression.default"), GameData.get_record("player.giant"))
	c.level = 3
	c.xp = 268
	c.unspent_attribute_points = 3
	c.talent_points = 2
	c.growth_stage = 2
	c.attributes.endurance = 13
	c.level_exempt = ["ability.stone_skin"]
	c.loadout.slots[2] = "ability.stone_skin"
	(c.known_abilities as Array).append("ability.stone_skin")
	c.resources = {"health": health, "stamina": 110.0, "essence": 102.0, "fury": 0.0}
	return {"schema_version": SaveSlots.SCHEMA_VERSION, "build_version": "0.2.0-m3", "saved_at_unix": 1793836800,
		"slot": SaveSlots.SLOT, "level": "level.valley",
		"checkpoint": {"respawn": respawn, "reason": "quest_stage"},
		"character": c,
		"world": {"schema_version": 2,
			"deltas": {"valley.hollow.fence_pen": {"destroyed": true, "damage_stage": 1, "health": 0.0, "loot_awarded": true},
				"valley.ruins.practice_gate": {"destroyed": false, "damage_stage": 1, "health": 96.0},
				"valley.forest.wolf_a1": {"killed": true}},
			"inventory": {"item.wood_scrap": 1},
			"flags": {"quest.main.stage": "hurl", "reward.tutorial.awaken": true}},
		"stats": {"deaths": 1, "checkpoint_loads": 1, "play_time_s": 512.4}}


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_paths() -> void:
	assert_eq(SaveSlots.path(), TEST_PATH, "the override wins")
	SaveSlots.path_override = ""
	assert_eq(SaveSlots.path(), "user://saves/valley_1.json", "the one slot (decision 14)")
	assert_eq(SaveSlots.rejected_path(2), "user://saves/valley_1.schema2.rejected.json", "where a newer save is kept")
	SaveSlots.path_override = TEST_PATH
	assert_false(SaveSlots.exists(), "no slot yet")
	var r := SaveSlots.read()
	assert_false(r.ok, "nothing to read")
	assert_eq(r.source, "none", "no source")


func test_round_trip_keeps_types_ancestry_and_level_exempt() -> void:
	var doc := _doc()
	var w := SaveSlots.write(doc)
	assert_true(w.ok, "written: %s" % w.message)
	assert_true(SaveSlots.exists(), "the slot exists")
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"), "no temp file left")
	var r := SaveSlots.read()
	assert_true(r.ok, "read back: %s" % r.message)
	assert_eq(r.source, "main", "from the main file")
	assert_eq(r.message, "", "no message for a clean file")
	var c: Dictionary = r.data.character
	assert_eq(c, CharacterState.normalize(doc.character), "the character dictionary is equal after the round trip")
	for key: String in ["level", "xp", "unspent_attribute_points", "talent_points", "growth_stage"]:
		assert_eq(typeof(c[key]), TYPE_INT, "%s is an int" % key)
	assert_eq(c.level, 3, "level")
	assert_eq(c.xp, 268, "xp")
	assert_eq(typeof(c.attributes.endurance), TYPE_INT, "attributes are ints")
	assert_eq(c.ancestry, "ancestry.neutral", "ancestry kept")
	assert_eq(c.level_exempt, ["ability.stone_skin"], "level_exempt kept")
	assert_eq(c.loadout.slots[2], "ability.stone_skin", "loadout kept")
	assert_near(float(c.resources.health), 695.0, 1e-6, "resources kept")
	assert_eq(r.data.checkpoint, {"respawn": "valley.shrine.grove", "reason": "quest_stage"}, "checkpoint kept")
	assert_eq(r.data.level, "level.valley", "level kept")
	assert_true(WorldState.from_save_dict(r.data.world), "the world part loads into WorldState")
	assert_eq(typeof(WorldState.get_delta("valley.ruins.practice_gate").damage_stage), TYPE_INT, "damage stages are ints")
	assert_near(float(WorldState.get_delta("valley.ruins.practice_gate").health), 96.0, 1e-6, "a cracked gate keeps its health")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "inventory")
	assert_eq(WorldState.get_flag("quest.main.stage"), "hurl", "flags")
	WorldState.clear()


func test_corrupt_main_recovers_from_the_backup() -> void:
	assert_true(SaveSlots.write(_doc(400.0)).ok, "first save")
	assert_true(SaveSlots.write(_doc(300.0)).ok, "second save (the first becomes the backup)")
	_write_text(TEST_PATH, "{ this is not json")
	var r := SaveSlots.read()
	assert_true(r.ok, "recovered")
	assert_eq(r.source, "backup", "from the backup")
	assert_near(float(r.data.character.resources.health), 400.0, 1e-6, "the previous valid copy")
	assert_true(str(r.message).contains("corrupt") and str(r.message).contains("Recovered"),
		"a clear message: %s" % r.message)


func test_invalid_content_also_falls_back_to_the_backup() -> void:
	assert_true(SaveSlots.write(_doc(400.0)).ok, "first save")
	assert_true(SaveSlots.write(_doc(300.0)).ok, "second save")
	_write_text(TEST_PATH, JSON.stringify({"schema_version": 1, "level": "level.valley",
		"checkpoint": {"respawn": ""}, "character": "not an object", "world": {"schema_version": 2}}))
	var r := SaveSlots.read()
	assert_true(r.ok, "recovered")
	assert_eq(r.source, "backup", "from the backup")
	assert_near(float(r.data.character.resources.health), 400.0, 1e-6, "the previous valid copy")
	assert_true(str(r.message).contains("invalid") and str(r.message).contains("Recovered"),
		"a clear message: %s" % r.message)
	DirAccess.remove_absolute(TEST_PATH + ".bak")
	var none := SaveSlots.read()
	assert_false(none.ok, "without a backup an invalid file does not load")
	assert_true(str(none.message).contains("invalid"), "and says why: %s" % none.message)


func test_future_version_is_rejected_kept_and_never_becomes_the_backup() -> void:
	assert_true(SaveSlots.write(_doc(400.0)).ok, "first save")
	assert_true(SaveSlots.write(_doc(300.0)).ok, "second save: backup = first")
	# P20: the build's own version is 2 (save schema 2), so "a newer build" writes SCHEMA_VERSION + 1.
	var future := SaveSlots.SCHEMA_VERSION + 1
	var newer := JSON.stringify({"schema_version": future, "note": "written by a newer build"})
	_write_text(TEST_PATH, newer)
	var r := SaveSlots.read()
	assert_eq(int(r.future_version), future, "the newer version is reported")
	var kept := SaveSlots.rejected_path(future)
	assert_eq(kept, "user://test_saves/valley_1.schema%d.rejected.json" % future, "kept beside the slot")
	assert_true(FileAccess.file_exists(kept), "the newer file is kept")
	assert_eq(FileAccess.get_file_as_string(kept), newer, "unchanged")
	assert_true(str(r.message).contains("newer") and str(r.message).contains("valley_1.schema%d.rejected.json" % future),
		"the message says so: %s" % r.message)
	assert_true(r.ok and r.source == "backup", "the older backup still loads")
	assert_near(float(r.data.character.resources.health), 400.0, 1e-6, "it is the first save")
	assert_true(SaveSlots.write(_doc(200.0)).ok, "a new checkpoint is written over the newer file")
	var bak := SaveIO.read_json(TEST_PATH + ".bak", SaveSlots.SCHEMA_VERSION)
	assert_true(bak.ok, "the backup is still loadable")
	assert_near(float(bak.data.character.resources.health), 400.0, 1e-6, "the backup was not overwritten by the newer file")
	assert_true(FileAccess.file_exists(kept), "the rejected copy is still there")
	assert_near(float(SaveSlots.read().data.character.resources.health), 200.0, 1e-6, "the new save reads")


func test_future_version_without_a_backup_does_not_load() -> void:
	_write_text(TEST_PATH, JSON.stringify({"schema_version": 5}))
	var r := SaveSlots.read()
	assert_false(r.ok, "not loaded")
	assert_eq(int(r.future_version), 5, "version 5 reported")
	assert_true(FileAccess.file_exists(SaveSlots.rejected_path(5)), "kept as schema5.rejected")
	assert_true(str(r.message).contains("newer version"), "clear message: %s" % r.message)


func test_unknown_ids_are_dropped_with_a_message() -> void:
	var doc := _doc()
	doc.character.loadout.slots[5] = "ability.not_real"
	(doc.character.known_abilities as Array).append("ability.not_real")
	doc.world.inventory["item.vanished"] = 2
	assert_true(SaveSlots.write(doc).ok, "written")
	var r := SaveSlots.read()
	assert_true(r.ok, "still loads")
	assert_eq(r.data.character.loadout.slots[5], "", "the unknown ability left its slot")
	assert_false((r.data.character.known_abilities as Array).has("ability.not_real"), "and the known list")
	assert_false((r.data.world.inventory as Dictionary).has("item.vanished"), "an unknown item is dropped")
	assert_eq(int(r.data.world.inventory["item.wood_scrap"]), 1, "known items stay")
	assert_true((r.dropped as PackedStringArray).has("ability.not_real") and (r.dropped as PackedStringArray).has("item.vanished"),
		"both are listed")
	assert_true(str(r.message).contains("ability.not_real"), "the message names them: %s" % r.message)


func test_validate_names_the_problems() -> void:
	assert_eq(SaveSlots.validate(_doc()), PackedStringArray(), "a full document is valid")
	var text := "\n".join(SaveSlots.validate({}))
	for want in ["schema_version", "level", "checkpoint.respawn", "character", "world"]:
		assert_true(text.contains(want), "an empty document misses %s" % want)
	var doc := _doc()
	doc.world.schema_version = 9
	doc.world.flags = []
	doc.checkpoint.respawn = 4
	doc.stats = "lots"
	var bad := "\n".join(SaveSlots.validate(doc))
	for want in ["world.schema_version", "world.flags", "checkpoint.respawn", "stats"]:
		assert_true(bad.contains(want), "reports %s (%s)" % [want, bad])
	doc = _doc()
	doc.schema_version = SaveSlots.SCHEMA_VERSION + 1   # P20: 2 is this build's own version now
	assert_true("\n".join(SaveSlots.validate(doc)).contains("schema_version"), "a newer document is not valid here")


func test_write_creates_the_folder_and_delete_removes_the_slot() -> void:
	SaveSlots.path_override = "user://test_saves/nested/deeper/valley_1.json"
	assert_true(SaveSlots.write(_doc()).ok, "the folders are created")
	assert_true(SaveSlots.write(_doc()).ok, "a second write makes a backup")
	assert_true(FileAccess.file_exists(SaveSlots.path() + ".bak"), "backup present")
	SaveSlots.delete_slot()
	assert_false(SaveSlots.exists(), "slot and backup removed")
	DirAccess.remove_absolute("user://test_saves/nested/deeper")
	DirAccess.remove_absolute("user://test_saves/nested")
	SaveSlots.path_override = TEST_PATH


func test_a_failed_write_reports_it() -> void:
	_write_text("user://test_saves/blocked", "a file where the folder should be")
	SaveSlots.path_override = "user://test_saves/blocked/valley_1.json"
	var w := SaveSlots.write(_doc())
	assert_false(w.ok, "the write fails")
	assert_true(str(w.message) != "", "with a message: %s" % w.message)
	DirAccess.remove_absolute("user://test_saves/blocked")
	SaveSlots.path_override = TEST_PATH
