extends IntegrationSuite
## The skinned rig in motion (P43; plan M10 §2.9 step 2, the motion half of §3.3's test_skinned_rig, kept
## out of the default tier for its 0.6 s cap: docs/systems/P43.md). With the skinned layers on:
##   * a 5 s walk: the brain's footfalls are the rig's (footfall audio stays on the brain: one per half
##     cycle of its walk phase, as the stylized rig counted them), and on every footfall a foot of the
##     clips is planted, the clip's time set from the brain's phase; never a frozen stride;
##   * a dodge, a stagger and a knockback: the legs hold the stance (every leg bone within 2 degrees of the
##     idle's legs), never a walk;
##   * Shoulder Charge: the run clip on the skin's own clock while the dash moves the giant;
##   * a jump: the airborne pose past half within three frames of leaving the ground;
##   * death: the walk and the idle stop, the death clip follows the fall (the pelvis sinks), and the
##     corpse does not breathe;
##   * a heavy at stage 4 measured in `posed` (tip matching's contract);
##   * a hold: the visible palm within 0.33 x k of the socket, the held body's Visual moved by the gap and
##     put back when the held body dies;
##   * every family's lights and heavy at stages 1 and 3: the wrist bends at most 45 degrees and the elbow
##     stays near its side of the body.

const LEG_BONES := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const STANCE_DEG := 2.0


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _grounded(stage := 1) -> GiantPlayer:
	SkinnedRig.enable_for_tests()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	if stage != 1:
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
	await step_ticks(3)
	return p


static func _rig(p: GiantPlayer) -> SkinnedRig:
	return p.get_node("Visual") as SkinnedRig


