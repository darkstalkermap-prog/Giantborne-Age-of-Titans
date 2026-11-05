extends IntegrationSuite
## Checkpoint triggers, respawn points and deferral (plan §2.9, decision 13) on the flow test
## level: every row of the trigger table takes exactly one checkpoint with its respawn point
## (events emitted synthetically; shrines are FakeShrines, P05 is not referenced), other quests
## take none; a request waits while the player executes, is grabbed, holds something, is dead
## or a screen is open, and while an aware enemy is within 40 m; later requests replace earlier
## ones but keep the newest respawn; the sandbox never checkpoints or writes; a waystone needs
## its flag and fires once per load.

const FLOW := "res://scenes/test/flow_test_level.tscn"

## An action that runs in EXECUTING (hit_shape "grab"), for the deferral test.
const HOLD_ACTION := {"schema_version": 1, "id": "ability.test_session_hold", "type": "action",
	"kind": "ability", "display_name": "Test hold", "hit_shape": "grab", "windup_s": 0.3,
	"active_s": 0.2, "recovery_s": 0.3, "tags": ["Ability"], "category": "ability",
	"uses_weapon": false, "movement": {"windup_speed_mult": 0.0, "active_speed_mult": 0.0,
		"recovery_speed_mult": 0.0}}

## A modal screen that does not pause the game (like the title screen), so ticks still run.
class OverlayScreen:
	extends UiScreen

	func pauses_game() -> bool:
		return false


var level: FlowTestLevel
var player: GiantPlayer
## [tick, checkpoint_id, ok, message, the player's controller state at that moment]
var saved: Array = []
var reached: Array[String] = []


func before_each() -> void:
	await super()
	saved.clear()
	reached.clear()
	Events.checkpoint_saved.connect(_on_saved)
	Events.checkpoint_reached.connect(_on_reached)


func after_each() -> void:
	for sig: Signal in [Events.checkpoint_saved, Events.checkpoint_reached]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	level = null
	player = null
	await super()


func _on_saved(tick: int, checkpoint_id: String, ok: bool, message: String) -> void:
	var state := player.controller.state if player != null and is_instance_valid(player) else -1
	saved.append([tick, checkpoint_id, ok, message, state])


func _on_reached(_tick: int, checkpoint_id: String, _kind: String) -> void:
	reached.append(checkpoint_id)


## Instantiates the flow level under the test world and runs on_level_ready as main.gd does.
func _load_level(ready := true) -> void:
	level = (load(FLOW) as PackedScene).instantiate() as FlowTestLevel
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	TestSpawn.disable_all_ai(level)
	if ready:
		GameSession.on_level_ready(level, player)


func _unload_level() -> void:
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	level = null
	player = null


## Emits a trigger with the respawn reset to test.cp_a first; then checks the count and respawn.
func _expect(label: String, emit: Callable, want_count: int, want_respawn: String, ticks := 2) -> void:
	GameSession.respawn_id = "test.cp_a"
	saved.clear()
	emit.call()
	await step_ticks(ticks)
	assert_eq(saved.size(), want_count, "%s takes %d checkpoint(s)" % [label, want_count])
	assert_eq(GameSession.respawn_id, want_respawn, "%s: respawn point" % label)
	if want_count > 0:
		assert_eq(str(saved.back()[1]), want_respawn, "%s: checkpoint_saved names the respawn point" % label)
		assert_eq(str((GameSession.checkpoint_doc.checkpoint as Dictionary).respawn), want_respawn,
			"%s: the document stores it" % label)


func test_level_start_takes_a_first_checkpoint_in_memory() -> void:
	_load_level()
	assert_true(GameSession.test_checkpoints, "the flow level opts in to checkpoints")
	assert_true(GameSession.checkpoints_enabled(), "so checkpoints are on in the sandbox mode")
	assert_eq(saved.size(), 1, "one checkpoint when the level is ready")
	assert_eq(GameSession.respawn_id, "test.cp_a", "at the level's start checkpoint")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "level_start", "reason")
	assert_false(SaveSlots.exists(), "a test level in the sandbox never writes the slot")
	await _unload_level()
	assert_false(GameSession.test_checkpoints, "leaving the level turns them off again")
	assert_false(GameSession.checkpoints_enabled(), "back to the plain sandbox")


