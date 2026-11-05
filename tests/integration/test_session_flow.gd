extends IntegrationSuite
## The session flow (plan §2.9, §3.6, §15 "save/load restores character, loadout, flags and
## gate; loot never twice"): death -> reload restores the loadout and the world from the
## checkpoint and puts the player at the respawn marker; a checkpoint holding 15 % health
## reloads at 60 % with full stamina after a death, and Continue from the title restores 15 %
## exactly; a fence broken before the checkpoint stays broken with no second loot. Also: the
## title screen (New Game -> pending restore, Continue, Valley not built yet), unknown ids in a
## save, the command-line modes (--autoplay still boots the sandbox), the pause menu and the
## death hint by mode, the checkpoint toast and a failed write.
##
## GameSession.reset_for_tests() logs scene reloads instead of reloading the test runner, so each
## test frees and instantiates the flow level itself, as main.gd does on a reload.

const FLOW := "res://scenes/test/flow_test_level.tscn"

var level: FlowTestLevel
var player: GiantPlayer
var saved: Array = []     ## [checkpoint_id, ok, message]
var loaded: Array = []    ## [checkpoint_id, source]
var notices: Array[String] = []   ## Events.hud_message texts
var layer: CanvasLayer
var stack: ScreenStack


func before_each() -> void:
	await super()
	saved.clear()
	loaded.clear()
	notices.clear()
	Events.checkpoint_saved.connect(_on_saved)
	Events.checkpoint_loaded.connect(_on_loaded)
	Events.hud_message.connect(_on_notice)
	layer = CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)


