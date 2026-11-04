extends Node
## Persistent world changes (autoload "WorldState").
##
## Stores only deltas for objects that changed, keyed by stable world ids (never node paths
## or instance ids). M1 keeps them in memory for the session; the versioned save format below
## is what M3/M4 checkpoint saves will write through SaveIO.

const SCHEMA_VERSION := 1

var deltas: Dictionary = {}     ## world_id -> {"destroyed": bool, "damage_stage": int, "loot_awarded": bool}
var inventory: Dictionary = {}  ## item_id -> count (minimal prototype inventory)


func get_delta(world_id: String) -> Dictionary:
	return deltas.get(world_id, {})


func is_destroyed(world_id: String) -> bool:
	return bool(get_delta(world_id).get("destroyed", false))


func record_destroyed(world_id: String, damage_stage: int = 1) -> void:
	var d: Dictionary = deltas.get(world_id, {})
	d["destroyed"] = true
	d["damage_stage"] = damage_stage
	deltas[world_id] = d


## Returns true exactly once per world object; later calls (re-breaks, reloads) return false.
func try_award_loot(world_id: String) -> bool:
	var d: Dictionary = deltas.get(world_id, {})
	if d.get("loot_awarded", false):
		return false
	d["loot_awarded"] = true
	deltas[world_id] = d
	return true


func add_item(item_id: String, count: int) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count


## Debug/sandbox reset only: forget every world change. Normal play never calls this.
func clear() -> void:
	deltas.clear()
	inventory.clear()


func to_save_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "deltas": deltas.duplicate(true),
		"inventory": inventory.duplicate(true)}


func from_save_dict(data: Dictionary) -> bool:
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	deltas = (data.get("deltas", {}) as Dictionary).duplicate(true)
	inventory = (data.get("inventory", {}) as Dictionary).duplicate(true)
	return true
