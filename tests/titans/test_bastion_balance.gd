extends IntegrationSuite
## C2: the balance evidence for the Broken Warden (docs/BALANCE_LOG.md, "C2"): bot duels in the toll-keep yard test
## arena (scenes/test/bastion_test.tscn), his AI on (the arena wakes him), a giant readied for each stage
## (TitanDuel.prepare) and played by TitanDuelBot - the expert's fighting with the titans' rules and his own (get off
## his shield's side and round to his back and his broken right side; heavies into his guard when it is nearly
## broken; his bar's blow's recovery, his guard down; bait his wall charge into his walls; bring a crumbling tower
## down on him; his greaves for the topple; his downs). One attempt each, no respawn. The owner's claims:
##   * stage 4: deadly - the giant dies in every duel, never winning;
##   * stage 5: a hard fight - it wins about two duels of three, in roughly three to six minutes, his blows landing;
##   * stage 6: fair - it wins every duel.
## And the fight repeats: the same seed fights the same first minute tick for tick, another seed differs.
## Every duel is printed as one C2_DUEL line (the log's table). The titans' tier (--titans; --gate runs it).
##
## One duel alone (a probe while tuning; nothing else runs):
##   tools/run_tests.sh --titans --suite=res://tests/titans/test_bastion_balance.gd --c2-duel=<stage>:<seed>[:<max s>[:trace]]
## (a fourth field prints a C2_TRACE line a second: the distance, both healths, his action, his guard, the bot's rule;
## --c2-film with a display and --write-movie films it through the giant's camera).

const YARD := "res://scenes/test/bastion_test.tscn"
const SEEDS := [1, 2, 3]
const PROBE := "--c2-duel="
## With a display and --write-movie: the duel's own viewport drawn full screen (the giant's camera), to film a duel.
const FILM := "--c2-film"


static func probe_arg() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PROBE):
			return arg.substr(PROBE.length()).split(":")
	return PackedStringArray()


func _film(host: SubViewport) -> void:
	host.size = Vector2i(1280, 720)
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "DuelFilm"
	var view := TextureRect.new()
	view.texture = host.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(view)
	host.get_parent().add_child(layer)


func _setup(stage: int, seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()   # (the towers of an earlier duel would come back fallen)
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(YARD) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	var host := TestWait.duel_host(world)
	host.add_child(level)   # (B5: its own physics space)
	if OS.get_cmdline_user_args().has(FILM):
		_film(host)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)   # (each duel on a whole second)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Bastion") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 26)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt)
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true   # (his yard's walls and towers stand in his fight, as the Rootwarden's grove does)
	bot.setup(p, t, "expert", seed_value, true)
	return {"level": level, "player": p, "titan": t, "bot": bot}


