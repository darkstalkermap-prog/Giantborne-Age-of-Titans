class_name RootwardenRig
extends ActorRig
## The Rootwarden in play (B3): his model (RootwardenModel, tools/giant/kit/rootwarden.py's asset) under his actor
## (TitanEnemy, enemy.rootwarden), posed from the actor's state on the frame clock as OgreKingRig poses the King.
## Presentation only: it writes under its own Visual node and reads the actor (get_rig_state) and the events of his
## blows; nothing in the simulation reads it back.
##
##   Visual (RootwardenRig)
##   └ Body                  the clips carry the body
##     ├ Model (RootwardenModel) the warden, turned to face the actor's -Z, made where the people are drawn
##     │                      (PersonRig.layers_enabled(): a display, --skin, enable_for_tests(); never --no-skin)
##     └ LodProxy             the one-box stand-in elsewhere (headless: no model is loaded)
##
## The clip by the action he performs (its id's last word), each strike's keys the clip's own (the manifest's
## clip_keys: [start, wound, hit, past, end]) so the blow lands on the action's first active tick:
##   lash     the root-arm drawn across him and swept out wide (dust along the arc as it passes);
##   erupt    the root-arm driven into the ground: roots burst up along the line (each pulse of his titan_shock);
##   snare    the root-arm thrust down: roots burst up in a ring round the committed point and close;
##   hurl     `rip` over the windup's first RIP_SHARE (the dead tree torn out of the ground at his right side: dirt),
##            `hurl` to the release (the tree leaves his hand as the projectile is launched);
##   stomp    the knee raised, the foot driven down (dust, a shake);
##   uproot   his second phase's enter action: he tears his roots out of the ground (dirt at his hand);
##   asleep   `dormant` (head bowed, the roots in the soil); waking, `roar` once;
##   a stagger `reel`; down on a knee `kneel`, held, `rise`; walking or running `walk` / `run` on the distance
##   walked; dead `death` (he falls forward like a felled tree: dust and a shake as he lands).
## His plates: cracking as their bark wears, broken (hidden, a copy of the piece falls and lies on the ground, bark
## splinters, the sapwood beneath shown glowing), regrowing (the piece shown again eaten away, closing over the
## wound: RootwardenModel.set_plate_grow), seared (the sapwood charred: set_sap_char), whole again. While his
## wounds are withered (the knot broken) his roots grey. Falling trees: each arena hazard his brain announces (the
## grove's dead trees in his second phase) shows a dead tree toppling into its circle.

const FADE_S := 0.22
const MODEL_NAME := "Model"
const SPLINTER := Vector3(1.8, 0.24, 0.40)
const BARK_COLOR := Color(0.30, 0.25, 0.19)
const SAP_COLOR := Color(0.85, 0.55, 0.18)
const DIRT_COLOR := Color(0.30, 0.24, 0.17)
## The shakes at the giant (full within SHAKE_NEAR_M, none beyond SHAKE_FAR_M).
const STOMP_SHAKE := 0.6
const ERUPT_SHAKE := 0.4
const STEP_SHAKE := 0.18
const RUN_STEP_SHAKE := 0.28
const KNEEL_SHAKE := 0.5
const FALL_SHAKE := 0.7
const SHAKE_NEAR_M := 22.0
const SHAKE_FAR_M := 110.0
const FALL_G := 14.0
const FALL_SPIN := 1.2
const GAIT_RUN_FROM := 5.5
## The hurl's windup: the rip's share (the rest draws the tree back to the release).
const RIP_SHARE := 0.5
## A root burst: how many spikes, their height and how long they stand (s).
const BURST_SPIKES := 6
const BURST_H := 5.5
const BURST_STAND_S := 1.4
const TREE_FALL_EXTRA_S := 0.15

