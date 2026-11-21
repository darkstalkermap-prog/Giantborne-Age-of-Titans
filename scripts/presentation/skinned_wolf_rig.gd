class_name SkinnedWolfRig
extends QuadrupedRig
## The wolf and the dire wolf skinned in play (P64; plan M11 §2.10, §3.17 design 2). The brain stays: this is a
## QuadrupedRig, whose _process poses the box rig's pivots (Body, Body/Head, Body/Tail, the four legs) from the actor's
## state on the frame clock as before, counts the paw falls and keeps the flash and the status tint. Where the people
## are drawn (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never with --no-skin) and the
## record's `body.rig` is not "box", the box rig's meshes hide and P63's wolf shows:
##
##   Visual (SkinnedWolfRig)
##   └ Body                       crouches, lunges, staggers and rolls over dead as the brain says (QuadrupedRig)
##     ├ (the box rig's pivots and merged meshes, hidden)
##     ├ Wolf                     the creature's glTF (assets/creatures/wolf.glb), turned 180 degrees, at the
##     │ └ Skeleton3D             variant's size (the manifest's sizes: the wolf 1, the dire wolf 2); 25 bones driven
##     │   ├ wolf                 here (no clip): the coat (person.gdshader on the wolf's atlas, the palette's coat,
##     │   │                      marks and eyes; the tail's cards cut by alpha scissor)
##     │   └ Fur                  the fur shell (fur_shell.gdshader): the shell mesh's layers in one surface; none at
##     │                          the `low` graphics preset
##     └ Far                      the far mesh (no slot: see CreatureSlots)
##
## The gait is the horse's plan (SkinnedQuadrupedRig) made for a wolf, written here so the wolf does not move with
## the horse's tuning: each paw is in stance or in swing in the world; a planted paw stays where it landed (never a
## slide), a swing carries it on an arc to where its stance will be centred under its hip or shoulder; the timing is a
## clock blending the walk (four beats), the trot (the diagonal pairs) and the rotary gallop (the canid's: left hind,
## right hind, right fore, left fore) by speed. The wolf is the horse's dynamic similar: every length is the horse's
## times SIZE_K x the variant's size (the wolf stands half the horse's height), every speed and frequency by its
## square root (equal Froude numbers), its step a little quicker (HZ_GAIN), so the trot of 3 m/s takes about 3.1
## strides a second and the gallop of 8 m/s about 4; the shoulder blade slides with the foreleg (SCAPULA_*). The legs
## are solved in the skeleton's space: the toes as at rest (rolled over in a swing), the metapodial plumb, the upper
## and lower bones by a two-bone solve bending as at rest. The back flexes and extends with the gallop, the body bobs
## and leans into a turn.
## The attacks on the brain's clock: the bite's windup raises the head and opens the jaw (the `jaw_open` pose), the
## active phase snaps it shut as the head drops; the lunge's windup is the crouch, its dash the `lunge` pose (the
## forelegs reaching, the hind legs driving, the jaw open), the paws planted again where it lands. Dead, held by the
## scruff or thrown, the legs hang at rest under the brain's roll.
## Draw calls: the body and the fur (2); one shadow draw a cascade (the body). The slots: at most
## CreatureSlots.MAX_SKINNED brutes and wolves are skinned at once; a wolf of a pack beyond it, or farther from the
## camera than its record's render_lod_m, shows its far mesh. AI LOD tier 2 (dormant): Visual/LodProxy shows the far
## mesh. Headless, with --no-skin, or with `body.rig` "box", the box rig draws as before (the beasts' gate's fallback).
##
## Presentation only: this rig writes under its own Visual node and reads the actor; nothing in the simulation reads
## it (plan M10 §2.7).

const WOLF_NAME := "Wolf"
const FUR_NAME := "Fur"
const FAR_NAME := "Far"
const FUR_SHADER := "res://assets/shaders/fur_shell.gdshader"
const GROUP := "skinned_wolf_rigs"
const LEGS := ["fore_l", "fore_r", "hind_l", "hind_r"]
## The fur shell's layers: at `medium`; none at `low` (the Web), plan §3.17 design 3 as the brief set it.
const FUR_LAYERS := {"low": 0, "medium": 12}
## The wolf's lengths against the horse's (withers 0.8 m to 1.6 m), times the variant's size (k).
const SIZE_K := 0.5
## The gaits' phase offsets (LEGS' order): the walk's lateral sequence, the trot's diagonal pairs, the rotary gallop.
const WALK_OFF := [0.25, 0.75, 0.0, 0.5]
const TROT_OFF := [0.5, 1.0, 0.5, 1.0]
const GALLOP_OFF := [0.62, 0.5, 0.0, 0.1]
const WALK_DUTY := 0.6
const TROT_DUTY := 0.42
const GALLOP_DUTY := 0.26
const FAST_GALLOP_DUTY := 0.18
## The wolf's stride frequency over the horse's similar (see stride_hz).
const HZ_GAIN := 1.3
## The shoulder blade's slide with the foreleg (the 25 bones carry no scapula): this share of the paw's distance
## before or behind the shoulder joint, at most SCAPULA_M (at the wolf's size).
const SCAPULA_SHARE := 0.35
const SCAPULA_M := 0.07
## The gaits' speeds at the horse's size (m/s; times sqrt(k)): the walk into the trot, the trot into the gallop.
const TROT_FROM := Vector2(1.6, 2.4)
const GALLOP_FROM := Vector2(6.0, 9.0)
const FAST_MPS := 14.0
const STAND_MPS := 0.2
## A swing's paw lift at the walk, the trot and the gallop (m at the horse's size; the hind paws HIND_LIFT of it).
const LIFT := Vector3(0.1, 0.18, 0.26)
const HIND_LIFT := 0.85
## The wrist's and the hock's fold in a swing (degrees: the metapodial's tilt, the toes' further fold).
const FORE_FOLD := Vector2(70.0, 45.0)
const HIND_FOLD := Vector2(-30.0, 40.0)
const REACH_FORE_M := 0.42
const REACH_HIND_M := 0.48
const FORE_AHEAD_M := 0.06
const SETTLE_M := 0.1
const STEP_S := 0.3
## The body's bob (m) and the back's flexion (degrees) at the walk, the trot and the gallop.
const BOB := Vector3(0.012, 0.02, 0.035)
const FLEX_DEG := Vector3(0.0, 1.5, 9.0)
const LEAN_MAX_DEG := 16.0
const NOD_DEG := Vector3(3.0, 2.0, 5.0)
const TELEPORT_M := 3.0
## The jaw: opened in a bite's windup, snapped shut in its active phase; the lunge's pose weight's rate.
const JAW_RATE := 14.0
const LUNGE_RATE := 10.0

