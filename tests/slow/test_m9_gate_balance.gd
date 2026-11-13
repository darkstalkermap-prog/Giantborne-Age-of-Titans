extends IntegrationSuite
## M9 gate (lane "balance"; docs/BALANCE_LOG.md, "M9 gate"): the fixes of the W23 confirmation's misses.
##   * awe tiers (EnemyBrain.awe_loss_at, tactics.awe_tiers): a lone soldier flees a stage-4 giant on sight
##     (plan §5.14: "single humans flee on sight (awe at 6.1x)"), a stage-3 one costs it the base 35 of its
##     70 morale as before (the Valley's stages 1-3 unchanged), and a formation's pikeman has no tier;
##   * the world bot walks past a formation that holds its ground off its way (the road to Brannock and the
##     Raiders' Hollow), and fights it once it closes in, braces, or stands where the objective leads;
##   * an engine that shot at the giant is sought from SIEGE_SHOT_SEEK_M (the walk to the Moot passed the
##     Moot battery beyond SIEGE_SEEK_M);
##   * Rampart Grip reads as ready only with something in reach to seize, and a slotted ability the run has
##     not used yet is tried at the first free tick it fits;
##   * the music's combat radius is capped for a stage-4+ giant (audio_mix.intensity.combat_cap_m): a
##     formation holding 50 m off raises danger, one 30 m off or a boss combat; the Valley's stages keep the
##     scaled radius.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const BALLISTA := "res://scenes/world/siege_ballista.tscn"

var f: Formation
var p: GiantPlayer
var bot: WorldBot


func before_each() -> void:
	await super()
	WorldBot.reset_world()


func after_each() -> void:
	if f != null:
		f.dissolve()
		f = null
	if bot != null and is_instance_valid(bot):
		bot.queue_free()
	bot = null
	WorldBot.reset_world()
	await super()


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


## Stands in for the bot a BotCombat reads its run's metrics through (no run: the bot's own tick idles).
class MetricsHolder extends RefCounted:
	var metrics := RunMetrics.new()


## A WorldBot bound by hand to the test's giant (no run: its own tick does nothing), its BotCombat set up;
## it counts as in the world (a WorldRoot it does not tick).
func _bot(skill := "novice") -> void:
	bot = WorldBot.new()
	world.add_child(bot)
	bot.player = p
	bot._world = WorldRoot.new()
	p.router.use_injection = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	bot.combat = BotCombat.new()
	bot.combat.setup(bot, p, skill, rng)


## A soldier with its AI on at `pos`, facing the giant.
func _soldier_facing_giant(pos: Vector3, id: String) -> SoldierEnemy:
	return spawn_soldier(pos, yaw_towards(pos, p.global_position), id, true)


func test_a_lone_soldier_flees_a_stage_4_giant_on_sight_and_not_a_stage_3_one() -> void:
	var rec := GameData.get_record("enemy.soldier")
	var tactics: Dictionary = rec.get("tactics", {})
	assert_eq(float(tactics.get("awe_morale_loss", 0.0)), 35.0, "the base awe (the Valley's) is 35")
	await _giant(3, Vector3(0, 0.05, 0))
	var calm := _soldier_facing_giant(Vector3(0, 0.05, -12), "test.m9_awed_3")
	await TestWait.until(self, func() -> bool: return calm.brain.awed, 120)
	assert_true(calm.brain.awed, "a stage-3 giant (4.4x a soldier) awes it")
	assert_near(calm.brain.awe_loss_at(calm.brain.size_ratio()), 35.0, 1e-6, "at 4.4x the base loss")
	assert_true(calm.brain.morale > float(calm.brain.ai.get("flee_morale", 25.0)),
		"its morale (%.1f) stays above its flee threshold: it stands (the Valley as it was)" % calm.brain.morale)
	assert_false(calm.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED], "and does not flee")
	assert_false(calm.brain.awed_at_tier, "the base awe, not a tier's")
	calm.queue_free()
	p.set_profile(_profile(4))
	await step_ticks(2)
	var lone := _soldier_facing_giant(Vector3(0, 0.05, -14), "test.m9_awed_4")
	await TestWait.until(self, func() -> bool: return lone.brain.awed, 120)
	assert_true(lone.brain.size_ratio() >= 6.0, "a stage-4 giant is %.2fx a soldier" % lone.brain.size_ratio())
	assert_near(lone.brain.awe_loss_at(lone.brain.size_ratio()), 50.0, 1e-6, "its awe tier at 6.0x costs 50")
	assert_true(lone.brain.morale < float(lone.brain.ai.get("flee_morale", 25.0)),
		"its morale (%.1f) falls below its flee threshold" % lone.brain.morale)
	await TestWait.until(self, func() -> bool: return lone.brain.state == EnemyBrain.AIState.FLEE, 60)
	assert_eq(lone.brain.state, EnemyBrain.AIState.FLEE, "a lone soldier flees a stage-4 giant on sight (plan §5.14)")
	assert_true(lone.brain.awed_at_tier, "awed by its tier")
	# The flight ends in a rout, not in a walk back to the giant (no formation here to take it): the Millford
	# raiders regrouped and went back to burning the hamlet among its folk.
	await TestWait.until(self, func() -> bool: return lone.brain.state == EnemyBrain.AIState.ROUTED, 60 * 40)
	assert_eq(lone.brain.state, EnemyBrain.AIState.ROUTED, "its flight ends in a rout: it does not come back")
	assert_false(lone.brain.aware, "routed, it is out of the fight")
	var pike := TestSpawn.enemy(world, PIKEMAN, Vector3(20, 0.05, -14), "test.m9_pike", false)
	await step_ticks(2)
	assert_near(pike.brain.awe_loss_at(6.1), float(pike.brain.tactics.get("awe_morale_loss", 0.0)), 1e-6,
		"a pikeman has no tier: formations keep their ground as they did")