var model: RootwardenModel = null
var skinned := false
var _clip := ""
var _clip_t := 0.0
var _gait := 0.0
var _stride := {"walk": 12.4, "run": 12.4}
var _dead_t := -1.0
var _stagger_t := 0.0
var _wake_t := -1.0
var _was_dormant := false
var _hidden: Dictionary = {}
var _keys: Dictionary = {}
var _bursts: Array = []
var _trees: Array = []
var _spike_mesh: Mesh = null
## The pieces fallen to the ground ({piece: {"node", "vel", "spin", "axis", "landed"}}).
var fallen: Dictionary = {}
## Tests and stats.
var posed_frames := 0
var plates_shown_broken: Array[String] = []
var plates_shown_regrown: Array[String] = []
var bursts_raised := 0
var trees_felled := 0
var footfalls_shaken := 0
var stomp_impacts := 0
var knee_impacts := 0
var dust_raised := 0
var tree_released := 0
var _foot_phase := -1
var _stomped_instance := -1
var _knelt_instance := -1
var _ripped_instance := -1
var _released_instance := -1
var _lashed_instance := -1
var _uprooted_instance := -1
var _fell_dead := false


func _ready() -> void:
	super()
	if PersonRig.layers_enabled():
		_build_model()
	Events.area_pulse.connect(_on_area_pulse)
	Events.telegraph_started.connect(_on_telegraph)


func _exit_tree() -> void:
	if Events.area_pulse.is_connected(_on_area_pulse):
		Events.area_pulse.disconnect(_on_area_pulse)
	if Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.disconnect(_on_telegraph)


func _build_model() -> void:
	if model != null or body == null:
		return
	model = RootwardenModel.new()
	model.name = MODEL_NAME
	body.add_child(model)
	if model.model == null:
		model.queue_free()
		model = null
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skinned = true
	_keys = RootwardenModel.clip_keys()
	var gaits: Dictionary = ((RootwardenModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
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
	_bursts_step(delta)
	_trees_step(delta)
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
	var wounds: Dictionary = s.get("wounds", {})
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	if ps == null:
		return
	for p: Dictionary in ps.plates:
		var id := str(p.id)
		var piece := str(p.piece)
		if piece == "" or model.piece(piece) == null:
			continue
		var gone := broken.has(id)
		var w: Dictionary = wounds.get(id, {})
		var state := str(w.get("state", ""))
		if bool(p.breakable) and not gone:
			var crack := RootwardenModel.crack_for(ps.health_frac(id))
			if not is_equal_approx(crack, model.plate_crack(piece)):
				model.set_plate_crack(piece, crack)
		if gone != bool(_hidden.get(id, false)):
			_hidden[id] = gone
			if gone:
				plates_shown_broken.append(id)
				var at := model.piece_centre(piece)
				_drop(piece, (at - actor.global_position) * Vector3(1, 0, 1))
				model.set_plate_visible(piece, false)
				model.set_sap_char(piece, 0.0)
				_splinters(at, int(p.debris), BARK_COLOR, 1.0)
				_splinters(at, maxi(2, int(p.debris) / 3), SAP_COLOR, 0.6)
				_dust(at, 4.0, 14, 6.0)
			else:
				# whole again: grown back, or a new attempt
				model.set_plate_visible(piece, true)
				model.set_plate_grow(piece, 1.0)
				model.set_plate_crack(piece, 0.0)
				model.set_sap_char(piece, 0.0)
				_unfall(piece)
				plates_shown_regrown.append(id)
		if gone:
			var mi := model.piece(piece)
			match state:
				PlateRules.WOUND_REGROWING:
					mi.visible = true
					model.set_sap_visible(piece, true)
					model.set_plate_grow(piece, maxf(0.02, float(w.get("grow", 0.0))))
				PlateRules.WOUND_SEARED:
					mi.visible = false
					model.set_sap_char(piece, minf(1.0, model.sap_char(piece) + get_process_delta_time() * 1.5))
				_:
					mi.visible = false
	var withered := bool((actor as TitanEnemy).plates().is_withered(Sim.tick)) if actor is TitanEnemy else false
	var roots := model.piece("roots")
	if roots != null and roots.material_override is ShaderMaterial:
		(roots.material_override as ShaderMaterial).set_shader_parameter(&"tone",
			Color(0.62, 0.60, 0.58) if withered else RootwardenModel.BARK_TONE)


func _splinters(at: Vector3, count: int, color: Color, size: float) -> void:
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool if is_inside_tree() else null
	if pool == null or count <= 0:
		return
	var out := at - actor.global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 1e-4 else -actor.global_transform.basis.z
	var xs: Array[Transform3D] = []
	var vs: Array[Vector3] = []
	for i in count:
		var a := TAU * float(i) / float(count) + 0.41 * float(i % 5)
		var side := Vector3(cos(a), 0.0, sin(a))
		xs.append(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.5 * float(i % 3)), at + out + side * 0.5))
		vs.append((out * 7.0 + side * 4.0 + Vector3.UP * (5.0 + float(i % 3) * 2.0)) * size)
	pool.spawn(xs, vs, SPLINTER * size, color)


