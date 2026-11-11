extends IntegrationSuite
## P37 (plan M6-M9 §2.13, §5.10, decision 27): world events on a tiny streamed level
## (tests/support/living_world_fixtures.gd: a raid whose centre lies by the giant, protecting two
## props, and a column on the road):
##   * an event starts only with its centre chunk loaded and ready and the giant within 200 m; at most
##     one runs at a time (the other waits until it ends);
##   * starting counts a run, says its notice on the HUD, emits world_event_started, puts its objective
##     in Quests (active, tracked, its line "Hold: 2 of 2 stand") and brings its encounters' copies into
##     the world;
##   * a respawn within 120 m of it is refused with its text and moves to another checkpoint;
##   * the protect objective lost (lost_to_fail of its targets destroyed) ends it with its fail outcome:
##     done and outcome flags, its set_flags, the tracker's choice given back, world_event_ended;
##   * every copy defeated ends it with its success outcome and pays its XP once (a second run's
##     success pays none);
##   * the giant's death resets the attempt: its copies go, its timer starts again, it waits and its
##     encounters come back; an outcome already won stays;
##   * M8 gate (F2): "at most one at a time" is about the events in play - an event left behind (its centre
##     unloaded, the giant beyond its start radius, none of its members in the world) keeps no other from
##     starting where the giant is, and while that one is in play the one left behind waits (its attempt
##     does not begin); its abandonment clock outlives the giant's death and the reload that follows.
##   * M8 gate fix-up 1 (N4.4): a running event leads the tracker (the HUD marker, the compass, the map)
##     only while it is in play - left behind, it gives the tracker back and the main quest leads again
##     (it stays in the tracker's list and the journal, where the player may track it: that choice is
##     kept); back in play it takes the tracker again.

const F := preload("res://tests/support/living_world_fixtures.gd")
## M8 gate (F2): a second raid at the tiny world's east end (more than its start radius from the first).
const EAST := "event.p37_east"
const EAST_TPL := "encounter.p37_tpl_east"
const EAST_AT := [104.0, 0.0, 96.0]

var _root: WorldRoot
var _wd: WanderDirector
var _started: Array = []
var _ended: Array = []
var _hud: Array = []
var _xp: Array = []


func before_each() -> void:
	await super()
	_started.clear()
	_ended.clear()
	_hud.clear()
	_xp.clear()
	Events.world_event_started.connect(_on_event_started)
	Events.world_event_ended.connect(_on_event_ended)
	Events.hud_message.connect(_on_hud)
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	for sig: Signal in [Events.world_event_started, Events.world_event_ended, Events.hud_message, Events.xp_award_requested]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	F.reset()
	await super()


func _on_event_started(_t: int, id: String) -> void:
	_started.append(id)


func _on_event_ended(_t: int, id: String, outcome: String) -> void:
	_ended.append([id, outcome])


func _on_hud(text: String, _kind: String) -> void:
	_hud.append(text)


func _on_xp(amount: int, source: String) -> void:
	_xp.append([amount, source])


func _setup() -> void:
	F.install()
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]


## Kills every living member of the event's copies.
func _defeat(e: WorldEvent) -> void:
	for id in e.copies:
		for n: Node3D in _wd.director.p37_living(id):
			var en := (n as EnemyActor).entity
			en.combatant.pools.health = 0.0
			en.combatant.dead = true
			Events.entity_died.emit(Sim.tick, en.entity_id, "")


