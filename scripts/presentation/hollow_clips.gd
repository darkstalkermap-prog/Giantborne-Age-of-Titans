class_name HollowClips
extends RefCounted
## E3: the Hollow Titan's own clips (decision E3-1), made when his model is: key poses (where the feet stand, where the
## sword's grip is and which way its blade points, where the left hand is, how the spine, neck and head bend, how far the
## hips drop) solved onto the Stormcaller's 23 bones - the legs and arms by two-bone IK with a knee or elbow pole, the
## sword hand turned so the blade points where the key says - eased between keys and baked at FPS into an
## AnimationLibrary (LIBRARY) beside the Stormcaller's. No file: the library is plain numbers. His walk, run, reel,
## kneel and rise, and the cleave, reap, thrust, lash and call are the Stormcaller's (the rod held as a sword); these
## are his own:
##   idle     (3.0, a loop) the king's stance: the feet set wide, the Kingsword held up before his right shoulder, the
##            shell swaying a little, as a thing hung on chains sways
##   dormant  (4.0, a loop) his vigil: down on his right knee, both hands on the pommel of the Kingsword planted point-down
##            before him, the helm bowed over it
##   wake     (3.6) he lifts his head, rises and draws the sword out of the ground, lifts it and settles into his stance
##   draw     (2.4) his arms drawn in across his breast, then flung wide and back, his breast thrust out (the chains lash
##            out of it: DRAW_HIT), held while they haul, then back
##   embrace  (1.85) he stoops and swings his arms wide, then closes them low before him (EMBRACE_HIT)
##   echo     (2.75) the sword raised two-handed high, point down, and driven into the ground before him (ECHO_HIT); the
##            shell rings; he pulls it out
##   death    (3.0) the knees go, the arms hang, he sinks onto his knees and his helm drops - then his harness comes apart
##            (HollowRig: the pieces fall from the bones)
## Model space: the Stormcaller's (34 m, facing +Z, his left +X). Presentation only.

const LIBRARY := &"hollow"
const FPS := 30.0
const DRAW_HIT := 1.5
const EMBRACE_HIT := 0.95
const ECHO_HIT := 1.6
## The strikes' keys [start, wound, hit, past, end] (HollowRig reads them as the Stormcaller's manifest keys are read).
const KEYS := {"draw": [0.0, 1.4, DRAW_HIT, 1.7, 2.4], "embrace": [0.0, 0.6, EMBRACE_HIT, 1.1, 1.85],
	"echo": [0.0, 1.4, ECHO_HIT, 1.75, 2.75]}
const LOOPS := ["idle", "dormant"]
const BONES := ["Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l",
	"lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_r", "calf_r", "foot_r", "ball_r"]

## The stance every clip starts from and returns to (the pose's fields: see _pose()).
const STANCE := {"pelvis": Vector3(0, -0.75, -0.1), "pelvis_rot": Vector3(0, -4, 0), "spine": Vector3(3, 6, 0),
	"neck": Vector3(-2, -3, 0), "head": Vector3(-4, 0, 0),
	"foot_l": Vector3(4.0, 1.57, 1.6), "foot_r": Vector3(-4.1, 1.57, -1.4), "foot_yaw_l": 10.0, "foot_yaw_r": -18.0,
	"knee_l": Vector3(0.25, 0, 1), "knee_r": Vector3(-0.2, 0, 1),
	"grip_r": Vector3(-6.0, 19.6, 5.2), "blade_r": Vector3(0.12, 0.86, 0.5), "pole_r": Vector3(-0.6, -0.6, -0.5),
	"hand_l": Vector3(7.4, 17.6, 2.4), "pole_l": Vector3(0.5, -0.5, -0.7), "two_hand": 0.0, "clav_l": Vector3.ZERO,
	"clav_r": Vector3.ZERO}

static var _cache: Dictionary = {}


## Adds his library to `model`'s AnimationPlayer (made once a run: the same numbers every time).
static func install(model: HollowModel) -> void:
	if model == null or model.player == null or model.skeleton == null:
		return
	var lib: AnimationLibrary = _cache.get("lib")
	if lib == null:
		lib = AnimationLibrary.new()
		var solver := HollowClips.new(model)
		for name: String in clips():
			lib.add_animation(StringName(name), solver.bake(name))
		_cache["lib"] = lib
	if not model.player.has_animation_library(LIBRARY):
		model.player.add_animation_library(LIBRARY, lib)


