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
##     engine to seize.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"

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
func _bot() -> void:
	bot = WorldBot.new()
	world.add_child(bot)
	bot.player = p
	p.router.use_injection = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	bot.combat = BotCombat.new()
	bot.combat.setup(bot, p, "novice", rng)


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
