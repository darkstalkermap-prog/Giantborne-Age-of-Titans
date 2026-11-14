extends TestSuite
## The appearance schemas (P42; plan M10 §2.3): the shipped sets and presets pass; bad sets are rejected
## (an unknown category, duplicate keys, two defaults or none, a palette option without a colour or with
## one that is not #rrggbb, a design option without a region or without its design, a mark without its
## line, an outfit without garments, a wrong id) and bad presets too (no record, a record that is not a
## full one, a wrong version, a wrong id); GameData's post-pass (Appearance.data_errors, anchor P42)
## catches a missing set, a second set of one category, a default preset that does not use the sets'
## defaults and a preset naming ids no set has.


func _set_rec(category: String, options: Array) -> Dictionary:
	return {"schema_version": 1, "id": "appearance_set." + category, "type": "appearance_set", "category": category,
		"display_name": category.capitalize(), "options": options}


func _errors(rec: Dictionary) -> String:
	return "\n".join(DataValidator.validate_record(rec, "test.json").errors)


func _rejects(rec: Dictionary, needle: String, label: String) -> void:
	var e := _errors(rec)
	assert_true(e != "", "%s is rejected" % label)
	assert_true(e.contains(needle), "%s: the error says '%s' (%s)" % [label, needle, e])


func _skin(key: String, default := false, color := "#b07a62") -> Dictionary:
	var o := {"key": key, "name": key.capitalize(), "color": color}
	if default:
		o["default"] = true
	return o


func test_the_shipped_sets_and_presets_pass() -> void:
	var sets := GameData.ids_of_type("appearance_set")
	assert_eq(sets.size(), 13, "thirteen sets")
	for id: String in sets:
		assert_eq(_errors(GameData.get_record(id)), "", "%s passes its schema" % id)
	var presets := GameData.ids_of_type("appearance_preset")
	assert_eq(presets.size(), 8, "eight presets")
	for id: String in presets:
		assert_eq(_errors(GameData.get_record(id)), "", "%s passes its schema" % id)


func test_bad_sets_are_rejected() -> void:
	assert_eq(_errors(_set_rec("skin", [_skin("pale"), _skin("ruddy", true)])), "", "a good skin set passes")
	_rejects(_set_rec("wings", [{"key": "bat", "name": "Bat"}]), "wings", "an unknown category")
	_rejects(_set_rec("skin", [_skin("pale", true), _skin("pale")]), "duplicate key 'pale'", "duplicate keys")
	_rejects(_set_rec("skin", [_skin("pale", true), _skin("ruddy", true)]), "exactly one option", "two defaults")
	_rejects(_set_rec("skin", [_skin("pale"), _skin("ruddy")]), "exactly one option", "no default")
	_rejects(_set_rec("skin", [{"key": "pale", "name": "Pale", "default": true}]), "color", "a palette without a colour")
	_rejects(_set_rec("dye", [{"key": "red", "name": "Red", "default": true, "color": "red"}]), "not a colour",
		"a colour that is not #rrggbb")
	_rejects(_set_rec("tattoo", [{"key": "bands", "name": "Bands", "design": "tat_bands"}]), "region",
		"a design option without a region")
	_rejects(_set_rec("tattoo", [{"key": "bands", "name": "Bands", "design": "tat_bands", "region": "tail"}]), "region",
		"a design option in a region the body has not")
	_rejects(_set_rec("paint", [{"key": "stripes", "name": "Stripes", "design": "", "region": "face"}]), "design",
		"a design option without its design")
	_rejects(_set_rec("tattoo", [{"key": "bands", "name": "Bands", "design": "tat_bands", "region": "arms",
		"default": true}]), "has no default", "a default in a set whose default is none")
	_rejects(_set_rec("mark", [{"key": "veins", "name": "Veins", "design": "mark_veins", "color": "#808080"}]),
		"belongs to a line", "a mark without its line")
	_rejects(_set_rec("outfit", [{"key": "bare", "name": "Bare", "garments": [], "default": true}]), "at least one garment",
		"an outfit without garments")
	_rejects(_set_rec("skin", [_skin("Pale Skin", true)]), "lowercase", "a key that is not lowercase")
	var wrong := _set_rec("skin", [_skin("pale", true)])
	wrong.id = "appearance_set.skins"
	_rejects(wrong, "appearance_set.skin", "a set whose id is not appearance_set.<category>")
	_rejects(_set_rec("skin", [_skin("pale", true)]).merged({"options": []}, true), "at least one option", "an empty set")
	# (A requires naming an ancestry that does not exist is GameData's reference check, as for every U.ref.)
	var locked := _set_rec("skin", [_skin("pale", true), {"key": "ashen", "name": "Ashen", "color": "#8a8580",
		"requires": {"ancestry": 7}}])
	_rejects(locked, "ancestry", "requires naming no ancestry id")


