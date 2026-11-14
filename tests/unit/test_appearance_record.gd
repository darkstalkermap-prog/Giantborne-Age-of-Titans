extends TestSuite
## The appearance record (P42; plan M10 §2.2-§2.4, §2.10): the default from the data, resolve(), the
## sanitize() rules with their dropped ids and notes, to_look() for every option of every set and for the
## default (GiantLook.DEFAULT_LOOK within §2.4's tolerance), random_record() in every scope (valid, never a
## design where the outfit hides it, Sim.rng untouched), the summary in words, the covered regions and the
## presets. Pure: no node, no scene. (tests/slow/test_appearance_random.gd runs random_record over 1,000
## seeds in every scope; this suite runs 6.)

const STONE := "ancestry.stoneblood"
const STORM := "ancestry.stormborn"
const WILD := "ancestry.wildheart"
## Plan M10 §2.4: a hex-parsed colour may differ from DEFAULT_LOOK's literal in the last bit.
const COLOR_TOLERANCE := 1.0 / 255.0
const RANDOM_SEEDS := 6
const RandomCheck := preload("res://tests/support/appearance_random_check.gd")


func after_each() -> void:
	Appearance.cli_preset = ""


## a == b, numbers by value (JSON gives floats where the code writes ints), colours within tolerance.
static func deep_eq(a: Variant, b: Variant, tol := 1e-6) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return absf(float(a) - float(b)) <= tol
	if typeof(a) == TYPE_COLOR and typeof(b) == TYPE_COLOR:
		var ca: Color = a
		var cb: Color = b
		return absf(ca.r - cb.r) <= COLOR_TOLERANCE + 1e-6 and absf(ca.g - cb.g) <= COLOR_TOLERANCE + 1e-6 \
			and absf(ca.b - cb.b) <= COLOR_TOLERANCE + 1e-6 and absf(ca.a - cb.a) <= COLOR_TOLERANCE + 1e-6
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not deep_eq(a[k], b[k], tol):
				return false
		return true
	if typeof(a) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] and typeof(b) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not deep_eq(a[i], b[i], tol):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


## The default record with `changes` merged in (one level into the blocks).
static func with(changes: Dictionary) -> Dictionary:
	var r := Appearance.default_record()
	for k: Variant in changes:
		if typeof(changes[k]) == TYPE_DICTIONARY and typeof(r.get(k)) == TYPE_DICTIONARY:
			for sub: Variant in changes[k]:
				r[k][sub] = changes[k][sub]
		else:
			r[k] = changes[k]
	return r


static func _hex(opt_id: String, key := "color") -> Color:
	return Color.html(str(Appearance.option(opt_id).get(key, "")))


# --------------------------------------------------------------------------- the default and resolve

func test_the_default_record_is_the_wanderer_from_the_data() -> void:
	var d := Appearance.default_record()
	var data: Dictionary = GameData.get_record(Appearance.DEFAULT_PRESET).get("appearance", {})
	assert_true(not data.is_empty(), "the Wanderer preset is loaded")
	assert_true(deep_eq(d, data), "default_record() is the Wanderer's record")
	assert_true(deep_eq(d, Appearance.FALLBACK_RECORD), "and FALLBACK_RECORD holds the same values")
	for c: String in ["skin", "eyes"]:
		assert_eq(str(d[c]), Appearance.set_default(c), "the default %s is its set's default" % c)
	assert_eq(str(d.hair.style), Appearance.set_default("hair"), "the default hair style")
	assert_eq(str(d.hair.color), Appearance.set_default("haircolor"), "the default hair colour")
	assert_eq(str(d.beard.style), Appearance.set_default("beard"), "the default beard")
	assert_eq(str(d.outfit.set), Appearance.set_default("outfit"), "the default outfit")
	assert_eq(str(d.outfit.primary), Appearance.set_default("dye"), "the default dye")
	assert_eq(str(d.mark), Appearance.MARK_AUTO, "the mark shows once a line is chosen")
	assert_true(Appearance.is_valid(d), "the default passes sanitize unchanged")
	d.skin = "skin.pale"
	assert_eq(str(Appearance.default_record().skin), "skin.ruddy", "default_record() is a copy")