## The largest angle (degrees) between a leg bone's pose now and the idle clip's legs (the nearest of 24
## samples over the clip: the stance).
static func _stance_off_deg(rig: SkinnedRig) -> float:
	var sk := rig.skeleton()
	var idle := SkinnedRig.clip_library().get_animation("idle")
	var worst := 0.0
	for b: String in LEG_BONES:
		var i := sk.find_bone(b)
		var tr := idle.find_track(NodePath("Giant_rig/Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
		var now := sk.get_bone_pose_rotation(i)
		var best := INF
		for s in 24:
			var q: Quaternion = idle.rotation_track_interpolate(tr, idle.length * float(s) / 24.0) if tr >= 0 \
				else sk.get_bone_rest(i).basis.get_rotation_quaternion()
			best = minf(best, rad_to_deg(now.angle_to(q)))
		worst = maxf(worst, best)
	return worst


## The lower ankle's height above the giant's feet (metres).
static func _lower_ankle(p: GiantPlayer, rig: SkinnedRig) -> float:
	var sk := rig.skeleton()
	var y := INF
	for b in ["foot_l", "foot_r"]:
		y = minf(y, (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin).y)
	return y - p.global_position.y


func test_a_walk_steps_on_the_brains_footfalls() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var k := rig.body_scale
	var rest_ankle := float((rig.model().landmarks().get("ankle_l", Vector3(0, 0.16, 0)) as Vector3).y) * k
	var heard := [0]
	var strikes: Array[float] = []
	var pending := [false]
	rig.footfall.connect(func() -> void:
		heard[0] += 1
		pending[0] = true)
	var on_posed := func() -> void:
		if pending[0]:
			pending[0] = false
			strikes.append(_lower_ankle(p, rig))
	rig.posed.connect(on_posed)
	var phase0 := rig.walk_phase()
	var walking_frames := 0
	p.router.set_injected_move(Vector2(0, 1))
	for i in 300:
		await step_ticks(1)
		if rig.legs_source() == "walking":
			walking_frames += 1
	p.router.set_injected_move(Vector2.ZERO)
	rig.posed.disconnect(on_posed)
	var steps := int(floor(rig.walk_phase() / PI)) - int(floor(phase0 / PI))
	assert_true(heard[0] >= 8, "the giant walked (%d footfalls in 5 s)" % heard[0])
	assert_true(absi(heard[0] - steps) <= 1, "the footfalls are the brain's, one per half cycle of its phase (%d vs %d)" % [heard[0], steps])
	assert_true(walking_frames >= 280, "the legs walked (%d of 300 frames)" % walking_frames)
	var worst := 0.0
	for h in strikes:
		worst = maxf(worst, h)
	assert_true(strikes.size() >= heard[0] - 1, "every footfall measured (%d)" % strikes.size())
	assert_true(worst <= rest_ankle + 0.12 * k, "on every footfall a foot is down (lower ankle at most %.2f m, standing %.2f m)" % [
		worst, rest_ankle])


func test_dodge_stagger_and_knockback_hold_the_stance() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	await step_ticks(20)
	assert_true(_stance_off_deg(rig) <= STANCE_DEG, "standing: the stance (%.2f deg)" % _stance_off_deg(rig))
	for what: String in ["dodge", "stagger", "knockback"]:
		await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
		await step_ticks(30)
		match what:
			"dodge":
				p.router.set_injected_move(Vector2(1, 0))
				p.router.inject_edge(&"dodge")
			"stagger":
				p.entity.stagger(1.0, "test")
			"knockback":
				p.apply_knockback(Vector3.BACK, 10.0)
		var frames := 0
		var worst := 0.0
		var sources := {}
		for i in 24:
			await step_ticks(1)
			if what == "dodge":
				p.router.set_injected_move(Vector2.ZERO)
			var moving := Vector2(p.velocity.x, p.velocity.z).length() > 0.3
			if moving or p.controller.state != CombatController.State.LOCOMOTION:
				frames += 1
				sources[rig.legs_source()] = true
				worst = maxf(worst, _stance_off_deg(rig))
		assert_true(frames >= 6, "%s: it ran (%d frames)" % [what, frames])
		assert_eq(sources.keys(), ["stance"], "%s: the legs' source is the stance" % what)
		assert_true(worst <= STANCE_DEG, "%s: every leg bone within %.0f degrees of the stance (worst %.2f)" % [what, STANCE_DEG, worst])


func test_shoulder_charge_runs_on_the_skins_clock() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	p.set_loadout_slot("slot_3", "ability.shoulder_charge")
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	var clock0 := float(rig.get("_charge_phase"))
	p.router.inject_edge(&"slot_3")
	var motion_frames := 0
	var weight := 0.0
	for i in 90:
		await step_ticks(1)
		if rig.legs_source() == "motion":
			motion_frames += 1
			weight = maxf(weight, float(rig.blend_weights().charge))
	assert_true(motion_frames >= 10, "the dash's frames run the legs on the charge (%d)" % motion_frames)
	assert_true(weight > 0.9, "the run clip takes the legs (%.2f)" % weight)
	var advanced := float(rig.get("_charge_phase")) - clock0
	assert_true(advanced > PI, "the run clip advanced on its own clock (%.2f rad)" % advanced)


func test_a_jump_shows_the_airborne_pose_within_three_frames() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	p.router.inject_edge(&"jump")
	var left := -1
	var shown := -1
	for i in 40:
		await step_ticks(1)
		if left < 0 and not p.is_on_floor():
			left = i
		if left >= 0 and shown < 0 and float(rig.blend_weights().air) > 0.5:
			shown = i
	assert_true(left >= 0, "the giant left the ground")
	assert_true(shown >= 0 and shown - left <= 3, "the airborne pose shows within three frames (%d)" % (shown - left))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 120)
	await step_ticks(20)
	assert_true(float(rig.blend_weights().air) < 0.05, "and leaves on landing")


func test_death_stops_the_idle_and_follows_the_fall() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var sk := rig.skeleton()
	var pelvis := sk.find_bone("pelvis")
	var stand := sk.get_bone_global_pose(pelvis).origin
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, -2), 50000.0, PackedStringArray(["Melee", "Unblockable"]))
	await step_ticks(1)
	assert_eq(p.controller.state, CombatController.State.DEAD, "the giant died")
	var last_fall := -1.0
	var monotonic := true
	for i in 60:
		await step_ticks(1)
		var f := rig.fall_fraction()
		monotonic = monotonic and f >= last_fall - 1e-6
		last_fall = f
		assert_eq(rig.legs_source(), "dead", "dead")
	assert_true(monotonic and last_fall > 0.99, "the fall ran (%.2f)" % last_fall)
	var w := rig.blend_weights()
	assert_true(float(w.dead) > 0.99 and is_zero_approx(float(w.move)), "the death clip took over, the walk stopped (%s)" % w)
	var sunk := stand.distance_to(sk.get_bone_global_pose(pelvis).origin)
	assert_true(sunk > 0.2, "the death clip moved the body (the pelvis %.2f m from the stance)" % sunk)
	var a := []
	for i in sk.get_bone_count():
		a.append(sk.get_bone_pose(i))
	await step_ticks(45)
	var breathing := 0
	for i in sk.get_bone_count():
		if not sk.get_bone_pose(i).is_equal_approx(a[i]):
			breathing += 1
	assert_eq(breathing, 0, "the corpse does not breathe (bones still moving: %d)" % breathing)


