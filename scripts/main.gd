extends Node
## Entry scene. Refuses to start on invalid data (shows every validation error); otherwise it
## builds what GameSession.mode asks for (plan §2.9, §3.6):
##   * title: the screen stack with the title screen only (no level, no HUD);
##   * sandbox and Valley: a "Loading..." label while the game is paused (no simulation tick
##     passes): one frame, then the level GameSession.level_scene_path() names, HitFeedback, the
##     HUD, the debug panel and the screen stack, then GameSession.on_level_ready(level, player)
##     (respawn point and character state), then the autopilot when one was asked for; then the
##     loading gate (P19): the tree stays paused behind "Loading..." until Audio.is_ready() - every
##     SFX sample of the level registered - so no sound plays before its sample exists and the
##     first play() never registers (plan M6-M9 §2.5, decision 2). Paused frames run no tick, so
##     the seeded timeline is the same with audio on or off.
## The ScreenStack (P03) handles pause / Esc itself (and every modal screen); focus loss and a
## lost pointer lock open the pause screen through it. main owns the global keys: controls
## overlay, debug panel, the debug reset (F5, sandbox only) and checkpoint reload (F9), and the
## death confirm (Enter / pad A): a sandbox restart, or "load last checkpoint" where
## checkpoints exist (GameSession.checkpoints_enabled()). Every restart, reset and mode change
## reloads this scene through GameSession; autoload state survives the reload.
##
## Command-line options (after "--"; GameSession.parse_args reads the session ones):
##   --mode=title|sandbox|valley  start screen (default title; without --mode, --autoplay,
##                        --scenario and --level boot the sandbox, so the M1 tools keep working)
##   --new-game / --continue      how --mode=valley starts
##   --level=res://...tscn        load this scene instead of the mode's level
##   --save-dir=user://...        folder of the save slot (keeps saving on with --no-user-settings)
##   --autoplay=SECONDS   drive the player with the seeded autopilot, then quit
##   --scenario=capture   scripted screenshot tour (needs a display; see tools/)
##   --capture-dir=PATH   where screenshots go
##   --no-user-settings   ignore user://settings.json and never write the save slot

## The M1 sandbox (GameSession.SANDBOX_SCENE is the one loaded).
const SANDBOX_SCENE := "res://scenes/world/sandbox_arena.tscn"
const LOADING_TEXT := "Loading..."
## The death screen ignores its confirm for this long after the death (handle_death_confirm).
const DEATH_CONFIRM_DELAY_S := 1.0

var hud: Hud
var screen_stack: ScreenStack
var debug_panel: DebugPanel
## The loaded level (the sandbox arena, the Valley or a --level scene); its M1 name is kept.
var sandbox: Node3D
var level: Node
var autopilot: Autopilot
var _layer: CanvasLayer
var _in_level := false
var _was_captured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	UiNav.ensure_pad_actions()   # P16: pad A / B accept and cancel in every menu
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	if not GameData.is_valid():
		_show_data_errors(_layer)
		return
	Events.sandbox_reset_requested.connect(_on_reset_requested)
	if GameSession.mode == GameSession.Mode.TITLE:
		_build_title()
		return
	var loading := UiKit.label(LOADING_TEXT, 30)
	loading.process_mode = Node.PROCESS_MODE_ALWAYS
	loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(loading)
	# "Loading..." while the tree is paused, so the simulation does not run a tick without the level
	# (the seeded soak keeps its exact timeline): one frame, the level built behind it, then the
	# audio loading gate.
	get_tree().paused = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_level()
	await hold_until_audio_ready(loading)
	if not is_inside_tree():
		return
	loading.queue_free()
	if not _pausing_screen_open():
		get_tree().paused = false


## The loading gate (P19, plan M6-M9 §2.5): waits, frame by frame with the tree paused, until the
## Audio autoload has registered every sample of the level (Audio.is_ready(); true at once without
## audio), showing the registration progress on the loading label.
func hold_until_audio_ready(loading: Label) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("is_ready"):
		return
	while is_inside_tree() and not bool(audio.call("is_ready")):
		if is_instance_valid(loading):
			loading.text = "%s %d%%" % [LOADING_TEXT, int(float(audio.call("registration_progress")) * 100.0)]
		await get_tree().process_frame


## True while a screen that pauses the game is open (the gate then leaves the pause to it).
func _pausing_screen_open() -> bool:
	if screen_stack == null:
		return false
	for child in screen_stack.get_children():
		var s := child as UiScreen
		if s != null and screen_stack.has_screen(s) and s.pauses_game():
			return true
	return false


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


## Title mode: the screen stack and the title screen, nothing else.
func _build_title() -> void:
	screen_stack = ScreenStack.new()
	screen_stack.name = "ScreenStack"
	_layer.add_child(screen_stack)
	screen_stack.open("title")
	_start_autopilot_if_requested()   # --mode=title --autoplay=S: idles, then reports and quits


