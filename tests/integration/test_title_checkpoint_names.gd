extends IntegrationSuite
## Checkpoint names and the skip-prologue choice (P20; plan M6-M9 §2.6, FOLLOWUPS: the title named
## the checkpoint by its id): the title's save line names the respawn by its display name from the
## level's world index ("Saved game: level 7, stage 3, at the Grove Shrine, ...") and never by its
## id; the checkpoint toast names it too ("Checkpoint saved: Grove Shrine", "Game loaded: Forest road
## waystone"), from the index or, without one, from the loaded shrine or waystone; New Game offers
## "Play the prologue" / "Skip to the Old Kingdom" only for a save that finished the prologue while
## level.world exists (a stub record here), and Skip starts the world from world_start.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const STAND_IN := "res://scenes/test/flow_test_level.tscn"
## A level.world scene that does not exist: a build without the world (P25 ships the world).
const NO_WORLD_SCENE := "res://scenes/world/no_such_world.tscn"
const SHRINE_SCENE := "res://scenes/world/shrine.tscn"
const TOAST := preload("res://ui/hud/checkpoint_toast.gd")

var layer: CanvasLayer
var stack: ScreenStack


func before_each() -> void:
	await super()
	layer = CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	SaveSlots.delete_slot(true)
	await super()


func _fixture(fixture_name: String) -> Dictionary:
	return SaveSlots.migrate(JsonIO.read_file(FIXTURE_DIR + fixture_name + ".json").data)


func _write_save(doc: Dictionary) -> void:
	GameSession.persist = true
	assert_true(SaveSlots.write(doc).ok, "the save is written")


func _stub_world() -> void:
	TestFixtures.record_override(GameSession.WORLD_LEVEL_ID, {"schema_version": 1, "type": "level",
		"display_name": "The Old Kingdom", "scene": STAND_IN, "start_checkpoint": "world.cp.kingsgate_shelf"})


func _title() -> TitleScreen:
	GameSession.mode = GameSession.Mode.TITLE
	var t := stack.open("title") as TitleScreen
	assert_true(t != null, "the title opens")
	return t


# --------------------------------------------------------------------------- the save line

func test_the_title_names_the_checkpoint_never_its_id() -> void:
	var doc := _fixture("v1_force_complete")
	doc.checkpoint.respawn = "valley.shrine.grove"
	_write_save(doc)
	var title := _title()
	var line := str(title.state().save)
	assert_true(line.begins_with("Saved game: level 7, stage 3, at the Grove Shrine"), "the save line: %s" % line)
	assert_false(line.contains("valley.shrine.grove"), "never the id")
	assert_true(title.state()["continue"], "Continue is offered")
	stack.close_all()
	for pair: Array in [["valley.cp.barrow_gap", "at the Barrow gap waystone"], ["valley.cp.forest_road", "at the Forest road waystone"],
			["valley.shrine.hollow", "at the Hollow Shrine"]]:
		doc.checkpoint.respawn = pair[0]
		var text := TitleScreen.describe_save(doc)
		assert_true(text.contains(str(pair[1])), "%s: %s" % [pair[0], text])
		assert_false(text.contains(str(pair[0])), "without the id: %s" % text)
	doc.checkpoint.respawn = "valley.cp.not_in_the_index"
	var unknown := TitleScreen.describe_save(doc)
	assert_false(unknown.contains(" at ") or unknown.contains("valley.cp"), "an unknown checkpoint is left out: %s" % unknown)
	# Another level: its name, and its own index's names ("The ..." names keep their article).
	_stub_world()
	var idx := WorldIndex.new()
	idx.checkpoints = {"world.cp.kingsgate_shelf": {"position": Vector3.ZERO, "display_name": "Kingsgate shelf"},
		"world.cp.kings_door": {"position": Vector3.ZERO, "display_name": "The Kings' Door"}}
	WorldIndex.put_cached(GameSession.WORLD_LEVEL_ID, idx)
	doc.level = GameSession.WORLD_LEVEL_ID
	doc.checkpoint.respawn = "world.cp.kingsgate_shelf"
	var w := TitleScreen.describe_save(doc)
	# P39f: a name that begins with "The" reads "the" mid-sentence (it was "in The Old Kingdom")
	assert_true(w.contains("at the Kingsgate shelf, in the Old Kingdom"), "a world save: %s" % w)
	assert_false(w.contains("The "), "no capital article mid-sentence: %s" % w)
	doc.checkpoint.respawn = "world.cp.kings_door"
	var door := TitleScreen.describe_save(doc)
	assert_true(door.contains("at the Kings' Door") and not door.contains("the the") and not door.contains("The "),
		"no doubled article, no capital one: %s" % door)
	assert_eq(TitleScreen.mid_sentence("The Old Kingdom"), "the Old Kingdom", "the level's name mid-sentence")
	assert_eq(TitleScreen.mid_sentence("Grove Shrine"), "the Grove Shrine", "a name without an article takes one")


