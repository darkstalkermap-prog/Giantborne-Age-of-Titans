class_name PoseBrainModifier
extends SkeletonModifier3D
## The pose brain on the realistic skeleton (P43; plan M10 §2.9 step 3, decision 3). A run-time child of the
## model's Skeleton3D, created by SkinnedRig when the skinned layers are on (never saved). It runs after
## the AnimationTree has put the clips on the bones, in the skeleton's update, and moves only bones of its
## own skeleton and the rig's WeaponSocket (Visual/Body/WeaponSocket); it reads the brain (ActorRig's
## outputs this frame) and the actor's gameplay geometry, and writes nothing else (plan §2.7: the skin may
## read gameplay state, never the other way round).
##
##   1. the brain's torso twist, spread over spine_01..03 (each a third, about the skeleton's up axis);
##   2. the weapon arm: during a weapon arc by tip matching (TipMatching.match_swing_at from the shoulder
##      where the clips put it: the visible weapon aims from a grip the real arm reaches at the tested
##      segment's tip), otherwise by the generic mapping (the palm at shoulder + direction x 0.9 x reach,
##      the wrist straight, the weapon GRIP_AXIS_DEG off the hand toward the front - toward the sky for the
##      tree and the pine), blended over ARC_BLEND_S so the hand never jumps; the walk's arm swing is put
##      in phase with the clips' legs (the brain's swing peaks a quarter cycle after the heel strikes the
##      clips' time is set for);
##   3. the off arm: the clip's arm in plain locomotion; while an action, a block, a dodge or a pose
##      override (a grab) runs, the brain's off pose by the generic mapping; during a grab's hold the off
##      palm on the hand socket when in reach, else its farthest point toward it, and `held_gap` (the palm
##      minus the socket, at most HELD_GAP_MAX x k) for SkinnedRig to move the held body's visual by;
##   4. WeaponSocket in the fist along the weapon's direction (its local -Z), the weapon's own scale left
##      as PlayerEquipment sets it (effective_weapon_scale / k);
##   5. at death the arms go back to the death clip's (the drive fades with the brain's fall).
## P50 (plan M11 §2.3): the weapon hand is placed by its fist, not its knuckle line: the fist's centre (the
## index's `grip_local_r`, in the hand bone's own space) goes where tip matching or the generic mapping puts the
## grip, the hand turned so the handle's line through the fist (`grip_axis_r`) lies along the weapon, rolled
## about it so the wrist bends least and tilted off it only past MAX_WRIST_DEG; WeaponSocket sits on the fist's
## centre, so the handle passes through the closed fist in every pose. The off hand under the generic mapping
## keeps its wrist straight (the hand along the forearm: it never droops). In first person at rest the
## weapon arm fades to the clip's (`fp_rest`, the weapon in the fist's own line). A weapon carried past its fit
## stage reaches with the clavicle, the spine's lean and the pelvis (TipMatching.match_swing_reach; the feet
## kept where they stand by a two-bone solve of each leg).
## Gate A: outside a tested swing no arm bone (the upper arm, the forearm, the hand) turns faster than ARM_STEP_DEG_S
## in its parent's frame (_limit_arm: a block's press and release, an action's first frame, the off arm handed back
## to its clip; the weapon turns with the hand so the handle stays in the fist). Presentation only.
## P64c: two hands on a long haft (two_handed(): a rival giant's or Harrok's axe). The overhead chop (a line pulse with
## the weapon) is keyed on the action's own clock (CHOP_KEYS: raised over the head across the windup, brought down onto
## the line in the first part of the active phase and held there while the crack runs, the spine bent into it); a
## weapon arc's windup draws the axe back over the shoulder of the swing (ARC_KEYS, the backhand's mirrored), and its
## active phase keeps tip matching exactly (the tested swing); in every phase of both the off hand holds the haft
## TWO_HAND_GAP of its length above the weapon fist (two_w, its weight), and the blade's edge leads the stroke.
## Every arm is placed by an analytic two-bone solve (TipMatching.two_bone, the elbow toward
## TipMatching.pole_for) and set as whole frames: the upper arm and the forearm keep the rest arm's plane
## (the elbow bends about its own hinge), the hand's long axis (wrist to the knuckles) and its across axis
## (index to little finger) are set together. Everything is computed in Visual/Body space (stage-1 metres,
## the game frame: +X the giant's right, -Z his front), converted to the skeleton's space (the glTF is
## turned 180 degrees inside the model) when set.

const SPINE := ["spine_01", "spine_02", "spine_03"]
## The generic mapping: the palm at the shoulder + direction x this share of the palm's reach.
const GENERIC_REACH_USE := 0.9
## The most the held body's visual moves toward the palm (stage-1 metres; x k in the world).
const HELD_GAP_MAX := 0.33
## How fast the weapon arm crosses between the generic mapping and tip matching, and the off arm and the
## death's drive fade (1 / s of weight).
const ARC_BLEND_RATE := 12.0
const OFF_BLEND_RATE := 9.0
const DEATH_BLEND_RATE := 5.0
## The most a wrist bends (degrees between the forearm and the hand's long axis; the animation brief).
const MAX_WRIST_DEG := 45.0
## How many times the arm is solved again to bring a wrist bend under MAX_WRIST_DEG (the elbow moves with the
## wrist, so the forearm turns a little each time).
const WRIST_PASSES := 4
## The walk's arm swing (degrees at full swing), as the brain adds it (ActorRig._process).
const SWING_DEG := 16.0
## A hold beyond the arm's reach (the gameplay socket is the stylized arm's, 1.5·k out, about 0.33 m past
## the real palm's reach): the clavicle turns the shoulder toward it by up to this much, as a reaching
## shoulder protracts, and the arm reaches straight (TipMatching.SOLVE_MARGIN of the palm's reach).
const PROTRACT_MAX_DEG := 18.0
## How fast the weapon arm fades to the first-person rest clip (1 / s of weight).
const FP_BLEND_RATE := 8.0
## The knee's pole for the legs' solve (Body space: forward and a little down).
const KNEE_POLE := Vector3(0.0, -0.2, -1.0)
## The most the pelvis moves for a reach (stage-1 metres; TipMatching.REACH_PELVIS_M).
const REACH_PELVIS_MAX := TipMatching.REACH_PELVIS_M
## No reach extension (reach_ext's value outside a past-fit swing; read-only).
const REACH_NONE := {"clavicle_m": 0.0, "lean_deg": 0.0, "pelvis_m": 0.0}
## The fastest an arm bone turns in its parent's frame outside a tested swing (degrees a second: 20 a frame at 60 fps;
## _limit_arm), and the bones it holds.
const ARM_STEP_DEG_S := 1200.0
const ARM_LIMITED := {"r": ["upperarm_r", "lowerarm_r", "hand_r"], "l": ["upperarm_l", "lowerarm_l", "hand_l"]}
## TipMatching's poles for the right arm (_pole_r).
const POLE_R: Vector3 = TipMatching.POLES.r
const CROSS_POLE_R: Vector3 = TipMatching.CROSS_POLES.r
## Halvings of the search for the share of the grip's turn the wrist allows.
const ALIGN_STEPS := 4
## P64c: the two-handed keys (see the class notes). The chop's: [the weapon fist's elevation from the front (degrees:
## 0 ahead, 90 straight up, 180 behind), its lateral lean (actor space, toward -X: the body's middle), its share of the
## palm's reach, the haft's elevation, the spine's bend forward (degrees)]. The arc's windup: [the fist's direction
## (yaw, pitch: AttackGeometry's), its share of the reach, the haft's direction (yaw, pitch)], for a stroke from the
## right (mirrored from the left).
const CHOP_KEYS := {
	"lift": [10.0, -0.25, 0.8, 70.0, 0.0],
	"raised": [104.0, -0.4, 0.86, 205.0, -9.0],
	"over": [62.0, -0.35, 0.92, 95.0, 6.0],
	"hit": [-42.0, -0.3, 0.94, -62.0, 30.0],
	"settle": [-48.0, -0.2, 0.86, -25.0, 8.0],
}
const ARC_KEYS := {
	"ready": [Vector2(30.0, -30.0), 0.75, Vector2(55.0, 15.0)],
	"wound": [Vector2(52.0, 16.0), 0.72, Vector2(128.0, 34.0)],
}
## The off fist on the haft: this share of the weapon's length above the weapon fist.
const TWO_HAND_GAP := 0.17
## How fast the keyed weapon arm comes in and out (1 / s of weight), and the blade's edge turns.
const KEY_BLEND_RATE := 6.0
const EDGE_RATE := 10.0

