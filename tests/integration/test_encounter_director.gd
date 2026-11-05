extends IntegrationSuite
## P10a: the EncounterDirector on the director test level (scenes/test/director_test.tscn;
## data/world/*director_test*.json): activation and deactivation radii, the budget of 12 with
## 14 (and 20) members requested, kill persistence through a reload, clearing (routed members
## count) with its flag and event once, the leash return, LOD tiers by distance, spawn
## properties and the patrol route, despawn and re-activation, flag gates and alert groups.
##
## Most tests spawn with the AI off (member_spawned) so nothing but the director moves; the
## leash test runs the real soldier AI.

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

func test_activation_and_deactivation_radii() -> void:
	await _load_level()
	await step_ticks(31)   # the first checks ran with the player at the start, far from both camps
	for id in [WOLVES, SOLDIERS, BUDGET]:
		assert_eq(director.encounter_state(id), EncounterDirector.DORMANT, "%s starts dormant" % id)
	assert_eq(_spawned_count(), 0, "nothing spawned at the start")
	_teleport(Vector3(-35, 0.05, 0))   # 30 m from the wolves' centre (activate radius 25)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.DORMANT, "30 m: still dormant")
	_teleport(Vector3(-35, 0.05, -8))   # 22 m
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "22 m: active")
	assert_eq(activated, [WOLVES] as Array[String], "encounter_activated once")
	assert_eq(_spawned_count(), 3, "the three wolves spawned")
	var w1 := _enemy("test.director.wolf_1")
	assert_true(w1 != null and w1.is_inside_tree(), "wolf_1 is in the world")
	assert_true(w1.home_position.distance_to(Vector3(-38, EncounterDirector.SPAWN_LIFT_M, -28)) < 1e-3,
		"its home is its data position (%s)" % w1.home_position)
	assert_eq(director.unaware_deactivate_s, EncounterDirector.UNAWARE_DEACTIVATE_S, "10 s by default")
	assert_eq(EncounterDirector.UNAWARE_DEACTIVATE_S, 10.0, "the plan's 10 s")
	director.unaware_deactivate_s = 1.0   # keep the test short; the rule is the same
	_teleport(Vector3(-35, 0.05, 25))   # 55 m: beyond the deactivate radius (50)
	await step_ticks(20)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE,
		"beyond the radius but less than the grace since the last awareness: still active")
	await step_ticks(45)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.DORMANT, "then it deactivates")
	assert_eq(director.spawned("test.director.wolf_1"), null, "its members are gone")
	assert_false(is_instance_valid(w1) and w1.is_inside_tree(), "the node left the tree")
	assert_false(WorldState.is_killed("test.director.wolf_1"), "freed, not killed")
	assert_eq(director.member_status("test.director.wolf_1"), EncounterDirector.UNSPAWNED, "waiting again")
	# Back in range: they return at home and at full health; an aware member keeps it active.
	_teleport(Vector3(-35, 0.05, -8))
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "re-activated")
	assert_eq(activated.size(), 2, "a second encounter_activated")
	assert_eq(director.spawn_count("test.director.wolf_1"), 2, "wolf_1 spawned a second time")
	var again := _enemy("test.director.wolf_1")
	assert_true(again != w1, "a new instance")
	assert_near(again.entity.combatant.pools.health, again.entity.combatant.pools.health_max, 1e-3, "at full health")
	again.brain.aware = true
	_teleport(Vector3(-35, 0.05, 25))
	await step_ticks(70)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "an aware member keeps it active")
	for id in director.members_of(WOLVES):
		(_enemy(id).brain as EnemyBrain).aware = false
	await step_ticks(70)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.DORMANT, "unaware for the grace: dormant")


