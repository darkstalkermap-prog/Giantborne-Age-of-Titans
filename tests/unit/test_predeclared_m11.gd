extends TestSuite
## The M11 pre-declarations of Part A (P49; plan M11 §1.5, §2.11, §3.2): the anchors P50-P66 are in
## events.gd, after M10's and in package order, with no signal among them (M11 adds no gameplay event);
## anchors_expected lists them with P49 as their creator; ResetHooks.AFTER_EACH resets the giant's
## secondary motion (P50's file: skipped silently until it exists, and it must exist once P50 has
## merged); and the build knows the staged budgets and the people's share before any file of theirs
## exists (tools/build_web.sh, tools/pck_files.py - parsed here, run by test_build_web_budget).
## Part B's registries are P53's (test_predeclared_m12) and Part C's P59's (test_predeclared_m13).

const EVENTS_PATH := "res://scripts/core/events.gd"
const SECONDARY_MOTION := "res://scripts/presentation/secondary_motion.gd"
const BUILD_WEB := "res://tools/build_web.sh"
const PCK_FILES := "res://tools/pck_files.py"
const M11_PACKAGES := ["P50", "P51", "P52", "P53", "P54", "P55", "P56", "P57", "P58", "P59", "P60", "P61",
	"P62", "P63", "P64", "P65", "P66"]


## True once `owner`'s package has merged (its system doc is in the tree).
func _merged(owner: String) -> bool:
	return FileAccess.file_exists("res://docs/systems/%s.md" % owner)


func test_the_m11_anchors_follow_m10s_in_package_order() -> void:
	var text := FileAccess.get_file_as_string(EVENTS_PATH)
	var last := text.find("## @anchor P47\n")
	assert_true(last > 0, "events.gd keeps M10's last anchor")
	for pkg: String in M11_PACKAGES:
		assert_eq(text.count("## @anchor %s\n" % pkg), 1, "events.gd has the anchor %s once" % pkg)
		var at := text.find("## @anchor %s\n" % pkg)
		assert_true(at > last, "anchor %s comes after the one before it" % pkg)
		last = at
	for pkg: String in ["P48", "P49"]:
		assert_eq(text.count("## @anchor %s\n" % pkg), 0, "%s has no anchor (plan M11 §3.2: P50-P66)" % pkg)


func test_m11_declares_no_signal_at_its_start() -> void:
	# Plan M11 §2.11: "Signal: none new". What a later package adds below its own anchor is its own;
	# this package's block is anchors only, and the M10 signal list is what it was.
	var text := FileAccess.get_file_as_string(EVENTS_PATH)
	var block := text.find("# M11 (written by P49")
	assert_true(block > text.find("## @anchor P47\n"), "the M11 block follows M10's anchors")
	if not _merged("P50"):
		assert_false(text.substr(block).contains("\nsignal "), "no signal under the M11 anchors yet")
	assert_true(Events.has_signal("appearance_changed"), "M10's signal is still declared")


func test_the_anchor_rows_name_p49_their_creator() -> void:
	var listed: Array = []
	for row: Array in AnchorsExpected.TABLE:
		if str(row[0]) == EVENTS_PATH and str(row[1]) == "P49":
			for p: Variant in row[2]:
				listed.append(str(p))
	assert_eq(listed, M11_PACKAGES, "anchors_expected lists events.gd's M11 anchors with P49 as the creator")
	assert_eq(AnchorsExpected.EVENTS_PACKAGES_M11, M11_PACKAGES, "EVENTS_PACKAGES_M11")
	assert_true(AnchorsExpected.creator_landed("P49"), "P49's rows are checked on this branch")
	assert_true(AnchorsExpected.creator_landed("P42"), "and M10's still are")


func test_reset_hooks_reset_the_secondary_motion() -> void:
	var hook := ["script", SECONDARY_MOTION, "reset_for_tests"]
	var at := -1
	var skin := -1
	for i in ResetHooks.AFTER_EACH.size():
		var e: Array = ResetHooks.AFTER_EACH[i]
		if e.slice(0, 3) == hook:
			at = i
		if str(e[1]).ends_with("skinned_rig.gd"):
			skin = i
	assert_true(at >= 0, "ResetHooks.AFTER_EACH resets SecondaryMotion after every test (P50)")
	assert_true(skin >= 0 and at > skin, "after the skinned rig's own reset")
	assert_true(at < ResetHooks.AFTER_EACH.size() - 1, "and the world index cache stays the last entry")
	assert_true(str((ResetHooks.AFTER_EACH.back() as Array)[1]).ends_with("world_index.gd"), "world_index.gd is last")
	if ResourceLoader.exists(SECONDARY_MOTION):
		assert_true(ResetHooks.has_callable(load(SECONDARY_MOTION), "reset_for_tests"),
			"SecondaryMotion has the static reset_for_tests the hook calls")
	else:
		assert_false(_merged("P50"), "secondary_motion.gd exists once P50 has merged")
		assert_true(ResetHooks.resolve(hook, get_tree()) == null, "until then the entry is skipped silently")
		var problems: PackedStringArray = await ResetHooks.run([hook], get_tree())
		assert_eq(problems.size(), 0, "and running it reports nothing")


func test_the_build_knows_the_staged_budgets_and_the_peoples_share() -> void:
	var sh := FileAccess.get_file_as_string(BUILD_WEB)
	for needle: String in ["--people-share-mb=", "PEOPLE_SHARE", "--people-share", "PEOPLE_FROM_MILESTONE=13",
			"PEOPLE_SHARE_CAP_MB=12.0", "OTHER_SHARE_MB=18.4", "PEOPLE_SHARE_CAP_MB=14.0"]:
		assert_true(sh.contains(needle), "build_web.sh has %s" % needle)
	# The giant pipeline's estimate (tools/giant/build_giant.py, web_budget_mib) reads the LAST default
	# this script assigns: it must stay the current milestone's.
	var re := RegEx.create_from_string("\\bBUDGET_MB=([0-9]+(?:\\.[0-9]+)?)\\b")
	var found: Array = []
	for m: RegExMatch in re.search_all(sh):
		found.append(m.get_string(1))
	for mb: String in ["7.5", "21", "23", "26", "32", "44", "46"]:
		assert_true(found.has(mb), "build_web.sh assigns a default budget of %s MB" % mb)
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var milestone := int(version.get_slice("-m", 1)) if version.contains("-m") else 6
	# (A1b: 46 MB from -m14, the owner's raised download cap)
	var current := "26" if milestone <= 11 else ("32" if milestone == 12 else ("44" if milestone == 13 else "46"))
	assert_eq(str(found.back()), current, "the last default assigned is %s's own (%s MB)" % [version, current])
	var py := FileAccess.get_file_as_string(PCK_FILES)
	for needle: String in ["--people-share", "PEOPLE_PREFIXES", "\"assets/people/\"", "\"assets/creatures/\"",
			"\"scenes/people/\"", "\"scenes/creatures/\"", "PEOPLE_SHARE people_bytes="]:
		assert_true(py.contains(needle), "pck_files.py has %s" % needle)
