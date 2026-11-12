extends IntegrationSuite
## P38 (plan M6-M9 §6.1): the world bot's smoke run and its world invariants.
##   * a child process plays the open world from a new game with the mixed preset, assisted, until
##     Brannock's oath is done (--bot-until=oath.march.done): Kingsgate's beacon, the growth to stage 4,
##     the road to Brannock and Edda intimidated. It exits 0 with finish_reason "until", the march's
##     outcome "intimidate", no breach, no watchdog, no invariant failure, no error, and the world's
##     metrics written (the region, the discoveries, the streaming with its margin, the save size,
##     the path queries, the segments); under 4 minutes of wall time;
##   * each world invariant (BotDiagnosis.check_world_invariants) fires on its own injected fault on the
##     streamed test world - the formation cap, a living member in a chunk that is not loaded, a chunk
##     reloaded within the thrash window, two world events at once, an event's fail timer running while
##     its centre is unloaded, a save over 200 KB - and stays quiet without one; a group lock on a
##     formation that is gone is a lock failure.

const SCENE := "res://scenes/test/test_world.tscn"
const BAND := "encounter.test_world_soldiers"
const SMOKE_WALL_S := 240.0
const RESULT_PREFIX := "AUTOPILOT_RESULT "


## A world event stand-in's director: a node in the WanderDirector group with the events table.
class FakeWander extends Node:
	var events := {}

	func _enter_tree() -> void:
		add_to_group(WanderDirector.GROUP)


static func run_smoke() -> Dictionary:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--no-audio", "--save-dir=user://bot_saves/gate_smoke",
		"--mode=world", "--new-game", "--scenario=world", "--autoplay=600", "--bot-preset=mixed", "--bot-assist",
		"--bot-seed=1", "--bot-until=oath.march.done"])
	var output: Array = []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var out := {"code": code, "wall_s": (Time.get_ticks_msec() - t0) / 1000.0, "result": {}, "output": text}
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX):
			var parsed: Variant = JSON.parse_string(line.substr(RESULT_PREFIX.length()).strip_edges())
			if typeof(parsed) == TYPE_DICTIONARY:
				out.result = parsed
			break
	return out


func test_the_world_bot_plays_from_a_new_game_to_brannocks_oath() -> void:
	var r := run_smoke()
	var result: Dictionary = r.result
	var wb: Dictionary = result.get("world_bot", {})
	var world_m: Dictionary = wb.get("world", {})
	var tail := "\n".join((str(r.output).split("\n") as PackedStringArray).slice(-12))
	print("    test_world_bot_smoke: exit %d in %.0f s wall, %.0f s simulated, march %s, %d discoveries, margin %.0f m, save %d bytes" % [
		r.code, r.wall_s, float(wb.get("simulated_s", 0.0)), str((wb.get("outcomes", {}) as Dictionary).get("march", "")),
		int(world_m.get("discovered", 0)), float((world_m.get("streaming", {}) as Dictionary).get("min_margin_m", 0.0)),
		int(world_m.get("save_bytes_max", 0))])
	assert_eq(int(r.code), 0, "the run exits 0:\n%s" % tail)
	assert_false(wb.is_empty(), "the result has the world bot's block")
	if wb.is_empty():
		return
	assert_eq(str(wb.get("finish_reason", "")), "until", "it ended at --bot-until (oath.march.done)")
	assert_eq(str((wb.get("outcomes", {}) as Dictionary).get("march", "")), "intimidate", "Edda was intimidated (the mixed preset)")
	assert_eq((wb.get("breaches", []) as Array).size(), 0, "no watchdog breach: %s" % [wb.get("breaches")])
	assert_eq((wb.get("invariant_failures", []) as Array).size(), 0, "no invariant failure: %s" % [wb.get("invariant_failures")])
	assert_eq(int(result.get("errors", -1)), 0, "no error: %s" % [result.get("error_samples")])
	assert_eq(int(wb.get("world_blocked", -1)), 0, "nothing world_blocked")
	assert_true((world_m.get("regions", {}) as Dictionary).has("region.crownmarch"), "the Crownmarch's time is counted")
	assert_true(int(world_m.get("discovered", 0)) >= 3, "the shelf, the beacon, the shrine and Brannock discovered (%d)" % int(world_m.get("discovered", 0)))
	var streaming: Dictionary = world_m.get("streaming", {})
	assert_true(int(streaming.get("loads", 0)) > 0 and int(streaming.get("thrash", -1)) == 0, "chunks streamed in, none thrashed")
	assert_true(float(streaming.get("min_margin_m", 0.0)) > 0.0, "the loaded margin ahead is measured")
	assert_true(int(world_m.get("save_bytes_max", 0)) > 0, "the checkpoint saves are measured")
	assert_true((world_m.get("path_queries_per_tick", {}) as Dictionary).has("p95"), "the path queries per tick are counted")
	var segments: Array = wb.get("segments", [])
	assert_eq(segments.size(), 5, "the five world segments")
	assert_true(not segments.is_empty() and float((segments[0] as Dictionary).get("raw_s", 0.0)) > 0.0, "the opening segment has time")
	assert_true(float(wb.get("human_estimate_s", 0.0)) > float(wb.get("simulated_s", 0.0)), "a human estimate above the bot's time")
	assert_true(float(r.wall_s) < SMOKE_WALL_S, "under %d s of wall time (%.0f s)" % [int(SMOKE_WALL_S), r.wall_s])


