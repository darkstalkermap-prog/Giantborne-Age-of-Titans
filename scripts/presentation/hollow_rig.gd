class_name HollowRig
extends StormcallerRig
## The Hollow Titan in play (E3): his model (HollowModel: a harness of plate on the Stormcaller's skeleton, scaled to
## 39.6 m) under his actor (HollowEnemy, enemy.hollow), posed from the actor's state as StormcallerRig poses the
## Stormcaller - his actions name their clips (CLIPS: the Stormcaller's for the cleave, reap, thrust, lash and call, his
## own HollowClips for his stance, vigil, wake, draw, embrace, echo and fall) - and the hollow's signs drawn
## (presentation only: nothing in the simulation reads it back):
##   * his torn plates: a plate breaks, its piece falls off him and lies where the sim says it lies (HollowEnemy.shards);
##     drawn back, it rises off the ground and flies home; crushed, it flattens into the ground; hurled, it flies from the
##     giant into his breast and drops at his feet;
##   * the oath-knot: its light through the shell, bright once the breastplate is off (HollowModel.set_knot_bare);
##   * his echo: the shell's edges shimmering as it fills (set_resonance); given back, a ring of dust and a pale ring
##     running out over the ground;
##   * the oath-chains: one from each standing oath-stone's collar to his back, sagging (a MultiMesh of links, one draw
##     call for every chain); a stone brought down, its chain is gone with a burst of iron;
##   * his draw: chains out of his breast to the giant while they haul it in;
##   * his fall: the knees go, then the harness comes apart piece by piece and lies on the ground, the light dying.

const CLIPS := {"cleave": "slam", "reap": "sweep", "thrust": "chain", "draw": "draw", "embrace": "embrace",
	"echo": "echo", "lash": "call", "call": "roar", "unbinding": "roar", "wake": "wake"}
const OWN_STRIKES := ["slam", "sweep", "call", "chain", "draw", "embrace", "echo"]
const IRON := Color(0.16, 0.16, 0.17)
const GILT := Color(0.55, 0.42, 0.2)
const FALL_S := 0.9
const CRUSH_S := 0.3
const COLLAPSE_FROM_S := 2.2
const COLLAPSE_EVERY_S := 0.16
const LIFE_FADE_S := 5.0
const LINK_M := 2.6
const CHAIN_SAG := 0.08

var shards_drawn: Dictionary = {}
var chains: MultiMeshInstance3D = null
var chain_links := 0
var draws_drawn := 0
var echoes_drawn := 0
var collapsed: Array[String] = []
var _life := 1.0
var _draw_t := 0.0
var _t := 0.0
var _collapse_t := 0.0


func _ready() -> void:
	super()
	Events.echo_released.connect(_on_echo)
	Events.titan_drew.connect(_on_drew)
	Events.oath_stone_fell.connect(_on_stone_fell)


func _exit_tree() -> void:
	super()
	for pair: Array in [[Events.echo_released, _on_echo], [Events.titan_drew, _on_drew],
			[Events.oath_stone_fell, _on_stone_fell]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _build_model() -> void:
	if model != null or body == null:
		return
	var m := HollowModel.new()
	m.name = MODEL_NAME
	body.add_child(m)
	if m.model == null:
		m.queue_free()
		return
	model = m
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * HollowModel.SCALE), Vector3.ZERO)
	skinned = true
	_keys = StormcallerModel.clip_keys().duplicate()
	_keys.merge(HollowClips.KEYS, true)
	var gaits: Dictionary = ((StormcallerModel.facts().get("clips", {}) as Dictionary).get("gaits", {}))
	for g: String in ["walk", "run"]:
		_stride[g] = float((gaits.get(g, {}) as Dictionary).get("stride_m", _stride[g])) * HollowModel.SCALE
	var proxy := get_node_or_null("LodProxy") as GeometryInstance3D
	if proxy != null:
		proxy.visible = false
	for c in body.get_children():
		if c != model and c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false
	chains = MultiMeshInstance3D.new()
	chains.name = "OathChains"
	chains.top_level = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var ab := HollowArmour.new()
	ab.tone = 0.35
	ab.link(Vector3.ZERO, Vector3.BACK, LINK_M, LINK_M * 0.56, LINK_M * 0.13, false)
	ab.link(Vector3(0, 0, LINK_M * 0.78), Vector3.BACK, LINK_M, LINK_M * 0.56, LINK_M * 0.13, true)
	mm.mesh = ab.mesh()
	mm.instance_count = 200
	mm.visible_instance_count = 0
	chains.multimesh = mm
	chains.material_override = m.chain_material
	add_child(chains)


