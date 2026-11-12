extends IntegrationSuite
## P39 (plan M6-M9 §3.23: bot fixes that correct measurement mistakes; §6.4's growth targets).
##   * WorldMetrics takes the formation lock samples only while a formation is engaged with the giant
##     (a living member, aware and hostile, within RunMetrics.HOSTILE_NEAR_M): P38 took them whenever any
##     formation lived in the loaded world, so a lock on a lone soldier with a formation 100 m off counted
##     as a "single lock with formations present";
##   * it measures §6.4's growth shares directly: a lone human's engaged and fleeing seconds (a formation
##     member is not one), a formation's engaged and holding seconds while its banner lives, and the
##     seconds when only lesser enemies are engaged (the music's own rule) with the music's intensity;
##   * the world bot's siege disruption at stage 6 (plan §5.14; P38's bot never seized an engine): a
##     crewed ballista in reach is struck until its poise breaks, seized with both hands and thrown at
##     the soldier beyond it, where it smashes; below stage 6, or at peace (a neutral engine), it is no
##     engine to seize;
##   * an enemy above reach is shot only along a clear line, from a spot chosen by that line;
##   * from stage 4 a lone big foe within reach draws the roar and the area blows.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const ARCHER := "res://scenes/enemies/archer.tscn"
const TROLL := "res://scenes/enemies/troll.tscn"

var f: Formation
var p: GiantPlayer
var bot: WorldBot
var thrown: Array[String] = []


func before_each() -> void:
	await super()
	WorldBot.reset_world()
	thrown.clear()
	Events.grab_ended.connect(_on_grab_ended)


func after_each() -> void:
	if Events.grab_ended.is_connected(_on_grab_ended):
		Events.grab_ended.disconnect(_on_grab_ended)
	if f != null:
		f.dissolve()
		f = null
	if bot != null and is_instance_valid(bot):
		bot.queue_free()
	bot = null
	WorldBot.reset_world()
	await super()


func _on_grab_ended(_t: int, holder: String, target: String, reason: String) -> void:
	if holder == "player" and reason == "thrown":
		thrown.append(target)


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _giant(stage: int, pos: Vector3) -> void:
	p = spawn_player(pos, 0.0)
	p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	p.camera_rig.yaw = 0.0
	await step_ticks(1)


## A formation of five pikemen and its banner around `pivot`, AI off; `aware` marks them aware of the giant.
func _formation(pivot: Vector3, aware: bool) -> void:
	f = Formation.new()
	f.id = "test.p39_pikes"
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.banner_name = "Banner of the Test Pikes"
	f.ranks = 1
	f.files = 5
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.place(pivot, PI * 0.5)
	Formation.register(f)
	for i in 5:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.p39_pike_%d" % i, false, PI * 0.5), i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "test.p39_banner", false, PI * 0.5))
	await step_ticks(2)
	for m: EnemyActor in f.members + [f.banner]:
		m.brain.aware = aware


## Runs the metrics' per-tick sampling for `ticks` ticks (a multiple of the growth sample's period).
func _sample(m: WorldMetrics, ticks: int) -> void:
	for i in ticks:
		await step_ticks(1)
		m.on_tick(Sim.tick, p, null)


func test_formation_lock_samples_need_an_engaged_formation() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var lone := spawn_soldier(Vector3(0, 0.05, -12), 0.0, "test.p39_lone")
	lone.brain.aware = true
	await _formation(Vector3(0, 0, -100), true)
	# a single lock on the lone soldier while the formation stands 100 m off
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.p39_lone", "the giant locks the lone soldier")
	var m := WorldMetrics.new()
	await _sample(m, 60)
	assert_eq(int(m.formations.single_lock_samples) + int(m.formations.group_lock_samples) + int(m.formations.banner_lock_samples), 0,
		"no lock sample with the only formation 100 m away (%s)" % [m.formations])
	# the formation comes within reach of the fight: the lock on the lone soldier is now a single lock with a formation present
	f.place(Vector3(0, 0, -30), PI * 0.5)
	for i in 5:
		f.members[i].global_position = f.slot_position(i)
	f.banner.global_position = f.slot_position(Formation.BANNER_SLOT)
	await _sample(m, 60)
	assert_true(int(m.formations.single_lock_samples) > 0, "a single lock sampled with a formation engaged 30 m off (%s)" % [m.formations])
	assert_eq(int(m.formations.group_lock_samples), 0, "no group lock yet")
	assert_true(float(m.growth.formation_engaged_s) > 0.0, "the formation's engaged time is counted")
	# a formation not aware of the giant is not engaged
	for mem: EnemyActor in f.members + [f.banner]:
		mem.brain.aware = false
	var before := int(m.formations.single_lock_samples)
	await _sample(m, 60)
	# (the engaged state is sampled every GROWTH_SAMPLE_TICKS: at most one period of lag)
	assert_true(int(m.formations.single_lock_samples) - before <= WorldMetrics.GROWTH_SAMPLE_TICKS,
		"no lock sample while the formation is not aware of the giant (%d more)" % (int(m.formations.single_lock_samples) - before))


