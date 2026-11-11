class_name Civilian
extends CharacterBody3D
## A person of a level: a villager (role "civilian") or a talker such as the elder (an `npc`
## record; plan §3.13 design 1, §2.7.4). Team NEUTRAL with a faction ("village"), so the player
## can neither lock it nor touch it with area effects (TargetingRules), while a direct blow is an
## offence (FactionState). It never fights. Groups "npcs" and, for role civilian, "civilians".
##
## A CivilianBrain decides (IDLE -> FLEE -> SAFE): the giant rushing close, combat within 20 m,
## or its faction turning hostile or standing down sends a civilian to the nearest reachable safe
## marker (group "safe_markers", faction "" or its own): each candidate, nearest first, is snapped
## to this actor's navmesh layer (NavQuery.closest_point: the layer's own map in a streamed world,
## LevelRoot.nav_region in the Valley; P24b) and accepted when a path on its layers ends there
## (NavQuery.path; spec 15: reachable destinations). The agent gets that target once and
## re-paths only after a path failure (no progress for 2 s: the next candidate). At the marker the
## civilian takes shelter: it goes inside (hidden) and stops processing (process_mode DISABLED, so
## Sim skips it and its body leaves physics). A civilian spawned while its faction is already
## hostile or stood down is put straight into its shelter once the navigation map answers.
## A talker never flees; a `protected` npc refuses every hit (IMMUNE: still an offence).
##
## P24b: in a streamed world (a level with nav_query settings) the agent paths on its layer's own map
## with unlimited polygons and the far distance cap (NavQuery), like every other query of this actor.
##
## M7 polish: there its safe-point search keeps NavQuery's per-tick budget, as the enemies' firing-
## point, flee and rout searches do (EnemyActor's P24b section): each marker tried - a closest point
## and a path, SEARCH_CANDIDATE_QUERIES - waits until the level's budget_left() has them and this
## civilian's share of the tick (SEARCH_QUERIES_PER_TICK, one marker) allows; otherwise the search
## stops at that marker, brain.nav_search_pending says so, and the next tick resumes it there. Its
## agent's path to the chosen marker (one query) waits for the budget too and is counted. A town's
## folk fleeing at once (Brannock's eight villagers when it turns hostile; Millford's in P37's raid)
## used to search every marker in the same tick, outside the budget: 16 queries NavQuery counted and 8
## agent paths it did not, with all eight deciding in one tick.
##
## Required children: CombatEntity (team NEUTRAL), NavAgent; Visual (ActorRig) with Body and
## LodProxy, Anchors/Torso, Hurtboxes/*. The elder also carries an NpcTalker (P13), which reads
## this actor's `entity_id` and its record's `dialogue`.

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 30.0
const PATH_CHECK_S := 2.0
## Closer than this to its goal a civilian steers straight at it.
const DIRECT_STEER_DISTANCE := 1.5
const PERCEPTION_INTERVAL := 12
const DECISION_INTERVAL := 6
const SAFE_GROUP := "safe_markers"
## A safe marker counts only when the navmesh of this actor's layer lies within this of it...
const MARKER_SNAP_M := 2.0
## ... and a path on its layers ends within this of that point.
const REACH_END_M := 1.0
const SIGHT_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
const LAYER_BLOCKER := 32
## M7 polish (the header): a safe marker tried costs this many path queries (its closest point and a
## path), and one civilian's search tries at most one marker a tick...
const SEARCH_CANDIDATE_QUERIES := 2
const SEARCH_QUERIES_PER_TICK := 2
## ... and resumes at the marker it stopped at when asked again within this many ticks (the next tick
## asks: the actor decides again while a search waits); later it starts anew.
const SEARCH_RESUME_TICKS := 30

## Stable id of this placed or spawned person (unique per level).
@export var entity_id := ""
## Its faction ("village": Thornwick). The director sets it from the encounter's spawn.
@export var faction := "village"
## Set by the EncounterDirector (P10a).
@export var encounter_id := ""
## When true the director records this death as a world delta (killed).
@export var persist_death := false
## When false the brain neither perceives nor decides (tests).
@export var ai_enabled := true

## Spawn point (the director sets it).
var home_position := Vector3.ZERO

@onready var entity: CombatEntity = $CombatEntity
@onready var agent: NavigationAgent3D = $NavAgent
@onready var rig: ActorRig = get_node_or_null("Visual") as ActorRig