func hollow_model() -> HollowModel:
	return model as HollowModel


func clip_kind(a: ActionDef) -> String:
	if a == null:
		return ""
	var k := a.id.get_slice(".", 1)
	k = k.substr(k.find("_") + 1)
	return str(CLIPS.get(k, k))


func _len(clip: String) -> float:
	return model.clip_length(clip) if model != null else 1.0


func _process(delta: float) -> void:
	super(delta)
	_t += delta
	var m := hollow_model()
	if m == null or actor == null or not actor.has_method("get_rig_state"):
		return
	var s := rig_state()
	var dead := bool(s.get("dead", false))
	m.set_knot_bare(bool(s.get("knot_open", false)))
	m.set_resonance(float(s.get("resonance", 0.0)))
	if dead:
		_life = maxf(0.0, _life - delta / LIFE_FADE_S)
		_collapse_step(delta)
	else:
		_life = 1.0
		_collapse_t = 0.0
	m.set_life(_life)
	_shards_step(s, delta)
	_chains_step(s, delta)


# --------------------------------------------------------------------------- the clips

func _play(s: Dictionary, delta: float) -> void:
	var player := model.player
	if player == null:
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
	elif kind in OWN_STRIKES:
		clip = kind
		t = _strike(clip, phase, f)
	elif kind == "wake" or kind == "roar":
		clip = "roar2" if kind == "roar" else kind
		t = _len(clip) * TitanRig._action_share(action, phase, f)
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
	var lib := HollowClips.LIBRARY if HollowClips.has(model, clip) else StormcallerModel.LIBRARY
	var full := StringName(String(lib) + "/" + clip)
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


func _feel(clip: String, t: float, before: float, length: float, s: Dictionary) -> void:
	super(clip, t, before, length, s)
	var hit := float((_keys.get(clip, [0, 0, -1.0]) as Array)[2]) if _keys.has(clip) else -1.0
	if hit <= 0.0 or t < hit or before >= hit + 0.25 or not clip in ["draw", "embrace", "echo"]:
		return
	if _struck_instance == _instance():
		return
	_struck_instance = _instance()
	impacts += 1
	var m := hollow_model()
	match clip:
		"echo":
			var at := m.rod_point("head_local")
			at.y = actor.global_position.y
			_splash_or_dust(at, 12.0, 34)
			_chips(at, 12, GRIT_COLOR, 1.0)
			_shake_at(at, RING_SHAKE)
		"embrace":
			var at := actor.global_position - actor.global_transform.basis.z * 9.0
			_splash_or_dust(at, 10.0, 24)
			_shake_at(at, STOMP_SHAKE)
		"draw":
			var at := m.piece_centre("cuirass") if m.plate_visible("cuirass") else m.global_position + Vector3.UP * 28.0
			_dust(at, 6.0, 14, 8.0, DUST)


# --------------------------------------------------------------------------- the plates and the shards

## The plates as the actor has them: cracking as they wear; broken, the shards draw them (_shards_step); whole again
## (drawn back) shown on him.
func _show_plates(s: Dictionary) -> void:
	var broken: Array = s.get("plates_broken", [])
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	if ps == null or bool(s.get("dead", false)):
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
			_chips(at, int(p.debris), IRON, 1.0)
			_chips(at, maxi(2, int(p.debris) / 3), GILT, 0.6)
			_dust(at, 5.5, 20, 6.0, DUST)
			_make_shard(id, piece)
			model.set_plate_visible(piece, false)
		else:
			model.set_plate_visible(piece, true)
			model.set_plate_crack(piece, 0.0)
			var rec: Dictionary = shards_drawn.get(id, {})
			if not rec.is_empty():
				(rec.node as Node).queue_free()
				shards_drawn.erase(id)
				_chips(model.piece_centre(piece), 8, GILT, 0.5)


func _piece_of(id: String) -> String:
	var ps := (actor as TitanEnemy).plates() if actor is TitanEnemy else null
	return str(ps.plate(id).get("piece", "")) if ps != null else ""


