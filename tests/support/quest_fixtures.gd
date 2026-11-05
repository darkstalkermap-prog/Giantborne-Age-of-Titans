class_name QuestFixtures
extends RefCounted
## In-memory quest, dialogue and tutorial_prompt records for the P13 tests (plan §2.13: fixtures
## are dictionaries installed through TestFixtures, never shipped data files; ResetHooks restores
## them after every test), plus activate(), which turns quests on and scopes Quests and the
## tutorial director to the fixtures, so shipped records (P15's quest line and prompts) never
## interfere with a test.


## Installs every record (TestFixtures.record_override; undone after the test).
static func install(records: Array) -> void:
	for r: Dictionary in records:
		TestFixtures.record_override(str(r.id), r)
	Quests.tutorial.refresh_records()


## An id no record has: an empty list scopes to it, so "no quests" (or "no prompts") really is none
## (an empty scope would mean every record, the shipped ones included).
const NONE := "test.none"


## Turns quests on (Quests.test_active) for these quest and prompt ids only (an empty list: none);
## main_id names the quest listed first (default: none of them is the main quest unless it is
## "quest.main").
static func activate(quest_ids: Array, prompt_ids: Array = [], main_id := "") -> void:
	Quests.test_active = true
	Quests.scope = PackedStringArray(quest_ids if not quest_ids.is_empty() else [NONE])
	Quests.tutorial.scope = PackedStringArray(prompt_ids if not prompt_ids.is_empty() else [NONE])
	if main_id != "":
		Quests.main_quest_id = main_id
	Quests.tutorial.refresh_records()


static func quest(id: String, stages: Array, extra: Dictionary = {}) -> Dictionary:
	var r := {"schema_version": 1, "id": id, "type": "quest", "display_name": id.trim_prefix("quest.").capitalize(),
		"prototype_pacing": true, "auto_start": true, "start_conditions": [], "abandon_when": null,
		"stages": stages, "on_complete_flags": {}}
	r.merge(extra, true)
	return r


static func stage(id: String, complete_when: Dictionary, xp := 0, extra: Dictionary = {}) -> Dictionary:
	var s := {"id": id, "objective": "Objective %s" % id, "complete_when": complete_when, "marker": "",
		"xp": xp, "items": [], "set_flags": {}, "bot": {"action": "go"}}
	s.merge(extra, true)
	return s


static func flag_cond(flag: String, equals: Variant = null) -> Dictionary:
	var c := {"type": "flag", "flag": flag}
	if equals != null:
		c["equals"] = equals
	return c


static func prompt(id: String, trigger: Dictionary, dismiss: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var r := {"schema_version": 1, "id": id, "type": "tutorial_prompt", "text": "Prompt %s" % id,
		"trigger": trigger, "dismiss": dismiss, "requires_flags": [], "min_stage": 1, "priority": 0,
		"once": true, "defer_in_combat": false, "sets_flag": id + ".done"}
	r.merge(extra, true)
	return r


## The elder's conversation of plan §2.8.3 with the nodes the example leaves out (test copy).
static func elder_dialogue(id := "dialogue.test_elder") -> Dictionary:
	return {"schema_version": 1, "id": id, "type": "dialogue", "speaker": "Elder Maren",
		"entries": [
			{"node": "hostile", "conditions": [{"type": "flag", "flag": "faction.village.hostile"}]},
			{"node": "done", "conditions": [{"type": "flag", "flag": "quest.village.outcome"}]},
			{"node": "report_cache", "conditions": [{"type": "has_item", "item": "item.supply_cache", "count": 1}]},
			{"node": "greet", "conditions": []}],
		"nodes": [
			{"id": "greet", "text": "A giant... we want no trouble.",
				"choices": [
					{"text": "I'll bring back your stolen supplies.", "next": "thanks",
						"effects": {"set_flags": {"quest.village.offer": "cache", "dialogue.elder.met": true}, "outcome": "offer_cache"}},
					{"text": "I'll drive the ogre out of your fields.", "next": "thanks",
						"effects": {"set_flags": {"quest.village.offer": "ogre", "dialogue.elder.met": true}, "outcome": "offer_ogre"}},
					{"text": "[Loom over them] Open the bridge. Now.", "next": "cowed",
						"conditions": [{"type": "stage_at_least", "stage": 2}],
						"effects": {"set_flags": {"quest.village.outcome": "intimidate", "faction.village.stood_down": true,
							"faction.village.gate_open": true, "dialogue.elder.met": true},
							"outcome": "intimidate", "xp": 40, "learn_abilities": ["ability.thunder_roar"],
							"once_flag": "reward.village.intimidate"}},
					{"text": "Not now.", "next": ""}]},
			{"id": "thanks", "text": "Then go, and come back with good news.",
				"choices": [{"text": "Farewell.", "next": ""}]},
			{"id": "cowed", "text": "...The bridge is yours. Leave us be."},
			{"id": "report_cache", "text": "You found it!",
				"choices": [{"text": "Here is your supply cache.", "next": "rewarded",
					"effects": {"take_items": [{"item": "item.supply_cache", "count": 1}],
						"set_flags": {"quest.village.outcome": "help_cache", "faction.village.gate_open": true},
						"outcome": "help_cache", "xp": 120, "give_items": [{"item": "item.iron_ingot", "count": 2}],
						"learn_abilities": ["ability.ancestral_mend"], "once_flag": "reward.village.help"}}]},
			{"id": "rewarded", "text": "Thornwick thanks you."},
			{"id": "done", "text": "The bridge is open to you."},
			{"id": "hostile", "text": "Get away from us!"}]}


## A conversation whose rewarded choice stays on offer every time (to prove the once-flag gate).
static func storyteller_dialogue(id := "dialogue.test_story") -> Dictionary:
	return {"schema_version": 1, "id": id, "type": "dialogue", "speaker": "Old Tomas",
		"entries": [{"node": "start", "conditions": []}],
		"nodes": [
			{"id": "start", "text": "Sit, giant. Hear of the First King?",
				"choices": [
					{"text": "Tell me the tale.", "next": "tale",
						"effects": {"xp": 25, "give_items": [{"item": "item.wood_scrap", "count": 1}],
							"learn_abilities": ["ability.stone_skin"], "once_flag": "reward.test_story.tale",
							"outcome": "heard"}},
					{"text": "Goodbye.", "next": ""}]},
			{"id": "tale", "text": "He was the first of us to grow.",
				"choices": [{"text": "Thank you.", "next": "", "effects": {"close": true}}]}]}
