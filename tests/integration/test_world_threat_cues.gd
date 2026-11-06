extends IntegrationSuite
## P28 (plan M6-M9 §3.11 tests, decision 7, §4.1 family F and the M7-M9 rows): the world's threats,
## water and birds, audio on:
##   * a braced formation of ten pikes logs one wall cue per brace cycle, at its striker, and its
##     members' own footfalls stay silent (the march loop is theirs);
##   * a catapult shot logs its launch at the engine and the incoming whistle at the landing circle,
##     timed to end as the stone lands; a shot that lands early drops its whistle;
##   * a stage-6 giant among fleeing soldiers keeps the music at explore, and a soldier's chop at it
##     plays no sting;
##   * a stomp near birds flushes them (the Crownmarch's larks), once; wading logs `wade`
##     footfalls from the world's water and a splash on entering it;
##   * the two nearest advancing formations march (the march loop at each one's anchor, following
##     it); one that braces or dissolves fades out and the next takes its place;
##   * a size gate answers with its own cue where the giant touched it (a stage-gated prop by what
##     it is made of).

const WORLD := "level.world"
const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const GATE_WATER := "res://scenes/world/size_gate_water.tscn"
const GATE_STONE := "res://scenes/world/size_gate_stone.tscn"
const TITAN_TREE := "res://scenes/world/titan_tree.tscn"
const BRACE := "ability.formation_brace_pike"
const CATAPULT := "ability.test_catapult_stone"
const CHOP := "ability.soldier_chop"
## A point of the Crownmarch away from its places (the larks' fields), and a pond 60 m on.
const FIELDS := Vector3(-100, 0.05, 760)
const POND := Vector3(-100, 0.05, 820)


## A world level without its streamed ground: the index's regions (or one fixed region) and, for
## wading, a pool of water `water_y` high over `water` (x, z).
class WorldStub extends LevelRoot:
	var fixed_region := "-"
	var water := Rect2()
	var water_y := 0.0

	func region_at(pos: Vector3) -> String:
		if fixed_region != "-":
			return fixed_region
		var idx := index()
		return idx.region_at(pos) if idx != null else ""

	func water_at(pos: Vector3) -> float:
		return water_y if water.has_point(Vector2(pos.x, pos.z)) else NAN

	func surface_at(pos: Vector3) -> String:
		return "wet" if water.grow(4.0).has_point(Vector2(pos.x, pos.z)) else ""

	func create_runtime_nodes(_entries: Array = RUNTIME_NODES) -> Array[Node]:
		return []


## A formation without bodies, for the march emitters: `standing` of its members stand.
class MarchingFormation extends Formation:
	var standing := 8

	func living_count() -> int:
		return standing


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	Audio.enable_for_tests(false)
	await super()


func _world(fixed_region := "-") -> WorldStub:
	var lv := WorldStub.new()
	lv.name = "WorldStub"
	lv.level_id = WORLD
	lv.fixed_region = fixed_region
	world.add_child(lv)
	Audio.is_ready()   # detects the level and queues its samples
	# The loading gate's registration is test_audio_director's and test_sfx_valley_pass's: here the
	# queue is dropped (registering is a no-op on desktop and plays load lazily), for the time budget.
	Audio._reg_queue.clear()
	return lv


func _giant(pos: Vector3, stage: int) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			p.set_profile(rec)
	assert_eq(p.current_growth_stage(), stage, "a stage-%d giant" % stage)
	return p


func _logged(cue_id: String) -> Array:
	return Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.cue) == cue_id)


func _requested(prefix: String) -> Array:
	return Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.requested).begins_with(prefix))


# --------------------------------------------------------------------------- formations