## The Raiders' Hollow (gate_world's w.peaceful:novice:1): a shieldman thrown 30 m up came down through the
## ground and fell on, alive, until its encounter could never clear. A living enemy below the world is set
## back at its home on the floor, still; a dead one, or one in the giant's hand, is left alone.
func test_an_enemy_fallen_through_the_world_is_set_back_at_its_home() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	var home := Vector3(6, 0.05, -10)
	var s := spawn_soldier(home, 0.0, "test.m9_void", false)
	await TestWait.until(self, func() -> bool: return s.is_on_floor(), 40)
	assert_near(s.home_position.distance_to(home), 0.0, 0.1, "its home is where it came into the world")
	s.global_position = Vector3(30, EnemyActor.OUT_OF_WORLD_Y - 5.0, 40)
	s.velocity = Vector3(0, -40, 0)
	s.knockback_velocity = Vector3(3, 0, 0)
	await step_ticks(2)
	assert_true(s.global_position.y > EnemyActor.OUT_OF_WORLD_Y, "it is back above the world (y %.1f)" % s.global_position.y)
	assert_true(Vector2(s.global_position.x - home.x, s.global_position.z - home.z).length() < 0.5,
		"at its home (%s)" % s.global_position)
	assert_true(s.entity.is_alive(), "alive, as it fell")
	assert_true(s.knockback_velocity.length() < 0.5 and s.velocity.y > -1.0, "and still")
	await TestWait.until(self, func() -> bool: return s.is_on_floor(), 40)
	assert_true(s.is_on_floor(), "standing on the floor there")
	assert_false(s.recover_from_void(), "above the world nothing moves it")
	s.ai_enabled = false
	s.entity.combatant.dead = true
	s.global_position = Vector3(30, EnemyActor.OUT_OF_WORLD_Y - 5.0, 40)
	assert_false(s.recover_from_void(), "a dead body is left where it fell")
	assert_true(s.global_position.y < EnemyActor.OUT_OF_WORLD_Y, "(it stays below)")


## A formation of five pikemen and its banner around `pivot`, AI off, aware of the giant.
func _formation(pivot: Vector3) -> void:
	f = Formation.new()
	f.id = "test.m9_pikes"
	f.kind = "pike"
	f.ranks = 1
	f.files = 5
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.place(pivot, PI * 0.5)
	Formation.register(f)
	for i in 5:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.m9_pike_%d" % i, false, PI * 0.5), i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "test.m9_banner", false, PI * 0.5))
	await step_ticks(2)
	for m: EnemyActor in f.members + [f.banner]:
		m.brain.aware = true


func _move_formation(pivot: Vector3) -> void:
	f.place(pivot, PI * 0.5)
	for i in 5:
		f.members[i].global_position = f.slot_position(i)
	f.banner.global_position = f.slot_position(Formation.BANNER_SLOT)
	await step_ticks(1)


