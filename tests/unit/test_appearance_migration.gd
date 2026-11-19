extends TestSuite
## The look record's migration from version 1 to 2 (P53; plan M11 §2.5, §2.13, §3.6): every M10 preset as
## 0.10.0-m10 shipped it draws through Appearance.migrate exactly the meshes, designs and colours M10's own code
## drew (tests/support/appearance_v1_oracle.gd, M10's Appearance kept unchanged), new keys aside, describes itself
## in the same words and is the shipped version-2 preset; the rest of the matrix - a record per M10 option of every
## set, every outfit in every dye pair, random M10 records - is tests/slow/test_appearance_migration_matrix.gd's
## (about 1.5 s, over the default tier's share); migrate is one pure step; every M10 save fixture and 26 broken shapes (and their version-2 equivalents)
## load without a failure; the version-2 fixtures (an unknown slot item, a garment in the wrong slot, a broken
## `slots`) and a future version 3 are repaired or kept as §2.5 says. Pure: no node, no scene.

const Oracle := preload("res://tests/support/appearance_v1_oracle.gd")
const M10_PRESETS := "res://tests/fixtures/appearance/m10_presets.json"
const SAVES := "res://tests/fixtures/saves/"
const LINES := ["", "ancestry.stoneblood", "ancestry.stormborn", "ancestry.wildheart"]
## Plan M10 §2.4: hex-parsed colours may differ in the last bit.
const COLOR_TOLERANCE := 1.0 / 255.0 + 1e-6


func after_each() -> void:
	Appearance.cli_preset = ""
	Oracle.cli_preset = ""


static func _m10_presets() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(M10_PRESETS))
	return (d as Dictionary).presets if typeof(d) == TYPE_DICTIONARY else {}