func test_each_trigger_takes_one_checkpoint_with_its_respawn() -> void:
	_load_level()
	var shrine := FakeShrine.make("test.shrine", "shrine.test", player.global_position + Vector3(10, 0, 0))
	world.add_child(shrine)
	await step_ticks(1)
	await _expect("checkpoint_reached (waystone)",
		func() -> void: Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone"), 1, "test.cp_b")
	await _expect("checkpoint_reached (a shrine's first activation)",
		func() -> void: Events.checkpoint_reached.emit(Sim.tick, "test.shrine", "shrine"), 1, "test.shrine")
	await _expect("shrine_activated (by record id)",
		func() -> void: Events.shrine_activated.emit(Sim.tick, "shrine.test"), 1, "test.shrine")
	await _expect("shrine_rested (by world id)",
		func() -> void: Events.shrine_rested.emit(Sim.tick, "test.shrine"), 1, "test.shrine")
	await _expect("growth_changed beside a shrine",
		func() -> void: Events.growth_changed.emit(Sim.tick, "player", 1, 2), 1, "test.shrine")
	await _expect("boss_defeated",
		func() -> void: Events.boss_defeated.emit(Sim.tick, "valley.arena.ogre_king"), 1, "valley.shrine.kingsfall")
	await _expect("quest_stage_changed for quest.main",
		func() -> void: Events.quest_stage_changed.emit(Sim.tick, "quest.main", "ogre"), 1, "test.cp_a")
	await _expect("quest_stage_changed for another quest",
		func() -> void: Events.quest_stage_changed.emit(Sim.tick, "quest.village", "fields"), 0, "test.cp_a", 5)
	await _expect("an unknown shrine id",
		func() -> void: Events.shrine_rested.emit(Sim.tick, "shrine.nowhere"), 1, "test.cp_a")
	await _expect("growth_changed of another entity",
		func() -> void: Events.growth_changed.emit(Sim.tick, "someone_else", 1, 2), 0, "test.cp_a", 5)
	shrine.position = Vector3(200, 0, 200)
	await _expect("growth_changed far from every shrine (a debug grow)",
		func() -> void: Events.growth_changed.emit(Sim.tick, "player", 2, 3), 0, "test.cp_a", 5)
	# The shrine screen: taken at once, before the screen opens (no tick needed).
	shrine.position = player.global_position + Vector3(10, 0, 0)
	GameSession.respawn_id = "test.cp_a"
	saved.clear()
	Events.ui_screen_requested.emit("shrine", {"shrine": shrine})
	assert_eq(saved.size(), 1, "ui_screen_requested(shrine) checkpoints immediately")
	assert_eq(GameSession.respawn_id, "test.shrine", "at that shrine")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "shrine_screen", "reason shrine_screen")
	saved.clear()
	Events.ui_screen_requested.emit("pause", {})
	await step_ticks(2)
	assert_eq(saved.size(), 0, "other screens take none")


func test_a_request_waits_while_the_player_is_executing() -> void:
	_load_level()
	TestFixtures.record_override(HOLD_ACTION.id, HOLD_ACTION)
	player.controller.force_action(GameData.get_action(HOLD_ACTION.id))
	assert_eq(player.controller.state, CombatController.State.EXECUTING, "a grab-shaped action executes")
	assert_true(GameSession.checkpoint_blockers().has("executing"), "executing blocks")
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(10)
	assert_eq(saved.size(), 0, "nothing is taken while executing")
	assert_eq(str(GameSession.pending_checkpoint().get("respawn", "")), "test.cp_b", "the request waits")
	var done: bool = await TestWait.until(self, func() -> bool: return saved.size() > 0, 120)
	assert_true(done, "taken once the action is over")
	assert_eq(int(saved[0][4]), CombatController.State.LOCOMOTION, "in LOCOMOTION, not before")
	assert_eq(GameSession.respawn_id, "test.cp_b", "with the waystone as the respawn point")
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing pending any more")


