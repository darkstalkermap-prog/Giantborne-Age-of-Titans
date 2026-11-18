class_name SkinnedRig
extends ActorRig
## The realistic giant in play (P43; plan M10 §2.9, decisions 2, 4, 5, 6, 8). The pose brain stays: this is
## an ActorRig, and ActorRig._process computes every pose on the frame clock as before (the stylized
## pivots under Visual/Body - HipL, HipR, Torso, ShoulderL, ShoulderR and their Hand markers - stay, with no
## meshes); the skinned body follows it. Every `is ActorRig` reader keeps working, and footfall audio and
## camera shake stay on the brain's `footfall`.
##
##   Visual (SkinnedRig)
##   └ Body (scale k)                  leans, staggers and falls as the brain says
##     ├ HipL, HipR, Torso, ShoulderL, ShoulderR (+ /Hand)   the brain's pivots
##     ├ Model (GiantModel)            giant_model.tscn: the glTF (turned 180 degrees inside), the index
##     │ ├ (imported) Skeleton3D
##     │ │ └ PoseBrainModifier         run time: the spine's twist, both arms, the weapon in the fist
##     │ ├ AnimationPlayer             run time: the clip library "giant" (assets/giant/giant_clips.glb)
##     │ └ AnimationTree               run time: the legs' sources and the hands (below)
##     └ WeaponSocket                  the weapon visual's parent, placed in the fist
##
## The skinned layers (materials, clips, tree, modifier) run where something is drawn (decision 6): with a
## display, with --skin, or after enable_for_tests(); never with --no-skin. Without them the run-time nodes
## are not made, the skeleton stays at rest, GiantLook only shows and hides meshes, and WeaponSocket
## follows the brain's ShoulderR/Hand marker exactly as the weapon followed the stylized arm.
##
## One frame (plan §2.9): ActorRig._process (the brain) -> _drive_tree (the legs' source from the brain's
## state, never from speed alone) and AnimationTree.advance -> the skeleton's update runs the
## PoseBrainModifier -> skeleton_updated: the held body's visual offset, then `posed` (final bone poses and
## the weapon are valid inside it). The legs' sources, in order of precedence:
##   dead       the idle and locomotion stop; the death clip is seeked by the brain's fall fraction, under
##              the body's own fall;
##   airborne   not on the floor for more than AIR_FRAMES frames: the airborne pose;
##   motion     an action's `motion` block moving the giant in its phase (Shoulder Charge, the grab's
##              lunge): the run clip on the skin's own clock, advanced by ground speed / stride;
##   walking    the brain walks (over 0.3 m/s in LOCOMOTION or BLOCKING): idle | walk | run by normalized
##              speed (speed / k), the clips' time from the brain's walk phase,
##              t = fposmod(walk_phase + pi/2, 2 pi) / 2 pi x length, so heel strikes fall on footfalls;
##   otherwise  the stance (the idle's legs) under the body's lean: dodges, staggers, knockbacks and
##              standing actions never glide in a frozen stride.
## Then the hands: the right fist always closed on the weapon (grip_r), the left hand closed on a held
## body (grip_l) or open while reaching or casting (open_l), else the clip's relaxed hand.
##
## Paint: GiantLook gives every surface its own ShaderMaterial; flash() and set_status_tint() reach them
## through RigPaint.paint_shaders (the `tint` and `flash` uniforms) beside the weapon's flat materials.
## Write-only (decision 5, plan §2.7): this rig and its modifier write under their own Visual node, and,
## during a hold, the held body's Visual.position (moved by the gap between the visible palm and the
## socket the simulation holds it at, at most 0.33 x k), restored when the hold ends or the body goes.
## SKIN_STATS (--skin-stats): run_stats(), printed by the Autopilot at exit, proves what ran.

## After the modifier ran (from Skeleton3D.skeleton_updated): read final bone poses and the weapon here.
signal posed

