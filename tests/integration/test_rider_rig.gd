extends IntegrationSuite
## P62 (plan M11 §2.10, §3.15 design 2): the cavalry's horse skinned in play and its rider (SkinnedQuadrupedRig),
## headless with the people switched on (PersonRig.enable_for_tests; ResetHooks turns them off after every test):
##   * headless the box rig draws as before (the brain's pivots and its merged meshes, the footfalls);
##   * skinned: the creatures' horse (25 bones, the tacked mesh, the box rig hidden) in person.gdshader with the
##     strands cut, a rider of the rider role on the saddle's seat in the seated clip, the lance in the right fist:
##     three meshes drawn; a flash reaches all three;
##   * the gait: walking, trotting and galloping (the actor carried at 1.6, 4 and 13 m/s) the gait's weights follow
##     the speed, a planted hoof never moves, and every standing leg's solve reaches its hoof;
##   * the record's body.rig "box" keeps the box rig (the beasts' gate's fallback);
##   * the charge's windup couches the lance (its telegraph), its run holds it couched.

const CAVALRY := "res://scenes/enemies/cavalry.tscn"
const CHARGE := "ability.cavalry_charge"

var player: Node3D


func before_each() -> void:
	await super()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 30)
	world.add_child(player)
	player.add_to_group("player")


func _cavalry(pos: Vector3, id: String, yaw := 0.0) -> CavalryEnemy:
	var c := (load(CAVALRY) as PackedScene).instantiate() as CavalryEnemy
	c.entity_id = id
	c.ai_enabled = false
	c.position = pos
	c.rotation.y = yaw
	world.add_child(c)
	return c


static func _shown(node: Node) -> Array:
	var out: Array = []
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).is_visible_in_tree():
			out.append(g)
	return out


func test_headless_the_box_rig_draws_as_before() -> void:
	var c := _cavalry(Vector3(0, 0.05, 0), "test.box_rider")
	await step_ticks(3)
	var rig := c.quad as SkinnedQuadrupedRig
	assert_true(rig != null, "the cavalry's Visual is a SkinnedQuadrupedRig (a QuadrupedRig)")
	assert_false(rig.skinned, "headless: not skinned")
	assert_true(rig.horse() == null and rig.rider() == null, "no horse model, no rider")
	assert_true(_shown(rig.body).size() >= 5, "the box rig's merged meshes draw (%d)" % _shown(rig.body).size())


func test_the_horse_and_its_rider_are_skinned_and_draw_three_meshes() -> void:
	PersonRig.enable_for_tests()
	var c := _cavalry(Vector3(0, 0.05, 0), "test.rider_a")
	c.faction = "aldmere"
	await step_ticks(3)
	var rig := c.quad as SkinnedQuadrupedRig
	assert_true(rig.skinned, "skinned where the people are drawn")
	var sk := rig.skeleton()
	assert_true(sk != null and sk.get_bone_count() == 25, "the horse's 25 bones")
	var shown := _shown(rig.body)
	assert_eq(shown.size(), 3, "three meshes drawn: the horse, the rider, the lance (%s)" % [shown.map(func(g: Node) -> String: return str(g.name))])
	var tacked := sk.get_node_or_null("horse_tacked") as MeshInstance3D
	assert_true(tacked != null and tacked.visible and not (sk.get_node("horse") as MeshInstance3D).visible,
		"the tacked horse, not the bare one")
	assert_true(bool(rig.material().get_shader_parameter("strands")), "its mane and tail cut by alpha scissor")
	var r := rig.rider()
	assert_true(r != null and r.role == "rider" and r.get_parent() == sk, "a rider of the rider role on the horse's skeleton")
	var seat: Array = (SkinnedQuadrupedRig.creature_index().horse.landmarks.saddle_seat as Dictionary).position
	assert_true(r.position.distance_to(Vector3(float(seat[0]), float(seat[1]), float(seat[2]))) < 1e-4,
		"its origin on the saddle's seat")
	assert_eq(String(r.player().current_animation), "people/seated", "in the seated clip")
	var lance := rig.lance_socket().get_node_or_null("Gear_lance") as MeshInstance3D
	assert_true(lance != null and lance.mesh == PersonModel.gear_mesh("spear"), "the lance in the socket")
	var fist := r.skeleton().global_transform * (r.skeleton().get_bone_global_pose(r.skeleton().find_bone("hand_r"))
		* (PersonRig.grips_of(r.role, r.variant).grip_r as Vector3))
	assert_true(rig.lance_socket().global_position.distance_to(fist) < 0.01, "the lance in the right fist")
	assert_true(rig.lance_socket().global_transform.basis.y.normalized().y > 0.8, "carried upright at rest")
	# a flash reaches the horse, the rider and the lance
	c.flash(1.0)
	await step_ticks(1)
	for m: ShaderMaterial in [rig.material(), r.material, lance.material_override as ShaderMaterial]:
		assert_true((m.get_shader_parameter("flash") as Vector3).x > 0.3, "the flash on %s" % m)
	assert_true(not (c.get_node("Visual/LodProxy") as MeshInstance3D).visible and
		(c.get_node("Visual/LodProxy") as MeshInstance3D).mesh == tacked.mesh, "the dormant stand-in is the horse's mesh")