func after_each() -> void:
	for sig: Signal in [Events.checkpoint_saved, Events.checkpoint_loaded, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	level = null
	player = null
	await super()


func _on_saved(_tick: int, checkpoint_id: String, ok: bool, message: String) -> void:
	saved.append([checkpoint_id, ok, message])


func _on_loaded(_tick: int, checkpoint_id: String, source: String) -> void:
	loaded.append([checkpoint_id, source])


func _on_notice(text: String, _kind: String) -> void:
	notices.append(text)


## Instantiates the flow level and calls on_level_ready, as main.gd does after a (re)load.
func _load_level() -> void:
	level = (load(FLOW) as PackedScene).instantiate() as FlowTestLevel
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	GameSession.on_level_ready(level, player)


## Frees the level (the scene reload frees everything) and waits until it is gone.
func _unload_level() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	level = null
	player = null


func _marker(node_path: String) -> CheckpointMarker:
	return level.get_node(node_path) as CheckpointMarker


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _start_new_game_on_the_flow_level() -> void:
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	assert_true(GameSession.is_valley(), "New Game puts the session in the Valley mode")
	assert_true(GameSession.pending_restore, "with a pending restore")
	_load_level()


func test_death_reload_restores_loadout_world_position_and_the_floor() -> void:
	_start_new_game_on_the_flow_level()
	assert_eq(saved.size(), 1, "New Game took the first checkpoint")
	await step_ticks(2)
	var fence := level.get_node("Fence") as BreakableProp
	queue_hit("tester", "test.flow_fence", fence.global_position + Vector3(0, 0, -2), 400.0)
	await step_ticks(2)
	assert_true(fence.destroyed, "the fence broke before the checkpoint")
	assert_eq(loot.size(), 1, "its loot once")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "one wood scrap")
	player.set_loadout_slot("slot_3", "ability.stone_skin")
	var pools := player.entity.combatant.pools
	pools.health = pools.health_max * 0.15
	pools.stamina = pools.stamina_max * 0.2
	saved.clear()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(2)
	assert_eq(saved.size(), 1, "the waystone checkpoint was taken")
	var doc := GameSession.checkpoint_doc
	assert_true(bool(doc.world.deltas["test.flow_fence"].destroyed), "the snapshot holds the broken fence")
	assert_eq(str(doc.character.loadout.slots[2]), "ability.stone_skin", "and the loadout")
	# After the checkpoint: changes that a death must roll back.
	player.set_loadout_slot("slot_3", "")
	WorldState.set_flag("test.after_checkpoint", true)
	WorldState.add_item("item.wood_scrap", 2, "test")
	queue_hit("tester", "player", player.global_position + Vector3(0, 0, -2), 50000.0)
	await step_ticks(2)
	assert_eq(player.controller.state, CombatController.State.DEAD, "the player died")
	assert_eq(int(GameSession.stats.deaths), 1, "the session counts the death")
	Events.reload_checkpoint_requested.emit("death")
	assert_eq(GameSession.scene_reloads.back(), "death", "the death confirm reloads the scene")
	assert_true(GameSession.pending_restore, "with a pending restore")
	assert_false(WorldState.has_flag("test.after_checkpoint"), "flags roll back to the checkpoint")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "so does the inventory")
	await _unload_level()
	_load_level()
	var cp_b := _marker("Checkpoints/CpB")
	assert_near(_flat(player.global_position, cp_b.global_position), 0.0, 0.01, "the player is at the respawn marker")
	assert_near(player.facing_yaw, cp_b.spawn_transform().basis.get_euler().y, 1e-4, "facing its way")
	assert_near(player.camera_rig.yaw, player.facing_yaw, 1e-4, "the camera too")
	assert_true(player.spawn_transform.origin.is_equal_approx(cp_b.spawn_transform().origin),
		"the out-of-world reset point moved with it")
	assert_eq(str(player.controller.loadout.slot_3), "ability.stone_skin", "the loadout came back")
	pools = player.entity.combatant.pools
	assert_near(pools.health, pools.health_max * 0.6, 1e-3, "15 % health reloads at the 60 % floor")
	assert_near(pools.stamina, pools.stamina_max, 1e-3, "and full stamina")
	assert_true(pools.essence >= pools.essence_max * 0.5 - 1e-3, "at least half essence")
	assert_near(pools.fury, 0.0, 1e-9, "no fury")
	var fence2 := level.get_node("Fence") as BreakableProp
	assert_true(fence2.destroyed, "the fence broken before the checkpoint stays broken")
	await step_ticks(5)
	assert_eq(loot.size(), 1, "and never awards loot again")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "the inventory holds the one scrap")
	assert_eq(loaded, [["test.cp_b", "death"]], "checkpoint_loaded reports the death reload")
	assert_eq(int(GameSession.stats.checkpoint_loads), 1, "one checkpoint load")
	assert_eq(int(GameSession.stats.deaths), 1, "deaths survive the reload")
	assert_eq(int(player.controller.level), 1, "the character level came back (new game: level 1)")


func test_continue_from_the_title_restores_the_save_exactly() -> void:
	GameSession.persist = true
	_start_new_game_on_the_flow_level()
	assert_true(SaveSlots.exists(), "New Game wrote the slot")
	var pools := player.entity.combatant.pools
	pools.health = pools.health_max * 0.15
	player.set_loadout_slot("slot_4", "ability.runic_bolt")
	WorldState.set_flag("test.saved_flag", "yes")
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(2)
	assert_eq(saved.size(), 2, "the waystone checkpoint was written")
	assert_true(bool(saved.back()[1]) and str(saved.back()[2]) == "", "on disk")
	var health := float(GameSession.checkpoint_doc.character.resources.health)
	assert_near(health, pools.health_max * 0.15, 1.0, "the save holds about 15 % health")
	Events.mode_change_requested.emit("title", {})
	assert_true(GameSession.last_mode_result.ok, "quit to title")
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "title mode")
	assert_eq(GameSession.scene_reloads.back(), "title", "a reload into the title")
	assert_false(WorldState.has_flag("test.saved_flag"), "the title starts from a clean world")
	await _unload_level()
	# A fresh start has no --level: the save itself names its level (the flow test level here).
	GameSession.level_override = ""
	var title := stack.open("title") as TitleScreen
	assert_true(title != null, "the title screen opens")
	assert_false(get_tree().paused, "it does not pause")
	var state := title.state()
	assert_false(state.new_game, "New Game still needs the Valley")
	assert_true(state["continue"], "Continue is enabled: the save loads and its level exists")
	assert_true(str(state.save).contains("test.cp_b"), "and describes it: %s" % state.save)
	assert_eq(title.first_focus(), title.button("Continue"), "Continue has the focus")
	title.button("Continue").pressed.emit()
	assert_true(GameSession.last_mode_result.ok, "Continue started: %s" % GameSession.last_mode_result)
	assert_eq(GameSession.scene_reloads.back(), "continue", "a reload into the save")
	assert_true(GameSession.is_valley() and GameSession.pending_restore, "the Valley mode with a pending restore")
	assert_eq(GameSession.level_scene_path(), FLOW, "the save's level is loaded")
	assert_eq(WorldState.get_flag("test.saved_flag"), "yes", "the world came back")
	stack.close_all()
	_load_level()
	pools = player.entity.combatant.pools
	assert_near(pools.health, health, 1e-4, "Continue restores 15 % health exactly (no death floor)")
	assert_eq(str(player.controller.loadout.slot_4), "ability.runic_bolt", "and the loadout")
	assert_near(_flat(player.global_position, _marker("Checkpoints/CpB").global_position), 0.0, 0.01,
		"at the saved respawn point")
	assert_eq(loaded, [["test.cp_b", "continue"]], "checkpoint_loaded reports the continue")