const MODEL_PATH := NodePath("Body/Model")
const SOCKET_PATH := NodePath("Body/WeaponSocket")
const HAND_PATH := NodePath("Hand")
const CLIPS_PATH := "res://assets/giant/giant_clips.glb"
const LIBRARY := &"giant"
const LOOPS := ["idle", "walk", "run"]
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
## The run blends in between these normalized speeds (m/s / k): stage 1 walks at 5.0 (a jog) and sprints
## at 7.5 (a run); stage 6 walks at 1.57 (a walk).
const RUN_FROM := 3.5
const RUN_FULL := 6.5
## Frames off the floor before the airborne pose shows (a step down is not a jump); it then blends in at
## AIR_RATE, past half on the third frame off the ground.
const AIR_FRAMES := 2
## How fast each source's weight moves (1 / s, exponential).
const BLEND_RATE := 14.0
const AIR_RATE := 45.0
const DEATH_RATE := 20.0
const HAND_RATE := 12.0
## A knockback faster than this (m/s) slides the giant on the stance, never on a walk.
const KNOCKBACK_STANCE_MPS := 0.5
## The held body's visual moves by at most this (stage-1 metres, x k).
const HELD_GAP_MAX := PoseBrainModifier.HELD_GAP_MAX

const P_MOVE := &"parameters/move/blend_amount"
const P_RUN := &"parameters/gait/blend_amount"
const P_CHARGE := &"parameters/charge/blend_amount"
const P_AIR := &"parameters/air/blend_amount"
const P_DEAD := &"parameters/dead/blend_amount"
const P_GRIP_R := &"parameters/hand_r/blend_amount"
const P_OPEN_L := &"parameters/open_l/blend_amount"
const P_GRIP_L := &"parameters/grip_l/blend_amount"
const P_WALK_T := &"parameters/walk_seek/seek_request"
const P_RUN_T := &"parameters/run_seek/seek_request"
const P_CHARGE_T := &"parameters/charge_seek/seek_request"
const P_DEATH_T := &"parameters/death_seek/seek_request"
## The blend weights (_w) and their tree parameters, set only when they change.
const BLEND_PARAMS := {"move": P_MOVE, "run": P_RUN, "charge": P_CHARGE, "air": P_AIR, "dead": P_DEAD, "open_l": P_OPEN_L,
	"grip_l": P_GRIP_L}

## The run's counts over every SkinnedRig of the process (a sandbox reset makes a new rig), for SKIN_STATS.
static var totals := {"posed_frames": 0, "modifier_runs": 0, "held_visual_writes": 0, "rig_footfalls": 0, "rigs": 0}
static var _forced := false
static var _cli := 2           # 2 unread, 1 --skin, -1 --no-skin, 0 neither
static var _clips: AnimationLibrary = null
static var _last: WeakRef = null

var _model: GiantModel = null
var _socket: Node3D = null
var _skeleton: Skeleton3D = null
var _gltf: Node3D = null
var _player: AnimationPlayer = null
var _tree: AnimationTree = null
var _mod: PoseBrainModifier = null
var _layers := false
var _look: Dictionary = {}
var _lengths := {}
var _w := {"move": 0.0, "run": 0.0, "charge": 0.0, "air": 0.0, "dead": 0.0, "open_l": 0.0, "grip_l": 0.0}
var _sent := {}
var _air := 0
var _legs := "stance"
var _charge_phase := 0.0
var _held: Node3D = null
var _held_visual: Node3D = null
var _held_base := Vector3.ZERO
## This rig's own counts (skin_stats()).
var posed_frames := 0
var held_visual_writes := 0


# --------------------------------------------------------------------------- the switch (decision 6)

## The skinned layers on in a headless test until reset_for_tests() (ResetHooks runs it after every test).
## Call it before the giant is spawned: a rig decides in its _ready.
static func enable_for_tests() -> void:
	_forced = true


static func reset_for_tests() -> void:
	_forced = false


## True where the skinned layers run: a display, --skin or enable_for_tests(); never with --no-skin.
static func layers_enabled() -> bool:
	var cli := _cli_mode()
	if cli < 0:
		return false
	if _forced or cli > 0:
		return true
	return DisplayServer.get_name() != "headless"


static func _cli_mode() -> int:
	if _cli == 2:
		var args := OS.get_cmdline_user_args()
		_cli = -1 if args.has("--no-skin") else (1 if args.has("--skin") else 0)
	return _cli


## The clip library (a copy of the imported one, loops set: imported clips have loop off), held for the
## process; null when the clips are missing.
static func clip_library() -> AnimationLibrary:
	if _clips == null and ResourceLoader.exists(CLIPS_PATH):
		var src := load(CLIPS_PATH) as AnimationLibrary
		if src != null:
			_clips = src.duplicate(true) as AnimationLibrary
			for n: String in LOOPS:
				if _clips.has_animation(n):
					_clips.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return _clips


