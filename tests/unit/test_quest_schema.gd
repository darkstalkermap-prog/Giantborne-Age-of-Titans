extends TestSuite
## The three P13 record types (plan §2.8.3): quest, dialogue and tutorial_prompt. The plan's
## examples (the elder's conversation completed with the nodes it leaves out) and the test
## fixtures validate; every field and semantic rule rejects bad values with its message; the
## registry now loads the three modules.


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


func _warnings(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).warnings)


func _main_quest() -> Dictionary:
	return {"schema_version": 1, "id": "quest.main", "type": "quest", "display_name": "The Valley of Broken Kings",
		"prototype_pacing": true, "auto_start": true, "start_conditions": [], "abandon_when": null,
		"stages": [{"id": "ogre", "objective": "Defeat the ogre blocking the forest trail",
			"complete_when": {"type": "killed", "targets": ["valley.forest.ogre"]},
			"marker": "valley.marker.ogre_clearing", "xp": 110, "items": [], "set_flags": {},
			"bot": {"action": "kill", "target": "valley.forest.ogre"}}],
		"on_complete_flags": {"slice.completed": true}}


func _block_prompt() -> Dictionary:
	return {"schema_version": 1, "id": "tutorial.block", "type": "tutorial_prompt",
		"text": "Raise your guard with {block}. Block just as the blow lands to parry it.",
		"trigger": {"type": "event", "event": "telegraph_started", "target": "player", "action_tags_any": ["Parryable"]},
		"dismiss": {"type": "event", "event": "hit_resolved", "defender": "player", "outcome_in": ["blocked", "parried"]},
		"requires_flags": [], "min_stage": 1, "priority": 20, "once": true, "defer_in_combat": false,
		"sets_flag": "tutorial.block.done"}


func test_registry_loads_the_three_modules() -> void:
	for t: String in ["dialogue", "quest", "tutorial_prompt"]:
		assert_true(DataValidator.RECORD_TYPES.has(t), "%s records can be validated" % t)
	assert_eq(DataValidator.SCHEMAS["quest"].required_ids(), {}, "no quest record is required by P13's code")


func test_the_plan_examples_and_the_fixtures_validate() -> void:
	var recs := [_main_quest(), QuestFixtures.elder_dialogue("dialogue.elder"), _block_prompt(),
		QuestFixtures.storyteller_dialogue(),
		QuestFixtures.quest("quest.test_a", [QuestFixtures.stage("one", QuestFixtures.flag_cond("test.flag.go"), 10)]),
		QuestFixtures.prompt("tutorial.test_light", {"type": "flag", "flag": "test.flag.go"},
			{"type": "action_kind", "action_kind": "light", "count": 2})]
	for rec: Dictionary in recs:
		var r := _validate(rec)
		assert_eq(r.errors, PackedStringArray(), "%s validates" % rec.id)
		assert_eq(r.warnings, PackedStringArray(), "%s has no warnings" % rec.id)
	var refs: Array = _validate(QuestFixtures.elder_dialogue("dialogue.elder")).refs
	var ids: Array = []
	for ref: Dictionary in refs:
		ids.append("%s:%s" % [ref.type, ref.id])
	for expected: String in ["item:item.supply_cache", "item:item.iron_ingot", "action:ability.thunder_roar",
			"action:ability.ancestral_mend"]:
		assert_true(ids.has(expected), "the dialogue references %s (checked against the records)" % expected)
	var abandon := _main_quest()
	abandon.auto_start = false
	abandon.start_conditions = [{"type": "flag", "flag": "quest.village.offer", "equals": "cache"}]
	abandon.abandon_when = {"type": "all", "of": [{"type": "flag", "flag": "quest.village.outcome"},
		{"type": "not", "of": {"type": "flag", "flag": "quest.village.outcome", "equals": "help_cache"}}]}
	assert_eq(_errors(abandon), "", "a branch quest with start_conditions and abandon_when validates")


