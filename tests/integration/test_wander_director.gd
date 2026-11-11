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
##     reached, after STALE_S;
##   * M8 gate (F18): a wanderer stands only on a node of a road's own polyline open to every stage - never
##     on a place's connector, the layout's extra edges or a stage-limited edge, nor by a checkpoint - and
##     neither stands nor walks inside a sealed place; every member's body must stand clear of static and
##     prop geometry (a node with a rock on it is refused).
##   * M8 gate fix-up 1 (N3.3): an engaged battle's reservation (EncounterDirector.p34_reserve: room in the
##     caps for its units still to come) is not room for a wanderer - no copy is admitted beside it, nor its
##     entry's spawn counted - and a moving column's copy is held back meanwhile; once released, copies come.

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
	# The director's own check (every CHECK_TICKS of Sim.tick) drops a copy the giant left: the two ticks
	# below must not hold one, or the put-back state is gone before it is read (whether they did hung on
	# the ticks every earlier suite ran).
	while (Sim.tick + 1) % WanderDirector.CHECK_TICKS == 0 or (Sim.tick + 2) % WanderDirector.CHECK_TICKS == 0:
		await step_ticks(1)
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


# --------------------------------------------------------------------------- M8 gate (F18)

func test_wanderers_stand_on_open_roads_clear_of_places_and_solids() -> void:
	_setup()
	var idx := WorldIndex.for_level(F.LEVEL)
	var road_count := idx.road_nodes().size()
	# a place's connector off the road at x = -64, the layout's extra edge on to a pocket, a stage-6 road
	idx.add_road(F.ground(-64.0, 0.0), F.ground(-64.0, -40.0), 10.0, 0, WorldIndex.ANY_STAGE, false, 0.5, WorldIndex.ROAD_KIND_CONNECTOR)
	idx.add_road(F.ground(-64.0, -40.0), F.ground(-80.0, -56.0), 5.0, 0, 4, true, 0.5, WorldIndex.ROAD_KIND_EXTRA)
	idx.add_road(F.ground(-32.0, 0.0), F.ground(-32.0, 40.0), 60.0, 6)
	# a waystone by the road at x = 16, a sealed place over its east end
	idx.checkpoints["p37.cp.mid"] = {"position": F.ground(16.0, 6.0), "yaw": 0.0, "display_name": "Mid stone", "kind": "waystone",
		"chunk": "c2_2", "fast_travel": true, "requires_flags": PackedStringArray(), "region": F.REGION, "district": "", "max_stage": 10}
	idx.pois["p37.poi.vault"] = {"position": F.ground(104.0, 0.0), "radius": 10.0, "kind": "secret", "region": F.REGION,
		"display_name": "Vault", "chunk": "c3_2", "min_stage": 5}
	_wd.refresh()
	var nodes := idx.road_nodes()
	var xs := []
	for i: int in _wd.anchor_nodes(F.REGION):
		assert_true(i < road_count, "only the road's own nodes are anchors (node %d at %s)" % [i, nodes[i]])
		xs.append(snappedf(nodes[i].x, 0.5))
	for x: float in [0.0, 16.0, 32.0]:
		assert_false(xs.has(x), "not by the waystone (within %.0f m): x = %.0f" % [WanderDirector.PLACE_CLEAR_M, x])
	for x: float in [96.0, 112.0]:
		assert_false(xs.has(x), "not in the sealed place (its radius + %.0f m): x = %.0f" % [WanderDirector.SEALED_MARGIN_M, x])
	for x: float in [-112.0, -64.0, -32.0, 48.0, 80.0]:
		assert_true(xs.has(x), "the road's node at x = %.0f is an anchor (a connector or a stage-6 road may leave it)" % x)
	var east := _wd.patrol_points(idx.nearest_road_node(F.ground(80.0, 0.0)), 40.0, F.ground(80.0, 0.0))
	assert_false(east.is_empty(), "a patrol from x = 80")
	for q: Vector3 in east:
		assert_true(q.x < 90.0, "no patrol walks into the sealed place (%s)" % q)
	var west := _wd.patrol_points(idx.nearest_road_node(F.ground(-64.0, 0.0)), 40.0, F.ground(-64.0, 0.0))
	assert_false(west.is_empty(), "a patrol from x = -64")
	for q: Vector3 in west:
		assert_true(absf(q.z) < 0.01, "a patrol keeps to the road, not the connector, the extra edge or the stage-6 road (%s)" % q)
	# a rock where a member would stand (the node at x = -96; every other rule holds there): refused
	var tpl := GameData.get_record(F.PACK)
	var at := F.ground(-96.0, 0.0)
	var pts := WanderDirector.footprint(tpl, at, _wd.road_yaw(idx.nearest_road_node(at)))
	assert_eq(_wd.footprint_problem(tpl, at, pts), "", "a clear road node fits")
	var rock := add_box(Vector3(2, 3, 2), F.ground(pts[0].x, pts[0].z) + Vector3(0, 1.5, 0))
	await step_ticks(2)
	assert_eq(_wd.footprint_problem(tpl, at, pts), "body:p37.pack_a", "a member would stand in the rock: refused")
	rock.queue_free()


