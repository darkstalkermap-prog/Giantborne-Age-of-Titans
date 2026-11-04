class_name Interactable
extends Node3D
## Something the giant can use with the interact key (E / pad X): shrines, weapon racks,
## pickups, the forge, talkers (plan §2.7.4). PlayerInteract finds the best one around the
## player every few ticks; the HUD shows "[E] <prompt>" for it; pressing E calls interact(),
## or shows blocked_reason() as a warning when can_interact() is false.
##
## Subclasses override the four methods below; the defaults make a plain, always-usable node.
## Group "interactables" (joined at construction, so subclasses need no super() calls).

## Stable id reported in Events.interacted (quests, tutorial, bot).
@export var interact_id := ""
## Verb shown after the key, e.g. "Talk", "Rest", "Take the club".
@export var prompt := "Interact"
## Horizontal reach from the player's capsule edge, in metres.
@export var radius_m := 3.5
## Lower wins when several are in reach (then the nearest).
@export var priority := 50
## Disabled interactables are ignored entirely (no prompt, no E).
@export var enabled := true


func _init() -> void:
	add_to_group("interactables")


func can_interact(_player: GiantPlayer) -> bool:
	return true


## Shown as a warning when E is pressed while can_interact() is false.
func blocked_reason(_player: GiantPlayer) -> String:
	return ""


func prompt_text(_player: GiantPlayer) -> String:
	return prompt


func interact(_player: GiantPlayer) -> void:
	pass
