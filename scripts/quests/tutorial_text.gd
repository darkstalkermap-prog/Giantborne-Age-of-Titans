class_name TutorialText
extends RefCounted
## The {placeholder} words of tutorial prompt texts (plan §2.8.3, §4.5) and their resolution to
## key or button names for the last input device: "Strike with {light_attack}" reads
## "Strike with Mouse Left" on a keyboard and "Strike with Pad RB / R1" on a pad. Shared by the
## tutorial_prompt schema (unknown words are a warning), the tutorial director and the HUD
## widget (ui/hud/tutorial_prompt.gd). Pure; reads the live bindings through InputBindings.

## Placeholder word -> the input action it names. "heavy_attack" is special on a keyboard: the
## heavy modifier plus the light attack (Shift + Mouse Left), unless attack_heavy has a key.
## Every InputBindings action name is a placeholder too ({attack_light}, {ability_5}, ...).
const PLACEHOLDERS := {
	"light_attack": "attack_light",
	"heavy_attack": "attack_heavy",
	"block": "block",
	"dodge": "dodge",
	"jump": "jump",
	"interact": "interact",
	"sprint": "sprint",
	"lock_target": "lock_target",
	"camera_toggle": "camera_toggle",
	"inventory": "inventory",
	"slot_1": "ability_1", "slot_2": "ability_2", "slot_3": "ability_3", "slot_4": "ability_4",
	"slot_5": "ability_5", "slot_6": "ability_6", "slot_7": "ability_7", "slot_8": "ability_8",
	"ultimate": "ultimate",
	"pause": "pause",
	"help": "help",
}

const _WORD := "\\{([a-z0-9_]+)\\}"


## The placeholder words used in `text`, in order (duplicates kept once).
static func placeholders_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in RegEx.create_from_string(_WORD).search_all(text):
		var w := m.get_string(1)
		if not out.has(w):
			out.append(w)
	return out


## True when `word` names an input action (an alias of PLACEHOLDERS or an action name).
static func is_known(word: String) -> bool:
	return PLACEHOLDERS.has(word) or InputBindings.ACTIONS.has(word)


## The input action a placeholder word names ("" when it names none).
static func action_for(word: String) -> String:
	if PLACEHOLDERS.has(word):
		return str(PLACEHOLDERS[word])
	return word if InputBindings.ACTIONS.has(word) else ""


## What a placeholder reads as for the device (pad or keyboard and mouse); the word itself in
## braces when it names no action.
static func label_for(word: String, pad: bool) -> String:
	var action := action_for(word)
	if action == "":
		return "{%s}" % word
	if action == "attack_heavy" and not pad:
		var direct := InputBindings.describe_action("attack_heavy", false)
		if direct != "-":
			return direct
		return "%s + %s" % [InputBindings.describe_action("heavy_modifier", false),
			InputBindings.describe_action("attack_light", false)]
	return InputBindings.describe_action(action, pad)


## `text` with every known placeholder replaced by its key or button name for the device.
static func resolve(text: String, pad: bool) -> String:
	var out := text
	for w in placeholders_in(text):
		if is_known(w):
			out = out.replace("{%s}" % w, label_for(w, pad))
	return out
