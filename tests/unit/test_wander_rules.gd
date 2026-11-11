extends TestSuite
## P37 (plan M6-M9 §2.13, §5.10, decision 27): the living world's pure rules - no world loaded:
##   * a wander table's entries by stage, flags and quest conditions (faction standings filter them),
##     the weighted pick, the kill-XP share of an entry's spawns (full for the first three, then none)
##     and the counting flag;
##   * a template's copy: ids, every spawn moved and turned about the template's centre onto the
##     ground, persisting and dropping nothing, its preferred archetype when that record exists, its
##     formations' banners and yaws, the director's copy radii; and its footprint;
##   * a world event's start rule (stage, flags, conditions, runs, cooldowns from its start or end, its
##     centre loaded, the giant within 200 m), its protect objective (targets, the loss that fails it,
##     the tracker's line), its flags and once-flag, and the event_done condition;
##   * a column's route: walked at its speed, turned along the road, projected, and a round trip that
##     began part-way along coming back to where it began;
##   * the schemas' P37 rules and GameData's template checks on hand-made records;
##   * the shipped Crownmarch table and events (the plan's entries, stages and triggers) and the most
##     kill XP the living world can ever pay there.

const TABLE := "wander.crownmarch"
const RAID := "event.millford_raid"
const COLUMN := "event.army_column"


func _validate(rec: Dictionary) -> String:
	return "\n".join(DataValidator.validate_record(rec, "test.json").errors)


func _table() -> Dictionary:
	return {"id": "wander.test", "entries": [
		{"id": "early", "weight": 3, "min_stage": 3, "max_stage": 4, "template": "encounter.a"},
		{"id": "late", "weight": 1, "min_stage": 5, "template": "encounter.b"},
		{"id": "hostile_only", "weight": 2, "template": "encounter.c",
			"requires_flags": ["faction.test.hostile"], "forbids_flags": ["faction.test.reconciled"]},
		{"id": "no_parley", "weight": 2, "template": "encounter.d",
			"conditions": [{"type": "not", "of": {"type": "flag", "flag": "oath.crown.outcome", "equals": "parley"}}]}]}


func _ids(entries: Array) -> Array:
	return entries.map(func(e: Dictionary) -> String: return str(e.id))


func _ctx(flags: Dictionary) -> Dictionary:
	var ctx := QuestConditions.empty_context()
	ctx["flags"] = flags
	return ctx


# --------------------------------------------------------------------------- wander tables

func test_entries_by_stage_flags_conditions_and_the_weighted_pick() -> void:
	var t := _table()
	assert_eq(_ids(WanderDirector.eligible_entries(t, 3, _ctx({}))), ["early", "no_parley"], "stage 3: the early entry and the unconditional one")
	assert_eq(_ids(WanderDirector.eligible_entries(t, 5, _ctx({}))), ["late", "no_parley"], "stage 5: the late one")
	assert_eq(_ids(WanderDirector.eligible_entries(t, 5, _ctx({"faction.test.hostile": true}))), ["late", "hostile_only", "no_parley"],
		"a hostile faction adds its entry")
	assert_eq(_ids(WanderDirector.eligible_entries(t, 5, _ctx({"faction.test.hostile": true, "faction.test.reconciled": true}))),
		["late", "no_parley"], "reconciled, it goes again")
	assert_eq(_ids(WanderDirector.eligible_entries(t, 5, _ctx({"oath.crown.outcome": "parley"}))), ["late"],
		"a condition that fails removes its entry (the crown's parley)")
	assert_eq(_ids(WanderDirector.eligible_entries(t, 5, _ctx({"oath.crown.outcome": "breach"}))), ["late", "no_parley"],
		"another outcome keeps it")
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var counts := {}
	var entries := WanderDirector.eligible_entries(t, 3, _ctx({}))   # early 3, no_parley 2
	for i in 1000:
		var e := WanderDirector.pick_entry(entries, rng)
		counts[e.id] = int(counts.get(e.id, 0)) + 1
	assert_true(absi(int(counts.get("early", 0)) - 600) < 60, "picked by weight: early ~3/5 (%s)" % counts)
	assert_true(absi(int(counts.get("no_parley", 0)) - 400) < 60, "no_parley ~2/5 (%s)" % counts)
	assert_eq(WanderDirector.pick_entry([], rng), {}, "nothing to pick: {}")
	assert_eq(WanderDirector.pick_entry([{"id": "zero", "weight": 0}], rng), {}, "no weight: {}")


