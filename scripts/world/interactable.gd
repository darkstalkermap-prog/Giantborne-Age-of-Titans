class_name Interactable
extends Node3D
## Something the giant can use with the interact key (E / pad X): shrines, weapon racks,
## pickups, the forge, talkers (plan §2.7.4). PlayerInteract finds the best one around the
## player every few ticks; the HUD shows "[E] <prompt>" for it; pressing E calls interact(),
## or shows blocked_reason() as a warning when can_interact() is false.
##
## Subclasses override the four methods below; the defaults make a plain, always-usable node.
## Group "interactables": joined in _notification (which runs for every class of the
## hierarchy), so subclasses need no super() calls in _init or _ready.

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
## P26 (plan M6-M9 §2.9): the growth stage the giant needs to use this (0 = any) - a ledge only a
## stage-6 giant reaches. Below it PlayerInteract shows stage_reason() and emits size_gate_blocked
## instead of calling interact().
@export var requires_stage := 0
## The refusal below requires_stage ("" = "Out of reach. Grow to stage N.").
@export var stage_message := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group("interactables")


func can_interact(_player: GiantPlayer) -> bool:
	return true


## P26: "" when a giant of `stage` may use this, else its refusal (requires_stage).
func stage_reason(stage: int) -> String:
	if requires_stage <= 0 or stage >= requires_stage:
		return ""
	return stage_message if stage_message != "" else "Out of reach. Grow to stage %d." % requires_stage


## Shown as a warning when E is pressed while can_interact() is false.
func blocked_reason(_player: GiantPlayer) -> String:
	return ""


func prompt_text(_player: GiantPlayer) -> String:
	return prompt


func interact(_player: GiantPlayer) -> void:
	pass
