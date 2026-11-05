extends IntegrationSuite
## P03: UiScreen / ScreenStack (plan §2.10.2) and the pause menu as a screen. Esc opens the
## pause menu and closes the top screen first; while a screen is open the tree is paused and
## gameplay edges are suppressed; the first focus is grabbed on open (pad navigation);
## close_all_static (the test reset hook) closes a leftover screen; screen requests open
## deferred; HOTKEYS only open screens that exist. Nothing here steps the simulation while the
## tree is paused (Sim is pausable).


## A pausing test screen with one focusable button.
class ProbeScreen:
	extends UiScreen
	static var close_calls := 0
	var button: Button
	var opened := 0

	func _ready() -> void:
		button = Button.new()
		button.text = "Probe"
		button.focus_mode = Control.FOCUS_ALL
		add_child(button)

	func first_focus() -> Control:
		return button

	func on_open() -> void:
		opened += 1

	func on_close() -> void:
		close_calls += 1


## A screen that does not pause the game (like the title screen).
class OverlayScreen:
	extends UiScreen

	func pauses_game() -> bool:
		return false


var stack: ScreenStack
var results: Array = []


func before_each() -> void:
	await super()
	results.clear()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	await super()


func _on_closed(result: Dictionary) -> void:
	results.append(result)


func _press(action_name: String) -> void:
	var e := InputEventAction.new()
	e.action = action_name
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new()
	up.action = action_name
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _press_escape() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ESCAPE
	k.pressed = true
	Input.parse_input_event(k)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func test_escape_opens_pause_and_closes_the_top_screen_first() -> void:
	assert_false(stack.any_open(), "nothing open")
	await _press_escape()
	assert_true(stack.is_open("pause"), "Esc opens the pause menu")
	assert_true(stack.top() is PauseMenu, "a PauseMenu on top")
	assert_true(get_tree().paused, "the game is paused")
	assert_eq(InputRouter.context, InputRouter.Context.MENU, "menu input context")
	ProbeScreen.close_calls = 0
	var probe := ProbeScreen.new()
	probe.closed.connect(_on_closed)
	stack.push(probe)
	assert_eq(stack.top(), probe, "a second screen on top")
	assert_eq(stack.count(), 2, "two screens")
	assert_eq(probe.opened, 1, "on_open ran")
	await _press_escape()
	assert_eq(results, [{"cancelled": true}], "Esc cancels the top screen first")
	assert_eq(ProbeScreen.close_calls, 1, "on_close ran")
	assert_true(stack.is_open("pause"), "the pause menu is still open")
	assert_true(get_tree().paused, "still paused")
	await _press("pause")
	assert_false(stack.any_open(), "the pause key closes the pause menu")
	assert_false(get_tree().paused, "unpaused")
	assert_eq(InputRouter.context, InputRouter.Context.GAMEPLAY, "gameplay input again")
	await get_tree().process_frame
	assert_false(is_instance_valid(probe), "closed screens are freed")


func test_pause_blocks_gameplay_edges() -> void:
	var router := InputRouter.new()
	router.use_injection = true
	world.add_child(router)
	router.inject_edge(&"light")
	assert_eq(router.consume().edges, [&"light"] as Array, "edges flow in gameplay")
	stack.open("pause")
	router.inject_edge(&"light")
	router.inject_edge(&"slot_6")
	assert_eq(router.consume().edges, [] as Array, "a pausing screen suppresses gameplay edges")
	var t := Sim.tick
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(Sim.tick, t, "the simulation does not advance while paused")
	stack.close_all()
	router.inject_edge(&"light")
	assert_eq(router.consume().edges, [&"light"] as Array, "and flow again once it closes")


func test_focus_is_grabbed_on_open() -> void:
	var menu := stack.open("pause") as PauseMenu
	assert_true(menu != null, "opened")
	var first := menu.first_focus()
	assert_true(first is Button, "the pause menu focuses a button (Resume)")
	assert_true(first.has_focus(), "focus grabbed on open (pad navigation)")
	var probe := ProbeScreen.new()
	stack.push(probe)
	assert_true(probe.button.has_focus(), "a pushed screen takes the focus")
	probe.close()
	assert_true(first.has_focus(), "closing the top screen gives the focus back to the one below")
	stack.close_all()


