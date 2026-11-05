extends IntegrationSuite
## P16 (plan §3.18, FOLLOWUPS wave 6): the HUD layout. At 1280 x 720 and 1920 x 1080 (and the sizes
## between and above) every fixed HUD region - the HUD's own panels and every widget's
## (Hud.layout_regions) - lies on the screen and no two overlap, except where designed: the target
## frame hides while the boss bar shows the locked boss, and sits below the bar
## (target_frame_under_boss_bar) while the bar shows another boss. The boss bar and the quest
## tracker never touch (they overlapped by 36 px at 1280 px). The full-screen overlays (crosshair,
## lock marker, threat arrows, objective marker, the death and help overlays, the F3 panel) draw at
## points or cover the screen on purpose and are not regions.
## M4 gate: the edge overlays are not regions, but no panel may hide them or lie under them. The
## threat arrows and the objective marker are the last widgets (over every panel, under the death
## and help overlays), and with the tutorial's TIP box, the tracker, the boss bar, the target frame
## and the loot line on screen, an arrow or a clamped marker in any direction, at every supported
## size, keeps clear of every panel drawn (Hud.overlay_keep_out) on its edge rectangle: the
## threats 80-120 degrees to the left that the TIP box covered and the ones behind that sat on the
## hotbar, with the giant's real camera, and the live widgets with a real archer's shot from behind
## and an objective behind and to the left.

const KING := "res://scenes/enemies/ogre_king.tscn"
const ARCHER := "res://scenes/enemies/archer.tscn"
const Arrows := preload("res://ui/hud/threat_arrows.gd")
const Marker := preload("res://ui/hud/objective_marker.gd")
const Fx := preload("res://tests/support/quest_fixtures.gd")
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


# --------------------------------------------------------------------------- edge overlays (M4 gate)

static func _inset_of(p: Vector2, view: Vector2) -> float:
	return minf(minf(p.x, view.x - p.x), minf(p.y, view.y - p.y))


## The panels of `keep_out` that the drawing at `p` (its footprint) touches, as text ("" when none).
static func _covered_by(p: Vector2, footprint: Rect2, keep_out: Array[Rect2]) -> String:
	var drawn := Rect2(p + footprint.position, footprint.size)
	var out := PackedStringArray()
	for r: Rect2 in keep_out:
		if drawn.intersects(r):
			out.append(str(r))
	return ", ".join(out)


