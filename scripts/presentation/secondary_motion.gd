class_name SecondaryMotion
extends SkeletonModifier3D
## Secondary motion (P50; plan M11 §2.3, decision 8, probe 4): the giant's hair, beard, braids and cape swing on
## the leaf chains P48 added to the skeleton (the index's `chains`: `hair`, `hair_l`, `hair_r` and `beard` under
## `head`; `cape_c`, `cape_l`, `cape_r` under `spine_03`). One object per model, a run-time child of its
## Skeleton3D made by SkinnedRig when the skinned layers are on (never saved, never headless):
##
##   Skeleton3D
##   ├ PoseBrainModifier       the brain's arms, spine and weapon (P43)
##   ├ SpringBoneSimulator3D   the engine's springs, one setting a chain the look uses ("Springs")
##   │ ├ Head  (SpringBoneCollisionSphere3D on `head`)      for the side locks and the beard
##   │ └ Chest (SpringBoneCollisionCapsule3D on `spine_03`) for the back hair and the beard
##   └ SecondaryMotion         this: the chains' angle limits, after the springs
##
## A chain runs only while a shown mesh hangs on it (the index's `meshes[id].chains`): none for the crop, the
## short beard and no cape (configure()). The springs' stiffness, drag and gravity start from the index's
## values with this package's tuning on top (TUNING; FOLLOWUPS: the next asset writer moves them into the
## index), and every joint is held within the chain's `max_deg` of the pose its parent carries it in - the
## hair off the shoulders, the beard off the chest - and a cape joint swings at most CAPE_FRONT_DEG toward the
## giant's front, so it never cuts into the legs (probe 4: colliders only where a chain can reach them; the
## springs have no angle limits of their own). The springs' state resets (reset()) on a teleport, a respawn,
## a growth and a look change: without it a teleport throws every chain out to 90 degrees (probe 4).
##
## Presentation only: it moves leaf bones no mesh but hair, beards and the cape hangs on, reads nothing of the
## simulation and writes nothing outside its skeleton. M10's shader sway (GiantLook.sway) stays for the cards'
## tips.

## Tuning in play over the index's starting values (P50; probe 4: lift the cape less with more gravity, not
## more drag, which only slows the settle). By chain kind; a key left out keeps the index's value.
const TUNING := {
	"hair": {"stiffness": 3.0, "drag": 0.5, "gravity": 0.8},
	"beard": {"stiffness": 3.0, "drag": 0.5, "gravity": 0.6},
	"cape": {"stiffness": 1.2, "drag": 0.5, "gravity": 2.5},
}
## A cape joint swings at most this far toward the giant's front from where its parent carries it (degrees).
const CAPE_FRONT_DEG := 6.0
## The fastest a joint turns against its parent (degrees a second): an instant change of speed (Shoulder Charge's
## dash starts at 26 m/s and stops dead) would otherwise whip a chain from one side of its limit to the other in
## a single frame.
const MAX_TURN_DEG_S := 720.0
## The springs' joint radius (stage-1 metres in the skeleton's space) and the colliders.
const JOINT_RADIUS := 0.02
const HEAD_RADIUS := 0.13
const CHEST_RADIUS := 0.2
const CHEST_HEIGHT := 0.62
## The chains that collide with the head sphere and the chest capsule (the cape hangs off spine_03 behind the
## back and its limits keep it there: no collider).
const COLLIDES := {"hair_l": ["Head"], "hair_r": ["Head"], "beard": ["Chest"]}

## The run's counts over every SecondaryMotion of the process (SKIN_STATS: secondary_frames).
static var totals := {"frames": 0, "resets": 0, "limited": 0, "builds": 0}

var springs: SpringBoneSimulator3D = null
## The chains running now (ids of the index's `chains`).
var chains: PackedStringArray = PackedStringArray()
## This object's counts and the last pass's numbers: "us" (microseconds of this limiter), "worst_deg" (the
## largest joint angle from its carried pose before the limit), "limited" (joints the limit moved).
var frames := 0
var resets := 0
var stats := {}