func test_a_braced_formation_of_ten_pikes_logs_one_wall_cue_per_brace_cycle() -> void:
	# a quicker brace than the shipped one (the time budget): the counts are the test
	TestFixtures.record_override(BRACE, {"windup_s": 0.02, "active_s": 0.02, "recovery_s": 0.02})
	var p := _giant(Vector3(0, 0.05, 6), 4)
	var f := Formation.new()
	f.id = "test.pikes"
	f.kind = "pike"
	f.ranks = 2
	f.files = 5
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.brace_m = 7.0
	f.brace_action = BRACE
	f.place(Vector3.ZERO, PI)
	Formation.register(f)
	var _held := load(PIKEMAN)   # held: each spawn's load() then finds it in the cache
	for i in 10:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.pike_%d" % i, false, PI), i)
	for e: EnemyActor in f.members:
		e.brain.aware = true
	await step_ticks(1)
	Audio.clear_log()
	var strikers: Array = []
	for i in 60:
		# the director updates a formation every UPDATE_TICKS; here every tick (fewer ticks to wait)
		f.update(Sim.tick, p)
		var holder := f.brace_holder()
		if holder != null and (strikers.is_empty() or strikers[-1] != holder):
			strikers.append(holder)
		if f.brace_count == 1 and holder == null and f._brace_ready_tick > Sim.tick:
			# the next brace at once (the time budget), its 0.6 s pause passed for the audio's
			# clock, which merges one brace's band telegraphs into one wall within 0.5 s
			f._brace_ready_tick = Sim.tick
			Audio.clock_s += Formation.BRACE_PAUSE_S
		await step_ticks(1)
		if f.brace_count >= 2 and not f.brace_running():
			break
	assert_eq(f.state, "braced", "the giant 6 m in front of the rank: braced")
	assert_eq(f.brace_count, 2, "two brace cycles")
	var walls := _logged("sfx.threat.windup.wall")
	assert_eq(walls.size(), f.brace_count, "one wall cue per brace cycle (%s)" % [Audio.logged_cues()])
	for k in walls.size():
		var at: Vector3 = walls[k].pos
		assert_eq(int(walls[k].priority), 100, "the wall at the threat priority")
		if k < strikers.size():
			var s: EnemyActor = strikers[k]
			assert_true(at.distance_to(s.global_position) < 3.0, "the wall at its striker (%s)" % at)
	assert_eq(_requested("sfx.threat.windup.line").size(), 0, "no pike's own windup")
	assert_eq(_logged("sfx.formation.brace").size(), 1, "the brace's call once, when it braced")
	# a member's footfall while the formation holds its slots is the march loop's; on its own, its own
	var rig := (f.members[0] as Node).find_children("*", "ActorRig", true, false)
	if not rig.is_empty():
		Audio.clear_log()
		(rig[0] as ActorRig).footfall.emit()
		Audio.advance_for_tests(0.05, 0.05)
		assert_eq(_requested("sfx.step.human").size(), 0, "a member's footfall in formation: silent (the march)")
		f.state = "broken"
		(rig[0] as ActorRig).footfall.emit()
		Audio.advance_for_tests(0.05, 0.05)
		assert_eq(_requested("sfx.step.human").size(), 1, "out of formation: its own footfall")
	else:
		fail("a pikeman has an ActorRig")


# --------------------------------------------------------------------------- indirect fire

