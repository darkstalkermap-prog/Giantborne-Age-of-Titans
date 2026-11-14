extends IntegrationSuite
## P27 (plan M6-M9 §3.10 design 1): Discovery on a stub level (tests/support/world_ux_fixtures.gd:
## records and an index built in code, no level load). A POI is found once - its flag, its XP and
## poi_discovered - at its min_stage or above; a vista reveals its neighbours (on the map, no XP;
## their XP waits for the visit) and the fog of the chunks around it; a sealed place is seen within
## 60 m and found only once its seal is open; entering a chunk clears its fog; a region's first
## entry pays its discover_xp; the flags survive a save and a found POI never pays twice; the
## discovered and region_entered conditions read them (a revealed POI is not discovered). The HUD's
## discovery toast says what was found (with the places a vista put on the map) and which sealed
## place was seen; the region banner names the region entered and warns below its recommended stage.

const Fx := preload("res://tests/support/world_ux_fixtures.gd")
const Toast := preload("res://ui/hud/discovery_toast.gd")
const Banner := preload("res://ui/hud/region_banner.gd")

var xp: Array = []          ## [amount, source]
var found: Array[String] = []


func before_each() -> void:
	await super()
	xp.clear()
	found.clear()
	Events.xp_award_requested.connect(_on_xp)
	Events.poi_discovered.connect(_on_found)
	Fx.install()


func after_each() -> void:
	for sig: Signal in [Events.xp_award_requested, Events.poi_discovered]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_xp(amount: int, source: String) -> void:
	xp.append([amount, source])


func _on_found(_tick: int, poi_id: String) -> void:
	found.append(poi_id)


func test_a_poi_is_found_once_with_its_xp_at_its_stage() -> void:
	var d := Fx.discovery(world)
	assert_eq(d.pois.size(), 7, "the stub level's seven POIs")
	assert_eq(d.scan(Vector3(5, 0, -95), 3, 30), PackedStringArray(["poi.test_p27_town"]), "inside the town's radius")
	assert_eq(WorldState.get_flag("discovered.test_p27_town"), true, "discovered.<short> is true")
	assert_eq(xp, [[40, "discovery:poi.test_p27_town"]], "its 40 XP, once")
	assert_eq(found, ["poi.test_p27_town"], "poi_discovered once")
	assert_eq(d.scan(Vector3(0, 0, -100), 3, 60), PackedStringArray(), "a second visit finds nothing")
	assert_eq(xp.size(), 1, "and pays nothing")
	assert_eq(d.scan(Vector3(100, 0, -100), 4, 90), PackedStringArray(), "a stage-5 place is not found at stage 4")
	assert_eq(d.scan(Vector3(100, 0, -100), 5, 120), PackedStringArray(["poi.test_p27_high"]), "but at stage 5")
	assert_eq(d.scan(Vector3(-100, 0, -50), 3, 150), PackedStringArray(["poi.test_p27_shrine"]), "a shrine is found")
	assert_eq(xp.size(), 2, "with no XP (its record gives 0)")
	assert_true(Discovery.of_tree(get_tree()) == d, "the level's Discovery node is in its group")


func test_a_vista_reveals_its_neighbours_and_their_fog() -> void:
	var toast := Toast.new()
	world.add_child(toast)
	var d := Fx.discovery(world)
	d.scan(Vector3(100, 0, 100), 3, 30)
	assert_eq(found, ["poi.test_p27_vista"], "the vista is found")
	await get_tree().process_frame
	assert_eq(toast.visible_text(), "Discovered: Vista  +30 XP  (1 place on your map)",
		"the toast: its XP and the place it put on the map")
	assert_eq(WorldState.get_flag("discovered.test_p27_ruin"), Discovery.REVEALED, "the ruin 111 m away is revealed")
	assert_true(Discovery.is_known(WorldState.flags, "poi.test_p27_ruin"), "on the map")
	assert_false(Discovery.is_found(WorldState.flags, "poi.test_p27_ruin"), "but not found")
	assert_false(WorldState.has_flag("discovered.test_p27_far"), "the far landmark is beyond its 150 m")
	assert_false(WorldState.has_flag("discovered.test_p27_seal"), "a vista never reveals a sealed place")
	assert_eq(xp, [[30, "discovery:poi.test_p27_vista"]], "only the vista's XP")
	for chunk: String in ["c3_3", "c2_2", "c3_1", "c1_3"]:
		assert_true(QuestConditions.truthy(WorldState.get_flag("map.seen." + chunk)), "%s's fog is cleared" % chunk)
	assert_false(WorldState.has_flag("map.seen.c0_0"), "c0_0 (283 m away) stays fogged")
	d.scan(Vector3(150, 0, 0), 3, 60)
	assert_eq(found, ["poi.test_p27_vista", "poi.test_p27_ruin"], "visiting the revealed ruin finds it")
	assert_eq(xp.back(), [25, "discovery:poi.test_p27_ruin"], "with its XP")


