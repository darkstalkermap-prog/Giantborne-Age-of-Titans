class_name StressScenario
extends Node
## The stress arena's runtime and its bot (P14; plan §3.16 items 1-2, §5.3; spec §16: 12 active
## combatants, 20 breakables, at most 40 debris). One node of this script sits in
## scenes/test/stress_arena.tscn (tools/builders/stress.gd builds it); group "stress_scenario".
##
## Always (also when a person plays the arena: --level=res://scenes/test/stress_arena.tscn):
##   * the 12 combatant slots (Spawns/Combatants/<slot>: meta "scene", "definition") spawn at
##     load under LevelRoot/Spawned and each one respawns at its spawn point respawn_delay_s (5 s)
##     after it died or routed (a routed unit is out of the fight), so 12 stay active. Spawned ids
##     are "stress.<slot>.<n>"; the old body is freed when its replacement spawns.
##   * the 20 breakables (Breakables/*, meta "stop" and "order") are tracked: every destruction is
##     counted per original world id. reset_breakables() replaces the broken ones with fresh
##     copies (world id "<original>.r<n>", so WorldState sees a new, intact prop).
## The bot (start_bot(); the Autopilot calls it for --scenario=stress, the slow smoke test too):
##   * gives the player the hidden status.debug_invulnerable (damage taken x0; hits, poise and
##     knockback still land) for the whole run and grows it to `stage` (default 2) with the debug
##     growth path;
##   * walks the route's stops (Route/1..8) in order and, at each stop, breaks its cluster in lap
##     order: Heavy Footfall when it is ready and catches two or more of the cluster's breakables
##     (or a breakable and two enemies), then a heavy on the current breakable, or a light when
##     a light finishes it (the smallest light damage seen on a breakable) or stamina is short;
##     a breakable it cannot break within TARGET_TIMEOUT_S is skipped for that lap;
##   * fights what engages it on the way: a light at an enemy in its path within reach, Footfall
##     when three or more enemies stand within its radius, and when it is stuck behind an enemy
##     it swings at it (otherwise it sidesteps);
##   * when every breakable of the lap is broken (or skipped) it calls reset_breakables() and
##     starts the next lap, so debris keeps flowing for the whole 300 s run (the pool saturates at
##     40 pieces).
## result() reports the run (laps, breaks, respawns, active combatants, debris, deaths, the bot's
## inputs) with check_failures(): the scenario's own checks (the player never died, debris at
## most 40, at least 10 active combatants on average, and from 60 s every breakable broken at
## least once). The Autopilot exits with code 2 when one fails.

const GROUP := "stress_scenario"
const RESPAWN_DELAY_S := 5.0
const STATUS_INVULNERABLE := "status.debug_invulnerable"
## The invulnerability is renewed while less than this is left of it.
const INVULNERABLE_RENEW_S := 60.0
const DEFAULT_STAGE := 2
const COMBATANTS := 12
const BREAKABLES := 20
const MAX_DEBRIS := 40
const MIN_ACTIVE_AVG := 10.0
## From this run length on, every breakable must have been broken at least once.
const FULL_LAP_CHECK_S := 60.0
## The bot stands this close to a stop before it attacks the stop's breakables.
const STOP_RADIUS_M := 1.0
const TARGET_TIMEOUT_S := 15.0
## Stamina the bot wants before it chooses each attack (the actions' costs).
const HEAVY_STAMINA := 22.0
const LIGHT_STAMINA := 8.0
const FOOTFALL_STAMINA := 20.0
const FOOTFALL_SLOT := 1
## Growth refused (busy, airborne) is retried this often.
const GROW_RETRY_TICKS := 30
## At most one swing at an enemy in its path per this many ticks.
const SWING_GAP_TICKS := 60
## No progress over this many ticks while walking counts as stuck.
const STUCK_TICKS := 30
const STUCK_MOVE_M := 0.3
const STRAFE_TICKS := 36

@export var respawn_delay_s := RESPAWN_DELAY_S