static func clips() -> PackedStringArray:
	return PackedStringArray(["idle", "dormant", "wake", "draw", "embrace", "echo", "death"])


static func has(model: StormcallerModel, name: String) -> bool:
	return model != null and model.player != null and model.player.has_animation(StringName(String(LIBRARY) + "/" + name))


static func length_of(model: StormcallerModel, name: String) -> float:
	if not has(model, name):
		return 0.0
	return model.player.get_animation(StringName(String(LIBRARY) + "/" + name)).length


## The keys: [time s, pose (fields over STANCE), ease ("io" in-out, "in", "out", "lin")].
static func keys_of(name: String) -> Array:
	var vigil := {"pelvis": Vector3(0, -9.0, -1.4), "pelvis_rot": Vector3(4, 0, 0), "spine": Vector3(12, 0, 0),
		"neck": Vector3(10, 0, 0), "head": Vector3(22, 0, 0),
		"foot_l": Vector3(3.2, 1.57, 6.2), "foot_r": Vector3(-2.7, 1.0, -9.4), "foot_yaw_l": 6.0, "foot_yaw_r": 0.0,
		"foot_pitch_r": -62.0, "knee_l": Vector3(0.1, 0.4, 1), "knee_r": Vector3(0, -0.4, 1),
		"grip_r": Vector3(-0.4, 17.6, 8.6), "blade_r": Vector3(0, -1, 0.04), "pole_r": Vector3(-1, -0.4, -0.4),
		"hand_l": Vector3(0.5, 19.0, 8.6), "pole_l": Vector3(1, -0.4, -0.4), "two_hand": 0.0,
		"clav_l": Vector3(0, 0, -6), "clav_r": Vector3(0, 0, 6)}
	match name:
		"idle":
			var sway := STANCE.duplicate()
			sway["spine"] = Vector3(4.2, 6.5, 1.2)
			sway["neck"] = Vector3(-1.5, -2.0, -0.8)
			sway["grip_r"] = Vector3(-6.1, 19.9, 5.3)
			sway["hand_l"] = Vector3(7.5, 17.4, 2.7)
			return [[0.0, STANCE, "io"], [1.5, sway, "io"], [3.0, STANCE, "io"]]
		"dormant":
			var still := vigil.duplicate()
			still["head"] = Vector3(24, 1.5, 0)
			still["spine"] = Vector3(13, 0, 0.6)
			return [[0.0, vigil, "io"], [2.0, still, "io"], [4.0, vigil, "io"]]
		"wake":
			var lift := vigil.duplicate()
			lift["head"] = Vector3(-6, 0, 0)
			lift["neck"] = Vector3(0, 0, 0)
			lift["spine"] = Vector3(4, 0, 0)
			var rise := {"pelvis": Vector3(0, -4.6, -0.8), "pelvis_rot": Vector3(2, 0, 0), "spine": Vector3(8, 2, 0),
				"neck": Vector3(0, 0, 0), "head": Vector3(-8, 0, 0),
				"foot_l": Vector3(3.6, 1.57, 4.0), "foot_r": Vector3(-3.4, 1.57, -4.2), "foot_yaw_l": 6.0,
				"foot_pitch_r": -20.0, "knee_l": Vector3(0.1, 0.2, 1), "knee_r": Vector3(0, 0.2, 1),
				"grip_r": Vector3(-1.2, 21.5, 8.2), "blade_r": Vector3(0, -0.97, 0.2), "pole_r": Vector3(-1, -0.4, -0.4),
				"hand_l": Vector3(0.8, 22.6, 8.2), "pole_l": Vector3(1, -0.4, -0.4)}
			var up := STANCE.duplicate()
			up["grip_r"] = Vector3(-3.6, 25.5, 7.0)
			up["blade_r"] = Vector3(0.05, 0.95, 0.3)
			up["hand_l"] = Vector3(-1.4, 24.4, 7.4)
			up["two_hand"] = 1.0
			up["head"] = Vector3(-10, 0, 0)
			up["spine"] = Vector3(-4, 2, 0)
			return [[0.0, vigil, "io"], [0.9, lift, "io"], [1.9, rise, "io"], [2.8, up, "io"], [3.6, STANCE, "io"]]
		"draw":
			var gather := STANCE.duplicate()
			gather.merge({"spine": Vector3(16, 0, 0), "neck": Vector3(6, 0, 0), "head": Vector3(10, 0, 0),
				"pelvis": Vector3(0, -1.6, -0.3), "grip_r": Vector3(-1.8, 22.0, 5.8), "blade_r": Vector3(0.6, -0.7, 0.3),
				"hand_l": Vector3(2.2, 23.0, 5.6), "pole_l": Vector3(1, -0.2, -0.5), "pole_r": Vector3(-1, -0.2, -0.5),
				"clav_l": Vector3(0, -8, -4), "clav_r": Vector3(0, 8, 4)}, true)
			var fling := STANCE.duplicate()
			fling.merge({"spine": Vector3(-20, 0, 0), "neck": Vector3(-8, 0, 0), "head": Vector3(-16, 0, 0),
				"pelvis": Vector3(0, -1.2, 1.0), "pelvis_rot": Vector3(-6, 0, 0),
				"grip_r": Vector3(-9.6, 26.5, -2.6), "blade_r": Vector3(-0.55, -0.75, -0.35), "pole_r": Vector3(0, -1, -0.2),
				"hand_l": Vector3(9.8, 27.2, -2.4), "pole_l": Vector3(0, -1, -0.2),
				"clav_l": Vector3(0, 10, 8), "clav_r": Vector3(0, -10, -8)}, true)
			var haul := fling.duplicate()
			haul.merge({"spine": Vector3(-24, 0, 0), "grip_r": Vector3(-9.0, 25.0, -4.0), "hand_l": Vector3(9.2, 25.6, -3.8),
				"pelvis": Vector3(0, -1.5, 0.4)}, true)
			return [[0.0, STANCE, "io"], [0.6, gather, "io"], [1.4, fling, "out"], [1.5, fling, "lin"], [1.9, haul, "io"],
				[2.4, STANCE, "io"]]
		"embrace":
			var wide := STANCE.duplicate()
			wide.merge({"spine": Vector3(22, 0, 0), "neck": Vector3(-6, 0, 0), "head": Vector3(-10, 0, 0),
				"pelvis": Vector3(0, -2.4, -0.8), "grip_r": Vector3(-9.6, 20.5, 6.0), "blade_r": Vector3(-0.6, 0.2, 0.75),
				"hand_l": Vector3(9.6, 20.8, 6.0), "pole_l": Vector3(0.6, 0.2, -1), "pole_r": Vector3(-0.6, 0.2, -1),
				"foot_l": Vector3(4.6, 1.57, 2.4), "foot_r": Vector3(-4.6, 1.57, -1.2)}, true)
			var close := wide.duplicate()
			close.merge({"spine": Vector3(40, 0, 0), "neck": Vector3(-12, 0, 0), "head": Vector3(-14, 0, 0),
				"pelvis": Vector3(0, -4.4, -2.2), "grip_r": Vector3(-1.6, 12.6, 9.8), "blade_r": Vector3(0.85, -0.1, -0.5),
				"hand_l": Vector3(1.8, 12.8, 9.6), "pole_l": Vector3(1, 0.3, -0.3), "pole_r": Vector3(-1, 0.3, -0.3)}, true)
			return [[0.0, STANCE, "io"], [0.6, wide, "io"], [0.95, close, "in"], [1.1, close, "lin"], [1.85, STANCE, "io"]]
		"echo":
			var high := STANCE.duplicate()
			high.merge({"spine": Vector3(-10, 0, 0), "neck": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0),
				"pelvis": Vector3(0, -0.4, 0), "grip_r": Vector3(-0.8, 34.5, 5.2), "blade_r": Vector3(0, -0.9, 0.42),
				"hand_l": Vector3(0.6, 33.2, 5.0), "two_hand": 1.0, "pole_l": Vector3(1, 0, -0.3),
				"pole_r": Vector3(-1, 0, -0.3)}, true)
			var drive := high.duplicate()
			drive.merge({"spine": Vector3(26, 0, 0), "neck": Vector3(4, 0, 0), "head": Vector3(6, 0, 0),
				"pelvis": Vector3(0, -3.6, -1.2), "grip_r": Vector3(-0.6, 16.6, 10.6), "blade_r": Vector3(0, -1, 0.1),
				"pole_l": Vector3(1, -0.2, -0.5), "pole_r": Vector3(-1, -0.2, -0.5),
				"foot_l": Vector3(4.4, 1.57, 3.2), "foot_r": Vector3(-4.2, 1.57, -2.2)}, true)
			return [[0.0, STANCE, "io"], [1.4, high, "io"], [1.6, drive, "in"], [1.75, drive, "lin"], [2.75, STANCE, "io"]]
		"death":
			var sag := STANCE.duplicate()
			sag.merge({"pelvis": Vector3(0, -3.0, -0.6), "spine": Vector3(14, 3, 3), "neck": Vector3(10, 0, 0),
				"head": Vector3(18, 0, 6), "grip_r": Vector3(-6.4, 14.8, 4.6), "blade_r": Vector3(-0.3, -0.6, 0.75),
				"hand_l": Vector3(6.2, 15.0, 2.4), "knee_l": Vector3(0.3, 0, 1), "knee_r": Vector3(-0.3, 0, 1)}, true)
			var kneel := vigil.duplicate()
			kneel.merge({"spine": Vector3(30, 4, 6), "neck": Vector3(16, 0, 0), "head": Vector3(30, 0, 10),
				"foot_l": Vector3(3.6, 1.0, -7.8), "foot_pitch_l": -62.0, "knee_l": Vector3(0, -0.4, 1),
				"pelvis": Vector3(0, -9.6, -2.6), "grip_r": Vector3(-6.0, 6.0, 5.0), "blade_r": Vector3(-0.5, -0.1, 0.85),
				"hand_l": Vector3(5.6, 7.0, 4.4), "pole_l": Vector3(1, 0, -0.5), "pole_r": Vector3(-1, 0, -0.5),
				"two_hand": 0.0}, true)
			return [[0.0, STANCE, "io"], [0.9, sag, "in"], [2.0, kneel, "out"], [3.0, kneel, "lin"]]
	return [[0.0, STANCE, "io"], [1.0, STANCE, "io"]]


