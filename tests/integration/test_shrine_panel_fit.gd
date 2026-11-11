extends IntegrationSuite
## M8 gate (F17): the shrine screen in a 1280 x 720 window at the highest level. The panel grew
## downward only, so at level 20 the Talents tab's passives line pushed Leave below the window and
## under the stack's footer hint. Here a level-20 giant at a stage-5 shrine (every tab offered):
##   * every tab's panel, its Leave button and the ancestry screen's frame for each ancestry lie inside
##     the 1280 x 720 window and above the footer hint ("Arrows / Tab: move ...");
##   * the Talents tab with the most passives a level-20 giant can gather (talents chosen for new
##     passive keys, then Wildheart) and every talent's detail shown in turn: the panel, Learn and
##     Leave stay inside and above the hint; the passives line shows at most PASSIVE_LINES lines and its
##     tooltip lists every passive.
## The stack sits in a 1280 x 720 control (the headless window is taller), so the layout is the
## player's. Default tier: one screen, no world.

const SHRINE := "res://scenes/world/shrine.tscn"
const VIEW := Vector2(1280, 720)

var stack: ScreenStack
var frame: Control


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	frame = Control.new()
	frame.size = VIEW
	layer.add_child(frame)
	stack = ScreenStack.new()
	frame.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await super()


## The rect of `c` in the window (the frame's coordinates).
func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - frame.get_global_rect().position, c.size)


## The window above the stack's footer hint.
func _room() -> Rect2:
	var hint := _rect(stack.get_node("NavHint") as Control)
	return Rect2(Vector2.ZERO, Vector2(VIEW.x, hint.position.y))


func _fits(what: String, c: Control, bad: PackedStringArray) -> void:
	var r := _rect(c)
	if not _room().grow(0.5).encloses(r):
		bad.append("%s %s (room %s)" % [what, r, _room()])


## Learns, while points last, the talent that adds the most passive keys not held yet.
static func _learn_most_keys(tab: Node, prog: PlayerProgression) -> void:
	var held := {}
	while true:
		var best := ""
		var best_gain := -1
		for id: Variant in Talents.ids():
			if prog.knows_talent(str(id)) or not bool(prog.can_learn_talent(str(id)).ok):
				continue
			var gain := 0
			for k: Variant in Talents.modifiers_of(str(id)):
				if not held.has(str(k)):
					gain += 1
			if gain > best_gain:
				best = str(id)
				best_gain = gain
		if best == "":
			return
		for k: Variant in Talents.modifiers_of(best):
			held[str(k)] = true
		tab.call("learn", best)


func _open(level: int) -> ShrineScreen:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	var st := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	st["level"] = level
	st["xp"] = Progression.xp_for_level(level)
	st["talent_points"] = Talents.points_at_level(level)
	p.apply_character_state(CharacterState.normalize(st))
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "test.fit_shrine"
	s.shrine_id = "shrine.world_greywood"
	s.position = Vector3(0, 0, -10)
	world.add_child(s)
	await step_ticks(1)
	var screen := stack.open("shrine", {"shrine": s, "player": p}) as ShrineScreen
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func test_every_tab_and_the_ancestry_screen_fit_at_level_20() -> void:
	var screen := await _open(20)
	assert_true(screen != null, "the shrine screen opened")
	if screen == null:
		return
	var panel := screen.get_child(1) as Control
	var titles: Array = screen.tabs.map(func(t: ShrineTab) -> String: return t.tab_title())
	assert_eq(titles, ["Rest", "Grow", "Loadout", "Attributes", "Talents", "Ancestry"], "every tab is offered")
	var bad := PackedStringArray()
	for i in screen.tabs.size():
		screen.show_tab(i)
		await get_tree().process_frame
		await get_tree().process_frame
		_fits("the %s tab's panel" % titles[i], panel, bad)
		_fits("Leave on the %s tab" % titles[i], screen.leave_button(), bad)
	assert_eq(bad, PackedStringArray(), "every tab fits the 1280 x 720 window above the footer hint")
	for id: Variant in Talents.ancestry_ids():
		var anc := stack.open("ancestry", {"player": screen.player, "ancestry": str(id)}) as AncestryScreen
		await get_tree().process_frame
		await get_tree().process_frame
		_fits("the ancestry screen on %s" % id, anc.get_child(1) as Control, bad)
		_fits("Choose on %s" % id, anc.confirm_button, bad)
		anc.cancel()
		await get_tree().process_frame
	assert_eq(bad, PackedStringArray(), "and so does the ancestry screen for each ancestry")


func test_the_talents_tab_with_the_most_passives_fits_at_level_20() -> void:
	var screen := await _open(20)
	if screen == null:
		return
	var prog: PlayerProgression = screen.player.progression
	var tab := screen.tab("Talents")
	screen.show_tab(screen.tabs.find(tab))
	await get_tree().process_frame
	_learn_most_keys(tab, prog)
	assert_true(bool(prog.choose_ancestry("ancestry.wildheart").ok), "Wildheart chosen")
	screen.notify_changed()
	await get_tree().process_frame
	var lines: PackedStringArray = prog.passive_lines()
	assert_true(lines.size() >= 16, "the most passives a level-20 giant gathers (%d)" % lines.size())
	var panel := screen.get_child(1) as Control
	var bad := PackedStringArray()
	for id: Variant in (tab.get("buttons") as Dictionary):
		tab.call("show_detail", str(id))
		await get_tree().process_frame
		await get_tree().process_frame
		_fits("the panel with %s's detail" % id, panel, bad)
		_fits("Learn with %s's detail" % id, tab.get("learn_button") as Control, bad)
		_fits("Leave with %s's detail" % id, screen.leave_button(), bad)
	assert_eq(bad, PackedStringArray(), "the Talents tab fits the window above the footer hint with every talent's detail")
	var passives := tab.get("_passives") as Label
	var most := int((tab.get_script() as Script).get_script_constant_map().get("PASSIVE_LINES", 0))
	assert_true(most > 0 and passives.get_visible_line_count() <= most,
		"the passives line shows at most %d lines (%d)" % [most, passives.get_visible_line_count()])
	for line: String in lines:
		assert_true(passives.tooltip_text.contains(line), "its tooltip lists %s" % line)
	assert_true(str(tab.call("passives_text")).contains(lines[lines.size() - 1]), "and its text holds them all")
