class_name YieldPrompt
extends DialogueScreen
## The yield prompt (plan M6-M9 §2.10 the yield protocol; P34): ScreenStack SCREENS["yield"], opened
## by a yielding boss (EnemyActor.p34_yield: Events.ui_screen_requested("yield", {"session",
## "boss_id", "name"})). It is the boss's yield dialogue (dialogue_yield_harrok, dialogue_yield_corvane)
## on the dialogue screen, made hard to decide by accident:
##   * a header names who yields ("HARROK YIELDS");
##   * its choices stay disabled for ARM_S after it opens (or after the line changes), so a blow, a
##     mashed button or a held key that was meant for the fight cannot choose;
##   * the focus starts on Spare; Strike leads to a confirm line first (the dialogue's own node);
##   * Esc / pad B never closes it undecided: on the confirm line it goes back to the choice, otherwise
##     nothing happens (the boss reopens a prompt that was closed some other way).
## Only the outcome it chooses (Events.dialogue_outcome) decides the boss's fate.

## Seconds the choices stay disabled after the prompt opens or its line changes.
const ARM_S := 0.75

var boss_name := ""
var _header: Label
var _armed_at_ms := 0


func _ready() -> void:
	super()
	_header = UiKit.label("", 26, Color(1.0, 0.62, 0.32))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_header.offset_top = 120
	_header.offset_left = -300
	_header.offset_right = 300
	add_child(_header)


func on_open() -> void:
	boss_name = str(args.get("name", ""))
	if _header != null:
		_header.text = ("%s yields" % boss_name).to_upper() if boss_name != "" else "YIELDS"
	super()
	_arm()


## True once the choices take presses (ARM_S after the prompt opened or its line changed).
func armed() -> bool:
	return Time.get_ticks_msec() >= _armed_at_ms


func _arm() -> void:
	_armed_at_ms = Time.get_ticks_msec() + int(ARM_S * 1000.0)
	_set_buttons_enabled(false)


func _process(_delta: float) -> void:
	if is_open() and armed() and not choice_buttons.is_empty() and choice_buttons[0].disabled:
		_set_buttons_enabled(true)


func _set_buttons_enabled(on: bool) -> void:
	for b in choice_buttons:
		if is_instance_valid(b):
			b.disabled = not on


## A choice before the prompt is armed is refused ({"ok": false, "reason": "not_armed"}).
func press_choice(index: int) -> Dictionary:
	if not armed():
		return {"ok": false, "reason": "not_armed"}
	var r := super(index)
	if session != null and session.is_active():
		_arm()
	return r


func _rebuild_choices() -> void:
	super()
	if not armed():
		_set_buttons_enabled(false)


## Esc / pad B: back from the confirm line to the choice; never closes undecided.
func cancel() -> void:
	if session == null or not session.is_active() or not armed():
		return
	for c: Dictionary in session.choices():
		if str(c.get("next", "")) == "yield" and not bool(c.get("locked", false)):
			press_choice(int(c.index))
			return