# --------------------------------------------------------------------------- the solver

var _sk: Skeleton3D
var _rest_local: Dictionary = {}   # bone -> Transform3D
var _rest_global: Dictionary = {}
var _parent: Dictionary = {}
var _len: Dictionary = {}
var _grip_local := Vector3.ZERO
var _axis_local := Vector3.UP


func _init(model: HollowModel) -> void:
	_sk = model.skeleton
	for b: String in BONES:
		var i := _sk.find_bone(b)
		if i < 0:
			continue
		_rest_local[b] = _sk.get_bone_rest(i)
		_rest_global[b] = _sk.get_bone_global_rest(i)
		var p := _sk.get_bone_parent(i)
		_parent[b] = _sk.get_bone_name(p) if p >= 0 else ""
	for pair: Array in [["upperarm_l", "lowerarm_l"], ["lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r"],
			["lowerarm_r", "hand_r"], ["thigh_l", "calf_l"], ["calf_l", "foot_l"], ["thigh_r", "calf_r"], ["calf_r", "foot_r"]]:
		_len[pair[0]] = ((_rest_global[pair[1]] as Transform3D).origin - (_rest_global[pair[0]] as Transform3D).origin).length()
	var rod: Dictionary = (StormcallerModel.entry().get("pieces", {}) as Dictionary).get("rod", {})
	var hl: Array = rod.get("head_local", [7.3, 7.4, 13.8])
	var bl: Array = rod.get("butt_local", [-9.4, -3.5, -15.8])
	var head := Vector3(float(hl[0]), float(hl[1]), float(hl[2]))
	var butt := Vector3(float(bl[0]), float(bl[1]), float(bl[2]))
	_axis_local = (head - butt).normalized()
	_grip_local = butt + _axis_local * (Vector3(0, 1.3, 0) - butt).dot(_axis_local)


