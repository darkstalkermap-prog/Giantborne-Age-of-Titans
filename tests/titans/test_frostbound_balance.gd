extends IntegrationSuite
## D1: the balance evidence for the Frostbound Titan (docs/BALANCE_LOG.md, "D1"): bot duels in the frozen tarn test
## arena (scenes/test/frostbound_test.tscn: the tarn's ice, two balefires on its shore), his AI on (the arena wakes him:
## his intro first), a giant readied for each stage (TitanDuel.prepare) and played by TitanDuelBot - the expert's
## fighting with the titans' rules and the cold's (a heavy to shatter the ice when frozen fast; to a balefire to thaw
## when the rime is high; his greaves for the topple; his downs - the ice's too). One attempt each, no respawn. The
## owner's claims ("a deadly titan that can kill you until you max out in the area"):
##   * stage 6: deadly - the giant dies in every duel, never winning;
##   * stage 7: hard but fair - it wins at least one duel of three and dies in at least one, its wins a fight of
##     minutes with his blows landing and the cold on it;
##   * stage 8: beatable - it wins every duel.
## And the fight repeats: the same seed fights the same first minute tick for tick, another seed differs.
## Every duel is printed as one D1_DUEL line (the log's table). The titans' tier (--titans; --gate runs it).
##
## One duel alone (a probe while tuning; nothing else runs):
##   tools/run_tests.sh --titans --suite=res://tests/titans/test_frostbound_balance.gd --d1-duel=<stage>:<seed>[:<max s>[:trace]]
## (a fourth field prints a D1_TRACE line a second: the distance, both healths, his action, the rime, the bot's rule;
## --d1-film with a display and --write-movie films it through the giant's camera).

const TARN := "res://scenes/test/frostbound_test.tscn"
const SEEDS := [1, 2, 3]
const PROBE := "--d1-duel="
## With a display and --write-movie: the duel's own viewport drawn full screen (the giant's camera), to film a duel.
const FILM := "--d1-film"


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
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(TARN) as PackedScene).instantiate() as Node3D
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
	var t := level.get_node("Frostbound") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 30)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt)
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true   # (the tarn's seracs stand at its edge)
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
	var trace := not probe_arg().is_empty() and probe_arg().size() > 3
	var rime_peak := 0.0
	var rime_sum := 0.0
	var frozen_ticks := 0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		rime_peak = maxf(rime_peak, p.rime.rime)
		rime_sum += p.rime.rime
		if p.rime.is_frozen():
			frozen_ticks += 1
		if trace and (Sim.tick - start) % 60 == 0:
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			print("D1_TRACE t=%.0f d=%.1f stamina=%.0f giant=%.0f him=%.0f act=%s rime=%.0f%s phase=%d rule=%s" % [
				(Sim.tick - start) / 60.0, rel.length(), p.entity.combatant.pools.stamina, p.entity.combatant.pools.health,
				t.entity.combatant.pools.health, t.controller.action_id(), p.rime.rime, " FROZEN" if p.rime.is_frozen()
				else "", t.brain.boss_phase(), bot.last_rule])
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
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.frostbound_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id:
			if r.health_damage > 0:
				dealt += r.health_damage
				var key := "%s:%s" % [r.event.plate_id, r.event.plate_state]
				by_plate[key] = int(by_plate.get(key, 0)) + r.health_damage
	var sheet := level_ice(s)
	var out := {"stage": stage, "seed": seed_value, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(),
		"topples": t.topples, "ice_falls": t.ice_falls, "dealt": dealt, "dealt_by": by_plate,
		"hit_by": by_action, "flank_s": snappedf(bot.flank_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "down_heavies": bot.down_heavies,
		"hugs": (t.brain as TitanBrain).hug_answers, "flanks": (t.brain as TitanBrain).flank_answers,
		"rime_peak": snappedf(rime_peak, 0.1), "rime_mean": snappedf(rime_sum / maxf(1.0, float(Sim.tick - start)), 0.1),
		"freezes": p.rime.freezes, "shatters": p.rime.shatters, "frozen_s": snappedf(frozen_ticks / 60.0, 0.1),
		"rime_by": p.rime.gained, "thaws": bot.thaws, "thaw_s": snappedf(bot.thaw_ticks / 60.0, 0.1),
		"aura_rime": snappedf(t.aura_rime, 0.1), "ice": sheet.counts() if sheet != null else {},
		"ice_by": sheet.by if sheet != null else {},
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("D1_DUEL " + JSON.stringify(out))
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


func test_stage_6_giants_die() -> void:
	if not probe_arg().is_empty():
		return
	var died := 0
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(6, seed_value, 480.0)
		if float(d.giant_died_s) > 0.0:
			died += 1
		if float(d.titan_killed_s) > 0.0:
			won += 1
		assert_true(float(d.titan_left) > 0.3, "stage 6 seed %d: far from bringing him down (%.2f left)" % [seed_value,
			float(d.titan_left)])
		assert_true(int(d.freezes) >= 1 or float(d.rime_peak) >= 80.0, "stage 6 seed %d: the cold took hold (%s)" % [
			seed_value, str(d.rime_peak)])
	assert_eq(died, SEEDS.size(), "stage 6: deadly - the giant dies in every duel (%d of %d)" % [died, SEEDS.size()])
	assert_eq(won, 0, "stage 6: never a win")


func test_stage_7_giants_fight_a_hard_fair_fight() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	var died := 0
	for seed_value: int in SEEDS:
		var d := await _duel(7, seed_value, 720.0)
		if float(d.giant_died_s) > 0.0:
			died += 1
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 150.0, "stage 7 seed %d: a hard fight, not a rout (%.0f s)" % [
				seed_value, float(d.titan_killed_s)])
			assert_true(int(d.blows_taken) >= 4, "stage 7 seed %d: his blows land (%d)" % [seed_value,
				int(d.blows_taken)])
		assert_true(float(d.rime_peak) >= 40.0, "stage 7 seed %d: the cold on it (%s)" % [seed_value, str(d.rime_peak)])
	assert_true(won >= 1, "stage 7: fair - it can be won (%d of %d)" % [won, SEEDS.size()])
	assert_true(died >= 1, "stage 7: hard - he kills it in at least one duel (%d of %d)" % [died, SEEDS.size()])


func test_stage_8_giants_win() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(8, seed_value, 720.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 90.0, "stage 8 seed %d: a fight of minutes (%.0f s)" % [seed_value,
				float(d.titan_killed_s)])
		assert_true(int(d.phase) >= 2 or float(d.titan_killed_s) > 0.0, "stage 8 seed %d: his second phase" % seed_value)
	assert_eq(won, SEEDS.size(), "stage 8: beatable - the giant wins every duel (%d of %d)" % [won, SEEDS.size()])


## The same seed fights the same first minute (every hit, the plates' ice, the rime and the tarn's ice, his sequence), another
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
	var s := await _setup(7, seed_value)
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
	var sheet := level_ice(s)
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"rime": snappedf(p.rime.rime, 0.001), "ice": sheet.counts() if sheet != null else {}, "falls": t.ice_falls,
		"titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out


func level_ice(s: Dictionary) -> IceSheet:
	return (s.level as Node).get_node_or_null("Ice") as IceSheet