## A copy of the plate's piece where it hangs now, to fall off him (the piece itself is hidden).
func _make_shard(id: String, piece: String) -> void:
	var mi := model.piece(piece)
	if mi == null or mi.mesh == null or shards_drawn.has(id):
		return
	var copy := MeshInstance3D.new()
	copy.name = "Shard_" + piece
	copy.mesh = mi.mesh
	copy.material_override = mi.material_override
	copy.top_level = true
	add_child(copy)
	copy.global_transform = mi.global_transform
	shards_drawn[id] = {"node": copy, "piece": piece, "start": mi.global_transform, "lie": mi.global_transform, "t": 0.0,
		"state": "", "landed": false}


## Each shard the actor holds, drawn: falling to where it lies, lying, drawn home, crushed, hurled.
func _shards_step(s: Dictionary, delta: float) -> void:
	var list: Dictionary = s.get("shards", {})
	var m := hollow_model()
	for id: String in list:
		var sh: Dictionary = list[id]
		var rec: Dictionary = shards_drawn.get(id, {})
		if rec.is_empty():
			continue
		var node := rec.node as MeshInstance3D
		var piece := str(rec.piece)
		var state := str(sh.state)
		if state != str(rec.state) and str(rec.state) != "dropped":
			if str(rec.state) == "":
				rec.lie = _lie_transform(node, sh.p as Vector3, node.global_transform)
			rec.state = state
			rec.t = 0.0
			rec.start = node.global_transform
		rec.t = float(rec.t) + delta
		var tt := float(rec.t)
		match str(rec.state):
			HollowEnemy.LYING:
				var k := clampf(tt / FALL_S, 0.0, 1.0)
				node.global_transform = _arc_xf(rec.start as Transform3D, rec.lie as Transform3D, k * k, 0.0)
				if k >= 1.0 and not bool(rec.landed):
					rec.landed = true
					var at := (rec.lie as Transform3D).origin
					_splash_or_dust(at, 6.0, 18)
					_chips(at, 8, IRON, 0.7)
					_shake_at(at, 0.18)
			HollowEnemy.RETURNING:
				var k := clampf(tt / 3.0, 0.0, 1.0)
				var home := m.piece(piece).global_transform if m.piece(piece) != null else node.global_transform
				node.global_transform = _arc_xf(rec.start as Transform3D, home, k * k * (3.0 - 2.0 * k), 6.0)
			HollowEnemy.CRUSHED:
				var k := clampf(tt / CRUSH_S, 0.0, 1.0)
				var lie: Transform3D = rec.start
				var squash := Basis.from_scale(Vector3(1.0 + 0.25 * k, 1.0 - 0.55 * k, 1.0 + 0.25 * k))
				node.global_transform = Transform3D(squash * lie.basis, lie.origin - Vector3.UP * 0.6 * k * HollowModel.SCALE)
				if tt <= delta + 1e-4:
					_chips(lie.origin, 14, IRON, 1.0)
					_dust(lie.origin, 8.0, 26, 8.0, DUST)
					_shake_at(lie.origin, 0.3)
			HollowEnemy.HURLED:
				var k := clampf(tt / 0.7, 0.0, 1.0)
				var h := actor as HollowEnemy
				var hit_at: Vector3 = h.knot_point() if bool(s.get("knot_open", false)) and h.knot_point().is_finite() \
					else actor.global_position + Vector3.UP * 27.0
				var into := Transform3D((rec.start as Transform3D).basis.rotated(Vector3.RIGHT, k * 2.5), hit_at)
				if k < 1.0:
					node.global_transform = _arc_xf(rec.start as Transform3D, into, k, 10.0)
				else:
					_chips(hit_at, 20, IRON, 1.2)
					_chips(hit_at, 8, GILT, 0.8)
					_dust(hit_at, 9.0, 28, 10.0, DUST)
					_shake_at(hit_at, 0.5)
					var at := actor.global_position + (hit_at - actor.global_position) * Vector3(1, 0, 1) * 1.6
					at.y = actor.global_position.y
					rec.lie = _lie_transform(node, at, node.global_transform)
					rec.start = node.global_transform
					rec.t = 0.0
					rec.state = "dropped"
			"dropped":
				var k := clampf(tt / FALL_S, 0.0, 1.0)
				node.global_transform = _arc_xf(rec.start as Transform3D, rec.lie as Transform3D, k * k, 0.0)
	# shards the actor no longer holds (drawn back on, a new attempt): the plate shows on him again (_show_plates)
	for id: String in shards_drawn.keys():
		if not list.has(id) and not bool(_hidden.get(id, false)):
			((shards_drawn[id] as Dictionary).node as Node).queue_free()
			shards_drawn.erase(id)


