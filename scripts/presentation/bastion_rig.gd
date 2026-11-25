class_name BastionRig
extends ActorRig
## The Broken Warden in play (C2): his model (BastionModel, tools/giant/kit/bastion.py's asset) under his actor
## (TitanEnemy, enemy.bastion), posed from the actor's state on the frame clock as RootwardenRig poses the warden.
## Presentation only: it writes under its own Visual node and reads the actor (get_rig_state) and the events of his
## blows; nothing in the simulation reads it back.
##
##   Visual (BastionRig)
##   └ Body                  the clips carry the body
##     ├ Model (BastionModel) the warden, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip by the action he performs (its id's last word), each strike's keys the clip's own (the manifest's
## clip_keys: [start, wound, hit, past, end]) so the blow lands on the action's first active tick:
##   bash     the shield drawn in and driven out before him in a lunge (dust at the shield's foot);
##   hammer   the bar up over his right shoulder and down over the shield's rim: its tip strikes the ground (dust,
##            a shake at the tip; the shock's pulses raise dust along the line);
##   sweep    the bar drawn back low on his right, swung round to his left;
##   charge   `charge` over the windup (the shoulder set into the shield), `charge_run` while it runs; his reel after
##            his walls stopped him `reel`;
##   stomp    the knee raised behind the shield, the foot driven down (dust, a shake);
##   rearm    his second phase's enter action (the shield gone: the bar taken two-handed);
##   smash2, sweep2  the two-handed strikes of his second phase;
##   asleep   `dormant` (bound into his wall, the head bowed); waking, `roar` once;
##   a stagger `reel`, his guard broken `guardbreak` (the shield struck out wide); down on a knee `kneel` (behind the
##   shield planted before him), held, `rise`; walking or running `walk` / `run` on the distance walked (`walk2` /
##   `run2` once the shield is gone, and `idle2`); dead `death`.
## His plates: cracking as their stone wears, broken (hidden, a copy of the piece falls and lies on the ground, stone
## and iron fly, dust). The shield's copy is his disarm: it falls from his hand and stays where it lies until a new
## attempt (`fallen_shield`). A blow his guard catches throws chips of stone off the shield's face; his guard
## broken, dust and stone off it.

const FADE_S := 0.22
const MODEL_NAME := "Model"
const CHIP := Vector3(0.9, 0.5, 0.7)
const STONE_COLOR := Color(0.52, 0.50, 0.46)
const IRON_COLOR := Color(0.16, 0.15, 0.14)
const DIRT_COLOR := Color(0.32, 0.27, 0.21)
## The shakes at the giant (full within SHAKE_NEAR_M, none beyond SHAKE_FAR_M).
const STOMP_SHAKE := 0.6
const SMASH_SHAKE := 0.55
const BASH_SHAKE := 0.35
const STEP_SHAKE := 0.2
const RUN_STEP_SHAKE := 0.3
const KNEEL_SHAKE := 0.5
const FALL_SHAKE := 0.75
const SHIELD_SHAKE := 0.45
const SHAKE_NEAR_M := 24.0
const SHAKE_FAR_M := 120.0
const FALL_G := 14.0
const FALL_SPIN := 1.0
const GAIT_RUN_FROM := 5.2
## The strikes that take their clip's keys (the rest: their own handling).
const STRIKES := ["bash", "hammer", "sweep", "stomp", "smash2", "sweep2"]

var model: BastionModel = null
var skinned := false
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0
var _stride := {"walk": 13.4, "run": 13.4, "walk2": 13.4, "run2": 13.4, "charge_run": 13.4}
var _dead_t := -1.0
var _stagger_t := 0.0
var _wake_t := -1.0
var _was_dormant := false
var _hidden: Dictionary = {}
var _keys: Dictionary = {}
## The pieces fallen to the ground ({piece: {"node", "vel", "spin", "axis", "landed"}}).
var fallen: Dictionary = {}
## Tests and stats.
var posed_frames := 0
var plates_shown_broken: Array[String] = []
var footfalls_shaken := 0
var impacts := 0
var knee_impacts := 0
var dust_raised := 0
var guard_chips := 0
var guard_breaks_shown := 0
var _foot_phase := -1
var _struck_instance := -1
var _knelt_instance := -1
var _fell_dead := false


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()
	Events.area_pulse.connect(_on_area_pulse)
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.titan_guard_broken.connect(_on_guard_broken)