func test_the_bot_walks_past_a_formation_that_holds_its_ground_off_its_way() -> void:
	await _giant(4, Vector3(0, 0.05, 0))
	await _formation(Vector3(0, 0, -23))
	_bot()
	f.state = "formed"
	bot._plan_place = Vector3(0, 0, 400)   # the objective leads away from it (Brannock past the Hollow)
	assert_true(bot._passing_by(f.members[0]), "a formed wall 23 m off the road is passed")
	assert_true(bot._passing_by(f.banner), "and its banner")
	f.state = "advancing"
	assert_true(bot._passing_by(f.members[2]), "still while it advances, far off (1.2 m/s against a giant's stride)")
	f.state = "braced"
	assert_false(bot._passing_by(f.members[0]), "a wall braced against the giant is fought")
	f.state = "formed"
	await _move_formation(Vector3(0, 0, -10))
	assert_false(bot._passing_by(f.members[0]), "one that closed within %.0f m is fought" % WorldBot.FORMATION_PASS_M)
	await _move_formation(Vector3(0, 0, -23))
	bot._plan_place = Vector3.INF
	assert_false(bot._passing_by(f.members[0]), "with no place the objective leads to, the old rule (fought)")
	# its encounter's ground is where the objective leads (the march's help clears the Hollow): fought
	f.encounter_id = "encounter.crownmarch_raiders"
	var centre := bot._where(f.encounter_id)
	assert_true(centre.is_finite(), "the Hollow's centre is known from the world's index")
	bot._plan_place = centre + Vector3(10, 0, 0)
	assert_false(bot._passing_by(f.members[0]), "a wall where the objective leads is fought")
	bot._plan_place = centre + Vector3(300, 0, 0)
	assert_true(bot._passing_by(f.members[0]), "the same wall off the objective's way is passed")
	# a lone soldier is never passed
	var lone := spawn_soldier(Vector3(10, 0.05, -20), 0.0, "test.m9_lone")
	lone.brain.aware = true
	assert_false(bot._passing_by(lone), "a lone enemy in no formation is fought as before")
	# the objective's place: a talker, a thing to smash, a fight's target, a travel's spot
	assert_eq(bot._objective_place({"kind": "travel", "pos": Vector3(1, 2, 3)}), Vector3(1, 2, 3), "a travel's spot")
	assert_eq(bot._objective_place({"kind": "fight", "target": lone}), lone.global_position, "a fight's target")
	assert_false(bot._objective_place({"kind": "wait"}).is_finite(), "a wait leads nowhere")


## A ballista at `pos` facing `face`, uncrewed unless `crew`.
func _engine(id: String, pos: Vector3, face: Vector3, crew := true) -> SiegeEngine:
	var e := (load(BALLISTA) as PackedScene).instantiate() as SiegeEngine
	e.world_id = id
	e.position = pos
	e.rotation.y = yaw_towards(pos, face)
	world.add_child(e)
	if crew:
		e.add_crew(TestSpawn.enemy(world, "res://scenes/enemies/siege_crew.tscn", pos + Vector3(0, 0.05, -2.5), id + "_hauler", false, 0.0))
	return e


func test_an_engine_that_shoots_at_the_giant_is_sought_from_farther() -> void:
	await _giant(6, Vector3(0, 0.05, 0))
	var eng := _engine("test.m9_battery_ballista", Vector3(0, 0, -60), Vector3(0, 0, 0))
	await step_ticks(2)
	_bot()
	assert_true(bot._can_seize_engines(), "a stage-6 giant may seize engines")
	assert_true(bot._seizable_engine(eng), "the ballista is one to seize")
	assert_true(bot._siege_target(Sim.tick) == null, "60 m off, beyond SIEGE_SEEK_M (%.0f m), it is not sought" % WorldBot.SIEGE_SEEK_M)
	bot._on_engine_fired(Sim.tick, eng.world_id, "ability.ballista_bolt", p.entity.entity_id)
	assert_eq(bot._siege_target(Sim.tick), eng, "once it shot at the giant it is sought from %.0f m" % WorldBot.SIEGE_SHOT_SEEK_M)
	var later := Sim.tick + ActionDef.seconds_to_ticks(WorldBot.SIEGE_SHOT_MEMORY_S) + 1
	assert_true(bot._siege_target(later) == null, "a shot %.0f s ago is forgotten" % WorldBot.SIEGE_SHOT_MEMORY_S)
	bot._on_engine_fired(Sim.tick, eng.world_id, "ability.ballista_bolt", "test.someone_else")
	bot._shot_at_by.clear()
	bot._on_engine_fired(Sim.tick, eng.world_id, "ability.ballista_bolt", "test.someone_else")
	assert_true(bot._siege_target(Sim.tick) == null, "a shot at someone else is no reason")
	eng.global_position = Vector3(0, 0, -100)
	bot._on_engine_fired(Sim.tick, eng.world_id, "ability.ballista_bolt", p.entity.entity_id)
	assert_true(bot._siege_target(Sim.tick) == null, "nor one beyond SIEGE_SHOT_SEEK_M")


