class_name TitanRig
extends ActorRig
## A signature titan in play (A2): Stoneback's model (StonebackRig, A1's asset) under his actor (TitanEnemy), posed
## from the actor's state on the frame clock as BruteRig poses the brutes. Presentation only: it writes under its own
## Visual node and reads the actor (get_rig_state); nothing in the simulation reads it back.
##
##   Visual (TitanRig)
##   └ Body                  the box rig's lean and stagger are not used: the clips carry the body
##     ├ Model (StonebackRig) the creature, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip and its time from the brain's state (cross-faded over FADE_S on a change). Each attack finishes A1's
## wind-up: the wind-up clip plays over the first share of the action's windup, the strike clip's swing over the
## rest so that the blow lands on the first active tick, its follow-through and the recovery over the active and
## recovery phases (STRIKES: per hit shape, the windup share the wind-up clip takes and the strike clip's key times):
##   titan_shock (the smash)   `overhead` then `smash` (the trunk comes down two-handed, the root ball strikes the
##                             ground at SMASH_HIT_S, held, he straightens up);
##   sector_pulse (the sweep)  `sweep` (drawn back low to the right, swung round through his front, round to the
##                             left, recovered); one clip over the whole action;
##   body_sweep (the charge)   `charge` over the windup (the shoulder lowered), `charge_run` while it runs (on the
##                             distance run, the run's stride), then back to idle; his reel after a wall: `reel`;
##   projectile (the boulder)  `rip` (he crouches, tears the boulder out of the ground at his left foot and lifts it),
##                             then `throw` (A1's draw back over the shoulder), then `release` (the lob, the follow
##                             through); the boulder shows in his hand from the rip's grip to the release;
##   none (the rage)           `roar`; a stagger (a poise break, a plate breaking) `reel` on its own clock;
##   walking or running        `walk` / `run` on the distance walked (no slide); dead: `death`; else `idle`.
## A plate the actor lists in plates_broken hides (StonebackRig.set_plate_visible); the frame it breaks, stone
## flies from it (the level's DebrisPool, grey pieces). The ripped boulder throws dirt at his foot.

const FADE_S := 0.22
const MODEL_NAME := "Model"
## Per strike: the share of the windup A1's wind-up clip takes; the strike clip's time at the blow (the first
## active tick) and where the active phase ends in it.
const SMASH_WINDUP_SHARE := 0.8
const SMASH_HIT_S := 0.3
const SMASH_HOLD_S := 0.6
const SWEEP_WOUND_S := 0.9
const SWEEP_HIT_S := 1.2
const SWEEP_PAST_S := 1.45
const BOULDER_RIP_SHARE := 0.42
const BOULDER_THROW_SHARE := 0.9
const RELEASE_AT_S := 0.25
## The rip clip's time the left hand closes on the boulder (it shows from here: StonebackRig.BOULDER_SPANS).
const RIP_GRIP_S := 0.75
## The stone debris of a broken plate: the pieces' size (m) and colour.
const STONE_PIECE := Vector3(1.5, 0.9, 1.3)
const STONE_COLOR := Color(0.47, 0.45, 0.41)
const DIRT_COLOR := Color(0.36, 0.30, 0.23)

var model: StonebackRig = null
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0
var _stride := {"walk": 14.8, "run": 14.8}
var _run_from := 5.4
var _dead_t := -1.0
var _stagger_t := 0.0
var _hidden: Dictionary = {}
var _ripped_instance := -1
## Frames posed with the model (tests, stats).
var posed_frames := 0
## Plates whose break this rig showed (tests).
var plates_shown_broken: Array[String] = []


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()


func _build_model() -> void:
	if model != null or body == null:
		return
	model = StonebackRig.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var gaits := _gaits()
	for g: String in ["walk", "run"]:
		_stride[g] = float((gaits.get(g, {}) as Dictionary).get("stride_m", _stride[g]))
	var proxy := get_node_or_null("LodProxy") as GeometryInstance3D
	if proxy != null:
		proxy.visible = false
	for c in body.get_children():
		if c != model and c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false


static func _gaits() -> Dictionary:
	BruteRig.creature_index()
	return ((BruteRig._facts.get(StonebackRig.CREATURE, {}) as Dictionary).get("clips", {}) as Dictionary).get("gaits", {})


func has_model() -> bool:
	return model != null


## The model's clips are the brain's poses: the box pivots are not posed.
func _box_posed() -> bool:
	return model == null


## The clips carry the body (the fall, the reel): Body stays where the actor stands.
func _update_body(s: Dictionary, delta: float) -> void:
	if model == null:
		super._update_body(s, delta)
		return
	body.rotation = body.rotation.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	body.position = body.position.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))


func _process(delta: float) -> void:
	super._process(delta)
	if model == null or actor == null or not actor.has_method("get_rig_state"):
		return
	var s := rig_state()
	_show_plates(s)
	_play(s, delta)
	posed_frames += 1


