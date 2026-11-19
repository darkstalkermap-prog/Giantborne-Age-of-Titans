extends TestSuite
## The migration matrix's long part (P53; plan M11 §2.5, §3.6): a record per M10 option of every set (the Wanderer of
## 0.10 with one option put on as M10's creator did, for the line that unlocks it), every outfit in every dye pair,
## and random M10 records from M10's own Randomize, each migrated and drawn against M10's code kept as the oracle
## (tests/support/appearance_v1_oracle.gd): the same meshes, designs and colours, the same words, the same regions
## hidden. The presets, the edges and the fixtures are tests/unit/test_appearance_migration.gd's (the default tier).

const Oracle := preload("res://tests/support/appearance_v1_oracle.gd")
const Migration := preload("res://tests/unit/test_appearance_migration.gd")
const LINES := Migration.LINES
## Random M10 records a scope.
const RANDOM_SEEDS := 40


func after_each() -> void:
	Appearance.cli_preset = ""
	Oracle.cli_preset = ""


## Checks one version-1 record for a giant of `line` against the oracle (Migration.check_migrated's rules).
func check_migrated(r: Dictionary, line: String, label: String) -> void:
	var old: Dictionary = Oracle.to_look(r, line)
	var migrated := Appearance.migrate(r)
	assert_eq(int(migrated.get("v", 0)), Appearance.RECORD_VERSION, "%s: migrate gives version 2" % label)
	assert_eq(Migration.look_difference(old, Appearance.to_look(migrated, line)), "",
		"%s (%s): the migrated record draws what M10 drew" % [label, line])
	assert_eq(Appearance.summary_lines(migrated, line), Oracle.summary_lines(r, line), "%s (%s): in the same words" % [label, line])
	assert_eq(Appearance.covered_regions(migrated), Oracle.covered_regions(r), "%s: the same regions hidden" % label)


## A record per M10 option: the Wanderer of 0.10 (the oracle's FALLBACK_RECORD) with one option put on the way
## M10's creator put it on, for the line that unlocks it.
func test_a_record_per_m10_option_migrates_to_the_look_it_drew() -> void:
	var n := 0
	for c: String in Oracle.CATEGORIES:
		for id: String in Oracle.option_ids(c):
			var o := Oracle.option(id)
			var line := Oracle.required_ancestry(o)
			var r: Dictionary = Oracle.FALLBACK_RECORD.duplicate(true)
			match c:
				"skin", "eyes":
					r[c] = id
				"hair":
					r.hair.style = id
				"haircolor":
					r.hair.color = id
					r.beard.color = id
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
					r.mark = Oracle.MARK_AUTO
				"outfit":
					r.outfit.set = id
				"dye":
					r.outfit.primary = id
					r.outfit.secondary = Oracle.option_ids("dye")[(Oracle.option_ids("dye").find(id) + 3) % Oracle.option_ids("dye").size()]
			check_migrated(r, line, id)
			if c in ["outfit", "dye"]:
				for outfit: String in Oracle.option_ids("outfit"):   # every outfit in a dye pair, every dye on every outfit
					var o2 := r.duplicate(true)
					o2.outfit.set = outfit
					check_migrated(o2, line, "%s on %s" % [id, outfit])
			n += 1
	assert_true(n >= 99, "every option of M10's thirteen sets (%d)" % n)


## Random M10 records (M10's own Randomize from the Wanderer of 0.10; its Presets scope reads this build's version-2
## presets, so it is left out: the presets are the default tier's).
func test_random_m10_records_migrate_to_the_looks_they_drew() -> void:
	var rng := RandomNumberGenerator.new()
	var n := 0
	for scope: String in Oracle.RANDOM_SCOPES:
		if scope == "presets":
			continue
		for seed in RANDOM_SEEDS:
			rng.seed = seed * 104729 + scope.hash()
			var line: String = LINES[seed % LINES.size()]
			var r: Dictionary = Oracle.random_record(rng, scope, seed % 2 == 0, line, Oracle.FALLBACK_RECORD.duplicate(true))
			var diff := Migration.look_difference(Oracle.to_look(r, line), Appearance.to_look(r, line))
			assert_eq(diff, "", "%s seed %d (%s): the look M10 drew" % [scope, seed, line])
			n += 1
	assert_true(n >= 9 * RANDOM_SEEDS, "%d random M10 records" % n)