func test_one_event_at_a_time_near_its_centre_its_objective_and_the_respawn_it_moves() -> void:
	_setup()
	WorldState.set_flag("p37.raid.on", true)
	WorldState.set_flag("p37.column.on", true)
	var raid: WorldEvent = _wd.events[F.RAID]
	var column: WorldEvent = _wd.events[F.COLUMN]
	F.move_giant(_root, 96.0, 16.0)
	assert_eq(raid.can_start_with(_wd.event_context(raid)), "unloaded", "its centre chunk is not loaded")
	_wd.check_events(Sim.tick)
	assert_eq(_wd.running_event(), null, "nothing starts away from both centres")
	F.move_giant(_root, -96.0, 16.0)
	_wd.check_events(Sim.tick)
	assert_eq(_wd.running_event(), column, "one starts (the first by id)")
	_wd.check_events(Sim.tick)
	assert_false(raid.is_running(), "the raid waits while the column runs: events never overlap")
	assert_eq(raid.can_start_with(_wd.event_context(raid)), "", "though its own rules hold")
	_wd.end_event(column, WanderDirector.ABANDONED)
	assert_eq(_ended, [[F.COLUMN, WanderDirector.ABANDONED]], "the column ends (no outcome)")
	assert_false(WorldState.has_flag("event.p37_column.done"), "an abandoned run sets no outcome")
	_wd.check_events(Sim.tick)
	assert_eq(_wd.running_event(), raid, "now the raid starts")
	assert_eq(raid.state, WorldEvent.RUNNING, "its encounters in the world (its centre ready, the giant near)")
	assert_eq(_started, [F.COLUMN, F.RAID], "world_event_started for each")
	assert_true(_hud.has("Raid!"), "its notice on the HUD (%s)" % [_hud])
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "a run counted")
	assert_true(Quests.active_quest_ids().has(F.RAID), "its objective is an active quest of the tracker and the journal")
	assert_eq(Quests.tracked_quest_id, F.RAID, "tracked at once (compass, map, marker)")
	var obj := Quests.objective_for(F.RAID)
	assert_eq(str(obj.get("text", "")), "Hold: 2 of 2 stand", "the tracker's line")
	var at: Vector3 = obj.get("position", Vector3.INF)
	assert_true(Vector2(at.x + 104.0, at.z + 8.0).length() < 0.5, "its marker at the event's centre (%s)" % at)
	assert_eq(raid.copies.size(), 1, "one copy of its template")
	await step_ticks(3)
	assert_eq(_wd.director.p37_living(raid.copies[0]).size(), 2, "its raiders came")
	# A respawn near it is refused and moves on.
	GameSession.level_override = F.LEVEL
	assert_eq(GameSession.respawn_blocker(F.NEAR_CP, F.LEVEL), "The raid goes on there.", "no respawn within 120 m of it")
	assert_eq(GameSession.respawn_blocker(F.FAR_CP, F.LEVEL), "", "the far stone is fine")
	GameSession.respawn_id = F.NEAR_CP
	assert_eq(GameSession.respawn_checkpoint(), F.FAR_CP, "a death near it wakes at the other checkpoint")
	# The protect objective lost: two props destroyed.
	WorldState.record_destroyed("p37.prop_a", 1)
	_wd.update_event(raid, 0.1)
	assert_eq(str(Quests.objective_for(F.RAID).get("text", "")), "Hold: 1 of 2 stand", "the line counts what stands")
	WorldState.record_destroyed("p37.prop_b", 1)
	_wd.update_event(raid, 0.1)
	assert_false(raid.is_running(), "it ended")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "fell"], "with its fail outcome")
	assert_eq(WorldState.get_flag("event.p37_raid.done"), true, "done")
	assert_eq(WorldState.get_flag("event.p37_raid.outcome"), "fell", "and its outcome (event_done)")
	assert_eq(WorldState.get_flag("p37.tiny.fell"), true, "its set_flags")
	assert_true(_hud.has("Lost."), "its text")
	assert_false(Quests.active_quest_ids().has(F.RAID), "no longer an objective")
	assert_eq(Quests.tracked_quest_id, "", "the tracker's choice given back (none before)")
	assert_eq(GameSession.respawn_blocker(F.NEAR_CP, F.LEVEL), "", "respawns there are fine again")
	assert_eq(raid.can_start_with(_wd.event_context(raid)), "cooldown", "ten minutes before the next")


