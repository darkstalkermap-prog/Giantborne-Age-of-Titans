extends IntegrationSuite
## M7 polish, lane B (AI, formations and navigation; the M7 gate review's findings and the gate's own
## follow-ups; the slow half on the real world is tests/slow/test_m7_polish_world.gd):
##   * a formation whose members all flee at the same moment while its banner lives is broken, not
##     routed for good: once they regroup (above ai.regroup_morale, their banner their leader) it forms
##     again and they hold their slots (they used to come back as loose soldiers - no brace, no slot -
##     under a formation stuck in "routed"); it still routs for good when every member routed, or when
##     none stands and its banner is dead;
##   * a civilian whose safe-point search stopped for the tick's path-query budget asks again at its
##     next decision - not after REPICK_S, as when nowhere is reachable - and the resumed search is the
##     same choice (picks counts choices); the world's half is in the slow suite (Brannock's folk);
##   * posts: a ranged unit spawned on an elevation marker its navmesh does not reach (a tower's top)
##     holds it - its firing point is the post without a search, its band is its shot's reach, it never
##     kicks, a flight leaves it there - and gives it up once it falls off; a unit on a marker the
##     navmesh reaches searches as before (the toll fort's tower archers on the real world: the slow suite);
##   * a streamed world's layer map keys its edges at its cell x 0.1 (NavMaps.MERGE_RASTERIZER_SCALE)
##     even with the engine's default cells (the human layer's 0.25 / 0.25, which Godot 4.6.3 left
##     keyed at 0.25 m): a sliver triangle between two vertices 5 cm apart merges without an edge error;
##     NavBake.edge_conflicts and weld_for_map key alike (the slow suite loads every chunk).

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	await super()


# --------------------------------------------------------------------------- formations: flight is not a rout

## A stage-4 giant at `pos` facing -Z (its profile set directly: the growth path is P05's and P26's).
func _stage_4_giant(pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	assert_eq(int(p.current_growth_stage()), 4, "a stage-4 giant")
	return p


## Three pikemen in one rank facing +Z at the origin and their banner behind them, AI on (the
## reviewer's probe), braced at 6 m and holding their ground (no advance).
func _rank_with_banner(id: String) -> Formation:
	var f := Formation.new()
	f.id = id
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.ranks = 1
	f.files = 3
	f.rank_spacing_m = 2.2
	f.file_spacing_m = 1.6
	f.brace_m = 6.0
	f.brace_action = "ability.formation_brace_pike"
	f.place(Vector3.ZERO, PI)
	Formation.register(f)
	for i in 3:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i) + Vector3(0, 0.05, 0), "%s_%d" % [id, i], true, PI), i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT) + Vector3(0, 0.05, 0),
		"%s_banner" % id, true, PI))
	return f


## Steps `ticks` ticks with the formation updated ten times a second, as the director does; returns
## every state it passed through.
func _run(f: Formation, threat: Node3D, ticks: int) -> Array[String]:
	var seen: Array[String] = []
	for i in ticks:
		await step_ticks(1)
		if Sim.tick % Formation.UPDATE_TICKS == 0:
			f.update(Sim.tick, threat)
			if seen.is_empty() or seen[-1] != f.state:
				seen.append(f.state)
	return seen


func _states(f: Formation) -> String:
	var out := PackedStringArray()
	for m in f.members:
		out.append("%s %s morale %.0f hold %s" % [m.entity_id.get_slice(".", 2), m.brain.state_name(), m.brain.morale,
			m.brain.formation_hold])
	return ", ".join(out)