func test_quest_rules() -> void:
	var q := _main_quest()
	q.id = "main.quest"
	assert_true(_errors(q).contains("quest ids start with 'quest.'"), "the id prefix")
	q = _main_quest()
	q.stages = []
	assert_true(_errors(q).contains("stages must list at least one stage"), "no stages")
	q = _main_quest()
	q.erase("stages")
	assert_true(_errors(q).contains("missing required key 'stages'"), "stages are required")
	q = _main_quest()
	q.stages.append((q.stages[0] as Dictionary).duplicate(true))
	assert_true(_errors(q).contains("duplicate stage id 'ogre'"), "duplicate stage ids")
	q = _main_quest()
	q.stages[0].id = "Ogre Fight"
	assert_true(_errors(q).contains("must be a plain lowercase word"), "stage ids are plain words")
	q = _main_quest()
	q.stages[0].erase("complete_when")
	assert_true(_errors(q).contains("missing required key 'complete_when'"), "complete_when is required")
	q = _main_quest()
	q.stages[0].complete_when = {"type": "teleport"}
	assert_true(_errors(q).contains("complete_when.type: unknown value 'teleport'"), "an unknown condition")
	q = _main_quest()
	q.stages[0].complete_when = {"type": "killed", "targets": []}
	assert_true(_errors(q).contains("must list at least one id"), "a kill condition needs targets")
	q = _main_quest()
	q.stages[0].marker = "ogre_clearing"
	assert_true(_errors(q).contains(".marker: id 'ogre_clearing' must be lowercase dotted"), "marker ids are dotted")
	q = _main_quest()
	q.stages[0].bot = {"action": "teleport"}
	assert_true(_errors(q).contains(".bot.action: unknown value 'teleport'"), "bot actions are known")
	q = _main_quest()
	q.stages[0].bot = {"target": "valley.forest.ogre"}
	assert_true(_errors(q).contains(".bot: missing required key 'action'"), "a bot hint names its action")
	q = _main_quest()
	q.stages[0].bot = {"action": "grow", "target": "valley.shrine.grove", "stage": 2}
	assert_eq(_errors(q), "", "other bot keys are the bot's")
	q = _main_quest()
	q.stages[0].set_flags = {"Bad Flag": true}
	assert_true(_errors(q).contains("flag id 'Bad Flag' must be lowercase dotted"), "set_flags ids")
	q = _main_quest()
	q.on_complete_flags = {"slice.completed": [1]}
	assert_true(_errors(q).contains("a flag value must be true/false, a number or a string"), "flag values are scalars")
	q = _main_quest()
	q.stages[0].items = [{"item": "item.iron_ingot", "count": 0}]
	assert_true(_errors(q).contains("count: must be >= 1"), "item counts")
	q = _main_quest()
	q.stages[0].xp = -5
	assert_true(_errors(q).contains(".xp: must be >= 0"), "XP is not negative")
	q = _main_quest()
	q.abandon_when = {"type": "flag"}
	assert_true(_errors(q).contains("abandon_when: missing required key 'flag'"), "abandon_when is a condition")
	q = _main_quest()
	q.start_conditions = [{"type": "flag", "flag": "quest.village.offer"}]
	assert_true(_warnings(q).contains("start_conditions are ignored while auto_start is true"), "a warning")
	q = _main_quest()
	q["reward"] = 5
	assert_true(_errors(q).contains("unknown key 'reward'"), "unknown keys")


func test_dialogue_rules() -> void:
	var d := QuestFixtures.elder_dialogue("dialogue.elder")
	d.id = "elder.talk"
	assert_true(_errors(d).contains("dialogue ids start with 'dialogue.'"), "the id prefix")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[1].choices[0].next = "nowhere"
	assert_true(_errors(d).contains("next: unknown node 'nowhere'"), "next names a node")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.entries[0].node = "missing"
	assert_true(_errors(d).contains("node: unknown node 'missing'"), "entries name nodes")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes.append({"id": "greet", "text": "again"})
	assert_true(_errors(d).contains("duplicate node id 'greet'"), "node ids are unique")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[0].id = "Greet Node"
	assert_true(_errors(d).contains("must be a plain lowercase word like 'greet'"), "node ids are plain words")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	var effects: Dictionary = d.nodes[0].choices[2].effects
	effects.erase("once_flag")
	var e := _errors(d)
	for key: String in ["xp", "learn_abilities"]:
		assert_true(e.contains("effects.%s: a reward needs a once_flag" % key), "%s needs a once_flag" % key)
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[3].choices[0].effects.erase("once_flag")
	assert_true(_errors(d).contains("effects.give_items: a reward needs a once_flag"), "items need a once_flag")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[0].choices[0].effects.outcome = "Offer Cache"
	assert_true(_errors(d).contains("must be a plain lowercase word like 'intimidate'"), "outcomes are plain words")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[0].choices[2].effects.once_flag = "village"
	assert_true(_errors(d).contains("once_flag: flag id 'village' must be lowercase dotted"), "once flags are flag ids")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[0].choices[2].conditions = [{"type": "stage_at_least", "stage": 0}]
	assert_true(_errors(d).contains("stage: must be >= 1"), "choice conditions are checked")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.nodes[0].choices[0].effects["teleport"] = true
	assert_true(_errors(d).contains("unknown key 'teleport'"), "effects are a closed set")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.entries = [{"node": "greet", "conditions": [{"type": "flag", "flag": "dialogue.elder.met"}]}]
	var w := _warnings(d)
	assert_true(w.contains("no entry without conditions"), "a dialogue that may not start warns")
	assert_true(w.contains("node 'hostile' is never reached"), "unreachable nodes warn")
	d = QuestFixtures.elder_dialogue("dialogue.elder")
	d.erase("speaker")
	assert_true(_errors(d).contains("missing required key 'speaker'"), "a speaker")


