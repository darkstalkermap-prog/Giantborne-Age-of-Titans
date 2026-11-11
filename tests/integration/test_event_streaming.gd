extends IntegrationSuite
## P37 (plan M6-M9 §2.13 "streaming rules", decision 27): world events and the streamed world on a tiny
## level (tests/support/living_world_fixtures.gd; TinyWorld unloads chunks three or more from the giant's):
##   * a raid's clock runs only while its centre chunk is loaded and ready: unloaded it is suspended (its
##     copies leave the world with the chunk), loaded again it resumes where it stopped; unloaded for
##     abandon_after_s it is given up with no outcome; its fail timer (loaded time only) ends it;
##   * a column marches as a point on its route whatever is loaded: it is in the world only while that
##     point lies on loaded, ready ground (despawned back into the abstract when it leaves it, spawned
##     again where it has walked to when it comes back) and ends with its end outcome when it comes home;
##   * across a reload (a death, a travel) a running event is carried: a respawn within 120 m of it is
##     refused and moves to another checkpoint, the new level resumes it (a death from the start of its
##     attempt, its run kept), and the title or a new game forget it;
##   * M8 gate (F19): a run the save holds in progress survives a save, a quit to the title and a continue:
##     the next load resumes it (its run counted once, its abandonment clock from the save) and it ends
##     with its outcome; M8 gate (F12): fail.within_m runs the fail timer only while the giant is near.

const F := preload("res://tests/support/living_world_fixtures.gd")

var _root: WorldRoot
var _wd: WanderDirector
var _ended: Array = []


func before_each() -> void:
	await super()
	_ended.clear()
	Events.world_event_ended.connect(_on_event_ended)


func after_each() -> void:
	if Events.world_event_ended.is_connected(_on_event_ended):
		Events.world_event_ended.disconnect(_on_event_ended)
	F.reset()
	await super()


func _on_event_ended(_t: int, id: String, outcome: String) -> void:
	_ended.append([id, outcome])


func _setup(extra := {}) -> void:
	F.install(extra)
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]


func test_a_raids_clock_stops_while_its_centre_is_unloaded() -> void:
	_setup({F.RAID: {"fail": {"timer_s": 30}}})
	var raid: WorldEvent = _wd.events[F.RAID]
	var d := _wd.director
	_wd.start_event(raid)
	await step_ticks(3)
	var copy := raid.copies[0]
	assert_eq(d.encounter_state(copy), EncounterDirector.ACTIVE, "its raiders in the world")
	for i in 5:
		_wd.update_event(raid, 1.0)
	assert_near(raid.elapsed_s, 5.0, 0.3, "its clock runs while its centre is loaded (%.1f s)" % raid.elapsed_s)
	var before := raid.elapsed_s
	F.move_giant(_root, 96.0, 16.0)
	await step_ticks(2)
	assert_false(_root.streamer.is_loaded(_root.chunk_at(raid.centre)), "its centre chunk unloaded")
	assert_eq(d.encounter_state(copy), EncounterDirector.DORMANT, "its raiders left the world with the chunk")
	for i in 10:
		_wd.update_event(raid, 1.0)
	assert_eq(raid.state, WorldEvent.SUSPENDED, "suspended")
	assert_eq(raid.elapsed_s, before, "its clock stopped")
	assert_near(raid.unloaded_s, 10.0, 0.3, "it counts the time unloaded (%.1f s)" % raid.unloaded_s)
	assert_true(raid.is_running(), "still running")
	F.move_giant(_root, -96.0, 16.0)
	_wd.update_event(raid, 1.0)
	assert_eq(raid.state, WorldEvent.RUNNING, "it resumes once its centre is loaded")
	assert_near(raid.elapsed_s, before + 1.0, 1e-4, "where its clock stopped")
	assert_eq(raid.unloaded_s, 0.0, "the unloaded count starts again")
	await step_ticks(3)
	assert_eq(d.encounter_state(copy), EncounterDirector.ACTIVE, "its raiders came back")
	for i in 23:
		_wd.update_event(raid, 1.0)
	assert_true(raid.is_running(), "29 s of loaded time: still running")
	_wd.update_event(raid, 1.0)
	assert_false(raid.is_running(), "its fail timer ran out at 30 s of loaded time")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "fell"], "with its fail outcome")
	# Abandoned: unloaded for abandon_after_s (20 s here).
	_wd.start_event(raid)
	F.move_giant(_root, 96.0, 16.0)
	for i in 19:
		_wd.update_event(raid, 1.0)
	assert_true(raid.is_running(), "19 s unloaded: still waiting")
	_wd.update_event(raid, 1.0)
	assert_false(raid.is_running(), "20 s: given up")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, WanderDirector.ABANDONED], "with no outcome")
	assert_eq(WorldState.get_flag("event.p37_raid.outcome"), "fell", "the outcome won before stays")


