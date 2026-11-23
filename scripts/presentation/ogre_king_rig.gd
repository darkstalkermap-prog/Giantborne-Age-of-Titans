class_name OgreKingRig
extends ActorRig
## The Ogre King in play (B2): his model (OgreKingModel, tools/giant/kit/ogre_king.py's asset) under his actor
## (TitanEnemy, enemy.ogre_king), posed from the actor's state on the frame clock as TitanRig poses Stoneback.
## Presentation only: it writes under its own Visual node and reads the actor (get_rig_state); nothing in the
## simulation reads it back.
##
##   Visual (OgreKingRig)
##   └ Body                  the box rig's lean and stagger are not used: the clips carry the body
##     ├ Model (OgreKingModel) the King, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip and its time from the brain's state (cross-faded over FADE_S on a change), each strike's keys the clip's
## own (the manifest's clip_keys: [start, wound, hit, past, end]) so the blow lands on the action's first active tick:
##   sector_pulse (the combo)  ability.boss_combo_1 `combo_a` (the ram heaved off the shoulder, cocked back and swung
##                             down across him), its chained second blow `combo_b` (back across flat, onto the
##                             shoulder again): the windup's first share draws to the wound pose, the rest swings to
##                             the hit, the active phase follows through, the recovery recovers;
##   cylinder_pulse (the slam) `slam` (the ram up two-handed, rocked back, brought down head-first before him: dust
##                             and a shake where its head strikes);
##   body_sweep (the charge)   `charge` over the windup (the ram levelled as a ram), `charge_run` while it runs (on
##                             the distance run), then idle; his reel after a wall, or a stagger: `reel`;
##   none (the phase roar)     `roar`;
##   down on a knee            `kneel` (the keg burst: his foot slides, the knee strikes at the clip's kneel key: dust,
##                             a shake), its last frame held, then `rise` over the down's last rise_s;
##   walking or running        `walk` / `run` on the distance walked (no slide); dead: `death`; else `idle`.
## A trophy shows its damage as its health wears (OgreKingModel.set_trophy_crack: the wood split along its grain,
## the metal dented); the frame it breaks it hides and a copy of it falls from where it was to the ground and lies
## there (tumbling as it falls), its splinters thrown (the level's DebrisPool: long wood shards, dark iron bits) in
## a puff of dust. Dying, the ram falls from his fist the same way. Broken trophies come back whole on a new attempt.

const FADE_S := 0.22
const MODEL_NAME := "Model"
## The debris of a broken trophy: splinters (long thin pieces) in the wood's colour, iron bits for the metal ones.
const SPLINTER := Vector3(1.4, 0.18, 0.28)
const WOOD_COLOR := Color(0.46, 0.33, 0.21)
const IRON_COLOR := Color(0.18, 0.17, 0.16)
const BRONZE_COLOR := Color(0.55, 0.40, 0.20)
const METAL_TROPHIES := {"trophy_crown": IRON_COLOR, "trophy_bell": BRONZE_COLOR}
## The camera shake of his blow and footfalls at the giant (full within SHAKE_NEAR_M, none beyond SHAKE_FAR_M): he
## is half Stoneback's size, so lighter.
const SLAM_SHAKE := 0.42
const COMBO_SHAKE := 0.12
const STEP_SHAKE := 0.07
const RUN_STEP_SHAKE := 0.13
const KNEEL_SHAKE := 0.3
const SHAKE_NEAR_M := 12.0
const SHAKE_FAR_M := 60.0
## A falling piece: gravity (m/s^2) and how fast it tumbles (rad/s).
const FALL_G := 14.0
const FALL_SPIN := 1.8
const GAIT_RUN_FROM := 4.3

