extends IntegrationSuite
## P10a: LevelRoot lookups (markers, checkpoints, areas, patrol routes, districts, player,
## navigation map and regions), LevelMarker groups by kind, AreaTrigger events for the player
## only (and `once`), and the offline-baked human navigation of the director test level.

const LEVEL_SCENE := "res://scenes/test/director_test.tscn"

var level: LevelRoot
var player: GiantPlayer
var area_events: Array[String] = []


func before_each() -> void:
	await super()
	area_events.clear()
	Events.area_entered.connect(_on_entered)
	Events.area_exited.connect(_on_exited)


func after_each() -> void:
	for sig: Signal in [Events.area_entered, Events.area_exited]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	level = null
	player = null
	await super()


func _on_entered(_t: int, area_id: String, entity_id: String) -> void:
	area_events.append("in:%s:%s" % [area_id, entity_id])


func _on_exited(_t: int, area_id: String, entity_id: String) -> void:
	area_events.append("out:%s:%s" % [area_id, entity_id])


func _load_level() -> void:
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	player = level.player()
	player.router.use_injection = true
	await step_ticks(1)


func _teleport(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.move_velocity = Vector3.ZERO


# --------------------------------------------------------------------------- lookups

func test_lookups() -> void:
	await _load_level()
	assert_true(get_tree().get_nodes_in_group(LevelRoot.GROUP).has(level), "group level_root")
	assert_eq(level.level_id, "level.director_test", "level id")
	assert_eq(str(level.level_record().get("start_checkpoint")), "test.director.cp_start", "its record")
	var wolves := level.marker("test.marker.wolves") as LevelMarker
	assert_true(wolves != null and wolves.kind == LevelMarker.Kind.OBJECTIVE, "objective marker by id")
	assert_true(get_tree().get_nodes_in_group("objective_markers").has(wolves), "in objective_markers")
	assert_eq(level.marker("test.marker.nope"), null, "an unknown marker is null")
	var formation := get_tree().get_nodes_in_group("ai_formation_points")
	assert_eq(formation.size(), 3, "three formation posts in ai_formation_points")
	for spec: Array in [["test.marker.cover_1", "ai_cover_points"], ["test.marker.safe_1", "safe_markers"],
			["test.marker.bot_1", "bot_route_points"], ["test.marker.formation_2", "ai_formation_points"]]:
		var m := level.marker(spec[0])
		assert_true(m != null and m.is_in_group(spec[1]) and m.is_in_group(LevelMarker.GROUP),
			"%s is in %s" % spec)
	assert_eq(LevelMarker.group_for(LevelMarker.Kind.ELEVATION), "ai_elevation_points", "elevation group")
	assert_eq(LevelMarker.group_for(LevelMarker.Kind.PATROL), "patrol_points", "patrol group")
	var cp := level.checkpoint("test.director.cp_start")
	assert_true(cp is CheckpointMarker and cp.global_position.distance_to(Vector3(0, 0.05, 50)) < 1e-3,
		"checkpoint by id")
	var den := level.area("test.area.wolf_den")
	assert_true(den != null and not den.once, "area by id")
	assert_true(level.area("test.area.camp").once, "the camp trigger reports one visit")
	assert_eq(den.collision_layer, 0, "triggers sit on no layer")
	assert_eq(den.collision_mask, 2, "and watch the actors layer")
	var route := level.patrol_route("test.patrol.soldiers")
	assert_true(route != null and route.get_child_count() == 3, "the patrol route and its three points")
	assert_eq(route.get_path(), level.get_node("Markers/Patrol/test_patrol_soldiers").get_path(),
		"Markers/Patrol/<route id with dots as underscores>")
	assert_eq(level.patrol_route("test.patrol.nope"), null, "an unknown route is null")
	assert_eq(level.district_at(Vector3(-30, 0, 10)), "west", "west half")
	assert_eq(level.district_at(Vector3(30, 0, -50)), "east", "east half")
	assert_eq(level.district_at(Vector3(0, 0, 100)), "", "outside every district")
	assert_true(level.player() == level.get_node("Player"), "its player")
	assert_eq(level.nav_map(), level.get_world_3d().navigation_map, "the world's navigation map")
	assert_eq(level.nav_region(1), (level.get_node("Navigation/Human") as NavigationRegion3D).get_rid(),
		"nav layer 1: Navigation/Human")
	assert_false(level.nav_region(2).is_valid(), "no large-layer region in this level")
	assert_true(ProjectileSystem.parent_for(get_tree()) == level, "projectiles live under the level root")
	assert_true(level.spawn_parent() == level.get_node("Spawned"), "Spawned")
	assert_true(level.director() is EncounterDirector, "its director")
	assert_true(get_tree().get_nodes_in_group(EncounterDirector.GROUP).has(level.director()), "group encounter_director")
	# Nodes added later are found (the lookup is rebuilt on a miss); a kind change moves groups.
	var late := LevelMarker.new()
	late.marker_id = "test.marker.late"
	late.kind = LevelMarker.Kind.SAFE
	level.get_node("Markers").add_child(late)
	assert_true(level.marker("test.marker.late") == late, "a marker added later is found")
	late.kind = LevelMarker.Kind.ELEVATION
	assert_true(late.is_in_group("ai_elevation_points") and not late.is_in_group("safe_markers"),
		"changing the kind moves it to the new group")


func test_navigation_is_baked_offline_and_paths() -> void:
	await _load_level()
	var region := level.get_node("Navigation/Human") as NavigationRegion3D
	assert_true(region.navigation_mesh.get_polygon_count() > 0, "the scene carries a baked navmesh")
	assert_eq(region.navigation_layers, 1, "on the human layer")
	assert_near(region.navigation_mesh.cell_size, 0.3, 1e-6, "cell 0.3 m (plan §2.2)")
	assert_near(region.navigation_mesh.agent_radius, 0.6, 1e-6, "agent radius 0.6 m")
	var map := level.nav_map()
	var synced: bool = await TestWait.until(self, func() -> bool:
		return NavigationServer3D.map_get_iteration_id(map) > 0 \
			and not NavigationServer3D.map_get_path(map, Vector3(-40, 0, 40), Vector3(40, 0, -40), true, 1).is_empty(), 120)
	assert_true(synced, "the map synchronises without a bake")
	assert_false(region.is_baking(), "nothing bakes at runtime")
	var path := NavigationServer3D.map_get_path(map, Vector3(-40, 0, 40), Vector3(40, 0, -40), true, 1)
	assert_true(path.size() >= 2 and Vector2(path[-1].x - 40, path[-1].z + 40).length() < 1.0,
		"a path across the level on layer 1 (%d points)" % path.size())
	var around := NavigationServer3D.map_get_path(map, Vector3(20, 0, -6), Vector3(20, 0, 6), true, 1)
	var detour := 0.0
	for i in range(1, around.size()):
		detour += around[i].distance_to(around[i - 1])
	assert_true(detour > 12.5, "paths go round the pillar (%.1f m for 12 m)" % detour)
	var near_pillar := NavigationServer3D.region_get_closest_point(level.nav_region(1), Vector3(20.5, 0, 0.5))
	assert_true(absf(near_pillar.x - 20.0) >= 2.0 or absf(near_pillar.z) >= 2.0,
		"the pillar and its margin are cut out (%s)" % near_pillar)


# --------------------------------------------------------------------------- triggers

func test_area_triggers_report_the_player_only() -> void:
	await _load_level()
	var den := level.area("test.area.wolf_den")
	await step_ticks(3)
	assert_false(den.player_inside, "the player starts outside the den")
	assert_eq(area_events.size(), 0, "no event at the start")
	_teleport(Vector3(-35, 0.05, -25))
	var inside: bool = await TestWait.until(self, func() -> bool: return den.player_inside, 6)
	assert_true(inside, "player_inside once it walks in")
	await step_ticks(1)
	assert_eq(area_events, ["in:test.area.wolf_den:player"] as Array[String], "area_entered for the player")
	# Enemies in the area are no event: the wolves spawn inside the den.
	level.director().force_activate("encounter.director_test_wolves")
	await step_ticks(4)
	assert_eq(level.director().encounter_state("encounter.director_test_wolves"), "active", "wolves in the den")
	assert_eq(area_events.size(), 1, "their bodies entering the trigger are no event")
	_teleport(Vector3(-35, 0.05, 20))
	await step_ticks(3)
	assert_false(den.player_inside, "outside again")
	assert_eq(area_events, ["in:test.area.wolf_den:player", "out:test.area.wolf_den:player"] as Array[String],
		"area_exited")
	_teleport(Vector3(-35, 0.05, -25))
	await step_ticks(3)
	assert_eq(den.entered_count, 2, "an ordinary trigger reports every visit")


func test_a_once_trigger_reports_the_first_visit_only() -> void:
	await _load_level()
	var camp := level.area("test.area.camp")
	for i in 2:
		_teleport(Vector3(35, 0.05, -30))
		await step_ticks(3)
		assert_true(camp.player_inside, "visit %d: inside" % (i + 1))
		_teleport(Vector3(35, 0.05, 10))
		await step_ticks(3)
		assert_false(camp.player_inside, "visit %d: outside" % (i + 1))
	assert_eq(area_events, ["in:test.area.camp:player", "out:test.area.camp:player"] as Array[String],
		"one entered and one exited for two visits")
	assert_eq([camp.entered_count, camp.exited_count], [1, 1], "counts")
