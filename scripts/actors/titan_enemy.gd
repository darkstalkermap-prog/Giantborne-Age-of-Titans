class_name TitanEnemy
extends RivalGiantEnemy
## A signature titan (A2; archetype "titan"): the first is Stoneback, the 16.8 m quarry giant (enemy.stoneback).
## The rival giants' machinery (RivalGiantEnemy, OgreBoss: group "bosses", the boss framework's phases and
## sequences, chained strikes, the committed shoulder charge and its body sweep, the lobbed boulder whose
## landing circle is committed at its windup, attempts and the disengage rule) with what a titan adds:
##
## * **Breakable plates** (the record's `plates`, PlateRules / PlateSet): CombatEntity.plates is set from the
##   record, so every hit on him resolves against the plate of the region it struck (HitFactory picks one region
##   a pulse). An intact plate keeps most of a blow from the body ("armoured"); its stone takes the blow's raw
##   damage and breaks at 0: Events.plate_broken, the plate's own stagger (forced: it cuts his attack short, as
##   a wound would), and from then on the region is a weak point (weak_multiplier). The rig hides the plate's
##   mesh, throws stone and plays the break cue (TitanRig reads `plates_broken` from get_rig_state()).
## * **Phases by plates**: a boss phase with enter_on_plates_broken also begins once that many plates broke
##   (Stoneback's rage after two), at the first step he is not staggered (the break's stagger plays out first).
## * **The shock line** (hit shape titan_shock, the trunk-club smash): pulses along a line from the club's
##   impact, like line_pulse, but one hit per target for the whole line (every pulse shares pulse id 1: the hit
##   registry keeps the first), so standing in the shock costs one blow, not six.
## * **The charge breaks props**: while it runs, a prop in his way that a giant of his growth_stage tramples
##   is trampled (BreakableProp.trample: one hit, it breaks this tick); WORLD geometry (a quarry wall, a rock)
##   stops him in the record's on_wall_action - Stoneback reels for 3.5 s with his back to the giant.
## * **Lock points on the plates** (titan_lock_point, CombatEntity.lock_anchor_position): a giant tall enough to
##   reach them locks onto the nearest plate anchor it can reach, a broken one (a weak point) before an intact one;
##   PlayerAttack aims its swing's tilt at that point. A4: an anchor above the giant's comfortable swing
##   (LOCK_COMFORT_SHARE of its height) counts LOCK_HIGH_PENALTY_M farther, so a giant smaller than him goes for
##   the plates it can strike squarely - his shins - and a topple plate (a knee on the ground) is never framed
##   while he is down.
## * **Down on a knee** (A4; a plate whose on_break effect is "topple", PlateRules): the plate broken - or, once
##   broken, every again_damage more health damage to its region or the record's topple.again_regions, no sooner
##   than again_immune_s after he rose - he goes down on a knee: a stagger of the kneel, down_s and the rise
##   (reason "topple"), his attack cut short. His hurtboxes and lock anchors follow the kneel (each node's
##   `kneel_position` meta, from the kneel clip's bones: tools/builders/titans.gd), weighted by
##   PlateRules.down_weight: his shoulders, back and brow come down into a smaller giant's reach. While he is
##   down every blow takes topple.damage_mult and a Heavy topple.heavy_mult besides (PlateSet.down_mult); another
##   plate breaking keeps him down (no new stagger). TitanRig plays `kneel`, holds its last frame, then `rise`.
##
## Never grabbable, ignores morale and Fear (his record).

const SHOCK_SHAPE := "titan_shock"
## A prop this far ahead of his capsule's front (m) is trampled before his body meets it.
const CHARGE_SMASH_AHEAD_M := 1.5
## A plate anchor counts as reachable for a giant `h` metres tall up to h * this + LOCK_REACH_SLACK_M.
const LOCK_REACH_SHARE := 1.0
const LOCK_REACH_SLACK_M := 0.5
## A broken plate's anchor is preferred over an intact one this many metres nearer.
const LOCK_WEAK_BONUS_M := 8.0
## A4: an anchor higher than this share of the viewer's height counts LOCK_HIGH_PENALTY_M farther (out of a square
## swing's reach: the giant's blows at it pass under it).
const LOCK_COMFORT_SHARE := 0.9
const LOCK_HIGH_PENALTY_M := 12.0
## A4: the stagger reason of a topple, and the meta key of a node that follows the kneel.
const TOPPLE_REASON := "topple"
const KNEEL_META := "kneel_position"