func test_flags_gate_activation() -> void:
	TestFixtures.record_override(WOLVES, {"requires_flags": ["test.director.gate_open"],
		"forbids_flags": ["test.director.gate_shut"]})
	await _load_level()
	_teleport(Vector3(-35, 0.05, -10))
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.DORMANT, "a required flag is missing")
	WorldState.set_flag("test.director.gate_open", true)
	WorldState.set_flag("test.director.gate_shut", true)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.DORMANT, "a forbidden flag is set")
	WorldState.set_flag("test.director.gate_shut", false)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "both satisfied: active")
	assert_true(EncounterDirector.flags_allow({"requires_flags": [], "forbids_flags": []}), "no flags: allowed")


# --------------------------------------------------------------------------- budget

func test_budget_never_exceeds_twelve() -> void:
	await _load_level()
	assert_eq(director.max_active_enemies, 12, "the level record's budget")
	for id in [BUDGET, SOLDIERS, WOLVES]:
		director.force_activate(id)
	var peak := 0
	for i in 3:
		await step_ticks(1)
		peak = maxi(peak, director.active_combatant_count())
	assert_eq(director.active_combatant_count(), 12, "20 members requested, 12 alive")
	assert_eq(_spawned_count(), 12, "and 12 in the world")
	for id in [BUDGET, SOLDIERS, WOLVES]:
		assert_eq(director.encounter_state(id), EncounterDirector.ACTIVE, "%s active (forced)" % id)
	assert_eq(director.member_status("test.director.budget_s5"), EncounterDirector.SPAWNED,
		"the budget encounter (first by id) filled the twelve")
	assert_eq(director.member_status("test.director.budget_s6"), EncounterDirector.UNSPAWNED,
		"its 13th member waits")
	assert_eq(director.member_status("test.director.budget_s7"), EncounterDirector.UNSPAWNED, "and its 14th")
	assert_eq(director.member_status("test.director.soldier_1"), EncounterDirector.UNSPAWNED, "the soldiers wait")
	for id in ["test.director.budget_w1", "test.director.budget_w2", "test.director.budget_w3"]:
		await _kill(id)
		peak = maxi(peak, director.active_combatant_count())
	assert_eq(director.active_combatant_count(), 9, "three died")
	for i in 31:
		await step_ticks(1)
		peak = maxi(peak, director.active_combatant_count())
	assert_eq(director.active_combatant_count(), 12, "the next check filled the budget again")
	assert_eq(director.member_status("test.director.budget_s6"), EncounterDirector.SPAWNED, "the 13th spawned")
	assert_eq(director.member_status("test.director.budget_s7"), EncounterDirector.SPAWNED, "the 14th too")
	assert_eq(director.member_status("test.director.budget_w1"), EncounterDirector.DEAD, "the dead stay dead")
	assert_eq(director.member_status("test.director.soldier_1"), EncounterDirector.SPAWNED,
		"the next encounter got the rest of the room")
	assert_eq(director.member_status("test.director.soldier_2"), EncounterDirector.UNSPAWNED, "and no more")
	assert_true(peak <= 12 and director.peak_active <= 12, "never more than 12 alive (peak %d / %d)" % [
		peak, director.peak_active])
	assert_eq(director.peak_active, 12, "the budget was full")


func test_members_outside_the_budget_do_not_count() -> void:
	TestFixtures.record_override(WOLVES, {"counts_toward_budget": false})
	await _load_level()
	director.force_activate(BUDGET)
	director.force_activate(WOLVES)
	await step_ticks(2)
	assert_eq(director.active_combatant_count(), 12, "the budgeted members fill the twelve")
	assert_eq(_spawned_count(), 15, "the three unbudgeted wolves spawned beyond it")
	assert_eq(director.member_status("test.director.wolf_3"), EncounterDirector.SPAWNED, "wolf_3 is up")


# --------------------------------------------------------------------------- kills, clearing

