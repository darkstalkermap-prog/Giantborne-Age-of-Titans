class_name FrostboundRig
extends ActorRig
## The Frostbound Titan in play (D1): his model (FrostboundModel, tools/giant/kit/frostbound.py's asset) under his actor
## (TitanEnemy, enemy.frostbound), posed from the actor's state on the frame clock as BastionRig poses the warden.
## Presentation only: it writes under its own Visual node and reads the actor (get_rig_state) and the events of his
## blows; nothing in the simulation reads it back.
##
##   Visual (FrostboundRig)
##   └ Body                  the clips carry the body
##     ├ Model (FrostboundModel) the titan, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip by the action he performs (its id's last word), each strike's keys the clip's own (the manifest's
## clip_keys: [start, wound, hit, past, end]) so the blow lands on the action's first active tick:
##   rake     the claw drawn across and raked out to his left (snow thrown up where it passes low);
##   fist     the ice fist raised and brought down onto the ground ahead (ice and snow burst at the fist, a shake;
##            the shock's pulses raise snow along the line);
##   breath   the chest filled (the heart-ice brightens), the breath driven out over the ground: frost billowing
##            along the cone each pulse;
##   stamp    the knee raised, the foot driven down (snow, ice chips, a shake);
##   sweep    the ice fist swung round low;
##   hurl     the claw tears a shard of the crest from his back (a shard in his hand until it is thrown);
##   nova     he gathers (the heart-ice blazing) and drives both arms down: a ring of frost and ice bursts round him;
##   roar2    his second phase's whiteout roar (the cold roar: frost streaming off him);
##   wake     his intro (rising out of the ice), asleep `dormant`;
##   a stagger `reel`; down on a knee (a greave, or the ice gone under him: water and ice thrown up) `kneel`, held,
##   `rise`; walking or running `walk` / `run` on the distance walked; dead `death`.
## His plates: fracturing as their ice wears, broken (hidden, a burst of ice shards and frost).

const FADE_S := 0.22
const MODEL_NAME := "Model"
const CHIP := Vector3(0.9, 0.5, 0.7)
const ICE_COLOR := Color(0.78, 0.86, 0.92)
const SNOW_COLOR := Color(0.90, 0.92, 0.95)
const WATER_COLOR := Color(0.10, 0.14, 0.17)
const FROST := Color(0.88, 0.93, 0.98, 0.85)
const STOMP_SHAKE := 0.65
const SMASH_SHAKE := 0.6
const STEP_SHAKE := 0.22
const RUN_STEP_SHAKE := 0.32
const KNEEL_SHAKE := 0.6
const FALL_SHAKE := 0.8
const NOVA_SHAKE := 0.85
const SHAKE_NEAR_M := 28.0
const SHAKE_FAR_M := 140.0
const FALL_G := 14.0
const FALL_SPIN := 1.0
const GAIT_RUN_FROM := 6.0
## The strikes that take their clip's keys (the rest: their own handling).
const STRIKES := ["rake", "fist", "breath", "stamp", "sweep", "hurl", "nova"]
const LOOPS := ["idle", "walk", "run", "dormant"]

var model: FrostboundModel = null
var skinned := false
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0
var _stride := {"walk": 15.0, "run": 15.0}
var _dead_t := -1.0
var _stagger_t := 0.0
var _hidden: Dictionary = {}
var _keys: Dictionary = {}
var fallen: Dictionary = {}
var _shard: MeshInstance3D = null
## Tests and stats.
var posed_frames := 0
var plates_shown_broken: Array[String] = []
var footfalls_shaken := 0
var impacts := 0
var knee_impacts := 0
var dust_raised := 0
var breath_puffs := 0
var _foot_phase := -1
var _struck_instance := -1
var _knelt_instance := -1
var _fell_dead := false


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()
	Events.area_pulse.connect(_on_area_pulse)
	Events.ability_effect.connect(_on_ability_effect)