static var _fur_meshes: Dictionary = {}   # layers -> ArrayMesh
static var _poses: Dictionary = {}        # pose -> {bone: Quaternion}

var skinned := false
var _mode := -1
var _pending_lod := 0.0
var _variant := "wolf"
var _size := 1.0
var _k := 0.5
var _wolf: Node3D = null
var _sk: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _fur: MeshInstance3D = null
var _far: MeshInstance3D = null
var _material: ShaderMaterial = null
var _fur_material: ShaderMaterial = null
var _bones := {}
var _rest_global := {}
var _legs := {}
var _phase := 0.0
var _speed := 0.0
var _vel := Vector3.ZERO
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _lean := 0.0
var _w_trot := 0.0
var _w_gallop := 0.0
var _w_lunge := 0.0
var _jaw := 0.0
var _feet := {}
var _slot := false
var _frozen := false
var _slot_applied := false
## P64b: the bones' rest rotations, the legs' bones, the bones the shoulder's slide moves; the legs' last solve
## (the skeleton's place, each paw's) for _legs_unchanged.
var _rest_rot: Array[Quaternion] = []
var _leg_bone := {}
var _slid_bones: Array[int] = []
var _legs_solved := false
var _half_skip := false
var _half_dt := 0.0
var _legs_xf := Transform3D()
var _legs_at := {}
## Frames posed skinned (tests, stats); of them, frames whose legs kept their last solve (standing).
var skinned_frames := 0
var kept_leg_frames := 0
## The largest slide of a planted paw seen this life (m; tests).
var max_planted_slide := 0.0
## The most a standing leg's solve fell short of its paw (m; tests).
var max_reach_miss := 0.0


# --------------------------------------------------------------------------- setup

func _enter_tree() -> void:
	CreatureSlots.register(self)
	add_to_group(GROUP)


func _exit_tree() -> void:
	CreatureSlots.unregister(self)


func set_render_lod(lod_m: float) -> void:
	_pending_lod = maxf(0.0, lod_m)
	if _mode == 1:
		render_lod_m = _pending_lod
	else:
		super.set_render_lod(lod_m)


## The fur shell's layers at the graphics preset in effect (0 at `low`).
static func fur_layers() -> int:
	var q := "medium"
	var settings: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings") \
		if Engine.get_main_loop() is SceneTree else null
	if settings != null and "graphics_quality" in settings:
		q = str(settings.get("graphics_quality"))
	return int(FUR_LAYERS.get(q, FUR_LAYERS.medium))


func _decide() -> void:
	var rec: Variant = actor.get("record") if actor != null and "record" in actor else null
	if typeof(rec) != TYPE_DICTIONARY or (rec as Dictionary).is_empty():
		return
	var body_key: Dictionary = (rec as Dictionary).get("body", {}) if typeof((rec as Dictionary).get("body")) == TYPE_DICTIONARY else {}
	var want := str(body_key.get("rig", "skinned")) != "box" and str(body_key.get("creature", "")) == "wolf"
	_mode = 1 if want and PersonRig.layers_enabled() and _build(body_key) else 0
	skinned = _mode == 1
	if not skinned:
		return
	RigPaint.apply_render_lod(self, body, 0.0)
	far_proxy = null
	if mid_proxy != null:
		RigPaint.remove_mid_lod(body, render_lod_m)
		mid_proxy = null
	render_lod_m = _pending_lod
	for c in body.get_children():
		if c == _wolf or c == _far:
			continue
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false
		elif c is Node3D:
			for g in (c as Node3D).find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visible = false
	var proxy := get_node_or_null("LodProxy") as MeshInstance3D
	if proxy != null and _far.mesh != null:
		proxy.mesh = _far.mesh
		proxy.material_override = _material
		proxy.transform = _wolf.transform


