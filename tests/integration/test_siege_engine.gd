extends IntegrationSuite
## P32 (plan M6-M9 §2.10, §3.16 tests, §5.11, decision 21): siege engines in play, on hand-placed
## engines and crews (the director's engines list is the slow battery's). Reloads and windups are cut
## short through TestFixtures, and the engines' firing rules are proven on a stand-in target - a
## soldier on the giant's team, which an engine takes for the giant (its target is the first living
## PLAYER entity) - so the default tier stays quick; the rules are the shipped ones (the giant itself
## is the target in test_size_override and the slow battery).
##   * An engine fires only while crewed and at most once per reload_s; a crew member killed leaves it
##     uncrewed (siege_engine_crewed false) and silent.
##   * Launches at one target stay at least 1.0 s apart with every other ranged attacker: two ballistae
##     ready at once launch a second apart, one after the other, and no archer's launch slot is granted
##     within a second of an engine's launch.
##   * An engine's fall costs every unit of its side within 30 m 20 morale, once (a second engine
##     falling within 2 s costs nothing more), units farther away nothing; its crew flees and routs.
## The engines' telegraphs - the ballista's aim line frozen at its lock, the catapult's landing circle
## through the flight - are the slow battery's (tests/slow/test_siege_battery.gd).

const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CATAPULT := "res://scenes/world/siege_catapult.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const BOLT := "ability.ballista_bolt"
const STONE := "ability.catapult_stone"

var fired: Array = []      ## [tick, engine id]
var crewed: Array = []     ## [tick, engine id, crewed]
var launches: Array = []   ## [tick, owner id, visual]


func before_each() -> void:
	await super()
	fired.clear()
	crewed.clear()
	launches.clear()
	Events.siege_engine_fired.connect(_on_fired)
	Events.siege_engine_crewed.connect(_on_crewed)
	Events.projectile_spawned.connect(_on_launch)


func after_each() -> void:
	for sig: Signal in [Events.siege_engine_fired, Events.siege_engine_crewed, Events.projectile_spawned]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_fired(tick: int, engine_id: String, _action_id: String, _target_id: String) -> void:
	fired.append([tick, engine_id])


func _on_crewed(tick: int, engine_id: String, is_crewed: bool) -> void:
	crewed.append([tick, engine_id, is_crewed])


func _on_launch(tick: int, _id: int, owner_id: String, _action_id: String, _pos: Vector3, _vel: Vector3, visual: String) -> void:
	launches.append([tick, owner_id, visual])


## Quick engines: reload `reload_s`, windups `windup_s` (the shipped tracking fractions).
static func _quick(reload_s: float, windup_s: float) -> void:
	for id: String in ["prop.siege_ballista", "prop.siege_catapult"]:
		TestFixtures.record_override(id, {"engine": {"reload_s": reload_s}})
	for id: String in [BOLT, STONE]:
		TestFixtures.record_override(id, {"windup_s": windup_s, "recovery_s": 0.05})


## An engine of `scene` at `pos` facing the origin.
func _engine(scene: String, world_id: String, pos: Vector3) -> SiegeEngine:
	var e := (load(scene) as PackedScene).instantiate() as SiegeEngine
	e.world_id = world_id
	e.position = pos
	e.rotation.y = TargetingRules.yaw_of(Vector3(-pos.x, 0.0, -pos.z))
	world.add_child(e)
	return e


## A crew member (AI off) at `engine`'s first crew place, taken into its crew.
func _crew(engine: SiegeEngine, id: String, ai := false) -> EnemyActor:
	var c := TestSpawn.enemy(world, CREW, engine.global_position + Vector3(0, 0.05, 0), id, ai, engine.rotation.y)
	engine.add_crew(c)
	c.global_position = engine.crew_slot(c) + Vector3(0, 0.05, 0)
	return c


func _kill(target: CombatEntity, by: Node3D) -> void:
	queue_hit((by.get("entity") as CombatEntity).entity_id, target.entity_id, by.global_position, 1.0e6)


## The engines' target in the firing tests: a soldier (AI off, unkillable) on the giant's team.
func _stand_in(pos: Vector3) -> EnemyActor:
	var s := spawn_soldier(pos, 0.0, "test.p32_target", false)
	s.entity.team = CombatEntity.Team.PLAYER
	s.entity.combatant.unkillable = true
	return s


func test_an_engine_fires_only_while_crewed_and_at_most_once_per_reload() -> void:
	_quick(0.3, 0.1)
	var p := _stand_in(Vector3(0, 0.05, 0))
	var b := _engine(BALLISTA, "test.p32_ballista", Vector3(0, 0, -30))
	await step_ticks(SiegeEngine.CREW_CHECK_TICKS + 2)
	var waiting := b.reload_left
	assert_eq(b.shots, 0, "no crew, no shot")
	assert_false(b.crewed, "uncrewed")
	assert_near(b.reload_left, waiting, 1e-6, "an uncrewed engine does not reload")
	var c := _crew(b, "test.p32_crew_a")
	await TestWait.until(self, func() -> bool: return fired.size() >= 1, 40)
	assert_true(crewed.has([crewed[0][0], "test.p32_ballista", true]) if not crewed.is_empty() else false,
		"siege_engine_crewed true once its crew stands by it (%s)" % [crewed])
	assert_eq(fired.size(), 1, "crewed, it shoots")
	assert_near(b.reload_left, 0.3, 1e-6, "and its reload starts: no second shot within reload_s")
	assert_eq(launches.size(), 1, "the shot launches one bolt")
	if not launches.is_empty():
		assert_eq(str(launches[0][2]), "ballista_bolt", "a ballista bolt")
	await step_ticks(12)   # its shot's recovery, then crewed reloading
	assert_true(b.reload_left < 0.3 - 0.05, "crewed, it reloads (%.3f s left)" % b.reload_left)
	# The crew falls: uncrewed, its reload stops and it cannot shoot.
	_kill(c.entity, p)
	await step_ticks(SiegeEngine.CREW_CHECK_TICKS + 2)
	assert_false(b.crewed, "its crew dead, the engine is uncrewed")
	assert_eq(crewed.back(), [crewed.back()[0], "test.p32_ballista", false], "siege_engine_crewed false")
	var left := b.reload_left
	await step_ticks(12)
	assert_near(b.reload_left, left, 1e-6, "its reload waits for a crew")
	assert_eq(b.shots, 1, "and it shoots no more")
	b.queue_free()


