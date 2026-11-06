extends Node
## Fixed-step combat simulation driver (autoload "Sim").
##
## Every physics tick (60 Hz) step() runs, in this order:
##   1. tick += 1
##   2. PRE_ACTORS hooks      (EncounterDirector activation, leash and LOD: order 10)
##   3. actors, in stable entity-id order (input -> actions -> movement -> hit queries)
##   4. POST_ACTORS hooks     (ProjectileSystem: order 100)
##   5. hit resolution, in a stable order (results never depend on scene-tree order, frame
##      rate or the physics engine's query ordering)
##   6. the status pass: every entity in id order runs CombatEntity.tick_statuses(tick)
##   7. POST_RESOLVE hooks    (Quests 100, FactionState 150, GameSession checkpoints 200)
## Hooks run in (phase, order, registration sequence) order and are called as hook(tick: int).
## Rendering runs independently in _process.
##
## Randomness: crits keep drawing from `rng` (pinned by the 37/66/44 worked-example tests).
## Every other random consumer (loot, AI picks, debris, bot) uses rng_for("<stream>") or a
## private RNG seeded from its id, so new features never shift the crit sequence.

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
const DEFAULT_SEED := 20261104

enum Hook { PRE_ACTORS, POST_ACTORS, POST_RESOLVE }

var tick: int = 0
## Seeded randomness for critical hits. Tests reseed it. New consumers use rng_for().
var rng := RandomNumberGenerator.new()

var _actors: Dictionary = {}     ## entity_id -> Node implementing sim_step(tick, dt)
var _ordered: Array[Node] = []
var _order_dirty := false
var _entities: Dictionary = {}   ## entity_id -> CombatEntity
var _entity_cache: Array[CombatEntity] = []
var _entity_cache_dirty := true
var _pending_hits: Array[HitEvent] = []
var _next_instance_id := 1
var _tokens: Dictionary = {}     ## target_id -> Array[String] of holder ids
var _hooks: Array = [[], [], []] ## per Hook phase: entries {order, seq, owner: WeakRef, callable, removed}
var _hook_seq := 0
var _seed := DEFAULT_SEED        ## base seed of rng and every stream (reseed() changes it)
var _streams: Dictionary = {}    ## stream name -> RandomNumberGenerator
var _launches: Dictionary = {}   ## target_id -> {"tick": int, "holder": String}


func _ready() -> void:
	process_physics_priority = -1000
	rng.seed = DEFAULT_SEED
	if Engine.physics_ticks_per_second != TICK_RATE:
		push_error("Sim: physics_ticks_per_second must be %d (is %d)" % [TICK_RATE, Engine.physics_ticks_per_second])
	if deterministic_run():
		make_navigation_synchronous(get_viewport())


## True for a run that must replay tick for tick from its seed: a headless run (the tests, the
## soaks, the bots) or one started with --deterministic-streaming (the same rule as
## ChunkStreamer.deterministic).
static func deterministic_run() -> bool:
	return DisplayServer.get_name() == "headless" \
		or OS.get_cmdline_user_args().has(ChunkStreamer.DETERMINISTIC_ARG)


## Deterministic navigation (M6 gate; the rule plan M6-M9 decision 13 sets for the world): every
## navigation map and region syncs in the physics step after it changes instead of on a worker
## thread, so a map change (a level's regions added, a broken gate's link enabled) is usable at a
## fixed tick, never at one that depends on the worker's wall time. With Godot's asynchronous
## iterations, a Valley bot run's paths diverged after a reload or a link change whenever the main
## thread took longer per frame - with the audio engine on, under load - from its twin. Maps and
## regions made later take the project settings changed here; the viewport's own map is switched now.
static func make_navigation_synchronous(viewport: Viewport) -> void:
	ProjectSettings.set_setting("navigation/world/map_use_async_iterations", false)
	ProjectSettings.set_setting("navigation/world/region_use_async_iterations", false)
	if viewport != null and viewport.world_3d != null:
		NavigationServer3D.map_set_use_async_iterations(viewport.world_3d.navigation_map, false)


## Reseeds `rng` and every named stream (stream seed = seed_value ^ hash(name)).
func reseed(seed_value: int) -> void:
	_seed = seed_value
	rng.seed = seed_value
	for stream: String in _streams:
		(_streams[stream] as RandomNumberGenerator).seed = seed_value ^ hash(stream)


