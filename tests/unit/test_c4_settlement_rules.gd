extends TestSuite
## C4 (decisions C4-1..C4-3): a settlement's development, pure - SettlementRules on plain dictionaries and the shipped
## records: a tier's projects and their needs (a load hauled, a material given, a deed done), a project raised only
## when every need is met and its tier is the one being earned, the tier's flags on its last project, the flags a state
## owes the world, the tier the world's flags say, trades by tier; the records' own checks; save schema 3's
## settlements with their projects (ExpansionState: read, validated, synced from the flags, never lowered).

const LH := "settlement.last_hearth"


func _rec() -> Dictionary:
	return SettlementRules.record(LH)


func _ctx(flags := {}, inventory := {}, stage := 6) -> Dictionary:
	var c := QuestConditions.empty_context()
	c.flags = flags
	c.inventory = inventory
	c.stage = stage
	return c


func test_the_shipped_records_load_and_check() -> void:
	assert_true(GameData.errors.is_empty(), "no data errors: %s" % str(GameData.errors.slice(0, 3)))
	var rec := _rec()
	assert_false(rec.is_empty(), "Last Hearth's record")
	assert_eq(SettlementRules.max_tier(rec), 3, "Last Hearth has three tiers to earn")
	assert_eq(str(SettlementRules.for_poi("poi.last_hearth").get("id", "")), LH, "found by its POI")
	assert_eq(SettlementRules.data_errors(GameData.records, GameData.record_paths), PackedStringArray(), "the cross-record checks pass")
	var kinds := {}
	for t: Dictionary in SettlementRules.tiers(rec):
		for p: Dictionary in t.get("projects", []):
			for n: Dictionary in p.needs:
				kinds[str(n.kind)] = true
	assert_eq(kinds.keys().size(), 3, "Last Hearth asks every kind of need: hauls, gifts, deeds")
	assert_true(SettlementRules.records().size() >= 5, "Last Hearth and the four older settlements")


func test_a_bad_record_is_refused() -> void:
	var bad := {"schema_version": 1, "id": "settlement.bad", "type": "settlement", "display_name": "Bad", "poi": "poi.last_hearth",
		"level": "level.world", "flag_prefix": "bad.prefix", "loads": {},
		"tiers": [{"tier": 0, "name": "a", "text": "a", "projects": [{"id": "x", "name": "x", "text": "x", "site": "s",
			"needs": [{"kind": "haul", "load": "nothing", "count": 1}]}]}]}
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray()}
	(load("res://scripts/core/schemas/settlement_schema.gd") as GDScript).call("semantic", bad, "bad", out)
	var text := "\n".join(out.errors)
	assert_true(text.contains("must begin with 'settlement.'"), "the prefix")
	assert_true(text.contains("tier 0 is the settlement as found"), "tier 0 has no projects")
	assert_true(text.contains("not one of the record's loads"), "an unknown load")
	assert_true(text.contains("at least one tier to earn"), "a single tier")