## M9 gate (lane review): a display name that begins with "The" reads "the" mid-sentence in the game's other
## lines too, through TextUtil (scripts/core/text_util.gd): the bailey's gate line said "until The Iron Regiment
## is beaten", the Valley's forge "Reforge at the The Giantforge", its two vault pickups "Take the The Kings'
## Annals", a talker "Talk to The ...", a moved respawn "You wake at The Broken Stair". Every item a pickup may
## hold, every dialogue's speaker, the forges, exits and battles with such names: no "the The", no capital "The"
## after a line's first word.
func test_display_names_read_lower_case_mid_sentence() -> void:
	assert_eq(TextUtil.mid_sentence("The Iron Regiment"), "the Iron Regiment", "a leading The is lower-cased")
	assert_eq(TextUtil.mid_sentence("Reeve Tamsin"), "Reeve Tamsin", "any other name is left as it is: it only lower-cases")
	assert_eq(TextUtil.with_the("The Broken Stair"), "the Broken Stair", "after a 'the' of the sentence's own")
	assert_eq(TextUtil.with_the("Kingsgate shelf waystone"), "the Kingsgate shelf waystone", "a name without one takes it")
	var bad: Array = []   # an Array: the lambda below appends to it (a packed array would be its own copy there)
	var check := func(line: String, what: String) -> void:
		if line.contains("the The ") or line.to_lower().contains("the the ") or line.substr(1).contains(" The "):
			bad.append("%s: '%s'" % [what, line])
	var battle := BattleBoss.new()
	battle.battle_name = "The Iron Regiment"
	check.call(battle.gate_line(), "the bailey's gate line")
	assert_eq(battle.gate_line(), "The portcullis drops behind you: no way out until the Iron Regiment is beaten.",
		"the battle's gate line")
	battle.free()
	var forge := Forge.new()
	forge.display_name = "The Giantforge"
	assert_eq(forge.prompt_text(null), "Reforge at the Giantforge", "the Valley's forge")
	forge.display_name = "Giantforge"
	assert_eq(forge.prompt_text(null), "Reforge at the Giantforge", "a forge named without its article")
	forge.free()
	var pickup := ItemPickup.new()
	var named := 0
	for rec: Dictionary in GameData.records_of_type("item"):
		pickup.item_id = str(rec.id)
		pickup.count = 1
		check.call(pickup.prompt_text(null), str(rec.id))
		named += 1 if str(rec.get("display_name", "")).begins_with("The ") else 0
	pickup.item_id = "item.kings_annals"
	assert_eq(pickup.prompt_text(null), "Take the Kings' Annals", "the Citadel's annals")
	pickup.free()
	assert_true(named >= 2, "items named The ... are checked (%d)" % named)
	var talker := NpcTalker.new()
	for rec: Dictionary in GameData.records_of_type("dialogue"):
		talker.dialogue_id = str(rec.id)
		check.call(talker.prompt_text(null), str(rec.id))
	talker.dialogue_id = "dialogue.kingsgate_beacon"
	assert_eq(talker.prompt_text(null), "Talk to the Kingsgate beacon", "a speaker named The ...")
	talker.free()
	for exit_name: String in ["The Kings' Door", "The Broken Stair", "The Citadel stair"]:
		assert_eq(Quests.by_exit_text(exit_name), "by " + exit_name.replace("The ", "the "), "the tracker's way by %s" % exit_name)
	assert_eq(bad, [], "no line puts a capital The mid-sentence")


