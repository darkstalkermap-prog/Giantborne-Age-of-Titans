class_name StoneThrone
extends Interactable
## The Stone Throne of the Moot (P36; plan M6-M9 §5.7 quest.world_main's last stage, §5.9): "Take the
## Stone Throne". It waits for the clans' champion: until Harrok the Unbowed's outcome is settled
## (`requires_flag`, boss.harrok.outcome: spared, slain or yielded_talk) it refuses with
## `blocked_message`. Taking it sets `claim_flag` (world.throne.claimed; first write wins), which ends
## the main thread's throne stage - and the main quest's completion (campaign.completed) opens the
## campaign's end screen from here: "The Giant King" with the oaths' and the champion's outcomes
## (ui/screens/end_screen.gd), once, when the flag is set during play (never when a save that holds it
## loads). Placed by the world builder's throne kind (tools/world/kinds/throne.gd).

const DEFAULT_PROMPT := "Take the Stone Throne"
const CAMPAIGN_FLAG := "campaign.completed"

@export var world_id := ""
@export var claim_flag := "world.throne.claimed"
@export var requires_flag := "boss.harrok.outcome"
@export var blocked_message := "Harrok the Unbowed holds the Moot: answer his challenge before you take the throne."
@export var claimed_message := "The Stone Throne is yours. The Old Kingdom has its Giant King."

## True once this node opened the end screen (tests).
var end_requested := false


func _init() -> void:
	prompt = DEFAULT_PROMPT


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)


func _exit_tree() -> void:
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)


func is_claimed() -> bool:
	return QuestConditions.truthy(WorldState.get_flag(claim_flag))


## True once the champion's outcome lets a giant sit the throne.
func champion_settled() -> bool:
	return requires_flag == "" or QuestConditions.truthy(WorldState.get_flag(requires_flag))


func can_interact(_player: GiantPlayer) -> bool:
	return champion_settled() and not is_claimed()


func blocked_reason(_player: GiantPlayer) -> String:
	return claimed_message if is_claimed() else blocked_message


## Takes the throne (the giant's E, the bot, tests): the claim flag and a HUD line. False when the
## champion is not settled or it was taken before.
func claim() -> bool:
	if not can_interact(null):
		return false
	if WorldState.try_set_flag(claim_flag, true):
		Events.hud_message.emit("You take the Stone Throne. The clans of the Stonehold raise their voices.", "good")
		return true
	return false


func interact(_player: GiantPlayer) -> void:
	claim()


## The main quest's completion during play: the campaign's end screen.
func _on_flag_changed(_tick: int, flag_id: String, value: Variant) -> void:
	if flag_id != CAMPAIGN_FLAG or not QuestConditions.truthy(value) or end_requested:
		return
	end_requested = true
	Events.ui_screen_requested.emit("end", campaign_summary())


## The end screen's arguments for the campaign: Quests.end_summary() (time, deaths, level, stage) with
## "campaign" true and the outcomes (EndScreen.campaign_lines reads the rest live).
static func campaign_summary() -> Dictionary:
	var out: Dictionary = Quests.end_summary()
	out["campaign"] = true
	out["outcome"] = ""
	return out
