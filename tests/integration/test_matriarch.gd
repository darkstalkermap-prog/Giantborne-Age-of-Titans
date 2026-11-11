extends IntegrationSuite
## The Troll Matriarch in her den (plan M6-M9 §5.13 boss 2; P34) on scenes/test/troll_den_test.tscn:
## her whelp throw carries a whelp of her brood at the giant; her second phase (50 %) begins once per
## attempt with the roar that calls three whelps; the drive-out ending - the nests burned, the back wall
## open, below 60 % - sends her through the exit: her outcome "fled", Events.boss_disengaged(fled), the
## arena done and the music out of the boss state. (A burning whelp thrown into her: the slow battery.)

const DEN := "res://scenes/test/troll_den_test.tscn"
const BB := preload("res://tools/builders/big.gd")

var level: Node3D
var gone: Array = []


func before_each() -> void:
	await super()
	gone.clear()
	WorldState.clear()
	Events.boss_disengaged.connect(_on_disengaged)


func after_each() -> void:
	if Events.boss_disengaged.is_connected(_on_disengaged):
		Events.boss_disengaged.disconnect(_on_disengaged)
	await super()


func _on_disengaged(_t: int, id: String, reason: String) -> void:
	gone.append([id, reason])


func _load() -> Dictionary:
	level = (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	return {"player": p, "arena": level.get_node("BossArena") as BossArena,
		"matriarch": level.get_node("TrollMatriarch") as TrollEnemy}


func test_the_whelp_throw_and_her_second_phase_once() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var m: TrollEnemy = n.matriarch
	assert_true(m.is_matriarch(), "the Matriarch")
	assert_true(m.is_in_group("bosses"), "a boss")
	assert_false(m.can_be_grabbed(), "never grabbable")
	(n.arena as BossArena).engage()
	p.global_position = m.global_position + Vector3(0, 0, 22)
	m.brain.target_id = p.entity.entity_id
	assert_true(m.whelp_in_reach(), "a whelp within 16 m")
	var a := GameData.get_action("ability.troll_throw_whelp")
	m.controller.force_action(a)
	await step_ticks(1)
	var held: TrollEnemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var w := node as TrollEnemy
		if w != null and w.entity.definition_id == "enemy.troll_whelp" and w.is_held():
			held = w
	assert_true(held != null, "she picks a whelp up at the windup")
	assert_eq(held.grab_holder_id, BB.DEN_ID, "in her hand")
	var thrown := await TestWait.until(self, func() -> bool: return m.whelp_throws > 0, a.windup_ticks + 4)
	assert_true(thrown, "the throw carries it")
	assert_eq(ProjectileSystem.instance(get_tree()).carried_count(), 1, "a thrown body in the air")
	# Her second phase: once, with the roar and three whelps.
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.49
	await step_ticks(1)
	assert_eq(m.attempt_phases, [2] as Array[int], "phase 2 at 50 %")
	assert_eq(m.controller.action_id(), "ability.matriarch_roar", "the roar")
	assert_eq(m.summoned.size(), 3, "it calls three whelps")
	assert_near(m.p34_regen_rate(), 40.0, 0.01, "40 hp/s in phase 2")
	pools.health = pools.health_max
	await step_ticks(1)
	pools.health = pools.health_max * 0.3
	await step_ticks(1)
	assert_eq(m.attempt_phases, [2] as Array[int], "never twice in an attempt")
	assert_eq(m.summoned.size(), 3, "no second call")


func test_the_drive_out_ending() -> void:
	Audio.enable_for_tests()
	var n := await _load()
	var m: TrollEnemy = n.matriarch
	var arena: BossArena = n.arena
	arena.engage()
	assert_eq(Audio.music.boss_id, BB.DEN_ID, "the boss music follows her")
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.55
	await step_ticks(1)
	assert_false(m.is_fleeing(), "not before the nests burn and the wall is open")
	WorldState.set_flag("world.troll_den.nests_burned", true)
	WorldState.set_flag("world.troll_den.wall_open", true)
	await step_ticks(1)
	assert_true(m.is_fleeing(), "below 60 % with the wall open she runs")
	assert_false(m.ai_enabled, "she fights no more")
	assert_eq(m.brain.move_target.distance_to(m.exit_point()), 0.0, "for the back wall's opening")
	m.global_position = m.exit_point() + Vector3(0, 0.05, 1.5)
	await step_ticks(2)
	assert_true(not is_instance_valid(m) or m.fled, "she is gone through it")
	assert_true(Sim.get_entity(BB.DEN_ID) == null, "out of the den")
	assert_eq(gone, [[BB.DEN_ID, "fled"]], "boss_disengaged(fled)")
	assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "fled", "her outcome")
	assert_true(arena.is_defeated(), "the arena is done")
	assert_eq(Audio.music.boss_id, "", "the music leaves the boss state")
	assert_true(Audio.music.state_name() != "boss", "no boss set")
	Audio.enable_for_tests(false)
