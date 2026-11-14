extends IntegrationSuite
## The tutorial's event prompts queue (the M8 gate's F28 and F32; moved here from
## tests/integration/test_tutorial.gd by P42, plan M10 §1.7 rule 4: the two tests wait out real prompt
## lifetimes, about 3.8 s of the default tier): two prompts of one event (the world's arrival and the map;
## a shrine's ancestry and fast-travel lessons) both show, one after the other, and a pending event prompt
## does not age while another prompt holds the screen (it shows when the screen is free; it still lapses
## after EVENT_PENDING_S when it could be shown but is held back, in combat). The shipped prompts' queue is
## also exercised end to end by tests/slow/test_m8_gate_tutorials.gd.

const Fx := preload("res://tests/support/quest_fixtures.gd")

var shown: Array = []
var dismissed: Array = []


func before_each() -> void:
	await super()
	shown.clear()
	dismissed.clear()
	Events.tutorial_shown.connect(_on_tutorial_shown)
	Events.tutorial_dismissed.connect(_on_tutorial_dismissed)


func after_each() -> void:
	for pair: Array in [[Events.tutorial_shown, _on_tutorial_shown], [Events.tutorial_dismissed, _on_tutorial_dismissed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_tutorial_shown(_t: int, id: String) -> void:
	shown.append(id)


func _on_tutorial_dismissed(_t: int, id: String, reason: String) -> void:
	dismissed.append([id, reason])


func _current_id() -> String:
	return str(Quests.current_tutorial().get("id", ""))


## Two prompts of one event: the higher shows first (20 s), the second is queued behind it and follows.
func test_two_prompts_of_one_event_both_show_one_after_the_other() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	var on_entry := {"type": "event", "event": "level_entered"}
	Fx.install([
		Fx.prompt("tutorial.test_arrival", on_entry, {"type": "timeout", "timeout_s": 20}, {"priority": 12}),
		Fx.prompt("tutorial.test_map", on_entry, {"type": "timeout", "timeout_s": 5}, {"priority": 8})])
	Fx.activate([], ["tutorial.test_arrival", "tutorial.test_map"])
	await step_ticks(1)
	Events.level_entered.emit(Sim.tick, "level.test", "new_game")
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_arrival", "the higher priority first")
	assert_eq(Quests.tutorial.pending_ids(), PackedStringArray(["tutorial.test_map"]), "the other one queued")
	await step_ticks(60 * 20 + 2)
	assert_eq(_current_id(), "tutorial.test_map", "20 s later the queued one follows (it was dropped after 6 s)")
	assert_eq(shown, ["tutorial.test_arrival", "tutorial.test_map"], "both shown")


## A pending event prompt waits behind another event's prompt, and behind a prompt whose state trigger
## takes the screen first; it lapses only when it could be shown and is held back for EVENT_PENDING_S.
func test_a_pending_event_prompt_waits_while_other_prompts_hold_the_screen() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	Fx.install([
		Fx.prompt("tutorial.test_ancestry", {"type": "event", "event": "shrine_activated"},
			{"type": "timeout", "timeout_s": 10}, {"priority": 14}),
		Fx.prompt("tutorial.test_travel", {"type": "event", "event": "shrine_activated"},
			{"type": "timeout", "timeout_s": 5}, {"priority": 6, "defer_in_combat": true}),
		Fx.prompt("tutorial.test_sealed", Fx.flag_cond("test.flag.sealed"), {"type": "timeout", "timeout_s": 12},
			{"priority": 7}),
		Fx.prompt("tutorial.test_gate", {"type": "event", "event": "size_gate_blocked"},
			{"type": "timeout", "timeout_s": 5}, {"priority": 9, "defer_in_combat": true})])
	Fx.activate([], ["tutorial.test_ancestry", "tutorial.test_travel", "tutorial.test_sealed", "tutorial.test_gate"])
	await step_ticks(1)
	Events.shrine_activated.emit(Sim.tick, "world.shrine.test")
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_ancestry", "the shrine's first lesson")
	WorldState.set_flag("test.flag.sealed", true)   # a sealed place seen meanwhile (a state trigger)
	await step_ticks(60 * 10 + 2)
	assert_eq(_current_id(), "tutorial.test_sealed", "then the higher-priority state prompt")
	await step_ticks(60 * 12 + 2)
	assert_eq(_current_id(), "tutorial.test_travel", "and then the shrine's second lesson, 22 s after the shrine")
	await step_ticks(60 * 5 + 2)
	assert_eq(shown, ["tutorial.test_ancestry", "tutorial.test_sealed", "tutorial.test_travel"], "all three, in order")
	# Held back in combat with the screen free: it still lapses after EVENT_PENDING_S.
	p.entity.combatant.pools.mark_combat()
	Events.size_gate_blocked.emit(Sim.tick, "world.gate.test", 5, "Too deep.")
	for i in int(TutorialDirector.EVENT_PENDING_S * 60) + 30:
		p.entity.combatant.pools.mark_combat()
		await step_ticks(1)
	assert_eq(Quests.tutorial.pending_ids(), PackedStringArray(), "a prompt held back in combat lapses")
	p.entity.combatant.pools.since_combat = 999.0
	await step_ticks(2)
	assert_false(shown.has("tutorial.test_gate"), "and does not show after the fight")
