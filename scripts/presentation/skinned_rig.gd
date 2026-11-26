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
## PoseBrainModifier, then the springs and SecondaryMotion (P50) -> skeleton_updated: the held body's visual
## offset, then `posed` (final bone poses and the weapon are valid inside it). The legs' sources, first match
## wins (P50 added landing, stomp, roar, sprint, turning and bracing; plan M11 §2.3):
##   dead       the idle and locomotion stop; the death clip is seeked by the brain's fall fraction, under
##              the body's own fall;
##   airborne   not on the floor for more than AIR_FRAMES frames: the airborne pose;
##   landing    LAND_S after the floor returns from the airborne pose: `land`, on its own clock;
##   stomp      an action whose hit is a cylinder_pulse without morale damage (Heavy Footfall, Titan Stomp):
##              `stomp_r`, the windup seeked onto the clip's lift and hold so the foot is planted as the
##              ACTIVE phase starts (STOMP_PLANT), the rest of the action onto its settle;
##   roar       a cylinder_pulse with morale damage (Thunder Roar): `roar` by the action's whole fraction;
##   motion     an action's `motion` block moving the giant in its phase (Shoulder Charge, the grab's
##              lunge): the run clip on the skin's own clock, advanced by ground speed / stride (at most the
##              sprint's cadence), the sprint clip above SPRINT_FROM of the sprint's speed;
##   walking    the brain walks (over 0.3 m/s in LOCOMOTION or BLOCKING): idle | walk | run | sprint by
##              normalized speed (speed / k; the sprint by speed / the sprint's speed), the clips' time from
##              the brain's walk phase, t = fposmod(walk_phase + pi/2, 2 pi) / 2 pi x length, so heel strikes
##              fall on footfalls;
##   turning    the actor's yaw changing faster than TURN_MIN_DEG_S while the brain does not walk: `turn_l` or
##              `turn_r` on a clock of the yaw travelled (a quarter turn a cycle; a snap of more than
##              SNAP_DEG in one frame is a teleport, not a turn);
##   bracing    blocking (or guarding) and standing: `brace`;
##   otherwise  the stance (the idle's legs) under the body's lean: dodges, staggers, knockbacks and
##              standing actions never glide in a frozen stride.
## Every change of source cross-fades by the rig's exponential easing (FADE_RATES; docs/systems/P50.md has the
## table). On top, additive, a flinch (`flinch_f`, `_b`, `_l`, `_r`, named by the side the hit came from) when
## HitFeedback passes one (flinch()), weighted by the flash's strength and never during an attack's ACTIVE
## phase. Then the hands: the right fist closed on the weapon by its family's grip (`grip_club`, `grip_sword`,
## ...), the left hand closed on a held body (grip_l), open while reaching or casting (open_l), both fists
## for the fists, else a relaxed curl (open_l with a share of grip_l: the off hand never droops); in first
## person at rest the arms take `fp_rest` (the weapon in the lower right of the view).
##
## Paint: GiantLook gives every surface its own ShaderMaterial; flash() and set_status_tint() reach them
## through RigPaint.paint_shaders (the `tint` and `flash` uniforms) beside the weapon's flat materials.
## Write-only (decision 5, plan §2.7): this rig and its modifier write under their own Visual node, and,
## during a hold, the held body's Visual.position (moved by the gap between the visible palm and the
## socket the simulation holds it at, at most 0.33 x k), restored when the hold ends or the body goes.
## SKIN_STATS (--skin-stats): run_stats(), printed by the Autopilot at exit, proves what ran.
##
## P62 (plan M11 §2.10): the rig is the player's no more than any actor's. A rival giant and Harrok are SkinnedRigs on
## their own instances of giant_model.tscn (the same meshes, maps and clips as the player's: nothing copied), their
## Body scaled by the scene's fixed_body_scale (their height / 3.6576 m), their look from their record's `appearance`
## (an npc appearance preset) and their axe from their record's weapon, both set up on the first frame
## (_setup_own); everything else - the clips from the brain, tip matching on their own weapon data, the hands,
## secondary motion, the flashes and tints - is the player's code. What reads the player (the camera's first person,
## the eyes' look at the lock, the grab's held body) finds nothing on an enemy and does nothing; SKIN_STATS' look is
## the player's rig's.

## After the modifier ran (from Skeleton3D.skeleton_updated): read final bone poses and the weapon here.
signal posed

const MODEL_PATH := NodePath("Body/Model")
const SOCKET_PATH := NodePath("Body/WeaponSocket")
const HAND_PATH := NodePath("Hand")
const CLIPS_PATH := "res://assets/giant/giant_clips.glb"
const LIBRARY := &"giant"
const LOOPS := ["idle", "walk", "run", "sprint"]
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const ARM_BONES := ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
## The run blends in between these normalized speeds (m/s / k): stage 1 walks at 5.0 (a jog) and sprints
## at 7.5 (a run); stage 6 walks at 1.57 (a walk).
const RUN_FROM := 3.5
const RUN_FULL := 6.5
## The sprint clip blends in between these shares of the sprint's speed (the profile's walk speed x the sprint
## action's speed_mult): stage 1 runs at 5.0 and sprints at 7.5 m/s.
const SPRINT_FROM := 0.8
const SPRINT_FULL := 0.95
## Frames off the floor before the airborne pose shows (a step down is not a jump); it then blends in at
## AIR_RATE, past half by the third frame off the ground.
const AIR_FRAMES := 1
## The landing clip's time after the floor returns (seconds).
const LAND_S := 0.25
## A landing needs this long off the ground (seconds): a step down or a spawn's drop is not a jump.
const LAND_MIN_AIR_S := 0.2
## The stomp's foot is planted at this share of `stomp_r` (P48's clip: up by 0.34, held to 0.58, planted at
## 0.72): the windup is seeked onto [0, STOMP_PLANT], ACTIVE and RECOVERY onto [STOMP_PLANT, 1].
const STOMP_PLANT := 0.72
## Turning on the spot: the yaw rate that starts it (degrees a second), how long it holds after the yaw stops
## (seconds), the yaw a turn clip's cycle covers (degrees), and the most a frame may turn before it counts as a
## teleport's snap (degrees).
const TURN_MIN_DEG_S := 60.0
const TURN_HOLD_S := 0.12
const TURN_CYCLE_DEG := 90.0
const SNAP_DEG := 30.0
## A frame's move of the actor farther than this (stage-1 metres, x k) is a teleport: the springs reset.
const TELEPORT_M := 3.0
## The relaxed off hand: open_l's weight and grip_l's share on top of it (a loose curl, not the bind pose).
const RELAX_OPEN := 1.0
const RELAX_CURL := 0.05
## How fast each source's weight moves (1 / s, exponential): a fade reaches 95 % in 3 / rate seconds (0.12-0.2 s
## for every change of source - the airborne pose 0.125 s, still past half on the third frame off the ground
## (M10's 0.07 s turned a calf 30 degrees in a frame); the speed blends inside the gait M10's 0.37 s).
const BLEND_RATE := 16.0
const FADE_RATES := {"move": 16.0, "run": 8.0, "sprint": 8.0, "charge": 12.0, "charge_sprint": 16.0, "air": 24.0,
	"dead": 20.0, "land": 20.0, "stomp": 20.0, "roar": 20.0, "turn": 18.0, "turn_side": 18.0, "brace": 16.0,
	"fp": 16.0, "open_l": 12.0, "grip_l": 12.0, "fist_l": 12.0}