func test_resolve_absent_preset_and_own_record() -> void:
	assert_true(deep_eq(Appearance.resolve({}), Appearance.default_record()), "no look: the default")
	assert_true(deep_eq(Appearance.resolve({"ancestry": STONE}), Appearance.default_record()),
		"no look with a line: the default too")
	Appearance.cli_preset = "appearance_preset.storm_herald"
	var herald := Appearance.preset_record("storm_herald")
	assert_true(not herald.is_empty(), "the Storm Herald preset is loaded (short id)")
	assert_true(deep_eq(Appearance.resolve({}), herald), "--appearance=: a character without a look wears the preset")
	var own := with({"skin": "skin.deep"})
	assert_true(deep_eq(Appearance.resolve({"appearance": own}), own), "a look of its own wins over --appearance=")
	Appearance.cli_preset = "appearance_preset.no_such"
	assert_true(deep_eq(Appearance.resolve({}), Appearance.default_record()), "an unknown preset: the default")


func test_the_mark_auto_with_and_without_a_line_and_none() -> void:
	var d := Appearance.default_record()
	assert_true((Appearance.to_look(d, "").mark as Dictionary).is_empty(), "no line: no mark")
	assert_true((Appearance.to_look(d, Appearance.NEUTRAL_ANCESTRY).mark as Dictionary).is_empty(),
		"the prologue's neutral ancestry: no mark")
	for line: String in [STONE, STORM, WILD]:
		var mark := Appearance.ancestry_mark(line)
		assert_true(not mark.is_empty(), "%s has a mark" % line)
		var look := Appearance.to_look(d, line)
		assert_eq(str((look.mark as Dictionary).get("design", "")), str(mark.get("design", "")),
			"\"auto\" shows %s's mark" % line)
		assert_true(deep_eq((look.mark as Dictionary).get("color"), Color.html(str(mark.color))), "in its colour")
		var hidden := Appearance.to_look(with({"mark": "none"}), line)
		assert_true((hidden.mark as Dictionary).is_empty(), "\"none\" hides %s's mark" % line)
	assert_true(float(Appearance.to_look(d, STORM).mark.get("glow", 0.0)) >= 0.0, "the mark's glow is a number")


# --------------------------------------------------------------------------- sanitize

func test_unknown_ids_fall_back_to_the_default_and_are_listed() -> void:
	var r := with({"skin": "skin.purple", "hair": {"style": "hair.mohawk", "color": "haircolor.green"},
		"outfit": {"set": "outfit.armour"}, "scars": ["scar.brow", "scar.dragon"], "eyes": "hair.crop"})
	var s := Appearance.sanitize(r)
	var d := Appearance.default_record()
	assert_eq(str(s.record.skin), str(d.skin), "an unknown skin: the default skin")
	assert_eq(str(s.record.hair.style), str(d.hair.style), "an unknown hair style: the default")
	assert_eq(str(s.record.hair.color), str(d.hair.color), "an unknown hair colour: the default")
	assert_eq(str(s.record.outfit.set), str(d.outfit.set), "an unknown outfit: the default")
	assert_eq(str(s.record.eyes), str(d.eyes), "another set's id in the eyes: the default eyes")
	assert_eq(s.record.scars, ["scar.brow"], "an unknown scar dropped, the known one kept")
	for id: String in ["skin.purple", "hair.mohawk", "haircolor.green", "outfit.armour", "scar.dragon", "hair.crop"]:
		assert_true((s.dropped as PackedStringArray).has(id), "%s is in the dropped list" % id)
	assert_true((s.notes as PackedStringArray).is_empty(), "unknown ids alone add no note (read() lists them)")
	var twice := Appearance.sanitize(with({"skin": "skin.purple", "eyes": "skin.purple"}))
	assert_eq((twice.dropped as PackedStringArray).count("skin.purple"), 1, "each dropped id once")


