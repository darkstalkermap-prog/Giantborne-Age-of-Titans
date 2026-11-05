extends TestSuite
## P01 WorldState v2: flags (first-write-wins and overwrite, change-only events), killed /
## opened / damage deltas, item events, v1 -> v2 migration and the save round trip.

var flag_events: Array = []
var item_events: Array = []


func before_each() -> void:
	WorldState.clear()
	flag_events = []
	item_events = []
	Events.flag_changed.connect(_on_flag)
	Events.item_added.connect(_on_item_added)
	Events.item_removed.connect(_on_item_removed)


func after_each() -> void:
	Events.flag_changed.disconnect(_on_flag)
	Events.item_added.disconnect(_on_item_added)
	Events.item_removed.disconnect(_on_item_removed)
	WorldState.clear()


func _on_flag(_tick: int, id: String, value: Variant) -> void:
	flag_events.append([id, value])


func _on_item_added(_tick: int, item_id: String, count: int, source: String) -> void:
	item_events.append(["added", item_id, count, source])


func _on_item_removed(_tick: int, item_id: String, count: int, reason: String) -> void:
	item_events.append(["removed", item_id, count, reason])


func test_try_set_flag_is_true_only_once() -> void:
	assert_false(WorldState.has_flag("reward.main.grove"), "unset")
	assert_true(WorldState.try_set_flag("reward.main.grove"), "first write wins")
	assert_false(WorldState.try_set_flag("reward.main.grove"), "second write refused")
	assert_false(WorldState.try_set_flag("reward.main.grove", false), "whatever the value")
	assert_eq(WorldState.get_flag("reward.main.grove"), true, "the first value is kept")
	assert_eq(flag_events, [["reward.main.grove", true]], "one flag_changed event")
	assert_true(WorldState.try_set_flag("quest.village.outcome", "intimidate"), "string values")
	assert_eq(WorldState.get_flag("quest.village.outcome"), "intimidate", "stored")
	assert_eq(WorldState.get_flag("missing.flag.id", "fallback"), "fallback", "get_flag default")
	assert_eq(WorldState.get_flag("missing.flag.id"), null, "null by default")


func test_flag_changed_only_on_change() -> void:
	WorldState.set_flag("quest.main.stage", "grove")
	WorldState.set_flag("quest.main.stage", "grove")
	assert_eq(flag_events.size(), 1, "setting the same value again emits nothing")
	WorldState.set_flag("quest.main.stage", "hurl")
	assert_eq(flag_events.back(), ["quest.main.stage", "hurl"], "a new value emits")
	WorldState.set_flag("faction.village.warned", 1)
	WorldState.set_flag("faction.village.warned", 1.0)
	assert_eq(flag_events.size(), 3, "1 and 1.0 are the same number (JSON loads floats)")
	WorldState.set_flag("faction.village.warned", "1")
	assert_eq(flag_events.size(), 4, "a different type is a change")
	WorldState.set_flag("quest.main.done", false)
	assert_eq(flag_events.size(), 5, "false is a value")
	assert_true(WorldState.has_flag("quest.main.done"), "a false flag exists")
	WorldState.try_set_flag("quest.main.done", true)
	assert_eq(flag_events.size(), 5, "a refused try_set_flag emits nothing")


func test_killed_opened_and_damage_deltas() -> void:
	WorldState.record_killed("valley.forest.wolf_a1")
	assert_true(WorldState.is_killed("valley.forest.wolf_a1"), "killed")
	assert_false(WorldState.is_killed("valley.forest.wolf_a2"), "others are not")
	WorldState.record_opened("valley.ruins.practice_gate")
	assert_true(WorldState.is_opened("valley.ruins.practice_gate"), "opened")
	WorldState.record_damage("valley.ruins.practice_gate", 1, 96.0)
	var d := WorldState.get_delta("valley.ruins.practice_gate")
	assert_eq([d.damage_stage, d.health, d.opened], [1, 96.0, true], "damage stage and health join the delta")
	assert_false(WorldState.is_destroyed("valley.ruins.practice_gate"), "damaged is not destroyed")
	WorldState.record_destroyed("valley.hollow.fence_pen")
	assert_true(WorldState.try_award_loot("valley.hollow.fence_pen"), "loot once")
	assert_false(WorldState.try_award_loot("valley.hollow.fence_pen"), "never twice")


