extends IntegrationSuite
## The Valley walked (P10b, plan §3.11 acceptance "Valley walkable: New Game -> explore all
## districts at stage 1 except behind gates"; slow, runs with --slow):
##   * New Game loads the Valley: the giant wakes at the Cradle, the respawn point is the Hollow
##     Shrine, and a death reload puts it at that shrine's spawn point.
##   * At stage 1 every district has a small-giant path from the spawn except those behind the
##     barricade (the ruins and Kingsfall) and the Deadfall (the Barrow); the wall walks, terraces
##     and the quarry ledge are reachable for humans (archers) over their ramps.
##   * The stage-1 giant walks its navigation path from the Cradle to the Grove Shrine.
##   * The stage-3 giant walks the return leg from the causeway through the opened practice gate,
##     over the bridge and through the opened barricade to the village square.
##   * The forest encounters and the road patrol spawn from data (positions, patrol route, the
##     road patrol's flag gate).

var level: LevelRoot
var areas: Array[String] = []


func before_each() -> void:
	await super()
	level = null
	areas.clear()
	Events.area_entered.connect(_on_area_entered)


func after_each() -> void:
	if Events.area_entered.is_connected(_on_area_entered):
		Events.area_entered.disconnect(_on_area_entered)
	await super()


func _on_area_entered(_tick: int, area_id: String, _entity_id: String) -> void:
	if not areas.has(area_id):
		areas.append(area_id)


func _add_valley(no_director := true) -> LevelRoot:
	level = ValleyProbe.instance(no_director)
	world.add_child(level)
	return level


func test_new_game_starts_in_the_valley() -> void:
	assert_true(GameSession.valley_available(), "the Valley can start")
	GameSession.start_new_valley()
	assert_eq(GameSession.scene_reloads, ["new_game"] as Array[String], "New Game reloads into the Valley")
	assert_true(GameSession.is_valley() and GameSession.pending_restore, "Valley mode, pending restore")
	assert_eq(GameSession.level_scene_path(), ValleyProbe.VALLEY, "the Valley scene")
	var lv := _add_valley(false)
	var p := lv.player()
	var cradle := (lv.get_node("Spawns/PlayerSpawn") as Node3D).global_position
	GameSession.on_level_ready(lv, p)
	assert_false(GameSession.pending_restore, "restored")
	assert_eq(GameSession.respawn_id, "valley.shrine.hollow", "the respawn point is the level's start checkpoint")
	assert_eq(str(GameSession.checkpoint_doc.level), "level.valley", "the first checkpoint names the Valley")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "new_game", "taken by New Game")
	assert_near(ValleyProbe.flat(p.global_position, cradle), 0.0, 0.01, "the giant wakes at the Cradle")
	assert_eq(int(p.controller.level), 1, "a level-1 character")
	assert_eq(p.current_growth_stage(), 1, "at stage 1")
	var hollow := ValleyProbe.shrine(lv, "valley.shrine.hollow")
	var marker := GameSession.find_checkpoint("valley.shrine.hollow")
	assert_true(marker != null and marker == hollow.get_node("SpawnPoint"), "the Hollow Shrine's spawn point is the checkpoint")
	assert_eq(lv.district_at(p.global_position), "hollow", "in Giant's Hollow")
	# A death reload puts the giant at the Hollow Shrine.
	GameSession.reload_checkpoint("death")
	assert_eq(GameSession.scene_reloads.back(), "death", "the death reload reloads the scene")
	world.remove_child(lv)
	lv.free()
	var again := _add_valley(false)
	GameSession.on_level_ready(again, again.player())
	var spawn := (ValleyProbe.shrine(again, "valley.shrine.hollow").get_node("SpawnPoint") as Node3D).global_position
	assert_near(ValleyProbe.flat(again.player().global_position, spawn), 0.0, 0.01, "the giant respawns at the Hollow Shrine")


