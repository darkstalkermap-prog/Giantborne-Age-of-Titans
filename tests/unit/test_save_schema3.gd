extends TestSuite
## A4: save schema 3 (SaveSlots._migrate_2_to_3, ExpansionState): every schema 2 save comes up to 3 with the
## expansion's fields - act 1, the seven armour slots empty, no cutscene seen, and the titans' and settlements'
## records from the flags A3 wrote (boss.stoneback.outcome / .defeated, discovered.stoneback_quarry,
## world.quarry.reopened, world.millford.*), which stay as they were; nothing else of the document changes. The
## fixtures are schema 2 saves the pre-A4 build wrote (tests/fixtures/saves/v2_a4_*.json: docs/systems/A4.md says
## how): a Valley save, a save in the middle of the world, a save with the campaign completed, and the mid-world
## save with Stoneback slain (its flags and loot set as his death sets them: derived, said so in A4.md). Each
## migrates, validates and Continues through the real Continue path (GameSession.continue_valley) into its
## character and its expansion state; its next checkpoint writes schema 3 and keeps the schema 2 file as the backup;
## a schema 4 file is refused and kept (test_save_migration); a titan this build does not know is dropped.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const V2_A4 := ["v2_a4_valley", "v2_a4_world_mid", "v2_a4_campaign_complete", "v2_a4_stoneback_slain"]


func before_each() -> void:
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()


func _fixture(fixture_name: String) -> Dictionary:
	var r := JsonIO.read_file(FIXTURE_DIR + fixture_name + ".json")
	assert_true(r.ok, "fixture %s reads" % fixture_name)
	return r.data if r.ok else {}


func _text(fixture_name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURE_DIR + fixture_name + ".json")


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_fixtures_are_schema_2_saves() -> void:
	var levels := {}
	for f: String in V2_A4:
		var doc := _fixture(f)
		assert_eq(int(doc.get("schema_version", 0)), 2, "%s is a schema 2 save" % f)
		for k: String in ExpansionState.KEYS:
			assert_false(doc.has(k), "%s has no %s yet" % [f, k])
		levels[f] = str(doc.get("level", ""))
	assert_eq(levels.v2_a4_valley, "level.valley", "one in the Valley")
	assert_eq(levels.v2_a4_world_mid, "level.world", "one in the world")
	assert_true(QuestConditions.truthy(_fixture("v2_a4_campaign_complete").world.flags.get("campaign.completed")),
		"one with the campaign completed")
	assert_eq(str(_fixture("v2_a4_stoneback_slain").world.flags.get("boss.stoneback.outcome", "")), "slain",
		"one with Stoneback slain")


func test_each_migrates_with_the_new_fields_and_nothing_else_changes() -> void:
	for f: String in V2_A4:
		var doc := _fixture(f)
		var before := doc.duplicate(true)
		var m := SaveSlots.migrate(doc)
		assert_eq(doc, before, "%s: migrate works on a copy" % f)
		assert_eq(int(m.schema_version), 3, "%s: schema 3" % f)
		assert_eq(SaveSlots.validate(m), PackedStringArray(), "%s: valid" % f)
		assert_true(SaveSlots.loads(doc), "%s: SaveSlots.loads accepts the schema 2 file (it may become the backup)" % f)
		assert_eq(int(m.act), 1, "%s: act one" % f)
		assert_eq((m.equipment.slots as Dictionary).keys(), ExpansionState.ARMOUR_SLOTS, "%s: the seven armour slots" % f)
		for s: String in ExpansionState.ARMOUR_SLOTS:
			assert_eq(str(m.equipment.slots[s]), "", "%s: %s empty" % [f, s])
		assert_eq(m.cinematics_seen, [], "%s: no cutscene seen (a Continue never plays one)" % f)
		var rest := m.duplicate(true)
		for k: String in ExpansionState.KEYS:
			rest.erase(k)
		rest.schema_version = before.schema_version
		assert_eq(rest, before, "%s: every other key exactly as the schema 2 file had it" % f)