func test_new_game_from_the_title_takes_the_pending_restore_path() -> void:
	GameSession.level_override = FLOW
	GameSession.mode = GameSession.Mode.TITLE
	WorldState.set_flag("test.old_world", true)
	var title := stack.open("title") as TitleScreen
	assert_true(title.state().new_game, "New Game is enabled when the level exists")
	assert_false(title.state()["continue"], "Continue is disabled without a save")
	assert_eq(title.first_focus(), title.button("New Game"), "New Game has the focus")
	title.button("New Game").pressed.emit()
	assert_true(GameSession.last_mode_result.ok, "New Game started")
	assert_eq(GameSession.scene_reloads, ["new_game"] as Array[String], "one reload into the new game")
	assert_true(GameSession.is_valley(), "the Valley mode")
	assert_true(GameSession.pending_restore, "pending restore")
	assert_false(WorldState.has_flag("test.old_world"), "a clean world")
	var expected := CharacterState.new_game(GameData.get_record("progression.default"), GameData.get_record("player.giant"))
	assert_eq(GameSession.character, expected, "the progression record's new character")
	stack.close_all()
	_load_level()
	assert_false(GameSession.pending_restore, "restored")
	var spawn := level.get_node("Spawns/PlayerSpawn") as Node3D
	assert_near(_flat(player.global_position, spawn.global_position), 0.0, 0.01, "a new game starts at the scene's Player node")
	assert_eq(int(player.controller.level), 1, "level 1")
	var ng: Dictionary = GameData.get_record("progression.default").new_game
	for i in 8:
		assert_eq(str(player.controller.loadout["slot_%d" % (i + 1)]), str(ng.slots[i]), "slot %d from new_game" % (i + 1))
	assert_eq(GameSession.respawn_id, "test.cp_a", "respawn_id = the level's start checkpoint")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "new_game", "the first checkpoint")
	assert_eq(saved.size(), 1, "taken once")
	assert_eq(str(saved[0][2]), GameSession.NO_SAVING, "not written while persist is off")
	assert_false(SaveSlots.exists(), "nothing on disk")