func test_stage_1_reaches_every_district_but_those_behind_gates() -> void:
	var lv := _add_valley()
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var spawn := (lv.get_node("Spawns/PlayerSpawn") as Node3D).global_position
	var open_districts := [["hollow", Vector3(-115, 0, 155)], ["forest", Vector3(-90, 0, -35)],
		["forest", Vector3(-30, 0, -104)], ["village", Vector3(35, 0, -40)], ["village", Vector3(40, 0, 55)],
		["village", Vector3(60, 0, -70)], ["village", Vector3(-15, 0, 0)], ["quarry", Vector3(30, 0, -154)],
		["quarry", Vector3(18, 5, -164)]]
	for e: Array in open_districts:
		assert_eq(lv.district_at(e[1]), e[0], "%s lies in %s" % [e[1], e[0]])
		assert_true(ValleyProbe.reaches(lv, spawn, e[1], ValleyProbe.SMALL_GIANT),
			"stage 1 walks from the Cradle to %s in %s" % [e[1], e[0]])
	var behind := [["barrow", Vector3(-55, 0, -160)], ["ruins", Vector3(158, 0, -50)], ["ruins", Vector3(118, 0, -20)],
		["kingsfall", Vector3(150, 0, 48.5)], ["kingsfall", Vector3(150, 0, 135)]]
	for e: Array in behind:
		assert_false(ValleyProbe.reaches(lv, spawn, e[1], ValleyProbe.SMALL_GIANT),
			"%s in %s is behind a gate" % [e[1], e[0]])
	await ValleyProbe.set_links(self, lv, true)
	for e: Array in behind:
		var ok: bool = await ValleyProbe.settle(self, lv, spawn, e[1], ValleyProbe.SMALL_GIANT, true)
		assert_true(ok, "with the gates open stage 1 reaches %s in %s" % [e[1], e[0]])
	# Archers' perches: the wall walks and terraces over their ramps; the tower top is its own island.
	var from := Vector3(158, 0, -50)
	for perch: String in ["valley.marker.ruins_wall_w", "valley.marker.ruins_wall_e", "valley.marker.ruins_gate_wall"]:
		var at := lv.marker(perch).global_position
		var ok: bool = await ValleyProbe.settle(self, lv, from, at, ValleyProbe.HUMAN, true)
		assert_true(ok, "a human walks up to %s" % perch)
	var ledge := lv.marker("valley.marker.quarry_ledge").global_position
	assert_true(ValleyProbe.reaches(lv, Vector3(40, 0, -140), ledge, ValleyProbe.HUMAN), "and up to the quarry ledge")
	var tower := lv.marker("valley.marker.tower").global_position
	var on_tower := NavigationServer3D.region_get_closest_point(lv.nav_region(ValleyProbe.HUMAN), tower)
	assert_true(ValleyProbe.flat(on_tower, tower) < 0.5 and on_tower.y > 5.5, "the watchtower top carries navmesh (%s)" % on_tower)
	assert_false(ValleyProbe.reaches(lv, Vector3(60, 0, -20), tower, ValleyProbe.HUMAN), "but no path climbs it")


func test_walk_from_the_cradle_to_the_grove() -> void:
	var lv := _add_valley()
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var p := lv.player()
	p.router.use_injection = true
	assert_eq(int(p.profile.get("nav_layers", 0)), ValleyProbe.SMALL_GIANT, "stage 1 paths on the small-giant layer")
	var grove := ValleyProbe.shrine(lv, "valley.shrine.grove").growth_pad_position()
	var route := ValleyProbe.path(lv, p.global_position, grove, ValleyProbe.SMALL_GIANT)
	assert_true(route.size() > 2, "a path to the Grove (%d points)" % route.size())
	var r: Dictionary = await ValleyProbe.walk(self, p, route)
	print("    valley: the stage-1 giant walked from the Cradle to the Grove in %.1f s (%d waypoints)" % [
		int(r.ticks) / 60.0, r.total])
	assert_eq(r.reached, r.total, "every waypoint reached (stuck at %s)" % r.stuck_at)
	assert_true(ValleyProbe.flat(p.global_position, grove) < 2.0, "at the Grove Shrine's pad (%s)" % p.global_position)
	assert_true(p.global_position.y > -0.5, "never fell through the ground")
	assert_eq(lv.district_at(p.global_position), "forest", "in the Old Wood")
	for id: String in ["valley.area.forest_edge", "valley.area.grove"]:
		assert_true(areas.has(id), "the walk entered %s (entered: %s)" % [id, areas])


func test_stage_3_walks_the_return_leg() -> void:
	var lv := _add_valley()
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var p := lv.player()
	p.router.use_injection = true
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, PI), Vector3(155, 0.05, 25)))
	await step_ticks(2)
	assert_true(bool(p.growth.debug_set_stage(3).ok), "the giant grows to stage 3 at the causeway")
	await step_ticks(30)
	assert_eq(int(p.profile.get("nav_layers", 0)), ValleyProbe.GIANT, "stage 3 paths on the giant layer")
	for id: String in ["valley.ruins.practice_gate", "valley.village.barricade"]:
		assert_true((ValleyProbe.prop(lv, id) as BreakableProp).force_open("test"), "%s opens" % id)
	await ValleyProbe.wait_for_map_update(self, lv)
	var square := Vector3(45, 0, -20)
	var ok: bool = await ValleyProbe.settle(self, lv, p.global_position, square, ValleyProbe.GIANT, true)
	assert_true(ok, "a giant path from the causeway to the village square")
	var route := ValleyProbe.path(lv, p.global_position, square, ValleyProbe.GIANT)
	var r: Dictionary = await ValleyProbe.walk(self, p, route)
	print("    valley: the stage-3 giant walked from the causeway to the square in %.1f s (%d waypoints)" % [
		int(r.ticks) / 60.0, r.total])
	assert_eq(r.reached, r.total, "every waypoint reached (stuck at %s)" % r.stuck_at)
	assert_true(ValleyProbe.flat(p.global_position, square) < 2.0, "in the square (%s)" % p.global_position)
	assert_eq(lv.district_at(p.global_position), "village", "back in Thornwick")
	for id: String in ["valley.area.causeway", "valley.area.ruins_approach"]:
		assert_true(areas.has(id), "the return leg entered %s (entered: %s)" % [id, areas])


