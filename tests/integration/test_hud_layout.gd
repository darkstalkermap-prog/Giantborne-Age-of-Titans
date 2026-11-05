extends IntegrationSuite
## P16 (plan §3.18, FOLLOWUPS wave 6): the HUD layout. At 1280 x 720 and 1920 x 1080 (and the sizes
## between and above) every fixed HUD region - the HUD's own panels and every widget's
## (Hud.layout_regions) - lies on the screen and no two overlap, except where designed: the target
## frame hides while the boss bar shows the locked boss, and sits below the bar
## (target_frame_under_boss_bar) while the bar shows another boss. The boss bar and the quest
## tracker never touch (they overlapped by 36 px at 1280 px). The full-screen overlays (crosshair,
## lock marker, threat arrows, objective marker, the death and help overlays, the F3 panel) draw at
## points or cover the screen on purpose and are not regions.

const KING := "res://scenes/enemies/ogre_king.tscn"
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1366, 768), Vector2(1600, 900),
	Vector2(2560, 1440)]
const REGIONS := ["resources", "hotbar", "loot", "capture_hint", "messages", "target_frame",
	"target_frame_under_boss_bar", "interact_prompt", "status_row", "checkpoint_toast", "xp_bar",
	"ability_notice", "boss_bar", "quest_tracker", "tutorial_prompt"]
## Pairs allowed to overlap (sorted names): the frame's two heights, and the frame at the top with
## the bar (never both on screen: the frame moves down or hides while the bar shows).
const DESIGNED := [["boss_bar", "target_frame"], ["target_frame", "target_frame_under_boss_bar"]]


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


static func _designed(a: String, b: String) -> bool:
	var pair := [a, b]
	pair.sort()
	return DESIGNED.has(pair)


static func _size_text(view: Vector2) -> String:
	return "%dx%d" % [int(view.x), int(view.y)]


func test_no_two_regions_overlap_at_any_supported_size() -> void:
	var hud := _hud()
	await get_tree().process_frame
	for view: Vector2 in SIZES:
		var regions := hud.layout_regions(view)
		for region: String in REGIONS:
			assert_true(regions.has(region), "%s is a HUD region" % region)
		var names: Array = regions.keys()
		names.sort()
		var screen := Rect2(Vector2.ZERO, view)
		for n: String in names:
			assert_true(screen.encloses(regions[n]), "%s lies on the %s screen: %s" % [n, _size_text(view), regions[n]])
		var overlaps := PackedStringArray()
		for i in names.size():
			for j in range(i + 1, names.size()):
				if _designed(names[i], names[j]):
					continue
				if (regions[names[i]] as Rect2).intersects(regions[names[j]]):
					overlaps.append("%s %s / %s %s" % [names[i], regions[names[i]], names[j], regions[names[j]]])
		assert_eq(overlaps, PackedStringArray(), "no regions overlap at %s" % _size_text(view))
		var bar: Rect2 = regions.boss_bar
		assert_false(bar.intersects(regions.quest_tracker, true),
			"the boss bar and the quest tracker do not touch at %s" % _size_text(view))
		assert_false(bar.intersects(regions.target_frame_under_boss_bar, true),
			"the target frame below the boss bar clears it at %s" % _size_text(view))
	var r := hud.layout_regions(Vector2(1280, 720))
	var gap: float = (r.quest_tracker as Rect2).position.x - (r.boss_bar as Rect2).end.x
	assert_true(gap >= 8.0, "at 1280 px the boss bar ends %.0f px before the tracker (it overlapped by 36)" % gap)


## The regions are where the panels are drawn: at the test screen's real size each region control's
## rect equals its anchored rect (no panel grew past its region).
func test_the_regions_are_where_the_panels_are_drawn() -> void:
	var hud := _hud()
	await get_tree().process_frame
	await get_tree().process_frame
	var view := hud.size
	assert_true(view.x > 0.0 and view.y > 0.0, "the HUD fills the screen (%s)" % view)
	var controls := hud.layout_controls()
	for region: String in ["resources", "hotbar", "loot", "capture_hint", "messages", "target_frame",
			"interact_prompt", "status_row", "checkpoint_toast", "xp_bar", "ability_notice", "boss_bar",
			"quest_tracker", "tutorial_prompt"]:
		assert_true(controls.has(region), "%s has a control" % region)
		if not controls.has(region):
			continue
		var c: Control = controls[region]
		var drawn := Rect2(c.get_global_rect().position - hud.get_global_rect().position, c.size)
		var want := HudWidget.anchored_rect(c, view)
		assert_true(drawn.position.distance_to(want.position) <= 1.0 and drawn.size.distance_to(want.size) <= 1.0,
			"%s is drawn at its region: %s (region %s)" % [region, drawn, want])


## While an engaged boss's bar shows, the frame of another locked target sits below the bar; it
## goes back up when the boss is defeated.
func test_the_target_frame_moves_below_the_boss_bar() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	TestSpawn.enemy(world, KING, Vector3(30, 0.05, -40), "test.king_layout", false, 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), 0.0, "test.soldier_layout")
	await step_ticks(3)
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.soldier_layout", "locked on the soldier")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(hud.target_frame_visible(), "its target frame shows")
	assert_near(hud.target_frame_rect().position.y, Hud.TARGET_FRAME_TOP, 0.5, "at the top")
	Events.boss_engaged.emit(Sim.tick, "test.king_layout")
	for i in 3:
		await get_tree().process_frame
	assert_true(hud.boss_bar_visible(), "the engaged boss shows its bar")
	assert_true(hud.target_frame_visible(), "the soldier keeps its frame")
	assert_near(hud.target_frame_rect().position.y, Hud.TARGET_FRAME_TOP_UNDER_BOSS, 0.5, "below the bar")
	var bar: Rect2 = hud.layout_regions(hud.size).boss_bar
	assert_false(hud.target_frame_rect().intersects(bar, true), "clear of it")
	Events.boss_defeated.emit(Sim.tick, "test.king_layout")
	for i in 3:
		await get_tree().process_frame
	assert_false(hud.boss_bar_visible(), "defeated: the bar hides")
	assert_near(hud.target_frame_rect().position.y, Hud.TARGET_FRAME_TOP, 0.5, "and the frame goes back up")
