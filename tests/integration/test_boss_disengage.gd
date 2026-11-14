extends IntegrationSuite
## The disengage rule (plan M6-M9 §2.10, §5.13; P34) on scenes/test/troll_den_test.tscn: a giant that
## stays beyond the arena radius + 20 m for the disengage time ends the attempt - the Matriarch goes
## home at full health in her first phase, the whelps her roar called go, Events.boss_disengaged(left)
## and the music back to the zone - and entering again starts a new attempt in which each phase happens
## once more, exactly once. Stepping out and back in before the time runs out changes nothing. (The
## default tier shortens the 5 s to 0.25 s; the slow battery waits the full 5 s.) M8 gate fix-up 1 (N4.6): the
## boss's own talker beyond the line (the Moot's challenge stone) is the fight's ground: answering it warns
## nothing and resets nothing; beyond its reach the rule holds. Fix-up 2 (N4.6): so is the way out to it from
## the line, as wide as its reach - walking out at the giant's pace and back warns nothing; beside it, it does.

const DEN := "res://scenes/test/troll_den_test.tscn"
const BB := preload("res://tools/builders/big.gd")

var level: Node3D
var gone: Array = []
var engaged: Array = []


func before_each() -> void:
	await super()
	gone.clear()
	engaged.clear()
	WorldState.clear()
	Events.boss_disengaged.connect(_on_disengaged)
	Events.boss_engaged.connect(_on_engaged)


func after_each() -> void:
	for sig: Signal in [Events.boss_disengaged, Events.boss_engaged]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_disengaged(_t: int, id: String, reason: String) -> void:
	gone.append([id, reason])


func _on_engaged(_t: int, id: String) -> void:
	engaged.append(id)


