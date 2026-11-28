class_name StoneThrone
extends Interactable
## The Stone Throne of the Moot (P36; plan M6-M9 §5.7 quest.world_main's last stage, §5.9): "Take the
## Stone Throne". It waits for the clans' champion: until Harrok the Unbowed's outcome is settled
## (`requires_flag`, boss.harrok.outcome: spared, slain or yielded_talk) it refuses with
## `blocked_message`. Taking it sets `claim_flag` (world.throne.claimed; first write wins), which ends
## the main thread's throne stage - and the main quest's completion (campaign.completed) opens the
## campaign's end screen from here: "The Giant King" with the oaths' and the champion's outcomes
## (ui/screens/end_screen.gd), once, when the flag is set during play (never when a save that holds it
## loads). C1: that is act one's end - GameSession.act_one_finale plays the act-one finale first, begins act two
## (ActTwo) and then shows the end screen, as act one's. Placed by the world builder's throne kind (tools/world/kinds/throne.gd).
## Fix (council): once taken, the throne is where act two's first stage is heard - "Hear the oath-holders at the Stone
## Throne", whose marker (world.marker.stone_throne) stands before it. A claimed throne with act two begun opens the rim
## council (`council_dialogue`, spoken for `council_npc_id`: the same talk as the council's stone west of the throne)
## under `council_prompt`, from any side (facing_free: the giant need not face it) and ahead of the oath-stone and the
## council's stone (its priority 30 beats a talker's 40). It used to keep offering "Take the Stone Throne" and answer E
## with `claimed_message` only, so a giant at the marker never reached the council 30 m off. Between the claim and act
## two's start (the finale) it offers nothing.

const DEFAULT_PROMPT := "Take the Stone Throne"
const CAMPAIGN_FLAG := "campaign.completed"

@export var world_id := ""
@export var claim_flag := "world.throne.claimed"
@export var requires_flag := "boss.harrok.outcome"
@export var blocked_message := "Harrok the Unbowed holds the Moot: answer his challenge before you take the throne."
@export var claimed_message := "The Stone Throne is yours. The Old Kingdom has its Giant King."
## Fix (council): what the claimed throne opens once act two has begun (see the header).
@export var council_npc_id := "world.stonehold.rim_council"
@export var council_dialogue := "dialogue.rim_council"
@export var council_prompt := "Hear the oath-holders at the throne"

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


## Fix (council): true while the claimed throne opens the rim council (act two begun, its dialogue in the data).
func hears_council() -> bool:
	return is_claimed() and ActTwo.begun(WorldState.flags) and council_dialogue != "" \
		and str(GameData.get_record(council_dialogue).get("type", "")) == "dialogue"


func can_interact(_player: GiantPlayer) -> bool:
	return hears_council() or (champion_settled() and not is_claimed())


func blocked_reason(_player: GiantPlayer) -> String:
	return claimed_message if is_claimed() else blocked_message


func prompt_text(_player: GiantPlayer) -> String:
	return council_prompt if hears_council() else prompt


## Fix (council): the oath-holders gather round the throne - heard from any side.
func facing_free(_player: GiantPlayer) -> bool:
	return hears_council()


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
	if hears_council():
		Events.dialogue_requested.emit(council_npc_id, council_dialogue)
		return
	claim()


## Fix (council): a claimed throne before act two has begun (the finale playing) is no prompt: nothing to do there.
func offered(_player: GiantPlayer) -> bool:
	return not is_claimed() or hears_council()


## The main quest's completion during play: the campaign's end screen.
func _on_flag_changed(_tick: int, flag_id: String, value: Variant) -> void:
	if flag_id != CAMPAIGN_FLAG or not QuestConditions.truthy(value) or end_requested:
		return
	end_requested = true
	# C1: act one's end - its finale, act two, then the end screen once (GameSession.act_one_finale)
	GameSession.act_one_finale(campaign_summary())


## The end screen's arguments for the campaign: Quests.end_summary() (time, deaths, level, stage) with
## "campaign" true and the outcomes of the oaths, Skarn and the champion (EndScreen.campaign_summary).
static func campaign_summary() -> Dictionary:
	var out: Dictionary = Quests.end_summary()
	out.merge(EndScreen.campaign_summary(WorldState.flags), true)
	out["campaign"] = true
	out["outcome"] = ""
	return out
