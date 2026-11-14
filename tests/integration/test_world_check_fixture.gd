extends TestSuite
## P39f (plan M6-M9 §6.3, §6.6): the web world check's defaults (tools/web/world_check.json, read by
## tools/web/world_check.mjs) hold on this build, so the check measures the world and never its own
## mistakes: the fixture - a world save the world bot wrote - is a valid schema 2 save of level.world that
## the title's Continue loads at its respawn (nothing dropped, no recovery); the travel's waystone is one
## the fixture reached and fast travel may take at the fixture's stage; the route sets off beside it and
## crosses region borders. Reads files and the world's index only (no level is loaded);
## tests/slow/test_world_check_route.gd walks the route on the real world.

const CONFIG := "res://tools/web/world_check.json"
const LEVEL := "level.world"
## The route's first point lies this close to the waystone (the walk's first leg is the arrival's).
const FIRST_LEG_MAX_M := 80.0


func _config() -> Dictionary:
	var r := JsonIO.read_file(CONFIG)
	assert_true(r.ok and typeof(r.data) == TYPE_DICTIONARY, "%s reads" % CONFIG)
	return r.data if r.ok and typeof(r.data) == TYPE_DICTIONARY else {}


func _fixture(cfg: Dictionary) -> Dictionary:
	var r := JsonIO.read_file("res://" + str(cfg.get("fixture", "")))
	assert_true(r.ok and typeof(r.data) == TYPE_DICTIONARY, "the fixture %s reads" % cfg.get("fixture", ""))
	return r.data if r.ok and typeof(r.data) == TYPE_DICTIONARY else {}


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	WorldState.clear()


func test_the_fixture_continues_at_its_respawn() -> void:
	var cfg := _config()
	var doc := _fixture(cfg)
	assert_eq(int(doc.get("schema_version", 0)), SaveSlots.SCHEMA_VERSION, "a schema %d save" % SaveSlots.SCHEMA_VERSION)
	assert_eq(str(doc.get("level", "")), LEVEL, "of the world")
	assert_eq(Array(SaveSlots.validate(SaveSlots.migrate(doc))), [], "valid on this build")
	var respawn := str((doc.get("checkpoint", {}) as Dictionary).get("respawn", ""))
	var idx := WorldIndex.for_level(LEVEL)
	assert_true(idx != null and idx.has_checkpoint(respawn), "its respawn %s is a checkpoint of the world" % respawn)
	# the title's Continue, from the slot as the browser holds it (Continue needs saving on: the check runs
	# with --save-dir=user://saves beside --no-user-settings, as here)
	GameSession.persist = true
	DirAccess.make_dir_recursive_absolute(SaveSlots.path().get_base_dir())
	var f := FileAccess.open(SaveSlots.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://" + str(cfg.fixture)))
	f.close()
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads it (%s)" % r.message)
	assert_eq(GameSession.last_load_message, "", "cleanly: nothing recovered, nothing dropped")
	assert_eq(GameSession.level_id, LEVEL, "into the world")
	assert_eq(GameSession.respawn_id, respawn, "at its respawn")
	assert_eq(GameSession.scene_reloads.back(), "continue", "a Continue's load")
	assert_eq(int((GameSession.character as Dictionary).get("growth_stage", 0)), 5, "a stage-5 giant (the fixture's)")


func test_the_travel_is_open_from_the_fixture() -> void:
	var cfg := _config()
	var doc := _fixture(cfg)
	var to := str(cfg.get("travel_to", ""))
	var flags: Dictionary = ((doc.get("world", {}) as Dictionary).get("flags", {}) as Dictionary)
	var stage := int((doc.get("character", {}) as Dictionary).get("growth_stage", 0))
	var idx := WorldIndex.for_level(LEVEL)
	assert_true(idx.has_checkpoint(to), "%s is a checkpoint of the world" % to)
	var entry := idx.checkpoint(to)
	assert_true(bool(entry.get("fast_travel", true)), "a fast travel point (a waystone or shrine)")
	assert_true(QuestConditions.truthy(flags.get("visited." + to)), "the fixture reached it (visited.%s)" % to)
	assert_true(idx.max_stage_of(to) >= stage, "it takes a stage-%d giant (max_stage %d)" % [stage, idx.max_stage_of(to)])
	for req: Variant in entry.get("requires_flags", PackedStringArray()):
		assert_true(QuestConditions.truthy(flags.get(str(req))), "its flag %s holds" % req)
	var respawn := str((doc.get("checkpoint", {}) as Dictionary).get("respawn", ""))
	assert_true(to != respawn, "it is another place than the fixture's respawn (a real travel)")
	var from := idx.position_of(respawn)
	var there := idx.position_of(to)
	assert_true(Vector2(from.x - there.x, from.z - there.z).length() > 300.0, "far from it (a load of other chunks)")


func test_the_route_sets_off_beside_the_waystone_and_crosses_borders() -> void:
	var cfg := _config()
	var idx := WorldIndex.for_level(LEVEL)
	var there := idx.position_of(str(cfg.travel_to))
	var points: Array = cfg.get("route", [])
	assert_true(points.size() >= 2, "a route of two or more points")
	var first := Vector3(float(points[0][0]), 0.0, float(points[0][1]))
	assert_true(Vector2(first.x - there.x, first.z - there.z).length() <= FIRST_LEG_MAX_M,
		"its first point is beside the waystone (%.0f m)" % Vector2(first.x - there.x, first.z - there.z).length())
	var regions := PackedStringArray([idx.region_at(there)])
	var length := Vector2(first.x - there.x, first.z - there.z).length()
	var last := first
	for p: Array in points:
		var q := Vector3(float(p[0]), 0.0, float(p[1]))
		length += Vector2(q.x - last.x, q.z - last.z).length()
		last = q
		var r := idx.region_at(q)
		if r != "" and r != regions[regions.size() - 1]:
			regions.append(r)
	assert_true(regions.size() >= 1 + int(cfg.get("min_borders", 1)), "it crosses region borders: %s" % [regions])
	# a stage-5 giant sprints about 10 m/s: the route lasts the check's least walk with room to spare
	assert_true(length >= 10.0 * float(cfg.get("walk_min_s", 60)) * 1.1, "long enough for %s s of walking (%.0f m)" % [cfg.walk_min_s, length])