func test_kill_xp_pays_for_the_first_three_spawns_of_an_entry() -> void:
	for n in [1, 2, 3]:
		assert_eq(WanderDirector.xp_scale_for(n, 3), 1.0, "spawn %d pays its kill XP" % n)
	for n in [4, 5, 40]:
		assert_eq(WanderDirector.xp_scale_for(n, 3), 0.0, "spawn %d pays none" % n)
	assert_eq(WanderDirector.xp_scale_for(1, 0), 0.0, "xp_full_spawns 0: never")
	assert_eq(WanderDirector.spawns_flag(TABLE, "toll_patrol"), "wander.crownmarch.toll_patrol.spawns", "the counting flag")
	var e := WorldEvent.make({"id": "event.t", "xp_full_runs": 2})
	assert_eq([e.xp_scale_for_run(1), e.xp_scale_for_run(2), e.xp_scale_for_run(3)], [1.0, 1.0, 0.0], "an event's runs: its first two")
	assert_eq(WorldEvent.make({"id": "event.t"}).xp_scale_for_run(3), 1.0, "three by default")
	assert_eq(WorldEvent.make({"id": "event.t"}).xp_scale_for_run(4), 0.0, "and not the fourth")


# --------------------------------------------------------------------------- copies of templates

func _template() -> Dictionary:
	return {"id": "encounter.tpl_test", "type": "encounter", "template": true, "level": "level.world",
		"center_m": [100.0, 5.0, 100.0], "activate_radius_m": 120, "deactivate_radius_m": 200, "leash_radius_m": 50,
		"requires_flags": ["x.y"], "forbids_flags": ["y.z"],
		"formations": [{"id": "pikes", "banner": "test.banner", "yaw_deg": 0}],
		"spawns": [
			{"entity_id": "test.a", "definition": "enemy.soldier", "position_m": [102.0, 5.0, 100.0], "yaw_deg": 0,
				"persist_death": true, "loot_table": "loot.raider", "targets": {"factions": ["faction.millford"]}},
			{"entity_id": "test.b", "definition": "enemy.wolf", "position_m": [100.0, 5.0, 97.0], "yaw_deg": 45,
				"prefer": "enemy.archer"},
			{"entity_id": "test.c", "definition": "enemy.wolf", "position_m": [100.0, 5.0, 100.0], "prefer": "enemy.no_such_wolf"},
			{"entity_id": "test.banner", "definition": "enemy.bannerman", "position_m": [100.0, 5.0, 103.0],
				"formation": "pikes", "slot": -1}]}


