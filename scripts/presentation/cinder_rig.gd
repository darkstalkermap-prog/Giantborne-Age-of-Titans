class_name CinderRig
extends StormcallerRig
## The Cinder Titan in play (E2): his model (CinderModel: the Stormcaller's body and clips in his own look, scaled to
## 41.0 m) under his actor (CinderEnemy, enemy.cinder), posed from the actor's state as StormcallerRig poses the
## Stormcaller - his actions name the Stormcaller's clips (CLIPS) - and his fire drawn (presentation only: nothing in the
## simulation reads it back):
##   * his burning ground: each patch his actor lays (Events.burn_laid) a disc of charred, ember-lit ground and a cluster
##     of flames (CinderFx: one MultiMesh for every flame, one for every disc), smoke and sparks as it catches; going out
##     (burn_out, burn_cleared) its flames sink and its embers dim, the char fading over CHAR_FADE_S;
##   * his telegraphed embers: the red disc where each will fall (his hazards have no actor of their own);
##   * his blows: sparks and smoke where the brand strikes the ground, fire along the blast's cone, the stamp's;
##   * his crust: the fire in him (CinderModel.set_heat) sinking when water quenches him - steam roaring off him - and
##     flaring again as it melts; his fall: the fire going out of him over FALL_COOL_S, smoke.

## His actions' last word -> the Stormcaller's clip that carries it.
const CLIPS := {"blast": "gust", "embers": "call", "firerun": "chain", "firering": "ring"}
const FIRE_STRIKES := ["slam", "sweep", "gust", "call", "stamp", "chain", "ring"]
const FLAMES_PER_PATCH := 4
const CHAR_FADE_S := 14.0
const OUT_S := 2.5
const FALL_COOL_S := 9.0
const GRIT := Color(0.24, 0.22, 0.2)
const SLAG := Color(0.12, 0.1, 0.09)

var fx: CinderFx = null
## Patch id -> {"flames": [slots], "disc": slot, "p", "r", "out": seconds since it went out (-1 burning), "seed"}.
var patches_drawn: Dictionary = {}
var patches_shown := 0
var quench_steams := 0
var embers_marked := 0
var _heat_shown := 1.0
var _fx_t := 0.0
## The fire on an ablaze giant: flame slots that ride its body while it burns (the HUD says ABLAZE; this shows it).
const ABLAZE_FLAMES := 7
var _ablaze_slots: Array = []
var _ablaze_k := 0.0
var ablaze_frames := 0


func _ready() -> void:
	super()
	fx = CinderFx.new(FLAMES_PER_PATCH * 48 + 16, 56)
	fx.name = "CinderFx"
	if PersonRig.layers_enabled():
		add_child(fx)
	Events.burn_laid.connect(_on_burn_laid)
	Events.burn_out.connect(_on_burn_out)
	Events.burn_cleared.connect(_on_burn_cleared)
	Events.titan_quenched.connect(_on_quenched)
	Events.titan_remelted.connect(_on_remelted)