const AIR_RATE := 24.0
const DEATH_RATE := 20.0
const HAND_RATE := 12.0
## The eyes' look (_look_eyes): its largest (P51's shader clamps at a quarter of the iris's radius), the iris's
## radius in the eyeball's polar angle / pi (the shader's iris_r, which GiantLook leaves at its default), and its
## easing (1 / s).
const EYE_LOOK_MAX := 0.25
const EYE_IRIS_R := 0.168
const EYE_RATE := 10.0
## A flinch's weight: the flash's strength x this, eased in and out with the clip (which starts and ends at
## nothing); it fades out at FLINCH_CUT_RATE when an attack's ACTIVE phase starts. Gate A2: the clips' offsets
## (about 10 degrees of the torso) were hard to see at the game camera's distance, so they are added at more than
## their whole (the Add2 extrapolates an additive clip) and played slower than keyed (FLINCH_RATE: the 0.3 s clip
## over 0.5 s, its peak at 0.15 s, then the ease back).
const FLINCH_GAIN := 2.5
const FLINCH_RATE := 0.6
const FLINCH_CUT_RATE := 40.0
const FLINCH_SIDES := ["f", "b", "l", "r"]
## The grab's phases in which the off hand closes on the held body.
const GRIP_PHASES := ["hold", "crush", "throw"]
## A knockback faster than this (m/s) slides the giant on the stance, never on a walk.
const KNOCKBACK_STANCE_MPS := 0.5
## The held body's visual moves by at most this (stage-1 metres, x k).
const HELD_GAP_MAX := PoseBrainModifier.HELD_GAP_MAX
## The family of a weapon -> its grip clip (P48's one-frame finger poses).
## fp_rest is whole down to the first of these pitches (degrees) and gone by the second.
const FP_REST_PITCH_DEG := Vector2(-30.0, -48.0)
const GRIP_CLIPS := {"club": "grip_club", "sword": "grip_sword", "hammer": "grip_hammer", "axe": "grip_axe",
	"fists": "grip_fist", "fist": "grip_fist", "tree": "grip_tree"}

const P_RUN := &"parameters/gait/blend_amount"
const P_SPRINT := &"parameters/sprint/blend_amount"
const P_CHARGE_SPRINT := &"parameters/charge_gait/blend_amount"
const P_TURN_SIDE := &"parameters/turn_side/blend_amount"
const P_FP := &"parameters/fp/blend_amount"
const P_GRIP_R := &"parameters/hand_r/blend_amount"
const P_OPEN_L := &"parameters/open_l/blend_amount"
const P_GRIP_L := &"parameters/grip_l/blend_amount"
const P_FIST_L := &"parameters/fist_l/blend_amount"
const P_WALK_T := &"parameters/walk_seek/seek_request"
const P_RUN_T := &"parameters/run_seek/seek_request"
const P_SPRINT_T := &"parameters/sprint_seek/seek_request"
const P_CHARGE_T := &"parameters/charge_seek/seek_request"
const P_CHARGE_SPRINT_T := &"parameters/charge_sprint_seek/seek_request"
const P_DEATH_T := &"parameters/death_seek/seek_request"
const P_LAND_T := &"parameters/land_seek/seek_request"
const P_STOMP_T := &"parameters/stomp_r_seek/seek_request"
const P_ROAR_T := &"parameters/roar_seek/seek_request"
const P_TURN_L_T := &"parameters/turn_l_seek/seek_request"
const P_TURN_R_T := &"parameters/turn_r_seek/seek_request"
## The blend weights (_w) that are tree parameters as they stand (inside the gait, the turn, the charge, the hands
## and first person).
const BLEND_PARAMS := {"run": P_RUN, "sprint": P_SPRINT, "charge_sprint": P_CHARGE_SPRINT, "turn_side": P_TURN_SIDE,
	"fp": P_FP, "open_l": P_OPEN_L, "grip_l": P_GRIP_L, "fist_l": P_FIST_L}
## The legs' sources over the stance, from the lowest precedence to the highest (the weights' chain: each source's
## share of the legs is its weight times what the sources above it leave; source_weights()).
const SOURCE_CHAIN := ["brace", "turn", "move", "charge", "stomp", "roar", "land", "air", "dead"]
## Gate A (lens 6): the tree places the sources' shares by a balanced tree of Blend2 nodes over the leaves in
## SOURCE_LEAVES' order (the order P50's chain blended them in, so the mixer adds their clips in the same order), each
## node's amount its right half's share of the weight under it (_send_all), so each clip's weight is the chain's
## (source_weights()); and gates ("gate_*", Transitions) before the branches that are often at no weight: a gate is
## "on" while anything under it weighs, else "off" (an empty clip, GATE_CLIP), and its branch is not evaluated at
## all (behind a Blend2 at a weight of 0 it still is: about 1 microsecond a node). The tree's advance at the stance:
## about 0.025 ms, from 0.068 (docs/systems/P50.md, "Gate A").
const SOURCE_LEAVES := ["stance", "brace", "turn", "move", "charge", "stomp", "roar", "land", "air", "dead"]
const GATE_CLIP := "_gate_off"
## Every blend amount _send_all sets, in its slot order: BLEND_PARAMS' then the sources' nodes (sources, sources_lo,
## stance_brace, turn_move, sources_hi, charge_pulse, stomp_roar, land_fall, air_dead).
const SLOT_PARAMS := [P_RUN, P_SPRINT, P_CHARGE_SPRINT, P_TURN_SIDE, P_FP, P_OPEN_L, P_GRIP_L, P_FIST_L,
	&"parameters/sources/blend_amount", &"parameters/sources_lo/blend_amount", &"parameters/stance_brace/blend_amount",
	&"parameters/turn_move/blend_amount", &"parameters/sources_hi/blend_amount", &"parameters/charge_pulse/blend_amount",
	&"parameters/stomp_roar/blend_amount", &"parameters/land_fall/blend_amount", &"parameters/air_dead/blend_amount"]
## Every gate _send_all opens and closes, in its slot order.
const GATE_NAMES := ["gate_turn", "gate_move", "gate_turn_move", "gate_charge", "gate_pulse", "gate_fall", "gate_charge_pulse",
	"gate_land_fall", "gate_hi", "gate_walk", "gate_run", "gate_sprint", "gate_fist_l", "gate_fp"]
const GATE_PARAMS := [&"parameters/gate_turn/transition_request", &"parameters/gate_move/transition_request",
	&"parameters/gate_turn_move/transition_request", &"parameters/gate_charge/transition_request",
	&"parameters/gate_pulse/transition_request", &"parameters/gate_fall/transition_request",
	&"parameters/gate_charge_pulse/transition_request", &"parameters/gate_land_fall/transition_request",
	&"parameters/gate_hi/transition_request", &"parameters/gate_walk/transition_request",
	&"parameters/gate_run/transition_request", &"parameters/gate_sprint/transition_request",
	&"parameters/gate_fist_l/transition_request", &"parameters/gate_fp/transition_request"]
## The flinches: one Add2 ("flinch") by the sum of their weights over a blend of the four sides by their shares
## (each side's clip added at its own weight, as four Add2 nodes did, for one node evaluated without a flinch).
const P_FLINCH := &"parameters/flinch/add_amount"
const P_FLINCH_SIDES := &"parameters/flinch_sides/blend_amount"
const P_FLINCH_FB := &"parameters/flinch_fb/blend_amount"
const P_FLINCH_LR := &"parameters/flinch_lr/blend_amount"
const P_FLINCH_T := {"f": &"parameters/flinch_f_seek/seek_request", "b": &"parameters/flinch_b_seek/seek_request",
	"l": &"parameters/flinch_l_seek/seek_request", "r": &"parameters/flinch_r_seek/seek_request"}