func test_a_copy_moves_and_turns_every_spawn_and_keeps_nothing() -> void:
	var ground := func(p: Vector3) -> float: return 0.5 * p.x
	var rec := EncounterDirector.p37_copy_record(_template(), 7, Vector3(10.0, 0.0, 10.0), PI / 2.0, ground)
	assert_eq(rec.id, "encounter.tpl_test.7", "the copy's id")
	assert_eq(rec.template, false, "a copy is no template")
	assert_eq(rec.requires_flags, [], "its flags are the director's to choose")
	assert_eq(rec.forbids_flags, [], "both lists")
	assert_eq(rec.center_m, [10.0, 0.0, 10.0], "its centre at the anchor")
	assert_eq(float(rec.activate_radius_m), EncounterDirector.P37_ACTIVATE_M, "the copy radii (280 m)")
	assert_eq(float(rec.deactivate_radius_m), EncounterDirector.P37_DEACTIVATE_M, "and 340 m")
	var a: Dictionary = rec.spawns[0]
	assert_eq(a.entity_id, "test.a.7", "spawn ids take the suffix")
	assert_near(float(a.position_m[0]), 10.0, 1e-4, "2 m east of the centre, turned 90 degrees: x")
	assert_near(float(a.position_m[2]), 8.0, 1e-4, "z (east turns to north)")
	assert_near(float(a.position_m[1]), 5.0, 1e-4, "on the ground's height there")
	assert_near(float(a.yaw_deg), 90.0, 1e-4, "its yaw turned with the copy")
	assert_eq(a.persist_death, false, "a copy's member persists nothing")
	assert_eq(a.loot_table, "", "and drops nothing")
	assert_eq(a.targets, {"factions": ["faction.millford"]}, "its targets ride along")
	var b: Dictionary = rec.spawns[1]
	assert_eq(b.definition, "enemy.archer", "a preferred record that exists replaces the definition")
	assert_near(float(b.yaw_deg), 135.0, 1e-4, "45 + 90")
	assert_eq((rec.spawns[2] as Dictionary).definition, "enemy.wolf", "a preferred record that does not exist yet: the definition")
	var f: Dictionary = rec.formations[0]
	assert_eq(f.banner, "test.banner.7", "the formation's banner renamed with its spawn")
	assert_near(float(f.yaw_deg), 90.0, 1e-4, "the formation turned with the copy")
	var meta: Dictionary = rec._p37
	assert_eq(meta.template, "encounter.tpl_test", "the copy knows its template")
	assert_eq(meta.offsets["test.a.7"], Vector3(2.0, 0.0, 0.0), "and each member's offset at yaw 0")
	assert_eq((_template().spawns[0] as Dictionary).entity_id, "test.a", "the template is untouched")
	var fp := WanderDirector.footprint(_template(), Vector3(0.0, 1.0, 0.0), 0.0)
	assert_eq(fp.size(), 4, "a footprint point per spawn")
	assert_eq(fp[0], Vector3(2.0, 1.0, 0.0), "at its offset from the anchor")
	assert_true(WanderDirector.footprint(_template(), Vector3.ZERO, PI)[1].distance_to(Vector3(0.0, 0.0, 3.0)) < 1e-4, "turned with the yaw")


# --------------------------------------------------------------------------- world events

func _event() -> Dictionary:
	return {"id": "event.test", "level": "level.world", "centre_m": [0, 0, 0], "start_radius_m": 200,
		"trigger": {"min_stage": 3, "max_stage": 5, "requires_flags": ["world.kingsgate.lit"], "forbids_flags": ["world.no"],
			"conditions": [{"type": "not", "of": {"type": "event_done", "event": "event.other", "outcome": "won"}}],
			"cooldown_s": 600, "max_runs": 2},
		"objective": {"kind": "protect", "targets": ["t.a", "t.b", "t.c"], "lost_to_fail": 5, "text": "{standing} of {total} stand"},
		"outcomes": {"defended": {}, "fell": {}}, "fail_outcome": "fell"}


func _start_ctx(flags: Dictionary, extra := {}) -> Dictionary:
	var ctx := {"stage": 4, "flags": flags, "now_s": 1000.0, "centre_ready": true, "distance_m": 150.0}
	ctx.merge(extra, true)
	return ctx