var rig: SkinnedRig = null
var tm: TipMatching = null
## Runs of _process_modification_with_delta (this modifier's; SkinnedRig.totals counts the run's).
var runs := 0
## After a run, in Body space: each palm where it is, the weapon's direction, the target the weapon hand
## was solved for (the tip-matched grip during an arc), and the held body's gap.
var palm := {"r": Vector3.ZERO, "l": Vector3.ZERO}
var palm_target := {"r": Vector3.ZERO, "l": Vector3.ZERO}
var weapon_dir := Vector3.FORWARD
var holding := false
var held_gap := Vector3.ZERO
## The last run's numbers: "arc" (the tip-matching weight), "fist_error_m" (world metres between the weapon
## palm and its target), "wrist_deg" (the weapon wrist's bend), "off_w", "us" (the run's microseconds).
var stats := {}
## The reach extension in use this frame (stage-1 metres and degrees, weighted by the arc's blend).
var reach_ext: Dictionary = REACH_NONE

var _bi := {}
## Each arm's bones as _limit_arm left them last frame ("r"/"l" -> [Quaternion]), and the rig's teleports then.
var _arm_prev := {}
var _arm_teleports := -1
## The last _solve's elbow and end.
var _sv_elbow := Vector3.ZERO
var _sv_end := Vector3.ZERO
var _grip_local := {"r": Vector3.ZERO, "l": Vector3.ZERO}
var _grip_axis := {"r": Vector3.ZERO, "l": Vector3.ZERO}
var _leg_len := {}
var _w_fp := 0.0
var _body_from_skel := Transform3D.IDENTITY
var _skel_from_body := Transform3D.IDENTITY
var _rest := {}
var _w_arc := 0.0
var _w_off := 0.0
## P64c: the two-handed state this frame (two_handed()): the keyed weapon arm's weight, the off hand's weight on the
## haft, the key ({} without one), the blade edge's way (Body space) and the weapon fist placed (Body space).
var two_w := 0.0
var _w_key := 0.0
var _two_key: Dictionary = {}
var _edge := Vector3.UP
var _fist_r := Vector3.ZERO
var _w_live := 1.0
var _ok := false