var _index: Dictionary = {}
var _joints: Array = []   # [{"bone", "parent", "axis" (local, toward the child), "rest" (local), "max", "cape", "chain"}]
## The same joints as packed arrays for the per-frame pass (Gate A, lens 6: no Dictionary read a joint a frame), and
## each joint's last limited direction in its parent's frame ("prev"; _has_prev 0 after a reset).
var _j_bone := PackedInt32Array()
var _j_parent := PackedInt32Array()
var _j_axis := PackedVector3Array()
var _j_rest: Array[Basis] = []
var _j_max := PackedFloat64Array()
var _j_cape := PackedByteArray()
var _j_prev := PackedVector3Array()
var _has_prev := PackedByteArray()
var _front_skel := Vector3.BACK
var _colliders := {}


## Puts a SecondaryMotion (and its springs) under `skeleton` after every modifier already there; `front` is the
## giant's front in the skeleton's space. Runs no chain until configure().
static func attach(skeleton: Skeleton3D, index: Dictionary, front: Vector3) -> SecondaryMotion:
	var sm := SecondaryMotion.new()
	sm.name = "SecondaryMotion"
	sm._index = index
	sm._front_skel = front.normalized() if front.length_squared() > 1e-8 else Vector3.BACK
	sm.springs = SpringBoneSimulator3D.new()
	sm.springs.name = "Springs"
	skeleton.add_child(sm.springs)
	skeleton.add_child(sm)
	sm._make_colliders(skeleton)
	totals["builds"] = int(totals.get("builds", 0)) + 1
	return sm


static func reset_for_tests() -> void:
	totals = {"frames": 0, "resets": 0, "limited": 0, "builds": 0}


## The chains the meshes `shown` hang on (the index's `meshes[id].chains`), sorted.
static func chains_for(index: Dictionary, shown: Array) -> PackedStringArray:
	var found := {}
	var meshes: Dictionary = index.get("meshes", {})
	var known: Dictionary = index.get("chains", {})
	for id: Variant in shown:
		var e: Variant = meshes.get(str(id))
		if typeof(e) != TYPE_DICTIONARY:
			continue
		for c: Variant in (e as Dictionary).get("chains", []):
			if known.has(str(c)):
				found[str(c)] = true
	var out := PackedStringArray(found.keys())
	out.sort()
	return out


## A chain's spring values: the index's, with TUNING for its kind on top.
static func chain_values(index: Dictionary, chain_id: String) -> Dictionary:
	var c: Dictionary = (index.get("chains", {}) as Dictionary).get(chain_id, {})
	var out := {"stiffness": float(c.get("stiffness", 1.0)), "drag": float(c.get("drag", 0.4)),
		"gravity": float(c.get("gravity", 0.6)), "max_deg": float(c.get("max_deg", 40.0)), "kind": str(c.get("kind", "hair")),
		"bones": c.get("bones", []), "length_m": float(c.get("length_m", 0.3))}
	var t: Dictionary = TUNING.get(out.kind, {})
	for key: String in t:
		out[key] = float(t[key])
	return out