func test_success_pays_once_and_a_death_resets_the_attempt() -> void:
	_setup()
	var raid: WorldEvent = _wd.events[F.RAID]
	_wd.start_event(raid)
	await step_ticks(3)
	var first := raid.copies[0]
	assert_eq(_wd.director.p37_living(first).size(), 2, "its raiders came")
	raid.elapsed_s = 5.0
	# The giant dies: the attempt starts again.
	var p := _root.player()
	Events.entity_died.emit(Sim.tick, p.entity.entity_id, "")
	assert_eq(raid.state, WorldEvent.WAITING, "the attempt waits to begin again")
	assert_true(raid.copies.is_empty(), "its copies go")
	assert_eq(raid.elapsed_s, 0.0, "its timer starts again")
	assert_true(WanderDirector.is_carried(F.LEVEL, F.RAID), "carried for the reload that follows a death")
	await step_ticks(WanderDirector.UPDATE_TICKS + 2)
	assert_eq(_wd.director.encounter_state(first), "", "the old copy is gone")
	assert_eq(raid.state, WorldEvent.RUNNING, "it began again (its rule holds)")
	assert_eq(raid.copies.size(), 1, "with a new copy")
	assert_ne(raid.copies[0], first, "a new copy id")
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "the same run")
	await step_ticks(3)
	_defeat(raid)
	_wd.update_event(raid, 0.1)
	assert_false(raid.is_running(), "every raider down: it ends")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "defended"], "with its success outcome")
	assert_eq(_xp, [[100, "event:" + F.RAID]], "its XP paid")
	assert_eq(WorldState.get_flag("p37.tiny.defended"), true, "its flags")
	# A second run's success pays nothing more; the outcome stays.
	_wd.start_event(raid)
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 2, "a second run")
	await step_ticks(3)
	Events.entity_died.emit(Sim.tick, p.entity.entity_id, "")
	assert_eq(WorldState.get_flag("event.p37_raid.outcome"), "defended", "a death keeps the outcome won")
	await step_ticks(WanderDirector.UPDATE_TICKS + 4)
	_defeat(raid)
	_wd.update_event(raid, 0.1)
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "defended"], "defended again")
	assert_eq(_xp.size(), 1, "but its XP was paid once (%s)" % [_xp])


func assert_ne(a: Variant, b: Variant, message: String) -> void:
	assert_true(a != b, "%s (%s)" % [message, a])


# --------------------------------------------------------------------------- M8 gate (F2)

## A second raid at the east end: its own template there, its own switch (p37.east.on).
func _install_east() -> void:
	TestFixtures.record_override(EAST_TPL, F._template(EAST_TPL, EAST_AT, [["p37.east_a", -2.0, 0.0, ""], ["p37.east_b", 2.0, 0.0, ""]], 40.0))
	var rec := (GameData.get_record(F.RAID) as Dictionary).duplicate(true)
	rec["id"] = EAST
	rec["display_name"] = "Tiny east raid"
	rec["centre_m"] = [EAST_AT[0], F.height(EAST_AT[0], EAST_AT[2]), EAST_AT[2]]
	(rec.trigger as Dictionary)["requires_flags"] = ["p37.east.on"]
	rec["encounters"] = [EAST_TPL]
	rec["objective"] = {"kind": "defeat", "targets": [], "text": "Hold the east"}
	TestFixtures.record_override(EAST, rec)


