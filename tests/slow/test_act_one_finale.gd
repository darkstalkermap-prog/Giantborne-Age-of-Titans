extends IntegrationSuite
## C1: act one's end in play (headless: no cutscenes, so the finale's work happens at once) - the Stone Throne's
## completion begins act two and then opens the end screen once, as act one's (its title and Continue's line say
## so), for each of Harrok's ends; a save that finished act one before act two existed begins it on entering the world
## (its first Continue), without an end screen; act two's thread then leads the tracker; the finale's record plays in
## the cutscene player's timeline (its shots cover it, its card is the last thing).

var screens: Array = []


func before_each() -> void:
	await super()
	screens.clear()
	Events.ui_screen_requested.connect(_on_screen)


func after_each() -> void:
	if Events.ui_screen_requested.is_connected(_on_screen):
		Events.ui_screen_requested.disconnect(_on_screen)
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _on_screen(screen: String, args: Dictionary) -> void:
	screens.append([screen, args])


func _throne() -> StoneThrone:
	var t := StoneThrone.new()
	t.world_id = "test.c1.throne"
	world.add_child(t)
	return t


func test_the_throne_begins_act_two_then_shows_act_ones_end_for_each_champion() -> void:
	for champion: String in ["spared", "slain", "yielded_talk"]:
		WorldState.clear()
		screens.clear()
		GameSession.expansion = ExpansionState.defaults()
		var t := _throne()
		WorldState.set_flag("boss.harrok.outcome", champion)
		WorldState.set_flag("oath.march.done", true)
		WorldState.set_flag("oath.march.outcome", "help")
		WorldState.set_flag("campaign.completed", true)
		await step_ticks(2)
		assert_true(ActTwo.begun(WorldState.flags), "%s: act two has begun" % champion)
		assert_eq(int(GameSession.expansion.act), 2, "%s: the save's act is 2" % champion)
		var ends := screens.filter(func(s: Array) -> bool: return str(s[0]) == "end")
		assert_eq(ends.size(), 1, "%s: the end screen opens once" % champion)
		if ends.size() == 1:
			assert_true(bool((ends[0][1] as Dictionary).get("campaign", false)), "%s: as the campaign's end" % champion)
		assert_eq(str(WorldState.get_flag("pledge.harrok_clan")), "refuses" if champion == "slain" else "sends",
			"%s: Harrok's clan's pledge" % champion)
		assert_eq(str(WorldState.get_flag("pledge.brannock")), "sends", "%s: Brannock helped sends" % champion)
		t.queue_free()
		await step_ticks(1)
	assert_true(EndScreen.CAMPAIGN_TITLE.begins_with("Act One"), "the end screen reads as act one's")
	assert_true(EndScreen.CAMPAIGN_CONTINUE_HINT.contains("Breach"), "and Continue points at the Breach")


func test_an_older_completed_save_begins_act_two_on_entering_the_world() -> void:
	GameSession.start_world_for_tests("world.cp.moot_foot")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.set_flag("campaign.completed", true)
	WorldState.set_flag("boss.harrok.outcome", "spared")
	assert_true(ActTwo.due(WorldState.flags), "act two is due")
	Events.level_entered.emit(Sim.tick, GameSession.WORLD_LEVEL_ID, "continue")
	await step_ticks(2)
	assert_true(ActTwo.begun(WorldState.flags), "entering the world begins act two")
	assert_eq(str(WorldState.get_flag("pledge.harrok_clan")), "sends", "with its pledges")
	assert_eq(screens.filter(func(s: Array) -> bool: return str(s[0]) == "end").size(), 0, "and no end screen (seen before)")
	Events.level_entered.emit(Sim.tick, GameSession.WORLD_LEVEL_ID, "continue")
	await step_ticks(2)
	assert_eq(str(WorldState.get_flag("pledge.harrok_clan")), "sends", "a second entry changes nothing")


func test_the_finale_record_plays_in_the_cutscene_timeline() -> void:
	var rec := GameData.get_record(ActTwo.FINALE_ID)
	var ticks := int(rec.ticks)
	var covered := 0
	for t in range(0, ticks, 10):
		if not CutsceneRules.shot_at(rec, t).is_empty():
			covered += 1
	assert_eq(covered, int(ceil(ticks / 10.0)), "a shot at every moment of the finale")
	assert_true(str(CutsceneRules.line_at(rec, 40)).contains("Stone Throne"), "it opens on the throne taken")
	assert_true(CutsceneRules.title_at(rec, ticks - 30) > 0.9, "and ends on its card")
	assert_eq(str(rec.title.text), "ACT TWO", "the Act Two card")
	var actors: Array = rec.get("actors", [])
	assert_eq(int((actors[0] as Dictionary).stage), 6, "the giant at the throne is the crowned stage 6")