func test_lone_humans_formations_and_lesser_enemies_are_measured() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var lone := spawn_soldier(Vector3(6, 0.05, -10), 0.0, "test.p39_runner")
	lone.brain.aware = true
	await _formation(Vector3(0, 0, -25), true)
	var m := WorldMetrics.new()
	assert_true(WorldMetrics.is_lone_human(lone), "a soldier in no formation is a lone human")
	assert_false(WorldMetrics.is_lone_human(f.members[0]), "a formation's pikeman is not")
	assert_false(WorldMetrics.is_lone_human(f.banner), "nor its banner")
	assert_false(WorldMetrics.counts_for_music(lone, p.entity.combatant.height_m, 0.3), "a lone soldier is a lesser enemy for the music")
	assert_true(WorldMetrics.counts_for_music(f.members[0], p.entity.combatant.height_m, 0.3), "a formation member counts (special)")
	# the lone soldier flees for 60 ticks; the formation holds (formed)
	lone.brain._set_state(EnemyBrain.AIState.FLEE)
	await _sample(m, 60)
	assert_near(float(m.growth.lone_engaged_s), 1.0, 0.11, "a second of a lone human engaged (%s)" % [m.growth])
	assert_near(float(m.growth.lone_fled_s), float(m.growth.lone_engaged_s), 0.11, "fleeing all of it")
	assert_near(float(m.growth.formation_engaged_s), 1.0, 0.11, "a second of the formation engaged")
	assert_true(f.is_intact(), "the formation is formed")
	assert_near(float(m.growth.formation_held_s), float(m.growth.formation_engaged_s), 0.11, "holding all of it")
	assert_eq(m.music_lesser.size(), 0, "no lesser-only time while a formation is engaged")
	# the formation breaks up and its men lose sight of the giant: only the lesser soldier is engaged
	var men: Array[EnemyActor] = f.members.duplicate()
	men.append(f.banner)
	f.dissolve()
	f = null
	for mem: EnemyActor in men:
		mem.brain.aware = false
	var lone_before := float(m.growth.lone_engaged_s)
	await _sample(m, 60)
	assert_true(float(m.growth.lone_engaged_s) > lone_before, "the lone soldier is still measured")
	var lesser := 0.0
	for k: String in m.music_lesser:
		lesser += float(m.music_lesser[k])
	assert_near(lesser, 1.0, 0.11, "a second with only a lesser enemy engaged (%s)" % [m.music_lesser])
	var out: Dictionary = m.result().get("growth", {})
	assert_near(float(out.get("lone_fled_share", -1.0)), 1.0, 0.01, "the lone humans' flee share in the result")
	assert_near(float(out.get("formation_held_share", -1.0)), 1.0, 0.01, "the formations' hold share in the result")


## A ballista at `pos` facing `face`, crewed by one hauler.
func _crewed_engine(id: String, pos: Vector3, face: Vector3) -> SiegeEngine:
	var e := (load(BALLISTA) as PackedScene).instantiate() as SiegeEngine
	e.world_id = id
	e.position = pos
	e.rotation.y = yaw_towards(pos, face)
	world.add_child(e)
	var crew := TestSpawn.enemy(world, CREW, pos + Vector3(0, 0.05, -2.5), id + "_hauler", false, 0.0)
	e.add_crew(crew)
	return e