func test_an_event_starts_only_when_its_rules_hold() -> void:
	var e := WorldEvent.make(_event())
	var lit := {"world.kingsgate.lit": true}
	assert_eq(e.can_start_with(_start_ctx(lit)), "", "every rule holds: it may start")
	assert_eq(e.can_start_with(_start_ctx(lit, {"stage": 2})), "stage", "below its stages")
	assert_eq(e.can_start_with(_start_ctx(lit, {"stage": 6})), "stage", "above them")
	assert_eq(e.can_start_with(_start_ctx({})), "flags", "a required flag missing")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "world.no": true})), "flags", "a forbidden flag set")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.other.done": true, "event.other.outcome": "won"})),
		"conditions", "its conditions (an event_done)")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.other.done": true, "event.other.outcome": "lost"})),
		"", "another outcome of that event does not count")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.test.runs": 2})), "max_runs", "at most twice")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.test.runs": 1, "event.test.last_end_s": 500.0})),
		"cooldown", "ten minutes after the last one ended (500 s ago)")
	assert_eq(e.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.test.runs": 1, "event.test.last_end_s": 400.0})),
		"", "600 s after it ended")
	assert_eq(e.can_start_with(_start_ctx(lit, {"centre_ready": false})), "unloaded", "its centre chunk not loaded and ready")
	assert_eq(e.can_start_with(_start_ctx(lit, {"distance_m": 200.5})), "far", "the giant beyond 200 m")
	var from_start := _event()
	(from_start.trigger as Dictionary)["cooldown_from"] = "start"
	var s := WorldEvent.make(from_start)
	assert_eq(s.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.test.last_start_s": 400.0, "event.test.last_end_s": 900.0})),
		"", "cooldown_from start: 600 s after the last start (its end 100 s ago does not count)")
	assert_eq(s.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.test.last_start_s": 401.0})), "cooldown", "599 s after it")
	e.state = WorldEvent.RUNNING
	assert_eq(e.can_start_with(_start_ctx(lit)), "running", "a running event does not start again")


## M8 gate (F19, F12): a run a save holds in progress (counted, started after the last one ended), and the
## fail block's within_m.
func test_a_run_in_progress_and_the_fail_timer_within_m() -> void:
	var e := WorldEvent.make(_event())
	assert_false(e.run_in_progress({}), "never run")
	assert_true(e.run_in_progress({"event.test.runs": 1, "event.test.last_start_s": 10.0}), "started, never ended")
	assert_false(e.run_in_progress({"event.test.runs": 1, "event.test.last_start_s": 10.0, "event.test.last_end_s": 40.0}),
		"ended after it started")
	assert_true(e.run_in_progress({"event.test.runs": 2, "event.test.last_start_s": 900.0, "event.test.last_end_s": 40.0}),
		"a second run started after the first ended")
	assert_false(e.run_in_progress({"event.test.runs": 0, "event.test.last_start_s": 10.0}), "no run counted")
	assert_eq(e.fail_within_m(), 0.0, "no within_m: the fail timer runs wherever the giant is")
	var near := _event()
	near["fail"] = {"timer_s": 600, "within_m": 200}
	assert_eq(WorldEvent.make(near).fail_timer_s(), 600.0, "its timer")
	assert_eq(WorldEvent.make(near).fail_within_m(), 200.0, "only while the giant is within 200 m")
	var ev := {"schema_version": 1, "id": "event.t", "type": "world_event", "level": "level.world", "centre_m": [0, 0, 0],
		"fail": {"timer_s": 600, "within_m": 200}, "outcomes": {"defended": {}}}
	assert_eq(_validate(ev), "", "the schema takes fail.within_m")
	(ev.fail as Dictionary)["within_m"] = -5
	assert_true(_validate(ev).contains("within_m"), "but not below 0")


func test_the_protect_objective_its_flags_and_the_event_done_condition() -> void:
	var e := WorldEvent.make(_event())
	assert_eq(e.targets(), PackedStringArray(["t.a", "t.b", "t.c"]), "its protected targets")
	assert_eq(e.lost_to_fail(), 3, "lost_to_fail is capped at the targets listed")
	assert_eq(WorldEvent.make({"id": "event.x"}).lost_to_fail(), 0, "no objective: nothing to lose")
	assert_eq(WorldEvent.objective_text("Defend: {standing} of {total} stand", 3, 5), "Defend: 3 of 5 stand", "the tracker's line")
	assert_eq(WorldEvent.flag("event.millford_raid", "outcome"), "event.millford_raid.outcome", "the event's flags")
	assert_eq(WorldEvent.reward_flag("event.millford_raid", "defended"), "reward.millford_raid.defended", "its once-flag")
	assert_eq(e.success_outcome(), "defended", "success defaults to defended")
	assert_eq(e.fail_outcome(), "fell", "its fail outcome")
	assert_eq(e.runs({"event.test.runs": 2}), 2, "runs from its flag")
	var ctx := _ctx({})
	var c := {"type": "event_done", "event": "event.test"}
	assert_false(QuestConditions.holds(c, ctx), "not done")
	ctx.flags["event.test.done"] = true
	ctx.flags["event.test.outcome"] = "fell"
	assert_true(QuestConditions.holds(c, ctx), "done, any outcome")
	assert_true(QuestConditions.holds({"type": "event_done", "event": "event.test", "outcome": "fell"}, ctx), "done with that outcome")
	assert_false(QuestConditions.holds({"type": "event_done", "event": "event.test", "outcome": "defended"}, ctx), "not with another")
	assert_false(QuestConditions.holds({"type": "event_done", "event": ""}, ctx), "no event named: false")


func test_a_column_walks_its_route_and_a_round_trip_comes_back_to_its_start() -> void:
	var r := WorldEvent.Route.from_points(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]), false, 2.0)
	assert_eq(r.points.size(), 3, "a repeated point is dropped")
	assert_true(r.is_valid(), "two legs")
	assert_near(r.length, 20.0, 1e-4, "20 m of road")
	assert_eq(r.point_at(5.0), Vector3(5, 0, 0), "5 m along")
	assert_eq(r.point_at(15.0), Vector3(10, 0, 5), "15 m along, round the corner")
	assert_true(Formation.forward_of(r.yaw_at(5.0)).distance_to(Vector3(1, 0, 0)) < 1e-4, "it faces along the first leg")
	assert_true(Formation.forward_of(r.yaw_at(15.0)).distance_to(Vector3(0, 0, 1)) < 1e-4, "and the second")
	assert_near(r.project(Vector3(11.0, 3.0, 4.0)), 14.0, 1e-4, "a point beside the road projects onto it")
	r.advance(4.0)
	assert_near(r.s, 8.0, 1e-4, "it walks at its speed")
	r.advance(100.0)
	assert_true(r.done(), "and stops at its end")
	assert_eq(r.point_at(), Vector3(10, 0, 10), "the far end")
	var rt := WorldEvent.Route.from_points(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)]), true, 1.0)
	rt.begin_at(rt.project(Vector3(6.0, 0.0, -2.0)))
	assert_near(rt.start, 6.0, 1e-4, "it forms up where its centre lies on the road")
	assert_near(rt.end_s(), 34.0, 1e-4, "a round trip ends where it began")
	rt.advance(20.0)
	assert_true(Formation.forward_of(rt.yaw_at()).distance_to(Vector3(0, 0, -1)) < 1e-4, "turned about on the way back (%s)" % rt.point_at())
	rt.advance(100.0)
	assert_true(rt.done(), "home")
	assert_eq(rt.point_at(), Vector3(6, 0, 0), "back at its start")
	assert_false(WorldEvent.Route.from_points(PackedVector3Array([Vector3.ZERO])).is_valid(), "one point is no route")


