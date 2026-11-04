class_name IntegrationSuite
extends TestSuite
## Base for engine integration tests: builds a small world (floor, optional walls) and spawns
## the real game scenes, then steps real 60 Hz physics ticks through Sim.

const GIANT := "res://scenes/player/giant.tscn"
const SOLDIER := "res://scenes/enemies/soldier.tscn"
const DUMMY := "res://scenes/world/practice_dummy.tscn"
const FENCE := "res://scenes/world/fence_wood.tscn"

var world: Node3D
var hits: Array[HitResult] = []
var deaths: Array[String] = []
var destroyed: Array[String] = []
var loot: Array[String] = []
var lock_events: Array[Array] = []
var started: Array[String] = []
var clanks := 0


func before_each() -> void:
	Sim.clear_pending()
	WorldState.clear()
	Settings.session["camera_mode"] = 0
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	hits.clear()
	deaths.clear()
	destroyed.clear()
	loot.clear()
	lock_events.clear()
	started.clear()
	clanks = 0
	world = Node3D.new()
	world.name = "TestWorld"
	add_child(world)
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	Events.hit_resolved.connect(_on_hit)
	Events.entity_died.connect(_on_died)
	Events.object_destroyed.connect(_on_destroyed)
	Events.loot_awarded.connect(_on_loot)
	Events.lock_target_changed.connect(_on_lock)
	Events.ability_started.connect(_on_started)
	Events.attack_clanked.connect(_on_clank)
	await step_ticks(1)


func after_each() -> void:
	for sig: Signal in [Events.hit_resolved, Events.entity_died, Events.object_destroyed,
			Events.loot_awarded, Events.lock_target_changed, Events.ability_started, Events.attack_clanked]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sim.clear_pending()


func _on_hit(_t: int, r: HitResult) -> void:
	hits.append(r)


func _on_died(_t: int, id: String, _k: String) -> void:
	deaths.append(id)


func _on_destroyed(_t: int, id: String, _by: String) -> void:
	destroyed.append(id)


func _on_loot(_t: int, w: String, item: String, _c: int, _r: String) -> void:
	loot.append("%s:%s" % [w, item])


func _on_lock(actor: String, target: String, reason: String) -> void:
	lock_events.append([Sim.tick, actor, target, reason])


func _on_started(_t: int, actor: String, action_id: String, _i: int) -> void:
	started.append("%s:%s" % [actor, action_id])


func _on_clank(_t: int, _a: String, _i: int, _p: Vector3) -> void:
	clanks += 1


func add_box(size: Vector3, pos: Vector3, layer := HitQueryAdapter.LAYER_WORLD) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	b.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	world.add_child(b)
	return b


func spawn_player(pos: Vector3, yaw := 0.0) -> GiantPlayer:
	var p: GiantPlayer = (load(GIANT) as PackedScene).instantiate()
	p.position = pos
	p.rotation.y = yaw
	world.add_child(p)
	p.router.use_injection = true
	p.camera_rig.yaw = yaw
	return p


func spawn_soldier(pos: Vector3, yaw := 0.0, id := "soldier_01", ai := false) -> SoldierEnemy:
	var s: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	s.entity_id = id
	s.ai_enabled = ai
	s.position = pos
	s.rotation.y = yaw
	world.add_child(s)
	return s


func spawn_dummy(pos: Vector3, id := "dummy_01") -> PracticeDummy:
	var d: PracticeDummy = (load(DUMMY) as PackedScene).instantiate()
	d.entity_id = id
	d.position = pos
	world.add_child(d)
	return d


func spawn_fence(pos: Vector3, world_id := "test.fence_01", yaw := 0.0) -> BreakableProp:
	var f: BreakableProp = (load(FENCE) as PackedScene).instantiate()
	f.world_id = world_id
	f.position = pos
	f.rotation.y = yaw
	world.add_child(f)
	return f


func hits_on(target_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits:
		if r.event.target_id == target_id:
			out.append(r)
	return out


## Yaw (Godot convention) that makes an actor at `from` face `to`.
static func yaw_towards(from: Vector3, to: Vector3) -> float:
	return TargetingRules.yaw_of(Vector3(to.x - from.x, 0.0, to.z - from.z))


## Queue a synthetic hit through the real resolution path (Sim -> CombatEntity).
func queue_hit(attacker_id: String, target_id: String, attacker_pos: Vector3, power := 10.0,
		tags := PackedStringArray(["Melee", "Parryable"]), height := 1.8) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker_id
	e.target_id = target_id
	e.power = power
	e.attacker_stat = 10.0
	e.attacker_height_m = height
	e.damage_split = {"physical": 1.0}
	e.poise_damage = 5.0
	e.tags = tags
	e.attacker_position = attacker_pos
	Sim.queue_hit(e)
