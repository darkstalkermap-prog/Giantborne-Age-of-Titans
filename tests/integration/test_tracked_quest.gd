extends IntegrationSuite
## P27 (plan M6-M9 §2.12, §3.10 design 4): the tracked quest. track() and track_next() cycle the
## active quests (main first) with Events.quest_tracked; current_objective() and objectives()'
## "tracked" follow it, the tracker's first line and the objective marker too; a multi-marker stage
## gives every marker to the compass (three diamonds) and, while another quest is tracked, the main
## quest's markers are its leads (at most three); the tracked quest survives a save (Continue) and a
## fast travel (GameSession's progress.tracked_quest, P20).

const Fx := preload("res://tests/support/quest_fixtures.gd")
const Wux := preload("res://tests/support/world_ux_fixtures.gd")
const Tracker := preload("res://ui/hud/quest_tracker.gd")

var tracked_events: Array[String] = []


func before_each() -> void:
	await super()
	tracked_events.clear()
	Events.quest_tracked.connect(_on_tracked)


func after_each() -> void:
	if Events.quest_tracked.is_connected(_on_tracked):
		Events.quest_tracked.disconnect(_on_tracked)
	await super()


func _on_tracked(quest_id: String) -> void:
	tracked_events.append(quest_id)


func _marker(id: String, pos: Vector3) -> LevelMarker:
	var m := LevelMarker.new()
	m.marker_id = id
	m.position = pos
	world.add_child(m)
	return m