## The run's numbers for SKIN_STATS (every rig of the process; the look and meshes of the last one made).
static func run_stats() -> Dictionary:
	var rig: SkinnedRig = _last.get_ref() as SkinnedRig if _last != null else null
	var out := {"look": rig.look_name() if rig != null else "", "layers": rig._layers if rig != null else layers_enabled(),
		"posed_frames": int(totals.posed_frames), "modifier_runs": int(totals.modifier_runs),
		"held_visual_writes": int(totals.held_visual_writes), "shown_meshes": rig.shown_meshes() if rig != null else [],
		"rig_footfalls": int(totals.rig_footfalls), "rigs": int(totals.rigs)}
	return out


# --------------------------------------------------------------------------- setup

func _ready() -> void:
	super._ready()
	_model = get_node_or_null(MODEL_PATH) as GiantModel
	_socket = get_node_or_null(SOCKET_PATH) as Node3D
	_skeleton = _model.skeleton() if _model != null else null
	if _model != null and _skeleton != null:
		_gltf = _skeleton.get_parent().get_parent() as Node3D if _skeleton.get_parent() != null else null
	totals.rigs = int(totals.rigs) + 1
	_last = weakref(self)
	footfall.connect(_on_footfall)
	_layers = layers_enabled() and _model != null and _skeleton != null
	if _layers:
		_build_layers()
	_follow_brain_hand()


func _exit_tree() -> void:
	_restore_held()


func _build_layers() -> void:
	GiantLook.build_materials(_model, _model.index, "auto")
	var lib := clip_library()
	if lib != null and _gltf != null:
		_player = AnimationPlayer.new()
		_player.name = "AnimationPlayer"
		_model.add_child(_player)
		_player.root_node = _player.get_path_to(_gltf)
		_player.add_animation_library(LIBRARY, lib)
		_player.active = false
		_tree = AnimationTree.new()
		_tree.name = "AnimationTree"
		_model.add_child(_tree)
		_tree.tree_root = _blend_tree(lib)
		_tree.anim_player = _tree.get_path_to(_player)
		_tree.root_node = _tree.get_path_to(_gltf)
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_tree.active = true
		_tree.set(P_GRIP_R, 1.0)
		for n: String in ["walk", "run", "death"]:
			_lengths[n] = lib.get_animation(n).length if lib.has_animation(n) else 1.0
	_mod = PoseBrainModifier.new()
	_mod.name = "PoseBrainModifier"
	_skeleton.add_child(_mod)
	_mod.setup(self, _model.index, body)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_tint_dirty = true


## The BlendTree of §2.9 step 2, built in code (the run-time nodes are never saved, plan §2.5).
func _blend_tree(lib: AnimationLibrary) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var x := 0.0
	var anim := func(node_name: StringName, clip: String) -> void:
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(String(LIBRARY) + "/" + clip)
		bt.add_node(node_name, a, Vector2(x, 0))
	var seek := func(node_name: StringName, src: StringName) -> void:
		bt.add_node(node_name, AnimationNodeTimeSeek.new(), Vector2(x + 200, 0))
		bt.connect_node(node_name, 0, src)
	var blend := func(node_name: StringName, a: StringName, b: StringName, filter_side: String) -> void:
		var n := AnimationNodeBlend2.new()
		if filter_side != "":
			n.filter_enabled = true
			for path: NodePath in _finger_paths(filter_side):
				n.set_filter_path(path, true)
		bt.add_node(node_name, n, Vector2(x + 400, 0))
		bt.connect_node(node_name, 0, a)
		bt.connect_node(node_name, 1, b)
	anim.call(&"idle_clip", "idle")
	anim.call(&"walk_clip", "walk")
	seek.call(&"walk_seek", &"walk_clip")
	anim.call(&"run_clip", "run")
	seek.call(&"run_seek", &"run_clip")
	blend.call(&"gait", &"walk_seek", &"run_seek", "")
	blend.call(&"move", &"idle_clip", &"gait", "")
	anim.call(&"charge_clip", "run")
	seek.call(&"charge_seek", &"charge_clip")
	blend.call(&"charge", &"move", &"charge_seek", "")
	anim.call(&"air_clip", "airborne")
	blend.call(&"air", &"charge", &"air_clip", "")
	anim.call(&"death_clip", "death")
	seek.call(&"death_seek", &"death_clip")
	blend.call(&"dead", &"air", &"death_seek", "")
	anim.call(&"grip_r_clip", "grip_r")
	blend.call(&"hand_r", &"dead", &"grip_r_clip", "r")
	anim.call(&"open_l_clip", "open_l")
	blend.call(&"open_l", &"hand_r", &"open_l_clip", "l")
	anim.call(&"grip_l_clip", "grip_l")
	blend.call(&"grip_l", &"open_l", &"grip_l_clip", "l")
	bt.connect_node(&"output", 0, &"grip_l")
	return bt


