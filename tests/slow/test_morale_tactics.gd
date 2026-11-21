extends IntegrationSuite
## Morale and size tactics on real actors (plan §3.4, spec 10, decision 26): debounced ally
## deaths, the commander, Thunder Roar's morale damage (x1.5 when outmatched), the scripted
## siege event, reachable flee points on the sandbox navmesh, regroup with a leader, rout
## without one, and soldiers holding formation - at markers or in an ad-hoc line - against a
## stage-2 giant while a stage-1 giant is simply approached.

const ARENA := "res://scenes/world/sandbox_arena.tscn"

var morale_events: Array = []
var routed_events: Array = []


func before_each() -> void:
	await super()
	morale_events.clear()
	routed_events.clear()
	Events.morale_changed.connect(_on_morale)
	Events.enemy_routed.connect(_on_routed)


func after_each() -> void:
	Events.morale_changed.disconnect(_on_morale)
	Events.enemy_routed.disconnect(_on_routed)
	await super()


func _on_morale(_t: int, id: String, value: float, delta: float, reason: String) -> void:
	morale_events.append([id, value, delta, reason])


func _on_routed(_t: int, id: String, encounter: String) -> void:
	routed_events.append([id, encounter])


func _events_of(id: String) -> Array:
	return morale_events.filter(func(e: Array) -> bool: return e[0] == id)


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	queue_hit("test.executioner", id, e.actor.global_position + Vector3(0, 0, 2), 5000.0)


## A Thunder Roar hit as P03 builds it: no real damage, morale_damage 20, from the player.
func _roar_hit(target_id: String, from: Vector3) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.thunder_roar"
	e.power = 1.0
	e.attacker_height_m = 3.6576
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Ability", "AoE", "Unblockable"])
	e.attacker_position = from
	e.morale_damage = 20.0
	Sim.queue_hit(e)


func _grow(p: GiantPlayer, profile_id: String) -> void:
	var prof: Dictionary = GameData.get_record(profile_id)
	p.set_profile(prof)
	p.entity.combatant.set_height(float(prof.height_m))


func _formation_marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	world.add_child(m)
	m.add_to_group("ai_formation_points")
	return m


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# --------------------------------------------------------------------------- morale

func test_three_ally_deaths_within_the_debounce_cost_10() -> void:
	var watcher := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "test.watcher")
	for i in 4:
		spawn_soldier(Vector3(-6 + 4 * i, 0.05, -6), 0.0, "test.ally_%d" % i)
	await step_ticks(2)
	for i in 3:
		_kill("test.ally_%d" % i)
		await step_ticks(30)
	assert_eq(deaths.size(), 3, "three allies died within 1.5 s")
	assert_near(watcher.brain.morale, 60.0, 1e-6, "three deaths within 2 s cost -10 once")
	await step_ticks(40)
	_kill("test.ally_3")
	await step_ticks(2)
	assert_near(watcher.brain.morale, 50.0, 1e-6, "a death after the 2 s debounce costs another -10")
	var mine := _events_of("test.watcher")
	assert_eq(mine.size(), 2, "two morale changes reported")
	if mine.size() == 2:
		assert_eq(mine[0], ["test.watcher", 60.0, -10.0, "ally_died"], "morale_changed carries the value, delta and reason")


func test_commander_death_costs_25() -> void:
	var near := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "test.near")
	var far := spawn_soldier(Vector3(0, 0.05, 30), 0.0, "test.far")
	var stranger := spawn_soldier(Vector3(0, 0.05, -28), 0.0, "test.stranger")
	var captain := spawn_soldier(Vector3(4, 0.05, -4), 0.0, "test.captain")
	captain.commander = true
	for s: SoldierEnemy in [near, far, captain]:
		s.encounter_id = "test.patrol"
	await step_ticks(2)
	_kill("test.captain")
	await step_ticks(2)
	assert_near(near.brain.morale, 45.0, 1e-6, "a soldier nearby: 70 - 25")
	assert_near(far.brain.morale, 45.0, 1e-6, "the encounter's members lose 25 however far away they are")
	assert_near(stranger.brain.morale, 70.0, 1e-6, "another encounter's soldier 24 m away notices nothing")
	assert_eq(_events_of("test.near")[0][3], "commander_died", "reason")


