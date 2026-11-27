extends IntegrationSuite
## P60 (plan M11 §2.9, §2.12, §3.13 tests; slow, runs with --slow): the people at their limits.
##   * the cap: eighteen soldiers near the giant, sixteen skinned and never more; a held soldier is skinned even
##     with the cap at 0 and hangs limp; the others' models go back to the pool;
##   * tip matching, the people's contract: over every ACTIVE frame of every weapon arc of every person role
##     (the soldier's slash and chop, the bannerman's slash, the mage's staff), the visible weapon's outer half
##     lies within the tested capsule (its hit radius) of the swing the simulation tests;
##   * rendered (tests/support/people_probe.gd --probe=render in a child process under Xvfb, the gl_compatibility
##     renderer; skipped with a note without xvfb-run): a skinned soldier costs at most 3 draw calls; a flash
##     reaches one crowd instance and only it; forty soldiers at about 30 m as a crowd cost at most a dozen draw
##     calls and 600 triangles a person, and with the sixteen nearest skinned stay within the plan's primitives
##     (16 x 5,000 + 24 x 600); the probe's numbers are printed (docs/systems/P60.md).
## The giant is a stand-in (a node of group "player" at stage 1's distance scale) but in the rendered child.

const PROBE := "res://tests/support/people_probe.gd"
const PREFIX := "PEOPLE_PROBE "
const ARCS := [["res://scenes/enemies/soldier.tscn", "enemy.soldier", "ability.soldier_slash"],
	["res://scenes/enemies/soldier.tscn", "enemy.soldier", "ability.soldier_chop"],
	["res://scenes/enemies/bannerman.tscn", "enemy.bannerman", "ability.soldier_slash"],
	["res://scenes/enemies/mage.tscn", "enemy.mage", "ability.mage_staff"]]

var player: Node3D


func before_each() -> void:
	await super()
	PersonRig.enable_for_tests()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 6)
	world.add_child(player)
	player.add_to_group("player")


func test_the_cap_holds_a_held_soldier_is_skinned_and_models_go_back_to_the_pool() -> void:
	var all: Array[EnemyActor] = []
	for i in 18:
		all.append(spawn_soldier(Vector3(-6.0 + (i % 6) * 2.4, 0.05, -2.0 - (i / 6) * 2.4), 0.0, "test.cap_%d" % i))
	await step_ticks(2)
	var skinned := 0
	for s in all:
		skinned += 1 if (s.rig as PersonRig).skinned() else 0
	assert_eq(skinned, PersonRig.MAX_SKINNED, "sixteen of eighteen skinned, never more")
	PersonRig.set_cap(0)
	all[0].on_grabbed("test.holder")
	await step_ticks(2)
	skinned = 0
	for s in all:
		skinned += 1 if (s.rig as PersonRig).skinned() else 0
	assert_eq(skinned, 1, "with the cap at 0 only the held soldier is skinned")
	assert_true((all[0].rig as PersonRig).skinned() and (all[0].rig as PersonRig).current_clip() == "held",
		"it hangs limp (the held clip)")
	assert_true(PersonModel.pooled() >= 15, "the others' models went back to the pool (%d)" % PersonModel.pooled())
	assert_true(int(PersonRig.run_stats().skinned_max) <= PersonRig.MAX_SKINNED, "the run never skinned more than the cap")
	all[0].on_released("dropped")