## The growth stage he tramples and charges through props as (the record's growth_stage).
var growth_stage := 6
## Plates broken in this attempt (the record's ids, in order) and props his charges broke (tests, debug).
var plate_breaks: Array[String] = []
var props_smashed := 0
var _plates_phase_due := -1
var _shock: Dictionary = {}
var _wall_actions: Dictionary = {}
## A4: the record's topple block (PlateRules.parse_topple; {} when no plate topples him), the down in progress
## (the tick it began, its length in ticks and the plate that dropped him; -1 standing), how far down he is now
## (0..1: PlateRules.down_weight), the times he went down this attempt (tests, the report), the tick he last rose,
## each broken topple plate's damage toward the next topple, and the nodes that follow the kneel
## ([node, its standing position, its kneeling position]).
var topple: Dictionary = {}
var down_since := -1
var down_ticks := 0
var down_plate := ""
var down_weight := 0.0
var topples := 0
var _risen_at := -1000000
var _again: Dictionary = {}
var _kneel_nodes: Array = []


func _ready() -> void:
	super()
	growth_stage = int(record.get("growth_stage", 6))
	if typeof(record.get("plates")) == TYPE_ARRAY:
		entity.plates = PlateSet.from_record(record)
		entity.plate_struck.connect(_on_plate_struck)
	runner.register_shape(SHOCK_SHAPE, _run_shock)
	_collect_wall_actions()
	topple = PlateRules.parse_topple(record)
	_collect_kneel_nodes()


func _make_brain() -> EnemyBrain:
	return TitanBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


func current_growth_stage() -> int:
	return growth_stage


func sim_step(tick: int, dt: float) -> void:
	_down_step()
	_plates_phase_step()
	super(tick, dt)


# --------------------------------------------------------------------------- the plates

func plates() -> PlateSet:
	return entity.plates if entity != null else null


func _on_plate_struck(result: HitResult, info: Dictionary) -> void:
	if not entity.is_alive():
		return
	if not bool(info.get("broken", false)):
		_count_toward_topple(result)
		return
	var id := str(info.plate)
	plate_breaks.append(id)
	Events.plate_broken.emit(Sim.tick, entity.entity_id, id)
	var p := entity.plates.plate(id)
	var stagger := float(p.get("stagger_s", PlateRules.DEFAULT_STAGGER_S))
	if str(p.get("effect", "")) == PlateRules.EFFECT_TOPPLE and not topple.is_empty() and not yielded:
		_again[id] = 0.0
		if not is_down():
			_topple(id)
		_check_plates_phase()
		return
	if is_down():
		stagger = 0.0   # (A4: another plate breaking keeps him down; it does not stand him up into a reel)
	if stagger > 0.0 and not yielded:
		# The break staggers him whatever he was doing (a super-armoured windup included): the stone tearing off
		# is a wound, not a blow his poise answers.
		if controller.action != null:
			controller.call("_finish_action", true)
		controller.buffer.clear()
		entity.stagger(stagger, "plate_broken")
	_check_plates_phase()


## The first later phase whose enter_on_plates_broken the breaks so far reach is due (entered at the next step
## he is not staggered: _plates_phase_step).
func _check_plates_phase() -> void:
	if brain == null or not brain.has_boss_phases() or entity.plates == null:
		return
	for i in range(brain.phase_index + 1, brain.boss_phases.size()):
		var need := int((brain.boss_phases[i] as Dictionary).get("enter_on_plates_broken", 0))
		if need > 0 and entity.plates.broken_count() >= need:
			_plates_phase_due = i
			return


func _plates_phase_step() -> void:
	if _plates_phase_due < 0 or brain == null or not entity.is_alive():
		return
	if _plates_phase_due <= brain.phase_index:
		_plates_phase_due = -1
		return
	if controller.state == CombatController.State.STAGGERED:
		return
	var frac := float((brain.boss_phases[_plates_phase_due] as Dictionary).get("health_frac_below", 0.0))
	_plates_phase_due = -1
	brain.update_boss_phase(frac, Sim.tick)