func test_the_gait_follows_the_speed_and_planted_hooves_never_slide() -> void:
	PersonRig.enable_for_tests()
	var c := _cavalry(Vector3(0, 0.05, 0), "test.rider_gait", -PI * 0.5)
	await step_ticks(3)
	var rig := c.quad as SkinnedQuadrupedRig
	c.process_mode = Node.PROCESS_MODE_DISABLED   # carried: the rig reads the actor's motion
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	for spec: Array in [[1.6, "walk"], [4.0, "trot"], [13.0, "gallop"]]:
		var v: float = spec[0]
		c.position = Vector3(0, 0.05, 0)
		await step_ticks(2)
		var lifted := 0
		var planted_moves := 0.0
		var last := {}
		for k in 90:
			c.velocity = Vector3(v, 0, 0)
			c.position.x += v / 60.0
			if k == 40:
				rig.max_reach_miss = 0.0
			await step_ticks(1)
			if k > 40:
				var h := rig.hooves()
				for leg: String in h:
					if bool(h[leg][1]) and last.has(leg) and bool(last[leg][1]):
						planted_moves = maxf(planted_moves, (h[leg][0] as Vector3).distance_to(last[leg][0]))
					if not bool(h[leg][1]):
						lifted += 1
				last = h
		var g := rig.gait()
		assert_true(float(g[spec[1]]) > 0.95, "at %.1f m/s the %s (%s)" % [v, spec[1], g])
		assert_true(lifted > 0, "%s: the legs swing" % spec[1])
		assert_true(planted_moves < 1e-4, "%s: a planted hoof never slides (%.5f m)" % [spec[1], planted_moves])
		assert_true(rig.max_reach_miss < 0.02, "%s: every standing leg reaches its hoof (%.3f m short)" % [spec[1], rig.max_reach_miss])
	# standing: the hooves step back under the horse
	await step_ticks(120)   # (one step at a time, STEP_S each)
	var stand := rig.hooves()
	for leg: String in stand:
		assert_true(bool(stand[leg][1]), "standing: %s stands" % leg)


func test_the_box_rig_is_selectable_and_the_charge_couches_the_lance() -> void:
	PersonRig.enable_for_tests()
	var box := (load(CAVALRY) as PackedScene).instantiate() as CavalryEnemy
	box.entity_id = "test.rider_box"
	box.ai_enabled = false
	box.position = Vector3(-6, 0.05, 0)
	world.add_child(box)
	box.record = box.record.duplicate(true)
	(box.record.body as Dictionary)["rig"] = "box"
	var c := _cavalry(Vector3(6, 0.05, 0), "test.rider_charge")
	await step_ticks(3)
	assert_false((box.quad as SkinnedQuadrupedRig).skinned, "body.rig box: the box rig")
	assert_true(_shown(box.quad.body).size() >= 5, "drawn as boxes")
	var rig := c.quad as SkinnedQuadrupedRig
	assert_true(rig.skinned and rig.lance_couched() < 0.05, "skinned, the lance carried")
	if not c.controller.library.has(CHARGE):
		c.controller.add_action(GameData.get_action(CHARGE))
	c.controller.request(&"attack", {"action_id": CHARGE})
	var couched_in_windup := 0.0
	var active_min := 1.0
	for k in 180:
		await step_ticks(1)
		var s := c.get_rig_state()
		if s.action == null:
			break
		if int(s.phase) == ActionDef.Phase.WINDUP:
			couched_in_windup = maxf(couched_in_windup, rig.lance_couched())
		elif int(s.phase) == ActionDef.Phase.ACTIVE:
			active_min = minf(active_min, rig.lance_couched())
	assert_true(couched_in_windup > 0.6, "the windup lowers the lance (%.2f)" % couched_in_windup)
	assert_true(active_min > 0.95, "the run holds it couched (%.2f)" % active_min)
	var dir := rig.lance_socket().global_transform.basis.y.normalized()
	assert_true(absf(dir.y) < 0.4, "couched: the lance near level")