func test_thunder_roar_morale_damage_is_scaled_when_outmatched() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI)
	await step_ticks(3)
	s.brain.perceive(Sim.tick, s._sense())
	assert_false(s.brain.is_outmatched(), "a stage-1 giant (2.03x) does not outmatch a soldier")
	_roar_hit("soldier_01", p.global_position)
	await step_ticks(1)
	assert_near(s.brain.morale, 50.0, 1e-6, "the roar's on_morale_delta(-20) lands as -20")
	_grow(p, "growth.02")
	s.brain.perceive(Sim.tick, s._sense())
	assert_true(s.brain.is_outmatched(), "a stage-2 giant (3.05x >= 2.5) outmatches it")
	_roar_hit("soldier_01", p.global_position)
	await step_ticks(1)
	assert_near(s.brain.morale, 20.0, 1e-6, "and the same -20 is applied as -30")
	var mine := _events_of("soldier_01")
	assert_eq(mine.size(), 2, "two reports")
	if mine.size() == 2:
		assert_near(float(mine[1][2]), -30.0, 1e-6, "delta -30")
		assert_eq(mine[1][3], "player", "the attacker is the reason")


func test_real_thunder_roar_when_present() -> void:
	# Thunder Roar is P03's ability. On a branch without it the synthetic roar above covers the
	# morale path; once both packages are merged this runs the real one.
	if GameData.get_action("ability.thunder_roar") == null:
		assert_true(true, "no Thunder Roar record on this branch")
		return
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -3), PI)
	await step_ticks(3)
	_grow(p, "growth.02")
	s.brain.perceive(Sim.tick, s._sense())
	p.ensure_action("ability.thunder_roar")
	p.set_loadout_slot("slot_8", "ability.thunder_roar")
	p.entity.combatant.pools.essence = p.entity.combatant.pools.essence_max
	p.router.inject_edge(&"slot_8")
	var landed: bool = await TestWait.until(self, func() -> bool:
		return hits_on("soldier_01").any(func(r: HitResult) -> bool:
			return r.event.action_id == "ability.thunder_roar"), 150)
	assert_true(landed, "the roar reached the soldier")
	if landed:
		assert_near(s.brain.morale, 40.0, 1e-6, "the real Thunder Roar: -20 x 1.5 on an outmatched soldier")


func test_siege_destroyed_event_costs_20() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI)
	await step_ticks(2)
	s.on_morale_event(&"siege_destroyed")
	assert_near(s.brain.morale, 50.0, 1e-6, "-20 (the deferred siege-destruction morale event)")
	assert_eq(_events_of("soldier_01").back()[3], "siege_destroyed", "reported with its reason")


# --------------------------------------------------------------------------- flight

func test_flee_destinations_are_reachable_on_the_sandbox_navmesh() -> void:
	var arena: Node3D = (load(ARENA) as PackedScene).instantiate()
	TestSpawn.disable_all_ai(arena)
	world.add_child(arena)
	var s := arena.get_node("Soldier01") as SoldierEnemy
	var map := arena.get_world_3d().navigation_map
	# The map's iteration id is already > 0 when earlier tests synced it, and the region's
	# polygons arrive one sync after the region itself: wait until the map answers a path.
	var synced: bool = await TestWait.until(self, func() -> bool:
		return NavigationServer3D.map_get_path(map, Vector3(0, 0, -12), Vector3(0, 0, -24), true, 1).size() > 1, 120)
	assert_true(synced, "the sandbox navmesh is ready")
	await step_ticks(2)
	assert_true(s.nav_region_for_layers().is_valid(), "the soldier finds the sandbox region on its nav layer")
	var cases := [
		[Vector3(0, 0, -12), Vector3(0, 0, -4), "open floor"],
		[Vector3(0, 0, -57), Vector3(0, 0, -50), "backed against the north wall"],
		[Vector3(-57, 0, -57), Vector3(-50, 0, -50), "cornered in the north-west corner"],
		[Vector3(-22, 0, -7.5), Vector3(-22, 0, 3), "behind a pillar"],
		[Vector3(25, 0, 12), Vector3(25, 0, 20), "in front of the low arch"],
	]
	for c: Array in cases:
		var from := NavigationServer3D.map_get_closest_point(map, c[0])
		var threat: Vector3 = c[1]
		var p := s._resolve_flee_point(from, threat, 12.0)
		assert_true(p != Vector3.INF, "%s: a flee point exists" % c[2])
		if p == Vector3.INF:
			continue
		var path := NavigationServer3D.map_get_path(map, from, p, true, 1)
		assert_true(path.size() > 0 and path[path.size() - 1].distance_to(p) <= 1.0,
			"%s: the path ends within 1 m of the flee point" % c[2])
		assert_true(_flat(p - from) >= 6.0, "%s: at least half the flee distance away (%.1f m)" % [c[2], _flat(p - from)])
		assert_true(_flat(p - threat) > _flat(from - threat), "%s: farther from the threat" % c[2])
	# The brain uses it: a broken soldier backed against the wall runs to a reachable point.
	s.global_position = Vector3(0, 0.05, -56)
	await step_ticks(2)
	s.brain.on_noise(Sim.tick, Vector3(0, 0, -50), "player", true)
	s.brain.morale = 10.0
	s.brain.decide(Sim.tick, s.controller.state, s.global_position, func() -> bool: return true,
		func() -> void: pass)
	assert_eq(s.brain.state, EnemyBrain.AIState.FLEE, "low morale and aware: it flees")
	var fp := s.brain.flee_point
	var flee_path := NavigationServer3D.map_get_path(map, s.global_position, fp, true, 1)
	assert_true(flee_path.size() > 0 and flee_path[flee_path.size() - 1].distance_to(fp) <= 1.0,
		"its flee point is reachable")
	var arrived: bool = await TestWait.until(self, func() -> bool: return _flat(s.global_position - fp) < 1.5, 360)
	assert_true(arrived, "and it gets there (%.1f m left)" % _flat(s.global_position - fp))


