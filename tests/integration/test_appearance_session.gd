extends IntegrationSuite
## The look through the session (P42; plan M10 §2.2, §2.10, §2.11, decisions 14-16): a New Game with an
## appearance option stores it (Valley and world) and the giant wears it; --appearance= gives the sandbox,
## a bot's or a command-line New Game the preset's look and is never saved; --creator sets creator_start
## instead of starting; a later build's look is written back unchanged by the next checkpoint; a character
## without a look captures no key. (The saves' own cases are in tests/unit/test_save_slots.gd and
## test_save_migration.gd; a look kept at a shrine - F15's checkpoint, the line's mark and its prompt - is
## tests/slow/test_appearance_shrine.gd, which needs the shrine's scene and screen: about 0.25 s.)

const START := "world.cp.kingsgate_shelf"
const Look := preload("res://tests/unit/test_appearance_record.gd")

var stack: ScreenStack


func before_each() -> void:
	await super()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _own_look() -> Dictionary:
	var r := Appearance.preset_record("young_giant")
	r.preset = ""
	r.skin = "skin.olive"
	r.hair.color = "haircolor.red"
	return r


## The player of the session's level: spawned, the session's character applied (on_level_ready).
func _player() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	return p


func test_a_new_game_with_a_look_stores_it_in_the_valley_and_the_world() -> void:
	var look := _own_look()
	var v := GameSession.change_mode("valley", {"new_game": true, "appearance": look})
	assert_true(v.ok, "a Valley New Game with a look starts (%s)" % v.message)
	assert_true(Look.deep_eq(GameSession.character.get("appearance"), look), "the new character holds the look")
	assert_eq(GameSession.scene_reloads.back(), "new_game", "and the Valley loads")
	var plain := GameSession.change_mode("valley", {"new_game": true})
	assert_true(plain.ok, "a New Game without one")
	assert_false((GameSession.character as Dictionary).has("appearance"), "has no look: the default")
	var w := GameSession.change_mode("world", {"start": START, "appearance": look})
	if not w.ok:
		print("    test_appearance_session: the world New Game skipped - %s" % w.message)
		GameSession.start_world_for_tests(START, look)
	assert_true(Look.deep_eq(GameSession.character.get("appearance"), look), "the world's New Game holds it too")
	var broken := GameSession.change_mode("valley", {"new_game": true, "appearance": {"skin": "skin.ashen"}})
	assert_true(broken.ok, "a New Game with a look the line has not unlocked")
	assert_eq(str(GameSession.character.appearance.skin), "skin.ruddy", "is stored repaired for the character's line")


func test_the_command_line_look_in_every_mode_is_never_saved() -> void:
	var herald := Appearance.preset_record("storm_herald")
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=sandbox", "--appearance=storm_herald"])))
	assert_eq(GameSession.mode, GameSession.Mode.SANDBOX, "the sandbox")
	assert_eq(Appearance.cli_preset, "appearance_preset.storm_herald", "--appearance= is kept for the run")
	var p := await _player()
	assert_false(p.appearance.has_record(), "the sandbox giant has no look of its own")
	assert_true(Look.deep_eq(p.appearance.record(), herald), "and wears the Storm Herald")
	assert_eq(str(p.appearance.look().beard_mesh), str(Appearance.option("beard.short").mesh), "its short beard")
	assert_false(p.capture_character_state().has("appearance"), "a capture writes no look")
	p.queue_free()
	await step_ticks(1)
	for args: Array in [["--mode=valley", "--new-game", "--appearance=ash_raider"],
			["--mode=world", "--new-game", "--appearance=ash_raider"]]:
		GameSession.reset_for_tests()
		GameSession.apply_args(GameSession.parse_args(PackedStringArray(args)))
		assert_eq(Appearance.cli_preset, "appearance_preset.ash_raider", "%s: the preset" % [args])
		assert_false((GameSession.character as Dictionary).has("appearance"), "%s: the character has no look" % [args])
		assert_true(Look.deep_eq(Appearance.resolve(GameSession.character), Appearance.preset_record("ash_raider")),
			"%s: the giant of a bot's or a command-line New Game wears the preset" % [args])
	GameSession.level_id = "level.world"
	var q := await _player()
	assert_true(Look.deep_eq(q.appearance.record(), Appearance.preset_record("ash_raider")), "the spawned giant wears it")
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	assert_true(bool(q.progression.choose_ancestry("ancestry.stoneblood").ok), "a line is chosen")
	await step_ticks(1)
	assert_false(WorldState.flags.has(PlayerAppearance.MARK_SHOWN_FLAG),
		"a command-line look brings up no mark prompt (a bot's run sets no new flag)")
	assert_false(q.capture_character_state().has("appearance"), "and nothing of it is saved")


func test_creator_start_is_set_by_the_command_line() -> void:
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=world", "--creator", "--start=" + START])))
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "--creator shows the title first")
	assert_eq(GameSession.creator_start, {"mode": "world", "options": {"start": START}},
		"with the world's New Game waiting for the creator")
	GameSession.reset_for_tests()
	assert_true(GameSession.creator_start.is_empty(), "reset_for_tests clears it")
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--new-game", "--creator"])))
	assert_eq(GameSession.creator_start, {"mode": "valley", "options": {"new_game": true}}, "or the Valley's")
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "still the title")
	assert_eq(GameSession.scene_reloads.size(), 0, "nothing started")


func test_a_later_builds_look_is_written_back_by_the_next_checkpoint() -> void:
	var fixture := JsonIO.read_file("res://tests/fixtures/saves/v2_appearance_future.json")
	assert_true(fixture.ok, "the fixture reads")
	var raw: Dictionary = fixture.data.character.appearance
	GameSession.persist = true
	SaveSlots.write(fixture.data)
	var c := GameSession.continue_valley()
	assert_true(c.ok, "Continue: %s" % c.message)
	assert_true(str(GameSession.last_load_message).contains(Appearance.NOTE_FUTURE), "the player is told")
	var p := await _player()
	assert_eq(str(p.appearance.look().hair_mesh), str(GiantLook.DEFAULT_LOOK.hair_mesh), "the default look is shown")
	assert_true(Look.deep_eq(p.capture_character_state().get("appearance"), raw), "the record is kept as it is")
	GameSession.take_checkpoint("test")
	var doc := SaveSlots.read()
	assert_true(doc.ok and Look.deep_eq(doc.data.character.get("appearance"), raw),
		"the next checkpoint writes the later build's record back unchanged")
	assert_false(WorldState.flags.has(GameSession.LEGACY_LOOK_FLAG), "a save with a look is no legacy save")
