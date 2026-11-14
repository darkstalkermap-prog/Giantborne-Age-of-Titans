extends IntegrationSuite
## The campaign across levels (P20; plan M6-M9 §2.6, decision 11), on a pair of small levels built
## here in code - each a LevelRoot with a floor, CheckpointMarkers and a LevelExit, named by a stub
## `level` record (TestFixtures.record_override) whose scene is an existing test scene (the reload
## is only logged in tests, so the test builds each level itself, as main.gd does):
##   * an exit takes a checkpoint at the destination, emits level_leaving, reloads, and the next
##     level puts the giant at the destination checkpoint with the character, flags, inventory and
##     world deltas intact; level_entered waits for the level's is_ready(); checkpoints and saves
##     work on the second level;
##   * travel is refused while grabbed or holding, for a checkpoint whose max_stage is below the
##     giant's stage, for an unknown checkpoint, for fast travel to an unvisited or closed one, for an
##     unknown reason, outside the campaign and for a level this build lacks; an exit ignores aware
##     enemies; a locked LevelExit never asks;
##   * a respawn blocker moves the respawn to the nearest unblocked checkpoint (visited first), and a
##     checkpoint whose node is not loaded respawns from the world index;
##   * Continue on a world save loads level.world when it exists (a stub record), else falls back to
##     the Valley with a message.

const LEVEL_A := "level.test_p20_a"
const LEVEL_B := "level.test_p20_b"
const STAND_IN := "res://scenes/test/flow_test_level.tscn"
## A level.world scene that does not exist: a build without the world (P25 ships the world).
const NO_WORLD_SCENE := "res://scenes/world/no_such_world.tscn"
const GATED_LEVEL_SOURCE := "extends LevelRoot\nvar ready_now := false\nfunc is_ready() -> bool:\n\treturn ready_now\n"

## A modal screen that does not pause the game (the map screen fast travel is chosen on, P27).
class OverlayScreen:
	extends UiScreen

	func pauses_game() -> bool:
		return false


var leaving: Array = []     ## [from, to, reason]
var entered: Array = []     ## [level, reason]
var saved: Array = []       ## [checkpoint, ok, message]
var loaded_cps: Array = []  ## [checkpoint, source]
var notices: Array[String] = []


func before_each() -> void:
	await super()
	leaving.clear()
	entered.clear()
	saved.clear()
	loaded_cps.clear()
	notices.clear()
	Events.level_leaving.connect(_on_leaving)
	Events.level_entered.connect(_on_entered)
	Events.checkpoint_saved.connect(_on_saved)
	Events.checkpoint_loaded.connect(_on_loaded)
	Events.hud_message.connect(_on_notice)
	for id: String in [LEVEL_A, LEVEL_B]:
		TestFixtures.record_override(id, {"schema_version": 1, "type": "level", "display_name": id.capitalize(),
			"scene": STAND_IN, "start_checkpoint": "test.a.start" if id == LEVEL_A else "test.b.arrive"})
	WorldIndex.put_cached(LEVEL_B, _index_b())