var record: Dictionary = {}
var brain: CivilianBrain
var facing_yaw := 0.0
var move_velocity := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
## The safe marker it runs to (null while none is chosen).
var safe_marker: Node3D = null
## True once it reached its safe marker: hidden, processing stopped.
var sheltered := false
var path_failures := 0
var lod_tier := 0
var _failed_markers: Array = []
var _phase_offset := 0
var _progress_anchor := Vector3.INF
var _progress_timer := 0.0
var _nav_target := Vector3.INF
var _world_agent := false   # P24b: the agent paths on a streamed world's layer map (_setup_world_agent)
var _shelter_at_once := false
var _pending_lod := -1
var _lod_body: Node3D
var _lod_proxy: Node3D
## M7 polish: the safe-point search in progress (its markers, nearest first, and where it stopped for
## the budget), what this civilian's searches spent this tick, and the most they spent in one tick.
var _search_markers: Array = []
var _search_next := 0
var _search_stop_tick := -1000000
var _search_spent_tick := -1
var _search_spent := 0
var search_queries_peak := 0


func _ready() -> void:
	add_to_group("npcs")
	entity_id = entity.entity_id
	if home_position == Vector3.ZERO:
		home_position = global_position
	record = GameData.get_record(entity.definition_id)
	brain = CivilianBrain.new(entity.entity_id, record)
	brain.safe_resolver = _resolve_safe_point
	if brain.can_flee():
		add_to_group("civilians")
	facing_yaw = rotation.y
	agent.radius = float(record.get("capsule_radius_m", 0.3))
	agent.height = float(record.get("height_m", 1.7))
	agent.navigation_layers = int(record.get("nav_layers", 1))
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = false
	_setup_world_agent()
	_phase_offset = absi(hash(entity.entity_id)) % PERCEPTION_INTERVAL
	_lod_body = get_node_or_null("Visual/Body") as Node3D
	_lod_proxy = get_node_or_null("Visual/LodProxy") as Node3D
	Events.ability_started.connect(_on_any_ability_started)
	Events.hit_resolved.connect(_on_any_hit_resolved)
	Events.faction_changed.connect(_on_faction_changed)
	if faction != "":
		FactionState.hub()
		var standing := FactionState.standing(faction)
		if brain.can_flee() and standing in ["hostile", "stood_down"]:
			_shelter_at_once = true
			brain.start_fleeing(standing)
	Sim.register_actor(entity.entity_id, self)
	if _pending_lod >= 0:
		var tier := _pending_lod
		_pending_lod = -1
		set_lod_tier(tier)


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	var alive := entity.is_alive()
	if ai_enabled and alive and (tick + _phase_offset) % PERCEPTION_INTERVAL == 0:
		brain.perceive(tick, _sense())
	if ai_enabled and (not alive or (tick + _phase_offset) % DECISION_INTERVAL == 0 or brain.nav_search_pending):
		brain.decide(tick, global_position, alive)   # M7 polish: a search waiting for the budget resumes the next tick
	if brain.state == CivilianBrain.State.FLEE and _shelter_at_once and brain.destination != Vector3.INF:
		global_position = brain.destination   # already in hiding when the level loaded
		brain.decide(tick, global_position, alive)
	if brain.state == CivilianBrain.State.SAFE and not sheltered:
		_take_shelter()
		return
	_update_facing(dt)
	_update_movement(dt, alive)


## The giant as this civilian sees it: {"exists", "position", "distance", "speed", "hostile",
## "stood_down"} (the faction flags are read every time: a spawn after the news still hears it).
func _sense() -> Dictionary:
	var out := {"exists": false, "hostile": FactionState.is_hostile(faction),
		"stood_down": FactionState.is_stood_down(faction)}
	var t := _player()
	if t == null or not is_instance_valid(t.actor) or not t.is_alive():
		return out
	var v: Vector3 = t.actor.get("velocity") if "velocity" in t.actor else Vector3.ZERO
	out.merge({"exists": true, "position": t.actor.global_position,
		"distance": _flat(t.actor.global_position - global_position), "speed": Vector2(v.x, v.z).length()}, true)
	return out


func _player() -> CombatEntity:
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER:
			return e
	return null


## Combat nearby: an attack someone began (light, heavy, ability, enemy attack, ultimate).
func _on_any_ability_started(tick: int, actor_id: String, action_id: String, _instance: int) -> void:
	if not _listening():
		return
	var a := GameData.get_action(action_id)
	var src := Sim.get_entity(actor_id)
	if a == null or not a.is_attack() or src == null or src == entity or not is_instance_valid(src.actor):
		return
	brain.on_noise(tick, _flat(src.actor.global_position - global_position))


