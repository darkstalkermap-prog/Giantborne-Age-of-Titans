class_name HollowEnemy
extends TitanEnemy
## E3: the Hollow Titan (enemy.hollow, 39.6 m) - the shell of Ormund, the last giant king: his armour and his crown with
## nothing living inside, moved by the oath that bound him to keep the Worldbreaker chained. A signature titan
## (TitanEnemy: his plates, phases, the circling and the hug answers, a phase's arena hazard, the topple on his greaves)
## whose fight is his hollowness (decision E3-2; his record's `hollow`):
##
## * **Nothing inside to hurt.** His hide (the mail over nothing) keeps most of a blow; a plate torn off lays bare an
##   empty socket (a broken plate's weak multiplier is under 1), but his breastplate (`hollow.knot_cover`) off lays bare
##   **the oath-knot** (`hollow.knot_region`): the binding of chain in his breast that drives the shell, the one thing in
##   him that can be hurt (PlateSet.region_mults: knot_mult). Its hurtbox and lock anchor are out of the world while the
##   breastplate holds (knot_open).
## * **What is torn off comes back.** A plate broken falls hollow.shard_out_m out from him and lies there (a shard,
##   HollowShard: the giant's interact). Its regrowth (the plate's `regrow`: the oath-chains drawing it back) puts it on
##   him again - unless the giant **crushes** it (a heavy or a stamp whose blow reaches within hollow.crush_m of it) or
##   **hurls** it back at him (hurl_shard: it strikes his breast - the knot when bare - hollow.hurl_flight_s later, as
##   the giant's own blow, hollow.hurl_action). Either way it never comes back (PlateSet.sear). Nothing regrows once no
##   oath-stone stands, nor from his last phase (the unbinding).
## * **The oath-stones** (props tagged hollow.pillar_tag within pillar_reach_m of him, BreakableProp): each stands for a
##   chain into him. While one stands his plates regrow; one brought down snaps its chain - he reels pillar_stagger_s.
##   His lash (bolts pattern "pillars") whips the chains down along the lines from each standing stone to him.
## * **His echo.** From his second phase every blow that lands on his shell (not the knot) rings in him (resonance: 1, a
##   Heavy hollow.resonance_heavy, up to resonance_full); his echo (hit shape hollow_echo: a ring of force round him)
##   gives it back - echo_min_mult .. echo_max_mult of its power by how full it rang - and empties it.
## * **His draw** (hit shape hollow_draw): the chains lash out of his breast along a cone; a giant they catch is dragged
##   toward him (its knockback held toward him) until it stands at his feet - and his embrace follows (draw.then).
## * **The preparation**: with hollow.stake_flag set (the Oath-stake pulled out of the ridge) his plates wait
##   stake_regrow_mult times as long before they are drawn back.
## Everything is decided from the sim's clock, the props' places and his brain's RNG, so a seeded fight repeats.

const DRAW_SHAPE := "hollow_draw"
const ECHO_SHAPE := "hollow_echo"
const PILLAR_REASON := "oath_snapped"
const LYING := "lying"
const RETURNING := "returning"
const CRUSHED := "crushed"
const HURLED := "hurled"
## The giant's actions that crush a shard (a heavy blow, a stamp).
const CRUSH_SHAPES := ["foot_stamp"]

var hollow: Dictionary = {}
## Plate id -> {"p": Vector3 (where it lies), "state": LYING | RETURNING | CRUSHED | HURLED, "since": tick, "node":
## its HollowShard (the interact) or null}.
var shards: Dictionary = {}
## His echo (0 .. hollow.resonance_full).
var resonance := 0.0
## The breastplate off: the oath-knot bare.
var knot_open := false
## His last phase began: nothing torn from him comes back.
var unbound := false
## Tallies this attempt (tests, the duel report).
var crushes := 0
var hurls := 0
var reforms := 0
var echoes := 0
var echo_peak := 0.0
var draws_landed := 0
var stones_felled := 0
var knot_hits := 0
var knot_damage := 0.0
var _knot_boxes: Array[Hurtbox] = []
## The breastplate's own boxes: out of the world while it is off (the knot is what a blow there meets).
var _cover_boxes: Array[Hurtbox] = []
var _knot_anchor: Node3D = null
var _knot_layer := HitQueryAdapter.LAYER_HURTBOX
var _drag: Dictionary = {}
var _flights: Array = []
var _pillars_known := 0
var _watched := {}
var _base_after := {}


