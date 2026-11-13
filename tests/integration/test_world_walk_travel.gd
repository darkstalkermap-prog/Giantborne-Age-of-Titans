extends IntegrationSuite
## P39f (plan M6-M9 §6.3, §6.6: tools/web/world_check.mjs): the world walk's fast travel (WorldWalk's
## --walk-travel) on the tiny streamed world of tests/support/living_world_fixtures.gd (its index has two
## waystones, the west and the east stone), in the campaign. The web world check Continues a save, fast
## travels and walks: before, the walk had no travel - stream_check.mjs could only walk from New Game's
## start - so the web build's level reload by fast travel was never measured.
##   * the walk waits for the level to settle, asks for the travel the map's way (Events.travel_requested,
##     "fast_travel"): GameSession commits a checkpoint at the stone and reloads (logged in tests); on the
##     level it arrives in, the next walk sets off from where the travel put the giant and walks its route;
##   * a held-back travel (an aware enemy close by) is asked again until it goes, its refusals counted;
##   * a refused place (not visited) ends the walk at once with the reason, alone in its failures.

const LW := preload("res://tests/support/living_world_fixtures.gd")
## The scene the tiny level's record names (any existing scene: tests never load it - a reload is logged).
const STAND_IN_SCENE := "res://scenes/world/world.tscn"

var w: WorldRoot
var p: GiantPlayer


func before_each() -> void:
	await super()
	WorldWalk.reset_run()
	LW.install()
	TinyWorld.install_record(LW.GRID, {"regions": [LW.REGION], "max_active_enemies": 12, "scene": STAND_IN_SCENE})
	var made := LW.make(world)
	w = made[0]
	p = w.player()
	TestSpawn.disable_all_ai(w)
	WanderDirector.test_active = false   # (the living world stays off: only the travel and the walk here)
	# the campaign on the tiny level, started at the west stone (as a Continue would put the giant there)
	GameSession.start_world_for_tests(LW.NEAR_CP)
	GameSession.level_id = LW.LEVEL
	GameSession.on_level_ready(w, p)
	LW.load_ring(w, p.global_position)


func after_each() -> void:
	WorldWalk.reset_run()
	LW.reset()
	await super()


## A WorldWalk with the travel to the east stone and a short route near it (the arrival comes first).
func _walk(extra := {}) -> WorldWalk:
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	add_child(walk)
	var opts := {"route": PackedVector3Array([Vector3(104.0, 0.0, 92.0), Vector3(110.0, 0.0, 88.0)]), "speed": 0.0,
		"travel": LW.FAR_CP}
	opts.merge(extra, true)
	walk.start(p, w, null, opts)
	return walk


## Steps until `walk` is done, or its state is `state`, or `max_ticks` passed.
func _run(walk: WorldWalk, max_ticks: int, state := "") -> void:
	var ticks := 0
	while not walk.done and ticks < max_ticks and (state == "" or walk.get("_state") != state):
		await step_ticks(1)
		ticks += 1


func test_the_walk_fast_travels_then_walks_from_where_it_arrived() -> void:
	assert_eq(WorldWalk.parse_options(PackedStringArray(["--walk-travel=" + LW.FAR_CP])).travel, LW.FAR_CP,
		"--walk-travel names the stone")
	WorldState.set_flag("visited." + LW.FAR_CP, true)
	var reloads := GameSession.scene_reloads.size()
	var first := _walk()
	assert_eq(first.get("_state"), "travel", "the walk asks for the travel first")
	await _run(first, WorldWalk.TRAVEL_SETTLE_TICKS - 5)
	assert_true(WorldWalk.travel_run.is_empty(), "not during the level's first ticks")
	await _run(first, 60, "travelling")
	assert_eq(str(WorldWalk.travel_run.get("to", "")), LW.FAR_CP, "then it travels (%s)" % [WorldWalk.travel_run])
	assert_eq(str(WorldWalk.travel_run.get("from", "")), LW.NEAR_CP, "from the stone the level started at")
	assert_eq(int(WorldWalk.travel_run.get("refusals", -1)), 0, "nothing held it back")
	assert_eq(GameSession.scene_reloads.size(), reloads + 1, "one reload")
	assert_eq(GameSession.scene_reloads.back(), "fast_travel", "a fast travel's")
	assert_eq(GameSession.respawn_id, LW.FAR_CP, "the giant respawns at the east stone now")
	assert_eq(str((GameSession.checkpoint_doc.get("checkpoint", {}) as Dictionary).get("respawn", "")), LW.FAR_CP,
		"the travel's checkpoint is at it")
	assert_false(first.done, "the walk waits for the reload (which frees it)")
	assert_eq(first.ticks, 0, "and walked nothing")
	first.queue_free()
	# the reload: the level again, the giant where the travel puts him, a new walk with the same options
	GameSession.on_level_ready(w, p)
	var place := LW.make_index().checkpoints[LW.FAR_CP].position as Vector3
	assert_true(Vector2(p.global_position.x - place.x, p.global_position.z - place.z).length() < 1.0,
		"the arrival puts the giant at the east stone (%s)" % p.global_position)
	LW.load_ring(w, p.global_position)
	var arrived_at := p.global_position
	var second := _walk()
	assert_eq(second.get("_state"), "wait_ring", "on the level it arrived in, the walk sets off at once")
	assert_eq(second.route.size(), 3, "from the arrival, then the route's two points")
	assert_true(Vector2(second.route[0].x - arrived_at.x, second.route[0].z - arrived_at.z).length() < 0.01,
		"its first point is where the travel put the giant")
	await _run(second, 60 * 10)
	var r := second.result()
	assert_true(second.done and bool(r.finished), "the walk finished (%s)" % [r.check_failures])
	assert_eq(int(r.stuck_teleports), 0, "with no teleport (the walk did not jump to its first point)")
	assert_eq(str(r.travel_to), LW.FAR_CP, "the report names the travel")
	assert_true((r.travel as Dictionary).has("arrived_tick"), "and its arrival")
	assert_true(float((r.travel as Dictionary).get("arrival_m", -1.0)) >= 0.0
		and float((r.travel as Dictionary).get("arrival_m", 99.0)) < 1.0, "at the stone (%s)" % [r.travel])
	for f: String in r.check_failures:
		assert_false(f.contains("travel"), "no travel failure (%s)" % f)   # (the tiny world is too small for the 200 m margin)
	second.queue_free()


