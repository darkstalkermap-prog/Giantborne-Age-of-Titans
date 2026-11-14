extends TestSuite
## M8 gate (F31; plan M6-M9 §6.6: at each release "the launcher's notes describe the build"): the play
## page and the project's own description keep step with the build they ship with. Before, at 0.8.0-m8's
## content, web/launcher.html still read "build 0.7.0-m7", growth "to 36 and 48 feet", "Growth to
## 48 ft" and a main quest that "pauses after Brannock's oath", and project.godot described "the Valley
## of Broken Kings slice (milestones M0-M5)" under version 0.7.0-m7.
##   * the page's masthead names config/version ("build 0.8.0-m8");
##   * the project's description counts the milestones up to its version's ("M0-M8" for "-m8");
##   * the page names the tallest growth stage's height (the growth records' display names: "62 ft") in
##     its pitch and in "About this build";
##   * the page names where the main quest ends (quest.world_main's last stage: the Stone Throne) and no
##     longer says it pauses.
## Files only (the default tier). tests/integration/test_web_presets.gd keeps the page's script.

const LAUNCHER := "res://web/launcher.html"
const MAIN_QUEST := "quest.world_main"


## The page's text with every run of white space made one space (its lines wrap mid-sentence).
func _html() -> String:
	var f := FileAccess.open(LAUNCHER, FileAccess.READ)
	var text := f.get_as_text() if f != null else ""
	return RegEx.create_from_string("\\s+").sub(text, " ", true)


## The tallest growth stage's height in feet, from its record's display name ("Titan (62 ft)" -> 62).
static func tallest_feet() -> int:
	var best := 0
	var re := RegEx.create_from_string("\\((\\d+) ft\\)")
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		var m := re.search(str(rec.get("display_name", "")))
		if m != null:
			best = maxi(best, int(m.get_string(1)))
	return best


func test_the_masthead_names_the_version() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_true(version.contains("-m"), "config/version names its milestone (%s)" % version)
	assert_true(_html().contains("&middot; build %s</p>" % version), "the page's masthead names build %s" % version)


func test_the_description_counts_the_milestones_of_the_version() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var milestone := int(version.get_slice("-m", 1))
	var description := str(ProjectSettings.get_setting("application/config/description", ""))
	assert_true(description.ends_with("(milestones M0-M%d)." % milestone),
		"the description ends with the milestones up to M%d: %s" % [milestone, description])
	assert_false(description.contains("slice"), "and no longer calls the game the Valley slice")


func test_the_page_names_the_tallest_growth() -> void:
	var feet := tallest_feet()
	assert_true(feet >= 62, "the growth records reach %d ft" % feet)
	var html := _html()
	assert_true(html.contains("%d feet" % feet), "the pitch names %d feet" % feet)
	assert_true(html.contains("Growth to %d&nbsp;ft" % feet), "About this build: growth to %d ft" % feet)


func test_the_page_names_where_the_main_quest_ends() -> void:
	var stages: Array = GameData.get_record(MAIN_QUEST).get("stages", [])
	assert_true(not stages.is_empty(), "the main quest has stages")
	var last := str((stages[-1] as Dictionary).get("objective", "")) if not stages.is_empty() else ""
	assert_true(last.contains("Stone Throne"), "it ends on the Stone Throne (%s)" % last)
	var html := _html()
	assert_true(html.contains("<strong>the Stone Throne</strong>"), "the pitch says where the campaign ends")
	assert_true(html.contains("the campaign's end on the Stone Throne"), "and so does About this build")
	assert_false(html.contains("main quest pauses"), "and no longer that the main quest pauses")
