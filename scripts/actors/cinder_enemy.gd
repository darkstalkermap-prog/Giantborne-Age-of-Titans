class_name CinderEnemy
extends TitanEnemy
## E2: the Cinder Titan (enemy.cinder, 41.0 m), who burns a road toward the kingdom. A signature titan (TitanEnemy: his
## plates, phases, the circling and the hug answers, the called fire as the Stormcaller's called lightning - hit shape
## titan_bolts -, a phase's arena hazard) whose fight is his fire (decision E2-2; his record's `cinder`):
##
## * **His burning ground** (`burn` on his actions): where his brand strikes the ground, where his blast and his embers
##   land, the ground burns - patches (`patches`: a point and a radius, each its own key) that stay burning for the
##   action's `burn.life_s` (from his last phase, `burn_lasts`, until he falls), at most cinder.burn_max of them (the
##   oldest go out). Water puts them out: nothing burns where water stands cinder.douse_m deep. A giant standing in a
##   patch takes cinder.burn_heat_per_s of heat a second; the arena shrinks as the fight goes on.
## * **Heat on the giant** (PlayerHeat): his blows' `heat`, his burning ground, his furnace's breath near him (a phase's
##   `heat_aura`), and his molten crust (cinder.crust_heat for each blow that lands on him while he is hot). Full, the
##   giant is ablaze: this titan strikes it with cinder.scorch_action every cinder.scorch_every_s until it has cooled.
## * **His molten crust** (PlateSet.heat_mult): while he is hot, every blow's damage and every plate's stone take
##   cinder.hot_mult - he shrugs off a giant's fists. **Water quenches him**: standing cinder.quench_depth_m deep, his
##   crust goes brittle for cinder.quench_s (blows land whole and his plates crack) and he reels (cinder.quench_stagger_s);
##   standing cinder.quench_down_depth_m deep (the dammed water) the steam takes him off his feet - down on a knee for
##   cinder.quench_down_s (his topple's kneel and rise round it). Not again for cinder.quench_cooldown_s after the crust
##   melts again. His second phase's roar melts it at once (his furnace wakes).
## Everything is decided from the sim's clock and his brain's RNG, so a seeded fight repeats.

const BURN_GROUP := "cinder_burn"
const QUENCH_REASON := "quenched"

var cinder: Dictionary = {}
## The burning ground: [{id, p (Vector3), r, until (tick, -1: until he falls), born}], in the order laid.
var patches: Array = []
## Quenched (his crust brittle) until this tick (-1: hot); the tick he may be quenched again.
var quenched_until := -1
var _quench_ready := -1
## Tallies this attempt (tests, the duel report).
var patches_laid := 0
var patches_doused := 0
var quenches := 0
var quench_downs := 0
var remelts := 0
var scorches := 0
var crust_burns := 0
var _next_id := 1
var _next_scorch := {}


func _ready() -> void:
	super()
	add_to_group(BURN_GROUP)
	cinder = record.get("cinder", {}) if typeof(record.get("cinder")) == TYPE_DICTIONARY else {}
	if entity.plates != null:
		entity.plates.heat_mult = hot_mult()
	if not Events.hit_resolved.is_connected(_on_any_hit):
		Events.hit_resolved.connect(_on_any_hit)
	controller.phase_entered.connect(_on_cinder_phase)


func _exit_tree() -> void:
	super()
	if Events.hit_resolved.is_connected(_on_any_hit):
		Events.hit_resolved.disconnect(_on_any_hit)


func hot_mult() -> float:
	return float(cinder.get("hot_mult", 0.45))


func is_quenched() -> bool:
	return quenched_until >= 0 and Sim.tick < quenched_until


## Seconds of brittle crust left (0 hot).
func quench_left_s() -> float:
	return maxf(0.0, float(quenched_until - Sim.tick) / float(Sim.TICK_RATE)) if is_quenched() else 0.0


func sim_step(tick: int, dt: float) -> void:
	_e2_step(tick, dt)
	super(tick, dt)