func _drop(piece: String, out: Vector3) -> void:
	var mi := model.piece(piece)
	if mi == null or mi.mesh == null or fallen.has(piece):
		return
	var copy := MeshInstance3D.new()
	copy.name = "Fallen_" + piece
	copy.mesh = mi.mesh
	copy.material_override = (mi.material_override as Material).duplicate() if mi.material_override != null else null
	if copy.material_override is ShaderMaterial:
		(copy.material_override as ShaderMaterial).set_shader_parameter(&"grow", 1.0)
	copy.top_level = true
	add_child(copy)
	copy.global_transform = model.piece_transform(piece)
	var dir := out.normalized() if out.length() > 0.05 else -actor.global_transform.basis.z
	var axis := dir.cross(Vector3.UP).normalized()
	fallen[piece] = {"node": copy, "vel": dir * 3.0 + Vector3.UP * 1.5, "spin": FALL_SPIN,
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
			_dust(t * a.get_center(), 3.0, 10, 4.0)
			_shake_at(t.origin, 0.14)


func _unfall(piece: String) -> void:
	if not fallen.has(piece):
		return
	(fallen[piece].node as Node).queue_free()
	fallen.erase(piece)


func fallen_landed(piece: String) -> bool:
	return fallen.has(piece) and bool(fallen[piece].landed)


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null or not player.has_animation_library(RootwardenModel.LIBRARY):
		return
	var action: ActionDef = s.get("action")
	var phase := int(s.get("phase", ActionDef.Phase.NONE))
	var f := clampf(float(s.get("phase_fraction", 0.0)), 0.0, 1.0)
	var speed := float(s.get("speed", 0.0))
	var dead := bool(s.get("dead", false))
	var staggered := bool(s.get("staggered", false))
	var dormant := bool(s.get("dormant", false))
	if _was_dormant and not dormant and not dead:
		_wake_t = 0.0   # waking: the roar once
	_was_dormant = dormant
	var clip := "idle"
	var t := -1.0
	var tree := false
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
		clip = "reel"
		t = minf(_stagger_t, _len("reel"))
	elif kind in ["lash", "erupt", "snare", "stomp"]:
		clip = kind
		t = _strike(clip, phase, f)
	elif kind == "hurl":
		var picked := _hurl_time(action, phase, f)
		clip = picked[0]
		t = picked[1]
		tree = bool(picked[2])
	elif kind == "uproot":
		clip = "uproot"
		t = _len("uproot") * TitanRig._action_share(action, phase, f)
	elif action != null and action.hit_shape == "none":
		clip = "roar"
		t = _len("roar") * TitanRig._action_share(action, phase, f)
	elif _wake_t >= 0.0 and _wake_t < _len("roar"):
		_wake_t += delta
		clip = "roar"
		t = minf(_wake_t, _len("roar"))
	elif speed > 0.3:
		_gait += speed * delta
		clip = "run" if speed >= GAIT_RUN_FROM else "walk"
		t = fposmod(_gait / maxf(float(_stride[clip]), 0.1), 1.0) * _len(clip)
	if clip != "roar" or _wake_t >= _len("roar"):
		_wake_t = -1.0 if clip != "roar" else _wake_t
	if not _has(clip):
		clip = "idle"
		t = -1.0
	var full := StringName(String(RootwardenModel.LIBRARY) + "/" + clip)
	if clip != _clip:
		var first := _clip == ""
		_clip = clip
		player.play(full, 0.0 if first else FADE_S)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta
		t = fposmod(_clip_t, _len(clip))
	var loops := clip in ["idle", "walk", "run", "dormant"]
	var length := _len(clip)
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	_feel(clip, t, before, length)
	player.seek(before, false)
	player.advance(delta if loops or t >= delta else t)
	model.clip = clip
	model.clip_time = t
	model.set_tree(tree)


## The kind of an action by its id's last word (ability.rootwarden_lash_rage -> "lash").
static func _kind(a: ActionDef) -> String:
	if a == null:
		return ""
	for k: String in ["lash", "erupt", "snare", "hurl", "stomp", "uproot"]:
		if a.id.contains("_" + k):
			return k
	return ""


func _strike(clip: String, phase: int, f: float) -> float:
	var k: Array = _keys.get(clip, [])
	if k.size() < 5:
		var L := _len(clip)
		k = [0.0, L * 0.35, L * 0.5, L * 0.6, L]
	var share := float(k[1]) / maxf(float(k[2]), 1e-3)
	return TitanRig._strike_time(phase, f, k, share)


## The hurl: `rip` over the windup's first RIP_SHARE (the tree shown from the grip), `hurl` from its start to the
## release over the rest; after the launch the hurl's follow-through without the tree. [clip, time, tree shown].
func _hurl_time(action: ActionDef, phase: int, f: float) -> Array:
	var grip := float(_keys.get("rip_grip", 0.7))
	var release := float(_keys.get("hurl_release", 0.8))
	if phase == ActionDef.Phase.WINDUP:
		if f < RIP_SHARE:
			var t := _len("rip") * f / RIP_SHARE
			if t >= grip and _ripped_instance != _instance():
				_ripped_instance = _instance()
				var at := model.hand_point("tree", "foot_local", "hand_r")
				at.y = actor.global_position.y
				_splinters(at, 8, DIRT_COLOR, 0.8)
				_dust(at, 5.0, 16, 6.0)
			return ["rip", t, t >= grip]
		var u := (f - RIP_SHARE) / (1.0 - RIP_SHARE)
		return ["hurl", release * u * u, true]
	if _released_instance != _instance():
		_released_instance = _instance()
		tree_released += 1
	var share := TitanRig._action_share(action, phase, f)
	var after := (share - TitanRig._action_share(action, ActionDef.Phase.ACTIVE, 0.0)) \
		/ maxf(1.0 - TitanRig._action_share(action, ActionDef.Phase.ACTIVE, 0.0), 1e-3)
	return ["hurl", lerpf(release, _len("hurl"), clampf(after, 0.0, 1.0)), false]


## The blows' dust and shake as their clips pass them; the footfalls'; his fall.
func _feel(clip: String, t: float, before: float, length: float) -> void:
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	if clip == "stomp" and hit > 0.0 and t >= hit and before < hit + 0.25 and _stomped_instance != _instance():
		_stomped_instance = _instance()
		stomp_impacts += 1
		var foot := model.bone_position("foot_r")
		foot.y = actor.global_position.y
		_dust(foot, 9.0, 26, 10.0)
		_shake_at(foot, STOMP_SHAKE)
	if clip == "lash" and hit > 0.0 and t >= hit and before < hit + 0.25 and _lashed_instance != _instance():
		_lashed_instance = _instance()
		var tip := model.roots_tip()
		tip.y = actor.global_position.y
		_dust(tip, 6.0, 16, 9.0)
	if clip == "uproot" and t >= float(_keys.get("uproot_tear", 1.1)) and _uprooted_instance != _instance():
		_uprooted_instance = _instance()
		var hand := model.bone_position("hand_l")
		hand.y = actor.global_position.y
		_splinters(hand, 10, DIRT_COLOR, 1.0)
		_dust(hand, 8.0, 24, 8.0)
		_shake_at(hand, ERUPT_SHAKE)
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
	if clip in ["walk", "run"] and length > 0.0:
		var half := int(floor(t / length * 2.0))
		if _foot_phase >= 0 and half != _foot_phase:
			footfalls_shaken += 1
			_shake_at(actor.global_position, STEP_SHAKE if clip == "walk" else RUN_STEP_SHAKE)
			_dust(actor.global_position, 3.5, 6, 3.0)
		_foot_phase = half
	else:
		_foot_phase = -1


# --------------------------------------------------------------------------- root bursts, falling trees

## A pulse of his erupt (the line) or his snare (the ring) raises roots out of the ground there.
func _on_area_pulse(_tick: int, entity_id: String, action_id: String, point: Vector3, radius: float) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	if action_id.contains("_erupt"):
		_burst(point, maxf(2.5, radius * 0.8), 1.0)
	elif action_id.contains("_snare"):
		_burst(point, radius, 1.15)


## Each arena hazard of his ("<id>#stone<n>": the grove's dead trees in his second phase) shows a dead tree
## toppling into its circle over the telegraph's time.
func _on_telegraph(_tick: int, entity_id: String, _action_id: String, _target: String, _shape: String,
		origin: Vector3, _yaw: float, radius: float, _length: float, duration: float) -> void:
	if actor == null or not is_instance_valid(actor) or model == null:
		return
	if not entity_id.begins_with(str(actor.get("entity_id")) + "#"):
		return
	var tree := model.piece("tree")
	if tree == null or tree.mesh == null:
		return
	var copy := MeshInstance3D.new()
	copy.name = "FallingTree%d" % trees_felled
	copy.mesh = tree.mesh
	copy.material_override = tree.material_override
	copy.top_level = true
	add_child(copy)
	# the tree stands upright at the circle's far side from him, its foot on the ground, and falls across it
	var away := origin - actor.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var foot_at := origin + away * (radius + 2.5)
	var e := RootwardenModel.entry().get("pieces", {}) as Dictionary
	var foot: Array = (e.get("tree", {}) as Dictionary).get("foot_local", [0, 0, 0])
	var head: Array = (e.get("tree", {}) as Dictionary).get("head_local", [0, 8, 0])
	var fl := Vector3(float(foot[0]), float(foot[1]), float(foot[2]))
	var hl := Vector3(float(head[0]), float(head[1]), float(head[2]))
	# the copy's vertices are in the skeleton's rest space; the hand's rest frame maps the tree's line
	var skel := model.skeleton
	var i := skel.find_bone("hand_r")
	var hand_rest := skel.get_bone_global_rest(i)
	var f_rest := hand_rest * fl
	var h_rest := hand_rest * hl
	var up_rest := (h_rest - f_rest).normalized()
	var align := Basis(Quaternion(up_rest, Vector3.UP))
	var stand := Transform3D(align, Vector3.ZERO) * Transform3D(Basis(), -f_rest)
	stand.origin += foot_at
	_trees.append({"node": copy, "stand": stand, "pivot": foot_at, "axis": Vector3.UP.cross(-away).normalized(),
		"t": 0.0, "total": maxf(0.4, duration + TREE_FALL_EXTRA_S), "landed": false, "at": origin})
	copy.global_transform = stand
	trees_felled += 1


func _trees_step(delta: float) -> void:
	for tr: Dictionary in _trees.duplicate():
		var n := tr.node as MeshInstance3D
		if not is_instance_valid(n):
			_trees.erase(tr)
			continue
		tr.t = float(tr.t) + delta
		var u := clampf(float(tr.t) / float(tr.total), 0.0, 1.0)
		var a := deg_to_rad(86.0) * u * u
		var pivot: Vector3 = tr.pivot
		n.global_transform = Transform3D(Basis(), pivot) * Transform3D(Basis(tr.axis as Vector3, a), Vector3.ZERO) \
			* Transform3D(Basis(), -pivot) * (tr.stand as Transform3D)
		if u >= 1.0 and not bool(tr.landed):
			tr.landed = true
			_dust(tr.at as Vector3, 8.0, 22, 7.0)
			_shake_at(tr.at as Vector3, 0.35)
		if float(tr.t) > float(tr.total) + 6.0:
			n.queue_free()
			_trees.erase(tr)


func _burst(point: Vector3, radius: float, scale: float) -> void:
	if not is_inside_tree():
		return
	if _spike_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.05
		c.bottom_radius = 0.55
		c.height = BURST_H
		c.radial_segments = 6
		c.rings = 1
		_spike_mesh = c
	var mat: Material = model.piece("roots").material_override if model != null and model.piece("roots") != null else null
	var root := Node3D.new()
	root.name = "RootBurst%d" % bursts_raised
	root.top_level = true
	add_child(root)
	root.global_position = point
	var nodes: Array = []
	for i in BURST_SPIKES:
		var ang := TAU * float(i) / float(BURST_SPIKES) + 0.7 * float(bursts_raised % 3)
		var r := radius * (0.35 + 0.5 * float((i * 7 + bursts_raised) % 5) / 4.0)
		var mi := MeshInstance3D.new()
		mi.mesh = _spike_mesh
		if mat != null:
			mi.material_override = mat
		var lean := Vector3(cos(ang), 0.0, sin(ang)) * -0.45
		var up := (Vector3.UP + lean).normalized()
		var b := Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(Vector3.ONE * scale * (0.8 + 0.1 * float(i % 3)))
		mi.transform = Transform3D(b, Vector3(cos(ang), 0.0, sin(ang)) * r - up * BURST_H * 0.5)
		root.add_child(mi)
		nodes.append([mi, mi.transform])
	_bursts.append({"node": root, "spikes": nodes, "t": 0.0})
	bursts_raised += 1
	_dust(point, radius * 1.2, 16, 6.0)
	_shake_at(point, ERUPT_SHAKE * 0.5)


func _bursts_step(delta: float) -> void:
	for bu: Dictionary in _bursts.duplicate():
		var root := bu.node as Node3D
		if not is_instance_valid(root):
			_bursts.erase(bu)
			continue
		bu.t = float(bu.t) + delta
		var t := float(bu.t)
		# up in 0.2 s, standing, sinking back over 0.5 s
		var rise := clampf(t / 0.2, 0.0, 1.0)
		var sink := clampf((t - BURST_STAND_S) / 0.5, 0.0, 1.0)
		var k := rise * (1.0 - sink)
		for e: Array in bu.spikes:
			var mi := e[0] as MeshInstance3D
			var x0: Transform3D = e[1]
			var up := x0.basis.y.normalized()
			mi.transform = Transform3D(x0.basis, x0.origin + up * BURST_H * k * x0.basis.get_scale().y)
		if sink >= 1.0:
			root.queue_free()
			_bursts.erase(bu)


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
	return BruteRig.clip_length(RootwardenModel.CREATURE, clip)


func _down_count() -> int:
	return int(actor.get("topples")) if actor != null and "topples" in actor else 0


func _instance() -> int:
	var c: Variant = actor.get("controller") if actor != null else null
	return (c as CombatController).instance_id if c is CombatController else -1


func current_clip() -> String:
	return _clip
