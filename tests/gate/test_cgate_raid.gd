extends IntegrationSuite
## The milestone C gate (docs/systems/Cgate.md, finding G3): the Rimward's raid on Last Hearth decided by the giant.
## The raid fought in the real open world (deterministic streaming) at each of Last Hearth's tiers by the bots' own
## fighting (RaidFight: BotCombat for the novice profile, going for the raider nearest the folk), and the same raid with
## the giant standing idle at the bonfire: at tier 1 (no garrison) the idle giant loses the Hearth and the fighting one
## holds it; at tiers 2 and 3 the garrison alone does not hold it either, and with the giant fighting he, not the
## garrison, makes most of the kills.
##
## The measurement over several seeds (docs/systems/Cgate.md, "The raid"): the same suite with
## `-- --raid-matrix[=seeds]` prints a RAID line per run and asserts nothing more.

const SCENE := "res://scenes/world/world.tscn"
const LH := "settlement.last_hearth"
const BONFIRE := Vector2(-206.0, -1262.0)
const IDLE_AT := Vector2(-265.0, -1262.0)
var LIMIT_S := 300.0 if not OS.get_cmdline_user_args().has("--raid-short") else 90.0

var _w: WorldRoot


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 220.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 180.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(3)


## One raid: Last Hearth at `tier` (every tier's life come), the giant at `stage`, Sim and the bot seeded with `seed`.
## {"outcome", "s", "kills": {giant, garrison, other}, "folk_lost", "lowest_health", "giant_dead", "shots", "hits"}.
func raid(tier: int, stage: int, seed_value: int, idle: bool) -> Dictionary:
	await TestWait.duel_start(self)
	Sim.reseed(seed_value)
	GameSession.start_world_for_tests("world.cp.last_hearth")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.set_flag("act.two.begun", true)
	if tier > 0:
		SettlementWork.debug_set_tier(SettlementRules.record(LH), tier, true)
	_w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(_w)
	_w.streamer.deterministic = true
	var p := _w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(_w, p)
	await _place(_w, BONFIRE)
	TitanDuel.prepare(p, stage)
	await step_ticks(90)
	var out := {"outcome": "", "s": 0.0, "kills": {}, "folk_lost": 0, "lowest_health": 1.0, "giant_dead": false,
		"shots": 0, "hits": 0}
	var wd := _w.get_node_or_null("WanderDirector") as WanderDirector
	if wd == null or not wd.events.has("event.hearth_raid"):
		return out
	var ev: WorldEvent = wd.events["event.hearth_raid"]
	var bot := RaidFight.new()
	var skill := BotCombat.NOVICE
	for a in OS.get_cmdline_user_args():
		if a == "--raid-skill=expert":
			skill = BotCombat.EXPERT
	bot.setup(p, skill, seed_value, idle)
	if _trace:
		print("    TRACE target_points %s" % str(wd.target_points(ev)))
	wd.start_event(ev)
	if idle:
		# what the raiders do without him: he stands off behind the hall, 60 m west of the bonfire (near enough that the folk and the raiders stay in play, beyond the raiders' 24 m)
		p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
		await _place(_w, IDLE_AT)
	var garrison := get_tree().get_first_node_in_group("settlement_garrisons") as SettlementGarrison
	var t0 := Sim.tick
	var limit := int(LIMIT_S * Sim.TICK_RATE)
	while Sim.tick - t0 < limit:
		var o := str(WorldState.get_flag("event.hearth_raid.outcome", ""))
		if o != "" and not ev.is_running():
			out.outcome = o
			break
		if not p.entity.is_alive():
			out.outcome = "giant_dead"
			break
		bot.tick(Sim.tick)
		if _trace and (Sim.tick - t0) % 300 == 0:
			_trace_line(p, bot, Sim.tick - t0)
		await step_ticks(1)
	out.s = snappedf(float(Sim.tick - t0) / Sim.TICK_RATE, 0.1)
	out.kills = bot.kills.duplicate()
	out.folk_lost = bot.folk_lost
	out.lowest_health = snappedf(bot.lowest_health, 0.01)
	out.taken = bot.taken.duplicate()
	out.dealt = bot.dealt
	out.garrison_dealt = bot.garrison_dealt
	out.health_max = p.entity.combatant.pools.health_max
	out.giant_dead = bot.giant_dead or not p.entity.is_alive()
	out.shots = garrison.shots if garrison != null else 0
	out.hits = garrison.hits if garrison != null else 0
	bot.teardown()
	print("    RAID %s" % JSON.stringify({"tier": tier, "stage": stage, "seed": seed_value, "idle": idle, "result": out}))
	_w.queue_free()
	_w = null
	await step_ticks(2)
	return out


