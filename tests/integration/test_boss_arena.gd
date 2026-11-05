extends IntegrationSuite
## The boss arena (plan §3.12 design 4, spec 10 "a safe exit before engagement") on
## scenes/test/boss_arena_test.tscn - the Valley's Kingsfall arena at the origin: leaving before
## engagement is possible (stepping back out of the threshold cancels it); engagement closes the gate
## behind the giant (never on it), removes an enemy that followed it in and alerts the king; the
## king's death opens the gate, sets world.ogre_king.defeated and emits boss_defeated; a level loaded
## after the king's defeat stays open; and ten seeded phase-2 charges from random spots at least 8 m
## from the giant all end against stone (the ring, a pillar or the closed gate) in the wall recovery.

const ARENA := "res://scenes/test/boss_arena_test.tscn"
const HB := preload("res://tools/builders/heavy.gd")
const CHARGE := "ability.boss_charge"
const WALL := "ability.boss_wall_recover"
const CS := CombatController.State

var level: Node3D
var engaged: Array = []
var defeated: Array = []


func before_each() -> void:
	await super()
	level = null
	engaged.clear()
	defeated.clear()
	Events.boss_engaged.connect(_on_engaged)
	Events.boss_defeated.connect(_on_defeated)


func after_each() -> void:
	for sig: Signal in [Events.boss_engaged, Events.boss_defeated]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_engaged(tick: int, boss_id: String) -> void:
	engaged.append([tick, boss_id])


func _on_defeated(tick: int, boss_id: String) -> void:
	defeated.append([tick, boss_id])


