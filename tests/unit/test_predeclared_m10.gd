extends TestSuite
## The M10 pre-declarations (P42; plan M10 §1.5, §2.11): every registry entry M10 needs is spelled as
## §1.5 lists it and its file exists once its owner has merged (an owner has merged when its system doc,
## docs/systems/<owner>.md, is in the tree; until then a missing file is skipped silently, which the
## registries' own loaders do too); the signal appearance_changed is declared in an "appearance (M10)"
## block above the package anchors, with its arguments and its emitter named; the M10 anchors are in
## their files; the command-line options and the two tutorial prompts of §2.11 exist. (test_anchors
## checks the anchors' rows and creators through tests/support/anchors_expected.gd.)

const EVENTS_PATH := "res://scripts/core/events.gd"
const CREATOR := "res://ui/screens/creator/creator_screen.gd"
const APPEARANCE_TAB := "res://ui/screens/shrine/appearance_tab.gd"
const PLAYER_APPEARANCE := "res://scripts/actors/player/player_appearance.gd"
const SKINNED_RIG := "res://scripts/presentation/skinned_rig.gd"
const GIANT_MODEL_BUILDER := "res://tools/builders/giant_model.gd"
const PLAYER_BUILDER := "res://tools/builders/player.gd"
const SCHEMAS := {"appearance_set": "res://scripts/core/schemas/appearance_set_schema.gd",
	"appearance_preset": "res://scripts/core/schemas/appearance_preset_schema.gd"}
## file -> the M10 anchors in it (plan §1.5's table).
const ANCHORS := {
	"res://scripts/core/events.gd": ["P41", "P43", "P44", "P45", "P46", "P47"],
	"res://scripts/core/game_data.gd": ["P42", "P46"],
	"res://scripts/progression/character_state.gd": ["P46"],
}


## True once `owner`'s package has merged (its system doc is in the tree).
func _merged(owner: String) -> bool:
	return FileAccess.file_exists("res://docs/systems/%s.md" % owner)


## The registry path `path` of `owner`: spelled as the plan has it (the caller compares), and existing
## once the owner has merged.
func _exists_once_merged(path: String, owner: String, label: String) -> void:
	if _merged(owner):
		assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"%s: %s exists now that %s has merged" % [label, path, owner])


# --------------------------------------------------------------------------- the signal

func test_appearance_changed_is_declared_with_its_arguments_and_emitter() -> void:
	assert_true(Events.has_signal("appearance_changed"), "Events.appearance_changed is declared")
	var args: Array = []
	for s: Dictionary in Events.get_signal_list():
		if str(s.name) == "appearance_changed":
			for a: Dictionary in s.args:
				args.append([str(a.name), int(a.type)])
	assert_eq(args, [["tick", TYPE_INT], ["entity_id", TYPE_STRING]],
		"appearance_changed(tick: int, entity_id: String) as plan §2.11 declares it")
	var text := FileAccess.get_file_as_string(EVENTS_PATH)
	var lines := text.split("\n")
	var block := -1
	var at := -1
	var first_anchor := -1
	for i in lines.size():
		var line := lines[i].strip_edges()
		if block < 0 and line.contains("appearance (M10)"):
			block = i
		if at < 0 and line.begins_with("signal appearance_changed("):
			at = i
		if first_anchor < 0 and line.begins_with("## @anchor "):
			first_anchor = i
	assert_true(block >= 0, "events.gd has the \"appearance (M10)\" block")
	assert_true(at > block, "appearance_changed sits in that block")
	assert_true(first_anchor > at, "the block is above the package anchors")
	var comment := ""
	var j := at - 1
	while j >= 0 and lines[j].strip_edges().begins_with("##"):
		comment = lines[j] + "\n" + comment
		j -= 1
	assert_true(comment.contains("Emitter:") and comment.contains("PlayerAppearance"),
		"the comment above it names its emitter, PlayerAppearance: %s" % comment)
	assert_true(comment.contains("GameSession"), "and its listener, GameSession (the F15 checkpoint)")