func test_the_title_without_the_valley() -> void:
	GameSession.mode = GameSession.Mode.TITLE
	assert_false(GameSession.valley_available(), "no level.valley yet (P10b)")
	var title := stack.open("title") as TitleScreen
	var state := title.state()
	assert_false(state.new_game, "New Game disabled")
	assert_false(state["continue"], "Continue disabled")
	assert_eq(state.note, TitleScreen.VALLEY_MISSING, "with the note")
	assert_true(state.sandbox, "Sandbox works")
	assert_eq(state.quit, not OS.has_feature("web"), "Quit is hidden on the web only")
	assert_eq(title.first_focus(), title.button("Sandbox"), "Sandbox has the focus")
	assert_eq(str(state.save), "Saving is off for this run (--no-user-settings).", "persist off: no save is read")
	title.cancel()
	assert_true(title.is_open(), "Esc / pad B never closes the title")
	title.call("_show_page", "Settings")
	assert_eq(title.current_page(), "Settings", "the shared settings page")
	title.cancel()
	assert_eq(title.current_page(), "", "cancel goes back to the menu")
	title.call("_show_page", "Controls")
	assert_eq(title.current_page(), "Controls", "the controls page")
	title.call("_show_page", "")
	title.button("New Game").pressed.emit()
	assert_eq(GameSession.scene_reloads.size(), 0, "a disabled New Game does nothing")
	Events.mode_change_requested.emit("valley", {"new_game": true})
	assert_false(GameSession.last_mode_result.ok, "the session refuses the Valley")
	assert_eq(GameSession.last_mode_result.message, GameSession.VALLEY_MISSING, "and says why")
	title.button("Sandbox").pressed.emit()
	assert_true(GameSession.last_mode_result.ok, "Sandbox starts")
	assert_eq(GameSession.mode, GameSession.Mode.SANDBOX, "sandbox mode")
	assert_eq(GameSession.scene_reloads, ["sandbox"] as Array[String], "a reload into the sandbox")
	assert_eq(GameSession.level_scene_path(), GameSession.SANDBOX_SCENE, "the M1 sandbox")


func test_new_game_asks_before_replacing_a_save() -> void:
	GameSession.persist = true
	_start_new_game_on_the_flow_level()
	await _unload_level()
	GameSession.go_to_title()
	var title := stack.open("title") as TitleScreen
	assert_true(title.state()["continue"], "a save exists")
	GameSession.scene_reloads.clear()
	title.button("New Game").pressed.emit()
	assert_eq(GameSession.scene_reloads.size(), 0, "the first press only asks")
	assert_true(title.button("New Game").text.contains("replace"), "the button asks: %s" % title.button("New Game").text)
	title.button("New Game").pressed.emit()
	assert_eq(GameSession.scene_reloads, ["new_game"] as Array[String], "the second press starts over")


func test_unknown_ability_ids_in_a_save_are_dropped_with_a_message() -> void:
	GameSession.persist = true
	_start_new_game_on_the_flow_level()
	await step_ticks(1)
	var doc := GameSession.checkpoint_doc.duplicate(true)
	doc.character.loadout.slots[3] = "ability.removed_in_this_build"
	(doc.character.known_abilities as Array).append("ability.removed_in_this_build")
	assert_true(SaveSlots.write(doc).ok, "a save with an ability this build lacks")
	await _unload_level()
	GameSession.go_to_title()
	var r := GameSession.continue_valley()
	assert_true(r.ok, "it still continues")
	assert_true(str(r.message).contains("ability.removed_in_this_build"), "the message names the id: %s" % r.message)
	assert_eq(GameSession.last_load_message, r.message, "kept for the HUD and the title")
	assert_eq(str(GameSession.character.loadout.slots[3]), "", "the slot is empty")
	assert_false((GameSession.character.known_abilities as Array).has("ability.removed_in_this_build"), "not known")
	_load_level()
	assert_eq(str(player.controller.loadout.slot_4), "", "the player has the empty slot")
	assert_false(player.controller.library.has("ability.removed_in_this_build"), "and no such action")


func test_debug_and_menu_reloads_restore_exactly() -> void:
	_start_new_game_on_the_flow_level()
	var pools := player.entity.combatant.pools
	pools.health = pools.health_max * 0.2
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(2)
	var health := float(GameSession.checkpoint_doc.character.resources.health)
	for reason in ["debug", "menu"]:
		Events.reload_checkpoint_requested.emit(reason)
		assert_eq(GameSession.scene_reloads.back(), reason, "%s reloads" % reason)
		await _unload_level()
		_load_level()
		pools = player.entity.combatant.pools
		assert_near(pools.health, health, 1e-4, "%s restores 20 %% exactly (the floor is for deaths)" % reason)
	assert_eq(loaded, [["test.cp_b", "debug"], ["test.cp_b", "menu"]], "both reported")