## Bakes clip `name`: its keys eased into a pose a frame, solved, written as rotation tracks (and the pelvis's position).
func bake(name: String) -> Animation:
	var keys := keys_of(name)
	var anim := Animation.new()
	var length := float((keys[keys.size() - 1] as Array)[0])
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if name in LOOPS else Animation.LOOP_NONE
	var tracks := {}
	for b: String in BONES:
		if b == "Root":
			continue
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton3D:" + b))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		tracks[b] = t
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton3D:pelvis"))
	var frames := int(round(length * FPS))
	for f in frames + 1:
		var time := minf(float(f) / FPS, length)
		var pose := _pose_at(keys, time)
		var locals := solve(pose)
		for b: String in tracks:
			anim.rotation_track_insert_key(int(tracks[b]), time, (locals[b] as Transform3D).basis.get_rotation_quaternion())
		anim.position_track_insert_key(pos_track, time, (locals["pelvis"] as Transform3D).origin)
	return anim


static func _ease(t: float, kind: String) -> float:
	match kind:
		"in":
			return t * t
		"out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"lin":
			return t
	return t * t * (3.0 - 2.0 * t)


## The pose at `time`: the fields of the key before and after, eased (the next key's ease).
static func _pose_at(keys: Array, time: float) -> Dictionary:
	var i := 0
	while i < keys.size() - 2 and float((keys[i + 1] as Array)[0]) < time:
		i += 1
	var k0: Array = keys[i]
	var k1: Array = keys[mini(i + 1, keys.size() - 1)]
	var span := maxf(float(k1[0]) - float(k0[0]), 1e-4)
	var t := _ease(clampf((time - float(k0[0])) / span, 0.0, 1.0), str(k1[2]))
	var a := STANCE.duplicate()
	a.merge(k0[1] as Dictionary, true)
	var b := STANCE.duplicate()
	b.merge(k1[1] as Dictionary, true)
	for key: String in (k0[1] as Dictionary):
		if not b.has(key):
			b[key] = (k0[1] as Dictionary)[key]
	for key: String in (k1[1] as Dictionary):
		if not a.has(key):
			a[key] = (k1[1] as Dictionary)[key]
	var out := {}
	for key: String in a:
		var va: Variant = a[key]
		var vb: Variant = b.get(key, va)
		if typeof(va) == TYPE_VECTOR3:
			out[key] = (va as Vector3).lerp(vb as Vector3, t)
		else:
			out[key] = lerpf(float(va), float(vb), t)
	return out