func _build(body_key: Dictionary) -> bool:
	var w: Dictionary = SkinnedQuadrupedRig.creature_index().get("wolf", {})
	if w.is_empty() or not ResourceLoader.exists(str(w.get("scene", ""))):
		return false
	var sizes: Dictionary = w.get("sizes", {})
	_variant = str(body_key.get("variant", "wolf"))
	if not sizes.has(_variant):
		_variant = "wolf"
	_size = float(sizes.get(_variant, 1.0))
	_k = SIZE_K * _size
	_wolf = (load(str(w.scene)) as PackedScene).instantiate() as Node3D
	_wolf.name = WOLF_NAME
	body.add_child(_wolf)
	_wolf.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * _size), Vector3.ZERO)
	var meshes: Dictionary = w.get("meshes", {})
	var shell: MeshInstance3D = null
	var far_src: MeshInstance3D = null
	for n in _wolf.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if str(mi.name) == str(meshes.get("body", "wolf")):
			_mesh = mi
		elif str(mi.name) == str(meshes.get("shell", "wolf_shell")):
			shell = mi
		elif str(mi.name) == str(meshes.get("far", "wolf_far")):
			far_src = mi
	if _mesh == null:
		return false
	_sk = _mesh.get_node_or_null(_mesh.skeleton) as Skeleton3D
	_material = SkinnedQuadrupedRig.horse_material(w)
	var pal: Dictionary = ((w.get("palettes", {}) as Dictionary).get(_variant, {}) as Dictionary).duplicate()
	if body_key.get("palette") is Dictionary:
		pal.merge(body_key.palette, true)
	for band: String in ["skin", "hair", "cloth", "faction"]:
		if pal.has(band):
			_material.set_shader_parameter(StringName(band + "_color"), Color.html(str(pal[band])))
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_far = MeshInstance3D.new()
	_far.name = FAR_NAME
	_far.mesh = far_src.mesh if far_src != null else null
	_far.material_override = _material
	_far.transform = _wolf.transform
	_far.visible = false
	body.add_child(_far)
	if far_src != null:
		far_src.get_parent().remove_child(far_src)
		far_src.free()
	var layers := fur_layers()
	if shell != null and layers > 0:
		_fur = MeshInstance3D.new()
		_fur.name = FUR_NAME
		_fur.mesh = fur_mesh(shell.mesh, layers)
		_fur.skin = shell.skin
		_sk.add_child(_fur)
		_fur.skeleton = NodePath("..")
		_fur_material = ShaderMaterial.new()
		_fur_material.shader = load(FUR_SHADER)
		_fur_material.set_shader_parameter(&"albedo_tex", load(str(w.albedo)))
		_fur_material.set_shader_parameter(&"band_tex", load(str(w.orm)))
		_fur_material.set_shader_parameter(&"fur_tex", load(str(w.fur)))
		_fur_material.set_shader_parameter(&"length_m", float((w.get("shell", {}) as Dictionary).get("length_m", 0.045)))
		for band: String in ["skin", "hair", "cloth"]:
			if pal.has(band):
				_fur_material.set_shader_parameter(StringName(band + "_color"), Color.html(str(pal[band])))
		_fur.material_override = _fur_material
		_fur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the shell reads at the distances a wolf is looked at; beyond, the coat's own map
		_fur.visibility_range_end = 30.0 * _size
	if shell != null:
		shell.get_parent().remove_child(shell)
		shell.free()
	for i in _sk.get_bone_count():
		_bones[_sk.get_bone_name(i)] = i
		_rest_global[i] = _sk.get_bone_global_rest(i)
	_index_legs(w)
	_reset_feet()
	return true


## The fur shell's surface: `layers` copies of the shell mesh's one surface, each copy's layer (its share of the
## fur's length, 1 / layers to 1) in UV2.x; one mesh a process for each count.
static func fur_mesh(shell: Mesh, layers: int) -> ArrayMesh:
	if _fur_meshes.has(layers):
		return _fur_meshes[layers]
	var src := shell.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var idx_src: PackedInt32Array = src[Mesh.ARRAY_INDEX] if src[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES,
			Mesh.ARRAY_WEIGHTS]:
		if src[k] == null:
			continue
		var acc: Variant = src[k].duplicate()
		acc.clear()
		for l in layers:
			acc.append_array(src[k])
		out[k] = acc
	for l in layers:
		var f := float(l + 1) / float(layers)
		for i in n:
			uv2.append(Vector2(f, 0.0))
		for j in idx_src:
			idx.append(j + l * n)
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	var flags: int = shell.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	_fur_meshes[layers] = m
	return m


## The wolf's poses (wolf_poses.glb): each pose's bone rotations, read once a process.
static func pose(pose_name: String) -> Dictionary:
	if _poses.is_empty():
		var w: Dictionary = SkinnedQuadrupedRig.creature_index().get("wolf", {})
		var lib := load(str(w.get("poses", ""))) as AnimationLibrary if ResourceLoader.exists(str(w.get("poses", ""))) else null
		if lib != null:
			for an: StringName in lib.get_animation_list():
				var a := lib.get_animation(an)
				var rots := {}
				for t in a.get_track_count():
					if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
						rots[str(a.track_get_path(t)).get_slice(":", 1)] = a.rotation_track_interpolate(t, 0.0)
				_poses[str(an)] = rots
		if _poses.is_empty():
			_poses["-"] = {}
	return _poses.get(pose_name, {})