## A placed encounter of `n` counted soldiers that stays dormant (its flag is never set): the battle's
## units still to come, whose room an engaged battle reserves.
func _battle_record(id: String, n: int) -> Dictionary:
	var spawns: Array = []
	for i in n:
		var x := 100.0 + float(i)
		spawns.append({"entity_id": "%s.unit_%d" % [id, i], "definition": "enemy.soldier", "position_m": [x, F.height(x, 100.0), 100.0],
			"yaw_deg": 0, "patrol": "", "faction": "", "commander": false, "ai_enabled": false, "persist_death": false, "loot_table": ""})
	return {"schema_version": 1, "id": id, "type": "encounter", "level": F.LEVEL,
		"center_m": [100.0, F.height(100.0, 100.0), 100.0], "activate_radius_m": 10, "deactivate_radius_m": 20,
		"leash_radius_m": 40, "alert_group": true, "requires_flags": ["test.never"], "forbids_flags": [],
		"counts_toward_budget": true, "spawns": spawns}


func test_a_battles_reserved_room_admits_no_wanderer_and_holds_a_column() -> void:
	F.install()
	TestFixtures.record_override("encounter.test_battle", _battle_record("encounter.test_battle", 11))
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]
	var d := _wd.director
	await step_ticks(3)
	assert_eq(d.max_active_enemies, 12, "the tiny level's cap")
	var ids: Array = []
	for i in 11:
		ids.append("encounter.test_battle.unit_%d" % i)
	d.p34_reserve("battle.test", ids)   # BattleBoss.engage reserves its plan's room
	assert_eq(d.p34_reserved_room(false), 11, "11 counted units still to come")
	assert_true(_wd.battle_holds_room(), "a battle holds room")
	var flag := WanderDirector.spawns_flag(F.TABLE, "pack")
	var before := int(WorldState.get_flag(flag, 0))
	assert_false(_wd.budget_allows(GameData.get_record(F.PACK)), "two soldiers do not fit beside the 11 reserved (cap 12)")
	var r := _wd.try_spawn(GameData.get_record(F.TABLE))
	assert_eq(str(r.reason), "budget", "no copy is admitted (%s)" % [r])
	assert_eq(int(WorldState.get_flag(flag, 0)), before, "and the entry's spawn is not counted")
	# A moving column's copy out of the world is held back while the battle waits for its units.
	var column: WorldEvent = _wd.events[F.COLUMN]
	_wd.start_event(column)
	var copy := str(column.copies[0]) if not column.copies.is_empty() else ""
	if copy != "":
		var at := _anchor(copy)
		d.p37_deactivate(copy)
		for i in 5:
			_wd.update_event(column, 1.0)
		assert_true(_anchor(copy).is_equal_approx(at), "the column's copy stays where it was (%s -> %s)" % [at, _anchor(copy)])
		_wd.end_event(column, WanderDirector.ABANDONED)
	# Released (the battle ended): copies come again.
	d.p34_release("battle.test")
	assert_false(_wd.battle_holds_room(), "no battle holds room")
	assert_true(_wd.budget_allows(GameData.get_record(F.PACK)), "two soldiers fit")
	assert_true(bool(_wd.try_spawn(GameData.get_record(F.TABLE)).ok), "a copy is admitted")
	assert_eq(int(WorldState.get_flag(flag, 0)), before + 1, "and counted")