## The bot is running.
var bot_active := false
var player: GiantPlayer
var bot_stage := DEFAULT_STAGE
var bot_ticks := 0
## Completed laps (every breakable of the lap broken or skipped), and the bot's second at each.
var laps := 0
var lap_seconds: Array[float] = []
var respawns := 0
var breakable_breaks := 0
var skipped := 0
var player_deaths := 0
var max_debris := 0
var max_active := 0
var min_active := 1000000
## Bot inputs (heavy, light, footfall, enemy_swings, strafes).
var inputs := {"heavy": 0, "light": 0, "footfall": 0, "enemy_swings": 0, "strafes": 0}

var level: LevelRoot
var _slots: Array = []        # Slot
var _props: Array = []        # Prop, in lap order
var _stops: Array[Vector3] = []
var _scenes: Dictionary = {}  # path -> PackedScene
var _broken_once: Dictionary = {}   # original world id -> times broken
var _active_sum := 0.0
var _active_samples := 0
var _was_dead := false
var _target: Prop = null
var _target_since := 0
var _last_pos := Vector3.INF
var _still_ticks := 0
var _strafe_left := 0
var _strafe_sign := 1.0
var _light_damage := INF      # smallest light damage seen on a breakable (not a killing blow)
var _last_swing_tick := -1000000
var _last_grow_tick := -1000000
var _rng := RandomNumberGenerator.new()


class Slot extends RefCounted:
	var name := ""
	var scene := ""
	var definition := ""
	var marker: Node3D
	var node: Node3D = null
	var entity_id := ""
	var serial := 0
	var down_tick := -1      ## the tick it died or routed; -1 while it fights or before it spawns


class Prop extends RefCounted:
	var base_id := ""        ## the original world id (stress.fence_01)
	var scene := ""
	var xform := Transform3D.IDENTITY
	var stop := 0
	var order := 0
	var node: BreakableProp = null
	var generation := 1
	var skipped_lap := -1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	level = _find_level()
	_rng.seed = 1414
	_collect()
	Events.entity_died.connect(_on_entity_died)
	Events.enemy_routed.connect(_on_enemy_routed)
	Events.object_destroyed.connect(_on_object_destroyed)
	Events.hit_resolved.connect(_on_hit_resolved)
	_spawn_all.call_deferred()


# --------------------------------------------------------------------------- the arena

func _find_level() -> LevelRoot:
	var n := get_parent()
	while n != null:
		if n is LevelRoot:
			return n as LevelRoot
		n = n.get_parent()
	return null


func _arena() -> Node:
	return level if level != null else get_parent()


func _collect() -> void:
	var root := _arena()
	var route := root.get_node_or_null("Route")
	if route != null:
		for m in route.get_children():
			if m is Node3D:
				_stops.append((m as Node3D).global_position if m.is_inside_tree() else (m as Node3D).position)
	var spawns := root.get_node_or_null("Spawns/Combatants")
	if spawns != null:
		for m in spawns.get_children():
			if not (m is Node3D) or not m.has_meta("scene"):
				continue
			var s := Slot.new()
			s.name = String(m.name).to_snake_case()
			s.scene = str(m.get_meta("scene"))
			s.definition = str(m.get_meta("definition", ""))
			s.marker = m
			_slots.append(s)
	var props := root.get_node_or_null("Breakables")
	if props != null:
		for n in props.get_children():
			var bp := n as BreakableProp
			if bp == null:
				continue
			var p := Prop.new()
			p.base_id = bp.world_id
			p.scene = bp.scene_file_path
			p.xform = bp.transform
			p.stop = int(bp.get_meta("stop", 0))
			p.order = int(bp.get_meta("order", _props.size()))
			p.node = bp
			_props.append(p)
	_props.sort_custom(func(a: Prop, b: Prop) -> bool: return a.order < b.order)


## The combatant slots' current actors (alive or not), in slot order.
func combatants() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for s: Slot in _slots:
		if s.node != null and is_instance_valid(s.node):
			out.append(s.node)
	return out


## Living, non-routed combatants (the spec's "active").
func active_count() -> int:
	var n := 0
	for s: Slot in _slots:
		if s.down_tick < 0 and _alive(s.node):
			n += 1
	return n


func slot_count() -> int:
	return _slots.size()


## The breakables in lap order (their current instances; broken ones until reset).
func breakables() -> Array[BreakableProp]:
	var out: Array[BreakableProp] = []
	for p: Prop in _props:
		if p.node != null and is_instance_valid(p.node):
			out.append(p.node)
	return out