static func _euler(v: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)), EULER_ORDER_YXZ)


## The shortest turn taking direction `a` onto `b`.
static func _arc(a: Vector3, b: Vector3) -> Basis:
	a = a.normalized()
	b = b.normalized()
	var axis := a.cross(b)
	var s := axis.length()
	var c := a.dot(b)
	if s < 1e-6:
		if c > 0.0:
			return Basis()
		var ortho := a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP).normalized()
		return Basis(ortho, PI)
	return Basis(axis / s, atan2(s, c))


## A pose's bones: {bone: local Transform3D} (the skeleton's rest locals for what the pose does not move).
func solve(pose: Dictionary) -> Dictionary:
	var g := {}   # bone -> global (model) transform
	g["Root"] = _rest_global["Root"]
	# the pelvis: dropped and turned about its own head
	var pr: Transform3D = _rest_global["pelvis"]
	var pb := _euler(pose.get("pelvis_rot", Vector3.ZERO)) * pr.basis
	g["pelvis"] = Transform3D(pb, pr.origin + (pose.get("pelvis", Vector3.ZERO) as Vector3))
	# the spine: the bend shared out over its three bones, then the neck and the head (model-space turns at each joint)
	var spine: Vector3 = pose.get("spine", Vector3.ZERO)
	var shares := {"spine_01": 0.3, "spine_02": 0.3, "spine_03": 0.4}
	for b: String in ["spine_01", "spine_02", "spine_03"]:
		_fk(g, b, _euler(spine * float(shares[b])))
	_fk(g, "neck_01", _euler(pose.get("neck", Vector3.ZERO)))
	_fk(g, "head", _euler(pose.get("head", Vector3.ZERO)))
	_fk(g, "clavicle_l", _euler(pose.get("clav_l", Vector3.ZERO)))
	_fk(g, "clavicle_r", _euler(pose.get("clav_r", Vector3.ZERO)))
	# the legs: the ankles where the pose sets them, the knees toward their poles, the feet level (turned by yaw, pitch)
	for s: String in ["l", "r"]:
		var foot_at: Vector3 = pose.get("foot_" + s, (_rest_global["foot_" + s] as Transform3D).origin)
		_limb(g, "thigh_" + s, "calf_" + s, foot_at, pose.get("knee_" + s, Vector3.BACK))
		var turn := _euler(Vector3(float(pose.get("foot_pitch_" + s, 0.0)), float(pose.get("foot_yaw_" + s, 0.0)), 0.0))
		var fr: Transform3D = _rest_global["foot_" + s]
		g["foot_" + s] = Transform3D(turn * fr.basis, ((g["calf_" + s] as Transform3D) * (_rest_local["foot_" + s] as Transform3D)).origin)
		_fk(g, "ball_" + s, Basis())
	# the sword arm: its grip where the pose sets it, the blade along blade_r (a few passes: the hand's turn moves the
	# grip off the wrist)
	var grip: Vector3 = pose.get("grip_r", Vector3(-6, 19, 5))
	var blade: Vector3 = (pose.get("blade_r", Vector3.UP) as Vector3).normalized()
	var wrist := grip - blade * 1.4
	for _pass in 4:
		_limb(g, "upperarm_r", "lowerarm_r", wrist, pose.get("pole_r", Vector3(-1, -0.5, -0.5)))
		var h0 := (g["lowerarm_r"] as Transform3D) * (_rest_local["hand_r"] as Transform3D)
		var hb := _arc(h0.basis * _axis_local, blade) * h0.basis
		g["hand_r"] = Transform3D(hb, h0.origin)
		var got := (g["hand_r"] as Transform3D) * _grip_local
		wrist += grip - got
	# the left hand: on the grip below the right (two_hand), else where the pose sets it
	var two := float(pose.get("two_hand", 0.0))
	var lh: Vector3 = pose.get("hand_l", (_rest_global["hand_l"] as Transform3D).origin)
	if two > 0.0:
		var hr: Transform3D = g["hand_r"]
		var on_grip := hr * (_grip_local - _axis_local * 1.7) + (hr.basis * _axis_local).cross(Vector3.UP).normalized() * 0.4
		lh = lh.lerp(on_grip, two)
	_limb(g, "upperarm_l", "lowerarm_l", lh, pose.get("pole_l", Vector3(1, -0.5, -0.5)))
	var hl := (g["lowerarm_l"] as Transform3D) * (_rest_local["hand_l"] as Transform3D)
	if two > 0.0:
		var hr2: Transform3D = g["hand_r"]
		hl.basis = _arc(hl.basis * _axis_local, hr2.basis * _axis_local).slerp(Basis(), 1.0 - two) * hl.basis
	g["hand_l"] = hl
	var out := {}
	for b: String in BONES:
		if not g.has(b):
			continue
		var p := str(_parent.get(b, ""))
		out[b] = (g[p] as Transform3D).affine_inverse() * (g[b] as Transform3D) if p != "" and g.has(p) else g[b]
	return out


