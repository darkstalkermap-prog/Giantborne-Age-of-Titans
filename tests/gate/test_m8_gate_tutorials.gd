extends IntegrationSuite
## M8 gate (F28, F32): the Old Kingdom's first lessons in the real game - main.tscn builds level.world
## as a New Game in the world or a travel through the Kings' Door would (the loading gate pauses the
## tree, the world's starting ring loads behind it and GameSession emits level_entered during it, before
## the level's first tick), with the shipped tutorial prompts and Quests:
##   * a New Game in the world: the arrival's lesson shows at once, then the map's (queued behind it on
##     the same level_entered), then the compass's (its flag trigger, tutorial.map.seen) - before, the
##     first tick's level-memory reset wiped the event, and the map's lesson lapsed behind the arrival's;
##   * through the Kings' Door (a Valley level, then the exit to the Kingsgate shelf): the same three;
##   * the first world shrine walked up to while the compass's lesson still shows: both of the shrine's
##     lessons, the ancestry's and then the fast-travel's (queued behind it on the same
##     shrine_activated) - before, the fast-travel lesson lapsed behind the ancestry's.
## The giant lights the beacon (its BeaconFire, the scouts taken as beaten), opens the map (the map
## screen) and chooses its ancestry (PlayerProgression) the way a player dismisses those lessons.

const MAIN := "res://scenes/main.tscn"
const START_CP := "world.cp.kingsgate_shelf"
const BEACON := "world.crownmarch.kingsgate_beacon_fire"
const SHRINE := "world.shrine.kingsgate"

var shown: Array = []   ## [id, tick]
var main_node: Node = null


func before_each() -> void:
	await super()
	shown.clear()
	Events.tutorial_shown.connect(_on_shown)


func after_each() -> void:
	if Events.tutorial_shown.is_connected(_on_shown):
		Events.tutorial_shown.disconnect(_on_shown)
	if is_instance_valid(main_node):
		main_node.queue_free()
	main_node = null
	await get_tree().process_frame
	get_tree().paused = false
	await super()


func _on_shown(tick: int, id: String) -> void:
	shown.append([id, tick])


func _ids() -> Array:
	return shown.map(func(s: Array) -> String: return str(s[0]))


## main.tscn as GameSession's reload would build it; returns once its loading gate let the game run.
func _load_main() -> Node:
	main_node = (load(MAIN) as PackedScene).instantiate()
	world.add_child(main_node)
	var guard := 0
	await get_tree().process_frame
	while is_instance_valid(main_node) and bool(main_node.call("is_loading")) and guard < 4000:
		await get_tree().process_frame
		guard += 1
	assert_false(bool(main_node.call("is_loading")), "main.tscn's loading gate opened (%d frames)" % guard)
	return main_node


func _player() -> GiantPlayer:
	return GameSession.player()


## Steps until the prompt `id` is on screen (at most `seconds` of play); true when it is.
func _until_shown(id: String, seconds: float) -> bool:
	return await TestWait.until(self, func() -> bool: return str(Quests.current_tutorial().get("id", "")) == id,
		int(seconds * 60.0))


func _find(world_id: String) -> Node:
	for n in main_node.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


## The beacon's scene (a dialogue screen that pauses the game) read to its end, as a player does.
func _read_the_scene() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var guard := 0
	while Quests.dialogue != null and Quests.dialogue.is_active() and guard < 12:
		var cs := Quests.dialogue.choices()
		Quests.dialogue.choose(int((cs[0] as Dictionary).index))
		guard += 1
		await get_tree().process_frame
	var stack := main_node.get("screen_stack") as ScreenStack
	if stack != null:
		stack.close_all()
	await get_tree().process_frame
	get_tree().paused = false


