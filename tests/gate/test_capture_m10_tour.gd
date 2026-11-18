extends TestSuite
## M10 gate (LC-7 and its aside): the whole M10 capture tour (scripts/debug/capture_m10.gd,
## --scenario=capture_m10) in a child Godot, headless (no frame is drawn; every beat still runs): it ends,
## with 0 errors, and the game refuses none of its beats. Before the gate the throw beat cast
## ability.throw_held through a loadout slot, which the game refuses, so the giant kept the soldier in his
## hand and Heavy Footfall, Thunder Roar and Stone Skin were refused after it: the tour's frames 20 to 23
## showed him standing with "[E] Put down" and the notes said nothing. Now the tour notes every cast that
## has not started by its beat's shot, throws as a player does (PlayerGrab.try_throw), and fells the arena's
## soldiers before the growth beats (the one thrown walks back and stands in the way of every growth).
## The mouse the tour holds captured is tests/slow/test_capture_m10.gd's. About 12 s.

const RESULT_PREFIX := "AUTOPILOT_RESULT "


func test_the_tour_ends_with_every_beat_run() -> void:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--",
		"--no-user-settings", "--no-audio", "--scenario=capture_m10", "--skin"])
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
	var tour: Dictionary = r.get("capture_m10", {})
	assert_eq(int(r.get("errors", -1)), 0, "0 errors (%s)" % str(r.get("error_samples", [])))
	assert_true(bool(tour.get("complete", false)), "the tour reached its end")
	assert_eq(tour.get("notes", ["?"]), [], "no beat was refused and every cast ran by its shot")
	var shots: Array = tour.get("shots", [])
	assert_eq(shots.size(), 38, "its 38 frames")
	for beat: String in ["throw", "stomp", "roar", "self_buff", "stage_6", "earthquake", "death"]:
		var found := false
		for s: String in shots:
			found = found or s.ends_with("_%s.png" % beat)
		assert_true(found, "the %s beat took its frame" % beat)
