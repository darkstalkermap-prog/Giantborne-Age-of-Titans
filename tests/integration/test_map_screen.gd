extends IntegrationSuite
## P27 (plan M6-M9 §2.14, §3.10 design 2): the map screen on the stub level of
## tests/support/world_ux_fixtures.gd (an index and records built in code). What it shows
## (MapScreen.entries_for, pure): fog by chunk - a place in an unseen chunk is hidden unless it is a
## visited checkpoint -, POIs once known (found bright, revealed dim), sealed places once seen with a
## lock and their stage, a shrine POI shown by its shrine; the region lines with the recommended
## stage; the pin written and cleared ([x, z, level]); the three zoom levels and panning; the
## Valley's vector map and the world's picture; and the screen with a pad: D-pad between places, A
## on a place says why it cannot be travelled to, Y pins, B closes - and M closes it from a keyboard.

const Fx := preload("res://tests/support/world_ux_fixtures.gd")

var stack: ScreenStack


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	await super()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


static func _ids(entries: Array) -> Array:
	var out: Array = entries.map(func(e: Dictionary) -> String: return str(e.id))
	out.sort()
	return out


func test_what_the_map_shows_for_the_flags() -> void:
	var idx := Fx.install()
	assert_eq(MapScreen.entries_for(Fx.LEVEL, idx, {}), [], "nothing seen, nothing known: an empty map")
	var flags := {"visited.test.p27.cp_far": true, "map.seen.c2_3": true, "discovered.test_p27_town": true,
		"discovered.test_p27_ruin": Discovery.REVEALED, "sealed.test_p27_seal.seen": true,
		"discovered.test_p27_shrine": true, "map.seen.c3_2": true}
	var entries := MapScreen.entries_for(Fx.LEVEL, idx, flags)
	assert_eq(_ids(entries), ["poi.test_p27_ruin", "poi.test_p27_seal", "poi.test_p27_shrine", "poi.test_p27_town",
		"test.p27.cp_far", "test.p27.cp_start", "test.p27.exit"],
		"a visited checkpoint in the fog, a checkpoint and the exit in seen chunks, the known POIs and the seen sealed place")
	var by_id := {}
	for e: Dictionary in entries:
		by_id[str(e.id)] = e
	assert_true(bool(by_id["test.p27.cp_far"].visited) and not bool(by_id["test.p27.cp_start"].visited), "visited or not")
	assert_true(bool(by_id["poi.test_p27_town"].found), "the town was found")
	assert_true(bool(by_id["poi.test_p27_ruin"].revealed), "the ruin is only revealed (dim)")
	assert_true(bool(by_id["poi.test_p27_seal"].sealed) and int(by_id["poi.test_p27_seal"].stage) == 5,
		"the sealed place shows its lock and stage 5")
	flags["visited.test.p27.shrine"] = true
	entries = MapScreen.entries_for(Fx.LEVEL, idx, flags)
	assert_true(_ids(entries).has("test.p27.shrine") and not _ids(entries).has("poi.test_p27_shrine"),
		"once its shrine shows, the shrine POI is shown by the shrine alone")
	WorldState.record_destroyed(Fx.SEAL)
	entries = MapScreen.entries_for(Fx.LEVEL, idx, flags)
	for e: Dictionary in entries:
		if e.id == "poi.test_p27_seal":
			assert_false(bool(e.sealed), "a heaved seal opens the place on the map")
	var lines := MapScreen.detail_lines(by_id["poi.test_p27_town"], 3, idx)
	assert_true(lines.has("The North Test - recommended stage 4-5 (you are stage 3)"),
		"the region line warns below its recommended stage (%s)" % lines)
	assert_true(MapScreen.detail_lines(by_id["test.p27.cp_start"], 3, idx).has("Not visited yet."), "an unvisited stone")
	var regions := MapScreen.regions_for(Fx.LEVEL)
	assert_eq(regions.size(), 2, "the stub level's two region labels")


