extends TestSuite
## The M11 pre-declarations of Part C (P59; plan M11 §1.5, §2.11), so that PersonRig and the crowd (P60), the mounts
## and the giants' looks (P61), townsfolk, named characters and riders (P62), the brutes and beasts (P63, P64) and the
## people look pass (P65) only add files: the person_role record type is known to the validator and skipped until
## P60 writes its schema module; build_scenes.gd's BUILDERS runs people_models.gd before the soldier's builder,
## skipped until it exists; ResetHooks.AFTER_EACH turns the skinned people back off after every test (PersonRig's
## reset, skipped until P60's file exists, and it must exist once P60 has merged); game_data.gd has the anchors of
## Part C's data packages, with P59 their creator in anchors_expected; and the people's assets of P59 are where
## the index says.

const GAME_DATA := "res://scripts/core/game_data.gd"
const PERSON_ROLE_SCHEMA := "res://scripts/core/schemas/person_role_schema.gd"
const PEOPLE_MODELS := "res://tools/builders/people_models.gd"
const PERSON_RIG := "res://scripts/presentation/person_rig.gd"
const PART_C_ANCHORS := ["P60", "P61", "P62", "P64", "P65"]
const BUILD_SCENES := "res://tools/build_scenes.gd"


func _merged(owner: String) -> bool:
	return FileAccess.file_exists("res://docs/systems/%s.md" % owner)


func test_the_person_role_type_is_declared_and_skipped_until_its_module_exists() -> void:
	assert_eq(str(DataValidator.SCHEMA_PATHS.get("person_role", "")), PERSON_ROLE_SCHEMA, "person_role's module path")
	if ResourceLoader.exists(PERSON_ROLE_SCHEMA):
		assert_true(DataValidator.RECORD_TYPES.has("person_role"), "the type validates once P60 wrote its module")
	else:
		assert_false(_merged("P60"), "person_role_schema.gd exists once P60 has merged")
		assert_false(DataValidator.RECORD_TYPES.has("person_role"), "until then the registry skips it")
	assert_false(GameData.records.is_empty(), "the shipped data loads without the people's records")


func test_people_models_builds_before_the_soldier() -> void:
	# (read as text: loading build_scenes.gd compiles every builder's dependencies)
	var text := FileAccess.get_file_as_string(BUILD_SCENES)
	var at := text.find('"%s",' % PEOPLE_MODELS)
	var soldier := text.find('"res://tools/builders/soldier.gd",')
	assert_true(at >= 0, "BUILDERS names people_models.gd (plan §2.11)")
	assert_true(at < soldier, "before soldier.gd, so the soldiers' scenes can instance the people's models")
	assert_true(text.find('"res://tools/builders/giant_model.gd",') < at, "after the giant's model")
	if not FileAccess.file_exists(PEOPLE_MODELS):
		assert_false(_merged("P60"), "people_models.gd exists once P60 has merged")


func test_reset_hooks_turn_the_skinned_people_off() -> void:
	var hook := ["script", PERSON_RIG, "reset_for_tests"]
	var at := -1
	for i in ResetHooks.AFTER_EACH.size():
		if (ResetHooks.AFTER_EACH[i] as Array).slice(0, 3) == hook:
			at = i
	assert_true(at >= 0, "ResetHooks.AFTER_EACH resets PersonRig after every test (P60)")
	assert_true(at < ResetHooks.AFTER_EACH.size() - 1, "and the world index cache stays the last entry")
	if ResourceLoader.exists(PERSON_RIG):
		assert_true(ResetHooks.has_callable(load(PERSON_RIG), "reset_for_tests"),
			"PersonRig has the static reset_for_tests the hook calls")
	else:
		assert_false(_merged("P60"), "person_rig.gd exists once P60 has merged")
		assert_true(ResetHooks.resolve(hook, get_tree()) == null, "until then the entry is skipped silently")
		var problems: PackedStringArray = await ResetHooks.run([hook], get_tree())
		assert_eq(problems.size(), 0, "and running it reports nothing")


func test_the_part_c_anchors_and_their_rows() -> void:
	var text := FileAccess.get_file_as_string(GAME_DATA)
	var last := text.find("## @anchor P56\n")
	assert_true(last > 0, "game_data.gd keeps Part B's last anchor")
	for pkg: String in PART_C_ANCHORS:
		assert_eq(text.count("## @anchor %s\n" % pkg), 1, "game_data.gd has the anchor %s once" % pkg)
		var at := text.find("## @anchor %s\n" % pkg)
		assert_true(at > last, "anchor %s comes after the one before it" % pkg)
		last = at
	var listed: Array = []
	for row: Array in AnchorsExpected.TABLE:
		if str(row[0]) == GAME_DATA and str(row[1]) == "P59":
			listed.append_array(row[2])
	assert_eq(listed, PART_C_ANCHORS, "anchors_expected lists them with P59 as their creator")
	assert_true(AnchorsExpected.creator_landed("P59"), "P59's rows are checked on this branch")
	for pkg: String in ["P59", "P60", "P61", "P62", "P63", "P64", "P65", "P66"]:
		assert_true(AnchorsExpected.EVENTS_PACKAGES_M11.has(pkg), "events.gd keeps an anchor for %s (P49)" % pkg)


func test_the_people_assets_are_where_the_index_says() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/people/manifest.json"))
	assert_true(doc is Dictionary, "assets/people/manifest.json (P59)")
	if not doc is Dictionary:
		return
	var index: Dictionary = (doc as Dictionary).index
	for role: String in index.role_order:
		for k: String in ["scene", "albedo", "normal", "orm"]:
			assert_true(FileAccess.file_exists(str(index.roles[role][k])), "%s's %s" % [role, k])
	assert_true(FileAccess.file_exists(str(index.clips)), "the people's clips")
	assert_true(FileAccess.file_exists(str(index.gear)), "the gear")
