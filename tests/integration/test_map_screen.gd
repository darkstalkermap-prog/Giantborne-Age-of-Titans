extends IntegrationSuite
## P27 (plan M6-M9 §2.14, §3.10 design 2): the map screen on the stub level of
## tests/support/world_ux_fixtures.gd (an index and records built in code). What it shows
## (MapScreen.entries_for, pure): fog by chunk - a place in an unseen chunk is hidden unless it is a
## visited checkpoint -, POIs once known (found bright, revealed dim), sealed places once seen with a
## lock and their stage, a shrine POI shown by its shrine; the region lines with the recommended
## stage; the pin written and cleared ([x, z, level]); the three zoom levels and panning; the
## Valley's vector map and the world's picture; and the screen with a pad: D-pad between places, A
## on a place says why it cannot be travelled to, Y pins, B closes - and M closes it from a keyboard;
## the panel lists the controls of the device in use. The pad's D-pad opens the map and the journal
## and tracks the next quest only without LT: with LT held it stays ability slots 6-8.

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
	InputBindings.reset_device()
	await super()


## One press and release of a pad button; the device is noted as main.gd's _input does in the game.
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		InputBindings.note_device(e)
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
	assert_true(map.hint_text().contains("P or right click: pin") and map.hint_text().contains("Esc / M: close"),
		"the panel lists the keyboard and mouse controls (%s)" % map.hint_text())
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
	assert_false(map.pin_point().is_finite(), "the pin stays on its own level's map")
	assert_true(Discovery.pin_on(WorldState.flags, Fx.LEVEL).is_finite() and not Discovery.pin_on(WorldState.flags,
		"level.valley").is_finite(), "and its compass: pin_on() reads it on its level only")
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
	assert_true(map.hint_text().contains("A: choose   Y: pin   B: close"), "the panel lists the pad's controls now")
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


## Plan §2.14: map, journal and track_next are D-pad Down, Right and Left "without LT". With LT held
## those presses are ability slots 6-8, which the giant's InputRouter takes before the screen stack
## and the HUD see them: main.gd adds its UI layer (the HUD, the stack) before the level, and Godot
## hands unhandled input to the last node in the tree first. This world is built in the same order:
## the layer (before_each), then the router.
func test_lt_keeps_the_d_pad_for_the_abilities() -> void:
	QuestFixtures.install([
		QuestFixtures.quest("quest.test_main", [QuestFixtures.stage("go", QuestFixtures.flag_cond("test.flag.never"))]),
		QuestFixtures.quest("quest.test_side", [QuestFixtures.stage("go", QuestFixtures.flag_cond("test.flag.never"))]),
	])
	QuestFixtures.activate(["quest.test_main", "quest.test_side"], [], "quest.test_main")
	stack.get_parent().add_child(Hud.new())
	var router := InputRouter.new()
	world.add_child(router)
	await step_ticks(2)
	assert_true(stack.get_parent().get_index() < router.get_index(), "the UI layer comes before the router, as in main.gd")
	assert_eq(Quests.tracked_id(), "quest.test_main", "the main quest is followed")
	Input.action_press("ability_modifier")
	for b: JoyButton in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]:
		await _pad(b)
	Input.action_release("ability_modifier")
	assert_eq(router.consume().edges, [&"slot_6", &"slot_7", &"slot_8"] as Array,
		"LT + D-pad Right / Down / Left: ability slots 6, 7 and 8")
	assert_false(stack.any_open(), "neither the map nor the journal opened")
	assert_eq(Quests.tracked_id(), "quest.test_main", "and the tracked quest stayed")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(Quests.tracked_id(), "quest.test_side", "D-pad Left alone tracks the next quest")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(stack.is_open("map"), "D-pad Down alone opens the map")
	stack.close_all()
	await get_tree().process_frame
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_true(stack.is_open("journal"), "D-pad Right alone opens the journal")
	assert_eq(router.consume().edges, [] as Array, "and none of them fired an ability")