## The HUD with the tutorial's TIP box (a fixture prompt), the quest tracker (a fixture quest), the
## loot line and the giant locked on a soldier while an engaged king shows the boss bar (the target
## frame below it): every panel near an edge on screen at once.
func _busy_hud(p: GiantPlayer) -> Hud:
	var hud := _hud()
	hud.player = p
	TestSpawn.enemy(world, KING, Vector3(30, 0.05, -40), "test.king_edges", false, 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), 0.0, "test.soldier_edges")
	Fx.install([Fx.prompt("tutorial.test_tip", Fx.flag_cond("test.flag.tip"), Fx.flag_cond("test.flag.never")),
		Fx.quest("quest.test_edges", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Reach the far side of the valley"})])])
	Fx.activate(["quest.test_edges"], ["tutorial.test_tip"], "quest.test_edges")
	WorldState.set_flag("test.flag.tip", true)
	WorldState.add_item("item.wood_scrap", 1, "test")
	await step_ticks(3)
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	Events.boss_engaged.emit(Sim.tick, "test.king_edges")
	for i in 4:
		await get_tree().process_frame
	return hud


## The panels _busy_hud puts on screen, at `view` (from the layout regions, not from the HUD's own
## keep-out list), plus anything else that list holds: what the overlays must clear. Checks that
## the HUD keeps clear of each of them.
func _panels_on_screen(hud: Hud, view: Vector2) -> Array[Rect2]:
	var regions := hud.layout_regions(view)
	var keep := hud.overlay_keep_out(view)
	var out: Array[Rect2] = keep.duplicate()
	for key: String in ["tutorial_prompt", "hotbar", "resources", "quest_tracker", "boss_bar", "loot",
			"target_frame_under_boss_bar"]:
		assert_true(keep.has(regions[key]), "%s is kept clear of at %s" % [key, _size_text(view)])
		if not out.has(regions[key]):
			out.append(regions[key])
	return out


func test_the_edge_overlays_draw_over_every_panel() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var arrows := hud.get_node_or_null("ThreatArrows")
	var marker := hud.get_node_or_null("ObjectiveMarker")
	assert_true(arrows != null and marker != null, "both edge overlays are on the HUD")
	if arrows == null or marker == null:
		return
	var controls := hud.layout_controls()
	for key: String in controls:
		var c := controls[key] as Control
		var top := c
		while top.get_parent() != hud:
			top = top.get_parent() as Control
		assert_true(top.get_index() < marker.get_index(), "%s draws under the objective marker" % key)
	assert_true(marker.get_index() < arrows.get_index(), "the threat arrows draw over the marker")
	for overlay: String in ["_death", "_help"]:
		var o := hud.get(overlay) as Control
		assert_true(o != null and o.get_index() > arrows.get_index(), "%s still covers them" % overlay)
	var paths: Array = HudWidgets.WIDGETS
	assert_eq(paths.slice(-2), ["res://ui/hud/objective_marker.gd", "res://ui/hud/threat_arrows.gd"],
		"the registry lists the overlays last")


## The reviewer's case: a stage-1 giant's real camera, threats and objectives 80-120 degrees to the
## left (and behind) at 20-120 m while the TIP box shows. The old placement put arrows and clamped
## markers under the TIP box and on the hotbar; now each clears every panel drawn, on its edge
## rectangle, pointing the same way. Arrows (their direction is the camera's, whatever the screen)
## at 1280 x 720 and the test screen; markers (projected) on the test screen.
func test_left_and_behind_overlays_clear_the_panels_with_the_real_camera() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := await _busy_hud(p)
	var tip_widget := hud.get_node_or_null("TutorialPrompt")
	assert_true(tip_widget != null and tip_widget.call("shown_id") == "tutorial.test_tip", "the TIP box shows")
	var view := hud.get_viewport_rect().size
	var keep := hud.overlay_keep_out(view)
	var regions := hud.layout_regions(view)
	var panels := _panels_on_screen(hud, view)
	var hd := Vector2(1280, 720)
	var keep_hd := hud.overlay_keep_out(hd)
	var regions_hd := hud.layout_regions(hd)
	var panels_hd := _panels_on_screen(hud, hd)
	var cam := p.camera_rig.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var old_under := {"tip": 0, "hotbar": 0}
	var old_under_hd := {"tip": 0, "hotbar": 0}
	for dist: float in [20.0, 40.0, 80.0, 120.0]:
		for ang: float in [80.0, 100.0, 120.0, 150.0, 180.0, 210.0]:
			var pt := p.global_position + fwd.rotated(Vector3.UP, deg_to_rad(ang)) * dist
			var what := "%d m at %d degrees" % [int(dist), int(ang)]
			var dir: Vector2 = Arrows.screen_direction(cam, pt + Vector3.UP)
			var old_tip: Vector2 = Arrows.edge_point(view, dir, Arrows.EDGE_INSET_PX)
			var tip: Vector2 = Arrows.tip_for(view, dir, keep)
			assert_eq(_covered_by(tip, Arrows.footprint(dir), panels), "", "%s: the arrow clears every panel (%s)" % [what, tip])
			assert_near(_inset_of(tip, view), Arrows.EDGE_INSET_PX, 0.01, "%s: the arrow stays on the edge" % what)
			var old_hd: Vector2 = Arrows.edge_point(hd, dir, Arrows.EDGE_INSET_PX)
			var tip_hd: Vector2 = Arrows.tip_for(hd, dir, keep_hd)
			assert_eq(_covered_by(tip_hd, Arrows.footprint(dir), panels_hd), "",
				"%s at 1280 x 720: the arrow clears every panel (%s)" % [what, tip_hd])
			assert_near(_inset_of(tip_hd, hd), Arrows.EDGE_INSET_PX, 0.01, "%s at 1280 x 720: on the edge" % what)
			if (regions_hd.tutorial_prompt as Rect2).has_point(old_hd):
				old_under_hd.tip += 1
			if (regions_hd.hotbar as Rect2).has_point(old_hd):
				old_under_hd.hotbar += 1
			var old_place: Dictionary = Marker.placement(cam, pt, view, Marker.INSET_PX)
			var place: Dictionary = Marker.placement(cam, pt, view, Marker.INSET_PX, keep)
			assert_false(bool(place.on_screen), "%s: off screen" % what)
			assert_eq(place.direction, old_place.direction, "%s: the marker points the same way" % what)
			assert_eq(_covered_by(place.position, Marker.FOOTPRINT, panels), "",
				"%s: the marker clears every panel (%s)" % [what, place.position])
			assert_near(_inset_of(place.position, view), Marker.INSET_PX, 0.01, "%s: the marker stays on the edge" % what)
			for old: Vector2 in [old_tip, old_place.position]:
				if (regions.tutorial_prompt as Rect2).has_point(old):
					old_under.tip += 1
				if (regions.hotbar as Rect2).has_point(old):
					old_under.hotbar += 1
	assert_true(int(old_under.tip) >= 6 and int(old_under.hotbar) >= 4,
		"the old placement put %d under the TIP box and %d on the hotbar" % [old_under.tip, old_under.hotbar])
	assert_true(int(old_under_hd.tip) >= 6 and int(old_under_hd.hotbar) >= 4,
		"at 1280 x 720 the old arrows: %d under the TIP box, %d on the hotbar" % [old_under_hd.tip, old_under_hd.hotbar])


## Any direction at every supported size, with every edge panel on screen: an arrow and a clamped
## marker always find a clear place on their edge rectangle.
func test_every_direction_clears_the_panels_at_every_size() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := await _busy_hud(p)
	assert_true(hud.boss_bar_visible() and hud.target_frame_visible(), "the boss bar and the target frame show")
	for view: Vector2 in SIZES:
		var keep := hud.overlay_keep_out(view)
		var panels := _panels_on_screen(hud, view)
		var bad := PackedStringArray()
		for i in 72:
			var dir := Vector2.from_angle(TAU * float(i) / 72.0)
			var tip: Vector2 = Arrows.tip_for(view, dir, keep)
			if _covered_by(tip, Arrows.footprint(dir), panels) != "" or absf(_inset_of(tip, view) - Arrows.EDGE_INSET_PX) > 0.01:
				bad.append("arrow %d deg at %s" % [i * 5, tip])
			var spot := HudEdge.clear_of(Marker.edge_point(view, dir, Marker.INSET_PX), view, Marker.INSET_PX,
				Marker.FOOTPRINT, keep)
			if _covered_by(spot, Marker.FOOTPRINT, panels) != "" or absf(_inset_of(spot, view) - Marker.INSET_PX) > 0.01:
				bad.append("marker %d deg at %s" % [i * 5, spot])
		assert_eq(bad, PackedStringArray(), "every direction clears the panels at %s" % _size_text(view))


## The live widgets: a real archer's shot from behind the camera gets its arrow off the hotbar, and
## the objective marker for an objective behind and one to the left keeps clear of the hotbar and
## the TIP box.
func test_the_live_overlays_clear_the_panels() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)   # faces -Z; its camera looks along -Z
	p.entity.combatant.unkillable = true
	var hud := await _busy_hud(p)
	var view := hud.get_viewport_rect().size
	var regions := hud.layout_regions(view)
	var panels := _panels_on_screen(hud, view)
	var archer := TestSpawn.enemy(world, ARCHER, Vector3(1, 0.05, 14), "test.archer_edges", false, 0.0) as ArcherEnemy
	await step_ticks(2)
	archer.brain.target_id = "player"
	archer.controller.request(&"attack", {"action_id": "ability.archer_shot"})
	await step_ticks(1)
	var arrows_widget := hud.get_node("ThreatArrows")
	var arrows: Array = arrows_widget.call("arrows")
	assert_eq(arrows.size(), 1, "the archer behind gets an arrow")
	if arrows.size() == 1:
		var a: Dictionary = arrows[0]
		var old: Vector2 = Arrows.edge_point(view, a.direction, Arrows.EDGE_INSET_PX)
		assert_true((regions.hotbar as Rect2).has_point(old), "its old place was on the hotbar (%s)" % old)
		assert_eq(_covered_by(a.position, Arrows.footprint(a.direction), panels), "",
			"now the arrow clears every panel (%s)" % a.position)
		assert_near(_inset_of(a.position, view), Arrows.EDGE_INSET_PX, 0.01, "24 px inside the screen edge")
		assert_true((a.direction as Vector2).y > 0.5, "pointing down: behind the camera")
	var marker_widget := hud.get_node("ObjectiveMarker")
	var cam := p.camera_rig.camera
	for spot: Array in [["behind", Vector3(4, 2, 60)], ["to the left", Vector3(-80, 2, 14)]]:
		var m := LevelMarker.new()
		m.marker_id = "test.marker.edges_%s" % str(spot[0]).replace(" ", "_")
		m.position = spot[1]
		world.add_child(m)
		Fx.install([Fx.quest("quest.test_edges", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"marker": m.marker_id})])])
		Quests.refresh_positions()
		await step_ticks(2)
		for i in 2:
			await get_tree().process_frame
		var place: Dictionary = marker_widget.call("placement_now")
		assert_false(place.is_empty() or bool(place.on_screen), "the objective %s is clamped" % spot[0])
		if place.is_empty():
			continue
		var old: Dictionary = Marker.placement(cam, m.global_position, view, Marker.INSET_PX)
		var panel: Rect2 = regions.hotbar if spot[0] == "behind" else regions.tutorial_prompt
		assert_true(panel.has_point(old.position), "%s: its old place was under a panel (%s)" % [spot[0], old.position])
		assert_eq(_covered_by(place.position, Marker.FOOTPRINT, panels), "",
			"%s: now the marker clears every panel (%s)" % [spot[0], place.position])
		assert_near(_inset_of(place.position, view), Marker.INSET_PX, 0.01, "%s: 36 px inside the edge" % spot[0])
		m.queue_free()
