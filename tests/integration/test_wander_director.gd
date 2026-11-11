extends IntegrationSuite
## P37 (plan M6-M9 §2.13, §5.10, decision 27): the WanderDirector's wandering encounters on a tiny
## streamed level (tests/support/living_world_fixtures.gd: a road along z = 0, the ring of chunks around
## the giant loaded, a test table of the region whose entry copies a template of two soldiers, its
## distances 40-120 m):
##   * a copy stands on a road node within the table's distances of the giant, on loaded, ready ground
##     (never on a node whose chunk is not loaded), outside the camera's view, out of a settlement, and
##     never while every candidate is in view; the template itself is never active;
##   * the caps: max_active copies of the table at once, the director's budget for whole copies only, an
##     entry's stages, flags and conditions (a faction standing);
##   * the table's clock: an attempt when its interval has run out, the next 60-120 s later;
##   * a copy activates like a placed encounter: its members spawn at their offsets from the anchor with
##     their record's kill XP for the entry's first three spawns and none for the fourth, walk the road's
##     nodes near the anchor, and a member of a neutral faction spawns at peace;
##   * a copy leaves when the giant leaves it (its chunk unloads: nothing of it is saved) and, never
##     reached, after STALE_S.

const F := preload("res://tests/support/living_world_fixtures.gd")

var _root: WorldRoot
var _wd: WanderDirector


func after_each() -> void:
	F.reset()
	await super()


func _setup(extra := {}) -> void:
	F.install(extra)
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]


func _table(patch := {}) -> Dictionary:
	var t := GameData.get_record(F.TABLE).duplicate(true)
	TestFixtures.deep_merge(t, patch)
	return t


func _anchor(copy_id: String) -> Vector3:
	return _wd.director.p37_copy_info(copy_id).get("centre", Vector3.INF)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_a_wanderer_stands_on_loaded_ground_out_of_view_within_its_distances() -> void:
	_setup()
	var d := _wd.director
	var giant := _root.player().global_position
	assert_eq(d.encounter_state(F.PACK), "", "the template is never an encounter of its own")
	var anchors: Array = []
	for i in 6:
		var r := _wd.try_spawn(_table(), Sim.tick)
		assert_true(bool(r.ok), "spawn %d placed (%s)" % [i, r.reason])
		if not bool(r.ok):
			return
		var a := _anchor(str(r.copy))
		anchors.append(a)
		var dist := _flat(a, giant)
		assert_true(dist >= 40.0 and dist <= 120.0, "40-120 m from the giant (%.1f)" % dist)
		assert_true(a.x < 0.0 and absf(a.z) < 0.01, "on a road node of the loaded ground (%s)" % a)
		var info := d.p37_copy_info(str(r.copy))
		var basis := Basis(Vector3.UP, float(info.yaw))
		for id: String in (info.offsets as Dictionary):
			var at: Vector3 = a + basis * (info.offsets[id] as Vector3)
			assert_true(_root.streamer.is_ready(_root.chunk_at(at)), "%s stands on a ready chunk" % id)
		_wd.drop_copy(str(r.copy))
	assert_eq(int(WorldState.get_flag(WanderDirector.spawns_flag(F.TABLE, "pack"), 0)), 6, "every spawn counted")
	# Only the two road nodes beyond x = 0 (97 and 113 m away) remain: their chunks are not loaded.
	var far := _wd.try_spawn(_table({"min_distance_m": 90}), Sim.tick)
	assert_eq(far.reason, "no_place", "no wanderer on ground that is not loaded")
	# The camera's view: every candidate in view, none; only x <= -40 out of view, the one there.
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return true
	assert_eq(_wd.try_spawn(_table(), Sim.tick).reason, "no_place", "never in view")
	WanderDirector.view_probe = func(p: Vector3) -> bool: return p.x > -40.0
	var r := _wd.try_spawn(_table(), Sim.tick)
	assert_true(bool(r.ok), "out of view at x = -48")
	assert_near(_anchor(str(r.copy)).x, -48.0, 0.01, "the one node out of view and far enough")
	_wd.drop_copy(str(r.copy))
	# A settlement there keeps it away (its radius and 25 m).
	WorldIndex.for_level(F.LEVEL).pois["p37.poi.hamlet"] = {"position": F.ground(-52.0, 0.0), "radius": 4.0, "kind": "settlement",
		"region": F.REGION, "display_name": "Hamlet", "chunk": "c1_2", "min_stage": 0}
	assert_eq(_wd.try_spawn(_table(), Sim.tick).reason, "no_place", "never in a settlement")
	assert_true(int(_wd.refusals.get("no_place", 0)) >= 3, "the refusals are counted (%s)" % _wd.refusals)