func test_locked_options_are_reset_with_a_note() -> void:
	var r := with({"skin": "skin.ashen", "eyes": "eyes.storm"})
	var s := Appearance.sanitize(r, "")
	assert_eq(str(s.record.skin), "skin.ruddy", "Ashen needs Stoneblood: the default skin before a line")
	assert_eq(str(s.record.eyes), "eyes.grey_green", "the Storm eyes need Stormborn")
	assert_true((s.dropped as PackedStringArray).is_empty(), "locked ids are not unknown")
	assert_eq((s.notes as PackedStringArray).size(), 1, "one note for the locked options")
	var note: String = s.notes[0] if not (s.notes as PackedStringArray).is_empty() else ""
	assert_true(note.contains("Ashen") and note.contains("not unlocked"), "the note names them: %s" % note)
	var stone := Appearance.sanitize(r, STONE)
	assert_eq(str(stone.record.skin), "skin.ashen", "a Stoneblood giant keeps Ashen")
	assert_eq(str(stone.record.eyes), "eyes.grey_green", "but not the Stormborn's eyes")
	assert_eq(Appearance.locked_reason("skin.ashen", ""), Appearance.LOCKED_HINT, "before a line: the hint")
	assert_eq(Appearance.locked_reason("skin.ashen", Appearance.NEUTRAL_ANCESTRY), Appearance.LOCKED_HINT,
		"the prologue's ancestry counts as no line")
	assert_true(Appearance.locked_reason("skin.ashen", STORM).begins_with("Only for the "), "another line: whose it is")
	assert_eq(Appearance.locked_reason("skin.ashen", STONE), "", "its own line: unlocked")
	assert_eq(Appearance.locked_reason("skin.pale", ""), "", "an option without requires is never locked")
	var opts := Appearance.options("skin", "")
	var ashen: Dictionary = {}
	for o: Dictionary in opts:
		if str(o.id) == "skin.ashen":
			ashen = o
	assert_true(bool(ashen.get("locked", false)) and str(ashen.get("reason", "")) == Appearance.LOCKED_HINT,
		"options() marks Ashen locked with its reason")


func test_a_tattoo_in_the_wrong_region_is_removed_with_a_note() -> void:
	var s := Appearance.sanitize(with({"tattoos": {"chest": "tattoo.face_lines", "arms": "tattoo.arm_bands"}}))
	assert_eq(str(s.record.tattoos.chest), "", "a face tattoo on the chest is removed")
	assert_eq(str(s.record.tattoos.arms), "tattoo.arm_bands", "the arm tattoo on the arms stays")
	assert_eq((s.notes as PackedStringArray).size(), 1, "one note")
	assert_true(str(s.notes[0]).contains("tattoo.face_lines"), "it names the design: %s" % s.notes[0])
	var unknown := Appearance.sanitize(with({"tattoos": {"back": "paint.face_stripes"}}))
	assert_eq(str(unknown.record.tattoos.back), "", "a war paint in a tattoo slot is no tattoo")
	assert_true((unknown.dropped as PackedStringArray).has("paint.face_stripes"), "and is dropped")


func test_scars_unique_and_at_most_four_numbers_clamped_and_cast() -> void:
	var r := with({"scars": ["scar.brow", "scar.brow", "scar.knuckles", "scar.chest_claws", "scar.forearm_slash",
		"scar.knuckles", ""], "hair": {"grey": 1.7}, "beard": {"grey": -3}})
	var s := Appearance.sanitize(r)
	assert_eq(s.record.scars, ["scar.brow", "scar.knuckles", "scar.chest_claws", "scar.forearm_slash"],
		"scars unique, in order, at most %d" % Appearance.MAX_SCARS)
	assert_eq((s.record.scars as Array).size() <= Appearance.MAX_SCARS, true, "never more than four")
	assert_eq(s.record.hair.grey, 1.0, "the hair's grey clamped to 1")
	assert_eq(typeof(s.record.beard.grey), TYPE_FLOAT, "an int grey is cast to a float")
	assert_eq(s.record.beard.grey, 0.0, "and clamped to 0")
	var as_text := Appearance.sanitize(with({"hair": {"grey": "0.5"}}))
	assert_eq(as_text.record.hair.grey, 0.0, "a grey that is not a number reads as 0")
	var v := Appearance.sanitize(with({"v": 1.0}))
	assert_eq(typeof(v.record.v), TYPE_INT, "v 1.0 (JSON) is cast to the int 1")
	assert_eq(v.record.v, 1, "v is 1")
	assert_eq(str(Appearance.sanitize(with({"mark": "sometimes"})).record.mark), "auto", "an unknown mark mode: auto")
	assert_eq(str(Appearance.sanitize(with({"preset": "appearance_preset.no_such"})).record.preset), "",
		"an unknown preset name is cleared")