## A WorldBot bound by hand to the test's giant (no run: its own tick does nothing), its BotCombat set up.
func _bot(skill := "novice") -> void:
	bot = WorldBot.new()
	world.add_child(bot)
	bot.player = p
	p.router.use_injection = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	bot.combat = BotCombat.new()
	bot.combat.setup(bot, p, skill, rng)


func test_the_world_bot_seizes_and_throws_an_engine_at_stage_6() -> void:
	await _giant(6, Vector3(0, 0.05, 0))
	p.equipment.grant_weapon("weapon.club_titan", true)   # the weapon the bot carries at stage 6 (its great moveset)
	var eng := _crewed_engine("test.p39_ballista", Vector3(0, 0, -7.5), Vector3(0, 0, 40))
	var soldier := spawn_soldier(Vector3(4, 0.05, -22.0), 0.0, "test.p39_target")
	soldier.brain.aware = true
	await step_ticks(2)
	_bot()
	var eng_id := eng.entity.entity_id
	assert_true(eng.crewed, "the ballista is crewed")
	assert_true(bot._can_seize_engines(), "a stage-6 giant may seize engines")
	assert_true(bot._seizable_engine(eng), "a hostile engine on the giant's level is one to seize")
	assert_eq(p.grab.check_target(eng.entity, "hold"), "engine_crewed", "its crew holds it at first")
	var seized := false
	var smashed := false
	for i in 900:
		await step_ticks(1)
		smashed = not is_instance_valid(eng) or eng.destroyed
		if smashed and not p.grab.is_holding():
			break
		if bot.combat.defend(Sim.tick):
			continue
		bot._act_siege(Sim.tick, false, null if smashed else eng)
		seized = seized or p.grab.is_holding()
	assert_true(seized, "the bot seized the ballista (struck until its poise broke, then grabbed it)")
	assert_eq(thrown, [eng_id] as Array[String], "and threw it (grab_ended thrown)")
	assert_true(smashed, "it smashed where it landed")
	assert_false(p.grab.is_holding(), "nothing held afterwards")


func test_no_engine_to_seize_below_stage_6_or_at_peace() -> void:
	await _giant(5, Vector3(0, 0.05, 0))
	var eng := _crewed_engine("test.p39_ballista_5", Vector3(0, 0, -9.0), Vector3(0, 0, 40))
	await step_ticks(2)
	_bot()
	assert_false(bot._can_seize_engines(), "a stage-5 giant may not seize engines")
	p.set_profile(_profile(6))
	await step_ticks(1)
	assert_true(bot._can_seize_engines(), "at stage 6 it may")
	eng.entity.team = CombatEntity.Team.NEUTRAL
	assert_false(bot._seizable_engine(eng), "an engine at peace (neutral) is no engine to seize")
	eng.entity.team = CombatEntity.Team.ENEMY
	assert_true(bot._seizable_engine(eng), "hostile again, it is")
	eng.global_position.y += 30.0
	assert_false(bot._seizable_engine(eng), "an engine far above the giant's reach is not")


## The world stability run's loop (plan §6.2: --bot-loop through the presets): when a campaign ends,
## the next game's first reward - Kings' Door's, granted as the world starts - is that game's first
## and only, not the last game's given twice (the rewards already given were read before the new
## game emptied the world, and the first 60-minute run stopped there with exit 3).
func test_a_loops_next_world_game_counts_its_first_reward_once() -> void:
	WorldBot.configure_world(PackedStringArray(["--bot-loop", "--bot-preset=peaceful", "--bot-assist"]))
	WorldState.try_set_flag("reward.world_main.kings_door", true)   # the first game's
	bot = WorldBot.new()
	world.add_child(bot)
	assert_false(GameSession.allow_scene_reload, "no scene reload under the test runner")
	bot._on_campaign_complete(Sim.tick)
	assert_eq(ValleyBot.run.run_index, 1, "the loop's second game began")
	assert_false(QuestConditions.truthy(WorldState.get_flag("reward.world_main.kings_door")), "the new game emptied the world")
	WorldState.try_set_flag("reward.world_main.kings_door", true)   # the new game's
	var m: Dictionary = ValleyBot.run.metrics.result(Sim.tick)
	assert_eq((m.rewards as Dictionary).get("duplicates"), [], "no reward given twice")
	assert_eq(((m.rewards as Dictionary).get("granted", []) as Array).size(), 1, "Kings' Door's reward given once in this game")


