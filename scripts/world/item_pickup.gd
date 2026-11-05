class_name ItemPickup
extends Interactable
## Something to pick up with E (plan §2.7.4, §3.8 design 3): the quarry's supply cache, the crown of
## the First King. interact() grants `count` of `item_id` (WorldState.add_item; Events.loot_awarded
## so the HUD shows "+1 ..."), sets `set_flag` when there is one (first write wins), records the
## delta `taken` for its world id and hides itself; a reload of a taken pickup starts hidden and
## disabled. Grants are once per world id.
##
## The static is_taken() / record_taken() helpers serve the other one-time world interactables
## (WeaponRack) too.
##
## Children: Visual (hidden once taken).

const TAKEN_KEY := "taken"

## Placed, persistent id, e.g. "valley.quarry.cache".
@export var world_id := ""
@export var item_id := "item.iron_ingot"
@export var count := 1
## "" or a flag id set (try_set_flag, true) when taken, e.g. "slice.crown_claimed".
@export var set_flag := ""

var taken := false


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id
	if world_id == "":
		push_error("ItemPickup %s has no world_id" % get_path())
	if GameData.get_record(item_id).is_empty():
		push_error("ItemPickup %s: unknown item '%s'" % [world_id, item_id])
	if is_taken(world_id):
		_hide()


static func is_taken(id: String) -> bool:
	return bool(WorldState.get_delta(id).get(TAKEN_KEY, false))


static func record_taken(id: String) -> void:
	var d: Dictionary = WorldState.deltas.get(id, {})
	d[TAKEN_KEY] = true
	WorldState.deltas[id] = d


func item_name() -> String:
	return str(GameData.get_record(item_id).get("display_name", item_id))


func prompt_text(_player: GiantPlayer) -> String:
	return "Take the %s%s" % [item_name(), " (x%d)" % count if count > 1 else ""]


func can_interact(_player: GiantPlayer) -> bool:
	return not taken


func interact(player: GiantPlayer) -> void:
	if taken:
		return
	taken = true
	record_taken(world_id)
	WorldState.add_item(item_id, count, "pickup")
	var recipient := player.entity.entity_id if player != null else "player"
	Events.loot_awarded.emit(Sim.tick, world_id, item_id, count, recipient)
	if set_flag != "":
		WorldState.try_set_flag(set_flag, true)
	_hide()


func _hide() -> void:
	taken = true
	enabled = false
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = false