func _exit_tree() -> void:
	for pair: Array in [[Events.area_pulse, _on_area_pulse], [Events.hit_resolved, _on_hit_resolved],
			[Events.titan_guard_broken, _on_guard_broken]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _build_model() -> void:
	if model != null or body == null:
		return
	model = BastionModel.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skinned = true
	_keys = BastionModel.clip_keys()
	var gaits: Dictionary = ((BastionModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
	for g: String in ["walk", "run"]:
		var stride := float((gaits.get(g, {}) as Dictionary).get("stride_m", _stride[g]))
		_stride[g] = stride
		_stride[g + "2"] = stride
	_stride["charge_run"] = _stride["run"]
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
	_show_plates(s)
	_play(s, delta)
	_fall_step(delta)
	posed_frames += 1
	CreatureSlots.totals.skinned_frames = int(CreatureSlots.totals.skinned_frames) + 1
	CreatureSlots.totals.skinned_max = maxi(int(CreatureSlots.totals.skinned_max), 1)


# --------------------------------------------------------------------------- the plates

func _show_plates(s: Dictionary) -> void:
	var broken: Array = s.get("plates_broken", [])
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	if ps == null:
		return
	for p: Dictionary in ps.plates:
		var id := str(p.id)
		var piece := str(p.piece)
		if piece == "" or model.piece(piece) == null:
			continue
		var gone := broken.has(id)
		if bool(p.breakable) and not gone:
			var crack := BastionModel.crack_for(ps.health_frac(id))
			if not is_equal_approx(crack, model.plate_crack(piece)):
				model.set_plate_crack(piece, crack)
		if gone == bool(_hidden.get(id, false)):
			continue
		_hidden[id] = gone
		if gone:
			plates_shown_broken.append(id)
			var at := model.piece_centre(piece)
			_drop(piece, (at - actor.global_position) * Vector3(1, 0, 1))
			model.set_plate_visible(piece, false)
			_chips(at, int(p.debris), STONE_COLOR, 1.0)
			_chips(at, maxi(2, int(p.debris) / 3), IRON_COLOR, 0.6)
			_dust(at, 5.0, 16, 6.0)
		else:
			# whole again: a new attempt
			model.set_plate_visible(piece, true)
			model.set_plate_crack(piece, 0.0)
			_unfall(piece)


func _chips(at: Vector3, count: int, color: Color, size: float) -> void:
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
		xs.append(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.5 * float(i % 3)), at + out + side * 0.5))
		vs.append((out * 6.0 + side * 4.0 + Vector3.UP * (5.0 + float(i % 3) * 2.0)) * size)
	pool.spawn(xs, vs, CHIP * size, color)


## A broken piece's copy falls from him and lies where it lands (the shield's stays: it is his disarm).
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
	# (the shield topples outward off his arm; the plates fall away from him)
	fallen[piece] = {"node": copy, "vel": dir * (2.0 if piece == "shield" else 3.0) + Vector3.UP * 1.0,
		"spin": FALL_SPIN * (1.4 if piece == "shield" else 1.0),
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
			_dust(t * a.get_center(), 6.0 if piece == "shield" else 3.0, 18 if piece == "shield" else 10, 5.0)
			_shake_at(t.origin, SHIELD_SHAKE if piece == "shield" else 0.14)


func _unfall(piece: String) -> void:
	if not fallen.has(piece):
		return
	(fallen[piece].node as Node).queue_free()
	fallen.erase(piece)


func fallen_landed(piece: String) -> bool:
	return fallen.has(piece) and bool(fallen[piece].landed)


## The shield where it fell (null while he holds it).
func fallen_shield() -> MeshInstance3D:
	return fallen.get("shield", {}).get("node") as MeshInstance3D if fallen.has("shield") else null


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(BastionModel.LIBRARY):
		return
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var dead := bool(s.get("dead", false))
	var staggered := bool(s.get("staggered", false))
	var dormant := bool(s.get("dormant", false))
	var two := bool(s.get("disarmed", false))
	if _was_dormant and not dormant and not dead:
		_wake_t = 0.0   # waking: the roar once
	_was_dormant = dormant
	var clip := "idle2" if two else "idle"
	var t := -1.0
	if dead:
		_dead_t = maxf(_dead_t, 0.0) + delta
		clip = "death"
		t = minf(_dead_t, _len("death"))
	else:
		_dead_t = -1.0
		_fell_dead = false
	if staggered and not dead:
		_stagger_t += delta
	else:
		_stagger_t = 0.0
	var down: Dictionary = s.get("down", {})
	var kind := _kind(action)
	if dead:
		pass
	elif dormant:
		clip = "dormant"
		_wake_t = -1.0
	elif not down.is_empty() and _has("kneel"):
		var dt := float(down.get("t", 0.0))
		var rise_from := float(down.get("total", 0.0)) - float(down.get("rise_s", 0.0))
		if dt < rise_from or not _has("rise"):
			clip = "kneel"
			t = minf(dt, _len("kneel"))
		else:
			clip = "rise"
			t = clampf((dt - rise_from) / maxf(float(down.get("rise_s", 1.0)), 1e-3), 0.0, 1.0) * _len("rise")
	elif staggered:
		clip = "guardbreak" if str(s.get("stagger_reason", "")) == TitanEnemy.GUARD_REASON and not two else "reel"
		t = minf(_stagger_t, _len(clip))
	elif kind in STRIKES:
		clip = kind
		t = _strike(clip, phase, f)
	elif kind == "charge":
		if phase == ActionDef.Phase.WINDUP:
			clip = "charge"
			t = _len("charge") * minf(1.0, f * 1.05)
		elif phase == ActionDef.Phase.ACTIVE and speed > 0.5:
			_gait += speed * delta
			clip = "charge_run"
			t = fposmod(_gait / maxf(float(_stride["charge_run"]), 0.1), 1.0) * _len("charge_run")
		else:
			clip = "charge"
			t = _len("charge") * (1.0 - clampf(f, 0.0, 1.0))
	elif kind == "rearm":
		clip = "rearm"
		t = _len("rearm") * TitanRig._action_share(action, phase, f)
	elif kind == "reel" or (action != null and action.hit_shape == "none"):
		clip = "reel"
		t = _len("reel") * TitanRig._action_share(action, phase, f)
	elif _wake_t >= 0.0 and _wake_t < _len("roar"):
		_wake_t += delta
		clip = "roar"
		t = minf(_wake_t, _len("roar"))
	elif speed > 0.3:
		_gait += speed * delta
		clip = ("run" if speed >= GAIT_RUN_FROM else "walk") + ("2" if two else "")
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * _len(clip)
	if clip != "roar" or _wake_t >= _len("roar"):
		_wake_t = -1.0 if clip != "roar" else _wake_t
	if not _has(clip):
		clip = "idle"
		t = -1.0
	var full := StringName(String(BastionModel.LIBRARY) + "/" + clip)
	if clip != _clip:
		var first := _clip == ""
		_clip = clip
		player.play(full, 0.0 if first else FADE_S)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta
		t = fposmod(_clip_t, _len(clip))
	var loops := clip in ["idle", "walk", "run", "idle2", "walk2", "run2", "dormant", "charge_run"]
	var length := _len(clip)
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	_feel(clip, t, before, length)
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t


## The kind of an action by its id's last word (ability.bastion_smash2 -> "smash2").
static func _kind(a: ActionDef) -> String:
	if a == null:
		return ""
	var word := a.id.get_slice(".", 1).trim_prefix("bastion_")
	return word


func _strike(clip: String, phase: int, f: float) -> float:
	var k: Array = _keys.get(clip, [])
	if k.size() < 5:
		var L := _len(clip)
		k = [0.0, L * 0.35, L * 0.5, L * 0.6, L]
	var share := float(k[1]) / maxf(float(k[2]), 1e-3)
	return TitanRig._strike_time(phase, f, k, share)


## The blows' dust and shake as their clips pass them; the footfalls'; his fall.
func _feel(clip: String, t: float, before: float, length: float) -> void:
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	if clip in STRIKES and hit > 0.0 and t >= hit and before < hit + 0.25 and _struck_instance != _instance():
		_struck_instance = _instance()
		impacts += 1
		match clip:
			"stomp":
				var foot := model.bone_position("foot_r")
				foot.y = actor.global_position.y
				_dust(foot, 9.0, 26, 10.0)
				_shake_at(foot, STOMP_SHAKE)
			"hammer", "smash2":
				var tip := model.bar_tip()
				tip.y = actor.global_position.y
				_dust(tip, 8.0, 24, 9.0)
				_chips(tip, 6, DIRT_COLOR, 0.8)
				_shake_at(tip, SMASH_SHAKE)
			"bash":
				var at := model.piece_centre("shield") if model.plate_visible("shield") else actor.global_position
				at.y = actor.global_position.y
				_dust(at, 7.0, 18, 8.0)
				_shake_at(at, BASH_SHAKE)
			_:
				var tip := model.bar_tip()
				tip.y = actor.global_position.y
				_dust(tip, 5.0, 14, 8.0)
	var kh := float(_keys.get("kneel_hit", 0.55))
	if clip == "kneel" and t >= kh and before < kh + 0.25 and _knelt_instance != _down_count():
		_knelt_instance = _down_count()
		knee_impacts += 1
		var knee := actor.global_position + actor.global_transform.basis.x * 2.6
		_dust(knee, 8.0, 20, 8.0)
		_shake_at(knee, KNEEL_SHAKE)
	if clip == "death" and t >= _len("death") - 0.3 and not _fell_dead:
		_fell_dead = true
		var front := actor.global_position - actor.global_transform.basis.z * 10.0
		_dust(front, 14.0, 34, 10.0)
		_shake_at(front, FALL_SHAKE)
	if clip in ["walk", "run", "walk2", "run2", "charge_run"] and length > 0.0:
		var half := int(floor(t / length * 2.0))
		if _foot_phase >= 0 and half != _foot_phase:
			footfalls_shaken += 1
			_shake_at(actor.global_position, STEP_SHAKE if clip.begins_with("walk") else RUN_STEP_SHAKE)
			_dust(actor.global_position, 3.5, 6, 3.0)
		_foot_phase = half
	else:
		_foot_phase = -1


# --------------------------------------------------------------------------- the guard, the shock

## A pulse of his blows' shock lines raises dust along them.
func _on_area_pulse(_tick: int, entity_id: String, action_id: String, point: Vector3, radius: float) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	if action_id.contains("_hammer") or action_id.contains("_smash2"):
		_dust(point, maxf(3.0, radius * 1.6), 10, 6.0)


## A blow his guard caught: stone chips off the shield's face where it struck.
func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if model == null or actor == null or not is_instance_valid(actor) or r == null or r.event == null:
		return
	if r.event.target_id != str(actor.get("entity_id")) or not r.event.guarded:
		return
	guard_chips += 1
	var at := r.event.hit_point if r.event.hit_point != Vector3.ZERO else model.piece_centre("shield")
	_chips(at, 3, STONE_COLOR, 0.5)


## His guard broken: the shield struck aside - stone and dust off it.
func _on_guard_broken(_tick: int, entity_id: String, _plate_id: String) -> void:
	if model == null or actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	guard_breaks_shown += 1
	var at := model.piece_centre("shield")
	_chips(at, 10, STONE_COLOR, 0.9)
	_dust(at, 6.0, 16, 7.0)
	_shake_at(at, SHIELD_SHAKE)


# --------------------------------------------------------------------------- small helpers

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
	return BruteRig.clip_length(BastionModel.CREATURE, clip)


func _down_count() -> int:
	return int(actor.get("topples")) if actor != null and "topples" in actor else 0


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
