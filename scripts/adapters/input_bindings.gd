class_name InputBindings
extends RefCounted
## Engine adapter: builds Godot's InputMap from data/input/default_bindings.json plus the
## player's overrides from Settings. All gameplay actions are remappable this way.

const ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"look_left", "look_right", "look_up", "look_down",
	"attack_light", "attack_heavy", "heavy_modifier", "block", "dodge", "jump", "interact",
	"sprint", "lock_target", "target_prev", "target_next", "camera_toggle",
	"ability_1", "ability_2", "ability_3", "ability_4",
	"ability_5", "ability_6", "ability_7", "ability_8",
	"ability_modifier", "ultimate", "pause", "help", "debug_panel", "debug_reset",
	"inventory", "debug_grow", "debug_shrink", "debug_xp", "debug_checkpoint",
]

## Actions whose controller binding is a combo with "ability_modifier" (LT by default).
const COMBO_ACTIONS := ["ability_1", "ability_2", "ability_3", "ability_4", "ability_5",
	"ability_6", "ability_7", "ability_8", "ultimate"]

const LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left",
	"move_right": "Move right", "look_left": "Look left (stick)", "look_right": "Look right (stick)",
	"look_up": "Look up (stick)", "look_down": "Look down (stick)",
	"attack_light": "Light attack", "attack_heavy": "Heavy attack (direct)",
	"heavy_modifier": "Heavy modifier (+ light)", "block": "Block / parry", "dodge": "Dodge",
	"jump": "Jump", "interact": "Interact / grab", "sprint": "Sprint", "lock_target": "Lock target",
	"target_prev": "Previous target / zoom in", "target_next": "Next target / zoom out",
	"camera_toggle": "Camera mode", "ability_1": "Ability 1", "ability_2": "Ability 2",
	"ability_3": "Ability 3", "ability_4": "Ability 4", "ability_5": "Ability 5",
	"ability_6": "Ability 6", "ability_7": "Ability 7", "ability_8": "Ability 8",
	"ability_modifier": "Ability modifier (pad)", "ultimate": "Ultimate", "pause": "Pause menu",
	"help": "Controls overlay", "debug_panel": "Debug panel", "debug_reset": "Debug reset",
	"inventory": "Inventory", "debug_grow": "Debug grow", "debug_shrink": "Debug shrink",
	"debug_xp": "Debug +100 XP", "debug_checkpoint": "Debug reload checkpoint",
}

const MOUSE_BUTTONS := {"left": 1, "right": 2, "middle": 3, "wheel_up": 4, "wheel_down": 5,
	"wheel_left": 6, "wheel_right": 7, "extra_1": 8, "extra_2": 9}
const JOY_BUTTONS := {"a": 0, "b": 1, "x": 2, "y": 3, "back": 4, "guide": 5, "start": 6,
	"left_stick": 7, "right_stick": 8, "left_shoulder": 9, "right_shoulder": 10, "dpad_up": 11,
	"dpad_down": 12, "dpad_left": 13, "dpad_right": 14}
const JOY_AXES := {"left_x": 0, "left_y": 1, "right_x": 2, "right_y": 3, "trigger_left": 4,
	"trigger_right": 5}

const SHORT_PAD := {"a": "A", "b": "B", "x": "X", "y": "Y", "back": "Back", "guide": "Guide",
	"start": "Start", "left_stick": "L3", "right_stick": "R3", "left_shoulder": "LB",
	"right_shoulder": "RB", "dpad_up": "Up", "dpad_down": "Dn", "dpad_left": "Lt", "dpad_right": "Rt",
	"trigger_left": "LT", "trigger_right": "RT"}

const MOUSE_LABELS := {"left": "Mouse Left", "right": "Mouse Right", "middle": "Mouse Middle",
	"wheel_up": "Wheel Up", "wheel_down": "Wheel Down", "wheel_left": "Wheel Left",
	"wheel_right": "Wheel Right", "extra_1": "Mouse 4", "extra_2": "Mouse 5"}
const JOY_LABELS := {"a": "Pad A / Cross", "b": "Pad B / Circle", "x": "Pad X / Square",
	"y": "Pad Y / Triangle", "back": "Pad Back", "guide": "Pad Guide", "start": "Pad Start",
	"left_stick": "Pad L3", "right_stick": "Pad R3", "left_shoulder": "Pad LB / L1",
	"right_shoulder": "Pad RB / R1", "dpad_up": "D-pad Up", "dpad_down": "D-pad Down",
	"dpad_left": "D-pad Left", "dpad_right": "D-pad Right"}


## Returns "" when the event description is valid, otherwise a readable problem.
static func validate_event_dict(ev: Variant) -> String:
	if typeof(ev) != TYPE_DICTIONARY:
		return "input event must be an object"
	var d: Dictionary = ev
	var kinds: Array = []
	for k: String in ["key", "mouse_button", "joy_button", "joy_axis"]:
		if d.has(k):
			kinds.append(k)
	if kinds.size() != 1:
		return "input event needs exactly one of key / mouse_button / joy_button / joy_axis"
	for k: Variant in d.keys():
		if not ["key", "mouse_button", "joy_button", "joy_axis", "dir"].has(k):
			return "unknown key '%s' in input event" % k
	var kind: String = kinds[0]
	if typeof(d[kind]) != TYPE_STRING:
		return "%s must be a string" % kind
	match kind:
		"key":
			if OS.find_keycode_from_string(d.key) == KEY_NONE:
				return "unknown key name '%s'" % d.key
		"mouse_button":
			if not MOUSE_BUTTONS.has(d.mouse_button):
				return "unknown mouse button '%s' (allowed: %s)" % [d.mouse_button, MOUSE_BUTTONS.keys()]
		"joy_button":
			if not JOY_BUTTONS.has(d.joy_button):
				return "unknown joypad button '%s' (allowed: %s)" % [d.joy_button, JOY_BUTTONS.keys()]
		"joy_axis":
			if not JOY_AXES.has(d.joy_axis):
				return "unknown joypad axis '%s' (allowed: %s)" % [d.joy_axis, JOY_AXES.keys()]
			var dir: Variant = d.get("dir")
			if not (typeof(dir) == TYPE_INT or typeof(dir) == TYPE_FLOAT) or (float(dir) != 1.0 and float(dir) != -1.0):
				return "joy_axis events need \"dir\": 1 or -1"
	if kind != "joy_axis" and d.has("dir"):
		return "'dir' only applies to joy_axis events"
	return ""