## A named, independently seeded random stream (seed = DEFAULT_SEED ^ hash(stream) until
## reseed() changes the base seed). Drawing from it never changes `rng`'s sequence.
func rng_for(stream: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = _streams.get(stream)
	if r == null:
		r = RandomNumberGenerator.new()
		r.seed = _seed ^ hash(stream)
		_streams[stream] = r
	return r


# --------------------------------------------------------------------------- hooks

## Registers callable(tick: int) to run every tick in `hook` (a Hook value). Lower `order` runs
## first; equal orders run in registration order. The hook is dropped when `owner` is freed (or
## by remove_hooks(owner)); with owner null the callable's object is the owner.
func add_hook(hook: int, owner: Object, callable: Callable, order: int = 100) -> void:
	if hook < Hook.PRE_ACTORS or hook > Hook.POST_RESOLVE:
		push_error("Sim.add_hook: unknown hook phase %d" % hook)
		return
	if not callable.is_valid():
		push_error("Sim.add_hook: invalid callable")
		return
	if callable.get_argument_count() < 1:
		push_error("Sim.add_hook: %s must take the tick (hook(tick: int))" % callable)
		return
	if owner == null:
		owner = callable.get_object()
	_hook_seq += 1
	var list: Array = _hooks[hook]
	list.append({"order": order, "seq": _hook_seq, "owner": weakref(owner) if owner != null else null,
		"callable": callable, "removed": false})
	list.sort_custom(_hook_less)


## Removes every hook registered with this owner (also happens automatically once it is freed).
func remove_hooks(owner: Object) -> void:
	for phase_index in _hooks.size():
		var list: Array = _hooks[phase_index]
		for entry: Dictionary in list:
			if entry.owner != null and (entry.owner as WeakRef).get_ref() == owner:
				entry.removed = true
		_hooks[phase_index] = list.filter(func(e: Dictionary) -> bool: return not e.removed)


## Number of live hooks in one phase (tests, debug panel).
func hook_count(hook: int) -> int:
	var n := 0
	for entry: Dictionary in _hooks[hook]:
		if not entry.removed and _hook_alive(entry):
			n += 1
	return n


func _run_hooks(hook: int) -> void:
	var list: Array = _hooks[hook]
	if list.is_empty():
		return
	var prune := false
	for entry: Dictionary in list.duplicate():
		if entry.removed:
			continue
		if not _hook_alive(entry):
			entry.removed = true
			prune = true
			continue
		(entry.callable as Callable).call(tick)
	if prune:
		_hooks[hook] = (_hooks[hook] as Array).filter(func(e: Dictionary) -> bool: return not e.removed)


static func _hook_alive(entry: Dictionary) -> bool:
	if entry.owner != null and (entry.owner as WeakRef).get_ref() == null:
		return false
	return (entry.callable as Callable).is_valid()


static func _hook_less(a: Dictionary, b: Dictionary) -> bool:
	if a.order != b.order:
		return a.order < b.order
	return a.seq < b.seq


# --------------------------------------------------------------------------- registry

func register_actor(entity_id: String, node: Node) -> void:
	_actors[entity_id] = node
	_order_dirty = true


func unregister_actor(entity_id: String, node: Node) -> void:
	if _actors.get(entity_id) == node:
		_actors.erase(entity_id)
		_order_dirty = true


func register_entity(entity: CombatEntity) -> void:
	if entity.entity_id == "":
		push_error("Sim: CombatEntity on %s has no entity_id" % entity.get_path())
		return
	var existing: CombatEntity = _entities.get(entity.entity_id)
	if existing != null and existing != entity and is_instance_valid(existing):
		push_error("Sim: duplicate entity_id '%s' (%s and %s)" % [
			entity.entity_id, existing.get_path(), entity.get_path()])
		return
	_entities[entity.entity_id] = entity
	_entity_cache_dirty = true


func unregister_entity(entity: CombatEntity) -> void:
	if _entities.get(entity.entity_id) == entity:
		_entities.erase(entity.entity_id)
		_entity_cache_dirty = true
	release_all_tokens(entity.entity_id)


func get_entity(entity_id: String) -> CombatEntity:
	var e: CombatEntity = _entities.get(entity_id)
	if e != null and not is_instance_valid(e):
		_entities.erase(entity_id)
		return null
	return e


## Entities sorted by id (stable iteration for targeting and AI). The sorted list is cached
## and rebuilt only when the registry changes.
func entities() -> Array[CombatEntity]:
	if _entity_cache_dirty:
		_entity_cache_dirty = false
		_entity_cache.clear()
		var ids := _entities.keys()
		ids.sort()
		for id: String in ids:
			_entity_cache.append(_entities[id])
	var out: Array[CombatEntity] = []
	for e in _entity_cache:
		if is_instance_valid(e):
			out.append(e)
	return out


func new_instance_id() -> int:
	var id := _next_instance_id
	_next_instance_id += 1
	return id


# --------------------------------------------------------------------------- hits

func queue_hit(hit: HitEvent) -> void:
	_pending_hits.append(hit)


## Drops queued hits, attack tokens and launch slots (scene resets, tests).
func clear_pending() -> void:
	_pending_hits.clear()
	_tokens.clear()
	_launches.clear()


func pending_hit_count() -> int:
	return _pending_hits.size()


# --------------------------------------------------------------------------- attack tokens

## At most max_holders attackers may hold a token on one target; others reposition.
## Ranged enemies use the key target_id + ":ranged" for their separate pool.
func request_token(target_id: String, holder_id: String, max_holders: int) -> bool:
	var holders: Array = _tokens.get(target_id, [])
	if holders.has(holder_id):
		return true
	if holders.size() >= max_holders:
		return false
	holders.append(holder_id)
	_tokens[target_id] = holders
	return true


func release_token(target_id: String, holder_id: String) -> void:
	var holders: Array = _tokens.get(target_id, [])
	holders.erase(holder_id)
	if holders.is_empty():
		_tokens.erase(target_id)


func release_all_tokens(holder_id: String) -> void:
	for target_id: String in _tokens.keys():
		release_token(target_id, holder_id)


func token_holders(target_id: String) -> Array:
	return (_tokens.get(target_id, []) as Array).duplicate()


# --------------------------------------------------------------------------- launch slots

## Staggers ranged launches at one target (spec 10): grants a slot when at least min_gap_ticks
## have passed since the last granted launch at that target (or there was none), then records
## this tick. Returns false (nothing recorded) otherwise.
func request_launch_slot(target_id: String, holder_id: String, min_gap_ticks: int) -> bool:
	if _launches.has(target_id) and tick - last_launch_tick(target_id) < min_gap_ticks:
		return false
	_launches[target_id] = {"tick": tick, "holder": holder_id}
	return true


## Tick of the last granted launch at target_id, or -1 when there was none.
func last_launch_tick(target_id: String) -> int:
	return int((_launches.get(target_id, {"tick": -1}) as Dictionary).tick)


# --------------------------------------------------------------------------- stepping

func _physics_process(_delta: float) -> void:
	step()


## One simulation tick. Public so tests can reason about exact tick boundaries.
func step() -> void:
	tick += 1
	_run_hooks(Hook.PRE_ACTORS)
	if _order_dirty:
		_rebuild_order()
	for node in _ordered:
		if is_instance_valid(node) and node.is_inside_tree() and node.can_process():
			node.sim_step(tick, DT)
	_run_hooks(Hook.POST_ACTORS)
	_resolve_hits()
	_tick_statuses()
	_run_hooks(Hook.POST_RESOLVE)


func _rebuild_order() -> void:
	_order_dirty = false
	_ordered.clear()
	var ids := _actors.keys()
	ids.sort()
	for id: String in ids:
		var n: Node = _actors[id]
		if is_instance_valid(n):
			_ordered.append(n)


func _resolve_hits() -> void:
	if _pending_hits.is_empty():
		return
	var hits := _pending_hits
	_pending_hits = []
	hits.sort_custom(HitEvent.compare_stable)
	for hit in hits:
		var target := get_entity(hit.target_id)
		if target == null:
			continue
		var attacker := get_entity(hit.attacker_id)
		# A dead attacker's hits are dropped, except projectiles already in flight: those still
		# land unless their owner died on this very tick (earlier in this pass, decision 8).
		if attacker != null and attacker.combatant.dead \
				and (not hit.from_projectile or attacker.died_tick == tick):
			continue
		target.receive_hit(hit, attacker)


## The built-in status pass: periodic effects and expiry for every entity, in id order.
func _tick_statuses() -> void:
	for e in entities():
		e.tick_statuses(tick)
