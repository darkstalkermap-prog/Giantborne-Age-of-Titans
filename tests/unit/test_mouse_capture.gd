extends TestSuite
## Click-to-capture rule in scripts/main.gd. While the mouse is free (always the case at the start
## of the web build, where browsers grant pointer lock only inside a click), a click must take the
## mouse back instead of reaching the input router as an attack or block.

const MainScript := preload("res://scripts/main.gd")


func _click(button: MouseButton, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e


func test_click_on_free_mouse_captures() -> void:
	assert_true(MainScript.is_capture_click(_click(MOUSE_BUTTON_LEFT), false, false), "left click with a free mouse captures")
	assert_true(MainScript.is_capture_click(_click(MOUSE_BUTTON_RIGHT), false, false), "right click with a free mouse captures")
	assert_true(MainScript.is_capture_click(_click(MOUSE_BUTTON_MIDDLE), false, false), "middle click with a free mouse captures")


func test_click_is_gameplay_when_already_captured() -> void:
	assert_false(MainScript.is_capture_click(_click(MOUSE_BUTTON_LEFT), true, false), "captured: left click stays an attack")
	assert_false(MainScript.is_capture_click(_click(MOUSE_BUTTON_RIGHT), true, false), "captured: right click stays a block")


func test_menu_clicks_and_other_events_never_capture() -> void:
	assert_false(MainScript.is_capture_click(_click(MOUSE_BUTTON_LEFT), false, true), "clicks in the pause menu go to the menu")
	assert_false(MainScript.is_capture_click(_click(MOUSE_BUTTON_LEFT, false), false, false), "a button release does not capture")
	assert_false(MainScript.is_capture_click(_click(MOUSE_BUTTON_WHEEL_UP), false, false), "a wheel step does not capture")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	assert_false(MainScript.is_capture_click(key, false, false), "a key press does not capture")