func test_forest_encounters_spawn_from_data() -> void:
	var lv := _add_valley(false)
	await step_ticks(2)
	var d := lv.director()
	assert_true(d != null, "the EncounterDirector")
	for id: String in ["encounter.forest_wolves_a", "encounter.forest_hunters", "encounter.road_patrol"]:
		assert_eq(d.encounter_state(id), EncounterDirector.DORMANT, "%s waits" % id)
	assert_eq(d.max_active_enemies, 12, "the level's budget")
	var p := lv.player()
	GameSession.place_player(p, Transform3D(Basis(), Vector3(-128, 0.05, 45)))
	await step_ticks(1)
	d.update_now()
	assert_eq(d.encounter_state("encounter.forest_wolves_a"), EncounterDirector.ACTIVE, "wolves A activate")
	assert_eq(d.encounter_state("encounter.forest_hunters"), EncounterDirector.ACTIVE, "the hunters activate")
	var expected := {
		"valley.forest.wolf_a1": [Vector3(-150, 0, 50), "enemy.wolf"],
		"valley.forest.wolf_a2": [Vector3(-136, 0, 48), "enemy.wolf"],
		"valley.forest.wolf_a3": [Vector3(-145, 0, 62), "enemy.wolf"],
		"valley.forest.hunter_1": [Vector3(-125, 0, 5), "enemy.soldier"],
		"valley.forest.hunter_2": [Vector3(-114, 0, 4), "enemy.soldier"],
		"valley.forest.hunter_wolf": [Vector3(-118, 0, 16), "enemy.wolf"]}
	for id: String in expected:
		var n := d.spawned(id)
		assert_true(n != null, "%s spawned" % id)
		if n == null:
			continue
		assert_near(ValleyProbe.flat(n.global_position, expected[id][0]), 0.0, 0.05, "%s at its data position" % id)
		assert_eq(str((n.get_node("CombatEntity") as CombatEntity).definition_id), str(expected[id][1]), "%s is %s" % [id, expected[id][1]])
		var on_mesh := NavigationServer3D.region_get_closest_point(lv.nav_region(ValleyProbe.HUMAN), n.global_position)
		assert_true(ValleyProbe.flat(on_mesh, n.global_position) < 0.5, "%s stands on the human navmesh" % id)
	var wolf := d.spawned("valley.forest.wolf_a1")
	if wolf != null:
		var route := wolf.get_node_or_null(wolf.get("patrol_route")) as Node3D
		assert_true(route != null and route == lv.patrol_route("valley.patrol.wolves_a"), "wolf A1 patrols valley.patrol.wolves_a")
		assert_eq(route.get_child_count() if route != null else 0, 4, "four patrol points")
	assert_eq(d.active_combatant_count(), 6, "six combatants")
	# The road patrol waits for the Grove's reward.
	GameSession.place_player(p, Transform3D(Basis(), Vector3(-8, 0.05, -20)))
	await step_ticks(1)
	d.update_now()
	assert_eq(d.encounter_state("encounter.road_patrol"), EncounterDirector.DORMANT, "the road patrol needs reward.main.grove")
	WorldState.set_flag("reward.main.grove", true)
	d.update_now()
	assert_eq(d.encounter_state("encounter.road_patrol"), EncounterDirector.ACTIVE, "with it, the road patrol activates")
	for id: String in ["valley.village.road_soldier_1", "valley.village.road_soldier_2", "valley.village.road_mage"]:
		assert_true(d.spawned(id) != null, "%s spawned" % id)
	var mage := d.spawned("valley.village.road_mage")
	if mage != null:
		assert_eq(str((mage.get_node("CombatEntity") as CombatEntity).definition_id), "enemy.mage", "the first mage")
	var soldier := d.spawned("valley.village.road_soldier_1")
	if soldier != null:
		assert_eq(soldier.get_node_or_null(soldier.get("patrol_route")), lv.patrol_route("valley.patrol.road"),
			"soldier 1 walks valley.patrol.road")
	var posts := 0
	for m in get_tree().get_nodes_in_group("ai_formation_points"):
		if lv.is_ancestor_of(m) and str((m as LevelMarker).marker_id).begins_with("valley.marker.road_line"):
			posts += 1
	assert_eq(posts, 2, "the road_line formation markers")
	assert_true(d.active_combatant_count() <= 12, "within the budget")