func test_kills_persist_and_cleared_encounters_stay_cleared() -> void:
	TestFixtures.record_override("level.director_test", {"lod": {"corpse_free_s": 0.25}})
	await _load_level()
	assert_near(director.corpse_free_s, 0.25, 1e-6, "corpse_free_s comes from the level record")
	director.force_activate(WOLVES)
	await step_ticks(1)
	var corpse := _enemy("test.director.wolf_1")
	await _kill("test.director.wolf_1")
	assert_true(WorldState.is_killed("test.director.wolf_1"), "the kill is a world delta")
	assert_eq(director.member_status("test.director.wolf_1"), EncounterDirector.DEAD, "dead")
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "two left: not cleared")
	assert_true(director.spawned("test.director.wolf_1") == corpse, "the corpse is still there")
	await step_ticks(31)
	assert_eq(director.spawned("test.director.wolf_1"), null, "the corpse was freed after corpse_free_s")
	# Reload: the killed wolf never spawns again.
	await _reload_level()
	director.force_activate(WOLVES)
	await step_ticks(1)
	assert_eq(director.member_status("test.director.wolf_1"), EncounterDirector.DEAD, "still dead after a reload")
	assert_eq(director.spawned("test.director.wolf_1"), null, "not spawned")
	assert_eq(_spawned_count(), 2, "the other two are back")
	# A routed member counts toward clearing.
	var w2 := _enemy("test.director.wolf_2")
	w2.brain.state = EnemyBrain.AIState.ROUTED
	w2.brain.routed.emit()
	assert_true(w2.is_routed(), "wolf_2 routed")
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "one wolf still fights")
	assert_eq(director.active_combatant_count(), 1, "a routed member no longer counts as a combatant")
	await _kill("test.director.wolf_3")
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.CLEARED, "dead or routed: cleared")
	assert_eq(cleared, [WOLVES] as Array[String], "encounter_cleared once")
	var flag := "encounter.director_test_wolves.cleared"
	assert_eq(EncounterDirector.cleared_flag(WOLVES), flag, "the flag id")
	assert_eq(WorldState.get_flag(flag), true, "the cleared flag is set")
	await _kill("test.director.wolf_2")   # the routed survivor dies later: nothing more
	director.update_now()
	assert_eq(cleared.size(), 1, "still once")
	assert_eq(flag_events.count(flag), 1, "the flag changed once")
	# A cleared encounter never activates again, even forced and after a reload.
	await _reload_level()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.CLEARED, "cleared at load (its flag)")
	_teleport(Vector3(-35, 0.05, -20))
	director.force_activate(WOLVES)
	await step_ticks(2)
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.CLEARED, "never activates again")
	assert_eq(_spawned_count(), 0, "nothing spawned")
	assert_eq(cleared.size(), 1, "and no second encounter_cleared")


# --------------------------------------------------------------------------- with the real AI

func test_spawned_wolves_engage_and_their_deaths_clear_the_encounter() -> void:
	await _load_level(true)
	_teleport(WOLVES_CENTER + Vector3(0, 0.05, 18))   # in front of the pack, inside its radius
	player.facing_yaw = 0.0
	director.update_now()
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "the player walked in")
	var attacking: bool = await TestWait.until(self, func() -> bool:
		return started.any(func(x: String) -> bool: return x.begins_with("test.director.wolf_")), 240)
	assert_true(attacking, "the spawned wolves notice the giant and attack")
	for id in director.members_of(WOLVES):
		assert_true(_enemy(id).brain.aware, "%s is aware (seen or shared)" % id)
	var lines := director.debug_lines()
	assert_true(lines.size() >= 2 and lines[0].begins_with("DIRECTOR level.director_test  combatants 3/12"),
		"the F3 line (%s)" % lines[0])
	assert_true(lines[1].contains(WOLVES), "and the active encounter's line")
	for id in director.members_of(WOLVES):
		await _kill(id)
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.CLEARED, "all dead: cleared")
	assert_eq(cleared, [WOLVES] as Array[String], "encounter_cleared once")


# --------------------------------------------------------------------------- leash

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