func test_aware_enemies_within_40_m_defer_and_unaware_ones_do_not() -> void:
	_load_level()
	var stub := TestSpawn.stub_enemy(world, player.global_position + Vector3(0, 0, -30), "test.stub_aware")
	await step_ticks(2)
	stub.brain.aware = true
	assert_true(GameSession.checkpoint_blockers().has("aware:test.stub_aware"), "an aware enemy 30 m away blocks")
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(10)
	assert_eq(saved.size(), 0, "the checkpoint waits")
	stub.brain.aware = false
	await step_ticks(2)
	assert_eq(saved.size(), 1, "taken once the enemy is unaware")
	saved.clear()
	stub.brain.aware = true
	Events.quest_stage_changed.emit(Sim.tick, "quest.main", "next")
	await step_ticks(5)
	assert_eq(saved.size(), 0, "aware again: waits")
	stub.global_position = player.global_position + Vector3(0, 0, -45)
	await step_ticks(2)
	assert_eq(saved.size(), 1, "taken once the aware enemy is more than 40 m away")
	saved.clear()
	stub.global_position = player.global_position + Vector3(0, 0, -10)
	stub.brain.aware = false
	assert_true(GameSession.checkpoint_blockers().is_empty(), "an unaware enemy 10 m away does not block")
	Events.quest_stage_changed.emit(Sim.tick, "quest.main", "after")
	await step_ticks(2)
	assert_eq(saved.size(), 1, "taken at once")
	stub.brain.aware = true
	queue_hit("tester", "test.stub_aware", stub.global_position + Vector3(0, 0, -2), 5000.0)
	await step_ticks(2)
	assert_false(stub.entity.is_alive(), "the stub died")
	assert_true(stub.brain.aware, "its brain still says aware")
	assert_false(GameSession.checkpoint_blockers().has("aware:test.stub_aware"), "but the dead never block")


func test_dead_grabbed_holding_and_screens_block() -> void:
	_load_level()
	var c := player.controller
	c.holding_id = "test.held"
	assert_true(GameSession.checkpoint_blockers().has("holding"), "holding something blocks")
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(5)
	assert_eq(saved.size(), 0, "waits while holding")
	c.holding_id = ""
	await step_ticks(2)
	assert_eq(saved.size(), 1, "taken after the drop")
	assert_true(c.enter_grabbed("test.holder"), "grabbed")
	assert_true(GameSession.checkpoint_blockers().has("grabbed"), "being grabbed blocks")
	c.release_grabbed("test", 0.0)
	assert_false(GameSession.checkpoint_blockers().has("grabbed"), "released")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	var overlay := OverlayScreen.new()
	stack.push(overlay)
	assert_true(GameSession.checkpoint_blockers().has("screen"), "an open modal screen blocks")
	saved.clear()
	Events.shrine_rested.emit(Sim.tick, "test.cp_b")
	await step_ticks(1)
	assert_eq(saved.size(), 0, "waits while the screen is open")
	stack.close_all()
	await step_ticks(2)
	assert_eq(saved.size(), 1, "taken once it closed")
	queue_hit("tester", "player", player.global_position + Vector3(0, 0, -2), 50000.0)
	await step_ticks(2)
	assert_eq(c.state, CombatController.State.DEAD, "dead")
	assert_true(GameSession.checkpoint_blockers().has("dead"), "death blocks")


func test_later_requests_replace_earlier_ones_and_keep_the_respawn() -> void:
	_load_level()
	player.controller.holding_id = "test.held"
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	Events.quest_stage_changed.emit(Sim.tick, "quest.main", "next")
	await step_ticks(3)
	assert_eq(saved.size(), 0, "both wait")
	assert_eq(str(GameSession.pending_checkpoint().reason), "quest_stage", "the later request replaced the reason")
	assert_eq(str(GameSession.pending_checkpoint().respawn), "test.cp_b", "and kept the waystone's respawn")
	player.controller.holding_id = ""
	await step_ticks(3)
	assert_eq(saved.size(), 1, "one checkpoint for both")
	assert_eq(GameSession.respawn_id, "test.cp_b", "at the waystone")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "quest_stage", "for the latest reason")


