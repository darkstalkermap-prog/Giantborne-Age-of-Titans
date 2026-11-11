extends IntegrationSuite
## The yield protocol (plan M6-M9 §2.10; P34): a blow that would take Harrok below 25 % holds him at
## 25 % and he yields - at once IMMUNE and harmless, unlockable, the giant's lock released,
## Events.boss_yielded and the prompt's dialogue open. Hits still in flight (an Earthquake's later
## pulses) and Burning across the yield change nothing: the outcome waits for the prompt, and Spare
## stays possible. Only Strike confirmed in the prompt decides death: Corvane dies by the giant's one
## accepted blow; Harrok rises to fight to the death. Three poise breaks make Harrok yield, two under
## Wildheart's challenge. The yield prompt is armed only after a moment and Esc goes back, never away.
## M8 gate (F11): Harrok struck rises to a fight the boss bar and the music follow again (no "yields",
## the boss set back, in the phase the fight is in). (F13): a yield ends the giant's hold on the boss.

const HARROK := "res://scenes/enemies/harrok.tscn"
const CORVANE := "res://scenes/enemies/corvane.tscn"
const BOSS_BAR := preload("res://ui/hud/boss_bar.gd")
const FRAME := 1.0 / 60.0

var yields: Array = []


func before_each() -> void:
	await super()
	yields.clear()
	Events.boss_yielded.connect(_on_yielded)
	WorldState.clear()
	Quests.end_dialogue()


func after_each() -> void:
	if Events.boss_yielded.is_connected(_on_yielded):
		Events.boss_yielded.disconnect(_on_yielded)
	Quests.end_dialogue()
	await super()


func _on_yielded(_tick: int, id: String) -> void:
	yields.append(id)


func _spawn(path: String, id: String, pos: Vector3) -> EnemyActor:
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.position = pos
	world.add_child(e)
	return e


func _hit(target: EnemyActor, power: float, poise := 0.0, tick := -1, tags := PackedStringArray(["Melee"])) -> int:
	var h := HitEvent.new()
	h.tick = tick if tick >= 0 else Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = target.entity_id
	h.power = power
	h.attacker_stat = 10.0
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.poise_damage = poise
	h.tags = tags
	h.attacker_position = target.global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)
	return h.instance_id


func test_harrok_yields_at_25_percent_and_nothing_after_it_decides() -> void:
	var p := spawn_player(Vector3(0, 0.05, 20), 0.0)
	var h := _spawn(HARROK, "test.harrok", Vector3(0, 0.05, 0)) as RivalGiantEnemy
	await step_ticks(2)
	var pools := h.entity.combatant.pools
	assert_true(h.entity.combatant.unkillable, "armed: he cannot be killed before he yields")
	p.lock.target_id = h.entity.entity_id
	p.targeting.sync_lock(h.entity.entity_id, "test")
	h.p34_ignite(10.0)   # Burning across the yield
	_hit(h, 1.0e6)
	await step_ticks(1)
	assert_true(h.yielded, "he yields")
	assert_eq(h.yield_reason, "health", "at 25 %")
	assert_near(pools.health, 1250.0, 0.01, "held at exactly 25 % of 5,000")
	assert_eq(yields, ["test.harrok"], "boss_yielded with his id")
	assert_false(h.entity.combatant.lockable, "no longer lockable")
	assert_false(p.lock.is_locked(), "the giant's lock released")
	assert_false(h.ai_enabled, "harmless: his AI is off")
	assert_eq(h.controller.action_id(), "", "nothing swinging")
	assert_true(Quests.dialogue != null and Quests.dialogue.dialogue_id == "dialogue.yield_harrok", "the prompt's dialogue")
	# An Earthquake's later pulses (made before the yield), a fresh blow and an area effect: all refused.
	var before := pools.health
	_hit(h, 5000.0, 400.0, h.yield_tick - 1, PackedStringArray(["AoE", "Earthquake"]))
	_hit(h, 5000.0, 400.0)
	await step_ticks(1)
	assert_eq(pools.health, before, "no blow lands after the yield")
	var immune := 0
	for r in hits_on("test.harrok"):
		if r.outcome == HitResult.Outcome.IMMUNE:
			immune += 1
	assert_eq(immune, 2, "both IMMUNE")
	await step_ticks(30)
	assert_true(h.entity.is_alive(), "Burning across the yield changes nothing")
	assert_eq(pools.health, before, "not a point of health")
	assert_eq(h.yield_decided, "", "the outcome waits for the prompt")
	assert_true(h.entity.combatant.statuses.has("status.burning"), "still burning")
	# Spare stays possible.
	var s := Quests.dialogue
	assert_true(s.find_choice("spare") >= 0, "Spare is offered")
	s.choose_outcome("spare")
	assert_eq(h.yield_decided, "spare", "spared")
	assert_eq(WorldState.get_flag("boss.harrok.outcome"), "spared", "the outcome flag")
	assert_true(Waystone.flag_truthy(WorldState.get_flag("boss.harrok.defeated")), "the duel is won")
	_hit(h, 1.0e6)
	await step_ticks(1)
	assert_true(h.entity.is_alive(), "a spared giant is never struck down")