func after_each() -> void:
	for sig: Signal in [Events.level_leaving, Events.level_entered, Events.checkpoint_saved,
			Events.checkpoint_loaded, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_leaving(_tick: int, from: String, to: String, reason: String) -> void:
	leaving.append([from, to, reason])


func _on_entered(_tick: int, level_id: String, reason: String) -> void:
	entered.append([level_id, reason])


func _on_saved(_tick: int, checkpoint_id: String, ok: bool, message: String) -> void:
	saved.append([checkpoint_id, ok, message])


func _on_loaded(_tick: int, checkpoint_id: String, source: String) -> void:
	loaded_cps.append([checkpoint_id, source])


func _on_notice(text: String, _kind: String) -> void:
	notices.append(text)


## Level B's world index: where its checkpoints are (also those not built here) and who may arrive.
func _index_b() -> WorldIndex:
	var idx := WorldIndex.new()
	idx.level_id = LEVEL_B
	idx.checkpoints = {
		"test.b.arrive": {"position": Vector3(40, 0.05, 10), "yaw": PI / 2, "display_name": "Arrival stone",
			"kind": "waystone", "fast_travel": true, "requires_flags": PackedStringArray(), "max_stage": 10},
		"test.b.near": {"position": Vector3(50, 0.05, 10), "yaw": PI, "display_name": "Near stone", "kind": "waystone",
			"fast_travel": true, "requires_flags": PackedStringArray(), "max_stage": 10},
		"test.b.narrow": {"position": Vector3(45, 0.05, 10), "yaw": 0.0, "display_name": "Narrow stair",
			"kind": "waystone", "fast_travel": true, "requires_flags": PackedStringArray(), "max_stage": 2},
		"test.b.far": {"position": Vector3(140, 0.05, 10), "yaw": 0.0, "display_name": "Far stone", "kind": "waystone",
			"fast_travel": true, "requires_flags": PackedStringArray(["test.b.gate_open"]), "max_stage": 10}}
	return idx


## A level built in code: a LevelRoot (or a subclass from `source`) with a floor, its checkpoints
## [[id, position, yaw]] and exits [[exit id, to level, to checkpoint, position]], added to the world.
func _make_level(level_id: String, checkpoints: Array, exits: Array, source := "") -> LevelRoot:
	var root: LevelRoot
	if source != "":
		var script := GDScript.new()
		script.source_code = source
		script.reload()
		root = script.new()
	else:
		root = LevelRoot.new()
	root.name = "Level_" + level_id.get_slice(".", 1)
	root.level_id = level_id
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = HitQueryAdapter.LAYER_WORLD
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0, -0.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	for cp: Array in checkpoints:
		var m := CheckpointMarker.new()
		m.checkpoint_id = str(cp[0])
		m.position = cp[1]
		m.rotation.y = float(cp[2])
		root.add_child(m)
	for x: Array in exits:
		var e := LevelExit.new()
		e.name = "Exit_" + str(x[0]).replace(".", "_")
		e.exit_id = str(x[0])
		e.to_level = str(x[1])
		e.to_checkpoint = str(x[2])
		e.position = x[3]
		e.display_name = "The way to " + str(x[1])
		root.add_child(e)
	world.add_child(root)
	return root


## The giant of a level (a child of its root, as the scene's Player is).
func _player_in(level: Node3D, pos: Vector3) -> GiantPlayer:
	var p: GiantPlayer = (load(GIANT) as PackedScene).instantiate()
	p.position = pos
	level.add_child(p)
	p.router.use_injection = true
	return p


func _level_a() -> LevelRoot:
	return _make_level(LEVEL_A, [["test.a.start", Vector3(0, 0.05, 0), 0.0]],
		[["test.exit.a_to_b", LEVEL_B, "test.b.arrive", Vector3(0, 0, -8)]])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The world_start campaign on level A (level.world stands for any campaign level): New Game's
## first checkpoint at A's start.
func _start_on_level_a() -> Dictionary:
	GameSession.start_world_for_tests()
	GameSession.level_id = LEVEL_A
	var a := _level_a()
	var p := _player_in(a, Vector3(3, 0.05, 3))
	GameSession.on_level_ready(a, p)
	return {"level": a, "player": p, "exit": a.get_node("Exit_test_exit_a_to_b") as LevelExit}


# --------------------------------------------------------------------------- travel

func test_an_exit_carries_the_giant_and_the_world_to_the_other_level() -> void:
	GameSession.persist = true
	var s := _start_on_level_a()
	var p: GiantPlayer = s.player
	assert_eq(GameSession.respawn_id, "test.a.start", "New Game respawns at level A's start checkpoint")
	assert_eq(entered, [[LEVEL_A, "new_game"]], "level_entered for A (no is_ready, no Audio: at once)")
	assert_eq(GameSession.progress.levels_visited, [LEVEL_A], "A is visited")
	await step_ticks(2)
	# What the travel must keep: the world, the inventory, the loadout and the wounds.
	WorldState.set_flag("test.p20.flag", "kept")
	WorldState.add_item("item.wood_scrap", 3, "test")
	WorldState.record_destroyed("test.p20.fence")
	p.set_loadout_slot("slot_8", "")
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max * 0.4
	var exit: LevelExit = s.exit
	assert_true(exit.can_interact(p), "the exit is open")
	saved.clear()
	exit.interact(p)
	assert_true(bool(GameSession.last_travel_result.get("ok", false)), "the travel starts: %s" % GameSession.last_travel_result)
	assert_eq(GameSession.scene_reloads.back(), "travel", "a reload into the destination")
	assert_eq(leaving, [[LEVEL_A, LEVEL_B, "exit"]], "level_leaving names both levels and the reason")
	assert_eq(saved.size(), 1, "a checkpoint at the destination, before the reload")
	assert_eq(str(saved[0][0]), "test.b.arrive", "its respawn is the destination checkpoint")
	assert_true(bool(saved[0][1]), "written")
	var doc := GameSession.checkpoint_doc
	assert_eq(str(doc.level), LEVEL_B, "the document's level is the destination")
	assert_eq(str(doc.checkpoint.reason), "travel", "for a travel")
	var at: Array = doc.checkpoint.get("position", [0, 0, 0])
	assert_true(Vector3(float(at[0]), float(at[1]), float(at[2])).is_equal_approx(Vector3(40, 0.05, 10)),
		"with the destination's index position (%s)" % [at])
	assert_eq(str(SaveSlots.read().data.level), LEVEL_B, "and the save slot names level B")
	assert_true(GameSession.pending_restore, "waiting for the next level")
	assert_eq(GameSession.level_id, LEVEL_B, "the campaign moved on")
	var health := pools.health
	# The reload: level A and its giant are freed; level B (not ready at first) comes up.
	(s.level as Node).queue_free()
	await get_tree().process_frame
	var b := _make_level(LEVEL_B, [["test.b.arrive", Vector3(40, 0.05, 10), PI / 2]],
		[["test.exit.b_to_a", LEVEL_A, "test.a.start", Vector3(40, 0, 30)]], GATED_LEVEL_SOURCE)
	var p2 := _player_in(b, Vector3(0, 0.05, 0))
	GameSession.on_level_ready(b, p2)
	var arrive := b.checkpoint("test.b.arrive") as CheckpointMarker
	assert_true(arrive != null, "level B has its arrival marker")
	assert_near(_flat(p2.global_position, arrive.global_position), 0.0, 0.01, "the giant stands at the destination")
	assert_near(p2.facing_yaw, arrive.spawn_transform().basis.get_euler().y, 1e-4, "facing its way")
	assert_eq(loaded_cps, [["test.b.arrive", "travel"]], "checkpoint_loaded reports the travel")
	assert_eq(int(p2.progression.level), 6, "the character came along (world_start: level 6)")
	assert_eq(p2.current_growth_stage(), 3, "at stage 3")
	assert_eq(str(p2.controller.loadout.slot_8), "", "with its loadout")
	assert_near(p2.entity.combatant.pools.health, health, 1e-3, "and its wounds (a travel is no death: no floor)")
	assert_eq(WorldState.get_flag("test.p20.flag"), "kept", "the flags")
	assert_eq(WorldState.count_of("item.wood_scrap"), 3, "the inventory")
	assert_true(WorldState.is_destroyed("test.p20.fence"), "and the world deltas")
	assert_eq(GameSession.progress.levels_visited, [LEVEL_A, LEVEL_B], "both levels visited")
	# level_entered waits until the level says it is ready.
	assert_eq(entered.size(), 1, "level_entered waits for B's is_ready()")
	assert_true(GameSession.level_entered_pending(), "pending")
	await get_tree().process_frame
	assert_eq(entered.size(), 1, "still waiting")
	b.set("ready_now", true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(entered.back(), [LEVEL_B, "travel"], "then level_entered(B, travel)")
	assert_false(GameSession.level_entered_pending(), "nothing waits")
	assert_eq(GameSession.entered_log.size(), 2, "the session's log of entries")
	# Checkpoints and saves work on the second level too.
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.b.arrive", "waystone")
	await step_ticks(2)
	assert_true(QuestConditions.truthy(WorldState.get_flag("visited.test.b.arrive")), "a reached checkpoint is visited")
	assert_eq(saved.size(), 1, "the waystone checkpoint is taken on level B")
	assert_eq(str(GameSession.checkpoint_doc.level), LEVEL_B, "in level B")


func test_travel_is_refused_with_its_reason() -> void:
	var s := _start_on_level_a()
	var p: GiantPlayer = s.player
	var exit: LevelExit = s.exit
	await step_ticks(1)
	var reloads := GameSession.scene_reloads.size()
	assert_true(p.controller.enter_grabbed("test.holder"), "grabbed")
	var r := GameSession.travel_to(LEVEL_B, "test.b.arrive", "exit")
	assert_false(r.ok, "no travel while grabbed")
	assert_eq(str(r.message), "Not while you are held.", "and why")
	p.controller.release_grabbed("test", 0.0)
	p.controller.holding_id = "test.held"
	exit.interact(p)
	assert_false(bool(GameSession.last_travel_result.ok), "no travel while holding something")
	assert_eq(str(GameSession.last_travel_result.message), "Put down what you are holding first.", "and why")
	assert_true(notices.has("Put down what you are holding first."), "the HUD says it")
	p.controller.holding_id = ""
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.narrow", "exit").message), GameSession.NARROW_PATHS,
		"a stage 3 giant cannot arrive where max_stage is 2")
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.nowhere", "exit").message), GameSession.UNKNOWN_PLACE,
		"a checkpoint the destination's index does not know")
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.far", "fast_travel").message), GameSession.NOT_VISITED,
		"fast travel only to a visited checkpoint")
	WorldState.set_flag("visited.test.b.far", true)
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.far", "fast_travel").message), GameSession.NOT_OPEN,
		"nor to one whose flags do not hold")
	assert_true(str(GameSession.travel_to(LEVEL_B, "test.b.arrive", "teleport").message).contains("Unknown travel reason"),
		"an unknown reason")
	assert_eq(str(GameSession.travel_to("level.nowhere", "x.cp", "exit").message), "That land is not in this build.",
		"a level this build lacks")
	assert_eq(GameSession.scene_reloads.size(), reloads, "no refused travel reloads")
	assert_true(leaving.is_empty(), "nor leaves")
	assert_eq(GameSession.level_id, LEVEL_A, "the giant is still on level A")
	# An aware enemy holds back a checkpoint and a debug travel, never an exit.
	var stub := TestSpawn.stub_enemy(world, p.global_position + Vector3(0, 0, -20), "test.p20.watcher")
	stub.brain.aware = true
	assert_true(GameSession.travel_blockers("debug").has("aware:test.p20.watcher"), "a debug travel waits for it")
	assert_true(GameSession.travel_blockers("exit").is_empty(), "an exit does not")
	# An open menu holds back an exit, not the fast travel chosen on it.
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	stack.push(OverlayScreen.new())
	assert_true(GameSession.travel_blockers("exit").has("screen"), "an exit waits for the open screen")
	assert_false(GameSession.travel_blockers("fast_travel").has("screen"), "fast travel (from the map screen) does not")
	stack.close_all()
	# A locked exit never asks to travel.
	var locked := LevelExit.new()
	locked.exit_id = "test.exit.locked"
	locked.to_level = LEVEL_B
	locked.to_checkpoint = "test.b.arrive"
	locked.requires_flags = PackedStringArray(["test.p20.door_open"])
	locked.locked_message = "The door is barred."
	(s.level as Node3D).add_child(locked)
	assert_false(locked.can_interact(p), "a locked exit cannot be used")
	assert_eq(locked.blocked_reason(p), "The door is barred.", "it says why")
	locked.interact(p)
	assert_eq(GameSession.scene_reloads.size(), reloads, "and asks for nothing")
	# Fast travel waits for the aware enemy, then goes to a visited, open checkpoint.
	WorldState.set_flag("test.b.gate_open", true)
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.far", "fast_travel").message), "Not while enemies are close.",
		"no fast travel with an enemy aware of the giant")
	stub.brain.aware = false
	var ok := GameSession.travel_to(LEVEL_B, "test.b.far", "fast_travel")
	assert_true(ok.ok, "fast travel to a visited, open checkpoint: %s" % ok.message)
	assert_eq(GameSession.scene_reloads.back(), "fast_travel", "a fast travel reload")
	assert_eq(leaving.back(), [LEVEL_A, LEVEL_B, "fast_travel"], "level_leaving says so")
	GameSession.mode = GameSession.Mode.SANDBOX
	assert_eq(str(GameSession.travel_to(LEVEL_B, "test.b.arrive", "exit").message), "There is nowhere to travel from here.",
		"no travel outside the campaign")