func test_a_formation_whose_members_all_flee_at_once_regroups_to_its_slots_while_its_banner_lives() -> void:
	var p := _stage_4_giant(Vector3(0, 0.05, 14.0))   # 13 m before the rank: aware, not braced
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var f := _rank_with_banner("test.polish.regroup")
	await _run(f, p, 60)
	assert_true(f.is_intact() and f.aware, "the rank stands and knows the giant (%s, %s)" % [f.state, _states(f)])
	# every member drops to 15 at once (two Titan Roars at x1.5 can do that at stage 5)
	for m in f.members:
		m.brain.apply_morale(15.0 - m.brain.morale, "script", Sim.tick)
	var during := await _run(f, p, 30)
	var fled := 0
	for m in f.members:
		if m.brain.state == EnemyBrain.AIState.FLEE:
			fled += 1
	assert_eq(fled, 3, "all three fled at once (%s)" % _states(f))
	assert_true(f.banner_alive(), "their banner lives")
	assert_false(during.has("routed"), "a formation whose members only fled, its banner alive, is not routed (%s)" % [during])
	assert_eq(f.state, "broken", "it is broken while they flee")
	# their morale comes back (+60): past ai.regroup_morale, with the banner to lead them, they regroup
	for m in f.members:
		m.brain.apply_morale(60.0, "rally", Sim.tick)
	var after := await _run(f, p, int(EnemyBrain.MIN_FLEE_S * Sim.TICK_RATE) + 60)
	assert_false(after.has("routed"), "never routed (%s)" % [after])
	assert_true(f.is_intact(), "the formation formed again once they regrouped (%s; %s)" % [f.state, _states(f)])
	for m in f.members:
		assert_true(m.brain.formation_hold, "%s holds its slot again (%s)" % [m.entity_id, _states(f)])
		assert_eq(m.brain.state, EnemyBrain.AIState.HOLD, "%s stands in its slot (%s)" % [m.entity_id, m.brain.state_name()])
	# routed for good: every member routed (a routed unit never regroups), though the banner stands
	for m in f.members:
		m.p30_force_rout()
	await _run(f, p, 12)
	assert_eq(f.state, "routed", "every member routed: routed, though the banner stands")
	assert_true(f.banner_alive(), "(the banner still stands)")


func test_a_formation_whose_banner_fell_routs_when_none_stands() -> void:
	var p := _stage_4_giant(Vector3(0, 0.05, 14.0))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var f := _rank_with_banner("test.polish.leaderless")
	await _run(f, p, 30)
	queue_hit(p.entity.entity_id, f.banner.entity_id, p.global_position, 100000.0)
	await step_ticks(1)
	assert_false(f.banner_alive(), "the banner fell")
	for m in f.members:
		m.brain.apply_morale(15.0 - m.brain.morale, "script", Sim.tick)
	var seen := await _run(f, p, 30)
	var fleeing := 0
	for m in f.members:
		if m.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]:
			fleeing += 1
	assert_eq(fleeing, 3, "all three fled (%s)" % _states(f))
	assert_true(seen.has("routed") and f.state == "routed", "none stands and no banner leads them back: routed (%s)" % [seen])


# --------------------------------------------------------------------------- civilians: a search waits for the budget

func test_a_civilians_safe_point_search_that_waits_for_the_budget_resumes_as_the_same_choice() -> void:
	var b := CivilianBrain.new("test.polish.villager", GameData.get_record("npc.villager"))
	var calls: Array = []
	b.safe_resolver = func(_from: Vector3, skip_failed: bool) -> Vector3:
		calls.append(skip_failed)
		if calls.size() < 3:
			b.nav_search_pending = true   # the actor's search stopped for the tick's budget
			return Vector3.INF
		return Vector3(10, 0, 0)
	b.start_fleeing("hostile")
	b.decide(6, Vector3.ZERO, true)
	assert_true(b.nav_search_pending and b.destination == Vector3.INF, "the search waits for the budget")
	assert_eq(b.move_target, Vector3.INF, "standing meanwhile")
	b.decide(7, Vector3.ZERO, true)   # the actor decides again the next tick while a search waits
	assert_eq(calls.size(), 2, "it resumes at once, not REPICK_S later")
	b.decide(8, Vector3.ZERO, true)
	assert_eq(b.destination, Vector3(10, 0, 0), "and finds its shelter")
	assert_false(b.nav_search_pending, "nothing waits any more")
	assert_eq(b.picks, 1, "one choice, though it took three ticks")
	assert_eq(calls, [false, false, false], "the same search, never a skip")
	b.on_path_failed(Vector3(4, 0, 0))
	assert_eq(b.picks, 2, "a path failure is a new choice")
	assert_eq(calls[-1], true, "skipping the failed shelter")
	b.safe_resolver = Callable()   # the resolver holds the brain: break the cycle