func test_a_failed_write_warns_and_play_continues() -> void:
	GameSession.persist = true
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	var f := FileAccess.open("user://test_saves/blocked", FileAccess.WRITE)
	f.store_string("a file where the save folder should be")
	f.close()
	SaveSlots.path_override = "user://test_saves/blocked/valley_1.json"
	var hud := Hud.new()
	layer.add_child(hud)
	_start_new_game_on_the_flow_level()
	await step_ticks(2)
	assert_eq(saved.size(), 1, "the first checkpoint was attempted")
	assert_false(bool(saved[0][1]), "and reported as not written")
	assert_true(str(saved[0][2]) != "", "with the reason: %s" % saved[0][2])
	var toast := hud.get_node_or_null("CheckpointToast")
	assert_true(toast != null, "the HUD has the checkpoint toast")
	assert_true(str(toast.call("visible_text")).contains("NOT saved"), "a warning in the HUD: %s" % toast.call("visible_text"))
	var warned := notices.filter(func(t: String) -> bool: return t.begins_with("Checkpoint not saved: could not"))
	assert_eq(warned.size(), 1, "and a HUD message with the reason: %s" % [notices])
	assert_true(str(warned[0]).ends_with("Play continues.") if not warned.is_empty() else false, "saying play continues")
	assert_true(GameSession.has_checkpoint(), "the checkpoint still lives in memory")
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(2)
	assert_eq(GameSession.respawn_id, "test.cp_b", "play continues: later checkpoints still work")
	queue_hit("tester", "player", player.global_position + Vector3(0, 0, -2), 50000.0)
	await step_ticks(2)
	Events.reload_checkpoint_requested.emit("death")
	assert_true(GameSession.pending_restore, "and a death still reloads it")
	DirAccess.remove_absolute("user://test_saves/blocked")
	hud.queue_free()


func test_the_checkpoint_toast_and_the_death_hint() -> void:
	var hud := Hud.new()
	layer.add_child(hud)
	_load_level()   # sandbox mode + the flow level: checkpoints on, in memory
	await step_ticks(2)
	var toast := hud.get_node_or_null("CheckpointToast")
	assert_true(toast != null and toast is HudWidget, "the toast widget comes from the HUD registry")
	assert_eq(str(toast.call("visible_text")), "Checkpoint (kept in memory)", "the level-start checkpoint was shown")
	Events.checkpoint_saved.emit(Sim.tick, "test.cp_b", true, "")
	assert_eq(str(toast.call("visible_text")), "Checkpoint saved", "a written checkpoint")
	Events.checkpoint_loaded.emit(Sim.tick, "test.cp_b", "death")
	assert_eq(str(toast.call("visible_text")), "Checkpoint loaded", "a reload")
	assert_eq(Hud.death_hint(true, false), "Enter / A: load last checkpoint", "the checkpoint death hint")
	assert_eq(Hud.death_hint(false, false), "Press Enter / A to restart the sandbox", "the sandbox death hint")
	assert_true(Hud.death_hint(false, true).contains("F5"), "debug builds mention F5 in the sandbox")
	queue_hit("tester", "player", player.global_position + Vector3(0, 0, -2), 50000.0)
	await step_ticks(2)
	await get_tree().process_frame
	assert_eq(hud.death_hint_text(), "Enter / A: load last checkpoint", "the overlay shows the checkpoint hint here")
	hud.queue_free()


