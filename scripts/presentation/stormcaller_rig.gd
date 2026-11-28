class_name StormcallerRig
extends ActorRig
## The Stormcaller in play (D2): his model (StormcallerModel, tools/giant/kit/stormcaller.py's asset) under his actor
## (TitanEnemy, enemy.stormcaller), posed from the actor's state on the frame clock as FrostboundRig poses the
## Frostbound. Presentation only: it writes under its own Visual node and reads the actor (get_rig_state) and the events
## of his blows; nothing in the simulation reads it back.
##
##   Visual (StormcallerRig)
##   └ Body                  the clips carry the body
##     ├ Model (StormcallerModel) the titan, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip by the action he performs (its id's last word), each strike's keys the clip's own (the manifest's
## clip_keys: [start, wound, hit, past, end]) so the blow lands on the action's first active tick:
##   slam     the rod raised over his shoulder and brought down onto the ground ahead (spray or grit at the fork, a
##            shake; the shock's pulses throw up water or dust along the line);
##   sweep    the rod swung round low (spray where it passes through water);
##   gust     the left hand flung out: rain and spray driven along the cone;
##   call     the rod raised high and held while his bolts come down (the storm's light in him: set_charge);
##   chain    the rod thrust out ahead (charged) - the lightning runs out along the ground;
##   ring     the rod driven down at his feet (charged): the ring of storms;
##   stamp    the knee raised, the foot driven down (water or grit, a shake);
##   roar     his second phase's storm-break (roar2, charged); wake: his intro (the rod raised), asleep `dormant`;
##   a stagger `reel`; down on a knee (a greave, or grounded: steam and sparks off him) `kneel`, held, `rise`; walking
##   or running `walk` / `run` on the distance walked; dead `death`.
## His bolts (Events.storm_bolt): a jagged bolt from the cloud down to the point and its flash; on water a burst of
## spray and the shock's pale ring spreading over it (Events.storm_shock). A bolt telegraphed on the water shows, over
## the red circle, a pale ring as far as its shock will reach (the water's warning) until it strikes.
## His plates: split as their bronze wears, broken (hidden, the piece falling from him, bronze chips).

const FADE_S := 0.22
const MODEL_NAME := "Model"
const CHIP := Vector3(0.9, 0.5, 0.7)
const BRONZE_COLOR := Color(0.36, 0.30, 0.20)
const GRIT_COLOR := Color(0.45, 0.44, 0.42)
const WATER_COLOR := Color(0.16, 0.20, 0.22)
const SPRAY := Color(0.80, 0.84, 0.88, 0.75)
const DUST := Color(0.55, 0.54, 0.52, 0.7)
const STEAM := Color(0.86, 0.88, 0.92, 0.8)
const STOMP_SHAKE := 0.65
const SMASH_SHAKE := 0.6
const STEP_SHAKE := 0.22
const RUN_STEP_SHAKE := 0.32
const KNEEL_SHAKE := 0.6
const FALL_SHAKE := 0.8
const RING_SHAKE := 0.85
const BOLT_SHAKE := 0.35
## The cloud his bolts come down from (m over the ground).
const CLOUD_M := 150.0
const SHAKE_NEAR_M := 28.0
const SHAKE_FAR_M := 140.0
const FALL_G := 14.0
const FALL_SPIN := 1.0
const GAIT_RUN_FROM := 6.0
## The strikes that take their clip's keys (the rest: their own handling).
const STRIKES := ["slam", "sweep", "gust", "call", "stamp", "chain", "ring"]
## The actions that call the storm into him (his charge glows through them).
const CHARGED := ["call", "chain", "ring", "roar", "wake"]
const LOOPS := ["idle", "walk", "run", "dormant"]

var model: StormcallerModel = null
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
## Tests and stats.
var posed_frames := 0
var plates_shown_broken: Array[String] = []
var footfalls_shaken := 0
var impacts := 0
var knee_impacts := 0
var dust_raised := 0
var bolts_drawn := 0
var shocks_drawn := 0
var warnings_drawn := 0
var marks_drawn := 0
var _charge := 0.0
var _foot_phase := -1
var _struck_instance := -1
var _knelt_instance := -1
var _fell_dead := false


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()
	Events.area_pulse.connect(_on_area_pulse)
	Events.storm_bolt.connect(_on_storm_bolt)
	Events.storm_shock.connect(_on_storm_shock)
	Events.telegraph_started.connect(_on_telegraph)