func test_only_a_confirmed_strike_kills() -> void:
	spawn_player(Vector3(0, 0.05, 12), 0.0)
	var c := _spawn(CORVANE, "test.corvane", Vector3(0, 0.05, 0))
	await step_ticks(2)
	c.p34_yield("guard_broken")
	assert_eq(yields, ["battle.iron_regiment"], "Corvane's yield carries the battle's id")
	var s := Quests.dialogue
	assert_true(s != null and s.dialogue_id == "dialogue.yield_corvane", "his prompt")
	assert_eq(s.find_choice("strike"), -1, "no Strike without a confirm first")
	var strike_idx := -1
	for ch: Dictionary in s.choices():
		if str(ch.next) == "confirm":
			strike_idx = int(ch.index)
	s.choose(strike_idx)
	await step_ticks(2)
	assert_true(c.entity.is_alive(), "asking to strike is not striking")
	assert_true(s.find_choice("strike") >= 0, "the confirm line")
	var back := -1
	for ch: Dictionary in s.choices():
		if str(ch.next) == "yield":
			back = int(ch.index)
	s.choose(back)
	assert_true(s.find_choice("spare") >= 0, "back at the choice")
	for ch: Dictionary in s.choices():
		if str(ch.next) == "confirm":
			strike_idx = int(ch.index)
	s.choose(strike_idx)
	s.choose_outcome("strike")
	await step_ticks(2)
	assert_eq(c.yield_decided, "strike", "struck")
	assert_false(c.entity.is_alive(), "the one accepted blow kills him")
	assert_eq(WorldState.get_flag("boss.corvane.outcome"), "slain", "slain")


func test_poise_breaks_wildheart_and_the_strike_that_lets_him_rise() -> void:
	var p := spawn_player(Vector3(0, 0.05, 20), 0.0)
	var h := _spawn(HARROK, "test.harrok", Vector3(0, 0.05, 0)) as RivalGiantEnemy
	await step_ticks(2)
	assert_eq(h.p34_yield_poise_breaks(), 3, "three poise breaks")
	p.progression.ancestry = "ancestry.wildheart"
	assert_eq(h.p34_yield_poise_breaks(), 2, "two under Wildheart's challenge")
	for i in 2:
		if h.controller.state == CombatController.State.STAGGERED:
			h.controller.call("_end_stagger")   # the next blow may break his poise again
		h.entity.combatant.poise.immunity_left = 0.0   # (the 1.5 s immunity after a stagger, skipped)
		_hit(h, 10.0, 1.0e5)
		await step_ticks(1)
	assert_eq(h.poise_breaks, 2, "two breaks")
	assert_true(h.yielded, "he kneels")
	assert_eq(h.yield_reason, "honour", "for honour")
	assert_true(h.entity.is_alive() and h.entity.combatant.pools.ratio("health") > 0.9, "unhurt")
	# Struck, he rises to fight to the death.
	h.ai_enabled = true
	h.set("_p34_ai_before", true)
	assert_true(h.p34_decide("strike"), "Strike decided")
	assert_false(h.yielded, "he rises")
	assert_true(h.ai_enabled, "and fights")
	assert_true(h.entity.combatant.lockable, "lockable again")
	assert_false(h.entity.combatant.unkillable, "to the death")
	_hit(h, 1.0e7)
	await step_ticks(1)
	assert_false(h.entity.is_alive(), "he can die now")
	assert_false(h.yielded, "no second yield")
	assert_eq(WorldState.get_flag("boss.harrok.outcome"), "slain", "slain")


