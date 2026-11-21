extends TestSuite
## The character creator (P44; plan M10 §2.10, §3.4): from the title, New Game opens the creator and Begin
## starts the game with its record in the same call stack as the press (one mode-change request); with a save
## the confirm comes first; the launcher's creator_start opens it at once; Back with no change leaves the title as it was and the save
## file's bytes unchanged, Back after a change asks "Discard your changes?" (Keep editing keeps the look,
## Discard leaves); Undo steps back through a swatch, Randomize, a preset and Reset; Y randomizes only the
## open category and "Randomize all" everything but the outfit; Randomize leaves Sim.rng untouched; locked
## options give their reason; a design under the outfit says "Hidden by your clothing".
##
## Headless and cheap: no level is loaded (GameSession logs its scene reloads in tests); the creator's preview
## instances the real giant_model.tscn in its own world. Elsewhere: the pad and keyboard walks through every
## category and row (tests/slow/test_creator_controls.gd: a default-tier cost the plan's cap cannot carry), the
## prologue's skip through the creator into the world and the confirm before it
## (test_title_checkpoint_names, test_session_flow: every New Game path through the creator and Begin).

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const STAND_IN := "res://scenes/test/flow_test_level.tscn"

var layer: CanvasLayer
var stack: ScreenStack
var requests: Array = []   ## [mode, options] of Events.mode_change_requested


func before_each() -> void:
	InputBindings.reset_device()
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	requests.clear()
	Events.mode_change_requested.connect(_on_request)
	await get_tree().process_frame


func after_each() -> void:
	if Events.mode_change_requested.is_connected(_on_request):
		Events.mode_change_requested.disconnect(_on_request)
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(layer):
		layer.queue_free()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	SaveSlots.delete_slot(true)
	await get_tree().process_frame


func _on_request(mode_name: String, options: Dictionary) -> void:
	requests.append([mode_name, options.duplicate(true)])


func _title() -> TitleScreen:
	GameSession.mode = GameSession.Mode.TITLE
	var t := stack.open("title") as TitleScreen
	assert_true(t != null, "the title opens")
	return t


func _creator() -> CreatorScreen:
	return stack.top() as CreatorScreen


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _write_save(doc: Dictionary) -> void:
	GameSession.persist = true
	assert_true(SaveSlots.write(doc).ok, "a save is written")


func _fixture(fixture_name: String) -> Dictionary:
	return SaveSlots.migrate(JsonIO.read_file(FIXTURE_DIR + fixture_name + ".json").data)


# --------------------------------------------------------------------------- New Game

func test_new_game_opens_the_creator_and_begin_starts_in_the_same_call_stack() -> void:
	var title := _title()
	assert_true(title.state().new_game, "New Game is enabled at once headless (no warm-up without a display)")
	assert_eq(title.warmup_viewport(), null, "and there is no warm-up viewport")
	title.button("New Game").pressed.emit()
	var c := _creator()
	assert_true(c != null and c.screen_name == "creator", "New Game opens the creator over the title")
	if c == null:
		return
	assert_eq(requests.size(), 0, "nothing started yet")
	assert_eq(c.context, "new_game", "for a New Game")
	assert_eq(c.begin_button.text, CreatorScreen.BEGIN_VALLEY, "Begin your journey (the prologue)")
	assert_true(OptionRows.same(c.current_record(), Appearance.default_record()), "it starts on the default look")
	assert_true(c.first_focus() != c.begin_button, "the focus never starts on Begin")
	c.show_category("Hair")
	assert_true(c.pick("hair.color", "haircolor.auburn"), "a new hair colour")
	var record := c.current_record()
	assert_eq(str(record.hair.color), "haircolor.auburn", "the record has it")
	assert_eq(str(record.preset), "", "an edited look is custom")
	c.begin_button.pressed.emit()
	# no await: the request was made inside the press (browsers grant the pointer lock only in the click)
	assert_eq(requests.size(), 1, "one mode-change request, in the same call stack as the press")
	if requests.size() == 1:
		assert_eq(str(requests[0][0]), "valley", "for the Valley")
		assert_true(bool((requests[0][1] as Dictionary).get("new_game", false)), "a New Game")
		assert_true(OptionRows.same((requests[0][1] as Dictionary).get("appearance", {}), record), "carrying the record")
	assert_false(stack.is_open("creator"), "the creator closed")
	assert_eq(GameSession.scene_reloads, ["new_game"] as Array[String], "one reload into the new game")
	assert_true(OptionRows.same(GameSession.character.get("appearance", {}), record), "the new character has the look")