## P39f (FOLLOWUPS, "From the M8 screenshot pass": "the map's labels overlap"): the real world's map at its
## fullest - every place found, every chunk seen, every stone visited, a pin - at each zoom level, centred on
## each settlement and on the crowded Kingsgate: no label covers another label or any mark (an icon, the pin),
## none is cut by the view's edge, the place in focus always shows, and on the whole map every region's label
## and every settlement's name shows. (On the screenshot pass's frames "Hollowmere" printed over "THE
## GREYWOOD", "Greywood Shrine" over "Needle waystone", icons sat on "THE CROWNMARCH" and "The Broken Stair".)
## M9 gate (lane review): then again in the campaign with the raid on Millford tracked - its diamond on the map -
## and the pin between the Kingsgate shrine and its shelf. The review's frame: the Kingsgate Shrine in focus at
## zoom 0 had none of its 8 spots free, and its label went over the diamond and Millford's icon (_place took its
## first spot whatever it covered); now it finds a spot farther out.
func test_the_world_map_labels_never_overlap() -> void:
	var idx := WorldIndex.for_level(GameSession.WORLD_LEVEL_ID)
	assert_true(idx != null, "the world's index")
	if idx == null:
		return
	for id: String in Discovery.poi_table(GameSession.WORLD_LEVEL_ID):
		WorldState.set_flag(Discovery.discovered_flag(id), true)
	var g := Discovery.chunk_grid(GameSession.WORLD_LEVEL_ID)
	var n: Vector2i = g.grid
	for z in n.y:
		for x in n.x:
			WorldState.set_flag(Discovery.seen_flag("c%d_%d" % [x, z]), true)
	for id: String in idx.checkpoint_ids():
		WorldState.set_flag(GameSession.VISITED_PREFIX + id, true)
	WorldState.set_flag(Discovery.PIN_FLAG, [-560.0, -260.0, GameSession.WORLD_LEVEL_ID])
	var map := stack.open("map", {"level": GameSession.WORLD_LEVEL_ID}) as MapScreen
	await get_tree().process_frame
	var font := map.view.get_theme_default_font()
	var bad := PackedStringArray()
	var shown := 0
	# at the screenshot pass's 1280 x 720 and at 1920 x 1080: the stack (and the map filling it) sized so
	stack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for screen: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080)]:
		stack.size = screen
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, map.view.size)
		assert_true(bounds.size.x > 400.0 and bounds.size.y > 300.0, "the map's view is laid out (%s)" % bounds.size)
		var settlements: Array = map.entries().filter(func(e: Dictionary) -> bool: return str(e.kind) == "settlement")
		assert_true(settlements.size() >= 6, "the world's settlements are on the map (%d)" % settlements.size())
		var focus: Array = settlements.map(func(e: Dictionary) -> String: return str(e.id))
		focus.append_array(["world.shrine.kingsgate", "world.cp.kingsgate_shelf"])
		for zoom in MapScreen.ZOOMS.size():
			for id: String in focus:
				map.set_zoom(zoom)
				if not map.select(id):
					continue
				var labels := map.layout_labels(font)
				var marks := map.mark_rects()
				var what := "%dx%d zoom %d, %s" % [int(screen.x), int(screen.y), zoom, id]
				bad.append_array(_label_faults(labels, marks, bounds, id, what))
				shown += labels.size()
				if zoom == 0:
					var regions := labels.filter(func(l: Dictionary) -> bool: return str(l.kind) == "region").size()
					if regions != MapScreen.regions_for(GameSession.WORLD_LEVEL_ID).size():
						if id == "poi.brannock":
							for l: Dictionary in labels:
								print("DBG ", l.kind, " ", l.id, " ", l.rect)
							for reg: Dictionary in MapScreen.regions_for(GameSession.WORLD_LEVEL_ID):
								print("DBG REGION ", reg.id, " ", map.to_screen(reg.pos), " ", reg.name)
							for k: String in marks:
								print("DBG MARK ", k, " ", marks[k])
						bad.append("%s: %d region labels of %d" % [what, regions, MapScreen.regions_for(GameSession.WORLD_LEVEL_ID).size()])
					for e: Dictionary in settlements:
						if not labels.any(func(l: Dictionary) -> bool: return str(l.id) == str(e.id)):
							bad.append("%s: %s has no name" % [what, e.id])
	assert_eq(bad, PackedStringArray(), "no label covers a label or a mark, none is cut, the regions and settlements show")
	assert_true(shown > 100, "the views laid out %d labels in all" % shown)
	# M9 gate (lane review): the campaign on the world, the raid on Millford tracked (its objective's marker, read
	# from the event's record), the pin between the Kingsgate shrine and its shelf, and the giant by the shrine
	# where its checkpoint put him (the review's frame: at (-294, 774), the shrine at (-300, 770)) - his arrow
	# covered every spot by the shrine's icon.
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	Quests.test_active = true
	var raid := GameData.get_record("event.millford_raid")
	var marker := str((raid.get("objective", {}) as Dictionary).get("marker", ""))
	var at := idx.position_of(marker)
	assert_true(at.is_finite(), "the raid's objective marker '%s' is on the world's index" % marker)
	Quests.p37_set_event("event.millford_raid", {"quest_id": "event.millford_raid", "title": "Raid on Millford",
		"text": "Defend Millford", "kind": "protect", "marker_id": marker, "position": at, "positions": [at],
		"main": false, "event": true, "in_play": true})
	assert_true(Quests.track("event.millford_raid"), "the raid is tracked")
	var shrine: Vector2 = map.entry("world.shrine.kingsgate").get("pos", Vector2.INF)
	var shelf: Vector2 = map.entry("world.cp.kingsgate_shelf").get("pos", Vector2.INF)
	assert_true(shrine.is_finite() and shelf.is_finite(), "the Kingsgate shrine and its shelf are on the map")
	var pin := (shrine + shelf) * 0.5
	WorldState.set_flag(Discovery.PIN_FLAG, [pin.x, pin.y, GameSession.WORLD_LEVEL_ID])
	var giant := spawn_player(Vector3(shrine.x + 6.0, 0.0, shrine.y + 4.0))
	giant.process_mode = Node.PROCESS_MODE_DISABLED   # it stands there: no floor under it in this test's world
	bad.clear()
	var diamonds := 0
	for screen: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080)]:
		stack.size = screen
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, map.view.size)
		for zoom in MapScreen.ZOOMS.size():
			for id: String in ["world.shrine.kingsgate", "world.cp.kingsgate_shelf", "world.cp.millford", "poi.millford",
					"world.cp.brannock"]:
				map.set_zoom(zoom)
				if not map.select(id):
					continue
				var labels := map.layout_labels(font)
				var marks := map.mark_rects()
				var what := "raid tracked, %dx%d zoom %d, %s" % [int(screen.x), int(screen.y), zoom, id]
				if zoom == 0 and not (marks.has("objective_0") and marks.has("pin") and marks.has("player")):
					bad.append("%s: the diamond, the pin or the giant is not on the whole map (%s)" % [what, marks.keys()])
				diamonds += 1 if marks.has("objective_0") else 0
				bad.append_array(_label_faults(labels, marks, bounds, id, what))
	assert_eq(bad, PackedStringArray(), "with the raid tracked and the pin by the shrine, no label covers a label or a mark")
	assert_true(diamonds >= 6, "the raid's diamond was on %d of the views" % diamonds)
	map.close()


## The faults of the map's labels as laid out (test_the_world_map_labels_never_overlap): the place in focus `id`
## without its label, a label cut by the view's edge `bounds`, over another label or over a mark of `marks`.
static func _label_faults(labels: Array, marks: Dictionary, bounds: Rect2, id: String, what: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var in_focus := labels.filter(func(l: Dictionary) -> bool: return str(l.kind) == "selected")
	if in_focus.size() != 1 or str(in_focus[0].id) != id:
		bad.append("%s: the place in focus has no label" % what)
	for i in labels.size():
		var a: Dictionary = labels[i]
		var ra: Rect2 = a.rect
		if not bounds.encloses(ra):
			bad.append("%s: %s's label is cut by the view's edge (%s)" % [what, a.id, ra])
		for j in range(i + 1, labels.size()):
			if ra.intersects(labels[j].rect):
				bad.append("%s: %s's label covers %s's" % [what, a.id, labels[j].id])
		for k: String in marks:
			if ra.intersects(marks[k]):
				bad.append("%s: %s's label covers the mark %s %s" % [what, a.id, k, marks[k]])
	return bad