## Where a fallen piece lies: its middle over `at`, tipped over toward its outside, its lowest point on the ground.
func _lie_transform(mi: MeshInstance3D, at: Vector3, from: Transform3D) -> Transform3D:
	var out := (at - actor.global_position) * Vector3(1, 0, 1)
	out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD
	var axis := Vector3.UP.cross(out).normalized()
	var b := Basis(axis, deg_to_rad(68.0)) * from.basis
	var aabb := mi.mesh.get_aabb()
	var centre := b * aabb.get_center()
	var low := INF
	for i in 8:
		low = minf(low, (b * aabb.get_endpoint(i)).y)
	return Transform3D(b, Vector3(at.x - centre.x, at.y - low + 0.05, at.z - centre.z))


## From `a` to `b` by `k`, its middle raised `lift` m (a throw's arc), the turn slerped.
static func _arc_xf(a: Transform3D, b: Transform3D, k: float, lift: float) -> Transform3D:
	var p := a.origin.lerp(b.origin, k) + Vector3.UP * lift * 4.0 * k * (1.0 - k)
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	var sa := a.basis.get_scale()
	var sb := b.basis.get_scale()
	return Transform3D(Basis(qa.slerp(qb, k)).scaled(sa.lerp(sb, k)), p)


# --------------------------------------------------------------------------- the oath-chains

## His chains this frame: one from each standing oath-stone's collar to his back (sagging), and while his draw hauls
## the giant, three from his breast to it.
func _chains_step(s: Dictionary, delta: float) -> void:
	if chains == null or chains.multimesh == null:
		return
	var mm := chains.multimesh
	var n := 0
	var h := actor as HollowEnemy
	var m := hollow_model()
	if h != null and m != null and not bool(s.get("dead", false)):
		var back := m.bone_position("spine_03") + actor.global_transform.basis.z * 2.4 * HollowModel.SCALE \
			+ Vector3.UP * 3.0 * HollowModel.SCALE
		for b: BreakableProp in h.standing_stones():
			var collar := b.global_position + Vector3.UP * float(b.get_meta(&"collar_m", 21.0))
			n = _lay_chain(mm, n, collar, back, CHAIN_SAG)
		if bool(s.get("dragging", false)):
			_draw_t = minf(1.0, _draw_t + delta * 4.0)
		else:
			_draw_t = maxf(0.0, _draw_t - delta * 2.0)
		if _draw_t > 0.0:
			var g := get_tree().get_first_node_in_group("player") as GiantPlayer
			if g != null and g.entity != null:
				var chest := h.knot_point() if bool(s.get("knot_open", false)) and h.knot_point().is_finite() \
					else actor.global_position + Vector3.UP * 28.0 - actor.global_transform.basis.z * 3.0
				var to := g.global_position + Vector3.UP * g.entity.combatant.height_m * 0.55
				for k in 3:
					var off := Vector3(float(k - 1) * 1.6, float(k % 2) * 1.2, 0.0)
					n = _lay_chain(mm, n, chest + off, chest.lerp(to + off, _draw_t), 0.02)
	mm.visible_instance_count = n
	chain_links = n


## Lays the links of one chain from `a` to `b` (a catenary's sag of `sag` x its length) into `mm` from index `n`.
func _lay_chain(mm: MultiMesh, n: int, a: Vector3, b: Vector3, sag: float) -> int:
	var length := a.distance_to(b)
	var count := clampi(int(length / (LINK_M * 1.56)), 1, 60)
	var prev := a
	for i in count:
		if n >= mm.instance_count:
			return n
		var t1 := float(i + 1) / float(count)
		var p := a.lerp(b, t1) - Vector3.UP * length * sag * 4.0 * t1 * (1.0 - t1)
		var d := p - prev
		if d.length() < 0.01:
			continue
		var z := d.normalized()
		var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
		var y := x.cross(z)
		var basis := Basis(x, y, z).scaled(Vector3.ONE * (d.length() / (LINK_M * 1.56)))
		mm.set_instance_transform(n, Transform3D(basis, prev))
		n += 1
		prev = p
	return n