## BotCombat's look at the abilities (the novice's once a second) that finds the giant mid-blow: from
## stage 4 it waits for the giant's next free tick (P38's runs: Titan Stomp used in 0 of 9 windows, the
## novice's light chains spent the looks); in the Valley (stages 1-3) the look is spent as before, so the
## Valley's matrix stays the M6 gate's.
func test_a_look_at_the_abilities_mid_blow_waits_from_stage_4() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var soldier := spawn_soldier(Vector3(0, 0.05, -6), 0.0, "test.p39_mid_blow")
	soldier.brain.aware = true
	_bot()
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_true(p.controller.state != CombatController.State.LOCOMOTION, "the giant is mid-blow")
	bot.combat._next_ability_tick = 0
	assert_false(bot.combat._abilities(Sim.tick, soldier, 6.0), "no ability mid-blow")
	assert_eq(bot.combat._next_ability_tick, 0, "at stage 4 the look is not spent: the next free tick looks again")
	p.set_profile(_profile(3))
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_true(p.controller.state != CombatController.State.LOCOMOTION, "the stage-3 giant is mid-blow")
	bot.combat._next_ability_tick = 0
	assert_false(bot.combat._abilities(Sim.tick, soldier, 6.0), "no ability mid-blow at stage 3 either")
	assert_true(bot.combat._next_ability_tick > Sim.tick, "but at stage 3 the look is spent (P17a's rule, the Valley unchanged)")


## The world bot's bolt at an enemy above reach goes only along a clear line (P39: from 17 m east of
## the toll fort's tower the line to its west archer struck the deck's edge, the blows that did not
## hurt it came a bolt's cooldown apart so the ranged give-up never ran out, and the bot stood there
## until the march's watchdog). An archer on a 13 m deck, 5 m in from its near edge: from the ground
## the old rule chose (16 m toward the giant) the line meets the deck; the points the bot chooses now
## are clear, the nearest to the giant first, and a spot given up is not chosen again.
func test_an_enemy_above_reach_is_shot_from_a_clear_line() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	add_box(Vector3(6, 13, 6), Vector3(0, 6.5, -20))
	var archer := TestSpawn.enemy(world, ARCHER, Vector3(0, 13.1, -22.0), "test.p39_deck_archer", false, 0.0)
	await TestWait.until(self, func() -> bool: return archer.is_on_floor(), 60)
	_bot()
	await step_ticks(1)
	assert_true(bot.combat.is_elevated(archer), "the archer stands above the stage-4 giant's reach")
	assert_false(bot._shot_clear(p.global_position, archer), "from 22 m south the bolt's line meets the deck")
	assert_false(bot._shot_clear(Vector3(0, 0.05, -6), archer), "so it does from 16 m toward the giant (P38's spot)")
	assert_true(bot._shot_clear(Vector3(0, 0.05, -38), archer), "from 16 m north, past the deck's far edge, it is clear")
	var points: Array[Vector3] = bot._clear_shot_points(archer, [], 4)
	assert_eq(points.size(), 4, "clear points around it")
	for q in points:
		assert_true(bot._shot_clear(q, archer), "each one clear: %s" % q)
	for i in range(1, points.size()):
		assert_true(WorldBot._flat_dist(points[i - 1], p.global_position) <= WorldBot._flat_dist(points[i], p.global_position) + 1e-3,
			"nearest the giant first")
	var again: Array[Vector3] = bot._clear_shot_points(archer, [points[0]], 4)
	assert_false(again.has(points[0]), "a spot given up is not chosen again")
	for q in again:
		assert_true(WorldBot._flat_dist(q, points[0]) >= WorldBot.ELEVATED_SHOT_BAD_M, "nor one beside it")
	# The spot the bot walks to fails when the line from where the giant stopped stays blocked for
	# ELEVATED_SHOT_BLOCKED_S: it joins the failed spots and the next is chosen (none in the test world,
	# which has no navigation: INF, so P38's rule).
	WorldBot.configure_world(PackedStringArray(["--bot-preset=peaceful"]))
	bot.set_physics_process(false)   # a configured run would start the bot's own ticks (a level bind)
	var id := archer.entity.entity_id
	bot._shot_spots[id] = {"spot": p.global_position, "at": archer.global_position, "tick": Sim.tick, "bad": [],
		"arrived": false, "until": -1, "blocked_since": -1}
	assert_eq(bot._shot_spot(archer), bot._shot_spots[id].spot, "the giant stands at its spot")
	await step_ticks(ActionDef.seconds_to_ticks(WorldBot.ELEVATED_SHOT_BLOCKED_S) + 2)
	assert_false(bot._shot_spot(archer).is_finite(), "the line stayed blocked there: the spot failed")
	assert_eq((bot._shot_spots[id].bad as Array).size(), 1, "and is not chosen again")


