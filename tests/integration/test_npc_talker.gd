extends IntegrationSuite
## NpcTalker and the dialogue screen (plan §2.7.4, §3.15 designs 3-4) with the real giant: E next
## to a test NPC emits dialogue_requested and opens the dialogue screen on Quests' session; the
## screen shows the speaker, the line and numbered choices (keys 1-4), pauses the game, takes a
## rewarded choice through the real progression (the ability learned once, XP once over two
## conversations) and closes when the conversation ends, leaving Quests.dialogue null; Esc leaves
## without choosing; a talker on an NPC takes its ids from its parent and goes when it dies. M8 gate
## (F5): a talker whose npc's death WorldState records starts silent (its chunk loaded again).

const Fx := preload("res://tests/support/quest_fixtures.gd")
const STORY := "dialogue.test_story"

var requests: Array = []
var interactions: Array = []
var messages: Array = []


func before_each() -> void:
	await super()
	requests.clear()
	interactions.clear()
	messages.clear()
	Events.dialogue_requested.connect(_on_dialogue_requested)
	Events.interacted.connect(_on_interacted)
	Fx.install([Fx.storyteller_dialogue(STORY)])


func after_each() -> void:
	for pair: Array in [[Events.dialogue_requested, _on_dialogue_requested], [Events.interacted, _on_interacted]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	await super()


func _on_dialogue_requested(npc_id: String, dialogue_id: String) -> void:
	requests.append([npc_id, dialogue_id])


func _on_interacted(_t: int, actor_id: String, interact_id: String) -> void:
	interactions.append([actor_id, interact_id])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


func _stack() -> ScreenStack:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	return stack


func _talker(pos: Vector3, npc_id := "test.npc", dialogue_id := STORY) -> NpcTalker:
	var t := NpcTalker.new()
	t.npc_id = npc_id
	t.dialogue_id = dialogue_id
	t.position = pos
	world.add_child(t)
	return t


func _press_key(keycode: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.pressed = true
	Input.parse_input_event(k)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


## [§3.15 tests] E next to a test NPC emits dialogue_requested and opens the dialogue screen on
## that session.
func test_e_next_to_a_talker_opens_the_dialogue_screen_on_its_session() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(1)
	# A New Game character: level 1, it knows only Footfall and Sweeping Blow.
	p.apply_character_state(CharacterState.new_game(GameData.get_record("progression.default"),
		GameData.get_record("player.giant")))
	assert_false(p.known_abilities.has("ability.stone_skin"), "Stone Skin is not known yet")
	var stack := _stack()
	_talker(Vector3(0, 0, -3))
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "Talk to Old Tomas", "the prompt names the speaker")
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_eq(requests, [["test.npc", STORY]], "E emits dialogue_requested(npc_id, dialogue_id)")
	assert_eq(interactions, [["player", "test.npc"]], "interacted names the npc")
	var session := Quests.dialogue
	assert_true(session != null and session.is_active(), "Quests started the conversation")
	await get_tree().process_frame
	assert_true(stack.is_open("dialogue"), "the dialogue screen opened")
	var screen := stack.top() as DialogueScreen
	assert_true(screen != null, "a DialogueScreen")
	if screen == null:
		return
	assert_true(screen.session == session, "on Quests' session")
	assert_true(get_tree().paused, "it pauses the game")
	assert_eq(screen.visible_text(), "Old Tomas: Sit, giant. Hear of the First King?", "speaker and line")
	assert_eq(screen.choice_texts(), PackedStringArray(["1. Tell me the tale.", "2. Goodbye."]), "numbered choices")
	assert_true(screen.first_focus() == screen.choice_buttons[0], "the first choice has the focus")
	await _press_key(KEY_1)
	assert_true(stack.is_open("dialogue"), "the tale goes on")
	assert_eq(screen.visible_text(), "Old Tomas: He was the first of us to grow.", "the next line")
	assert_eq(screen.choice_texts(), PackedStringArray(["1. Thank you."]), "its choices")
	assert_eq(p.progression.xp, 25, "the reward's XP reached the giant")
	assert_true(p.known_abilities.has("ability.stone_skin"), "the ability was taught through its progression")
	assert_eq(p.progression.learned, [{"id": "ability.stone_skin", "slot": "slot_3", "source": "reward"}],
		"as a reward, into its slot")
	assert_true(p.controller.level_exempt.has("ability.stone_skin"), "usable before level 2")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "the gift")
	await _press_key(KEY_1)
	assert_false(stack.is_open("dialogue"), "the last choice closes the screen")
	assert_true(Quests.dialogue == null, "Quests.dialogue is null after the conversation")
	assert_false(get_tree().paused, "the game runs again")
	# A second conversation: the same choice is offered and taken, but grants nothing.
	await step_ticks(2)
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	await get_tree().process_frame
	screen = stack.top() as DialogueScreen
	assert_true(screen != null, "talking again opens it again")
	if screen == null:
		return
	screen.press_choice(0)
	assert_eq(p.progression.xp, 25, "no second XP")
	assert_eq(p.progression.learned.size(), 1, "taught once")
	assert_eq(WorldState.count_of("item.wood_scrap"), 1, "no second gift")
	screen.cancel()
	await get_tree().process_frame
	assert_false(stack.any_open(), "Esc leaves the conversation")
	assert_true(Quests.dialogue == null, "and ends it")