func _e2_step(tick: int, dt: float) -> void:
	_expire_patches(tick)
	if not entity.is_alive():
		return
	# the crust melts again when the quench is over
	if quenched_until >= 0 and tick >= quenched_until:
		_remelt(tick)
	if not ai_enabled or yielded or stood_down or dormant:
		return
	_quench_check(tick)
	_heat_giants(tick, dt)


# --------------------------------------------------------------------------- the burning ground

## Lays a patch of burning ground at `p` (radius `r` m, burning `life_s`; from his last phase until he falls). False on
## water (cinder.douse_m deep or more) or once he is dead.
func lay_burn(p: Vector3, r: float, life_s: float, tick: int = -1) -> bool:
	if not entity.is_alive():
		return false
	if tick < 0:
		tick = Sim.tick
	if is_inside_tree() and StormWater.depth_at(get_tree(), p) >= float(cinder.get("douse_m", 0.5)):
		patches_doused += 1
		return false
	var lasts := bool(_phase_value("burn_lasts", false))
	var until := -1 if lasts or life_s <= 0.0 else tick + ActionDef.seconds_to_ticks(life_s)
	var id := _next_id
	_next_id += 1
	patches.append({"id": id, "p": p, "r": r, "until": until, "born": tick})
	patches_laid += 1
	Events.burn_laid.emit(tick, entity.entity_id, id, p, r)
	var cap := int(cinder.get("burn_max", 40))
	while patches.size() > cap:
		var old: Dictionary = patches.pop_front()
		Events.burn_out.emit(tick, entity.entity_id, int(old.id), false)
	return true


func _expire_patches(tick: int) -> void:
	var i := 0
	while i < patches.size():
		var u := int((patches[i] as Dictionary).until)
		if u >= 0 and tick >= u:
			Events.burn_out.emit(tick, entity.entity_id, int((patches[i] as Dictionary).id), false)
			patches.remove_at(i)
		else:
			i += 1


## Every patch goes out (his fall, a new attempt).
func clear_burn() -> void:
	if patches.is_empty():
		return
	patches.clear()
	Events.burn_cleared.emit(Sim.tick, entity.entity_id)


## Whether `p` stands in his burning ground (within a patch's radius, `slack` m more).
func burning_at(p: Vector3, slack := 0.0) -> bool:
	for pt: Dictionary in patches:
		var c: Vector3 = pt.p
		if Vector2(p.x - c.x, p.z - c.z).length() <= float(pt.r) + slack:
			return true
	return false


## Whether any Cinder Titan's burning ground covers `p` (the duel bot, the HUD).
static func burn_at(tree: SceneTree, p: Vector3, slack := 0.0) -> bool:
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(BURN_GROUP):
		var c := n as CinderEnemy
		if c != null and c.burning_at(p, slack):
			return true
	return false


## The burn an action of his lays as it strikes (its `burn`): "line" along his facing (start_m, step_m, count), "arc"
## round his front (at_m out, arc_deg wide, count), "feet" round himself (count at at_m). `origin`/`fwd` his own.
func _lay_action_burn(a: ActionDef, tick: int) -> void:
	var b: Dictionary = a.param("burn", {})
	if b.is_empty() or str(b.get("pattern", "")) == "strike":
		return
	var r := float(b.get("radius_m", 6.0))
	var life := float(b.get("life_s", 40.0))
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var count := int(b.get("count", 3))
	match str(b.get("pattern", "line")):
		"arc":
			var at := float(b.get("at_m", 20.0))
			var arc := deg_to_rad(float(b.get("arc_deg", 120.0)))
			for i in count:
				var ang := -arc * 0.5 + arc * (float(i) + 0.5) / float(count)
				var d := fwd.rotated(Vector3.UP, ang)
				lay_burn(_on_ground(global_position + d * at), r, life, tick)
		"feet":
			var at := float(b.get("at_m", 10.0))
			for i in count:
				var d := fwd.rotated(Vector3.UP, TAU * float(i) / float(count))
				lay_burn(_on_ground(global_position + d * at), r, life, tick)
		_:
			var start := float(b.get("start_m", 18.0))
			var step := float(b.get("step_m", 9.0))
			for i in count:
				lay_burn(_on_ground(global_position + fwd * (start + step * i)), r, life, tick)


