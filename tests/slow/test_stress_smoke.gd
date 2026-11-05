extends IntegrationSuite
## The stress route (P14, plan §3.16, §5.3; spec §16; slow, runs with --slow):
##   * the arena as built: 12 combatant slots (4 soldiers, 3 wolves, 2 archers, 1 mage, 2 ogres)
##     that spawn at load, 20 breakables (8 fences, 6 pines, 4 crates, 2 practice gates) in reach of
##     their stops, the 8-stop rectangular route, human and large navigation regions baked into the
##     scene, the level record's render presets; a dead or routed combatant is replaced 5 s later and
##     reset_breakables() puts fresh copies in the place of broken ones;
##   * the smoke run: 60 s of the stress bot (the same StressScenario the Autopilot starts for
##     --scenario=stress): no errors (the runner fails a test on any), at least 10 active combatants
##     on average, never more than 40 debris pieces, every breakable destroyed at least once, and the
##     invulnerable giant never dies.

const ARENA := "res://scenes/test/stress_arena.tscn"
const RUN_S := 60.0

var arena: LevelRoot
var scenario: StressScenario


func before_each() -> void:
	await super()
	arena = (load(ARENA) as PackedScene).instantiate() as LevelRoot
	world.add_child(arena)
	scenario = arena.get_node("StressScenario") as StressScenario
	await step_ticks(2)


func after_each() -> void:
	if scenario != null and is_instance_valid(scenario):
		scenario.stop_bot()
	arena = null
	scenario = null
	await super()


func test_the_arena_as_built() -> void:
	assert_eq(arena.level_id, "level.stress_arena", "a LevelRoot of its own record")
	assert_eq(str(arena.level_record().get("type", "")), "level", "the record exists")
	assert_true(arena.applied_graphics.has("shadow_distance_m"), "the render preset applied")
	# Combatants: spawned at load, one per slot, ids from the slots.
	assert_eq(scenario.slot_count(), 12, "12 combatant slots")
	assert_eq(scenario.active_count(), 12, "all 12 active at load")
	var defs := {}
	for c in scenario.combatants():
		var e: CombatEntity = c.get("entity")
		defs[e.definition_id] = int(defs.get(e.definition_id, 0)) + 1
		assert_true(e.entity_id.begins_with("stress."), "%s carries a stress id" % e.entity_id)
		assert_true(c.get_parent() == arena.spawn_parent(), "%s spawned under LevelRoot/Spawned" % e.entity_id)
	assert_eq(defs, {"enemy.soldier": 4, "enemy.wolf": 3, "enemy.archer": 2, "enemy.mage": 1, "enemy.ogre": 2},
		"4 soldiers, 3 wolves, 2 archers, 1 mage, 2 ogres")
	# Breakables: 20 in lap order, each in reach of its stop's Footfall.
	var props := scenario.breakables()
	assert_eq(props.size(), 20, "20 breakables")
	var kinds := {}
	var stops := scenario.stops()
	assert_eq(stops.size(), 8, "an 8-stop route")
	for bp in props:
		var id := str(bp.record.get("id", ""))
		kinds[id] = int(kinds.get(id, 0)) + 1
		var stop: Vector3 = stops[int(bp.get_meta("stop"))]
		var near := _nearest_point(bp, stop)
		assert_true(near.distance_to(Vector3(stop.x, near.y, stop.z)) <= 3.4,
			"%s lies within 3.4 m of its stop (%.2f m)" % [bp.world_id, near.distance_to(Vector3(stop.x, near.y, stop.z))])
	assert_eq(kinds, {"prop.fence_wood": 8, "prop.tree_small": 6, "prop.crate": 4, "prop.gate_practice": 2},
		"8 fences, 6 pines, 4 crates, 2 practice gates")
	# The route is a rectangle round the centre.
	for i in stops.size():
		var a: Vector3 = stops[i]
		var b: Vector3 = stops[(i + 1) % stops.size()]
		assert_true(is_zero_approx(a.x - b.x) or is_zero_approx(a.z - b.z), "route leg %d runs along an axis" % (i + 1))
	# Navigation: baked into the scene on the human and large layers.
	for spec: Array in [["Navigation/Human", 1], ["Navigation/Large", 2]]:
		var region := arena.get_node(str(spec[0])) as NavigationRegion3D
		assert_true(region != null and region.navigation_layers == int(spec[1]), "%s on layer %d" % spec)
		assert_true(region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0,
			"%s has a baked navmesh" % spec[0])
	# A dead combatant comes back 5 s later at its spawn point, with a new id.
	var victim: Node3D = scenario.combatants()[0]
	var victim_id := (victim.get("entity") as CombatEntity).entity_id
	queue_hit("player", victim_id, victim.global_position + Vector3(0, 0, 2), 50000.0)
	await step_ticks(2)
	assert_eq(scenario.active_count(), 11, "11 active while one is down")
	await step_ticks(int(StressScenario.RESPAWN_DELAY_S * 60.0) + 2)
	assert_eq(scenario.active_count(), 12, "12 again 5 s later")
	assert_eq(scenario.respawns, 1, "one respawn")
	assert_true(Sim.get_entity(victim_id) == null, "the old body is gone")
	# Broken breakables come back as fresh copies with new world ids.
	var crate: BreakableProp = null
	for bp in props:
		if str(bp.record.get("id", "")) == "prop.crate":
			crate = bp
			break
	var crate_id := crate.world_id
	queue_hit("player", crate.entity.entity_id, crate.global_position + Vector3(0, 0, 2), 50000.0,
		PackedStringArray(["Melee"]))
	await step_ticks(2)
	assert_true(crate.destroyed, "the crate broke")
	assert_eq(scenario.broken_once_count(), 1, "one breakable broken once")
	assert_eq(scenario.reset_breakables(), 1, "reset brings one back")
	var fresh: BreakableProp = null
	for bp in scenario.breakables():
		if bp.world_id.begins_with(crate_id + "."):
			fresh = bp
	assert_true(fresh != null and not fresh.destroyed and fresh.world_id == crate_id + ".r2",
		"a fresh crate %s stands in its place" % (fresh.world_id if fresh != null else "?"))
	assert_false(is_instance_valid(crate) and crate.is_inside_tree(), "the wreck is gone")


