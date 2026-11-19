extends IntegrationSuite
## The giant's motion (P50; plan M11 §3.3 items 1-7, its tests). Slow tier: the motion runs a few hundred frames
## a check. With the skinned layers on, headless:
##   * each of the legs' sources is chosen for its state and no other - walking (and the sprint's clip above
##     SPRINT_FROM of the sprint's speed), turning on the spot (only while the brain does not walk), airborne and
##     landing, the stomp, the roar, Shoulder Charge's motion, bracing on a block, the stance - and no bone's
##     rotation changes by more than 25 degrees between two posed frames through all of them (outside a
##     teleport); the arms and hands, which the brain's generic mapping places, by no more than ARM_POP_DEG (Gate A:
##     PoseBrainModifier holds an arm bone to 20 degrees a frame outside a tested swing; it was 81.1 on a block's
##     release at the W30 merge, 65.4 at wave-29);
##   * the stomp's right foot leaves the ground in the windup and is planted as the ACTIVE phase starts (the
##     pulse), the left foot never lifts;
##   * a hit flinches the upper body from its side, and never during an attack's ACTIVE phase;
##   * in every generic pose (idle, the stomp, the roar, a self buff, first person at rest) the handle's line
##     passes within 0.02 x k of the fist's centre and the open off hand keeps its fingers in line with the
##     forearm (no droop);
##   * the reach past a weapon's fit stage in play: an unreforged club's lights and heavy at stage 6 - every ACTIVE
##     frame's visible outer half within one capsule radius of the tested segment and at most 15 degrees off it;
##   * the secondary motion: the cape and braids swing on a sprint and rest within 1.5 s of the stop, and stay
##     within their limits through a full head turn and a heavy swing (test_secondary_motion's motion half).
## Plus, rendered (a child Godot under Xvfb, skipped with a note without xvfb-run): the capture tour's stomp and
## turn beats from the side draw the giant with no shader error.

const POP_DEG := 25.0
## The arms' worst change between two frames (Gate A: 20.0 measured; PoseBrainModifier.ARM_STEP_DEG_S at 60 fps).
const ARM_POP_DEG := 22.0
const HANDLE_MAX := 0.02
const DROOP_MAX_DEG := 40.0
const SecondarySuite := preload("res://tests/integration/test_secondary_motion.gd")
const SETTLE_S := 1.5
const SETTLE_DEG := 2.0


func _grounded(stage := 1) -> GiantPlayer:
	SkinnedRig.enable_for_tests()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	if stage != 1:
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
	await step_ticks(30)
	return p


static func _rig(p: GiantPlayer) -> SkinnedRig:
	return p.get_node("Visual") as SkinnedRig


func _cast(p: GiantPlayer, id: String) -> void:
	p.set_loadout_slot("slot_3", id)
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	p.controller.cooldowns.clear()
	p.router.inject_edge(&"slot_3")


## Runs `frames` ticks recording each posed frame's legs' source and the largest bone rotation change.
class Watch:
	var rig: SkinnedRig
	var sources := {}
	var pop := 0.0
	var pop_where := ""
	var arm_pop := 0.0
	var arm_where := ""
	var arms := {}
	var prev: Array = []
	var teleports := 0
	var label := ""

	func _init(r: SkinnedRig) -> void:
		rig = r
		teleports = r.teleports
		r.posed.connect(_on_posed)
		var sk := r.skeleton()
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			for part: String in ["clavicle_", "upperarm_", "lowerarm_", "hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"]:
				if n.begins_with(part):
					arms[i] = true

	func stop() -> void:
		rig.posed.disconnect(_on_posed)

	func _on_posed() -> void:
		sources[rig.legs_source()] = int(sources.get(rig.legs_source(), 0)) + 1
		var sk := rig.skeleton()
		var now: Array = []
		for i in sk.get_bone_count():
			now.append(sk.get_bone_pose_rotation(i))
		if not prev.is_empty() and rig.teleports == teleports:
			for i in now.size():
				var d := rad_to_deg((prev[i] as Quaternion).angle_to(now[i]))
				if arms.has(i):
					if d > arm_pop:
						arm_pop = d
						arm_where = "%s in %s (%s)" % [sk.get_bone_name(i), rig.legs_source(), label]
				elif d > pop:
					pop = d
					pop_where = "%s in %s (%s)" % [sk.get_bone_name(i), rig.legs_source(), label]
		teleports = rig.teleports
		prev = now