func test_a_soldier_with_a_living_commander_regroups() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	var s := spawn_soldier(Vector3(0, 0.05, -7), PI, "test.private", true)
	var captain := spawn_soldier(Vector3(30, 0.05, -30), PI, "test.captain", false)
	captain.commander = true
	s.encounter_id = "test.patrol"
	captain.encounter_id = "test.patrol"
	var aware: bool = await TestWait.until(self, func() -> bool: return s.brain.aware, 60)
	assert_true(aware, "the soldier has seen the giant")
	s.brain.morale = 10.0
	var fled: bool = await TestWait.until(self, func() -> bool: return s.brain.state == EnemyBrain.AIState.FLEE, 30)
	assert_true(fled, "broken morale: it flees")
	var fled_at := Sim.tick
	assert_true(s.brain.has_leader(), "its living commander is its leader")
	s.brain.morale = 60.0
	var back: bool = await TestWait.until(self, func() -> bool: return s.brain.state != EnemyBrain.AIState.FLEE, 420)
	assert_true(back, "with morale back above 45 and a leader it regroups")
	assert_true(Sim.tick - fled_at >= 4 * 60, "after fleeing for at least 4 s (%d ticks)" % (Sim.tick - fled_at))
	assert_true(s.brain.state in [EnemyBrain.AIState.APPROACH, EnemyBrain.AIState.ALERT],
		"and goes back to the fight (%s)" % s.brain.state_name())
	assert_eq(routed_events.size(), 0, "nobody routed")


func test_without_a_leader_a_soldier_never_regroups_and_routs() -> void:
	# The real 20 s rout timer is pinned in tests/unit/test_enemy_brain_v2.gd; 3 s keeps this short.
	TestFixtures.record_override("enemy.soldier", {"ai": {"rout_after_s": 3.0}})
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	var s := spawn_soldier(Vector3(0, 0.05, -7), PI, "test.loner", true)
	s.encounter_id = "test.alone"
	var aware: bool = await TestWait.until(self, func() -> bool: return s.brain.aware, 60)
	assert_true(aware, "the soldier has seen the giant")
	s.brain.morale = 10.0
	var fled: bool = await TestWait.until(self, func() -> bool: return s.brain.state == EnemyBrain.AIState.FLEE, 30)
	assert_true(fled, "it flees")
	assert_false(s.brain.has_leader(), "alone: no leader")
	s.brain.morale = 60.0
	await step_ticks(150)
	assert_eq(s.brain.state, EnemyBrain.AIState.FLEE, "morale above 45 does not end the flight without a leader")
	var routed: bool = await TestWait.until(self, func() -> bool: return s.is_routed(), 120)
	assert_true(routed, "with no leader for rout_after_s it routs")
	assert_eq(routed_events, [["test.loner", "test.alone"]], "enemy_routed once, with its encounter")
	assert_false(s.brain.aware, "a routed unit is out of the fight (never aware again)")
	# It stays at its flee point and attacks nothing, even with the giant right beside it.
	var spot := s.brain.flee_point
	await TestWait.until(self, func() -> bool: return _flat(s.global_position - spot) < 1.5, 240)
	p.global_position = s.global_position + Vector3(0, 0, 2.0)
	var before := started.size()
	await step_ticks(90)
	assert_eq(started.slice(before).filter(func(x: String) -> bool: return x.begins_with("test.loner:")).size(), 0,
		"a routed unit attacks nothing")
	assert_eq(s.brain.state, EnemyBrain.AIState.ROUTED, "and stays routed")
	queue_hit("player", "test.loner", p.global_position, 5.0)
	await step_ticks(8)
	assert_true(s.brain.flee_point.distance_to(spot) > 1.0, "hit, it flees again to a new point")
	assert_eq(s.brain.state, EnemyBrain.AIState.ROUTED, "still routed")
	assert_eq(routed_events.size(), 1, "enemy_routed is not repeated")


