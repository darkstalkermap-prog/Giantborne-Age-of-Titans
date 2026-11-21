extends IntegrationSuite
## P64 (plan M11 §2.10, §3.17 design 1): the brutes skinned in play (BruteRig), headless with the people switched on
## (PersonRig.enable_for_tests; ResetHooks turns them off after every test):
##   * headless the box rig draws as before; the record's body.rig "box" keeps it;
##   * the ogre: its creature model on the 23 bones in the creature's atlas, the box rig hidden, a club in the right
##     fist: two meshes drawn; a flash and a status tint reach the body and the club;
##   * the Ogre King at x 2.5 with his gear (three meshes), always holding a slot; the whelp the troll's variant at
##     its record's 3.5 m; the Matriarch with her gear;
##   * the smash plays the slam on the brain's clock (the fists over the head as its windup ends, on the ground in
##     its active phase), the sweep puts the arms on the brain's poses; walking, a planted foot does not slide;
##   * the slots: with the cap at one, the second ogre shows its far mesh until the first is gone.

const OGRE := "res://scenes/enemies/ogre.tscn"
const KING := "res://scenes/enemies/ogre_king.tscn"
const WHELP := "res://scenes/enemies/troll_whelp.tscn"
const MATRIARCH := "res://scenes/enemies/troll_matriarch.tscn"


func before_each() -> void:
	await super()
	var stand_in := Node3D.new()
	stand_in.name = "GiantStandIn"
	stand_in.position = Vector3(0, 0.05, 40)
	world.add_child(stand_in)
	stand_in.add_to_group("player")


func after_each() -> void:
	CreatureSlots.reset_for_tests()
	await super()


func _brute(path: String, pos: Vector3, id: String) -> EnemyActor:
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.position = pos
	world.add_child(e)
	return e


static func _shown(node: Node) -> Array:
	var out: Array = []
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).is_visible_in_tree():
			out.append(g)
	return out


func test_headless_and_box_the_box_rig_draws_as_before() -> void:
	var o := _brute(OGRE, Vector3(-4, 0.05, 0), "test.brute_headless")
	await step_ticks(3)
	var rig := o.rig as BruteRig
	assert_true(rig != null, "the ogre's Visual is a BruteRig (an ActorRig)")
	assert_false(rig.skinned, "headless: not skinned")
	assert_true(rig.model() == null and _shown(rig.body).size() >= 5, "the box rig's merged meshes draw")
	PersonRig.enable_for_tests()
	var box := (load(OGRE) as PackedScene).instantiate() as EnemyActor
	box.entity_id = "test.brute_box"
	box.ai_enabled = false
	box.position = Vector3(4, 0.05, 0)
	world.add_child(box)
	box.record = box.record.duplicate(true)
	(box.record.body as Dictionary)["rig"] = "box"
	await step_ticks(2)
	assert_false((box.rig as BruteRig).skinned, "body.rig box: the box rig")


func test_the_ogre_the_king_the_whelp_and_the_matriarch_skinned() -> void:
	PersonRig.enable_for_tests()
	var o := _brute(OGRE, Vector3(-8, 0.05, 0), "test.brute_ogre")
	var k := _brute(KING, Vector3(8, 0.05, 0), "test.brute_king")
	var w := _brute(WHELP, Vector3(0, 0.05, -8), "test.brute_whelp")
	var m := _brute(MATRIARCH, Vector3(0, 0.05, -24), "test.brute_matriarch")
	await step_ticks(3)
	var rig := o.rig as BruteRig
	assert_true(rig.skinned, "skinned where the people are drawn")
	assert_eq(rig.skeleton().get_bone_count(), 23, "the 23 bones")
	assert_eq(str(rig.body_mesh().name), "ogre", "the ogre's mesh")
	assert_true(rig.material().get_shader_parameter("albedo_tex") == load("res://assets/creatures/ogre_albedo.png"),
		"in the ogre's atlas")
	var shown := _shown(rig.body)
	assert_eq(shown.size(), 2, "two meshes drawn: the body and the club (%s)" % [shown.map(func(g: Node) -> String: return str(g.name))])
	var sk := rig.skeleton()
	var fist := sk.global_transform * (sk.get_bone_global_pose(sk.find_bone("hand_r")).origin)
	assert_true(rig.club().global_position.distance_to(fist) < 0.4, "the club in the right hand")
	assert_eq(rig.current_clip(), "idle", "standing: the idle")
	o.flash(1.0)
	rig.set_status_tint(Color(0.2, 0.9, 0.3, 0.5))
	await step_ticks(1)
	for mat: ShaderMaterial in [rig.material(), rig.club().material_override as ShaderMaterial]:
		assert_true((mat.get_shader_parameter("flash") as Vector3).x > 0.3, "the flash on %s" % mat)
		assert_true((mat.get_shader_parameter("tint") as Vector4).w > 0.4, "the tint on %s" % mat)
	var kr := k.rig as BruteRig
	assert_near(kr.model_scale(), 2.5, 1e-3, "the King at x 2.5")
	assert_true(kr.gear_mesh() != null and kr.gear_mesh().is_visible_in_tree(), "the King's mantle, belt and crown")
	assert_eq(_shown(kr.body).size(), 3, "the King: body, gear and club")
	assert_true(bool(kr.creature_spec().boss) and kr.has_slot(), "a boss always holds a slot")
	var wr := w.rig as BruteRig
	assert_eq(str(wr.body_mesh().name), "whelp", "the whelp's variant")
	assert_near(wr.model_scale(), 0.595, 0.01, "the whelp at its record's 3.5 m")
	var mr := m.rig as BruteRig
	assert_true(mr.gear_mesh() != null and str(mr.gear_mesh().name) == "troll_matriarch_gear", "the Matriarch's gear")
	var head := mr.skeleton().global_transform * mr.skeleton().get_bone_global_pose(mr.skeleton().find_bone("head")).origin
	assert_true(head.y > 6.5 and head.y < 9.2, "the Matriarch's head at her 9 m (%.2f)" % head.y)
	assert_true(not (k.get_node("Visual/LodProxy") as MeshInstance3D).visible and
		(k.get_node("Visual/LodProxy") as MeshInstance3D).mesh == kr.far_mesh().mesh, "the dormant stand-in is the far mesh")


