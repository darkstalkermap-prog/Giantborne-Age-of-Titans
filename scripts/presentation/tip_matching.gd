class_name TipMatching
extends RefCounted
## Tip matching (P42; plan M10 §2.9, decision 3): where the realistic giant's weapon hand goes so the
## visible weapon shows the tested swing. Pure: the gameplay geometry (the growth profile's pivot and arm,
## the weapon's length and radius, AttackGeometry's arcs) and the skeleton's landmarks in, points out;
## nothing reads the simulation and nothing in the simulation reads this (a code rule). P43's
## PoseBrainModifier puts the bones on what it returns; P44's preview takes idle_grip().
##
## The gameplay arm is the stylized giant's - pivot (0.82, 2.9, 0)·k and a 1.5·k arm - and a real body of
## that height has its shoulder at (0.414, 3.015, -0.033)·k and reaches about 1.39·k, so the tested grip is
## out of reach in nearly every swing. Instead, in Body space (stage-1 metres: actor values / k; +X right,
## -Z forward):
##   tip  = pivot + direction × (arm + weapon), the tested segment's far end;
##   grip = the natural grip (shoulder + direction × REACH_USE × reach) moved onto the sphere of radius
##          weapon around the tip, then projected alternately into the grip's reach (RMAX_USE of the
##          palm's reach) and back onto the sphere; beyond reach, the farthest reachable point toward the
##          tip (the visible tip then falls short of the tested one);
##   the weapon points from the grip at the tip; the hand's long axis lies GRIP_AXIS_DEG off the weapon (a
##   diagonal grip across the palm), turned toward the arm so the wrist bends least; the wrist is the
##   palm's offset back along it, pulled in along the shoulder line until the two bones reach it; an
##   analytic two-bone solve with the elbow's pole down, back and out (lifted further out on cross-body
##   arcs) places the elbow, so the palm lands exactly on the grip.
## Contract (plan §2.9): over every ACTIVE sample of every player weapon arc at stages 1, 3, 4 and 6, the
## visible weapon's outer half lies inside the tested capsule, at most MAX_ANGLE_DEG off the tested
## direction, the fist within FIST_TOLERANCE_M of its target (tests/unit/test_tip_matching.gd). A weapon
## carried past its fit stage (an unreforged club, sword or hammer at stage 4 or 6) keeps its stage-2
## length while the arm is the stage's: its tested capsule starts up to 0.28·k beyond the real hand's
## reach, so for it only the direction, the reach and the solve hold (docs/systems/P42.md).
##
## The landmarks are the exported skeleton's joints at stage 1 in the game frame: from the model's index
## (from_index; plan §2.5 "landmarks"), else DEFAULT_LANDMARKS (the animation research's lab body, read
## from its skeleton's rest pose: the brief's shoulder and reach).

const STAGE1_HEIGHT_M := 3.6576
const REACH_USE := 0.93
## 0.95, not 0.97 (the W25 merge): the exported skeleton's palm is the knuckle line (index, middle and ring
## bases; reach 1.385 = upper arm + forearm + wrist-to-knuckles), so a grip at 0.97 of that reach left the wrist
## beyond the two bones on two end-of-arc samples at stage 3 and the pull-in turned the weapon 16-17° off.
const RMAX_USE := 0.95
const PROJECTIONS := 12
const GRIP_AXIS_DEG := 41.0
const SOLVE_MARGIN := 0.999
## The resting grip (idle_grip): the hand at this share of the palm's reach along the brain's idle arm.
const IDLE_REACH_USE := 0.9
const DEFAULT_IDLE_POSE := Vector2(12.0, -78.0)   ## ActorRig.idle_arm_pose
const IDLE_POSES := {"tree": Vector2(24.0, 30.0)}  ## WeaponVisuals.TREE_IDLE_POSE (the tree and the pine)
## The elbow's pole: down, back (+Z) and out; across the body it lifts further out.
const POLES := {"r": Vector3(0.55, -0.55, 0.6), "l": Vector3(-0.55, -0.55, 0.6)}
const CROSS_POLES := {"r": Vector3(0.85, -0.25, 0.45), "l": Vector3(-0.85, -0.25, 0.45)}
## How far (stage-1 metres) across the body's middle the pole has turned fully to CROSS_POLES.
const CROSS_BLEND_M := 0.5
## The contract's bounds (plan M10 §2.9).
const MAX_ANGLE_DEG := 15.0
const FIST_TOLERANCE_M := 0.01
## The outer half of the visible weapon is measured at this many points (t = 0.5 ... 1.0).
const OUTER_HALF_SAMPLES := 6

