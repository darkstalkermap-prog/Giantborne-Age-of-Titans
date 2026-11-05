extends TestSuite
## QuestConditions (plan §2.8.3, §3.15 design 2): every condition type, true and false, on
## hand-built contexts; hits_on counts only the blows whose action matches action_kind /
## action_id; all / any / not and malformed conditions; the ids an objective names; the flag
## names of encounter clears and dialogue outcomes.


func _ctx() -> Dictionary:
	return QuestConditions.empty_context()


func _holds(c: Variant, ctx: Dictionary) -> bool:
	return QuestConditions.holds(c, ctx)


func test_flag_conditions() -> void:
	var c := _ctx()
	c.flags = {"quest.main.stage": "grove", "test.flag.n": 3, "test.flag.off": false, "test.flag.empty": "",
		"test.flag.on": true}
	assert_true(_holds({"type": "flag", "flag": "quest.main.stage"}, c), "a non-empty string is truthy")
	assert_true(_holds({"type": "flag", "flag": "test.flag.on"}, c), "true is truthy")
	assert_false(_holds({"type": "flag", "flag": "test.flag.off"}, c), "false is not")
	assert_false(_holds({"type": "flag", "flag": "test.flag.empty"}, c), "an empty string is not")
	assert_false(_holds({"type": "flag", "flag": "test.flag.missing"}, c), "a missing flag is not")
	assert_true(_holds({"type": "flag", "flag": "quest.main.stage", "equals": "grove"}, c), "equals a string")
	assert_false(_holds({"type": "flag", "flag": "quest.main.stage", "equals": "ogre"}, c), "another string")
	assert_true(_holds({"type": "flag", "flag": "test.flag.n", "equals": 3.0}, c), "numbers compare as numbers (3 == 3.0)")
	assert_false(_holds({"type": "flag", "flag": "test.flag.n", "equals": "3"}, c), "a number is not its string")
	assert_true(_holds({"type": "flag", "flag": "test.flag.n", "at_least": 3}, c), "at_least 3")
	assert_false(_holds({"type": "flag", "flag": "test.flag.n", "at_least": 4}, c), "not at_least 4")
	assert_false(_holds({"type": "flag", "flag": "quest.main.stage", "at_least": 1}, c), "at_least needs a number")
	assert_false(_holds({"type": "flag", "flag": "test.flag.missing", "equals": false}, c), "a missing flag equals nothing")


func test_entered_is_inside_now_or_entered_since_the_load() -> void:
	var c := _ctx()
	var cond := {"type": "entered", "area": "valley.area.village"}
	assert_false(_holds(cond, c), "never there")
	c.inside = {"valley.area.village": true}
	assert_true(_holds(cond, c), "inside now")
	c.inside = {}
	c.entered = {"valley.area.village": true}
	assert_true(_holds(cond, c), "entered earlier (since the level loaded)")
	assert_false(_holds({"type": "entered", "area": "valley.area.bridge"}, c), "another area")


func test_killed_destroyed_and_encounter_cleared() -> void:
	var c := _ctx()
	var both := {"type": "killed", "targets": ["valley.forest.ogre", "valley.forest.wolf_a1"]}
	assert_false(_holds(both, c), "nobody dead")
	c.deltas = {"valley.forest.ogre": {"killed": true}}
	assert_false(_holds(both, c), "one of two")
	c.died = {"valley.forest.wolf_a1": true}
	assert_true(_holds(both, c), "a saved kill and a death seen")
	assert_true(_holds({"type": "killed", "targets": ["valley.forest.ogre"]}, c), "one target")
	assert_false(_holds({"type": "killed", "targets": []}, c), "no targets never holds")
	var gate := {"type": "destroyed", "world_id": "valley.ruins.practice_gate"}
	assert_false(_holds(gate, c), "standing")
	c.deltas["valley.ruins.practice_gate"] = {"destroyed": false, "damage_stage": 1}
	assert_false(_holds(gate, c), "cracked is not destroyed")
	c.deltas["valley.ruins.practice_gate"] = {"destroyed": true}
	assert_true(_holds(gate, c), "destroyed (saved)")
	c.deltas.erase("valley.ruins.practice_gate")
	c.destroyed = {"valley.ruins.practice_gate": true}
	assert_true(_holds(gate, c), "destroyed (seen)")
	var cleared := {"type": "encounter_cleared", "encounter": "encounter.forest_wolves_a"}
	assert_false(_holds(cleared, c), "not cleared")
	c.flags = {EncounterDirector.cleared_flag("encounter.forest_wolves_a"): true}
	assert_true(_holds(cleared, c), "the director's cleared flag")


