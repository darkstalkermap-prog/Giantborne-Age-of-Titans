extends TestSuite
## Quests in the campaign (P20; plan M6-M9 §2.12): the pure condition types count, quest_done,
## level_is, ancestry_is and ancestry_chosen; the shapes of every declared type (discovered,
## region_entered, event_done and near are evaluated by their packages); the new context keys;
## a stage's xp_floor_level lifts its award to the level; multi-marker stages and waiting_text in
## the objective; the dialogue effect attribute_points granted once through its once_flag;
## locked_text choices listed, refused and shown greyed by the dialogue screen.

const QUEST := "quest.test_p20"
const DIALOGUE := "dialogue.test_p20"
const LEVEL := "level.test_p20_quests"

var awards: Array = []
var notices: Array[String] = []


func before_each() -> void:
	WorldState.clear()
	awards.clear()
	notices.clear()
	Events.xp_award_requested.connect(_on_award)
	Events.hud_message.connect(_on_notice)


func after_each() -> void:
	if Events.xp_award_requested.is_connected(_on_award):
		Events.xp_award_requested.disconnect(_on_award)
	if Events.hud_message.is_connected(_on_notice):
		Events.hud_message.disconnect(_on_notice)
	Quests.end_dialogue()
	Quests.refresh_positions()
	WorldState.clear()


func _on_award(amount: int, source: String) -> void:
	awards.append([amount, source])


func _on_notice(text: String, _kind: String) -> void:
	notices.append(text)


func _ctx() -> Dictionary:
	return QuestConditions.empty_context()


func _holds(c: Variant, ctx: Dictionary) -> bool:
	return QuestConditions.holds(c, ctx)


func _shape_errors(c: Dictionary) -> String:
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "refs": []}
	SchemaUtil.check_condition(c, "c", out)
	return "\n".join(out.errors)


func _shape_refs(c: Dictionary) -> Array:
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "refs": []}
	SchemaUtil.check_condition(c, "c", out)
	var refs: Array = []
	for r: Dictionary in out.refs:
		refs.append("%s:%s" % [r.type, r.id])
	return refs


# --------------------------------------------------------------------------- the pure types

func test_count_holds_when_n_of_its_conditions_hold() -> void:
	var c := _ctx()
	c.flags = {"test.a": true, "test.b": true, "test.c": false}
	var of := [{"type": "flag", "flag": "test.a"}, {"type": "flag", "flag": "test.b"}, {"type": "flag", "flag": "test.c"}]
	assert_true(_holds({"type": "count", "n": 2, "of": of}, c), "2 of 3 hold")
	assert_false(_holds({"type": "count", "n": 3, "of": of}, c), "not 3 of 3")
	assert_true(_holds({"type": "count", "n": 1, "of": of}, c), "1 of 3")
	assert_true(_holds({"type": "count", "of": of}, c), "n defaults to 1")
	assert_false(_holds({"type": "count", "n": 1, "of": []}, c), "nothing listed: never")
	assert_false(_holds({"type": "count", "n": 1, "of": {"type": "flag", "flag": "test.a"}}, c), "of must be a list")
	var nested := {"type": "count", "n": 2, "of": [{"type": "all", "of": of.slice(0, 2)}, {"type": "not", "of": of[2]},
		{"type": "count", "n": 3, "of": of}]}
	assert_true(_holds(nested, c), "nested conditions count too")