func test_the_attacks_play_on_the_brains_clock() -> void:
	PersonRig.enable_for_tests()
	var o := _brute(OGRE, Vector3(0, 0.05, 0), "test.brute_attacks")
	await step_ticks(3)
	var rig := o.rig as BruteRig
	var sk := rig.skeleton()
	var hand := sk.find_bone("hand_r")
	o.controller.request(&"attack", {"action_id": "ability.ogre_smash"})
	var top := 0.0
	var low := 99.0
	var clip_ok := true
	for i in 140:
		await step_ticks(1)
		var s := o.get_rig_state()
		if s.action == null:
			break
		clip_ok = clip_ok and rig.current_clip() == "slam"
		var y := (sk.global_transform * sk.get_bone_global_pose(hand).origin).y
		if int(s.phase) == ActionDef.Phase.WINDUP and float(s.phase_fraction) > 0.85:
			top = maxf(top, y)
		elif int(s.phase) == ActionDef.Phase.RECOVERY and float(s.phase_fraction) < 0.15:
			low = minf(low, y)
	assert_true(clip_ok, "the smash plays the slam")
	assert_true(top > 3.3, "the fists over the head as the windup ends (%.2f m)" % top)
	assert_true(low < 1.4, "down in front as it strikes (%.2f m)" % low)
	await step_ticks(30)
	o.controller.request(&"attack", {"action_id": "ability.ogre_sweep"})
	var weight := 0.0
	for i in 50:
		await step_ticks(1)
		weight = maxf(weight, float(rig.arm_weights().arm))
	assert_eq(rig.current_clip(), "brace", "the sweep from the brace's stance")
	assert_true(weight > 0.99, "the arms on the brain's poses")


func test_walking_a_planted_foot_does_not_slide_and_the_slots_hold() -> void:
	PersonRig.enable_for_tests()
	var o := _brute(OGRE, Vector3(0, 0.05, 0), "test.brute_walk")
	await step_ticks(3)
	var rig := o.rig as BruteRig
	var sk := rig.skeleton()
	o.process_mode = Node.PROCESS_MODE_DISABLED   # carried: the rig reads the actor's speed
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	var balls := [sk.find_bone("ball_l"), sk.find_bone("ball_r")]
	var last := {}
	var worst := 0.0
	var planted := 0
	for i in 120:
		o.velocity = Vector3(0, 0, -2.2)
		o.position.z -= 2.2 / 60.0
		await step_ticks(1)
		for b: int in balls:
			var p := sk.global_transform * sk.get_bone_global_pose(b).origin
			if i > 20 and p.y < 0.05 and last.has(b) and (last[b] as Vector3).y < 0.05:
				worst = maxf(worst, Vector2(p.x - last[b].x, p.z - last[b].z).length())
				planted += 1
			last[b] = p
	assert_eq(rig.current_clip(), "walk", "walking: the walk")
	assert_true(planted > 20, "feet planted on the way (%d)" % planted)
	assert_true(worst < 0.02, "a planted foot moves at most 2 cm a frame (the body moves 3.7) (%.3f m)" % worst)
	o.process_mode = Node.PROCESS_MODE_INHERIT
	CreatureSlots.set_cap(1)
	var o2 := _brute(OGRE, o.position + Vector3(30, 0, 0), "test.brute_waits")
	await step_ticks(4)
	var r2 := o2.rig as BruteRig
	assert_true(rig.has_slot() != r2.has_slot(), "one slot for two ogres")
	var waiting := r2 if not r2.has_slot() else rig
	assert_true(waiting.far_mesh().is_visible_in_tree() and not waiting.model().is_visible_in_tree(),
		"the one without a slot shows its far mesh")
	var holder := rig if waiting == r2 else r2
	holder.get_parent().queue_free()
	await step_ticks(4)
	assert_true(waiting.has_slot() and waiting.model().is_visible_in_tree(), "the slot freed, it is skinned")