func _build_level() -> void:
	var path := GameSession.level_scene_path()
	var packed: PackedScene = load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("Giantborn: no level to load for mode %s (%s); back to the title" % [
			GameSession.mode_name(), path if path != "" else GameSession.VALLEY_MISSING])
		GameSession.go_to_title()
		return
	level = packed.instantiate()
	sandbox = level as Node3D
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	var feedback := HitFeedback.new()
	feedback.name = "HitFeedback"
	feedback.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(feedback)
	add_child(TelegraphVisuals.new())   # P09: telegraph decals, aim lines (threat arrows: a HUD widget)
	hud = Hud.new()
	hud.name = "Hud"
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	_layer.add_child(hud)
	debug_panel = DebugPanel.new()
	debug_panel.name = "DebugPanel"
	_layer.add_child(debug_panel)
	screen_stack = ScreenStack.new()
	screen_stack.name = "ScreenStack"
	_layer.add_child(screen_stack)
	_in_level = true
	GameSession.on_level_ready(level, get_tree().get_first_node_in_group("player") as GiantPlayer)
	_start_autopilot_if_requested()
	# Browsers only grant pointer lock from a click, so on the web wait for the first click.
	if autopilot == null and not OS.has_feature("web"):
		_capture_mouse()


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
## through it. The other global keys work only in a level while no screen is open.
func _unhandled_input(event: InputEvent) -> void:
	if screen_stack == null or not _in_level:
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
		if GameSession.is_valley():
			Events.hud_message.emit("F5 resets the sandbox only (F9 reloads the last checkpoint)", "info")
		else:
			Events.sandbox_reset_requested.emit("debug_reset")
	elif event.is_action_pressed("debug_checkpoint") and OS.is_debug_build():
		if GameSession.checkpoints_enabled():
			Events.reload_checkpoint_requested.emit("debug")
		else:
			Events.hud_message.emit("No checkpoints in the sandbox", "info")


## The death confirm runs here, before the input router turns pad A into a (dead) jump. A click
## on the game view while the mouse is free takes the mouse back and does nothing else (no
## swing, no block); this runs in _input because the input router consumes mouse buttons as
## attacks in _unhandled_input, so a handler there never saw the click. Browsers grant pointer
## lock only inside a click, so in the web build this click is how the player starts
## controlling the camera. Every event first tells InputBindings which device the player is using
## (P16: the prompts and menus show that device's buttons), in every mode, the title included.
func _input(event: InputEvent) -> void:
	InputBindings.note_device(event)
	if screen_stack == null or not _in_level:
		return
	if handle_death_confirm(event, get_tree().get_first_node_in_group("player") as GiantPlayer, _screen_open()):
		get_viewport().set_input_as_handled()
		return
	if autopilot != null or DisplayServer.get_name() == "headless":
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


## True for the death screen's confirm: Enter / keypad Enter, or pad A (the HUD shows
## "Enter / A").
static func is_death_confirm(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER]
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == JOY_BUTTON_A


## The death screen's confirm (Enter / pad A) while `player` is dead and no screen is open: once
## the death screen has shown for DEATH_CONFIRM_DELAY_S it loads the last checkpoint (or restarts
## the sandbox); before that the press is swallowed and does nothing (P17a, M4 review: a player
## mashing pad A - jump - or LT+A - Heavy Footfall - at the moment of death skipped the death
## screen). True when the event was such a confirm (used or ignored), so _input consumes it.
func handle_death_confirm(event: InputEvent, player: GiantPlayer, screen_open: bool) -> bool:
	if screen_open or not is_death_confirm(event) or not is_dead(player):
		return false
	if death_confirm_ready(player, Sim.tick):
		_confirm_death()
	return true


static func is_dead(player: GiantPlayer) -> bool:
	return player != null and is_instance_valid(player) and player.controller != null \
		and player.controller.state == CombatController.State.DEAD


## True when the death screen of a dead `player` accepts its confirm at `now_tick`: at least
## DEATH_CONFIRM_DELAY_S (in simulation ticks) after the death (CombatEntity.died_tick; a death
## without a recorded tick is ready at once, so the screen can never lock).
static func death_confirm_ready(player: GiantPlayer, now_tick: int) -> bool:
	if not is_dead(player):
		return false
	var died := player.entity.died_tick if player.entity != null else -1
	return died < 0 or now_tick - died >= ActionDef.seconds_to_ticks(DEATH_CONFIRM_DELAY_S)


## Death confirm: load the last checkpoint where checkpoints exist, else restart the sandbox.
func _confirm_death() -> void:
	if GameSession.checkpoints_enabled():
		Events.reload_checkpoint_requested.emit("death")
	else:
		Events.sandbox_reset_requested.emit("restart_after_death")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen_stack != null and _in_level \
			and autopilot == null and not _screen_open() and DisplayServer.get_name() != "headless":
		screen_stack.open("pause")


## In a browser the first Esc press releases pointer lock without reaching the game. Treat that
## release like Esc on desktop and open the pause menu, so the game never keeps running with a
## free cursor and no camera control. (Only in a level: the title screen has no pause menu.)
func _process(_delta: float) -> void:
	if screen_stack == null or autopilot != null or not _in_level:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if OS.has_feature("web") and _was_captured and not captured and not _screen_open() \
			and not _player_dead():
		screen_stack.open("pause")
	_was_captured = captured


## Events.sandbox_reset_requested (death restart, F5, the pause menu, the autopilot). Where
## checkpoints exist a death restart reloads the last checkpoint instead, and the Valley ignores
## the other resets; elsewhere every world change is forgotten and the level reloads.
func _on_reset_requested(reason: String) -> void:
	if GameSession.checkpoints_enabled() and reason.ends_with("after_death"):
		Events.reload_checkpoint_requested.emit("death")
		return
	if GameSession.is_valley():
		print("[session] ignored a sandbox reset (%s) in the Valley at tick %d" % [reason, Sim.tick])
		return
	print("[sandbox] reset (%s) at tick %d" % [reason, Sim.tick])
	if screen_stack != null:
		screen_stack.close_all()
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	get_tree().paused = false
	GameSession.restart_sandbox(reason)