## Combat nearby: a blow that landed (on anyone, this civilian included).
func _on_any_hit_resolved(tick: int, result: HitResult) -> void:
	if not _listening() or result == null or result.event == null \
			or result.outcome == HitResult.Outcome.IGNORED:
		return
	var target := Sim.get_entity(result.event.target_id)
	var where := result.event.attacker_position
	if target != null and is_instance_valid(target.actor):
		where = target.actor.global_position
	brain.on_noise(tick, _flat(where - global_position))


func _on_faction_changed(tick: int, changed_faction: String, _state: String) -> void:
	if changed_faction == faction and _listening():
		brain.on_faction(tick, FactionState.standing(faction))


## M8 gate fix-up 1 (N4.7): only in the tree - a civilian whose chunk is unloading (out of the tree, not
## freed yet) stays connected to Events and measured its noise from its global transform, an engine error
## ("!is_inside_tree()") for every attack begun nearby.
func _listening() -> bool:
	return is_inside_tree() and ai_enabled and brain != null and brain.state == CivilianBrain.State.IDLE \
		and not sheltered and entity != null and entity.combatant != null and entity.is_alive()


# --------------------------------------------------------------------------- safe points

## brain.safe_resolver: the nearest reachable safe marker point from `from` (Vector3.INF when
## none is reachable). skip_failed: the marker it ran to could not be reached; never again.
## In a streamed world the markers are tried within the tick's path-query budget (M7 polish, the
## header): a search that stops for it returns Vector3.INF with brain.nav_search_pending set, and
## resumes at that marker when asked again (the next tick) within SEARCH_RESUME_TICKS.
func _resolve_safe_point(from: Vector3, skip_failed: bool) -> Vector3:
	if skip_failed and safe_marker != null and not _failed_markers.has(safe_marker):
		_failed_markers.append(safe_marker)
	safe_marker = null
	var start := 0
	if not skip_failed and not _search_markers.is_empty() and Sim.tick - _search_stop_tick <= SEARCH_RESUME_TICKS:
		start = _search_next   # the search stopped there for the budget: it goes on
	else:
		_search_markers = _safe_markers(from)
	for i in range(start, _search_markers.size()):
		var m := _search_markers[i] as Node3D
		if m == null or not is_instance_valid(m) or not m.is_inside_tree() or _failed_markers.has(m):
			continue
		if not _search_affords():
			_search_next = i
			_search_stop_tick = Sim.tick
			if brain != null:
				brain.nav_search_pending = true
			return Vector3.INF
		var q0 := NavQuery.queries_total
		var p := reachable_point(from, m.global_position)
		_search_spend(q0)
		if p == Vector3.INF:
			continue
		_search_markers.clear()
		safe_marker = m
		return p
	_search_markers.clear()
	return Vector3.INF


## The safe markers this civilian may use (faction "" or its own, not failed), nearest `from` first.
func _safe_markers(from: Vector3) -> Array:
	var candidates: Array = []
	for n in get_tree().get_nodes_in_group(SAFE_GROUP):
		var m := n as Node3D
		if m == null or not m.is_inside_tree() or _failed_markers.has(m):
			continue
		var f: Variant = m.get("faction")
		if typeof(f) == TYPE_STRING and f != "" and f != faction:
			continue
		candidates.append(m)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat(a.global_position - from) < _flat(b.global_position - from))
	return candidates


## True when one more safe marker may be tried this tick: always without nav_query settings; in a
## streamed world when the level's budget has SEARCH_CANDIDATE_QUERIES left and this civilian's
## searches spent at most SEARCH_QUERIES_PER_TICK - SEARCH_CANDIDATE_QUERIES this tick (M7 polish).
func _search_affords() -> bool:
	if not _world_agent:
		return true
	_search_roll()
	return _search_spent + SEARCH_CANDIDATE_QUERIES <= SEARCH_QUERIES_PER_TICK \
		and NavQuery.budget_left(nav_level()) >= SEARCH_CANDIDATE_QUERIES


## Counts what one marker's try spent (NavQuery.queries_total when it began).
func _search_spend(queries_before: int) -> void:
	_search_roll()
	_search_spent += NavQuery.queries_total - queries_before
	search_queries_peak = maxi(search_queries_peak, _search_spent)