func test_close_all_static_closes_a_leftover_screen() -> void:
	stack.open("pause")
	stack.push(OverlayScreen.new())
	assert_eq(stack.count(), 2, "two screens left open")
	assert_true(stack.open_seconds() >= 0.0 and stack.open_seconds() < 5.0, "open_seconds counts real time")
	assert_eq(ScreenStack.close_all_static(), 2, "the reset hook closes both and reports them")
	assert_false(stack.any_open(), "nothing left")
	assert_false(get_tree().paused, "unpaused")
	assert_eq(InputRouter.context, InputRouter.Context.GAMEPLAY, "gameplay context restored")
	assert_eq(ScreenStack.close_all_static(), 0, "nothing to close the second time")
	assert_near(stack.open_seconds(), 0.0, 1e-9, "no pausing screen open")


func test_non_pausing_screens_keep_the_game_running() -> void:
	var overlay := OverlayScreen.new()
	stack.push(overlay)
	assert_true(stack.any_open(), "a modal screen is open")
	assert_false(get_tree().paused, "but it does not pause the game")
	assert_eq(InputRouter.context, InputRouter.Context.MENU, "gameplay input is still suppressed")
	var t := Sim.tick
	await step_ticks(2)
	assert_eq(Sim.tick, t + 2, "the simulation runs")
	overlay.close({"done": true})
	assert_false(stack.any_open(), "closed")
	assert_eq(InputRouter.context, InputRouter.Context.GAMEPLAY, "gameplay context")


func test_requests_unknown_screens_and_hotkeys() -> void:
	Events.ui_screen_requested.emit("pause", {"from": "test"})
	assert_false(stack.any_open(), "requests open deferred")
	await get_tree().process_frame
	assert_true(stack.is_open("pause"), "the requested screen opened")
	assert_eq(stack.top().args, {"from": "test"}, "with its args")
	assert_eq(stack.top().screen_name, "pause", "and its name")
	stack.close_all()
	assert_eq(stack.open("no_such_screen"), null, "an unknown screen opens nothing")
	for screen_name: String in ScreenStack.SCREENS:
		var path := str(ScreenStack.SCREENS[screen_name])
		assert_true(path.begins_with("res://ui/"), "%s is a ui/ script path" % screen_name)
	var inventory_exists := ResourceLoader.exists(str(ScreenStack.SCREENS[ScreenStack.HOTKEYS.inventory]))
	await _press("inventory")
	assert_eq(stack.is_open("inventory"), inventory_exists,
		"the inventory hotkey opens its screen only once the screen exists (P12)")
	stack.close_all()


func test_pause_menu_pages_and_wrappers() -> void:
	var menu := stack.open("pause") as PauseMenu
	assert_true(menu.is_open(), "is_open() inside the stack")
	assert_eq(menu.current_page(), "Main", "opens on the main page")
	menu.call("_show_page", "Controls")
	assert_eq(menu.current_page(), "Controls", "the controls page from SettingsPages")
	var pages := menu.settings_pages()
	pages.begin_capture("jump", false)
	assert_true(pages.is_capturing(), "a rebinding capture starts")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	assert_true(pages.handle_input(esc), "Esc is consumed by the capture")
	assert_false(pages.is_capturing(), "and cancels it")
	assert_true(stack.is_open("pause"), "without closing the menu")
	menu.close()
	assert_false(menu.is_open(), "close() pops it")
	assert_false(get_tree().paused, "and resumes")
	# Standalone, as in M1: the menu pauses and resumes the game itself.
	var solo := PauseMenu.new()
	world.add_child(solo)
	assert_false(solo.is_open(), "hidden until opened")
	solo.open()
	assert_true(solo.is_open() and get_tree().paused, "open() pauses")
	assert_eq(InputRouter.context, InputRouter.Context.MENU, "menu context")
	solo.close()
	assert_false(solo.is_open() or get_tree().paused, "close() resumes")
	assert_eq(InputRouter.context, InputRouter.Context.GAMEPLAY, "gameplay context")
	solo.queue_free()