# --------------------------------------------------------------------------- schemas and GameData

func test_the_schemas_p37_rules() -> void:
	var enc := {"schema_version": 1, "id": "encounter.t", "type": "encounter", "level": "level.world", "center_m": [0, 0, 0],
		"activate_radius_m": 50, "deactivate_radius_m": 80, "leash_radius_m": 40,
		"spawns": [{"entity_id": "t.a", "definition": "enemy.soldier", "position_m": [0, 0, 0], "targets": {"factions": ["faction.millford"]},
			"prefer": "enemy.dire_wolf"}]}
	assert_true(_validate(enc).contains("only a template's spawns take targets"), "a placed encounter's spawn takes no targets")
	assert_true(_validate(enc).contains("only a template's spawns take prefer"), "nor prefer")
	enc["template"] = true
	assert_eq(_validate(enc), "", "a template's spawn takes both")
	(enc.spawns[0] as Dictionary)["targets"] = {"aggro_player_m": 20}
	assert_true(_validate(enc).contains("names no team, faction or prop tag"), "targets that name nothing")
	var table := {"schema_version": 1, "id": "wander.t", "type": "wander_table", "region": "region.crownmarch", "patrol_m": 40,
		"entries": [{"id": "col", "weight": 1, "template": "encounter.t", "speed_mps": 1.5,
			"route": {"from": "world.marker.a", "to": "world.marker.b", "round_trip": true},
			"conditions": [{"type": "not", "of": {"type": "flag", "flag": "oath.crown.outcome", "equals": "parley"}}]}]}
	assert_eq(_validate(table), "", "a route, a speed and conditions")
	(table.entries[0] as Dictionary)["path"] = "world.patrol.road"
	assert_true(_validate(table).contains("a path or a route, not both"), "a path and a route")
	(table.entries[0] as Dictionary).erase("path")
	(table.entries[0] as Dictionary).erase("route")
	assert_true(_validate(table).contains("speed_mps needs a route or a path"), "a speed without a way to walk")
	(table.entries[0] as Dictionary)["route"] = {"from": "world.marker.a", "to": "world.marker.a"}
	assert_true(_validate(table).contains("from == to"), "a route from a place to itself")
	var ev := {"schema_version": 1, "id": "event.t", "type": "world_event", "level": "level.world", "centre_m": [0, 0, 0],
		"trigger": {"max_runs": 2, "cooldown_from": "end", "cooldown_s": 600},
		"objective": {"kind": "protect", "targets": ["world.a"], "lost_to_fail": 1, "text": "{standing}/{total}", "marker": "world.marker.a"},
		"success_outcome": "defended", "fail_outcome": "fell", "start_text": "Raid!", "respawn_text": "Not here.",
		"outcomes": {"defended": {"xp": 100, "text": "Saved."}, "fell": {"burn": 2, "text": "Burned."}}}
	assert_eq(_validate(ev), "", "the P37 event fields")
	ev["end_outcome"] = "passed"
	assert_true(_validate(ev).contains("'passed' is not one of its outcomes"), "a named outcome must exist")
	ev.erase("end_outcome")
	ev["route"] = {"from": "world.marker.a", "to": "world.cp.b"}
	ev["path"] = "world.patrol.road"
	assert_true(_validate(ev).contains("a path or a route, not both"), "an event's path and route")
	(ev.trigger as Dictionary)["cooldown_from"] = "noon"
	assert_true(_validate(ev).contains("cooldown_from"), "cooldown_from is start or end")