func test_quest_done_level_is_and_ancestry() -> void:
	var c := _ctx()
	assert_false(_holds({"type": "quest_done", "quest": "quest.village"}, c), "a quest not yet done")
	c.flags = {"quest.village.done": true, "quest.tutorial.done": false}
	assert_true(_holds({"type": "quest_done", "quest": "quest.village"}, c), "done (quest.<id>.done true)")
	assert_false(_holds({"type": "quest_done", "quest": "quest.tutorial"}, c), "abandoned (done false) is not done")
	assert_false(_holds({"type": "quest_done", "quest": "quest.main"}, c), "another quest")
	assert_false(_holds({"type": "quest_done", "quest": ""}, c), "no quest named")
	c.flags = {"quest.village.done": "yes"}
	assert_false(_holds({"type": "quest_done", "quest": "quest.village"}, c), "only true counts")
	assert_false(_holds({"type": "level_is", "level": "level.valley"}, c), "outside the campaign no level is")
	c.level_id = "level.valley"
	assert_true(_holds({"type": "level_is", "level": "level.valley"}, c), "the campaign level")
	assert_false(_holds({"type": "level_is", "level": "level.world"}, c), "another level")
	assert_false(_holds({"type": "level_is", "level": ""}, c), "no level named")
	c.ancestry = "ancestry.neutral"
	assert_true(_holds({"type": "ancestry_is", "ancestry": "ancestry.neutral"}, c), "ancestry_is")
	assert_false(_holds({"type": "ancestry_is", "ancestry": "ancestry.stoneblood"}, c), "another ancestry")
	assert_false(_holds({"type": "ancestry_chosen"}, c), "not chosen")
	c.ancestry_chosen = true
	assert_true(_holds({"type": "ancestry_chosen"}, c), "chosen")
	assert_true(QuestConditions.all_hold([{"type": "level_is", "level": "level.valley"}, {"type": "ancestry_chosen"}], c),
		"they combine like any condition")


func test_the_context_has_the_new_keys() -> void:
	for key: String in ["level_id", "position", "ancestry", "ancestry_chosen"]:
		assert_true(QuestConditions.KEYS.has(key), "QuestConditions.KEYS has %s" % key)
	var empty := QuestConditions.empty_context()
	for key: String in QuestConditions.KEYS:
		assert_true(empty.has(key), "empty_context() has %s" % key)
	assert_eq(str(empty.level_id), "", "no level")
	assert_false((empty.position as Vector3).is_finite(), "no position")
	var ctx := Quests.condition_context()
	for key: String in QuestConditions.KEYS:
		assert_true(ctx.has(key), "Quests.condition_context() has %s" % key)
	assert_eq(str(ctx.level_id), "", "the sandbox is no campaign level")
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = "level.valley"
	GameSession.character = {"ancestry": "ancestry.neutral", "ancestry_chosen": true, "xp": 0}
	ctx = Quests.condition_context()
	assert_eq(str(ctx.level_id), "level.valley", "the campaign level being played")
	assert_eq(str(ctx.ancestry), "ancestry.neutral", "the character's ancestry")
	assert_true(bool(ctx.ancestry_chosen), "and whether it was chosen")
	assert_false((ctx.position as Vector3).is_finite(), "no player: no position")


func test_the_targets_of_the_new_types() -> void:
	var c := {"type": "count", "n": 1, "of": [{"type": "discovered", "poi": "poi.hollowmere"},
		{"type": "near", "target": "world.marker.ford", "radius_m": 150},
		{"type": "destroyed", "world_id": "world.prop.gate"}, {"type": "quest_done", "quest": "quest.main"}]}
	assert_eq(QuestConditions.targets_of(c), PackedStringArray(["poi.hollowmere", "world.marker.ford", "world.prop.gate"]),
		"a count's places are its targets (a quest is not a place)")