var model: OgreKingModel = null
## Drawn by his skinned model (the people's layers on): the readability probe's flag, as BruteRig's. A boss: always
## skinned when it is, outside CreatureSlots' cap, its frames counted in CreatureSlots.totals as a boss brute's were.
var skinned := false
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0
var _stride := {"walk": 6.12, "run": 6.12}
var _dead_t := -1.0
var _stagger_t := 0.0
var _hidden: Dictionary = {}
var _keys: Dictionary = {}
## The pieces fallen to the ground ({piece: {"node", "vel", "spin", "axis", "landed"}}).
var fallen: Dictionary = {}
## Frames posed with the model (tests, stats); the trophies whose break was shown, in order; impacts and shakes.
var posed_frames := 0
var trophies_shown_broken: Array[String] = []
var slam_impacts := 0
var footfalls_shaken := 0
var knee_impacts := 0
var dust_raised := 0
var _foot_phase := -1
var _slammed_instance := -1
var _knelt_instance := -1


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()


func _build_model() -> void:
	if model != null or body == null:
		return
	model = OgreKingModel.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skinned = true
	_keys = OgreKingModel.clip_keys()
	var gaits: Dictionary = ((OgreKingModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
	for g: String in ["walk", "run"]:
		_stride[g] = float((gaits.get(g, {}) as Dictionary).get("stride_m", _stride[g]))
	var proxy := get_node_or_null("LodProxy") as GeometryInstance3D
	if proxy != null:
		proxy.visible = false
	for c in body.get_children():
		if c != model and c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false


func has_model() -> bool:
	return model != null


func _box_posed() -> bool:
	return model == null


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
	_show_trophies(s)
	_play(s, delta)
	_fall_step(delta)
	posed_frames += 1
	CreatureSlots.totals.skinned_frames = int(CreatureSlots.totals.skinned_frames) + 1
	CreatureSlots.totals.skinned_max = maxi(int(CreatureSlots.totals.skinned_max), 1)


# --------------------------------------------------------------------------- the trophies

func _show_trophies(s: Dictionary) -> void:
	var broken: Array = s.get("plates_broken", [])
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	if ps == null:
		return
	for p: Dictionary in ps.plates:
		var id := str(p.id)
		var piece := str(p.piece)
		var gone := broken.has(id)
		if bool(p.breakable) and not gone:
			var crack := OgreKingModel.crack_for(ps.health_frac(id))
			if not is_equal_approx(crack, model.trophy_crack(piece)):
				model.set_trophy_crack(piece, crack)
		if gone == bool(_hidden.get(id, false)):
			continue
		_hidden[id] = gone
		if gone:
			trophies_shown_broken.append(id)
			var at := model.piece_centre(piece)
			_drop(piece, (at - actor.global_position) * Vector3(1, 0, 1))
			model.set_trophy_visible(piece, false)
			var metal: Color = METAL_TROPHIES.get(piece, WOOD_COLOR)
			_burst(at, int(p.debris), WOOD_COLOR if not METAL_TROPHIES.has(piece) else metal, 1.0)
			if METAL_TROPHIES.has(piece):
				_burst(at, maxi(2, int(p.debris) / 2), WOOD_COLOR, 0.7)
			_dust(at, 3.0, 12, 5.0)
		else:
			model.set_trophy_visible(piece, true)
			model.set_trophy_crack(piece, 0.0)
			_unfall(piece)


## Splinters thrown from `at`, outward from his body and up; deterministic (presentation: the debris collides with
## the world only and is never read by the simulation).
func _burst(at: Vector3, count: int, color: Color, size: float) -> void:
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool if is_inside_tree() else null
	if pool == null or count <= 0:
		return
	var out := at - actor.global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 1e-4 else -actor.global_transform.basis.z
	var xs: Array[Transform3D] = []
	var vs: Array[Vector3] = []
	for i in count:
		var a := TAU * float(i) / float(count) + 0.37 * float(i % 5)
		var side := Vector3(cos(a), 0.0, sin(a))
		xs.append(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.6 * float(i % 3)), at + out * 0.8 + side * 0.4))
		vs.append((out * 6.0 + side * 3.5 + Vector3.UP * (4.0 + float(i % 3) * 2.0)) * size)
	pool.spawn(xs, vs, SPLINTER * size, color)


