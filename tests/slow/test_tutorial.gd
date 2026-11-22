extends IntegrationSuite
## The tutorial director (plan §3.15 design 5, §4.5) on fixture prompts with the real giant: a
## prompt is dismissed by the matching action (real light attacks) and never shows again after its
## seen flag; an event trigger on a real soldier's chop telegraphed at the player (a Parryable
## action) shows the block prompt, which a hit_resolved with outcome blocked or parried dismisses;
## a defer_in_combat prompt waits until the fight is over; the highest priority shows first, one at
## a time; an entered trigger is presence and combines with min_stage after growing inside the
## area; timeouts (the lesson) and timeout fallbacks (no lesson); once=false prompts come back on a
## new edge; event filters; the HUD widget resolves {placeholders} for the device.
## M4 gate: a fallback takes the prompt away, not its lesson - real camera toggles and light attacks
## after it, a block and a dodge after theirs (event lessons with a dependent prompt), and a flag
## lesson still set the lesson's flag, so a quest stage waiting for it completes and a prompt that
## needs it follows; the prompt itself never shows again.
## M8 gate (F28, F32): an event recorded with a new giant before the first tick of its level (main.gd's
## loading gate emits level_entered while the tree is paused) survives that tick's level-memory reset.
## The event prompts' queue (two prompts of one event shown one after the other; a pending event prompt
## that does not age while another prompt holds the screen) waits out real prompt lifetimes, about 3.8 s:
## M10 (P42, plan M10 §1.7 rule 4) moved those two tests to tests/slow/test_tutorial_queues.gd.

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


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func _current_id() -> String:
	return str(Quests.current_tutorial().get("id", ""))


func _hit(attacker: String, defender: String, outcome: int) -> void:
	var ev := HitEvent.new()
	ev.attacker_id = attacker
	ev.target_id = defender
	ev.action_id = "ability.soldier_chop"
	var r := HitResult.new()
	r.event = ev
	r.outcome = outcome
	Events.hit_resolved.emit(Sim.tick, r)


func test_a_prompt_is_dismissed_by_its_action_and_never_shows_again() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var hud := _hud()
	Fx.install([Fx.prompt("tutorial.test_light", Fx.flag_cond("test.flag.at_dummies"),
		{"type": "action_kind", "action_kind": "light", "count": 2},
		{"text": "Strike with {light_attack}. Press it again to chain."})])
	Fx.activate([], ["tutorial.test_light"])
	await step_ticks(3)
	assert_eq(_current_id(), "", "no prompt before its trigger")
	WorldState.set_flag("test.flag.at_dummies", true)
	await step_ticks(1)
	assert_eq(_current_id(), "tutorial.test_light", "shown when its trigger holds")
	assert_eq(shown, ["tutorial.test_light"], "tutorial_shown")
	await get_tree().process_frame
	var w := hud.get_node_or_null("TutorialPrompt")
	assert_true(w != null, "the widget is on the HUD")
	if w != null:
		assert_eq(w.call("visible_text"), "Strike with %s. Press it again to chain." % InputBindings.describe_action("attack_light", false),
			"the placeholder resolved for the keyboard")
		assert_eq(w.call("shown_id"), "tutorial.test_light", "its id")
	Events.ability_started.emit(Sim.tick, "soldier_01", "ability.light_1", 1)
	Events.ability_started.emit(Sim.tick, "player", "ability.heavy_1", 2)
	assert_eq(int(Quests.current_tutorial().progress), 0, "another actor's light and the player's heavy do not count")
	p.router.inject_light_attack()
	await step_ticks(14)
	assert_eq(int(Quests.current_tutorial().progress), 1, "the first real light attack counts")
	p.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return _current_id() == "", 90)
	assert_eq(_current_id(), "", "two lights dismiss it")
	assert_eq(dismissed, [["tutorial.test_light", "done"]], "tutorial_dismissed: done")
	assert_eq(WorldState.get_flag("tutorial.test_light.done"), true, "its sets_flag")
	assert_eq(WorldState.get_flag(TutorialDirector.seen_flag("tutorial.test_light")), true, "its seen flag")
	await step_ticks(10)
	await get_tree().process_frame
	assert_eq(shown.size(), 1, "never shown again although its trigger still holds")
	if w != null:
		assert_eq(w.call("visible_text"), "", "the widget is empty")