func test_bad_presets_are_rejected() -> void:
	var good: Dictionary = GameData.get_record("appearance_preset.wanderer").duplicate(true)
	assert_eq(_errors(good), "", "the Wanderer passes")
	var none := good.duplicate(true)
	none.erase("appearance")
	_rejects(none, "appearance", "a preset without a record")
	var partial := good.duplicate(true)
	(partial.appearance as Dictionary).erase("hair")
	_rejects(partial, "full record", "a preset whose record is not a full one")
	var broken := good.duplicate(true)
	(broken.appearance as Dictionary)["scars"] = "brow"
	_rejects(broken, "scars", "a preset whose record is broken")
	var later := good.duplicate(true)
	(later.appearance as Dictionary)["v"] = 2
	_rejects(later, "version 1", "a preset of another record version")
	var id := good.duplicate(true)
	id.id = "preset.wanderer"
	_rejects(id, "appearance_preset.", "a preset whose id lacks the prefix")


func test_the_post_pass_rules() -> void:
	var records := {}
	var paths := {}
	for t: String in ["appearance_set", "appearance_preset"]:
		for rid: String in GameData.ids_of_type(t):
			records[rid] = GameData.get_record(rid).duplicate(true)
			paths[rid] = "data/appearance/%s.json" % rid
	assert_eq(Appearance.data_errors(records, paths), PackedStringArray(), "the shipped sets and presets pass")
	var missing := records.duplicate(true)
	missing.erase("appearance_set.dye")
	assert_true("\n".join(Appearance.data_errors(missing, paths)).contains("no appearance set of category 'dye'"),
		"a missing set is an error")
	var twice := records.duplicate(true)
	twice["appearance_set.dye2"] = (records["appearance_set.dye"] as Dictionary).duplicate(true)
	assert_true("\n".join(Appearance.data_errors(twice, paths)).contains("a second set of category 'dye'"),
		"a second set of one category is an error")
	var off := records.duplicate(true)
	off[Appearance.DEFAULT_PRESET]["appearance"]["skin"] = "skin.pale"
	assert_true("\n".join(Appearance.data_errors(off, paths)).contains("should use the skin set's default"),
		"a default preset that does not use a set's default is an error")
	var unknown := records.duplicate(true)
	unknown["appearance_preset.ash_raider"]["appearance"]["eyes"] = "eyes.violet"
	assert_true("\n".join(Appearance.data_errors(unknown, paths)).contains("eyes.violet"),
		"a preset naming an id no set has is an error")
	var locked := records.duplicate(true)
	locked["appearance_preset.ash_raider"]["appearance"]["skin"] = "skin.ashen"
	assert_true("\n".join(Appearance.data_errors(locked, paths)).contains("not unlocked"),
		"a preset using a locked option is an error (presets are offered before any line)")
	var selfless := records.duplicate(true)
	selfless["appearance_preset.ash_raider"]["appearance"]["preset"] = "appearance_preset.wanderer"
	assert_true("\n".join(Appearance.data_errors(selfless, paths)).contains("not the preset itself"),
		"a preset whose record names another preset is an error")
	assert_eq(Appearance.data_errors({"x": {"type": "weapon"}}, {}), PackedStringArray(),
		"no appearance record at all (a test's temporary data): nothing to check")