func _index_legs(w: Dictionary) -> void:
	var soles: Dictionary = (w.get("landmarks", {}) as Dictionary).get("soles", {})
	for leg: String in LEGS:
		var parts := leg.split("_")
		var b: Array = []
		var joints: Array = []
		for seg: String in ["upper", "lower", "cannon", "foot"]:
			var i: int = _bones.get("%s_%s_%s" % [parts[0], seg, parts[1]], -1)
			b.append(i)
			joints.append((_rest_global[i] as Transform3D).origin if i >= 0 else Vector3.ZERO)
		var so: Array = soles.get(leg, [0.0, 0.0, 0.0])
		joints.append(Vector3(float(so[0]), float(so[1]), float(so[2])))
		var lens: Array = []
		for k in 4:
			lens.append((joints[k + 1] as Vector3).distance_to(joints[k]))
		var a: Vector3 = joints[0]
		var c: Vector3 = joints[2]
		var d := (c - a).normalized()
		var pole := (joints[1] as Vector3 - a) - d * (joints[1] as Vector3 - a).dot(d)
		if pole.length_squared() < 1e-8:
			pole = Vector3(0.0, 0.0, -1.0 if parts[0] == "fore" else 1.0)
		_legs[leg] = {"b": b, "joints": joints, "len": lens, "pole": pole.normalized(), "fore": parts[0] == "fore"}
		# P64b: the solve's constants, made once (the same values it computed every frame)
		var d_rest: Array = []
		var rest_basis: Array = []
		for k in 4:
			d_rest.append(((joints[k + 1] as Vector3) - (joints[k] as Vector3)).normalized())
			rest_basis.append((_rest_global[b[k]] as Transform3D).basis if int(b[k]) >= 0 else Basis())
		var parent_basis := _global_basis(_sk.get_bone_parent(int(b[0]))) if int(b[0]) >= 0 else Basis()
		_legs[leg].merge({"d_rest": d_rest, "rest_basis": rest_basis, "parent_basis": parent_basis,
			"parent_inv": parent_basis.inverse(), "foot_rest": (joints[4] as Vector3) - (joints[3] as Vector3),
			"cannon_n": ((joints[3] as Vector3) - (joints[2] as Vector3)).normalized(),
			"rest_pos0": _sk.get_bone_rest(int(b[0])).origin if int(b[0]) >= 0 else Vector3.ZERO})


# --------------------------------------------------------------------------- the slots (CreatureSlots)

func slot_wanted() -> bool:
	return _mode == 1 and is_inside_tree() and actor != null and actor.visible \
		and not (actor is EnemyActor and (actor as EnemyActor).lod_tier >= 2 and not _held())


func slot_priority(cam: Vector3) -> float:
	var d := actor.global_position.distance_to(cam)
	if render_lod_m > 0.0 and d > render_lod_m * sqrt(_size) and not _held():
		return INF
	if _slot:
		d *= CreatureSlots.KEEP_SHARE
	var s: Dictionary = rig_state()
	if _held() or s.get("action") != null or bool(s.get("staggered", false)):
		return CreatureSlots.ACTING + d
	return d + (500.0 if bool(s.get("dead", false)) else 0.0)


func set_slot(on: bool) -> void:
	var dead := actor != null and bool(rig_state().get("dead", false))
	if _slot_applied and on == _slot and _frozen == (not on and dead):
		return
	_slot_applied = _wolf != null
	_slot = on
	_frozen = not on and dead
	if _wolf == null:
		return
	var show := on or _frozen
	_wolf.visible = show
	_far.visible = not show


func has_slot() -> bool:
	return _slot


func _held() -> bool:
	return actor != null and actor.has_method("is_held") and bool(actor.call("is_held"))


# --------------------------------------------------------------------------- the frame

## The box rig's pivots are left alone while the skinned body shows (QuadrupedRig._box_posed).
func _box_posed() -> bool:
	return _mode != 1


func _process(delta: float) -> void:
	super._process(delta)
	if actor == null or not actor.has_method("get_rig_state"):
		return
	if _mode < 0:
		_decide()
	if _mode != 1:
		return
	CreatureSlots.allocate(self)
	if not _slot or not is_visible_in_tree() or not body.visible:
		if not _slot:
			CreatureSlots.totals.far_frames = int(CreatureSlots.totals.far_frames) + 1
		_last_pos = Vector3.INF
		_half_dt = 0.0
		return
	# P64b: out of view, or far and idle, the body poses every other frame (CreatureSlots.half_rate)
	var s := rig_state()
	var acting := s.get("action") != null or bool(s.get("staggered", false)) or bool(s.get("lunging", false)) \
		or bool(s.get("dead", false)) or _held()
	if not _half_skip and CreatureSlots.half_rate(actor.global_position + Vector3.UP * 0.5 * _size, 1.3 * _size,
			render_lod_m * sqrt(_size), acting):
		_half_skip = true
		_half_dt += delta
		CreatureSlots.totals.half_rate_skips = int(CreatureSlots.totals.half_rate_skips) + 1
		return
	_half_skip = false
	_skinned_frame(delta + _half_dt)
	_half_dt = 0.0


func _skinned_frame(delta: float) -> void:
	skinned_frames += 1
	CreatureSlots.totals.skinned_frames = int(CreatureSlots.totals.skinned_frames) + 1
	var s: Dictionary = rig_state()
	var dead := bool(s.get("dead", false))
	var held := _held()
	var lunging := bool(s.get("lunging", false))
	_track_motion(delta)
	var free := not dead and not held and not lunging
	_update_gait(delta, free)
	_w_lunge = move_toward(_w_lunge, 1.0 if lunging and not dead else 0.0, delta * LUNGE_RATE)
	var g := _gait_vec()
	var bob := 0.0
	var flex := 0.0
	if free and _speed > STAND_MPS * sqrt(_k):
		var amp := g.dot(BOB) * _k * clampf(_speed / 2.0, 0.3, 1.0)
		var twice := 1.0 - _w_gallop
		bob = -amp * cos(TAU * (2.0 * twice + (1.0 - twice)) * (_phase - _duty() * 0.5))
		flex = deg_to_rad(g.dot(FLEX_DEG)) * sin(TAU * _phase)
	var lean_want := 0.0
	if free:
		lean_want = clampf(atan(_speed * _yaw_rate / 9.81), -deg_to_rad(LEAN_MAX_DEG), deg_to_rad(LEAN_MAX_DEG))
	_lean = lerpf(_lean, lean_want, 1.0 - exp(-6.0 * delta))
	var bp := bite_pose(s)
	var wolf_xf := Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.BACK, -_lean),
		Vector3(0.0, bob - BITE_CROUCH_M * _k * bp.z, -BITE_REACH_M * _k * bp.y)) \
		* Transform3D(Basis().scaled(Vector3.ONE * _size), Vector3.ZERO)
	if wolf_xf != _wolf.transform:
		_wolf.transform = wolf_xf   # (unchanged, it is not set: setting it moves every node under it)
	var keep := free and _w_lunge <= 0.0 and _legs_unchanged()
	if keep:
		kept_leg_frames += 1
	_reset_pose(keep)
	if free and not keep:
		_solve_legs()
	_mark_legs(free and _w_lunge <= 0.0)
	_pose_spine(flex)
	if _w_lunge > 0.0:
		_blend_pose("lunge", _w_lunge, true)
	_pose_head_jaw_tail(s, delta, free)