# --------------------------------------------------------------------------- the plates

func _show_plates(s: Dictionary) -> void:
	var broken: Array = s.get("plates_broken", [])
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	if ps == null:
		return
	for p: Dictionary in ps.plates:
		var id := str(p.id)
		var gone := broken.has(id)
		if gone == bool(_hidden.get(id, false)):
			continue
		_hidden[id] = gone
		model.set_plate_visible(str(p.piece), not gone)
		if gone:
			plates_shown_broken.append(id)
			_burst(str(p.piece), int(p.debris), STONE_COLOR, 1.0)


## Stone (or dirt) thrown from the posed piece's centre, outward and up; deterministic per piece (presentation:
## the debris collides with the world only and is never read by the simulation).
func _burst(piece: String, count: int, color: Color, size: float) -> void:
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool if is_inside_tree() else null
	if pool == null or count <= 0:
		return
	var at := _piece_centre(piece)
	var out := at - actor.global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 1e-4 else -actor.global_transform.basis.z
	var xs: Array[Transform3D] = []
	var vs: Array[Vector3] = []
	for i in count:
		var a := TAU * float(i) / float(count) + 0.37 * float(hash(piece) % 7)
		var side := Vector3(cos(a), 0.0, sin(a))
		xs.append(Transform3D(Basis(Vector3.UP, a), at + out * 1.6 + side * 0.8))
		vs.append((out * 9.0 + side * 4.5 + Vector3.UP * (6.0 + float(i % 3) * 2.5)) * size)
	pool.spawn(xs, vs, STONE_PIECE * size, color)


func _piece_centre(piece: String) -> Vector3:
	var mi := model.piece(piece) if model != null else null
	if mi == null or mi.mesh == null:
		return actor.global_position + Vector3.UP * 12.0
	var skel := model.skeleton
	var aabb := mi.mesh.get_aabb()
	var c := mi.global_transform * aabb.get_center()
	# a skinned piece's mesh AABB is its rest pose: follow its main bone's posed offset
	if skel != null:
		var bone := _piece_bone(piece)
		var i := skel.find_bone(bone)
		if i >= 0:
			var rest := skel.global_transform * skel.get_bone_global_rest(i)
			var now := skel.global_transform * skel.get_bone_global_pose(i)
			c = now * (rest.affine_inverse() * c)
	return c


static func _piece_bone(piece: String) -> String:
	match piece:
		"plate_shoulder_l":
			return "upperarm_l"
		"plate_shoulder_r":
			return "upperarm_r"
		"plate_brow":
			return "head"
		"plate_back":
			return "spine_03"
		"boulder":
			return "hand_l"
	return "spine_02"


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(StonebackRig.LIBRARY):
		return
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var dead := bool(s.get("dead", false))
	var staggered := bool(s.get("staggered", false))
	var clip := "idle"
	var t := -1.0
	var boulder := false
	if dead:
		_dead_t = maxf(_dead_t, 0.0) + delta
		clip = "death"
		t = minf(_dead_t, _len("death"))
	else:
		_dead_t = -1.0
	if staggered and not dead:
		_stagger_t += delta
	else:
		_stagger_t = 0.0
	if dead:
		pass
	elif staggered or bool(s.get("reeling", false)):
		clip = "reel"
		var span := _len("reel")
		t = minf(_stagger_t, span) if staggered else lerpf(0.0, span, _action_share(action, phase, f))
	elif action != null and action.hit_shape == TitanEnemy.SHOCK_SHAPE:
		var picked := _smash_time(phase, f)
		clip = picked[0]
		t = picked[1]
	elif action != null and action.hit_shape == "sector_pulse":
		clip = "sweep"
		t = _strike_time(phase, f, [0.0, SWEEP_WOUND_S, SWEEP_HIT_S, SWEEP_PAST_S, _len("sweep")], 0.85)
	elif action != null and action.hit_shape == "body_sweep":
		if phase == ActionDef.Phase.WINDUP:
			clip = "charge"
			t = _len("charge") * (1.0 - (1.0 - f) * (1.0 - f))
		elif phase == ActionDef.Phase.ACTIVE and speed > 0.5:
			_gait += speed * delta
			clip = "charge_run" if _has("charge_run") else "run"
			t = fposmod(_gait / maxf(float(_stride.run), 0.1), 1.0) * _len(clip)
		else:
			clip = "idle"
	elif action != null and action.hit_shape == "projectile":
		var picked := _boulder_time(action, phase, f)
		clip = picked[0]
		t = picked[1]
		boulder = bool(picked[2])
	elif action != null and action.hit_shape == "none":
		clip = "roar"
		t = _len("roar") * _action_share(action, phase, f)
	elif speed > 0.3:
		_gait += speed * delta
		clip = "run" if speed >= _run_from else "walk"
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * _len(clip)
	if not _has(clip):
		clip = "idle"
		t = -1.0
	var full := StringName(String(StonebackRig.LIBRARY) + "/" + clip)
	if clip != _clip:
		var first := _clip == ""
		_clip = clip
		player.play(full, 0.0 if first else FADE_S)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta
		t = fposmod(_clip_t, _len(clip))
	var loops := clip in ["idle", "walk", "run", "charge_run"]
	var length := _len(clip)
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t
	model.set_boulder(boulder)


