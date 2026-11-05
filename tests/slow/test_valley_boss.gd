extends IntegrationSuite
## The Ogre King in Kingsfall, in the Valley itself (P11a, plan §3.12; slow, runs with --slow):
##   * Kingsfall/BossArena stands at the arena's centre, wired to Kingsfall/ArenaGate, the pillars and
##     valley.area.arena_engage; its bounds hold the arena and the antechamber, not the shrine.
##   * The ogres and the king spawn from data: the forest ogre (with its two wolves) and the field
##     ogre on the large nav layer, the king on the giant layer once the giant reaches the
##     antechamber (not from the Kingsfall shrine).
##   * A stage-2 giant walks through the gate: the engagement despawns an encounter member that
##     followed it in (through the EncounterDirector: it returns to its encounter), closes the gate
##     behind it and wakes the king; the king, on its own AI, fights in phase 1, roars once into
##     phase 2 and charges into stone; its death opens the gate, sets world.ogre_king.defeated,
##     records the kill, clears the encounter, pays 300 XP and loot.ogre_king once, and the
##     checkpoint it triggers respawns the giant at the Kingsfall shrine.
##   * A reload resets the arena while the king lives, and keeps it open (no king) after his defeat.

const KING_ID := "valley.arena.ogre_king"
const BOSS_ENCOUNTER := "encounter.kingsfall_boss"
const CENTRE := Vector3(150, 0, 135)

var level: LevelRoot
var engaged: Array = []
var defeated: Array = []
var phases: Array = []


func before_each() -> void:
	await super()
	level = null
	engaged.clear()
	defeated.clear()
	phases.clear()
	Events.boss_engaged.connect(_on_engaged)
	Events.boss_defeated.connect(_on_defeated)
	Events.boss_phase_changed.connect(_on_phase)


func after_each() -> void:
	for sig: Signal in [Events.boss_engaged, Events.boss_defeated, Events.boss_phase_changed]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_engaged(tick: int, boss_id: String) -> void:
	engaged.append([tick, boss_id])


func _on_defeated(tick: int, boss_id: String) -> void:
	defeated.append([tick, boss_id])


func _on_phase(tick: int, boss_id: String, phase: int) -> void:
	phases.append([tick, boss_id, phase])


func _add_valley(no_director := false) -> LevelRoot:
	level = ValleyProbe.instance(no_director)
	world.add_child(level)
	return level


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _kill(e: CombatEntity) -> void:
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = e.entity_id
	h.power = 100000.0
	h.attacker_stat = 10.0
	h.attacker_height_m = 5.4864
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = e.actor.global_position + Vector3(0, 0, -3)
	Sim.queue_hit(h)


## Walks `p` straight south (+Z) with the stick until z >= `z` or stop() holds (at most max_ticks).
func _walk_south(p: GiantPlayer, z: float, max_ticks: int, stop := Callable()) -> bool:
	p.camera_rig.yaw = PI
	for i in max_ticks:
		if p.global_position.z >= z or (stop.is_valid() and stop.call()):
			p.router.set_injected_move(Vector2.ZERO)
			return true
		p.router.set_injected_move(Vector2(0, 1))
		await step_ticks(1)
	p.router.set_injected_move(Vector2.ZERO)
	return false


func test_kingsfall_arena_is_wired() -> void:
	var lv := _add_valley(false)
	await step_ticks(2)
	var arena := lv.get_node_or_null("Kingsfall/BossArena") as BossArena
	assert_true(arena != null, "Kingsfall/BossArena")
	if arena == null:
		return
	assert_true(ValleyProbe.flat(arena.global_position, CENTRE) < 0.01, "at the arena's centre")
	assert_eq(arena.boss_id, KING_ID, "for the Ogre King")
	assert_eq(arena.encounter_id, BOSS_ENCOUNTER, "spawned by its encounter")
	assert_eq(arena.engage_area_id, "valley.area.arena_engage", "engaged at the threshold")
	assert_true(lv.area(arena.engage_area_id) != null, "the trigger exists")
	assert_eq(arena.gate, lv.get_node("Kingsfall/ArenaGate"), "wired to the gate")
	assert_eq(arena.pillar_positions().size(), 4, "and the four pillars")
	assert_false(arena.is_gate_closed(), "open before the fight")
	assert_eq(arena.state_name(), "waiting", "waiting")
	assert_true(arena.in_bounds(Vector3(150, 0, 170)), "the arena floor is in bounds")
	assert_true(arena.in_bounds(Vector3(150, 0, 80)), "the antechamber is in bounds")
	assert_false(arena.in_bounds(Vector3(150, 0, 55)), "the shrine is not")
	assert_false(arena.in_bounds(Vector3(120, 0, -20)), "the bridgehead is not")
	assert_eq(lv.director().encounter_state(BOSS_ENCOUNTER), EncounterDirector.DORMANT, "the king waits")