func test_the_prompt_is_armed_late_and_esc_goes_back() -> void:
	spawn_player(Vector3(0, 0.05, 20), 0.0)
	var c := _spawn(CORVANE, "test.corvane", Vector3(0, 0.05, 0))
	await step_ticks(2)
	c.p34_yield("health")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	var prompt := stack.open("yield", {"session": Quests.dialogue, "name": "Corvane"}) as YieldPrompt
	assert_true(prompt != null, "the yield screen opens")
	assert_eq(prompt.choice_buttons.size(), 2, "two choices")
	assert_true(prompt.choice_buttons[0].disabled, "not armed yet")
	assert_eq(str(prompt.press_choice(0).get("reason", "")), "not_armed", "an early press is refused")
	prompt.arm_now()   # M8 gate (F7): the hook that stands for every button let go long enough
	prompt.press_choice(1)
	await get_tree().process_frame
	assert_true(Quests.dialogue.find_choice("strike") >= 0, "on the confirm line")
	prompt.arm_now()   # M8 gate (F7): the hook that stands for every button let go long enough
	prompt.cancel()
	assert_true(Quests.dialogue.find_choice("spare") >= 0, "Esc goes back to the choice")
	prompt.cancel()
	assert_true(prompt.is_open(), "and never closes the prompt undecided")
	assert_eq(c.yield_decided, "", "undecided")
	stack.close_all()


## M8 gate (F11): Strike on Harrok ("he rises and fights to the death") takes back everything his
## yield ended: the bar no longer says "yields", and his boss music is due again, in the phase the fight
## is in (the director's boss state is pending: a test world has no zone for it to play over).
func test_struck_he_rises_and_the_bar_and_the_music_follow_the_fight() -> void:
	Audio.enable_for_tests()
	spawn_player(Vector3(0, 0.05, 20), 0.0)
	var h := _spawn(HARROK, "test.harrok", Vector3(0, 0.05, 0)) as RivalGiantEnemy
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var bar := BOSS_BAR.new()
	layer.add_child(bar)
	await step_ticks(2)
	Events.boss_engaged.emit(Sim.tick, h.entity_id)   # (his arena's engagement)
	assert_eq(Audio.music.boss_id, h.entity_id, "his music is due")
	h.brain.update_boss_phase(0.4, Sim.tick)
	assert_eq(h.boss_phase(), 2, "his second phase")
	assert_eq(Audio.music.boss_phase, 2, "the music follows to phase 2")
	h.p34_yield("health")
	await get_tree().process_frame
	assert_true(bar.visible_text().ends_with("yields"), "the bar: he yields ('%s')" % bar.visible_text())
	assert_eq(Audio.music.boss_id, "", "his music ends with the yield")
	assert_true(h.p34_decide("strike"), "Strike")
	Quests.end_dialogue()
	await get_tree().process_frame
	assert_false(bar.visible_text().ends_with("yields"), "he fights to the death: no 'yields' ('%s')" % bar.visible_text())
	assert_eq(Audio.music.boss_id, h.entity_id, "his music again")
	assert_eq(int(Audio.music.pending.get("state", -1)), MusicDirector.State.BOSS, "the boss state is due")
	assert_eq(Audio.music.boss_phase, 2, "in the phase the fight is in")
	assert_true(h.entity.combatant.lockable and not h.yielded and not h.entity.combatant.unkillable, "and he fights")