func test_a_project_is_earned_by_its_needs_then_raised() -> void:
	var rec := _rec()
	var st := SettlementRules.blank()
	var s := SettlementRules.project_status(rec, "hall_roof", st, _ctx())
	assert_eq([int(s.met), int(s.total), bool(s.ready), bool(s.current)], [0, 3, false, true], "nothing done, its tier being earned")
	assert_eq(str(SettlementRules.can_raise(rec, st, "hall_roof", _ctx()).reason), "needs", "not raised before its needs")
	# the loads: two timbers, a third refused
	assert_eq(SettlementRules.wants_load(rec, st, "hall_roof", "timber"), 2, "it wants two timbers")
	assert_eq(SettlementRules.wants_load(rec, st, "hall_roof", "kingstone"), 0, "and no king-stone")
	assert_eq(SettlementRules.deliver(rec, st, "hall_roof", "timber"), 1, "the first timber")
	assert_eq(SettlementRules.deliver(rec, st, "hall_roof", "timber"), 2, "the second")
	assert_eq(SettlementRules.deliver(rec, st, "hall_roof", "timber"), -1, "a third is not wanted")
	# the gift: from what the giant carries, at most what is still wanted
	assert_eq(str(SettlementRules.can_give(rec, st, "hall_roof", "item.hide", {}).reason), "missing_items", "no hides")
	var g := SettlementRules.can_give(rec, st, "hall_roof", "item.hide", {"item.hide": 7})
	assert_eq([bool(g.ok), int(g.count)], [true, 3], "three of seven hides")
	SettlementRules.give(st, "hall_roof", "item.hide", 3)
	assert_eq(str(SettlementRules.can_give(rec, st, "hall_roof", "item.hide", {"item.hide": 4}).reason), "not_needed", "no more")
	# the deed: the rockfall heaved
	var deed_ctx := _ctx()
	deed_ctx.deltas = {"world.hoarfell.hearth_rockfall": {"destroyed": true}}
	assert_true(bool(SettlementRules.project_status(rec, "hall_roof", st, deed_ctx).ready), "every need met")
	assert_eq(str(SettlementRules.can_raise(rec, st, "hall_roof", _ctx({}, {}, 6)).reason), "needs", "(the deed not done)")
	var small := deed_ctx.duplicate()
	small.stage = 5
	assert_eq(str(SettlementRules.can_raise(rec, st, "hall_roof", small).reason), "stage", "a stage-5 giant cannot raise it")
	assert_true(bool(SettlementRules.can_raise(rec, st, "hall_roof", deed_ctx).ok), "a stage-6 giant can")
	var r := SettlementRules.raise(rec, st, "hall_roof")
	assert_eq(int(r.tier_up), 1, "its tier's only project: tier 1")
	assert_eq(SettlementRules.tier_of(st), 1, "the state's tier")
	assert_true(bool(r.flags.get("settlement.last_hearth.hall_roof.raised", false)), "its raised flag")
	assert_eq(r.flags.get("settlement.last_hearth.tier"), 1, "the tier's number flag")
	assert_true(bool(r.flags.get("settlement.last_hearth.tier_1", false)), "the tier's flag")
	assert_eq(str(SettlementRules.can_raise(rec, st, "hall_roof", deed_ctx).reason), "raised", "not twice")


func test_a_later_tier_waits_and_a_tier_needs_all_its_projects() -> void:
	var rec := _rec()
	var st := SettlementRules.blank()
	assert_eq(SettlementRules.wants_load(rec, st, "ring_wall", "kingstone"), 0, "tier 2's ring wants nothing at tier 0")
	assert_eq(str(SettlementRules.can_raise(rec, st, "ring_wall", _ctx()).reason), "later_tier", "nor is raised")
	assert_eq(str(SettlementRules.can_give(rec, st, "forge", "item.iron_ingot", {"item.iron_ingot": 9}).reason), "later_tier",
		"nor takes gifts")
	st.level = 1
	SettlementRules.deliver(rec, st, "ring_wall", "kingstone")
	SettlementRules.deliver(rec, st, "ring_wall", "kingstone")
	SettlementRules.deliver(rec, st, "ring_wall", "kingstone")
	var ctx := _ctx({"encounter.hoarfell_frost_trolls.cleared": true})
	assert_true(bool(SettlementRules.can_raise(rec, st, "ring_wall", ctx).ok), "the ring ready")
	var r := SettlementRules.raise(rec, st, "ring_wall")
	assert_eq(int(r.tier_up), -1, "the forge is still to raise: no tier yet")
	assert_eq(SettlementRules.tier_of(st), 1, "still tier 1")
	SettlementRules.deliver(rec, st, "forge", "kingstone")
	SettlementRules.give(st, "forge", "item.iron_ingot", 3)
	r = SettlementRules.raise(rec, st, "forge")
	assert_eq(int(r.tier_up), 2, "tier 2 with its last project")
	assert_eq(SettlementRules.current_projects(rec, st).size(), 2, "tier 3's two projects being earned")