func test_the_ogres_and_the_king_spawn_from_data() -> void:
	var lv := _add_valley(false)
	await step_ticks(2)
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var d := lv.director()
	var p := lv.player()
	var cases := [
		[Vector3(-100, 0.05, -20), "encounter.forest_ogre", "valley.forest.ogre", Vector3(-88, 0, -38), ValleyProbe.LARGE,
			["valley.forest.ogre_wolf_1", "valley.forest.ogre_wolf_2"]],
		[Vector3(45, 0.05, 15), "encounter.field_ogre", "valley.fields.ogre", Vector3(42, 0, 58), ValleyProbe.LARGE,
			["valley.fields.wolf_1", "valley.fields.wolf_2"]],
	]
	for c: Array in cases:
		GameSession.place_player(p, Transform3D(Basis(), c[0]))
		await step_ticks(1)
		d.update_now()
		assert_eq(d.encounter_state(c[1]), EncounterDirector.ACTIVE, "%s activates" % c[1])
		var ogre := d.spawned(c[2])
		assert_true(ogre is OgreEnemy, "%s is an ogre" % c[2])
		if ogre != null:
			assert_true(ValleyProbe.flat(ogre.global_position, c[3]) < 0.1, "%s at its data position" % c[2])
			var on := NavigationServer3D.region_get_closest_point(lv.nav_region(int(c[4])), ogre.global_position)
			assert_true(ValleyProbe.flat(on, ogre.global_position) < 0.5, "%s stands on the large navmesh" % c[2])
			assert_eq((ogre as EnemyActor).agent.navigation_layers, 2, "and paths on it")
		for w: String in c[5]:
			assert_true(d.spawned(w) is WolfEnemy, "%s spawned" % w)
	# The king: not from the Kingsfall shrine (85 m), but from the antechamber.
	GameSession.place_player(p, Transform3D(Basis(), Vector3(150, 0.05, 55)))
	await step_ticks(1)
	d.update_now()
	assert_eq(d.encounter_state(BOSS_ENCOUNTER), EncounterDirector.DORMANT, "the king waits while the giant rests at the shrine")
	GameSession.place_player(p, Transform3D(Basis(), Vector3(150, 0.05, 80)))
	await step_ticks(1)
	d.update_now()
	assert_eq(d.encounter_state(BOSS_ENCOUNTER), EncounterDirector.ACTIVE, "the king wakes as the giant enters the antechamber")
	var king := d.spawned(KING_ID)
	assert_true(king is OgreBoss, "the Ogre King")
	if king != null:
		assert_true(ValleyProbe.flat(king.global_position, Vector3(150, 0, 150)) < 0.1, "at (150, 150)")
		var on := NavigationServer3D.region_get_closest_point(lv.nav_region(ValleyProbe.GIANT), king.global_position)
		assert_true(ValleyProbe.flat(on, king.global_position) < 0.5, "on the giant navmesh")
		assert_true(absf(TargetingRules.yaw_delta((king as OgreBoss).facing_yaw, 0.0)) < 0.01, "facing the entrance")
		assert_false((king as OgreBoss).brain.aware, "not yet aware of the giant")