func test_a_parryable_telegraph_at_the_player_shows_block_until_a_block() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -3), PI)
	Fx.install([Fx.prompt("tutorial.test_block",
		{"type": "event", "event": "telegraph_started", "target": "player", "action_tags_any": ["Parryable"]},
		{"type": "event", "event": "hit_resolved", "defender": "player", "outcome_in": ["blocked", "parried"]},
		{"text": "Raise your guard with {block}.", "priority": 20})])
	Fx.activate([], ["tutorial.test_block"])
	await step_ticks(2)
	Events.telegraph_started.emit(Sim.tick, "soldier_01", "ability.soldier_chop", "test.someone_else", "line",
		Vector3.ZERO, 0.0, 0.0, 2.5, 0.85)
	Events.telegraph_started.emit(Sim.tick, "test.mage", "ability.mage_slow_bolt", "player", "line",
		Vector3.ZERO, 0.0, 0.0, 20.0, 1.0)
	await step_ticks(2)
	assert_eq(_current_id(), "", "not for a telegraph at someone else, nor for an unparryable one")
	s.brain.target_id = "player"
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_block", "a real chop telegraphed at the player shows it")
	_hit("soldier_01", "player", HitResult.Outcome.HIT)
	_hit("player", "soldier_01", HitResult.Outcome.BLOCKED)
	assert_eq(_current_id(), "tutorial.test_block", "a hit taken, or a block by someone else, does not dismiss it")
	_hit("soldier_01", "player", HitResult.Outcome.PARRIED)
	assert_eq(_current_id(), "", "a parry dismisses it")
	assert_eq(dismissed, [["tutorial.test_block", "done"]], "done")
	assert_eq(WorldState.get_flag("tutorial.test_block.done"), true, "tutorial.test_block.done set")
	await TestWait.until(self, func() -> bool: return s.controller.action == null, 120)
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(3)
	assert_eq(shown, ["tutorial.test_block"], "a once prompt never shows again after its seen flag")
	assert_false(p.entity == null, "the giant is there")


func test_a_defer_in_combat_prompt_waits_until_the_fight_is_over() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	Fx.install([Fx.prompt("tutorial.test_attributes", {"type": "level", "level": 2},
		{"type": "event", "event": "attributes_changed", "timeout_s": 20}, {"defer_in_combat": true})])
	Fx.activate([], ["tutorial.test_attributes"])
	await step_ticks(2)
	p.entity.combatant.pools.mark_combat()
	p.progression.add_xp(100, "test")
	assert_eq(p.progression.level, 2, "level 2")
	await step_ticks(30)
	assert_eq(_current_id(), "", "in combat: it waits")
	p.entity.combatant.pools.since_combat = 999.0
	await step_ticks(1)
	assert_eq(_current_id(), "tutorial.test_attributes", "out of combat: shown")
	p.progression.allocate({"strength": 1})
	assert_eq(_current_id(), "", "spending a point dismisses it")
	assert_eq(dismissed, [["tutorial.test_attributes", "done"]], "done")


