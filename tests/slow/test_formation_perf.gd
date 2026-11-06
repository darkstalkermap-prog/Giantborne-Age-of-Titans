extends IntegrationSuite
## P30 (plan M6-M9 §3.13 slow tests; slow, runs with --slow): the formation stress case on the
## formation test level - encounter.formation_test_stress, two pike regiments of nineteen pikemen
## and a banner each: 40 members, the desktop max_formation_members - at AI tier 0 around an
## invulnerable stage-4 giant standing 5.6 m in front of the left one:
##   * the director spawns all 40 (none counts toward max_active_enemies), two formations with a
##     crowd renderer each, every member at tier 0; the regiments turn to the giant, brace and draw
##     their rank and file as crowds;
##   * CPU per tick p95 <= 5 ms headless (PerfProbe's cpu_tick_ms over 4 s after its warm-up);
##   * rendered, the 40 members cost <= 120 draw calls with their six nearest promoted each
##     (tests/support/formation_draw_probe.gd in a child process under Xvfb, the gl_compatibility
##     renderer; skipped with a note without xvfb-run);
##   * the mid distance (FOLLOWUPS, the Valley's views at `low`): at `low` a soldier's rig draws as
##     one merged rest-pose mesh from 0.45 x render_lod_m, as its full rig again while it acts, and
##     not at all at `medium`.

const LEVEL := "res://scenes/test/formation_test.tscn"
const STRESS := "encounter.formation_test_stress"
const PROBE := "res://tests/support/formation_draw_probe.gd"
const PREFIX := "FORMATION_DRAWS "
const MAX_P95_MS := 5.0
const MAX_DRAWS := 120
const RUN_TICKS := 240


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