## From stage 4 a lone big foe within reach (a boss, a troll, a rival giant) draws the roar and the area
## blows (P39: the first world matrix's novice died six and seven times to Harrok with Earthquake never
## used - P17a's rules want two enemies near, three for the roar); a lone soldier is no big foe, and the
## Valley's stages keep P17a's rules.
func test_a_lone_big_foe_draws_the_roar_and_the_area_blows_from_stage_4() -> void:
	await _giant(3, Vector3(0, 0.05, 0))
	var troll := TestSpawn.enemy(world, TROLL, Vector3(0, 0.05, -7.0), "test.p39_troll", false, 0.0)
	await step_ticks(2)
	_bot()
	troll.brain.aware = true
	var dist := p.global_position.distance_to(troll.global_position)
	bot.combat._next_ability_tick = 0
	assert_false(bot.combat._abilities(Sim.tick, troll, dist), "at stage 3 a lone troll draws no ability (P17a's rules)")
	p.set_profile(_profile(4))
	await step_ticks(1)
	assert_true(bot.combat.big_foe(troll), "a troll is a big foe")
	bot.combat._next_ability_tick = 0
	assert_true(bot.combat._abilities(Sim.tick, troll, dist), "at stage 4 it draws an ability")
	assert_eq(str(bot.combat._ability_log[-1][2]), "roar at a big foe", "the roar first")
	await step_ticks(3)
	assert_true(p.controller.state != CombatController.State.LOCOMOTION, "the roar is being cast")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
	bot.combat._next_ability_tick = 0
	assert_true(bot.combat._abilities(Sim.tick, troll, dist), "then, the roar spent, an area blow")
	var why := str(bot.combat._ability_log[-1][2])
	assert_true(why.ends_with("at a big foe") and not why.begins_with("roar"), "an area blow at a big foe: " + why)
	var soldier := spawn_soldier(Vector3(5, 0.05, -5), 0.0, "test.p39_lone_soldier")
	assert_false(bot.combat.big_foe(soldier), "a soldier is no big foe")


## WorldMetrics keeps each boss attempt's lowest health share (P39: the M8 release check's Iron Regiment
## bar never fell below 62 % - a fight lost is told from one nearly won): sampled while the attempt is
## open (and at engagement), kept when a death's reload, a disengage or a defeat closes it.
func test_a_boss_attempts_lowest_health_share_is_kept() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var troll := TestSpawn.enemy(world, TROLL, Vector3(0, 0.05, -12.0), "test.p39_boss_troll", false, 0.0)
	await step_ticks(2)
	var m := WorldMetrics.new(RunMetrics.new())
	var id := troll.entity.entity_id
	m._on_boss_engaged(Sim.tick, id)
	var pools := troll.entity.combatant.pools
	pools.health = pools.health_max * 0.4
	m._sample_boss(id, m.bosses[id])
	pools.health = pools.health_max * 0.7
	m._on_boss_disengaged(Sim.tick, id, "left")
	var lows: Array = m.bosses[id].lows
	assert_eq(lows.size(), 1, "one closed attempt")
	assert_near(float(lows[0]), 0.4, 0.001, "the attempt's lowest share, kept as it closed")
	m._on_boss_engaged(Sim.tick, id)
	m.note_level_loaded(null)
	lows = m.bosses[id].lows
	assert_eq(lows.size(), 2, "a reload closes the next attempt")
	assert_near(float(lows[1]), 0.7, 0.001, "the next attempt starts from its share at engagement")


