extends TestSuite
## The M11 pre-declarations of Part B (P53; plan M11 §1.5, §2.6, §2.11, §3.6 item 6), so that the wardrobe (P54),
## the creator II (P55), the catalogue II (P56) and the checks (P57) only add files: the appearance sets P54 and
## P56 ship (accessory, bead, face) are known categories, optional until their files exist and validated by their
## fields before; GiantLook draws the accessory and bead categories with the cloth shader and shows them by the
## look; the record's later keys (accessories, beads, face) are kept and sanitized before their sets exist;
## game_data.gd has the anchors of Part B's data packages, with P53 their creator in anchors_expected;
## ResetHooks.AFTER_EACH resets the creator II's thumbnail cache (skipped until P55's file exists, and it must
## exist once P55 has merged); and the flag appearance.slots_seen and its prompt are declared.

const GAME_DATA := "res://scripts/core/game_data.gd"
const THUMBNAIL_CACHE := "res://ui/screens/creator/thumbnail_cache.gd"
const PART_B_ANCHORS := ["P53", "P54", "P56"]


func _merged(owner: String) -> bool:
	return FileAccess.file_exists("res://docs/systems/%s.md" % owner)


func test_part_bs_sets_are_declared_and_optional_until_they_exist() -> void:
	for c: String in ["accessory", "bead", "face"]:
		assert_true(Appearance.LATER_CATEGORIES.has(c), "%s is a later category" % c)
		assert_true(Appearance.ALL_CATEGORIES.has(c), "the schema knows %s" % c)
		assert_false((Appearance.CATEGORIES + Appearance.SLOT_CATEGORIES).has(c), "%s is not required" % c)
		var missing := Appearance.set_record(c).is_empty()
		var owner := "P56" if c != "accessory" else "P54"
		if missing:
			assert_false(_merged(owner), "%s's set exists once %s has merged" % [c, owner])
	for c: String in Appearance.SLOT_CATEGORIES:
		assert_false(Appearance.set_record(c).is_empty(), "the record v2's %s set ships with P53" % c)
	assert_eq(Appearance.data_errors(GameData.records, GameData.record_paths), PackedStringArray(),
		"the shipped data passes without Part B's later sets")
	assert_eq(Appearance.SLOTS.size(), 10, "ten garment slots (decision 10)")
	assert_eq(Appearance.ACCESSORY_SLOTS, ["neck", "arm_ring", "belt"], "three accessory slots")
	assert_eq(Appearance.MATERIALS, ["cloth", "leather", "fur", "metal", "stone"],
		"the materials of §2.6's filter (B1: stone, the Quarry set's)")


func test_the_record_keeps_part_bs_keys_before_their_sets() -> void:
	var r := Appearance.default_record()
	assert_eq(str(r.hair.beads), Appearance.BEAD_NONE, "beads none")
	assert_eq((r.outfit.accessories as Dictionary).keys(), Appearance.ACCESSORY_SLOTS, "the accessory slots, empty")
	assert_eq((r.face as Dictionary).keys(), Appearance.FACE_KEYS, "the six face sliders at 0")
	assert_true(Appearance.is_valid(r), "valid as it is")
	var look := Appearance.to_look(r)
	for k: String in ["build", "face", "hair_beads", "beard_beads", "accessories"]:
		assert_true(look.has(k) and GiantLook.DEFAULT_LOOK.has(k), "the look and DEFAULT_LOOK carry %s" % k)


func test_giant_look_draws_part_bs_categories() -> void:
	for c: String in ["accessory", "bead"]:
		assert_eq(GiantLook.shader_kind(c), "cloth", "%s meshes take the cloth shader" % c)
	for n: String in ["build", "build_max_m"]:
		assert_true((GiantLook.UNIFORMS.skin as Array).has(n) and (GiantLook.UNIFORMS.cloth as Array).has(n),
			"GiantLook sets %s on the skin and the garments" % n)
	assert_eq(GiantLook.undeclared_uniforms(GiantLook.SKIN_SHADER, ["build", "build_max_m"]), PackedStringArray(),
		"giant_skin declares the build uniforms")
	assert_eq(GiantLook.undeclared_uniforms(GiantLook.CLOTH_SHADER, ["build", "build_max_m"]), PackedStringArray(),
		"giant_cloth too")


func test_the_part_b_anchors_and_their_rows() -> void:
	var text := FileAccess.get_file_as_string(GAME_DATA)
	var last := text.find("## @anchor P46\n")
	assert_true(last > 0, "game_data.gd keeps M10's last anchor")
	for pkg: String in PART_B_ANCHORS:
		assert_eq(text.count("## @anchor %s\n" % pkg), 1, "game_data.gd has the anchor %s once" % pkg)
		var at := text.find("## @anchor %s\n" % pkg)
		assert_true(at > last, "anchor %s comes after the one before it" % pkg)
		last = at
	var listed: Array = []
	for row: Array in AnchorsExpected.TABLE:
		if str(row[0]) == GAME_DATA and str(row[1]) == "P53":
			listed.append_array(row[2])
	assert_eq(listed, PART_B_ANCHORS, "anchors_expected lists them with P53 as their creator")
	assert_true(AnchorsExpected.creator_landed("P53"), "P53's rows are checked on this branch")


func test_reset_hooks_empty_the_thumbnail_cache() -> void:
	var hook := ["script", THUMBNAIL_CACHE, "reset_for_tests"]
	var at := -1
	for i in ResetHooks.AFTER_EACH.size():
		if (ResetHooks.AFTER_EACH[i] as Array).slice(0, 3) == hook:
			at = i
	assert_true(at >= 0, "ResetHooks.AFTER_EACH empties the thumbnail cache after every test (P55)")
	assert_true(at < ResetHooks.AFTER_EACH.size() - 1, "and the world index cache stays the last entry")
	if ResourceLoader.exists(THUMBNAIL_CACHE):
		assert_true(ResetHooks.has_callable(load(THUMBNAIL_CACHE), "reset_for_tests"),
			"ThumbnailCache has the static reset_for_tests the hook calls")
	else:
		assert_false(_merged("P55"), "thumbnail_cache.gd exists once P55 has merged")
		assert_true(ResetHooks.resolve(hook, get_tree()) == null, "until then the entry is skipped silently")
		var problems: PackedStringArray = await ResetHooks.run([hook], get_tree())
		assert_eq(problems.size(), 0, "and running it reports nothing")


func test_the_slots_seen_flag_and_its_prompt() -> void:
	assert_eq(SaveSlots.SLOTS_SEEN_FLAG, "appearance.slots_seen", "the flag's name (§2.11)")
	var prompt := GameData.get_record("tutorial.appearance_slots")
	assert_false(prompt.is_empty(), "tutorial.appearance_slots is loaded")
	assert_true((prompt.get("requires_flags", []) as Array).has(SaveSlots.SLOTS_SEEN_FLAG),
		"it shows only after a migrated look (the flag)")
	assert_true(bool(prompt.get("once", false)), "once")
	# (M12 kept schema 2 for the look's slots: the look's own "v" carries them; A4's schema 3 adds only the
	# expansion's fields, ExpansionState)
	assert_eq(SaveSlots.SCHEMA_VERSION, 3, "the save is schema 3 (A4), the look still versioned by its own v")
	assert_eq(Appearance.RECORD_VERSION, 2, "the record is version 2")
