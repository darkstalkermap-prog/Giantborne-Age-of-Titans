extends IntegrationSuite
## M8 gate (F15): what the giant makes of itself in a shrine's screen is saved with the shrine as the
## respawn. The real path: a world shrine's interact() asks for the screen (GameSession takes the
## shrine's checkpoint first), the stack opens it, and in it the giant learns two talents (Talents
## tab), spends attribute points (Attributes tab) and chooses Stoneblood (Ancestry tab, then the
## ancestry screen's Choose) - the screens call these permanent. Then Leave, and:
##   * the save slot holds them at once, the shrine the respawn (a closed tab or a crash keeps them);
##   * a death before any later checkpoint reloads them, and a second, other ancestry is refused;
##   * Quit to title and Continue load them, and a second ancestry is refused there too;
##   * a loadout change at the shrine is saved as well; a change outside a shrine screen takes no
##     shrine checkpoint (it waits for the next checkpoint, as XP does).
## The shrine and the screens only (no world): the default tier.

const SHRINE := "res://scenes/world/shrine.tscn"
const SHRINE_ID := "world.shrine.kingsgate"
const TALENTS := ["talent.guardian_stone_hide", "talent.destroyer_heavy_hands"]

var stack: ScreenStack


func before_each() -> void:
	await super()
	InputBindings.reset_device()
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
	InputBindings.reset_device()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


## The campaign in level.world (saving on), a level-9 stage-4 giant with talent and attribute points
## in the Old Kingdom, and the Kingsgate shrine before it.
func _start() -> Dictionary:
	GameSession.persist = true
	GameSession.start_world_for_tests("world.cp.kingsgate_shelf")
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	var lv := CharacterState.normalize(p.capture_character_state())
	lv["level"] = 9
	lv["xp"] = Progression.xp_for_level(9)
	lv["talent_points"] = 8
	lv["unspent_attribute_points"] = 3
	p.apply_character_state(lv)
	p.set_profile(GameData.get_record("growth.04"))
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = SHRINE_ID
	s.shrine_id = "shrine.world_kingsgate"
	s.position = Vector3(0, 0, -6)
	world.add_child(s)
	await step_ticks(2)
	return {"player": p, "shrine": s}


## Uses the shrine (E): GameSession checkpoints, the stack opens the screen (deferred).
func _open(s: Shrine, p: GiantPlayer) -> ShrineScreen:
	s.interact(p)
	await get_tree().process_frame
	await get_tree().process_frame
	return stack.top() as ShrineScreen


## Learns the two talents, spends 2 attribute points and chooses Stoneblood through the tabs and the
## ancestry screen.
func _choose_at_the_shrine(screen: ShrineScreen) -> void:
	var talents := screen.tab("Talents")
	for id: String in TALENTS:
		assert_true(bool(talents.call("learn", id).ok), "%s learned at the shrine" % id)
	var attrs := screen.tab("Attributes")
	assert_true(bool(attrs.call("spend", {"constitution": 2}).ok), "2 attribute points spent at the shrine")
	var anc := screen.tab("Ancestry")
	var confirm := anc.call("press_choose", "ancestry.stoneblood") as AncestryScreen
	assert_true(confirm != null, "Choose Stoneblood... opens the ancestry screen")
	if confirm == null:
		return
	assert_true(bool(confirm.confirm().ok), "Stoneblood chosen")
	await get_tree().process_frame


func _saved_character() -> Dictionary:
	var doc := SaveSlots.read()
	assert_true(doc.ok, "the save slot reads (%s)" % doc.message)
	return doc.data.get("character", {}) if doc.ok else {}


func _saved_respawn() -> String:
	var doc := SaveSlots.read()
	return str((doc.data.get("checkpoint", {}) as Dictionary).get("respawn", "")) if doc.ok else ""


func _assert_kept(ch: Dictionary, constitution: int, label: String) -> void:
	assert_eq(ch.get("talents"), TALENTS, "%s: the talents learned at the shrine" % label)
	assert_eq(str(ch.get("ancestry", "")), "ancestry.stoneblood", "%s: the ancestry chosen at the shrine" % label)
	assert_true(bool(ch.get("ancestry_chosen", false)), "%s: chosen for good" % label)
	assert_eq(int(ch.get("talent_points", -1)), 6, "%s: the talent points spent" % label)
	assert_eq(int((ch.get("attributes", {}) as Dictionary).get("constitution", -1)), constitution,
		"%s: the attribute points spent (and Stoneblood's)" % label)