## The run's counts over every SkinnedRig of the process (a sandbox reset makes a new rig), for SKIN_STATS.
static var totals := {"posed_frames": 0, "modifier_runs": 0, "held_visual_writes": 0, "rig_footfalls": 0, "rigs": 0,
	"flinches": 0, "flinches_refused": 0, "teleports": 0}
static var _forced := false
static var _cli := 2           # 2 unread, 1 --skin, -1 --no-skin, 0 neither
static var _clips: AnimationLibrary = null
static var _last: WeakRef = null

## P62: a body scale the scene fixes (a rival giant's k = its height / the stage-1 giant's; 0: growth sets it, as
## the player's).
@export var fixed_body_scale := 0.0
## P62: the appearance preset this rig's own actor wears ("" for the player, whose look PlayerAppearance applies).
var own_look := ""
var _own_done := false

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
var _w := {"move": 0.0, "run": 0.0, "sprint": 0.0, "charge": 0.0, "charge_sprint": 0.0, "air": 0.0, "dead": 0.0, "land": 0.0,
	"stomp": 0.0, "roar": 0.0, "turn": 0.0, "turn_side": 0.0, "brace": 0.0, "fp": 0.0, "open_l": 0.0, "grip_l": 0.0,
	"fist_l": 0.0}
var _sent := {}
## _send_all's slots: the amounts and gates wanted this frame and those last set (-1 / 0: none yet, all closed).
var _want := PackedFloat64Array()
var _sent_v := PackedFloat64Array()
var _want_gate := PackedByteArray()
var _sent_gate := PackedByteArray()
## The flinches' gate (open while one plays).
var _gates := {}
## The hair's sway (_sway): its card meshes, the head bone, and the last frame's place, time and motion.
var _sway_meshes: Array[MeshInstance3D] = []
var _sway_bone := -1
var _sway_dirty := true
var _sway_has := false
var _sway_pos := Vector3.ZERO
var _sway_t := 0
var _sway_motion := Vector3.ZERO
## The eyes' look (_look_eyes): the Eyes material, the head bone and its rest, the eased look and the last written.
var _eye_mat: ShaderMaterial = null
var _head_bone := -1
var _head_rest := Basis()
var _eye_look := Vector2.ZERO
var _eye_sent := Vector2.ZERO
var _air := 0
var _legs := "stance"
var _charge_phase := 0.0
var _land_t := -1.0
var _was_air := false
var _air_t := 0.0
var _yaw := 0.0
var _yaw_set := false
var _turn_hold := 0.0
var _turn_travel := {"l": 0.0, "r": 0.0}
var _last_pos := Vector3.ZERO
var _was_dead := false
var _grip_clip := ""
## The running flinches: side -> {"t": seconds into the clip, "w": weight}.
var _flinch := {}
var _secondary: SecondaryMotion = null
var _held: Node3D = null
var _held_visual: Node3D = null
var _held_base := Vector3.ZERO
## This rig's own counts (skin_stats()).
var posed_frames := 0
var held_visual_writes := 0
var flinches := 0
var flinches_refused := 0
var teleports := 0


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
			# the gates' empty clip (no track: a closed gate evaluates nothing)
			var none := Animation.new()
			none.length = 1.0 / 30.0
			_clips.add_animation(GATE_CLIP, none)
	return _clips


## The run's numbers for SKIN_STATS (every rig of the process; the look and meshes of the last one made).
static func run_stats() -> Dictionary:
	var rig: SkinnedRig = _last.get_ref() as SkinnedRig if _last != null else null
	var out := {"look": rig.look_name() if rig != null else "", "layers": rig._layers if rig != null else layers_enabled(),
		"posed_frames": int(totals.posed_frames), "modifier_runs": int(totals.modifier_runs),
		"held_visual_writes": int(totals.held_visual_writes), "shown_meshes": rig.shown_meshes() if rig != null else [],
		"rig_footfalls": int(totals.rig_footfalls), "rigs": int(totals.rigs),
		"secondary_frames": int(SecondaryMotion.totals.get("frames", 0)), "secondary_resets": int(SecondaryMotion.totals.get("resets", 0)),
		"chains": Array(rig._secondary.chains) if rig != null and rig._secondary != null else [],
		"flinches": int(totals.get("flinches", 0)), "flinches_refused": int(totals.get("flinches_refused", 0)),
		"teleports": int(totals.get("teleports", 0))}
	return out


# --------------------------------------------------------------------------- setup

func _ready() -> void:
	super._ready()
	motion_lean = true   # C3b: the giant's weight leans into his starts, stops and turns (ActorRig._motion_lean)
	_model = get_node_or_null(MODEL_PATH) as GiantModel
	_socket = get_node_or_null(SOCKET_PATH) as Node3D
	_skeleton = _model.skeleton() if _model != null else null
	if _model != null and _skeleton != null:
		_gltf = _skeleton.get_parent().get_parent() as Node3D if _skeleton.get_parent() != null else null
	totals.rigs = int(totals.rigs) + 1
	if not (actor is EnemyActor):
		_last = weakref(self)   # SKIN_STATS' look is the player's (P62: a rival giant is a SkinnedRig too)
	footfall.connect(_on_footfall)
	_layers = layers_enabled() and _model != null and _skeleton != null
	if fixed_body_scale > 0.0:
		set_body_scale(fixed_body_scale)
	if _layers:
		_build_layers()
	_follow_brain_hand()


## P62 (plan M11 §2.10): an actor that is not the player - a rival giant, Harrok - is its own rig's owner: its look
## from its record's `appearance` (an appearance preset: Appearance.to_look of the preset's record, as the player's
## look comes from his), its weapon visual from its record's weapon (WeaponVisuals, scaled so the mesh is as long as
## the gameplay's sweep: the record's length_m in world metres under Body's k). Done once, on the first frame (the
## actor reads its record in its own _ready, after this rig's).
func _setup_own() -> void:
	_own_done = true
	if not (actor is EnemyActor):
		return
	var rec: Dictionary = actor.get("record") if typeof(actor.get("record")) == TYPE_DICTIONARY else {}
	var preset := str(rec.get("appearance", ""))
	if _layers and preset != "" and not Appearance.preset_record(preset).is_empty():
		apply_look(Appearance.to_look(Appearance.preset_record(preset)))
		own_look = preset
	var w: Variant = actor.get("weapon")
	if typeof(w) == TYPE_DICTIONARY and not (w as Dictionary).is_empty() and weapon_visual == null:
		var node := WeaponVisuals.build(w)
		node.scale = Vector3.ONE / maxf(body_scale, 0.01)
		set_weapon_visual(node)


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
		_want.resize(SLOT_PARAMS.size())
		_sent_v.resize(SLOT_PARAMS.size())
		_sent_v.fill(-1.0)
		_want_gate.resize(GATE_NAMES.size())
		_sent_gate.resize(GATE_NAMES.size())
		_sent_gate.fill(0)
		for n: String in ["walk", "run", "sprint", "death", "land", "stomp_r", "roar", "turn_l", "turn_r", "flinch_f", "flinch_b",
				"flinch_l", "flinch_r"]:
			_lengths[n] = lib.get_animation(n).length if lib.has_animation(n) else 1.0
	_mod = PoseBrainModifier.new()
	_mod.name = "PoseBrainModifier"
	_skeleton.add_child(_mod)
	_mod.setup(self, _model.index, body)
	# P50: the springs and their limits after the brain (the giant's front is -Z in Body space)
	_secondary = SecondaryMotion.attach(_skeleton, _model.index, _mod.skeleton_dir(Vector3.FORWARD))
	_secondary.configure(SecondaryMotion.chains_for(_model.index, shown_meshes()))
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_tint_dirty = true