## A static copy of `piece` where it is drawn now, falling and tumbling to the ground away from his body.
func _drop(piece: String, out: Vector3) -> void:
	var mi := model.piece(piece)
	if mi == null or mi.mesh == null or fallen.has(piece):
		return
	var copy := MeshInstance3D.new()
	copy.name = "Fallen_" + piece
	copy.mesh = mi.mesh
	copy.material_override = mi.material_override
	copy.top_level = true
	add_child(copy)
	copy.global_transform = model.piece_transform(piece)
	var dir := out.normalized() if out.length() > 0.05 else -actor.global_transform.basis.z
	var axis := dir.cross(Vector3.UP).normalized()
	fallen[piece] = {"node": copy, "vel": dir * 2.5 + Vector3.UP * 1.5, "spin": FALL_SPIN * (0.7 + 0.1 * float(piece.length() % 5)),
		"axis": axis if axis.length() > 0.1 else Vector3.RIGHT, "landed": false}


func _fall_step(delta: float) -> void:
	var ground := actor.global_position.y
	for piece: String in fallen:
		var f: Dictionary = fallen[piece]
		if bool(f.landed):
			continue
		var n := f.node as MeshInstance3D
		var v: Vector3 = f.vel
		v.y -= FALL_G * delta
		f.vel = v
		var t := n.global_transform
		var c := t * n.mesh.get_aabb().get_center()
		var turn := Basis(f.axis as Vector3, float(f.spin) * delta)
		t = Transform3D(turn, Vector3.ZERO) * Transform3D(Basis(), -c) * t
		t.origin += c + v * delta
		n.global_transform = t
		var low := INF
		var a := n.mesh.get_aabb()
		for i in 8:
			low = minf(low, (t * a.get_endpoint(i)).y)
		if low <= ground + 0.02:
			t.origin.y += ground + 0.02 - low
			n.global_transform = t
			f.landed = true
			_dust(t * a.get_center(), 2.5, 10, 4.0)
			_shake_at(t.origin, 0.12)


func _unfall(piece: String) -> void:
	if not fallen.has(piece):
		return
	(fallen[piece].node as Node).queue_free()
	fallen.erase(piece)


## True once a fallen copy of `piece` lies on the ground (tests).
func fallen_landed(piece: String) -> bool:
	return fallen.has(piece) and bool(fallen[piece].landed)


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(OgreKingModel.LIBRARY):
		return
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var dead := bool(s.get("dead", false))
	var staggered := bool(s.get("staggered", false))
	var clip := "idle"
	var t := -1.0
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
	var down: Dictionary = s.get("down", {})
	if dead:
		pass
	elif not down.is_empty() and _has("kneel"):
		var dt := float(down.get("t", 0.0))
		var rise_from := float(down.get("total", 0.0)) - float(down.get("rise_s", 0.0))
		if dt < rise_from or not _has("rise"):
			clip = "kneel"
			t = minf(dt, _len("kneel"))
		else:
			clip = "rise"
			t = clampf((dt - rise_from) / maxf(float(down.get("rise_s", 1.0)), 1e-3), 0.0, 1.0) * _len("rise")
	elif staggered or bool(s.get("reeling", false)):
		clip = "reel"
		var span := _len("reel")
		t = minf(_stagger_t, span) if staggered else lerpf(0.0, span, TitanRig._action_share(action, phase, f))
	elif action != null and action.hit_shape == "sector_pulse":
		clip = "combo_b" if action.id.ends_with("_2") else "combo_a"
		t = _strike(clip, phase, f)
	elif action != null and action.hit_shape == "cylinder_pulse":
		clip = "slam"
		t = _strike(clip, phase, f)
	elif action != null and action.hit_shape == "body_sweep":
		if phase == ActionDef.Phase.WINDUP:
			clip = "charge"
			t = _len("charge") * (1.0 - (1.0 - f) * (1.0 - f))
		elif phase == ActionDef.Phase.ACTIVE and speed > 0.5:
			_gait += speed * delta
			clip = "charge_run"
			t = fposmod(_gait / maxf(float(_stride.run), 0.1), 1.0) * _len(clip)
	elif action != null and action.hit_shape == "none":
		clip = "roar"
		t = _len("roar") * TitanRig._action_share(action, phase, f)
	elif speed > 0.3:
		_gait += speed * delta
		clip = "run" if speed >= GAIT_RUN_FROM else "walk"
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * _len(clip)
	if not _has(clip):
		clip = "idle"
		t = -1.0
	var full := StringName(String(OgreKingModel.LIBRARY) + "/" + clip)
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
	_feel(clip, t, before, length)
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t