func test_every_declared_shape_validates() -> void:
	var good := [
		{"type": "count", "n": 2, "of": [{"type": "flag", "flag": "test.a"}, {"type": "flag", "flag": "test.b"}]},
		{"type": "quest_done", "quest": "quest.main"},
		{"type": "level_is", "level": "level.world"},
		{"type": "discovered", "poi": "poi.hollowmere"},
		{"type": "region_entered", "region": "region.greywood"},
		{"type": "ancestry_is", "ancestry": "ancestry.neutral"},
		{"type": "ancestry_chosen"},
		{"type": "event_done", "event": "event.hollowmere_raid", "outcome": "saved"},
		{"type": "event_done", "event": "event.hollowmere_raid"},
		{"type": "near", "target": "world.marker.ford", "radius_m": 150}]
	for g: Dictionary in good:
		assert_eq(_shape_errors(g), "", "%s validates" % g.type)
	assert_eq(_shape_refs(good[1]), ["quest:quest.main"], "quest_done references its quest")
	assert_eq(_shape_refs(good[2]), ["level:level.world"], "level_is its level")
	assert_eq(_shape_refs(good[3]), ["poi:poi.hollowmere"], "discovered its POI")
	assert_eq(_shape_refs(good[4]), ["region:region.greywood"], "region_entered its region")
	assert_eq(_shape_refs(good[5]), ["ancestry:ancestry.neutral"], "ancestry_is its ancestry")
	assert_eq(_shape_refs(good[7]), ["world_event:event.hollowmere_raid"], "event_done its world event")
	var bad := {
		"missing required key 'n'": {"type": "count", "of": [{"type": "flag", "flag": "test.a"}]},
		"more than the 1 conditions": {"type": "count", "n": 2, "of": [{"type": "flag", "flag": "test.a"}]},
		"missing required key 'of'": {"type": "count", "n": 1},
		"missing required key 'quest'": {"type": "quest_done"},
		"unknown key 'name'": {"type": "level_is", "level": "level.world", "name": "x"},
		"missing required key 'target'": {"type": "near", "radius_m": 50},
		"missing required key 'radius_m'": {"type": "near", "target": "world.marker.ford"},
		"unknown key 'ancestry'": {"type": "ancestry_chosen", "ancestry": "ancestry.neutral"},
		"missing required key 'event'": {"type": "event_done", "outcome": "saved"},
	}
	for why: String in bad:
		var e := _shape_errors(bad[why])
		assert_true(e.contains(why), "%s: %s" % [why, e])
	assert_true(_shape_errors({"type": "count", "n": 0, "of": [{"type": "flag", "flag": "test.a"}]}) != "", "n >= 1")
	assert_true(_shape_errors({"type": "count", "n": 1, "of": [{"type": "nonsense"}]}).contains("nonsense"),
		"the listed conditions are checked too")


# --------------------------------------------------------------------------- stages

func test_xp_floor_level_lifts_an_award_to_the_level() -> void:
	var to5 := Progression.xp_for_level(5)
	assert_true(to5 > 100, "level 5 needs %d XP" % to5)
	assert_eq(Quests.stage_award({"xp": 50}, 0), 50, "no floor: the stage's xp")
	assert_eq(Quests.stage_award({"xp": 50, "xp_floor_level": 5}, 0), to5, "lifted to reach level 5 from nothing")
	assert_eq(Quests.stage_award({"xp": 50, "xp_floor_level": 5}, to5 - 20), 50, "never below the stage's own xp")
	assert_eq(Quests.stage_award({"xp": 50, "xp_floor_level": 5}, to5 - 80), 80, "just enough to reach the level")
	assert_eq(Quests.stage_award({"xp": 50, "xp_floor_level": 5}, to5 + 500), 50, "past the level: the stage's xp")
	assert_eq(Quests.stage_award({"xp": 0, "xp_floor_level": 1}, 0), 0, "level 1 lifts nothing")
	assert_eq(Quests.stage_award({"xp": -5}, 0), 0, "never negative")
	# Through a quest: the award follows the character's XP (no player: the session character's).
	QuestFixtures.install([QuestFixtures.quest(QUEST, [
		QuestFixtures.stage("first", QuestFixtures.flag_cond("test.p20.first"), 30, {"xp_floor_level": 4}),
		QuestFixtures.stage("second", QuestFixtures.flag_cond("test.p20.second"), 30)])])
	QuestFixtures.activate([QUEST])
	GameSession.character = {"xp": 120}
	Quests.evaluate_now()
	assert_eq(Quests.stage_of(QUEST), "first", "the quest started")
	WorldState.set_flag("test.p20.first", true)
	Quests.evaluate_now()
	assert_eq(awards.size(), 1, "one award")
	if awards.size() == 1:
		assert_eq(int(awards[0][0]), Progression.xp_for_level(4) - 120, "enough to reach level 4 from 120 XP")
		assert_eq(str(awards[0][1]), "quest:%s:first" % QUEST, "for the stage")
	WorldState.set_flag("test.p20.second", true)
	Quests.evaluate_now()
	assert_eq(int(awards.back()[0]), 30, "a stage without a floor gives its xp")


