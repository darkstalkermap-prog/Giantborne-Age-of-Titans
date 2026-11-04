class_name PauseMenu
extends Control
## Pause menu (Esc / Start): resume, settings, control rebinding, restart, quit.
## While open the game is paused and the input context is MENU, so gameplay input is
## suppressed. Rebinding captures the next key/mouse button (keyboard column) or the next
## pad button/trigger (controller column); Esc cancels a capture.

var _root_panel: PanelContainer
var _pages: Dictionary = {}
var _capture_action := ""
var _capture_pad := false
var _capture_label: Label
var _binding_buttons: Dictionary = {}
var _status: Label


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
	for name: String in ["Main", "Settings", "Controls"]:
		var b := UiKit.button(name, 16)
		b.pressed.connect(_show_page.bind(name))
		tabs.add_child(b)
	var holder := MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(holder)
	_pages["Main"] = _build_main()
	_pages["Settings"] = _build_settings()
	_pages["Controls"] = _build_controls()
	for page: Control in _pages.values():
		holder.add_child(page)
	_status = UiKit.label("", 13, UiKit.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_show_page("Main")
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	InputRouter.set_context(InputRouter.Context.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = Settings.load_message
	_show_page("Main")


func close() -> void:
	_cancel_capture()
	Settings.save_settings()  # covers keyboard/gamepad slider changes (no drag_ended)
	visible = false
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_page(name: String) -> void:
	for key: String in _pages:
		(_pages[key] as Control).visible = key == name
	if name == "Controls":
		_refresh_bindings()


func _build_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var resume := UiKit.button("Resume", 20)
	resume.pressed.connect(close)
	v.add_child(resume)
	var restart := UiKit.button("Restart sandbox", 20)
	restart.pressed.connect(func() -> void:
		close()
		Events.sandbox_reset_requested.emit("menu_restart"))
	v.add_child(restart)
	var quit := UiKit.button("Quit to desktop", 20)
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)
	var info := UiKit.label("Giantborn: Age of Titans  -  prototype %s  -  Godot %s" % [
		ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 12, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	return v


func _slider_row(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float) -> void:
	grid.add_child(UiKit.label(text, 15))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(260, 24)
	var value_label := UiKit.label("%.2f" % s.value, 13, UiKit.MUTED)
	# Apply live while dragging; write the settings file once, when the drag ends.
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v, false)
		value_label.text = "%.2f" % v)
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.save_settings())
	var h := HBoxContainer.new()
	h.add_child(s)
	h.add_child(value_label)
	grid.add_child(h)


func _check_row(grid: GridContainer, text: String, key: String) -> void:
	grid.add_child(UiKit.label(text, 15))
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		Settings.set_value(key, on))
	grid.add_child(c)


func _option_row(grid: GridContainer, text: String, key: String, options: Array) -> void:
	grid.add_child(UiKit.label(text, 15))
	var o := OptionButton.new()
	for i in options.size():
		o.add_item(str(options[i]).capitalize(), i)
		if options[i] == Settings.get_value(key):
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, options[i]))
	grid.add_child(o)


func _build_settings() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_slider_row(grid, "Mouse sensitivity", "mouse_sensitivity", 0.02, 0.6, 0.01)
	_slider_row(grid, "Stick look speed", "stick_look_speed_deg_s", 60.0, 400.0, 5.0)
	_check_row(grid, "Invert look Y", "invert_y")
	_slider_row(grid, "Field of view", "fov_deg", 60.0, 100.0, 1.0)
	_option_row(grid, "Sprint", "sprint_mode", ["hold", "toggle"])
	_option_row(grid, "Lock-on", "lock_mode", ["toggle", "hold"])
	_slider_row(grid, "Camera shake", "camera_shake", 0.0, 1.0, 0.05)
	_slider_row(grid, "Head bob (first person)", "head_bob", 0.0, 1.0, 0.05)
	_slider_row(grid, "Hit flash", "hit_flash", 0.0, 1.0, 0.05)
	_slider_row(grid, "Controller vibration", "vibration", 0.0, 1.0, 0.05)
	_check_row(grid, "First-person lock aim assist", "fp_aim_assist")
	_check_row(grid, "Damage numbers", "damage_numbers")
	grid.add_child(UiKit.label("Motion blur", 15))
	var mb := CheckBox.new()
	mb.button_pressed = false
	mb.disabled = true
	mb.text = "Off (not in prototype)"
	grid.add_child(mb)
	return scroll


func _build_controls() -> Control:
	var v := VBoxContainer.new()
	var hint := UiKit.label("Click a binding, then press the new key / button. Esc cancels.", 13, UiKit.MUTED)
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	grid.add_child(UiKit.label("Action", 14, UiKit.MUTED))
	grid.add_child(UiKit.label("Keyboard / mouse", 14, UiKit.MUTED))
	grid.add_child(UiKit.label("Controller", 14, UiKit.MUTED))
	for action_name: String in InputBindings.ACTIONS:
		grid.add_child(UiKit.label(InputBindings.LABELS.get(action_name, action_name), 14))
		for pad in [false, true]:
			var b := UiKit.button("", 13)
			b.custom_minimum_size = Vector2(190, 0)
			b.pressed.connect(_begin_capture.bind(action_name, pad))
			grid.add_child(b)
			_binding_buttons["%s|%s" % [action_name, pad]] = b
	_capture_label = UiKit.label("", 14, UiKit.WARN)
	v.add_child(_capture_label)
	var reset := UiKit.button("Reset all bindings to defaults", 14)
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh_bindings())
	v.add_child(reset)
	return v


func _refresh_bindings() -> void:
	for key: String in _binding_buttons:
		var parts := key.split("|")
		(_binding_buttons[key] as Button).text = InputBindings.describe_action(parts[0], parts[1] == "true")


func _begin_capture(action_name: String, pad: bool) -> void:
	_capture_action = action_name
	_capture_pad = pad
	_capture_label.text = "Press a %s for '%s'..." % ["controller button" if pad else "key or mouse button",
		InputBindings.LABELS.get(action_name, action_name)]


func _cancel_capture() -> void:
	_capture_action = ""
	if _capture_label != null:
		_capture_label.text = ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture_action == "":
		return
	if event is InputEventMouseMotion:
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE and event.is_pressed():
		_cancel_capture()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() and not (event is InputEventJoypadMotion):
		return
	var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if is_pad != _capture_pad:
		return
	# Holding the modifier (LT) while choosing a combo button must not bind the modifier itself.
	if InputBindings.COMBO_ACTIONS.has(_capture_action) and event.is_action("ability_modifier"):
		return
	var d := InputBindings.event_to_dict(event)
	if d.is_empty():
		return
	var conflicts := Settings.find_conflicts(_capture_action, d)
	Settings.set_action_binding(_capture_action, _capture_pad, d)
	_capture_label.text = ("Bound %s. Also used by: %s" % [InputBindings.describe(d), ", ".join(conflicts)]) \
		if not conflicts.is_empty() else "Bound %s." % InputBindings.describe(d)
	_capture_action = ""
	_refresh_bindings()
	get_viewport().set_input_as_handled()