func test_the_pause_menu_items_follow_the_mode() -> void:
	var menu := stack.open("pause") as PauseMenu
	assert_eq(menu.item_labels(), PackedStringArray(["Resume", "Restart sandbox", "Quit to title"]),
		"the plain sandbox: no checkpoint item")
	stack.close_all()
	_start_new_game_on_the_flow_level()
	menu = stack.open("pause") as PauseMenu
	assert_eq(menu.item_labels(), PackedStringArray(["Resume", "Load last checkpoint", "Quit to title"]),
		"the Valley: load last checkpoint, no sandbox restart")
	assert_false(menu.item("Load last checkpoint").disabled, "a checkpoint exists")
	menu.item("Load last checkpoint").pressed.emit()
	assert_false(stack.any_open(), "the menu closed")
	assert_eq(GameSession.scene_reloads.back(), "menu", "and the checkpoint reloads")
	await _unload_level()
	_load_level()
	menu = stack.open("pause") as PauseMenu
	menu.item("Quit to title").pressed.emit()
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "Quit to title")
	assert_eq(GameSession.scene_reloads.back(), "title", "reloads into the title")


func test_command_line_modes_keep_the_m1_tools_working() -> void:
	var a := GameSession.parse_args(PackedStringArray([]))
	assert_eq(a.mode, "title", "no flags: the title (the play link)")
	assert_true(a.persist, "and saving on")
	a = GameSession.parse_args(PackedStringArray(["--no-user-settings", "--autoplay=120"]))
	assert_eq(a.mode, "sandbox", "--autoplay without --mode boots the sandbox (decision 15)")
	assert_false(a.persist, "--no-user-settings: no writes")
	assert_eq(GameSession.parse_args(PackedStringArray(["--scenario=capture"])).mode, "sandbox",
		"--scenario too (the capture tour)")
	assert_eq(GameSession.parse_args(PackedStringArray(["--autoplay=5", "--mode=title"])).mode, "title",
		"an explicit --mode wins")
	assert_eq(GameSession.parse_args(PackedStringArray(["--level=" + FLOW])).mode, "sandbox",
		"--level alone loads that level without the title")
	a = GameSession.parse_args(PackedStringArray(["--new-game", "--level=" + FLOW]))
	assert_eq(a.mode, "valley", "--new-game means the Valley flow")
	assert_eq(a.level, FLOW, "on the given level")
	a = GameSession.parse_args(PackedStringArray(["--no-user-settings", "--save-dir=user://test_saves/other"]))
	assert_true(a.persist, "--save-dir keeps saving on")
	assert_eq(GameSession.parse_args(PackedStringArray(["--mode=nowhere"])).mode, "title", "an unknown mode: title")
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--no-user-settings", "--autoplay=60"])))
	assert_eq(GameSession.mode, GameSession.Mode.SANDBOX, "applied: sandbox")
	assert_eq(GameSession.level_scene_path(), GameSession.SANDBOX_SCENE, "the M1 sandbox scene")
	assert_false(GameSession.checkpoints_enabled(), "without checkpoints")
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--new-game",
		"--level=" + FLOW, "--save-dir=user://test_saves"])))
	assert_true(GameSession.is_valley() and GameSession.pending_restore, "--mode=valley --new-game starts a new game")
	assert_eq(GameSession.level_scene_path(), FLOW, "on the --level scene")
	assert_eq(SaveSlots.path(), "user://test_saves/valley_1.json", "the save goes to --save-dir")
	assert_true(GameSession.persist, "saving on")
	assert_eq(GameSession.scene_reloads.size(), 0, "applying arguments never reloads (main is not loaded yet)")
	GameSession.reset_for_tests()
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--no-user-settings"])))
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "without the Valley --mode=valley falls back to the title")


func test_continue_from_the_command_line() -> void:
	GameSession.persist = true
	_start_new_game_on_the_flow_level()
	Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
	await step_ticks(2)
	await _unload_level()
	GameSession.go_to_title()
	GameSession.level_override = ""
	GameSession.scene_reloads.clear()
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--continue"])))
	assert_true(GameSession.is_valley() and GameSession.pending_restore, "--mode=valley --continue loads the save")
	assert_eq(GameSession.level_scene_path(), FLOW, "the save's own level, without --level")
	assert_eq(GameSession.respawn_id, "test.cp_b", "at its respawn point")
	assert_eq(GameSession.scene_reloads.size(), 0, "no reload at start-up")
	GameSession.reset_for_tests()
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--continue"])))
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "--continue without a save falls back to the title")
