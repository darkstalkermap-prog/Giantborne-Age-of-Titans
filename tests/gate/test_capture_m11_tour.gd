extends TestSuite
## P50 (plan M11 §3.3 item 7, its acceptance "the tour complete with 0 errors"): the M11 capture tour, part A
## (scripts/debug/capture_m11.gd, --scenario=capture_m11 --part=a) in a child Godot, headless with the skinned
## layers (no frame is drawn; every beat and every measure still runs): it ends with 0 errors, no beat refused
## and its frames named for the three views, and its measures hold -
##   * each moment's legs' source is its beat's (walking, the sprint's clip, turning both ways, airborne and the
##     landing, the stomp, the roar, Shoulder Charge's motion, bracing, the death);
##   * a flinch from each of the four sides played;
##   * over the generic poses the handle's line passes within 0.02 x k of the fist's centre;
##   * the secondary motion ran on every chain of the tour's look and never passed its limits.
## About 20 s.

const RESULT_PREFIX := "AUTOPILOT_RESULT "
const SOURCES := {"walk": "walking", "run": "walking", "sprint": "walking", "turn_left_30": "turning", "turn_right_30": "turning",
	"jump": "airborne", "land": "landing", "stomp_08": "stomp", "stomp_25": "stomp", "roar": "roar", "block": "bracing",
	"death_85": "dead", "shoulder_charge_15": "motion"}


func test_the_tour_ends_with_every_beat_and_its_measures() -> void:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--",
		"--no-user-settings", "--no-audio", "--scenario=capture_m11", "--part=a", "--skin"])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(RESULT_PREFIX):
			line = l.substr(RESULT_PREFIX.length()).strip_edges()
	var parsed: Variant = JSON.parse_string(line) if line != "" else null
	assert_eq(code, 0, "the tour ran (exit %d)" % code)
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "it reported: %s" % text.right(400))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var r: Dictionary = parsed
	var tour: Dictionary = r.get("capture_m11", {})
	assert_eq(int(r.get("errors", -1)), 0, "0 errors (%s)" % str(r.get("error_samples", [])))
	assert_true(bool(tour.get("complete", false)), "the tour reached its end")
	assert_eq(tour.get("notes", ["?"]), [], "no beat was refused and every cast ran by its shot")
	var shots: Array = tour.get("shots", [])
	assert_true(shots.size() >= 150, "its frames (%d)" % shots.size())
	for view: String in ["side", "front", "three_quarter"]:
		assert_true(shots.has("m11a_02_walk_%s.png" % view), "the walk from the %s" % view)
	var m: Dictionary = tour.get("measures", {})
	var legs: Dictionary = m.get("legs", {})
	for moment: String in SOURCES:
		assert_eq(str(legs.get(moment, "?")), SOURCES[moment], "%s: the legs' source" % moment)
	assert_true(float((m.get("gait", {}) as Dictionary).get("sprint", {}).get("sprint", 0.0)) > 0.9, "the sprint's clip shows")
	assert_true(float((m.get("gait", {}) as Dictionary).get("walk", {}).get("sprint", 1.0)) < 0.05, "and not on the walk")
	for side: String in ["f", "b", "l", "r"]:
		assert_true(bool((m.get("flinch_sides", {}) as Dictionary).get(side, false)), "a hit from %s flinched" % side)
	var grip: Dictionary = m.get("grip", {})
	assert_true(int(grip.get("frames", 0)) > 300, "the generic poses measured (%s)" % grip.get("frames"))
	assert_true(float(grip.get("handle_m", 1.0)) <= 0.02, "the handle within 0.02 x k of the fist's centre (%s)" % grip.get("handle_m"))
	var sec: Dictionary = m.get("secondary", {})
	assert_eq(sec.get("chains", []), ["beard", "cape_c", "cape_l", "cape_r", "hair", "hair_l", "hair_r"], "every chain ran")
	assert_true(float(sec.get("worst_over_limit_deg", 9.0)) <= 0.5, "within its limits (%s deg over)" % sec.get("worst_over_limit_deg"))
	print("    test_capture_m11_tour: %d frames; the grip %s; the reach %s; the secondary motion %s" % [shots.size(), grip,
		m.get("reach"), sec.get("worst_over_limit_deg")])


## P57 (plan M11 §3.10 item 6): part B, the wardrobe in play - every preset, the fullest look standing, walking,
## running, at stage 4 and in first person, the build sliders at their ends - ends with 0 errors and no note, its
## frames named for the three views (one in first person). About 25 s.
func test_part_b_dresses_every_preset_and_the_fullest_look() -> void:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--",
		"--no-user-settings", "--no-audio", "--scenario=capture_m11", "--part=b", "--skin"])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(RESULT_PREFIX):
			line = l.substr(RESULT_PREFIX.length()).strip_edges()
	var parsed: Variant = JSON.parse_string(line) if line != "" else null
	assert_eq(code, 0, "part b ran (exit %d)" % code)
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "it reported: %s" % text.right(400))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var tour: Dictionary = (parsed as Dictionary).get("capture_m11", {})
	assert_eq(int((parsed as Dictionary).get("errors", -1)), 0, "0 errors (%s)" % str((parsed as Dictionary).get("error_samples", [])))
	assert_eq(str(tour.get("part", "")), "b", "the part is b")
	assert_true(bool(tour.get("complete", false)), "part b reached its end")
	assert_eq(tour.get("notes", ["?"]), [], "no note")
	var shots: Array = tour.get("shots", [])
	var presets := Appearance.preset_ids().size()
	for pid in Appearance.preset_ids():
		var want := "_preset_%s_side.png" % pid.get_slice(".", 1)
		assert_true(shots.any(func(n: String) -> bool: return n.ends_with(want)), "the preset %s is filmed" % pid)
	assert_true(shots.size() >= 3 * (presets + 4) + 2, "its frames (%d)" % shots.size())
	assert_true(shots.any(func(n: String) -> bool: return n.begins_with("m11b_") and n.ends_with("_fullest_fp_game.png")),
		"the fullest look in first person")