func test_stress_route_smoke() -> void:
	var player := arena.player()
	assert_true(player != null, "the arena's giant")
	var probe := PerfProbe.new()
	probe.label = "stress_smoke"
	arena.add_child(probe)
	scenario.start_bot(player)
	var max_seen := 0
	var dead_ticks := 0
	for i in int(RUN_S):
		await step_ticks(60)
		max_seen = maxi(max_seen, PerfProbe.debris_count(get_tree()))
		if player.controller.state == CombatController.State.DEAD:
			dead_ticks += 1
	probe.finish()
	var r := scenario.result(RUN_S)
	var perf := probe.result()
	print("    stress smoke: %d laps (ends %s s), %d/%d broken once, %d breaks, active avg %.2f (min %d), debris max %d, %d respawns, inputs %s; CPU per tick p50 %.2f p95 %.2f p99 %.2f ms (container, indicative)" % [
		r.laps, r.lap_end_s, r.breakables_broken_once, r.breakables, r.breakable_breaks, r.active_avg,
		r.active_min, r.max_debris, r.respawns, r.inputs, perf.cpu_tick_ms.p50, perf.cpu_tick_ms.p95,
		perf.cpu_tick_ms.p99])
	assert_eq(r.check_failures, PackedStringArray(), "the scenario's own checks pass")
	assert_eq(player.current_growth_stage(), StressScenario.DEFAULT_STAGE, "the bot grew the giant to stage 2")
	assert_true(player.entity.combatant.statuses.has(StressScenario.STATUS_INVULNERABLE),
		"the giant carries the hidden invulnerability")
	assert_true(float(r.active_avg) >= 10.0, "at least 10 active combatants on average (%.2f)" % r.active_avg)
	assert_true(int(r.max_debris) <= 40 and max_seen <= 40, "debris never above 40 (%d)" % r.max_debris)
	assert_true(int(r.max_debris) >= 30, "and the clusters do fill the pool (%d)" % r.max_debris)
	assert_eq(int(r.breakables_broken_once), 20, "every breakable destroyed at least once")
	assert_true(int(r.laps) >= 1, "a full lap")
	assert_eq(int(r.player_deaths), 0, "the giant never died")
	assert_eq(dead_ticks, 0, "never seen dead")
	assert_true(int(perf.counters.hits_resolved) > 0, "the fight resolved hits")


## The point of a breakable's length (fences and gates lie along local X) nearest to `p`.
static func _nearest_point(bp: BreakableProp, p: Vector3) -> Vector3:
	var half := 0.0
	match str(bp.record.get("id", "")):
		"prop.fence_wood":
			half = 4.0
		"prop.gate_practice":
			half = 5.9
	var axis := bp.global_transform.basis.x.normalized()
	var along := clampf((p - bp.global_position).dot(axis), -half, half)
	return bp.global_position + axis * along