func test_rampart_grip_is_ready_only_with_something_to_seize_and_is_tried_once_it_fits() -> void:
	await _giant(6, Vector3(0, 0.05, 0))
	p.set_loadout_slot("slot_4", "ability.rampart_grip")   # as the evolution leaves it at stage 6 (P32)
	await step_ticks(1)
	_bot()
	var c := bot.combat
	var key := c.slot_of(BotCombat.GRIP)
	assert_true(key != "", "the grip's slot (loadout %s)" % [p.controller.loadout])
	var def: ActionDef = p.controller.library.get(str(p.controller.loadout.get(key, "")))
	assert_true(PlayerGrab.is_rampart(def), "at stage 6 it holds Rampart Grip (%s)" % (def.id if def != null else "-"))
	assert_true(c.slot_reason(key) != "", "with nothing in reach it is not ready (%s)" % c.slot_reason(key))
	assert_false(c.readiness().get(def.id, true), "nor counted ready by the 'used when ready' windows")
	var eng := _engine("test.m9_crewless", Vector3(0, 0, -7.5), Vector3(0, 0, 40), false)
	await step_ticks(3)
	assert_eq(p.grab.check_target(eng.entity, "hold"), "", "a crewless engine in reach may be seized")
	assert_eq(c.slot_reason(key), "", "Rampart Grip is ready with the engine in reach")
	assert_true(c.readiness().get(def.id, false), "and counted ready")
	# the first use: the run has not used it - offered at a free tick, the expert's reserve aside
	var holder := MetricsHolder.new()
	c.bot = holder
	assert_true(c._first_use_slot(4.0) != "", "with nothing used yet this run a slot is offered")
	for k: String in GiantPlayer.SLOT_KEYS:
		var id := str(p.controller.loadout.get(k, ""))
		if id != "" and id != def.id:
			holder.metrics.ability_uses[id] = 1
	assert_eq(c._first_use_slot(4.0), key, "the one slot the run has not used is offered for its first use")
	holder.metrics.ability_uses[def.id] = 1
	assert_eq(c._first_use_slot(4.0), "", "once every slotted ability was used this run, none is due")
	# an area blow's first use waits for a foe within reach
	var stomp := c.slot_of(BotCombat.FOOTFALL)
	if stomp != "":
		holder.metrics.ability_uses.erase(str(p.controller.loadout.get(stomp, "")))
		var reach := float(p.profile.get("melee_reach_m", 3.5))
		assert_eq(c._first_use_slot(reach + 20.0), "", "not at a foe %.0f m off" % (reach + 20.0))
		if c.slot_reason(stomp) == "":
			assert_eq(c._first_use_slot(reach), stomp, "at a foe within reach")
	c.bot = bot


func _threat(distance: float, height: float, special: bool) -> Dictionary:
	return {"distance": distance, "height": height, "special": special, "aware": true, "engaged": true,
		"fleeing": false, "hostile": true}


func _snap(threats: Array, giant_h: float, extra := {}) -> Dictionary:
	var s := {"threats": threats, "player_height": giant_h, "scale": AudioMath.distance_scale(giant_h),
		"boss_engaged": false, "combat_hit_age_s": INF, "lesser_hit_age_s": INF, "telegraph_age_s": INF,
		"encounter_inside": false}
	s.merge(extra, true)
	return s


func test_the_music_s_combat_radius_is_capped_for_a_stage_4_giant() -> void:
	var cfg: Dictionary = (GameData.get_record("audio_mix.default").get("intensity", {}) as Dictionary)
	var cap := float(cfg.get("combat_cap_m", 0.0))
	assert_true(cap > 0.0 and cap <= 45.0, "a combat cap near the lesser enemies' 40 m (%.0f m)" % cap)
	var s4 := 10.97
	assert_eq(AudioMath.intensity_target(_snap([_threat(50.0, 1.8, true)], s4), cfg), AudioMath.DANGER,
		"a formation member holding 50 m from a stage-4 giant raises danger (was combat: 105 m)")
	assert_eq(AudioMath.intensity_target(_snap([_threat(30.0, 1.8, true)], s4), cfg), AudioMath.COMBAT,
		"30 m off: combat (a formation fight)")
	assert_eq(AudioMath.intensity_target(_snap([_threat(90.0, 9.0, false)], 18.9), cfg), AudioMath.DANGER,
		"a big foe 90 m from a stage-6 giant: danger")
	assert_eq(AudioMath.intensity_target(_snap([], s4, {"boss_engaged": true}), cfg), AudioMath.COMBAT,
		"an engaged boss is combat at any distance")
	assert_eq(AudioMath.intensity_target(_snap([], s4, {"combat_hit_age_s": 2.0}), cfg), AudioMath.COMBAT,
		"and a hit from what counts within 5 s")
	assert_eq(AudioMath.intensity_target(_snap([_threat(60.0, 3.4, false)], 7.92), cfg), AudioMath.COMBAT,
		"a stage-3 giant (the Valley) keeps the scaled radius: an ogre 60 m off is combat (75.8 m)")
	assert_eq(AudioMath.intensity_target(_snap([_threat(50.0, 1.8, false)], 5.49), cfg), AudioMath.COMBAT,
		"and a stage-2 giant: a soldier 50 m off is combat (52.5 m)")