## The BlendTree of §2.9 step 2 with P50's sources (the class notes), built in code (the run-time nodes are
## never saved, plan §2.5): the sources' leaves under a balanced tree of Blend2 nodes with gates (SOURCE_LEAVES; each
## leaf weighs what SOURCE_CHAIN's chain gives it), the flinches added on top by one gated Add2, then the hands and
## first person's arms through filtered blends.
func _blend_tree(lib: AnimationLibrary) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var x := 0.0
	var has := func(clip: String) -> bool: return lib.has_animation(clip)
	var anim := func(node_name: StringName, clip: String) -> void:
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(String(LIBRARY) + "/" + (clip if has.call(clip) else "idle"))
		bt.add_node(node_name, a, Vector2(x, 0))
	var seek := func(node_name: StringName, src: StringName) -> void:
		bt.add_node(node_name, AnimationNodeTimeSeek.new(), Vector2(x + 200, 0))
		bt.connect_node(node_name, 0, src)
	var clip_seek := func(clip: String) -> StringName:
		anim.call(StringName(clip + "_clip"), clip)
		seek.call(StringName(clip + "_seek"), StringName(clip + "_clip"))
		return StringName(clip + "_seek")
	var blend := func(node_name: StringName, a: StringName, b: StringName, filter: Array) -> void:
		var n := AnimationNodeBlend2.new()
		if not filter.is_empty():
			n.filter_enabled = true
			for path: NodePath in filter:
				n.set_filter_path(path, true)
		bt.add_node(node_name, n, Vector2(x + 400, 0))
		bt.connect_node(node_name, 0, a)
		bt.connect_node(node_name, 1, b)
	# a gate (GATE_NAMES) before a branch that is often at no weight: off, a Transition shows an empty clip and the branch
	# is not evaluated at all (a Blend2 still evaluates a branch at a weight of 0)
	var gate := func(node_name: StringName, branch: StringName) -> StringName:
		var t := AnimationNodeTransition.new()
		t.add_input("off")
		t.add_input("on")
		t.set_input_reset(1, false)
		bt.add_node(node_name, t, Vector2(x + 300, 0))
		var off := AnimationNodeAnimation.new()
		off.animation = StringName(String(LIBRARY) + "/" + GATE_CLIP)
		bt.add_node(StringName(String(node_name) + "_off"), off, Vector2(x + 100, 0))
		bt.connect_node(node_name, 0, StringName(String(node_name) + "_off"))
		bt.connect_node(node_name, 1, branch)
		return node_name
	# the leaves, in SOURCE_LEAVES' order
	anim.call(&"idle_clip", "idle")
	anim.call(&"brace_clip", "brace")
	blend.call(&"turn_side", clip_seek.call("turn_l"), clip_seek.call("turn_r"), [])
	blend.call(&"gait", gate.call(&"gate_walk", clip_seek.call("walk")), gate.call(&"gate_run", clip_seek.call("run")), [])
	blend.call(&"sprint", &"gait", gate.call(&"gate_sprint", clip_seek.call("sprint")), [])
	anim.call(&"charge_clip", "run")
	seek.call(&"charge_seek", &"charge_clip")
	anim.call(&"charge_sprint_clip", "sprint")
	seek.call(&"charge_sprint_seek", &"charge_sprint_clip")
	blend.call(&"charge_gait", &"charge_seek", &"charge_sprint_seek", [])
	var stomp_leaf: StringName = clip_seek.call("stomp_r")
	var roar_leaf: StringName = clip_seek.call("roar")
	var land_leaf: StringName = clip_seek.call("land")
	anim.call(&"air_clip", "airborne")
	var death_leaf: StringName = clip_seek.call("death")
	# the sources' balanced tree (SLOT_PARAMS), gated
	blend.call(&"stance_brace", &"idle_clip", &"brace_clip", [])
	blend.call(&"turn_move", gate.call(&"gate_turn", &"turn_side"), gate.call(&"gate_move", &"sprint"), [])
	blend.call(&"sources_lo", &"stance_brace", gate.call(&"gate_turn_move", &"turn_move"), [])
	blend.call(&"stomp_roar", stomp_leaf, roar_leaf, [])
	blend.call(&"charge_pulse", gate.call(&"gate_charge", &"charge_gait"), gate.call(&"gate_pulse", &"stomp_roar"), [])
	blend.call(&"air_dead", &"air_clip", death_leaf, [])
	blend.call(&"land_fall", land_leaf, gate.call(&"gate_fall", &"air_dead"), [])
	blend.call(&"sources_hi", gate.call(&"gate_charge_pulse", &"charge_pulse"), gate.call(&"gate_land_fall", &"land_fall"), [])
	blend.call(&"sources", &"sources_lo", gate.call(&"gate_hi", &"sources_hi"), [])
	# the flinches, added on top by their sum over the sides' shares
	blend.call(&"flinch_fb", clip_seek.call("flinch_f"), clip_seek.call("flinch_b"), [])
	blend.call(&"flinch_lr", clip_seek.call("flinch_l"), clip_seek.call("flinch_r"), [])
	blend.call(&"flinch_sides", &"flinch_fb", &"flinch_lr", [])
	var add := AnimationNodeAdd2.new()
	bt.add_node(&"flinch", add, Vector2(x + 600, 0))
	bt.connect_node(&"flinch", 0, &"sources")
	bt.connect_node(&"flinch", 1, gate.call(&"gate_flinch", &"flinch_sides"))
	var top := &"flinch"
	anim.call(&"grip_r_clip", "grip_r")
	blend.call(&"hand_r", top, &"grip_r_clip", _finger_paths("r"))
	anim.call(&"open_l_clip", "open_l")
	blend.call(&"open_l", &"hand_r", &"open_l_clip", _finger_paths("l"))
	anim.call(&"grip_l_clip", "grip_l")
	blend.call(&"grip_l", &"open_l", &"grip_l_clip", _finger_paths("l"))
	anim.call(&"fist_l_clip", "grip_fist")
	blend.call(&"fist_l", &"grip_l", gate.call(&"gate_fist_l", &"fist_l_clip"), _finger_paths("l"))
	anim.call(&"fp_clip", "fp_rest")
	blend.call(&"fp", &"fist_l", gate.call(&"gate_fp", &"fp_clip"), _bone_paths(ARM_BONES))
	bt.connect_node(&"output", 0, &"fp")
	return bt


## The track paths of `bones` ("Giant_rig/Skeleton3D:clavicle_l", ...).
func _bone_paths(bones: Array) -> Array[NodePath]:
	var out: Array[NodePath] = []
	var sk_path := String(_gltf.get_path_to(_skeleton))
	for b: Variant in bones:
		if _skeleton.find_bone(str(b)) >= 0:
			out.append(NodePath("%s:%s" % [sk_path, b]))
	return out


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
	if not _own_done:
		_setup_own()
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