func _ready() -> void:
	super()
	hollow = record.get("hollow", {}) if typeof(record.get("hollow")) == TYPE_DICTIONARY else {}
	runner.register_shape(DRAW_SHAPE, _run_draw)
	runner.register_shape(ECHO_SHAPE, _run_echo)
	var region := knot_region()
	var cover_region := ""
	if entity.plates != null:
		cover_region = str(entity.plates.plate(knot_cover()).get("region", ""))
	for n in find_children("*", "Hurtbox", true, false):
		var hb := n as Hurtbox
		if hb != null and hb.region == region:
			_knot_boxes.append(hb)
		elif hb != null and cover_region != "" and hb.region == cover_region:
			_cover_boxes.append(hb)
	_knot_anchor = get_node_or_null(NodePath("Anchors/" + str(hollow.get("knot_anchor", "PlateKnot")))) as Node3D
	if entity.plates != null:
		entity.plates.region_mults[region] = [float(hollow.get("knot_mult", 2.4)), float(hollow.get("knot_poise_mult", 1.0))]
		for p: Dictionary in entity.plates.plates:
			if not (p.get("regrow", {}) as Dictionary).is_empty():
				_base_after[str(p.id)] = float((p.regrow as Dictionary).get("after_s", 12.0))
	_apply_stake()
	for pair: Array in [[Events.plate_broken, _on_plate_broken_e3], [Events.plate_regrowing, _on_plate_regrowing_e3],
			[Events.plate_regrown, _on_plate_regrown_e3], [Events.hit_resolved, _on_any_hit_e3],
			[Events.object_destroyed, _on_object_destroyed_e3]]:
		if not (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).connect(pair[1])
	controller.phase_entered.connect(_on_hollow_phase)
	_set_knot(false)
	_pillars_known = _pillars(false).size()