## The track paths of one hand's fingers ("Giant_rig/Skeleton3D:index_01_r", ...).
func _finger_paths(side: String) -> Array[NodePath]:
	var out: Array[NodePath] = []
	var sk_path := String(_gltf.get_path_to(_skeleton))
	for i in _skeleton.get_bone_count():
		var bn := _skeleton.get_bone_name(i)
		if bn.ends_with("_" + side):
			for f: String in FINGERS:
				if bn.begins_with(f):
					out.append(NodePath("%s:%s" % [sk_path, bn]))
	return out


# --------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	super._process(delta)
	if actor == null:
		return
	if _tree == null:
		_follow_brain_hand()
		return
	_drive_tree(delta)
	_tree.advance(delta)


## Without the layers: the socket where the weapon hung on the stylized arm (the brain's hand).
func _follow_brain_hand() -> void:
	if _socket == null or weapon_arm == null:
		return
	var hand := weapon_arm.get_node_or_null(HAND_PATH) as Node3D
	_socket.transform = weapon_arm.transform * (hand.transform if hand != null else Transform3D(Basis(), Vector3(0, 0, -1.5)))


## The legs' sources and the hands from the brain's state this frame (see the class notes).
func _drive_tree(delta: float) -> void:
	var s := rig_state()
	var action: ActionDef = s.get("action")
	var speed := float(s.get("speed", 0.0))
	var k := maxf(body_scale, 0.01)
	var n := speed / k
	var dead := bool(s.get("dead", false))
	var on_floor := (actor as CharacterBody3D).is_on_floor() if actor is CharacterBody3D else true
	_air = 0 if on_floor else _air + 1
	var airborne := not dead and _air > AIR_FRAMES
	var charging := not dead and not airborne and speed > 0.3 and motion_moves(action, int(s.get("phase", 0)))
	var knocked: bool = "knockback_velocity" in actor and (actor.get("knockback_velocity") as Vector3).length() > KNOCKBACK_STANCE_MPS
	var walking := is_walking() and not dead and not airborne and not charging and not knocked
	_legs = "dead" if dead else ("airborne" if airborne else ("motion" if charging else ("walking" if walking else "stance")))
	_ease("dead", 1.0 if dead else 0.0, DEATH_RATE, delta)
	_ease("air", 1.0 if airborne else 0.0, AIR_RATE, delta)
	_ease("charge", 1.0 if charging else 0.0, BLEND_RATE, delta)
	_ease("move", clampf(n, 0.0, 1.0) if walking else 0.0, BLEND_RATE, delta)
	_ease("run", smoothstep(RUN_FROM, RUN_FULL, n), BLEND_RATE * 0.5, delta)
	var grab_phase := str(s.get("grab_phase", ""))
	var gripping := grab_phase in ["hold", "crush", "throw"] and str(s.get("holding", "")) != ""
	var open := grab_phase == "reach" or casting(action)
	_ease("grip_l", 1.0 if gripping else 0.0, HAND_RATE, delta)
	_ease("open_l", 1.0 if open and not gripping else 0.0, HAND_RATE, delta)
	if charging:
		_charge_phase += delta * speed / (stride_length_m * k) * PI
	# Seek a clip only while its branch shows: a seeking branch is evaluated even at weight 0 (the tree's
	# optimization skips only the branches that do not seek), and the brain sets the time of every shown one.
	var live: float = (1.0 - float(_w.dead)) * (1.0 - float(_w.air))
	var gait: float = live * (1.0 - float(_w.charge)) * float(_w.move)
	var walk_t := fposmod(walk_phase() + PI * 0.5, TAU) / TAU
	if gait * (1.0 - float(_w.run)) > 0.0:
		_tree.set(P_WALK_T, walk_t * float(_lengths.get("walk", 1.0)))
	if gait * float(_w.run) > 0.0:
		_tree.set(P_RUN_T, walk_t * float(_lengths.get("run", 1.0)))
	if live * float(_w.charge) > 0.0:
		_tree.set(P_CHARGE_T, fposmod(_charge_phase + PI * 0.5, TAU) / TAU * float(_lengths.get("run", 1.0)))
	if float(_w.dead) > 0.0:
		_tree.set(P_DEATH_T, clampf(fall_fraction(), 0.0, 1.0) * float(_lengths.get("death", 1.0)))
	for key: String in BLEND_PARAMS:
		var v: float = _w[key]
		if v != float(_sent.get(key, -1.0)):
			_sent[key] = v
			_tree.set(BLEND_PARAMS[key], v)