## Runs the springs on `chain_ids` (and only those) and resets them; [] runs none.
func configure(chain_ids: PackedStringArray) -> void:
	var sk := get_skeleton()
	if sk == null or springs == null:
		return
	chains = PackedStringArray()
	_joints.clear()
	_j_bone.clear()
	_j_parent.clear()
	_j_axis.clear()
	_j_rest.clear()
	_j_max.clear()
	_j_cape.clear()
	_j_prev.clear()
	_has_prev.clear()
	springs.clear_settings()
	var ids: Array = Array(chain_ids)
	ids.sort()
	var settings: Array = []
	for cid: String in ids:
		var v := chain_values(_index, cid)
		var bones: Array = v.bones
		if bones.is_empty():
			continue
		var ok := true
		for b: Variant in bones:
			ok = ok and sk.find_bone(str(b)) >= 0
		if not ok:
			push_warning("SecondaryMotion: the skeleton lacks a bone of chain %s" % cid)
			continue
		settings.append([cid, v])
	springs.set_setting_count(settings.size())
	for i in settings.size():
		var cid: String = settings[i][0]
		var v: Dictionary = settings[i][1]
		var bones: Array = v.bones
		springs.set_root_bone_name(i, str(bones[0]))
		springs.set_end_bone_name(i, str(bones[-1]))
		springs.set_extend_end_bone(i, true)
		springs.set_end_bone_direction(i, SpringBoneSimulator3D.BONE_DIRECTION_FROM_PARENT)
		springs.set_end_bone_length(i, float(v.length_m) / float(bones.size()))
		springs.set_stiffness(i, float(v.stiffness))
		springs.set_drag(i, float(v.drag))
		springs.set_gravity(i, float(v.gravity))
		springs.set_gravity_direction(i, Vector3.DOWN)
		springs.set_radius(i, JOINT_RADIUS)
		springs.set_enable_all_child_collisions(i, false)
		var cols: Array = COLLIDES.get(cid, [])
		springs.set_collision_count(i, cols.size())
		for j in cols.size():
			springs.set_collision_path(i, j, springs.get_path_to(_colliders[cols[j]]))
		chains.append(cid)
		_add_joints(sk, cid, v)
	springs.active = not chains.is_empty()
	active = not chains.is_empty()
	reset()


## Starts every running chain at rest where the skeleton stands now (teleports, respawns, growth, a new look).
func reset() -> void:
	if springs != null and not chains.is_empty():
		springs.reset()
	_has_prev.fill(0)
	resets += 1
	totals["resets"] = int(totals.get("resets", 0)) + 1


func _make_colliders(sk: Skeleton3D) -> void:
	var head := SpringBoneCollisionSphere3D.new()
	head.name = "Head"
	head.radius = HEAD_RADIUS
	springs.add_child(head)
	head.bone_name = "head"
	head.position_offset = Vector3(0.0, 0.1, 0.0)
	var chest := SpringBoneCollisionCapsule3D.new()
	chest.name = "Chest"
	chest.radius = CHEST_RADIUS
	chest.height = CHEST_HEIGHT
	springs.add_child(chest)
	chest.bone_name = "spine_03"
	chest.position_offset = Vector3(0.0, 0.08, 0.0)
	# the capsule lies across the chest, from shoulder to shoulder
	chest.rotation_offset = Quaternion(Vector3.FORWARD, PI * 0.5)
	_colliders = {"Head": head, "Chest": chest}
	if sk.find_bone("head") < 0 or sk.find_bone("spine_03") < 0:
		push_warning("SecondaryMotion: the skeleton has no head or spine_03 for the colliders")


func _add_joints(sk: Skeleton3D, cid: String, v: Dictionary) -> void:
	var bones: Array = v.bones
	var last_axis := Vector3.UP
	for k in bones.size():
		var b := sk.find_bone(str(bones[k]))
		var axis := last_axis
		if k + 1 < bones.size():
			var child := sk.find_bone(str(bones[k + 1]))
			var o := sk.get_bone_rest(child).origin
			if o.length_squared() > 1e-10:
				axis = o.normalized()
		last_axis = axis
		_joints.append({"bone": b, "parent": sk.get_bone_parent(b), "axis": axis, "rest": sk.get_bone_rest(b),
			"max": deg_to_rad(float(v.max_deg)), "cape": str(v.kind) == "cape", "chain": cid})
		_j_bone.append(b)
		_j_parent.append(sk.get_bone_parent(b))
		_j_axis.append(axis)
		_j_rest.append(sk.get_bone_rest(b).basis)
		_j_max.append(deg_to_rad(float(v.max_deg)))
		_j_cape.append(1 if str(v.kind) == "cape" else 0)
		_j_prev.append(Vector3.ZERO)
		_has_prev.append(0)