func test_the_flags_become_the_titans_and_settlements_records() -> void:
	var valley := SaveSlots.migrate(_fixture("v2_a4_valley"))
	assert_eq(valley.titans, {}, "the Valley: no titan met")
	assert_eq(valley.settlements, {}, "nor any settlement")
	var slain := SaveSlots.migrate(_fixture("v2_a4_stoneback_slain"))
	var sb: Dictionary = slain.titans.get("titan.stoneback", {})
	assert_eq(str(sb.get("state", "")), "slain", "Stoneback slain, by boss.stoneback.outcome")
	assert_eq(int(sb.get("kills", 0)), 1, "one kill")
	assert_eq(sb.get("drops", []), ExpansionState.loot_of("loot.stoneback"), "his drops")
	assert_true((slain.settlements.get("poi.millford", {}) as Dictionary).get("flags", {}).get("quarry_reopened", false),
		"Millford's quarry reopened, by world.quarry.reopened")
	assert_eq(slain.world.flags.get("boss.stoneback.outcome"), "slain", "the flag itself stays")
	assert_true(QuestConditions.truthy(slain.world.flags.get("world.quarry.reopened")), "and so does the quarry's")
	# a hand-edited later key is kept as it is
	var edited := _fixture("v2_a4_world_mid")
	edited["act"] = 1
	edited["titans"] = {"titan.stoneback": {"state": "sighted"}}
	assert_eq(SaveSlots.migrate(edited).titans, {"titan.stoneback": {"state": "sighted"}}, "a key present is kept")


func test_each_continues_through_the_real_continue_path() -> void:
	GameSession.persist = true
	for f: String in V2_A4:
		var doc := _fixture(f)
		_write_text(SaveSlots.path(), _text(f))
		var r := GameSession.continue_valley()
		assert_true(r.ok, "%s: Continue works (%s)" % [f, r.message])
		# (B4: a save past the Valley is given the Ogre King's parts once, and says so: decision B4-1)
		assert_eq(str(r.message).replace(_owed_note(f), "").strip_edges(), "", "%s: nothing dropped, nothing recovered" % f)
		assert_eq(GameSession.level_id, str(doc.level), "%s: in its level" % f)
		assert_eq(GameSession.respawn_id, str(doc.checkpoint.respawn), "%s: at its respawn" % f)
		assert_eq(GameSession.character, CharacterState.normalize(doc.character), "%s: its character" % f)
		assert_eq(GameSession.expansion, ExpansionState.from_doc(SaveSlots.migrate(doc)), "%s: its expansion state" % f)
		assert_false(GameSession.intro_due, "%s: no intro on a Continue" % f)
		# the next checkpoint writes schema 3; the schema 2 file becomes the backup, unchanged
		var snap := GameSession.snapshot_document("test_a4")
		assert_eq(int(snap.schema_version), 3, "%s: the next checkpoint is schema 3" % f)
		for k: String in ExpansionState.KEYS:
			assert_true(snap.has(k), "%s: it holds %s" % [f, k])
		assert_true(SaveSlots.write(snap).ok, "%s: written" % f)
		assert_eq(FileAccess.get_file_as_string(SaveSlots.path() + ".bak"), _text(f), "%s: the schema 2 file is the backup" % f)
		var back := SaveSlots.read()
		assert_true(back.ok and str(back.source) == "main", "%s: the schema 3 file reads back" % f)
		assert_eq(back.data.titans, snap.titans, "%s: its titans" % f)
		SaveSlots.delete_slot()
		WorldState.clear()


func test_an_unknown_titan_is_dropped_and_said() -> void:
	var doc := SaveSlots.migrate(_fixture("v2_a4_world_mid"))
	doc.titans["titan.from_a_later_build"] = {"state": "slain"}
	_write_text(SaveSlots.path(), JSON.stringify(doc))
	var r := SaveSlots.read()
	assert_true(r.ok, "it loads")
	assert_false((r.data.titans as Dictionary).has("titan.from_a_later_build"), "the unknown titan is dropped")
	assert_true(str(r.message).contains("titan.from_a_later_build"), "and named: %s" % r.message)
	doc.titans["titan.stoneback"] = {"state": "nonsense"}
	assert_true(SaveSlots.validate(doc).size() >= 1, "a titan record with an unknown state does not validate")


## A5: the roster the save's titan records and the Character menu read names the story's ten signature titans in
## its order (docs/DECISIONS.md section 2.7: Harrok, returning at stage 8, is the sixth), each with a name.
func test_the_roster_is_the_storys_ten_in_order() -> void:
	var names: Array = []
	for t: Dictionary in ExpansionState.roster():
		names.append(str(t.get("display_name", "")))
	assert_eq(names, ["Stoneback", "The Ogre King", "The Rootwarden", "The Bastion Titan", "The Frostbound Titan",
		"Orrik the Fetterer", "The Stormcaller", "The Cinder Titan", "The Hollow Titan", "The Worldbreaker"],
		"the ten, named, in the story's order")


## B4: the line a load of fixture `f` says when it is given a titan's owed parts ("" when none are owed).
func _owed_note(f: String) -> String:
	var raw: Dictionary = JsonIO.read_file(FIXTURE_DIR + f + ".json").data
	return " ".join(ExpansionState.give_owed(raw.duplicate(true), ExpansionState.owed_parts(raw)))