func test_each_source_for_its_state_without_a_pop() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var w := Watch.new(rig)
	var seen := {}
	var note := func(what: String) -> void: seen[what] = rig.legs_source()
	# walking, then the sprint
	w.label = "walk"
	p.router.set_injected_move(Vector2(0, 1))
	await step_ticks(60)
	note.call("walk")
	var gait_walk := rig.blend_weights()
	p.router.set_injected_hold(&"sprint", true)
	await step_ticks(60)
	note.call("sprint")
	var gait_sprint := rig.blend_weights()
	p.router.set_injected_hold(&"sprint", false)
	p.router.set_injected_move(Vector2.ZERO)
	await step_ticks(40)
	note.call("stand")
	# turning on the spot: only while the brain does not walk
	w.label = "turn"
	var turned := {}
	for i in 60:
		p.facing_yaw = wrapf(p.facing_yaw + deg_to_rad(150.0) / 60.0, -PI, PI)
		await step_ticks(1)
		turned[rig.legs_source()] = true
	note.call("turn")
	var walk_turns := {}
	p.router.set_injected_move(Vector2(1, 0))
	for i in 40:
		await step_ticks(1)
		if rig.is_walking():
			walk_turns[rig.legs_source()] = true
	p.router.set_injected_move(Vector2.ZERO)
	await step_ticks(40)
	# a jump and its landing
	w.label = "jump"
	var air := {}
	p.router.inject_edge(&"jump")
	for i in 120:
		await step_ticks(1)
		air[rig.legs_source()] = true
	# a block
	w.label = "block"
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(30)
	note.call("block")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")
	await step_ticks(30)
	# the roar and Shoulder Charge
	w.label = "roar"
	_cast(p, "ability.thunder_roar")
	await step_ticks(20)
	note.call("roar")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
	await step_ticks(20)
	var charge := {}
	w.label = "charge"
	_cast(p, "ability.shoulder_charge")
	for i in 60:
		await step_ticks(1)
		charge[rig.legs_source()] = true
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
	await step_ticks(30)
	w.stop()
	assert_eq(seen.walk, "walking", "walking")
	assert_true(float(gait_walk.sprint) < 0.05, "a walk shows no sprint (%.2f)" % float(gait_walk.sprint))
	assert_eq(seen.sprint, "walking", "the sprint is walking's")
	assert_true(float(gait_sprint.sprint) > 0.9, "with the sprint clip (%.2f)" % float(gait_sprint.sprint))
	assert_eq(seen.stand, "stance", "standing")
	assert_true(turned.has("turning"), "turning on the spot steps (%s)" % [turned.keys()])
	assert_false(walk_turns.has("turning"), "never while the brain walks (%s)" % [walk_turns.keys()])
	assert_true(air.has("airborne") and air.has("landing"), "a jump: airborne, then the landing (%s)" % [air.keys()])
	assert_eq(seen.block, "bracing", "a block braces")
	assert_eq(seen.roar, "roar", "the roar")
	assert_true(charge.has("motion"), "Shoulder Charge runs on its motion (%s)" % [charge.keys()])
	print("    test_giant_motion_render: the sources %s; the largest change between two frames %.1f deg (%s); the arms (the brain's, M10's mapping) %.1f deg (%s)" % [
		w.sources, w.pop, w.pop_where, w.arm_pop, w.arm_where])
	assert_true(w.pop <= POP_DEG, "no bone turns more than %.0f degrees between two frames (worst %.1f: %s)" % [POP_DEG, w.pop, w.pop_where])
	assert_true(w.arm_pop <= ARM_POP_DEG, "no arm bone turns more than %.0f degrees between two frames (worst %.1f: %s)" % [
		ARM_POP_DEG, w.arm_pop, w.arm_where])