## Called by SkinnedRig once the modifier is under the skeleton: the bones, the frames between the
## skeleton and Visual/Body, the rest arms, and tip matching from the model's landmarks.
func setup(p_rig: SkinnedRig, index: Dictionary, body: Node3D) -> void:
	rig = p_rig
	tm = TipMatching.for_fist(index)
	var sk := get_skeleton()
	if sk == null or body == null:
		return
	for i in sk.get_bone_count():
		_bi[sk.get_bone_name(i)] = i
	for b: String in SPINE + ["clavicle_r", "clavicle_l", "upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "lowerarm_l", "hand_l",
			"index_01_r", "middle_01_r", "ring_01_r", "pinky_01_r", "index_01_l", "middle_01_l", "ring_01_l", "pinky_01_l",
			"pelvis", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
		if not _bi.has(b):
			push_warning("PoseBrainModifier: the skeleton has no bone %s" % b)
			return
	_body_from_skel = relative_transform(sk, body)
	_skel_from_body = _body_from_skel.affine_inverse()
	for side: String in ["r", "l"]:
		var up := sk.get_bone_global_rest(_bi["upperarm_" + side])
		var lo := sk.get_bone_global_rest(_bi["lowerarm_" + side])
		var ha := sk.get_bone_global_rest(_bi["hand_" + side])
		var palm0 := (sk.get_bone_global_rest(_bi["index_01_" + side]).origin
			+ sk.get_bone_global_rest(_bi["middle_01_" + side]).origin
			+ sk.get_bone_global_rest(_bi["ring_01_" + side]).origin) / 3.0
		var along0 := (palm0 - ha.origin).normalized()
		var across0 := sk.get_bone_global_rest(_bi["pinky_01_" + side]).origin - sk.get_bone_global_rest(_bi["index_01_" + side]).origin
		_rest[side] = {"up": up.basis, "lo": lo.basis, "ha": ha.basis,
			"frame_up": _frame(lo.origin - up.origin, (ha.origin - up.origin).cross(lo.origin - up.origin)),
			"frame_lo": _frame(ha.origin - lo.origin, (ha.origin - up.origin).cross(lo.origin - up.origin)),
			"frame_ha": _frame(along0, across0),
			"palm_local": ha.basis.inverse() * (palm0 - ha.origin), "hand_len": (palm0 - ha.origin).length()}
		# the fist's centre and the handle's line through it, in the hand bone's own space (P48's landmarks;
		# without them the knuckle line and the hand's across axis)
		var lm: Dictionary = index.get("landmarks", {})
		var gl: Variant = lm.get("grip_local_" + side)
		var ga: Variant = lm.get("grip_axis_" + side)
		_grip_local[side] = Vector3(gl[0], gl[1], gl[2]) if typeof(gl) == TYPE_ARRAY and (gl as Array).size() == 3 \
			else (_rest[side].palm_local as Vector3)
		_grip_axis[side] = (Vector3(ga[0], ga[1], ga[2]) if typeof(ga) == TYPE_ARRAY and (ga as Array).size() == 3 \
			else -(ha.basis.inverse() * across0)).normalized()
		var th := sk.get_bone_global_rest(_bi["thigh_" + side]).origin
		var ca := sk.get_bone_global_rest(_bi["calf_" + side]).origin
		var fo := sk.get_bone_global_rest(_bi["foot_" + side]).origin
		_leg_len[side] = [th.distance_to(ca), ca.distance_to(fo)]
	_ok = true


## `node`'s transform in `ancestor`'s space (the local transforms between them; outside the tree too).
static func relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## An orthonormal frame: x along `d`, y along `f` made perpendicular to d, z = x cross y.
static func _frame(d: Vector3, f: Vector3) -> Basis:
	var x := d.normalized()
	var y := f - x * f.dot(x)
	if y.length_squared() < 1e-10:
		y = Vector3.UP - x * Vector3.UP.dot(x)
		if y.length_squared() < 1e-10:
			y = Vector3.BACK - x * Vector3.BACK.dot(x)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


func _process_modification_with_delta(delta: float) -> void:
	if not _ok or rig == null or not is_instance_valid(rig):
		return
	var t0 := Time.get_ticks_usec()
	var sk := get_skeleton()
	runs += 1
	SkinnedRig.totals["modifier_runs"] = int(SkinnedRig.totals.get("modifier_runs", 0)) + 1
	var s := rig.rig_state()
	var dead := bool(s.get("dead", false))
	_w_live = move_toward(_w_live, 0.0 if dead else 1.0, delta * DEATH_BLEND_RATE)
	_twist_spine(sk, rig.torso_twist() * _w_live)
	_two_hand_state(s, delta)
	if absf(float(_two_key.get("lean", 0.0))) * _w_key > 1e-3:
		_bend_spine(sk, deg_to_rad(float(_two_key.lean)) * _w_key * _w_live)
	var actor := rig.actor
	var k := maxf(rig.body_scale, 0.01)
	var body: Node3D = rig.body
	# actor space -> Body space (the body's own lean, stagger and fall included)
	var to_body := (rig.transform * body.transform).affine_inverse()
	_weapon_arm(sk, s, actor, k, to_body, delta)
	_off_arm(sk, s, actor, k, to_body, delta)
	stats["us"] = Time.get_ticks_usec() - t0


# --------------------------------------------------------------------------- the spine

func _twist_spine(sk: Skeleton3D, twist: float) -> void:
	if absf(twist) < 1e-6:
		return
	var q := Basis(Vector3.UP, twist / 3.0)   # a turn about +Y is the same in both frames (180 degrees about Y apart)
	for b: String in SPINE:
		var i: int = _bi[b]
		var gp := sk.get_bone_global_pose(i)
		gp.basis = q * gp.basis
		sk.set_bone_global_pose(i, gp)


# --------------------------------------------------------------------------- the weapon arm

func _weapon_arm(sk: Skeleton3D, s: Dictionary, actor: Node, k: float, to_body: Transform3D, delta: float) -> void:
	var pose := rig.arm_pose()
	# the walk's swing in phase with the clips' legs: the clips' heel strikes fall on the brain's footfalls
	# (walk phase 0, pi) while the brain's own swing peaks at pi/2; cos() moves the peak onto the strike
	var share := rig.arm_swing_share()
	if share > 0.0:
		pose.y += SWING_DEG * share * (cos(rig.walk_phase()) - sin(rig.walk_phase()))
	var dir_actor := AttackGeometry.local_direction(pose.x, clampf(pose.y, -AttackGeometry.MAX_PITCH_DEG, AttackGeometry.MAX_PITCH_DEG))
	var dir := (to_body.basis * dir_actor).normalized()
	var sh := _to_body(sk.get_bone_global_pose(_bi.upperarm_r).origin)
	var arc := _is_arc(s)
	_w_arc = move_toward(_w_arc, 1.0 if arc else 0.0, delta * ARC_BLEND_RATE)
	_w_fp = move_toward(_w_fp, rig.first_person_rest_weight(), delta * FP_BLEND_RATE)
	# the generic mapping
	var target := sh + dir * (GENERIC_REACH_USE * tm.palm_reach("r"))
	var hand_dir := dir
	var wdir := _carried_weapon_dir(hand_dir, actor)
	var tip := Vector3.INF
	if not is_same(reach_ext, REACH_NONE):
		reach_ext = REACH_NONE
	if _w_arc > 0.0:
		var pivot := to_body * (_prop(actor, "weapon_pivot", Vector3(0.82, 2.9, 0.0) * k) as Vector3)
		var arm_m := float(_prop(actor, "arm_length", 1.5 * k)) / k
		var weapon_m := float(_prop(actor, "weapon_length", 1.85 * k)) / k
		var radius_m := float(_prop(actor, "weapon_radius", 0.45 * k)) / k
		var m := tm.match_swing_reach(sh, pivot, dir, arm_m, weapon_m, radius_m, "r")
		if float(m.clavicle_m) + float(m.lean_deg) + float(m.pelvis_m) > 0.0:
			_extend(sk, m, _w_arc)
			var predicted: Vector3 = m.shoulder
			sh = _to_body(sk.get_bone_global_pose(_bi.upperarm_r).origin)
			stats["reach_miss_m"] = sh.distance_to(predicted)
			m = tm.match_swing_at(sh, pivot, dir, arm_m, weapon_m, "r")
		target = target.lerp(m.grip, _w_arc)
		hand_dir = hand_dir.slerp(m.hand_dir, _w_arc).normalized()
		wdir = wdir.slerp(m.weapon_dir, _w_arc).normalized()
		if _w_arc >= 1.0:
			tip = m.tip
	if _w_key > 0.0 and not _two_key.is_empty():
		var kf := (to_body.basis * (_two_key.fist as Vector3)).normalized()
		var kt := sh + kf * float(_two_key.share) * tm.palm_reach("r")
		target = target.lerp(kt, _w_key)
		hand_dir = hand_dir.slerp(kf, _w_key).normalized()
		wdir = wdir.slerp((to_body.basis * (_two_key.weapon as Vector3)).normalized(), _w_key).normalized()
		if _w_key > 0.0:
			tip = Vector3.INF
	var weight := _w_live * (1.0 - _w_fp)
	# the point placed on the target: the fist's centre (tip matching is built for the fist: TipMatching.for_fist)
	var anchor: Vector3 = _grip_local.r
	var placed := _place_weapon_hand(sk, sh, target, wdir, hand_dir, tip, weight, anchor, maxf(1.0 - _w_arc, _w_key))
	target = placed.target
	wdir = placed.weapon_dir
	palm_target["r"] = target
	# Gate A: no arm bone turns faster than ARM_STEP_DEG_S outside a tested swing (a block's press and release moved
	# the brain's arm 37 degrees in one frame and the hand up to 81); the weapon turns with the hand, in the fist
	var computed := sk.get_bone_global_pose(_bi.hand_r).basis
	if _limit_arm("r", delta, _w_arc <= 0.0 and not _keyed_stroke()):
		var turn := sk.get_bone_global_pose(_bi.hand_r).basis.orthonormalized() * computed.orthonormalized().inverse()
		wdir = _to_body_dir(turn * _to_skel_dir(wdir))
	var hand := sk.get_bone_global_pose(_bi.hand_r)
	palm["r"] = _to_body(hand.origin + hand.basis * (_rest.r.palm_local as Vector3))
	var fist := _to_body(hand.origin + hand.basis * (_grip_local.r as Vector3))
	var placed_at := _to_body(hand.origin + hand.basis * anchor)
	var axis := _to_body_dir(hand.basis * (_grip_axis.r as Vector3))
	if weight < 1.0:
		wdir = axis.slerp(wdir, weight).normalized()   # where the clip's arm shows, the weapon lies in the fist's line
	weapon_dir = wdir
	_fist_r = fist
	var socket := rig.weapon_socket()
	if socket != null:
		var up := Vector3.UP if absf(wdir.y) < 0.98 else Vector3.BACK
		if rig.two_handed():
			# P64c: the blade's edge leads the stroke (the head's blade is the weapon's +X: wdir x up)
			var want: Vector3 = (to_body.basis * (_two_key.get("edge", Vector3.UP) as Vector3)).normalized()
			_edge = _edge.slerp(want, 1.0 - exp(-EDGE_RATE * delta)).normalized() if _edge.angle_to(want) < PI - 1e-3 else want
			if absf(wdir.normalized().dot(_edge)) < 0.97:
				up = _edge
		socket.transform = Transform3D(Basis.looking_at(wdir, up), fist)
	var fore := _to_body_dir(hand.origin - sk.get_bone_global_pose(_bi.lowerarm_r).origin)
	stats["arc"] = _w_arc
	stats["fp"] = _w_fp
	stats["fist_error_m"] = placed_at.distance_to(target) * k
	stats["grip_axis_deg"] = rad_to_deg(axis.angle_to(wdir))
	stats["wrist_deg"] = rad_to_deg(fore.angle_to(_to_body_dir(hand.basis * (_rest.r.palm_local as Vector3))))
	stats["reach"] = reach_ext   # (a new Dictionary whenever it changes: _extend makes one, REACH_NONE is read-only)


## Places the weapon hand by its fist (P50; see the class notes): the point `anchor` of the hand (the hand bone's
## own space: the fist's centre, or the knuckle line in a tested swing) on `target` (Body space),
## the handle's line through the fist along `wdir`, the hand rolled about it so the wrist bends least and
## tilted off it past MAX_WRIST_DEG. A target beyond the arm is pulled in along the shoulder line (and, given the
## tested `tip`, the weapon re-aimed at it, as TipMatching's own pull-in does). `weight` < 1 blends the fist and
## the hand from the clip's arm. Returns {"target" (where the fist was solved for), "weapon_dir"}.
func _place_weapon_hand(sk: Skeleton3D, sh: Vector3, target: Vector3, wdir: Vector3, hint: Vector3, tip: Vector3,
		weight: float, anchor: Vector3, align: float) -> Dictionary:
	var r: Dictionary = _rest.r
	var gl: Vector3 = anchor
	var ga: Vector3 = _grip_axis.r
	var l1: float = tm.upper.r
	var l2: float = tm.fore.r
	var reach := (l1 + l2) * TipMatching.SOLVE_MARGIN
	var w_s := _to_skel_dir(wdir)
	var lim := deg_to_rad(MAX_WRIST_DEG) - 1e-3
	var across := -w_s
	# 1. M10's hand (the long axis along `hint`, the knuckles across the handle), bent at the wrist by at most
	#    the limit: the hand's axis comes toward the forearm and the arm is solved again (the fist stays put)
	var hand_dir := hint.normalized()
	var hs := _frame(_to_skel_dir(hand_dir), across) * (r.frame_ha as Basis).inverse() * (r.ha as Basis)
	for i in WRIST_PASSES:
		if sh.distance_to(target - _to_body_vec(hs * gl)) > reach:
			target = _pulled_in(sh, target, _to_body_vec(hs * gl), reach)
			if tip != Vector3.INF:
				wdir = (tip - target).normalized()
				w_s = _to_skel_dir(wdir)
				across = -w_s
		var wrist_t := target - _to_body_vec(hs * gl)
		_solve(sh, wrist_t, l1, l2, _pole_r(wrist_t))
		var fore := (_sv_end - _sv_elbow).normalized()
		var bend := fore.angle_to(hand_dir)
		if bend <= lim + 1e-4:
			break
		hand_dir = fore.slerp(hand_dir, lim / bend).normalized()
		hs = _frame(_to_skel_dir(hand_dir), across) * (r.frame_ha as Basis).inverse() * (r.ha as Basis)
	# 2. the handle's line through the fist: as much of the turn that lays the fist's own axis along the weapon
	#    as the wrist's limit allows (all of it in most poses), up to `align` of it (a tested swing keeps M10's
	#    hand: tip matching decides the hand's place and aim)
	var full := _aligned_hand(hs, ga, w_s)
	var best := hs
	var lo := 0.0
	var hi := clampf(align, 0.0, 1.0)
	var q_from := hs.get_rotation_quaternion()
	var q_to := full.get_rotation_quaternion()
	var palm_local: Vector3 = r.palm_local
	var lim_align := lim + deg_to_rad(0.4)
	for i in (ALIGN_STEPS + 1 if hi > 0.0 else 0):
		var t := hi if i == 0 else (lo + hi) * 0.5
		var cand := Basis(q_from.slerp(q_to, t))
		var wt := target - _to_body_vec(cand * gl)
		if sh.distance_to(wt) > reach:
			hi = t
			continue
		_solve(sh, wt, l1, l2, _pole_r(wt))
		var fore_s := _to_skel_dir(_sv_end - _sv_elbow)
		if fore_s.angle_to((cand * palm_local).normalized()) <= lim_align:
			best = cand
			if i == 0:
				break
			lo = t
		else:
			hi = t
	hs = best
	# the final solve for the hand as turned
	var wrist_t2 := target - _to_body_vec(hs * gl)
	if weight < 1.0:
		var now := sk.get_bone_global_pose(_bi.hand_r)
		var clip_fist := _to_body(now.origin + now.basis * gl)
		target = clip_fist.lerp(target, weight)
		hs = Basis(now.basis.get_rotation_quaternion().slerp(hs.get_rotation_quaternion(), weight)).scaled(now.basis.get_scale())
		wrist_t2 = target - _to_body_vec(hs * gl)
	_solve(sh, wrist_t2, l1, l2, _pole_r(wrist_t2))
	_set_arm(sk, "r", sh, _sv_elbow, _sv_end, hs)
	return {"target": target, "weapon_dir": wdir}


## TipMatching.two_bone into _sv_elbow and _sv_end: the same arithmetic without a Dictionary a solve (the weapon hand
## runs up to ten a frame; Gate A, lens 6).
func _solve(sh: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> void:
	var d := target - sh
	var lo := absf(l1 - l2) * 1.001 + 1e-4
	var hi := (l1 + l2) * TipMatching.SOLVE_MARGIN
	var dist := clampf(d.length(), lo, hi)
	var dn := d.normalized() if d.length_squared() > 1e-10 else Vector3.DOWN
	var pv := pole - dn * pole.dot(dn)
	if pv.length_squared() < 1e-8:
		pv = Vector3.DOWN - dn * Vector3.DOWN.dot(dn)
	if pv.length_squared() < 1e-8:
		pv = Vector3.BACK - dn * Vector3.BACK.dot(dn)
	pv = pv.normalized()
	var a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	_sv_elbow = sh + dn * a + pv * h
	_sv_end = sh + dn * dist


## TipMatching.pole_for("r", target), the same arithmetic.
static func _pole_r(target: Vector3) -> Vector3:
	var t := clampf(-target.x / TipMatching.CROSS_BLEND_M, 0.0, 1.0)
	return POLE_R.lerp(CROSS_POLE_R, t).normalized()


## The fist's target pulled in along the shoulder line until its wrist (the target less `offset`, the fist's
## place from the wrist) is `reach` from the shoulder `sh`.
static func _pulled_in(sh: Vector3, target: Vector3, offset: Vector3, reach: float) -> Vector3:
	var e := (target - sh).normalized()
	var c := offset.dot(e)
	var rr := c + sqrt(maxf(0.0, reach * reach - (offset.length_squared() - c * c)))
	return sh + e * minf(rr, sh.distance_to(target))


## `hand` turned by the shortest arc that lays its handle axis `grip_axis` (hand bone space) along `w_s`
## (skeleton space).
static func _aligned_hand(hand: Basis, grip_axis: Vector3, w_s: Vector3) -> Basis:
	var g := (hand * grip_axis).normalized()
	if g.angle_to(w_s) < 1e-5:
		return hand
	return Basis(Quaternion(g, w_s.normalized())) * hand


## Sets an arm's upper arm and forearm from the shoulder `sh`, `elbow` and `wrist` (Body space; the bones keep
## the rest arm's plane) and the hand's basis `hand_basis` (skeleton space).
func _set_arm(sk: Skeleton3D, side: String, sh: Vector3, elbow: Vector3, wrist: Vector3, hand_basis: Basis) -> void:
	var r: Dictionary = _rest[side]
	var iu: int = _bi["upperarm_" + side]
	var il: int = _bi["lowerarm_" + side]
	var ih: int = _bi["hand_" + side]
	var sh_s := _to_skel(sh)
	var el_s := _to_skel(elbow)
	var wr_s := _to_skel(wrist)
	var normal := (wr_s - sh_s).cross(el_s - sh_s)
	if normal.length_squared() < 1e-10:
		normal = (wr_s - sh_s).cross(_to_skel_dir(tm.pole_for(side, wrist)))
	var up_b := _frame(el_s - sh_s, normal) * (r.frame_up as Basis).inverse() * (r.up as Basis)
	sk.set_bone_global_pose(iu, Transform3D(up_b, sk.get_bone_global_pose(iu).origin))
	var lo_rot := _frame(wr_s - el_s, normal) * (r.frame_lo as Basis).inverse()
	sk.set_bone_global_pose(il, Transform3D(lo_rot * (r.lo as Basis), sk.get_bone_global_pose(il).origin))
	sk.set_bone_global_pose(ih, Transform3D(hand_basis, sk.get_bone_global_pose(ih).origin))


## The reach extension on the bones (Body space amounts from TipMatching.match_swing_reach, x `weight`): the
## pelvis shifted (the feet kept where they stand), the spine leaned, the clavicle protracted.
func _extend(sk: Skeleton3D, m: Dictionary, weight: float) -> void:
	var lean := deg_to_rad(float(m.lean_deg)) * weight
	var cla := float(m.clavicle_m) * weight
	var sh0 := _to_body(sk.get_bone_global_pose(_bi.upperarm_r).origin)
	if lean > 0.0:
		var axis := _to_skel_dir(m.lean_axis as Vector3)
		for b: String in SPINE:
			var i: int = _bi[b]
			var g := sk.get_bone_global_pose(i)
			g.basis = Basis(axis, lean / float(SPINE.size())) * g.basis
			sk.set_bone_global_pose(i, g)
	if cla > 0.0:
		var shn := _to_body(sk.get_bone_global_pose(_bi.upperarm_r).origin)
		_protract(sk, "r", shn + (m.clavicle_dir as Vector3), cla, 1.0)
	# the pelvis: its own share, and what the clavicle's and the spine's joints fell short of the shoulder the
	# extension was solved for (the bones turn about their own joints, the solve about the pelvis), within its
	# bound; the feet stay where they stand
	var want := sh0.lerp(m.shoulder as Vector3, weight)
	var now := _to_body(sk.get_bone_global_pose(_bi.upperarm_r).origin)
	var shift := (want - now).limit_length(REACH_PELVIS_MAX * weight)
	reach_ext = {"clavicle_m": cla, "lean_deg": rad_to_deg(lean), "pelvis_m": shift.length()}
	if shift.length() > 1e-5:
		var feet := {}
		for side: String in ["l", "r"]:
			feet[side] = sk.get_bone_global_pose(_bi["foot_" + side])
		var ip: int = _bi.pelvis
		var gp := sk.get_bone_global_pose(ip)
		gp.origin += _to_skel_vec(shift)
		sk.set_bone_global_pose(ip, gp)
		for side: String in ["l", "r"]:
			_keep_foot(sk, side, feet[side])


## Brings a foot back to `was` (its global pose before the pelvis moved) by a two-bone solve of the leg, the knee
## kept in its own plane toward KNEE_POLE.
func _keep_foot(sk: Skeleton3D, side: String, was: Transform3D) -> void:
	var it: int = _bi["thigh_" + side]
	var ic: int = _bi["calf_" + side]
	var ifo: int = _bi["foot_" + side]
	var hip := sk.get_bone_global_pose(it).origin
	var knee := sk.get_bone_global_pose(ic).origin
	var ankle := sk.get_bone_global_pose(ifo).origin
	var bend := knee - (hip + ankle) * 0.5
	var pole := bend if bend.length_squared() > 1e-8 else _to_skel_dir(KNEE_POLE)
	var lens: Array = _leg_len[side]
	var solve := TipMatching.two_bone(hip, was.origin, float(lens[0]), float(lens[1]), pole)
	var tg := sk.get_bone_global_pose(it)
	var from_t := (knee - hip).normalized()
	var to_t := ((solve.elbow as Vector3) - hip).normalized()
	if from_t.angle_to(to_t) > 1e-6:
		tg.basis = Basis(Quaternion(from_t, to_t)) * tg.basis
		sk.set_bone_global_pose(it, tg)
	var cg := sk.get_bone_global_pose(ic)
	var knee2 := cg.origin
	var ankle2 := sk.get_bone_global_pose(ifo).origin
	var from_c := (ankle2 - knee2).normalized()
	var to_c := ((solve.end as Vector3) - knee2).normalized()
	if from_c.angle_to(to_c) > 1e-6:
		cg.basis = Basis(Quaternion(from_c, to_c)) * cg.basis
		sk.set_bone_global_pose(ic, cg)
	var fg := sk.get_bone_global_pose(ifo)
	sk.set_bone_global_pose(ifo, Transform3D(was.basis, fg.origin))


## A weapon arc's arm (the tested swing): an action with a weapon_arc hit and no pose override (a grab).
static func _is_arc(s: Dictionary) -> bool:
	var a: ActionDef = s.get("action")
	return a != null and a.hit_shape == "weapon_arc" and typeof(s.get("pose_override")) != TYPE_DICTIONARY


## The carried weapon's direction for a hand along `hand_dir` (the generic mapping, as
## TipMatching.idle_grip holds it): GRIP_AXIS_DEG off the hand toward the front, toward the sky for the
## tree and the pine.
static func _carried_weapon_dir(hand_dir: Vector3, actor: Node) -> Vector3:
	var w: Variant = _prop(actor, "weapon", {})
	var shape := WeaponVisuals.shape_of(w) if typeof(w) == TYPE_DICTIONARY else "club"
	var toward := Vector3.UP if shape == "tree" or shape == "pine" else Vector3.FORWARD
	var h := hand_dir.normalized()
	var perp := toward - h * toward.dot(h)
	if perp.length_squared() < 1e-8:
		perp = Vector3.FORWARD - h * Vector3.FORWARD.dot(h)
	var a := deg_to_rad(TipMatching.GRIP_AXIS_DEG)
	return (h * cos(a) + perp.normalized() * sin(a)).normalized()


# --------------------------------------------------------------------------- two hands on the haft (P64c)

## The two-handed key this frame (see the class notes) into _two_key ({"fist", "share", "weapon" (actor-space
## directions), "lean" (degrees), "edge" (actor space)}), its weight _w_key and the off hand's two_w.
func _two_hand_state(s: Dictionary, delta: float) -> void:
	if not rig.two_handed():
		_w_key = 0.0
		two_w = 0.0
		_two_key = {}
		return
	var a: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var dead := bool(s.get("dead", false))
	var want_key := 0.0
	var want_two := 0.0
	if a != null and not dead and typeof(s.get("pose_override")) != TYPE_DICTIONARY:
		if ActorRig.is_weapon_chop(a):
			var ck := chop_key(phase, f)
			_two_key = ck[0]
			want_key = 1.0
			want_two = float(ck[1])
		elif a.hit_shape == "weapon_arc":
			var from_left := float(a.param("arc", {}).get("yaw_start_deg", 0.0)) < float(a.param("arc", {}).get("yaw_end_deg", 0.0))
			var ak := arc_key(phase, f, from_left)
			_two_key = ak[0]
			want_key = 1.0 if phase == ActionDef.Phase.WINDUP else 0.0
			want_two = float(ak[1])
	if want_key > 0.0:
		_w_key = move_toward(_w_key, want_key, delta * KEY_BLEND_RATE)
	else:
		_w_key = 0.0 if a != null and a.hit_shape == "weapon_arc" else move_toward(_w_key, 0.0, delta * KEY_BLEND_RATE)
	# the keys' own weights are smooth on the action's clock; without an action the hand lets go
	two_w = want_two if want_key > 0.0 or want_two > 0.0 or (a != null and a.hit_shape == "weapon_arc") \
		else move_toward(two_w, 0.0, delta * KEY_BLEND_RATE)
	if _w_key <= 0.0 and two_w <= 0.0 and a == null:
		_two_key = {}


## The chop's key at `phase` / `f` ([key, the off hand's weight]): CHOP_KEYS mixed on the action's clock.
static func chop_key(phase: int, f: float) -> Array:
	var t := clampf(f, 0.0, 1.0)
	match phase:
		ActionDef.Phase.WINDUP:
			var e := 1.0 - (1.0 - t) * (1.0 - t)
			var k := _chop_mix(CHOP_KEYS.lift, CHOP_KEYS.raised, smoothstep(0.0, 1.0, e)) if t > 0.15 \
				else _chop_mix(CHOP_KEYS.settle, CHOP_KEYS.lift, t / 0.15)
			return [_chop_dirs(k), smoothstep(0.0, 0.3, t)]
		ActionDef.Phase.ACTIVE:
			var u := smoothstep(0.0, 0.45, t)
			var k2 := _chop_mix(CHOP_KEYS.raised, CHOP_KEYS.over, u * 2.0) if u < 0.5 \
				else _chop_mix(CHOP_KEYS.over, CHOP_KEYS.hit, u * 2.0 - 1.0)
			return [_chop_dirs(k2), 1.0]
		ActionDef.Phase.RECOVERY:
			return [_chop_dirs(_chop_mix(CHOP_KEYS.hit, CHOP_KEYS.settle, smoothstep(0.0, 0.8, t))), 1.0 - smoothstep(0.35, 0.9, t)]
	return [_chop_dirs(CHOP_KEYS.settle), 0.0]


static func _chop_mix(a: Array, b: Array, t: float) -> Array:
	var out: Array = []
	for i in a.size():
		out.append(lerpf(float(a[i]), float(b[i]), t))
	return out


## A chop key's directions (actor space: -Z the front): the fist and the haft in the body's middle plane, leaning in.
static func _chop_dirs(k: Array) -> Dictionary:
	var fe := deg_to_rad(float(k[0]))
	var we := deg_to_rad(float(k[3]))
	return {"fist": Vector3(float(k[1]), sin(fe), -cos(fe)).normalized(), "share": float(k[2]),
		"weapon": Vector3(-0.06, sin(we), -cos(we)).normalized(), "lean": float(k[4]), "edge": Vector3.RIGHT}


## A weapon arc's two-handed key ([key, the off hand's weight]): the windup drawn back over the shoulder of the swing
## (ARC_KEYS; `from_left` mirrored), the off hand on the haft through the active phase, letting go in the recovery.
static func arc_key(phase: int, f: float, from_left: bool) -> Array:
	var t := clampf(f, 0.0, 1.0)
	var sx := -1.0 if from_left else 1.0
	var ready: Array = ARC_KEYS.ready
	var wound: Array = ARC_KEYS.wound
	var e := 1.0 - (1.0 - t) * (1.0 - t)
	var fp := (ready[0] as Vector2).lerp(wound[0], e) if phase == ActionDef.Phase.WINDUP else (wound[0] as Vector2)
	var wp := (ready[2] as Vector2).lerp(wound[2], e) if phase == ActionDef.Phase.WINDUP else (wound[2] as Vector2)
	var share := lerpf(float(ready[1]), float(wound[1]), e)
	var key := {"fist": AttackGeometry.local_direction(fp.x * sx, fp.y), "share": share,
		"weapon": AttackGeometry.local_direction(wp.x * sx, wp.y), "lean": 0.0,
		"edge": Vector3.UP if from_left else Vector3.DOWN}
	var two := 0.0
	match phase:
		ActionDef.Phase.WINDUP:
			two = smoothstep(0.0, 0.35, t)
		ActionDef.Phase.ACTIVE:
			two = 1.0
		ActionDef.Phase.RECOVERY:
			two = 1.0 - smoothstep(0.15, 0.7, t)
	return [key, two]


## True while a keyed two-handed stroke swings (the chop's active phase): its arms are not held to ARM_STEP_DEG_S (the
## stroke's own clock moves them, as a tested swing's).
func _keyed_stroke() -> bool:
	var a: ActionDef = rig.rig_state().get("action")
	return _w_key > 0.0 and a != null and ActorRig.is_weapon_chop(a) \
		and int(rig.rig_state().get("phase", 0)) == ActionDef.Phase.ACTIVE


## Bends the spine forward (+) or back (-) by `ang` radians over its three bones, about the body's own side axis.
func _bend_spine(sk: Skeleton3D, ang: float) -> void:
	var axis := _to_skel_dir(Vector3.RIGHT)
	for b: String in SPINE:
		var i: int = _bi[b]
		var gp := sk.get_bone_global_pose(i)
		gp.basis = Basis(axis, -ang / float(SPINE.size())) * gp.basis
		sk.set_bone_global_pose(i, gp)


# --------------------------------------------------------------------------- the off arm

func _off_arm(sk: Skeleton3D, s: Dictionary, actor: Node, k: float, to_body: Transform3D, delta: float) -> void:
	var override: Variant = s.get("pose_override")
	var state := int(s.get("state", 0))
	var acting := s.get("action") != null or typeof(override) == TYPE_DICTIONARY \
		or state == CombatController.State.BLOCKING or state == CombatController.State.DODGING or bool(s.get("guarding", false))
	_w_off = move_toward(_w_off, 1.0 if acting else 0.0, delta * OFF_BLEND_RATE)
	var sh := _to_body(sk.get_bone_global_pose(_bi.upperarm_l).origin)
	var grab_phase := str(s.get("grab_phase", ""))
	holding = grab_phase in SkinnedRig.GRIP_PHASES and str(s.get("holding", "")) != ""
	var hold := grab_phase == "hold" or grab_phase == "crush"
	var target: Vector3
	var hand_dir: Vector3
	# (read only in a grab: outside one nothing below uses it)
	var grab: Variant = _prop(actor, "grab", null) if grab_phase != "" else null
	if hold and grab != null and (grab as Object).has_method("socket_local"):
		var socket := to_body * ((grab as Object).call("socket_local") as Vector3)
		var reach := tm.palm_reach("l") * TipMatching.SOLVE_MARGIN
		if sh.distance_to(socket) > reach:
			_protract(sk, "l", socket, sh.distance_to(socket) - reach, _w_off * _w_live)
			sh = _to_body(sk.get_bone_global_pose(_bi.upperarm_l).origin)
		target = socket if sh.distance_to(socket) <= reach else sh + (socket - sh).normalized() * reach
		hand_dir = (target - sh).normalized()
	else:
		var off := rig.off_pose()
		var dir := (to_body.basis * AttackGeometry.local_direction(off.x, clampf(off.y, -80.0, 80.0))).normalized()
		target = sh + dir * (GENERIC_REACH_USE * tm.palm_reach("l"))
		hand_dir = dir
	if two_w > 0.0 and not hold:
		# P64c: the off fist on the haft above the weapon fist, the hand across the haft (the fingers round it); a haft
		# beyond the arm's reach brings the shoulder forward (the clavicle), as a reaching shoulder does
		var length := float(_prop(actor, "weapon_length", 1.85 * k)) / k
		var on_haft := _fist_r + weapon_dir * TWO_HAND_GAP * length
		var reach := tm.palm_reach("l") * TipMatching.SOLVE_MARGIN
		if sh.distance_to(on_haft) > reach:
			_protract(sk, "l", on_haft, sh.distance_to(on_haft) - reach, two_w * _w_live)
			sh = _to_body(sk.get_bone_global_pose(_bi.upperarm_l).origin)
		var across := (on_haft - sh) - weapon_dir * (on_haft - sh).dot(weapon_dir)
		var hd := across.normalized() if across.length_squared() > 1e-6 else (on_haft - sh).normalized()
		target = target.lerp(on_haft, two_w)
		hand_dir = hand_dir.slerp(hd, two_w).normalized()
		_w_off = maxf(_w_off, two_w)
	palm_target["l"] = target
	var w := _w_off * _w_live
	if w > 0.0:
		_place_arm(sk, "l", target, hand_dir, Vector3.ZERO, w, not hold and two_w <= 0.0)
	_limit_arm("l", delta, not _keyed_stroke())
	var hand := sk.get_bone_global_pose(_bi.hand_l)
	palm["l"] = _to_body(hand.origin + hand.basis * (_rest.l.palm_local as Vector3))
	stats["off_w"] = w
	held_gap = Vector3.ZERO
	if holding and grab != null and (grab as Object).has_method("socket_local"):
		var socket := to_body * ((grab as Object).call("socket_local") as Vector3)
		held_gap = (palm.l as Vector3) - socket
		if held_gap.length() > HELD_GAP_MAX:
			held_gap = held_gap.normalized() * HELD_GAP_MAX


## Holds the arm of `side` (the upper arm, the forearm and the hand, in their parents' frames) within ARM_STEP_DEG_S
## of where it was last frame when `limit` is true (Gate A: the pop on a block's press and release, and the off arm
## handed back to its clip); remembers where it is now either way. Forgets on a teleport or a respawn. Presentation
## only: what the bones show, never when anything happens. True when it moved a bone.
func _limit_arm(side: String, delta: float, limit: bool) -> bool:
	var sk := get_skeleton()
	if rig.teleports != _arm_teleports:
		_arm_teleports = rig.teleports
		_arm_prev.clear()
	var prev: Array = _arm_prev.get(side, [])
	var bones: Array = ARM_LIMITED[side]
	var max_step := deg_to_rad(ARM_STEP_DEG_S) * maxf(delta, 1.0 / 240.0)
	var moved := false
	var now: Array = []
	for i in bones.size():
		var b: int = _bi[bones[i]]
		var q := sk.get_bone_pose_rotation(b)
		if limit and not prev.is_empty():
			var was: Quaternion = prev[i]
			var ang := was.angle_to(q)
			if ang > max_step:
				q = was.slerp(q, max_step / ang)
				sk.set_bone_pose_rotation(b, q)
				moved = true
		now.append(q)
	_arm_prev[side] = now
	if moved:
		stats["arm_limited"] = int(stats.get("arm_limited", 0)) + 1
	return moved


## Turns the clavicle of `side` about its own joint so the shoulder moves toward `toward` (Body space) by
## about `short_m`, at most PROTRACT_MAX_DEG, scaled by `weight`.
func _protract(sk: Skeleton3D, side: String, toward: Vector3, short_m: float, weight: float) -> void:
	var ic: int = _bi["clavicle_" + side]
	var cl := sk.get_bone_global_pose(ic)
	var arm := sk.get_bone_global_pose(_bi["upperarm_" + side]).origin - cl.origin
	var to := _to_skel(toward) - cl.origin
	var axis := arm.cross(to)
	if axis.length_squared() < 1e-10 or arm.length() < 1e-4:
		return
	var ang := minf(minf(short_m / arm.length(), deg_to_rad(PROTRACT_MAX_DEG)), arm.angle_to(to)) * weight
	cl.basis = Basis(axis.normalized(), ang) * cl.basis
	sk.set_bone_global_pose(ic, cl)


# --------------------------------------------------------------------------- placing an arm

## Puts the palm of `side` on `palm_target` (Body space) with the hand's long axis along `hand_dir`; the
## hand's across axis (index to little finger) toward `across` made perpendicular to it (Vector3.ZERO:
## the wrist straight, the hand as the forearm carries it). `weight` < 1 blends the target and the hand's
## direction from the clip's own arm.
func _place_arm(sk: Skeleton3D, side: String, palm_target: Vector3, hand_dir: Vector3, across: Vector3, weight: float,
		straight := false) -> void:
	var r: Dictionary = _rest[side]
	var iu: int = _bi["upperarm_" + side]
	var il: int = _bi["lowerarm_" + side]
	var ih: int = _bi["hand_" + side]
	var sh := _to_body(sk.get_bone_global_pose(iu).origin)
	if weight < 1.0:
		var hand_now := sk.get_bone_global_pose(ih)
		var clip_palm := _to_body(hand_now.origin + hand_now.basis * (r.palm_local as Vector3))
		var clip_dir := _to_body_dir(hand_now.basis * (r.palm_local as Vector3))
		palm_target = clip_palm.lerp(palm_target, weight)
		hand_dir = clip_dir.slerp(hand_dir.normalized(), weight)
	hand_dir = hand_dir.normalized()
	var l1: float = tm.upper[side]
	var l2: float = tm.fore[side]
	var wrist := palm_target - hand_dir * float(r.hand_len)
	var solve := TipMatching.two_bone(sh, wrist, l1, l2, tm.pole_for(side, wrist))
	var elbow: Vector3 = solve.elbow
	wrist = solve.end
	# the wrist bends at most MAX_WRIST_DEG: the hand turns toward the forearm and the arm is solved again (the
	# palm stays on its target; only the hand's angle around the grip changes)
	for i in WRIST_PASSES:
		var fore := (wrist - elbow).normalized()
		var bend := fore.angle_to(hand_dir)
		if straight and bend > 1e-3:
			hand_dir = fore   # P50: the relaxed off hand along its forearm (it never droops)
		elif bend <= deg_to_rad(MAX_WRIST_DEG) + 1e-4:
			break
		else:
			hand_dir = fore.slerp(hand_dir, (deg_to_rad(MAX_WRIST_DEG) - 1e-3) / bend).normalized()
		wrist = palm_target - hand_dir * float(r.hand_len)
		solve = TipMatching.two_bone(sh, wrist, l1, l2, tm.pole_for(side, wrist))
		elbow = solve.elbow
		wrist = solve.end
	# skeleton space from here
	var sh_s := _to_skel(sh)
	var el_s := _to_skel(elbow)
	var wr_s := _to_skel(wrist)
	var normal := (wr_s - sh_s).cross(el_s - sh_s)
	if normal.length_squared() < 1e-10:
		normal = (wr_s - sh_s).cross(_to_skel_dir(tm.pole_for(side, wrist)))
	var up_b := _frame(el_s - sh_s, normal) * (r.frame_up as Basis).inverse() * (r.up as Basis)
	sk.set_bone_global_pose(iu, Transform3D(up_b, sk.get_bone_global_pose(iu).origin))
	var lo_rot := _frame(wr_s - el_s, normal) * (r.frame_lo as Basis).inverse()
	sk.set_bone_global_pose(il, Transform3D(lo_rot * (r.lo as Basis), sk.get_bone_global_pose(il).origin))
	var along := _to_skel_dir(hand_dir)
	var acr := _to_skel_dir(across) if across != Vector3.ZERO else lo_rot * (r.frame_ha as Basis).y
	var ha_b := _frame(along, acr) * (r.frame_ha as Basis).inverse() * (r.ha as Basis)
	sk.set_bone_global_pose(ih, Transform3D(ha_b, sk.get_bone_global_pose(ih).origin))


# --------------------------------------------------------------------------- frames and reads

func _to_body(p: Vector3) -> Vector3:
	return _body_from_skel * p


func _to_body_dir(v: Vector3) -> Vector3:
	return (_body_from_skel.basis * v).normalized()


func _to_skel(p: Vector3) -> Vector3:
	return _skel_from_body * p


func _to_skel_dir(v: Vector3) -> Vector3:
	return (_skel_from_body.basis * v).normalized()


func _to_body_vec(v: Vector3) -> Vector3:
	return _body_from_skel.basis * v


func _to_skel_vec(v: Vector3) -> Vector3:
	return _skel_from_body.basis * v


## A Body-space direction in the skeleton's space (SecondaryMotion's front; tests).
func skeleton_dir(v: Vector3) -> Vector3:
	return _to_skel_dir(v)


## A skeleton-space direction in Body space (the eyes' look: SkinnedRig).
func body_dir(v: Vector3) -> Vector3:
	return _to_body_dir(v)


## The weapon fist's centre and the handle's line through it now (Body space; valid inside SkinnedRig.posed):
## {"centre", "axis"} from the posed hand bone and the index's grip landmarks.
func fist(side := "r") -> Dictionary:
	var sk := get_skeleton()
	if sk == null or not _ok:
		return {}
	var hand := sk.get_bone_global_pose(_bi["hand_" + side])
	return {"centre": _to_body(hand.origin + hand.basis * (_grip_local[side] as Vector3)),
		"axis": _to_body_dir(hand.basis * (_grip_axis[side] as Vector3))}


static func _prop(o: Variant, name: String, fallback: Variant) -> Variant:
	if o == null or not is_instance_valid(o) or not (name in o):
		return fallback
	var v: Variant = (o as Object).get(name)
	return fallback if v == null else v