## A bone posed from its parent by its rest local, then turned by `turn` (model space) about its own head.
func _fk(g: Dictionary, b: String, turn: Basis) -> void:
	var p := str(_parent[b])
	var t := (g[p] as Transform3D) * (_rest_local[b] as Transform3D)
	g[b] = Transform3D(turn * t.basis, t.origin)


## A two-bone limb (upper, lower) reaching `target` with its middle joint toward `pole` (model directions).
func _limb(g: Dictionary, upper: String, lower: String, target: Vector3, pole: Vector3) -> void:
	var p := str(_parent[upper])
	var u0 := (g[p] as Transform3D) * (_rest_local[upper] as Transform3D)
	var s := u0.origin
	var a := float(_len[upper])
	var b := float(_len[lower])
	var to := target - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.01)
	var along := to.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var perp := pole - along * pole.dot(along)
	if perp.length() < 1e-4:
		perp = along.cross(Vector3.RIGHT).normalized()
	perp = perp.normalized()
	var elbow := s + along * a * cos_a + perp * a * sqrt(1.0 - cos_a * cos_a)
	var ub := _arc(u0.basis.y, elbow - s) * u0.basis
	g[upper] = Transform3D(ub, s)
	var l0 := (g[upper] as Transform3D) * (_rest_local[lower] as Transform3D)
	var end := s + along * d
	var lb := _arc(l0.basis.y, end - l0.origin) * l0.basis
	g[lower] = Transform3D(lb, l0.origin)