var _trace := OS.get_cmdline_user_args().has("--raid-trace")


func _trace_line(p: GiantPlayer, bot: RaidFight, dt: int) -> void:
	var parts := PackedStringArray()
	for r in bot.raiders():
		var e := r.entity
		var tgt := str(r.brain.target_id) if r.brain != null else "?"
		parts.append("%s@(%.0f,%.0f) hp%.0f %s>%s" % [e.entity_id.get_slice("_", 2), r.global_position.x, r.global_position.z,
			e.combatant.pools.health, EnemyBrain.STATE_NAMES[r.brain.state] + str(r.brain.patrol_points.size()) + ("F" if r.brain.formation_id != "" else ""), tgt])
	for c in get_tree().get_nodes_in_group("civilians"):
		var cv := c as Civilian
		if cv != null and cv.entity != null and cv.entity.entity_id.contains("hearth_folk"):
			parts.append("%s(%.0f,%.0f)st%d%s" % [cv.entity.entity_id.get_slice("_", 2), cv.global_position.x, cv.global_position.z,
				int(cv.brain.state), "S" if cv.sheltered else ""])
	var t := bot.combat.target
	print("    TRACE %.0fs giant(%.0f,%.0f) hp%.2f tgt=%s folk_lost=%d | %s" % [dt / 60.0, p.global_position.x, p.global_position.z,
		p.entity.combatant.pools.health / p.entity.combatant.pools.health_max, t.entity.entity_id if t != null and is_instance_valid(t) else "-",
		bot.folk_lost, " ".join(parts)])


func _matrix_seeds() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--raid-matrix"):
			var n := int(a.get_slice("=", 1)) if a.contains("=") else 3
			return range(1, maxi(1, n) + 1)
	return []


func test_the_giant_decides_the_raid() -> void:
	var seeds := _matrix_seeds()
	if not seeds.is_empty():
		var tiers := [1, 2, 3]
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--raid-tier="):
				tiers = [int(a.get_slice("=", 1))]
		var stg := 6
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--raid-stage="):
				stg = int(a.get_slice("=", 1))
		for tier: int in tiers:
			for s: int in seeds:
				await raid(tier, stg, s, false)
				if not OS.get_cmdline_user_args().has("--raid-no-idle"):
					await raid(tier, stg, s, true)
		return
	# tier 1: the Hearth has only him
	var only := OS.get_cmdline_user_args().has("--raid-one")
	if only:
		await raid(1, 6, 1, OS.get_cmdline_user_args().has("--raid-idle"))
		return
	var idle1 := await raid(1, 6, 1, true)
	assert_eq(str(idle1.outcome), "fell", "tier 1, the giant idle: the raiders reach the folk and the Hearth falls (%s)" % str(idle1))
	var fight1 := await raid(1, 6, 1, false)
	assert_eq(str(fight1.outcome), "defended", "tier 1, the giant fighting: the Hearth holds (%s)" % str(fight1))
	assert_eq(int(fight1.folk_lost), 0, "tier 1: no folk lost while he fights")
	assert_false(bool(fight1.giant_dead), "tier 1: a stage-6 novice survives it")
	# tier 3: six archers and the great bow thin the raid, but they cannot end it alone
	LIMIT_S = 150.0
	var idle3 := await raid(3, 6, 1, true)
	assert_ne_str(str(idle3.outcome), "defended", "tier 3, the giant idle: the garrison alone does not beat the raid back (%s)" % str(idle3))
	LIMIT_S = 300.0
	var fight3 := await raid(3, 6, 1, false)
	assert_eq(str(fight3.outcome), "defended", "tier 3, the giant fighting: it holds (%s)" % str(fight3))
	var share := float(fight3.dealt) / maxf(1.0, float(fight3.dealt) + float(fight3.garrison_dealt))
	assert_true(share >= 0.6, "tier 3: the giant deals most of the raiders' wounds (%.2f: %d against the garrison's %d)" % [
		share, int(fight3.dealt), int(fight3.garrison_dealt)])
	assert_true(int(fight3.shots) > int(fight3.hits), "tier 3: the garrison's arrows can miss (%d shots, %d hits)" % [
		int(fight3.shots), int(fight3.hits)])


func assert_ne_str(got: String, not_this: String, msg: String) -> void:
	assert_true(got != not_this, msg)