func test_closing_the_screen_ends_the_conversation() -> void:
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var stack := _stack()
	await step_ticks(1)
	Events.dialogue_requested.emit("test.npc", STORY)
	await get_tree().process_frame
	assert_true(stack.is_open("dialogue"), "a request opens the screen")
	var session := Quests.dialogue
	stack.close_all()
	await get_tree().process_frame
	assert_false(session.is_active(), "closing every screen (the bot, a reload) ends the conversation")
	assert_true(Quests.dialogue == null, "and clears it")
	Events.hud_message.connect(_on_message)
	Events.dialogue_requested.emit("test.npc", "dialogue.test_missing")
	Events.hud_message.disconnect(_on_message)
	await get_tree().process_frame
	assert_false(stack.any_open(), "an unknown dialogue opens nothing")
	assert_eq(messages, [Quests.NOTHING_TO_SAY], "and says so")


func test_a_talker_on_an_npc_takes_its_ids_and_goes_when_it_dies() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var npc := spawn_soldier(Vector3(0, 0.05, -3), PI, "test.villager")
	var t := NpcTalker.new()
	t.dialogue_id = STORY
	npc.add_child(t)
	await step_ticks(8)
	assert_eq(t.resolved_npc_id(), "test.villager", "the npc id is the parent's entity id")
	assert_eq(t.interact_id, "test.villager", "and its interact id")
	assert_true(t.can_interact(p), "it can talk")
	assert_eq(p.interact.current_prompt(), "Talk to Old Tomas", "the prompt")
	var mute := NpcTalker.new()
	mute.dialogue_id = "dialogue.test_missing"
	mute.prompt = "Listen"
	world.add_child(mute)
	assert_false(mute.can_interact(p), "no dialogue: nothing to say")
	assert_eq(mute.blocked_reason(p), "They have nothing to say.", "with a reason")
	assert_eq(mute.prompt_text(p), "Listen", "a scene's own prompt is kept")
	queue_hit("player", "test.villager", Vector3(0, 0.05, 0), 5000.0)
	await step_ticks(2)
	assert_false(npc.entity.is_alive(), "the NPC died")
	assert_false(t.enabled, "gone once its NPC is dead")
	assert_false(t.can_interact(p), "and silent")


## M8 gate (F5): a talker standing for a spawned actor (P36's talker kind: Ulfra's beside Skarn's
## longhouses, Harrok's challenge stone) names the actor's npc_id, so its talk ends with the actor's
## death - also when the death was recorded before the talker was made (its chunk loaded again after
## the kill, a reload): WorldState.is_killed counts as dead in _ready and in can_interact.
func test_a_talker_whose_npc_was_killed_before_it_loaded_stays_silent() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	WorldState.record_killed("test.dead_chief")
	var dead := _talker(Vector3(0, 0, -3), "test.dead_chief")
	var alive := _talker(Vector3(30, 0, -3), "test.living_chief")
	await step_ticks(8)
	assert_false(dead.enabled, "a talker whose npc's death is recorded is gone when it loads")
	assert_false(dead.can_interact(p), "and cannot talk")
	assert_eq(dead.blocked_reason(p), "", "without a refusal line")
	assert_eq(p.interact.current_prompt(), "", "no prompt beside it")
	assert_true(alive.enabled and alive.can_interact(p), "another npc's talker still talks")
	# A death recorded while the talker stands (a kill elsewhere, a loaded save) silences it too.
	WorldState.record_killed("test.living_chief")
	assert_false(alive.can_interact(p), "a recorded death silences a standing talker")
