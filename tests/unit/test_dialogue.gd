extends TestSuite
## DialogueSession (plan §3.15 design 3) on fixture records, without a screen: the start node
## follows the world (the first entry that holds); a choice gated by stage is hidden below it;
## choices apply their effects (first-write-wins flags, the outcome flag and event) and advance;
## an XP choice chosen in two sessions grants once [spec §14 no farming by repeating dialogue];
## learn_abilities applies once; take_items must be held; Quests.dialogue is the running session
## during the conversation and null after it.

const ELDER := "dialogue.test_elder"
const STORY := "dialogue.test_story"

var started: Array = []
var ended: Array = []
var outcomes: Array = []
var xp: Array = []
var learned: Array = []


func before_each() -> void:
	WorldState.clear()
	started.clear()
	ended.clear()
	outcomes.clear()
	xp.clear()
	learned.clear()
	QuestFixtures.install([QuestFixtures.elder_dialogue(ELDER), QuestFixtures.storyteller_dialogue(STORY)])
	Events.dialogue_started.connect(_on_started)
	Events.dialogue_ended.connect(_on_ended)
	Events.dialogue_outcome.connect(_on_outcome)
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	for pair: Array in [[Events.dialogue_started, _on_started], [Events.dialogue_ended, _on_ended],
			[Events.dialogue_outcome, _on_outcome], [Events.xp_award_requested, _on_xp]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	Quests.end_dialogue()
	WorldState.clear()


func _on_started(_tick: int, dialogue_id: String, npc_id: String) -> void:
	started.append([dialogue_id, npc_id])


func _on_ended(_tick: int, dialogue_id: String) -> void:
	ended.append(dialogue_id)


func _on_outcome(_tick: int, dialogue_id: String, outcome: String) -> void:
	outcomes.append([dialogue_id, outcome])


func _on_xp(amount: int, source: String) -> void:
	xp.append([amount, source])


## A context over the live WorldState with the giant at `stage`.
func _ctx(stage := 1) -> Callable:
	return func() -> Dictionary:
		var c := QuestConditions.empty_context()
		c.flags = WorldState.flags
		c.inventory = WorldState.inventory
		c.deltas = WorldState.deltas
		c.stage = stage
		return c


func _learner() -> Callable:
	return func(id: String, source: String) -> bool:
		learned.append([id, source])
		return true


func _session(id := ELDER, stage := 1) -> DialogueSession:
	var s := DialogueSession.new()
	var ok := s.begin(GameData.get_record(id), "valley.village.elder", _ctx(stage), _learner())
	assert_true(ok, "%s starts" % id)
	return s


func _texts(s: DialogueSession) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in s.choices():
		out.append(str(c.text))
	return out


func test_the_start_node_follows_the_world() -> void:
	var s := _session()
	assert_eq(s.node_id, "greet", "a first meeting greets")
	assert_eq(s.speaker(), "Elder Maren", "the speaker")
	assert_eq(s.text(), "A giant... we want no trouble.", "the line")
	assert_eq(started, [[ELDER, "valley.village.elder"]], "dialogue_started")
	WorldState.add_item("item.supply_cache", 1)
	assert_eq(_session().node_id, "report_cache", "carrying the cache: the report")
	WorldState.set_flag("quest.village.outcome", "help_ogre")
	assert_eq(_session().node_id, "done", "settled: done")
	WorldState.set_flag("faction.village.hostile", true)
	assert_eq(_session().node_id, "hostile", "the first entry that holds wins")
	var none := {"id": "dialogue.test_none", "type": "dialogue", "speaker": "Nobody",
		"entries": [{"node": "a", "conditions": [{"type": "flag", "flag": "test.flag.never"}]}],
		"nodes": [{"id": "a", "text": "..."}]}
	var n := DialogueSession.new()
	started.clear()
	assert_false(n.begin(none, "", _ctx(), _learner()), "no entry holds: no conversation")
	assert_false(n.is_active(), "inactive")
	assert_true(started.is_empty(), "nothing started")


func test_a_choice_gated_by_stage_is_hidden_below_it() -> void:
	var low := _session(ELDER, 1)
	assert_eq(_texts(low), ["I'll bring back your stolen supplies.", "I'll drive the ogre out of your fields.",
		"Not now."] as Array[String], "stage 1: no intimidation")
	assert_eq(low.find_choice("intimidate"), -1, "not offered")
	assert_eq(low.choose_outcome("intimidate").reason, "no_such_choice", "cannot be taken")
	low.end()
	var high := _session(ELDER, 2)
	assert_eq(high.choices().size(), 4, "stage 2: four choices")
	assert_eq(high.find_choice("intimidate"), 2, "the third")
	assert_eq(str(high.choices()[2].text), "[Loom over them] Open the bridge. Now.", "loom over them")


func test_choices_apply_effects_and_advance() -> void:
	var s := _session()
	var r := s.choose(0)
	assert_true(r.ok and not r.ended, "the offer moves on")
	assert_eq(s.node_id, "thanks", "to the thanks")
	assert_eq(WorldState.get_flag("quest.village.offer"), "cache", "the offer flag")
	assert_eq(WorldState.get_flag("dialogue.elder.met"), true, "met")
	assert_eq(WorldState.get_flag(QuestConditions.outcome_flag(ELDER, "offer_cache")), true, "the outcome flag")
	assert_eq(outcomes, [[ELDER, "offer_cache"]], "dialogue_outcome")
	assert_false(r.granted, "no reward for an offer")
	assert_eq(_texts(s), ["Farewell."] as Array[String], "the next node's choices")
	r = s.choose(0)
	assert_true(r.ended and not s.is_active(), "next \"\" ends it")
	assert_eq(s.end_reason, "done", "by a choice")
	assert_eq(ended, [ELDER], "dialogue_ended once")
	var again := _session()
	again.choose(1)
	assert_eq(WorldState.get_flag("quest.village.offer"), "cache", "set_flags are first-write-wins")
	assert_eq(WorldState.get_flag(QuestConditions.outcome_flag(ELDER, "offer_ogre")), true, "the other outcome is recorded")
	assert_eq(s.choose(0).reason, "inactive", "an ended session takes no choice")
	assert_eq(again.choose(7).reason, "no_such_choice", "an index out of range")


## [spec §14] The rewarded choice is offered every time, but its once_flag grants it once.
func test_an_xp_choice_is_granted_once_across_two_sessions() -> void:
	var first := _session(STORY)
	var r := first.choose(0)
	assert_true(r.granted, "the first telling is rewarded")
	assert_eq(xp, [[25, "dialogue:" + STORY]], "25 XP requested")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "the gift")
	assert_eq(learned, [["ability.stone_skin", "reward"]], "the ability taught as a reward")
	assert_eq(WorldState.get_flag("reward.test_story.tale"), true, "the once-flag")
	first.choose(0)
	assert_false(first.is_active(), "close ends it")
	var second := _session(STORY)
	assert_eq(second.find_choice("heard"), 0, "the same choice is offered again")
	r = second.choose(0)
	assert_true(r.ok and not r.granted, "taken, but nothing granted")
	assert_eq(xp.size(), 1, "no second XP")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "no second gift")
	assert_eq(learned.size(), 1, "no second teaching")
	assert_eq(outcomes, [[STORY, "heard"], [STORY, "heard"]], "the outcome event is not a reward")


