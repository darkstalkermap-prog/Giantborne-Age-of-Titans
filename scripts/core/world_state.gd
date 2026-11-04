extends Node
## Persistent world changes (autoload "WorldState").
##
## Stores only deltas for objects that changed, keyed by stable world ids or spawned entity ids
## (never node paths or instance ids), the minimal inventory, and the world flags (quest
## stages, once-flags, faction state). GameSession snapshots it into checkpoint saves through
## to_save_dict(); from_save_dict() reads both save versions.
##
## Flag writes: try_set_flag (first write wins) for dialogue set_flags, prop on_destroyed_flags
## and reward once-flags; set_flag (overwrite) only for quest.*.stage / quest.*.done (quest
## runner), encounter.*.cleared (director) and faction.village.warned (FactionState).
## Both emit Events.flag_changed only when the stored value actually changed. Bulk loads
## (from_save_dict, clear) emit nothing.

## Version 2 added "flags". Version 1 documents load with empty flags.
const SCHEMA_VERSION := 2

## world_id / entity_id -> {"destroyed": bool, "damage_stage": int, "health": float,
## "loot_awarded": bool, "killed": bool, "opened": bool, ...}
var deltas: Dictionary = {}
var inventory: Dictionary = {}  ## item_id -> count (minimal prototype inventory)
var flags: Dictionary = {}      ## flag id -> bool / number / string


func get_delta(world_id: String) -> Dictionary:
	return deltas.get(world_id, {})


func is_destroyed(world_id: String) -> bool:
	return bool(get_delta(world_id).get("destroyed", false))


func record_destroyed(world_id: String, damage_stage: int = 1) -> void:
	var d: Dictionary = deltas.get(world_id, {})
	d["destroyed"] = true
	d["damage_stage"] = damage_stage
	deltas[world_id] = d


## Every persistent prop, on each damaging hit: its current damage stage and health, so a
## cracked gate reloads cracked.
func record_damage(world_id: String, damage_stage: int, health: float) -> void:
	var d: Dictionary = deltas.get(world_id, {})
	d["damage_stage"] = damage_stage
	d["health"] = health
	deltas[world_id] = d


## A persistent spawned actor (director kill tracking) died for good.
func record_killed(entity_id: String) -> void:
	var d: Dictionary = deltas.get(entity_id, {})
	d["killed"] = true
	deltas[entity_id] = d


func is_killed(entity_id: String) -> bool:
	return bool(get_delta(entity_id).get("killed", false))


## A gate or barricade was opened without being destroyed (BreakableProp.force_open, P08).
func record_opened(world_id: String) -> void:
	var d: Dictionary = deltas.get(world_id, {})
	d["opened"] = true
	deltas[world_id] = d


func is_opened(world_id: String) -> bool:
	return bool(get_delta(world_id).get("opened", false))


## Returns true exactly once per world object; later calls (re-breaks, reloads) return false.
func try_award_loot(world_id: String) -> bool:
	var d: Dictionary = deltas.get(world_id, {})
	if d.get("loot_awarded", false):
		return false
	d["loot_awarded"] = true
	deltas[world_id] = d
	return true


# --------------------------------------------------------------------------- inventory

## Adds count (> 0) of an item and emits item_added.
func add_item(item_id: String, count: int, source: String = "") -> void:
	if count <= 0:
		return
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	Events.item_added.emit(Sim.tick, item_id, count, source)


## All-or-nothing: removes count (> 0) of an item if that many are held, emits item_removed and
## returns true; otherwise changes nothing and returns false.
func remove_item(item_id: String, count: int, reason: String = "") -> bool:
	if count <= 0:
		return false
	var held := int(inventory.get(item_id, 0))
	if held < count:
		return false
	if held == count:
		inventory.erase(item_id)
	else:
		inventory[item_id] = held - count
	Events.item_removed.emit(Sim.tick, item_id, count, reason)
	return true


func count_of(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


# --------------------------------------------------------------------------- flags

func get_flag(id: String, default: Variant = null) -> Variant:
	return flags.get(id, default)


func has_flag(id: String) -> bool:
	return flags.has(id)


## Overwrites a flag. Emits flag_changed only when the value changed.
func set_flag(id: String, value: Variant) -> void:
	if id == "":
		push_error("WorldState.set_flag: empty flag id")
		return
	if flags.has(id) and _same_value(flags[id], value):
		return
	flags[id] = value
	Events.flag_changed.emit(Sim.tick, id, value)


## First write wins: sets the flag and returns true only if it did not exist yet. Rewards are
## granted only when this returns true, so they can never be farmed.
func try_set_flag(id: String, value: Variant = true) -> bool:
	if id == "":
		push_error("WorldState.try_set_flag: empty flag id")
		return false
	if flags.has(id):
		return false
	flags[id] = value
	Events.flag_changed.emit(Sim.tick, id, value)
	return true


static func _same_value(a: Variant, b: Variant) -> bool:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


# --------------------------------------------------------------------------- persistence

## Forgets every world change: deltas, inventory and flags (sandbox reset, New Game, tests).
func clear() -> void:
	deltas.clear()
	inventory.clear()
	flags.clear()


func to_save_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "deltas": deltas.duplicate(true),
		"inventory": inventory.duplicate(true), "flags": flags.duplicate(true)}


## Accepts version 1 (no flags: migrated with empty flags) and version 2. Returns false and
## changes nothing for any other version or a malformed document. Item counts and damage
## stages come back as ints (JSON numbers load as floats).
func from_save_dict(data: Dictionary) -> bool:
	var version := int(data.get("schema_version", 0)) if SchemaUtil.is_number(data.get("schema_version")) else 0
	if version != 1 and version != SCHEMA_VERSION:
		return false
	for key: String in ["deltas", "inventory", "flags"]:
		if data.has(key) and typeof(data[key]) != TYPE_DICTIONARY:
			return false
	var new_deltas := {}
	var raw_deltas: Dictionary = data.get("deltas", {})
	for id: Variant in raw_deltas:
		if typeof(raw_deltas[id]) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = (raw_deltas[id] as Dictionary).duplicate(true)
		if SchemaUtil.is_number(d.get("damage_stage")):
			d["damage_stage"] = int(d.damage_stage)
		if SchemaUtil.is_number(d.get("health")):
			d["health"] = float(d.health)
		new_deltas[str(id)] = d
	var new_inventory := {}
	var raw_inventory: Dictionary = data.get("inventory", {})
	for item: Variant in raw_inventory:
		if SchemaUtil.is_number(raw_inventory[item]) and int(raw_inventory[item]) > 0:
			new_inventory[str(item)] = int(raw_inventory[item])
	var new_flags := {}
	if version >= 2:
		new_flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	deltas = new_deltas
	inventory = new_inventory
	flags = new_flags
	return true
