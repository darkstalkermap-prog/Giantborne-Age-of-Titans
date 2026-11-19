extends IntegrationSuite
## The EncounterDirector's leash return with the real soldier AI (moved here from
## tests/integration/test_encounter_director.gd by P53, plan M11 §1.7 rule 2: about 0.4 s of the default tier;
## unchanged): a soldier lured 60 m out of its 40 m leash walks home ignoring the giant, heals 6 s into the
## return, arrives and engages again. tests/slow/test_leash_waits.gd and the gate's test_war_camp_leash walk the
## leash's other cases; the default tier keeps the director's radii, budget, kills, clearing, LOD and alerts.
## The director test level and the helpers are test_encounter_director's (copied with the test).

const LEVEL_SCENE := "res://scenes/test/director_test.tscn"
const WOLVES := "encounter.director_test_wolves"
const SOLDIERS := "encounter.director_test_soldiers"
const BUDGET := "encounter.director_test_budget"
const WOLVES_CENTER := Vector3(-35, 0, -30)
const SOLDIERS_CENTER := Vector3(35, 0, -30)

var level: LevelRoot
var director: EncounterDirector
var player: GiantPlayer
var activated: Array[String] = []
var cleared: Array[String] = []
var leashed: Array[String] = []
var flag_events: Array[String] = []
var spawn_events: Array[String] = []
var _ai := false


func before_each() -> void:
	await super()
	activated.clear()
	cleared.clear()
	leashed.clear()
	flag_events.clear()
	spawn_events.clear()
	Events.encounter_activated.connect(_on_activated)
	Events.encounter_cleared.connect(_on_cleared)
	Events.encounter_leashed.connect(_on_leashed)
	Events.flag_changed.connect(_on_flag)


func after_each() -> void:
	for sig: Signal in [Events.encounter_activated, Events.encounter_cleared, Events.encounter_leashed,
			Events.flag_changed]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	level = null
	director = null
	player = null
	await super()


func _on_activated(_t: int, id: String) -> void:
	activated.append(id)


func _on_cleared(_t: int, id: String) -> void:
	cleared.append(id)


func _on_leashed(_t: int, enc: String, id: String) -> void:
	leashed.append("%s:%s" % [enc, id])


func _on_flag(_t: int, id: String, _v: Variant) -> void:
	flag_events.append(id)


func _on_member_spawned(_enc: String, entity_id: String, node: Node3D) -> void:
	spawn_events.append(entity_id)
	if not _ai and "ai_enabled" in node:
		node.set("ai_enabled", false)


## Instances the test level (record overrides must come first: the director reads its records
## when it is ready). ai: whether spawned members keep their AI.
func _load_level(ai := false) -> void:
	_ai = ai
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	director = level.director()
	director.member_spawned.connect(_on_member_spawned)
	player = level.player()
	player.router.use_injection = true
	await step_ticks(1)


## Frees the level and instances it again with the world state a checkpoint would carry (the
## WorldState document round trip a reload performs).
func _reload_level(ai := false) -> void:
	var doc := WorldState.to_save_dict()
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	WorldState.clear()
	assert_true(WorldState.from_save_dict(JSON.parse_string(JSON.stringify(doc))), "the world state reloads")
	await _load_level(ai)


func _teleport(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.move_velocity = Vector3.ZERO


func _spawned_count() -> int:
	var n := 0
	for c in level.get_node("Spawned").get_children():
		var e: Variant = c.get("entity")
		if e is CombatEntity and (e as CombatEntity).is_alive():
			n += 1
	return n


func _kill(entity_id: String) -> void:
	var n := director.spawned(entity_id)
	queue_hit("player", entity_id, n.global_position + Vector3(0, 0, 2), 5000.0)
	await step_ticks(1)


func _enemy(entity_id: String) -> EnemyActor:
	return director.spawned(entity_id) as EnemyActor


# --------------------------------------------------------------------------- activation


func test_leash_return_walks_home_ignoring_the_player() -> void:
	await _load_level(true)
	director.force_activate(SOLDIERS)
	await step_ticks(2)
	var s := _enemy("test.director.soldier_3")
	var home := s.home_position
	var hp_max := s.entity.combatant.pools.health_max
	queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, -2), 60.0)   # from behind
	await step_ticks(1)
	assert_true(s.entity.combatant.pools.health < hp_max, "hurt before the lure")
	# Lured 60 m out of its 40 m leash, the giant right in front of it.
	s.global_position = SOLDIERS_CENTER + Vector3(0, 0.05, 60)
	_teleport(SOLDIERS_CENTER + Vector3(0, 0.05, 64))
	director.update_now()
	assert_eq(leashed, ["%s:test.director.soldier_3" % SOLDIERS] as Array[String], "encounter_leashed")
	assert_true(s.is_returning(), "it returns")
	assert_eq(s.brain.state, EnemyBrain.AIState.RETURN, "brain state RETURN")
	assert_eq(s.brain.state_name(), "Return", "named Return")
	assert_eq(s.leash_count, 1, "one leash")
	var start_dist := s.global_position.distance_to(home)
	var attacked := false
	var aware := false
	var healed_early := false
	for i in 359:
		if i == 120:
			queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, 2), 10.0)   # it ignores even this
		await step_ticks(1)
		if i < 350 and s.entity.combatant.pools.health >= hp_max - 1e-3:
			healed_early = true
		attacked = attacked or started.any(func(x: String) -> bool: return x.begins_with(s.entity_id + ":"))
		aware = aware or s.brain.aware or s.brain.target_id != ""
		if i % 30 == 29:
			director.update_now()
	assert_false(healed_early, "not healed before 6 s")
	await step_ticks(2)
	assert_near(s.entity.combatant.pools.health, hp_max, 1e-3, "full health 6 s after the leash")
	assert_false(attacked, "no attack on the way home, though the giant stood next to it")
	assert_false(aware, "it never became aware or took a target")
	assert_true(s.is_returning(), "still on its way")
	assert_eq(leashed.size(), 1, "leashed once while it returns")
	var walked := start_dist - s.global_position.distance_to(home)
	assert_true(walked > 12.0, "it ran home (%.1f m in 6 s)" % walked)
	# Near home it arrives, and its AI resumes: it engages the giant again.
	s.global_position = home + Vector3(0, 0, 3)
	_teleport(home + Vector3(0, 0.05, -8))   # ahead of it: it arrives facing north
	var arrived: bool = await TestWait.until(self, func() -> bool: return not s.is_returning(), 120)
	assert_true(arrived, "the return ends at home")
	assert_true(s.ai_enabled, "its AI is back on")
	var engaged: bool = await TestWait.until(self, func() -> bool: return s.brain.aware, 90)
	assert_true(engaged, "back inside, it engages again")
	assert_eq(director.encounter_state(SOLDIERS), EncounterDirector.ACTIVE, "the encounter stayed active")
