class_name RebuildPoint
extends Interactable
## The rebuild of a burned longhouse (P36; plan M6-M9 §5.7 quest.skarn_rebuild, §5.9): "Lift the roof
## beams back" - on a longhouse of Skarn that the siege burned (its prop destroyed), while Skarn waits
## for its rebuild (`waiting_flag` truthy: world.skarn.burned) and before the house stands again
## (`rebuilt_flag`). A giant of `requires_stage` (6: the beams are a titan's lift) sets `rebuilt_flag`
## (first write wins), which shows the house rebuilt (its FlagVisibility sibling) and counts for the
## errand. Placed by the longhouse kind (tools/world/kinds/longhouse.gd) as a child of the house.

const DEFAULT_PROMPT := "Lift the roof beams back"

## The longhouse prop this rebuilds (its world id).
@export var prop_world_id := ""
## Set when the house stands again.
@export var rebuilt_flag := ""
## The rebuild waits for this flag (the siege's burned outcome).
@export var waiting_flag := ""


func _init() -> void:
	prompt = DEFAULT_PROMPT
	requires_stage = 6


func _ready() -> void:
	if interact_id == "":
		interact_id = prop_world_id + ".rebuild"
	if not Events.flag_changed.is_connected(_on_world_changed):
		Events.flag_changed.connect(_on_world_changed)
	if not Events.object_destroyed.is_connected(_on_world_changed):
		Events.object_destroyed.connect(_on_world_changed)
	refresh()


func _exit_tree() -> void:
	if Events.flag_changed.is_connected(_on_world_changed):
		Events.flag_changed.disconnect(_on_world_changed)
	if Events.object_destroyed.is_connected(_on_world_changed):
		Events.object_destroyed.disconnect(_on_world_changed)


## Shows the prompt only while the rebuild is needed (an intact house offers nothing).
func refresh() -> void:
	enabled = is_needed()


func _on_world_changed(_tick: int, _id: String, _value: Variant) -> void:
	refresh()


## True while the house lies burned, Skarn waits for its rebuild and it is not rebuilt yet.
func is_needed() -> bool:
	if prop_world_id == "" or rebuilt_flag == "":
		return false
	if QuestConditions.truthy(WorldState.get_flag(rebuilt_flag)):
		return false
	if waiting_flag != "" and not QuestConditions.truthy(WorldState.get_flag(waiting_flag)):
		return false
	return WorldState.is_destroyed(prop_world_id)


func can_interact(_player: GiantPlayer) -> bool:
	return is_needed()


func blocked_reason(_player: GiantPlayer) -> String:
	return ""


func prompt_text(_player: GiantPlayer) -> String:
	return prompt


## Lifts the beams back: the house stands again (rebuilt_flag), a HUD line.
func interact(_player: GiantPlayer) -> void:
	if not is_needed():
		return
	if WorldState.try_set_flag(rebuilt_flag, true):
		Events.hud_message.emit("You lift the great roof beams back onto the longhouse.", "good")
	refresh()


## The rebuild without a giant (tests, the bot): the same as interact() when it is needed.
func rebuild() -> bool:
	if not is_needed():
		return false
	interact(null)
	return QuestConditions.truthy(WorldState.get_flag(rebuilt_flag))