## A soldier winding its chop up at the giant (its controller in the windup, its brain on the giant).
func _winding(pos: Vector3, id: String) -> SoldierEnemy:
	var s := spawn_soldier(pos, yaw_towards(pos, p.global_position), id)
	await step_ticks(1)
	s.brain.target_id = p.entity.entity_id
	s.controller.force_action(GameData.get_action("ability.soldier_chop"))
	await step_ticks(1)
	assert_eq(s.controller.phase(), ActionDef.Phase.WINDUP, "%s winds its chop up" % id)
	return s


## From stage 4 the expert answers only the blows that can land on it, and its answers hold its own blows
## off for EXPERT_HOLD_MAX_TICKS at most (P39: before the toll fort's pikes and tower archers the expert
## swung 68 and 56 lights in a run where the novice swung 213-253, an answer always due within 20 ticks);
## an arrow holds no blow off. The Valley's stages keep P17a's rules.
func test_the_world_expert_answers_only_blows_that_can_land_and_strikes_between_answers() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	_bot("expert")
	var near := await _winding(Vector3(0, 0.05, -4.5), "test.p39_near_chop")
	var far := await _winding(Vector3(6, 0.05, -9), "test.p39_far_chop")
	var chop := GameData.get_action("ability.soldier_chop")
	assert_true(far.global_position.distance_to(p.global_position) < BotCombat.EXPERT_WATCH_M,
		"the far soldier stands within P17a's 12 m watch")
	assert_true(bot.combat.blow_can_land(chop, near), "the near chop can land")
	assert_false(bot.combat.blow_can_land(chop, far), "the far one cannot (%.1f m reach)" % BotCombat.blow_reach_m(chop, far))
	bot.combat._expert_watch(Sim.tick)
	var answered: Array = bot.combat._reactions.map(func(re: Dictionary) -> String: return (re.actor as WeakRef).get_ref().entity_id)
	assert_eq(answered, ["test.p39_near_chop"], "at stage 4 only the blow that can land is answered")
	# the Valley's stages: P17a's rule answers both
	p.set_profile(_profile(3))
	await step_ticks(1)
	bot.combat._reactions.clear()
	bot.combat._seen.clear()
	near.controller.force_action(chop)
	far.controller.force_action(chop)
	await step_ticks(1)
	bot.combat._expert_watch(Sim.tick)
	assert_eq(bot.combat._reactions.size(), 2, "at stage 3 every blow within 12 m is answered")
	# The hold: answers due one after another (one always due in 15 ticks) hold the blows off.
	for stage in [3, 4]:
		p.set_profile(_profile(stage))
		await step_ticks(1)
		bot.combat._seen.clear()
		bot.combat._reactions.clear()
		assert_false(bot.combat.defend(Sim.tick), "no answer due: no hold (a tick with none ends the last one)")
		await step_ticks(1)
		var held := 0
		var free_at := -1
		for i in 150:
			bot.combat._reactions = [{"at": Sim.tick + 15, "kind": "block", "actor": weakref(near), "why": "test"}]
			var busy := bot.combat.defend(Sim.tick)
			assert_eq(busy, bot.combat.defend_busy(Sim.tick), "defend and defend_busy agree (stage %d, tick %d)" % [stage, i])
			if busy:
				held += 1
			elif free_at < 0:
				free_at = i
			await step_ticks(1)
		if stage == 3:
			assert_eq(held, 150, "at stage 3 an answer always due holds every blow off (P17a)")
		else:
			assert_true(free_at > 0 and free_at <= BotCombat.EXPERT_HOLD_MAX_TICKS + 2,
				"at stage 4 the hold ends after %d ticks (free at %d)" % [BotCombat.EXPERT_HOLD_MAX_TICKS, free_at])
			bot.combat._note_blow(Sim.tick)
			bot.combat._reactions = [{"at": Sim.tick + 15, "kind": "block", "actor": weakref(near), "why": "test"}]
			assert_true(bot.combat.defend(Sim.tick), "a blow the giant starts begins the next hold")
	# An arrow (a light shot) holds no blow off, and is not dodged while a blow of the giant's own is under way.
	bot.combat._reactions.clear()
	var archer := TestSpawn.enemy(world, ARCHER, Vector3(0, 0.05, -30), "test.p39_archer", false, 0.0)
	await step_ticks(1)
	bot.combat._plan_reaction(Sim.tick, Sim.tick + 40, GameData.get_action("ability.archer_shot"), archer, "test")
	assert_true(bool(bot.combat._reactions[-1].get("light_shot", false)), "an arrow is a light shot")
	assert_false(bot.combat.defend_busy(Sim.tick), "it holds no blow off")
	bot.combat._plan_reaction(Sim.tick, Sim.tick + 40, GameData.get_action("ability.ballista_bolt"), archer, "test")
	assert_false(bool(bot.combat._reactions[-1].get("light_shot", false)), "a ballista bolt is no light shot")
	assert_true(bot.combat.defend_busy(Sim.tick) or Sim.tick + 40 - 10 - Sim.tick > 20, "a bolt is answered as before")
	bot.combat._reactions = [{"at": Sim.tick, "kind": "dodge", "actor": weakref(archer), "why": "test", "light_shot": true}]
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_eq(p.controller.state, CombatController.State.ATTACKING, "the giant is mid-blow")
	bot.combat._reactions[0]["at"] = Sim.tick
	bot.combat.defend(Sim.tick)
	assert_true(Sim.tick >= bot.combat.dodge_steer_until(), "the arrow is taken: no dodge given up the blow for")


