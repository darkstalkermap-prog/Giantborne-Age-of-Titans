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

var _bi := {}
var _body_from_skel := Transform3D.IDENTITY
var _skel_from_body := Transform3D.IDENTITY
var _rest := {}
var _w_arc := 0.0
var _w_off := 0.0
var _w_live := 1.0
var _ok := false


## Called by SkinnedRig once the modifier is under the skeleton: the bones, the frames between the
## skeleton and Visual/Body, the rest arms, and tip matching from the model's landmarks.
func setup(p_rig: SkinnedRig, index: Dictionary, body: Node3D) -> void:
	rig = p_rig
	tm = TipMatching.from_index(index)
	var sk := get_skeleton()
	if sk == null or body == null:
		return
	for i in sk.get_bone_count():
		_bi[sk.get_bone_name(i)] = i
	for b: String in SPINE + ["clavicle_r", "clavicle_l", "upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "lowerarm_l", "hand_l",
			"index_01_r", "middle_01_r", "ring_01_r", "pinky_01_r", "index_01_l", "middle_01_l", "ring_01_l", "pinky_01_l"]:
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
	# the generic mapping
	var target := sh + dir * (GENERIC_REACH_USE * tm.palm_reach("r"))
	var hand_dir := dir
	var wdir := _carried_weapon_dir(hand_dir, actor)
	if _w_arc > 0.0:
		var pivot_actor: Vector3 = _prop(actor, "weapon_pivot", Vector3(0.82, 2.9, 0.0) * k)
		var arm_m := float(_prop(actor, "arm_length", 1.5 * k))
		var weapon_m := float(_prop(actor, "weapon_length", 1.85 * k))
		var m := tm.match_swing_at(sh, to_body * pivot_actor, dir, arm_m / k, weapon_m / k, "r")
		target = target.lerp(m.grip, _w_arc)
		hand_dir = hand_dir.slerp(m.hand_dir, _w_arc).normalized()
		wdir = wdir.slerp(m.weapon_dir, _w_arc).normalized()
	palm_target["r"] = target
	_place_arm(sk, "r", target, hand_dir, -wdir, _w_live)
	var hand := sk.get_bone_global_pose(_bi.hand_r)
	palm["r"] = _to_body(hand.origin + hand.basis * (_rest.r.palm_local as Vector3))
	if _w_live < 1.0:
		wdir = wdir.slerp(_carried_weapon_dir(_to_body_dir(hand.basis * (_rest.r.palm_local as Vector3)), actor), 1.0 - _w_live)
	weapon_dir = wdir
	var socket := rig.weapon_socket()
	if socket != null:
		var up := Vector3.UP if absf(wdir.y) < 0.98 else Vector3.BACK
		socket.transform = Transform3D(Basis.looking_at(wdir, up), palm.r)
	var fore := _to_body_dir(hand.origin - sk.get_bone_global_pose(_bi.lowerarm_r).origin)
	stats["arc"] = _w_arc
	stats["fist_error_m"] = (palm.r as Vector3).distance_to(target) * k
	stats["wrist_deg"] = rad_to_deg(fore.angle_to(_to_body_dir(hand.basis * (_rest.r.palm_local as Vector3))))


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
	var toward := Vector3.UP if shape in ["tree", "pine"] else Vector3.FORWARD
	var h := hand_dir.normalized()
	var perp := toward - h * toward.dot(h)
	if perp.length_squared() < 1e-8:
		perp = Vector3.FORWARD - h * Vector3.FORWARD.dot(h)
	var a := deg_to_rad(TipMatching.GRIP_AXIS_DEG)
	return (h * cos(a) + perp.normalized() * sin(a)).normalized()


# --------------------------------------------------------------------------- the off arm

func _off_arm(sk: Skeleton3D, s: Dictionary, actor: Node, k: float, to_body: Transform3D, delta: float) -> void:
	var override: Variant = s.get("pose_override")
	var state := int(s.get("state", 0))
	var acting := s.get("action") != null or typeof(override) == TYPE_DICTIONARY \
		or state in [CombatController.State.BLOCKING, CombatController.State.DODGING] or bool(s.get("guarding", false))
	_w_off = move_toward(_w_off, 1.0 if acting else 0.0, delta * OFF_BLEND_RATE)
	var sh := _to_body(sk.get_bone_global_pose(_bi.upperarm_l).origin)
	var grab_phase := str(s.get("grab_phase", ""))
	holding = grab_phase in ["hold", "crush", "throw"] and str(s.get("holding", "")) != ""
	var target: Vector3
	var hand_dir: Vector3
	var grab: Variant = _prop(actor, "grab", null)
	if grab_phase in ["hold", "crush"] and grab != null and (grab as Object).has_method("socket_local"):
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
	palm_target["l"] = target
	var w := _w_off * _w_live
	if w > 0.0:
		_place_arm(sk, "l", target, hand_dir, Vector3.ZERO, w)
	var hand := sk.get_bone_global_pose(_bi.hand_l)
	palm["l"] = _to_body(hand.origin + hand.basis * (_rest.l.palm_local as Vector3))
	stats["off_w"] = w
	held_gap = Vector3.ZERO
	if holding and grab != null and (grab as Object).has_method("socket_local"):
		var socket := to_body * ((grab as Object).call("socket_local") as Vector3)
		held_gap = (palm.l as Vector3) - socket
		if held_gap.length() > HELD_GAP_MAX:
			held_gap = held_gap.normalized() * HELD_GAP_MAX


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
func _place_arm(sk: Skeleton3D, side: String, palm_target: Vector3, hand_dir: Vector3, across: Vector3, weight: float) -> void:
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
		if bend <= deg_to_rad(MAX_WRIST_DEG) + 1e-4:
			break
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


static func _prop(o: Variant, name: String, fallback: Variant) -> Variant:
	if o == null or not is_instance_valid(o) or not (name in o):
		return fallback
	var v: Variant = (o as Object).get(name)
	return fallback if v == null else v