func test_tutorial_prompt_rules() -> void:
	var p := _block_prompt()
	p.id = "hint.block"
	assert_true(_errors(p).contains("tutorial prompt ids start with 'tutorial.'"), "the id prefix")
	p = _block_prompt()
	p.trigger = {"type": "walk"}
	assert_true(_errors(p).contains("trigger.type: unknown value 'walk'"), "trigger types")
	p = _block_prompt()
	p.trigger.event = "hit_landed"
	assert_true(_errors(p).contains("trigger.event: unknown value 'hit_landed'"), "trigger events")
	p = _block_prompt()
	p.trigger["phase"] = 2
	assert_true(_errors(p).contains("trigger: unknown key 'phase'"), "a filter of another event")
	p = _block_prompt()
	p.trigger.action_tags_any = ["Sneaky"]
	assert_true(_errors(p).contains("unknown value 'Sneaky'"), "tags are known tags")
	p = _block_prompt()
	p.dismiss.outcome_in = ["dodged"]
	assert_true(_errors(p).contains("unknown value 'dodged'"), "outcomes are hit outcomes")
	p = _block_prompt()
	p.trigger = {"type": "entered", "area": "hollow_start"}
	assert_true(_errors(p).contains("trigger.area: id 'hollow_start' must be lowercase dotted"), "area ids")
	p = _block_prompt()
	p.trigger = {"type": "level", "level": 2}
	assert_eq(_errors(p), "", "a level trigger")
	p = _block_prompt()
	p.trigger = {"type": "stage", "stage": 11}
	assert_true(_errors(p).contains("stage: must be <= 10"), "stage bounds")
	p = _block_prompt()
	p.trigger = {"type": "flag", "flag": "tutorial.light.done"}
	p.dismiss = {"type": "timeout"}
	assert_true(_errors(p).contains("missing required key 'timeout_s'"), "a timeout needs its seconds")
	p = _block_prompt()
	p.dismiss = {"type": "action_kind", "action_kind": "light", "count": 3, "timeout_s": 20}
	assert_eq(_errors(p), "", "an action dismissal with a timeout fallback")
	p = _block_prompt()
	p.dismiss = {"type": "action_kind", "action_kind": "smash"}
	assert_true(_errors(p).contains("unknown value 'smash'"), "action kinds")
	p = _block_prompt()
	p.dismiss = {"type": "action_id", "action_id": "ability.heavy_footfall", "count": 0}
	assert_true(_errors(p).contains("count: must be >= 1"), "counts")
	p = _block_prompt()
	p.dismiss = {"type": "event", "event": "camera_mode_changed", "count": 2}
	assert_eq(_errors(p), "", "a filterless event counted twice")
	p = _block_prompt()
	p.dismiss = {"type": "event", "event": "interacted", "interact_prefix": "valley.shrine.", "timeout_s": 15}
	assert_eq(_errors(p), "", "an interact prefix or 15 s")
	p = _block_prompt()
	p.dismiss = {"type": "vanish"}
	assert_true(_errors(p).contains("dismiss.type: unknown value 'vanish'"), "dismiss types")
	p = _block_prompt()
	p.sets_flag = "done"
	assert_true(_errors(p).contains("sets_flag: flag id 'done' must be lowercase dotted"), "sets_flag")
	p = _block_prompt()
	p.requires_flags = ["Tutorial Light"]
	assert_true(_errors(p).contains("requires_flags[0]: flag id 'Tutorial Light'"), "requires_flags")
	p = _block_prompt()
	p.text = "Press {warp_drive} now."
	assert_true(_warnings(p).contains("{warp_drive} names no input action"), "an unknown placeholder warns")
	p = _block_prompt()
	p.text = "{camera_toggle} {light_attack} {heavy_attack} {slot_1} {lock_target} {block} {dodge} {interact} {slot_5} {inventory} {attack_light}"
	assert_eq(_warnings(p), "", "every §4.5 placeholder (and action names) is known")
	p = _block_prompt()
	p.erase("dismiss")
	assert_true(_errors(p).contains("missing required key 'dismiss'"), "a dismissal is required")
