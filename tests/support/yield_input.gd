class_name YieldInput
extends RefCounted
## M8 gate (F7): real input for the yield prompt's tests. Keys, pad buttons, pad axes (sticks and
## triggers) and mouse buttons go through Input.parse_input_event, so they take the game's own path:
## Input's state (is_anything_pressed), the ScreenStack's and the prompt's _input / _unhandled_input,
## and the focused or hovered button's GUI input. Every press waits one frame (Input flushes buffered
## events at the start of a frame). A fake clock drives YieldPrompt.test_clock, so the prompt's arm
## time and hold time pass without waiting real seconds. Everything still held is let go by
## release_all() (call it, then uninstall(), in the suite's after_each).

const PATTERN_GAP_MS := 100

var suite: Node
var clock_ms := 1000000
var _keys: Dictionary = {}       ## Key -> true while held
var _buttons: Dictionary = {}    ## JoyButton -> true
var _axes: Dictionary = {}       ## JoyAxis -> value while away from rest
var _mouse: Dictionary = {}      ## MouseButton -> true
var mouse_position := Vector2(640, 360)


func _init(p_suite: Node) -> void:
	suite = p_suite


## Makes the yield prompt read this object's clock.
func install() -> void:
	YieldPrompt.test_clock = func() -> int: return clock_ms


func uninstall() -> void:
	YieldPrompt.test_clock = Callable()


func frame() -> void:
	await suite.get_tree().process_frame


## Advances the fake clock by `ms` in steps of at most `step_ms`, a frame per step.
func wait_ms(ms: int, step_ms := 50) -> void:
	var left := ms
	while left > 0:
		var d := mini(step_ms, left)
		clock_ms += d
		left -= d
		await frame()


func key_down(code: Key) -> void:
	_keys[code] = true
	Input.parse_input_event(_key_event(code, true))
	await frame()


func key_up(code: Key) -> void:
	_keys.erase(code)
	Input.parse_input_event(_key_event(code, false))
	await frame()


func pad_down(button: JoyButton) -> void:
	_buttons[button] = true
	Input.parse_input_event(_pad_event(button, true))
	await frame()


func pad_up(button: JoyButton) -> void:
	_buttons.erase(button)
	Input.parse_input_event(_pad_event(button, false))
	await frame()


## A stick or trigger to `value` (0 = at rest).
func axis(which: JoyAxis, value: float) -> void:
	if absf(value) > 0.0:
		_axes[which] = value
	else:
		_axes.erase(which)
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = which
	e.axis_value = value
	Input.parse_input_event(e)
	await frame()


## Moves the mouse over `at` (a hover the buttons see), in the window's coordinates (centre_of).
func mouse_move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = at - mouse_position
	mouse_position = at
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await frame()


func mouse_down(button := MOUSE_BUTTON_LEFT) -> void:
	_mouse[button] = true
	Input.parse_input_event(_mouse_event(button, true))
	await frame()


func mouse_up(button := MOUSE_BUTTON_LEFT) -> void:
	_mouse.erase(button)
	Input.parse_input_event(_mouse_event(button, false))
	await frame()


## One tap of `what`: a Key, a JoyButton, "rt" / "lt" (a trigger pulled and let go), "mouse" (the
## left button where the mouse is) or "stick_up" / "stick_down" (the left stick pushed and let go).
func tap(what: Variant) -> void:
	if typeof(what) == TYPE_STRING:
		match str(what):
			"rt":
				await axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
				await axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
			"lt":
				await axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
				await axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
			"mouse":
				await mouse_down()
				await mouse_up()
			"stick_up":
				await axis(JOY_AXIS_LEFT_Y, -1.0)
				await axis(JOY_AXIS_LEFT_Y, 0.0)
			"stick_down":
				await axis(JOY_AXIS_LEFT_Y, 1.0)
				await axis(JOY_AXIS_LEFT_Y, 0.0)
		return
	if what is int and _is_pad_button(int(what)):
		await pad_down(what)
		await pad_up(what)
	else:
		await key_down(what)
		await key_up(what)


## Taps `pattern` in turn, one every gap_ms of the fake clock, for total_ms; stops early when
## `stop` (a Callable returning bool) says so. Returns the taps made.
func mash(pattern: Array, total_ms: int, gap_ms := PATTERN_GAP_MS, stop := Callable()) -> int:
	var start := clock_ms
	var i := 0
	while clock_ms - start < total_ms:
		await tap(pattern[i % pattern.size()])
		i += 1
		clock_ms += gap_ms
		if stop.is_valid() and bool(stop.call()):
			break
	return i


## Holds `what` (a Key, a JoyButton or "mouse") for hold_ms of the fake clock, then lets go.
func hold(what: Variant, hold_ms: int) -> void:
	if typeof(what) == TYPE_STRING and str(what) == "mouse":
		await mouse_down()
		await wait_ms(hold_ms)
		await mouse_up()
	elif what is int and _is_pad_button(int(what)):
		await pad_down(what)
		await wait_ms(hold_ms)
		await pad_up(what)
	else:
		await key_down(what)
		await wait_ms(hold_ms)
		await key_up(what)


## Lets go of everything still held (keys, pad buttons, axes, mouse buttons).
func release_all() -> void:
	for code: Key in _keys.keys():
		Input.parse_input_event(_key_event(code, false))
	for b: JoyButton in _buttons.keys():
		Input.parse_input_event(_pad_event(b, false))
	for a: JoyAxis in _axes.keys():
		var e := InputEventJoypadMotion.new()
		e.device = 0
		e.axis = a
		e.axis_value = 0.0
		Input.parse_input_event(e)
	for m: MouseButton in _mouse.keys():
		Input.parse_input_event(_mouse_event(m, false))
	_keys.clear()
	_buttons.clear()
	_axes.clear()
	_mouse.clear()
	Input.flush_buffered_events()


func anything_held() -> bool:
	return not (_keys.is_empty() and _buttons.is_empty() and _axes.is_empty() and _mouse.is_empty())


## Where a mouse event must say it is to land on the centre of `c`: the window's coordinates (the
## root viewport's content scale stretches a 1280 x 720 canvas onto the window, 64 x 64 headless).
static func centre_of(c: Control) -> Vector2:
	var in_viewport := c.get_global_transform_with_canvas() * (c.size * 0.5)
	return c.get_viewport().get_final_transform() * in_viewport


## Pad buttons and keys are both ints: the pad's are 0..14 (A..D-pad right), every key code is higher.
static func _is_pad_button(v: int) -> bool:
	return v >= JOY_BUTTON_A and v <= JOY_BUTTON_DPAD_RIGHT


func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _pad_event(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	return e


func _mouse_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = mouse_position
	e.global_position = mouse_position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	return e
