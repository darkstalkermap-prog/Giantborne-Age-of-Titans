extends TestSuite
## The appearance schemas (P42; plan M10 §2.3): the shipped sets and presets pass; bad sets are rejected
## (an unknown category, duplicate keys, two defaults or none, a palette option without a colour or with
## one that is not #rrggbb, a design option without a region or without its design, a mark without its
## line, an outfit without garments, a wrong id) and bad presets too (no record, a record that is not a
## full one, a wrong version, a wrong id); GameData's post-pass (Appearance.data_errors, anchor P42)
## catches a missing set, a second set of one category, a default preset that does not use the sets'
## defaults and a preset naming ids no set has. P53 (plan M11 §2.5, §2.6): the record v2's sets (garment,
## metal, build) and Part B's later ones (accessory, bead, face) by their fields; an outfit as slots; presets at
## version 2; the post-pass's slot rules (an outfit's slot naming a garment of another slot, its M10 garments
## not what its slots wear, an M10 garment moved off its slot, a preset whose outfit name is not its slots').


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
	assert_eq(sets.size(), 17, "M10's thirteen sets, the record v2's three (garment, metal, build) and P54's accessories")
	for id: String in sets:
		assert_eq(_errors(GameData.get_record(id)), "", "%s passes its schema" % id)
	var presets := GameData.ids_of_type("appearance_preset")
	assert_eq(presets.size(), 8, "eight presets")
	for id: String in presets:
		assert_eq(_errors(GameData.get_record(id)), "", "%s passes its schema" % id)