func test_game_session_listens_to_appearance_changed() -> void:
	var heard := false
	for c: Dictionary in Events.get_signal_connection_list("appearance_changed"):
		if (c.callable as Callable).get_object() == GameSession:
			heard = true
	assert_true(heard, "GameSession re-takes a shrine's checkpoint on appearance_changed (F15's list)")


# --------------------------------------------------------------------------- the anchors

func test_every_m10_anchor_is_in_its_file() -> void:
	for path: String in ANCHORS:
		var text := FileAccess.get_file_as_string(path)
		for pkg: String in ANCHORS[path]:
			var n := text.count("## @anchor %s\n" % pkg)
			assert_eq(n, 1, "%s has the anchor %s once" % [path.get_file(), pkg])
	# The M10 anchors of events.gd follow its last M7-M9 anchor (append only) in package order.
	var text := FileAccess.get_file_as_string(EVENTS_PATH)
	var last := -1
	for pkg: String in ANCHORS[EVENTS_PATH]:
		var i := text.find("## @anchor %s\n" % pkg)
		assert_true(i > last, "events.gd: anchor %s comes after the one before it" % pkg)
		last = i
	var gd := FileAccess.get_file_as_string("res://scripts/core/game_data.gd")
	var p42 := gd.find("## @anchor P42\n")
	assert_true(p42 > 0 and gd.find("Appearance.data_errors(records, record_paths)", p42) > p42,
		"game_data.gd's anchor P42 runs Appearance.data_errors")
	assert_true(gd.find("## @anchor P46\n") > p42, "and the anchor P46 follows it")


func test_the_anchor_rows_name_p42_their_creator() -> void:
	var rows: Array = AnchorsExpected.TABLE
	var found := {}
	for row: Array in rows:
		if ANCHORS.has(str(row[0])) and str(row[1]) == "P42":
			found[str(row[0])] = row[2]
	for path: String in ANCHORS:
		assert_true(found.has(path), "anchors_expected lists %s with P42 as the creator" % path.get_file())
		var listed: Array = []
		for p: Variant in found.get(path, []):
			listed.append(str(p))
		assert_eq(listed, ANCHORS[path], "%s's M10 anchors" % path.get_file())
	assert_eq(str(AnchorsExpected.CREATORS.get("P42", "")), "res://scripts/progression/appearance.gd",
		"P42's own creator file (the package's existence marker)")


# --------------------------------------------------------------------------- the registries

func test_screen_and_shrine_tab_registries() -> void:
	assert_eq(str(ScreenStack.SCREENS.get("creator", "")), CREATOR, "ScreenStack.SCREENS[\"creator\"] (P44)")
	_exists_once_merged(CREATOR, "P44", "the creator screen")
	var tabs: Array = ShrineScreen.TABS
	assert_true(not tabs.is_empty(), "the shrine has tabs")
	var last: Array = tabs.back() if not tabs.is_empty() else []
	assert_eq(last, ["Appearance", APPEARANCE_TAB], "ShrineScreen.TABS ends with the Appearance tab (P44)")
	_exists_once_merged(APPEARANCE_TAB, "P44", "the Appearance tab")
	var names: Array = []
	for t: Array in tabs:
		names.append(str(t[0]))
	assert_eq(names.count("Appearance"), 1, "one Appearance tab")
	if not ResourceLoader.exists(CREATOR):
		var stack := ScreenStack.new()
		add_child(stack)
		assert_true(stack.open("creator") == null, "the creator is skipped silently while its script is missing")
		assert_false(stack.any_open(), "nothing opened")
		stack.free()