func _duel(stage: int, seed_value: int, max_s: float) -> Dictionary:
	var s := await _setup(stage, seed_value)
	var p: GiantPlayer = s.player
	var t: TitanEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var open_ticks := 0
	var trace := not probe_arg().is_empty() and probe_arg().size() > 3
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if not t.guard_raised() and not t.disarmed:
			open_ticks += 1
		if trace and (Sim.tick - start) % 60 == 0:
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			print("C2_TRACE t=%.0f d=%.1f stamina=%.0f giant=%.0f him=%.0f act=%s guard=%s/%.2f rule=%s" % [
				(Sim.tick - start) / 60.0, rel.length(), p.entity.combatant.pools.stamina, p.entity.combatant.pools.health,
				t.entity.combatant.pools.health, t.controller.action_id(), str(t.guard_raised()), t.plates().guard_frac(),
				bot.last_rule])
		if not p.entity.is_alive():
			died_at = Sim.tick - start
			break
		if not t.entity.is_alive():
			killed_at = Sim.tick - start
			break
	bot.teardown()
	var blows := 0
	var dealt := 0
	var by_action := {}
	var by_plate := {}
	var guarded := 0
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.bastion_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id:
			if r.event.guarded:
				guarded += 1
				if r.event.has_tag("Heavy"):
					bot.guard_heavies += 1
			if r.health_damage > 0:
				dealt += r.health_damage
				var key := "%s:%s" % [r.event.plate_id, "guarded" if r.event.guarded else r.event.plate_state]
				by_plate[key] = int(by_plate.get(key, 0)) + r.health_damage
	var out := {"stage": stage, "seed": seed_value, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "disarmed": t.disarmed,
		"guarded": guarded, "guard_breaks": t.guard_breaks, "rubble": t.rubble_falls, "reels": t.wall_stops,
		"topples": t.topples, "open_s": snappedf(open_ticks / 60.0, 0.1), "dealt": dealt, "dealt_by": by_plate,
		"hit_by": by_action, "flank_s": snappedf(bot.flank_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "down_heavies": bot.down_heavies,
		"guard_heavies": bot.guard_heavies, "towers": bot.towers_felled, "hugs": (t.brain as TitanBrain).hug_answers,
		"flanks": (t.brain as TitanBrain).flank_answers,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("C2_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out


## The probe: one duel (--c2-duel=stage:seed[:max s]); the other tests do nothing while it is given.
func test_probe_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(int(a[0]), int(a[1]) if a.size() > 1 else 1, float(a[2]) if a.size() > 2 else 480.0)


func test_stage_4_giants_die() -> void:
	if not probe_arg().is_empty():
		return
	var died := 0
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(4, seed_value, 480.0)
		if float(d.giant_died_s) > 0.0:
			died += 1
		if float(d.titan_killed_s) > 0.0:
			won += 1
		assert_true(float(d.titan_left) > 0.3, "stage 4 seed %d: far from bringing him down (%.2f left)" % [seed_value,
			float(d.titan_left)])
	assert_true(died >= 2, "stage 4: deadly - the giant dies in most duels (%d of %d)" % [died, SEEDS.size()])
	assert_eq(won, 0, "stage 4: never a win")


func test_stage_5_giants_win_a_hard_fight() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(5, seed_value, 600.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 150.0, "stage 5 seed %d: a hard fight, not a rout (%.0f s)" % [
				seed_value, float(d.titan_killed_s)])
			assert_true(int(d.blows_taken) >= 3, "stage 5 seed %d: his blows land (%d)" % [seed_value,
				int(d.blows_taken)])
		assert_true(int(d.guarded) >= 1, "stage 5 seed %d: his guard caught blows (%d)" % [seed_value, int(d.guarded)])
	assert_true(won >= 1 and won <= 3, "stage 5: wins a hard fight (%d of %d)" % [won, SEEDS.size()])


func test_stage_6_giants_win_a_fair_fight() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(6, seed_value, 600.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 90.0, "stage 6 seed %d: a fight of minutes (%.0f s)" % [seed_value,
				float(d.titan_killed_s)])
		assert_true(int(d.phase) == 2 or float(d.titan_killed_s) > 0.0, "stage 6 seed %d: his second phase" % seed_value)
	assert_true(won >= 2, "stage 6: the giant wins (%d of %d)" % [won, SEEDS.size()])


## The same seed fights the same first minute (every hit, the plates' stone and the guard's meter, his sequence), another
## seed another.
func test_a_seeded_duel_repeats() -> void:
	if not probe_arg().is_empty():
		return
	var a := await _record(2)
	var b := await _record(2)
	var c := await _record(5)
	assert_true((a.hits as Array).size() > 10, "a real fight (%d hits)" % (a.hits as Array).size())
	assert_eq(a, b, "the same seed: the same fight, tick for tick")
	assert_true(a.hits != c.hits or a.log != c.log, "another seed: another fight")


func _record(seed_value: int) -> Dictionary:
	var s := await _setup(5, seed_value)
	var p: GiantPlayer = s.player
	var t: TitanEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	while Sim.tick - start < 60 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	var rec: Array = []
	for r in hits:
		rec.append([r.event.tick - start, r.event.attacker_id, r.event.action_id, r.event.target_id, r.event.region,
			r.event.plate_id, r.event.guarded, r.outcome, r.health_damage])
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"guard_breaks": t.guard_breaks, "rubble": t.rubble_falls,
		"titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out
