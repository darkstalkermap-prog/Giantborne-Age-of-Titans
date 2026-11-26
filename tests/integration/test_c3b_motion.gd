extends IntegrationSuite
## C3b (decisions C3b-1, C3b-3, C3b-4) on the skinned giant: a planted foot does not slide while he walks (stages 1, 4,
## 6 and 8, at a quarter, a half and all of his speed); the stamp's foot comes down where its pulse strikes; the body
## leans forward as he sets off and back as he stops; a blow carries past its arc's end; a landed blow holds still for
## its hit-stop, longer for a bigger giant, and the bots' swings never do.


func before_each() -> void:
	SkinnedRig.enable_for_tests()
	await super()


func after_each() -> void:
	await super()
	SkinnedRig.reset_for_tests()


func _rig(p: GiantPlayer) -> SkinnedRig:
	return p.rig as SkinnedRig


## The planted foot's slide along the walk (m/s, the mean over the frames each foot stands lowest) while he walks at
## `input` of his speed for two seconds, read on the rig's `posed` (the final bones).
func _slide(p: GiantPlayer, input: float) -> Dictionary:
	p.global_position = Vector3(0, 0.05, 0)
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, input))
	await step_ticks(90)
	var rig := _rig(p)
	var sk := rig.skeleton()
	var bi := {"l": sk.find_bone("foot_l"), "r": sk.find_bone("foot_r")}
	var samples := {"l": [], "r": []}
	var take := func() -> void:
		for side: String in ["l", "r"]:
			samples[side].append((sk.global_transform * sk.get_bone_global_pose(bi[side])).origin)
	rig.posed.connect(take)
	var v_sum := 0.0
	for i in 120:
		await get_tree().process_frame
		v_sum += Vector2(p.velocity.x, p.velocity.z).length()
	rig.posed.disconnect(take)
	p.router.set_injected_move(Vector2.ZERO)
	var h := float(p.profile.height_m)
	var worst := 0.0
	for side: String in ["l", "r"]:
		var arr: Array = samples[side]
		var low := INF
		for q: Vector3 in arr:
			low = minf(low, q.y)
		var sum := 0.0
		var n := 0
		for i in range(1, arr.size()):
			var a: Vector3 = arr[i - 1]
			var b: Vector3 = arr[i]
			if a.y < low + 0.015 * h and b.y < low + 0.015 * h:
				sum += Vector2(b.x - a.x, b.z - a.z).length() * 60.0
				n += 1
		worst = maxf(worst, sum / maxf(1.0, float(n)))
	await step_ticks(60)
	return {"slide": worst, "speed": v_sum / 120.0}


func test_a_planted_foot_does_not_slide() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true(_rig(p).layers_on(), "the skinned layers run")
	for stage in [1, 4, 6, 8]:
		TitanDuel.prepare(p, stage)
		await step_ticks(120)
		for input: float in [0.25, 0.5, 1.0]:
			var r := await _slide(p, input)
			print("    stage %d at %.2f of his speed (%.2f m/s): the planted foot slides %.2f m/s" % [stage, input, r.speed, r.slide])
			assert_true(float(r.slide) <= 0.05 * float(r.speed) + 0.03,
				"stage %d at %.2f: slide %.2f m/s within 5 %% of %.2f m/s" % [stage, input, r.slide, r.speed])


func test_the_stamp_comes_down_where_it_strikes() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	for stage in [6, 8]:
		TitanDuel.prepare(p, stage)
		await step_ticks(150)
		p.global_position = Vector3(0, 0.05, 0)
		p.facing_yaw = 0.0
		p.rotation.y = 0.0
		p.camera_rig.yaw = 0.0
		var cap := float(p.profile.capsule_radius_m)
		var man := spawn_soldier(Vector3(-0.2 * cap, 0.05, -(cap + 1.2)), PI, "c3b.stamped_%d" % stage)
		await step_ticks(10)
		p.camera_rig.pitch = deg_to_rad(-60.0)
		await step_ticks(30)   # (the soft target in front: the man at his toes)
		var plan := p.attack.next_swing_plan(false)
		assert_eq(str(plan.get("strike", "")), "stamp", "stage %d: the light stamps on the man at his toes" % stage)
		p.router.inject_edge(&"light")
		await TestWait.until(self, func() -> bool: return p.controller.action != null \
			and p.controller.phase() == ActionDef.Phase.ACTIVE, 60)
		assert_eq(p.controller.action_id(), PlayerAttack.LOW_LIGHT, "stage %d: the stamp runs" % stage)
		var st := p.attack.stamp_state()
		var sk := _rig(p).skeleton()
		var foot := sk.find_bone("foot_" + str(st.get("foot", "r")))
		var got := {"at": Vector3.INF}
		var take := func() -> void:
			got.at = (sk.global_transform * sk.get_bone_global_pose(foot)).origin
		_rig(p).posed.connect(take)
		await get_tree().process_frame
		await get_tree().process_frame
		_rig(p).posed.disconnect(take)
		var point: Vector3 = st.point
		var off := Vector2((got.at as Vector3).x - point.x, (got.at as Vector3).z - point.z).length()
		var radius := float(st.radius)
		print("    stage %d: the stamping foot (%s) lands %.2f m from the pulse's centre (radius %.2f m)" % [stage, st.foot, off, radius])
		assert_true(off <= radius, "stage %d: the foot lands inside the pulse (%.2f <= %.2f m)" % [stage, off, radius])
		await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
		assert_true(deaths.has(man.entity_id) or not hits_on(man.entity_id).is_empty(), "stage %d: and the man was struck" % stage)
		if is_instance_valid(man):
			man.queue_free()
		await step_ticks(30)