## The animation research's lab body (its export of the kit's giant on the game_engine rig, stage 1, the
## game frame), read from the skeleton's rest pose; reach_r / reach_l are the brief's 1.385 (shoulder to
## the knuckles).
const DEFAULT_LANDMARKS := {
	"shoulder_r": Vector3(0.413946, 3.015415, -0.033233), "shoulder_l": Vector3(-0.413945, 3.015415, -0.033233),
	"elbow_r": Vector3(0.816601, 2.569926, -0.057259), "elbow_l": Vector3(-0.816601, 2.569926, -0.057258),
	"wrist_r": Vector3(1.087127, 2.306697, -0.44995), "wrist_l": Vector3(-1.087127, 2.306697, -0.44995),
	"palm_r": Vector3(1.148734, 2.226685, -0.552275), "palm_l": Vector3(-1.148733, 2.226686, -0.552275),
	"hip_r": Vector3(0.21686, 2.071284, 0.005812), "hip_l": Vector3(-0.216859, 2.071284, 0.005812),
	"knee_r": Vector3(0.281627, 1.025667, -0.057457), "knee_l": Vector3(-0.281627, 1.025667, -0.057457),
	"ankle_r": Vector3(0.372591, 0.158973, 0.005816), "ankle_l": Vector3(-0.372591, 0.158973, 0.005816),
	"eye_mid": Vector3(0.0, 3.447093, -0.244148),
	"reach_r": 1.385, "reach_l": 1.385,
}

var shoulder := {}   ## side ("r", "l") -> Vector3
var upper := {}      ## side -> upper arm length
var fore := {}       ## side -> forearm length
var hand := {}       ## side -> wrist-to-palm-centre length
var reach := {}      ## side -> the arm's reach (the natural grip's scale)
var landmarks := {}  ## the landmarks it was built from (Vector3 values)
var source := "default"


# --------------------------------------------------------------------------- building

## From the model's index: its "landmarks" when they have both shoulders, else DEFAULT_LANDMARKS.
static func from_index(index: Dictionary) -> TipMatching:
	var lm: Variant = index.get("landmarks")
	if typeof(lm) == TYPE_DICTIONARY and (lm as Dictionary).has("shoulder_r") and (lm as Dictionary).has("shoulder_l"):
		var t := from_landmarks(lm)
		t.source = "index"
		return t
	return from_landmarks(DEFAULT_LANDMARKS)


## From landmarks ({"shoulder_r": [x, y, z] or Vector3, ...}); a missing joint takes DEFAULT_LANDMARKS'.
static func from_landmarks(lm: Dictionary) -> TipMatching:
	var t := TipMatching.new()
	for key: Variant in DEFAULT_LANDMARKS:
		t.landmarks[key] = _value(lm.get(key, DEFAULT_LANDMARKS[key]), DEFAULT_LANDMARKS[key])
	for side: String in ["r", "l"]:
		var sh: Vector3 = t.landmarks["shoulder_" + side]
		var el: Vector3 = t.landmarks["elbow_" + side]
		var wr: Vector3 = t.landmarks["wrist_" + side]
		var pa: Vector3 = t.landmarks["palm_" + side]
		t.shoulder[side] = sh
		t.upper[side] = sh.distance_to(el)
		t.fore[side] = el.distance_to(wr)
		t.hand[side] = wr.distance_to(pa)
		var r := float(t.landmarks.get("reach_" + side, 0.0))
		t.reach[side] = r if r > 0.0 else float(t.upper[side]) + float(t.fore[side]) + float(t.hand[side])
	t.source = "landmarks"
	return t


static func _value(v: Variant, fallback: Variant) -> Variant:
	if typeof(fallback) == TYPE_VECTOR3:
		if typeof(v) == TYPE_VECTOR3:
			return v
		if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		return fallback
	return float(v) if SchemaUtil.is_number(v) else fallback


## The palm centre's reach from the shoulder (upper arm + forearm + hand).
func palm_reach(side := "r") -> float:
	return float(upper[side]) + float(fore[side]) + float(hand[side])


## How far from the shoulder a grip may lie (RMAX_USE of the palm's reach).
func grip_reach(side := "r") -> float:
	return RMAX_USE * palm_reach(side)


# --------------------------------------------------------------------------- the swing