static func _near(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_COLOR and typeof(b) == TYPE_COLOR:
		var ca: Color = a
		var cb: Color = b
		return absf(ca.r - cb.r) <= COLOR_TOLERANCE and absf(ca.g - cb.g) <= COLOR_TOLERANCE \
			and absf(ca.b - cb.b) <= COLOR_TOLERANCE and absf(ca.a - cb.a) <= COLOR_TOLERANCE
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) <= 1e-6
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not _near(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _near(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


## An M10 look's garments as the version-2 look gives them: index garment -> its dye (each mesh of a garment took
## the primary, the secondary or its natural colour by its material: test_giant_look_real checks the material
## against the real index's dye slots).
static func _m10_garments(old: Dictionary) -> Dictionary:
	var out := {}
	for g: Variant in old.garments:
		var material := ""
		for id: String in Appearance.option_ids("garment"):
			if str(Appearance.option(id).get("mesh", "")) == str(g):
				material = str(Appearance.option(id).material)
		match material:
			"cloth":
				out[str(g)] = old.dye_primary
			"leather":
				out[str(g)] = old.dye_secondary
			_:
				out[str(g)] = Appearance.FUR_COLOR
	return out


## "" when the version-2 look `now` draws what M10's look `old` drew (the same meshes, designs and colours; the new
## keys at their defaults), else what differs.
static func look_difference(old: Dictionary, now: Dictionary) -> String:
	for k: Variant in old:
		if str(k) in ["garments", "dye_primary", "dye_secondary", "paint"]:
			continue
		if not now.has(k) or not _near(old[k], now[k]):
			return "%s: M10 %s, now %s" % [k, old[k], now.get(k)]
	var paints: Array = []
	if not (old.paint as Dictionary).is_empty():
		paints.append(old.paint)
	if not _near(paints, now.paint):
		return "paint: M10 %s, now %s" % [old.paint, now.paint]
	var want := _m10_garments(old)
	var got := {}
	for g: Dictionary in now.garments:
		got[str(g.mesh)] = g.dye
	if not _near(want, got):
		return "garments: M10 %s, now %s" % [want, got]
	if now.build != Vector2.ZERO or not (now.accessories as Array).is_empty() or str(now.hair_beads) != "" \
			or str(now.beard_beads) != "":
		return "new keys: build %s, accessories %s, beads %s / %s" % [now.build, now.accessories, now.hair_beads, now.beard_beads]
	for k: Variant in now.face:
		if float(now.face[k]) != 0.0:
			return "face: %s" % [now.face]
	return ""


## Checks one version-1 record for a giant of `line` against the oracle: the look, the summary, the covered regions.
func check_migrated(r: Dictionary, line: String, label: String) -> void:
	var old: Dictionary = Oracle.to_look(r, line)
	var migrated := Appearance.migrate(r)
	assert_eq(int(migrated.get("v", 0)), Appearance.RECORD_VERSION, "%s: migrate gives version 2" % label)
	var diff := look_difference(old, Appearance.to_look(migrated, line))
	assert_eq(diff, "", "%s (%s): the migrated record draws what M10 drew" % [label, line])
	assert_eq(look_difference(old, Appearance.to_look(r, line)), "", "%s (%s): and so does the record as loaded" % [label, line])
	assert_eq(Appearance.summary_lines(migrated, line), Oracle.summary_lines(r, line), "%s (%s): in the same words" % [label, line])
	assert_eq(Appearance.covered_regions(migrated), Oracle.covered_regions(r), "%s: the same regions hidden" % label)


# --------------------------------------------------------------------------- the matrix

func test_every_m10_preset_migrates_to_the_look_it_drew() -> void:
	var presets := _m10_presets()
	assert_eq(presets.size(), 8, "M10's eight presets")
	for id: Variant in presets:
		var r: Dictionary = presets[id]
		assert_eq(int(r.v), 1, "%s: a version-1 record" % id)
		for line: String in LINES:
			check_migrated(r, line, str(id))
		var s := Appearance.sanitize(r)
		assert_true(bool(s.migrated), "%s: sanitize says it migrated" % id)
		assert_true((s.dropped as PackedStringArray).is_empty() and (s.notes as PackedStringArray).is_empty(),
			"%s: nothing dropped, nothing noted" % id)
		var now := Appearance.preset_record(str(id))
		now.erase("preset")
		var kept: Dictionary = (s.record as Dictionary).duplicate(true)
		kept.erase("preset")
		assert_true(_near(kept, now), "%s: the shipped version-2 preset is its M10 record migrated" % id)


## A hand-made M10 record with more than four known scars (M10 wore the first four) and its other edges: unknown ids
## reported as M10 reported them, a missing block filled from the default as M10 filled it.
func test_the_edges_of_a_version_1_record() -> void:
	var scars := Array(Oracle.option_ids("scar"))
	var r: Dictionary = Oracle.FALLBACK_RECORD.duplicate(true)
	r.scars = scars
	check_migrated(r, "", "six scars")
	assert_eq((Appearance.to_look(r).scars as Array).size(), Oracle.MAX_SCARS, "the first four, as M10 drew them")
	var unknown := {"v": 1, "skin": "skin.violet", "outfit": {"set": "outfit.armour", "primary": "dye.gold_leaf"},
		"paint": {"design": "paint.sun_disc"}, "scars": ["scar.dragon", "scar.brow"]}
	var old := Oracle.sanitize(unknown)
	var now := Appearance.sanitize(unknown)
	var a := Array(old.dropped)
	var b := Array(now.dropped)
	a.sort()
	b.sort()
	assert_eq(b, a, "the dropped ids are M10's")
	assert_eq(look_difference(Oracle.to_look(unknown), Appearance.to_look(unknown)), "", "and the look M10 drew")
	for partial: Dictionary in [{}, {"v": 1}, {"v": 1, "outfit": {}}, {"v": 1, "paint": {}}, {"v": 1, "hair": {"grey": 0.9}},
			{"outfit": {"set": "outfit.raider"}}, {"v": 1, "outfit": {"secondary": "dye.bone"}}]:
		assert_eq(look_difference(Oracle.to_look(partial), Appearance.to_look(partial)), "", "%s: the look M10 drew" % [partial])


func test_migrate_is_one_pure_step() -> void:
	var r: Dictionary = _m10_presets()["appearance_preset.ash_raider"]
	var before := r.duplicate(true)
	var once := Appearance.migrate(r)
	assert_true(_near(r, before), "the input is not changed")
	assert_true(_near(Appearance.migrate(once), once), "a version-2 record is returned as it is")
	assert_false(once.has("primary") or (once.outfit as Dictionary).has("primary"), "primary and secondary are moved")
	assert_eq(str(once.outfit.dyes.cloth), "dye.walnut", "primary -> the cloth dye")
	assert_eq(str(once.outfit.dyes.leather), "dye.bone", "secondary -> the leather dye")
	assert_eq([str(once.paint.face), str(once.paint.body)], ["", "paint.back_hand"], "the hand print goes on the body")
	assert_eq(str(once.outfit.slots.shins.item), "garment.leg_wraps", "the leg wraps go to the shins (plan M11 §2.5)")
	for g: String in Appearance.M10_SLOTS:
		assert_eq(str(Appearance.option("garment." + g).get("slot", "")), str(Appearance.M10_SLOTS[g]),
			"%s is worn in the %s slot" % [g, Appearance.M10_SLOTS[g]])
	var future := {"v": 3, "outfit": {"primary": "dye.madder"}}
	assert_true(_near(Appearance.migrate(future), future), "a later version is not touched")
	var extra: Dictionary = r.duplicate(true)
	extra["horns"] = "ram"
	assert_eq(str(Appearance.migrate(extra).get("horns", "")), "ram", "a key M10 did not know is kept")


# --------------------------------------------------------------------------- never a failed load

## The M10 gate's 26 broken shapes (lens 4: a look that is not a record, a record of the wrong types, a version that
## is not one) and their version-2 equivalents: each loads - a record comes back that sanitizes cleanly and draws.
static func broken_shapes() -> Array:
	var out: Array = ["a string", 7, 2.5, true, [1, 2], null, {"v": 0}, {"v": -1}, {"v": "one"}, {"v": 1.5}, {"v": [1]},
		{"skin": 3}, {"eyes": ["blue"]}, {"preset": 5}, {"mark": false}, {"hair": "long"}, {"hair": {"style": 4}},
		{"beard": [1]}, {"beard": {"color": 9}}, {"tattoos": "many"}, {"tattoos": {"arms": 4}}, {"paint": 3},
		{"paint": {"design": 2}}, {"outfit": "warrior"}, {"outfit": {"primary": 1}}, {"scars": "brow"}]
	return out


func test_the_26_broken_shapes_and_their_version_2_equivalents_load() -> void:
	var shapes := broken_shapes()
	assert_eq(shapes.size(), 26, "the 26 broken shapes")
	var v2 := ["a string", {"v": 2, "build": 0.5}, {"v": 2, "face": "round"}, {"v": 2, "paint": {"face": 1}},
		{"v": 2, "paint": {"body": [1]}}, {"v": 2, "outfit": {"dyes": "red"}}, {"v": 2, "outfit": {"dyes": {"metal": 2}}},
		{"v": 2, "outfit": {"set": 3}}, {"v": 2, "hair": {"beads": 1}}, {"v": 2, "beard": {"beads": []}},
		{"v": 2, "tattoos": {"legs": 7}}, {"v": 2, "outfit": {"slots": "all"}}, {"v": 2, "outfit": {"slots": {"legs": 5}}},
		{"v": 2, "outfit": {"slots": {"legs": {"item": 5}}}}, {"v": 2, "outfit": {"slots": {"legs": {"dye": []}}}},
		{"v": 2, "outfit": {"accessories": 4}}, {"v": 2, "scars": {"a": 1}}, {"v": 2.5}, {"v": 2, "skin": 3}]
	for shape: Variant in shapes + v2:
		var s := Appearance.sanitize(shape)
		var rec: Dictionary = s.record
		assert_eq(Appearance.structure_errors(rec), PackedStringArray(), "%s: a readable record comes back" % [shape])
		assert_eq(Appearance.sanitize(rec).notes, PackedStringArray(), "%s: which sanitizes cleanly" % [shape])
		assert_false((s.notes as PackedStringArray).is_empty(), "%s: and the player is told (%s)" % [shape, s.notes])
		assert_false((Appearance.to_look(shape).garments as Array).is_empty(), "%s: it draws" % [shape])
		var character := {"definition_id": "player.giant", "level": 1, "appearance": shape}
		var c := CharacterState.sanitize(character)
		assert_true((c.data as Dictionary).has("appearance"), "%s: the character keeps a look" % [shape])


## Every M10 save fixture loads: those without a look keep none (absent stays absent), the M10 looks are migrated
## with the one note, the unknown ids reported as M10 reported them, a broken look is the default.
func test_every_m10_fixture_loads() -> void:
	var n := 0
	for f: String in DirAccess.get_files_at(SAVES):
		if not f.ends_with(".json") or f.begins_with("v2_appearance_v"):
			continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVES + f))
		assert_true(typeof(doc) == TYPE_DICTIONARY, "%s parses" % f)
		var data: Dictionary = SaveSlots.migrate(doc)
		assert_eq(SaveSlots.validate(data), PackedStringArray(), "%s validates" % f)
		var clean := SaveSlots.sanitize(data)
		var had: bool = (doc.character as Dictionary).has("appearance")
		assert_eq((clean.data.character as Dictionary).has("appearance"), had, "%s: a look only where it had one" % f)
		if had:
			var rec: Dictionary = clean.data.character.appearance
			assert_eq(int(rec.v), Appearance.RECORD_VERSION, "%s: the look is version 2 in memory" % f)
			assert_eq(Appearance.structure_errors(rec), PackedStringArray(), "%s: and readable" % f)
		else:
			assert_false((clean.data.world.get("flags", {}) as Dictionary).has(SaveSlots.SLOTS_SEEN_FLAG),
				"%s: no look, no flag" % f)
		n += 1
	assert_true(n >= 13, "every M10 fixture (%d)" % n)
	var v1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVES + "v2_appearance.json"))
	var s := Appearance.sanitize(v1.character.appearance)
	assert_true(bool(s.migrated), "v2_appearance.json's look is migrated")
	assert_eq(look_difference(Oracle.to_look(v1.character.appearance), Appearance.to_look(v1.character.appearance)), "",
		"and draws what it drew")
	var unknown: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVES + "v2_appearance_unknown_ids.json"))
	var a := Array(Oracle.sanitize(unknown.character.appearance).dropped)
	var b := Array(Appearance.sanitize(unknown.character.appearance).dropped)
	a.sort()
	b.sort()
	assert_eq(b, a, "the unknown ids are reported as M10 reported them")
	var odd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVES + "v2_appearance_future.json"))
	assert_eq(Appearance.sanitize(odd.character.appearance).notes, PackedStringArray([Appearance.NOTE_BROKEN]),
		"M10's imagined 'v 2' (a skin block) is not this build's version 2: the default look, never a failed load")