## M8 release (R2): the line names where Continue wakes the giant. A 0.7.0-m7 save at the Brannock waystone
## with Brannock hostile read "at the Brannock waystone" while Continue woke the giant at the Kingsgate shelf
## waystone ("Brannock's guards hold the ground there."): the line now applies the respawn blockers the load
## applies (GameSession.save_respawn), on the real world's index and records, before anything is loaded.
func test_the_save_line_names_where_continue_wakes_the_giant() -> void:
	var doc := _fixture("v2_m7_after_brannock_force")
	var flags: Dictionary = doc.world.flags
	assert_eq([str(doc.level), str(doc.checkpoint.respawn), flags.get("faction.brannock.hostile")],
		["level.world", "world.cp.brannock", true], "the save: the Brannock waystone, Brannock hostile")
	WorldState.set_flag("test.live_world", true)
	var line := TitleScreen.describe_save(doc)
	assert_true(line.begins_with("Saved game: level 9, stage 4, at the Kingsgate shelf waystone, in the Old Kingdom"),
		"the line names where the giant will wake: %s" % line)
	assert_false(line.contains("Brannock"), "not the stone its guards hold: %s" % line)
	assert_eq(WorldState.flags, {"test.live_world": true}, "describing a save leaves the live world as it was")
	# Continue wakes the giant there: the save loaded, the blockers the world's director registers move it.
	_write_save(doc)
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	GameSession.register_respawn_blocker(func(id: String) -> String: return FactionState.respawn_refusal(id))
	assert_eq(GameSession.respawn_checkpoint(), "world.cp.kingsgate_shelf", "Continue wakes the giant at the stone the line named")
	# With Brannock at peace the line names the saved stone.
	var calm := doc.duplicate(true)
	(calm.world.flags as Dictionary).erase("faction.brannock.hostile")
	assert_true(TitleScreen.describe_save(calm).contains("at the Brannock waystone"), "a stone nothing holds: %s" %
		TitleScreen.describe_save(calm))


# --------------------------------------------------------------------------- the toast

func test_the_toast_names_the_checkpoint() -> void:
	assert_eq(TOAST.saved_text(true, "", "Grove Shrine"), "Checkpoint saved: Grove Shrine", "saved, named")
	assert_eq(TOAST.saved_text(true, ""), "Checkpoint saved", "saved, unnamed")
	assert_eq(TOAST.saved_text(true, "saving is off", "Grove Shrine"), "Checkpoint (saving is off)",
		"not written: the reason, not the name")
	assert_eq(TOAST.saved_text(false, "disk full", "Grove Shrine"), "Checkpoint NOT saved (play continues)", "failed")
	assert_eq(TOAST.loaded_text("continue", "Forest road waystone"), "Game loaded: Forest road waystone", "Continue")
	assert_eq(TOAST.loaded_text("death", "Grove Shrine"), "Checkpoint loaded: Grove Shrine", "a death reload")
	assert_eq(TOAST.loaded_text("debug"), "Checkpoint reloaded (debug)", "unnamed")
	var toast: Control = TOAST.new()
	layer.add_child(toast)
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = "level.valley"
	assert_eq(GameSession.checkpoint_display_name("valley.shrine.grove"), "Grove Shrine", "the index names the shrine")
	Events.checkpoint_saved.emit(Sim.tick, "valley.shrine.grove", true, "")
	assert_eq(toast.call("visible_text"), "Checkpoint saved: Grove Shrine", "the live toast")
	Events.checkpoint_loaded.emit(Sim.tick, "valley.cp.forest_road", "continue")
	assert_eq(toast.call("visible_text"), "Game loaded: Forest road waystone", "Continue names the waystone")
	Events.checkpoint_saved.emit(Sim.tick, "valley.cp.no_such_stone", true, "")
	assert_eq(toast.call("visible_text"), "Checkpoint saved", "an unknown checkpoint: the plain line")
	# Without an index: the loaded shrine's record and the waystone's display_name.
	GameSession.mode = GameSession.Mode.SANDBOX
	GameSession.level_id = ""
	var shrine: Shrine = (load(SHRINE_SCENE) as PackedScene).instantiate()
	shrine.world_id = "test.shrine.toast"
	shrine.shrine_id = "shrine.thornwick"
	world.add_child(shrine)
	var stone := Waystone.new()
	stone.checkpoint_id = "test.cp.toast_stone"
	stone.display_name = "Test stone"
	world.add_child(stone)
	assert_eq(GameSession.checkpoint_display_name("test.shrine.toast"), "Thornwick Shrine", "a loaded shrine's record name")
	assert_eq(GameSession.checkpoint_display_name("test.cp.toast_stone"), "Test stone", "a loaded waystone's name")
	assert_eq(GameSession.checkpoint_display_name(""), "", "no checkpoint, no name")
	Events.checkpoint_saved.emit(Sim.tick, "test.cp.toast_stone", true, "")
	assert_eq(toast.call("visible_text"), "Checkpoint saved: Test stone", "the toast uses the node's name")
	toast.free()