## The arrival's lesson, then the map's, then the compass's - each dismissed the way a player does.
func _the_first_three_lessons(how: String) -> void:
	assert_true(await _until_shown("tutorial.world_arrival", 3.0), "%s: the arrival's lesson shows (%s)" % [how, _ids()])
	# The beacon lit (its scouts taken as beaten): the arrival's lesson is done.
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.crownmarch_kingsgate_scouts"), true)
	var fire := _find(BEACON) as BeaconFire
	assert_true(fire != null, "%s: the Kingsgate beacon's fire is in the starting ring" % how)
	await step_ticks(60 * 3)
	if fire != null:
		assert_true(fire.light(), "%s: the giant lights the beacon" % how)
		await _read_the_scene()
	assert_true(await _until_shown("tutorial.map", 2.0), "%s: then the map's lesson (%s)" % [how, _ids()])
	# The giant opens the map (its first opening sets map.opened), then closes it.
	var stack := main_node.get("screen_stack") as ScreenStack
	assert_true(stack != null and stack.open("map") != null, "%s: the map opens" % how)
	await get_tree().process_frame
	await get_tree().process_frame
	stack.close_all()
	await get_tree().process_frame
	get_tree().paused = false
	assert_true(await _until_shown("tutorial.compass", 2.0), "%s: then the compass's lesson (%s)" % [how, _ids()])
	var ids := _ids()
	assert_true(ids.find("tutorial.world_arrival") < ids.find("tutorial.map") and ids.find("tutorial.map") < ids.find("tutorial.compass"),
		"%s: world_arrival, then map, then compass (%s)" % [how, ids])


func test_a_new_game_in_the_world_shows_the_arrival_the_map_and_the_compass() -> void:
	GameSession.start_world_for_tests(START_CP)
	await _load_main()
	assert_eq(GameSession.level_id, "level.world", "the world loaded")
	assert_eq(str((GameSession.entered_log.back() as Dictionary).reason) if not GameSession.entered_log.is_empty() else "",
		"new_game", "entered as a New Game")
	await _the_first_three_lessons("New Game")


func test_through_the_kings_door_the_arrival_the_map_and_the_compass() -> void:
	# The Valley's end: a Valley level (a stand-in floor) with the slice done, then the exit through the
	# Kings' Door to the Kingsgate shelf - GameSession's travel, then main.tscn as its reload builds it.
	GameSession.start_new_valley()
	WorldState.set_flag("slice.completed", true)
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	await step_ticks(5)
	var r := GameSession.travel_to("level.world", START_CP, "exit")
	assert_true(bool(r.ok), "through the Kings' Door (%s)" % r.message)
	world.remove_child(p)
	p.free()
	await _load_main()
	assert_eq(GameSession.level_id, "level.world", "the world loaded")
	assert_eq(str((GameSession.entered_log.back() as Dictionary).reason), "travel", "entered by the exit")
	await _the_first_three_lessons("the Kings' Door")


func test_the_first_world_shrine_shows_the_ancestry_and_the_fast_travel_lessons() -> void:
	GameSession.start_world_for_tests(START_CP)
	await _load_main()
	await _the_first_three_lessons("New Game")
	# While the compass's lesson still shows, the giant walks up to the Kingsgate shrine: 40 m north of
	# it (outside its activation radius), then onto its spawn point.
	var shrine := _find(SHRINE) as Shrine
	assert_true(shrine != null, "the Kingsgate shrine is in the starting ring")
	if shrine == null:
		return
	var p := _player()
	var spot := (shrine.get_node("SpawnPoint") as Node3D).global_transform
	GameSession.place_player(p, Transform3D(spot.basis, spot.origin + Vector3(0, 0, 40)))
	await step_ticks(30)
	GameSession.place_player(p, spot)
	var activated: bool = await TestWait.until(self, func() -> bool: return Quests.tutorial.pending_ids().has("tutorial.ancestry") \
		or _ids().has("tutorial.ancestry"), 60 * 5)
	assert_true(activated, "the shrine activates: its lessons wait (%s, pending %s)" % [_ids(), Quests.tutorial.pending_ids()])
	assert_true(await _until_shown("tutorial.ancestry", 20.0), "the ancestry's lesson shows after the compass's (%s)" % [_ids()])
	# The giant chooses its ancestry at the shrine: the lesson is done.
	var chosen: Dictionary = p.progression.choose_ancestry("ancestry.stoneblood")
	assert_true(bool(chosen.get("ok", false)), "the ancestry chosen (%s)" % chosen)
	# (a sealed place seen on the way and the first place found may take their turns first: they queue too)
	assert_true(await _until_shown("tutorial.fast_travel", 45.0), "then the fast-travel lesson (%s)" % [_ids()])
	var ids := _ids()
	assert_true(ids.find("tutorial.ancestry") < ids.find("tutorial.fast_travel"), "ancestry, then fast travel (%s)" % [ids])
	print("    tutorials at the first world shrine: %s" % [shown])