func test_flags_owed_and_the_tier_the_flags_say() -> void:
	var rec := _rec()
	var st := SettlementRules.blank()
	st.level = 2
	SettlementRules.project_state(st, "hall_roof").raised = true
	SettlementRules.project_state(st, "beacon").hauled = {"kingstone": 1}
	var owed := SettlementRules.flags_owed(rec, st, {})
	assert_eq(owed.get("settlement.last_hearth.tier"), 2, "the tier")
	assert_true(owed.has("settlement.last_hearth.tier_1") and owed.has("settlement.last_hearth.tier_2"), "each tier's flag")
	assert_true(owed.has("settlement.last_hearth.hall_roof.raised"), "a raised project's")
	assert_true(owed.has("settlement.last_hearth.beacon.kingstone_1"), "a hauled load's stack")
	assert_eq(SettlementRules.flags_owed(rec, st, {"settlement.last_hearth.tier": 3}).has("settlement.last_hearth.tier"), false,
		"a higher number flag is never lowered")
	assert_eq(SettlementRules.tier_from_flags(rec, {}), 0, "no flags: tier 0")
	assert_eq(SettlementRules.tier_from_flags(rec, {"settlement.last_hearth.tier_2": true}), 2, "tier 2's flag")
	assert_eq(SettlementRules.tier_from_flags(rec, {"settlement.last_hearth.tier": 9}), 3, "clamped to the last tier")


func test_trades_by_tier() -> void:
	var rec := _rec()
	var st := SettlementRules.blank()
	assert_eq(SettlementRules.trades_open(rec, st).size(), 0, "nothing at tier 0")
	assert_eq(str(SettlementRules.can_trade(rec, st, "hides_for_iron", {"item.hide": 3}).reason), "tier", "not yet")
	st.level = 1
	assert_eq(SettlementRules.trades_open(rec, st).size(), 1, "one trade at tier 1")
	assert_eq(str(SettlementRules.can_trade(rec, st, "hides_for_iron", {"item.hide": 2}).reason), "missing_items", "two hides")
	assert_true(bool(SettlementRules.can_trade(rec, st, "hides_for_iron", {"item.hide": 3}).ok), "three")
	assert_eq(SettlementRules.trade_text(SettlementRules.trade(rec, "hides_for_iron")), "3 Wolf Hide for 1 Iron Ingot", "its words")


func test_save_schema_3_holds_the_projects() -> void:
	var doc := {"settlements": {"poi.last_hearth": {"level": 1, "flags": {"tier_1": true},
		"projects": {"hall_roof": {"hauled": {"timber": 2}, "given": {"item.hide": 3}, "raised": true},
			"ring_wall": {"hauled": {"kingstone": "x"}, "raised": "no"}}}}}
	assert_eq(ExpansionState.validate(doc), PackedStringArray(), "valid")
	var st: Dictionary = ExpansionState.from_doc(doc).settlements["poi.last_hearth"]
	assert_eq(st.projects.hall_roof, {"hauled": {"timber": 2}, "given": {"item.hide": 3}, "raised": true}, "kept")
	assert_eq(st.projects.ring_wall, {"hauled": {}, "given": {}, "raised": false}, "a bad project's values dropped")
	var old: Dictionary = ExpansionState.from_doc({"settlements": {"poi.millford": {"level": 0, "flags": {"quarry_reopened": true}}}})
	assert_false((old.settlements["poi.millford"] as Dictionary).has("projects"), "an older file's settlement has no projects key")
	var bad := {"settlements": {"poi.last_hearth": {"level": 0, "flags": {}, "projects": []}}}
	assert_eq(ExpansionState.validate(bad), PackedStringArray(["settlements.poi.last_hearth.projects: must be an object"]),
		"projects must be an object")
	# the world's flags raise the tier (never lower it)
	var state := ExpansionState.defaults()
	ExpansionState.sync_from_flags(state, {"settlement.last_hearth.tier_2": true})
	assert_eq(int(state.settlements["poi.last_hearth"].level), 2, "synced from the flags")
	state.settlements["poi.last_hearth"].level = 3
	ExpansionState.sync_from_flags(state, {"settlement.last_hearth.tier_2": true})
	assert_eq(int(state.settlements["poi.last_hearth"].level), 3, "never lowered")