## The test world with the giant held at (x, z) and the ring around it streamed in.
func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 300:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	return w


## A position of the grid in a chunk that is not loaded (Vector3.INF when every chunk is).
static func _unloaded_spot(s: ChunkStreamer, around: Vector3) -> Vector3:
	for r in range(1, 12):
		for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var p := around + Vector3(dir.x, 0.0, dir.y) * 128.0 * r
			var c := s.chunk_at(p)
			if c != "" and not s.is_loaded(c):
				return p
	return Vector3.INF


func test_each_world_invariant_fires_on_its_fault() -> void:
	var w := await _world(Vector2(2.0, 106.0))
	var s := w.streamer
	var d := w.director()
	var state := {}
	assert_eq(BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000), PackedStringArray(),
		"no failure on the world as it is")
	# the formation cap
	var cap := d.max_formation_members
	d.max_formation_members = d.formation_member_count() - 1
	var fails := BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000)
	assert_true(fails.size() == 1 and fails[0].begins_with("formation members"), "the formation cap: %s" % [fails])
	d.max_formation_members = cap
	# a save over 200 KB
	fails = BotDiagnosis.check_world_invariants(get_tree(), w, state, BotDiagnosis.MAX_SAVE_BYTES + 1)
	assert_true(fails.size() == 1 and fails[0].begins_with("the save is"), "the save size: %s" % [fails])
	# a chunk reloaded within the thrash window
	s.thrash += 1
	fails = BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000)
	assert_true(fails.size() == 1 and fails[0].begins_with("a chunk reloaded"), "thrash: %s" % [fails])
	assert_eq(BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000), PackedStringArray(), "counted once")
	# a living member standing in a chunk that is not loaded
	d.force_activate(BAND)
	d.update_now()
	var members := d.members_of(BAND)
	var moved: Node3D = null
	for id in members:
		var n := d.spawned(id)
		if n != null and is_instance_valid(n):
			moved = n
			break
	assert_true(moved != null, "the band spawned")
	var spot := _unloaded_spot(s, moved.global_position if moved != null else Vector3.ZERO)
	assert_true(spot.is_finite(), "a chunk of the grid is not loaded")
	if moved != null and spot.is_finite():
		var home := moved.global_position
		moved.global_position = spot
		fails = BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000)
		assert_true(fails.size() == 1 and fails[0].contains("which is not loaded"), "a member in an unloaded chunk: %s" % [fails])
		assert_eq(BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000, false).size(), 0,
			"the member scan is the full scan's (every 30 ticks)")
		moved.global_position = home
	# two world events at once, and a fail timer running with its centre unloaded
	var wander := FakeWander.new()
	add_child(wander)
	var a := WorldEvent.new()
	a.id = "event.test_a"
	a.state = WorldEvent.RUNNING
	a.centre = moved.global_position if moved != null else Vector3.ZERO
	wander.events[a.id] = a
	assert_eq(BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000), PackedStringArray(), "one event runs: no failure")
	var b := WorldEvent.new()
	b.id = "event.test_b"
	b.state = WorldEvent.RUNNING
	b.centre = spot
	wander.events[b.id] = b
	fails = BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000)
	assert_true(fails.size() == 1 and fails[0].begins_with("2 world events at once"), "two events: %s" % [fails])
	b.state = WorldEvent.SUSPENDED
	var timer_fails := PackedStringArray()
	for i in BotDiagnosis.EVENT_UNLOADED_GRACE_TICKS + 2:
		b.elapsed_s += 1.0 / 60.0
		for f in BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000):
			if f.contains("fail timer runs"):
				timer_fails.append(f)
	assert_true(timer_fails.size() >= 1, "a fail timer running while its centre is unloaded (after the grace)")
	wander.events.erase(b.id)
	a.state = WorldEvent.IDLE
	assert_eq(BotDiagnosis.check_world_invariants(get_tree(), w, state, 1000), PackedStringArray(), "quiet again")
	wander.queue_free()
	# a group lock on a formation that is gone
	assert_true(BotDiagnosis.lock_failure(BotDiagnosis.GROUP_LOCK_PREFIX + "formation.gone") != "",
		"a group lock on a formation that is gone is a lock failure")
	w.queue_free()
	await get_tree().process_frame
