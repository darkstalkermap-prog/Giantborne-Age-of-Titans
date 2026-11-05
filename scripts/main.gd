extends Node
## Entry scene. Refuses to start on invalid data (shows every validation error), otherwise
## builds the sandbox, HUD, the screen stack and hit feedback, and owns the global keys:
## controls overlay, debug panel and debug reset (debug builds only). The ScreenStack (P03)
## handles pause / Esc itself (and every modal screen); focus loss and a lost pointer lock open
## the pause screen through it. Restart/reset reloads the scene, which is the most reliable way
## to restore every system to its initial state.
##
## Command-line options (after "--"):
##   --autoplay=SECONDS   drive the player with the seeded autopilot, then quit
##   --scenario=capture   scripted screenshot tour (needs a display; see tools/)
##   --capture-dir=PATH   where screenshots go
##   --no-user-settings   ignore user://settings.json

const SANDBOX_SCENE := "res://scenes/world/sandbox_arena.tscn"

var hud: Hud
var screen_stack: ScreenStack
var debug_panel: DebugPanel
var sandbox: Node3D
var autopilot: Autopilot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	if not GameData.is_valid():
		_show_data_errors(layer)
		return
	sandbox = (load(SANDBOX_SCENE) as PackedScene).instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	var feedback := HitFeedback.new()
	feedback.name = "HitFeedback"
	feedback.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(feedback)
	hud = Hud.new()
	hud.name = "Hud"
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	layer.add_child(hud)
	debug_panel = DebugPanel.new()
	debug_panel.name = "DebugPanel"
	layer.add_child(debug_panel)
	screen_stack = ScreenStack.new()
	screen_stack.name = "ScreenStack"
	layer.add_child(screen_stack)
	Events.sandbox_reset_requested.connect(_on_reset_requested)
	_start_autopilot_if_requested()
	# Browsers only grant pointer lock from a click, so on the web wait for the first click.
	if autopilot == null and not OS.has_feature("web"):
		_capture_mouse()


func _show_data_errors(layer: CanvasLayer) -> void:
	var panel := UiKit.panel(Color(0.12, 0.02, 0.02, 0.95))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var text := "DATA VALIDATION FAILED - the sandbox will not start.\nFix these files under res://data and restart:\n\n"
	text += "\n".join(GameData.errors)
	var l := UiKit.label(text, 15, UiKit.BAD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1200, 0)
	scroll.add_child(l)
	push_error("Giantborn: %d data validation errors; sandbox not started." % GameData.errors.size())


func _start_autopilot_if_requested() -> void:
	var seconds := 0.0
	var scenario := ""
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoplay="):
			seconds = float(arg.substr(11))
		elif arg.begins_with("--scenario="):
			scenario = arg.substr(11)
		elif arg.begins_with("--capture-dir="):
			capture_dir = arg.substr(14)
	if seconds <= 0.0 and scenario == "":
		return
	autopilot = Autopilot.new()
	autopilot.name = "Autopilot"
	autopilot.configure(seconds, scenario, capture_dir)
	add_child(autopilot)


func _capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _player_dead() -> bool:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	return p != null and p.controller != null and p.controller.state == CombatController.State.DEAD


## True while a modal screen (pause, and later shrine, dialogue, ...) is open.
func _screen_open() -> bool:
	return screen_stack != null and screen_stack.any_open()


## Pause and Esc normally never reach this: the ScreenStack (a child) handles them first and
## stays in charge while a screen is open; a pause event that still arrives here is routed
## through it. The other global keys work only while no screen is open.
func _unhandled_input(event: InputEvent) -> void:
	if screen_stack == null:
		return
	if event.is_action_pressed("pause"):
		screen_stack.handle_pause()   # only if the stack did not see it first
		get_viewport().set_input_as_handled()
		return
	if _screen_open():
		return
	if event.is_action_pressed("help"):
		hud.toggle_help()
	elif event.is_action_pressed("debug_panel"):
		debug_panel.toggle()
	elif event.is_action_pressed("debug_reset") and OS.is_debug_build():
		Events.sandbox_reset_requested.emit("debug_reset")
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] and _player_dead():
		Events.sandbox_reset_requested.emit("restart_after_death")


## A click on the game view while the mouse is free takes the mouse back and does nothing else
## (no swing, no block). This runs in _input because the input router consumes mouse buttons as
## attacks in _unhandled_input, so a handler there never saw the click. Browsers grant pointer
## lock only inside a click, so in the web build this click is how the player starts controlling
## the camera.
func _input(event: InputEvent) -> void:
	if screen_stack == null or autopilot != null or DisplayServer.get_name() == "headless":
		return
	if is_capture_click(event, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, _screen_open()):
		_capture_mouse()
		get_viewport().set_input_as_handled()


## True for a button press that should only take the mouse back: the mouse is free and no menu is
## open. Wheel steps do not count; browsers grant pointer lock only to real clicks.
static func is_capture_click(event: InputEvent, mouse_captured: bool, menu_open: bool) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.pressed and not mouse_captured and not menu_open \
			and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen_stack != null and autopilot == null \
			and not _screen_open() and DisplayServer.get_name() != "headless":
		screen_stack.open("pause")


var _was_captured := false


## In a browser the first Esc press releases pointer lock without reaching the game. Treat that
## release like Esc on desktop and open the pause menu, so the game never keeps running with a
## free cursor and no camera control.
func _process(_delta: float) -> void:
	if screen_stack == null or autopilot != null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if OS.has_feature("web") and _was_captured and not captured and not _screen_open() \
			and not _player_dead():
		screen_stack.open("pause")
	_was_captured = captured


func _on_reset_requested(reason: String) -> void:
	print("[sandbox] reset (%s) at tick %d" % [reason, Sim.tick])
	if screen_stack != null:
		screen_stack.close_all()
	WorldState.clear()
	Sim.clear_pending()
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")