func test_with_a_save_the_confirm_comes_first_and_back_leaves_it_untouched() -> void:
	_write_save(_fixture("v1_pre_crown"))
	var path := SaveSlots.path()
	var before := FileAccess.get_file_as_bytes(path)
	var title := _title()
	assert_true(title.state()["continue"], "a save exists")
	title.button("New Game").pressed.emit()
	assert_false(stack.is_open("creator"), "the first press only asks")
	assert_true(title.button("New Game").text.contains("replace"), "the confirm: %s" % title.button("New Game").text)
	title.button("New Game").pressed.emit()
	var c := _creator()
	assert_true(c != null and c.screen_name == "creator", "the second press opens the creator")
	if c == null:
		return
	c.back_button.pressed.emit()
	assert_false(stack.is_open("creator"), "Back with no change closes at once")
	assert_eq(stack.top(), title, "back on the title")
	assert_true(title.button("New Game").text.contains("replace"), "the title as it was (the confirm kept)")
	assert_eq(requests.size(), 0, "nothing started")
	assert_eq(FileAccess.get_file_as_bytes(path), before, "the save file's bytes are unchanged")


func test_creator_start_opens_the_creator_at_once_for_a_world_start() -> void:
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=world", "--creator", "--no-user-settings"])))
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "--creator shows the title")
	assert_false(GameSession.creator_start.is_empty(), "with creator_start")
	var title := stack.open("title") as TitleScreen
	await get_tree().process_frame
	var c := _creator()
	assert_true(c != null and c.screen_name == "creator", "the title opened the creator by itself")
	assert_true(GameSession.creator_start.is_empty(), "and cleared creator_start")
	if c == null:
		return
	assert_eq(c.begin_button.text, CreatorScreen.BEGIN_WORLD, "for a world start")
	c.back_button.pressed.emit()
	assert_eq(stack.top(), title, "Back leaves the player on the title")
	assert_eq(requests.size(), 0, "nothing started")


## M10 gate, LA-6: with a display the creator of --mode=world --creator opens while the warm-up still holds
## New Game and Continue, so the title's focus was on Sandbox when the creator opened and Back gave it back
## to Sandbox: a pad or keyboard player who backed out and pressed A started the sandbox.
func test_back_from_creator_start_during_the_warmup_focuses_the_titles_first_entry() -> void:
	TitleScreen.force_warmup = true
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=world", "--creator", "--no-user-settings"])))
	var title := stack.open("title") as TitleScreen
	assert_true(title.warming(), "the warm-up holds New Game")
	assert_eq(_focus(), title.button("Sandbox"), "so the title's focus starts on Sandbox")
	await get_tree().process_frame
	var c := _creator()
	assert_true(c != null, "the creator opened over the warming title")
	if c == null:
		TitleScreen.force_warmup = false
		return
	for i in 12:
		if not title.warming():
			break
		await get_tree().process_frame
	await get_tree().process_frame   # the title enables its buttons in its own _process, under the creator
	await get_tree().process_frame
	assert_false(title.warming(), "the warm-up is done under the creator")
	assert_false(title.button("New Game").disabled, "and New Game is enabled while the creator is still open")
	c.back_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(stack.top(), title, "Back leaves the player on the title")
	assert_false(title.button("New Game").disabled, "New Game is enabled")
	assert_eq(_focus(), title.first_focus(), "the focus is on the title's first entry")
	assert_eq(_focus(), title.button("New Game"), "New Game, not Sandbox")
	assert_eq(requests.size(), 0, "nothing started")
	TitleScreen.force_warmup = false


# --------------------------------------------------------------------------- safety: the question and Undo

## The creator alone (New Game context), on the stack; its closed result is collected.
func _open_creator(extra: Dictionary = {}) -> CreatorScreen:
	var a := {"context": "new_game", "start": {"mode": "valley", "options": {"new_game": true}}}
	a.merge(extra, true)
	var c := stack.open("creator", a) as CreatorScreen
	assert_true(c != null, "the creator opens")
	if c != null:
		c.closed.connect(func(r: Dictionary) -> void: results.append(r))
	return c


var results: Array = []