func _records() -> Dictionary:
	var region := {"id": "region.crownmarch", "type": "region", "level": "level.world"}
	var tpl := {"id": "encounter.tpl_ok", "type": "encounter", "template": true, "level": "level.world", "leash_radius_m": 40,
		"spawns": [{"entity_id": "t.a", "definition": "enemy.soldier", "persist_death": false, "loot_table": ""}]}
	var placed := {"id": "encounter.placed", "type": "encounter", "level": "level.world", "leash_radius_m": 40, "spawns": []}
	var table := {"id": "wander.t", "type": "wander_table", "region": "region.crownmarch",
		"entries": [{"id": "a", "template": "encounter.tpl_ok"}]}
	return {"region.crownmarch": region, "encounter.tpl_ok": tpl, "encounter.placed": placed, "wander.t": table,
		"level.world": GameData.get_record("level.world")}


func test_gamedata_checks_tables_and_events_name_leashed_templates_that_keep_nothing() -> void:
	var r := _records()
	var p := WorldEvent.data_problems(r)
	assert_eq(p.errors, PackedStringArray(), "a table naming a leashed template of its level: no error")
	assert_eq(p.warnings, PackedStringArray(), "and no warning")
	r["wander.t"].entries = [{"id": "a", "template": "encounter.placed"}]
	assert_true("\n".join(WorldEvent.data_problems(r).errors).contains("is not a template"), "a placed encounter is never copied")
	assert_true("\n".join(WorldEvent.data_problems(r).warnings).contains("a template no wander table or world event uses"),
		"an unused template is a warning")
	r = _records()
	r["encounter.tpl_ok"].level = "level.valley"
	assert_true("\n".join(WorldEvent.data_problems(r).errors).contains("belongs to level.valley"), "a template of another level")
	r = _records()
	r["encounter.tpl_ok"].erase("leash_radius_m")
	assert_true("\n".join(WorldEvent.data_problems(r).errors).contains("needs a leash_radius_m"), "an unleashed template")
	r = _records()
	(r["encounter.tpl_ok"].spawns[0] as Dictionary)["persist_death"] = true
	(r["encounter.tpl_ok"].spawns[0] as Dictionary)["loot_table"] = "loot.raider"
	var errs := "\n".join(WorldEvent.data_problems(r).errors)
	assert_true(errs.contains("persists nothing"), "a template's spawn may not persist its death")
	assert_true(errs.contains("drops no loot"), "nor drop loot (farmable)")
	r = _records()
	r["event.t"] = {"id": "event.t", "type": "world_event", "level": "level.world", "encounters": ["encounter.tpl_ok"],
		"route": {"from": "world.marker.toll_fort", "to": "world.marker.nowhere"},
		"objective": {"kind": "protect", "marker": "world.marker.nowhere_else", "targets": ["world.crownmarch.millford_house_1", "world.nothing"]}}
	errs = "\n".join(WorldEvent.data_problems(r).errors)
	assert_true(errs.contains("'world.marker.nowhere' is not in level.world's world index"), "a route's end is a place of the index")
	assert_false(errs.contains("world.marker.toll_fort'"), "the toll fort is")
	assert_true(errs.contains("objective.marker: 'world.marker.nowhere_else'"), "so is an objective's marker")
	assert_true("\n".join(WorldEvent.data_problems(r).warnings).contains("'world.nothing' is not in level.world's world index"),
		"an unknown protect target is a warning")