## Breaks plate `id` as a blow would (tests, the capture tour, debug): the same events, stagger and phase rule.
func break_plate(id: String) -> bool:
	if entity.plates == null or not entity.plates.force_break(id):
		return false
	var r := HitResult.new()
	_on_plate_struck(r, {"plate": id, "broken": true})
	return true


## A new attempt: every plate whole again (P34's reset, then this).
func _p34_reset_extra() -> void:
	super()
	plate_breaks.clear()
	_plates_phase_due = -1
	if entity.plates != null:
		entity.plates.reset()
	_end_down(false)
	topples = 0
	_again.clear()
	_risen_at = -1000000


# --------------------------------------------------------------------------- A4: down on a knee

func is_down() -> bool:
	return down_since >= 0


## Seconds into the down in progress (-1 standing).
func down_elapsed_s() -> float:
	return float(Sim.tick - down_since) / float(Sim.TICK_RATE) if down_since >= 0 else -1.0


func down_total_s() -> float:
	return float(down_ticks) / float(Sim.TICK_RATE)


## Drops him on a knee for the topple plate `id`'s down (PlateRules.down_total_s): his attack cut short, a stagger
## of reason TOPPLE_REASON. False when he is already down or cannot be (dead, yielded, no topple block).
func knock_down(id: String) -> bool:
	if is_down() or topple.is_empty() or not entity.is_alive() or yielded or entity.plates == null:
		return false
	return _topple(id)


func _topple(id: String) -> bool:
	var p := entity.plates.plate(id)
	if p.is_empty():
		return false
	var total := PlateRules.down_total_s(p, topple)
	if controller.action != null:
		controller.call("_finish_action", true)
	controller.buffer.clear()
	entity.stagger(total, TOPPLE_REASON)
	if controller.state != CombatController.State.STAGGERED or controller.stagger_reason != TOPPLE_REASON:
		return false
	down_since = Sim.tick
	down_ticks = ActionDef.seconds_to_ticks(total)
	down_plate = id
	topples += 1
	_again[id] = 0.0
	entity.plates.down_mult = float(topple.get("damage_mult", 1.0))
	entity.plates.down_heavy_mult = float(topple.get("heavy_mult", 1.0))
	Events.titan_toppled.emit(Sim.tick, entity.entity_id, id, total)
	return true


## Each tick: how far down he is, his hurtboxes and anchors posed to it; the down ends with its stagger (or when
## something else ended that: death, a new attempt).
func _down_step() -> void:
	if down_since < 0:
		return
	var elapsed := Sim.tick - down_since
	if elapsed >= down_ticks or not entity.is_alive() or controller.state != CombatController.State.STAGGERED \
			or controller.stagger_reason != TOPPLE_REASON:
		_end_down(entity.is_alive())
		return
	down_weight = PlateRules.down_weight(float(elapsed) / float(Sim.TICK_RATE), down_total_s(), topple)
	_pose_kneel(down_weight)


func _end_down(rose: bool) -> void:
	if down_since < 0 and down_weight == 0.0:
		return
	down_since = -1
	down_ticks = 0
	down_plate = ""
	down_weight = 0.0
	_pose_kneel(0.0)
	if entity.plates != null:
		entity.plates.down_mult = 1.0
		entity.plates.down_heavy_mult = 1.0
	if rose:
		_risen_at = Sim.tick
		if brain != null:
			# (dazed: his next strike waits topple.recover_s after he stands)
			brain.strike_ready_tick = maxi(brain.strike_ready_tick,
				Sim.tick + ActionDef.seconds_to_ticks(float(topple.get("recover_s", 0.0))))
		Events.titan_rose.emit(Sim.tick, entity.entity_id)