# --------------------------------------------------------------------------- the layer maps' edge keys

## Two triangles joined by a sliver whose two near vertices (B and B', 5 cm apart) share a 0.25 m
## cell: four edges on one key at 0.25 m, two keys of two edges at 0.025 m (the human meshes of c4_1,
## c4_2, c5_2 and c6_6 had this, about 5-7 cm).
static func _sliver_mesh() -> NavigationMesh:
	var nm := NavBake.new_mesh(NavBake.spec_for(1))
	nm.set_vertices(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0.05), Vector3(0, 0, 2),
		Vector3(2, 0, 2)]))
	nm.add_polygon(PackedInt32Array([0, 1, 3]))
	nm.add_polygon(PackedInt32Array([1, 2, 3]))
	nm.add_polygon(PackedInt32Array([2, 4, 3]))
	return nm


func test_a_layer_map_keys_its_edges_at_a_tenth_of_its_cell_so_a_sliver_merges_cleanly() -> void:
	var nm := _sliver_mesh()
	assert_near(nm.cell_size, 0.25, 1e-6, "the human layer's cells are the engine's defaults (0.25)")
	assert_near(nm.cell_height, 0.25, 1e-6, "(0.25 high)")
	var cell := NavBake.merge_cell(nm)
	assert_near(cell.x, 0.025, 1e-6, "the map's merge cell is the cell x 0.1")
	assert_eq(NavBake.edge_conflicts(nm, Vector3.ZERO), [], "no edge key shared by more than two edges at 0.025 m")
	var copy := nm.duplicate(true) as NavigationMesh
	assert_eq(NavBake.weld_for_map(copy, Vector3.ZERO), 0, "nothing to weld at 0.025 m: the bake keeps its bytes")
	# the old keying (0.25 m cells) saw the two vertices as one point: four edges on one key
	var coarse := {}
	for p in nm.get_polygon_count():
		var poly := nm.get_polygon(p)
		for e in poly.size():
			var ka := Vector3i((nm.get_vertices()[poly[e]] / 0.25).floor())
			var kb := Vector3i((nm.get_vertices()[poly[(e + 1) % poly.size()]] / 0.25).floor())
			var ks := str([ka, kb]) if str(ka) < str(kb) else str([kb, ka])
			coarse[ks] = int(coarse.get(ks, 0)) + 1
	assert_eq(coarse.values().max(), 4, "in 0.25 m cells four edges shared one key (the review's edge errors)")
	# the runtime: a map NavMaps set up merges it without an edge error
	var log := NavEdgeLog.new()
	OS.add_logger(log)
	var maps := NavMaps.new()
	maps.setup([1], [], 16, true)
	maps.add_region("test.sliver", 1, nm, Transform3D(Basis(), Vector3(512.0, 10.0, -768.0)))
	for i in 3:
		await step_ticks(1)
	assert_true(maps.chunk_ready("test.sliver"), "the region synced")
	OS.remove_logger(log)
	assert_eq(log.edge_errors(), 0, "a NavMaps layer map merges the sliver without an edge error")
	maps.free_all()


# --------------------------------------------------------------------------- posts: ranged units hold a tower

const ARCHER := "res://scenes/enemies/archer.tscn"


## A 60 x 60 m navmesh floor (two triangles at y 0.35) on the test world's default map.
func _floor_navmesh() -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.set_vertices(PackedVector3Array([Vector3(-30, 0.35, -30), Vector3(30, 0.35, -30), Vector3(30, 0.35, 30),
		Vector3(-30, 0.35, 30)]))
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	region.navigation_layers = 1
	world.add_child(region)
	return region