func test_learn_abilities_applies_once_and_the_outcome_closes_the_offer() -> void:
	var s := _session(ELDER, 2)
	var r := s.choose_outcome("intimidate")
	assert_true(r.ok and r.granted, "intimidation is rewarded")
	assert_eq(learned, [["ability.thunder_roar", "reward"]], "Thunder Roar taught once")
	assert_eq(xp, [[40, "dialogue:" + ELDER]], "40 XP")
	for f: String in ["faction.village.stood_down", "faction.village.gate_open"]:
		assert_eq(WorldState.get_flag(f), true, f)
	assert_eq(WorldState.get_flag("quest.village.outcome"), "intimidate", "the village outcome")
	assert_eq(s.node_id, "cowed", "the cowed reply")
	assert_eq(_texts(s), [DialogueSession.LEAVE_TEXT] as Array[String], "a node without choices offers leave")
	assert_true(s.choose(0).ended, "leave ends it")
	assert_eq(s.end_reason, "left", "by leaving")
	var later := _session(ELDER, 2)
	assert_eq(later.node_id, "done", "a later visit opens on done")
	assert_eq(later.find_choice("intimidate"), -1, "the intimidation cannot be repeated")
	assert_eq(learned.size(), 1, "taught once")
	assert_eq(xp.size(), 1, "rewarded once")


func test_take_items_must_be_held() -> void:
	WorldState.add_item("item.supply_cache", 1)
	var s := _session()
	assert_eq(s.node_id, "report_cache", "the report")
	WorldState.remove_item("item.supply_cache", 1)
	assert_eq(_texts(s), [DialogueSession.LEAVE_TEXT] as Array[String], "without the cache only leaving is offered")
	s.end()
	WorldState.add_item("item.supply_cache", 1)
	s = _session()
	var r := s.choose_outcome("help_cache")
	assert_true(r.granted, "the help is rewarded")
	assert_eq(WorldState.count_of("item.supply_cache"), 0, "the cache handed over")
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "two ingots")
	assert_eq(xp, [[120, "dialogue:" + ELDER]], "120 XP")
	assert_eq(learned, [["ability.ancestral_mend", "reward"]], "Mend")
	assert_eq(WorldState.get_flag("quest.village.outcome"), "help_cache", "the outcome")
	assert_eq(s.node_id, "rewarded", "thanked")


func test_quests_dialogue_is_the_running_session() -> void:
	assert_true(Quests.dialogue == null, "no conversation yet")
	var s := Quests.start_dialogue(STORY, "test.npc")
	assert_true(s != null and Quests.dialogue == s, "start_dialogue sets Quests.dialogue")
	assert_true(s.is_active(), "running")
	assert_eq(started, [[STORY, "test.npc"]], "dialogue_started with the npc")
	var t := Quests.start_dialogue(ELDER, "valley.village.elder")
	assert_false(s.is_active(), "a new conversation ends the previous one")
	assert_eq(ended, [STORY], "dialogue_ended for it")
	assert_true(Quests.dialogue == t, "the new one is the running session")
	t.choose(t.choices().size() - 1)
	assert_false(t.is_active(), "\"Not now.\" ends it")
	assert_true(Quests.dialogue == null, "Quests.dialogue is null after the conversation")
	Quests.start_dialogue(STORY, "")
	Quests.end_dialogue()
	assert_true(Quests.dialogue == null, "end_dialogue clears it")
	assert_eq(ended.size(), 3, "every conversation ended once")
	var bad: Dictionary = {"id": "dialogue.test_none", "type": "dialogue", "speaker": "Nobody",
		"entries": [{"node": "a", "conditions": [{"type": "flag", "flag": "test.flag.never"}]}],
		"nodes": [{"id": "a", "text": "..."}]}
	QuestFixtures.install([bad])
	assert_true(Quests.start_dialogue("dialogue.test_none") == null, "no entry holds: null")
	assert_true(Quests.dialogue == null, "and no session")
