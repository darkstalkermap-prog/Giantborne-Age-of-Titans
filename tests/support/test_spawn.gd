class_name TestSpawn
extends RefCounted
## Spawning helpers for integration tests (plan §2.13).

const STUB_ENEMY_SCRIPT := "res://tests/support/stub_enemy.gd"
const SOLDIER_SCENE := "res://scenes/enemies/soldier.tscn"


## Instantiates an enemy scene with a stable id, places it and adds it to `world`.
static func enemy(world: Node3D, scene_path: String, pos: Vector3, id: String, ai: bool,
		yaw := 0.0) -> EnemyActor:
	var e := (load(scene_path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = ai
	e.position = pos
	e.rotation.y = yaw
	world.add_child(e)
	return e


## A non-soldier EnemyActor (StubEnemy: the base melee brain, no guard) built on the soldier's
## body, for tests of the enemy seams. definition_id picks the data record it fights with.
static func stub_enemy(world: Node3D, pos: Vector3, id: String, ai := false,
		definition_id := "enemy.soldier", yaw := 0.0) -> EnemyActor:
	var e := (load(SOLDIER_SCENE) as PackedScene).instantiate()
	e.set_script(load(STUB_ENEMY_SCRIPT))
	var actor := e as EnemyActor
	(actor.get_node("CombatEntity") as CombatEntity).definition_id = definition_id
	actor.name = "Stub_" + id.replace(".", "_")
	actor.entity_id = id
	actor.ai_enabled = ai
	actor.position = pos
	actor.rotation.y = yaw
	world.add_child(actor)
	return actor


## Turns off the brain of every enemy under `root` (and root itself). Works before or after
## the nodes enter the tree, e.g. on a freshly instantiated arena.
static func disable_all_ai(root: Node) -> void:
	if root == null:
		return
	if "ai_enabled" in root:
		root.set("ai_enabled", false)
	for child in root.get_children():
		disable_all_ai(child)