static func _stage_profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func test_forty_members_at_tier_0_cost_at_most_5_ms_per_tick() -> void:
	var lv := (load(LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	p.set_profile(_stage_profile(4))
	p.entity.apply_status(StressScenario.STATUS_INVULNERABLE, NAN, -1.0, "test")
	p.global_position = Vector3(148, 0.05, 8)   # in front of the left regiment (its front rank at z 2.4)
	p.velocity = Vector3.ZERO
	var d := lv.director()
	d.force_activate(STRESS)
	d.update_now()
	await step_ticks(2)
	assert_eq(d.formation_member_count(), 40, "the director spawned the 40 members")
	assert_eq(d.active_combatant_count(), 0, "none of them counts toward max_active_enemies")
	assert_eq(d.formations().size(), 2, "two formations")
	for f in d.formations():
		assert_true(d.crowd_renderer(f.id) != null, "%s has its crowd renderer" % f.id)
	var probe := PerfProbe.new()
	probe.warmup_ticks = 60
	probe.label = "formation_stress"
	world.add_child(probe)
	await step_ticks(RUN_TICKS)
	probe.finish()
	var tiers := {}
	for f in d.formations():
		for m in f.all_members():
			tiers[m.lod_tier] = int(tiers.get(m.lod_tier, 0)) + 1
	assert_eq(tiers, {0: 40}, "every member at AI tier 0 (the desktop budget's worst case)")
	var braces := 0
	var crowd := 0
	for f in d.formations():
		braces += f.brace_count
		crowd += d.crowd_renderer(f.id).instance_count()
	assert_true(braces > 0, "the regiments braced against the giant (%d pulses)" % braces)
	assert_true(crowd > 0, "and drew their rank and file as crowds (%d instances)" % crowd)
	var r := probe.result()
	var cpu: Variant = r.get("cpu_tick_ms")
	assert_true(typeof(cpu) == TYPE_DICTIONARY, "the probe measured the ticks (%s)" % [r.keys()])
	if typeof(cpu) != TYPE_DICTIONARY:
		return
	assert_true(float(cpu.p95) <= MAX_P95_MS, "CPU per tick p95 %.2f ms <= %.1f ms (p50 %.2f, max %.2f)" % [
		float(cpu.p95), MAX_P95_MS, float(cpu.p50), float(cpu.max)])
	print("    test_formation_perf: 40 members at tier 0, cpu_tick_ms p50 %.2f p95 %.2f p99 %.2f max %.2f; %d brace pulses, %d crowd instances" % [
		float(cpu.p50), float(cpu.p95), float(cpu.get("p99", 0.0)), float(cpu.max), braces, crowd])


func test_forty_members_draw_at_most_120_calls() -> void:
	if not _have("xvfb-run"):
		print("    test_formation_perf: rendered check skipped - xvfb-run is not installed (it needs a display)")
		return
	var args := PackedStringArray(["-a", "-s", "-screen 0 640x360x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--resolution", "640x360", "--audio-driver", "Dummy",
		"-s", PROBE])
	var output: Array = []
	var code := OS.execute("xvfb-run", args, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY, "it reported: %s" % (line if line != "" else text.right(600)))
	if typeof(r) != TYPE_DICTIONARY:
		return
	var near := int(r.near) - int(r.empty)
	var far := int(r.far) - int(r.empty)
	var rigs := int(r.rigs_each) - int(r.empty)
	assert_eq(int(r.members), 40, "the 40 members")
	assert_eq(int(r.promoted_near), 2 * CrowdRenderer.MAX_PROMOTED, "near a stage-4 giant each formation promotes six")
	assert_true(near > 0 and near <= MAX_DRAWS, "%d draw calls for the 40 near the giant (<= %d)" % [near, MAX_DRAWS])
	assert_true(far < near, "fewer with nobody promoted (%d)" % far)
	print("    test_formation_perf: 40 members draw %d calls near a stage-4 giant (12 promoted), %d far (none), %d as 40 rigs; %s" % [
		near, far, rigs, str(r.get("adapter", "?"))])


func test_at_low_a_rig_draws_one_rest_pose_mesh_at_mid_distance_and_its_full_rig_while_it_acts() -> void:
	var saved := Settings.graphics_override
	Settings.graphics_override = "low"
	var lv := LevelRoot.new()
	lv.name = "MidLodLevel"
	lv.level_id = "level.formation_test"
	world.add_child(lv)
	var s := TestSpawn.enemy(lv, "res://scenes/enemies/soldier.tscn", Vector3(0, 0.05, -6), "test.mid_soldier", false)
	await step_ticks(1)
	await get_tree().process_frame
	var rig := s.rig
	var lod := float(s.record.get("render_lod_m", 0.0))
	var mid := rig.mid_proxy
	assert_true(mid != null and mid.get_parent() == rig.body, "at low the rig has its mid-distance mesh under Body")
	if mid == null:
		Settings.graphics_override = saved
		return
	assert_eq(mid.mesh.get_surface_count(), 1, "one surface: one draw call")
	assert_near(mid.visibility_range_begin, lod * RigPaint.MID_FRACTION - RigPaint.RENDER_LOD_MARGIN_M, 0.01, "from 0.45 x render_lod_m")
	assert_near(mid.visibility_range_end, lod + RigPaint.RENDER_LOD_MARGIN_M, 0.01, "to render_lod_m")
	var part := rig.body.get_node("Torso/Mesh") as GeometryInstance3D
	assert_near(part.visibility_range_end, lod * RigPaint.MID_FRACTION + RigPaint.RENDER_LOD_MARGIN_M, 0.01,
		"the rig's parts end at the mid distance")
	assert_true(rig.far_proxy != null and rig.far_proxy.visibility_range_begin > mid.visibility_range_begin,
		"the one-box proxy still takes over beyond")
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	await get_tree().process_frame
	assert_near(part.visibility_range_end, lod + RigPaint.RENDER_LOD_MARGIN_M, 0.01, "acting: the full rig out to render_lod_m")
	assert_false(mid.visible, "and no mid mesh")
	var other := TestSpawn.enemy(lv, "res://scenes/enemies/soldier.tscn", Vector3(4, 0.05, -6), "test.mid_soldier_2", false)
	assert_true(rig.mid_proxy.mesh == other.rig.mid_proxy.mesh, "the rest-pose mesh is shared by the scene's instances")
	Settings.graphics_override = "medium"
	var med := TestSpawn.enemy(lv, "res://scenes/enemies/soldier.tscn", Vector3(8, 0.05, -6), "test.mid_soldier_3", false)
	assert_true(med.rig.mid_proxy == null, "at medium there is none")
	Settings.graphics_override = saved