func test_every_weapon_arc_shows_its_tested_swing() -> void:
	var report := PackedStringArray()
	for i in ARCS.size():
		var spec: Array = ARCS[i]
		var e := TestSpawn.enemy(world, spec[0], Vector3(-3.0 + i * 2.0, 0.05, 0), "test.arc_%d" % i, false, PI)
		await step_ticks(2)
		var rig := e.rig as PersonRig
		assert_true(rig.skinned(), "%s is skinned" % spec[1])
		var act := GameData.get_action(spec[2])
		if not e.controller.library.has(spec[2]):
			e.controller.add_action(act)
		e.controller.request(&"attack", {"action_id": spec[2]})
		assert_true(e.controller.action != null, "%s starts %s" % [spec[1], spec[2]])
		var worst := 0.0
		var frames := 0
		for k in 200:
			await get_tree().process_frame
			if e.controller.action == null and rig.rig_state().get("action") == null:
				break
			# what the rig showed last frame: its state and its pose (a process frame starts before the rigs run)
			if int(rig.rig_state().get("phase", 0)) != ActionDef.Phase.ACTIVE:
				continue
			var seg := e.weapon_segment_global(act, float(rig.rig_state().get("phase_fraction", 0.0)))
			var vis := rig.visible_weapon_segment()
			if vis.size() != 2:
				continue
			var grip: Vector3 = vis[0]
			var dir: Vector3 = (vis[1] as Vector3) - grip
			worst = maxf(worst, TipMatching.outer_half_deviation(grip, dir, dir.length(), seg[0], seg[1]))
			frames += 1
		assert_true(frames >= 2, "%s %s: ACTIVE frames seen (%d)" % [spec[1], spec[2], frames])
		assert_true(worst <= e.weapon_hit_radius(), "%s %s: the visible outer half within the tested capsule (%.3f m of %.2f)" % [
			spec[1], spec[2], worst, e.weapon_hit_radius()])
		report.append("%s %.3f" % [spec[2].trim_prefix("ability."), worst])
		e.queue_free()
	print("    test_people_render: the outer half's worst miss over the ACTIVE frames (m): %s" % ", ".join(report))


func test_rendered_draw_calls_flashes_and_the_formation_of_forty() -> void:
	if not _have("xvfb-run"):
		print("    test_people_render: rendered check skipped - xvfb-run is not installed (it needs a display)")
		return
	var r := run_probe("render")
	assert_true(not r.is_empty(), "the probe reported")
	if r.is_empty():
		return
	assert_true(bool(r.skinned), "the soldier alone is skinned")
	assert_true(int(r.one_calls) >= 1 and int(r.one_calls) <= 3, "a skinned person costs at most 3 draw calls (%d)" % int(r.one_calls))
	assert_true(int(r.flash_pixels) >= 40, "a flash lights a crowd instance (%d pixels)" % int(r.flash_pixels))
	assert_true(int((r.flash_box as Array)[2]) <= 40, "only the one flashed (a box %s wide)" % [r.flash_box])
	assert_true(int(r.crowd_prims) <= 40 * 600 + 20000, "forty as a crowd: at most 600 triangles each (%d primitives with the view)" % int(r.crowd_prims))
	assert_eq(int(r.mixed_skinned), PersonRig.MAX_SKINNED, "near the giant sixteen of the forty are skinned")
	assert_true(int(r.mixed_prims) <= 95000 + 20000, "and the primitives stay within 16 x 5,000 + 24 x 600 (%d with the view)" % int(r.mixed_prims))
	print("    test_people_render: one skinned %d calls; forty as a crowd %d calls, %d primitives; sixteen skinned %d calls, %d primitives; the people's CPU %.2f ms a frame; %s" % [
		int(r.one_calls), int(r.crowd_calls), int(r.crowd_prims), int(r.mixed_calls), int(r.mixed_prims),
		float(r.people_cpu_ms), str(r.get("adapter", "?"))])


## The probe's arguments (for xvfb-run) in `mode`.
static func probe_args(mode: String) -> PackedStringArray:
	return PackedStringArray(["-a", "-s", "-screen 0 640x480x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--rendering-driver", "opengl3", "--resolution", "640x480",
		"--audio-driver", "Dummy", "-s", PROBE, "--", "--no-user-settings", "--probe=" + mode])


## Dgate: the runner starts this suite's child ahead (ChildRuns), while the suites before it run.
static func prefetch_children() -> Array:
	return [["xvfb-run", probe_args("render")]] if _have("xvfb-run") else []


## people_probe.gd's result in `mode` ({} when it did not report).
static func run_probe(mode: String) -> Dictionary:
	var args := probe_args(mode)
	var output: Array = []
	ChildRuns.execute("xvfb-run", args, output)   # (Dgate: prefetched by the runner)
	for l in "\n".join(output).split("\n"):
		if l.begins_with(PREFIX):
			var parsed: Variant = JSON.parse_string(l.substr(PREFIX.length()).strip_edges())
			return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return {}


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0