## The actor's motion this frame (smoothed), its yaw rate; a teleport puts the paws back on their places.
func _track_motion(delta: float) -> void:
	var pos := actor.global_position
	var yaw := actor.global_rotation.y
	if _last_pos == Vector3.INF or pos.distance_to(_last_pos) > TELEPORT_M * _size or delta <= 0.0:
		_last_pos = pos
		_last_yaw = yaw
		_vel = Vector3.ZERO
		_speed = 0.0
		_reset_feet()
		return
	var v := (pos - _last_pos) / delta
	v.y = 0.0
	_vel = _vel.lerp(v, 1.0 - exp(-14.0 * delta))
	_speed = _vel.length()
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 1.0 - exp(-8.0 * delta))
	_last_pos = pos
	_last_yaw = yaw


func _gait_vec() -> Vector3:
	return Vector3((1.0 - _w_trot) * (1.0 - _w_gallop), _w_trot * (1.0 - _w_gallop), _w_gallop)


## The speed as the horse-sized similar would run it (m/s): the speed over sqrt(k / horse's).
func _similar_speed() -> float:
	return _speed / sqrt(_k)


func _duty() -> float:
	var v := _similar_speed()
	var fast := clampf((v - GALLOP_FROM.y) / (FAST_MPS - GALLOP_FROM.y), 0.0, 1.0)
	var g := _gait_vec()
	return g.x * WALK_DUTY + g.y * TROT_DUTY + g.z * lerpf(GALLOP_DUTY, FAST_GALLOP_DUTY, fast)


func _offset(i: int) -> float:
	var g := _gait_vec()
	return g.x * float(WALK_OFF[i]) + g.y * float(TROT_OFF[i]) + g.z * float(GALLOP_OFF[i])


## Strides a second at `v` m/s for a wolf of `k` (the horse's lengths times k): the horse's frequency at the similar
## speed v / sqrt(k), times 1 / sqrt(k), times HZ_GAIN (a canid's quicker step: its legs are shorter for its size
## than a horse's, so a stance covers less ground).
static func stride_hz(v: float, k: float) -> float:
	var s := sqrt(k)
	return SkinnedQuadrupedRig.stride_hz(v / s) / s * HZ_GAIN


func _home(leg: String, xf := Transform3D()) -> Vector3:
	if xf == Transform3D():
		xf = actor.global_transform
	var sole: Vector3 = (_legs[leg].joints as Array)[4]
	var ahead := FORE_AHEAD_M * _k * clampf(_speed / 2.0, 0.0, 1.0) if bool(_legs[leg].fore) else 0.0
	return xf * Vector3(-sole.x * _size, 0.0, -sole.z * _size - ahead)


func _reset_feet() -> void:
	if _legs.is_empty() or actor == null:
		return
	for leg: String in LEGS:
		var p := _home(leg)
		_feet[leg] = {"stance": true, "pos": p, "from": p, "s": 0.0, "last_p": -1.0, "step": false, "anchor": p,
			"lift_p": -1.0}