func test_a_later_builds_record_is_kept_untouched_with_its_note() -> void:
	var future := {"v": 2, "skin": "skin.starlight", "wings": {"span": 9}, "hair": "braided"}
	var s := Appearance.sanitize(future)
	assert_true(deep_eq(s.record, future), "a record with v 2 comes back exactly as it was")
	assert_eq(s.notes, PackedStringArray([Appearance.NOTE_FUTURE]), "with the later-build note")
	assert_true((s.dropped as PackedStringArray).is_empty(), "nothing dropped")
	assert_true(Appearance.is_future(future), "is_future")
	assert_true(Appearance.is_future({"v": 2.0}), "v 2.0 (JSON) is a later build's too")
	assert_false(Appearance.is_future({"v": 1}), "v 1 is this build's")
	var look := Appearance.to_look(future, STONE)
	assert_eq(str(look.hair_mesh), str(Appearance.to_look(Appearance.default_record(), STONE).hair_mesh),
		"it draws as the default look")
	future["skin"] = "skin.changed"
	assert_eq(str(s.record.skin), "skin.starlight", "sanitize returned a copy")


func test_unknown_keys_are_kept_and_a_broken_record_is_the_default() -> void:
	var r := with({"freckles": {"density": 0.4}})
	r["hair"]["shine"] = 0.2
	var s := Appearance.sanitize(r)
	assert_true(deep_eq(s.record.get("freckles"), {"density": 0.4}), "a top-level key this build does not know stays")
	assert_eq(float((s.record.hair as Dictionary).get("shine", -1.0)), 0.2, "and one inside a block")
	assert_true((s.notes as PackedStringArray).is_empty(), "no note for them")
	for broken: Variant in ["a string", 7, [1, 2], null, {"hair": "long"}, {"scars": "brow"}, {"skin": 3},
			{"v": 0}, {"v": "one"}, {"v": 1.5}, {"tattoos": {"arms": 4}}]:
		var b := Appearance.sanitize(broken)
		assert_true(deep_eq(b.record, Appearance.default_record()), "%s: the default record" % [broken])
		assert_eq(b.notes, PackedStringArray([Appearance.NOTE_BROKEN]), "%s: with the broken note" % [broken])
	var empty: Dictionary = Appearance.sanitize({}).record
	assert_eq(str(empty.get("preset", "?")), "", "an empty record names no preset")
	var d := Appearance.default_record()
	d["preset"] = ""
	assert_true(deep_eq(empty, d), "and is the default record otherwise, key by key")
	assert_true((Appearance.sanitize({}).notes as PackedStringArray).is_empty(), "and needs no note")


# --------------------------------------------------------------------------- to_look

func test_to_look_of_the_default_is_the_default_look() -> void:
	var look := Appearance.to_look(Appearance.default_record(), "")
	assert_eq(look.keys().size(), GiantLook.DEFAULT_LOOK.keys().size(), "the same keys")
	for k: Variant in GiantLook.DEFAULT_LOOK:
		assert_true(look.has(k), "the look has %s" % k)
		assert_true(deep_eq(look.get(k), GiantLook.DEFAULT_LOOK[k], 1e-4),
			"%s: %s against DEFAULT_LOOK's %s" % [k, look.get(k), GiantLook.DEFAULT_LOOK[k]])


