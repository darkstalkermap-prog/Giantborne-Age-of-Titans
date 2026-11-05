extends IntegrationSuite
## The seeded soak's target order (M2 gate). With P04's wolf pack in the sandbox, the bot used to
## cross the arena to the wolves as soon as the soldier died, so the definition-of-done soak never
## broke the fence again (no breakable, debris or loot coverage). Autopilot.pick_soak_target now
## takes the arena's enemies first, then an intact breakable, then far enemies, then a dummy; the
## sandbox layout check keeps its radii true to the real scene. tools/check.sh asserts the
## result: a 120 s soak breaks a fence, fills the debris pool and awards loot.

const ARENA := "res://scenes/world/sandbox_arena.tscn"


func _stand_in(pos: Vector3, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	world.add_child(n)
	return n


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_soak_target_order() -> void:
	var spawn := Vector3(0, 0.05, 40)   # the sandbox player spawn
	var centre := Vector3.ZERO
	var soldier := _stand_in(Vector3(0, 0, -12), "Soldier")
	var wolf_a := _stand_in(Vector3(-46, 0, -40), "WolfA")
	var wolf_b := _stand_in(Vector3(-41, 0, -46), "WolfB")
	var fence := _stand_in(Vector3(12, 0, 34), "Fence")
	var dummy := _stand_in(Vector3(0, 0, 32), "Dummy")
	await step_ticks(1)
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [wolf_a, soldier, wolf_b], fence, dummy), soldier,
		"the arena's soldier comes first, wherever the group lists it")
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [wolf_a, wolf_b], fence, dummy), fence,
		"with the soldier dead: the intact fence before the wolves in the far corner")
	assert_eq(Autopilot.pick_soak_target(Vector3(-25, 0, -20), centre, [wolf_a, wolf_b], fence, dummy), fence,
		"also when the giant stands nearer the wolves than the fence")
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [wolf_b, wolf_a], null, dummy), wolf_a,
		"fence broken: the nearest far enemy")
	var biter := _stand_in(Vector3(-44, 0, -40), "Biter")
	await step_ticks(1)
	var by_the_wolves := Vector3(-40, 0, -35)
	assert_true(_flat(by_the_wolves, biter.position) <= Autopilot.ENGAGE_RADIUS_M
		and _flat(centre, biter.position) > Autopilot.ARENA_RADIUS_M, "probe: a far enemy right beside the giant")
	assert_eq(Autopilot.pick_soak_target(by_the_wolves, centre, [biter, soldier], fence, dummy), biter,
		"an enemy beside the giant (ENGAGE_RADIUS_M) is fought first: before the fence and a farther arena enemy")
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [], fence, dummy), fence, "no enemy left: the fence")
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [], null, dummy), dummy, "nothing else: the dummy")
	assert_true(Autopilot.pick_soak_target(spawn, centre, [], null, null) == null, "and nothing at all: no target")


## The real sandbox: the wolves and their patrol lie outside ARENA_RADIUS_M of the arena centre and
## the soldier's patrol inside it, so from the player spawn the soak fights the soldier, then
## breaks the fence, and only then walks to the wolves.
func test_sandbox_layout_puts_the_fence_before_the_wolves() -> void:
	var arena: Node3D = (load(ARENA) as PackedScene).instantiate()
	TestSpawn.disable_all_ai(arena)
	world.add_child(arena)
	await step_ticks(2)
	var centre := arena.global_position
	var soldier: Node3D = null
	var wolves: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if not arena.is_ancestor_of(n):
			continue
		if n is WolfEnemy:
			wolves.append(n)
		elif n is SoldierEnemy:
			soldier = n
	assert_eq(wolves.size(), 3, "the sandbox wolf pack")
	assert_true(soldier != null, "and its soldier")
	for w: Node3D in wolves:
		assert_true(_flat(w.global_position, centre) > Autopilot.ARENA_RADIUS_M,
			"%s starts outside the arena radius (%.1f m)" % [w.name, _flat(w.global_position, centre)])
	for p: Node3D in arena.get_node("WolfPatrol").get_children():
		assert_true(_flat(p.global_position, centre) > Autopilot.ARENA_RADIUS_M,
			"wolf patrol point %s is outside the arena radius" % p.name)
	for p: Node3D in arena.get_node("PatrolRoute").get_children():
		assert_true(_flat(p.global_position, centre) <= Autopilot.ARENA_RADIUS_M,
			"soldier patrol point %s is inside the arena radius" % p.name)
	var fence: Node3D = null
	for n in get_tree().get_nodes_in_group("breakables"):
		if arena.is_ancestor_of(n):
			fence = n
	var dummy: Node3D = null
	for n in get_tree().get_nodes_in_group("dummies"):
		if arena.is_ancestor_of(n) and dummy == null:
			dummy = n
	assert_true(fence != null and dummy != null, "a fence and a dummy")
	var spawn := (arena as SandboxArena).player_spawn().origin
	assert_eq(Autopilot.pick_soak_target(spawn, centre, [soldier] + wolves, fence, dummy), soldier,
		"the soak starts on the soldier")
	assert_eq(Autopilot.pick_soak_target(spawn, centre, wolves, fence, dummy), fence,
		"then breaks the fence")
	assert_true(wolves.has(Autopilot.pick_soak_target(spawn, centre, wolves, null, dummy)),
		"and only then goes for the wolves")
	arena.queue_free()
	await step_ticks(2)