func test_a_new_game_starts_at_the_start_checkpoint_given() -> void:
	# --mode=world --new-game --start=<checkpoint>: the giant starts there, from the index when the
	# checkpoint's node is not loaded.
	GameSession.start_world_for_tests("test.b.near")
	GameSession.level_id = LEVEL_B
	var b := _make_level(LEVEL_B, [["test.b.arrive", Vector3(40, 0.05, 10), PI / 2]], [])
	var p := _player_in(b, Vector3(0, 0.05, 0))
	GameSession.on_level_ready(b, p)
	assert_eq(GameSession.respawn_id, "test.b.near", "the start checkpoint is the respawn")
	assert_near(_flat(p.global_position, Vector3(50, 0, 10)), 0.0, 0.01, "the giant starts at its index position")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.respawn), "test.b.near", "the first checkpoint is taken there")
	assert_eq(entered.back(), [LEVEL_B, "new_game"], "level_entered(new_game)")
	assert_true(bool(GameSession.progress.prologue_complete), "a world start has finished the prologue")
	# Every load is entered: the sandbox's too (reason debug).
	GameSession.mode = GameSession.Mode.SANDBOX
	GameSession.on_level_ready(b, p)
	assert_eq(entered.back(), [GameSession.SANDBOX_SCENE, "debug"], "a sandbox load is entered as debug")