func test_to_look_for_every_option_of_every_set() -> void:
	var n := 0
	for c: String in Appearance.CATEGORIES:
		for id: String in Appearance.option_ids(c):
			var o := Appearance.option(id)
			var line := Appearance.required_ancestry(o)
			var r := Appearance.default_record()
			match c:
				"skin", "eyes":
					r[c] = id
				"hair":
					r.hair.style = id
				"haircolor":
					r.hair.color = id
				"beard":
					r.beard.style = id
				"tattoo":
					r.tattoos[str(o.region)] = id
				"ink":
					r.tattoos.arms = "tattoo.arm_bands"
					r.tattoos.ink = id
				"paint":
					r.paint.design = id
				"paintcolor":
					r.paint.design = "paint.face_stripes"
					r.paint.color = id
				"scar":
					r.scars = [id]
				"mark":
					r.mark = Appearance.MARK_AUTO
				"outfit":
					r.outfit.set = id
				"dye":
					r.outfit.primary = id
					r.outfit.secondary = id
			assert_true(Appearance.is_valid(r, line), "%s: a record with it is valid for %s" % [id, line])
			var look := Appearance.to_look(r, line)
			match c:
				"skin":
					assert_true(deep_eq(look.skin_tone, _hex(id)), "%s: the skin tone" % id)
				"eyes":
					assert_true(deep_eq(look.eye_color, _hex(id)), "%s: the eye colour" % id)
					assert_eq(float(look.eye_glow), float(o.get("glow", 0.0)), "%s: the glow" % id)
				"hair":
					assert_eq(str(look.hair_mesh), str(o.get("mesh", "")), "%s: the hair mesh" % id)
					assert_eq(float(look.scalp_tint), float(o.get("scalp_tint", 0.0)), "%s: the scalp tint" % id)
				"haircolor":
					assert_true(deep_eq(look.hair_color, _hex(id)), "%s: the hair colour" % id)
					assert_true(deep_eq(look.beard_color, _hex(id)), "%s: the beard in the hair's colour" % id)
					var tip := _hex(id, "tip") if str(o.get("tip", "")) != "" else _hex(id)
					assert_true(deep_eq(look.hair_tip, tip), "%s: the tips" % id)
				"beard":
					assert_eq(str(look.beard_mesh), str(o.get("mesh", "")), "%s: the beard mesh" % id)
					assert_eq(float(look.stubble), float(o.get("stubble", 0.0)), "%s: the stubble" % id)
					assert_eq(float(look.beard_tint), float(o.get("beard_tint", 0.0)), "%s: the beard tint" % id)
				"tattoo":
					assert_eq((look.tattoos as Array).size(), 1, "%s: one tattoo" % id)
					assert_eq(str((look.tattoos as Array)[0].design), str(o.design), "%s: its design" % id)
				"ink":
					assert_true(deep_eq((look.tattoos as Array)[0].ink, _hex(id)), "%s: the tattoo's ink" % id)
				"paint":
					assert_eq(str(look.paint.get("design", "")), str(o.design), "%s: the war paint's design" % id)
				"paintcolor":
					assert_true(deep_eq(look.paint.get("color"), _hex(id)), "%s: the paint's colour" % id)
				"scar":
					assert_eq(look.scars, [str(o.design)], "%s: the scar's design" % id)
				"mark":
					assert_eq(str(look.mark.get("design", "")), str(o.design), "%s: the line's mark" % id)
					assert_true(deep_eq(look.mark.get("color"), _hex(id)), "%s: in its colour" % id)
				"outfit":
					var want: Array = []
					for g: Variant in o.get("garments", []):
						want.append(str(g))
					assert_eq(look.garments, want, "%s: its garments" % id)
				"dye":
					assert_true(deep_eq(look.dye_primary, _hex(id)), "%s: the first dye" % id)
					assert_true(deep_eq(look.dye_secondary, _hex(id)), "%s: the second dye" % id)
			n += 1
	assert_true(n >= 70, "every option of the thirteen sets was drawn (%d)" % n)


func test_a_locked_option_draws_as_the_default_until_the_line_is_chosen() -> void:
	var r := with({"skin": "skin.ashen"})
	assert_true(deep_eq(Appearance.to_look(r, "").skin_tone, _hex("skin.ruddy")), "before the line: the default skin")
	assert_true(deep_eq(Appearance.to_look(r, STONE).skin_tone, _hex("skin.ashen")), "a Stoneblood giant: Ashen")


# --------------------------------------------------------------------------- random_record

## Checks random records of every scope for `seeds` seeds (from `base`, for `line`): the count checked.
func check_random(seeds: int, base: Dictionary, line: String) -> int:
	var r := RandomCheck.run(seeds, base, line)
	checks += 1
	if str(r.error) != "":
		fail(str(r.error))
	return int(r.count)