func test_back_after_a_change_asks_and_undo_steps_back_through_every_kind_of_change() -> void:
	results.clear()
	var c := _open_creator()
	c.show_category("Skin")
	var base := c.current_record()
	assert_true(c.pick("skin", "skin.tan"), "a swatch: tan skin")
	assert_true(c.is_changed(), "the look changed")
	c.back_button.pressed.emit()
	assert_true(c.question_open(), "Back after a change asks: %s" % CreatorScreen.QUESTION)
	assert_eq(_focus(), c.keep_editing_button, "the focus starts on Keep editing")
	assert_eq(c.focus_rows(), [[c.keep_editing_button, c.discard_button]], "only the question's two buttons")
	c.keep_editing_button.pressed.emit()
	assert_false(c.question_open(), "Keep editing closes the question")
	assert_true(stack.has_screen(c), "the creator stays open")
	assert_eq(str(c.current_record().skin), "skin.tan", "and keeps the look")
	# Undo: a swatch, Randomize, a preset and Reset, one step each.
	var after_swatch := c.current_record()
	c.show_category("Hair")
	assert_true(c.randomize_category(), "Randomize changes the hair")
	var after_random := c.current_record()
	c.show_category("Presets")
	assert_true(c.pick("preset.appearance_preset.storm_herald", true), "a preset: the Storm Herald")
	assert_eq(str(c.current_record().preset), "appearance_preset.storm_herald", "the preset is on")
	assert_true(c.reset(), "Reset (to the default preset at New Game)")
	assert_true(OptionRows.same(c.current_record(), Appearance.default_record()), "Reset gives the default look")
	assert_true(c.undo(), "Undo Reset")
	assert_eq(str(c.current_record().preset), "appearance_preset.storm_herald", "back to the preset")
	assert_true(c.undo(), "Undo the preset")
	assert_true(OptionRows.same(c.current_record(), after_random), "back to the randomized hair")
	assert_true(c.undo(), "Undo Randomize")
	assert_true(OptionRows.same(c.current_record(), after_swatch), "back to the tan skin")
	assert_true(c.undo(), "Undo the swatch")
	assert_true(OptionRows.same(c.current_record(), base), "back to the look the screen opened with")
	assert_false(c.undo(), "nothing more to undo")
	assert_eq(c.status_text(), "Nothing to undo.", "and it says so")
	assert_true(UiNav.focus_owner(c) != null and c.is_ancestor_of(UiNav.focus_owner(c)), "the focus is still on the creator")
	assert_true(CreatorScreen.HISTORY_MAX >= 32, "Undo keeps at least 32 changes (%d)" % CreatorScreen.HISTORY_MAX)
	for i in CreatorScreen.HISTORY_MAX:
		c.history.append(c.current_record())
	c.set_record(OptionRows.with_value(c.current_record(), "hair.grey", 0.9))
	assert_eq(c.history.size(), CreatorScreen.HISTORY_MAX, "a full history drops its oldest change")
	c.cancel()
	assert_true(c.question_open(), "Esc / B with changes asks too")
	c.discard_button.pressed.emit()
	assert_false(stack.has_screen(c), "Discard closes the creator")
	assert_eq(results, [{"cancelled": true}], "without a look")


func test_randomize_one_category_all_but_the_outfit_and_never_sim_rng() -> void:
	results.clear()
	var c := _open_creator()
	var sim_state := Sim.rng.state
	c.show_category("Hair")
	var before := c.current_record()
	for i in 3:
		c.randomize_category()
	var r := c.current_record()
	for key: String in ["skin", "eyes", "tattoos", "paint", "scars", "outfit", "beard", "mark"]:
		assert_true(OptionRows.same(r[key], before[key]), "Y on Hair leaves %s as it was" % key)
	assert_false(OptionRows.same(r.hair, before.hair), "and changes the hair")
	var outfit: Dictionary = r.outfit.duplicate(true)
	var changed_any := false
	for i in 4:
		c.randomize_all()
		changed_any = changed_any or not OptionRows.same(c.current_record().skin, r.skin) \
			or not OptionRows.same(c.current_record().eyes, r.eyes)
		assert_true(OptionRows.same(c.current_record().outfit, outfit), "Randomize all keeps the outfit (Hair open)")
	assert_true(changed_any, "Randomize all changes the rest")
	c.show_category("Clothing")
	var outfit_changed := false
	for i in 6:
		c.randomize_all()
		outfit_changed = outfit_changed or not OptionRows.same(c.current_record().outfit, outfit)
	assert_true(outfit_changed, "with Clothing open, Randomize all changes the outfit too")
	assert_eq(Sim.rng.state, sim_state, "Randomize never draws from Sim.rng")
	assert_true(c.rng() != Sim.rng, "the creator has its own generator")
	assert_true(Appearance.is_valid(c.current_record(), c.ancestry), "the random look is valid")


