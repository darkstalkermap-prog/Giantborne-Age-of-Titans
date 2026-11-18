extends IntegrationSuite
## A look kept at a shrine (P42; plan M10 §2.10, §2.11, decision 16; the M8 gate's F15): a New Game with
## the creator's look saves it with its first checkpoint and the giant wears it; at a shrine, with its
## screen open, "Keep this look" (PlayerAppearance.set_record) emits appearance_changed once and GameSession
## re-takes the shrine's checkpoint at once, so the save holds the new look while the screen is still open;
## when a line is then chosen the mark ("auto") shows at once and appearance.mark_shown brings up the
## one-time tutorial.appearance_mark; outside a shrine's screen a new look waits for the next checkpoint.
## In the slow tier: the shrine's scene and screen cost about 0.25 s (P42.md, test cost).

const SHRINE := "res://scenes/world/shrine.tscn"
const Look := preload("res://tests/unit/test_appearance_record.gd")

var stack: ScreenStack


func before_each() -> void:
	await super()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _own_look() -> Dictionary:
	var r := Appearance.preset_record("young_giant")
	r.preset = ""
	r.skin = "skin.olive"
	r.hair.color = "haircolor.red"
	return r


func _player() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	return p


func test_a_look_kept_at_a_shrine_is_saved_at_once_and_the_mark_then_shows() -> void:
	GameSession.persist = true
	var look := _own_look()
	assert_true(GameSession.change_mode("valley", {"new_game": true, "appearance": look}).ok, "a New Game with a look")
	var p := await _player()
	assert_true(p.appearance.has_record() and Look.deep_eq(p.appearance.record(), look), "the giant wears its own look")
	assert_eq(str(p.appearance.look().hair_color.to_html(false)), str(Appearance.option("haircolor.red").color).trim_prefix("#"),
		"resolved from the record (the red hair)")
	var first := SaveSlots.read()
	assert_true(first.ok and Look.deep_eq(first.data.character.get("appearance"), look),
		"the New Game's first checkpoint saved it (%s)" % first.message)
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "valley.shrine.grove"
	s.shrine_id = "shrine.grove"
	s.position = Vector3(0, 0, -6)
	world.add_child(s)
	await step_ticks(2)
	s.interact(p)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(stack.top() is ShrineScreen, "the shrine's screen is open")
	var taken := GameSession.checkpoints_taken
	var kept := _own_look()
	kept.outfit.set = "outfit.chieftain"
	kept.mark = "auto"
	var heard := []
	var on_changed := func(tick: int, entity_id: String) -> void: heard.append([tick, entity_id])
	Events.appearance_changed.connect(on_changed)
	p.appearance.set_record(kept)
	Events.appearance_changed.disconnect(on_changed)
	assert_eq(heard.size(), 1, "Keep this look emits appearance_changed once")
	assert_eq(str(heard[0][1]) if not heard.is_empty() else "", p.entity.entity_id, "for the player")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(GameSession.checkpoints_taken > taken, "the shrine's checkpoint is taken again")
	var doc := SaveSlots.read()
	assert_true(doc.ok and Look.deep_eq(doc.data.character.get("appearance"), kept),
		"the save holds the new look while the screen is still open")
	assert_true((p.appearance.look().mark as Dictionary).is_empty(), "no line yet: no mark")
	assert_true(bool(p.progression.choose_ancestry("ancestry.stoneblood").ok), "Stoneblood chosen")
	await get_tree().process_frame
	assert_eq(str(p.appearance.look().mark.get("design", "")), str(Appearance.ancestry_mark("ancestry.stoneblood").design),
		"the line's mark shows at once (mark \"auto\")")
	assert_true(QuestConditions.truthy(WorldState.get_flag(PlayerAppearance.MARK_SHOWN_FLAG)),
		"and the one-time tutorial.appearance_mark is brought up (appearance.mark_shown)")
	(stack.top() as ShrineScreen).cancel()
	await get_tree().process_frame
	taken = GameSession.checkpoints_taken
	p.appearance.set_record(_own_look())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(GameSession.checkpoints_taken, taken, "outside a shrine's screen a new look waits for the next checkpoint")
