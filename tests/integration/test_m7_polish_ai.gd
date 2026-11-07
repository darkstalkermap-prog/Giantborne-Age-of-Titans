extends IntegrationSuite
## M7 polish, lane B (AI, formations and navigation; the M7 gate review's findings and the gate's own
## follow-ups; the slow half on the real world is tests/slow/test_m7_polish_world.gd):
##   * a formation whose members all flee at the same moment while its banner lives is broken, not
##     routed for good: once they regroup (above ai.regroup_morale, their banner their leader) it forms
##     again and they hold their slots (they used to come back as loose soldiers - no brace, no slot -
##     under a formation stuck in "routed"); it still routs for good when every member routed, or when
##     none stands and its banner is dead.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	await super()


# --------------------------------------------------------------------------- formations: flight is not a rout

## A stage-4 giant at `pos` facing -Z (its profile set directly: the growth path is P05's and P26's).
func _stage_4_giant(pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	assert_eq(int(p.current_growth_stage()), 4, "a stage-4 giant")
	return p


## Three pikemen in one rank facing +Z at the origin and their banner behind them, AI on (the
## reviewer's probe), braced at 6 m and holding their ground (no advance).
func _rank_with_banner(id: String) -> Formation:
	var f := Formation.new()
	f.id = id
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.ranks = 1
	f.files = 3
	f.rank_spacing_m = 2.2
	f.file_spacing_m = 1.6
	f.brace_m = 6.0
	f.brace_action = "ability.formation_brace_pike"
	f.place(Vector3.ZERO, PI)
	Formation.register(f)
	for i in 3:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i) + Vector3(0, 0.05, 0), "%s_%d" % [id, i], true, PI), i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT) + Vector3(0, 0.05, 0),
		"%s_banner" % id, true, PI))
	return f


## Steps `ticks` ticks with the formation updated ten times a second, as the director does; returns
## every state it passed through.
func _run(f: Formation, threat: Node3D, ticks: int) -> Array[String]:
	var seen: Array[String] = []
	for i in ticks:
		await step_ticks(1)
		if Sim.tick % Formation.UPDATE_TICKS == 0:
			f.update(Sim.tick, threat)
			if seen.is_empty() or seen[-1] != f.state:
				seen.append(f.state)
	return seen


func _states(f: Formation) -> String:
	var out := PackedStringArray()
	for m in f.members:
		out.append("%s %s morale %.0f hold %s" % [m.entity_id.get_slice(".", 2), m.brain.state_name(), m.brain.morale,
			m.brain.formation_hold])
	return ", ".join(out)


func test_a_formation_whose_members_all_flee_at_once_regroups_to_its_slots_while_its_banner_lives() -> void:
	var p := _stage_4_giant(Vector3(0, 0.05, 14.0))   # 13 m before the rank: aware, not braced
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var f := _rank_with_banner("test.polish.regroup")
	await _run(f, p, 60)
	assert_true(f.is_intact() and f.aware, "the rank stands and knows the giant (%s, %s)" % [f.state, _states(f)])
	# every member drops to 15 at once (two Titan Roars at x1.5 can do that at stage 5)
	for m in f.members:
		m.brain.apply_morale(15.0 - m.brain.morale, "script", Sim.tick)
	var during := await _run(f, p, 30)
	var fled := 0
	for m in f.members:
		if m.brain.state == EnemyBrain.AIState.FLEE:
			fled += 1
	assert_eq(fled, 3, "all three fled at once (%s)" % _states(f))
	assert_true(f.banner_alive(), "their banner lives")
	assert_false(during.has("routed"), "a formation whose members only fled, its banner alive, is not routed (%s)" % [during])
	assert_eq(f.state, "broken", "it is broken while they flee")
	# their morale comes back (+60): past ai.regroup_morale, with the banner to lead them, they regroup
	for m in f.members:
		m.brain.apply_morale(60.0, "rally", Sim.tick)
	var after := await _run(f, p, int(EnemyBrain.MIN_FLEE_S * Sim.TICK_RATE) + 60)
	assert_false(after.has("routed"), "never routed (%s)" % [after])
	assert_true(f.is_intact(), "the formation formed again once they regrouped (%s; %s)" % [f.state, _states(f)])
	for m in f.members:
		assert_true(m.brain.formation_hold, "%s holds its slot again (%s)" % [m.entity_id, _states(f)])
		assert_eq(m.brain.state, EnemyBrain.AIState.HOLD, "%s stands in its slot (%s)" % [m.entity_id, m.brain.state_name()])
	# routed for good: every member routed (a routed unit never regroups), though the banner stands
	for m in f.members:
		m.p30_force_rout()
	await _run(f, p, 12)
	assert_eq(f.state, "routed", "every member routed: routed, though the banner stands")
	assert_true(f.banner_alive(), "(the banner still stands)")


func test_a_formation_whose_banner_fell_routs_when_none_stands() -> void:
	var p := _stage_4_giant(Vector3(0, 0.05, 14.0))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var f := _rank_with_banner("test.polish.leaderless")
	await _run(f, p, 30)
	queue_hit(p.entity.entity_id, f.banner.entity_id, p.global_position, 100000.0)
	await step_ticks(1)
	assert_false(f.banner_alive(), "the banner fell")
	for m in f.members:
		m.brain.apply_morale(15.0 - m.brain.morale, "script", Sim.tick)
	var seen := await _run(f, p, 30)
	var fleeing := 0
	for m in f.members:
		if m.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]:
			fleeing += 1
	assert_eq(fleeing, 3, "all three fled (%s)" % _states(f))
	assert_true(seen.has("routed") and f.state == "routed", "none stands and no banner leads them back: routed (%s)" % [seen])
