extends Node
## Entry scene. Refuses to start on invalid data (shows every validation error), otherwise
## builds the sandbox, HUD, menus and hit feedback, and owns the global keys: pause, controls
## overlay, debug panel and debug reset (debug builds only). Restart/reset reloads the scene,
## which is the most reliable way to restore every system to its initial state.
##
## Command-line options (after "--"):
##   --autoplay=SECONDS   drive the player with the seeded autopilot, then quit
##   --scenario=capture   scripted screenshot tour (needs a display; see tools/)
##   --capture-dir=PATH   where screenshots go
##   --no-user-settings   ignore user://settings.json

const SANDBOX_SCENE := "res://scenes/world/sandbox_arena.tscn"

var hud: Hud
var pause_menu: PauseMenu
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
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	layer.add_child(pause_menu)
	Events.sandbox_reset_requested.connect(_on_reset_requested)
	_start_autopilot_if_requested()
	if autopilot == null:
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


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu == null:
		return
	if event.is_action_pressed("pause"):
		if pause_menu.is_open():
			pause_menu.close()
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if pause_menu.is_open():
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
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and autopilot == null:
		_capture_mouse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_menu != null and autopilot == null \
			and not pause_menu.is_open() and DisplayServer.get_name() != "headless":
		pause_menu.open()


func _on_reset_requested(reason: String) -> void:
	print("[sandbox] reset (%s) at tick %d" % [reason, Sim.tick])
	WorldState.clear()
	Sim.clear_pending()
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")
