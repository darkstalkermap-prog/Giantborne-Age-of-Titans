extends IntegrationSuite
## P64 (plan M11 §2.10, §3.17 design 2): the wolf and the dire wolf skinned in play (SkinnedWolfRig), headless with
## the people switched on (PersonRig.enable_for_tests; ResetHooks turns them off after every test):
##   * headless the box rig draws as before;
##   * skinned: P63's wolf on its 25 bones in its atlas and palette, the box rig hidden, the fur shell's layers in one
##     surface (two meshes drawn); a flash reaches the coat and the fur; no fur at the `low` graphics preset; the dire
##     wolf the same mesh at x 2 in its own palette;
##   * the gait: carried at 1, 3 and 8 m/s the wolf walks, trots and gallops, a planted paw never slides and every
##     standing leg reaches its paw;
##   * the bite opens the jaw in its windup and snaps it shut in its active phase; the lunge's dash takes the lunge's
##     pose.

const WOLF := "res://scenes/enemies/wolf.tscn"
const DIRE := "res://scenes/enemies/dire_wolf.tscn"


func before_each() -> void:
	await super()
	var stand_in := Node3D.new()
	stand_in.name = "GiantStandIn"
	stand_in.position = Vector3(0, 0.05, 40)
	world.add_child(stand_in)
	stand_in.add_to_group("player")


func after_each() -> void:
	Settings.graphics_override = ""
	await super()


func _wolf(path: String, pos: Vector3, id: String, yaw := 0.0) -> WolfEnemy:
	var w := (load(path) as PackedScene).instantiate() as WolfEnemy
	w.entity_id = id
	w.ai_enabled = false
	w.position = pos
	w.rotation.y = yaw
	world.add_child(w)
	return w


static func _shown(node: Node) -> Array:
	var out: Array = []
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).is_visible_in_tree():
			out.append(g)
	return out


func test_headless_the_box_rig_and_skinned_the_wolf_with_its_fur() -> void:
	var box := _wolf(WOLF, Vector3(-6, 0.05, 0), "test.wolf_box")
	await step_ticks(3)
	assert_true(box.quad is SkinnedWolfRig, "the wolf's Visual is a SkinnedWolfRig (a QuadrupedRig)")
	assert_false((box.quad as SkinnedWolfRig).skinned, "headless: the box rig")
	assert_true(_shown(box.quad.body).size() >= 5, "its merged meshes draw")
	PersonRig.enable_for_tests()
	var w := _wolf(WOLF, Vector3(0, 0.05, 0), "test.wolf_skinned")
	var d := _wolf(DIRE, Vector3(6, 0.05, 0), "test.wolf_dire")
	await step_ticks(3)
	var rig := w.quad as SkinnedWolfRig
	assert_true(rig.skinned, "skinned where the people are drawn")
	assert_eq(rig.skeleton().get_bone_count(), 25, "the 25 bones")
	var shown := _shown(rig.body)
	assert_eq(shown.size(), 2, "two meshes drawn: the coat and the fur (%s)" % [shown.map(func(g: Node) -> String: return str(g.name))])
	var fur := rig.fur()
	assert_true(fur != null and fur.mesh.get_surface_count() == 1, "the fur shell in one surface")
	var shell_tris: int = int((SkinnedQuadrupedRig.creature_index().wolf.get("shell", {}) as Dictionary).get("layers", {}).get("desktop", 12))
	assert_eq(shell_tris, SkinnedWolfRig.FUR_LAYERS.medium, "the manifest's twelve layers at medium")
	var uv2: PackedVector2Array = fur.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	assert_near(uv2[uv2.size() - 1].x, 1.0, 1e-6, "the last layer at the fur's tips")
	assert_true(fur.skin != null and fur.get_node(fur.skeleton) == rig.skeleton(), "the fur skinned to the wolf's bones")
	assert_eq(Color(rig.material().get_shader_parameter("skin_color")).to_html(false), "8e8476", "the wolf's coat")
	var dr := d.quad as SkinnedWolfRig
	assert_near(dr.size(), 2.0, 1e-6, "the dire wolf at x 2")
	assert_eq(Color(dr.material().get_shader_parameter("cloth_color")).to_html(false), "f06a2c", "its ember eyes")
	w.flash(1.0)
	await step_ticks(1)
	for m: ShaderMaterial in [rig.material(), rig.fur_material()]:
		assert_true((m.get_shader_parameter("flash") as Vector3).x > 0.3, "the flash on %s" % m)
	Settings.graphics_override = "low"
	var low := _wolf(WOLF, Vector3(0, 0.05, 8), "test.wolf_low")
	await step_ticks(3)
	assert_true((low.quad as SkinnedWolfRig).skinned and (low.quad as SkinnedWolfRig).fur() == null, "no fur at low")