func test_choices_at_a_shrine_are_saved_and_survive_a_death() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	var con0 := int(p.progression.attributes().get("constitution", 0))
	var con := con0 + 2 + int(Talents.attribute_bonus_of("ancestry.stoneblood").get("constitution", 0))
	var screen := await _open(st.shrine, p)
	assert_true(screen != null, "the shrine screen opened")
	if screen == null:
		return
	var taken := GameSession.checkpoints_taken
	await _choose_at_the_shrine(screen)
	assert_true(GameSession.checkpoints_taken > taken, "the choices take the shrine's checkpoint again")
	assert_eq(str(_saved_character().get("ancestry", "")), "ancestry.stoneblood",
		"the save holds the ancestry while the screen is still open (a closed tab keeps it)")
	screen.cancel()   # Leave
	await get_tree().process_frame
	await step_ticks(3)
	_assert_kept(_saved_character(), con, "on disk after Leave")
	assert_eq(_saved_respawn(), SHRINE_ID, "the shrine is the respawn")
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")
	# A death before any other checkpoint: the death reload keeps them.
	GameSession.reload_checkpoint("death")
	p.queue_free()
	await step_ticks(2)
	var q := spawn_player(Vector3(5, 0.05, 0))
	GameSession.on_level_ready(world, q)
	await step_ticks(2)
	assert_eq(q.progression.talents, TALENTS, "the talents survive a death")
	assert_true(q.progression.ancestry_chosen and q.progression.ancestry == "ancestry.stoneblood",
		"the ancestry survives a death")
	var again: Dictionary = q.progression.choose_ancestry("ancestry.wildheart")
	assert_false(bool(again.ok), "and a second, other ancestry is refused (%s)" % again.get("message", ""))
	assert_eq(str(again.get("reason", "")), "chosen", "because it is chosen")


func test_choices_at_a_shrine_survive_quit_to_title_and_continue() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	var screen := await _open(st.shrine, p)
	assert_true(screen != null, "the shrine screen opened")
	if screen == null:
		return
	await _choose_at_the_shrine(screen)
	screen.cancel()
	await get_tree().process_frame
	await step_ticks(1)
	GameSession.go_to_title()
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "at the title")
	p.queue_free()
	await step_ticks(2)
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	var q := spawn_player(Vector3(5, 0.05, 0))
	GameSession.on_level_ready(world, q)
	await step_ticks(2)
	assert_eq(q.progression.talents, TALENTS, "the talents after Continue")
	assert_true(q.progression.ancestry_chosen and q.progression.ancestry == "ancestry.stoneblood",
		"the ancestry after Continue")
	assert_false(bool(q.progression.choose_ancestry("ancestry.stormborn").ok), "a second ancestry is refused")


func test_a_loadout_change_at_a_shrine_is_saved_and_one_elsewhere_waits() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	var slot := ""
	var id := ""
	for key: String in GiantPlayer.SLOT_KEYS:
		if str(p.controller.loadout.get(key, "")) != "" and key != "ultimate":
			slot = key
			id = str(p.controller.loadout[key])
			break
	assert_true(slot != "", "a filled slot to empty")
	var screen := await _open(st.shrine, p)
	assert_true(screen != null, "the shrine screen opened")
	if screen == null:
		return
	var out: Dictionary = p.progression.set_slot(slot, "", st.shrine)
	assert_true(bool(out.ok), "the slot is emptied at the shrine (%s)" % out.get("message", ""))
	await get_tree().process_frame
	screen.cancel()
	await get_tree().process_frame
	await step_ticks(2)
	var saved_loadout: Dictionary = _saved_character().get("loadout", {})
	var slots: Array = saved_loadout.get("slots", [])
	var index := int(slot.trim_prefix("slot_")) - 1
	assert_true(index >= 0 and index < slots.size() and str(slots[index]) == "",
		"the emptied %s is in the save (%s held %s)" % [slot, slots, id])
	# Away from the shrine screen: a talent learned (a test or a tool) takes no shrine checkpoint.
	var taken := GameSession.checkpoints_taken
	assert_true(bool(p.progression.learn_talent(TALENTS[0]).ok), "a talent learned outside the screen")
	await get_tree().process_frame
	await step_ticks(2)
	assert_eq(GameSession.checkpoints_taken, taken, "no shrine checkpoint outside the shrine's screen")
	assert_eq(_saved_character().get("talents"), [], "the save waits for the next checkpoint")