# --------------------------------------------------------------------------- LOD

func test_lod_tiers_follow_the_distance() -> void:
	await _load_level()
	_teleport(Vector3(-35, 0.05, -8))
	director.update_now()
	var wolves: Array[EnemyActor] = []
	for id in director.members_of(WOLVES):
		wolves.append(_enemy(id))
	for spec: Array in [[Vector3(-35, 0.05, -5), 0], [Vector3(-35, 0.05, 30), 1], [Vector3(55, 0.05, 55), 2]]:
		_teleport(spec[0])
		director.update_now()
		for w in wolves:
			var d := w.global_position.distance_to(player.global_position)
			assert_eq(w.lod_tier, spec[1], "%s at %.0f m: tier %d" % [w.entity_id, d, spec[1]])
	for w in wolves:
		assert_false(w.can_process(), "%s: tier 2 is dormant (can_process false)" % w.entity_id)
		assert_true((w.get_node("Visual/LodProxy") as Node3D).visible, "%s shows its proxy" % w.entity_id)
	wolves[0].brain.aware = true
	await step_ticks(1)
	director.update_now()
	for w in wolves:
		assert_eq(w.lod_tier, 0, "%s: engaged (the alert group shares awareness) keeps tier 0" % w.entity_id)
		assert_true(w.can_process(), "%s processes again" % w.entity_id)
	# A held body (P07) keeps its tier and stays out of the simulation until it is released.
	for w in wolves:
		w.brain.aware = false
	var held := wolves[2]
	assert_true(held.controller.enter_grabbed("player"), "grabbed")
	held.on_grabbed("player")
	_teleport(Vector3(-35, 0.05, 30))
	director.update_now()
	assert_eq(wolves[0].lod_tier, 1, "a free wolf drops to tier 1")
	assert_eq(held.lod_tier, 0, "the held one keeps its tier")
	assert_false(held.can_process(), "and stays out of the simulation")
	held.on_released("dropped")
	director.update_now()
	assert_eq(held.lod_tier, 1, "released, it follows the distance again")
	assert_eq(director.lod_tier_for(Vector3.ZERO, Vector3(0, 0, 40), false), 0, "40 m: tier 0")
	assert_eq(director.lod_tier_for(Vector3.ZERO, Vector3(0, 0, 40.5), false), 1, "just beyond: tier 1")
	assert_eq(director.lod_tier_for(Vector3.ZERO, Vector3(0, 0, 90.5), false), 2, "beyond 90 m: tier 2")
	assert_eq(director.lod_tier_for(Vector3.ZERO, Vector3(0, 0, 200), true), 0, "engaged: tier 0")


# --------------------------------------------------------------------------- spawning

func test_spawned_members_carry_their_data_and_patrol_route() -> void:
	await _load_level()
	director.force_activate(SOLDIERS)
	await step_ticks(2)
	assert_eq(spawn_events.size(), 3, "member_spawned for each soldier")
	var s1 := _enemy("test.director.soldier_1")
	var s2 := _enemy("test.director.soldier_2")
	assert_true(s1 is SoldierEnemy, "the definition's scene (enemy.soldier)")
	assert_true(s1.get_parent() == level.get_node("Spawned"), "under LevelRoot/Spawned")
	assert_eq(s1.entity_id, "test.director.soldier_1", "entity id from the data")
	assert_true(Sim.get_entity("test.director.soldier_1") == s1.entity, "registered under it")
	assert_eq(s1.entity.definition_id, "enemy.soldier", "definition id")
	assert_eq(s1.encounter_id, SOLDIERS, "encounter id")
	assert_true(s1.persist_death, "persist_death")
	assert_false(s1.commander, "soldier_1 is no commander")
	assert_true(s2.commander, "soldier_2 is the commander")
	assert_eq(s1.loot_table, "", "loot table (the record's own)")
	assert_true(s1.ai_enabled == false, "the test turned its AI off after the spawn")
	assert_near(absf(s1.rotation.y), PI, 1e-3, "yaw 180")
	assert_true(s1.patrol_route.is_absolute(), "patrol_route is an absolute path (%s)" % s1.patrol_route)
	var route := level.patrol_route("test.patrol.soldiers")
	assert_true(route != null and s1.get_node(s1.patrol_route) == route, "it resolves to Markers/Patrol/<route>")
	assert_eq(s1.brain.patrol_points.size(), 3, "it collected the three route points")
	for i in route.get_child_count():
		assert_true(s1.brain.patrol_points[i].distance_to((route.get_child(i) as Node3D).global_position) < 1e-3,
			"point %d" % (i + 1))
	assert_eq(s2.brain.patrol_points.size(), 0, "soldier_2 has no patrol")
	assert_true(s1.nav_region_for_layers() == level.nav_region(1), "flee points snap to the level's human region")


