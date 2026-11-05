extends IntegrationSuite
## The ranged test level (scenes/test/ranged_test.tscn, built by tools/builders/ranged.gd) with its
## baked navmesh: an archer finds the platform's elevation marker, climbs the railed ramp onto it
## and shoots from the high ground. Slow (a 120 m level and up to 16 s of play); runs with --slow.

const RANGED_TEST := "res://scenes/test/ranged_test.tscn"

var spawned: Array = []


func before_each() -> void:
	await super()
	spawned.clear()
	Events.projectile_spawned.connect(_on_spawned)


func after_each() -> void:
	if Events.projectile_spawned.is_connected(_on_spawned):
		Events.projectile_spawned.disconnect(_on_spawned)
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


func _on_spawned(_t: int, _id: int, owner_id: String, _action_id: String, _pos: Vector3, _vel: Vector3, _visual: String) -> void:
	spawned.append(owner_id)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The playground's navmesh leads an archer up the railed ramp onto the platform's elevation marker.
func test_ranged_test_level_archer_climbs_to_the_elevation_marker() -> void:
	var level: Node3D = (load(RANGED_TEST) as PackedScene).instantiate()
	TestSpawn.disable_all_ai(level)
	world.add_child(level)
	var archer := level.get_node("Enemies/Archer01") as ArcherEnemy
	archer.ai_enabled = true
	var p := level.get_node("Player") as GiantPlayer
	p.entity.combatant.unkillable = true
	var marker := level.get_node("Markers/ElevationPlatform") as Node3D
	assert_true(marker.is_in_group(EnemyActor.ELEVATION_GROUP), "the platform marker is an elevation point")
	assert_eq(level.get_tree().get_nodes_in_group(EnemyActor.COVER_GROUP).size(), 2, "two cover points")
	var up: bool = await TestWait.until(self, func() -> bool:
		return _flat(archer.global_position, marker.global_position) < EnemyBrain.FIRING_SETTLE_M \
			and archer.global_position.y > marker.global_position.y - 0.2, 720)
	assert_true(up, "the archer climbed onto the platform (%s)" % archer.global_position)
	assert_true(await TestWait.until(self, func() -> bool: return spawned.has(archer.entity_id), 240),
		"and shoots from the high ground")