func test_the_stomp_lifts_and_plants_on_the_pulse() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var sk := rig.skeleton()
	var fr := sk.find_bone("foot_r")
	var fl := sk.find_bone("foot_l")
	var y := func(b: int) -> float: return (sk.global_transform * sk.get_bone_global_pose(b).origin).y - p.global_position.y
	var rest := [INF, INF]
	var rest_cb := func() -> void:
		if rest[0] == INF:
			rest[0] = y.call(fr)
			rest[1] = y.call(fl)
	rig.posed.connect(rest_cb)
	await step_ticks(2)
	rig.posed.disconnect(rest_cb)
	var trace: Array = []
	var cb := func() -> void:
		trace.append([int(rig.rig_state().get("phase", 0)), y.call(fr) - float(rest[0]), y.call(fl) - float(rest[1]), rig.legs_source()])
	rig.posed.connect(cb)
	_cast(p, "ability.heavy_footfall")
	await step_ticks(2)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
	rig.posed.disconnect(cb)
	var lift := 0.0
	var left := 0.0
	var at_pulse := INF
	for t: Array in trace:
		if int(t[0]) == ActionDef.Phase.WINDUP:
			lift = maxf(lift, float(t[1]))
		if int(t[0]) == ActionDef.Phase.ACTIVE and at_pulse == INF:
			at_pulse = float(t[1])
		left = maxf(left, absf(float(t[2])))
	print("    test_giant_motion_render: the stomp lifts the right foot %.2f m, %.3f m above its rest as the pulse starts, the left foot moves %.3f m" % [
		lift, at_pulse, left])
	assert_true(lift >= 0.5, "the windup lifts the right foot (%.2f m)" % lift)
	assert_true(at_pulse <= 0.06, "it is planted as the ACTIVE phase starts (%.3f m above its rest)" % at_pulse)
	assert_true(left <= 0.05, "the left foot stays down (%.3f m)" % left)


func test_flinches_from_the_hits_side_never_in_an_active_window() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	for side: Array in [["f", Vector3(0, 0, -3)], ["b", Vector3(0, 0, 3)], ["l", Vector3(-3, 0, 0)], ["r", Vector3(3, 0, 0)]]:
		assert_eq(SkinnedRig.flinch_side(side[1]), side[0], "a hit from %s flinches %s" % [side[1], side[0]])
		rig.flinch(side[1], 0.9)
		await step_ticks(6)
		assert_true(float(rig.flinch_weights().get(side[0], 0.0)) > 0.5, "the %s flinch plays (%s)" % [side[0], rig.flinch_weights()])
		await step_ticks(20)
	assert_true(rig.flinch_weights().is_empty(), "and ends")
	# a real hit through HitFeedback
	var fb := HitFeedback.new()
	world.add_child(fb)
	var before := rig.flinches
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "test"
	e.target_id = p.entity.entity_id
	e.power = 1.0
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Unblockable"])
	e.attacker_position = p.global_transform * Vector3(-4, 0, 0)
	Sim.queue_hit(e)
	await step_ticks(3)
	assert_eq(rig.flinches, before + 1, "a hit resolved flinches the giant (HitFeedback)")
	fb.queue_free()
	# never during an attack's ACTIVE phase
	var refused := rig.flinches_refused
	var during := {"frames": 0, "weight": 0.0}
	var cb := func() -> void:
		var a := p.controller.action
		if a != null and a.is_attack() and p.controller.phase() == ActionDef.Phase.ACTIVE:
			during.frames = int(during.frames) + 1
			for v: float in rig.flinch_weights().values():
				during.weight = maxf(float(during.weight), v)
			rig.flinch(Vector3(0, 0, -3), 0.9)
	rig.posed.connect(cb)
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"heavy")
	await step_ticks(3)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 200)
	rig.posed.disconnect(cb)
	assert_true(int(during.frames) > 3, "the heavy's ACTIVE frames were watched (%d)" % int(during.frames))
	assert_true(rig.flinches_refused > refused, "a flinch asked for in them is refused")
	assert_true(float(during.weight) < 0.05, "and none shows (%.3f)" % float(during.weight))