func test_a_stage_2_giant_fights_the_king_in_kingsfall() -> void:
	GameSession.start_new_valley()
	var lv := _add_valley(false)
	var p := lv.player()
	GameSession.on_level_ready(lv, p)
	p.router.use_injection = true
	p.set_profile(_profile(2))
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var d := lv.director()
	var arena := lv.get_node("Kingsfall/BossArena") as BossArena
	# A wolf of the forest ogre's encounter has followed the giant into the antechamber (placed
	# there right after the director's update, so its leash has not called it home yet).
	d.force_activate("encounter.forest_ogre")
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, PI), Vector3(150, 0.05, 95.0)))
	await step_ticks(1)
	d.update_now()
	var follower := d.spawned("valley.forest.ogre_wolf_1") as EnemyActor
	assert_true(follower != null, "the follower spawned")
	follower.ai_enabled = false
	follower.global_position = Vector3(152, 0.05, 88)
	var king := d.spawned(KING_ID) as OgreBoss
	assert_true(king != null, "the king is in the arena")
	if king == null:
		return
	var ok: bool = await _walk_south(p, 112.0, 60, func() -> bool: return arena.is_engaged())
	assert_true(ok and arena.is_engaged(), "the giant walked through the gate: engaged")
	assert_eq(engaged.size(), 1, "boss_engaged once")
	assert_true(arena.is_gate_closed(), "the gate closed behind the giant")
	assert_true(p.global_position.z - 1.2 > 95.6, "never on top of it (z %.2f)" % p.global_position.z)
	assert_eq(arena.removed_intruders, ["valley.forest.ogre_wolf_1"] as Array[String], "the follower was removed")
	assert_eq(d.member_status("valley.forest.ogre_wolf_1"), EncounterDirector.DESPAWNED,
		"through the director: it returns to its encounter")
	assert_true(king.brain.aware, "the king knows")
	# The fight, on the king's own AI. The giant stands its ground (and is kept alive).
	var hp := p.entity.combatant.pools
	var attacks: Array[String] = []
	var cb := func(_t: int, actor: String, action_id: String, _i: int) -> void:
		if actor == KING_ID:
			attacks.append(action_id)
	Events.ability_started.connect(cb)
	for i in 60 * 18:
		hp.health = hp.health_max
		await step_ticks(1)
	assert_true(attacks.size() >= 3, "the king attacks (%s)" % [attacks])
	if attacks.size() >= 3:
		assert_eq(attacks[0], "ability.boss_combo_1", "it opens with the combo")
	var strikes := attacks.filter(func(a: String) -> bool: return a != "ability.boss_combo_2")
	for i in range(1, strikes.size()):
		assert_true(strikes[i] != strikes[i - 1], "phase 1 alternates (%s)" % [strikes])
	king.entity.combatant.pools.health = king.entity.combatant.pools.health_max * 0.45
	var charged: bool = await TestWait.until(self, func() -> bool:
		hp.health = hp.health_max
		return king.wall_stops > 0, 60 * 30)
	Events.ability_started.disconnect(cb)
	assert_eq(phases.size(), 1, "phase 2 once")
	assert_eq(attacks.count("ability.boss_phase_roar"), 1, "one roar")
	assert_true(charged, "in phase 2 the king charges into stone (%s)" % [attacks])
	assert_eq(king.cap_stops, 0, "never running out in the arena")
	# The king falls.
	var xp_before := int(p.progression.xp)
	_kill(king.entity)
	await step_ticks(3)
	assert_false(king.entity.is_alive(), "the king is dead")
	assert_eq(defeated.size(), 1, "boss_defeated once")
	assert_false(arena.is_gate_closed(), "the gate opens")
	assert_true(Waystone.flag_truthy(WorldState.get_flag("world.ogre_king.defeated")), "world.ogre_king.defeated")
	assert_true(WorldState.is_killed(KING_ID), "the kill is recorded")
	assert_eq(d.encounter_state(BOSS_ENCOUNTER), EncounterDirector.CLEARED, "the encounter is cleared")
	assert_eq(int(p.progression.xp) - xp_before, 300, "300 XP")
	assert_eq(int(WorldState.inventory.get("item.ogre_tusk", 0)), 1, "the Ogre King's tusk")
	assert_eq(int(WorldState.inventory.get("item.iron_ingot", 0)), 1, "and an iron ingot")
	await TestWait.until(self, func() -> bool: return GameSession.respawn_id == GameSession.KINGSFALL_RESPAWN, 120)
	assert_eq(GameSession.respawn_id, GameSession.KINGSFALL_RESPAWN, "the checkpoint respawns at the Kingsfall shrine")
	assert_eq(str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", "")), "boss_defeated", "taken for the boss")


func test_a_reload_resets_the_arena_until_the_king_falls() -> void:
	var lv := _add_valley(false)
	await step_ticks(2)
	var p := lv.player()
	GameSession.place_player(p, Transform3D(Basis(), Vector3(150, 0.05, 110)))
	await step_ticks(1)
	lv.director().update_now()
	var arena := lv.get_node("Kingsfall/BossArena") as BossArena
	arena.engage()
	assert_true(arena.is_gate_closed(), "engaged: the gate is shut")
	var king := lv.director().spawned(KING_ID) as OgreBoss
	king.entity.combatant.pools.health = 400.0
	# The giant dies; the checkpoint reload reloads the level.
	world.remove_child(lv)
	lv.free()
	await step_ticks(2)
	var again := _add_valley(false)
	await step_ticks(2)
	var arena2 := again.get_node("Kingsfall/BossArena") as BossArena
	assert_eq(arena2.state_name(), "waiting", "the arena is reset")
	assert_false(arena2.is_gate_closed(), "the gate open")
	GameSession.place_player(again.player(), Transform3D(Basis(), Vector3(150, 0.05, 80)))
	await step_ticks(1)
	again.director().update_now()
	var king2 := again.director().spawned(KING_ID) as OgreBoss
	assert_true(king2 != null and is_equal_approx(king2.entity.combatant.pools.health, 1500.0),
		"the king is back at full health")
	assert_eq(king2.boss_phase() if king2 != null else 0, 1, "in phase 1")
	# After his defeat a reload keeps the arena open and empty.
	WorldState.record_killed(KING_ID)
	WorldState.set_flag("world.ogre_king.defeated", true)
	world.remove_child(again)
	again.free()
	await step_ticks(2)
	var after := _add_valley(false)
	await step_ticks(2)
	var arena3 := after.get_node("Kingsfall/BossArena") as BossArena
	assert_true(arena3.is_defeated(), "defeated")
	GameSession.place_player(after.player(), Transform3D(Basis(), Vector3(150, 0.05, 110)))
	await step_ticks(1)
	after.director().update_now()
	assert_true(after.director().spawned(KING_ID) == null, "no king")
	await step_ticks(2)
	assert_false(arena3.is_gate_closed(), "the gate stays open")