# --------------------------------------------------------------------------- size tactics

func test_outmatched_soldiers_hold_at_formation_markers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	_grow(p, "growth.02")
	var m1 := _formation_marker(Vector3(-3, 0.05, -9))
	var m2 := _formation_marker(Vector3(3, 0.05, -9))
	_formation_marker(Vector3(0, 0.05, -45))   # more than 25 m away: never used
	var a := spawn_soldier(Vector3(-5, 0.05, -13), PI, "test.hold_a", true)
	var b := spawn_soldier(Vector3(5, 0.05, -13), PI, "test.hold_b", true)
	var settled: bool = await TestWait.until(self, func() -> bool:
		return a.brain.state == EnemyBrain.AIState.HOLD and b.brain.state == EnemyBrain.AIState.HOLD \
			and _flat(a.global_position - m1.global_position) < 0.8 \
			and _flat(b.global_position - m2.global_position) < 0.8, 480)
	assert_true(settled, "both hold at their own marker (a %.1f m, b %.1f m away; %s / %s)" % [
		_flat(a.global_position - m1.global_position), _flat(b.global_position - m2.global_position),
		a.brain.state_name(), b.brain.state_name()])
	await step_ticks(30)
	assert_eq(a.formation_marker(), m1, "a claimed the marker nearest to it")
	assert_eq(b.formation_marker(), m2, "b the other one")
	for s: SoldierEnemy in [a, b]:
		assert_true(absf(float(s._sense().facing_deg)) < 25.0, "%s faces the giant" % s.entity_id)
		assert_true(s.is_guarding(), "%s has its guard up" % s.entity_id)
	assert_eq(started.filter(func(x: String) -> bool: return x.begins_with("test.hold_")).size(), 0,
		"holding soldiers do not strike a giant out of their reach")


func test_without_markers_outmatched_soldiers_form_a_line() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	_grow(p, "growth.02")
	var line: Array[SoldierEnemy] = []
	for spec: Array in [[Vector3(-4, 0.05, -12), "test.line_a"], [Vector3(0.5, 0.05, -13), "test.line_b"],
			[Vector3(4, 0.05, -12), "test.line_c"]]:
		var s := spawn_soldier(spec[0], PI, spec[1], true)
		s.encounter_id = "test.line"
		line.append(s)
	var held: bool = await TestWait.until(self, func() -> bool:
		return line.all(func(s: SoldierEnemy) -> bool:
			return s.brain.state == EnemyBrain.AIState.HOLD and s.velocity.length() < 0.1), 480)
	assert_true(held, "all three hold, standing still")
	var xs: Array[Vector3] = []
	for s in line:
		xs.append(s.global_position)
	xs.sort_custom(func(u: Vector3, v: Vector3) -> bool: return u.x < v.x)
	assert_near(_flat(xs[1] - xs[0]), 3.0, 0.5, "3 m between neighbours")
	assert_near(_flat(xs[2] - xs[1]), 3.0, 0.5, "3 m between neighbours")
	var centre: Vector3 = (xs[0] + xs[1] + xs[2]) / 3.0
	var to_giant := Vector3(p.global_position.x - centre.x, 0, p.global_position.z - centre.z).normalized()
	var along := Vector3(xs[2].x - xs[0].x, 0, xs[2].z - xs[0].z).normalized()
	assert_true(absf(along.dot(to_giant)) < 0.15, "the line runs across the direction to the giant")
	for s in line:
		assert_true(absf(float(s._sense().facing_deg)) < 25.0, "%s faces the giant" % s.entity_id)
	assert_eq(line[0].global_position.x < line[2].global_position.x, true, "nobody crossed over to the far end")


func test_a_stage_one_giant_is_approached() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	_formation_marker(Vector3(-3, 0.05, -9))
	var a := spawn_soldier(Vector3(-5, 0.05, -13), PI, "test.app_a", true)
	var b := spawn_soldier(Vector3(5, 0.05, -13), PI, "test.app_b", true)
	var start_a := _flat(a.global_position - p.global_position)
	var held := false
	for i in 240:
		await step_ticks(1)
		held = held or a.brain.state == EnemyBrain.AIState.HOLD or b.brain.state == EnemyBrain.AIState.HOLD
	assert_false(held, "no HOLD against a stage-1 giant (2.03x < 2.5)")
	assert_false(a.brain.is_outmatched(), "not outmatched")
	assert_true(_flat(a.global_position - p.global_position) < start_a - 4.0, "they close in on the giant")
