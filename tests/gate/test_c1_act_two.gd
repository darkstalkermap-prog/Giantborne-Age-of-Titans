extends IntegrationSuite
## C1: act two from the saves older builds wrote.
##   * the 0.15.0-m15 build's own save of a completed campaign (tests/fixtures/saves/v3_m15_campaign_complete.json:
##     the 0.14 campaign-complete fixture Continued in a clean checkout of `b-candidate`, played on and checkpointed -
##     schema 3, act 1, stage 6, level 14) and the 0.14 one Continue in this build: act two begins on entering the
##     world (no end screen: they saw it), the pledges are given, act two's thread leads, nothing they earned is lost
##     (level, stage, inventory, the titans' records, the oaths), and the next checkpoint writes act 2;
##   * the world bot, given the 0.15 save and --bot-until=region.hoarfell.entered, plays act two's thread as a player
##     would: the rim council at the Stone Throne, the Rim Road, up the Breach (a stage-6 climb) into the Hoarfell.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const FIXTURES := ["v3_m15_campaign_complete", "v2_a4_campaign_complete"]
const BOT_WALL_S := 600.0
const RESULT_PREFIX := "AUTOPILOT_RESULT "

var level: Node3D = null
var screens: Array = []


func before_each() -> void:
	await super()
	screens.clear()
	Events.ui_screen_requested.connect(_on_screen)


func after_each() -> void:
	if Events.ui_screen_requested.is_connected(_on_screen):
		Events.ui_screen_requested.disconnect(_on_screen)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await get_tree().process_frame
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _on_screen(screen: String, args: Dictionary) -> void:
	screens.append([screen, args])


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _load_level() -> GiantPlayer:
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	level = (load(GameSession.scene_for_level(GameSession.level_id)) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var w := level as WorldRoot
	if w != null:
		w.streamer.deterministic = true
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	if w != null:
		var at := p.global_position
		var guard := 0
		while not w.streamer.ring_ready(at) and guard < 900:
			w.streamer.load_ring_slice(at)
			await step_ticks(1)
			guard += 1
	return p


func test_older_completed_saves_begin_act_two_and_keep_everything() -> void:
	for f: String in FIXTURES:
		var text := FileAccess.get_file_as_string(FIXTURE_DIR + f + ".json")
		var doc: Dictionary = JSON.parse_string(text)
		screens.clear()
		GameSession.persist = true
		_write_text(SaveSlots.path(), text)
		var r := GameSession.continue_valley()
		assert_true(r.ok, "%s: Continue (%s)" % [f, r.message])
		var p := await _load_level()
		await step_ticks(60)
		assert_true(ActTwo.begun(WorldState.flags), "%s: act two begins on entering the world" % f)
		assert_eq(screens.filter(func(s: Array) -> bool: return str(s[0]) == "end").size(), 0, "%s: no end screen again" % f)
		for pl: Dictionary in ActTwo.pledges():
			assert_true(str(WorldState.get_flag(str(pl.flag), "")) in ["sends", "refuses"], "%s: %s answered" % [f, pl.id])
		assert_eq(str(WorldState.get_flag("pledge.harrok_clan")), "sends", "%s: Harrok spared, his clan sends" % f)
		assert_eq(Quests.quest_state(ActTwo.MAIN_QUEST), Quests.ACTIVE, "%s: act two's thread is active" % f)
		assert_eq(Quests.main_quest_id, ActTwo.MAIN_QUEST, "%s: and leads" % f)
		assert_eq(Quests.quest_state("quest.world_main"), Quests.COMPLETED, "%s: act one stays complete" % f)
		assert_eq(int(p.progression.level), int(doc.character.level), "%s: its level" % f)
		assert_eq(p.current_growth_stage(), int(doc.character.growth_stage), "%s: its stage" % f)
		for it: Dictionary in doc.character.get("inventory", []):
			assert_true(WorldState.count_of(str(it.item)) >= int(it.count), "%s: still holds %s" % [f, it.item])
		GameSession.request_checkpoint("c1_act_two")
		await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 240)
		var main := JsonIO.read_file(SaveSlots.path())
		assert_eq(int((main.data as Dictionary).get("act", 0)) if main.ok else 0, 2, "%s: the next checkpoint writes act 2" % f)
		if level != null and is_instance_valid(level):
			level.queue_free()
		level = null
		await get_tree().process_frame
		await get_tree().process_frame
		FactionState.reset_for_tests()
		WanderDirector.reset_for_tests()
		SaveSlots.delete_slot(true)
		WorldState.clear()


func test_the_world_bot_hears_the_council_and_climbs_the_breach() -> void:
	var dir := "user://bot_saves/c1_breach"
	DirAccess.make_dir_recursive_absolute(dir)
	_write_text(dir.path_join("valley_1.json"), FileAccess.get_file_as_string(FIXTURE_DIR + "v3_m15_campaign_complete.json"))
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--no-audio", "--save-dir=" + dir,
		"--mode=world", "--continue", "--scenario=world", "--autoplay=900", "--bot-preset=mixed", "--bot-assist",
		"--bot-seed=1", "--bot-until=region.hoarfell.entered"])
	var output: Array = []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var text := "\n".join(output)
	var result := {}
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX):
			var parsed: Variant = JSON.parse_string(line.substr(RESULT_PREFIX.length()).strip_edges())
			if typeof(parsed) == TYPE_DICTIONARY:
				result = parsed
	var wb: Dictionary = result.get("world_bot", {})
	var tail := "\n".join((text.split("\n") as PackedStringArray).slice(-14))
	print("    test_c1_act_two: the bot from the 0.15 save - exit %d, %.0f s wall, %.0f s simulated, %s" % [code, wall,
		float(wb.get("simulated_s", 0.0)), str(wb.get("finish_reason", "?"))])
	assert_eq(code, 0, "the run exits 0:\n%s" % tail)
	assert_eq(str(wb.get("finish_reason", "")), "until", "it reached the Hoarfell (region.hoarfell.entered):\n%s" % tail)
	assert_eq((wb.get("breaches", []) as Array).size(), 0, "no watchdog breach: %s" % [wb.get("breaches")])
	assert_eq((wb.get("invariant_failures", []) as Array).size(), 0, "no invariant failure: %s" % [wb.get("invariant_failures")])
	assert_eq(int(result.get("errors", -1)), 0, "no error: %s" % [result.get("error_samples")])
	assert_true(wall < BOT_WALL_S, "under %d s of wall time (%.0f)" % [int(BOT_WALL_S), wall])
	var saved := JsonIO.read_file(dir.path_join("valley_1.json"))
	var flags: Dictionary = (saved.data as Dictionary).get("world", {}).get("flags", {}) if saved.ok else {}
	assert_true(QuestConditions.truthy(flags.get("act_two.council_heard")), "it heard the rim council (its last checkpoint)")