## The legs' sources, the flinches and the hands from the brain's state this frame (see the class notes).
func _drive_tree(delta: float) -> void:
	var s := rig_state()
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", 0))
	var speed := float(s.get("speed", 0.0))
	var k := maxf(body_scale, 0.01)
	var n := speed / k
	var dead := bool(s.get("dead", false))
	var on_floor := (actor as CharacterBody3D).is_on_floor() if actor is CharacterBody3D else true
	var yaw_rate := _track_yaw_and_place(delta, dead)
	_air = 0 if on_floor else _air + 1
	var airborne := not dead and _air > AIR_FRAMES
	if airborne:
		_was_air = true
		_air_t += delta
		_land_t = -1.0
	elif _was_air:
		_was_air = false
		_land_t = 0.0 if _air_t >= LAND_MIN_AIR_S else -1.0
		_air_t = 0.0
	if _land_t >= 0.0:
		_land_t += delta
		if _land_t > LAND_S or dead:
			_land_t = -1.0
	var landing := not dead and not airborne and _land_t >= 0.0
	var pulse := action != null and action.hit_shape == "cylinder_pulse"
	var roaring := not dead and not airborne and not landing and pulse and float(action.param("morale_damage", 0.0)) > 0.0
	var stomping := not dead and not airborne and not landing and pulse and not roaring
	var charging := not dead and not airborne and not landing and not pulse and speed > 0.3 and motion_moves(action, phase)
	var knocked: bool = "knockback_velocity" in actor and (actor.get("knockback_velocity") as Vector3).length() > KNOCKBACK_STANCE_MPS
	var free := not dead and not airborne and not landing and not pulse and not charging and not knocked
	var walking := is_walking() and free
	var turning := free and not walking and _turn_hold > 0.0
	var state := int(s.get("state", 0))
	var bracing := free and not walking and not turning and (state == CombatController.State.BLOCKING or bool(s.get("guarding", false)))
	_legs = "dead" if dead else ("airborne" if airborne else ("landing" if landing else ("stomp" if stomping else (
		"roar" if roaring else ("motion" if charging else ("walking" if walking else ("turning" if turning else (
		"bracing" if bracing else "stance"))))))))
	var sprint_share := speed / maxf(sprint_speed(), 0.01)
	_ease("dead", 1.0 if dead else 0.0, float(FADE_RATES.dead), delta)
	_ease("air", 1.0 if airborne else 0.0, float(FADE_RATES.air), delta)
	_ease("land", 1.0 if landing else 0.0, float(FADE_RATES.land), delta)
	_ease("stomp", 1.0 if stomping else 0.0, float(FADE_RATES.stomp), delta)
	_ease("roar", 1.0 if roaring else 0.0, float(FADE_RATES.roar), delta)
	_ease("charge", 1.0 if charging else 0.0, float(FADE_RATES.charge), delta)
	_ease("charge_sprint", 1.0 if sprint_share >= SPRINT_FROM else 0.0, float(FADE_RATES.charge_sprint), delta)
	_ease("move", move_weight(n) if walking else 0.0, float(FADE_RATES.move), delta)
	_ease("run", smoothstep(RUN_FROM, RUN_FULL, n), float(FADE_RATES.run), delta)
	_ease("sprint", smoothstep(SPRINT_FROM, SPRINT_FULL, sprint_share), float(FADE_RATES.sprint), delta)
	_ease("turn", 1.0 if turning else 0.0, float(FADE_RATES.turn), delta)
	if turning:
		_ease("turn_side", 0.0 if yaw_rate > 0.0 else (1.0 if yaw_rate < 0.0 else float(_w.turn_side)), float(FADE_RATES.turn_side), delta)
	_ease("brace", 1.0 if bracing else 0.0, float(FADE_RATES.brace), delta)
	# the hands: the off hand closed on a held body, open to reach or cast, a fist with the fists, else relaxed
	var grab_phase := str(s.get("grab_phase", ""))
	var gripping := (grab_phase in GRIP_PHASES and str(s.get("holding", "")) != "") \
		or (_mod != null and _mod.two_w > 0.5)   # P64c: the off hand on the haft
	var open := grab_phase == "reach" or casting(action)
	var family := weapon_family()
	var fists := (family == "fists" or family == "fist") and not gripping and not open
	_ease("grip_l", 1.0 if gripping else (0.0 if open or fists else RELAX_CURL), HAND_RATE, delta)
	_ease("open_l", 1.0 if open and not gripping else (0.0 if gripping or fists else RELAX_OPEN), HAND_RATE, delta)
	_ease("fist_l", 1.0 if fists else 0.0, HAND_RATE, delta)
	_ease("fp", first_person_rest_weight(), float(FADE_RATES.fp), delta)
	_set_grip_clip(str(GRIP_CLIPS.get(family, "grip_r")))
	if charging:
		# the stride's cadence at most the sprint's: a dash (Shoulder Charge at 26 m/s) would otherwise spin the legs
		# through a third of a cycle a frame
		_charge_phase += delta * minf(speed, sprint_speed()) / (stride_length_m * k) * PI
	# Seek a clip only while its branch shows: a seeking branch is evaluated even at weight 0 (the tree's
	# optimization skips only the branches that do not seek), and the brain sets the time of every shown one.
	var eff := source_weights()
	var walk_t := fposmod(walk_phase() + PI * 0.5, TAU) / TAU
	var gait: float = eff.move
	if gait * (1.0 - float(_w.run)) * (1.0 - float(_w.sprint)) > 0.0:
		_tree.set(P_WALK_T, walk_t * float(_lengths.get("walk", 1.0)))
	if gait * float(_w.run) * (1.0 - float(_w.sprint)) > 0.0:
		_tree.set(P_RUN_T, walk_t * float(_lengths.get("run", 1.0)))
	if gait * float(_w.sprint) > 0.0:
		_tree.set(P_SPRINT_T, walk_t * float(_lengths.get("sprint", 1.0)))
	var charge_t := fposmod(_charge_phase + PI * 0.5, TAU) / TAU
	if float(eff.charge) * (1.0 - float(_w.charge_sprint)) > 0.0:
		_tree.set(P_CHARGE_T, charge_t * float(_lengths.get("run", 1.0)))
	if float(eff.charge) * float(_w.charge_sprint) > 0.0:
		_tree.set(P_CHARGE_SPRINT_T, charge_t * float(_lengths.get("sprint", 1.0)))
	if float(eff.dead) > 0.0:
		_tree.set(P_DEATH_T, clampf(fall_fraction(), 0.0, 1.0) * float(_lengths.get("death", 1.0)))
	if float(eff.land) > 0.0:
		_tree.set(P_LAND_T, clampf(maxf(_land_t, 0.0), 0.0, float(_lengths.get("land", 1.0))))
	if float(eff.stomp) > 0.0 and action != null:
		_tree.set(P_STOMP_T, stomp_fraction(action, phase, float(s.get("phase_fraction", 0.0))) * float(_lengths.get("stomp_r", 1.0)))
	if float(eff.roar) > 0.0 and action != null:
		_tree.set(P_ROAR_T, action_fraction(action, phase, float(s.get("phase_fraction", 0.0))) * float(_lengths.get("roar", 1.0)))
	if float(eff.turn) * (1.0 - float(_w.turn_side)) > 0.0:
		_tree.set(P_TURN_L_T, turn_time("l"))
	if float(eff.turn) * float(_w.turn_side) > 0.0:
		_tree.set(P_TURN_R_T, turn_time("r"))
	_send_all(eff, gait)
	_drive_flinches(delta, action, phase)
	_was_dead = dead


## C3b (decision C3b-3): the feet that do not slide. The walk's weight over the stance comes in by MOVE_FULL_N (m/s / k;
## it was the normalized speed itself, so a stage-8 giant at half his speed walked at 57 % of the clip's stride with his
## body at full speed: the planted foot slid at half his speed), at least MOVE_MIN while he walks; and the brain's walk
## phase covers, a half stride, the clips' own step (WALK_STRIDE_M, RUN_STRIDE_M, SPRINT_STRIDE_M by the gait's
## weights, measured on the clips) times the walk's weight - a slower walk takes shorter steps at nearly the same
## cadence, as people do - so the planted foot stays where it is set down (the film's slide: under 3 % of his speed).
const MOVE_FULL_N := 0.9
const MOVE_MIN := 0.35
const WALK_STRIDE_M := 1.45
const RUN_STRIDE_M := 1.45
const SPRINT_STRIDE_M := 1.45