func _on_stone_fell(_tick: int, entity_id: String, world_id: String) -> void:
	if not _mine(entity_id) or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("breakables"):
		var b := n as BreakableProp
		if b != null and b.world_id == world_id:
			var collar := b.global_position + Vector3.UP * float(b.get_meta(&"collar_m", 21.0))
			_chips(collar, 16, IRON, 1.2)
			_dust(collar, 8.0, 24, 10.0, DUST)
			_shake_at(collar, 0.35)
	var m := hollow_model()
	if m != null:
		_chips(m.bone_position("spine_03"), 10, IRON, 0.8)


func _on_drew(_tick: int, entity_id: String, _target_id: String) -> void:
	if _mine(entity_id):
		draws_drawn += 1


func _on_echo(_tick: int, entity_id: String, mult: float) -> void:
	if not _mine(entity_id) or not is_inside_tree():
		return
	echoes_drawn += 1
	var at := actor.global_position + Vector3.UP * 0.4
	var radius := 30.0
	var a := GameData.get_action("ability.hollow_echo")
	if a != null:
		radius = a.radius_m
	StormFx.shock_ring(self, at, radius, 0.7)
	_dust(at, 14.0 * clampf(mult, 0.5, 1.6), 46, 18.0, DUST)
	_shake_at(at, 0.4 + 0.3 * mult)


func _mine(entity_id: String) -> bool:
	return actor != null and is_instance_valid(actor) and entity_id == str(actor.get("entity_id"))


# --------------------------------------------------------------------------- his hazards

## His telegraphed hazards (the lash's circles, the ridge's stones): the red disc where each will fall (a hazard of his
## has no actor of its own for the telegraph decals to follow).
func _on_telegraph(_tick: int, key: String, _action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, radius: float, _length: float, duration_s: float) -> void:
	if actor == null or not is_instance_valid(actor) or not key.begins_with(str(actor.get("entity_id")) + "#"):
		return
	if not is_inside_tree():
		return
	marks_drawn += 1
	StormFx.strike_mark(self, Vector3(origin.x, origin.y + 0.1, origin.z), radius, duration_s)


func _on_area_pulse(_tick: int, entity_id: String, action_id: String, point: Vector3, radius: float) -> void:
	if actor == null or not is_instance_valid(actor) or entity_id != str(actor.get("entity_id")):
		return
	if action_id.ends_with("lash_strike"):
		_dust(point, radius * 1.2, 16, 9.0, DUST)
		_chips(point, 6, IRON, 0.8)
		_shake_at(point, 0.2)
	elif action_id.ends_with("hollow_rock"):
		_dust(point, radius * 1.4, 22, 10.0, DUST)
		_chips(point, 10, GRIT_COLOR, 1.1)
		_shake_at(point, 0.3)
	elif action_id.contains("_cleave") or action_id.contains("_thrust"):
		_splash_or_dust(point, maxf(3.0, radius * 1.6), 10)


func _on_storm_bolt(_tick: int, _entity_id: String, _point: Vector3, _in_water: bool) -> void:
	pass


# --------------------------------------------------------------------------- his fall

## Dead: once his knees have gone (COLLAPSE_FROM_S into his fall) the harness comes off him a piece at a time - the
## helm first, then the arms', then the rest - each falling where it hangs and lying there.
func _collapse_step(delta: float) -> void:
	var m := hollow_model()
	if m == null:
		return
	_collapse_t += delta
	if _collapse_t < COLLAPSE_FROM_S:
		return
	var order := ["helm", "kingsword", "pauldron_l", "pauldron_r", "gauntlet_l", "gauntlet_r", "vambrace", "vambrace_l",
		"couter_l", "couter_r", "rerebrace_l", "rerebrace_r", "gorget", "mantle", "cuirass", "backplate", "knot", "faulds", "tassets",
		"cuisse_l", "cuisse_r", "poleyn_l", "poleyn_r", "greave_l", "greave_r", "sabaton_l", "sabaton_r", "toe_l", "toe_r"]
	var due := int((_collapse_t - COLLAPSE_FROM_S) / COLLAPSE_EVERY_S) + 1
	var k := 0
	for piece: String in order:
		if k >= due:
			break
		k += 1
		if piece in collapsed:
			continue
		collapsed.append(piece)
		var mi := m.piece(piece)
		if mi == null or not mi.visible:
			continue
		var c := m.piece_centre(piece)
		_drop(piece, (c - actor.global_position) * Vector3(1, 0, 1) + Vector3(float(k % 3 - 1), 0, float(k % 2)) * 2.0)
		mi.visible = false
		if k % 3 == 0:
			_dust(c, 4.0, 10, 5.0, DUST)
