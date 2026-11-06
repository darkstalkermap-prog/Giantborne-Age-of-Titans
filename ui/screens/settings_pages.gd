class_name SettingsPages
extends RefCounted
## The Settings and Controls pages, shared by the pause menu and the title screen (P06): one
## instance per screen. The screen adds the pages it builds and forwards its _input events to
## handle_input(), which runs the rebinding capture: the next key or mouse button (keyboard
## column) or pad button / trigger (controller column) becomes the binding; Esc cancels.
##
## Settings rows apply live; sliders write the settings file when a drag ends (the screen calls
## Settings.flush() on close for keyboard and pad slider changes). P14 added the graphics preset
## row (graphics_row).
##
## P19 (audio): the page opens with an Audio section - Master, Music, Ambience, Effects and
## Interface volumes (0-100 %, applied live through Settings.changed) and "Mute when the window
## loses focus" - then the camera, control and display rows.
##
## P16 (pad and keyboard): settings_rows() and controls_rows() give the screens their focus rows
## (one row per setting; a keyboard and a controller binding button per action, then Reset); the
## scroll areas follow the focus. The controller row "Button prompts" (Auto / Keyboard and mouse /
## Controller) pins the glyphs the prompts show (Settings "prompt_device"). Esc still cancels a
## capture, and a capture also ends by itself after CAPTURE_TIMEOUT_S (the screen calls
## update_capture() every frame), so a controller-only player is never stuck in it.

const CAPTURE_TIMEOUT_S := 6.0
## The Button prompts row: [setting value, label].
const PROMPT_OPTIONS := [["auto", "Auto (last device)"], ["keyboard", "Keyboard and mouse"],
	["pad", "Controller"]]
## P19: the Audio section's sliders: [label, setting key] (Settings volume_*, 0..1; 0 mutes).
const AUDIO_SLIDERS := [["Master volume", "volume_master"], ["Music", "volume_music"],
	["Ambience", "volume_ambience"], ["Effects", "volume_sfx"], ["Interface", "volume_ui"]]

var _capture_action := ""
var _capture_pad := false
var _capture_ms := 0
var _capture_label: Label
var _binding_buttons: Dictionary = {}
var _settings_rows: Array = []    ## [[Control]] one per setting row, top to bottom
var _controls_rows: Array = []    ## [[keyboard Button, controller Button]] per action, then [[Reset]]


# --------------------------------------------------------------------------- settings page

func build_settings() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.follow_focus = true
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_settings_rows.clear()
	# P19: the Audio section first (five volumes and the focus mute; pad-navigable like every row).
	section_header(grid, "Audio")
	for entry: Array in AUDIO_SLIDERS:
		_row(volume_row(grid, str(entry[0]), str(entry[1])))
	_row(check_row(grid, "Mute when the window loses focus", "mute_when_unfocused"))
	section_header(grid, "Camera, controls and display")
	_row(slider_row(grid, "Mouse sensitivity", "mouse_sensitivity", 0.02, 0.6, 0.01))
	_row(slider_row(grid, "Stick look speed", "stick_look_speed_deg_s", 60.0, 400.0, 5.0))
	_row(check_row(grid, "Invert look Y", "invert_y"))
	_row(slider_row(grid, "Field of view", "fov_deg", 60.0, 100.0, 1.0))
	_row(option_row(grid, "Sprint", "sprint_mode", ["hold", "toggle"]))
	_row(option_row(grid, "Lock-on", "lock_mode", ["toggle", "hold"]))
	_row(slider_row(grid, "Camera shake", "camera_shake", 0.0, 1.0, 0.05))
	_row(slider_row(grid, "Head bob (first person)", "head_bob", 0.0, 1.0, 0.05))
	_row(slider_row(grid, "Hit flash", "hit_flash", 0.0, 1.0, 0.05))
	_row(slider_row(grid, "Controller vibration", "vibration", 0.0, 1.0, 0.05))
	_row(prompts_row(grid))
	_row(check_row(grid, "First-person lock aim assist", "fp_aim_assist"))
	_row(check_row(grid, "Damage numbers", "damage_numbers"))
	_row(graphics_row(grid))
	grid.add_child(UiKit.label("Motion blur", 15))
	var mb := CheckBox.new()
	mb.button_pressed = false
	mb.disabled = true
	mb.text = "Off (not in prototype)"
	grid.add_child(mb)
	return scroll


func _row(c: Control) -> void:
	_settings_rows.append([c])


## The settings page's focus rows (one control per row, top to bottom; P16).
func settings_rows() -> Array:
	return _settings_rows.duplicate()


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


## A volume slider (P19): 0-100 % in steps of 5, applied live (the Audio autoload listens to
## Settings.changed), written when the drag ends.
static func volume_row(grid: GridContainer, text: String, key: String) -> HSlider:
	grid.add_child(UiKit.label(text, 15))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(260, 24)
	s.focus_mode = Control.FOCUS_ALL
	var value_label := UiKit.label(volume_text(s.value), 13, UiKit.MUTED)
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v, false)
		value_label.text = volume_text(v))
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.flush())
	var h := HBoxContainer.new()
	h.add_child(s)
	h.add_child(value_label)
	grid.add_child(h)
	return s