func _load() -> Dictionary:
	level = (load(ARENA) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.camera_rig.yaw = PI
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	await step_ticks(2)
	return {"player": p, "arena": level.get_node("BossArena") as BossArena,
		"king": level.get_node("OgreKing") as OgreBoss, "gate": level.get_node("ArenaGate") as StaticBody3D}


## Walks `p` with the stick toward z = `target_z` (straight north or south), at most max_ticks; stops
## early when `stop` (if valid) returns true. Returns true when it got there (or stopped).
func _walk_to_z(p: GiantPlayer, target_z: float, max_ticks: int, stop := Callable()) -> bool:
	var south := target_z > p.global_position.z
	p.camera_rig.yaw = PI if south else 0.0
	for i in max_ticks:
		if stop.is_valid() and stop.call():
			p.router.set_injected_move(Vector2.ZERO)
			return true
		if (p.global_position.z >= target_z) == south:
			p.router.set_injected_move(Vector2.ZERO)
			return true
		p.router.set_injected_move(Vector2(0, 1))
		await step_ticks(1)
	p.router.set_injected_move(Vector2.ZERO)
	return false


func _kill(e: CombatEntity) -> void:
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = e.entity_id
	h.power = 100000.0
	h.attacker_stat = 10.0
	h.attacker_height_m = 3.6576
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = e.actor.global_position + Vector3(0, 0, -3)
	Sim.queue_hit(h)


func test_the_arena_scene_is_wired() -> void:
	var n := await _load()
	var arena: BossArena = n.arena
	var gate: StaticBody3D = n.gate
	assert_eq(arena.state_name(), "waiting", "waiting for the giant")
	assert_true(arena.is_in_group(BossArena.GROUP), "group boss_arenas")
	assert_eq(arena.boss_id, HB.BOSS_ID, "the king's id")
	assert_eq(arena.engage_area_id, HB.ENGAGE_ID, "the threshold trigger's id")
	assert_eq(arena.gate, gate, "wired to the gate")
	assert_false(gate.visible, "the gate is open (hidden)")
	assert_true((gate.get_node("Shape") as CollisionShape3D).disabled, "and passable")
	assert_false(arena.is_gate_closed(), "is_gate_closed false")
	var pillars := arena.pillar_positions()
	assert_eq(pillars.size(), 4, "four pillars")
	for pos in pillars:
		assert_near(Vector2(pos.x, pos.z).length(), 22.0, 0.01, "a pillar 22 m from the centre")
	assert_true(arena.in_bounds(Vector3(0, 0, 39)), "the arena floor is inside the bounds")
	assert_true(arena.in_bounds(Vector3(0, 0, -55)), "the antechamber too")
	assert_false(arena.in_bounds(Vector3(0, 0, -80)), "beyond the antechamber is outside")
	assert_false(arena.in_bounds(Vector3(50, 0, 0)), "beyond the ring is outside")
	var king: OgreBoss = n.king
	assert_eq(king.entity_id, HB.BOSS_ID, "the king stands in the arena")
	assert_eq(arena.boss(), king, "and is the arena's boss")
	var regions := level.get_node("Navigation").get_children()
	assert_eq(regions.size(), 2, "two navigation regions")
	var layers := []
	for r in regions:
		layers.append((r as NavigationRegion3D).navigation_layers)
		assert_true((r as NavigationRegion3D).navigation_mesh.get_polygon_count() > 0, "%s is baked" % r.name)
	assert_eq(layers, [4, 1], "giant and human layers")


func test_leaving_before_engagement_is_possible() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var arena: BossArena = n.arena
	# Up to the gateway and back: nothing happens.
	assert_true(await _walk_to_z(p, -43.0, 400), "the giant walks up to the gateway")
	assert_eq(arena.state_name(), "waiting", "not engaged")
	assert_true(await _walk_to_z(p, -60.0, 400), "and walks back out")
	# Into the threshold trigger and straight back out again: the engagement is called off.
	var stepped_in: bool = await _walk_to_z(p, -30.0, 400, func() -> bool: return arena.state == BossArena.State.ENGAGING)
	assert_true(stepped_in and arena.state == BossArena.State.ENGAGING, "stepping into the threshold begins the engagement")
	assert_true(await _walk_to_z(p, -66.0, 600), "the giant turns back and leaves")
	assert_eq(arena.state_name(), "waiting", "stepping back out calls it off")
	assert_false(arena.is_gate_closed(), "the gate stays open")
	assert_true(p.global_position.z < -60.0, "the antechamber is a safe exit (z %.1f)" % p.global_position.z)
	assert_eq(engaged.size(), 0, "no boss_engaged")
	assert_false(n.king.brain.aware, "the king never noticed")


func test_engagement_closes_the_gate_and_removes_a_follower() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var arena: BossArena = n.arena
	var king: OgreBoss = n.king
	var follower := spawn_soldier(Vector3(2, 0.05, -50), PI, "test.arena_follower")
	var outsider := spawn_soldier(Vector3(0, 0.05, -85), PI, "test.arena_outsider")
	await step_ticks(2)
	var ok: bool = await _walk_to_z(p, -20.0, 600, func() -> bool: return arena.is_engaged())
	assert_true(ok and arena.is_engaged(), "the giant entered and the arena engaged")
	assert_eq(engaged.size(), 1, "boss_engaged once")
	if engaged.size() == 1:
		assert_eq(engaged[0][1], HB.BOSS_ID, "for the king")
	assert_true(arena.is_gate_closed(), "the gate closed (bars shown, collision on)")
	var gate_inner := HB.GATE_POS.z + HB.GATE_SIZE.z * 0.5
	assert_true(p.global_position.z - 0.85 > gate_inner, "behind the giant, never on it (z %.2f)" % p.global_position.z)
	assert_eq(arena.removed_intruders, ["test.arena_follower"] as Array[String], "the soldier that followed it in is removed")
	await step_ticks(2)
	assert_false(is_instance_valid(follower), "and gone")
	assert_true(is_instance_valid(outsider) and outsider.is_inside_tree(), "an enemy outside the arena stays")
	assert_true(king.brain.aware, "the king knows where the giant is")
	# No way back out.
	await _walk_to_z(p, -60.0, 180)
	assert_true(p.global_position.z > gate_inner, "the closed gate holds the giant in (z %.2f)" % p.global_position.z)
	assert_eq(engaged.size(), 1, "still one boss_engaged")


func test_the_kings_death_opens_the_gate_and_emits_boss_defeated() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var arena: BossArena = n.arena
	var king: OgreBoss = n.king
	p.global_position = Vector3(0, 0.05, -25)
	await step_ticks(2)
	arena.engage()
	assert_true(arena.is_engaged() and arena.is_gate_closed(), "engaged, the gate closed")
	_kill(king.entity)
	await step_ticks(2)
	assert_false(king.entity.is_alive(), "the king falls")
	assert_true(arena.is_defeated(), "the arena is won")
	assert_false(arena.is_gate_closed(), "the gate opens")
	assert_true(Waystone.flag_truthy(WorldState.get_flag("world.ogre_king.defeated")), "world.ogre_king.defeated")
	assert_eq(defeated.size(), 1, "boss_defeated once")
	if defeated.size() == 1:
		assert_eq(defeated[0][1], HB.BOSS_ID, "for the king")
	arena.engage()
	await step_ticks(5)
	assert_eq(defeated.size(), 1, "never again")
	assert_false(arena.is_gate_closed(), "and the gate stays open")


func test_a_level_loaded_after_the_kings_defeat_stays_open() -> void:
	WorldState.set_flag("world.ogre_king.defeated", true)
	var n := await _load()
	var arena: BossArena = n.arena
	assert_true(arena.is_defeated(), "the arena starts won")
	var p: GiantPlayer = n.player
	await _walk_to_z(p, -30.0, 600)
	assert_false(arena.is_gate_closed(), "walking in closes nothing")
	assert_eq(engaged.size(), 0, "no boss_engaged")


func test_ten_seeded_phase_2_charges_end_against_stone() -> void:
	# The wall recovery's own length is tested in test_boss; here it is cut short between charges.
	TestFixtures.record_override(WALL, {"recovery_s": 0.1})
	var n := await _load()
	var p: GiantPlayer = n.player
	var arena: BossArena = n.arena
	var king: OgreBoss = n.king
	p.global_position = Vector3(0, 0.05, -25)
	await step_ticks(2)
	arena.engage()
	assert_true(arena.is_gate_closed(), "the fight is on: the gate is shut")
	king.entity.combatant.pools.health = king.entity.combatant.pools.health_max * 0.45
	await TestWait.until(self, func() -> bool: return king.boss_phase() == 2 and king.controller.action == null, 150)
	assert_eq(king.boss_phase(), 2, "phase 2")
	king.ai_enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 1104
	var ends: Array[String] = []
	for i in 10:
		var spot := Vector3.INF
		while spot == Vector3.INF:
			var a := rng.randf_range(0.0, TAU)
			var d := rng.randf_range(10.5, 34.0)
			var c := Vector3(cos(a) * d, 0.05, sin(a) * d)
			var clear := true
			for pillar in arena.pillar_positions():
				if Vector2(c.x - pillar.x, c.z - pillar.z).length() < 4.5:
					clear = false
			if clear:
				spot = c
		var start := Vector3(0, 0.05, 0)
		assert_true(Vector2(spot.x, spot.z).length() - 0.85 >= 8.0, "charge %d: the giant stands at least 8 m away" % i)
		king.global_position = start
		king.velocity = Vector3.ZERO
		king.knockback_velocity = Vector3.ZERO
		king.facing_yaw = wrapf(TargetingRules.yaw_of(spot - start) + deg_to_rad(rng.randf_range(-30.0, 30.0)), -PI, PI)
		king.rotation.y = king.facing_yaw
		p.global_position = spot
		p.knockback_velocity = Vector3.ZERO
		p.entity.heal(p.entity.combatant.pools.health_max, "test")
		await step_ticks(1)
		king.brain.target_id = "player"
		king.brain.face_point = spot
		king.motion_end_reason = ""   # the last charge's reason lasts until the next motion begins
		assert_eq(king.controller.request(&"attack", {"action_id": CHARGE}), CombatController.Verdict.ACCEPT,
			"charge %d starts" % i)
		var ended: bool = await TestWait.until(self, func() -> bool: return king.motion_end_reason != "", 460)
		ends.append(king.motion_end_reason)
		assert_true(ended and king.motion_end_reason == "wall", "charge %d ends against stone (%s)" % [i, king.motion_end_reason])
		assert_eq(king.controller.action_id(), WALL, "charge %d: the wall recovery" % i)
		await TestWait.until(self, func() -> bool: return king.controller.action == null, 60)
	assert_eq(king.wall_stops, 10, "ten wall stops (%s)" % [ends])
	assert_eq(king.cap_stops, 0, "none ran out")