func test_a_catapult_shot_logs_its_launch_at_the_engine_and_the_incoming_whistle_at_the_landing() -> void:
	TestFixtures.record_override(CATAPULT, {"type": "action", "kind": "enemy_attack", "hit_shape": "projectile",
		"power": 110, "windup_s": 2.0, "indirect": true,
		"projectile": {"visual": "catapult_stone", "speed_mps": 30.0, "gravity_mps2": 9.8, "arc_to_target": true}})
	var engine := Vector3(0, 2, -42)   # (no giant: the listener stands at the origin)
	var landing := Vector3(1, 0, -2)
	Audio.clear_log()
	Events.telegraph_started.emit(Sim.tick, "test.catapult", CATAPULT, "player", "circle", landing,
		0.0, 6.0, 0.0, 2.0)
	Audio.advance_for_tests(2.0, 0.5)   # the windup
	assert_eq(_logged("sfx.threat.incoming").size(), 0, "no whistle before the launch")
	# the launch: 40 m to the landing at 20 m/s across the ground: 2.0 s of flight
	var velocity := Vector3(0.0, 14.2, 20.0 * (landing.z - engine.z) / absf(landing.z - engine.z))
	var flight := Vector2(landing.x - engine.x, landing.z - engine.z).length() / Vector2(velocity.x, velocity.z).length()
	Events.projectile_spawned.emit(Sim.tick, 4101, "test.catapult", CATAPULT, engine, velocity, "catapult_stone")
	var launched_s := Audio.clock_s
	Audio.advance_for_tests(0.05, 0.05)
	var launch := _logged("sfx.projectile.catapult_stone.launch")
	assert_eq(launch.size(), 1, "the launch")
	if launch.size() == 1:
		assert_true((launch[0].pos as Vector3).distance_to(engine) < 0.01, "at the engine")
	var whistle_s := Audio.router.cue_seconds("sfx.threat.incoming")
	assert_true(whistle_s > 0.5, "a whistle (%.2f s)" % whistle_s)
	var heard_s := -1.0
	for i in 40:
		if not _logged("sfx.threat.incoming").is_empty():
			heard_s = Audio.clock_s
			break
		Audio.advance_for_tests(0.1, 0.1)
	var whistle := _logged("sfx.threat.incoming")
	assert_eq(whistle.size(), 1, "the incoming whistle")
	if whistle.size() == 1:
		var at: Vector3 = whistle[0].pos
		assert_true(Vector2(at.x - landing.x, at.z - landing.z).length() < 0.01, "at the landing circle (%s)" % at)
		assert_eq(int(whistle[0].priority), 100, "at the threat priority")
		assert_near(heard_s - launched_s + whistle_s, flight, 0.15, "ending as the stone lands (%.2f s of flight)" % flight)
	# a second shot that lands early (a wall in the way) drops its whistle
	Audio.clear_log()
	Events.telegraph_started.emit(Sim.tick, "test.catapult", CATAPULT, "player", "circle", landing,
		0.0, 6.0, 0.0, 2.0)
	Events.projectile_spawned.emit(Sim.tick, 4102, "test.catapult", CATAPULT, engine, velocity, "catapult_stone")
	Audio.advance_for_tests(0.1, 0.05)
	Events.projectile_impact.emit(Sim.tick, 4102, engine + Vector3(0, 0, 10), "")
	Audio.advance_for_tests(flight + 0.2, 0.5)
	assert_eq(_logged("sfx.threat.incoming").size(), 0, "no whistle for a stone that landed early")
	assert_eq(_requested("sfx.impact.catapult_stone").size(), 1, "its impact instead (its far thud from here)")


# --------------------------------------------------------------------------- a big giant, fleeing soldiers

func test_a_stage_6_giant_among_fleeing_soldiers_keeps_explore_and_hears_no_sting() -> void:
	_world("region.crownmarch")
	var p := _giant(FIELDS, 6)
	var _held := load(IntegrationSuite.SOLDIER)   # held: each spawn's load() then finds it in the cache
	var soldiers: Array = []
	for k in 2:
		var s := spawn_soldier(FIELDS + Vector3(-8.0 + 16.0 * k, 0, 14), 0.0, "test.fleeing_%d" % k)
		soldiers.append(s)
	await step_ticks(1)
	for s: SoldierEnemy in soldiers:
		s.brain.aware = true
		s.brain.state = EnemyBrain.AIState.FLEE
	Audio.clear_log()
	Audio.advance_for_tests(1.25, 0.25)
	assert_eq(Audio.music.state_name(), "zone", "the zone's music (%s)" % Audio.music.state_name())
	assert_eq(Audio.music.set_id(), "music.crownmarch", "the Crownmarch's")
	assert_eq(Audio.music.intensity, AudioMath.EXPLORE, "fleeing soldiers never count: explore")
	assert_eq(_logged("sfx.threat.sting").size(), 0, "no sting among them")
	# the control: the same soldiers standing their ground would raise danger (lesser: never combat)
	var cfg: Dictionary = Audio.mix.get("intensity", {})
	for s: SoldierEnemy in soldiers:
		s.brain.state = EnemyBrain.AIState.APPROACH
	assert_eq(AudioMath.intensity_target(Audio.music.intensity_snapshot(), cfg), AudioMath.DANGER,
		"aware soldiers standing near a stage-6 giant: danger, not combat")
	for s: SoldierEnemy in soldiers:
		s.brain.state = EnemyBrain.AIState.FLEE
	assert_eq(AudioMath.intensity_target(Audio.music.intensity_snapshot(), cfg), AudioMath.EXPLORE, "fleeing again: explore")
	# even a chop at the giant from behind (a soldier turning on it) plays its windup and no sting:
	# a scratch at stage 6 (its danger is the telegraph rule's, three seconds)
	Audio.clear_log()
	var suppressed := int(Audio.stats.suppressed)
	var s0: SoldierEnemy = soldiers[0]
	Events.telegraph_started.emit(Sim.tick, s0.entity.entity_id, CHOP, p.entity.entity_id, "line",
		s0.global_position, 0.0, 0.3, 2.5, 0.85)
	Audio.advance_for_tests(0.1, 0.05)
	assert_eq(_logged("sfx.threat.windup.line").size(), 1, "the windup at the soldier")
	assert_eq(_logged("sfx.threat.sting").size(), 0, "no sting")
	assert_eq(int(Audio.stats.suppressed), suppressed + 1, "the sting was suppressed (expected damage)")