func test_record_damage_round_trips_through_save_dict() -> void:
	WorldState.record_damage("valley.ruins.practice_gate", 1, 96.0)
	WorldState.record_killed("valley.forest.wolf_a1")
	WorldState.add_item("item.wood_scrap", 2, "loot")
	WorldState.try_set_flag("reward.main.grove")
	WorldState.set_flag("quest.main.stage", "hurl")
	var doc := WorldState.to_save_dict()
	assert_eq(int(doc.schema_version), 2, "saves are version 2")
	# Through JSON, as a real save file: numbers come back as floats.
	var parsed: Variant = JSON.parse_string(JSON.stringify(doc))
	WorldState.clear()
	assert_false(WorldState.has_flag("quest.main.stage"), "clear() also clears flags")
	assert_eq(WorldState.inventory.size(), 0, "and the inventory")
	assert_true(WorldState.from_save_dict(parsed), "loads")
	var d := WorldState.get_delta("valley.ruins.practice_gate")
	assert_eq(typeof(d.damage_stage), TYPE_INT, "damage_stage comes back as an int")
	assert_eq(d.damage_stage, 1, "damage stage")
	assert_near(float(d.health), 96.0, 1e-9, "health")
	assert_true(WorldState.is_killed("valley.forest.wolf_a1"), "kills persist")
	assert_eq(WorldState.inventory, {"item.wood_scrap": 2}, "inventory counts are ints")
	assert_eq(WorldState.get_flag("quest.main.stage"), "hurl", "flags persist")
	assert_false(WorldState.try_set_flag("reward.main.grove"), "a once-flag survives the reload")
	assert_eq(WorldState.to_save_dict(), doc, "the round trip is lossless")


func test_v1_documents_migrate_to_v2() -> void:
	var v1 := {"schema_version": 1, "deltas": {"sandbox.fence_01": {"destroyed": true, "damage_stage": 1.0,
		"loot_awarded": true}}, "inventory": {"item.wood_scrap": 1.0}}
	assert_true(WorldState.from_save_dict(v1), "a version 1 document loads")
	assert_true(WorldState.is_destroyed("sandbox.fence_01"), "its deltas are kept")
	assert_eq(WorldState.inventory, {"item.wood_scrap": 1}, "and its inventory")
	assert_eq(WorldState.flags, {}, "flags start empty")
	assert_eq(int(WorldState.to_save_dict().schema_version), 2, "it saves back as version 2")
	assert_eq(flag_events.size(), 0, "a bulk load emits no flag events")


func test_unknown_or_malformed_documents_are_rejected() -> void:
	WorldState.set_flag("quest.main.stage", "grove")
	var before := WorldState.to_save_dict()
	assert_false(WorldState.from_save_dict({"schema_version": 3, "deltas": {}}), "a future version is refused")
	assert_false(WorldState.from_save_dict({"deltas": {}}), "no version is refused")
	assert_false(WorldState.from_save_dict({"schema_version": 2, "deltas": [], "flags": {}}), "deltas must be an object")
	assert_false(WorldState.from_save_dict({"schema_version": 2, "deltas": {"a.b": 3}}), "each delta must be an object")
	assert_false(WorldState.from_save_dict({"schema_version": 2, "flags": "x"}), "flags must be an object")
	assert_eq(WorldState.to_save_dict(), before, "a refused document changes nothing")


func test_items_emit_events_and_remove_is_all_or_nothing() -> void:
	WorldState.add_item("item.wood_scrap", 2, "loot")
	assert_eq(item_events, [["added", "item.wood_scrap", 2, "loot"]], "item_added")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "count")
	assert_false(WorldState.remove_item("item.wood_scrap", 3, "forge"), "cannot remove more than held")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "nothing removed")
	assert_eq(item_events.size(), 1, "and no event")
	assert_true(WorldState.remove_item("item.wood_scrap", 2, "forge"), "remove all")
	assert_eq(item_events.back(), ["removed", "item.wood_scrap", 2, "forge"], "item_removed")
	assert_false(WorldState.inventory.has("item.wood_scrap"), "an emptied stack disappears")
	assert_false(WorldState.remove_item("item.wood_scrap", 1), "nothing left")
	WorldState.add_item("item.wood_scrap", 0)
	assert_eq(item_events.size(), 2, "adding nothing emits nothing")
