class_name ScreenStack
extends Control
## The modal screen stack (plan §2.10.2): a child of main's CanvasLayer (layer 10), above the
## HUD; group "screen_stack". It owns every screen it holds and frees a screen once it closes.
##
## While any screen is open the input context is MENU and the mouse is visible; while any open
## screen pauses_game() the tree is paused. When the last one closes: unpause, GAMEPLAY, and
## the mouse is captured again (never headless; in a browser only when the closing input was a
## click, because pointer lock needs one).
##
## Input (it runs while paused): `pause` (Esc / Start) cancels the top screen, or opens the
## pause menu when none is open; `ui_cancel` (pad B) cancels the top screen; with no screen
## open, a HOTKEYS action opens its screen. Gameplay asks for screens with
## Events.ui_screen_requested(screen, args), opened deferred. SCREENS is pre-declared: a path
## whose file does not exist yet opens nothing, silently.
##
## Pad and keyboard (P16): the stack adds pad A / B to ui_accept / ui_cancel (UiNav), wires the
## top screen's focus rows when it opens or comes back on top (and once more on the next frame,
## after the layout ran), puts a lost focus back every frame, and shows a footer hint ("A: select
## B: back" or "Enter: select Esc: back", by the last device) while any screen is open.
## P39f: the footer says what the top screen's nav_hint() says (UiNav's line by default); a screen with its own
## instructions returns "" and the footer hides - the yield prompt's choices are held, not selected, and its
## own line under them says so (the footer's "Enter: select" contradicted it).
## P39f: while any stack has a screen open, the HUD hides (Hud.MenuWatch) and so does every node in the
## HIDE_UNDER_SCREENS group (the shrines' floating names): the screens' panels are see-through, and what the
## HUD and the names drew read through them and round them.

const GROUP := "screen_stack"
## P39f: nodes hidden while a screen is open (sync_hidden_under_screens).
const HIDE_UNDER_SCREENS := "hide_under_screens"
## Every planned screen; a missing file is skipped (its package has not landed yet).
const SCREENS := {
	"pause": "res://ui/pause_menu.gd",                         # P03
	"title": "res://ui/screens/title_screen.gd",               # P06
	"shrine": "res://ui/screens/shrine_screen.gd",             # P05
	"dialogue": "res://ui/screens/dialogue_screen.gd",         # P13
	"inventory": "res://ui/screens/inventory_screen.gd",       # P12
	"attributes": "res://ui/screens/attributes_screen.gd",     # P12
	"forge": "res://ui/screens/forge_screen.gd",               # P12
	"end": "res://ui/screens/end_screen.gd",                   # P13
	# M6-M9 (pre-declared by P20, plan M6-M9 §2.14)
	"map": "res://ui/screens/map_screen.gd",                   # P27
	"journal": "res://ui/screens/journal_screen.gd",           # P27
	"ancestry": "res://ui/screens/ancestry_screen.gd",         # P33
	"yield": "res://ui/screens/yield_prompt.gd",               # P34
}
## Input action -> screen, used only while no screen is open (an action not in the InputMap yet -
## map and journal until P27 binds them - is skipped).
const HOTKEYS := {"inventory": "inventory", "map": "map", "journal": "journal"}

var _screens: Array[UiScreen] = []
var _opened_ms: Dictionary = {}       ## screen -> Time.get_ticks_msec() when it opened
var _menu_context := false            ## this stack set InputRouter MENU
var _paused := false                  ## this stack paused the tree
var _last_input_was_click := false
var _hint: Label                      ## the footer hint (P16), the stack's last child


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.ui_screen_requested.connect(_on_screen_requested)
	UiNav.ensure_pad_actions()
	_hint = UiKit.label("", 13, UiKit.MUTED)
	_hint.name = "NavHint"
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -360
	_hint.offset_right = 360
	_hint.offset_top = -30
	_hint.offset_bottom = -8
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.visible = false
	add_child(_hint)


## The footer hint shown now ("" while no screen is open).
func hint_text() -> String:
	return _hint.text if _hint != null and _hint.visible else ""


## Every frame (also while paused): the top screen's deferred focus wiring, a lost focus put
## back, and the footer hint for the last device.
func _process(_delta: float) -> void:
	var t := top()
	if _hint != null:
		var line := t.nav_hint(InputBindings.last_device_is_pad()) if t != null and is_instance_valid(t) else ""
		if _hint.text != line:
			_hint.text = line
		_hint.visible = line != ""
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return
	if t.focus_dirty:
		t.focus_dirty = false
		UiNav.link_rows(t.focus_rows())
	UiNav.keep_focus(t)


func _exit_tree() -> void:
	# A stack freed with its scene (reload) must not leave the game paused or in MENU.
	if _paused and is_inside_tree():
		get_tree().paused = false
	if _menu_context:
		InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	_paused = false
	_menu_context = false
	if is_inside_tree():
		sync_hidden_under_screens(get_tree(), self)