# --------------------------------------------------------------------------- water and birds

func test_a_stomp_near_birds_flushes_them_and_wading_logs_wade_footfalls_and_a_splash() -> void:
	var lv := _world("region.crownmarch")
	lv.water = Rect2(POND.x - 20.0, POND.z - 20.0, 40.0, 40.0)
	lv.water_y = 1.4
	var p := _giant(FIELDS, 4)
	Audio.advance_for_tests(0.5, 0.25)
	assert_eq(Audio.ambience.set_id, "ambience.crownmarch", "the Crownmarch's fields")
	assert_eq(Audio.ambience.flushes, 0, "no flush yet")
	# stomps beside the giant: the larks take flight once
	Audio.clear_log()
	for k in 3:
		Events.area_pulse.emit(Sim.tick, p.entity.entity_id, "ability.titan_stomp", p.global_position, 8.0)
		Audio.advance_for_tests(0.5, 0.25)
	assert_eq(Audio.ambience.flushes, 1, "the stomps flush the birds once")
	var flushed := Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.reason) == "flush")
	assert_eq(flushed.size(), 1, "the flush cue once")
	if flushed.size() == 1:
		assert_eq(str(flushed[0].requested), "amb.birds_flush", "the birds take flight")
	assert_true(Audio.clock_s < Audio.ambience.flushed_until_s, "and stay away a while")
	# a dry footfall, then into the pond: a splash, and wading footfalls
	Audio.clear_log()
	p.rig.footfall.emit()
	Audio.advance_for_tests(0.05, 0.05)
	assert_eq(_requested("sfx.step.giant_s4").map(func(e: Dictionary) -> String: return str(e.requested)),
		["sfx.step.giant_s4.soft"], "a dry footfall on the Crownmarch's soft ground")
	p.global_position = POND
	Audio.advance_for_tests(0.5, 0.25)
	var splash := _logged("sfx.world.splash.large")
	assert_eq(splash.size(), 1, "entering the water deeper than 0.5 m splashes (%s)" % [Audio.logged_cues()])
	if splash.size() == 1:
		assert_true((splash[0].pos as Vector3).distance_to(p.global_position) < 0.5, "at the giant")
	Audio.clear_log()
	for k in 2:
		Audio.router.set_walk_started(0.0)
		p.rig.footfall.emit()
		Audio.advance_for_tests(0.4, 0.2)
	var wade := _requested("sfx.step.giant_s4")
	assert_eq(wade.size(), 2, "two footfalls")
	for e: Dictionary in wade:
		assert_eq(str(e.requested), "sfx.step.giant_s4.wade", "wading")
		assert_eq(str(Audio.resolve(str(e.cue)).get("bank", "")), "audio_bank.world_steps", "the world's wading step")
	assert_eq(_logged("sfx.world.splash.large").size(), 0, "one splash for one entry")


# --------------------------------------------------------------------------- the march, the gates

func _column(id: String, pivot: Vector3) -> MarchingFormation:
	var f := MarchingFormation.new()
	f.id = id
	f.kind = "pike"
	f.ranks = 2
	f.files = 4
	f.place(pivot, 0.0)
	f.state = "advancing"
	Formation.register(f)
	return f