## The paws' timing in the world (the horse's plan; see the class notes).
func _update_gait(delta: float, free: bool) -> void:
	var v := _similar_speed()
	_w_trot = lerpf(_w_trot, smoothstep(TROT_FROM.x, TROT_FROM.y, v), 1.0 - exp(-5.0 * delta))
	_w_gallop = lerpf(_w_gallop, smoothstep(GALLOP_FROM.x, GALLOP_FROM.y, v), 1.0 - exp(-5.0 * delta))
	if not free:
		_reset_feet()
		return
	var l := _k     # lengths: the horse's times l
	var moving := _speed > STAND_MPS * sqrt(l)
	var hz := maxf(stride_hz(_speed, _k), 0.6 / sqrt(l))
	if moving:
		_phase = fposmod(_phase + hz * delta, 1.0)
	var duty := _duty()
	var stance_t := duty / hz
	var xf := actor.global_transform
	var g := _gait_vec()
	var lift_h := g.dot(LIFT) * l
	var homes := {}
	for leg: String in LEGS:
		homes[leg] = _home(leg, xf)
	var reach_share := (1.0 + _w_gallop * 0.15) * l
	var any_stepping := false
	for leg: String in LEGS:
		if bool((_feet[leg] as Dictionary).step) or not bool((_feet[leg] as Dictionary).stance):
			any_stepping = true
	var settle_leg := ""
	if not moving and not any_stepping:
		var worst := SETTLE_M * l
		for leg: String in LEGS:
			var fp: Vector3 = (_feet[leg] as Dictionary).pos
			var hp: Vector3 = homes[leg]
			var off := Vector2(fp.x - hp.x, fp.z - hp.z).length()
			if off > worst:
				worst = off
				settle_leg = leg
		if settle_leg == "":
			# (P64b: standing with every paw on its place nothing lifts: the paws keep the ground's height)
			for i in LEGS.size():
				var f: Dictionary = _feet[LEGS[i]]
				var hy: float = (homes[LEGS[i]] as Vector3).y
				var pos: Vector3 = f.pos
				if absf(pos.y - hy) > 1e-4:
					pos.y = hy
					f.pos = pos
					f.anchor = Vector3((f.anchor as Vector3).x, hy, (f.anchor as Vector3).z)
				max_planted_slide = maxf(max_planted_slide, (f.pos as Vector3).distance_to(f.anchor))
				f.last_p = fposmod(_phase + (g.x * float(WALK_OFF[i]) + g.y * float(TROT_OFF[i]) + g.z * float(GALLOP_OFF[i])), 1.0)
			return
	for i in LEGS.size():
		var leg: String = LEGS[i]
		var f: Dictionary = _feet[leg]
		var p := fposmod(_phase + (g.x * float(WALK_OFF[i]) + g.y * float(TROT_OFF[i]) + g.z * float(GALLOP_OFF[i])), 1.0)
		var wrapped := float(f.last_p) >= 0.0 and p < float(f.last_p) - 0.5
		var home: Vector3 = homes[leg]
		var reach := (REACH_FORE_M if bool(_legs[leg].fore) else REACH_HIND_M) * reach_share
		if bool(f.stance):
			var pos: Vector3 = f.pos
			if absf(pos.y - home.y) > 1e-4:
				pos.y = home.y
				f.pos = pos
				f.anchor = Vector3((f.anchor as Vector3).x, home.y, (f.anchor as Vector3).z)
			var lift := false
			if moving and float(f.last_p) >= 0.0 and float(f.last_p) < duty and p >= duty:
				lift = true
			if moving and Vector2(f.pos.x - home.x, f.pos.z - home.z).length() > reach:
				lift = true
			if leg == settle_leg:
				lift = true
				f.step = true
			if lift:
				f.stance = false
				f.from = f.pos
				f.s = 0.0
				f.lift_p = minf(p, 0.97) if not bool(f.step) else -1.0
		else:
			var on_clock := moving and not bool(f.step) and float(f.get("lift_p", -1.0)) >= 0.0
			var swing_s := (1.0 - duty) / hz if not bool(f.step) else STEP_S * sqrt(l)
			if on_clock:
				var lp := float(f.lift_p)
				f.s = 1.0 if wrapped else clampf((p - lp) / maxf(1.0 - lp, 0.03), float(f.s), 1.0)
			else:
				f.s = minf(1.0, float(f.s) + delta / maxf(swing_s, 0.04))
				f.lift_p = -1.0
			var left := 0.0 if float(f.s) >= 1.0 else ((1.0 - p) / hz if on_clock else (1.0 - float(f.s)) * swing_s)
			var to := home + _vel * left + _vel * stance_t * 0.5 if moving and not bool(f.step) else home
			to.y = xf.origin.y
			var e := smoothstep(0.0, 1.0, float(f.s))
			var h := lift_h * (1.0 if bool(_legs[leg].fore) else HIND_LIFT)
			if bool(f.step):
				h = 0.06 * l
			f.pos = (f.from as Vector3).lerp(to, e) + Vector3.UP * h * sin(PI * float(f.s))
			if float(f.s) >= 1.0:
				f.stance = true
				f.step = false
				f.pos = to
				f.anchor = to
		if bool(f.stance):
			max_planted_slide = maxf(max_planted_slide, (f.pos as Vector3).distance_to(f.anchor))
		f.last_p = p


## Every bone back to its rest rotation (the spine, the neck, the head, the jaw and the tail are turned from it each
## frame); `keep_legs`: the legs' bones keep the pose their last solve gave (P64b: see _legs_unchanged). Only the
## forelegs' upper bones are ever moved (the shoulder's slide), so only their positions go back.
func _reset_pose(keep_legs := false) -> void:
	if _rest_rot.is_empty():
		for i in _sk.get_bone_count():
			_rest_rot.append(_sk.get_bone_rest(i).basis.get_rotation_quaternion())
			_sk.set_bone_pose_position(i, _sk.get_bone_rest(i).origin)
		for leg: String in LEGS:
			for bi: int in (_legs[leg].b as Array):
				if bi >= 0:
					_leg_bone[bi] = true
			if bool(_legs[leg].fore) and int((_legs[leg].b as Array)[0]) >= 0:
				_slid_bones.append(int((_legs[leg].b as Array)[0]))
	for i in _rest_rot.size():
		if keep_legs and _leg_bone.has(i):
			continue
		_sk.set_bone_pose_rotation(i, _rest_rot[i])
	if not keep_legs:
		for i: int in _slid_bones:
			_sk.set_bone_pose_position(i, _sk.get_bone_rest(i).origin)


## P64b: whether the legs' solve would give the pose it gave last frame: every paw planted where it was (a planted paw
## never moves) and the skeleton where it was (the actor, the brain's Body and the bob and lean the same). A wolf
## that stands - idle, biting, waiting in a pack - then keeps its legs' pose instead of solving it again; the frame is
## the same to the bit.
func _legs_unchanged() -> bool:
	if not _legs_solved or _sk.global_transform != _legs_xf:
		return false
	for leg: String in LEGS:
		var f: Dictionary = _feet[leg]
		if not bool(f.stance) or bool(f.step) or (f.pos as Vector3) != (_legs_at[leg] as Vector3):
			return false
	return true


## After the frame's legs: what _legs_unchanged compares the next frame with (`solved`: the legs were solved onto
## their paws and nothing was blended over them).
func _mark_legs(solved: bool) -> void:
	_legs_solved = solved
	if not solved:
		return
	_legs_xf = _sk.global_transform
	for leg: String in LEGS:
		_legs_at[leg] = (_feet[leg] as Dictionary).pos


