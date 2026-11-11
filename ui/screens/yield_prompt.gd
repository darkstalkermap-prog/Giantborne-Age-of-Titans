class_name YieldPrompt
extends DialogueScreen
## The yield prompt (plan M6-M9 §2.10 the yield protocol; P34): ScreenStack SCREENS["yield"], opened
## by a yielding boss (EnemyActor.p34_yield: Events.ui_screen_requested("yield", {"session",
## "boss_id", "name"})). It is the boss's yield dialogue (dialogue_yield_harrok, dialogue_yield_corvane)
## on the dialogue screen, and no input meant for the fight can answer it (M8 gate F7: mashed ability
## keys 1 and 2 used to confirm Strike):
##   * a header names who yields ("HARROK YIELDS");
##   * the number keys never choose here (1-4 are the ability keys) and the choices carry no numbers;
##   * a line's choices arm only once every button has been let go for ARM_S - nothing held (keys,
##     mouse buttons, pad buttons, triggers and sticks past their dead zones) and nothing pressed or
##     released meanwhile - after the prompt opens and after every change of line: a fight that goes
##     on (mashed keys or buttons, a held trigger, a held mouse button) never arms it;
##   * on a line that decides (the Spare / Strike line and the confirm line) a choice is taken by
##     HOLDING it for HOLD_S - pad A, Enter or the mouse button held on it, a fill showing the hold - so
##     no tap decides; letting go early, moving the focus or the mouse off it cancels the hold;
##   * the focus starts on Spare, and on the confirm line on "No - let me think again" (the dialogue's
##     first choice there): Strike is never first nor the default;
##   * Esc / pad B never closes it undecided: on the confirm line it goes back to the choice, otherwise
##     nothing happens (the boss reopens a prompt that was closed some other way);
##   * a line under the choices says what to do, for the device in use (InputBindings).
## press_choice() takes an armed choice at once (tests and tools; the hold ends in it); the bots decide
## through EnemyActor.p34_decide or the dialogue session. Only the outcome it chooses
## (Events.dialogue_outcome) decides the boss's fate.

## Seconds every button must have been let go (nothing held, pressed or released) before a line's
## choices take input: after the prompt opens and after every change of line.
const ARM_S := 0.75
## Seconds a choice of a deciding line must be held (pad A, Enter, the mouse button) to be taken.
const HOLD_S := 0.8
## A stick or trigger at least this far from rest counts as touching the controls (InputBindings'
## device threshold).
const AXIS_TOUCH := 0.5
const HOLD_FILL := Color(1.0, 0.62, 0.32, 0.38)

## Tests: () -> int, the clock in milliseconds the arming and the holds read (default
## Time.get_ticks_msec). Put it back to Callable() after use.
static var test_clock := Callable()

var boss_name := ""
var _header: Label
var _hint: Label
var _armed := false
var _quiet_since_ms := 0
var _decides := false
var _hold_index := -1
var _hold_since_ms := 0
var _fills: Dictionary = {}   ## choice index -> its hold fill (ColorRect)
var _hint_key := ""


func _ready() -> void:
	super()
	_header = UiKit.label("", 26, Color(1.0, 0.62, 0.32))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_header.offset_top = 120
	_header.offset_left = -300
	_header.offset_right = 300
	add_child(_header)
	_hint = UiKit.label("", 14, UiKit.MUTED)
	_hint.name = "YieldHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(760, 0)
	_choices.get_parent().add_child(_hint)


func on_open() -> void:
	boss_name = str(args.get("name", ""))
	if _header != null:
		_header.text = ("%s yields" % boss_name).to_upper() if boss_name != "" else "YIELDS"
	super()
	_disarm()


func on_close() -> void:
	_cancel_hold()
	super()


## The clock the arming and the holds read (test_clock when set).
static func now_ms() -> int:
	return int(test_clock.call()) if test_clock.is_valid() else Time.get_ticks_msec()


## True once the current line's choices take input.
func armed() -> bool:
	return _armed


## Tests and tools: arms the current line at once (as if every button had been let go long enough).
func arm_now() -> void:
	if is_open() and session != null and session.is_active():
		_arm()


## True while the current line decides the yield (its choices are held, not pressed).
func line_decides() -> bool:
	return _decides


## The choice being held (-1 = none) and how far the hold has got (0..1).
func held_choice() -> int:
	return _hold_index


func hold_progress() -> float:
	if _hold_index < 0:
		return 0.0
	return clampf(float(now_ms() - _hold_since_ms) / (HOLD_S * 1000.0), 0.0, 1.0)


## The line under the choices: what to do now, for the device in use.
func hint_text() -> String:
	return _hint.text if _hint != null else ""


## Keys 1-4 are the fight's ability keys: they never choose here, and the buttons carry no numbers.
func numbered_keys() -> bool:
	return false


