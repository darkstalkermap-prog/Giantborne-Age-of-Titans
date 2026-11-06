class_name RewardArea
extends AreaTrigger
## An area that pays its XP once (P26, plan M6-M9 §5.6): the Citadel's hall gives 150 XP the first
## time the giant walks in. Everything an AreaTrigger does (area_entered / area_exited, "entered"
## quest conditions), plus: on the player's first entry ever - guarded by the world flag
## reward_flag, so a reload or a later visit never pays again - Events.xp_award_requested(reward_xp,
## "area:<area id>") and a HUD line.

## The XP of the first entry.
@export var reward_xp := 0
## The once-flag (first write wins), e.g. "reward.citadel.hall".
@export var reward_flag := ""
## The HUD line of the reward ("" = none).
@export var reward_message := ""


func _ready() -> void:
	super()
	Events.area_entered.connect(_on_area_entered)


func _on_area_entered(_tick: int, entered_id: String, _entity_id: String) -> void:
	if entered_id != area_id or reward_flag == "" or reward_xp <= 0:
		return
	if not WorldState.try_set_flag(reward_flag, true):
		return
	Events.xp_award_requested.emit(reward_xp, "area:%s" % area_id)
	if reward_message != "":
		Events.hud_message.emit(reward_message, "good")