static func volume_text(v: float) -> String:
	return "Off" if v <= 0.0001 else "%d %%" % int(round(v * 100.0))


## A section title spanning the grid's two columns (not focusable).
static func section_header(grid: GridContainer, text: String) -> void:
	grid.add_child(UiKit.label(text, 17, UiKit.WARN))
	grid.add_child(Control.new())


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


## The graphics preset row (P14): Low (shorter shadows and scenery range, no MSAA: the
## reference-PC measurement preset) or Medium. Changing it applies at once (LevelRoot listens).
## The web build always runs Low and a --graphics flag fixes the preset for the run: the row then
## shows the preset in effect, disabled, with the reason as its tooltip.
static func graphics_row(grid: GridContainer) -> OptionButton:
	var o := option_row(grid, "Graphics preset", "graphics_quality", Settings.GRAPHICS_QUALITIES)
	o.tooltip_text = "Low: shorter shadow and scenery distances, no MSAA (the reference-PC preset). " \
		+ "Medium: the full distances with MSAA. Each level's record sets the numbers."
	var reason := Settings.graphics_lock_reason()
	if reason != "":
		o.select(maxi(0, Settings.GRAPHICS_QUALITIES.find(Settings.graphics_quality)))
		o.disabled = true
		o.tooltip_text = reason
	return o


## The controller row "Button prompts" (P16): which buttons the prompts, the hotbar and the
## tutorial texts name - the last device used (Auto), always the keyboard and mouse, or always the
## controller.
static func prompts_row(grid: GridContainer) -> OptionButton:
	grid.add_child(UiKit.label("Button prompts", 15))
	var o := OptionButton.new()
	var current := str(Settings.get_value("prompt_device"))
	for i in PROMPT_OPTIONS.size():
		o.add_item(str(PROMPT_OPTIONS[i][1]), i)
		if PROMPT_OPTIONS[i][0] == current:
			o.select(i)
	o.tooltip_text = "Auto shows the buttons of the keyboard and mouse or the controller, whichever you used last."
	o.item_selected.connect(func(i: int) -> void: Settings.set_value("prompt_device", str(PROMPT_OPTIONS[i][0])))
	grid.add_child(o)
	return o


# --------------------------------------------------------------------------- controls page

func build_controls() -> Control:
	var v := VBoxContainer.new()
	var hint := UiKit.label("Select a binding (click, Enter or pad A), then press the new key or button. Esc cancels.",
		13, UiKit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	grid.add_child(UiKit.label("Action", 14, UiKit.MUTED))
	grid.add_child(UiKit.label("Keyboard / mouse", 14, UiKit.MUTED))
	grid.add_child(UiKit.label("Controller", 14, UiKit.MUTED))
	_controls_rows.clear()
	for action_name: String in InputBindings.ACTIONS:
		grid.add_child(UiKit.label(InputBindings.LABELS.get(action_name, action_name), 14))
		var row: Array = []
		for pad in [false, true]:
			var b := UiKit.button("", 13)
			b.custom_minimum_size = Vector2(190, 0)
			b.pressed.connect(begin_capture.bind(action_name, pad))
			grid.add_child(b)
			_binding_buttons["%s|%s" % [action_name, pad]] = b
			row.append(b)
		_controls_rows.append(row)
	_capture_label = UiKit.label("", 14, UiKit.WARN)
	v.add_child(_capture_label)
	var reset := UiKit.button("Reset all bindings to defaults", 14)
	reset.pressed.connect(_reset_bindings)
	v.add_child(reset)
	_controls_rows.append([reset])
	refresh_bindings()
	return v


## The controls page's focus rows (P16): [keyboard, controller] binding buttons per action, then
## the Reset button.
func controls_rows() -> Array:
	return _controls_rows.duplicate()


## The binding button of an action's keyboard (pad false) or controller column, or null (tests).
func binding_button(action_name: String, pad: bool) -> Button:
	return _binding_buttons.get("%s|%s" % [action_name, pad])


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
	_capture_ms = Time.get_ticks_msec()
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = "Press a %s for '%s'... (Esc cancels; it gives up after %d s)" % [
			"controller button" if pad else "key or mouse button",
			InputBindings.LABELS.get(action_name, action_name), int(CAPTURE_TIMEOUT_S)]


func cancel_capture() -> void:
	_capture_action = ""
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = ""


## Called every frame by the screen (P16): a capture nobody answered ends after CAPTURE_TIMEOUT_S
## (real time; a controller has no Esc). Returns true when it just timed out.
func update_capture(now_ms: int = -1) -> bool:
	if _capture_action == "":
		return false
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _capture_ms < int(CAPTURE_TIMEOUT_S * 1000.0):
		return false
	cancel_capture()
	if _capture_label != null and is_instance_valid(_capture_label):
		_capture_label.text = "No input: the binding was not changed."
	return true


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