func test_launches_at_one_target_stay_a_second_apart_with_other_ranged_attackers() -> void:
	_quick(0.4, 0.1)
	var p := _stand_in(Vector3(0, 0.05, 0))
	var a := _engine(BALLISTA, "test.p32_ballista_a", Vector3(-6, 0, -30))
	var b := _engine(BALLISTA, "test.p32_ballista_b", Vector3(6, 0, -30))
	_crew(a, "test.p32_crew_a")
	_crew(b, "test.p32_crew_b")
	var gap := ActionDef.seconds_to_ticks(SiegeEngine.LAUNCH_GAP_S)
	var archer_gap := ActionDef.seconds_to_ticks(1.0)
	var refused_after_launch := 0
	var asked_after_launch := 0
	var start := Sim.tick
	while Sim.tick - start < 110 and launches.size() < 2:
		await step_ticks(1)
		# another ranged attacker (an archer's draw: the same launch slots) asks right after each launch
		if not launches.is_empty() and Sim.tick - int(launches.back()[0]) < archer_gap - 2:
			asked_after_launch += 1
			if not Sim.request_launch_slot(p.entity.entity_id, "test.p32_other_archer", archer_gap):
				refused_after_launch += 1
	assert_eq(launches.size(), 2, "both ballistae launch (%s)" % [launches])
	var owners := {}
	for i in launches.size():
		owners[str(launches[i][1])] = true
		if i > 0:
			assert_true(int(launches[i][0]) - int(launches[i - 1][0]) >= gap,
				"launch %d came %d ticks after the one before (at least %d)" % [i, int(launches[i][0]) - int(launches[i - 1][0]), gap])
	assert_eq(owners.size(), 2, "the two engines take turns")
	assert_true(asked_after_launch > 0 and refused_after_launch == asked_after_launch,
		"no other launch slot within a second of an engine's launch (%d of %d refused)" % [refused_after_launch, asked_after_launch])
	a.queue_free()
	b.queue_free()


func test_an_engines_fall_costs_its_side_20_morale_once_and_its_crew_flees() -> void:
	var p := _stand_in(Vector3(0, 0.05, 30))   # who breaks the engines
	var e1 := _engine(BALLISTA, "test.p32_ballista_1", Vector3(-4, 0, -30))
	var e2 := _engine(CATAPULT, "test.p32_catapult_2", Vector3(8, 0, -30))
	var near := spawn_soldier(Vector3(-4, 0.05, -24), 0.0, "test.p32_near")      # 6 m from the first
	var far_in := spawn_soldier(Vector3(-4, 0.05, -2.5), 0.0, "test.p32_far_in")  # 27.5 m
	var out := spawn_soldier(Vector3(-4, 0.05, 6), 0.0, "test.p32_out")           # 36 m from the first, 37 m from the second
	var crew := _crew(e1, "test.p32_crew_1", true)
	await step_ticks(2)
	var before := {}
	for s: EnemyActor in [near, far_in, out]:
		before[s.entity_id] = s.brain.morale
	_kill(e1.entity, p)
	await step_ticks(2)
	assert_true(e1.destroyed, "the ballista breaks")
	assert_near(near.brain.morale, float(before[near.entity_id]) - 20.0, 1e-3, "a soldier 6 m off loses 20")
	assert_near(far_in.brain.morale, float(before[far_in.entity_id]) - 20.0, 1e-3, "one 27.5 m off loses 20")
	assert_near(out.brain.morale, float(before[out.entity_id]), 1e-3, "one 36 m off loses nothing")
	assert_eq(crew.brain.state, EnemyBrain.AIState.ROUTED, "its crew runs and routs (%s)" % crew.brain.state_name())
	assert_eq(crew.engine_id, "", "it serves no engine")
	# The second engine falls a moment later: within 2 s, so nobody loses morale again.
	await step_ticks(8)
	_kill(e2.entity, p)
	await step_ticks(2)
	assert_true(e2.destroyed, "the catapult breaks")
	assert_near(near.brain.morale, float(before[near.entity_id]) - 20.0, 1e-3, "two engines within 2 s: once")
	assert_near(far_in.brain.morale, float(before[far_in.entity_id]) - 20.0, 1e-3, "once for the far one too")
	# After the debounce a third fall counts again (the second engine's event at 2.5 s: unit tested here
	# through the brain).
	near.brain.now = Sim.tick + ActionDef.seconds_to_ticks(2.5)
	assert_true(near.brain.on_morale_event(&"siege_destroyed", Sim.tick + ActionDef.seconds_to_ticks(2.5)), "a known event")
	assert_near(near.brain.morale, float(before[near.entity_id]) - 40.0, 1e-3, "2.5 s later it costs again")
	for s: EnemyActor in [near, far_in, out]:
		s.queue_free()

