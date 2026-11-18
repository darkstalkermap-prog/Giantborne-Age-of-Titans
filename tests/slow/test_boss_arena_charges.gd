extends IntegrationSuite
## Ten seeded phase-2 charges of the Ogre King on scenes/test/boss_arena_test.tscn (moved here from
## tests/integration/test_boss_arena.gd by P42, plan M10 §1.7 rule 4: about 1.5 s of the default tier;
## tests/slow/test_valley_boss.gd fights the king in the real Valley): from random spots at least 8 m from
## the giant, every charge ends against stone (the ring, a pillar or the closed gate) in the wall recovery.

const ARENA := "res://scenes/test/boss_arena_test.tscn"
const CHARGE := "ability.boss_charge"
const WALL := "ability.boss_wall_recover"

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