func test_despawn_then_reactivation_respawns_at_home() -> void:
	await _load_level()
	director.force_activate(WOLVES)
	await step_ticks(2)
	var w := _enemy("test.director.wolf_2")
	var home := w.home_position
	w.global_position = home + Vector3(6, 0, 4)
	queue_hit("player", w.entity_id, w.global_position + Vector3(0, 0, 2), 30.0)
	await step_ticks(1)
	director.despawn("test.director.wolf_2")
	assert_eq(director.member_status("test.director.wolf_2"), EncounterDirector.DESPAWNED, "despawned")
	assert_eq(director.spawned("test.director.wolf_2"), null, "no longer listed")
	await get_tree().process_frame
	assert_false(is_instance_valid(w) and w.is_inside_tree(), "the node left the tree")
	assert_false(WorldState.is_killed("test.director.wolf_2"), "no kill recorded")
	await _kill("test.director.wolf_1")
	await _kill("test.director.wolf_3")
	assert_eq(director.encounter_state(WOLVES), EncounterDirector.ACTIVE, "a despawned member is no kill: not cleared")
	await step_ticks(31)
	assert_eq(director.member_status("test.director.wolf_2"), EncounterDirector.DESPAWNED,
		"it waits for the next activation")
	director.force_activate(WOLVES)
	await step_ticks(1)
	var back := _enemy("test.director.wolf_2")
	assert_true(back != null and back != w, "it is back (a new instance)")
	assert_true(back.global_position.distance_to(home) < 0.2, "at home (%s)" % back.global_position)
	assert_near(back.entity.combatant.pools.health, back.entity.combatant.pools.health_max, 1e-3, "at full health")
	assert_eq(director.spawn_count("test.director.wolf_2"), 2, "spawned twice")


# --------------------------------------------------------------------------- alert groups

func test_alert_groups_share_awareness() -> void:
	TestFixtures.record_override(SOLDIERS, {"alert_group": false})
	await _load_level()
	director.force_activate(WOLVES)
	director.force_activate(SOLDIERS)
	await step_ticks(2)
	var w1 := _enemy("test.director.wolf_1")
	w1.brain.aware = true
	w1.brain.target_id = "player"
	w1.brain.last_known = Vector3(-30, 0, -10)
	await step_ticks(1)
	for id in ["test.director.wolf_2", "test.director.wolf_3"]:
		var b := _enemy(id).brain
		assert_true(b.aware, "%s learned of the giant from its pack" % id)
		assert_true(b.last_known.distance_to(Vector3(-30, 0, -10)) < 1e-3, "%s knows what wolf_1 knows" % id)
		assert_eq(b.target_id, "player", "%s targets the giant" % id)
	var s1 := _enemy("test.director.soldier_1")
	s1.brain.aware = true
	s1.brain.target_id = "player"
	await step_ticks(2)
	assert_false(_enemy("test.director.soldier_2").brain.aware, "no alert group: the others stay unaware")