## The legs onto their paws (skeleton space): the toes as at rest (folded in a swing), the metapodial plumb (tilted
## toward the hip or the shoulder only as far as the leg must reach), the two-bone solve above it.
func _solve_legs() -> void:
	var inv := _sk.global_transform.affine_inverse()
	for leg: String in LEGS:
		var L: Dictionary = _legs[leg]
		var f: Dictionary = _feet[leg]
		var b: Array = L.b
		var lens: Array = L.len
		var fore: bool = L.fore
		var stance: bool = f.stance
		var sole := inv * (f.pos as Vector3)
		var fold := 0.0 if stance else sin(PI * float(f.s))
		var fold_deg: Vector2 = FORE_FOLD if fore else HIND_FOLD
		if bool(f.step):
			fold *= 0.4
		var fold_toes := Basis(Vector3.RIGHT, deg_to_rad(fold_deg.y) * fold)
		var fetlock: Vector3 = sole - fold_toes * (L.foot_rest as Vector3)
		var cannon_dir: Vector3 = Basis(Vector3.RIGHT, deg_to_rad(fold_deg.x) * fold) * (L.cannon_n as Vector3)
		var top: Vector3 = (L.joints as Array)[0]
		var slide := 0.0
		if fore:
			slide = clampf((fetlock.z - top.z) * SCAPULA_SHARE, -SCAPULA_M, SCAPULA_M)
			top += Vector3(0.0, -absf(slide) * 0.3, slide)
		var l2: float = lens[2]
		var reach := (float(lens[0]) + float(lens[1])) * 0.985
		var knee := fetlock - cannon_dir * l2
		if knee.distance_to(top) > reach:
			var toward := (top - fetlock).normalized()
			var lo := 0.0
			var hi := 1.0
			for _k2 in 8:
				var mid := (lo + hi) * 0.5
				var dirm := (-cannon_dir).slerp(toward, mid).normalized()
				if (fetlock + dirm * l2).distance_to(top) > reach:
					lo = mid
				else:
					hi = mid
			knee = fetlock + (-cannon_dir).slerp(toward, hi).normalized() * l2
		var solve := TipMatching.two_bone(top, knee, float(lens[0]), float(lens[1]), L.pole)
		var knee_s: Vector3 = solve.end
		if stance:
			max_reach_miss = maxf(max_reach_miss, knee_s.distance_to(knee) * _size)
		var pts := [top, solve.elbow, knee_s, knee_s + (fetlock - knee), sole]
		var parent_basis: Basis = L.parent_basis
		if fore and int(b[0]) >= 0:
			_sk.set_bone_pose_position(int(b[0]), (L.rest_pos0 as Vector3) + (L.parent_inv as Basis) * Vector3(0.0, -absf(slide) * 0.3, slide))
		var parent_inv: Basis = L.parent_inv
		var d_rest: Array = L.d_rest
		var rest_b: Array = L.rest_basis
		for k in 4:
			var bi: int = b[k]
			if bi < 0:
				continue
			var d_new := ((pts[k + 1] as Vector3) - (pts[k] as Vector3)).normalized()
			var gb := PersonRig._arc(d_rest[k], d_new) * (rest_b[k] as Basis)
			var q := (parent_inv * gb).orthonormalized().get_rotation_quaternion()
			if q.is_finite():
				_sk.set_bone_pose_rotation(bi, q)
			parent_basis = gb
			parent_inv = parent_basis.inverse()


func _global_basis(i: int) -> Basis:
	return (_rest_global[i] as Transform3D).basis if i >= 0 else Basis()


## The back's flexion at the gallop (gathered: the spine rounded; extended: hollowed), the pelvis and spine bones
## turned about the body's side axis, half each, so the legs' roots move with it.
func _pose_spine(flex: float) -> void:
	if absf(flex) < 1e-4:
		return
	_turn_bone("spine_01", Basis(Vector3.RIGHT, flex * 0.5))
	_turn_bone("spine_02", Basis(Vector3.RIGHT, flex * 0.5))


## Blends the bones of pose `pose_name` over the current pose by `w` (`legs`: the legs and the spine too; else the
## jaw only).
func _blend_pose(pose_name: String, w: float, legs: bool) -> void:
	var p := pose(pose_name)
	for bn: String in p:
		if not legs and bn != "jaw":
			continue
		var i: int = _bones.get(bn, -1)
		if i < 0:
			continue
		var cur := _sk.get_bone_pose_rotation(i)
		_sk.set_bone_pose_rotation(i, cur.slerp(p[bn] as Quaternion, w))