## The walk's weight over the stance at normalized speed `n` (m/s / k).
static func move_weight(n: float) -> float:
	return clampf(n / MOVE_FULL_N, MOVE_MIN, 1.0) if n > 0.0 else 0.0


func walk_stride_m(speed: float) -> float:
	if _tree == null:
		return stride_length_m
	var n := speed / maxf(body_scale, 0.01)
	var run := float(_w.get("run", 0.0))
	var spr := float(_w.get("sprint", 0.0))
	var clip := lerpf(lerpf(WALK_STRIDE_M, RUN_STRIDE_M, run), SPRINT_STRIDE_M, spr)
	return clip * move_weight(n)


## Each source's share of the final legs this frame (the chain's weights multiplied down from the death):
## {"dead", "air", "land", "roar", "stomp", "charge", "move", "turn", "brace", "stance"}.
func source_weights() -> Dictionary:
	var out := {}
	var rest := 1.0
	for i in range(SOURCE_CHAIN.size() - 1, -1, -1):
		var key: String = SOURCE_CHAIN[i]
		out[key] = rest * float(_w[key])
		rest *= 1.0 - float(_w[key])
	out["stance"] = rest
	return out


func _ease(key: String, target: float, rate: float, delta: float) -> void:
	var w: float = _w[key]
	if w == target:
		return   # (lerpf of a weight already at its target is that target)
	w = lerpf(w, target, 1.0 - exp(-rate * delta))
	_w[key] = target if absf(w - target) < 1e-3 else w


## The actor's yaw this frame: the turn's clock and hold (a snap of more than SNAP_DEG, or a move of more than
## TELEPORT_M x k, is a teleport: the springs reset and nothing turns), and a respawn's reset. Returns the yaw
## rate (radians a second; positive turns left).
func _track_yaw_and_place(delta: float, dead: bool) -> float:
	var yaw := actor.global_rotation.y
	var pos := actor.global_position
	var rate := 0.0
	if not _yaw_set:
		_yaw_set = true
	else:
		var dy := wrapf(yaw - _yaw, -PI, PI)
		var moved := pos.distance_to(_last_pos)
		if absf(dy) > deg_to_rad(SNAP_DEG) or moved > TELEPORT_M * maxf(body_scale, 0.01):
			_teleported()
			_turn_hold = 0.0
		elif delta > 0.0:
			rate = dy / delta
			if absf(rate) > deg_to_rad(TURN_MIN_DEG_S):
				_turn_hold = TURN_HOLD_S
				_turn_travel["l" if dy > 0.0 else "r"] = float(_turn_travel["l" if dy > 0.0 else "r"]) + absf(dy)
			else:
				_turn_hold = maxf(0.0, _turn_hold - delta)
				rate = 0.0
	_yaw = yaw
	_last_pos = pos
	if _was_dead and not dead:
		_teleported()   # a respawn
	return rate


func _teleported() -> void:
	teleports += 1
	totals["teleports"] = int(totals.get("teleports", 0)) + 1
	if _secondary != null:
		_secondary.reset()


## A turn clip's time from the yaw travelled that way (a quarter turn a cycle).
func turn_time(side: String) -> float:
	var cyc := deg_to_rad(TURN_CYCLE_DEG)
	return fposmod(float(_turn_travel[side]), cyc) / cyc * float(_lengths.get("turn_" + side, 1.0))


## The sprint's speed for this actor (m/s): its profile's walk speed x the sprint action's speed_mult (7.5 at
## stage 1); 1.5 x k x 5 without a profile.
func sprint_speed() -> float:
	var profile: Variant = actor.get("profile") if actor != null and "profile" in actor else null
	var walk := float((profile as Dictionary).get("walk_speed_mps", 5.0)) if typeof(profile) == TYPE_DICTIONARY else 5.0 * body_scale
	var def: Variant = actor.get("sprint_def") if actor != null and "sprint_def" in actor else null
	var mult := float((def as ActionDef).param("speed_mult", 1.5)) if def is ActionDef else 1.5
	return walk * mult


## The fraction of the whole of `action` at `phase` / `f` (windup, active and recovery by their ticks).
static func action_fraction(action: ActionDef, phase: int, f: float) -> float:
	var w := float(action.windup_ticks)
	var a := float(action.active_ticks)
	var r := float(action.recovery_ticks)
	var total := maxf(w + a + r, 1.0)
	match phase:
		ActionDef.Phase.WINDUP:
			return clampf(f, 0.0, 1.0) * w / total
		ActionDef.Phase.ACTIVE:
			return (w + clampf(f, 0.0, 1.0) * a) / total
		ActionDef.Phase.RECOVERY:
			return (w + a + clampf(f, 0.0, 1.0) * r) / total
	return 1.0 if phase == ActionDef.Phase.DONE else 0.0


## The stomp clip's share (0..1) at `phase` / `f`: the windup onto the lift and the hold, [0, STOMP_PLANT], so
## the foot comes down as ACTIVE starts; ACTIVE and RECOVERY onto the plant's settle, [STOMP_PLANT, 1].
static func stomp_fraction(action: ActionDef, phase: int, f: float) -> float:
	if phase == ActionDef.Phase.WINDUP:
		return clampf(f, 0.0, 1.0) * STOMP_PLANT
	var a := float(action.active_ticks)
	var r := float(action.recovery_ticks)
	var after := 0.0
	if phase == ActionDef.Phase.ACTIVE:
		after = clampf(f, 0.0, 1.0) * a / maxf(a + r, 1.0)
	elif phase == ActionDef.Phase.RECOVERY:
		after = (a + clampf(f, 0.0, 1.0) * r) / maxf(a + r, 1.0)
	elif phase == ActionDef.Phase.DONE:
		after = 1.0
	return STOMP_PLANT + (1.0 - STOMP_PLANT) * after


## P64c: true where the arms hold the weapon in both hands as they strike (PoseBrainModifier's two-handed keys): an actor
## that is not the player - a rival giant, Harrok - carrying an axe.
func two_handed() -> bool:
	if _two_handed < 0:
		if not (actor is EnemyActor):
			_two_handed = 0
		else:
			var w: Variant = actor.get("weapon")
			if typeof(w) != TYPE_DICTIONARY or (w as Dictionary).is_empty():
				return false   # (the actor reads its record after this rig is ready)
			_two_handed = 1 if weapon_family() == "axe" else 0
	return _two_handed == 1


var _two_handed := -1


## The family of the weapon the actor carries ("club", "sword", "fists", "tree", ...; "club" without one).
func weapon_family() -> String:
	var w: Variant = actor.get("weapon") if actor != null and "weapon" in actor else null
	if typeof(w) != TYPE_DICTIONARY:
		return "club"
	var fam := str((w as Dictionary).get("family", ""))
	return fam if fam != "" else WeaponVisuals.shape_of(w)


func _set_grip_clip(clip: String) -> void:
	if clip == _grip_clip or _tree == null:
		return
	var lib := clip_library()
	if lib == null or not lib.has_animation(clip):
		clip = "grip_r"
	_grip_clip = clip
	var node := (_tree.tree_root as AnimationNodeBlendTree).get_node(&"grip_r_clip") as AnimationNodeAnimation
	node.animation = StringName(String(LIBRARY) + "/" + clip)


## The grip clip the right fist takes now ("grip_club", ...).
func grip_clip() -> String:
	return _grip_clip