## The handle's line (the socket and its -Z) to the fist's centre, in stage-1 metres; the off hand's droop (the
## middle finger's line against the forearm's, degrees).
static func _grip_measures(p: GiantPlayer, rig: SkinnedRig) -> Array:
	var f := rig.modifier().fist("r")
	var socket := rig.weapon_socket()
	var centre := rig.body.global_transform * (f.centre as Vector3)
	var a := socket.global_position
	var off := centre.distance_to(Geometry3D.get_closest_point_to_segment_uncapped(centre, a, a - socket.global_transform.basis.z)) / rig.body_scale
	var sk := rig.skeleton()
	var gp := func(n: String) -> Vector3: return sk.get_bone_global_pose(sk.find_bone(n)).origin
	var fore: Vector3 = gp.call("hand_l") - gp.call("lowerarm_l")
	var finger: Vector3 = gp.call("middle_03_l") - gp.call("middle_01_l")
	return [off, rad_to_deg(fore.angle_to(finger))]


func test_the_handle_passes_through_the_fist_in_every_generic_pose() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	var worst := {"handle": 0.0, "droop": 0.0, "frames": 0, "axis": 0.0}
	var cb := func() -> void:
		var m := _grip_measures(p, rig)
		worst.handle = maxf(float(worst.handle), float(m[0]))
		worst.axis = maxf(float(worst.axis), float(rig.modifier().stats.get("grip_axis_deg", 0.0)))
		if float(rig.modifier().stats.get("off_w", 0.0)) > 0.99:
			worst.droop = maxf(float(worst.droop), float(m[1]))
		worst.frames = int(worst.frames) + 1
	rig.posed.connect(cb)
	await step_ticks(20)
	for id: String in ["ability.heavy_footfall", "ability.thunder_roar", "ability.stone_skin"]:
		_cast(p, id)
		await step_ticks(2)
		await TestWait.until(self, func() -> bool: return p.controller.action == null, 150)
		await step_ticks(10)
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
	await step_ticks(40)
	assert_true(float(rig.modifier().stats.get("fp", 0.0)) > 0.99, "first person at rest takes fp_rest's arms")
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)
	rig.posed.disconnect(cb)
	print("    test_giant_motion_render: the generic poses - the handle within %.4f x k of the fist's centre, the fist's axis at most %.1f deg off the handle, the off hand's fingers at most %.1f deg off its forearm (%d frames)" % [
		float(worst.handle), float(worst.axis), float(worst.droop), int(worst.frames)])
	assert_true(int(worst.frames) > 200, "measured (%d frames)" % int(worst.frames))
	assert_true(float(worst.handle) <= HANDLE_MAX, "the handle's line within %.2f x k of the fist's centre (%.4f)" % [HANDLE_MAX, float(worst.handle)])
	assert_true(float(worst.droop) <= DROOP_MAX_DEG, "the off hand does not droop (%.1f deg)" % float(worst.droop))
	assert_eq(rig.grip_clip(), "grip_club", "the club's family grip closes the fist")
	assert_true(bool(p.equipment.grant_weapon("weapon.sword", true).get("ok", false)), "a sword")
	await step_ticks(2)
	assert_eq(rig.grip_clip(), "grip_sword", "and its own grip")


