class_name Inscription
extends NpcTalker
## An inscribed stone of the world (P25; plan M6-M9 §2.7, decision 33): an Old Kings' cairn, read
## with E (pad X). It is an NpcTalker whose speaker is the stone itself: interact() opens its
## dialogue (dialogue.cairn_<name>), whose first choice gives one attribute point once - the
## choice's once_flag reward.cairn.<name> guards it, so reading it again (or after a reload, or
## after its streamed chunk came back) gives nothing more. Group "inscriptions" (plan §2.2).
##
## read_flag() is that once-flag (from the dialogue's choices), is_read() whether it is set: the
## map, the journal and the world bot ask (P27, P38).

const GROUP := "inscriptions"


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _init() -> void:
	super()
	prompt = "Read the cairn"


## The flag the dialogue sets when the cairn's gift is taken ("" when its dialogue has none).
func read_flag() -> String:
	return gift_flag(dialogue_record())


## True once the gift was taken.
func is_read() -> bool:
	var f := read_flag()
	return f != "" and QuestConditions.truthy(WorldState.get_flag(f))


## The once_flag of the first choice that gives attribute points in a dialogue record.
static func gift_flag(dialogue: Dictionary) -> String:
	for node: Variant in dialogue.get("nodes", []):
		if typeof(node) != TYPE_DICTIONARY:
			continue
		for choice: Variant in (node as Dictionary).get("choices", []):
			if typeof(choice) != TYPE_DICTIONARY:
				continue
			var fx: Variant = (choice as Dictionary).get("effects", {})
			if typeof(fx) == TYPE_DICTIONARY and int((fx as Dictionary).get("attribute_points", 0)) > 0:
				return str((fx as Dictionary).get("once_flag", ""))
	return ""