func test_a_column_marches_unloaded_and_is_in_the_world_only_on_loaded_ground() -> void:
	_setup()
	var column: WorldEvent = _wd.events[F.COLUMN]
	var d := _wd.director
	WorldState.set_flag("p37.column.on", true)
	_wd.check_events(Sim.tick)
	assert_eq(_wd.running_event(), column, "the column starts near the giant")
	assert_true(column.route != null and column.route.round_trip, "on its round trip")
	assert_near(column.route.start, 0.0, 1e-3, "formed up at its centre, the road's west end")
	await step_ticks(3)
	var copy := column.copies[0]
	assert_eq(d.encounter_state(copy), EncounterDirector.ACTIVE, "in the world on loaded ground")
	assert_eq(d.p37_living(copy).size(), 2, "its two marchers")
	var states := {}
	var unloaded_steps := 0
	var spawned_unloaded := 0
	var came_back := false
	var was_out := false
	for i in 80:
		_wd.update_event(column, 0.25)   # 10 m a step at 40 m/s
		await step_ticks(1)
		if not column.is_running():
			break
		var p := column.route.point_at()
		var loaded := _root.streamer.is_ready(_root.chunk_at(p))
		var st := d.encounter_state(copy)
		states[st] = true
		if not loaded:
			unloaded_steps += 1
			was_out = true
			if not d.p37_living(copy).is_empty():
				spawned_unloaded += 1
		elif was_out and not came_back and st == EncounterDirector.ACTIVE and not d.p37_living(copy).is_empty():
			came_back = true
			var near := false
			for n: Node3D in d.p37_living(copy):   # (its marchers' AI is off here: they stand where they came)
				near = near or Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 25.0
			assert_true(near, "it came back where it had walked to (%s)" % p)
	assert_true(unloaded_steps > 10, "it marched on while its point was on ground that is not loaded (%d steps)" % unloaded_steps)
	assert_eq(spawned_unloaded, 0, "never in the world there")
	assert_true(states.has(EncounterDirector.DORMANT), "despawned back into the abstract")
	assert_true(came_back, "and back in the world when its point came onto loaded ground")
	assert_false(column.is_running(), "it came home")
	assert_eq(_ended[_ended.size() - 1], [F.COLUMN, "passed"], "with its end outcome")
	assert_eq(WorldState.get_flag("event.p37_column.outcome"), "passed", "recorded")
	await step_ticks(2)
	assert_eq(d.encounter_state(copy), "", "out of view, it left the world")


func test_a_carried_event_moves_the_respawn_and_resumes_after_the_reload() -> void:
	_setup()
	var raid: WorldEvent = _wd.events[F.RAID]
	_wd.start_event(raid)
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "a run")
	GameSession.level_override = F.LEVEL
	GameSession.respawn_id = F.NEAR_CP
	Events.entity_died.emit(Sim.tick, _root.player().entity.entity_id, "")   # the giant dies near it
	assert_true(WanderDirector.is_carried(F.LEVEL, F.RAID), "carried across the reload")
	_root.free()
	assert_false(Quests.active_quest_ids().has(F.RAID), "the level left: no objective until it comes back")
	assert_true(WanderDirector.respawn_refusal(F.NEAR_CP).contains("raid"), "a respawn near it is refused (%s)" % WanderDirector.respawn_refusal(F.NEAR_CP))
	assert_eq(WanderDirector.respawn_refusal(F.FAR_CP), "", "the far stone is not")
	WorldState.set_flag("event.p37_raid.runs", 0)   # the reload rolled the world back to before it started
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]
	assert_eq(GameSession.respawn_checkpoint(), F.FAR_CP, "the reloaded level's respawn moves away from it")
	raid = _wd.events[F.RAID]
	assert_eq(raid.state, WorldEvent.WAITING, "the new level resumes it")
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "the same run (counted once)")
	assert_true(Quests.active_quest_ids().has(F.RAID), "its objective is back")
	await step_ticks(WanderDirector.UPDATE_TICKS + 4)
	assert_eq(raid.state, WorldEvent.RUNNING, "its attempt began again")
	assert_eq(raid.copies.size(), 1, "its raiders are back")
	Events.mode_change_requested.emit("title", {})
	assert_false(WanderDirector.is_carried(F.LEVEL, F.RAID), "the title forgets it")
	assert_eq(WanderDirector.respawn_refusal(F.NEAR_CP), "", "no respawn is refused then")