## The tested swing's geometry in Body space (stage-1 metres) for a player of `profile` holding `weapon`
## at `stage`, at fraction `f` of `action`'s arc tilted by `offset_deg` (the stage's arc pitch offset, or a
## vertical aim's tilt): {"pivot", "dir", "arm", "weapon", "radius", "k"} - as PlayerAttack sweeps it
## (pivot + dir × [arm, arm + weapon]), divided by k = height / 3.6576.
static func swing_geometry(profile: Dictionary, weapon: Dictionary, stage: int, action: ActionDef, f: float,
		offset_deg: float) -> Dictionary:
	var k := float(profile.get("height_m", STAGE1_HEIGHT_M)) / STAGE1_HEIGHT_M
	var p: Array = profile.get("weapon_pivot_m", [0.82, 2.9, 0.0])
	var scale := PlayerEquipment.scale_for(weapon, stage, profile)
	var ang := AttackGeometry.arc_point(action, clampf(f, 0.0, 1.0))
	return {"pivot": Vector3(float(p[0]), float(p[1]), float(p[2])) / k,
		"dir": AttackGeometry.local_direction(ang.x, ang.y + offset_deg),
		"arm": float(profile.get("arm_length_m", 1.5)) / k,
		"weapon": float(weapon.get("length_m", 1.85)) * scale / k,
		"radius": float(weapon.get("hit_radius_m", 0.45)) * scale / k, "k": k}


## Tip matching for one swing sample (Body space, stage-1 metres): the tested segment from `pivot` along
## `dir` from `arm` to `arm + weapon`. Returns {"tip", "grip", "weapon_dir", "visible_tip", "hand_dir",
## "wrist", "elbow", "palm", "fist_error", "reached" (the visible tip is the tested tip), "exact"}.
func match_swing(pivot: Vector3, dir: Vector3, arm: float, weapon: float, side := "r") -> Dictionary:
	var d := dir.normalized()
	var sh: Vector3 = shoulder[side]
	var tip := pivot + d * (arm + weapon)
	var natural := sh + d * (REACH_USE * float(reach[side]))
	var grip := tip_matched_grip(sh, tip, natural, weapon, grip_reach(side))
	var placed := _place_hand(sh, grip, tip, side)
	grip = placed.grip
	var wdir: Vector3 = placed.weapon_dir
	var hand_dir: Vector3 = placed.hand_dir
	var wrist_target: Vector3 = placed.wrist
	var arm_solve := two_bone(sh, wrist_target, float(upper[side]), float(fore[side]), pole_for(side, wrist_target))
	var palm: Vector3 = (arm_solve.end as Vector3) + hand_dir * float(hand[side])
	return {"tip": tip, "grip": grip, "weapon_dir": wdir, "visible_tip": grip + wdir * weapon, "hand_dir": hand_dir,
		"wrist": arm_solve.end, "elbow": arm_solve.elbow, "palm": palm, "fist_error": palm.distance_to(grip),
		"reached": absf(grip.distance_to(tip) - weapon) < 1e-3, "exact": bool(arm_solve.exact)}


## The grip for a weapon of `length` ending on `tip`: `natural` moved onto the sphere of radius `length`
## around the tip, then alternately projected into the reach (`rmax` from the shoulder `sh`) and back onto
## the sphere; when the sphere and the reach do not meet, the farthest reachable point toward the tip.
static func tip_matched_grip(sh: Vector3, tip: Vector3, natural: Vector3, length: float, rmax: float) -> Vector3:
	var dt := sh.distance_to(tip)
	if dt > length + rmax or dt < absf(length - rmax):
		return sh + (tip - sh).normalized() * rmax
	var away := natural - tip
	if away.length_squared() < 1e-10:
		away = sh - tip
	var v := tip + away.normalized() * length
	for i in PROJECTIONS:
		if v.distance_to(sh) <= rmax:
			break
		v = sh + (v - sh).normalized() * rmax
		v = tip + (v - tip).normalized() * length
	if v.distance_to(sh) > rmax:
		v = sh + (v - sh).normalized() * rmax   # not converged: the reach wins (the tip falls a hair short)
	return v


## The hand's long axis (wrist to palm) for a weapon along `weapon_dir`: GRIP_AXIS_DEG off the weapon, on
## the side of `toward` (the shoulder-to-grip line, so the wrist bends least); straight down (or back) when
## the two are parallel.
static func hand_axis(weapon_dir: Vector3, toward: Vector3) -> Vector3:
	var w := weapon_dir.normalized()
	var perp := toward - w * toward.dot(w)
	if perp.length_squared() < 1e-8:
		perp = Vector3.DOWN - w * Vector3.DOWN.dot(w)
	if perp.length_squared() < 1e-8:
		perp = Vector3.BACK - w * Vector3.BACK.dot(w)
	var a := deg_to_rad(GRIP_AXIS_DEG)
	return (w * cos(a) + perp.normalized() * sin(a)).normalized()