func _exit_tree() -> void:
	super()
	for pair: Array in [[Events.burn_laid, _on_burn_laid], [Events.burn_out, _on_burn_out],
			[Events.burn_cleared, _on_burn_cleared], [Events.titan_quenched, _on_quenched],
			[Events.titan_remelted, _on_remelted]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _build_model() -> void:
	if model != null or body == null:
		return
	var m := CinderModel.new()
	m.name = MODEL_NAME
	body.add_child(m)
	if m.model == null:
		m.queue_free()
		return
	model = m
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * CinderModel.SCALE), Vector3.ZERO)
	skinned = true
	_keys = StormcallerModel.clip_keys()
	var gaits: Dictionary = ((StormcallerModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
	for g: String in ["walk", "run"]:
		_stride[g] = float((gaits.get(g, {}) as Dictionary).get("stride_m", _stride[g])) * CinderModel.SCALE
	var proxy := get_node_or_null("LodProxy") as GeometryInstance3D
	if proxy != null:
		proxy.visible = false
	for c in body.get_children():
		if c != model and c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false


func cinder_model() -> CinderModel:
	return model as CinderModel


func clip_kind(a: ActionDef) -> String:
	if a == null:
		return ""
	var k := a.id.get_slice(".", 1)
	k = k.substr(k.find("_") + 1)
	return str(CLIPS.get(k, k))


func _process(delta: float) -> void:
	super(delta)
	_fx_t += delta
	_patches_step(delta)
	var m := cinder_model()
	if m == null or actor == null or not actor.has_method("get_rig_state"):
		return
	var s := rig_state()
	var want := 1.0 if bool(s.get("hot", true)) else 0.0
	if bool(s.get("dead", false)):
		want = 0.0
		_heat_shown = maxf(0.0, _heat_shown - delta / FALL_COOL_S)
	else:
		# quenched the fire sinks at once; it creeps back over the last seconds of the quench
		var left := float(s.get("quench_left", 0.0))
		if want < 0.5 and left < 3.0:
			want = 1.0 - left / 3.0
		_heat_shown = move_toward(_heat_shown, want, delta * (2.5 if want < _heat_shown else 0.6))
	m.set_heat(_heat_shown)
	m.update_fire(delta)
	_ablaze_step(delta)


## The giant ablaze: flames licking up its legs and body (one CinderFx's slots), fading in and out with the fire on it.
func _ablaze_step(delta: float) -> void:
	if fx == null or not fx.is_inside_tree():
		return
	var g := get_tree().get_first_node_in_group("player") as GiantPlayer
	var on: bool = g != null and g.heat != null and g.heat.is_ablaze()
	_ablaze_k = move_toward(_ablaze_k, 1.0 if on else 0.0, delta * 2.0)
	if _ablaze_slots.is_empty():
		if _ablaze_k <= 0.0:
			return
		for k in ABLAZE_FLAMES:
			_ablaze_slots.append(fx.add_flame(Vector3(0, -1000, 0), 1.0, 1.0, 0.31 + 0.11 * float(k), 0.0, 0.8))
	if g == null:
		return
	if on:
		ablaze_frames += 1
	var h := g.entity.combatant.height_m if g.entity != null else 10.0
	for k in _ablaze_slots.size():
		var a := TAU * float(k) / float(ABLAZE_FLAMES) + _fx_t * 0.7
		var up := h * (0.05 + 0.5 * fposmod(float(k) * 0.37, 1.0))
		var at := g.global_position + Vector3(cos(a), 0.0, sin(a)) * h * 0.11 + Vector3.UP * up
		var size := h * (0.22 - 0.1 * up / h)
		fx.set_flame(int(_ablaze_slots[k]), at, size, size * 0.6, 0.31 + 0.11 * float(k), _ablaze_k, 0.8)


# --------------------------------------------------------------------------- the burning ground

func _mine(entity_id: String) -> bool:
	return actor != null and is_instance_valid(actor) and entity_id == str(actor.get("entity_id"))


func _on_burn_laid(_tick: int, entity_id: String, id: int, point: Vector3, radius: float) -> void:
	if not _mine(entity_id) or not fx.is_inside_tree():
		return
	patches_shown += 1
	var seed_value := fposmod(float(id) * 0.6180339, 1.0)
	var rec := {"flames": [], "disc": fx.add_disc(point, radius, seed_value, 1.0), "p": point, "r": radius, "out": -1.0,
		"seed": seed_value, "age": 0.0}
	for k in FLAMES_PER_PATCH:
		var a := TAU * (seed_value + float(k) / float(FLAMES_PER_PATCH))
		var d := radius * (0.25 + 0.45 * fposmod(seed_value * 7.0 + float(k) * 0.37, 1.0))
		var at := point + Vector3(cos(a), 0.0, sin(a)) * d
		var h := radius * (1.1 + 0.6 * fposmod(seed_value * 3.0 + float(k) * 0.53, 1.0))
		(rec.flames as Array).append(fx.add_flame(at, h, h * 0.62, seed_value + 0.17 * float(k), 0.0, 0.5))
	patches_drawn[id] = rec
	CinderFx.sparks(self, point + Vector3.UP * 1.0, radius, 24, 12.0)
	CinderFx.smoke(self, point + Vector3.UP * radius * 0.6, radius * 1.4, 8, 3.0)


func _on_burn_out(_tick: int, entity_id: String, id: int, _doused: bool) -> void:
	if not _mine(entity_id) or not patches_drawn.has(id):
		return
	var rec: Dictionary = patches_drawn[id]
	if float(rec.out) < 0.0:
		rec.out = 0.0
		CinderFx.smoke(self, (rec.p as Vector3) + Vector3.UP * 2.0, float(rec.r) * 1.2, 6, 2.0)


func _on_burn_cleared(_tick: int, entity_id: String) -> void:
	if not _mine(entity_id):
		return
	for id: int in patches_drawn:
		var rec: Dictionary = patches_drawn[id]
		if float(rec.out) < 0.0:
			rec.out = 0.0


## Each frame: a new patch's flames rise, a burning one's flicker, an out one's flames sink and its char fades.
func _patches_step(delta: float) -> void:
	var gone: Array = []
	for id: int in patches_drawn:
		var rec: Dictionary = patches_drawn[id]
		rec.age = float(rec.age) + delta
		var flames: Array = rec.flames
		if float(rec.out) < 0.0:
			var rise := clampf(float(rec.age) / 0.6, 0.0, 1.0)
			for k in flames.size():
				var w := 0.85 + 0.15 * sin(_fx_t * (2.0 + 0.7 * float(k)) + float(rec.seed) * 20.0)
				fx.set_flame_strength(int(flames[k]), rise * w)
			continue
		rec.out = float(rec.out) + delta
		var o := float(rec.out)
		var sink := clampf(1.0 - o / OUT_S, 0.0, 1.0)
		for k in flames.size():
			fx.set_flame_strength(int(flames[k]), sink)
		fx.set_disc(int(rec.disc), sink * 0.6, clampf(1.0 - (o - OUT_S) / CHAR_FADE_S, 0.0, 1.0))
		if o >= OUT_S + CHAR_FADE_S:
			gone.append(id)
	for id: int in gone:
		var rec: Dictionary = patches_drawn[id]
		for slot: Variant in rec.flames:
			fx.free_flame(int(slot))
		fx.free_disc(int(rec.disc))
		patches_drawn.erase(id)


# --------------------------------------------------------------------------- the crust

func _on_quenched(_tick: int, entity_id: String, point: Vector3, down: bool) -> void:
	if not _mine(entity_id):
		return
	quench_steams += 1
	var m := cinder_model()
	var k := CinderModel.SCALE
	for h: float in [4.0, 14.0, 26.0]:
		CinderFx.steam(self, point + Vector3.UP * h * k, 16.0 if down else 12.0, 30, 9.0)
	if m != null:
		CinderFx.steam(self, m.piece_centre("lodestone"), 10.0, 20, 6.0)
	_shake_at(point, 0.3)


func _on_remelted(_tick: int, entity_id: String) -> void:
	if not _mine(entity_id):
		return
	var m := cinder_model()
	if m != null:
		CinderFx.sparks(self, m.piece_centre("lodestone"), 8.0, 40, 10.0)


# --------------------------------------------------------------------------- his blows

func _feel(clip: String, t: float, before: float, length: float, s: Dictionary) -> void:
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	var striking := clip in FIRE_STRIKES and hit > 0.0 and t >= hit and before < hit + 0.25 \
		and _struck_instance != _instance()
	super(clip, t, before, length, s)
	if not striking or model == null:
		return
	var m := cinder_model()
	var fwd := -actor.global_transform.basis.z
	match clip:
		"slam", "chain", "ring":
			var at := m.brand_point("head")
			at.y = actor.global_position.y
			CinderFx.sparks(self, at + Vector3.UP, 10.0, 60, 18.0)
			CinderFx.smoke(self, at + Vector3.UP * 4.0, 14.0, 12, 4.0)
		"gust":
			for k in 4:
				var at := actor.global_position + fwd * (12.0 + 10.0 * float(k)) + Vector3.UP * (8.0 + 2.0 * float(k))
				CinderFx.sparks(self, at, 8.0 + 2.0 * float(k), 26, 10.0)
				CinderFx.smoke(self, at, 8.0 + 3.0 * float(k), 8, 6.0)
		"stamp":
			var foot := m.bone_position("foot_r")
			foot.y = actor.global_position.y
			CinderFx.sparks(self, foot, 10.0, 40, 12.0)


## (no storm: his telegraphed embers are marked here - the red disc where each will fall)
func _on_telegraph(_tick: int, key: String, _action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, radius: float, _length: float, duration_s: float) -> void:
	if actor == null or not is_instance_valid(actor) or not key.begins_with(str(actor.get("entity_id")) + "#"):
		return
	if not is_inside_tree():
		return
	embers_marked += 1
	marks_drawn += 1
	StormFx.strike_mark(self, Vector3(origin.x, origin.y + 0.1, origin.z), radius, duration_s)


## (his embers are no lightning: the storm's bolt and shock are not drawn)
func _on_storm_bolt(_tick: int, _entity_id: String, _point: Vector3, _in_water: bool) -> void:
	pass