func test_component_schema_and_reset_registries() -> void:
	var entry: Array = []
	for c: Array in GiantPlayer.COMPONENTS:
		if str(c[0]) == "appearance":
			entry = c
	assert_eq(entry, ["appearance", PLAYER_APPEARANCE], "GiantPlayer.COMPONENTS has appearance (P42)")
	assert_true(ResourceLoader.exists(PLAYER_APPEARANCE), "PlayerAppearance exists (P42 is this package)")
	var names: Array = []
	for p: Dictionary in (load("res://scripts/actors/giant_player.gd") as GDScript).get_script_property_list():
		names.append(str(p.name))
	assert_true(names.has("appearance"), "GiantPlayer has the appearance field")
	for t: String in SCHEMAS:
		assert_eq(str(DataValidator.SCHEMA_PATHS.get(t, "")), SCHEMAS[t], "SCHEMA_PATHS[%s]" % t)
		assert_true(DataValidator.SCHEMAS.has(t), "the %s module is loaded" % t)
		assert_true(DataValidator.RECORD_TYPES.has(t), "%s records can be validated" % t)
	var hook := ["script", SKINNED_RIG, "reset_for_tests"]
	var at := -1
	for i in ResetHooks.AFTER_EACH.size():
		var e: Array = ResetHooks.AFTER_EACH[i]
		if e.slice(0, 3) == hook:
			at = i
	assert_true(at >= 0, "ResetHooks.AFTER_EACH resets the skinned rig after every test (P43)")
	assert_true(at < ResetHooks.AFTER_EACH.size() - 1, "and the world index cache stays the last entry")
	_exists_once_merged(SKINNED_RIG, "P43", "the skinned rig")


func test_the_giant_model_builder_comes_before_the_player_builder_once_p41_merged() -> void:
	var b: Array = (load("res://tools/build_scenes.gd") as GDScript).get_script_constant_map().get("BUILDERS", [])
	var model := b.find(GIANT_MODEL_BUILDER)
	var player := b.find(PLAYER_BUILDER)
	assert_true(player >= 0, "the player builder is registered")
	if model >= 0 or _merged("P41"):
		assert_true(model >= 0 and model < player, "BUILDERS has giant_model.gd before player.gd (P41)")
		_exists_once_merged(GIANT_MODEL_BUILDER, "P41", "the giant model's builder")


# --------------------------------------------------------------------------- command line, prompts, flags

func test_the_command_line_options() -> void:
	var o := GameSession.parse_args(PackedStringArray(["--mode=world", "--appearance=storm_herald", "--creator"]))
	assert_eq(str(o.appearance), "appearance_preset.storm_herald", "--appearance=<key> names the preset")
	assert_true(bool(o.creator), "--creator is read")
	o = GameSession.parse_args(PackedStringArray(["--appearance=appearance_preset.wanderer"]))
	assert_eq(str(o.appearance), "appearance_preset.wanderer", "--appearance=<full id> as it is")
	o = GameSession.parse_args(PackedStringArray([]))
	assert_eq(str(o.appearance), "", "no --appearance=")
	assert_false(bool(o.creator), "no --creator")
	assert_eq(GiantLook.TIERS, ["auto", "web", "hi"], "GiantLook's tiers (--giant-tier=web | hi forces one)")


func test_the_two_tutorial_prompts_and_the_flags() -> void:
	var shrines := GameData.get_record("tutorial.appearance_shrines")
	assert_eq(str(shrines.get("text", "")), "Your giant can now be shaped at any shrine: the Appearance tab.",
		"tutorial.appearance_shrines says what §2.11 says")
	assert_true(bool(shrines.get("once", false)), "shown once")
	assert_true((shrines.get("requires_flags", []) as Array).has(GameSession.LEGACY_LOOK_FLAG),
		"only after loading a save that had no look (appearance.legacy_save)")
	assert_eq(str((shrines.get("trigger", {}) as Dictionary).get("event", "")), "shrine_activated", "at a shrine")
	var mark := GameData.get_record("tutorial.appearance_mark")
	assert_eq(str(mark.get("text", "")),
		"Your line's mark now shows on your giant. You can hide it at a shrine, in Appearance.",
		"tutorial.appearance_mark says what §2.11 says")
	assert_true(bool(mark.get("once", false)), "shown once")
	assert_eq(str((mark.get("trigger", {}) as Dictionary).get("flag", "")), PlayerAppearance.MARK_SHOWN_FLAG,
		"brought up by the flag PlayerAppearance sets when a line's mark first shows")
	assert_eq(GameSession.LEGACY_LOOK_FLAG, "appearance.legacy_save", "the legacy flag's name (§2.11)")
	assert_eq(PlayerAppearance.LEGACY_FLAG, GameSession.LEGACY_LOOK_FLAG, "one name for it")