func test_sealed_places_fog_regions_and_the_save() -> void:
	var toast := Toast.new()
	world.add_child(toast)
	var banner := Banner.new()
	world.add_child(banner)
	var d := Fx.discovery(world)
	d.scan(Vector3(-100, 0, 45), 3, 30)
	assert_eq(WorldState.get_flag("sealed.test_p27_seal.seen"), true, "a sealed place 55 m away is seen")
	await get_tree().process_frame
	assert_eq(toast.visible_text(), "Sealed: Seal (grow to stage 5)", "the toast names it and its stage")
	assert_eq(int(WorldState.get_flag(Discovery.SEALED_COUNT_FLAG, 0)), 1, "the count of sealed places seen")
	assert_true(QuestConditions.truthy(WorldState.get_flag("map.seen.c1_2")), "the chunk entered is seen")
	assert_eq(d.scan(Vector3(-100, 0, 100), 6, 60), PackedStringArray(), "standing at the seal finds nothing while it is shut")
	WorldState.record_destroyed(Fx.SEAL)
	assert_eq(d.scan(Vector3(-100, 0, 100), 6, 90), PackedStringArray(["poi.test_p27_seal"]), "found once it is heaved")
	assert_eq(int(WorldState.get_flag(Discovery.SEALED_COUNT_FLAG, 0)), 1, "seen once")
	Events.region_changed.emit(Sim.tick, Fx.NORTH, "")
	assert_eq(banner.visible_text(), "THE NORTH TEST | Recommended stage 4-5", "the banner names the region")
	assert_true(banner.warns(), "in the warning colour below stage 4")
	Events.region_changed.emit(Sim.tick, Fx.SOUTH, Fx.NORTH)
	assert_eq(banner.shown_region(), Fx.SOUTH, "the next region replaces it")
	assert_false(banner.warns(), "the south's stages 1-3: no warning")
	Events.region_changed.emit(Sim.tick, Fx.NORTH, Fx.SOUTH)
	assert_eq(WorldState.get_flag("region.test_p27_north.entered"), true, "region.<short>.entered")
	assert_eq(WorldState.get_flag("region.test_p27_south.entered"), true, "for both")
	var region_xp := xp.filter(func(e: Array) -> bool: return str(e[1]).begins_with("discovery:region."))
	assert_eq(region_xp, [[25, "discovery:region.test_p27_north"]], "the north's discover_xp once; the south has none")
	# saved and restored: the flags come back from a checkpoint document and pay nothing again
	var doc := JSON.parse_string(JSON.stringify(WorldState.to_save_dict())) as Dictionary
	WorldState.clear()
	assert_true(WorldState.from_save_dict(doc), "the world loads back")
	assert_true(Discovery.is_found(WorldState.flags, "poi.test_p27_seal"), "the sealed place is still found")
	var before := xp.size()
	d.scan(Vector3(-100, 0, 100), 6, 120)
	Events.region_changed.emit(Sim.tick, Fx.NORTH, "")
	assert_eq(xp.size(), before, "no second award after the reload")
	# the quest conditions (P27)
	var ctx := QuestConditions.empty_context()
	ctx.flags = WorldState.flags
	assert_true(QuestConditions.holds({"type": "discovered", "poi": "poi.test_p27_seal"}, ctx), "discovered holds")
	assert_true(QuestConditions.holds({"type": "region_entered", "region": Fx.NORTH}, ctx), "region_entered holds")
	WorldState.set_flag("discovered.test_p27_ruin", Discovery.REVEALED)
	assert_false(QuestConditions.holds({"type": "discovered", "poi": "poi.test_p27_ruin"}, ctx), "revealed is not discovered")
	assert_false(QuestConditions.holds({"type": "region_entered", "region": "region.greywood"}, ctx), "an unentered region")


func test_the_world_and_the_valley_get_their_discovery() -> void:
	var table := Discovery.poi_table("level.world")
	assert_eq(table.size(), 48, "the world's 48 POIs")
	assert_eq(float((table["poi.kingsgate_shelf"] as Dictionary).reveals_m), 600.0, "the shelf reveals 600 m")
	assert_eq(Discovery.chunk_of(Discovery.chunk_grid("level.world"), Vector3(-300, 46, 920)), "c2_7",
		"the shelf stands in c2_7")
	assert_true(Discovery.chunk_grid("level.valley").is_empty(), "the Valley has no chunks (no fog)")
	var root := LevelRoot.new()
	root.level_id = "level.valley"
	world.add_child(root)
	assert_true(root.discovery() != null, "the Valley's root makes its Discovery node (RUNTIME_NODES)")
	assert_eq(root.discovery().level_id, "level.valley", "for its level")
	root.queue_free()
