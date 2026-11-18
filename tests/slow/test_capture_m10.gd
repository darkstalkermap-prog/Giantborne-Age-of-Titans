extends IntegrationSuite
## M10 gate (LC-7): the M10 capture tour (scripts/debug/capture_m10.gd, --scenario=capture_m10) holds the
## mouse captured, as a player's is while they play. The autopilot never captures it, so before this every
## third-person frame of the tour and its whole video carried the HUD's "Click the game to control the
## camera" across the giant (ui/hud.gd shows the hint whenever the mouse is free). Headless there is no
## mouse to capture, so the suite reads the mode the tour asks for on every tick (`mouse_mode_asked`) and
## that the HUD's rule hides the hint for exactly that mode; the frames themselves are the capture run's
## (docs/systems/P43.md).

func test_the_tour_holds_the_mouse_captured_from_its_first_tick() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var tour := CaptureM10.new(null)
	assert_eq(tour.mouse_mode_asked, -1, "nothing asked before the first step")
	assert_false(tour.step(p, 1.0 / float(Sim.TICK_RATE)), "the tour runs")
	assert_eq(tour.mouse_mode_asked, int(Input.MOUSE_MODE_CAPTURED), "the first tick asks for the captured mouse")
	# a free mouse in between (a lost focus, a screen that opened): the next tick takes it back
	tour.mouse_mode_asked = int(Input.MOUSE_MODE_VISIBLE)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tour.step(p, 1.0 / float(Sim.TICK_RATE))
	assert_eq(tour.mouse_mode_asked, int(Input.MOUSE_MODE_CAPTURED), "and every tick after it")
	assert_true(tour.beat_names().size() >= 35 and tour.beat_names()[0] == "idle", "the tour's beats (%d)" % tour.beat_names().size())
	tour.dispose()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The HUD's click hint is the frame's banner: it shows for a free mouse and never for a captured one.
func test_the_huds_click_hint_is_for_a_free_mouse_only() -> void:
	var src := FileAccess.get_file_as_string("res://ui/hud.gd")
	assert_true(src.contains("_capture_hint.visible = not _death.visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED"),
		"the hint follows the mouse mode the tour asks for")
	var tour_src := FileAccess.get_file_as_string("res://scripts/debug/capture_m10.gd")
	assert_true(tour_src.contains("Input.mouse_mode = Input.MOUSE_MODE_CAPTURED"), "the tour sets it on Input, not only its record")