func test_a_weapon_past_its_fit_stage_reaches_in_play() -> void:
	var p := await _grounded(6)
	var rig := _rig(p)
	assert_true(bool(p.equipment.grant_weapon("weapon.club", true).get("ok", false)), "the unreforged club at stage 6")
	await step_ticks(3)
	var worst := {"dev": 0.0, "deg": 0.0, "n": 0, "ext": 0.0}
	var cb := func() -> void:
		var a := p.controller.action
		if a == null or a.hit_shape != "weapon_arc" or p.controller.phase() != ActionDef.Phase.ACTIVE \
				or float(rig.modifier().stats.get("arc", 0.0)) < 0.999:
			return
		var seg := p.weapon_segment_global(a, p.controller.active_fraction())
		var vis := rig.visible_weapon_segment()
		for i in TipMatching.OUTER_HALF_SAMPLES:
			var t := 0.5 + 0.5 * float(i) / float(TipMatching.OUTER_HALF_SAMPLES - 1)
			var pt: Vector3 = (vis[0] as Vector3).lerp(vis[1], t)
			worst.dev = maxf(float(worst.dev), pt.distance_to(Geometry3D.get_closest_point_to_segment(pt, seg[0], seg[1])) / p.weapon_radius)
		worst.deg = maxf(float(worst.deg), rad_to_deg(((vis[1] as Vector3) - (vis[0] as Vector3)).angle_to(seg[1] - seg[0])))
		var ext: Dictionary = rig.modifier().reach_ext
		worst.ext = maxf(float(worst.ext), float(ext.clavicle_m) + float(ext.pelvis_m) + float(ext.lean_deg) / 100.0)
		worst.n = int(worst.n) + 1
	rig.posed.connect(cb)
	for i in 3:
		p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
		p.router.inject_light_attack()
		await step_ticks(40)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 150)
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"heavy")
	await step_ticks(3)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 250)
	rig.posed.disconnect(cb)
	print("    test_giant_motion_render: an unreforged club at stage 6 - %d ACTIVE frames, the outer half within %.2f radii, %.1f deg off; the extension used (sum) %.3f" % [
		int(worst.n), float(worst.dev), float(worst.deg), float(worst.ext)])
	assert_true(int(worst.n) > 10, "the swings were measured (%d frames)" % int(worst.n))
	assert_true(float(worst.dev) <= 1.0 + 1e-3, "the outer half within one capsule radius (%.2f radii)" % float(worst.dev))
	assert_true(float(worst.deg) <= TipMatching.MAX_ANGLE_DEG + 0.5, "at most 15 degrees off (%.1f)" % float(worst.deg))


func _long_look() -> GiantPlayer:
	var p := await _grounded()
	SecondarySuite._wear(p, SecondarySuite.LONG_LOOK)
	await step_ticks(2)
	return p


## Turns the head about the skeleton's up axis before the springs run (a test's stand-in for a look round).
class HeadTurn extends SkeletonModifier3D:
	var deg := 0.0

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		var i := sk.find_bone("head")
		if i < 0 or absf(deg) < 1e-3:
			return
		var g := sk.get_bone_global_pose(i)
		g.basis = Basis(Vector3.UP, deg_to_rad(deg)) * g.basis
		sk.set_bone_global_pose(i, g)