# --------------------------------------------------------------------------- skip the prologue

func test_skip_is_offered_only_for_a_finished_prologue_while_the_world_exists() -> void:
	_write_save(_fixture("v1_force_complete"))
	assert_true(TitleScreen.save_finished_prologue(SaveSlots.read().data), "the completed save finished the prologue")
	TestFixtures.record_override(GameSession.WORLD_LEVEL_ID, {"scene": NO_WORLD_SCENE})
	var title := _title()
	assert_false(GameSession.world_available(), "no world in this build (simulated)")
	assert_false(title.skip_available(), "so no skip")
	title.button("New Game").pressed.emit()
	assert_false(title.state().skip_choice, "New Game only asks to replace the save")
	assert_true(title.button("New Game").text.contains("replace"), "as before")
	# The title re-reads the slot whenever it refreshes (on_open).
	_stub_world()
	_write_save(_fixture("v1_pre_crown"))
	title.refresh()
	assert_false(TitleScreen.save_finished_prologue(SaveSlots.read().data), "a save before the crown")
	assert_false(title.skip_available(), "no skip for an unfinished prologue")
	title.button("New Game").pressed.emit()
	assert_false(title.state().skip_choice, "New Game asks to replace it")
	_write_save(_fixture("v1_force_complete"))
	title.refresh()
	assert_true(title.skip_available(), "a finished prologue with the world: skip is offered")
	assert_false(title.state().skip_choice, "once New Game is pressed")
	assert_eq(title.state().note, "", "no note yet")
	GameSession.scene_reloads.clear()
	title.button("New Game").pressed.emit()
	assert_true(title.state().skip_choice, "the two choices appear")
	assert_eq(title.state().note, TitleScreen.SKIP_NOTE, "with the note")
	assert_eq(GameSession.scene_reloads.size(), 0, "nothing started yet")
	assert_true(title.button(TitleScreen.PLAY_PROLOGUE).visible and title.button(TitleScreen.SKIP_PROLOGUE).visible,
		"Play the prologue and Skip to the Old Kingdom")
	var flat: Array = []
	for r: Array in title.focus_rows():
		flat.append_array(r)
	assert_true(flat.has(title.button(TitleScreen.PLAY_PROLOGUE)) and flat.has(title.button(TitleScreen.SKIP_PROLOGUE)),
		"both in the pad's focus column")
	title.button(TitleScreen.SKIP_PROLOGUE).pressed.emit()
	assert_true(bool(GameSession.last_mode_result.get("ok", false)), "Skip starts: %s" % GameSession.last_mode_result)
	assert_eq(GameSession.scene_reloads.back(), "new_game", "a New Game reload")
	assert_eq(GameSession.level_id, GameSession.WORLD_LEVEL_ID, "in the world")
	assert_eq(int(GameSession.character.level), int(GameData.get_record("progression.default").world_start.level),
		"with the world_start character")
	assert_true(QuestConditions.truthy(WorldState.get_flag("slice.completed")), "and its flags")
	_write_save(_fixture("v1_help_cache_complete"))
	title.refresh()
	assert_false(title.state().skip_choice, "a refresh hides the choice again")
	title.button("New Game").pressed.emit()
	title.button(TitleScreen.PLAY_PROLOGUE).pressed.emit()
	assert_true(bool(GameSession.last_mode_result.get("ok", false)), "Play the prologue starts")
	assert_eq(GameSession.level_id, GameSession.VALLEY_LEVEL_ID, "a New Game in the Valley")
	assert_eq(int(GameSession.character.level), 1, "from level 1")
