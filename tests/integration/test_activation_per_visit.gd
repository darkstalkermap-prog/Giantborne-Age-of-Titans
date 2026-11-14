extends IntegrationSuite
## Shrines and waystones activate once per level visit, not once per node (P20; plan M6-M9 §2.6):
## GameSession.activated_this_visit / mark_activated. A shrine freed and made again in the same
## visit (its streamed chunk unloading and loading again) gives no second free rest and no second
## checkpoint, only its lit glow; a waystone made again is already reached; a new visit (a level
## load: on_level_ready) activates them again.

const SHRINE := "res://scenes/world/shrine.tscn"
const SHRINE_ID := "test.shrine.visit"
const STONE_ID := "test.cp.visit"

var reached: Array = []
var activated: Array[String] = []


func before_each() -> void:
	await super()
	reached.clear()
	activated.clear()
	Events.checkpoint_reached.connect(_on_reached)
	Events.shrine_activated.connect(_on_activated)


func after_each() -> void:
	for sig: Signal in [Events.checkpoint_reached, Events.shrine_activated]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_reached(_t: int, id: String, kind: String) -> void:
	reached.append([id, kind])


func _on_activated(_t: int, id: String) -> void:
	activated.append(id)


func _shrine(pos: Vector3) -> Shrine:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = SHRINE_ID
	s.shrine_id = "shrine.grove"
	s.position = pos
	world.add_child(s)
	return s


func _stone(pos: Vector3) -> Waystone:
	var w := Waystone.new()
	w.checkpoint_id = STONE_ID
	w.display_name = "Visit stone"
	w.position = pos
	world.add_child(w)
	return w


func _free_and_wait(n: Node) -> void:
	n.queue_free()
	await get_tree().process_frame


func test_shrines_and_waystones_activate_once_per_level_visit() -> void:
	GameSession.test_checkpoints = true
	var p := spawn_player(Vector3(0, 0.05, 0))
	GameSession.on_level_ready(world, p)
	await step_ticks(2)
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max * 0.3
	var first := _shrine(Vector3(0, 0, -8))
	await step_ticks(2)
	assert_eq(reached, [[SHRINE_ID, "shrine"]], "the first activation reaches the shrine's checkpoint")
	assert_eq(activated, [SHRINE_ID] as Array[String], "and activates it")
	assert_near(pools.health, pools.health_max, 1e-3, "with its free rest")
	assert_true(GameSession.activated_this_visit(SHRINE_ID), "the visit remembers it")
	# Its chunk streams out and back in: the node is freed and made again in the same visit.
	await _free_and_wait(first)
	pools.health = pools.health_max * 0.3
	var again := _shrine(Vector3(0, 0, -8))
	await step_ticks(2)
	assert_true(again.is_activated(), "the new node counts as activated (its glow is lit)")
	assert_eq(reached.size(), 1, "no second checkpoint")
	assert_eq(activated.size(), 1, "no second activation")
	assert_near(pools.health, pools.health_max * 0.3, 1e-3, "and no second free rest")
	assert_false(again.activate(p), "activating it by hand gives nothing either")
	var rest := again.rest(p)
	assert_true(bool(rest.ok) and pools.health > pools.health_max * 0.99, "resting on purpose still heals")
	# A waystone the same way.
	var stone := _stone(p.global_position)
	assert_true(stone.check(), "the waystone is reached")
	assert_eq(reached.back(), [STONE_ID, "waystone"], "its checkpoint")
	await _free_and_wait(stone)
	var stone2 := _stone(p.global_position)
	assert_false(stone2.check(), "made again in the same visit it emits nothing")
	assert_true(stone2.is_reached(), "it is already reached")
	assert_eq(reached.size(), 2, "still two checkpoints")
	# A level load is a new visit: both activate again.
	await _free_and_wait(again)
	await _free_and_wait(stone2)
	GameSession.on_level_ready(world, p)
	assert_false(GameSession.activated_this_visit(SHRINE_ID), "a new visit forgets the shrine")
	assert_false(GameSession.activated_this_visit(STONE_ID), "and the waystone")
	pools.health = pools.health_max * 0.3
	_shrine(Vector3(0, 0, -8))
	await step_ticks(2)
	assert_eq(reached.size(), 3, "the shrine's checkpoint is reached again on the new visit")
	assert_near(pools.health, pools.health_max, 1e-3, "with its free rest")
	assert_true(_stone(p.global_position).check(), "and the waystone is reached again")
	assert_true(GameSession.activated_this_visit(STONE_ID), "the new visit remembers them")
	GameSession.mark_activated("")
	assert_false(GameSession.activated_this_visit(""), "an empty id is never remembered")