## The grip (pulled in along the shoulder line when the wrist would be beyond the two bones), the weapon's
## direction from it to the tip, the hand's axis and the wrist's target.
func _place_hand(sh: Vector3, grip_in: Vector3, tip: Vector3, side: String) -> Dictionary:
	var h := float(hand[side])
	var l := (float(upper[side]) + float(fore[side])) * SOLVE_MARGIN
	var grip := grip_in
	var wdir := (tip - grip).normalized()
	var hand_dir := hand_axis(wdir, (grip - sh).normalized())
	var wrist := grip - hand_dir * h
	for i in 4:
		if sh.distance_to(wrist) <= l + 1e-6:
			break
		# |sh->grip| = r along e; wrist = sh + e r - u h, so |sh->wrist|^2 = r^2 + h^2 - 2 r h (u.e) = l^2.
		var e := (grip - sh).normalized()
		var c := hand_dir.dot(e)
		var r := h * c + sqrt(maxf(0.0, l * l - h * h * (1.0 - c * c)))
		grip = sh + e * minf(r, sh.distance_to(grip))
		wdir = (tip - grip).normalized()
		hand_dir = hand_axis(wdir, e)
		wrist = grip - hand_dir * h
	return {"grip": grip, "weapon_dir": wdir, "hand_dir": hand_dir, "wrist": wrist}


## The elbow's pole for the arm of `side` reaching `target`: POLES, turned toward CROSS_POLES as the target
## crosses the body's middle (x < 0 for the right arm).
func pole_for(side: String, target: Vector3) -> Vector3:
	var across := -target.x if side == "r" else target.x
	var t := clampf(across / CROSS_BLEND_M, 0.0, 1.0)
	return (POLES[side] as Vector3).lerp(CROSS_POLES[side], t).normalized()


## The analytic two-bone solve (the law of cosines): from the shoulder `sh`, bones of `l1` and `l2`, the end
## on `target` (clamped into what the bones reach), the elbow toward `pole`. {"elbow", "end", "exact"}.
static func two_bone(sh: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Dictionary:
	var d := target - sh
	var lo := absf(l1 - l2) * 1.001 + 1e-4
	var hi := (l1 + l2) * SOLVE_MARGIN
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
	var end := sh + dn * dist
	return {"elbow": sh + dn * a + pv * h, "end": end, "exact": end.distance_to(target) < 1e-4}


# --------------------------------------------------------------------------- the resting grip

## The resting grip of a weapon `family` (the creator's preview; P44): the hand IDLE_REACH_USE of the palm's
## reach along the brain's idle arm (the tree and the pine on their carrying pose), the wrist straight, the
## weapon GRIP_AXIS_DEG off the hand toward the front (the tree's trunk toward the sky). {"grip",
## "weapon_dir", "hand_dir", "wrist", "elbow", "palm", "exact"} in Body space.
func idle_grip(family: String, side := "r") -> Dictionary:
	var pose: Vector2 = IDLE_POSES.get(family, DEFAULT_IDLE_POSE)
	var dir := AttackGeometry.local_direction(pose.x, pose.y)
	if side == "l":
		dir.x = -dir.x
	var sh: Vector3 = shoulder[side]
	var h := float(hand[side])
	var grip := sh + dir * (IDLE_REACH_USE * palm_reach(side))
	var hand_dir := dir
	var toward := Vector3.UP if family == "tree" else Vector3.FORWARD
	var perp := toward - hand_dir * toward.dot(hand_dir)
	if perp.length_squared() < 1e-8:
		perp = Vector3.FORWARD
	var a := deg_to_rad(GRIP_AXIS_DEG)
	var wdir := (hand_dir * cos(a) + perp.normalized() * sin(a)).normalized()
	var wrist := grip - hand_dir * h
	var solve := two_bone(sh, wrist, float(upper[side]), float(fore[side]), pole_for(side, wrist))
	return {"grip": grip, "weapon_dir": wdir, "hand_dir": hand_dir, "wrist": solve.end, "elbow": solve.elbow,
		"palm": (solve.end as Vector3) + hand_dir * h, "exact": bool(solve.exact)}


# --------------------------------------------------------------------------- the contract's measures

## The tested segment [near end, tip] in Body space.
static func tested_segment(pivot: Vector3, dir: Vector3, arm: float, weapon: float) -> PackedVector3Array:
	var d := dir.normalized()
	return PackedVector3Array([pivot + d * arm, pivot + d * (arm + weapon)])


## The farthest the visible weapon's outer half (from grip + dir × length / 2 to its tip) strays from the
## tested segment a-b, sampled at OUTER_HALF_SAMPLES points.
static func outer_half_deviation(grip: Vector3, weapon_dir: Vector3, length: float, a: Vector3, b: Vector3) -> float:
	var worst := 0.0
	for i in OUTER_HALF_SAMPLES:
		var t := 0.5 + 0.5 * float(i) / float(OUTER_HALF_SAMPLES - 1)
		var q := grip + weapon_dir.normalized() * (length * t)
		worst = maxf(worst, q.distance_to(Geometry3D.get_closest_point_to_segment(q, a, b)))
	return worst


## The angle (degrees) between two directions.
static func angle_deg(u: Vector3, v: Vector3) -> float:
	return rad_to_deg(u.normalized().angle_to(v.normalized()))