# --------------------------------------------------------------------------- the shipped Crownmarch

func test_the_crownmarch_table_and_events_are_the_plans() -> void:
	var t := GameData.get_record(TABLE)
	assert_eq(str(t.get("region", "")), "region.crownmarch", "the Crownmarch's table")
	assert_eq([int(t.max_active), t.interval_s, float(t.min_distance_m), float(t.max_distance_m), int(t.xp_full_spawns)],
		[2, [60.0, 120.0], 120.0, 220.0, 3], "2 at once, every 60-120 s, 120-220 m away, XP for three spawns")
	var want := {"toll_patrol": [3, 3, 4], "raider_band": [2, 3, 4], "wolf_pack": [2, 3, 3], "dire_wolf_pack": [2, 4, 10],
		"pike_column": [2, 4, 10], "cavalry_pair": [1, 5, 10], "militia": [3, 1, 10]}
	for e: Dictionary in t.entries:
		var w: Array = want.get(str(e.id), [])
		assert_false(w.is_empty(), "%s is one of the plan's entries" % e.id)
		if w.is_empty():
			continue
		assert_eq([int(e.weight), int(e.get("min_stage", 1)), int(e.get("max_stage", 10))], w, "%s's weight and stages" % e.id)
		var tpl := GameData.get_record(str(e.template))
		assert_true(bool(tpl.get("template", false)), "%s copies a template" % e.id)
		assert_true(float(tpl.get("leash_radius_m", 0.0)) > 0.0 and float(tpl.leash_radius_m) <= 70.0, "%s's template is leashed within 70 m" % e.id)
		for sp: Dictionary in tpl.spawns:
			assert_false(bool(sp.get("persist_death", true)) or str(sp.get("loot_table", "")) != "", "%s keeps nothing of %s" % [e.id, sp.entity_id])
	var ctx := _ctx({})
	assert_false(_ids(WanderDirector.eligible_entries(t, 6, ctx)).has("militia"), "Brannock's militia only while the town is hostile")
	ctx.flags["faction.brannock.hostile"] = true
	assert_true(_ids(WanderDirector.eligible_entries(t, 6, ctx)).has("militia"), "and then")
	assert_false(_ids(WanderDirector.eligible_entries(t, 6, ctx)).has("cavalry_pair"), "Aldmere's riders while Aldmere is hostile")
	ctx.flags["faction.aldmere.hostile"] = true
	assert_true(_ids(WanderDirector.eligible_entries(t, 6, ctx)).has("cavalry_pair"), "and then")
	ctx.flags["boss.corvane.outcome"] = "spared"
	assert_false(_ids(WanderDirector.eligible_entries(t, 6, ctx)).has("pike_column"), "the pike column is gone after Corvane is spared")
	var raid := WorldEvent.make(GameData.get_record(RAID))
	var lit := {"world.kingsgate.lit": true}
	assert_eq(raid.can_start_with(_start_ctx(lit, {"stage": 3})), "", "the raid: stage 3 with the beacon lit")
	assert_eq(raid.can_start_with(_start_ctx(lit, {"stage": 6})), "stage", "not at stage 6")
	assert_eq(raid.can_start_with(_start_ctx({"world.kingsgate.lit": true, "faction.millford.hostile": true})), "conditions",
		"not while Millford is hostile to the giant")
	assert_eq(raid.can_start_with(_start_ctx({"world.kingsgate.lit": true, "event.millford_raid.runs": 2})), "max_runs", "at most twice")
	assert_eq([raid.lost_to_fail(), raid.targets().size()], [3, 5], "it fails when three of five houses fall")
	var column := WorldEvent.make(GameData.get_record(COLUMN))
	assert_true(column.is_moving(), "the column marches")
	assert_eq(column.can_start_with(_start_ctx({})), "flags", "only while Aldmere is hostile")
	assert_eq(column.can_start_with(_start_ctx({"faction.aldmere.hostile": true}, {"stage": 4})), "", "at stage 4 then")
	assert_eq(column.can_start_with(_start_ctx({"faction.aldmere.hostile": true, "oath.crown.outcome": "parley"})), "conditions",
		"not after the crown's parley")
	assert_eq([column.success_outcome(), column.end_outcome()], ["broken", "passed"], "broken or passed")