## The neck's nod, the brain's head pivot, the jaw (the bite's windup opens it, its active phase snaps it shut; the
## lunge's dash holds it open) and the tail (the brain's sway; raised a little in a windup, carried higher at the run).
func _pose_head_jaw_tail(s: Dictionary, delta: float, free: bool) -> void:
	var g := _gait_vec()
	var nod := 0.0
	if free and _speed > STAND_MPS:
		var twice := 1.0 - _w_gallop
		nod = deg_to_rad(g.dot(NOD_DEG)) * sin(TAU * (2.0 * twice + (1.0 - twice)) * _phase)
	var brain_pitch := 0.0
	if head != null:
		brain_pitch = (_head_rest.inverse() * head_basis()).get_euler().x
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := float(s.get("phase_fraction", 0.0))
	var jaw_want := 0.0
	var bp := bite_pose(s)
	if action != null and not bool(s.get("dead", false)):
		match phase:
			ActionDef.Phase.WINDUP:
				jaw_want = smoothstep(0.3, 1.0, f) if not _is_bite(s) else smoothstep(0.15, 0.8, f)
			ActionDef.Phase.ACTIVE:
				jaw_want = 1.0 if bool(s.get("lunging", false)) and f < 0.85 else 0.0
				if _is_bite(s) and f < BITE_SHUT_AT:
					jaw_want = 1.0   # P64c: the jaw wide as the head snaps forward, then shut on the bite
	var rate := JAW_RATE * (3.0 if jaw_want < _jaw else 1.0)   # the snap is quick
	if _is_bite(s):
		rate *= 2.0
	_jaw = move_toward(_jaw, jaw_want, delta * rate)
	# P64c: the bite drawn back (the neck up and back, the head kept on its mark) and snapped forward and down
	var draw := bp.x
	var snap := bp.y
	_turn_bone("neck", Basis(Vector3.RIGHT, nod * 0.6 - brain_pitch * 0.55 * (1.0 - maxf(draw, snap))
		- BITE_NECK_BACK * draw + BITE_NECK_SNAP * snap))
	_turn_bone("head", Basis(Vector3.RIGHT, nod * 0.4 - brain_pitch * 0.45 * (1.0 - maxf(draw, snap))
		+ BITE_HEAD_KEEP * draw - BITE_HEAD_SNAP * snap))
	if _jaw > 0.0:
		_blend_pose("jaw_open", _jaw, false)
	var sway := tail_yaw() if tail != null else 0.0
	var lift := deg_to_rad(12.0) * _w_gallop + (deg_to_rad(10.0) if phase == ActionDef.Phase.WINDUP and action != null else 0.0)
	_turn_bone("tail_01", Basis(Vector3.UP, -sway) * Basis(Vector3.RIGHT, -lift))
	_turn_bone("tail_02", Basis(Vector3.UP, -sway * 0.8))


## P64c: the bite (a weapon arc that is not the lunge): the windup draws the head back and crouches, the jaw wide by
## its end; the active phase snaps the head forward and down with the body behind it and shuts the jaw at BITE_SHUT_AT;
## the recovery lets it go. The radians and shares (bite_pose: x the draw, y the snap, z the crouch).
const BITE_NECK_BACK := 0.38
const BITE_HEAD_KEEP := 0.16
const BITE_NECK_SNAP := 0.6
const BITE_HEAD_SNAP := -0.12
const BITE_CROUCH_M := 0.07
const BITE_REACH_M := 0.12
const BITE_SHUT_AT := 0.4


func _is_bite(s: Dictionary) -> bool:
	var a: ActionDef = s.get("action")
	return a != null and a.hit_shape == "weapon_arc" and not bool(s.get("lunging", false)) and not bool(s.get("dead", false))


## The bite's draw, snap and crouch now (see BITE_*), on the action's clock.
func bite_pose(s: Dictionary) -> Vector3:
	if not _is_bite(s):
		return Vector3.ZERO
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	match int(s.get("phase", 0)):
		ActionDef.Phase.WINDUP:
			var e := smoothstep(0.0, 0.85, f)
			return Vector3(e, 0.0, e)
		ActionDef.Phase.ACTIVE:
			var u := smoothstep(0.0, 0.35, f)
			return Vector3(1.0 - u, u, 1.0 - u)
		ActionDef.Phase.RECOVERY:
			return Vector3(0.0, 1.0 - smoothstep(0.0, 0.8, f), 0.0)
	return Vector3.ZERO


func _turn_bone(bone_name: String, turn: Basis) -> void:
	var i: int = _bones.get(bone_name, -1)
	if i < 0:
		return
	var p := _sk.get_bone_parent(i)
	var parent := _sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var rest_parent := _global_basis(p)
	var gb := turn * (parent * rest_parent.inverse()) * (_rest_global[i] as Transform3D).basis
	var q := (parent.inverse() * gb).orthonormalized().get_rotation_quaternion()
	if q.is_finite():
		_sk.set_bone_pose_rotation(i, q)


# --------------------------------------------------------------------------- paint and reads

func _update_flash(delta: float) -> void:
	var active := _flash > 0.0 or _flash_applied > 0.0 or _tint_dirty
	super._update_flash(delta)
	if active and _mode == 1:
		RigPaint.paint_shaders([_material, _fur_material].filter(func(x: Variant) -> bool: return x != null), _tint,
			_flash_applied, _flash_color)


func wolf() -> Node3D:
	return _wolf


func skeleton() -> Skeleton3D:
	return _sk


func body_mesh() -> MeshInstance3D:
	return _mesh


func fur() -> MeshInstance3D:
	return _fur


func far_mesh() -> MeshInstance3D:
	return _far


func material() -> ShaderMaterial:
	return _material


func fur_material() -> ShaderMaterial:
	return _fur_material


func size() -> float:
	return _size


func jaw_open() -> float:
	return _jaw


func lunge_weight() -> float:
	return _w_lunge


## The paws in the world now and whether each stands (tests): {leg: [position, standing]}.
func paws() -> Dictionary:
	var out := {}
	for leg: String in _feet:
		out[leg] = [(_feet[leg] as Dictionary).pos, (_feet[leg] as Dictionary).stance]
	return out


## A sole's place on the posed skeleton (world; tests).
func posed_sole(leg: String) -> Vector3:
	var L: Dictionary = _legs.get(leg, {})
	if L.is_empty():
		return Vector3.INF
	var bi: int = (L.b as Array)[3]
	var g := _sk.get_bone_global_pose(bi)
	var rest: Transform3D = _rest_global[bi]
	return _sk.global_transform * (g * (rest.affine_inverse() * ((L.joints as Array)[4] as Vector3)))


func gait() -> Dictionary:
	var g := _gait_vec()
	return {"walk": g.x, "trot": g.y, "gallop": g.z, "duty": _duty(), "hz": stride_hz(_speed, _k), "speed": _speed}