# --------------------------------------------------------------------------- the version-2 fixtures

func _fixture_look(f: String) -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVES + f + ".json"))
	return doc.character.appearance


func test_the_version_2_fixtures() -> void:
	var good := _fixture_look("v2_appearance_v2")
	var s := Appearance.sanitize(good)
	assert_true((s.dropped as PackedStringArray).is_empty() and (s.notes as PackedStringArray).is_empty(),
		"v2_appearance_v2: valid (%s / %s)" % [s.dropped, s.notes])
	assert_false(bool(s.migrated), "and not migrated")
	assert_true(_near(s.record, good), "kept as it is")
	var look := Appearance.to_look(good)
	assert_eq(look.build, Vector2(0.3, -0.2), "its build")
	assert_eq((look.paint as Array).size(), 2, "two war paints")
	assert_eq((look.scars as Array).size(), 5, "five scars")
	var legs: Dictionary = {}
	for g: Dictionary in look.garments:
		if str(g.mesh) == "braies":
			legs = g
	assert_true(_near(legs.get("dye"), Color.html(str(Appearance.option("dye.madder").color))), "the braies' own dye")
	var odd := _fixture_look("v2_appearance_v2_unknown_slot")
	var u := Appearance.sanitize(odd)
	for id: String in ["garment.mail_hauberk", "accessory.wolf_torc", "bead.amber"]:
		assert_true((u.dropped as PackedStringArray).has(id), "%s is reported" % id)
	assert_eq(str(u.record.outfit.slots.chest.item), "", "the unknown chest garment comes off")
	assert_eq(str(u.record.outfit.slots.head.item), "", "boots on the head come off")
	assert_true(str(u.notes).contains("garment.boots"), "with the note: %s" % [u.notes])
	assert_eq(str(u.record.outfit.slots.cape.item), "garment.cape", "the cape stays")
	assert_eq(str(u.record.outfit.slots.cape.dye), "", "its unknown dye is the outfit's")
	assert_true((u.record.outfit.slots as Dictionary).has("tail"), "a slot this build does not know is kept")
	var broken := _fixture_look("v2_appearance_v2_broken")
	var bs := Appearance.sanitize(broken)
	assert_eq(bs.notes, PackedStringArray([Appearance.NOTE_SLOTS]), "a broken slots block: the clothing's note")
	assert_true(_near(bs.record.outfit.slots, Appearance.default_record().outfit.slots), "the default clothing")
	assert_eq(str(bs.record.skin), str(broken.skin), "the rest of the look stays")
	assert_true(_near(bs.record.build, broken.build), "the build too")
	var future := _fixture_look("v2_appearance_v3_future")
	var fs := Appearance.sanitize(future)
	assert_eq(fs.notes, PackedStringArray([Appearance.NOTE_FUTURE]), "version 3: a later build's")
	assert_true(_near(fs.record, future), "kept untouched")
	assert_eq(JSON.stringify(fs.record, "", false), JSON.stringify(future, "", false), "byte for byte")