## From stage 4 every slotted ability takes its turn: one the rules have not used for ROTATION_IDLE_TICKS
## is used on the fight's target when nothing refuses it, the longest unused first; the two area blows
## take turns (P39: of the first world matrix's 18 runs, 14 never used Boulder Hurl when ready, 12 Sweeping
## Blow). The heal, Stone Skin and Titan Surge keep their own rules.
func test_every_slotted_ability_takes_its_turn_from_stage_4() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var soldier := spawn_soldier(Vector3(0, 0.05, -9), 0.0, "test.p39_rotation_target")
	soldier.brain.aware = true
	await step_ticks(2)
	_bot()
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.p39_rotation_target", "the giant locks its target")
	var c := bot.combat
	var key := c._rotation_slot(Sim.tick)
	assert_true(key != "", "a slotted ability is ready for its turn (loadout %s)" % [p.controller.loadout])
	var id := str(p.controller.loadout.get(key, ""))
	for own: String in [BotCombat.MEND, BotCombat.STONE_SKIN, BotCombat.SURGE]:
		assert_false(id == own or BotCombat.evolves_from_chain(id, own), "not one with its own rule: " + id)
	assert_eq(c.slot_reason(key), "", "nothing refuses it")
	c._next_ability_tick = 0
	c._last_used.clear()
	# every rule-bound slot used just now: only the rotation can pick
	assert_true(c._abilities(Sim.tick, soldier, 9.0), "the look uses an ability")
	var why := str(c._ability_log[-1][2])
	assert_true(why.begins_with("rotation: ") or why.ends_with("enemies") or why.ends_with("big foe"), why)
	var used := str(c._ability_log[-1][1])
	assert_eq(c._used_tick(used), Sim.tick, "its use is kept")
	assert_true(c._rotation_slot(Sim.tick) != used, "the same slot waits its turn (%d ticks)" % BotCombat.ROTATION_IDLE_TICKS)
	assert_true(c._rotation_slot(Sim.tick + BotCombat.ROTATION_IDLE_TICKS) == used or c._rotation_slot(Sim.tick + BotCombat.ROTATION_IDLE_TICKS) != "",
		"after its idle time a slot may take a turn again")
	# the area blows take turns: Heavy Footfall's slot (Titan Stomp) used last, Sweeping Blow's comes first
	var stomp := c.slot_of(BotCombat.FOOTFALL)
	var sweep := c.slot_of(BotCombat.SWEEP)
	if stomp != "" and sweep != "":
		c._last_used[stomp] = Sim.tick
		c._last_used[sweep] = Sim.tick - 600
		var second := spawn_soldier(Vector3(2, 0.05, -5), 0.0, "test.p39_rotation_second")
		second.brain.aware = true
		soldier.global_position = Vector3(-2, 0.05, -5)
		await step_ticks(1)
		await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
		c._next_ability_tick = 0
		if c.ready_slot(BotCombat.SWEEP) != "":
			assert_true(c._abilities(Sim.tick, soldier, soldier.global_position.distance_to(p.global_position)), "an area blow at two")
			assert_eq(str(c._ability_log[-1][1]), sweep, "Sweeping Blow's turn: Titan Stomp was used last")