func test_the_sandbox_takes_no_checkpoints_and_writes_nothing() -> void:
	GameSession.persist = true
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	assert_false(GameSession.checkpoints_enabled(), "no checkpoints in the sandbox")
	var shrine := FakeShrine.make("sandbox.shrine", "shrine.sandbox", Vector3(5, 0, 0))
	world.add_child(shrine)
	Events.shrine_rested.emit(Sim.tick, "shrine.sandbox")
	Events.shrine_activated.emit(Sim.tick, "shrine.sandbox")
	Events.checkpoint_reached.emit(Sim.tick, "sandbox.shrine", "shrine")
	Events.ui_screen_requested.emit("shrine", {"shrine": shrine})
	await step_ticks(3)
	assert_eq(saved.size(), 0, "the sandbox shrine heals but never saves (decision 13)")
	assert_false(GameSession.has_checkpoint(), "no checkpoint document")
	assert_false(SaveSlots.exists(), "and no file")
	p.queue_free()
	shrine.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# The contrast: the Valley flow (here on the test level) writes the slot.
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_override = FLOW
	_load_level()
	assert_true(SaveSlots.exists(), "the Valley writes the first checkpoint")
	saved.clear()
	Events.shrine_rested.emit(Sim.tick, "test.cp_b")
	await step_ticks(2)
	assert_eq(saved.size(), 1, "and every later one")
	assert_true(bool(saved[0][2]), "written")
	assert_eq(str(saved[0][3]), "", "no message: it is on disk")
	assert_eq(str(SaveSlots.read().data.checkpoint.respawn), "test.cp_b", "the file holds the new respawn point")


func test_a_waystone_needs_its_flag_and_fires_once_per_load() -> void:
	_load_level()
	var way := level.get_node("Waystones/CpWay") as Waystone
	assert_true(way.is_in_group("waystones") and way.is_in_group("checkpoints"), "groups")
	assert_eq(way.requires_flags, PackedStringArray(["test.way_open"]), "needs test.way_open")
	assert_false(way.is_open(), "closed without the flag")
	assert_false((way.get_node("Glow") as Node3D).visible, "no glow while closed")
	GameSession.place_player(player, way.spawn_transform())
	await step_ticks(40)
	assert_false(way.is_reached(), "standing inside does not reach a closed waystone")
	assert_eq(reached.size(), 0, "no checkpoint_reached")
	saved.clear()
	WorldState.set_flag("test.way_open", true)
	assert_true(way.is_reached(), "the flag opens it and the player inside reaches it at once")
	assert_eq(reached, ["test.cp_way"] as Array[String], "checkpoint_reached once")
	assert_true((way.get_node("Glow") as Node3D).visible, "glowing")
	await step_ticks(2)
	assert_eq(saved.size(), 1, "GameSession took the checkpoint")
	assert_eq(GameSession.respawn_id, "test.cp_way", "respawn at the waystone")
	await step_ticks(70)
	GameSession.place_player(player, (level.get_node("Checkpoints/CpB") as CheckpointMarker).spawn_transform())
	await step_ticks(35)
	GameSession.place_player(player, way.spawn_transform())
	await step_ticks(35)
	assert_eq(reached.size(), 1, "still once in this load, after leaving and coming back")
	await _unload_level()
	_load_level()
	var way2 := level.get_node("Waystones/CpWay") as Waystone
	assert_false(way2.is_reached(), "a new load starts unreached")
	assert_true(way2.is_open(), "the flag is world state: still open")
	GameSession.place_player(player, way2.spawn_transform())
	var ok: bool = await TestWait.until(self, func() -> bool: return way2.is_reached(), 40)
	assert_true(ok, "the 2 Hz check reaches it again in the new load")
	assert_eq(reached.size(), 2, "once per load")