func test_the_caps_the_budget_and_the_entries_filters() -> void:
	_setup()
	var d := _wd.director
	var one := _table({"max_active": 1})
	assert_true(bool(_wd.try_spawn(one, Sim.tick).ok), "the first copy")
	assert_eq(_wd.try_spawn(one, Sim.tick).reason, "cap", "max_active copies at once")
	assert_eq(_wd.live_copies_of(F.TABLE).size(), 1, "one live copy of the table")
	for id in _wd.copy_ids():
		_wd.drop_copy(id)
	var stage := _root.player().current_growth_stage()
	var later := _table()
	(later.entries[0] as Dictionary)["min_stage"] = stage + 1
	assert_eq(_wd.try_spawn(later, Sim.tick).reason, "no_entry", "an entry above the giant's stage")
	var standing := _table()
	(standing.entries[0] as Dictionary)["requires_flags"] = ["faction.p37.hostile"]
	assert_eq(_wd.try_spawn(standing, Sim.tick).reason, "no_entry", "an entry waiting for a hostile faction")
	WorldState.set_flag("faction.p37.hostile", true)
	assert_true(bool(_wd.try_spawn(standing, Sim.tick).ok), "and it comes once the faction is hostile")
	for id in _wd.copy_ids():
		_wd.drop_copy(id)
	d.max_active_enemies = 1
	assert_eq(_wd.try_spawn(_table(), Sim.tick).reason, "budget", "a copy comes whole or not at all (two soldiers, room for one)")
	d.max_active_enemies = 12
	# The table's clock: an attempt once its interval has run out, the next one 60-120 s later.
	_wd._table_state[F.TABLE] = {"next_tick": Sim.tick}
	_wd.check_tables(Sim.tick)
	assert_eq(_wd.copy_ids().size(), 1, "the table spawned when due")
	var next := int(_wd._table_state[F.TABLE].next_tick) - Sim.tick
	assert_true(next >= 60 * 60 and next <= 120 * 60, "the next attempt in 60-120 s (%d ticks)" % next)
	_wd.check_tables(Sim.tick + 1)
	assert_eq(_wd.copy_ids().size(), 1, "nothing before then")