func breakable_count() -> int:
	return _props.size()


## How many of the original breakables were broken at least once.
func broken_once_count() -> int:
	return _broken_once.size()


func stops() -> Array[Vector3]:
	return _stops.duplicate()


func _spawn_all() -> void:
	for s: Slot in _slots:
		if s.node == null:
			_spawn(s)


func _spawn(s: Slot) -> void:
	if level == null and get_parent() == null:
		return
	var packed := _scene(s.scene)
	if packed == null:
		push_warning("StressScenario: slot %s has no loadable scene %s" % [s.name, s.scene])
		return
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	s.serial += 1
	s.entity_id = "stress.%s.%d" % [s.name, s.serial]
	var ce := node.get_node_or_null("CombatEntity")
	if ce != null and "definition_id" in ce and s.definition != "":
		ce.set("definition_id", s.definition)
	_set_if(node, "entity_id", s.entity_id)
	_set_if(node, "ai_enabled", true)
	_set_if(node, "persist_death", false)
	var at := s.marker.global_transform if s.marker.is_inside_tree() else s.marker.transform
	at.origin += Vector3.UP * 0.05
	var parent: Node3D = level.spawn_parent() if level != null else get_parent() as Node3D
	node.transform = parent.global_transform.affine_inverse() * at if parent.is_inside_tree() else at
	_set_if(node, "home_position", at.origin)
	node.name = s.entity_id.validate_node_name()
	parent.add_child(node)
	s.node = node
	s.down_tick = -1


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	return _scenes[path]


func _on_entity_died(tick: int, entity_id: String, _killer_id: String) -> void:
	for s: Slot in _slots:
		if s.entity_id == entity_id and s.down_tick < 0:
			s.down_tick = tick
			return


func _on_enemy_routed(tick: int, entity_id: String, _encounter_id: String) -> void:
	_on_entity_died(tick, entity_id, "")


func _on_object_destroyed(_tick: int, world_id: String, _by: String) -> void:
	for p: Prop in _props:
		if p.node != null and is_instance_valid(p.node) and p.node.world_id == world_id:
			breakable_breaks += 1
			_broken_once[p.base_id] = int(_broken_once.get(p.base_id, 0)) + 1
			return


func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or player == null or not is_instance_valid(player):
		return
	if r.event.attacker_id != player.entity.entity_id or r.health_damage <= 0 or r.killed:
		return
	var a := GameData.get_action(r.event.action_id)
	if a == null or a.kind != "light":
		return
	var target := Sim.get_entity(r.event.target_id)
	if target != null and target.actor is BreakableProp:
		_light_damage = minf(_light_damage, float(r.health_damage))


## Replaces every broken breakable with a fresh copy at its place (world id "<original>.r<n>").
## One with a living actor standing on its spot waits for a later reset. Returns how many came back.
func reset_breakables() -> int:
	var parent := _arena().get_node_or_null("Breakables")
	if parent == null:
		return 0
	var n := 0
	for p: Prop in _props:
		if p.node != null and is_instance_valid(p.node) and not p.node.destroyed:
			continue
		if _occupied(p.xform.origin):
			continue
		var packed := _scene(p.scene)
		if packed == null:
			continue
		var fresh := packed.instantiate() as BreakableProp
		if fresh == null:
			continue
		var old := p.node
		p.generation += 1
		fresh.world_id = "%s.r%d" % [p.base_id, p.generation]
		fresh.transform = p.xform
		fresh.set_meta("stop", p.stop)
		fresh.set_meta("order", p.order)
		if old != null and is_instance_valid(old):
			fresh.loot_table = old.loot_table
			parent.remove_child(old)
			old.queue_free()
		fresh.name = fresh.world_id.validate_node_name()
		parent.add_child(fresh)
		p.node = fresh
		p.skipped_lap = -1
		n += 1
	return n


func _occupied(pos: Vector3) -> bool:
	for s: Slot in _slots:
		if _alive(s.node) and _flat(s.node.global_position, pos) < 1.5:
			return true
	return player != null and is_instance_valid(player) and _flat(player.global_position, pos) < 1.0