func test_leaving_resets_the_boss_and_returning_starts_a_new_attempt() -> void:
	Audio.enable_for_tests()
	level = (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var arena := level.get_node("BossArena") as BossArena
	var m := level.get_node("TrollMatriarch") as TrollEnemy
	assert_eq(arena.disengage_s, 5.0, "5 s by default")
	assert_eq(arena.disengage_margin_m, 20.0, "beyond the radius + 20 m")
	arena.disengage_s = 0.25
	arena.engage()
	assert_eq(engaged, [BB.DEN_ID], "attempt 1")
	assert_eq(Audio.music.boss_id, BB.DEN_ID, "the boss music")
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.45
	await step_ticks(1)
	assert_eq(m.attempt_phases, [2] as Array[int], "phase 2 in attempt 1")
	var summon := int(GameData.get_record("enemy.troll_matriarch").boss.phases[1].summon)
	assert_true(summon >= 1, "phase 2 calls whelps")
	assert_eq(m.summoned.size(), summon, "the record's whelps called (P39's balance pass: two, was three)")
	var called := m.summoned.duplicate()
	# Out to 45 m (inside radius + 20 m = 50 m): nothing happens.
	p.global_position = Vector3(0, 0.05, 45)
	await step_ticks(17)
	assert_true(arena.is_engaged(), "45 m is not far enough")
	# Out to 60 m, back in before the time runs out: the time starts again.
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(9)
	p.global_position = Vector3(0, 0.05, 40)
	await step_ticks(2)
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(10)
	assert_true(arena.is_engaged(), "back in time: the attempt goes on")
	assert_eq(gone, [], "no disengage")
	# Out for good.
	await step_ticks(8)
	assert_eq(gone, [[BB.DEN_ID, "left"]], "boss_disengaged(left)")
	assert_eq(arena.state_name(), "waiting", "the arena waits again")
	assert_false(arena.is_gate_closed(), "its way open")
	assert_eq(m.attempt, 2, "a new attempt")
	assert_eq(pools.health, pools.health_max, "full health")
	assert_eq(m.brain.boss_phase(), 1, "her first phase")
	assert_eq(m.attempt_phases, [] as Array[int], "no phase yet in attempt 2")
	assert_true(m.is_returning() or Vector2(m.global_position.x - m.home_position.x,
		m.global_position.z - m.home_position.z).length() <= 1.5, "she walks home (or is there)")
	assert_eq(Audio.music.boss_id, "", "the music returns to the zone")
	await step_ticks(1)
	for id: String in called:
		assert_true(Sim.get_entity(id) == null, "%s went with the attempt" % id)
	# Return: a new attempt; phase 2 once more, once.
	p.global_position = Vector3(0, 0.05, 20)
	arena.engage()
	assert_eq(engaged, [BB.DEN_ID, BB.DEN_ID], "attempt 2 engaged")
	assert_eq(arena.attempts, 2, "two attempts")
	pools.health = pools.health_max * 0.45
	await step_ticks(1)
	pools.health = pools.health_max * 0.2
	await step_ticks(1)
	assert_eq(m.attempt_phases, [2] as Array[int], "phase 2 exactly once in attempt 2")
	assert_eq(m.phase_changes, 2, "once per attempt over both")
	Audio.enable_for_tests(false)


# --------------------------------------------------------------------------- M8 gate (F33)

## The giant is told (F33): crossing the disengage line during an engaged attempt warns it on the HUD's
## message line - once, not again on every step across within LEAVING_WARN_EVERY_S - and the reset says
## the boss recovered; a battle's lines name the battle, which regroups.
func test_leaving_warns_the_giant_and_the_reset_tells_it() -> void:
	var lines: Array = []
	var on_message := func(text: String, kind: String) -> void: lines.append([text, kind])
	Events.hud_message.connect(on_message)
	level = (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 0.5
	p.global_position = Vector3(0, 0.05, 20)
	arena.engage()
	await step_ticks(2)
	lines.clear()
	p.global_position = Vector3(0, 0.05, 45)   # inside radius + 20 m: no word
	await step_ticks(6)
	assert_eq(lines, [], "nothing inside the line")
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(6)
	assert_eq(lines, [["The Troll Matriarch will recover unless you turn back.", "warn"]], "crossing the line warns the giant")
	p.global_position = Vector3(0, 0.05, 40)
	await step_ticks(3)
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(6)
	assert_eq(lines.size(), 1, "stepping across again at once does not repeat the warning")
	await step_ticks(30)
	assert_eq(gone, [[BB.DEN_ID, "left"]], "the attempt resets")
	assert_eq(lines.back(), ["The Troll Matriarch recovered: you left the fight.", "bad"], "and the HUD says so")
	# A battle names itself and regroups.
	level.queue_free()
	await step_ticks(2)
	var bailey := (load("res://scenes/test/bailey_test.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(bailey)
	await step_ticks(2)
	var bp := bailey.get_node("Player") as GiantPlayer
	var battle := bailey.get_node("BattleBoss") as BattleBoss
	battle.disengage_s = 0.25
	lines.clear()
	bp.global_position = Vector3(0, 0.05, 30)
	battle.engage()
	await step_ticks(2)
	bp.global_position = Vector3(0, 0.05, 90)
	await step_ticks(20)
	var texts := lines.map(func(l: Array) -> String: return str(l[0]))
	assert_true(texts.has("The Iron Regiment will regroup unless you turn back."), "the battle's warning (%s)" % [texts])
	assert_true(texts.has("The Iron Regiment regrouped: you left the battle."), "and its reset line")
	Events.hud_message.disconnect(on_message)


## M8 gate fix-up 1 (N4.6, the audit's play pass: Harrok engages as the giant enters the Moot, and his
## challenge stone stands 95.8 m from the ring's centre, beyond the 80 m line - answering it warned "will
## recover unless you turn back"). A talker naming the boss, 60 m out (beyond radius + 20 m = 50 m).
func test_the_bosss_own_talker_beyond_the_line_is_the_fights_ground() -> void:
	var lines: Array = []
	var on_message := func(text: String, kind: String) -> void: lines.append([text, kind])
	Events.hud_message.connect(on_message)
	level = (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 0.5
	var stone := NpcTalker.new()
	stone.npc_id = arena.boss_id
	stone.radius_m = 10.0
	stone.position = Vector3(0, 0, 70)
	level.add_child(stone)
	var other := NpcTalker.new()
	other.npc_id = "test.someone_else"
	other.radius_m = 10.0
	other.position = Vector3(40, 0, 70)
	level.add_child(other)
	p.global_position = Vector3(0, 0.05, 20)
	arena.engage()
	await step_ticks(2)
	lines.clear()
	p.global_position = Vector3(0, 0.05, 62)   # 62 m out: beyond the line, within the stone's reach
	assert_true(arena.outside_m(p.global_position) > arena.disengage_margin_m, "beyond the disengage line")
	assert_true(arena.at_boss_talker(p), "at the boss's own talker")
	await step_ticks(60)
	assert_eq(lines, [], "answering the boss's challenge warns nothing")
	assert_true(arena.is_engaged() and gone.is_empty(), "and resets nothing")
	p.global_position = Vector3(40, 0.05, 62)   # another's talker out there is no ground of the fight
	assert_false(arena.at_boss_talker(p), "another npc's talker is not the boss's")
	await step_ticks(6)
	assert_eq(lines, [["The Troll Matriarch will recover unless you turn back.", "warn"]], "it warns there")
	await step_ticks(40)
	assert_eq(gone, [[BB.DEN_ID, "left"]], "and the attempt resets")
	Events.hud_message.disconnect(on_message)


## M8 gate fix-up 2 (N4.6, the re-audit's walk: the Moot's challenge stone's reach begins 2.1 m beyond the
## line, and the giant walking out from the ring to answer it was warned on its first tick in between; the
## test above puts the giant straight into the reach). The way from the line to the boss's own talker, as wide
## as its reach, is the fight's ground: walking out to the talker at the giant's pace and back warns nothing
## and resets nothing. Beside that way, or past the talker, the rule holds.
func test_walking_out_to_the_bosss_own_talker_and_back_warns_nothing() -> void:
	var lines: Array = []
	var on_message := func(text: String, kind: String) -> void: lines.append([text, kind])
	Events.hud_message.connect(on_message)
	level = (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 0.5
	var stone := NpcTalker.new()
	stone.npc_id = arena.boss_id
	stone.radius_m = 10.0
	stone.position = Vector3(0, 0, 70)
	level.add_child(stone)
	var reach := stone.radius_m + float(p.profile.get("capsule_radius_m", 0.0))
	var line_m := arena.inner_radius_m + arena.disengage_margin_m
	assert_true(70.0 - reach > line_m + 2.0, "a gap of more than 2 m between the line (%.0f m) and the talker's reach (from %.1f m)" % [
		line_m, 70.0 - reach])
	assert_eq(arena.line_point_toward(Vector2(0, 70)), Vector2(0, line_m), "the line's point toward the talker")
	p.global_position = Vector3(0, 0.05, 20)
	arena.engage()
	await step_ticks(2)
	lines.clear()
	var pace := float(p.profile.get("walk_speed_mps", 0.0)) * Sim.DT
	assert_true(pace > 0.0, "the giant's walking pace (%.3f m a tick)" % pace)
	var gap := 0
	var off_way := 0
	var z := line_m - 4.0
	while z < 70.0:   # out across the gap into the talker's reach, at the giant's pace
		z = minf(70.0, z + pace)
		p.global_position = Vector3(0, 0.05, z)
		await step_ticks(1)
		if arena.outside_m(p.global_position) > arena.disengage_margin_m and not arena.at_boss_talker(p):
			gap += 1
			off_way += 0 if arena.on_way_to_boss_talker(p) else 1
	assert_true(gap > int(0.5 * Sim.TICK_RATE), "the walk spent longer in the gap than the disengage time (%d ticks)" % gap)
	assert_eq(off_way, 0, "in the gap the giant is on its way to the talker")
	await step_ticks(40)
	while z > line_m - 4.0:   # and back
		z -= pace
		p.global_position = Vector3(0, 0.05, z)
		await step_ticks(1)
	assert_eq(lines, [], "walking out to the boss's own talker, answering it and walking back warns nothing")
	assert_true(arena.is_engaged() and gone.is_empty(), "and resets nothing")
	# Beside the way (beyond its reach of it) and past the talker the giant has left the fight.
	for at: Vector3 in [Vector3(reach + 2.0, 0.05, (line_m + 70.0) * 0.5), Vector3(0, 0.05, 70.0 + reach + 2.0)]:
		p.global_position = at
		assert_true(arena.outside_m(at) > arena.disengage_margin_m and not arena.on_way_to_boss_talker(p),
			"%s is off the way to the talker" % at)
	p.global_position = Vector3(reach + 2.0, 0.05, (line_m + 70.0) * 0.5)
	await step_ticks(6)
	assert_eq(lines, [["The Troll Matriarch will recover unless you turn back.", "warn"]], "beside the way it warns")
	await step_ticks(40)
	assert_eq(gone, [[BB.DEN_ID, "left"]], "and the attempt resets")
	Events.hud_message.disconnect(on_message)


## M8 gate fix-up 1 (N4.5, the audit's play pass: the Iron Regiment's portcullis traps the giant in the
## bailey - P36 shuts it on purpose - and nothing said so; its leaving lines were reached only by a teleport
## out). Engaging the battle behind its gate tells the giant at once that there is no way out until it ends.
func test_a_battle_behind_its_gate_says_there_is_no_way_out() -> void:
	var lines: Array = []
	var on_message := func(text: String, kind: String) -> void: lines.append([text, kind])
	Events.hud_message.connect(on_message)
	var bailey := (load("res://scenes/test/bailey_test.tscn") as PackedScene).instantiate() as Node3D
	# The test bailey has no gate; give it the portcullis Fort Aldmere's battle shuts (a body and its shape,
	# where the battle's gate_path looks).
	var portcullis := StaticBody3D.new()
	portcullis.name = "ArenaGate"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(18, 13, 2)
	shape.shape = box
	portcullis.add_child(shape)
	portcullis.position = Vector3(0, 6.5, 60)
	bailey.add_child(portcullis)
	(bailey.get_node("BattleBoss") as BattleBoss).gate_path = ^"../ArenaGate"   # Fort Aldmere's battle's default
	world.add_child(bailey)
	await step_ticks(2)
	var bp := bailey.get_node("Player") as GiantPlayer
	bp.router.use_injection = true
	var battle := bailey.get_node("BattleBoss") as BattleBoss
	assert_true(battle.gate != null, "the bailey's gate")
	bp.global_position = Vector3(0, 0.05, 30)
	lines.clear()
	battle.engage()
	await step_ticks(2)
	assert_true(battle.is_gate_closed(), "the portcullis is down")
	# M9 gate (lane review): the battle's name mid-sentence reads "the Iron Regiment" (it was "until The Iron Regiment").
	assert_true(lines.has(["The portcullis drops behind you: no way out until the Iron Regiment is beaten.", "warn"]),
		"and the giant is told (%s)" % [lines])
	Events.hud_message.disconnect(on_message)