## The largest change (degrees) of any running joint's angle between two samples of joint_angles().
static func _moved(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for bone: String in a:
		if b.has(bone):
			worst = maxf(worst, absf(float(a[bone][0]) - float(b[bone][0])))
	return worst


func test_the_chains_swing_on_a_run_and_rest_within_one_and_a_half_seconds() -> void:
	var p := await _long_look()
	var rig := _rig(p)
	var sm := rig.secondary()
	await step_ticks(30)
	var rest := sm.joint_angles()
	var lift := {"cape": 0.0, "hair": 0.0}
	p.router.set_injected_move(Vector2(0, 1))
	p.router.set_injected_hold(&"sprint", true)
	var on_posed := func() -> void:
		var now := sm.joint_angles()
		lift.cape = maxf(float(lift.cape), float(now.get("cape_c_01", [0.0])[0]))
		lift.hair = maxf(float(lift.hair), maxf(float(now.get("hair_01", [0.0])[0]), float(now.get("hair_l_01", [0.0])[0])))
	rig.posed.connect(on_posed)
	await step_ticks(90)
	rig.posed.disconnect(on_posed)
	p.router.set_injected_move(Vector2.ZERO)
	p.router.set_injected_hold(&"sprint", false)
	assert_true(float(lift.cape) > 8.0, "the sprint lifts the cape (%.1f deg at its root)" % float(lift.cape))
	assert_true(float(lift.hair) > 3.0, "and swings the braids (%.1f deg)" % float(lift.hair))
	# the stop: sample every frame for 3 s; the chains rest by SETTLE_S
	var samples: Array = []
	var stopped := [-1]
	var take := func() -> void:
		if stopped[0] < 0 and Vector2(p.velocity.x, p.velocity.z).length() < 0.05:
			stopped[0] = samples.size()
		samples.append(sm.joint_angles())
	rig.posed.connect(take)
	await step_ticks(180)
	rig.posed.disconnect(take)
	# where each joint rests: its mean over the last second (the idle's breathing still sways it by about a
	# degree and a half either way, which is the rest it comes to)
	var last := {}
	var tail := samples.slice(samples.size() - Sim.TICK_RATE)
	for bone: String in samples.back():
		var sum := 0.0
		for smp: Dictionary in tail:
			sum += float(smp[bone][0])
		last[bone] = [sum / float(tail.size())]
	var settled_at := 0
	var late := ""
	for i in samples.size():
		if _moved(samples[i], last) > SETTLE_DEG:
			settled_at = i + 1
			for bone: String in samples[i]:
				if absf(float(samples[i][bone][0]) - float(last[bone][0])) > SETTLE_DEG:
					late = bone
	var settle_s := float(settled_at - maxi(stopped[0], 0)) / float(Sim.TICK_RATE)
	print("    test_secondary_motion: the sprint lifts the cape %.1f deg and the braids %.1f deg; rest %.2f s after the stop (last %s; the giant stood still %d frames after the release)" % [
		float(lift.cape), float(lift.hair), settle_s, late, stopped[0]])
	assert_true(settle_s <= SETTLE_S, "every joint within %.0f degrees of its rest %.2f s after the stop (at most %.1f s)" % [
		SETTLE_DEG, settle_s, SETTLE_S])
	assert_true(_moved(rest, last) < 6.0, "and back near the standing rest (%.1f deg)" % _moved(rest, last))


func test_the_limits_hold_through_a_full_head_turn_and_a_heavy_swing() -> void:
	var p := await _long_look()
	var rig := _rig(p)
	var sm := rig.secondary()
	var turn := HeadTurn.new()
	rig.skeleton().add_child(turn)
	rig.skeleton().move_child(turn, sm.springs.get_index())
	var limits := sm.joint_limits()
	var worst := {"over": 0.0, "front": 0.0, "frames": 0}
	var check := func() -> void:
		var a := sm.joint_angles()
		worst.frames = int(worst.frames) + 1
		for bone: String in a:
			worst.over = maxf(float(worst.over), float(a[bone][0]) - float(limits[bone]))
			if bone.begins_with("cape"):
				worst.front = maxf(float(worst.front), float(a[bone][1]))
	rig.posed.connect(check)
	for i in 40:
		turn.deg = 70.0 * sin(float(i) / 40.0 * PI)
		await step_ticks(1)
	turn.deg = 0.0
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"heavy")
	await step_ticks(3)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 200)
	rig.posed.disconnect(check)
	turn.queue_free()
	assert_true(int(worst.frames) > 60, "measured (%d frames)" % int(worst.frames))
	assert_true(float(worst.over) <= 0.5, "every joint within its chain's max_deg (worst %.2f deg over)" % float(worst.over))
	assert_true(float(worst.front) <= SecondaryMotion.CAPE_FRONT_DEG + 0.5, "the cape at most %.0f deg toward the legs (%.2f)" % [
		SecondaryMotion.CAPE_FRONT_DEG, float(worst.front)])