## The angle limits after the springs (see the class notes), root to tip so each joint is judged where its
## parent now carries it.
func _process_modification_with_delta(_delta: float) -> void:
	if chains.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var sk := get_skeleton()
	frames += 1
	totals["frames"] = int(totals.get("frames", 0)) + 1
	var worst := 0.0
	var limited := 0
	var front_lim := deg_to_rad(CAPE_FRONT_DEG)
	var max_step := deg_to_rad(MAX_TURN_DEG_S) * maxf(_delta, 1.0 / 240.0)
	for i in _j_bone.size():
		var b := _j_bone[i]
		var gp := sk.get_bone_global_pose(b)
		var parent := _j_parent[i]
		var parent_gp := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
		var axis := _j_axis[i]
		var carried := (parent_gp.basis * _j_rest[i] * axis).normalized()
		var d := (gp.basis * axis).normalized()
		var ang := carried.angle_to(d)
		worst = maxf(worst, ang)
		var want := d
		var jmax := _j_max[i]
		if ang > jmax:
			want = carried.slerp(d, jmax / ang).normalized()
		if _j_cape[i] == 1:
			var f := _front_skel - carried * _front_skel.dot(carried)
			if f.length_squared() > 1e-8:
				f = f.normalized()
				var tilt := atan2(want.dot(f), want.dot(carried))
				if tilt > front_lim:
					var side := carried.cross(f).normalized()
					want = want.rotated(side, front_lim - tilt).normalized()
		if _has_prev[i] == 1:
			var before := (parent_gp.basis * _j_prev[i]).normalized()
			var step := before.angle_to(want)
			if step > max_step:
				want = before.slerp(want, max_step / step).normalized()
		_j_prev[i] = (parent_gp.basis.inverse() * want).normalized()
		_has_prev[i] = 1
		if want.angle_to(d) > 1e-5:
			limited += 1
			gp.basis = Basis(Quaternion(d, want)) * gp.basis
			sk.set_bone_global_pose(b, gp)
	totals["limited"] = int(totals.get("limited", 0)) + limited
	stats["worst_deg"] = rad_to_deg(worst)
	stats["limited"] = limited
	stats["us"] = Time.get_ticks_usec() - t0


## Each running joint's angle (degrees) from the pose its parent carries it in now, and the cape joints'
## tilt toward the front: {"<bone>": [angle, front tilt]} (tests; valid inside SkinnedRig.posed).
func joint_angles() -> Dictionary:
	var out := {}
	var sk := get_skeleton()
	if sk == null:
		return out
	for j: Dictionary in _joints:
		var gp := sk.get_bone_global_pose(int(j.bone))
		var parent_gp := sk.get_bone_global_pose(int(j.parent)) if int(j.parent) >= 0 else Transform3D.IDENTITY
		var carried := (parent_gp.basis * (j.rest as Transform3D).basis * (j.axis as Vector3)).normalized()
		var d := (gp.basis * (j.axis as Vector3)).normalized()
		var f := _front_skel - carried * _front_skel.dot(carried)
		var tilt := atan2(d.dot(f.normalized()), d.dot(carried)) if f.length_squared() > 1e-8 else 0.0
		out[sk.get_bone_name(int(j.bone))] = [rad_to_deg(carried.angle_to(d)), rad_to_deg(tilt)]
	return out


## The limits of the running joints: {"<bone>": max_deg} (tests).
func joint_limits() -> Dictionary:
	var out := {}
	var sk := get_skeleton()
	for j: Dictionary in _joints:
		out[sk.get_bone_name(int(j.bone)) if sk != null else str(j.bone)] = rad_to_deg(float(j.max))
	return out