func _exit_tree() -> void:
	super()
	for pair: Array in [[Events.plate_broken, _on_plate_broken_e3], [Events.plate_regrowing, _on_plate_regrowing_e3],
			[Events.plate_regrown, _on_plate_regrown_e3], [Events.hit_resolved, _on_any_hit_e3],
			[Events.object_destroyed, _on_object_destroyed_e3]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	_free_shard_nodes()


func knot_region() -> String:
	return str(hollow.get("knot_region", "knot"))


func knot_cover() -> String:
	return str(hollow.get("knot_cover", "cuirass"))


func sim_step(tick: int, dt: float) -> void:
	_e3_step(tick)
	super(tick, dt)


func _e3_step(tick: int) -> void:
	if entity == null:
		return
	_watch_giants()
	_flights_step(tick)
	if not entity.is_alive():
		return
	_drag_step(tick)
	if not holds():
		_sear_all(tick)
	var open := entity.plates != null and entity.plates.is_broken(knot_cover())
	if open != knot_open:
		_set_knot(open)


# --------------------------------------------------------------------------- the knot

func _set_knot(open: bool) -> void:
	knot_open = open
	for hb in _knot_boxes:
		if is_instance_valid(hb):
			hb.collision_layer = _knot_layer if open else 0
	for hb in _cover_boxes:
		if is_instance_valid(hb):
			hb.collision_layer = 0 if open else _knot_layer
	if is_inside_tree() and entity != null:
		Events.knot_exposed.emit(Sim.tick, entity.entity_id, open)


## A5's lock candidates, and the oath-knot while it is bare (a weak point: the lock frames it before a plate).
func lock_candidates(viewer_height: float) -> Array:
	var out := super(viewer_height)
	if not knot_open or _knot_anchor == null or not is_instance_valid(_knot_anchor):
		return out
	var viewer := _lock_viewer()
	if viewer == null or viewer_height <= 0.0:
		return out
	var at := _knot_anchor.global_position
	var reach := viewer_height * LOCK_REACH_SHARE + LOCK_REACH_SLACK_M
	if at.y - global_position.y > reach:
		return out
	var viewer_pos := viewer.global_position + Vector3.UP * viewer_height * 0.75
	var comfortable := at.y - global_position.y <= viewer_height * LOCK_COMFORT_SHARE
	var score := at.distance_to(viewer_pos) - LOCK_WEAK_BONUS_M * 2.0 + (0.0 if comfortable else LOCK_HIGH_PENALTY_M)
	out.append({"id": knot_region(), "at": at, "score": score, "high": comfortable, "broken": true})
	return out


## The knot's place in the world (Vector3.INF when he has none).
func knot_point() -> Vector3:
	return _knot_anchor.global_position if _knot_anchor != null and is_instance_valid(_knot_anchor) else Vector3.INF


# --------------------------------------------------------------------------- the shards

## A plate of his broke: it falls and lies (a shard) - unless nothing comes back now, when it is seared at once (it still
## lies, and can still be hurled).
func _on_plate_broken_e3(tick: int, entity_id: String, plate_id: String) -> void:
	if entity == null or entity_id != entity.entity_id or not is_inside_tree():
		return
	var p := entity.plates.plate(plate_id)
	if p.is_empty() or str(p.get("piece", "")) == "":
		return
	var anchor := get_node_or_null(NodePath("Anchors/" + str(p.get("anchor", "")))) as Node3D
	var from := anchor.global_position if anchor != null else global_position
	var out := from - global_position
	out.y = 0.0
	out = out.normalized() if out.length() > 0.3 else -global_transform.basis.z
	var r := float(record.get("capsule_radius_m", 6.0)) + float(hollow.get("shard_out_m", 8.0))
	var at := global_position + out * r
	at.y = _ground_y(at, global_position.y)
	_drop_shard_node(plate_id)
	shards[plate_id] = {"p": at, "state": LYING, "since": tick, "node": null}
	_spawn_shard_node(plate_id, at)
	Events.shard_fell.emit(tick, entity.entity_id, plate_id, at)
	if not holds():
		_sear(plate_id, tick)


func _on_plate_regrowing_e3(tick: int, entity_id: String, plate_id: String) -> void:
	if entity == null or entity_id != entity.entity_id or not shards.has(plate_id):
		return
	var s: Dictionary = shards[plate_id]
	if str(s.state) != LYING:
		return
	s.state = RETURNING
	s.since = tick
	_drop_shard_node(plate_id)
	Events.shard_dealt.emit(tick, entity.entity_id, plate_id, RETURNING)


func _on_plate_regrown_e3(_tick: int, entity_id: String, plate_id: String) -> void:
	if entity == null or entity_id != entity.entity_id:
		return
	reforms += 1
	_drop_shard_node(plate_id)
	shards.erase(plate_id)
	var p := entity.plates.plate(plate_id)
	if str(p.get("effect", "")) == PlateRules.EFFECT_UNBALANCE and float(p.get("poise_mult", 1.0)) > 0.0:
		entity.plates.poise_taken_mult /= float(p.get("poise_mult", 1.0))   # (the crown back on: his balance back)


## The state of the shard of plate `id` ("" none).
func shard_state(id: String) -> String:
	return str((shards.get(id, {}) as Dictionary).get("state", ""))


## The plates lying where they fell (the duel bot, the HUD).
func lying_shards() -> Array[String]:
	var out: Array[String] = []
	for id: String in shards:
		if str(shards[id].state) == LYING:
			out.append(id)
	return out


## Whether the oath still draws his plates back (an oath-stone stands - or none ever stood near him - and his last
## phase has not begun).
func holds() -> bool:
	if unbound:
		return false
	return _pillars_known == 0 or not _pillars(true).is_empty()


## Plate `id`'s wound never regrows (crushed, hurled, the oath broken).
func _sear(id: String, tick: int) -> void:
	if entity.plates != null and entity.plates.sear(id):
		regrow_log.append([tick, "seared", id])
		Events.plate_seared.emit(tick, entity.entity_id, id)
	if shards.has(id) and str(shards[id].state) == RETURNING:
		shards[id].state = LYING   # (drawn halfway back when the oath broke: it drops where it was)


func _sear_all(tick: int) -> void:
	if entity.plates == null:
		return
	for id: String in entity.plates.wounds.keys():
		if entity.plates.wound_state(id) != PlateRules.WOUND_SEARED:
			_sear(id, tick)


## The giant's heavy or stamp reached a shard: it is crushed into the ground (it never comes back).
func crush_shard(id: String, tick: int = -1) -> bool:
	if shard_state(id) != LYING or not entity.is_alive():
		return false
	if tick < 0:
		tick = Sim.tick
	shards[id].state = CRUSHED
	shards[id].since = tick
	_drop_shard_node(id)
	_sear(id, tick)
	crushes += 1
	Events.shard_dealt.emit(tick, entity.entity_id, id, CRUSHED)
	return true


## The giant `g` hurls the shard of plate `id` back at him: it never comes back, and it strikes his breast (the knot when
## bare) hollow.hurl_flight_s later as the giant's blow (hollow.hurl_action). False when it does not lie within reach.
func hurl_shard(id: String, g: GiantPlayer) -> bool:
	if shard_state(id) != LYING or g == null or not entity.is_alive() or g.entity == null or not g.entity.is_alive():
		return false
	var s: Dictionary = shards[id]
	var reach := float(hollow.get("hurl_reach_m", 10.0)) + _giant_radius(g)
	if _flat(g.global_position, s.p) > reach + 1e-3:
		return false
	s.state = HURLED
	s.since = Sim.tick
	_drop_shard_node(id)
	_sear(id, Sim.tick)
	hurls += 1
	_flights.append({"plate": id, "due": Sim.tick + ActionDef.seconds_to_ticks(float(hollow.get("hurl_flight_s", 0.7))),
		"giant": g.entity.entity_id})
	Events.shard_dealt.emit(Sim.tick, entity.entity_id, id, HURLED)
	return true


func _flights_step(tick: int) -> void:
	var i := 0
	while i < _flights.size():
		var f: Dictionary = _flights[i]
		if tick < int(f.due):
			i += 1
			continue
		_flights.remove_at(i)
		var e := Sim.get_entity(str(f.giant))
		if e == null or not is_instance_valid(e.actor) or not entity.is_alive():
			continue
		var g := e.actor as GiantPlayer
		var a := GameData.get_action(str(hollow.get("hurl_action", "")))
		if g == null or a == null or g.attack == null:
			continue
		var ctx := g.attack.runner.context()
		ctx.instance_id = Sim.new_instance_id()
		ctx.registry = HitRegistry.new()
		ctx.area_effect = true
		var at := knot_point() if knot_open else global_position + Vector3.UP * float(record.get("height_m", 30.0)) * 0.7
		var cand := {"entity": entity, "hurtbox": null, "point": at, "substep": 0,
			"distance": _flat(g.global_position, global_position)}
		var hit := HitFactory.build(ctx, a, cand, 1, tick)
		hit.region = knot_region() if knot_open else str(entity.plates.plate(knot_cover()).get("region", "chest"))
		Sim.queue_hit(hit)


## The giant's heavy or stamp reaching its active phase: a lying shard within its reach is crushed.
func _watch_giants() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("player"):
		var g := n as GiantPlayer
		if g == null or g.controller == null or _watched.has(g.get_instance_id()):
			continue
		_watched[g.get_instance_id()] = true
		g.controller.phase_entered.connect(_on_giant_phase.bind(g))


func _on_giant_phase(a: ActionDef, _instance_id: int, phase: int, g: GiantPlayer) -> void:
	if a == null or phase != ActionDef.Phase.ACTIVE or not is_instance_valid(self) or entity == null \
			or not entity.is_alive() or not is_instance_valid(g) or shards.is_empty():
		return
	if not (a.has_tag("Heavy") or a.hit_shape in CRUSH_SHAPES):
		return
	var h := g.entity.combatant.height_m if g.entity != null else 10.0
	var fwd := Vector3(-sin(g.facing_yaw), 0.0, -cos(g.facing_yaw))
	var reach := g.global_position + fwd * h * 0.3
	var crush := float(hollow.get("crush_m", 9.0)) + h * 0.12
	for id: String in lying_shards():
		var p: Vector3 = shards[id].p
		if _flat(reach, p) <= crush or _flat(g.global_position, p) <= crush:
			crush_shard(id)


func _spawn_shard_node(id: String, at: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var n := HollowShard.new()
	n.name = "Shard_%s_%s" % [entity.entity_id, id]
	n.titan = self
	n.plate_id = id
	n.interact_id = "%s.shard.%s" % [entity.entity_id, id]
	n.radius_m = float(hollow.get("hurl_reach_m", 10.0))
	parent.add_child(n)
	n.global_position = at
	shards[id]["node"] = n


func _drop_shard_node(id: String) -> void:
	if not shards.has(id):
		return
	var n: Variant = shards[id].get("node")
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()
	shards[id]["node"] = null


func _free_shard_nodes() -> void:
	for id: String in shards:
		_drop_shard_node(id)


# --------------------------------------------------------------------------- the oath-stones

## The oath-stones near him (`standing` only those still up), in a stable order (their world ids).
func _pillars(standing: bool) -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var tag := str(hollow.get("pillar_tag", "oath_pillar"))
	var reach := float(hollow.get("pillar_reach_m", 170.0))
	var home := _home_point()
	for n in get_tree().get_nodes_in_group("breakables"):
		var b := n as BreakableProp
		if b == null or (standing and b.destroyed):
			continue
		var tags: Array = b.record.get("prop_tags", []) if typeof(b.record) == TYPE_DICTIONARY else []
		if not tags.has(tag) or _flat(b.global_position, home) > reach:
			continue
		out.append(b)
	out.sort_custom(func(a: BreakableProp, b: BreakableProp) -> bool: return a.world_id < b.world_id)
	return out


## The oath-stones still standing (the rig, the duel bot, tests).
func standing_stones() -> Array:
	return _pillars(true)


func _home_point() -> Vector3:
	var arena := territory()
	return arena.global_position if arena != null else global_position


func _on_object_destroyed_e3(tick: int, world_id: String, _killer_id: String) -> void:
	if entity == null or not entity.is_alive() or not is_inside_tree():
		return
	for b: BreakableProp in _pillars(false):
		if b.world_id != world_id:
			continue
		stones_felled += 1
		Events.oath_stone_fell.emit(tick, entity.entity_id, world_id)
		var s := float(hollow.get("pillar_stagger_s", 2.5))
		if s > 0.0 and not is_down() and not yielded and not dormant:
			if controller.action != null:
				controller.call("_finish_action", true)
			controller.buffer.clear()
			entity.stagger(s, PILLAR_REASON)
		return


# --------------------------------------------------------------------------- his echo

func _on_any_hit_e3(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or not is_instance_valid(self) or entity == null or not entity.is_alive():
		return
	if r.event.attacker_id == entity.entity_id:
		if r.event.action_id != "" and (r.outcome == HitResult.Outcome.HIT or r.outcome == HitResult.Outcome.BLOCKED):
			var a := GameData.get_action(r.event.action_id)
			if a != null and a.hit_shape == DRAW_SHAPE:
				_start_drag(r.event.target_id, a)
		return
	if r.event.target_id != entity.entity_id or r.outcome != HitResult.Outcome.HIT:
		return
	if r.event.region == knot_region():
		knot_hits += 1
		knot_damage += r.health_damage
		return
	if brain == null or brain.phase_index < 1:
		return   # (his echo wakes with his second phase's call)
	var full := float(hollow.get("resonance_full", 12.0))
	var add := float(hollow.get("resonance_heavy", 2.0)) if r.event.tags.has("Heavy") else 1.0
	resonance = minf(full, resonance + add)
	echo_peak = maxf(echo_peak, resonance)
	Events.echo_built.emit(Sim.tick, entity.entity_id, resonance)


## His echo's power multiplier now (by how full it rang).
func echo_mult() -> float:
	var full := maxf(float(hollow.get("resonance_full", 12.0)), 1e-3)
	return lerpf(float(hollow.get("echo_min_mult", 0.35)), float(hollow.get("echo_max_mult", 1.6)),
		clampf(resonance / full, 0.0, 1.0))


func resonance_frac() -> float:
	return clampf(resonance / maxf(float(hollow.get("resonance_full", 12.0)), 1e-3), 0.0, 1.0)


## The echo (hit shape hollow_echo): on its first active tick one ring of force round him (radius_m, height_m), its
## power echo_mult; his echo empties.
func _run_echo(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var mult := echo_mult()
	var cands := HitQueryAdapter.cylinder_pulse(get_world_3d().direct_space_state, entity,
		global_position + Vector3.UP * (a.height_m * 0.5), a.radius_m, a.height_m, global_position + Vector3.UP * 2.0)
	var ctx := runner.context()
	ctx.area_effect = true
	ctx.outgoing_damage_mult = entity.combatant.outgoing_damage_mult() * mult
	HitFactory.queue(ctx, a, cands, 1, tick)
	echoes += 1
	Events.echo_released.emit(tick, entity.entity_id, mult)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, global_position, a.radius_m)
	resonance = 0.0


# --------------------------------------------------------------------------- his draw

## The draw (hit shape hollow_draw): on its first active tick every giant within draw.range_m and draw.arc_deg of his
## facing is struck (a hit of the action: a dodge's frames evade it); one struck is dragged in (_start_drag).
func _run_draw(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var spec: Dictionary = a.param("draw", {})
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var half := deg_to_rad(float(spec.get("arc_deg", 36.0)) * 0.5)
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		var g := n as GiantPlayer
		if g == null or g.entity == null or not g.entity.is_alive():
			continue
		var to := g.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > float(spec.get("range_m", 70.0)) + _giant_radius(g) or d < 0.5:
			continue
		if absf(fwd.signed_angle_to(to.normalized(), Vector3.UP)) > half + atan2(_giant_radius(g), d):
			continue
		cands.append({"entity": g.entity, "hurtbox": null, "point": g.global_position + Vector3.UP * 2.0, "substep": 0,
			"distance": d})
	var ctx := runner.context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "draw", global_position, float(spec.get("range_m", 70.0)),
		facing_yaw, float(spec.get("arc_deg", 36.0)))


func _start_drag(target_id: String, a: ActionDef) -> void:
	var spec: Dictionary = a.param("draw", {})
	_drag = {"target": target_id, "until": Sim.tick + ActionDef.seconds_to_ticks(float(spec.get("drag_s", 1.6))),
		"speed": float(spec.get("speed_mps", 34.0)), "min_m": float(spec.get("min_m", 10.0)), "then": str(spec.get("then", ""))}
	draws_landed += 1
	Events.titan_drew.emit(Sim.tick, entity.entity_id, target_id)


## While a drag runs: the caught giant's knockback is held toward him until it stands at his feet.
func _drag_step(tick: int) -> void:
	if _drag.is_empty():
		return
	var e := Sim.get_entity(str(_drag.target))
	var g := e.actor as GiantPlayer if e != null and is_instance_valid(e.actor) else null
	var done := g == null or not g.entity.is_alive() or tick >= int(_drag.until) or is_down() \
		or controller.state == CombatController.State.STAGGERED
	if not done:
		var to := global_position - g.global_position
		to.y = 0.0
		var edge := to.length() - float(record.get("capsule_radius_m", 6.0)) - _giant_radius(g)
		if edge <= float(_drag.min_m):
			done = true
		else:
			g.knockback_velocity = to.normalized() * minf(float(_drag.speed), edge * float(Sim.TICK_RATE))
	if done:
		var then := str(_drag.get("then", ""))
		_drag = {}
		if then != "" and g != null and g.entity.is_alive() and not is_down() and brain is TitanBrain:
			(brain as TitanBrain).answer_next(then, true)


func is_dragging() -> bool:
	return not _drag.is_empty()


# --------------------------------------------------------------------------- the lash: along the oath-chains

## Bolts pattern "pillars": count circles along the line from each standing oath-stone to him (from the stone's foot to
## his feet, not under him), struck with bolts.action; with none standing, count x 2 round his own feet at radius_m.
func _run_bolts(a: ActionDef, tick: int) -> void:
	var spec: Dictionary = a.param("bolts", {})
	if str(spec.get("pattern", "")) != "pillars":
		super(a, tick)
		return
	if not controller.is_first_active_tick():
		return
	var hb := brain as HarrokBrain
	var bolt := GameData.get_action(str(spec.get("action", "")))
	if hb == null or bolt == null:
		return
	var hz: Dictionary = bolt.param("arena_hazard", {})
	var radius := float(hz.get("radius_m", bolt.radius_m))
	var tele := ActionDef.seconds_to_ticks(float(spec.get("telegraph_s", hz.get("telegraph_s", 1.5))))
	var step := ActionDef.seconds_to_ticks(float(spec.get("interval_s", 0.1)))
	var count := int(spec.get("count", 4))
	var points: Array = []
	var stones := _pillars(true)
	if stones.is_empty():
		var r := float(spec.get("radius_m", 22.0))
		var a0 := hb.rng.randf() * TAU
		for i in count * 2:
			var ang := a0 + TAU * i / float(count * 2)
			points.append(global_position + Vector3(sin(ang), 0.0, cos(ang)) * r)
	else:
		var own := float(record.get("capsule_radius_m", 6.0)) + radius
		for b: BreakableProp in stones:
			var from := b.global_position
			var line := global_position - from
			line.y = 0.0
			var length := line.length() - own
			if length < radius:
				continue
			for i in count:
				points.append(from + line.normalized() * (radius + (length - radius) * float(i) / float(maxi(1, count - 1))))
	for i in points.size():
		var p: Vector3 = points[i]
		p.y = _ground_y(p, global_position.y)
		var due := tick + tele + step * (i % count)
		var h := hb.add_hazard(p, due, bolt.id)
		bolts_called += 1
		Events.telegraph_started.emit(tick, hazard_key(int(h.id)), bolt.id, hb.target_id, "circle", p, 0.0, radius, 0.0,
			float(due - tick) / float(Sim.TICK_RATE))


# --------------------------------------------------------------------------- his phases

## The unbinding (his last phase's entry, ACTIVE): his breastplate bursts off (whole or not), and nothing comes back.
func _on_hollow_phase(a: ActionDef, _instance_id: int, phase: int) -> void:
	if a == null or phase != ActionDef.Phase.ACTIVE or not entity.is_alive():
		return
	if a.id == "ability.hollow_unbinding":
		unbind()


## His last phase: the oath gives - every open wound seared, the breastplate thrown off. False when already unbound.
func unbind() -> bool:
	if unbound or entity.plates == null:
		return false
	unbound = true
	var cover := knot_cover()
	if not entity.plates.is_broken(cover) and entity.plates.force_break(cover):
		plate_breaks.append(cover)
		Events.plate_broken.emit(Sim.tick, entity.entity_id, cover)
	_sear_all(Sim.tick)
	return true


func _apply_stake() -> void:
	if entity == null or entity.plates == null:
		return
	var flag := str(hollow.get("stake_flag", ""))
	var k := float(hollow.get("stake_regrow_mult", 1.0)) if flag != "" \
		and QuestConditions.truthy(WorldState.get_flag(flag)) else 1.0
	for p: Dictionary in entity.plates.plates:
		if _base_after.has(str(p.id)):
			(p.regrow as Dictionary)["after_s"] = float(_base_after[str(p.id)]) * k


# --------------------------------------------------------------------------- the attempt, his fall

func _p34_reset_extra() -> void:
	super()
	_free_shard_nodes()
	shards.clear()
	resonance = 0.0
	unbound = false
	_drag = {}
	_flights.clear()
	crushes = 0
	hurls = 0
	reforms = 0
	echoes = 0
	echo_peak = 0.0
	draws_landed = 0
	knot_hits = 0
	knot_damage = 0.0
	_apply_stake()
	_set_knot(false)


func on_entity_died(killer_id: String) -> void:
	super(killer_id)
	_free_shard_nodes()
	_drag = {}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _giant_radius(g: GiantPlayer) -> float:
	var h := g.entity.combatant.height_m if g != null and g.entity != null else 10.0
	return h * 0.19   # (the giant's capsule: 6.9 m at stage 9's 35.4 m)


func get_rig_state() -> Dictionary:
	var s := super()
	var list := {}
	for id: String in shards:
		list[id] = {"p": shards[id].p, "state": shards[id].state, "since": shards[id].since}
	s["shards"] = list
	s["knot_open"] = knot_open
	s["resonance"] = resonance_frac()
	s["unbound"] = unbound
	s["dragging"] = is_dragging()
	s["holds"] = holds()
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	d["hollow"] = "knot %s, echo %.0f, shards %d (crushed %d, hurled %d, back %d), stones %d" % [
		"BARE" if knot_open else "covered", resonance, shards.size(), crushes, hurls, reforms, _pillars(true).size()]
	return d
