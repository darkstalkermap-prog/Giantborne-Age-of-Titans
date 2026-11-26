class_name SettlementBoard
extends Interactable
## C4 (decision C4-4): a settlement's builder's board - the tally-post its steward keeps of what the place needs: E
## opens the settlement panel (ui/screens/settlement_screen.gd: its tier, its projects and what each needs and will
## unlock, the materials to give, its trades). Its look is scenes/world/settlement_board.tscn (a timber post-and-board
## with tally notches, hides pinned to it, a lamp), put on by the world builder's settlement_board kind.

@export var world_id := ""
@export var settlement_id := ""


func _init() -> void:
	priority = 42
	radius_m = 12.0


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id


func prompt_text(_player: GiantPlayer) -> String:
	var rec := SettlementRules.record(settlement_id)
	return "Read %s's tally-board" % str(rec.get("display_name", "the"))


func interact(player: GiantPlayer) -> void:
	Events.ui_screen_requested.emit("settlement", {"settlement": settlement_id, "player": player})