func _on_ground(p: Vector3) -> Vector3:
	p.y = _ground_y(p, global_position.y)
	return p


## A hazard of his struck (an ember of his called fire, his last phase's falling embers): its `burn` ("strike": a patch
## where it lands).
func _on_hazard_struck(a: ActionDef, point: Vector3, tick: int) -> void:
	super(a, point, tick)
	if a == null:
		return
	var b: Dictionary = a.param("burn", {})
	if b.is_empty():
		return
	lay_burn(point, float(b.get("radius_m", 6.0)), float(b.get("life_s", 40.0)), tick)


func _on_cinder_phase(a: ActionDef, _instance_id: int, phase: int) -> void:
	if a == null or phase != ActionDef.Phase.ACTIVE:
		return
	if a.param("burn") != null:
		_lay_action_burn(a, Sim.tick)
	# his second phase's roar: the furnace wakes - the crust melts at once
	if bool(a.param("remelt", false)) and is_quenched():
		_remelt(Sim.tick)


# --------------------------------------------------------------------------- heat on the giant

func _heat_giants(tick: int, dt: float) -> void:
	var aura: Dictionary = _phase_value("heat_aura", {})
	for n in get_tree().get_nodes_in_group("player"):
		var g := n as GiantPlayer
		if g == null or g.heat == null or g.entity == null or not g.entity.is_alive():
			continue
		var pos := g.global_position
		if burning_at(pos, float(cinder.get("burn_slack_m", 1.0))):
			g.heat.add_heat(float(cinder.get("burn_heat_per_s", 16.0)) * dt, "burn")
		if not aura.is_empty() and not is_down():
			var d := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
			if d <= float(aura.get("radius_m", 26.0)):
				g.heat.add_heat(float(aura.get("heat_per_s", 4.0)) * dt, "aura")
		if g.heat.is_ablaze():
			var due := int(_next_scorch.get(g.entity.entity_id, -1))
			if due < 0:
				due = tick + ActionDef.seconds_to_ticks(float(cinder.get("scorch_first_s", 0.5)))
				_next_scorch[g.entity.entity_id] = due
			if tick >= due:
				_scorch(g.entity, tick)
				_next_scorch[g.entity.entity_id] = tick + ActionDef.seconds_to_ticks(float(cinder.get("scorch_every_s", 1.0)))
		else:
			_next_scorch.erase(g.entity.entity_id)


## The fire on an ablaze giant: his scorch action's hit (fire; unblockable; his own, so a death by it is his kill).
func _scorch(target: CombatEntity, tick: int) -> void:
	var a := GameData.get_action(str(cinder.get("scorch_action", "")))
	if a == null or target.actor == null:
		return
	var ctx := runner.context()
	ctx.instance_id = Sim.new_instance_id()
	ctx.registry = HitRegistry.new()
	ctx.weapon = {}
	ctx.attacker_position = (target.actor as Node3D).global_position
	ctx.area_effect = true
	var cand := {"entity": target, "hurtbox": null, "point": ctx.attacker_position, "substep": 0, "distance": 0.0}
	Sim.queue_hit(HitFactory.build(ctx, a, cand, 1, tick))
	scorches += 1