func _elevation_marker(at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = at
	world.add_child(m)
	m.add_to_group(EnemyActor.ELEVATION_GROUP)
	return m


func test_a_ranged_unit_spawned_on_a_tower_top_holds_it_as_its_post() -> void:
	_floor_navmesh()
	add_box(Vector3(3, 8, 3), Vector3(10, 4, 0))   # a tower: a solid the navmesh does not cover
	var top := _elevation_marker(Vector3(10, 8.2, 0))
	var ground := _elevation_marker(Vector3(-10, 0.4, 0))   # a marker the navmesh reaches
	spawn_player(Vector3(10, 0.05, 20), PI)
	add_box(Vector3(3, 8, 3), Vector3(0, 4, -15))   # a second tower, a swordsman on its top
	_elevation_marker(Vector3(0, 8.2, -15))
	var on_tower := TestSpawn.enemy(world, ARCHER, Vector3(10, 8.05, 0), "test.polish.tower_archer", false)
	var on_ground := TestSpawn.enemy(world, ARCHER, Vector3(-10, 0.05, 0), "test.polish.ground_archer", false)
	var swordsman := TestSpawn.enemy(world, SOLDIER, Vector3(0, 8.05, -15), "test.polish.tower_soldier", false)
	for i in 4:
		await step_ticks(1)
	assert_true(on_tower.holds_post(), "the archer on the tower's top holds it as its post (one closest-point check)")
	assert_eq(on_tower.post_marker(), top, "the marker it spawned on")
	assert_false(on_ground.holds_post(), "a marker the navmesh reaches is no post: it searches as before")
	assert_true(on_ground.post_marker() == null and on_ground.brain.post_band == Vector2.ZERO, "(no post band)")
	assert_false(swordsman.holds_post(), "a unit without a shot holds no post, even on a tower's top")
	assert_eq(swordsman.brain.post_band, Vector2.ZERO, "(no post band for it either)")
	var reach := float(GameData.get_record("ability.archer_shot").get("ai_max_range_m", 0.0))
	assert_eq(on_tower.brain.post_band, Vector2(0.0, reach), "its band: anything its shot reaches (%.0f m)" % reach)
	assert_eq(on_tower.brain.ranged_band(true), on_tower.brain.post_band, "outmatched or not")
	# its firing point is the post, without a query
	var q0 := NavQuery.queries_total
	var target := Vector3(10, 0.05, 20)
	var fp: Vector3 = on_tower.brain.firing_point_resolver.call(on_tower.global_position, target,
		on_tower.brain.ranged_band(true), 10.0, false)
	assert_eq(fp, top.global_position, "the resolver gives the post")
	assert_eq(NavQuery.queries_total - q0, 0, "and asks the navigation nothing")
	assert_eq(str(top.get_meta(EnemyActor.FIRING_POINT_META, "")), on_tower.entity_id, "the post is claimed")
	# a flight leaves it cowering on its post (an agent off the navmesh would path from the ground below)
	var flee: Vector3 = on_tower.brain.flee_resolver.call(on_tower.global_position, target, 12.0)
	assert_eq(flee, Vector3.INF, "nowhere to run from its post: it stands there")
	assert_true(on_ground.brain.flee_resolver.call(on_ground.global_position, target, 12.0) != Vector3.INF,
		"the one on the ground flees as before")
	# the brain keeps the post whatever the target does, and never kicks from it
	on_tower.brain.firing_point = fp
	on_tower.brain.perception = {"exists": true, "alive": true, "visible": true, "position": target, "distance": 0.5,
		"target_radius": 2.2, "facing_deg": 0.0}
	assert_eq(on_tower.brain.call("_close_attack_for", 0.1), "ability.archer_kick", "(the kick fits the range...)")
	on_tower.brain.aware = true
	on_tower.brain.state = EnemyBrain.AIState.APPROACH
	on_tower.brain.call("_decide_ranged", on_tower.global_position, target, 0.5, true, true, true, func() -> bool: return true,
		func() -> void: pass, true, false)
	assert_true(on_tower.brain.attack_request != "ability.archer_kick", "(...but never from a post: %s)" % on_tower.brain.attack_request)
	assert_eq(on_tower.brain.firing_point, top.global_position, "and it holds the post")
	# a unit that falls off gives the post up and fights as any other
	on_tower.global_position = Vector3(12, 0.05, 3)
	assert_false(on_tower.holds_post(), "fallen off its tower: no post")
	assert_eq(on_tower.brain.post_band, Vector2.ZERO, "its band is its own again")
	assert_false(top.has_meta(EnemyActor.FIRING_POINT_META), "the post is free again")
	assert_eq(on_tower.brain.firing_point, Vector3.INF, "and it looks for a firing point afresh")