func test_the_gait_follows_the_speed_and_planted_paws_never_slide() -> void:
	PersonRig.enable_for_tests()
	var w := _wolf(WOLF, Vector3(0, 0.05, 0), "test.wolf_gait", -PI * 0.5)
	await step_ticks(3)
	var rig := w.quad as SkinnedWolfRig
	w.process_mode = Node.PROCESS_MODE_DISABLED   # carried: the rig reads the actor's motion
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	for spec: Array in [[1.0, "walk"], [3.0, "trot"], [8.0, "gallop"]]:
		var v: float = spec[0]
		w.position = Vector3(0, 0.05, 0)
		await step_ticks(2)
		var lifted := 0
		var planted_moves := 0.0
		var last := {}
		for k in 80:
			w.velocity = Vector3(v, 0, 0)
			w.position.x += v / 60.0
			if k == 40:
				rig.max_reach_miss = 0.0
			await step_ticks(1)
			if k > 40:
				var p := rig.paws()
				for leg: String in p:
					if bool(p[leg][1]) and last.has(leg) and bool(last[leg][1]):
						planted_moves = maxf(planted_moves, (p[leg][0] as Vector3).distance_to(last[leg][0]))
					if not bool(p[leg][1]):
						lifted += 1
				last = p
		var g := rig.gait()
		assert_true(float(g[spec[1]]) > 0.9, "at %.1f m/s the %s (%s)" % [v, spec[1], g])
		assert_true(lifted > 0, "%s: the legs swing" % spec[1])
		assert_true(planted_moves < 1e-4, "%s: a planted paw never slides (%.5f m)" % [spec[1], planted_moves])
		assert_true(rig.max_reach_miss < 0.02, "%s: every standing leg reaches its paw (%.3f m short)" % [spec[1], rig.max_reach_miss])
	assert_true(SkinnedWolfRig.stride_hz(3.0, 0.5) > 2.6 and SkinnedWolfRig.stride_hz(3.0, 0.5) < 3.4,
		"the trot of 3 m/s at about 3 strides a second (%.2f)" % SkinnedWolfRig.stride_hz(3.0, 0.5))


func test_the_bite_snaps_the_jaw_and_the_lunge_reaches() -> void:
	PersonRig.enable_for_tests()
	var w := _wolf(WOLF, Vector3(0, 0.05, 0), "test.wolf_bite")
	await step_ticks(3)
	var rig := w.quad as SkinnedWolfRig
	w.controller.request(&"attack", {"action_id": "ability.wolf_bite"})
	var open_windup := 0.0
	var open_late := 1.0
	for i in 60:
		await step_ticks(1)
		var s := w.get_rig_state()
		if s.action == null:
			break
		if int(s.phase) == ActionDef.Phase.WINDUP:
			open_windup = maxf(open_windup, rig.jaw_open())
		elif int(s.phase) == ActionDef.Phase.RECOVERY:
			open_late = minf(open_late, rig.jaw_open())
	assert_true(open_windup > 0.6, "the windup opens the jaw (%.2f)" % open_windup)
	assert_true(open_late < 0.05, "shut by the recovery (%.2f)" % open_late)
	await step_ticks(20)
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	var lunge := 0.0
	for i in 120:
		await step_ticks(1)
		lunge = maxf(lunge, rig.lunge_weight())
	assert_true(lunge > 0.9, "the dash in the lunge's pose (%.2f)" % lunge)
	assert_true(rig.lunge_weight() < 0.01, "and out of it after")