func _ease(key: String, target: float, rate: float, delta: float) -> void:
	_w[key] = lerpf(float(_w[key]), target, 1.0 - exp(-rate * delta))
	if absf(float(_w[key]) - target) < 1e-3:
		_w[key] = target


## True while `action`'s scripted `motion` moves the giant: its block names the phase that moves
## (Shoulder Charge's ACTIVE, the grab's lunge in its WINDUP).
static func motion_moves(action: ActionDef, phase: int) -> bool:
	if action == null:
		return false
	var m: Variant = action.param("motion")
	if typeof(m) != TYPE_DICTIONARY or phase < 0 or phase >= ActionDef.PHASE_NAMES.size():
		return false
	return ActionDef.PHASE_NAMES[phase] == str((m as Dictionary).get("phase", "active"))


## True for a one-hand cast (a projectile that is not a boulder or a thrown body): the off hand opens.
static func casting(action: ActionDef) -> bool:
	if action == null or action.hit_shape != "projectile":
		return false
	var spec: Variant = action.param("projectile", {})
	var visual := str((spec as Dictionary).get("visual", "bolt")) if typeof(spec) == TYPE_DICTIONARY else "bolt"
	return not visual in ["boulder", "thrown_body"]


func _on_skeleton_updated() -> void:
	posed_frames += 1
	totals.posed_frames = int(totals.posed_frames) + 1
	_apply_held_visual()
	if _model != null:
		GiantLook.sway(_model, _model.index, _skeleton)   # P46: the hair's tips lag the head's motion
	posed.emit()


func _on_footfall() -> void:
	totals.rig_footfalls = int(totals.rig_footfalls) + 1


# --------------------------------------------------------------------------- the held body's visual

## The body the giant holds (its actor), or null.
func _held_actor() -> Node3D:
	var grab: Variant = actor.get("grab") if actor != null and "grab" in actor else null
	if grab == null or not (grab as Object).has_method("is_holding") or not bool((grab as Object).call("is_holding")):
		return null
	var e: Variant = (grab as Object).call("held_entity")
	if e == null or not is_instance_valid(e):
		return null
	var a: Variant = (e as CombatEntity).actor
	return a as Node3D if a is Node3D and is_instance_valid(a) else null


func _apply_held_visual() -> void:
	if _mod == null:
		return
	var held := _held_actor() if _mod.holding else null
	if held != _held:
		_restore_held()
		_held = held
		_held_visual = held.get_node_or_null("Visual") as Node3D if held != null else null
		_held_base = _held_visual.position if _held_visual != null else Vector3.ZERO
	if _held == null or _held_visual == null or not is_instance_valid(_held_visual) or not is_instance_valid(_held):
		return
	var gap := body.global_transform.basis * _mod.held_gap
	_held_visual.position = _held_base + _held.global_transform.basis.orthonormalized().inverse() * gap
	held_visual_writes += 1
	totals.held_visual_writes = int(totals.held_visual_writes) + 1


## Puts the held body's visual back where it was (a release, the body's death, a new hold, this rig going).
func _restore_held() -> void:
	if _held_visual != null and is_instance_valid(_held_visual):
		_held_visual.position = _held_base
	_held = null
	_held_visual = null