static func event_from_dict(d: Dictionary) -> InputEvent:
	var e: InputEvent = null
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = OS.find_keycode_from_string(d.key)
		e = k
	elif d.has("mouse_button"):
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTONS[d.mouse_button]
		e = m
	elif d.has("joy_button"):
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTONS[d.joy_button]
		e = b
	elif d.has("joy_axis"):
		var a := InputEventJoypadMotion.new()
		a.axis = JOY_AXES[d.joy_axis]
		a.axis_value = float(d.get("dir", 1))
		e = a
	if e != null:
		e.device = -1  # any device
	return e


## Converts a captured InputEvent (rebinding) to the data form. Returns {} if unsupported.
static func event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var code: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if code == KEY_NONE:
			return {}
		return {"key": OS.get_keycode_string(code)}
	if e is InputEventMouseButton:
		for name: String in MOUSE_BUTTONS:
			if MOUSE_BUTTONS[name] == e.button_index:
				return {"mouse_button": name}
	if e is InputEventJoypadButton:
		for name: String in JOY_BUTTONS:
			if JOY_BUTTONS[name] == e.button_index:
				return {"joy_button": name}
	if e is InputEventJoypadMotion and absf(e.axis_value) >= 0.5:
		for name: String in JOY_AXES:
			if JOY_AXES[name] == e.axis:
				return {"joy_axis": name, "dir": 1 if e.axis_value > 0.0 else -1}
	return {}


static func is_pad_event(d: Dictionary) -> bool:
	return d.has("joy_button") or d.has("joy_axis")


static func describe(d: Dictionary) -> String:
	if d.has("key"):
		return str(d.key)
	if d.has("mouse_button"):
		return MOUSE_LABELS.get(d.mouse_button, str(d.mouse_button))
	if d.has("joy_button"):
		return JOY_LABELS.get(d.joy_button, str(d.joy_button))
	if d.has("joy_axis"):
		var axis: String = d.joy_axis
		if axis == "trigger_left":
			return "Pad LT / L2"
		if axis == "trigger_right":
			return "Pad RT / R2"
		return "Pad %s %s" % [axis.replace("_", " "), "+" if float(d.get("dir", 1)) > 0 else "-"]
	return "?"


## Rebuilds every gameplay action in the InputMap. An override replaces the default list for
## that action entirely, so unbinding is possible.
static func apply(defaults_record: Dictionary, overrides: Dictionary) -> void:
	var actions: Dictionary = defaults_record.get("actions", {})
	var deadzones: Dictionary = defaults_record.get("deadzones", {})
	for action_name: String in ACTIONS:
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		var dz := float(deadzones.get(action_name, deadzones.get("default", 0.2)))
		InputMap.add_action(action_name, dz)
		var events: Variant = overrides.get(action_name, actions.get(action_name, []))
		if typeof(events) != TYPE_ARRAY:
			continue
		for ev: Variant in events:
			if validate_event_dict(ev) == "":
				InputMap.action_add_event(action_name, event_from_dict(ev))


## Current bindings for one action, in data form.
static func current_events(action_name: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action_name):
		return out
	for e: InputEvent in InputMap.action_get_events(action_name):
		var d := event_to_dict(e)
		if not d.is_empty():
			out.append(d)
	return out


static func describe_action(action_name: String, pad: bool) -> String:
	var parts: PackedStringArray = []
	for d: Dictionary in current_events(action_name):
		if is_pad_event(d) == pad:
			parts.append(describe(d))
	if parts.is_empty():
		return "-"
	if pad and COMBO_ACTIONS.has(action_name):
		return "%s + %s" % [describe_action("ability_modifier", true), " / ".join(parts)]
	return " / ".join(parts)


## Compact controller label for the hotbar, e.g. "LT+A" (combos include the modifier).
static func short_pad_label(action_name: String) -> String:
	var button := ""
	for d: Dictionary in current_events(action_name):
		if is_pad_event(d):
			button = short_pad(d)
			break
	if button == "":
		return ""
	if not COMBO_ACTIONS.has(action_name):
		return button
	var modifier := ""
	for d: Dictionary in current_events("ability_modifier"):
		if is_pad_event(d):
			modifier = short_pad(d)
			break
	return "%s+%s" % [modifier if modifier != "" else "?", button]


static func short_pad(d: Dictionary) -> String:
	if d.has("joy_button"):
		return SHORT_PAD.get(d.joy_button, str(d.joy_button))
	if d.has("joy_axis"):
		if SHORT_PAD.has(d.joy_axis):
			return SHORT_PAD[d.joy_axis]
		var stick := "LS" if str(d.joy_axis).begins_with("left") else "RS"
		return "%s%s%s" % [stick, str(d.joy_axis).right(1).to_upper(), "+" if float(d.get("dir", 1)) > 0 else "-"]
	return ""