func test_a_stage_4_heavy_is_tip_matched_in_posed() -> void:
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 6})   # full size at stage 4 (P42.md)
	var p := await _grounded(4)
	var rig := _rig(p)
	p.equipment.equip_weapon("weapon.club")
	await step_ticks(2)
	var samples: Array = []
	var on_posed := func() -> void:
		if p.controller.action != null and p.controller.action.hit_shape == "weapon_arc" \
				and p.controller.phase() == ActionDef.Phase.ACTIVE and float(rig.modifier().stats.get("arc", 0.0)) >= 0.999:
			samples.append([p.weapon_segment_global(p.controller.action, p.controller.active_fraction()),
				rig.visible_weapon_segment(), float(rig.modifier().stats.get("fist_error_m", 1.0))])
	rig.posed.connect(on_posed)
	p.router.inject_edge(&"heavy")
	await step_ticks(2)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 200)
	rig.posed.disconnect(on_posed)
	assert_true(samples.size() >= 3, "the ACTIVE frames were measured (%d)" % samples.size())
	var worst_out := 0.0
	var worst_deg := 0.0
	var worst_fist := 0.0
	for smp: Array in samples:
		var seg: PackedVector3Array = smp[0]
		var vis: Array = smp[1]
		for i in TipMatching.OUTER_HALF_SAMPLES:
			var t := 0.5 + 0.5 * float(i) / float(TipMatching.OUTER_HALF_SAMPLES - 1)
			var pt: Vector3 = (vis[0] as Vector3).lerp(vis[1], t)
			worst_out = maxf(worst_out, pt.distance_to(Geometry3D.get_closest_point_to_segment(pt, seg[0], seg[1])) - p.weapon_radius)
		worst_deg = maxf(worst_deg, rad_to_deg(((vis[1] as Vector3) - (vis[0] as Vector3)).angle_to(seg[1] - seg[0])))
		worst_fist = maxf(worst_fist, float(smp[2]))
	assert_true(worst_out <= 1e-3 * rig.body_scale, "stage 4: the visible weapon's outer half inside the tested capsule (worst %.3f m out)" % worst_out)
	assert_true(worst_deg <= TipMatching.MAX_ANGLE_DEG, "stage 4: at most %d degrees off (worst %.1f)" % [TipMatching.MAX_ANGLE_DEG, worst_deg])
	assert_true(worst_fist <= TipMatching.FIST_TOLERANCE_M * rig.body_scale, "stage 4: the fist on its target (worst %.4f m)" % worst_fist)