## P46 (plan M10 §2.3): the target catalogue. The sets hold the floor's options and the look pass's, the
## tattoos four a region; a hair or beard option may carry a `length` (a shorter cut of its mesh).
func test_the_target_catalogue_is_in_the_sets() -> void:
	# P54 (plan M11 §2.6): twelve outfits, fourteen dyes, 35 garments, 8 accessories
	var want := {"hair": 7, "beard": 7, "tattoo": 16, "paint": 4, "scar": 6, "outfit": 12, "skin": 10, "eyes": 10,
		"haircolor": 10, "ink": 6, "paintcolor": 6, "mark": 3, "dye": 14, "garment": 35, "accessory": 8, "metal": 5}
	for cat: String in want:
		assert_eq(Appearance.option_ids(cat).size(), int(want[cat]), "the %s set's options" % cat)
	var per_region := {}
	for id in Appearance.option_ids("tattoo"):
		var region := str(Appearance.option(id).get("region", ""))
		per_region[region] = int(per_region.get(region, 0)) + 1
	assert_eq(per_region, {"arms": 4, "chest": 4, "back": 4, "face": 4}, "four tattoos a region")
	for id: String in ["hair.long_braided", "hair.warrior_tail", "hair.wild_mane", "beard.braided", "beard.forked",
			"tattoo.arm_sleeve", "tattoo.back_shoulders", "paint.full_face", "paint.back_hand", "scar.cheek",
			"scar.back_lash", "outfit.raider", "outfit.wayfarer"]:
		assert_false(Appearance.option(id).is_empty(), "%s is an option" % id)
	assert_true(is_equal_approx(float(Appearance.option("hair.shoulder").get("length", 1.0)), 0.6), "a shorter cut of the long hair")
	var cut := Appearance.default_record()
	cut.hair.style = "hair.shoulder"
	cut.beard.style = "beard.trimmed"
	var look := Appearance.to_look(cut, "")
	assert_eq([str(look.hair_mesh), str(look.beard_mesh)], ["Hair_long_back", "Beard_full"], "the cuts share their style's mesh")
	assert_true(float(look.hair_length) < 1.0 and float(look.beard_length) < 1.0, "and carry their length to the look")
	var whole := Appearance.to_look(Appearance.default_record(), "")
	assert_eq([float(whole.hair_length), float(whole.beard_length)], [1.0, 1.0], "the default look draws the whole length")
	var long_set: Dictionary = GameData.get_record("appearance_set.hair").duplicate(true)
	(long_set.options[0] as Dictionary)["length"] = 1.4
	assert_true(_errors(long_set).contains("length"), "a length above 1 is rejected")


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
	_rejects(_set_rec("outfit", [{"key": "bare", "name": "Bare", "slots": {}, "default": true}]), "at least one garment",
		"an outfit without garments")
	_rejects(_set_rec("outfit", [{"key": "bare", "name": "Bare", "garments": ["braies"], "default": true}]), "slots",
		"an outfit without slots (P53)")
	_rejects(_set_rec("outfit", [{"key": "odd", "name": "Odd", "slots": {"tail": "garment.braies"}, "default": true}]),
		"tail", "an outfit with a slot the body has not")
	_rejects(_set_rec("outfit", [{"key": "odd", "name": "Odd", "slots": {"legs": "braies"}, "default": true}]),
		"not a garment id", "an outfit slot naming no garment id")
	# P53: the record v2's sets and Part B's later ones
	var braies := {"key": "braies", "name": "Braies", "slot": "legs", "mesh": "braies", "material": "cloth"}
	assert_eq(_errors(_set_rec("garment", [braies])), "", "a garment set passes (no default)")
	_rejects(_set_rec("garment", [braies.merged({"slot": "tail"}, true)]), "slot", "a garment in a slot the body has not")
	_rejects(_set_rec("garment", [braies.merged({"material": "silk"}, true)]), "material", "an unknown material")
	_rejects(_set_rec("garment", [braies.merged({"mesh": ""}, true)]), "mesh", "a garment without its mesh")
	_rejects(_set_rec("garment", [braies.merged({"default": true}, true)]), "has no default", "a default garment")
	_rejects(_set_rec("garment", [braies.merged({"hides_hair": "some"}, true)]), "hides_hair", "an unknown hair cut")
	assert_eq(_errors(_set_rec("metal", [{"key": "iron", "name": "Iron", "color": "#6b6c6e", "default": true}])), "",
		"a metal set passes")
	_rejects(_set_rec("metal", [{"key": "iron", "name": "Iron", "default": true}]), "color", "a metal without a colour")
	assert_eq(_errors(_set_rec("build", [{"key": "brawn", "name": "Brawn", "low": "Lean", "high": "Brawny"}])), "",
		"a slider set passes")
	_rejects(_set_rec("build", [{"key": "brawn", "name": "Brawn", "default": true}]), "has no default", "a default slider")
	assert_eq(_errors(_set_rec("face", [{"key": "jaw", "name": "Jaw"}])), "", "the face sliders' set (P56) is declared")
	assert_eq(_errors(_set_rec("accessory", [{"key": "torc", "name": "Torc", "slot": "neck", "mesh": "Acc_torc"}])), "",
		"the accessories' set (P54) is declared")
	_rejects(_set_rec("accessory", [{"key": "torc", "name": "Torc", "slot": "legs", "mesh": "Acc_torc"}]), "slot",
		"an accessory in a garment slot")
	assert_eq(_errors(_set_rec("bead", [{"key": "none", "name": "None", "mesh": "", "default": true}])), "",
		"the beads' set (P56) is declared")
	assert_eq(_errors(_set_rec("tattoo", [{"key": "shin", "name": "Shin", "design": "tat_shin", "region": "legs"}])), "",
		"a tattoo may be on the legs (v2's fifth region)")
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
	(later.appearance as Dictionary)["v"] = 1
	_rejects(later, "version 2", "a preset of another record version (P53: presets are version 2)")
	var flat := good.duplicate(true)
	(flat.appearance as Dictionary).erase("build")
	_rejects(flat, "full record", "a preset without its build")
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
	var slot_off := records.duplicate(true)
	slot_off["appearance_set.outfit"]["options"][0]["slots"]["chest"] = "garment.braies"
	var e := "\n".join(Appearance.data_errors(slot_off, paths))
	assert_true(e.contains("a garment of the legs slot"), "an outfit's slot naming a garment of another slot: %s" % e)
	var m10 := records.duplicate(true)
	m10["appearance_set.outfit"]["options"][1]["slots"].erase("arms")
	assert_true("\n".join(Appearance.data_errors(m10, paths)).contains("its M10 garments are"),
		"an outfit whose slots do not wear its M10 garments is an error")
	var moved := records.duplicate(true)
	moved["appearance_set.garment"]["options"][0]["slot"] = "shins"
	assert_true("\n".join(Appearance.data_errors(moved, paths)).contains("worn in the legs slot"),
		"an M10 garment off its slot (plan M11 §2.5's mapping) is an error")
	var named := records.duplicate(true)
	named["appearance_preset.ash_raider"]["appearance"]["outfit"]["set"] = "outfit.warrior"
	assert_true("\n".join(Appearance.data_errors(named, paths)).contains("does not match its slots"),
		"a preset whose outfit name is not what its slots wear is an error")
	var no_garment := records.duplicate(true)
	no_garment.erase("appearance_set.garment")
	assert_true("\n".join(Appearance.data_errors(no_garment, paths)).contains("no appearance set of category 'garment'"),
		"the garment set is required")
	assert_eq(Appearance.data_errors({"x": {"type": "weapon"}}, {}), PackedStringArray(),
		"no appearance record at all (a test's temporary data): nothing to check")
