extends TestSuite
## P24b (plan M6-M9 §2.8, decision 13): NavQuery's parameters by purpose, the Valley's (and every
## level's without nav_query settings) equal to map_get_path's defaults, the per-tick query budget,
## NavMaps' map per layer and per mask, and LevelRoot's nav_layers / nav_layer_for /
## nav_query_settings.


## A stand-in level: only what NavQuery reads (nav_query_settings).
class FakeLevel extends Node:
	var settings := {}

	func nav_query_settings() -> Dictionary:
		return settings


const WORLD_SETTINGS := {"max_polygons": 0, "chase_distance_m": 120, "far_distance_m": 300, "repath_min_ticks": 6,
	"repath_min_move_m": 2.0, "queries_per_tick": 8}

var _nodes: Array[Node] = []


func before_each() -> void:
	NavQuery.reset_budget()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	NavQuery.reset_budget()


func _level(settings: Dictionary) -> FakeLevel:
	var l := FakeLevel.new()
	l.settings = settings
	_nodes.append(l)
	return l


func test_parameters_by_purpose() -> void:
	var l := _level(WORLD_SETTINGS)
	assert_eq(NavQuery.params_for(l, NavQuery.PURPOSE_CHASE), {"max_polygons": 0, "max_distance": 120.0},
		"a chase: unlimited polygons, capped at 120 m")
	assert_eq(NavQuery.params_for(l, NavQuery.PURPOSE_FAR), {"max_polygons": 0, "max_distance": 300.0},
		"the bot and the director: capped at 300 m")
	var partial := _level({"chase_distance_m": 80})
	assert_eq(NavQuery.params_for(partial, NavQuery.PURPOSE_CHASE).max_distance, 80.0, "a level's own chase cap")
	assert_eq(NavQuery.params_for(partial, NavQuery.PURPOSE_FAR).max_distance, 300.0, "the far cap's default")
	assert_eq(int(NavQuery.settings(partial).queries_per_tick), 8, "missing keys take the plan's defaults")


func test_without_settings_the_query_is_map_get_paths() -> void:
	var fresh := NavigationPathQueryParameters3D.new()
	var defaults := {"max_polygons": fresh.path_search_max_polygons, "max_distance": fresh.path_search_max_distance}
	assert_eq(defaults, {"max_polygons": NavQuery.DEFAULT_MAX_POLYGONS, "max_distance": 0.0},
		"NavigationPathQueryParameters3D's defaults: 4,096 polygons, no distance cap (map_get_path's)")
	for purpose: String in [NavQuery.PURPOSE_CHASE, NavQuery.PURPOSE_FAR]:
		assert_eq(NavQuery.params_for(_level({}), purpose), defaults, "a level without settings (%s)" % purpose)
		assert_eq(NavQuery.params_for(null, purpose), defaults, "no level at all (%s)" % purpose)
	assert_false(GameData.get_record("level.valley").has("nav_query"), "the Valley's record has no nav_query block")
	var valley := LevelRoot.new()
	valley.level_id = "level.valley"
	_nodes.append(valley)
	assert_eq(valley.nav_query_settings(), {}, "so its LevelRoot hands NavQuery no settings")
	assert_eq(NavQuery.settings(valley), {}, "and NavQuery keeps today's parameters there")
	assert_eq(NavQuery.budget_left(valley), NavQuery.UNLIMITED, "with no query budget")
	assert_false(NavQuery.uses_layer_maps(valley), "and the default map for every layer")
	var tw: Dictionary = GameData.get_record("level.test_world").get("nav_query", {})
	for k: String in WORLD_SETTINGS:
		assert_eq(tw.get(k), WORLD_SETTINGS[k], "the test world asks with the world's settings (%s)" % k)