## True for an input event that touches the controls: any key, mouse button or pad button, pressed
## or let go, and a stick or trigger pushed AXIS_TOUCH or more (mouse movement is not).
static func touches_controls(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		return true
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= AXIS_TOUCH
	return false


## Every event reaches this first (the screen runs while the game is paused): while the line is not
## armed, touching the controls starts the quiet time again.
func _input(event: InputEvent) -> void:
	if is_open() and not _armed and touches_controls(event):
		_quiet_since_ms = now_ms()


func _process(_delta: float) -> void:
	if not is_open():
		return
	if not _armed:
		if Input.is_anything_pressed():
			_quiet_since_ms = now_ms()
		elif now_ms() - _quiet_since_ms >= int(ARM_S * 1000.0) and session != null and session.is_active():
			_arm()
	elif _hold_index >= 0:
		_hold_step()
	_update_hint()


func _arm() -> void:
	_armed = true
	_set_buttons_enabled(true)
	refresh_focus()
	var f := first_focus()
	if f != null and is_instance_valid(f) and f.is_visible_in_tree() and not (f as Button).disabled:
		f.grab_focus()
	_update_hint()


## Not armed: the choices are disabled until every button has been let go for ARM_S from now.
func _disarm() -> void:
	_armed = false
	_quiet_since_ms = now_ms()
	_cancel_hold()
	_set_buttons_enabled(false)
	_update_hint()


func _set_buttons_enabled(on: bool) -> void:
	for b in choice_buttons:
		if is_instance_valid(b):
			b.disabled = not on or bool(b.get_meta("locked", false))


## A choice before the line is armed is refused ({"ok": false, "reason": "not_armed"}). A line that
## follows is not armed until every button has been let go for ARM_S again.
func press_choice(index: int) -> Dictionary:
	if not _armed:
		return {"ok": false, "reason": "not_armed"}
	_cancel_hold()
	var r := super(index)
	if session != null and session.is_active():
		_disarm()
	return r


func _rebuild_choices() -> void:
	_cancel_hold()
	_fills.clear()
	_decides = false
	if session != null and session.is_active():
		for c: Dictionary in session.choices():
			if str(c.get("outcome", "")) != "":
				_decides = true
	super()
	if not _armed:
		_set_buttons_enabled(false)
	_hint_key = ""
	_update_hint()


## A deciding line's buttons are held: button_down starts the hold, letting go, the focus or the mouse
## leaving ends it, and the button's own press (a tap) takes nothing. Other lines ([Leave]) press.
func _wire_choice(b: Button, c: Dictionary) -> void:
	b.set_meta("locked", bool(c.get("locked", false)))
	if not _decides:
		super(b, c)
		return
	var i := int(c.index)
	b.button_down.connect(_on_hold_down.bind(i))
	b.button_up.connect(_on_hold_up.bind(i))
	b.focus_exited.connect(_on_hold_up.bind(i))
	b.mouse_exited.connect(_on_hold_up.bind(i))
	var fill := ColorRect.new()
	fill.name = "HoldFill"
	fill.color = HOLD_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.0
	b.add_child(fill)
	_fills[i] = fill


func _on_hold_down(i: int) -> void:
	if not _armed or i < 0 or i >= choice_buttons.size() or not is_instance_valid(choice_buttons[i]) \
			or choice_buttons[i].disabled:
		return
	_hold_index = i
	_hold_since_ms = now_ms()


func _on_hold_up(i: int) -> void:
	if _hold_index == i:
		_cancel_hold()


func _hold_step() -> void:
	var p := hold_progress()
	var fill := _fills.get(_hold_index) as ColorRect
	if fill != null and is_instance_valid(fill):
		fill.anchor_right = p
		fill.offset_right = 0.0
	if p >= 1.0:
		var i := _hold_index
		_cancel_hold()
		press_choice(i)


func _cancel_hold() -> void:
	_hold_index = -1
	for f: Variant in _fills.values():
		if is_instance_valid(f):
			(f as ColorRect).anchor_right = 0.0
			(f as ColorRect).offset_right = 0.0


## Esc / pad B: back from the confirm line to the choice; never closes undecided.
func cancel() -> void:
	if session == null or not session.is_active() or not _armed:
		return
	var back := _back_choice()
	if back >= 0:
		press_choice(back)


## The index of the choice that goes back to the yield's first line (-1 when there is none).
func _back_choice() -> int:
	if session == null or not session.is_active():
		return -1
	for c: Dictionary in session.choices():
		if str(c.get("next", "")) == "yield" and not bool(c.get("locked", false)):
			return int(c.index)
	return -1


func _update_hint() -> void:
	if _hint == null:
		return
	var pad := InputBindings.last_device_is_pad()
	var back := _back_choice() >= 0
	var key := "%s|%s|%s|%s" % [_armed, _decides, back, pad]
	if key == _hint_key:
		return
	_hint_key = key
	_hint.text = hint_for(_armed, _decides, back, pad)


## What the line under the choices says: let go of everything while not armed; then how to move, how
## to take a choice (held on a deciding line) and, on the confirm line, how to go back.
static func hint_for(is_armed: bool, decides: bool, can_go_back: bool, pad: bool) -> String:
	if not is_armed:
		return "Let go of every button to choose."
	var parts: PackedStringArray = []
	if pad:
		parts.append("Hold A on a choice to take it" if decides else "A: choose")
		parts.append("D-pad / left stick: move")
		if can_go_back:
			parts.append("B: back")
	else:
		parts.append("Hold Enter, or hold the mouse button on a choice, to take it" if decides \
			else "Enter or click: choose")
		parts.append("Arrows: move")
		if can_go_back:
			parts.append("Esc: back")
	return "     ".join(parts)