func test_a_travel_held_back_by_an_aware_enemy_goes_once_it_may() -> void:
	WorldState.set_flag("visited." + LW.FAR_CP, true)
	var stub := TestSpawn.stub_enemy(w, p.global_position + Vector3(0.0, 0.0, -20.0), "p39f.watcher")
	stub.brain.aware = true
	var walk := _walk()
	await _run(walk, WorldWalk.TRAVEL_SETTLE_TICKS + 30)
	assert_false(walk.done, "the walk keeps waiting while an aware enemy is close (a blocker, not a refusal of the place)")
	assert_true(WorldWalk.travel_run.is_empty(), "no travel yet")
	assert_true(int(walk.get("_travel_refusals")) >= 20, "refused each tick (%d)" % int(walk.get("_travel_refusals")))
	stub.global_position = p.global_position + Vector3(0.0, 0.0, -70.0)
	await _run(walk, 30, "travelling")
	assert_eq(str(WorldWalk.travel_run.get("to", "")), LW.FAR_CP, "with the enemy 70 m off it travels")
	assert_true(int(WorldWalk.travel_run.get("refusals", 0)) >= 20, "the travel counts its refusals")
	assert_eq(str(WorldWalk.travel_run.get("last_refusal", "")), "Not while enemies are close.", "and the last reason")
	walk.queue_free()
	# a travel still held back after travel_wait_ticks fails the walk with the reason
	WorldWalk.reset_run()
	stub.global_position = p.global_position + Vector3(0.0, 0.0, -20.0)
	var held := _walk()
	held.travel_wait_ticks = WorldWalk.TRAVEL_SETTLE_TICKS + 20
	await _run(held, 120)
	assert_true(held.done, "the held travel gave up")
	assert_eq(held.travel_error, "fast travel to %s refused: Not while enemies are close." % LW.FAR_CP, "with the reason")
	assert_eq(Array(held.result().check_failures), [held.travel_error], "alone in the walk's failures")
	held.queue_free()


func test_a_refused_place_fails_the_walk_at_once() -> void:
	var reloads := GameSession.scene_reloads.size()
	var walk := _walk()   # the east stone was never reached
	await _run(walk, WorldWalk.TRAVEL_SETTLE_TICKS + 5)
	assert_true(walk.done, "a refusal no wait can end ends the walk")
	assert_eq(walk.travel_error, "fast travel to %s refused: %s" % [LW.FAR_CP, GameSession.NOT_VISITED], "with the reason")
	var r := walk.result()
	assert_eq(Array(r.check_failures), [walk.travel_error], "alone in the walk's failures")
	assert_false(bool(r.finished), "nothing was walked")
	assert_eq(GameSession.scene_reloads.size(), reloads, "and nothing reloaded")
	walk.queue_free()
	# outside the campaign there is nowhere to travel
	WorldWalk.reset_run()
	GameSession.mode = GameSession.Mode.SANDBOX
	var sandbox := _walk()
	await _run(sandbox, WorldWalk.TRAVEL_SETTLE_TICKS + 5)
	assert_true(sandbox.done and sandbox.travel_error.contains("not in the campaign"), "the sandbox: %s" % sandbox.travel_error)
	sandbox.queue_free()