func test_the_body_leans_into_a_start_and_a_stop() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, 4)
	await step_ticks(120)
	var body := _rig(p).body
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, 1))
	var lean_go := 0.0
	for i in 12:
		await get_tree().process_frame
		lean_go = minf(lean_go, body.rotation.x)
	await step_ticks(90)
	p.router.set_injected_move(Vector2.ZERO)
	var lean_stop := 0.0
	for i in 12:
		await get_tree().process_frame
		lean_stop = maxf(lean_stop, body.rotation.x)
	await step_ticks(120)
	print("    setting off %.1f deg, stopping %.1f deg, at rest %.2f deg" % [rad_to_deg(lean_go), rad_to_deg(lean_stop), rad_to_deg(body.rotation.x)])
	assert_true(lean_go < deg_to_rad(-1.0), "he leans forward as he sets off")
	assert_true(lean_stop > deg_to_rad(1.0), "and back as he stops")
	assert_true(absf(body.rotation.x) < deg_to_rad(0.3), "and stands straight at rest")


func test_a_blow_carries_past_its_arc() -> void:
	var a := GameData.get_action("ability.light_1")
	var finish := Vector2(float(a.arc.yaw_end_deg), float(a.arc.pitch_end_deg))
	var idle := Vector2(12.0, -78.0)
	var early := AttackGeometry.pose_for(a, ActionDef.Phase.RECOVERY, AttackGeometry.FOLLOW_PEAK, idle)
	var way := finish - AttackGeometry.arc_point(a, 0.8)
	assert_true((early - finish.lerp(idle, smoothstep(0.0, 1.0, AttackGeometry.FOLLOW_PEAK))).dot(way) > 0.0,
		"early in the recovery the arm is carried on along the blow's way")
	assert_true(AttackGeometry.pose_for(a, ActionDef.Phase.RECOVERY, 1.0, idle).is_equal_approx(idle), "and settles at rest")
	assert_true(AttackGeometry.pose_for(a, ActionDef.Phase.RECOVERY, 0.0, idle).is_equal_approx(finish), "from the arc's end")


func test_a_landed_blow_holds_for_its_hit_stop() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var held := {}
	for stage in [1, 8]:
		TitanDuel.prepare(p, stage)
		await step_ticks(150)
		p.global_position = Vector3(0, 0.05, 0)
		p.facing_yaw = 0.0
		p.rotation.y = 0.0
		p.camera_rig.yaw = 0.0
		p.camera_rig.pitch = deg_to_rad(-20.0)
		var d := maxf(1.6, float(p.profile.melee_reach_m) * 0.6) if stage == 1 else float(p.profile.melee_reach_m) * 0.75
		var dummy := spawn_dummy(Vector3(0, 0.05, -d), "c3b.post_%d" % stage)
		await step_ticks(20)
		p.router.inject_edge(&"heavy")
		var most := 0
		for i in 120:
			await step_ticks(1)
			most = maxi(most, p.controller.hold_ticks)
			if p.controller.action == null and i > 10:
				break
		held[stage] = most + 1 if most > 0 else 0
		print("    stage %d: the heavy held %d ticks on landing (hit-stop %d)" % [stage, held[stage], p.attack.hitstop_ticks(GameData.get_action("ability.heavy_1"))])
		assert_false(hits_on(dummy.entity_id).is_empty(), "stage %d: the heavy landed" % stage)
		assert_true(int(held[stage]) > 0, "stage %d: and held" % stage)
		dummy.queue_free()
		await step_ticks(10)
	assert_true(int(held[8]) > int(held[1]), "a colossus's blow holds longer than a stage-1 giant's")
	assert_true(p.attack.hitstop_ticks(GameData.get_action("ability.heavy_1")) <= PlayerAttack.HITSTOP_MAX, "within its cap")
	# the bots' swings are never held (the duels were tuned without it)
	p.attack.bot_controls()
	p.global_position = Vector3(0, 0.05, 0)
	var post := spawn_dummy(Vector3(0, 0.05, -float(p.profile.melee_reach_m) * 0.75), "c3b.post_bot")
	await step_ticks(20)
	p.router.inject_edge(&"heavy")
	var bot_most := 0
	for i in 120:
		await step_ticks(1)
		bot_most = maxi(bot_most, p.controller.hold_ticks)
		if p.controller.action == null and i > 10:
			break
	assert_eq(bot_most, 0, "a bot's blow holds nothing")
	post.queue_free()