func test_an_event_left_behind_keeps_no_other_from_starting() -> void:
	F.install()
	_install_east()
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]
	var raid: WorldEvent = _wd.events[F.RAID]
	var east: WorldEvent = _wd.events[EAST]
	WorldState.set_flag("p37.raid.on", true)
	WorldState.set_flag("p37.east.on", true)
	_wd.check_events(Sim.tick)
	assert_eq(_wd.running_event(), raid, "the raid starts where the giant is")
	await step_ticks(3)
	assert_true(_wd.in_play(raid), "it is in play: its raiders in the world")
	_wd.check_events(Sim.tick)
	assert_false(east.is_running(), "the east raid does not start while the raid is in play")
	# the giant walks away to the east end: the raid's centre unloads, its raiders leave with the chunk
	F.move_giant(_root, 96.0, 80.0)
	await step_ticks(2)
	_wd.update_event(raid, 0.5)
	assert_eq(raid.state, WorldEvent.SUSPENDED, "the raid left behind is suspended")
	assert_false(_wd.in_play(raid), "and out of play")
	assert_eq(east.can_start_with(_wd.event_context(east)), "", "the east raid's own rules hold")
	_wd.check_events(Sim.tick)
	assert_true(east.is_running(), "the east raid starts: the one left behind holds no slot (M8 gate, F2)")
	assert_true(_wd.in_play(east), "the east raid is in play")
	assert_true(raid.is_running(), "the raid left behind still runs (suspended)")
	assert_eq(_wd.running_event(), east, "running_event() names the one in play")
	assert_eq(Quests.tracked_quest_id, EAST, "the new one takes the tracker")
	# while the east raid is in play the raid left behind waits, even with its own start rule holding again
	F.move_giant(_root, -30.0, 40.0)
	await step_ticks(2)
	assert_true(_wd.in_play(east), "the east raid is still in play (its place within 200 m)")
	assert_true(_root.streamer.is_ready(_root.chunk_at(raid.centre)), "the raid's centre is loaded again")
	assert_true(Vector2(-30.0 - raid.centre.x, 40.0 - raid.centre.z).length() < raid.start_radius(), "and the giant near it")
	_wd.reset_attempt(raid)
	_wd.update_event(raid, 0.5)
	assert_eq(raid.state, WorldEvent.WAITING, "the raid waits: its attempt does not begin while another is in play")
	assert_true(raid.copies.is_empty(), "none of its raiders come")
	_wd.end_event(east, WanderDirector.ABANDONED)
	_wd.update_event(raid, 0.5)
	assert_eq(raid.state, WorldEvent.RUNNING, "once the east raid is over the raid begins again")
	assert_eq(raid.copies.size(), 1, "its raiders come back")
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "its run counted once")
	_wd.end_event(raid, WanderDirector.ABANDONED)
	assert_eq(Quests.tracked_quest_id, "", "each gave the tracker back (none was chosen before)")


func test_the_abandonment_clock_outlives_a_death_and_the_reload() -> void:
	_setup()
	var raid: WorldEvent = _wd.events[F.RAID]
	_wd.start_event(raid)
	F.move_giant(_root, 96.0, 16.0)
	await step_ticks(2)
	for i in 12:
		_wd.update_event(raid, 1.0)
	assert_near(raid.unloaded_s, 12.0, 0.3, "12 s unloaded (%.1f)" % raid.unloaded_s)
	Events.entity_died.emit(Sim.tick, _root.player().entity.entity_id, "")
	assert_eq(raid.state, WorldEvent.WAITING, "the giant's death restarts the attempt")
	assert_near(raid.unloaded_s, 12.0, 0.3, "but not its abandonment clock (%.1f)" % raid.unloaded_s)
	_root.free()
	var made := F.make(world, Vector3(96.0, 0.0, 16.0))
	_root = made[0]
	_wd = made[1]
	raid = _wd.events[F.RAID]
	assert_eq(raid.state, WorldEvent.WAITING, "the reload resumes it")
	assert_near(raid.unloaded_s, 12.0, 0.3, "with its abandonment clock (%.1f)" % raid.unloaded_s)
	for i in 7:
		_wd.update_event(raid, 1.0)
	assert_true(raid.is_running(), "19 s unloaded in all: still waiting")
	_wd.update_event(raid, 1.0)
	assert_false(raid.is_running(), "20 s: given up, a reload or a death did not restart the clock")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, WanderDirector.ABANDONED], "with no outcome")