func test_random_greys_are_kept_as_their_sliders_keep_them() -> void:
	# a drawn grey of 0.01 was snapped to 0 by its slider when shown, and that snap became a second undo step. P57
	# (plan M11 §1.7 rule 2): 40 seeds here, the 400 in tests/slow/test_giant_look_walks.gd
	random_greys_are_slider_values(self, 40)


## Every random grey of `seeds` seeds in the hair, beard and whole scopes is a value its slider keeps.
static func random_greys_are_slider_values(t: TestSuite, seeds: int) -> void:
	var rng := RandomNumberGenerator.new()
	for s in seeds:
		rng.seed = s
		for scope: String in ["hair", "beard", "all"]:
			var r := OptionRows.random_record(rng, scope, true, "", Appearance.default_record())
			for part: String in ["hair", "beard"]:
				var g := float(r[part].grey)
				if not is_equal_approx(g, OptionRows.snap_slider(g)):
					t.assert_true(false, "seed %d %s: %s grey %f is not a slider value" % [s, scope, part, g])
					return
	t.assert_true(true, "every random grey of %d seeds is a value its slider keeps" % seeds)


# --------------------------------------------------------------------------- reading in play, locks

func test_locked_options_give_their_reason_and_covered_designs_say_hidden() -> void:
	var c := _open_creator()
	c.show_category("Skin")
	var skin := c.row("skin") as OptionRows.SwatchRow
	assert_true(skin != null, "the skin row")
	var ashen: Dictionary = skin.choice("skin.ashen")
	assert_true(bool(ashen.get("locked", false)), "ashen skin is locked before a line is chosen")
	assert_eq(str(ashen.get("reason", "")), Appearance.LOCKED_HINT, "with its reason")
	(skin.buttons["skin.ashen"] as Button).pressed.emit()
	assert_eq(str(c.current_record().skin), "skin.ruddy", "a locked swatch applies nothing")
	assert_true(skin.name_label.text.contains(Appearance.LOCKED_HINT), "the row says why: %s" % skin.name_label.text)
	c.show_category("Eyes")
	var eyes := c.row("eyes") as OptionRows.SwatchRow
	assert_true(bool(eyes.choice("eyes.storm").locked) and bool(eyes.choice("eyes.amber").locked), "the line's eyes are locked")
	c.show_category("Tattoos")
	var mark := c.row("mark")
	assert_eq(mark.note_text(), OptionRows.MARK_NO_LINE, "the mark row says it waits for a line")
	assert_eq(c.row("tattoos.chest").note_text(), "", "the wanderer's chest is bare: no note")
	c.show_category("Clothing")
	assert_true(c.pick("outfit.set", "outfit.warrior"), "the warrior's tunic")
	c.show_category("Tattoos")
	for key: String in ["tattoos.chest", "tattoos.back"]:
		assert_eq(c.row(key).note_text(), OptionRows.HIDDEN_NOTE, "%s: %s" % [key, OptionRows.HIDDEN_NOTE])
	assert_eq(c.row("tattoos.face").note_text(), "", "the face is never covered")
	(c.row("tattoos.chest") as OptionRows.GridRow).button.grab_focus()   # P55: a grid row (was a cycler)
	assert_near(c.preview.fade(), 0.7, 1e-4, "while a hidden row has the focus the covering garments fade")
	assert_eq(c.preview.framing, "chest", "and the preview frames its region")
	(c.row("tattoos.face") as OptionRows.GridRow).button.grab_focus()
	assert_near(c.preview.fade(), 0.0, 1e-4, "the fade goes when the focus leaves")
	assert_eq(c.preview.framing, "face", "the face row frames the face")
	c.show_category("Scars")
	assert_eq(c.row("scar.chest_claws").note_text(), OptionRows.HIDDEN_NOTE, "a scar under the tunic says so")
	assert_eq(c.row("scar.brow").note_text(), "", "the brow scar shows")