func test_a_held_body_shows_in_the_palm_and_is_put_back_when_it_dies() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var s := spawn_soldier(Vector3(0, 0.05, -3.0), PI, "test.held_dies")
	await step_ticks(1)
	var visual := s.get_node("Visual") as Node3D
	var base := visual.position
	s.entity.stagger(3.0, "test")
	p.grab.hold_timeout_s = 60.0
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "grab")
	assert_true(await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40), "holding")
	await step_ticks(20)
	var socket := p.to_global(p.grab.socket_local())
	var palm := rig.palm_global(true)
	assert_true(palm.distance_to(socket) <= PoseBrainModifier.HELD_GAP_MAX * rig.body_scale,
		"the visible palm within 0.33 x k of the socket (%.3f m)" % palm.distance_to(socket))
	assert_false(visual.position.is_equal_approx(base), "the held body's Visual moved toward the palm")
	queue_hit("tester", "test.held_dies", p.global_position, 50000.0, PackedStringArray(["Melee", "Unblockable"]))
	await step_ticks(3)
	assert_false(p.grab.is_holding(), "the death ended the hold")
	assert_true(not is_instance_valid(visual) or visual.position.is_equal_approx(base), "the Visual is back where it was")


## The animation brief's limits on the weapon arm (plan §3.3 design 3): over every family's light chain and
## heavy at stages 1 and 3, the wrist bends at most PoseBrainModifier.MAX_WRIST_DEG (the arm is solved again
## with the hand turned toward the forearm; the fist stays on its target) and the elbow does not swing more
## than 0.15 m (x k) across the body's middle on the cross-body arcs.
func test_the_weapon_arm_keeps_its_wrist_and_elbow_on_every_family() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var sk := rig.skeleton()
	var lower := sk.find_bone("lowerarm_r")
	for st in [1, 3]:
		if st != 1:
			assert_true(p.growth.debug_set_stage(st).ok, "stage %d" % st)
			await step_ticks(5)
		var ids := ["weapon.club", "weapon.sword", "weapon.hammer", "weapon.axe"]
		if st == 3:
			ids.append("weapon.tree_oak")
		for id: String in ids:
			assert_true(bool(p.equipment.grant_weapon(id, true).get("ok", false)), "stage %d: %s equipped" % [st, id])
			await step_ticks(3)
			var worst := {"wrist": 0.0, "fist": 0.0, "elbow": -INF, "frames": 0}
			var cb := func() -> void:
				var stats: Dictionary = rig.modifier().stats
				worst.frames = int(worst.frames) + 1
				worst.wrist = maxf(float(worst.wrist), float(stats.get("wrist_deg", 0.0)))
				worst.fist = maxf(float(worst.fist), float(stats.get("fist_error_m", 0.0)))
				worst.elbow = maxf(float(worst.elbow), -rig.modifier()._to_body(sk.get_bone_global_pose(lower).origin).x)
			rig.posed.connect(cb)
			for i in 3:
				p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
				p.router.inject_light_attack()
				await step_ticks(30)
			await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
			p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
			p.router.inject_edge(&"heavy")
			await step_ticks(3)
			await TestWait.until(self, func() -> bool: return p.controller.action == null, 200)
			rig.posed.disconnect(cb)
			var what := "stage %d %s" % [st, id]
			assert_true(int(worst.frames) > 100, "%s: measured (%d frames)" % [what, int(worst.frames)])
			assert_true(float(worst.wrist) <= PoseBrainModifier.MAX_WRIST_DEG + 0.5, "%s: the wrist bends at most 45 degrees (%.1f)" % [what, float(worst.wrist)])
			assert_true(float(worst.fist) <= TipMatching.FIST_TOLERANCE_M * rig.body_scale, "%s: the fist on its target (%.4f m)" % [what, float(worst.fist)])
			assert_true(float(worst.elbow) <= 0.15, "%s: the elbow at most 0.15 m across the middle (%.2f)" % [what, float(worst.elbow)])