func test_items_stage_level_weapon_and_dialogue_outcome() -> void:
	var c := _ctx()
	c.inventory = {"item.iron_ingot": 2}
	assert_true(_holds({"type": "has_item", "item": "item.iron_ingot", "count": 2}, c), "two held")
	assert_false(_holds({"type": "has_item", "item": "item.iron_ingot", "count": 3}, c), "not three")
	assert_false(_holds({"type": "has_item", "item": "item.supply_cache", "count": 1}, c), "not held")
	c.stage = 2
	assert_true(_holds({"type": "stage_at_least", "stage": 2}, c), "stage 2")
	assert_false(_holds({"type": "stage_at_least", "stage": 3}, c), "not stage 3")
	c.level = 4
	assert_true(_holds({"type": "level_at_least", "level": 4}, c), "level 4")
	assert_false(_holds({"type": "level_at_least", "level": 5}, c), "not level 5")
	c.weapon = "weapon.club"
	assert_true(_holds({"type": "weapon_equipped", "weapon": "weapon.club"}, c), "the club")
	assert_false(_holds({"type": "weapon_equipped", "weapon": "weapon.tree_oak"}, c), "not the tree")
	var outcome := {"type": "dialogue_outcome", "dialogue": "dialogue.elder", "outcome": "intimidate"}
	assert_false(_holds(outcome, c), "not chosen")
	c.flags = {"dialogue.elder.outcome.intimidate": true}
	assert_true(_holds(outcome, c), "chosen (its flag)")
	assert_false(_holds({"type": "dialogue_outcome", "dialogue": "dialogue.elder", "outcome": "help_cache"}, c),
		"another outcome")


func test_hits_on_counts_only_matching_actions() -> void:
	var c := _ctx()
	c.hits = {"valley.hollow.dummy_1": {"ability.light_1": 2, "ability.heavy_1": 1, "ability.heavy_footfall": 1},
		"valley.hollow.dummy_2": {"ability.light_2": 1}, "test.other": {"ability.light_1": 9}}
	c.hit_kinds = {"ability.light_1": "light", "ability.light_2": "light", "ability.heavy_1": "heavy",
		"ability.heavy_footfall": "ability"}
	var dummies := ["valley.hollow.dummy_1", "valley.hollow.dummy_2"]
	var lights := {"type": "hits_on", "targets": dummies, "count": 3, "action_kind": "light"}
	assert_true(_holds(lights, c), "2 + 1 lights on the dummies")
	lights.count = 4
	assert_false(_holds(lights, c), "not 4: lights on another target do not count")
	assert_true(_holds({"type": "hits_on", "targets": dummies, "count": 1, "action_kind": "heavy"}, c), "one heavy")
	assert_false(_holds({"type": "hits_on", "targets": dummies, "count": 2, "action_kind": "heavy"}, c), "not two")
	assert_true(_holds({"type": "hits_on", "targets": dummies, "count": 1, "action_id": "ability.heavy_footfall"}, c),
		"Footfall by id")
	assert_false(_holds({"type": "hits_on", "targets": ["valley.hollow.dummy_2"], "count": 1,
		"action_id": "ability.heavy_footfall"}, c), "no Footfall on dummy 2")
	assert_false(_holds({"type": "hits_on", "targets": dummies, "count": 1, "action_kind": "light",
		"action_id": "ability.heavy_1"}, c), "both filters must match")
	assert_eq(QuestConditions.hit_count(c, dummies, "", ""), 5, "every blow on the dummies without a filter")
	assert_eq(QuestConditions.hit_count(c, dummies, "light", ""), 3, "the lights")
	assert_eq(QuestConditions.hit_count(c, dummies, "ability", ""), 1, "the Footfall is an ability")