func test_the_screen_pin_zoom_and_pan() -> void:
	Fx.install()
	WorldState.set_flag("visited.test.p27.cp_start", true)
	WorldState.set_flag("visited.test.p27.cp_narrow", true)
	var map := stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	assert_true(map != null and stack.is_open("map"), "the map opens")
	assert_eq(WorldState.get_flag(Discovery.MAP_OPENED_FLAG), true, "map.opened (the tutorial's dismissal)")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(map.shown_level(), Fx.LEVEL, "the level asked for")
	assert_eq(_ids(map.entries()), ["test.p27.cp_narrow", "test.p27.cp_start"], "the two visited stones")
	assert_true(map.select("test.p27.cp_start"), "a place is selected")
	assert_true(map.panel_text().contains("Start stone") and map.panel_text().contains("Visited"), "the panel names it (%s)" % map.panel_text())
	map.pin_here()
	assert_eq(WorldState.get_flag(Discovery.PIN_FLAG), [0.0, 150.0, Fx.LEVEL], "the pin at the place, on this level")
	assert_eq(Discovery.pin_of(WorldState.flags), Vector2(0, 150), "the compass reads it")
	assert_true(map.pin_point().is_finite(), "drawn on this level's map")
	map.clear_pin()
	assert_eq(WorldState.get_flag(Discovery.PIN_FLAG), "", "cleared")
	assert_false(Discovery.pin_of(WorldState.flags).is_finite(), "no pin")
	assert_eq(map.zoom_level(), 0, "the whole map first")
	map.zoom_by(5)
	assert_eq(map.zoom_level(), 2, "three zoom levels: the closest is 2")
	map.zoom_by(-1)
	var c := map.map_center()
	map.pan_by(Vector2(40, 0))
	assert_true(map.map_center().x > c.x, "panning moves the map")
	assert_eq(map.selected_id(), "", "and drops the selection (pins go to the centre)")
	var probe := Vector2(30, -20)
	assert_true(map.to_map(map.to_screen(probe)).is_equal_approx(probe), "screen and map points convert both ways")
	var at := map.pin_here()
	assert_true(at.is_equal_approx(map.map_center()), "with nothing chosen the pin goes to the centre")
	assert_true(map.show_level("level.valley"), "the Valley's map")
	assert_true(MapScreen.map_bounds_for(WorldIndex.for_level("level.valley")).encloses(Rect2(-200, -200, 400, 400)),
		"its vector map covers the districts")
	assert_true(map.entries().any(func(e: Dictionary) -> bool: return e.id == "valley.shrine.hollow"),
		"every shrine of the Valley (no fog there)")
	assert_true(map.show_level("level.world"), "the world's map")
	var widx := WorldIndex.for_level("level.world")
	assert_eq(MapScreen.map_bounds_for(widx), widx.map_bounds, "the picture's bounds")
	assert_true(ResourceLoader.exists(widx.map_image), "and its picture")
	assert_eq(map.entries(), [], "an unexplored world: fog everywhere")
	map.close()


func test_the_map_with_a_pad() -> void:
	Fx.install()
	WorldState.set_flag("visited.test.p27.cp_start", true)
	WorldState.set_flag("visited.test.p27.cp_narrow", true)
	var map := stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	await get_tree().process_frame
	await get_tree().process_frame
	map.icon("test.p27.cp_narrow").grab_focus()
	await get_tree().process_frame
	assert_eq(map.selected_id(), "test.p27.cp_narrow", "focus selects the place")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(map.selected_id(), "test.p27.cp_start", "D-pad Right moves to the place on the right")
	assert_true(map.icon("test.p27.cp_start").has_focus(), "with the focus")
	await _pad(JOY_BUTTON_A)
	assert_true(map.panel_text().contains("no giant"), "A on a stone it cannot travel to says why (%s)" % map.panel_text())
	await _pad(JOY_BUTTON_Y)
	assert_eq(WorldState.get_flag(Discovery.PIN_FLAG), [0.0, 150.0, Fx.LEVEL], "Y pins the place")
	await _pad(JOY_BUTTON_B)
	assert_false(stack.is_open("map"), "B closes the map")
	map = stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_false(stack.is_open("map"), "M closes it again")