func test_the_query_budget() -> void:
	var a := _level({"queries_per_tick": 3})
	var b := _level({"queries_per_tick": 3})
	assert_eq(NavQuery.budget_left(a), 3, "a fresh tick: the whole budget")
	NavQuery.spend(a, 2)
	assert_eq(NavQuery.budget_left(a), 1, "two spent")
	assert_eq(NavQuery.used_this_tick(a), 2, "and counted")
	NavQuery.spend(a)
	assert_eq(NavQuery.budget_left(a), 0, "the budget is spent: the rest wait a tick")
	NavQuery.spend(a)
	assert_eq(NavQuery.budget_left(a), 0, "never below zero")
	assert_eq(NavQuery.budget_left(b), 3, "another level keeps its own budget")
	assert_eq(NavQuery.budget_left(_level({})), NavQuery.UNLIMITED, "no setting: unlimited")
	assert_eq(NavQuery.budget_left(_level({"queries_per_tick": 0})), NavQuery.UNLIMITED, "0 means no limit")
	var t := Sim.tick
	var guard := 0
	while Sim.tick == t and guard < 20:
		await get_tree().physics_frame
		guard += 1
	assert_true(Sim.tick != t, "a tick passed")
	assert_eq(NavQuery.budget_left(a), 3, "the next tick has the whole budget again")
	var before := NavQuery.queries_total
	assert_eq(NavQuery.path(a, Vector3.ZERO, Vector3.ONE, 1).size(), 0, "a level without a map answers no path...")
	assert_eq(NavQuery.queries_total, before, "... and runs no query")


func test_nav_maps_by_layer_and_mask() -> void:
	var nm := NavMaps.new()
	nm.setup([1, 2, 16], [32, 64, 128], 16, true)
	assert_true(nm.has_maps(), "three maps")
	var human := nm.map_for(1)
	var large := nm.map_for(2)
	var titan := nm.map_for(16)
	assert_true(human.is_valid() and large.is_valid() and titan.is_valid(), "one per layer")
	assert_true(human != large and large != titan and human != titan, "each its own map")
	assert_eq(nm.map_for(0), human, "layer 0 is the human map")
	for gate: int in [32, 64, 128]:
		assert_eq(nm.map_for(gate), titan, "gate bit %d rides on the titan map" % gate)
		assert_eq(nm.layer_of(gate), 16, "gate bit %d's layer" % gate)
	assert_false(nm.map_for(4).is_valid(), "no map for the Valley's giant layer")
	assert_false(nm.map_for(8).is_valid(), "nor its small giant layer")
	assert_eq(nm.map_for_mask(16 | 32 | 64), titan, "a stage-5 titan mask asks the titan map")
	assert_eq(nm.map_for_mask(240), titan, "a rival giant's mask too")
	assert_eq(nm.map_for_mask(2 | 16), large, "the lowest bit the level has decides")
	assert_eq(nm.map_for_mask(4 | 16), titan, "a bit without a map is skipped")
	assert_false(nm.map_for_mask(4 | 8).is_valid(), "no map for masks of Valley layers only")
	# The server applies map settings at its next sync (a physics step).
	await get_tree().physics_frame
	await get_tree().physics_frame
	for m: RID in [human, large, titan]:
		assert_false(NavigationServer3D.map_get_use_edge_connections(m), "edge connections off")
		assert_false(NavigationServer3D.map_get_use_async_iterations(m), "deterministic: async iterations off")
		assert_true(NavigationServer3D.map_is_active(m), "active")
	assert_true(nm.chunk_ready("c9_9"), "a chunk without navigation is ready at once")
	nm.free_all()
	assert_false(nm.has_maps(), "free_all frees the maps")
	assert_false(nm.map_for(1).is_valid(), "none left")


func test_level_layers_and_the_fallback() -> void:
	var level := LevelRoot.new()
	level.level_id = "level.p24b_unit_level"
	_nodes.append(level)
	TestFixtures.record_override("level.p24b_unit_level", {"schema_version": 1, "type": "level",
		"scene": "", "start_checkpoint": "", "player_nav_fallback": 16})
	assert_eq(level.nav_layers(), PackedInt32Array(), "no Navigation: no layers")
	assert_eq(level.nav_layer_for(4), 16, "a stage-3 profile's giant layer falls back to the record's 16")
	var nav := Node3D.new()
	nav.name = "Navigation"
	level.add_child(nav)
	for bits: int in [1, 2, 4, 8]:
		var r := NavigationRegion3D.new()
		r.navigation_layers = bits
		nav.add_child(r)
	assert_eq(level.nav_layers(), PackedInt32Array([1, 2, 4, 8]), "the Valley's four layers from its regions")
	assert_eq(level.nav_layer_for(4), 4, "a level with the profile's layer keeps it")
	assert_eq(level.nav_layer_for(8), 8, "stage 1's small giant layer")
	assert_eq(level.nav_layer_for(16), 16, "stage 4-6 profiles' titan layer is not here: the fallback (16)")
	assert_eq(level.nav_map(4), level.nav_map(1), "outside the tree every layer's map is the same (none)")
	assert_eq(level.nav_query_settings(), {}, "no nav_query block")
	TestFixtures.restore_all()