func _search_roll() -> void:
	if _search_spent_tick != Sim.tick:
		_search_spent_tick = Sim.tick
		_search_spent = 0


## `target` as this civilian can reach it from `from`: on a navmesh, the closest point of its
## layer (NavQuery.closest_point, within MARKER_SNAP_M of the target) when a path on its layers
## (NavQuery.path, the far purpose) ends within REACH_END_M of it; Vector3.INF while the navigation
## map has not synchronised yet. Without any navmesh: the target itself when a straight run there is
## clear of walls and blockers.
func reachable_point(from: Vector3, target: Vector3) -> Vector3:
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	if NavQuery.has_regions(level, layers):
		if not NavQuery.is_synced(level, layers):
			return Vector3.INF
		var snapped := NavQuery.closest_point(level, target, layers)
		if not snapped.is_finite() or _flat(snapped - target) > MARKER_SNAP_M:
			return Vector3.INF
		var path := NavQuery.path(level, from, snapped, layers, NavQuery.PURPOSE_FAR)
		if path.is_empty() or path[path.size() - 1].distance_to(snapped) > REACH_END_M:
			return Vector3.INF
		return snapped
	var lift := Vector3.UP * 0.5
	if HitQueryAdapter.line_clear(get_world_3d().direct_space_state, from + lift, target + lift,
			SIGHT_MASK | LAYER_BLOCKER, entity.occlusion_rids):
		return Vector3(target.x, from.y, target.z)
	return Vector3.INF


## True when the agent may ask for its path now: always without nav_query settings; in a streamed
## world while the tick's budget has a query left (M7 polish: it is counted, as an enemy's re-path).
func _agent_path_affords() -> bool:
	return not _world_agent or NavQuery.budget_left(nav_level()) > 0


## The level this civilian asks for navigation (NavQuery): the level root of the tree, else the
## civilian itself (a bare test world: its world's default map).
func nav_level() -> Node:
	var level := get_tree().get_first_node_in_group("level_root") if is_inside_tree() else null
	return level if level != null else self


## In a streamed world (nav_query settings), the agent paths on its layer's own map with
## unlimited polygons and the far distance cap; elsewhere it keeps the world's map and today's
## parameters.
func _setup_world_agent() -> void:
	var level := nav_level()
	if NavQuery.settings(level).is_empty():
		return
	_world_agent = true
	var layers := int(agent.navigation_layers)
	var m := NavQuery.map_for(level, layers)
	if m.is_valid():
		agent.set_navigation_map(m)
	var p := NavQuery.params_for(level, NavQuery.PURPOSE_FAR)
	agent.path_search_max_polygons = int(p.max_polygons)
	agent.path_search_max_distance = float(p.max_distance)


## At the safe marker: it goes inside (hidden) and stops processing; Sim skips it from now on.
func _take_shelter() -> void:
	sheltered = true
	_shelter_at_once = false
	velocity = Vector3.ZERO
	move_velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


# --------------------------------------------------------------------------- movement

func _update_facing(dt: float) -> void:
	var target_yaw := facing_yaw
	if brain.face_point != Vector3.INF:
		var to := brain.face_point - global_position
		if Vector2(to.x, to.z).length_squared() > 1e-4:
			target_yaw = TargetingRules.yaw_of(to)
	elif Vector2(move_velocity.x, move_velocity.z).length() > 0.3:
		target_yaw = TargetingRules.yaw_of(move_velocity)
	var step := deg_to_rad(float(record.get("turn_rate_deg_s", 360.0))) * dt
	facing_yaw = wrapf(facing_yaw + clampf(TargetingRules.yaw_delta(facing_yaw, target_yaw), -step, step), -PI, PI)
	rotation.y = facing_yaw