## How much of fp_rest the arms take: all of it in first person at rest looking ahead, fading out as the view
## turns down from FP_REST_PITCH_DEG.x to .y degrees (looking down, the arm hangs as in M10 and the lower corners
## stay clear: test_first_person_shoulders); 0 otherwise.
func first_person_rest_weight() -> float:
	if not first_person_rest():
		return 0.0
	var cam: Variant = actor.get("camera_rig")
	var pitch := rad_to_deg(float((cam as Object).get("pitch"))) if cam != null and "pitch" in cam else 0.0
	return clampf((pitch - FP_REST_PITCH_DEG.y) / (FP_REST_PITCH_DEG.x - FP_REST_PITCH_DEG.y), 0.0, 1.0)


## True in first person while the brain is at rest: no action, no block, dodge or hold (the arms take fp_rest).
func first_person_rest() -> bool:
	var cam: Variant = actor.get("camera_rig") if actor != null and "camera_rig" in actor else null
	if cam == null or not (cam as Object).has_method("is_first_person") or not bool((cam as Object).call("is_first_person")):
		return false
	var s := rig_state()
	return s.get("action") == null and typeof(s.get("pose_override")) != TYPE_DICTIONARY and not bool(s.get("guarding", false)) \
		and int(s.get("state", 0)) == CombatController.State.LOCOMOTION and not bool(s.get("dead", false))


# --------------------------------------------------------------------------- flinches (P50)

## A hit taken from `from_local` (the attacker's place in the actor's own frame: -Z his front, +X his right),
## at `strength` (the flash's, 0..1): the flinch of that side, additive on the upper body (plan M11 §2.3).
## Refused during an attack's ACTIVE phase (the tested swing keeps its arm). Presentation only: called by
## HitFeedback, read by nothing.
func flinch(from_local: Vector3, strength: float) -> void:
	if _tree == null or strength <= 0.0:
		return
	var s := rig_state()
	var action: ActionDef = s.get("action")
	if action != null and action.is_attack() and int(s.get("phase", 0)) == ActionDef.Phase.ACTIVE:
		flinches_refused += 1
		totals["flinches_refused"] = int(totals.get("flinches_refused", 0)) + 1
		return
	var side := flinch_side(from_local)
	_flinch[side] = {"t": 0.0, "w": clampf(strength * FLINCH_GAIN, 0.0, FLINCH_GAIN)}
	flinches += 1
	totals["flinches"] = int(totals.get("flinches", 0)) + 1


## The side a hit from `from_local` lands on: "f" (in front, -Z), "b", "l" or "r" (+X).
static func flinch_side(from_local: Vector3) -> String:
	if absf(from_local.x) > absf(from_local.z):
		return "r" if from_local.x > 0.0 else "l"
	return "f" if from_local.z <= 0.0 else "b"


func _drive_flinches(delta: float, action: ActionDef, phase: int) -> void:
	if _flinch.is_empty():
		_send(P_FLINCH, 0.0)
		_open_gate(&"gate_flinch", false)
		return
	_open_gate(&"gate_flinch", true)
	var active := action != null and action.is_attack() and phase == ActionDef.Phase.ACTIVE
	for side: String in FLINCH_SIDES:
		if not _flinch.has(side):
			continue
		var f: Dictionary = _flinch[side]
		f.t = float(f.t) + delta * FLINCH_RATE
		if active:
			f.w = float(f.w) * exp(-FLINCH_CUT_RATE * delta)
		var length := float(_lengths.get("flinch_" + side, 0.3))
		if float(f.t) >= length or float(f.w) < 1e-3:
			_flinch.erase(side)
			continue
		_tree.set(P_FLINCH_T[side], float(f.t))
	# each side's clip at its own weight: the sum on the Add2, the sides' shares under it
	var wf := float(_flinch.f.w) if _flinch.has("f") else 0.0
	var wb := float(_flinch.b.w) if _flinch.has("b") else 0.0
	var wl := float(_flinch.l.w) if _flinch.has("l") else 0.0
	var wr := float(_flinch.r.w) if _flinch.has("r") else 0.0
	var sum := wf + wb + wl + wr
	_send(P_FLINCH, sum)
	if sum > 0.0:
		_send(P_FLINCH_SIDES, (wl + wr) / sum)
		_send(P_FLINCH_FB, wb / (wf + wb) if wf + wb > 0.0 else 0.0)
		_send(P_FLINCH_LR, wr / (wl + wr) if wl + wr > 0.0 else 0.0)


## Opens or closes the flinches' gate when that changes: the Transition switches at once.
func _open_gate(g: StringName, on: bool) -> void:
	if _gates.get(g, false) == on:
		return
	_gates[g] = on
	_tree.set(StringName("parameters/%s/transition_request" % g), "on" if on else "off")


## Sets a tree parameter when its value changed.
func _send(param: StringName, v: float) -> void:
	if _sent.get(param, -1.0) != v:
		_sent[param] = v
		_tree.set(param, v)


## The blend amounts (SLOT_PARAMS) and the gates (GATE_NAMES) from `eff` (source_weights()) and the gait's share,
## each set only when it changed: each source node's amount is its right half's share of the weight under it (0 with
## none), each gate open while anything under it weighs.
func _send_all(eff: Dictionary, gait: float) -> void:
	var st: float = eff.stance
	var br: float = eff.brace
	var tu: float = eff.turn
	var mo: float = eff.move
	var ch: float = eff.charge
	var so: float = eff.stomp
	var ro: float = eff.roar
	var la: float = eff.land
	var ai: float = eff.air
	var de: float = eff.dead
	var pulse := so + ro
	var fall := ai + de
	var tm := tu + mo
	var hi := ch + pulse + la + fall
	var run_w: float = _w.run
	var sprint_w: float = _w.sprint
	var fp_w: float = _w.fp
	var fist_w: float = _w.fist_l
	var want := _want
	want[0] = run_w
	want[1] = sprint_w
	want[2] = _w.charge_sprint
	want[3] = _w.turn_side
	want[4] = fp_w
	want[5] = _w.open_l
	want[6] = _w.grip_l
	want[7] = fist_w
	want[8] = _part(st + br + tm, hi)
	want[9] = _part(st + br, tm)
	want[10] = _part(st, br)
	want[11] = _part(tu, mo)
	want[12] = _part(ch + pulse, la + fall)
	want[13] = _part(ch, pulse)
	want[14] = _part(so, ro)
	want[15] = _part(la, fall)
	want[16] = _part(ai, de)
	for i in want.size():
		if want[i] != _sent_v[i]:
			_sent_v[i] = want[i]
			_tree.set(SLOT_PARAMS[i], want[i])
	var open := _want_gate
	open[0] = 1 if tu > 0.0 else 0
	open[1] = 1 if mo > 0.0 else 0
	open[2] = 1 if tm > 0.0 else 0
	open[3] = 1 if ch > 0.0 else 0
	open[4] = 1 if pulse > 0.0 else 0
	open[5] = 1 if fall > 0.0 else 0
	open[6] = 1 if ch + pulse > 0.0 else 0
	open[7] = 1 if la + fall > 0.0 else 0
	open[8] = 1 if hi > 0.0 else 0
	# inside the gait (the clips' shares as _drive_tree's seeks take them), the left fist and first person's arms
	open[9] = 1 if gait > 0.0 and run_w < 1.0 and sprint_w < 1.0 else 0
	open[10] = 1 if gait > 0.0 and run_w > 0.0 and sprint_w < 1.0 else 0
	open[11] = 1 if gait > 0.0 and sprint_w > 0.0 else 0
	open[12] = 1 if fist_w > 0.0 else 0
	open[13] = 1 if fp_w > 0.0 else 0
	for i in open.size():
		if open[i] != _sent_gate[i]:
			_sent_gate[i] = open[i]
			_tree.set(GATE_PARAMS[i], "on" if open[i] == 1 else "off")