func _exit_tree() -> void:
	for pair: Array in [[Events.area_pulse, _on_area_pulse], [Events.storm_bolt, _on_storm_bolt],
			[Events.storm_shock, _on_storm_shock], [Events.telegraph_started, _on_telegraph]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _build_model() -> void:
	if model != null or body == null:
		return
	model = StormcallerModel.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skinned = true
	_keys = StormcallerModel.clip_keys()
	var gaits: Dictionary = ((StormcallerModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
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
			var crack := StormcallerModel.crack_for(ps.health_frac(id))
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
			_chips(at, int(p.debris), BRONZE_COLOR, 1.0)
			_chips(at, maxi(2, int(p.debris) / 2), GRIT_COLOR, 0.6)
			_dust(at, 5.5, 20, 6.0, DUST)
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


## A broken plate's copy falls from him and lies where it lands (the bell, the bronze).
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
			_chips(t * a.get_center(), 8, BRONZE_COLOR, 0.6)
			_splash_or_dust(t * a.get_center(), 4.0, 12)
			_shake_at(t.origin, 0.16)


func _unfall(piece: String) -> void:
	if not fallen.has(piece):
		return
	(fallen[piece].node as Node).queue_free()
	fallen.erase(piece)


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(StormcallerModel.LIBRARY):
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
	var kind := clip_kind(action)
	var charge_to := 0.0
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
		if kind in CHARGED:
			charge_to = 1.0 if phase != ActionDef.Phase.RECOVERY else 0.3
	elif kind == "wake" or kind == "roar":
		clip = "roar2" if kind == "roar" else kind
		t = _len(clip) * TitanRig._action_share(action, phase, f)
		charge_to = 0.8
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
	if bool(s.get("grounded", false)):
		charge_to = 1.0
	_charge = lerpf(_charge, charge_to, 1.0 - exp(-(6.0 if charge_to > _charge else 2.0) * delta))
	model.set_charge(_charge)
	var full := StringName(String(StormcallerModel.LIBRARY) + "/" + clip)
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
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t


## The clip kind of an action (E2: CinderRig names his actions' clips its own way).
func clip_kind(a: ActionDef) -> String:
	return _kind(a)


## The kind of an action by its id's last word (ability.stormcaller_slam -> "slam").
static func _kind(a: ActionDef) -> String:
	if a == null:
		return ""
	return a.id.get_slice(".", 1).trim_prefix("stormcaller_")


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
				_splash_or_dust(foot, 10.0, 28)
				_shake_at(foot, STOMP_SHAKE)
			"slam":
				var c := model.rod_point("head_local")
				c.y = actor.global_position.y
				_splash_or_dust(c, 10.0, 30)
				_chips(c, 10, GRIT_COLOR, 0.9)
				_shake_at(c, SMASH_SHAKE)
			"ring":
				var at := model.rod_point("butt_local")
				at.y = actor.global_position.y
				_splash_or_dust(at, 16.0, 40)
				_shake_at(at, RING_SHAKE)
			"sweep":
				var c := model.rod_point("head_local")
				c.y = actor.global_position.y
				_splash_or_dust(c, 7.0, 16)
			"gust":
				var fwd := -actor.global_transform.basis.z
				for k in 4:
					var at := actor.global_position + fwd * (10.0 + 11.0 * float(k)) + Vector3.UP * (6.0 + 2.0 * float(k))
					_dust(at, 6.0 + 2.0 * float(k), 10, 14.0, SPRAY)
	var kh := float(_keys.get("kneel_hit", 0.55))
	if clip == "kneel" and t >= kh and before < kh + 0.25 and _knelt_instance != _down_count():
		_knelt_instance = _down_count()
		knee_impacts += 1
		var knee := actor.global_position + actor.global_transform.basis.x * 3.6
		if bool(s.get("grounded", false)):
			# grounded: his own lightning through him - steam off him, the water thrown up round his knee
			_dust(knee + Vector3.UP * 12.0, 10.0, 26, 6.0, STEAM)
			_splash_or_dust(knee, 10.0, 24)
		else:
			_splash_or_dust(knee, 9.0, 22)
		_shake_at(knee, KNEEL_SHAKE)
	if clip == "death" and t >= _len("death") - 0.3 and not _fell_dead:
		_fell_dead = true
		var front := actor.global_position - actor.global_transform.basis.z * 16.0
		_splash_or_dust(front, 18.0, 40)
		_chips(front, 16, GRIT_COLOR, 1.2)
		_shake_at(front, FALL_SHAKE)
	if clip in ["walk", "run"] and length > 0.0:
		var half := int(floor(t / length * 2.0))
		if _foot_phase >= 0 and half != _foot_phase:
			footfalls_shaken += 1
			_shake_at(actor.global_position, STEP_SHAKE if clip == "walk" else RUN_STEP_SHAKE)
			_splash_or_dust(actor.global_position, 4.0, 6)
		_foot_phase = half
	else:
		_foot_phase = -1


# --------------------------------------------------------------------------- the storm

## A pulse of his slam's shock line throws up water or grit along it.
func _on_area_pulse(_tick: int, entity_id: String, action_id: String, point: Vector3, radius: float) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	if action_id.contains("_slam"):
		_splash_or_dust(point, maxf(3.0, radius * 1.6), 10)


## A bolt of his struck: the bolt from the cloud and its flash; spray on water, grit on dry ground; a shake.
func _on_storm_bolt(tick: int, entity_id: String, point: Vector3, in_water: bool) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	bolts_drawn += 1
	var top := point + Vector3(0.0, CLOUD_M, 0.0) + actor.global_transform.basis.x * 12.0
	StormFx.bolt(self, top, point, tick * 31 + bolts_drawn, 0.34, 7.0 if model != null else 0.0)
	if in_water:
		_dust(point, 7.0, 22, 12.0, SPRAY)
	else:
		_dust(point, 6.0, 18, 9.0, DUST)
		_chips(point, 6, GRIT_COLOR, 0.7)
	_shake_at(point, BOLT_SHAKE)


## The shock running out through the water: its pale ring spreading over the surface.
func _on_storm_shock(_tick: int, entity_id: String, point: Vector3, radius: float, _hits: int) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	shocks_drawn += 1
	var y := _water_y(point)
	StormFx.shock_ring(self, Vector3(point.x, y, point.z), radius, 0.7)


## A bolt of his telegraphed on the water: the pale ring of its shock's reach, pulsing until it strikes.
func _on_telegraph(_tick: int, key: String, _action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, radius: float, _length: float, duration_s: float) -> void:
	if actor == null or not is_instance_valid(actor) or not key.begins_with(str(actor.get("entity_id")) + "#"):
		return
	var st: Dictionary = (actor as TitanEnemy).storm if actor is TitanEnemy else {}
	if st.is_empty() or not is_inside_tree():
		return
	# the red disc where it will strike (a hazard of his has no actor of its own for the telegraph decals to follow)
	marks_drawn += 1
	StormFx.strike_mark(self, Vector3(origin.x, maxf(origin.y, _water_y(origin)) + 0.1, origin.z), radius, duration_s)
	if StormWater.depth_at(get_tree(), origin) < float(st.get("min_water_m", 0.6)):
		return
	warnings_drawn += 1
	StormFx.water_warning(self, Vector3(origin.x, _water_y(origin), origin.z), float(st.get("spread_m", 30.0)),
		duration_s)


## The storm water's surface over `p` (its feet's height when none).
func _water_y(p: Vector3) -> float:
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(StormWater.GROUP):
			var w := n as StormWater
			if w != null:
				var y := w.surface_here(p)
				if not is_nan(y):
					return y
	return p.y


## Spray where the point stands in the storm's water, dust where it is dry.
func _splash_or_dust(at: Vector3, size: float, count: int) -> void:
	var wet := is_inside_tree() and StormWater.depth_at(get_tree(), at) > 0.4
	if wet:
		_dust(Vector3(at.x, _water_y(at), at.z), size, count, size * 1.1, SPRAY)
	else:
		_dust(at, size, count, size * 0.9, DUST)


# --------------------------------------------------------------------------- small helpers

func _shake_at(at: Vector3, amount: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer if is_inside_tree() else null
	if p == null or p.camera_rig == null:
		return
	var d := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
	var k := 1.0 - clampf((d - SHAKE_NEAR_M) / (SHAKE_FAR_M - SHAKE_NEAR_M), 0.0, 1.0)
	if k > 0.0:
		p.camera_rig.add_shake(amount * k)


func _dust(at: Vector3, size: float, count: int, speed: float, color := DUST) -> void:
	if DustBurst.puff(self, at, size, count, speed, color) != null:
		dust_raised += 1


func _has(clip: String) -> bool:
	return model != null and model.has_clip(clip)


func _len(clip: String) -> float:
	return BruteRig.clip_length(StormcallerModel.CREATURE, clip)


func _down_count() -> int:
	return int(actor.get("topples")) if actor != null and "topples" in actor else 0


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