## A strike clip's time from its keys (the manifest's clip_keys, the clip's whole length without them).
func _strike(clip: String, phase: int, f: float) -> float:
	var k: Array = _keys.get(clip, [])
	if k.size() < 5:
		var L := _len(clip)
		k = [0.0, L * 0.35, L * 0.5, L * 0.6, L]
	var share := float(k[1]) / maxf(float(k[2]), 1e-3)
	return TitanRig._strike_time(phase, f, k, share)


## The slam's dust and shake as its clip passes the blow; the combo's lighter thud; the knee's; the footfalls'
## (each half of a walk, run or charge cycle); dying, the ram falls from his fist.
func _feel(clip: String, t: float, before: float, length: float) -> void:
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	if clip == "slam" and hit > 0.0 and t >= hit and before < hit + 0.25 and _slammed_instance != _instance():
		_slammed_instance = _instance()
		slam_impacts += 1
		var at := model.ram_head()
		at.y = actor.global_position.y
		_dust(at, 5.0, 22, 8.0)
		_shake_at(at, SLAM_SHAKE)
	var kh := float(_keys.get("kneel_hit", 0.55))
	if clip == "kneel" and t >= kh and before < kh + 0.25 and _knelt_instance != _down_count():
		_knelt_instance = _down_count()
		knee_impacts += 1
		var knee := actor.global_position + actor.global_transform.basis.x * 1.0
		_dust(knee, 4.0, 16, 6.0)
		_shake_at(knee, KNEEL_SHAKE)
	if clip in ["walk", "run", "charge_run"] and length > 0.0:
		var half := int(floor(t / length * 2.0))
		if _foot_phase >= 0 and half != _foot_phase:
			footfalls_shaken += 1
			_shake_at(actor.global_position, STEP_SHAKE if clip == "walk" else RUN_STEP_SHAKE)
			if clip != "walk":
				_dust(actor.global_position, 2.5, 6, 3.0)
		_foot_phase = half
	else:
		_foot_phase = -1
	var drop := float(_keys.get("death_drop", 0.5))
	if clip == "death":
		if t >= drop and not fallen.has("ram"):
			_drop("ram", actor.global_transform.basis.x)
			model.piece("ram").visible = false
	elif fallen.has("ram"):
		_unfall("ram")
		model.piece("ram").visible = true


func _shake_at(at: Vector3, amount: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer if is_inside_tree() else null
	if p == null or p.camera_rig == null:
		return
	var d := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
	var k := 1.0 - clampf((d - SHAKE_NEAR_M) / (SHAKE_FAR_M - SHAKE_NEAR_M), 0.0, 1.0)
	if k > 0.0:
		p.camera_rig.add_shake(amount * k)


func _dust(at: Vector3, size: float, count: int, speed: float) -> void:
	if DustBurst.puff(self, at, size, count, speed) != null:
		dust_raised += 1


func _has(clip: String) -> bool:
	return model != null and model.has_clip(clip)


func _len(clip: String) -> float:
	return BruteRig.clip_length(OgreKingModel.CREATURE, clip)


func _down_count() -> int:
	return int(actor.get("topples")) if actor != null and "topples" in actor else 0


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