# --------------------------------------------------------------------------- paint, weapon, scale

func _update_flash(delta: float) -> void:
	var active := _flash > 0.0 or _flash_applied > 0.0 or _tint_dirty
	super._update_flash(delta)
	if active and _model != null:
		RigPaint.paint_shaders(GiantLook.materials(_model), _tint, _flash_applied, _flash_color)


## The weapon visual goes under WeaponSocket (in the fist) instead of the stylized arm; `hand_offset` (the
## arm's 1.5 m) does not apply. null takes the weapon away.
func set_weapon_visual(weapon: Node3D, _hand_offset := Vector3(0.0, 0.0, -1.5)) -> void:
	if weapon_visual != null and is_instance_valid(weapon_visual):
		_forget_materials(weapon_visual)
		if weapon_visual.get_parent() != null:
			weapon_visual.get_parent().remove_child(weapon_visual)
		weapon_visual.queue_free()
	weapon_visual = weapon
	if weapon == null or _socket == null:
		return
	weapon.position = Vector3.ZERO
	_socket.add_child(weapon)
	_make_materials_unique(weapon)
	_tint_dirty = true


# --------------------------------------------------------------------------- the look and the reads

## GiantLook.apply on the model (PlayerAppearance calls it with Appearance.to_look of the giant's record).
func apply_look(look: Dictionary) -> void:
	_look = look.duplicate(true)
	if _model != null:
		GiantLook.apply(_model, _model.index, look)
	_tint_dirty = true


func model() -> GiantModel:
	return _model


func weapon_socket() -> Node3D:
	return _socket


func skeleton() -> Skeleton3D:
	return _skeleton


func modifier() -> PoseBrainModifier:
	return _mod


func animation_tree() -> AnimationTree:
	return _tree


func layers_on() -> bool:
	return _layers


## This frame's source of the legs: "dead", "airborne", "motion", "walking" or "stance" (the class notes),
## and the tree's blend weights (move, run, charge, air, dead, open_l, grip_l).
func legs_source() -> String:
	return _legs


func blend_weights() -> Dictionary:
	return _w.duplicate()


## The visible weapon [grip, tip] in global space (valid inside `posed`): the socket and its -Z for the
## weapon's length.
func visible_weapon_segment() -> Array:
	if _socket == null:
		return []
	var grip := _socket.global_position
	var dir := (-_socket.global_transform.basis.z).normalized()
	var length := float(actor.get("weapon_length")) if actor != null and "weapon_length" in actor else 1.85 * body_scale
	return [grip, grip + dir * length]


## A palm in global space (valid inside `posed`): the modifier's, or the brain's hand marker headless.
func palm_global(left: bool) -> Vector3:
	if _mod != null:
		return body.global_transform * (_mod.palm["l" if left else "r"] as Vector3)
	var arm := off_arm if left else weapon_arm
	var hand := arm.get_node_or_null(HAND_PATH) as Node3D if arm != null else null
	return hand.global_position if hand != null else global_position


## The look's name: the preset of the giant's record when the record is that preset's, else "custom".
func look_name() -> String:
	var app: Variant = actor.get("appearance") if actor != null and "appearance" in actor else null
	if app == null or not (app as Object).has_method("record"):
		return "default"
	var rec: Dictionary = (app as Object).call("record")
	var preset := str(rec.get("preset", ""))
	var base := Appearance.preset_record(preset) if preset != "" else {}
	if not base.is_empty() and (base == rec or Appearance.sanitize(base, "", false).record == rec):
		return preset
	return "custom"


## The index meshes shown now, sorted.
func shown_meshes() -> Array:
	var out: Array = []
	if _model == null:
		return out
	for id: String in _model.index.get("meshes", {}):
		var mi := _model.mesh(id)
		if mi != null and mi.visible:
			out.append(id)
	out.sort()
	return out


## This rig's numbers (plan §2.9): the look, the layers, posed frames, modifier runs, held-visual writes,
## the meshes shown and the brain's footfalls.
func skin_stats() -> Dictionary:
	return {"look": look_name(), "layers": _layers, "posed_frames": posed_frames,
		"modifier_runs": _mod.runs if _mod != null else 0, "held_visual_writes": held_visual_writes,
		"shown_meshes": shown_meshes(), "rig_footfalls": footfalls}