## Opens SCREENS[screen_name] on top of the stack. Returns the screen, or null when the name is
## unknown or its file does not exist yet.
func open(screen_name: String, args: Dictionary = {}) -> UiScreen:
	var path := str(SCREENS.get(screen_name, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var script := load(path) as Script
	if script == null:
		return null
	var screen := script.new() as UiScreen
	if screen == null:
		push_warning("ScreenStack: %s is not a UiScreen" % path)
		return null
	screen.screen_name = screen_name
	screen.args = args
	push(screen)
	return screen


## Puts a screen on top (adding it as a child) and gives its first_focus() the focus.
func push(screen: UiScreen) -> void:
	if screen == null or _screens.has(screen):
		return
	screen.stack = self
	if screen.get_parent() == null:
		add_child(screen)
	elif screen.get_parent() != self:
		screen.reparent(self)
	move_child(screen, -1)
	if _hint != null:
		move_child(_hint, -1)   # the footer hint stays above every screen
	_screens.append(screen)
	_opened_ms[screen] = Time.get_ticks_msec()
	screen.visible = true
	_apply_state()
	screen.on_open()
	_focus_top()


## Removes a screen (any position), emits its closed(result) and frees it.
func pop(screen: UiScreen, result: Dictionary = {}) -> void:
	var i := _screens.find(screen)
	if i < 0:
		return
	_screens.remove_at(i)
	_opened_ms.erase(screen)
	screen.on_close()
	screen.closed.emit(result)
	if is_instance_valid(screen):
		screen.visible = false
		screen.queue_free()
	_apply_state()
	_focus_top()


func top() -> UiScreen:
	return _screens.back() if not _screens.is_empty() else null


func is_open(screen_name: String) -> bool:
	for s in _screens:
		if s.screen_name == screen_name:
			return true
	return false


func any_open() -> bool:
	return not _screens.is_empty()


func has_screen(screen: UiScreen) -> bool:
	return _screens.has(screen)


func count() -> int:
	return _screens.size()


## Real seconds since the game was paused by the screens open now (0 while nothing pauses).
## The Valley bot checks that no pausing screen stays open longer than 2 s.
func open_seconds() -> float:
	var since := -1
	for s in _screens:
		if s.pauses_game():
			var t := int(_opened_ms.get(s, Time.get_ticks_msec()))
			since = t if since < 0 else mini(since, t)
	if since < 0:
		return 0.0
	return (Time.get_ticks_msec() - since) / 1000.0


## Esc / pad B: cancels the top screen. False when nothing is open.
func handle_cancel() -> bool:
	var t := top()
	if t == null:
		return false
	t.cancel()
	return true


## The pause key: closes (cancels) the top screen first; with none open, opens the pause menu.
func handle_pause() -> void:
	if not handle_cancel():
		open("pause")


## Closes every screen, top first (mode changes, resets, the bot after screen-backed actions).
func close_all() -> void:
	while not _screens.is_empty():
		pop(_screens.back(), {"closed_all": true})


## P39f: true while a stack in `tree` (other than `except`) has a screen open (the HUD hides then).
static func any_open_in(tree: SceneTree, except: ScreenStack = null) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(GROUP):
		var s := node as ScreenStack
		if s != null and s != except and is_instance_valid(s) and s.any_open():
			return true
	return false


## P39f: hides the HIDE_UNDER_SCREENS group while a screen is open in `tree` and shows it again after (a stack
## leaving the tree passes itself as `leaving`: its screens go with it).
static func sync_hidden_under_screens(tree: SceneTree, leaving: ScreenStack = null) -> void:
	if tree == null:
		return
	var shown := not any_open_in(tree, leaving)
	for n in tree.get_nodes_in_group(HIDE_UNDER_SCREENS):
		if n is Node3D:
			(n as Node3D).visible = shown
		elif n is CanvasItem:
			(n as CanvasItem).visible = shown


## Closes the screens of every stack in the tree. Returns how many were open (the test reset
## hook reports a positive count as "screen left open").
static func close_all_static() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var closed_count := 0
	for node in tree.get_nodes_in_group(GROUP):
		var s := node as ScreenStack
		if s != null and is_instance_valid(s):
			closed_count += s.count()
			s.close_all()
	return closed_count


# --------------------------------------------------------------------------- state

func _apply_state() -> void:
	var modal := not _screens.is_empty()
	var pausing := false
	for s in _screens:
		if s.pauses_game():
			pausing = true
	if pausing != _paused:
		_paused = pausing
		get_tree().paused = pausing
	if modal and not _menu_context:
		_menu_context = true
		InputRouter.set_context(InputRouter.Context.MENU)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not modal and _menu_context:
		_menu_context = false
		InputRouter.set_context(InputRouter.Context.GAMEPLAY)
		_recapture_mouse()
	if is_inside_tree():
		sync_hidden_under_screens(get_tree())


func _recapture_mouse() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web") and not _last_input_was_click:
		return   # browsers grant pointer lock only inside a click; the next click takes it
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _focus_top() -> void:
	var t := top()
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		return
	t.refresh_focus()   # P16: wire its focus rows (wrap-around) before the focus lands
	var f := t.first_focus()
	if f != null and is_instance_valid(f) and f.is_inside_tree() and f.is_visible_in_tree():
		f.grab_focus()


# --------------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_last_input_was_click = true
	elif event is InputEventKey or event is InputEventJoypadButton:
		_last_input_was_click = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		handle_pause()
		get_viewport().set_input_as_handled()
		return
	if any_open():
		if event.is_action_pressed("ui_cancel"):
			handle_cancel()
			get_viewport().set_input_as_handled()
		return
	for action_name: String in HOTKEYS:
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			if open(str(HOTKEYS[action_name])) != null:
				get_viewport().set_input_as_handled()
			return


func _on_screen_requested(screen_name: String, args: Dictionary) -> void:
	call_deferred("open", screen_name, args)