func test_random_records_are_valid_and_never_where_the_outfit_hides_them() -> void:
	var n := check_random(RANDOM_SEEDS, {}, "")
	var warrior := with({"outfit": {"set": "outfit.warrior"}, "mark": "none"})
	n += check_random(RANDOM_SEEDS / 2, warrior, STONE)
	assert_true(n > 0, "%d random records checked" % n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var a := Appearance.random_record(rng, "all", false, "")
	rng.seed = 5
	assert_true(deep_eq(a, Appearance.random_record(rng, "all", false, "")), "one seed, one record")
	rng.seed = 11
	var hair_only := Appearance.random_record(rng, "hair", false, "", warrior)
	assert_true(deep_eq(hair_only.outfit, warrior.outfit) and deep_eq(hair_only.skin, warrior.skin),
		"a category's Randomize keeps the rest")
	rng.seed = 3
	var preset := Appearance.random_record(rng, "presets", false, "")
	assert_true(Appearance.preset_ids().has(str(preset.preset)), "Presets picks one of the presets")


# --------------------------------------------------------------------------- words, regions, presets

func test_the_summary_in_words() -> void:
	var lines := Appearance.summary_lines(Appearance.default_record())
	assert_eq(lines[0], "Hair: long, combed back, chestnut, a little grey", "the plan's example line")
	assert_true(lines[1].begins_with("Beard: full"), "the beard: %s" % lines[1])
	assert_true(lines.has("Tattoos: none") and lines.has("War paint: none") and lines.has("Scars: none"),
		"the empty designs say none")
	assert_true(lines.has("Ancestry mark: shown"), "the mark is shown")
	assert_eq(Appearance.grey_words(0.0), "", "no grey")
	assert_eq(Appearance.grey_words(0.4), "greying", "greying")
	assert_eq(Appearance.grey_words(0.9), "grey", "grey")
	var bare := Appearance.summary_lines(with({"beard": {"style": "beard.none"}, "mark": "none",
		"tattoos": {"arms": "tattoo.arm_bands"}}))
	assert_eq(bare[1], "Beard: none", "no beard: no colour")
	assert_true(bare.has("Ancestry mark: hidden"), "a hidden mark")
	var tat := ""
	for l: String in bare:
		if l.begins_with("Tattoos:"):
			tat = l
	assert_true(tat.contains("woad") and tat.contains("arm bands"), "a tattoo in its ink: %s" % tat)


func test_covered_regions_from_the_outfit_and_from_an_index() -> void:
	assert_eq(Appearance.covered_regions(Appearance.default_record()), PackedStringArray(), "the Wanderer hides none")
	assert_eq(Appearance.covered_regions(with({"outfit": {"set": "outfit.warrior"}})),
		PackedStringArray(["chest", "back"]), "the Warrior's tunic and jerkin hide the chest and back")
	var index := {"garments": {"tunic": ["Garment_tunic_core", "Garment_tunic_limbs"], "belt": ["Garment_belt"]},
		"meshes": {"Garment_tunic_core": {"covers": [3, 4, 5, 6]}, "Garment_tunic_limbs": {"covers": [8]},
			"Garment_belt": {"covers": []}}}
	assert_eq(Appearance.covered_body_regions(["tunic", "belt"], index), PackedInt32Array([3, 4, 5, 6, 8]),
		"the body regions of the garments' meshes")
	var r := with({"outfit": {"set": "outfit.warrior"}})
	assert_eq(Appearance.covered_regions(r, {"garments": {"tunic": ["Garment_tunic_core"]},
		"meshes": {"Garment_tunic_core": {"covers": [3, 4, 5, 6]}}}), PackedStringArray(["chest", "back"]),
		"with an index: a design region is hidden when all its body regions are")


func test_every_preset_is_valid_and_names_itself() -> void:
	var ids := Appearance.preset_ids()
	assert_eq(ids.size(), 8, "eight presets")
	for id: String in ids:
		var r := Appearance.preset_record(id)
		assert_eq(str(r.get("preset", "")), id, "%s names itself" % id)
		assert_true(Appearance.is_valid(r, ""), "%s is valid before any line (offered at New Game)" % id)
		assert_eq(Appearance.summary_lines(r).size(), 9, "%s reads in nine lines" % id)
	assert_true(ids.has(Appearance.DEFAULT_PRESET), "the Wanderer is one of them")
	assert_eq(Appearance.data_errors(GameData.records, GameData.record_paths), PackedStringArray(),
		"the data's own rules hold on the shipped data")