## M8 gate fix-up 1 (N4.4, the audit's play pass: a raid left behind at Millford and then Aldmere's column
## waiting for good kept the HUD marker and the compass, so the main thread's leads never showed).
func test_an_event_left_behind_gives_the_tracker_back_until_it_is_in_play_again() -> void:
	_setup()
	QuestFixtures.install([QuestFixtures.quest("quest.test_fixup_main", [QuestFixtures.stage("go", QuestFixtures.flag_cond("test.never"))])])
	QuestFixtures.activate(["quest.test_fixup_main"], [], "quest.test_fixup_main")
	Quests.evaluate_now()
	assert_eq(Quests.tracked_id(), "quest.test_fixup_main", "the main quest leads")
	var raid: WorldEvent = _wd.events[F.RAID]
	WorldState.set_flag("p37.raid.on", true)
	_wd.check_events(Sim.tick)
	assert_true(raid.is_running(), "the raid starts by the giant")
	assert_eq(Quests.tracked_id(), F.RAID, "and takes the tracker")
	# The giant walks off east: the raid's centre unloads, its raiders go, the giant is beyond its radius.
	F.move_giant(_root, 96.0, 80.0)
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_true(raid.is_running() and not _wd.in_play(raid), "the raid runs on, left behind (%s)" % raid.state)
	assert_eq(Quests.tracked_quest_id, "", "it gave the tracker back (none was chosen before it)")
	assert_eq(Quests.tracked_id(), "quest.test_fixup_main", "so the main quest leads the marker and the compass")
	assert_true(Quests.active_quest_ids().has(F.RAID), "the raid stays in the tracker's list and the journal")
	# The player tracks it from the journal while it is far off: that choice is kept.
	assert_true(Quests.track(F.RAID), "the journal's Track")
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_id(), F.RAID, "the player's own choice stays while it is out of play")
	Quests.tracked_quest_id = ""
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_id(), "quest.test_fixup_main", "untracked again: the main quest leads")
	# Back by it: in play again, it takes the tracker again; its end gives it back.
	F.move_giant(_root, -96.0, 16.0)
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_true(_wd.in_play(raid), "the raid is in play again")
	assert_eq(Quests.tracked_id(), F.RAID, "and leads again")
	_wd.end_event(raid, WanderDirector.ABANDONED)
	assert_eq(Quests.tracked_id(), "quest.test_fixup_main", "its end gives the tracker back")


## M8 gate fix-up 1 (N4.4): Aldmere's column (abandon_after_s 0) resumed after a Continue far from the toll
## fort waited for good - its run never began, never ended and held the tracker. A column with a finite
## abandon_after_s left waiting with its centre unloaded is given up like a raid; the shipped column has one.
func test_a_column_left_waiting_far_off_is_given_up() -> void:
	assert_true(float(GameData.get_record("event.army_column").get("abandon_after_s", 0.0)) > 0.0,
		"the shipped army column is given up after a while (abandon_after_s)")
	F.install({F.COLUMN: {"abandon_after_s": 20}})
	var made := F.make(world, Vector3(96.0, 0.0, 80.0))
	_root = made[0]
	_wd = made[1]
	var column: WorldEvent = _wd.events[F.COLUMN]
	_wd.start_event(column)
	assert_eq(column.state, WorldEvent.WAITING, "far from its start the column waits (its attempt cannot begin)")
	for i in 19:
		_wd.update_event(column, 1.0)
	assert_true(column.is_running(), "19 s with its centre unloaded: still waiting")
	_wd.update_event(column, 1.0)
	assert_false(column.is_running(), "20 s: given up")
	assert_eq(_ended[_ended.size() - 1], [F.COLUMN, WanderDirector.ABANDONED], "with no outcome")
	assert_false(Quests.active_quest_ids().has(F.COLUMN), "and gone from the tracker")

