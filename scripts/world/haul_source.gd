class_name HaulSource
extends Interactable
## C4 (decision C4-2): where a settlement's loads lie - the old kings' frost-killed pines in the Windfall, the drums of
## the toppled causeway pier, the reopened quarry's cut blocks. E takes one up in both arms (PlayerHaul.take_up) when a
## giant of requires_stage stands at it, carries nothing already, and some settlement's work being earned wants this
## load; otherwise it says why. The pile never runs out (it is the place's own stone or timber, drawn with the world:
## the source node draws nothing). Placed by the world builder's haul_source kind (and the Valley's layout).

@export var world_id := ""
@export var load_id := ""
## "great timber", "king-stone" (the prompt's and the HUD's words).
@export var load_name := ""


func _init() -> void:
	priority = 40
	radius_m = 16.0
	requires_stage = 6


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id


func prompt_text(_player: GiantPlayer) -> String:
	return "Take up a %s" % load_name


func can_interact(player: GiantPlayer) -> bool:
	return player != null and player.haul != null and not player.haul.is_carrying() and wanted_by() != ""


func blocked_reason(player: GiantPlayer) -> String:
	if player != null and player.haul != null and player.haul.is_carrying():
		return "Your arms are full."
	if wanted_by() == "":
		return "No settlement needs a %s now." % load_name
	return ""


## The first settlement work being earned that still wants this load ("<settlement>: <project>"; "" when none).
func wanted_by() -> String:
	for rec: Dictionary in SettlementRules.records():
		var st := SettlementWork.state(rec)
		for p: Dictionary in SettlementRules.current_projects(rec, st):
			if SettlementRules.wants_load(rec, st, str(p.id), load_id) > 0:
				return "%s: %s" % [str(rec.display_name), str(p.name)]
	return ""


func interact(player: GiantPlayer) -> void:
	if player == null or player.haul == null:
		return
	if player.haul.take_up(load_id, world_id, load_name):
		Events.hud_message.emit("You take up a %s. Carry it to %s." % [load_name, wanted_by()], "info")
		if is_inside_tree() and DisplayServer.get_name() != "headless":
			DustBurst.puff(get_parent(), player.global_position, 7.0, 16, 4.0, Color(0.7, 0.66, 0.6))