func _update_movement(dt: float, alive: bool) -> void:
	var desired := Vector3.ZERO
	if alive and brain.move_target != Vector3.INF:
		var speed := float(record.get("run_speed_mps", 3.0)) if brain.move_speed < 0.0 \
			else float(record.get("walk_speed_mps", 1.2))
		var goal := brain.move_target
		var flat_dist := _flat(goal - global_position)
		var next := goal
		var waiting := false
		if flat_dist > DIRECT_STEER_DISTANCE and NavQuery.is_synced(nav_level(), int(agent.navigation_layers)):
			if _nav_target == Vector3.INF or _nav_target.distance_to(goal) > 0.5:
				if _agent_path_affords():
					agent.target_position = goal   # once per destination: re-path only after a failure
					_nav_target = goal
					if _world_agent:
						NavQuery.spend(nav_level())   # M7 polish: the agent's path counts against the tick's budget
				else:
					waiting = true   # M7 polish: the path waits for the tick's budget; it stands meanwhile
			if not waiting:
				if _world_agent:
					NavQuery.level_waypoint(agent, global_position)   # P24b: lean navmeshes lie off the ground
				if not agent.is_navigation_finished():
					next = agent.get_next_path_position()
				if _flat(next - global_position) < 0.05:
					next = goal   # no path data: steer directly
		var dir := next - global_position
		dir.y = 0.0
		if not waiting and flat_dist > 0.1 and dir.length() > 0.01:
			desired = dir.normalized() * speed
		if not waiting:
			_track_progress(goal, dt)
	else:
		_progress_anchor = Vector3.INF
		_progress_timer = 0.0
	move_velocity = move_velocity.move_toward(desired, 20.0 * dt)
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECEL * dt)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * dt
	velocity.x = move_velocity.x + knockback_velocity.x
	velocity.z = move_velocity.z + knockback_velocity.z
	move_and_slide()


## No progress toward the goal for PATH_CHECK_S: a path failure (the brain picks another marker).
func _track_progress(goal: Vector3, dt: float) -> void:
	if _progress_anchor == Vector3.INF:
		_progress_anchor = global_position
		_progress_timer = 0.0
		return
	_progress_timer += dt
	if _progress_timer < PATH_CHECK_S:
		return
	var progressed := _progress_anchor.distance_to(global_position)
	if progressed < 0.3 and _flat(goal - global_position) >= 1.0:
		path_failures += 1
		_nav_target = Vector3.INF
		brain.on_path_failed(global_position)
	_progress_anchor = global_position
	_progress_timer = 0.0


# --------------------------------------------------------------------------- combat hooks

## A protected npc (the elder) refuses every hit: IMMUNE, which FactionState still counts.
func accepts_hit(_hit: HitEvent) -> bool:
	return not bool(record.get("protected", false))


func apply_knockback(direction: Vector3, speed: float) -> void:
	if direction.length_squared() < 1e-6:
		return
	knockback_velocity = direction.normalized() * maxf(speed, knockback_velocity.length())


func on_entity_died(_killer_id: String) -> void:
	set_deferred("collision_layer", 0)
	for hb in entity.hurtboxes:
		hb.set_deferred("monitorable", false)
		for child in hb.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).set_deferred("disabled", true)


# --------------------------------------------------------------------------- LOD

## AI level of detail from the EncounterDirector (as EnemyActor's): tier 2 is dormant (process
## DISABLED, the one-box proxy shown); 0 and 1 run normally. A sheltered civilian stays as it is.
## May be called before the civilian is ready.
func set_lod_tier(tier: int) -> void:
	tier = clampi(tier, 0, 2)
	if not is_node_ready():
		_pending_lod = tier
		return
	if tier == lod_tier or sheltered:
		return
	lod_tier = tier
	process_mode = Node.PROCESS_MODE_DISABLED if tier == 2 else Node.PROCESS_MODE_INHERIT
	if _lod_body != null:
		_lod_body.visible = tier != 2
	if _lod_proxy != null:
		_lod_proxy.visible = tier == 2


# --------------------------------------------------------------------------- presentation

func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	if rig != null:
		rig.flash(strength, color)


func get_rig_state() -> Dictionary:
	var dead := entity != null and entity.combatant != null and not entity.is_alive()
	return {
		"state": CombatController.State.DEAD if dead else CombatController.State.LOCOMOTION,
		"action": null,
		"phase": ActionDef.Phase.NONE,
		"phase_fraction": 0.0,
		"speed": Vector2(velocity.x, velocity.z).length(),
		"dead": dead,
		"staggered": false,
		"dodging": false,
		"guarding": false,
	}


func get_debug_info() -> Dictionary:
	return {
		"id": entity.entity_id,
		"ai": brain.state_name() if brain != null else "",
		"reason": brain.flee_reason if brain != null else "",
		"health": entity.combatant.pools.health if entity.combatant != null else 0.0,
		"faction": faction,
		"standing": FactionState.standing(faction),
		"sheltered": sheltered,
		"lod": lod_tier,
	}


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