# --------------------------------------------------------------------------- respawns

func test_a_respawn_blocker_moves_the_respawn_to_the_nearest_unblocked_checkpoint() -> void:
	GameSession.start_world_for_tests()
	GameSession.level_id = LEVEL_B
	var b := _make_level(LEVEL_B, [["test.b.arrive", Vector3(40, 0.05, 10), PI / 2]], [])
	var p := _player_in(b, Vector3(40, 0.05, 10))
	GameSession.on_level_ready(b, p)
	assert_eq(GameSession.respawn_id, "test.b.arrive", "level B's start checkpoint")
	assert_eq(GameSession.respawn_checkpoint(), "test.b.arrive", "nothing blocks it")
	assert_eq(GameSession.respawn_blocker("test.b.narrow"), GameSession.NARROW_PATHS, "the built-in rule: max_stage 2 < stage 3")
	var guards := func(id: String) -> String: return "Hostile guards hold it." if id == "test.b.arrive" else ""
	GameSession.register_respawn_blocker(guards)
	assert_eq(GameSession.respawn_blocker("test.b.arrive"), "Hostile guards hold it.", "a registered blocker refuses it")
	assert_eq(GameSession.respawn_checkpoint(), "test.b.near", "the nearest unblocked checkpoint (the narrow one is too small)")
	WorldState.set_flag("visited.test.b.far", true)
	assert_eq(GameSession.respawn_checkpoint(), "test.b.far", "a visited checkpoint before a nearer unvisited one")
	WorldState.set_flag("visited.test.b.near", true)
	assert_eq(GameSession.respawn_checkpoint(), "test.b.near", "the nearest visited one")
	var everything := func(_id: String) -> String: return "Nowhere is safe."
	GameSession.register_respawn_blocker(everything)
	assert_eq(GameSession.respawn_checkpoint(), "test.b.arrive", "every checkpoint refused: the saved respawn")
	GameSession.unregister_respawn_blocker(everything)
	# A reload respawns at the allowed checkpoint, from the index when its node is not loaded.
	GameSession.reload_checkpoint("debug")
	assert_eq(GameSession.scene_reloads.back(), "debug", "a reload")
	GameSession.on_level_ready(b, p)
	assert_eq(GameSession.respawn_id, "test.b.near", "the respawn moved to the near stone")
	assert_eq(loaded_cps.back(), ["test.b.near", "debug"], "checkpoint_loaded names it")
	assert_true(b.checkpoint("test.b.near") == null, "its node is not loaded in this level")
	assert_near(_flat(p.global_position, Vector3(50, 0, 10)), 0.0, 0.01, "the giant stands at its index position")
	assert_near(p.facing_yaw, GameSession.respawn_transform("test.b.near").basis.get_euler().y, 1e-4,
		"turned to its index yaw")
	assert_true(GameSession.respawn_transform("test.b.arrive").origin.is_equal_approx((b.checkpoint("test.b.arrive") as CheckpointMarker).spawn_transform().origin),
		"a loaded checkpoint's node decides its transform")
	assert_false(GameSession.respawn_transform("test.b.unknown").origin.is_finite(), "an unknown one: INF")