func test_the_highest_priority_shows_first_and_one_at_a_time() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	var go := Fx.flag_cond("test.flag.go")
	Fx.install([
		Fx.prompt("tutorial.test_low", go, Fx.flag_cond("test.flag.low_done"), {"priority": 5}),
		Fx.prompt("tutorial.test_high", go, Fx.flag_cond("test.flag.high_done"), {"priority": 20}),
		Fx.prompt("tutorial.test_known", go, Fx.flag_cond("test.flag.known"), {"priority": 50})])
	Fx.activate([], ["tutorial.test_low", "tutorial.test_high", "tutorial.test_known"])
	WorldState.set_flag("test.flag.known", true)
	WorldState.set_flag("test.flag.go", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_high", "the highest priority first")
	assert_eq(WorldState.get_flag("tutorial.test_known.done"), true,
		"a prompt whose lesson is already done is completed without showing")
	assert_false(shown.has("tutorial.test_known"), "and never shown")
	await step_ticks(5)
	assert_eq(shown, ["tutorial.test_high"], "one at a time")
	WorldState.set_flag("test.flag.high_done", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_low", "then the next")
	assert_eq(dismissed, [["tutorial.test_high", "done"]], "the flag dismissed the first")


## [§2.8.3] An entered trigger is a state: it combines with min_stage after growing inside the area.
func test_entered_is_presence_and_combines_with_min_stage() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var area := AreaTrigger.new()
	area.area_id = "test.area.grove"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 10, 20)
	cs.shape = shape
	cs.position.y = 5.0
	area.add_child(cs)
	world.add_child(area)
	Fx.install([Fx.prompt("tutorial.test_hurl", {"type": "entered", "area": "test.area.grove"},
		{"type": "action_id", "action_id": "ability.boulder_hurl"}, {"min_stage": 2})])
	Fx.activate([], ["tutorial.test_hurl"])
	await TestWait.until(self, func() -> bool: return area.player_inside, 30)
	assert_true(area.player_inside, "the giant stands in the area")
	await step_ticks(3)
	assert_eq(_current_id(), "", "stage 1: not yet")
	p.growth.debug_set_stage(2)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_hurl", "grown inside the area: shown")
	Events.ability_started.emit(Sim.tick, "player", "ability.runic_bolt", 1)
	assert_eq(_current_id(), "tutorial.test_hurl", "another ability does not dismiss it")
	Events.ability_started.emit(Sim.tick, "player", "ability.boulder_hurl", 2)
	assert_eq(_current_id(), "", "the hurl does")


func test_timeouts_and_timeout_fallbacks() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	Fx.install([
		Fx.prompt("tutorial.test_guard", Fx.flag_cond("test.flag.a"), {"type": "timeout", "timeout_s": 0.5}),
		Fx.prompt("tutorial.test_grab", Fx.flag_cond("test.flag.b"),
			{"type": "event", "event": "grab_started", "timeout_s": 0.5})])
	Fx.activate([], ["tutorial.test_guard", "tutorial.test_grab"])
	WorldState.set_flag("test.flag.a", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_guard", "shown")
	await step_ticks(32)
	assert_eq(dismissed, [["tutorial.test_guard", "done"]], "a timeout prompt is done when its time is up")
	assert_eq(WorldState.get_flag("tutorial.test_guard.done"), true, "and sets its flag")
	WorldState.set_flag("test.flag.b", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_grab", "the next")
	await step_ticks(32)
	assert_eq(dismissed[-1], ["tutorial.test_grab", "timeout"], "a fallback timeout dismisses it as timeout")
	assert_false(WorldState.has_flag("tutorial.test_grab.done"), "without the lesson's flag")
	assert_eq(WorldState.get_flag("tutorial.test_grab.seen"), true, "but seen")


## M4 gate: the camera lesson after its fallback (the Hollow's awaken stage, 45 s in the Valley):
## a toggle made while the prompt showed still counts, the second one after the fallback teaches
## it; the stage waiting for the flag completes once and the prompt waiting for it follows.
func test_a_lesson_still_counts_after_its_fallback_took_the_prompt_away() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	Fx.install([
		Fx.prompt("tutorial.test_camera", Fx.flag_cond("test.flag.cradle"),
			{"type": "event", "event": "camera_mode_changed", "count": 2, "timeout_s": 0.5}, {"priority": 10}),
		Fx.prompt("tutorial.test_after", Fx.flag_cond("tutorial.test_camera.done"),
			{"type": "timeout", "timeout_s": 0.2}, {"priority": 5}),
		Fx.quest("quest.test_hollow", [
			Fx.stage("awaken", Fx.flag_cond("tutorial.test_camera.done"), 10),
			Fx.stage("train", Fx.flag_cond("test.flag.never"), 10)])])
	Fx.activate(["quest.test_hollow"], ["tutorial.test_camera", "tutorial.test_after"])
	WorldState.set_flag("test.flag.cradle", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_camera", "shown")
	assert_eq(Quests.stage_of("quest.test_hollow"), "awaken", "the stage waits for the lesson")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(3)
	assert_eq(int(Quests.current_tutorial().progress), 1, "one real toggle counted while it shows")
	await step_ticks(30)
	assert_eq(_current_id(), "", "the fallback took it away")
	assert_eq(dismissed, [["tutorial.test_camera", "timeout"]], "as a timeout")
	assert_false(WorldState.has_flag("tutorial.test_camera.done"), "the lesson is not done")
	assert_eq(Quests.tutorial.open_lesson_ids(), PackedStringArray(["tutorial.test_camera"]), "it stays open")
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_camera"), 1, "with the toggle made while it showed")
	Events.ability_started.emit(Sim.tick, "player", "ability.light_1", 1)
	Events.lock_target_changed.emit("player", "test.dummy", "press")
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_camera"), 1, "other events count nothing")
	await step_ticks(20)
	assert_eq(Quests.stage_of("quest.test_hollow"), "awaken", "the stage still waits")
	assert_eq(shown, ["tutorial.test_camera"], "and nothing that needs the lesson shows")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(3)
	assert_eq(WorldState.get_flag("tutorial.test_camera.done"), true, "a real toggle after the fallback teaches it")
	assert_eq(Quests.tutorial.open_lesson_ids(), PackedStringArray(), "the lesson is closed")
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_camera"), 0, "its count gone")
	await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.test_hollow") == "train", 30)
	assert_eq(Quests.stage_of("quest.test_hollow"), "train", "the stage waiting for it completes")
	var rewards := Quests.history.filter(func(h: Dictionary) -> bool: return h.quest_id == "quest.test_hollow" and h.event == "reward")
	assert_eq(rewards.size(), 1, "rewarded once")
	await TestWait.until(self, func() -> bool: return _current_id() == "tutorial.test_after", 10)
	assert_eq(_current_id(), "tutorial.test_after", "the prompt waiting for its flag follows")
	assert_eq(shown, ["tutorial.test_camera", "tutorial.test_after"], "the taught prompt never shows again")
	assert_eq(dismissed, [["tutorial.test_camera", "timeout"]], "and nothing is dismissed twice")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(3)
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_camera"), 0, "a taught lesson counts no more")


## M4 gate: the Hollow's other lessons after their fallbacks - light attacks (an action lesson,
## its count restarting after a reload), a block that unlocks the dodge prompt (which requires it)
## and a dodge (event lessons on hit outcomes, the spar stage needs both), and a flag lesson. A
## plain timeout prompt (its time is its lesson) and a lesson done in time are never open.
func test_action_event_and_flag_lessons_stay_open_after_their_fallbacks() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)   # faces -Z: its light attacks miss the soldier behind
	var s := spawn_soldier(Vector3(0, 0.05, 3), 0.0)
	var telegraph := {"type": "event", "event": "telegraph_started", "target": "player"}
	Fx.install([
		Fx.prompt("tutorial.test_light", Fx.flag_cond("test.flag.dummies"),
			{"type": "action_kind", "action_kind": "light", "count": 2, "timeout_s": 0.3}),
		Fx.prompt("tutorial.test_block", telegraph.merged({"action_tags_any": ["Parryable"]}),
			{"type": "event", "event": "hit_resolved", "defender": "player", "outcome_in": ["blocked", "parried"],
				"timeout_s": 0.3}, {"priority": 30}),
		Fx.prompt("tutorial.test_dodge", telegraph,
			{"type": "event", "event": "hit_resolved", "defender": "player", "outcome_in": ["evaded"], "timeout_s": 0.3},
			{"priority": 30, "requires_flags": ["tutorial.test_block.done"]}),
		Fx.prompt("tutorial.test_flag", Fx.flag_cond("test.flag.ask"),
			{"type": "flag", "flag": "test.flag.answer", "timeout_s": 0.3}),
		Fx.prompt("tutorial.test_guard", Fx.flag_cond("test.flag.guard"), {"type": "timeout", "timeout_s": 0.3}),
		Fx.quest("quest.test_spar", [Fx.stage("spar", {"type": "all", "of": [
			Fx.flag_cond("tutorial.test_block.done"), Fx.flag_cond("tutorial.test_dodge.done")]}, 10)])])
	Fx.activate(["quest.test_spar"], ["tutorial.test_light", "tutorial.test_block", "tutorial.test_dodge",
		"tutorial.test_flag", "tutorial.test_guard"])
	await step_ticks(2)
	# Light attacks: one counts, a reload forgets it, two more teach the lesson.
	WorldState.set_flag("test.flag.dummies", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_light", "the light prompt")
	await step_ticks(20)
	assert_eq(dismissed[-1], ["tutorial.test_light", "timeout"], "its fallback")
	p.router.inject_light_attack()
	await step_ticks(14)
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_light"), 1, "a real light attack after it counts")
	Events.ability_started.emit(Sim.tick, "soldier_01", "ability.light_1", 7)
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_light"), 1, "another actor's does not")
	Quests.tutorial.reset()
	assert_eq(Quests.tutorial.lesson_count("tutorial.test_light"), 0, "a reload forgets the count")
	assert_true(Quests.tutorial.open_lesson_ids().has("tutorial.test_light"), "not the open lesson")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
	p.router.inject_light_attack()
	await step_ticks(14)
	assert_false(WorldState.has_flag("tutorial.test_light.done"), "one light is not two")
	p.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return WorldState.get_flag("tutorial.test_light.done") == true, 90)
	assert_eq(WorldState.get_flag("tutorial.test_light.done"), true, "two real light attacks teach it")
	# The block: shown on a real chop at the giant, its fallback passes, a block later teaches it.
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
	s.brain.target_id = "player"
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_block", "a chop at the giant shows the block prompt")
	await TestWait.until(self, func() -> bool: return _current_id() == "", 40)
	assert_eq(dismissed[-1], ["tutorial.test_block", "timeout"], "its fallback")
	await TestWait.until(self, func() -> bool: return s.controller.action == null, 120)
	assert_false(WorldState.has_flag("tutorial.test_block.done"), "the chop that landed taught nothing")
	_hit("soldier_01", "player", HitResult.Outcome.HIT)
	_hit("player", "soldier_01", HitResult.Outcome.BLOCKED)
	assert_false(WorldState.has_flag("tutorial.test_block.done"), "a hit taken or a block by someone else neither")
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(2)
	assert_eq(_current_id(), "", "the dodge prompt needs the block lesson")
	_hit("soldier_01", "player", HitResult.Outcome.BLOCKED)
	assert_eq(WorldState.get_flag("tutorial.test_block.done"), true, "a block after the fallback teaches it")
	await TestWait.until(self, func() -> bool: return s.controller.action == null, 120)
	assert_eq(Quests.stage_of("quest.test_spar"), "spar", "the spar stage needs the dodge too")
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_dodge", "the next chop shows the dodge prompt it unlocked")
	await TestWait.until(self, func() -> bool: return _current_id() == "", 40)
	assert_eq(dismissed[-1], ["tutorial.test_dodge", "timeout"], "its fallback passes too")
	_hit("soldier_01", "player", HitResult.Outcome.EVADED)
	assert_eq(WorldState.get_flag("tutorial.test_dodge.done"), true, "a dodge after it teaches it")
	await TestWait.until(self, func() -> bool: return Quests.is_complete("quest.test_spar"), 30)
	assert_true(Quests.is_complete("quest.test_spar"), "both lessons done late: the spar stage completes")
	# A flag lesson: done once its flag holds.
	WorldState.set_flag("test.flag.ask", true)
	await step_ticks(2)
	assert_eq(_current_id(), "tutorial.test_flag", "the flag prompt")
	await step_ticks(20)
	assert_eq(dismissed[-1], ["tutorial.test_flag", "timeout"], "its fallback")
	WorldState.set_flag("test.flag.answer", true)
	await step_ticks(1)
	assert_eq(WorldState.get_flag("tutorial.test_flag.done"), true, "its flag after the fallback teaches it")
	# A timeout prompt's time is its lesson: done, never open.
	WorldState.set_flag("test.flag.guard", true)
	await step_ticks(22)
	assert_eq(dismissed[-1], ["tutorial.test_guard", "done"], "a timeout prompt is done by its time")
	assert_eq(Quests.tutorial.open_lesson_ids(), PackedStringArray(), "no lesson stays open")
	assert_eq(shown, ["tutorial.test_light", "tutorial.test_block", "tutorial.test_dodge", "tutorial.test_flag",
		"tutorial.test_guard"], "each prompt shown once")


func test_once_false_prompts_come_back_on_a_new_edge() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	Fx.install([Fx.prompt("tutorial.test_again", Fx.flag_cond("test.flag.near", true),
		{"type": "timeout", "timeout_s": 0.1}, {"once": false})])
	Fx.activate([], ["tutorial.test_again"])
	WorldState.set_flag("test.flag.near", true)
	await step_ticks(12)
	assert_eq(shown, ["tutorial.test_again"], "shown and timed out")
	await step_ticks(12)
	assert_eq(shown.size(), 1, "not again while its trigger stays true")
	WorldState.set_flag("test.flag.near", false)
	await step_ticks(2)
	WorldState.set_flag("test.flag.near", true)
	await step_ticks(3)
	assert_eq(shown.size(), 2, "back after the trigger went false and true again")


func test_event_filters() -> void:
	var stag := {"type": "event", "event": "staggered", "near_player_m": 6.0, "grabbable": true}
	assert_true(TutorialDirector.event_matches(stag, "staggered", {"distance": 4.0, "grabbable": true}), "near and grabbable")
	assert_false(TutorialDirector.event_matches(stag, "staggered", {"distance": 7.0, "grabbable": true}), "too far")
	assert_false(TutorialDirector.event_matches(stag, "staggered", {"distance": 4.0, "grabbable": false}), "not grabbable")
	assert_false(TutorialDirector.event_matches(stag, "grab_started", {"distance": 4.0, "grabbable": true}), "another event")
	var lock := {"type": "event", "event": "lock_target_changed", "actor": "player", "non_empty": true}
	assert_true(TutorialDirector.event_matches(lock, "lock_target_changed", {"actor": "player", "target": "valley.hollow.dummy_1"}), "a lock")
	assert_false(TutorialDirector.event_matches(lock, "lock_target_changed", {"actor": "player", "target": ""}), "a release")
	var phase := {"type": "event", "event": "boss_phase_changed", "phase": 2}
	assert_true(TutorialDirector.event_matches(phase, "boss_phase_changed", {"phase": 2}), "phase 2")
	assert_false(TutorialDirector.event_matches(phase, "boss_phase_changed", {"phase": 1}), "not phase 1")
	var shrine := {"type": "event", "event": "interacted", "interact_prefix": "valley.shrine."}
	assert_true(TutorialDirector.event_matches(shrine, "interacted", {"interact_id": "valley.shrine.grove"}), "a shrine")
	assert_false(TutorialDirector.event_matches(shrine, "interacted", {"interact_id": "valley.quarry.cache"}), "a pickup")
	var started := {"type": "event", "event": "ability_started", "actor": "player", "action_kind": "ability",
		"action_id": "ability.heavy_footfall"}
	assert_true(TutorialDirector.event_matches(started, "ability_started", {"actor": "player", "action_kind": "ability",
		"action_id": "ability.heavy_footfall"}), "Footfall")
	assert_false(TutorialDirector.event_matches(started, "ability_started", {"actor": "player", "action_kind": "ability",
		"action_id": "ability.sweeping_blow"}), "another ability")
	var tele := {"type": "event", "event": "telegraph_started", "actor_archetype": "wolf"}
	assert_true(TutorialDirector.event_matches(tele, "telegraph_started", {"archetype": "wolf"}), "a wolf's")
	assert_false(TutorialDirector.event_matches(tele, "telegraph_started", {"archetype": "soldier"}), "a soldier's")
	assert_false(TutorialDirector.event_matches({"event": "camera_mode_changed", "zoom": 1}, "camera_mode_changed", {}),
		"an unknown filter never matches")


func test_placeholders_resolve_for_the_device() -> void:
	var text := "{light_attack} | {heavy_attack} | {slot_5} | {camera_toggle} | {warp_drive}"
	var kb := TutorialText.resolve(text, false)
	var expected_heavy := "%s + %s" % [InputBindings.describe_action("heavy_modifier", false),
		InputBindings.describe_action("attack_light", false)]
	assert_eq(kb, "%s | %s | %s | %s | {warp_drive}" % [InputBindings.describe_action("attack_light", false),
		expected_heavy, InputBindings.describe_action("ability_5", false), InputBindings.describe_action("camera_toggle", false)],
		"keyboard names; the heavy attack is the modifier plus the light; unknown words stay")
	var pad := TutorialText.resolve(text, true)
	assert_eq(pad, "%s | %s | %s | %s | {warp_drive}" % [InputBindings.describe_action("attack_light", true),
		InputBindings.describe_action("attack_heavy", true), InputBindings.describe_action("ability_5", true),
		InputBindings.describe_action("camera_toggle", true)], "pad names")
	assert_eq(TutorialText.placeholders_in("{a} {b} {a}"), PackedStringArray(["a", "b"]), "words once each")


# --------------------------------------------------------------------------- M8 gate (F28, F32)

## main.gd's loading gate emits level_entered while the tree is paused: before the new giant's first
## tick. The event's prompt survives that tick's level-memory reset (Quests syncs the level first).
func test_an_entry_prompt_recorded_before_the_new_levels_first_tick_survives_it() -> void:
	var old := spawn_player(Vector3(0, 0.05, 0))
	Fx.install([Fx.prompt("tutorial.test_arrival", {"type": "event", "event": "level_entered"},
		{"type": "timeout", "timeout_s": 5}, {"priority": 12})])
	Fx.activate([], ["tutorial.test_arrival"])
	await step_ticks(2)
	# A new level's giant replaces the old one, and level_entered comes before any tick with it.
	world.remove_child(old)
	old.free()
	spawn_player(Vector3(4, 0.05, 0))
	Events.level_entered.emit(Sim.tick, "level.test", "travel")
	assert_eq(Quests.tutorial.pending_ids(), PackedStringArray(["tutorial.test_arrival"]), "the arrival is pending")
	await step_ticks(3)
	assert_eq(_current_id(), "tutorial.test_arrival", "and shows after the new level's first ticks")