func _marching() -> Array:
	var ids := Array(Audio.ambience.march_ids())
	ids.sort()
	return ids


func test_the_two_nearest_advancing_formations_march_at_their_anchors() -> void:
	_world("region.crownmarch")
	_giant(FIELDS, 4)
	var near := _column("test.column_near", FIELDS + Vector3(0, 0, -40))
	var mid := _column("test.column_mid", FIELDS + Vector3(30, 0, -60))
	var far := _column("test.column_far", FIELDS + Vector3(-50, 0, -90))
	Audio.clear_log()
	Audio.advance_for_tests(0.5, 0.25)
	assert_eq(_marching(), ["test.column_mid", "test.column_near"], "the two nearest of three columns march")
	var started := Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.reason) == "march")
	assert_eq(started.size(), 2, "two march loops")
	for e: Dictionary in started:
		assert_eq([str(e.requested), str(e.bus), int(e.priority)], ["amb.march_loop", "Ambience", 75],
			"the march loop on the Ambience bus at the march emitters' priority")
	# the loop marches with its formation, a stream at its anchor
	near.pivot += Vector3(0, 0, 6)
	Audio.advance_for_tests(0.1, 0.05)
	var loop: AudioStreamPlayer3D = Audio.ambience.marches["test.column_near"].player
	assert_true(loop.global_position.distance_to(near.anchor()) < 0.01, "at the formation's anchor as it moves")
	assert_eq(loop.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "a stream (loops are never samples)")
	# the nearest braces: its march fades out and the third column's takes its place
	near.state = "braced"
	Audio.advance_for_tests(0.5, 0.25)
	assert_eq(_marching(), ["test.column_far", "test.column_mid"], "a braced formation no longer marches")
	Audio.advance_for_tests(1.0, 0.25)
	assert_false(Audio.ambience.marches.has("test.column_near"), "its loop faded out and was freed")
	# a dissolved formation (its encounter gone) fades out too
	mid.dissolve()
	Audio.advance_for_tests(1.25, 0.25)
	assert_eq(_marching(), ["test.column_far"], "the dissolved column's march stops")
	assert_false(Audio.ambience.marches.has("test.column_mid"), "and is freed")
	assert_true(far.living_count() > 0, "the last column marches on")


func test_a_size_gate_answers_with_its_own_cue_where_the_giant_touched_it() -> void:
	var water := (load(GATE_WATER) as PackedScene).instantiate() as SizeGate
	water.position = Vector3(0, 0, -20)
	world.add_child(water)
	water.last_contact = Vector3(3, 1, -19.5)   # (the gate keeps it when the giant touches it: test_size_gates)
	var stone := (load(GATE_STONE) as PackedScene).instantiate() as SizeGate
	stone.position = Vector3(20, 0, -20)
	world.add_child(stone)
	var tree := (load(TITAN_TREE) as PackedScene).instantiate() as BreakableProp
	tree.world_id = "test.titan_tree"
	tree.position = Vector3(-20, 0, -20)
	world.add_child(tree)
	Audio.clear_log()
	Events.size_gate_blocked.emit(Sim.tick, water.gate_id, water.min_stage, water.message)
	Events.size_gate_blocked.emit(Sim.tick, stone.gate_id, stone.min_stage, stone.message)
	Events.size_gate_blocked.emit(Sim.tick, tree.world_id, 5, "")   # a heave refused (BreakableProp)
	Audio.advance_for_tests(0.05, 0.05)
	var answers := {"sfx.gate.water": water.last_contact, "sfx.gate.stone": stone.global_position,
		"sfx.gate.timber": tree.global_position}
	for cue: String in answers:
		var logged := _logged(cue)
		assert_eq(logged.size(), 1, "%s answers once (%s)" % [cue, Audio.logged_cues()])
		if logged.size() == 1:
			assert_true((logged[0].pos as Vector3).distance_to(answers[cue]) < 0.01,
				"%s where the giant touched it, else at the gate (%s)" % [cue, logged[0].pos])
	assert_eq(_requested("sfx.gate.default").size(), 0, "every gate found its own cue")