# --------------------------------------------------------------------------- Continue

func _world_save(level: String, respawn: String) -> Dictionary:
	var doc := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/v1_force_complete.json").data)
	doc.level = level
	doc.checkpoint = {"respawn": respawn, "reason": "travel"}
	doc.progress.levels_visited = ["level.valley", level]
	doc.progress.world_entered = true
	return doc


func test_continue_on_a_world_save() -> void:
	GameSession.persist = true
	TestFixtures.record_override(GameSession.WORLD_LEVEL_ID, {"schema_version": 1, "type": "level",
		"display_name": "The Old Kingdom", "scene": STAND_IN, "start_checkpoint": "world.cp.kingsgate_shelf"})
	assert_true(SaveSlots.write(_world_save("level.world", "world.cp.kingsgate_shelf")).ok, "a save in the world")
	var r := GameSession.continue_valley()
	assert_true(r.ok, "Continue: %s" % r.message)
	assert_eq(str(r.message), "", "no fallback message")
	assert_eq(GameSession.level_id, "level.world", "it loads level.world")
	assert_eq(GameSession.level_scene_path(), STAND_IN, "its scene")
	assert_eq(GameSession.respawn_id, "world.cp.kingsgate_shelf", "at the saved checkpoint")
	assert_true(bool(GameSession.progress.world_entered), "the world was entered")
	# The same save in a build without the world (simulated: P25 ships it): back to the Valley,
	# with a message.
	TestFixtures.restore_all()
	TestFixtures.record_override(GameSession.WORLD_LEVEL_ID, {"scene": NO_WORLD_SCENE})
	GameSession.reset_for_tests()
	GameSession.persist = true
	assert_true(SaveSlots.write(_world_save("level.world", "world.cp.kingsgate_shelf")).ok, "written again")
	assert_true(GameSession.save_level_available(SaveSlots.read().data), "the title can still Continue it")
	r = GameSession.continue_valley()
	assert_true(r.ok, "Continue falls back")
	assert_true(str(r.message).contains(GameSession.WORLD_MISSING), "and says why: %s" % r.message)
	assert_eq(GameSession.level_id, "level.valley", "in the Valley")
	assert_eq(GameSession.level_scene_path(), "res://scenes/world/valley.tscn", "the Valley scene")
	var valley_index := WorldIndex.for_level("level.valley")
	var expected := GameSession.VALLEY_RETURN_CHECKPOINT if valley_index.has_checkpoint(GameSession.VALLEY_RETURN_CHECKPOINT) \
		else str(GameData.get_record("level.valley").start_checkpoint)
	assert_eq(GameSession.respawn_id, expected, "at the Valley's way back (until P26 builds the Kings' Door: its start)")
	assert_eq(str(GameSession.checkpoint_doc.level), "level.valley", "the session's document names the Valley")
	# A save naming a scene path that is gone does not fall back (a test level of another build).
	SaveSlots.write(_world_save("res://scenes/test/no_such_level.tscn", "test.cp_a"))
	r = GameSession.continue_valley()
	assert_false(r.ok, "a missing test level does not load")
	assert_true(str(r.message).contains("not in this build"), "and says so: %s" % r.message)