func test_multi_marker_stages_and_waiting_text() -> void:
	QuestFixtures.install([QuestFixtures.quest(QUEST, [
		QuestFixtures.stage("beacons", QuestFixtures.flag_cond("test.p20.beacons"), 0,
			{"marker": "test.marker.b1", "markers": ["test.marker.b2", "test.marker.b1", "test.marker.b3"],
				"waiting_text": "Waiting: stage 5"})])])
	QuestFixtures.activate([QUEST])
	TestFixtures.record_override(LEVEL, {"schema_version": 1, "type": "level", "display_name": "Quest test",
		"scene": "res://scenes/test/flow_test_level.tscn", "start_checkpoint": ""})
	var idx := WorldIndex.new()
	idx.markers = {"test.marker.b1": {"position": Vector3(100, 0, 0)}, "test.marker.b2": {"position": Vector3(0, 0, 50)}}
	WorldIndex.put_cached(LEVEL, idx)
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = LEVEL
	Quests.refresh_positions()
	Quests.evaluate_now()
	var o := Quests.objective_for(QUEST)
	assert_eq(o.get("markers"), PackedStringArray(["test.marker.b1", "test.marker.b2", "test.marker.b3"]),
		"the stage's marker, then its markers, each once")
	assert_eq(str(o.get("marker_id", "")), "test.marker.b1", "marker_id is the first")
	assert_eq(o.get("positions"), [Vector3(100, 0, 0), Vector3(0, 0, 50)], "every known position (b3 is nowhere)")
	assert_eq(o.get("position"), Vector3(100, 0, 0), "without a player the first known one")
	assert_eq(str(o.get("waiting_text", "")), "Waiting: stage 5", "the journal's waiting line")
	assert_eq(Quests.stage_markers({"marker": "", "markers": []}), PackedStringArray(), "a stage without markers")
	var errs := "\n".join(DataValidator.validate_record(QuestFixtures.quest(QUEST, [
		QuestFixtures.stage("bad", QuestFixtures.flag_cond("test.a"), 0,
			{"markers": ["Not An Id"], "xp_floor_level": 30, "waiting_text": 5})]), "test.json").errors)
	assert_true(errs.contains("markers[0]"), "marker ids are checked: %s" % errs)
	assert_true(errs.contains("xp_floor_level"), "xp_floor_level is a level 1-20: %s" % errs)
	assert_true(errs.contains("waiting_text"), "waiting_text is a string: %s" % errs)


# --------------------------------------------------------------------------- dialogue

func _dialogue() -> Dictionary:
	return {"schema_version": 1, "id": DIALOGUE, "type": "dialogue", "speaker": "Old Wyn",
		"entries": [{"node": "start", "conditions": []}],
		"nodes": [
			{"id": "start", "text": "The old line knew the strength in you.",
				"choices": [
					{"text": "Swear the peace", "next": "", "locked_text": "Return when you stand at stage 5",
						"conditions": [{"type": "stage_at_least", "stage": 5}],
						"effects": {"outcome": "sworn"}},
					{"text": "Take the old blessing", "next": "",
						"effects": {"attribute_points": 2, "once_flag": "reward.test_p20.blessing", "outcome": "blessed"}},
					{"text": "Leave the hall", "next": ""}]},
			{"id": "locked_only", "text": "Only the great may pass.",
				"choices": [{"text": "Pass the gate", "next": "", "locked_text": "Grow to stage 6",
					"conditions": [{"type": "stage_at_least", "stage": 6}]}]}]}