func _physics_process(_delta: float) -> void:
	var tick := Sim.tick
	var due := ActionDef.seconds_to_ticks(respawn_delay_s)
	for s: Slot in _slots:
		if s.node != null and not is_instance_valid(s.node):
			s.node = null
			if s.down_tick < 0:
				s.down_tick = tick
		elif s.node != null and s.down_tick < 0 and not _alive(s.node):
			s.down_tick = tick   # died without the event reaching us (e.g. freed mid-death)
		if s.down_tick >= 0 and tick - s.down_tick >= due:
			_free_node(s.node)
			s.node = null
			_spawn(s)
			respawns += 1
	if not bot_active:
		return
	bot_ticks += 1
	var active := active_count()
	_active_sum += float(active)
	_active_samples += 1
	max_active = maxi(max_active, active)
	min_active = mini(min_active, active)
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool
	if pool != null:
		max_debris = maxi(max_debris, pool.active_count())
	_bot_step()


# --------------------------------------------------------------------------- the bot

## Starts the bot on `p`: invulnerable for the run, grown to `stage` (debug growth), driving the
## player through its InputRouter injection (the same path as a keyboard).
func start_bot(p: GiantPlayer, stage := DEFAULT_STAGE) -> void:
	player = p
	bot_stage = stage
	bot_active = true
	p.router.use_injection = true
	_keep_invulnerable()
	_grow_to_stage()


## Grows the giant to bot_stage with the debug growth path once it stands on the floor, idle (it
## spawns a little above the floor); a refusal (clearance) is retried every GROW_RETRY_TICKS.
func _grow_to_stage() -> void:
	if player.growth == null or player.current_growth_stage() == bot_stage:
		return
	# Growth refuses an airborne or busy giant (it spawns a little above the floor).
	if not player.is_on_floor() or player.controller.state != CombatController.State.LOCOMOTION:
		return
	if bot_ticks - _last_grow_tick < GROW_RETRY_TICKS:
		return
	_last_grow_tick = bot_ticks
	player.growth.debug_set_stage(bot_stage)


func stop_bot() -> void:
	bot_active = false
	if player != null and is_instance_valid(player):
		player.router.set_injected_move(Vector2.ZERO)


func _keep_invulnerable() -> void:
	var e := player.entity
	if not e.is_alive():
		return
	var statuses := e.combatant.statuses
	if not statuses.has(STATUS_INVULNERABLE) \
			or statuses.remaining_s(STATUS_INVULNERABLE, Sim.tick) < INVULNERABLE_RENEW_S:
		e.apply_status(STATUS_INVULNERABLE, NAN, -1.0, "stress")


func _bot_step() -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var r := player.router
	var c := player.controller
	if c.state == CombatController.State.DEAD:
		if not _was_dead:
			player_deaths += 1
		_was_dead = true
		r.set_injected_move(Vector2.ZERO)
		return
	_was_dead = false
	_keep_invulnerable()
	if player.current_growth_stage() != bot_stage:
		r.set_injected_move(Vector2.ZERO)
		_grow_to_stage()
		return
	var target := _current_target()
	if target == null:
		laps += 1
		lap_seconds.append(snappedf(float(bot_ticks) / float(Sim.TICK_RATE), 0.01))
		reset_breakables()
		target = _current_target()
		if target == null:
			r.set_injected_move(Vector2.ZERO)
			return
	if target != _target:
		_target = target
		_target_since = bot_ticks
	elif bot_ticks - _target_since > ActionDef.seconds_to_ticks(TARGET_TIMEOUT_S):
		target.skipped_lap = laps
		skipped += 1
		_target = null
		return
	var stop := _stops[target.stop] if target.stop < _stops.size() else target.xform.origin
	var pos := player.global_position
	if _strafe_left > 0:
		_strafe_left -= 1
		r.set_injected_move(Vector2(_strafe_sign, 0.25))
		return
	if _flat(pos, stop) > STOP_RADIUS_M:
		_walk_to(stop)
		return
	_last_pos = Vector3.INF
	_still_ticks = 0
	_attack_at_stop(target)


## The first breakable of the lap (in lap order) that is still standing and not skipped.
func _current_target() -> Prop:
	for p: Prop in _props:
		if p.node == null or not is_instance_valid(p.node) or p.node.destroyed:
			continue
		if p.skipped_lap == laps:
			continue
		return p
	return null


