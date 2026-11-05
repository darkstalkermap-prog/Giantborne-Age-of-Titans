class_name PauseMenu
extends UiScreen
## Pause menu (Esc / Start). A UiScreen (P03): the ScreenStack opens it as SCREENS["pause"],
## pauses the tree and sets the MENU input context while it is open, and Esc / pad B (cancel)
## resumes. The main page depends on the mode (P06): Resume, Load last checkpoint (where
## checkpoints exist), Restart sandbox (outside the Valley), Quit to title, Quit to desktop
## (not on the web). The Settings and Controls pages come from SettingsPages (shared with the
## title screen); rebinding captures the next key or mouse button (keyboard column) or pad
## button / trigger (controller column), Esc cancels a capture.
##
## open(), close() and is_open() keep their M1 meaning: inside a stack they defer to it; a
## PauseMenu used on its own (no stack) pauses and unpauses the game itself, as in M1.

var _root_panel: PanelContainer
var _pages: Dictionary = {}
var _status: Label
var _resume: Button
var _load_checkpoint: Button
var _restart: Button
var _quit_title: Button
var _settings_pages := SettingsPages.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_root_panel = UiKit.panel(Color(0.08, 0.09, 0.11, 0.97))
	_root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_root_panel.offset_left = -360
	_root_panel.offset_right = 360
	_root_panel.offset_top = -300
	_root_panel.offset_bottom = 300
	add_child(_root_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_root_panel.add_child(v)
	var title := UiKit.label("PAUSED", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs)
	for page_name: String in ["Main", "Settings", "Controls"]:
		var b := UiKit.button(page_name, 16)
		b.pressed.connect(_show_page.bind(page_name))
		tabs.add_child(b)
	var holder := MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(holder)
	_pages["Main"] = _build_main()
	_pages["Settings"] = _settings_pages.build_settings()
	_pages["Controls"] = _settings_pages.build_controls()
	for page: Control in _pages.values():
		holder.add_child(page)
	_status = UiKit.label("", 13, UiKit.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_show_page("Main")
	if stack == null:
		visible = false   # standalone (M1 use): hidden until open()


# --------------------------------------------------------------------------- UiScreen

func first_focus() -> Control:
	return _resume


func on_open() -> void:
	_status.text = Settings.load_message
	refresh_items()
	_show_page("Main")


func on_close() -> void:
	_settings_pages.cancel_capture()
	Settings.flush()  # covers keyboard/wheel/gamepad slider changes (no drag_ended)


## M1 wrapper: inside a stack the menu is open while the stack holds it.
func is_open() -> bool:
	if stack != null:
		return super()
	return visible


## M1 wrapper: inside a stack it is already open; standalone it pauses the game itself.
func open() -> void:
	if stack != null:
		return
	visible = true
	get_tree().paused = true
	InputRouter.set_context(InputRouter.Context.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	on_open()
	if _resume != null:
		_resume.grab_focus()


## Resume. Inside a stack it pops the menu; standalone it unpauses the game itself (M1).
func close(result: Dictionary = {}) -> void:
	if stack != null:
		super(result)
		return
	on_close()
	visible = false
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit(result)


## The page currently shown ("Main", "Settings" or "Controls").
func current_page() -> String:
	for key: String in _pages:
		if (_pages[key] as Control).visible:
			return key
	return ""


func settings_pages() -> SettingsPages:
	return _settings_pages


func _show_page(page_name: String) -> void:
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page_name
	if page_name == "Controls":
		_settings_pages.refresh_bindings()


func _build_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_resume = UiKit.button("Resume", 20)
	_resume.pressed.connect(_on_resume)
	v.add_child(_resume)
	_load_checkpoint = UiKit.button("Load last checkpoint", 20)
	_load_checkpoint.pressed.connect(_on_load_checkpoint)
	v.add_child(_load_checkpoint)
	_restart = UiKit.button("Restart sandbox", 20)
	_restart.pressed.connect(_on_restart)
	v.add_child(_restart)
	_quit_title = UiKit.button("Quit to title", 20)
	_quit_title.pressed.connect(_on_quit_title)
	v.add_child(_quit_title)
	var quit := UiKit.button("Quit to desktop", 20)
	quit.pressed.connect(_on_quit)
	quit.visible = not OS.has_feature("web")  # a browser tab is closed by the browser
	v.add_child(quit)
	var info := UiKit.label("Giantborn: Age of Titans  -  prototype %s  -  Godot %s" % [
		ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 12, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	refresh_items()
	return v


## Shows the mode's items (GameSession): Load last checkpoint where checkpoints exist (disabled
## until one was taken), Restart sandbox outside the Valley.
func refresh_items() -> void:
	if _load_checkpoint == null:
		return
	_load_checkpoint.visible = GameSession.checkpoints_enabled()
	_load_checkpoint.disabled = not GameSession.has_checkpoint()
	_restart.visible = not GameSession.is_valley()


## The main page's visible items, top to bottom (tests).
func item_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Button in [_resume, _load_checkpoint, _restart, _quit_title]:
		if b != null and b.visible:
			out.append(b.text)
	return out


## The main page button with this text, or null.
func item(label: String) -> Button:
	for b: Button in [_resume, _load_checkpoint, _restart, _quit_title]:
		if b != null and b.text == label:
			return b
	return null


func _on_resume() -> void:
	close()


func _on_load_checkpoint() -> void:
	close()
	Events.reload_checkpoint_requested.emit("menu")


func _on_restart() -> void:
	close()
	Events.sandbox_reset_requested.emit("menu_restart")


func _on_quit_title() -> void:
	close()
	Events.mode_change_requested.emit("title", {})


func _on_quit() -> void:
	Settings.flush()
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not visible or not _settings_pages.is_capturing():
		return
	if _settings_pages.handle_input(event):
		get_viewport().set_input_as_handled()
