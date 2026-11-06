extends IntegrationSuite
## P27 (plan M6-M9 §3.10 design 2): fast travel from the map, on the stub level of
## tests/support/world_ux_fixtures.gd under two ids (a level pair: level.test_p27 and
## level.test_p27_b) and to the Valley's index. The map's Travel (MapScreen.travel_selected,
## Events.travel_requested with "fast_travel") is refused with GameSession's reason, which the panel
## shows: a stone not visited, a max_stage below the giant's stage, requires_flags that do not hold,
## an aware enemy within 40 m, a place that is no waystone or shrine; and goes otherwise - a
## checkpoint at the destination, a reload, and the next level start puts the giant there - the open
## map never holding it back. A pad: A on a visited stone puts the focus on Travel, A again goes.

const Fx := preload("res://tests/support/world_ux_fixtures.gd")
const LEVEL_B := "level.test_p27_b"

var stack: ScreenStack
var p: GiantPlayer


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	Fx.install(LEVEL_B)
	Fx.install()
	GameSession.level_override = ""
	GameSession.start_world_for_tests("test.p27.cp_start")
	GameSession.level_id = Fx.LEVEL
	p = spawn_player(Vector3(0, 0.05, 150), 0.0)
	GameSession.on_level_ready(world, p)
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


func test_travel_is_refused_with_its_reason() -> void:
	for flag: String in ["map.seen.c3_0", "map.seen.c3_2", "visited.test.p27.cp_start", "visited.test.p27.cp_narrow",
			"visited.test.p27.cp_gated"]:
		WorldState.set_flag(flag, true)
	var map := stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	var reloads := GameSession.scene_reloads.size()
	assert_true(map.select("test.p27.cp_far"), "the far stone is on the map (its chunk was seen)")
	assert_eq(map.travel_selected(), {"ok": false, "message": GameSession.NOT_VISITED}, "not visited: refused")
	assert_true(map.panel_text().contains(GameSession.NOT_VISITED), "the panel says why (%s)" % map.panel_text())
	assert_true(map.travel_button.disabled, "Travel is off")
	p.growth_stage = 3
	map.select("test.p27.cp_narrow")
	assert_eq(str(map.travel_selected().message), GameSession.NARROW_PATHS, "a max_stage of 2 below stage 3")
	assert_true(map.panel_text().contains("Too narrow above stage 2."), "the panel names the limit")
	p.growth_stage = 1
	map.select("test.p27.cp_gated")
	assert_eq(str(map.travel_selected().message), GameSession.NOT_OPEN, "requires_flags that do not hold")
	WorldState.set_flag("test.p27.gate_open", true)
	var stub := TestSpawn.stub_enemy(world, p.global_position + Vector3(0, 0, -30), "test.p27.watcher")
	stub.brain.aware = true
	assert_eq(str(map.travel_selected().message), "Not while enemies are close.", "an aware enemy 30 m away")
	assert_true(GameSession.checkpoint_blockers().has("screen"), "the open map holds a checkpoint back")
	stub.global_position = p.global_position + Vector3(0, 0, -60)
	assert_eq(map.travel_refusal_for("test.p27.cp_gated"), "", "but not the fast travel chosen on it, nor an enemy 60 m away")
	map.select("test.p27.exit")
	assert_eq(str(map.travel_selected().message), "You can only travel to a waystone or a shrine.", "an exit is no destination")
	assert_eq(GameSession.scene_reloads.size(), reloads, "no refused travel reloads")
	assert_eq(GameSession.level_id, Fx.LEVEL, "the giant is still here")
	stub.queue_free()


func test_travel_here_to_the_other_level_and_to_the_valley() -> void:
	WorldState.set_flag("visited.test.p27.cp_start", true)
	WorldState.set_flag("visited.test.p27.cp_far", true)
	var map := stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	await get_tree().process_frame
	await get_tree().process_frame
	# a pad: A on the stone, then A on Travel
	map.icon("test.p27.cp_far").grab_focus()
	await get_tree().process_frame
	await _pad(JOY_BUTTON_A)
	assert_true(map.travel_button.has_focus(), "A on a visited stone puts the focus on Travel")
	await _pad(JOY_BUTTON_A)
	assert_eq(GameSession.scene_reloads.back(), "fast_travel", "A on Travel goes: a fast travel reload")
	assert_eq([GameSession.level_id, GameSession.respawn_id], [Fx.LEVEL, "test.p27.cp_far"], "to the far stone")
	assert_eq(str(GameSession.last_travel_result.get("message", "?")), "", "accepted")
	GameSession.on_level_ready(world, p)
	assert_true(p.global_position.distance_to(Vector3(150, 0, -150)) < 0.5, "the giant arrives there (%s)" % p.global_position)
	# the level pair: the other level's tab, once visited
	(GameSession.progress.levels_visited as Array).append(LEVEL_B)
	stack.close_all()
	map = stack.open("map", {"level": Fx.LEVEL}) as MapScreen
	assert_true(map.level_buttons.has(LEVEL_B), "a tab for the other level (%s)" % [map.level_buttons.keys()])
	(map.level_buttons[LEVEL_B] as Button).pressed.emit()
	assert_eq(map.shown_level(), LEVEL_B, "its map")
	assert_true(map.select("test.p27.cp_start"), "its start stone (visited)")
	var r := map.travel_selected()
	assert_true(bool(r.ok), "travel to the other level (%s)" % r)
	assert_eq([GameSession.level_id, GameSession.respawn_id], [LEVEL_B, "test.p27.cp_start"], "to its stone")
	GameSession.on_level_ready(world, p)
	assert_true(p.global_position.distance_to(Vector3(0, 0, 150)) < 0.5, "and arrives there")
	# the Valley's index
	assert_true(map.show_level("level.valley"), "the Valley's map")
	assert_false(map.travel_refusal_for("valley.shrine.hollow") == "", "a Valley shrine not visited is refused")
	WorldState.set_flag("visited.valley.shrine.hollow", true)
	assert_eq(map.travel_refusal_for("valley.shrine.hollow"), "", "visited, it goes")
	assert_true(map.select("valley.shrine.hollow"), "chosen")
	r = map.travel_selected()
	assert_true(bool(r.ok), "travel to the Valley (%s)" % r)
	assert_eq([GameSession.level_id, GameSession.respawn_id], ["level.valley", "valley.shrine.hollow"], "to its shrine")
	assert_eq(GameSession.scene_reloads.back(), "fast_travel", "a reload into the Valley")
