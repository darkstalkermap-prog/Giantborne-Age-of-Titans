extends IntegrationSuite
## P37 on the real world (scenes/world/world.tscn, deterministic streaming; the living world switched on as
## in the campaign; plan M6-M9 §2.13, §5.10):
##   * the Crownmarch's table puts a wanderer on one of its real road nodes 120-220 m from the giant, on
##     the human navmesh (its anchor snapped within NAV_SNAP_M, one query of the tick's budget), on loaded
##     ground, away from Brannock and the placed fights; it comes into the world with its record's kill XP
##     and walks the road near its anchor;
##   * Aldmere's army column (Aldmere hostile, a stage-4 giant by the toll fort's east road): its pike
##     formation and four riders form up on the King's Road and march; when its point walks off the loaded
##     ring toward Fort Aldmere it leaves the world (back into the abstract), marches on unloaded, comes
##     back into the world on its way home, and ends "passed" when it is home.

const SCENE := "res://scenes/world/world.tscn"
const WANDER_SPOT := Vector2(100.0, 640.0)
## North-east of the toll fort's east road: 100 m from the column's start, 148 m from the fort's centre.
const COLUMN_SPOT := Vector2(560.0, 440.0)
const COLUMN := "event.army_column"


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _go(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 600:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _stage(p: GiantPlayer, stage: int) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			p.set_profile(rec)


func test_a_wanderer_on_the_real_roads_and_the_army_column_on_the_kings_road() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _go(w, WANDER_SPOT)
	var p := w.player()
	_stage(p, 3)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var wd := w.get_node_or_null("WanderDirector") as WanderDirector
	assert_true(wd != null, "level.world makes its WanderDirector")
	if wd == null:
		return
	var d := w.director()
	assert_true(wd.tables.has("region.crownmarch"), "the Crownmarch's table is read")
	# --- a wanderer
	var table: Dictionary = wd.tables["region.crownmarch"]
	var r := {}
	for i in 5:
		r = wd.try_spawn(table, Sim.tick, "toll_patrol")
		if bool(r.ok):
			break
		await step_ticks(1)   # the tick's path-query budget may be spent: try again next tick
	assert_true(bool(r.get("ok", false)), "a toll-rider patrol is placed (%s; refusals %s)" % [r.get("reason", ""), wd.refusals])
	if not bool(r.get("ok", false)):
		return
	var info := d.p37_copy_info(str(r.copy))
	var anchor: Vector3 = info.centre
	var dist := Vector2(anchor.x - p.global_position.x, anchor.z - p.global_position.z).length()
	print("    wanderer %s at %s, %.0f m from the giant" % [r.copy, anchor, dist])
	assert_true(dist >= 120.0 and dist <= 220.0, "120-220 m from the giant (%.0f)" % dist)
	var nodes := w.index().road_nodes()
	var on_road := false
	for n in nodes:
		on_road = on_road or Vector2(n.x - anchor.x, n.z - anchor.z).length() < 0.5
	assert_true(on_road, "on a road node")
	assert_true(w.streamer.is_ready(w.chunk_at(anchor)), "on loaded, ready ground")
	assert_true(Vector2(anchor.x - 60.0, anchor.z - 450.0).length() > 125.0, "out of Brannock (radius 100 + 25)")
	var spawned := false
	for i in 20:
		await step_ticks(6)
		if d.p37_living(str(r.copy)).size() == 4:
			spawned = true
			break
	assert_true(spawned, "its four riders came into the world (%s)" % d.encounter_state(str(r.copy)))
	for n: Node3D in d.p37_living(str(r.copy)):
		var e := n as EnemyActor
		assert_eq(e.entity.combatant.xp_reward, int(GameData.get_record(e.entity.definition_id).xp_reward), "%s pays its kill XP" % e.entity.entity_id)
		assert_false(e.brain.patrol_points.is_empty(), "%s walks the road" % e.entity.entity_id)
	wd.drop_copy(str(r.copy))
	# --- the army column
	await _go(w, COLUMN_SPOT)
	_stage(p, 4)
	WorldState.set_flag("faction.aldmere.hostile", true)
	var column: WorldEvent = wd.events.get(COLUMN)
	assert_true(column != null, "the army column is one of the world's events")
	if column == null:
		return
	assert_eq(column.can_start_with(wd.event_context(column)), "", "its rules hold: stage 4, Aldmere hostile, 100 m from its start")
	wd.check_events(Sim.tick)
	assert_eq(wd.running_event(), column, "the column marches")
	var copy := column.copies[0] if not column.copies.is_empty() else ""
	var formed := false
	for i in 30:
		await step_ticks(6)
		if d.p37_living(copy).size() >= 13:
			formed = true
			break
	assert_true(formed, "its pikes, banner and four riders are in the world (%d)" % d.p37_living(copy).size())
	var fid := Formation.formation_id(copy, "pikes")
	var f := d.formation(fid)
	assert_true(f != null and f.is_intact(), "its pike formation stands (%s)" % fid)
	var pivot0 := f.pivot if f != null else Vector3.ZERO
	await step_ticks(120)
	if f != null and not f.dissolved:
		var moved := Vector2(f.pivot.x - pivot0.x, f.pivot.z - pivot0.z).length()
		assert_true(moved > 1.0, "the formation marches with the column (%.1f m in 2 s)" % moved)
	column.route.speed = 40.0   # the rest of the way, quickly
	var left := false
	var back := false
	var out_spawned := 0
	while column.is_running() and Sim.tick < 1 << 30:
		await step_ticks(6)
		if not column.is_running():
			break
		var at := column.route.point_at()
		var ready := w.streamer.is_ready(w.chunk_at(at))
		if not ready:
			left = left or d.encounter_state(copy) == EncounterDirector.DORMANT
			if not d.p37_living(copy).is_empty():
				out_spawned += 1
		elif left and not back and not d.p37_living(copy).is_empty():
			back = true
			print("    the column came back into the world at %s" % at)
	assert_true(left, "it left the world when its point walked off the loaded ring")
	assert_eq(out_spawned, 0, "never in the world while its point lay on unloaded ground")
	assert_true(back, "it came back into the world on its way home")
	assert_eq(WorldState.get_flag("event.army_column.outcome"), "passed", "home: passed")
