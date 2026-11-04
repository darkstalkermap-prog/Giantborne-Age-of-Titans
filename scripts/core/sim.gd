extends Node
## Fixed-step combat simulation driver (autoload "Sim").
##
## Every physics tick (60 Hz) it: advances the tick counter, steps each registered actor in
## stable entity-id order (input -> actions -> movement -> hit queries), then resolves all
## queued hits in a stable order so results never depend on scene-tree order, frame rate or
## the physics engine's query ordering. Rendering runs independently in _process.

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
const DEFAULT_SEED := 20261104

var tick: int = 0
## Seeded randomness for gameplay rolls (critical hits, AI choices). Tests reseed it.
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


func _ready() -> void:
	process_physics_priority = -1000
	rng.seed = DEFAULT_SEED
	if Engine.physics_ticks_per_second != TICK_RATE:
		push_error("Sim: physics_ticks_per_second must be %d (is %d)" % [TICK_RATE, Engine.physics_ticks_per_second])


func reseed(seed_value: int) -> void:
	rng.seed = seed_value


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


## Entities sorted by id (stable iteration for targeting and AI).
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


func clear_pending() -> void:
	_pending_hits.clear()
	_tokens.clear()


func pending_hit_count() -> int:
	return _pending_hits.size()


# --------------------------------------------------------------------------- attack tokens

## At most max_holders attackers may hold a token on one target; others reposition.
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


# --------------------------------------------------------------------------- stepping

func _physics_process(_delta: float) -> void:
	step()


## One simulation tick. Public so tests can reason about exact tick boundaries.
func step() -> void:
	tick += 1
	if _order_dirty:
		_rebuild_order()
	for node in _ordered:
		if is_instance_valid(node) and node.is_inside_tree() and node.can_process():
			node.sim_step(tick, DT)
	_resolve_hits()


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
		# An attacker killed earlier in this same resolution pass loses its in-flight hits.
		if attacker != null and attacker.combatant.dead:
			continue
		target.receive_hit(hit, attacker)
