class_name SettingsPages
extends RefCounted
## The Settings and Controls pages, shared by the pause menu and the title screen (P06): one
## instance per screen. The screen adds the pages it builds and forwards its _input events to
## handle_input(), which runs the rebinding capture: the next key or mouse button (keyboard
## column) or pad button / trigger (controller column) becomes the binding; Esc cancels.
##
## Settings rows apply live; sliders write the settings file when a drag ends (the screen calls
## Settings.flush() on close for keyboard and pad slider changes). P14 adds the graphics preset
## row and P16 the controller rows here.

var _capture_action := ""
var _capture_pad := false
var _capture_label: Label
var _binding_buttons: Dictionary = {}


# --------------------------------------------------------------------------- settings page

func build_settings() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	slider_row(grid, "Mouse sensitivity", "mouse_sensitivity", 0.02, 0.6, 0.01)
	slider_row(grid, "Stick look speed", "stick_look_speed_deg_s", 60.0, 400.0, 5.0)
	check_row(grid, "Invert look Y", "invert_y")
	slider_row(grid, "Field of view", "fov_deg", 60.0, 100.0, 1.0)
	option_row(grid, "Sprint", "sprint_mode", ["hold", "toggle"])
	option_row(grid, "Lock-on", "lock_mode", ["toggle", "hold"])
	slider_row(grid, "Camera shake", "camera_shake", 0.0, 1.0, 0.05)
	slider_row(grid, "Head bob (first person)", "head_bob", 0.0, 1.0, 0.05)
	slider_row(grid, "Hit flash", "hit_flash", 0.0, 1.0, 0.05)
	slider_row(grid, "Controller vibration", "vibration", 0.0, 1.0, 0.05)
	check_row(grid, "First-person lock aim assist", "fp_aim_assist")
	check_row(grid, "Damage numbers", "damage_numbers")
	grid.add_child(UiKit.label("Motion blur", 15))
	var mb := CheckBox.new()
	mb.button_pressed = false
	mb.disabled = true
	mb.text = "Off (not in prototype)"
	grid.add_child(mb)
	return scroll


static func slider_row(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float) -> HSlider:
	grid.add_child(UiKit.label(text, 15))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(260, 24)
	s.focus_mode = Control.FOCUS_ALL
	var value_label := UiKit.label("%.2f" % s.value, 13, UiKit.MUTED)
	# Apply live while dragging; write the settings file once, when the drag ends.
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v, false)
		value_label.text = "%.2f" % v)
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.flush())
	var h := HBoxContainer.new()
	h.add_child(s)
	h.add_child(value_label)
	grid.add_child(h)
	return s


static func check_row(grid: GridContainer, text: String, key: String) -> CheckBox:
	grid.add_child(UiKit.label(text, 15))
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		Settings.set_value(key, on))
	grid.add_child(c)
	return c


static func option_row(grid: GridContainer, text: String, key: String, options: Array) -> OptionButton:
	grid.add_child(UiKit.label(text, 15))
	var o := OptionButton.new()
	for i in options.size():
		o.add_item(str(options[i]).capitalize(), i)
		if options[i] == Settings.get_value(key):
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, options[i]))
	grid.add_child(o)
	return o


# --------------------------------------------------------------------------- controls page

func build_controls() -> Control:
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
			b.pressed.connect(begin_capture.bind(action_name, pad))
			grid.add_child(b)
			_binding_buttons["%s|%s" % [action_name, pad]] = b
	_capture_label = UiKit.label("", 14, UiKit.WARN)
	v.add_child(_capture_label)
	var reset := UiKit.button("Reset all bindings to defaults", 14)
	reset.pressed.connect(_reset_bindings)
	v.add_child(reset)
	refresh_bindings()
	return v


func refresh_bindings() -> void:
	for key: String in _binding_buttons:
		var parts := key.split("|")
		var b: Button = _binding_buttons[key]
		if is_instance_valid(b):
			b.text = InputBindings.describe_action(parts[0], parts[1] == "true")


func is_capturing() -> bool:
	return _capture_action != ""


func capture_text() -> String:
	return _capture_label.text if _capture_label != null and is_instance_valid(_capture_label) else ""


func begin_capture(action_name: String, pad: bool) -> void:
	_capture_action = action_name
	_capture_pad = pad
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = "Press a %s for '%s'..." % ["controller button" if pad else "key or mouse button",
			InputBindings.LABELS.get(action_name, action_name)]


func cancel_capture() -> void:
	_capture_action = ""
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = ""


func _reset_bindings() -> void:
	Settings.reset_bindings()
	refresh_bindings()


## Feed every input event while the controls page is visible. Returns true when the event was
## used by the rebinding capture (the screen then marks it handled).
func handle_input(event: InputEvent) -> bool:
	if _capture_action == "":
		return false
	if event is InputEventMouseMotion:
		return false
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE and event.is_pressed():
		cancel_capture()
		return true
	if not event.is_pressed() and not (event is InputEventJoypadMotion):
		return false
	var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if is_pad != _capture_pad:
		return false
	# Holding the modifier (LT) while choosing a combo button must not bind the modifier itself.
	if InputBindings.COMBO_ACTIONS.has(_capture_action) and event.is_action("ability_modifier"):
		return false
	var d := InputBindings.event_to_dict(event)
	if d.is_empty():
		return false
	var conflicts := Settings.find_conflicts(_capture_action, d)
	Settings.set_action_binding(_capture_action, _capture_pad, d)
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = ("Bound %s. Also used by: %s" % [InputBindings.describe(d), ", ".join(conflicts)]) \
			if not conflicts.is_empty() else "Bound %s." % InputBindings.describe(d)
	_capture_action = ""
	refresh_bindings()
	return true