## A blow that broke nothing: its health damage to a broken topple plate's region (or the record's again_regions)
## counts toward the next topple, no sooner than again_immune_s after he rose.
func _count_toward_topple(result: HitResult) -> void:
	if topple.is_empty() or is_down() or result == null or result.event == null or result.health_damage <= 0:
		return
	var region := PlateRules.region_of(result.event.region, entity.plates.default_region)
	var regions: Array = topple.get("again_regions", [])
	for id: String in entity.plates.break_order:
		var p := entity.plates.plate(id)
		if str(p.get("effect", "")) != PlateRules.EFFECT_TOPPLE or float(p.get("again_damage", 0.0)) <= 0.0:
			continue
		if region != str(p.region) and not regions.has(region):
			continue
		_again[id] = float(_again.get(id, 0.0)) + float(result.health_damage)
		var immune := ActionDef.seconds_to_ticks(float(topple.get("again_immune_s", 0.0)))
		if float(_again[id]) >= float(p.again_damage) and Sim.tick - _risen_at >= immune:
			_topple(id)
			return


## The damage counted toward the next topple of broken plate `id` (tests, the HUD).
func topple_progress(id: String) -> float:
	var p := entity.plates.plate(id) if entity.plates != null else {}
	if p.is_empty() or float(p.get("again_damage", 0.0)) <= 0.0:
		return 0.0
	return clampf(float(_again.get(id, 0.0)) / float(p.again_damage), 0.0, 1.0)


func _collect_kneel_nodes() -> void:
	_kneel_nodes.clear()
	for group: String in ["Hurtboxes", "Anchors"]:
		var parent := get_node_or_null(group)
		if parent == null:
			continue
		for c in parent.get_children():
			if c is Node3D and c.has_meta(KNEEL_META):
				_kneel_nodes.append([c, (c as Node3D).position, c.get_meta(KNEEL_META) as Vector3])


## His hurtboxes and lock anchors at `w` of the way from standing to the kneel (coarsely: positions only).
func _pose_kneel(w: float) -> void:
	for e: Array in _kneel_nodes:
		var n := e[0] as Node3D
		if is_instance_valid(n):
			n.position = (e[1] as Vector3).lerp(e[2] as Vector3, w)


## The point a giant `viewer_height` metres tall locks onto (CombatEntity.lock_anchor_position, A2): the nearest
## plate anchor it can reach - a broken one LOCK_WEAK_BONUS_M nearer - else INF (the usual rule: a knee).
## A pure function of the bodies' positions (the camera, the HUD and the targeting ask it every frame, so it keeps
## no state of its own).
func titan_lock_point(viewer_height: float) -> Vector3:
	var viewer := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if entity.plates == null or viewer_height <= 0.0 or viewer == null:
		return Vector3.INF
	var viewer_pos := viewer.global_position + Vector3.UP * viewer_height * 0.75
	var best := Vector3.INF
	var best_score := INF
	var reach := viewer_height * LOCK_REACH_SHARE + LOCK_REACH_SLACK_M
	var comfort := viewer_height * LOCK_COMFORT_SHARE
	var down := is_down()
	for p: Dictionary in entity.plates.plates:
		if not bool(p.breakable) or str(p.anchor) == "":
			continue
		if down and str(p.get("effect", "")) == PlateRules.EFFECT_TOPPLE:
			continue   # (A4: a knee on the ground is no target while he is down)
		var n := get_node_or_null(NodePath("Anchors/" + str(p.anchor))) as Node3D
		if n == null:
			continue
		var at := n.global_position
		if at.y - global_position.y > reach:
			continue
		var score := at.distance_to(viewer_pos) - (LOCK_WEAK_BONUS_M if entity.plates.is_broken(str(p.id)) else 0.0)
		if at.y - global_position.y > comfort:
			score += LOCK_HIGH_PENALTY_M
		score += float(p.get("lock_bias_m", 0.0))
		if score < best_score - 1e-4:
			best_score = score
			best = at
	return best


# --------------------------------------------------------------------------- the shock line