func test_attribute_points_are_given_once_through_the_once_flag() -> void:
	QuestFixtures.install([_dialogue()])
	GameSession.character = {"unspent_attribute_points": 1}
	var s := Quests.start_dialogue(DIALOGUE, "test.npc.wyn")
	assert_true(s != null, "the conversation starts")
	var i := s.find_choice("blessed")
	assert_true(i >= 0, "the blessing is on offer")
	var r := s.choose(i)
	assert_true(bool(r.ok) and bool(r.granted), "chosen and rewarded")
	assert_eq(int(GameSession.character.unspent_attribute_points), 3, "+2 unspent attribute points (no player: the session character)")
	assert_true(notices.has("+2 attribute points"), "the HUD says so: %s" % [notices])
	assert_true(QuestConditions.truthy(WorldState.get_flag("reward.test_p20.blessing")), "the once-flag is set")
	s = Quests.start_dialogue(DIALOGUE, "test.npc.wyn")
	r = s.choose(s.find_choice("blessed"))
	assert_true(bool(r.ok) and not bool(r.granted), "a second conversation grants nothing")
	assert_eq(int(GameSession.character.unspent_attribute_points), 3, "still 3")
	# Without Quests: the session's own granter.
	WorldState.clear()
	var got: Array = []
	var direct := DialogueSession.new()
	direct.attribute_granter = func(points: int, source: String) -> void: got.append([points, source])
	assert_true(direct.begin(GameData.get_record(DIALOGUE), "test.npc.wyn"), "a session without Quests")
	direct.choose(direct.find_choice("blessed"))
	assert_eq(got, [[2, "dialogue:%s" % DIALOGUE]], "the granter is called once with the points and the source")
	var errs := "\n".join(DataValidator.validate_record({"schema_version": 1, "id": "dialogue.test_p20_bad", "type": "dialogue",
		"entries": [{"node": "a", "conditions": []}],
		"nodes": [{"id": "a", "text": "x", "choices": [{"text": "y", "next": "", "effects": {"attribute_points": 3}},
			{"text": "z", "next": "", "effects": {"attribute_points": 500, "once_flag": "reward.test.z"}}]}]}, "test.json").errors)
	assert_true(errs.contains("attribute_points") and errs.contains("once_flag"), "a reward needs its once_flag: %s" % errs)
	assert_true(errs.contains("[1].effects.attribute_points"), "at most 100 points: %s" % errs)


func test_locked_choices_are_listed_after_the_others_and_refused() -> void:
	QuestFixtures.install([_dialogue()])
	var s := DialogueSession.new()
	var ctx := func() -> Dictionary:
		var c := QuestConditions.empty_context()
		c.flags = WorldState.flags
		c.stage = 3
		return c
	assert_true(s.begin(GameData.get_record(DIALOGUE), "test.npc.wyn", ctx), "begins")
	var choices := s.choices()
	var texts: Array = []
	for c: Dictionary in choices:
		texts.append(str(c.text))
	assert_eq(texts, ["Take the old blessing", "Leave the hall", "Swear the peace"], "the locked choice comes last")
	var locked: Dictionary = choices[2]
	assert_true(bool(locked.locked), "it is locked")
	assert_eq(str(locked.locked_text), "Return when you stand at stage 5", "with its reason")
	assert_false(bool(choices[0].locked), "the others are not")
	assert_eq(s.find_choice("sworn"), -1, "find_choice never picks a locked choice")
	var r := s.choose(2)
	assert_false(bool(r.ok), "choosing it is refused")
	assert_eq(str(r.reason), "locked", "as locked")
	assert_true(s.is_active(), "and the conversation goes on")
	assert_false(QuestConditions.truthy(WorldState.get_flag(QuestConditions.outcome_flag(DIALOGUE, "sworn"))),
		"no outcome")
	s.node_id = "locked_only"
	choices = s.choices()
	assert_eq(str(choices[0].text), DialogueSession.LEAVE_TEXT, "a node with only locked choices offers [Leave] first")
	assert_true(bool(choices[0].implicit), "the implicit leave")
	assert_true(choices.size() == 2 and bool(choices[1].locked), "then the locked choice")
	# The dialogue screen shows it greyed, with its reason.
	s.node_id = "start"
	var screen := DialogueScreen.new()
	add_child(screen)
	screen.session = s
	screen.refresh()
	var labels := screen.choice_texts()
	assert_eq(labels.size(), 3, "three buttons")
	assert_eq(labels[2], "3. Swear the peace (Return when you stand at stage 5)", "the locked button names its reason")
	assert_true(screen.choice_buttons[2].disabled, "and is disabled")
	assert_false(screen.choice_buttons[0].disabled, "the others are not")
	screen.free()
	s.end("test")