func _exit_tree() -> void:
	for pair: Array in [[Events.area_pulse, _on_area_pulse], [Events.ability_effect, _on_ability_effect]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _build_model() -> void:
	if model != null or body == null:
		return
	model = FrostboundModel.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skinned = true
	_keys = FrostboundModel.clip_keys()
	var gaits: Dictionary = ((FrostboundModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
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
			var crack := FrostboundModel.crack_for(ps.health_frac(id))
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
			_chips(at, int(p.debris), ICE_COLOR, 1.0)
			_chips(at, maxi(2, int(p.debris) / 2), SNOW_COLOR, 0.6)
			_dust(at, 5.5, 20, 6.0, FROST)
		else:
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


## A broken plate's copy falls from him and lies where it lands (shattered ice).
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
	fallen[piece] = {"node": copy, "vel": dir * 3.0 + Vector3.UP * 1.0, "spin": FALL_SPIN,
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
			_chips(t * a.get_center(), 8, ICE_COLOR, 0.6)
			_dust(t * a.get_center(), 3.5, 12, 5.0, FROST)
			_shake_at(t.origin, 0.16)


func _unfall(piece: String) -> void:
	if not fallen.has(piece):
		return
	(fallen[piece].node as Node).queue_free()
	fallen.erase(piece)


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(FrostboundModel.LIBRARY):
		return
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var dead := bool(s.get("dead", false))
	var staggered := bool(s.get("staggered", false))
	var dormant := bool(s.get("dormant", false))
	var clip := "idle"
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
	var pulse := 0.0
	if dead:
		pass
	elif dormant:
		clip = "dormant"
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
		clip = "reel"
		t = minf(_stagger_t, _len(clip))
	elif kind in STRIKES:
		clip = kind
		t = _strike(clip, phase, f)
		if kind == "breath" or kind == "nova":
			var hit := float((_keys.get(kind, [0, 0, 1.0]) as Array)[2])
			pulse = clampf(t / maxf(hit, 0.01), 0.0, 1.0) if t < hit + 0.6 else 0.0
	elif kind == "wake" or kind == "cold_roar":
		clip = "roar2" if kind == "cold_roar" else kind
		t = _len(clip) * TitanRig._action_share(action, phase, f)
		if kind == "cold_roar":
			pulse = 0.6
	elif action != null and action.hit_shape == "none":
		clip = "reel"
		t = _len("reel") * TitanRig._action_share(action, phase, f)
	elif speed > 0.3:
		_gait += speed * delta
		clip = "run" if speed >= GAIT_RUN_FROM else "walk"
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * _len(clip)
	if not _has(clip):
		clip = "idle"
		t = -1.0
	model.set_heart_pulse(pulse)
	var full := StringName(String(FrostboundModel.LIBRARY) + "/" + clip)
	if clip != _clip:
		var first := _clip == ""
		_clip = clip
		player.play(full, 0.0 if first else FADE_S)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta
		t = fposmod(_clip_t, _len(clip))
	var loops := clip in LOOPS
	var length := _len(clip)
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	_feel(clip, t, before, length, s)
	_hurl_shard(clip, t)
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t


## The kind of an action by its id's last word (ability.frostbound_breath -> "breath").
static func _kind(a: ActionDef) -> String:
	if a == null:
		return ""
	return a.id.get_slice(".", 1).trim_prefix("frostbound_")


func _strike(clip: String, phase: int, f: float) -> float:
	var k: Array = _keys.get(clip, [])
	if k.size() < 5:
		var L := _len(clip)
		k = [0.0, L * 0.35, L * 0.5, L * 0.6, L]
	var share := float(k[1]) / maxf(float(k[2]), 1e-3)
	return TitanRig._strike_time(phase, f, k, share)


## The blows' snow, ice and shake as their clips pass them; the footfalls'; his fall.
func _feel(clip: String, t: float, before: float, length: float, s: Dictionary) -> void:
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	if clip in STRIKES and hit > 0.0 and t >= hit and before < hit + 0.25 and _struck_instance != _instance():
		_struck_instance = _instance()
		impacts += 1
		match clip:
			"stamp":
				var foot := model.bone_position("foot_r")
				foot.y = actor.global_position.y
				_dust(foot, 10.0, 28, 10.0, Color(SNOW_COLOR, 0.8))
				_chips(foot, 10, ICE_COLOR, 0.9)
				_shake_at(foot, STOMP_SHAKE)
			"fist":
				var c := model.fist_centre()
				c.y = actor.global_position.y
				_dust(c, 10.0, 30, 10.0, Color(SNOW_COLOR, 0.8))
				_chips(c, 14, ICE_COLOR, 1.0)
				_shake_at(c, SMASH_SHAKE)
			"nova":
				var at := actor.global_position
				_dust(at, 22.0, 46, 14.0, FROST)
				_chips(at, 24, ICE_COLOR, 1.2)
				_shake_at(at, NOVA_SHAKE)
			"rake", "sweep":
				var c := model.fist_centre() if clip == "sweep" else model.bone_position("hand_l")
				c.y = actor.global_position.y
				_dust(c, 6.0, 16, 8.0, Color(SNOW_COLOR, 0.7))
	var kh := float(_keys.get("kneel_hit", 0.55))
	if clip == "kneel" and t >= kh and before < kh + 0.25 and _knelt_instance != _down_count():
		_knelt_instance = _down_count()
		knee_impacts += 1
		var knee := actor.global_position + actor.global_transform.basis.x * 3.0
		if bool(s.get("through_ice", false)):
			# through the ice: black water and broken ice thrown up round his knee
			_chips(knee, 18, WATER_COLOR, 1.1)
			_chips(knee, 14, ICE_COLOR, 1.0)
			_dust(knee, 9.0, 24, 9.0, FROST)
		else:
			_dust(knee, 9.0, 22, 8.0, Color(SNOW_COLOR, 0.8))
		_shake_at(knee, KNEEL_SHAKE)
	if clip == "death" and t >= _len("death") - 0.3 and not _fell_dead:
		_fell_dead = true
		var front := actor.global_position - actor.global_transform.basis.z * 13.0
		_dust(front, 16.0, 40, 10.0, Color(SNOW_COLOR, 0.8))
		_chips(front, 20, ICE_COLOR, 1.2)
		_shake_at(front, FALL_SHAKE)
	if clip in ["walk", "run"] and length > 0.0:
		var half := int(floor(t / length * 2.0))
		if _foot_phase >= 0 and half != _foot_phase:
			footfalls_shaken += 1
			_shake_at(actor.global_position, STEP_SHAKE if clip == "walk" else RUN_STEP_SHAKE)
			_dust(actor.global_position, 4.0, 6, 3.0, Color(SNOW_COLOR, 0.6))
		_foot_phase = half
	else:
		_foot_phase = -1


## The shard he tears from his crest: in his claw from the grip until the throw (the projectile flies on).
func _hurl_shard(clip: String, t: float) -> void:
	var held := clip == "hurl" and t >= float(_keys.get("hurl_grip", 0.95)) and t < float(_keys.get("hurl_release", 1.9))
	if not held:
		if _shard != null:
			_shard.visible = false
		return
	if _shard == null:
		_shard = MeshInstance3D.new()
		_shard.name = "HeldShard"
		_shard.top_level = true
		_shard.mesh = ProjectileSystem.shard_mesh()
		_shard.material_override = model.ice_material
		add_child(_shard)
	_shard.visible = true
	var hand := model.bone_position("hand_l")
	_shard.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 2.0), hand + Vector3.UP * 0.5)


# --------------------------------------------------------------------------- the shock, the breath

## A pulse of his blows' shock lines raises snow and ice along them.
func _on_area_pulse(_tick: int, entity_id: String, action_id: String, point: Vector3, radius: float) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	if action_id.contains("_fist"):
		_dust(point, maxf(3.0, radius * 1.6), 10, 6.0, Color(SNOW_COLOR, 0.7))
		_chips(point, 3, ICE_COLOR, 0.6)


## The breath: frost billowing along the cone each pulse.
func _on_ability_effect(_tick: int, entity_id: String, _action_id: String, kind: String, center: Vector3,
		radius: float, yaw: float, _arc: float) -> void:
	if kind != "breath" or actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	breath_puffs += 1
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var mouth := model.mouth() if model != null else actor.global_position + Vector3.UP * 22.0
	for k in 3:
		var d := radius * (0.25 + 0.3 * float(k))
		var at := center + fwd * d
		at.y = lerpf(mouth.y, actor.global_position.y + 2.0, 0.4 + 0.25 * float(k))
		_dust(at, 4.0 + 3.0 * float(k), 8, 4.0, FROST)


# --------------------------------------------------------------------------- small helpers

func _shake_at(at: Vector3, amount: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer if is_inside_tree() else null
	if p == null or p.camera_rig == null:
		return
	var d := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
	var k := 1.0 - clampf((d - SHAKE_NEAR_M) / (SHAKE_FAR_M - SHAKE_NEAR_M), 0.0, 1.0)
	if k > 0.0:
		p.camera_rig.add_shake(amount * k)


func _dust(at: Vector3, size: float, count: int, speed: float, color := FROST) -> void:
	if DustBurst.puff(self, at, size, count, speed, color) != null:
		dust_raised += 1


func _has(clip: String) -> bool:
	return model != null and model.has_clip(clip)


func _len(clip: String) -> float:
	return BruteRig.clip_length(FrostboundModel.CREATURE, clip)


func _down_count() -> int:
	return int(actor.get("topples")) if actor != null and "topples" in actor else 0


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
