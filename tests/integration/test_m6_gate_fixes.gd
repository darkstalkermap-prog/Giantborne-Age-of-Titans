extends IntegrationSuite
## M6 gate review fixes (decision 1: audio has no effect on the simulation; the Valley bot's seeded
## runs diverged between audio on and --no-audio):
##   * headless runs - the tests, the soaks, the bots - sync every navigation map and region on the
##     main thread (Sim.make_navigation_synchronous), so a change is usable in the physics step after
##     it, never at a tick that depends on a worker thread's wall time;
##   * main.gd's loading gate holds the first tick until the level's navigation map has synced: the
##     map used to be ready at the first tick only when the audio gate had held long enough, and a
##     silent run's first ticks steered without it.
## The autopilot's half (no bot before the gate opens) and the whole runs are compared in
## tests/gate/test_valley_audio_determinism.gd.

const MainScript := preload("res://scripts/main.gd")
const NAV_SCENE := "user://m6_gate_nav_level.tscn"
## Far from the suites' floor and anything else on the shared map.
const FAR := Vector3(800, 0, 800)

var _tick0 := 0
var _first_tick: Dictionary = {}


func after_each() -> void:
	Sim.remove_hooks(self)
	await super()


## A square navmesh (half-size `half`) on nav layer 1, around the region's origin.
static func square_navmesh(half: float) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half),
		Vector3(-half, 0, half)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return nm


static func path_across(map: RID, centre: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, centre + Vector3(-8, 0, -8), centre + Vector3(8, 0, 8), true, 1)


func test_headless_runs_sync_navigation_in_the_next_physics_step() -> void:
	assert_true(Sim.deterministic_run(), "the suites run headless: a deterministic run")
	var map := get_viewport().world_3d.navigation_map
	assert_false(NavigationServer3D.map_get_use_async_iterations(map), "the level's map syncs on the main thread")
	var region := NavigationRegion3D.new()
	assert_false(NavigationServer3D.region_get_use_async_iterations(region.get_rid()),
		"and so does every region made after start-up")
	region.navigation_mesh = square_navmesh(15.0)
	region.position = FAR
	var before := NavigationServer3D.map_get_iteration_id(map)
	world.add_child(region)
	assert_true(path_across(map, FAR).is_empty(), "no path before the map has synced")
	await get_tree().process_frame   # one physics step: the scene's tick, then the navigation sync
	assert_true(NavigationServer3D.map_get_iteration_id(map) > before, "the map synced in the next step")
	assert_true(path_across(map, FAR).size() >= 2, "and the new region carries a path at once")
	region.queue_free()
	await get_tree().process_frame


func test_the_loading_gate_holds_the_first_tick_until_the_levels_navigation_is_synced() -> void:
	var lv := Node3D.new()
	lv.name = "NavGateLevel"
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = square_navmesh(15.0)
	region.position = FAR
	lv.add_child(region)
	region.owner = lv
	var packed := PackedScene.new()
	packed.pack(lv)
	lv.free()
	assert_eq(ResourceSaver.save(packed, NAV_SCENE), OK, "the gate's test level is saved")
	GameSession.level_override = NAV_SCENE
	var map := get_viewport().world_3d.navigation_map
	var before := NavigationServer3D.map_get_iteration_id(map)
	_tick0 = Sim.tick
	_first_tick = {}
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _on_tick, 0)
	var main := MainScript.new()
	add_child(main)
	var guard := 0
	while _first_tick.is_empty() and guard < 240:
		guard += 1
		await get_tree().process_frame
	Sim.remove_hooks(self)
	assert_false(_first_tick.is_empty(), "the level's first tick ran")
	if not _first_tick.is_empty():
		assert_true(int(_first_tick.iteration) > before,
			"the navigation map had synced the level before its first tick (iteration %d, %d before the load)" % [
				int(_first_tick.iteration), before])
		assert_true(int(_first_tick.path) >= 2, "a path on the level's navmesh at its first tick")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameSession.level_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NAV_SCENE))


func _on_tick(tick: int) -> void:
	if not _first_tick.is_empty() or tick <= _tick0:
		return
	var map := get_viewport().world_3d.navigation_map
	_first_tick = {"tick": tick, "iteration": NavigationServer3D.map_get_iteration_id(map),
		"path": path_across(map, FAR).size()}