func _walk_to(point: Vector3) -> void:
	var r := player.router
	var pos := player.global_position
	_face(point)
	r.set_injected_move(Vector2(0, 1))
	r.set_injected_hold(&"sprint", false)
	# Stuck: hardly moved for STUCK_TICKS while walking.
	if _last_pos == Vector3.INF or _flat(pos, _last_pos) > STUCK_MOVE_M:
		_last_pos = pos
		_still_ticks = 0
	else:
		_still_ticks += 1
	var blocker := _enemy_in_front(_reach(), 50.0)
	if blocker != null and _can_act() and player.entity.combatant.pools.stamina >= 40.0 \
			and Sim.tick - _last_swing_tick >= SWING_GAP_TICKS:
		# Fight what engages it: a swing at an enemy in its path.
		_last_swing_tick = Sim.tick
		_face(blocker.global_position)
		r.inject_edge(&"light")
		inputs.light += 1
		inputs.enemy_swings += 1
	elif _can_act() and _footfall_ready() and _enemies_within(_footfall_radius() - 0.3) >= 3 \
			and player.entity.combatant.pools.stamina >= FOOTFALL_STAMINA:
		_footfall()
	if _still_ticks >= STUCK_TICKS:
		_still_ticks = 0
		_last_pos = Vector3.INF
		if blocker == null:
			_strafe_left = STRAFE_TICKS
			_strafe_sign = -_strafe_sign if _rng.randf() < 0.5 else _strafe_sign
			inputs.strafes += 1


func _attack_at_stop(target: Prop) -> void:
	var r := player.router
	r.set_injected_move(Vector2.ZERO)
	r.set_injected_hold(&"sprint", false)
	var aim := _aim_point(target.node)
	var dist := _flat(player.global_position, aim)
	if dist > _reach() - 0.3:
		_face(aim)
		r.set_injected_move(Vector2(0, 0.6))   # a step closer
		return
	# The camera looks at the aim point; an attack's windup turns the giant to it.
	_face(aim)
	if not _can_act():
		return
	var stamina := player.entity.combatant.pools.stamina
	var near := _breakables_within(_footfall_radius() - 0.2)
	if _footfall_ready() and stamina >= FOOTFALL_STAMINA \
			and (near >= 2 or (near >= 1 and _enemies_within(_footfall_radius()) >= 2)):
		_footfall()
		return
	var hp := target.node.health()
	var light_finishes := _light_damage < INF and hp <= _light_damage * 0.95
	if stamina >= HEAVY_STAMINA and not light_finishes:
		r.inject_edge(&"heavy")
		inputs.heavy += 1
	elif stamina >= LIGHT_STAMINA:
		r.inject_edge(&"light")
		inputs.light += 1


func _footfall() -> void:
	player.router.inject_edge(StringName("slot_%d" % FOOTFALL_SLOT))
	inputs.footfall += 1


func _footfall_ready() -> bool:
	return player.controller.preview_reason(&"slot", {"slot": FOOTFALL_SLOT}) == ""


## The controller would start a new action now (also the light/heavy cancel windows).
func _can_act() -> bool:
	return player.controller.state == CombatController.State.LOCOMOTION


func _footfall_radius() -> float:
	var a := GameData.get_action("ability.heavy_footfall")
	if a == null:
		return 3.0
	var by_stage: Variant = a.param("radius_by_stage_m")
	if typeof(by_stage) == TYPE_ARRAY and not (by_stage as Array).is_empty():
		return float(by_stage[clampi(player.current_growth_stage() - 1, 0, (by_stage as Array).size() - 1)])
	return a.radius_m


func _reach() -> float:
	return float(player.profile.get("melee_reach_m", 3.5))


## The point of a breakable to swing at: the nearest point of its length (fences and gates lie
## along their local X) to the player, at the player's height.
func _aim_point(bp: BreakableProp) -> Vector3:
	var half := 0.0
	match str(bp.record.get("id", "")):
		"prop.fence_wood":
			half = 3.6
		"prop.gate_practice":
			half = 4.5
	var axis := bp.global_transform.basis.x.normalized()
	var to := player.global_position - bp.global_position
	var along := clampf(to.dot(axis), -half, half)
	var p := bp.global_position + axis * along
	p.y = player.global_position.y
	return p


