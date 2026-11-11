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
##     encounters come back; an outcome already won stays.

const F := preload("res://tests/support/living_world_fixtures.gd")

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