## The smash's shock (hit shape titan_shock): from the first active tick, every line.interval_s one cylinder
## pulse at the next point of the line (AttackRunner.line_pulse_points: line.start_m to line.length_m ahead of
## where he stood, his facing then), all sharing pulse id 1 - one hit per target for the whole shock. Each
## pulse emits area_pulse (the impact cue, the dust).
func _run_shock(a: ActionDef, tick: int) -> void:
	if controller.is_first_active_tick() or int(_shock.get("instance", -1)) != controller.instance_id:
		_shock = {"instance": controller.instance_id, "origin": global_position, "yaw": facing_yaw}
	var j := controller.elapsed - a.windup_ticks
	var interval := AttackRunner.line_pulse_interval(a)
	if j < 0 or j % interval != 0:
		return
	var points := AttackRunner.line_pulse_points(a, _shock.origin, float(_shock.yaw))
	var i := j / interval
	if i >= points.size():
		return
	var line: Dictionary = a.param("line", {})
	var radius := float(line.get("radius_m", 3.0))
	if i == 0:
		radius = float(line.get("impact_radius_m", radius))
	var height := float(line.get("height_m", 6.0))
	var point: Vector3 = points[i]
	var cands := HitQueryAdapter.cylinder_pulse(get_world_3d().direct_space_state, entity,
		point + Vector3.UP * (height * 0.5), radius, height, point + Vector3.UP * 0.8)
	var ctx := runner.context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, point, radius)


# --------------------------------------------------------------------------- the charge

## While a charge runs, the props in his way that a giant of his stage tramples break before his body meets
## them; then OgreBoss's motion (WORLD geometry still stops him: the record's on_wall_action).
func _custom_movement(dt: float) -> bool:
	if is_charging():
		_smash_props_ahead()
	return super(dt)


func _smash_props_ahead() -> void:
	var r := float(record.get("capsule_radius_m", 3.0))
	var h := float(record.get("height_m", 16.8))
	var fwd := Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var shape := CapsuleShape3D.new()
	shape.radius = r + 0.25
	shape.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = HitQueryAdapter.LAYER_BREAKABLE
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.transform = Transform3D(Basis(), global_position + fwd * CHARGE_SMASH_AHEAD_M + Vector3.UP * h * 0.5)
	var seen := {}
	var props: Array[BreakableProp] = []
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var n := hit.get("collider") as Node
		while n != null and not (n is BreakableProp):
			n = n.get_parent()
		if n == null or seen.has(n.get_instance_id()):
			continue
		seen[n.get_instance_id()] = true
		props.append(n as BreakableProp)
	props.sort_custom(func(x: BreakableProp, y: BreakableProp) -> bool: return x.world_id < y.world_id)
	for prop in props:
		if prop.trample(self):
			props_smashed += 1


# --------------------------------------------------------------------------- presentation and reads

## RivalGiantEnemy's keys plus the plates broken (TitanRig hides their meshes) and the reel (his wall stagger).
func get_rig_state() -> Dictionary:
	var s := super()
	s.erase("pose_override")   # (the titan's rig plays clips; the box poses are the rival giants')
	s["plates_broken"] = entity.plates.break_order if entity.plates != null else ([] as Array[String])
	var a := controller.action
	var m: Variant = a.param("motion") if a != null else null
	s["reeling"] = a != null and _wall_actions.has(a.id)
	if is_down():
		s["down"] = {"t": down_elapsed_s(), "total": down_total_s(), "rise_s": float(topple.get("rise_s", 0.0))}
	if typeof(m) == TYPE_DICTIONARY:
		s["charge_speed"] = float((m as Dictionary).get("speed_mps", 0.0))
	return s


## The actions his attacks name as their on_wall_action (the reel after a charge into stone).
func _collect_wall_actions() -> void:
	_wall_actions.clear()
	for id: String in controller.library:
		var other := controller.library[id] as ActionDef
		var m: Variant = other.param("motion") if other != null else null
		if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("on_wall_action", "")) != "":
			_wall_actions[str(m.on_wall_action)] = true
			var w := GameData.get_action(str(m.on_wall_action))
			if w != null and not controller.library.has(w.id):
				controller.add_action(w)


func get_debug_info() -> Dictionary:
	var d := super()
	if entity.plates != null:
		var parts := PackedStringArray()
		for p: Dictionary in entity.plates.plates:
			if bool(p.breakable):
				parts.append("%s %d%%" % [str(p.id), int(round(entity.plates.health_frac(str(p.id)) * 100.0))])
		d["plates"] = ", ".join(parts)
	if is_down():
		d["down"] = "%.1f / %.1f s (%s)" % [down_elapsed_s(), down_total_s(), down_plate]
	d["smashed"] = props_smashed
	return d
