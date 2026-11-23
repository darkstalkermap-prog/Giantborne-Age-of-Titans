extends TestSuite
## B4 (the milestone B gate; docs/systems/B4.md, decision B4-1): saves the shipped 0.14.0-m14 build wrote, read by this
## one. Every save past the Valley holds the Ogre King's fall (his defeated flag) but none of his parts - builds before
## B2 gave his tusk and an ingot only - and no record of him, so the Kingsfall set could never be made; such a save
## is given his parts once as it loads (ExpansionState.owed_parts, SaveSlots.read), and says so. A save this build
## wrote records him, so it is never given them twice. The fixtures: a clean checkout of the tag with its own user
## folder, `tools/run_bots.sh --tag=w400 --autoplay=400 w.mixed:novice:1:assist` (v3_m14_world_mixed: the world,
## level 10), `--tag=v320 --autoplay=320 help_cache:novice:1:assist` (v3_m14_valley: the Valley, before the King) and
## `--tag=v480 --autoplay=480` of the same run (v3_m14_valley_after_king: after him, at the Barrow gap waystone).

const FIXTURE_DIR := "res://tests/fixtures/saves/"


func before_each() -> void:
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()


func _put(fixture_name: String) -> void:
	var text := FileAccess.get_file_as_string(FIXTURE_DIR + fixture_name + ".json")
	DirAccess.make_dir_recursive_absolute(SaveSlots.path().get_base_dir())
	var f := FileAccess.open(SaveSlots.path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_a_world_save_of_0_14_is_given_the_kings_parts_once() -> void:
	var raw: Dictionary = JsonIO.read_file(FIXTURE_DIR + "v3_m14_world_mixed.json").data
	assert_eq(str(raw.build_version), "0.14.0-m14", "written by the shipped build")
	assert_true(QuestConditions.truthy(raw.world.flags.get("world.ogre_king.defeated")), "past the Valley: he fell")
	assert_false((raw.world.inventory as Dictionary).has("item.ogre_hide"), "with none of his hide")
	assert_eq(ExpansionState.owed_parts(raw).size(), 3, "his hide, crown-iron and bell-bronze owed")
	_put("v3_m14_world_mixed")
	var r := SaveSlots.read()
	assert_true(r.ok, "it loads")
	var inv: Dictionary = r.data.world.inventory
	assert_eq(int(inv.get("item.ogre_hide", 0)), 4, "four cuts of his hide")
	assert_eq(int(inv.get("item.ogre_crown_iron", 0)), 1, "his crown's iron")
	assert_eq(int(inv.get("item.kings_bell_bronze", 0)), 1, "the bell's bronze")
	assert_eq(int(inv.get("item.ogre_tusk", 0)), 1, "his tusk as it was")
	assert_true(str(r.message).contains("The Ogre King's parts are in your pack: 4 King's Hide, Crown-iron and Bell-bronze"),
		"the load says so (%s)" % r.message)
	var st := ExpansionState.from_doc(r.data)
	var king: Dictionary = st.titans.get("titan.ogre_king", {})
	assert_eq(str(king.get("state", "")), ExpansionState.STATE_SLAIN, "his record: slain")
	assert_eq(int(king.get("kills", 0)), 1, "once")
	# the Kingsfall set can be made from them (the helm and the cuirass: the crown-iron and the bell-bronze)
	for rid: String in ["recipe.kingsfall_helm", "recipe.kingsfall_cuirass", "recipe.kingsfall_tassets"]:
		for c: Dictionary in GameData.get_record(rid).get("cost", []):
			if str(c.item) != "item.iron_ingot":
				assert_true(int(inv.get(str(c.item), 0)) >= int(c.count), "%s: %s in the pack" % [rid, c.item])
	# the next checkpoint (this build) records him: read again, nothing more is given
	GameSession.persist = true
	var doc: Dictionary = r.data.duplicate(true)
	ExpansionState.write_into(doc, ExpansionState.sync_from_flags(st, doc.world.flags))
	doc["build_version"] = "this build"
	assert_true(SaveSlots.write(doc).ok, "written back")
	var again := SaveSlots.read()
	assert_eq(int((again.data.world.inventory as Dictionary).get("item.ogre_hide", 0)), 4, "not given twice")
	assert_false(str(again.message).contains("parts are in your pack"), "and nothing said")


func test_a_valley_save_of_0_14_after_the_king_is_owed_too() -> void:
	var raw: Dictionary = JsonIO.read_file(FIXTURE_DIR + "v3_m14_valley_after_king.json").data
	assert_eq(str(raw.build_version), "0.14.0-m14", "written by the shipped build")
	assert_eq(int(raw.world.inventory.get("item.ogre_tusk", 0)), 1, "his tusk, as 0.14 gave it")
	assert_eq(ExpansionState.owed_parts(raw).size(), 3, "his three parts owed")


func test_a_valley_save_of_0_14_before_the_king_owes_nothing() -> void:
	var raw: Dictionary = JsonIO.read_file(FIXTURE_DIR + "v3_m14_valley.json").data
	assert_eq(int(raw.schema_version), 3, "schema 3")
	assert_true(ExpansionState.owed_parts(raw).is_empty(), "he stands: nothing owed")
	_put("v3_m14_valley")
	var r := SaveSlots.read()
	assert_true(r.ok, "it loads")
	assert_false((r.data.world.inventory as Dictionary).has("item.ogre_hide"), "none of his hide")
	var eq := Armour.normalized(ExpansionState.from_doc(r.data).equipment)
	assert_true((eq.pieces as Dictionary).is_empty(), "the reserved empty equipment block: nothing owned")
	for s: String in Armour.SLOTS:
		assert_eq(str(eq.slots[s]), "", "%s empty" % s)


func test_a_schema_2_save_past_the_valley_is_owed_too_and_a_new_record_is_not() -> void:
	var raw: Dictionary = JsonIO.read_file(FIXTURE_DIR + "v2_m13_world_mixed.json").data
	assert_eq(ExpansionState.owed_parts(raw).size(), 3, "0.13's world save: owed")
	var written := raw.duplicate(true)
	written["titans"] = {"titan.ogre_king": ExpansionState.titan_defaults()}
	assert_true(ExpansionState.owed_parts(written).is_empty(), "a save that records him: nothing")