## The right part's share of left + right (0 when the right has none).
static func _part(left: float, right: float) -> float:
	return right / (left + right) if right > 0.0 else 0.0


## The flinches running now: side -> weight (tests).
func flinch_weights() -> Dictionary:
	var out := {}
	for side: String in _flinch:
		out[side] = float(_flinch[side].w)
	return out


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
	_sway()   # P46: the hair's tips lag the head's motion
	_look_eyes()   # Gate A: the eyes toward the lock target or the camera's facing
	posed.emit()


## GiantLook.sway's step for this rig (P46), with what it looked up every frame held here (Gate A, lens 6): the head
## bone's index and the hair's and beard's card meshes, found again when the look or the materials change. The same
## numbers as GiantLook.sway: the head's place, its motion eased by GiantLook.sway_step over the wall clock's frame,
## written as `head_motion` in each shown card mesh's own space, at most GiantLook.SWAY_MAX_M; out of the tree the
## last frame is forgotten. Shell styles (no `head_motion` uniform) are left out.
func _sway() -> void:
	if _model == null or _skeleton == null:
		return
	if not _model.is_inside_tree() or not _skeleton.is_inside_tree():
		_sway_has = false
		return
	if _sway_dirty:
		_find_sway_meshes()
	if _sway_bone < 0:
		return
	var now := Time.get_ticks_usec()
	var pos: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_sway_bone)).origin
	var motion := Vector3.ZERO
	if _sway_has:
		var dt := clampf(float(now - _sway_t) / 1.0e6, 1.0 / 240.0, 0.1)
		motion = GiantLook.sway_step(_sway_motion, (pos - _sway_pos) / dt, dt)
	_sway_has = true
	_sway_pos = pos
	_sway_t = now
	_sway_motion = motion
	for mi: MeshInstance3D in _sway_meshes:
		if not is_instance_valid(mi):
			_sway_dirty = true
			continue
		if not mi.visible or not mi.is_inside_tree():
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter(&"head_motion", (mi.global_transform.basis.inverse() * motion).limit_length(GiantLook.SWAY_MAX_M))


## The eyes' `look` (P51's uniform on the Eyes material: x toward the giant's right, y up, at most EYE_LOOK_MAX):
## toward the lock target's focus point when the camera holds one, else along the camera's facing, level (ahead of
## the giant only: a camera that faces him from the front leaves the eyes ahead), in the head's own frame, eased at
## EYE_RATE a second. The iris slides by look x its radius (the shader's iris_r) of the eyeball's polar angle / pi,
## so an eye turned by an angle a takes a / (pi x iris_r): the quarter of the iris's radius is about 7.6 degrees.
## Written through GiantLook.set_param when it moves; presentation only (the camera and the lock are read).
func _look_eyes() -> void:
	if _eye_mat == null or _head_bone < 0 or not _skeleton.is_inside_tree():
		return
	var want := Vector2.ZERO
	var cam: Variant = actor.get("camera_rig") if actor != null and "camera_rig" in actor else null
	if cam is CameraRig and is_instance_valid(cam) and not bool(rig_state().get("dead", false)):
		var rig_cam := cam as CameraRig
		var head := _skeleton.get_bone_global_pose(_head_bone)
		var focus := rig_cam.lock_focus_point()
		var dir := Vector3.ZERO
		if focus != Vector3.INF:
			dir = focus - _skeleton.global_transform * head.origin
		elif rig_cam.camera != null:
			dir = -rig_cam.camera.global_transform.basis.z
			dir.y = 0.0   # the camera's pitch frames the view; only where it faces turns the eyes
		if dir.length_squared() > 1e-8:
			# into the skeleton's space, back through the head's turn from its rest (where it faces Body's front),
			# then into Body's axes
			var dir_s := _skeleton.global_transform.basis.orthonormalized().inverse() * dir.normalized()
			var turn := head.basis.orthonormalized() * _head_rest.inverse()
			var d := _mod.body_dir(turn.inverse() * dir_s)
			var ahead := -d.z
			if ahead > 0.05:
				var per := 1.0 / (PI * EYE_IRIS_R)
				want = Vector2(clampf(atan2(d.x, ahead) * per, -EYE_LOOK_MAX, EYE_LOOK_MAX),
					clampf(atan2(d.y, Vector2(d.x, ahead).length()) * per, -EYE_LOOK_MAX, EYE_LOOK_MAX))
	_eye_look = _eye_look.lerp(want, 1.0 - exp(-EYE_RATE * get_process_delta_time()))
	if _eye_look.distance_squared_to(_eye_sent) > 1e-8:
		_eye_sent = _eye_look
		GiantLook.set_param(_eye_mat, "look", _eye_look)


## The eyes' look now (tests).
func eye_look() -> Vector2:
	return _eye_look


func _find_sway_meshes() -> void:
	_sway_dirty = false
	_sway_meshes.clear()
	_sway_bone = _skeleton.find_bone(GiantLook.SWAY_BONE)
	_head_bone = _skeleton.find_bone("head")
	_head_rest = _skeleton.get_bone_global_rest(_head_bone).basis.orthonormalized() if _head_bone >= 0 else Basis()
	_eye_mat = null
	for id in GiantLook.meshes_of(_model.index, "eyes"):
		var eyes := GiantLook.mesh_node(_model, _model.index, id)
		if eyes != null and eyes.material_override is ShaderMaterial:
			_eye_mat = eyes.material_override as ShaderMaterial
			_eye_sent = Vector2(INF, INF)
	var meshes: Dictionary = _model.index.get("meshes", {})
	for category: String in ["hair", "beard"]:
		for id in GiantLook.meshes_of(_model.index, category):
			if GiantLook.mesh_kind(meshes[id]) != "hair":
				continue
			var mi := GiantLook.mesh_node(_model, _model.index, id)
			if mi != null:
				_sway_meshes.append(mi)


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
	_sway_dirty = true
	if _model != null:
		GiantLook.apply(_model, _model.index, look)
	if _secondary != null:
		_secondary.configure(SecondaryMotion.chains_for(_model.index, shown_meshes()))   # configure() resets
	_tint_dirty = true


## Growth rescales the body: the springs start again at rest at the new size (P50).
func set_body_scale(k: float) -> void:
	super.set_body_scale(k)
	if _secondary != null:
		_secondary.reset()


func model() -> GiantModel:
	return _model


func weapon_socket() -> Node3D:
	return _socket


func skeleton() -> Skeleton3D:
	return _skeleton


func modifier() -> PoseBrainModifier:
	return _mod


## The hair's, beard's and cape's springs (null without the layers).
func secondary() -> SecondaryMotion:
	return _secondary


func animation_tree() -> AnimationTree:
	return _tree


func layers_on() -> bool:
	return _layers


## This frame's source of the legs: "dead", "airborne", "landing", "stomp", "roar", "motion", "walking",
## "turning", "bracing" or "stance" (the class notes), and the tree's blend weights (BLEND_PARAMS' keys).
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
	if own_look != "":
		return own_look
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
## the meshes shown and the brain's footfalls; P50: secondary-motion frames, the chains running, the flinches
## played and refused, the teleports the springs reset on.
func skin_stats() -> Dictionary:
	return {"look": look_name(), "layers": _layers, "posed_frames": posed_frames,
		"modifier_runs": _mod.runs if _mod != null else 0, "held_visual_writes": held_visual_writes,
		"shown_meshes": shown_meshes(), "rig_footfalls": footfalls,
		"secondary_frames": _secondary.frames if _secondary != null else 0,
		"chains": Array(_secondary.chains) if _secondary != null else [], "flinches": flinches,
		"flinches_refused": flinches_refused, "teleports": teleports}