func _breakables_within(radius: float) -> int:
	var n := 0
	var pos := player.global_position
	for p: Prop in _props:
		if p.node == null or not is_instance_valid(p.node) or p.node.destroyed:
			continue
		if _flat(pos, _aim_point(p.node)) <= radius:
			n += 1
	return n


func _enemies_within(radius: float) -> int:
	var n := 0
	var pos := player.global_position
	for s: Slot in _slots:
		if s.down_tick < 0 and _alive(s.node) and _flat(pos, s.node.global_position) <= radius:
			n += 1
	return n


## The nearest living combatant within `range_m` and `half_angle_deg` of the player's facing.
func _enemy_in_front(range_m: float, half_angle_deg: float) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var pos := player.global_position
	var fwd := Vector3(-sin(player.facing_yaw), 0, -cos(player.facing_yaw))
	for s: Slot in _slots:
		if s.down_tick >= 0 or not _alive(s.node):
			continue
		var to := s.node.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d > range_m or d < 0.01:
			continue
		if rad_to_deg(fwd.angle_to(to / d)) > half_angle_deg:
			continue
		if d < best_d:
			best = s.node
			best_d = d
	return best


func _face(point: Vector3) -> void:
	var to := point - player.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		player.camera_rig.yaw = TargetingRules.yaw_of(to)


# --------------------------------------------------------------------------- the report

func active_average() -> float:
	return _active_sum / float(_active_samples) if _active_samples > 0 else 0.0


## The run's report (Autopilot merges it into AUTOPILOT_RESULT under "stress").
func result(duration_s: float = -1.0) -> Dictionary:
	var seconds := float(bot_ticks) / float(Sim.TICK_RATE)
	return {
		"stage": bot_stage,
		"simulated_s": snappedf(seconds, 0.01),
		"laps": laps,
		"lap_end_s": lap_seconds.duplicate(),
		"breakables": _props.size(),
		"breakables_broken_once": _broken_once.size(),
		"breakable_breaks": breakable_breaks,
		"skipped": skipped,
		"combatants": _slots.size(),
		"respawns": respawns,
		"active_avg": snappedf(active_average(), 0.01),
		"active_min": min_active if _active_samples > 0 else 0,
		"active_max": max_active,
		"max_debris": max_debris,
		"player_deaths": player_deaths,
		"inputs": inputs.duplicate(),
		"check_failures": check_failures(duration_s if duration_s >= 0.0 else seconds),
	}


## The scenario's own checks for a run of `duration_s` ([] = all passed).
func check_failures(duration_s: float) -> PackedStringArray:
	var out := PackedStringArray()
	if _slots.size() != COMBATANTS:
		out.append("the arena has %d combatant slots (want %d)" % [_slots.size(), COMBATANTS])
	if _props.size() != BREAKABLES:
		out.append("the arena has %d breakables (want %d)" % [_props.size(), BREAKABLES])
	if player_deaths > 0:
		out.append("the player died %d time(s)" % player_deaths)
	if max_debris > MAX_DEBRIS:
		out.append("debris reached %d (max %d)" % [max_debris, MAX_DEBRIS])
	if _active_samples > 0 and active_average() < MIN_ACTIVE_AVG:
		out.append("active combatants averaged %.2f (want >= %.0f)" % [active_average(), MIN_ACTIVE_AVG])
	if duration_s >= FULL_LAP_CHECK_S and _broken_once.size() < _props.size():
		var missing := PackedStringArray()
		for p: Prop in _props:
			if not _broken_once.has(p.base_id):
				missing.append(p.base_id)
		out.append("%d breakable(s) never broken: %s" % [missing.size(), ", ".join(missing)])
	return out


# --------------------------------------------------------------------------- helpers

static func _alive(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var e: Variant = n.get("entity")
	return e is CombatEntity and (e as CombatEntity).is_alive()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _set_if(n: Node, prop: String, value: Variant) -> void:
	if prop in n:
		n.set(prop, value)


func _free_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var parent := n.get_parent()
	if parent != null:
		parent.remove_child(n)
	n.queue_free()