func test_all_any_not_and_malformed_conditions() -> void:
	var c := _ctx()
	c.flags = {"test.flag.a": true}
	var a := {"type": "flag", "flag": "test.flag.a"}
	var b := {"type": "flag", "flag": "test.flag.b"}
	assert_true(_holds({"type": "all", "of": [a, a]}, c), "all of true")
	assert_false(_holds({"type": "all", "of": [a, b]}, c), "all with a false")
	assert_true(_holds({"type": "all", "of": []}, c), "all of nothing")
	assert_true(_holds({"type": "any", "of": [b, a]}, c), "any with a true")
	assert_false(_holds({"type": "any", "of": [b]}, c), "any of false")
	assert_false(_holds({"type": "any", "of": []}, c), "any of nothing")
	assert_true(_holds({"type": "not", "of": b}, c), "not false")
	assert_false(_holds({"type": "not", "of": a}, c), "not true")
	assert_true(_holds({"type": "all", "of": [a, {"type": "not", "of": {"type": "any", "of": [b]}}]}, c), "nested")
	assert_true(QuestConditions.all_hold([], c), "an empty list holds")
	assert_true(QuestConditions.all_hold(null, c), "no list holds")
	assert_false(QuestConditions.all_hold([a, b], c), "a list with a false")
	assert_false(_holds("flag", c), "a string is no condition")
	assert_false(_holds({"type": "teleport"}, c), "an unknown type never holds")
	assert_false(_holds({"type": "not", "of": [a]}, c), "not of a list is malformed")
	assert_false(_holds({"type": "all", "of": a}, c), "all of a dict is malformed")


func test_targets_and_flag_names() -> void:
	var cond := {"type": "all", "of": [
		{"type": "killed", "targets": ["valley.forest.ogre", "valley.forest.wolf_a1"]},
		{"type": "entered", "area": "valley.area.grove"},
		{"type": "not", "of": {"type": "destroyed", "world_id": "valley.grove.cairn"}},
		{"type": "any", "of": [{"type": "hits_on", "targets": ["valley.forest.ogre", "valley.hollow.dummy_1"], "count": 1},
			{"type": "encounter_cleared", "encounter": "encounter.forest_wolves_a"}]},
		{"type": "flag", "flag": "test.flag.a"}]}
	assert_eq(QuestConditions.targets_of(cond), PackedStringArray(["valley.forest.ogre", "valley.forest.wolf_a1",
		"valley.area.grove", "valley.grove.cairn", "valley.hollow.dummy_1", "encounter.forest_wolves_a"]),
		"every id named, in order, once")
	assert_eq(QuestConditions.targets_of({"type": "stage_at_least", "stage": 2}), PackedStringArray(), "none")
	assert_eq(QuestConditions.outcome_flag("dialogue.elder", "intimidate"), "dialogue.elder.outcome.intimidate",
		"a dialogue outcome's flag")
	assert_eq(QuestConditions.encounter_flag("encounter.forest_wolves_a"),
		EncounterDirector.cleared_flag("encounter.forest_wolves_a"), "the director's cleared flag")
	assert_true(QuestConditions.truthy(1) and not QuestConditions.truthy(0.0) and QuestConditions.truthy("x")
		and not QuestConditions.truthy(null), "truthiness")
	assert_eq(QuestConditions.empty_context().keys(), QuestConditions.KEYS, "the context keys")
