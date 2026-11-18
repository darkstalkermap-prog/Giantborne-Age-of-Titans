extends IntegrationSuite
## The M8 gate's fix-up 2 (N4.6) on scenes/test/troll_den_test.tscn (moved here from
## tests/integration/test_boss_disengage.gd by P42, plan M10 §1.7 rule 4: the tick-by-tick walk is about
## 0.6 s of the default tier; the default suite keeps the talker's own ground, test_the_bosss_own_talker_
## beyond_the_line_is_the_fights_ground): the way from the line to the boss's own talker, as wide as its
## reach, is the fight's ground - walking out to the talker at the giant's pace and back warns nothing and
## resets nothing; beside that way, or past the talker, the disengage rule holds.

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