## The most kill XP the Crownmarch's living world can ever pay: each entry's first xp_full_spawns copies
## and each event's first xp_full_runs runs (no more than its max_runs), plus each outcome's XP once.
func test_the_living_worlds_kill_xp_is_bounded() -> void:
	var t := GameData.get_record(TABLE)
	var wander := 0
	for e: Dictionary in t.entries:
		wander += int(t.xp_full_spawns) * _kill_xp(GameData.get_record(str(e.template)))
	var events := 0
	for id: String in [RAID, COLUMN]:
		var rec := GameData.get_record(id)
		var runs := int(rec.get("xp_full_runs", WorldEvent.DEFAULT_XP_FULL_RUNS))
		var cap := int((rec.trigger as Dictionary).get("max_runs", 0))
		if cap > 0:
			runs = mini(runs, cap)
		for tid: Variant in rec.encounters:
			events += runs * _kill_xp(GameData.get_record(str(tid)))
		for o: Dictionary in (rec.outcomes as Dictionary).values():
			events += int(o.get("xp", 0))
	var placed := 0
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.id).begins_with("encounter.crownmarch_"):
			placed += _kill_xp(rec)
	print("    the Crownmarch's living world pays at most %d kill XP from wanderers and %d from its events (placed fights: %d)" % [
		wander, events, placed])
	assert_true(wander + events > 0, "it pays something")
	# A sanity bound with room for the archetypes the templates prefer once they land (P34's dire wolves):
	# the living world tops the Crownmarch's placed fights up, it does not dwarf them.
	assert_true(wander + events <= 3 * placed, "never more than three times the region's placed fights (%d + %d vs %d)" % [wander, events, placed])


func _kill_xp(enc: Dictionary) -> int:
	var n := 0
	for sp: Dictionary in enc.get("spawns", []):
		var def := str(sp.get("definition", ""))
		if str(sp.get("prefer", "")) != "" and GameData.has_record(str(sp.prefer)):
			def = str(sp.prefer)
		n += int(GameData.get_record(def).get("xp_reward", 0))
	return n
