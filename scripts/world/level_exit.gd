class_name LevelExit
extends Interactable
## A way out of a level (P20; plan M6-M9 §2.6, decision 11): the Kings' Door behind the crown
## altar, the Citadel stair, the world's way back into the Valley. It is an interaction, not a
## trigger, so nobody leaves by accident and the giant never has to fit through a door: E
## (pad X) emits Events.travel_requested(to_level, to_checkpoint, "exit") and GameSession.travel_to
## takes a checkpoint at the destination and reloads (an exit is never refused for aware enemies,
## but is for a dead, grabbed or holding giant, or an open screen). Group "level_exits".
##
## can_interact() holds while every requires_flags flag is truthy; otherwise E shows
## locked_message. The world index lists every exit (WorldIndex.exits) with its display_name.

const GROUP := "level_exits"

## Stable id, e.g. "valley.exit.kings_door".
@export var exit_id := ""
## The level record it leads to, e.g. "level.world".
@export var to_level := ""
## The checkpoint the giant arrives at, e.g. "world.cp.kingsgate_shelf".
@export var to_checkpoint := ""
## Flags that must all be truthy before it opens (the Kings' Door: slice.completed).
@export var requires_flags := PackedStringArray()
## Shown when E is pressed while it is closed.
@export var locked_message := "The way is shut."
## The player-facing name (the map, the index): "The Kings' Door".
@export var display_name := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	if interact_id == "":
		interact_id = exit_id
	if prompt == "Interact":
		prompt = "Step through"


## True while every required flag is truthy.
func is_open() -> bool:
	for flag_id in requires_flags:
		if not QuestConditions.truthy(WorldState.get_flag(flag_id)):
			return false
	return true


func can_interact(_player: GiantPlayer) -> bool:
	return enabled and is_open()


func blocked_reason(_player: GiantPlayer) -> String:
	return locked_message if not is_open() else ""


func interact(_player: GiantPlayer) -> void:
	if not is_open():
		return
	Events.travel_requested.emit(to_level, to_checkpoint, "exit")
