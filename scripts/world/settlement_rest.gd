class_name SettlementRest
extends Interactable
## C4: a settlement's fire the giant may rest by once its tier gives it (`requires_flag`: Last Hearth's hall roofed) -
## health, stamina and essence restored, his debuffs gone, and a checkpoint here (the settlement keeps his place).
## Placed by the world builder's settlement_rest kind.

@export var world_id := ""
@export var requires_flag := ""
@export var display_name := "fire"
## The checkpoint a rest here makes the respawn (the settlement's waystone; "" keeps the current one).
@export var respawn_checkpoint := ""


func _init() -> void:
	priority = 44
	radius_m = 12.0
	prompt = "Rest by the fire"


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id


func is_open() -> bool:
	return requires_flag == "" or QuestConditions.truthy(WorldState.get_flag(requires_flag))


func prompt_text(_player: GiantPlayer) -> String:
	return "Rest by the %s" % display_name


func can_interact(_player: GiantPlayer) -> bool:
	return is_open() and Armour.change_blocked() == ""


func blocked_reason(_player: GiantPlayer) -> String:
	if not is_open():
		return "The %s is cold." % display_name
	return Armour.change_blocked()


func interact(player: GiantPlayer) -> void:
	var r := SettlementWork.rest(player, world_id, respawn_checkpoint)
	Events.hud_message.emit(str(r.message), "good" if bool(r.ok) else "warn")