## A blow of his with `heat` that struck a giant adds it (half blocked); a blow of a giant that landed on him while he
## is hot burns it (cinder.crust_heat).
func _on_any_hit(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or not is_instance_valid(self) or entity == null:
		return
	if r.event.attacker_id == entity.entity_id:
		var a := GameData.get_action(r.event.action_id)
		var amount := float(a.param("heat", 0.0)) if a != null else 0.0
		if amount <= 0.0:
			return
		var g := _giant_of(r.event.target_id)
		if g != null and (r.outcome == HitResult.Outcome.HIT or r.outcome == HitResult.Outcome.BLOCKED):
			g.heat.add_heat(amount * (0.5 if r.outcome == HitResult.Outcome.BLOCKED else 1.0), "hit")
	elif r.event.target_id == entity.entity_id and r.outcome == HitResult.Outcome.HIT and not is_quenched() \
			and entity.is_alive():
		var g := _giant_of(r.event.attacker_id)
		if g != null:
			g.heat.add_heat(float(cinder.get("crust_heat", 3.0)), "crust")
			crust_burns += 1


func _giant_of(entity_id: String) -> GiantPlayer:
	var e := Sim.get_entity(entity_id)
	if e == null or not is_instance_valid(e.actor):
		return null
	var g := e.actor as GiantPlayer
	return g if g != null and g.heat != null else null


# --------------------------------------------------------------------------- the quench

func _quench_check(tick: int) -> void:
	if is_quenched() or tick < _quench_ready or not is_inside_tree():
		return
	var depth := StormWater.depth_at(get_tree(), global_position)
	if depth < float(cinder.get("quench_depth_m", 2.0)):
		return
	quench(depth >= float(cinder.get("quench_down_depth_m", 5.0)))


## Quenches him (water deep at his feet): his crust brittle for cinder.quench_s, a reel - or, `down`, a down on a knee.
## False when he is already quenched, dead or yielded.
func quench(down := false) -> bool:
	if is_quenched() or not entity.is_alive() or yielded:
		return false
	quenched_until = Sim.tick + ActionDef.seconds_to_ticks(float(cinder.get("quench_s", 20.0)))
	quenches += 1
	if entity.plates != null:
		entity.plates.heat_mult = 1.0
	if down and not topple.is_empty() and not is_down():
		if _topple("quench", {"id": "quench", "down_s": float(cinder.get("quench_down_s", 5.0))}):
			quench_downs += 1
	elif not is_down():
		var s := float(cinder.get("quench_stagger_s", 2.5))
		if s > 0.0:
			if controller.action != null:
				controller.call("_finish_action", true)
			controller.buffer.clear()
			entity.stagger(s, QUENCH_REASON)
	Events.titan_quenched.emit(Sim.tick, entity.entity_id, global_position, down)
	return true


func _remelt(tick: int) -> void:
	quenched_until = -1
	_quench_ready = tick + ActionDef.seconds_to_ticks(float(cinder.get("quench_cooldown_s", 10.0)))
	if entity.plates != null:
		entity.plates.heat_mult = hot_mult()
	remelts += 1
	Events.titan_remelted.emit(tick, entity.entity_id)


# --------------------------------------------------------------------------- the attempt, his fall

func _p34_reset_extra() -> void:
	super()
	clear_burn()
	quenched_until = -1
	_quench_ready = -1
	if entity.plates != null:
		entity.plates.heat_mult = hot_mult()
	patches_laid = 0
	patches_doused = 0
	quenches = 0
	quench_downs = 0
	remelts = 0
	scorches = 0
	crust_burns = 0
	_next_scorch.clear()


func on_entity_died(killer_id: String) -> void:
	super(killer_id)
	clear_burn()


## A value of the current boss phase's record (`fallback` without one).
func _phase_value(key: String, fallback: Variant) -> Variant:
	if brain == null or not brain.has_boss_phases():
		return fallback
	var v: Variant = brain.phase_record().get(key, fallback)
	return v if typeof(v) == typeof(fallback) else fallback


func get_rig_state() -> Dictionary:
	var s := super()
	s["hot"] = not is_quenched()
	s["quench_left"] = quench_left_s()
	s["quench_s"] = float(cinder.get("quench_s", 20.0))
	s["burning"] = patches.size()
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	d["crust"] = "brittle %.1f s" % quench_left_s() if is_quenched() else "molten (x%.2f)" % hot_mult()
	d["burn"] = "%d patches (%d laid, %d doused)" % [patches.size(), patches_laid, patches_doused]
	return d