# --------------------------------------------------------------------------- M8 gate (F19, F12)

## Kills every living member of the event's copies.
func _defeat(e: WorldEvent) -> void:
	for id in e.copies:
		for n: Node3D in _wd.director.p37_living(id):
			var en := (n as EnemyActor).entity
			en.combatant.pools.health = 0.0
			en.combatant.dead = true
			Events.entity_died.emit(Sim.tick, en.entity_id, "")


func test_a_running_event_survives_a_save_and_a_continue() -> void:
	_setup()
	var raid: WorldEvent = _wd.events[F.RAID]
	_wd.start_event(raid)
	await step_ticks(3)
	# the giant leaves it: 6 s of play with its centre unloaded (the director's own updates)
	F.move_giant(_root, 96.0, 16.0)
	await step_ticks(60 * 6)
	assert_eq(raid.state, WorldEvent.SUSPENDED, "left behind: suspended")
	var away := raid.unloaded_s
	assert_true(away > 4.0, "its abandonment clock runs (%.1f s)" % away)
	# a checkpoint saves the world as it is; quit to the title; continue
	var saved := WorldState.to_save_dict()
	Events.mode_change_requested.emit("title", {})
	_root.free()
	WorldState.clear()
	WorldState.from_save_dict(saved)
	Events.mode_change_requested.emit("continue", {})
	assert_false(WanderDirector.is_carried(F.LEVEL, F.RAID), "the continue carries nothing")
	var made := F.make(world, Vector3(96.0, 0.0, 16.0))
	_root = made[0]
	_wd = made[1]
	raid = _wd.events[F.RAID]
	assert_eq(raid.state, WorldEvent.WAITING, "the saved run in progress is resumed")
	assert_eq(int(WorldState.get_flag("event.p37_raid.runs", 0)), 1, "its run counted once")
	assert_near(raid.unloaded_s, away, 1.0, "its abandonment clock from the save (%.1f s)" % raid.unloaded_s)
	assert_true(Quests.active_quest_ids().has(F.RAID), "its objective is back in the tracker")
	assert_true(WanderDirector.is_carried(F.LEVEL, F.RAID), "and carried for the deaths that follow")
	# the giant comes back: its attempt begins and it can end with an outcome
	F.move_giant(_root, -96.0, 16.0)
	await step_ticks(WanderDirector.UPDATE_TICKS + 4)
	assert_eq(raid.state, WorldEvent.RUNNING, "its attempt began again")
	assert_eq(raid.copies.size(), 1, "its raiders are back")
	await step_ticks(3)
	_defeat(raid)
	_wd.update_event(raid, 0.1)
	assert_false(raid.is_running(), "it ends")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "defended"], "with its outcome")
	assert_eq(WorldState.get_flag("event.p37_raid.outcome"), "defended", "written: nothing is lost")


func test_a_fail_timer_with_within_m_runs_only_while_the_giant_is_near() -> void:
	_setup({F.RAID: {"fail": {"timer_s": 10, "within_m": 60}}})
	var raid: WorldEvent = _wd.events[F.RAID]
	_wd.start_event(raid)
	await step_ticks(3)
	for i in 5:
		_wd.update_event(raid, 1.0)
	assert_near(raid.elapsed_s, 5.0, 0.3, "near its centre its clock runs (%.1f s)" % raid.elapsed_s)
	# 80 m off: its centre still loaded (running), the giant beyond within_m
	F.move_giant(_root, -40.0, 50.0)
	await step_ticks(2)
	assert_true(_root.streamer.is_ready(_root.chunk_at(raid.centre)), "its centre is still loaded")
	for i in 20:
		if not raid.is_running():
			break
		_wd.update_event(raid, 1.0)
	assert_eq(_ended, [], "20 s far from it: it never ended")
	assert_eq(raid.state, WorldEvent.RUNNING, "it runs")
	assert_near(raid.elapsed_s, 5.0, 0.3, "but its fail clock pauses beyond within_m (%.1f s)" % raid.elapsed_s)
	F.move_giant(_root, -96.0, 16.0)
	for i in 5:
		if raid.is_running():
			_wd.update_event(raid, 1.0)
	assert_false(raid.is_running(), "back near it, the timer runs out at 10 s")
	assert_eq(_ended[_ended.size() - 1], [F.RAID, "fell"], "with its fail outcome")