## Three quests: the main one on a stage with three markers (the oath leads), two side quests with one.
func _quests() -> void:
	Fx.install([
		Fx.quest("quest.test_main", [Fx.stage("oaths", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Choose an oath", "markers": ["test.m.lead_a", "test.m.lead_b", "test.m.lead_c"]})],
			{"display_name": "The Main Thread"}),
		Fx.quest("quest.test_side_a", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Go to A", "marker": "test.m.side_a"})], {"display_name": "Side A"}),
		Fx.quest("quest.test_side_b", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Go to B", "marker": "test.m.side_b", "waiting_text": "Waiting: stage 5"})],
			{"display_name": "Side B"}),
	])
	Fx.activate(["quest.test_main", "quest.test_side_a", "quest.test_side_b"], [], "quest.test_main")


func test_track_cycles_and_everything_follows() -> void:
	_quests()
	for m: Array in [["test.m.lead_a", Vector3(0, 1, -40)], ["test.m.lead_b", Vector3(30, 1, -30)],
			["test.m.lead_c", Vector3(-30, 1, -30)], ["test.m.side_a", Vector3(40, 1, 0)], ["test.m.side_b", Vector3(-40, 1, 0)]]:
		_marker(m[0], m[1])
	await step_ticks(2)
	Quests.refresh_positions()
	assert_eq(Array(Quests.active_quest_ids()), ["quest.test_main", "quest.test_side_b", "quest.test_side_a"],
		"three active quests, main first")
	assert_eq(Quests.tracked_id(), "quest.test_main", "the main quest leads by default")
	assert_eq(str(Quests.current_objective().quest_id), "quest.test_main", "and the objective is its")
	var positions: Array = Quests.tracked_objective().positions
	assert_eq(positions.size(), 3, "a multi-marker stage gives all three markers")
	var diamonds := HudCompass.markers_for(Vector3.ZERO, 0.0, {}, {}, HudCompass.objective_positions(Quests.tracked_objective()),
		Quests.leads(), Vector2.INF)
	assert_eq(diamonds.filter(func(m: Dictionary) -> bool: return m.kind == "objective").size(), 3,
		"the compass shows three diamonds")
	assert_eq(Quests.leads(), [], "no leads while the main quest is tracked")
	var order: Array = []
	for i in 3:
		order.append(Quests.track_next())
	assert_eq(order, ["quest.test_side_b", "quest.test_side_a", "quest.test_main"], "track_next cycles in tracker order and wraps")
	assert_eq(tracked_events, order, "quest_tracked for each")
	assert_true(Quests.track("quest.test_side_a"), "track() an active quest")
	assert_false(Quests.track("quest.test_nothing"), "but not an unknown one")
	assert_eq(str(Quests.current_objective().quest_id), "quest.test_side_a", "the objective follows the tracked quest")
	assert_true((Quests.current_objective().position as Vector3).is_equal_approx(Vector3(40, 1, 0)), "its marker")
	var marked: Array = Quests.objectives().map(func(o: Dictionary) -> Array: return [o.quest_id, o.tracked])
	assert_eq(marked, [["quest.test_main", false], ["quest.test_side_b", false], ["quest.test_side_a", true]],
		"objectives() marks the tracked one")
	assert_eq(Quests.leads().size(), 3, "the main quest's three markers are the leads")
	var lines: Dictionary = Tracker.lines_for(Quests.objectives(), false, "", Quests.tracked_id())
	assert_eq([lines.main_title, lines.main_text, lines.side_title], ["Side A", "Go to A", "The Main Thread"],
		"the tracker leads with the tracked quest, then the main one")
	WorldState.set_flag(Quests.done_flag("quest.test_side_a"), true)
	assert_eq(Quests.tracked_id(), "quest.test_main", "a finished tracked quest hands back to the main quest")
	# the HUD: the objective marker and T
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	WorldState.flags.erase(Quests.done_flag("quest.test_side_a"))
	Quests.track("quest.test_main")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	await get_tree().process_frame
	assert_eq(hud.track_next_now(), "Tracking: Side B", "T tracks the next quest and says so")
	await get_tree().process_frame
	await get_tree().process_frame
	var place: Dictionary = hud.get_node("ObjectiveMarker").call("placement_now")
	assert_false(place.is_empty(), "the objective marker shows")
	if not place.is_empty():
		assert_true((place.target as Vector3).is_equal_approx(Vector3(-40, 1, 0)), "at the tracked quest's marker")
	assert_true(hud.message_texts().has("Tracking: Side B"), "the HUD line")
	p.queue_free()


func test_a_done_lead_leaves_the_objective_the_compass_and_the_leads() -> void:
	# M7 polish (the M7 gate review): a multi-marker stage drops a marker once its markers_done_when
	# condition holds - an oath lead once its oath is won - so the objective, its diamonds, the marker
	# the giant is led to and the compass's leads never point at a finished lead.
	Fx.install([
		Fx.quest("quest.test_main", [Fx.stage("oaths", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Choose an oath", "markers": ["test.m.lead_a", "test.m.lead_b", "test.m.lead_c"],
				"markers_done_when": {"test.m.lead_a": Fx.flag_cond("test.oath.a"), "test.m.lead_b": Fx.flag_cond("test.oath.b")}})],
			{"display_name": "The Main Thread"}),
		Fx.quest("quest.test_side_a", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Go to A", "marker": "test.m.side_a"})], {"display_name": "Side A"}),
	])
	Fx.activate(["quest.test_main", "quest.test_side_a"], [], "quest.test_main")
	var lead_a := Vector3(0, 1, -40)
	for m: Array in [["test.m.lead_a", lead_a], ["test.m.lead_b", Vector3(30, 1, -30)],
			["test.m.lead_c", Vector3(-30, 1, -30)], ["test.m.side_a", Vector3(40, 1, 0)]]:
		_marker(m[0], m[1])
	var p := spawn_player(lead_a + Vector3(0, -0.95, 2), 0.0)
	await step_ticks(2)
	Quests.refresh_positions()
	var diamonds := func() -> int:
		return HudCompass.markers_for(Vector3.ZERO, 0.0, {}, {}, HudCompass.objective_positions(Quests.tracked_objective()),
			[], Vector2.INF).filter(func(m: Dictionary) -> bool: return m.kind == "objective").size()
	assert_eq(Array(Quests.tracked_objective().markers), ["test.m.lead_a", "test.m.lead_b", "test.m.lead_c"], "three leads open")
	assert_eq(diamonds.call(), 3, "three diamonds")
	assert_true((Quests.current_objective().position as Vector3).is_equal_approx(lead_a), "the giant at lead A is led to it")
	WorldState.set_flag("test.oath.a", true)
	var o := Quests.tracked_objective()
	assert_eq(Array(o.markers), ["test.m.lead_b", "test.m.lead_c"], "lead A is done: two open")
	assert_eq(diamonds.call(), 2, "two diamonds")
	assert_false((o.position as Vector3).is_equal_approx(lead_a), "the marker no longer leads to A, though the giant stands there")
	assert_eq(str(o.marker_id), "test.m.lead_b", "the first open lead names the objective")
	Quests.track("quest.test_side_a")
	assert_eq(Quests.leads().map(func(l: Dictionary) -> String: return str(l.marker_id)), ["test.m.lead_b", "test.m.lead_c"],
		"the compass's leads are the open ones")
	Quests.track("quest.test_main")
	WorldState.set_flag("test.oath.b", true)
	o = Quests.tracked_objective()
	assert_eq(Array(o.markers), ["test.m.lead_c"], "lead C alone (it has no done condition)")
	assert_true((o.position as Vector3).is_equal_approx(Vector3(-30, 1, -30)), "and the objective is it")
	assert_eq(diamonds.call(), 1, "one diamond")
	p.queue_free()


func test_a_marker_on_another_level_leads_to_the_door_there() -> void:
	# M7 polish (the M7 gate review): a marker only another level's index knows had no position here
	# (Vector3.INF), so the tracker showed text alone and the compass, the map and the HUD marker
	# nothing. It now leads to this level's exit to that level, while the door is open.
	Wux.install()
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = Wux.LEVEL
	Fx.install([Fx.quest("quest.test_citadel", [Fx.stage("breach", Fx.flag_cond("test.flag.never"), 0,
		{"objective": "Breach the gate", "marker": "valley.marker.citadel_gate"})], {"display_name": "The Test Citadel"})])
	Fx.activate(["quest.test_citadel"], [], "quest.test_citadel")
	Quests.evaluate_now()
	var o := Quests.objective_for("quest.test_citadel")
	assert_false((o.position as Vector3).is_finite(), "the stub's door arrives at the Kings' Door waystone, shut before the crown")
	WorldState.set_flag("slice.completed", true)
	o = Quests.objective_for("quest.test_citadel")
	assert_true((o.position as Vector3).is_equal_approx(Vector3(190, 0, 0)), "the objective is the door to the Valley (%s)" % o.position)
	assert_eq([o.via_exit, o.via_name], ["test.p27.exit", "The test door"], "and names it")
	assert_eq(HudCompass.objective_positions(o).size(), 1, "one diamond on the compass and the map")
	assert_false(Quests.objective_position("valley.marker.citadel_gate").is_finite(),
		"objective_position stays this level's own (the near condition never holds beside a door)")
	var lines: Dictionary = Tracker.lines_for([o], false, "", "quest.test_citadel")
	assert_eq([lines.main_title, lines.main_text], ["The Test Citadel  -  by the test door", "Breach the gate"],
		"the tracker says which door")
	# A marker this level knows is not routed anywhere else.
	var here := Fx.quest("quest.test_here", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
		{"objective": "Go", "marker": "test.p27.cp_far"})])
	Fx.install([here])
	Fx.activate(["quest.test_here"], [], "quest.test_here")
	Quests.evaluate_now()
	var h := Quests.objective_for("quest.test_here")
	assert_true((h.position as Vector3).is_equal_approx(Vector3(150, 0, -150)), "a marker of this level is its own position")
	assert_eq(str(h.via_exit), "", "with no door")


func test_the_sealed_citadel_leads_out_of_the_world_and_the_oaths_out_of_the_valley() -> void:
	# The finding's cases on the shipped indexes: quest.sealed_citadel tracked in the world, and
	# quest.world_main's stages while the giant revisits the Valley.
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = "level.world"
	Quests.test_active = true
	Quests.scope = PackedStringArray(["quest.sealed_citadel", "quest.world_main"])
	Quests.main_quest_id = "quest.world_main"
	var world_idx := WorldIndex.for_level("level.world")
	var valley_idx := WorldIndex.for_level("level.valley")
	WorldState.set_flag("slice.completed", true)
	WorldState.set_flag(Quests.stage_flag("quest.sealed_citadel"), "breach")
	var o := Quests.objective_for("quest.sealed_citadel")
	assert_eq(str(o.via_exit), "world.exit.kingsgate", "the breach: by the Kings' Door (the Broken Stair is choked)")
	assert_true((o.position as Vector3).is_equal_approx(world_idx.exits["world.exit.kingsgate"].position), "at the door")
	assert_eq(str(o.via_name), "The Kings' Door", "named")
	var rows: Array = (JournalScreen.sections().active as Array).filter(func(r: Dictionary) -> bool:
		return str(r.id) == "quest.sealed_citadel")
	assert_eq(str(rows[0].region) if rows.size() == 1 else "?", "by the Kings' Door",
		"the journal names the door, not the region around it")
	WorldState.set_flag("world.citadel.breached", true)
	WorldState.set_flag(Quests.stage_flag("quest.sealed_citadel"), "hall")
	o = Quests.objective_for("quest.sealed_citadel")
	assert_eq(str(o.via_exit), "world.exit.broken_stair", "the hall: by the Broken Stair once the breach opened it")
	# Back in the Valley the world's main thread leads to the Kings' Door - not the Citadel stair,
	# shut behind its gate until the breach.
	GameSession.level_id = "level.valley"
	WorldState.clear()
	WorldState.set_flag("slice.completed", true)
	WorldState.set_flag(Quests.stage_flag("quest.world_main"), "beacon")
	o = Quests.objective_for("quest.world_main")
	assert_eq(str(o.via_exit), "valley.exit.kings_door", "the beacon: by the Kings' Door")
	assert_true((o.position as Vector3).is_equal_approx(valley_idx.exits["valley.exit.kings_door"].position), "at the door")
	WorldState.set_flag(Quests.stage_flag("quest.world_main"), "oaths")
	o = Quests.objective_for("quest.world_main")
	assert_eq(Array(o.markers).size(), 3, "the oaths stage still names its three leads")
	assert_eq((o.positions as Array).size(), 1, "which lead through one door: one diamond")
	assert_eq(str(o.via_exit), "valley.exit.kings_door", "the Kings' Door")
	assert_false(Quests.objective_position("world.marker.kingsgate_beacon").is_finite(), "the near condition's lookup is the Valley's own")


func test_the_tracked_quest_survives_a_save_and_a_fast_travel() -> void:
	Wux.install()
	GameSession.persist = true
	GameSession.level_override = ""
	GameSession.start_world_for_tests("test.p27.cp_start")
	GameSession.level_id = Wux.LEVEL
	var p := spawn_player(Vector3(0, 0.05, 150), 0.0)
	GameSession.on_level_ready(world, p)
	_quests()
	await step_ticks(1)
	Quests.track("quest.test_side_a")
	var c := GameSession.take_checkpoint("test")
	assert_true(bool(c.get("ok", false)), "a checkpoint is written (%s)" % c)
	assert_eq(str(GameSession.checkpoint_doc.progress.tracked_quest), "quest.test_side_a", "it holds the tracked quest")
	# quit and Continue: a fresh Quests state, the save's progress back
	Quests.tracked_quest_id = ""
	GameSession.progress = {}
	assert_true(bool(GameSession.continue_valley().ok), "Continue reads the save")
	GameSession.on_level_ready(world, p)
	assert_eq(Quests.tracked_quest_id, "quest.test_side_a", "the tracked quest is back after Continue")
	assert_eq(Quests.tracked_id(), "quest.test_side_a", "and followed")
	# a fast travel: the checkpoint at the destination carries it over the reload
	WorldState.set_flag("visited.test.p27.cp_far", true)
	var t := GameSession.travel_to(Wux.LEVEL, "test.p27.cp_far", "fast_travel")
	assert_true(bool(t.ok), "the fast travel goes (%s)" % t)
	assert_eq(GameSession.scene_reloads.back(), "fast_travel", "a reload")
	Quests.tracked_quest_id = ""
	GameSession.on_level_ready(world, p)
	assert_eq(Quests.tracked_quest_id, "quest.test_side_a", "the tracked quest survives the fast travel")
	assert_eq(GameSession.respawn_id, "test.p27.cp_far", "at the destination")