func test_copies_spawn_with_decaying_kill_xp_and_leave_when_the_giant_leaves() -> void:
	_setup({F.PACK: {"spawns": [
		{"entity_id": "p37.pack_a", "definition": "enemy.soldier", "position_m": [-114.0, F.height(-114.0, 0.0), 0.0], "faction": "",
			"ai_enabled": false, "persist_death": false, "loot_table": ""},
		{"entity_id": "p37.pack_b", "definition": "enemy.soldier", "position_m": [-110.0, F.height(-110.0, 0.0), 0.0], "faction": "aldmere",
			"ai_enabled": false, "persist_death": false, "loot_table": ""}]}})
	var d := _wd.director
	var soldier_xp := int(GameData.get_record("enemy.soldier").xp_reward)
	var first := _wd.try_spawn(_table(), Sim.tick)
	assert_true(bool(first.ok), "a copy")
	await step_ticks(3)
	var members := d.p37_living(str(first.copy))
	assert_eq(members.size(), 2, "its two members spawned (%s)" % d.encounter_state(str(first.copy)))
	if members.size() != 2:
		return
	var anchor := _anchor(str(first.copy))
	for n: Node3D in members:
		var e := n as EnemyActor
		assert_true(e.entity.entity_id.ends_with(".1"), "%s carries the copy's suffix" % e.entity.entity_id)
		assert_eq(e.entity.combatant.xp_reward, soldier_xp, "%s pays its record's kill XP (first spawn)" % e.entity.entity_id)
		assert_true(_flat(n.global_position, anchor) < 4.0, "%s stands at its offset from the anchor" % e.entity.entity_id)
		assert_false(e.brain.patrol_points.is_empty(), "%s walks the road near its anchor" % e.entity.entity_id)
		for pt: Vector3 in e.brain.patrol_points:
			assert_true(_flat(pt, anchor) <= 20.0 + 16.0 + 3.0, "a patrol point within the table's patrol_m of the anchor (%s)" % pt)
	var neutral := members.filter(func(n: Node3D) -> bool: return (n as EnemyActor).faction == "aldmere")
	assert_eq(neutral.size(), 1, "one member of Aldmere")
	if neutral.size() == 1:
		assert_true((neutral[0] as EnemyActor).at_peace(), "a neutral faction's member spawns at peace")
		assert_eq((neutral[0] as EnemyActor).entity.team, CombatEntity.Team.NEUTRAL, "on the neutral team")
	var hostile := members.filter(func(n: Node3D) -> bool: return (n as EnemyActor).faction == "")
	if hostile.size() == 1:
		assert_eq((hostile[0] as EnemyActor).entity.team, CombatEntity.Team.ENEMY, "a factionless wanderer is hostile")
	_wd.drop_copy(str(first.copy))
	await step_ticks(1)
	WorldState.set_flag(WanderDirector.spawns_flag(F.TABLE, "pack"), 3)
	var fourth := _wd.try_spawn(_table(), Sim.tick)
	assert_true(bool(fourth.ok), "the entry's fourth copy")
	await step_ticks(3)
	for n: Node3D in d.p37_living(str(fourth.copy)):
		assert_eq((n as EnemyActor).entity.combatant.xp_reward, 0, "%s pays no kill XP (fourth spawn)" % (n as EnemyActor).entity.entity_id)
	assert_eq(float(_wd.spawn_log[_wd.spawn_log.size() - 1].xp_scale), 0.0, "logged with xp_scale 0")
	assert_eq(d.p37_living(str(fourth.copy)).size(), 2, "its members are there")
	_wd.drop_copy(str(fourth.copy))
	# The giant leaves: a copy standing in a chunk that unloads goes with its members, and is dropped.
	var near := _wd.try_spawn(_table({"min_distance_m": 10, "max_distance_m": 30}), Sim.tick)
	assert_true(bool(near.ok), "a copy in the giant's own chunk")
	await step_ticks(3)
	assert_eq(d.p37_living(str(near.copy)).size(), 2, "in the world")
	F.move_giant(_root, 96.0, 16.0)
	await step_ticks(2)
	assert_false(_root.streamer.is_loaded(d.encounter_chunk(str(near.copy))), "its chunk unloaded")
	assert_eq(d.encounter_state(str(near.copy)), EncounterDirector.DORMANT, "the director put it back (its members went with the chunk)")
	_wd._prune_copies(Sim.tick)
	assert_eq(d.encounter_state(str(near.copy)), "", "a wanderer the giant left is gone")
	assert_false(WorldState.is_killed("p37.pack_a.3"), "nothing of it is saved")
	# A copy the giant never reached goes after STALE_S.
	F.move_giant(_root, -96.0, 16.0)
	var stale := _wd.try_spawn(_table(), Sim.tick)
	assert_true(bool(stale.ok), "another copy (%s)" % stale.reason)
	_wd._prune_copies(Sim.tick + WanderDirector.seconds_to_ticks(WanderDirector.STALE_S) - 1)
	assert_ne_state(d, str(stale.copy))
	_wd._prune_copies(Sim.tick + WanderDirector.seconds_to_ticks(WanderDirector.STALE_S) + 1)
	assert_eq(d.encounter_state(str(stale.copy)), "", "a copy never reached is dropped after %d s" % int(WanderDirector.STALE_S))


func assert_ne_state(d: EncounterDirector, id: String) -> void:
	assert_eq(d.encounter_state(id), EncounterDirector.DORMANT, "not before STALE_S")