func _has(clip: String) -> bool:
	return model != null and model.player != null \
		and model.player.has_animation(StringName(String(StonebackRig.LIBRARY) + "/" + clip))


func _len(clip: String) -> float:
	return BruteRig.clip_length(StonebackRig.CREATURE, clip)


## The whole action's progress (0..1) over its three phases by their lengths.
static func _action_share(a: ActionDef, phase: int, f: float) -> float:
	if a == null:
		return 0.0
	var w := float(a.windup_ticks)
	var ac := float(a.active_ticks)
	var r := float(a.recovery_ticks)
	var total := maxf(w + ac + r, 1.0)
	match phase:
		ActionDef.Phase.WINDUP:
			return f * w / total
		ActionDef.Phase.ACTIVE:
			return (w + f * ac) / total
		ActionDef.Phase.RECOVERY:
			return (w + ac + f * r) / total
	return 0.0


## A strike clip's time: keys [start, wound (the end of the draw), hit (the blow, the first active tick), past (the
## end of the active phase), end]; the windup's first `share` draws to `wound` (eased out), its rest swings to
## `hit`; the active phase follows through to `past`; the recovery to the end.
static func _strike_time(phase: int, f: float, keys: Array, share: float) -> float:
	match phase:
		ActionDef.Phase.WINDUP:
			if f < share:
				var u := f / share
				return lerpf(float(keys[0]), float(keys[1]), 1.0 - (1.0 - u) * (1.0 - u))
			var v := (f - share) / maxf(1.0 - share, 1e-3)
			return lerpf(float(keys[1]), float(keys[2]), v * v)   # accelerating into the blow
		ActionDef.Phase.ACTIVE:
			return lerpf(float(keys[2]), float(keys[3]), f)
		ActionDef.Phase.RECOVERY:
			return lerpf(float(keys[3]), float(keys[4]), f)
	return float(keys[0])


## The smash: A1's `overhead` over the windup's first SMASH_WINDUP_SHARE (eased out: the trunk goes up fast and
## settles at the top), then `smash` from its start to SMASH_HIT_S (the downswing, accelerating), held to
## SMASH_HOLD_S over the active phase, and his straightening up over the recovery.
func _smash_time(phase: int, f: float) -> Array:
	if phase == ActionDef.Phase.WINDUP and f < SMASH_WINDUP_SHARE:
		var u := f / SMASH_WINDUP_SHARE
		return ["overhead", _len("overhead") * (1.0 - (1.0 - u) * (1.0 - u))]
	return ["smash", _strike_time(phase, f, [0.0, 0.0, SMASH_HIT_S, SMASH_HOLD_S, _len("smash")], SMASH_WINDUP_SHARE)]


## The boulder: `rip` over the windup's first BOULDER_RIP_SHARE, A1's `throw` to BOULDER_THROW_SHARE, then `release`
## to RELEASE_AT_S at the launch (the first active tick) and on over the recovery. [clip, time, boulder shown].
func _boulder_time(action: ActionDef, phase: int, f: float) -> Array:
	if phase == ActionDef.Phase.WINDUP:
		if f < BOULDER_RIP_SHARE:
			var t := _len("rip") * f / BOULDER_RIP_SHARE
			if t >= RIP_GRIP_S and _ripped_instance != _instance():
				_ripped_instance = _instance()
				_burst("boulder", 6, DIRT_COLOR, 0.7)
			return ["rip", t, t >= RIP_GRIP_S]
		if f < BOULDER_THROW_SHARE:
			var u := (f - BOULDER_RIP_SHARE) / (BOULDER_THROW_SHARE - BOULDER_RIP_SHARE)
			return ["throw", _len("throw") * (1.0 - (1.0 - u) * (1.0 - u)), true]
		var v := (f - BOULDER_THROW_SHARE) / (1.0 - BOULDER_THROW_SHARE)
		return ["release", RELEASE_AT_S * v * v, true]
	var share := _action_share(action, phase, f)
	var after := (share - _action_share(action, ActionDef.Phase.ACTIVE, 0.0)) / maxf(1.0 - _action_share(action, ActionDef.Phase.ACTIVE, 0.0), 1e-3)
	return ["release", lerpf(RELEASE_AT_S, _len("release"), clampf(after, 0.0, 1.0)), false]


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
