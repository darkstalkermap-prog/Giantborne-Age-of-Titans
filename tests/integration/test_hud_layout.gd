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
## P27: the compass (top centre), the region banner (below the ability notice) and the discovery toast
## (under the checkpoint toast) are regions too, at every size; and the whole HUD keeps HudKit's
## batching rules (FOLLOWUPS: the HUD cost about 117-120 draw calls of every Valley view) - no
## StyleBoxFlat, outline, shadow outline or clipping under it, every panel and text on an absolute
## layer under the modal screens - with every part built; the lock line turns a formation's banner
## mark into a drawn flag.
## M8 screenshot pass (V2): the lock line's label is as wide as its name and distance (it was laid out
## 1 px wide and drew nothing), inside the frame; a name too long for the frame is trimmed at its width.

const KING := "res://scenes/enemies/ogre_king.tscn"
const ARCHER := "res://scenes/enemies/archer.tscn"
const Arrows := preload("res://ui/hud/threat_arrows.gd")
const Marker := preload("res://ui/hud/objective_marker.gd")
const Fx := preload("res://tests/support/quest_fixtures.gd")
const SIZES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1366, 768), Vector2(1600, 900),
	Vector2(2560, 1440)]
const REGIONS := ["resources", "hotbar", "loot", "capture_hint", "messages", "target_frame",
	"target_frame_under_boss_bar", "interact_prompt", "status_row", "checkpoint_toast", "xp_bar",
	"ability_notice", "boss_bar", "quest_tracker", "tutorial_prompt", "compass", "region_banner", "discovery_toast"]
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
			"quest_tracker", "tutorial_prompt", "compass", "region_banner", "discovery_toast"]:
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


## The width (px) `label` needs to show its text untrimmed, in its own font and size.
static func _text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x


## `c`'s rect in `hud`.
static func _rect_in(hud: Hud, c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - hud.get_global_rect().position, c.size)


## M8 screenshot pass (V2): the lock line shows the locked target's name and distance. Its label sits
## in a centred line beside a banner's flag and trims a text too long for the frame with an ellipsis -
## and a trimming label's own minimum width is 1 px, so it was laid out 1 px wide and the line was
## blank outside boss fights (the Valley ogre, a troll, the Aldmere Shield Wall). Now the label is as
## wide as its text, inside the frame and centred in it; a name too long for the frame is trimmed at
## the frame's width and never grows the frame.
func test_the_lock_line_shows_the_name_and_the_distance() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	hud.player = p
	var s := spawn_soldier(Vector3(0, 0.05, -8), 0.0, "test.soldier_line")
	await step_ticks(3)
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.soldier_line", "locked on the soldier")
	for i in 3:
		await get_tree().process_frame
	assert_true(hud.target_frame_visible(), "the target frame shows")
	var label := hud.get("_target_name") as Label
	var text := str(hud.lock_line_now().get("text", ""))
	assert_true(text.begins_with("Soldier") and text.ends_with(" m"), "the line holds the name and the distance (%s)" % text)
	assert_eq(label.text, text, "in the label")
	var need := _text_width(label)
	assert_true(need > 20.0, "the text needs %.0f px" % need)
	assert_true(label.size.x + 0.5 >= need, "the label is wide enough to show it: %.0f px for %.0f px" % [label.size.x, need])
	var frame := hud.target_frame_rect()
	var drawn := _rect_in(hud, label)
	assert_true(frame.encloses(drawn), "inside the frame: %s in %s" % [drawn, frame])
	assert_near(drawn.get_center().x, frame.get_center().x, 2.0, "centred in the frame")
	# A name too long for the frame: trimmed at the frame's width, the frame keeps its rect.
	s.entity.combatant.display_name = "The Banner of the Iron Regiment of Fort Aldmere and its Shield Wall"
	for i in 3:
		await get_tree().process_frame
	assert_true(str(hud.lock_line_now().get("text", "")).begins_with("The Banner of the Iron"), "the long name is the label's text")
	assert_true(_text_width(label) > frame.size.x, "a text wider than the frame (%.0f px)" % _text_width(label))
	assert_true(hud.target_frame_rect().is_equal_approx(frame), "the frame keeps its rect: %s" % hud.target_frame_rect())
	drawn = _rect_in(hud, label)
	assert_true(frame.encloses(drawn), "the trimmed label stays inside the frame: %s in %s" % [drawn, frame])
	assert_true(drawn.size.x > frame.size.x * 0.75, "and uses the frame's width (%.0f px of %.0f)" % [drawn.size.x, frame.size.x])


## P27: the batching rules over the whole HUD with every part built and showing - a giant's hotbar
## and target frame, a message, the help overlay, the compass, a region banner and a discovery toast -
## and the lock line.
func test_the_hud_keeps_the_batching_rules() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), 0.0, "test.soldier_batches")
	var hud := _hud()
	hud.player = p
	await step_ticks(2)
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	hud.show_message("Tracking: The Main Thread", "info")
	hud.toggle_help()
	hud.get_node("RegionBanner").call("show_region", "region.greywood", 1)
	hud.get_node("DiscoveryToast").call("push", "Discovered: Hollowmere  +40 XP", Color.WHITE)
	for i in 2:
		await get_tree().process_frame
	assert_true(hud.help_visible() and hud.target_frame_visible(), "the help overlay and the target frame show")
	assert_true(str(hud.get_node("RegionBanner").call("visible_text")).begins_with("THE GREYWOOD | Recommended stage"),
		"the region banner shows (%s)" % hud.get_node("RegionBanner").call("visible_text"))
	assert_true(bool(hud.get_node("RegionBanner").call("warns")), "below the recommended stage: the warning colour")
	assert_eq(hud.get_node("DiscoveryToast").call("visible_text"), "Discovered: Hollowmere  +40 XP", "the discovery toast shows")
	assert_eq(HudKit.batch_breakers(hud), PackedStringArray(), "nothing under the HUD breaks its batches")
	var probe := Control.new()
	var outlined := Label.new()
	outlined.add_theme_constant_override("outline_size", 2)
	probe.add_child(outlined)
	var flat := PanelContainer.new()
	flat.add_theme_stylebox_override("panel", StyleBoxFlat.new())
	probe.add_child(flat)
	assert_eq(HudKit.batch_breakers(probe).size(), 4,
		"the rules catch an outlined label and a StyleBoxFlat panel, each on the default layer (%s)" % HudKit.batch_breakers(probe))
	probe.free()
	hud.toggle_help()
	assert_eq(hud.lock_line_now(), {"text": hud.lock_line_now().get("text", "?"), "banner": false}, "a soldier's lock line has no flag")
	assert_true(str(hud.lock_line_now().get("text", "")).begins_with("Soldier"), "and names it (%s)" % hud.lock_line_now())
	assert_eq(Hud.lock_line("%s Pike block (6)" % Hud.BANNER_MARK), {"text": "Pike block (6)", "banner": true},
		"a formation's banner mark becomes the drawn flag")
	assert_eq(Hud.lock_line(" Ogre "), {"text": "Ogre", "banner": false}, "any other label is kept")


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


# --------------------------------------------------------------------------- P39f (the M8 screenshot pass)

## P39f ("the HUD stays drawn round an open menu"; "a tutorial tip stays behind the shrine window"; "the last
## message shows through the end screen"): while a screen of the stack is open - a pausing one (the pause menu,
## the journal) or not - the HUD is hidden: no panel, hotbar, tracker, TIP box, loot panel, message or edge
## marker draws round it or under the stack's footer, and the edge overlays keep clear of nothing. When the
## last screen closes the HUD is back as it was, the message (aged nothing meanwhile) included.
func test_the_hud_hides_behind_an_open_screen() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := await _busy_hud(p)
	var stack := ScreenStack.new()
	hud.get_parent().add_child(stack)
	var line := "You take the Stone Throne. The clans of the Stonehold raise their voices."
	hud.show_message(line, "good")
	for i in 2:
		await get_tree().process_frame
	var view := hud.get_viewport_rect().size
	assert_true(hud.is_visible_in_tree() and not hud.menu_hidden(), "the HUD shows while no screen is open")
	assert_false(hud.overlay_keep_out(view).is_empty(), "with its panels on screen")
	for screen_name: String in ["pause", "journal"]:
		var s := stack.open(screen_name)
		assert_true(s != null, "%s opens" % screen_name)
		for i in 2:
			await get_tree().process_frame
		assert_true(get_tree().paused, "%s pauses the game" % screen_name)
		assert_true(hud.menu_hidden() and not hud.is_visible_in_tree(), "%s open: the HUD is hidden" % screen_name)
		for key: String in ["hotbar", "quest_tracker", "tutorial_prompt", "messages", "loot", "resources", "compass"]:
			var c := hud.layout_controls().get(key) as Control
			assert_true(c == null or not c.is_visible_in_tree(), "%s open: the %s is not drawn" % [screen_name, key])
		assert_eq(hud.overlay_keep_out(view), [] as Array[Rect2], "%s open: nothing to keep clear of" % screen_name)
		assert_true(stack.hint_text() != "", "%s open: the stack's footer shows (over nothing of the HUD)" % screen_name)
		s.close()
		for i in 2:
			await get_tree().process_frame
		assert_true(hud.is_visible_in_tree() and not hud.menu_hidden(), "%s closed: the HUD is back" % screen_name)
	assert_true(hud.message_texts().has(line), "the message waited behind the screens (%s)" % hud.message_texts())
	var overlay := UiScreen.new()
	overlay.set_script(load("res://tests/support/test_overlay_screen.gd"))
	stack.push(overlay)
	for i in 2:
		await get_tree().process_frame
	assert_false(get_tree().paused, "a screen that does not pause the game")
	assert_true(hud.menu_hidden(), "hides the HUD all the same")
	stack.close_all()
	for i in 2:
		await get_tree().process_frame
	assert_false(hud.menu_hidden(), "and it is back once that closes")
	stack.queue_free()


## P39f ("ability names too long for their hotbar slot are cut with no '...'": RAMPART read "RAMPA", Heavy
## Footfall "FOOTF"): a slot's title spans the slot inside its border (Hud.SLOT_TITLE_WIDTH, it was the box's
## 42 px content) and every hotbar label in the data fits it whole in the title's font; the live hotbar shows
## Heavy Footfall's label untrimmed. The red reason line under the slots ends REASON_EDGE_PX or more above the
## screen's edge, one whole line of its font tall (its letters' tails were cut), inside the hotbar's region.
func test_hotbar_names_and_notes_fit() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	hud.player = p
	await step_ticks(2)
	for i in 2:
		await get_tree().process_frame
	var slots: Array = hud.get("_slots")
	var title := (slots[0] as Dictionary).title as Label
	assert_near(title.size.x, Hud.SLOT_TITLE_WIDTH, 0.5, "a title spans the slot's inner width (%.1f px)" % title.size.x)
	var font := title.get_theme_font("font")
	var fs := title.get_theme_font_size("font_size")
	var too_long := PackedStringArray()
	var past_old := 0
	var labels := 0
	for rec: Dictionary in GameData.records_of_type("action"):
		if not rec.has("hotbar_label"):
			continue
		labels += 1
		var w := font.get_string_size(str(rec.hotbar_label), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > title.size.x:
			too_long.append("%s %s (%.0f px)" % [rec.id, rec.hotbar_label, w])
		if w > 42.0:
			past_old += 1
	assert_true(labels >= 25, "every ability's label is measured (%d)" % labels)
	assert_eq(too_long, PackedStringArray(), "every hotbar label fits its slot whole")
	assert_true(past_old >= 5, "%d labels were wider than the old 42 px title (RAMPART, FOOTFALL, ...)" % past_old)
	hud.refresh()
	assert_eq(title.text, GameData.get_action(str(p.controller.loadout.get("slot_1", ""))).hotbar_label,
		"slot 1 shows its ability's label (%s)" % title.text)
	assert_true(font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= title.size.x,
		"untrimmed: %s" % title.text)
	var region: Rect2 = hud.layout_regions(hud.size).hotbar
	for slot: Dictionary in slots:
		var reason := slot.reason as Label
		reason.text = "Busy"
		var r := _rect_in(hud, reason)
		assert_true(r.end.y <= hud.size.y - Hud.REASON_EDGE_PX + 0.5,
			"slot %d's note ends %.1f px above the screen's edge" % [int(slot.index), hud.size.y - r.end.y])
		assert_true(r.size.y + 0.5 >= font.get_height(reason.get_theme_font_size("font_size")),
			"slot %d's note is a whole line tall (%.1f px)" % [int(slot.index), r.size.y])
		assert_true(region.grow(0.5).encloses(Rect2(r.position.x + 1.0, r.position.y, maxf(r.size.x - 2.0, 1.0), r.size.y)),
			"slot %d's note lies in the hotbar's region" % int(slot.index))


## P39f ("long HUD lines are cut with '...'"; "the loot line has no backing"): the loot panel lists the
## materials the giant carries (stackable items) packed whole onto lines, on a backing, growing upward inside its
## region; one-of-a-kind trophies and quest items are the inventory screen's. Every material in the data at its
## stack's limit fits LOOT_MAX_LINES lines whole.
func test_the_loot_panel_lists_the_materials_whole() -> void:
	assert_eq(Hud.loot_entries({"item.iron_ingot": 3, "item.ogre_tusk": 1, "item.titan_iron": 2, "item.kings_annals": 1}),
		PackedStringArray(["Iron Ingot x3", "Titan Iron x2"]), "the materials, not the trophies")
	var hud := _hud()
	await get_tree().process_frame
	var label := hud.get("_loot_label") as Label
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var full := {}
	for rec: Dictionary in GameData.records_of_type("item"):
		if int(rec.get("stack_max", 1)) > 1:
			full[str(rec.id)] = int(rec.stack_max)
	var entries := Hud.loot_entries(full)
	assert_true(entries.size() >= 3, "the data's materials: %s" % entries)
	var lines := Hud.loot_lines(entries, font, fs, hud.loot_text_width())
	assert_true(lines.size() <= Hud.LOOT_MAX_LINES, "every material at its limit takes %d lines" % lines.size())
	var joined := Hud.LOOT_SEPARATOR.join(lines)
	for e in entries:
		assert_true(joined.contains(e), "%s is shown whole" % e)
	for l in lines:
		assert_true(font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= hud.loot_text_width(), "%s fits its line" % l)
	for pair: Array in [["item.iron_ingot", 3], ["item.titan_iron", 2], ["item.wood_scrap", 12], ["item.ogre_tusk", 1],
			["item.barrow_arm_ring", 1], ["item.kings_annals", 1]]:
		WorldState.add_item(str(pair[0]), int(pair[1]), "test")
	for i in 3:
		await get_tree().process_frame
	var shown := hud.loot_lines_now()
	assert_eq("\n".join(shown), "\n".join(Hud.loot_lines(PackedStringArray(["Iron Ingot x3", "Titan Iron x2",
		"Wood Scrap x12"]), font, fs, hud.loot_text_width())), "the live panel shows the three materials")
	assert_false("\n".join(shown).contains("Tusk"), "and no trophy")
	var panel := hud.get("_loot_panel") as PanelContainer
	var drawn := _rect_in(hud, panel)
	assert_true(hud.layout_regions(hud.size).loot.grow(0.5).encloses(drawn), "inside its region: %s" % drawn)
	var box := panel.get_theme_stylebox("panel") as HudKit.Box
	assert_true(box != null and box.bg.a >= 0.6, "on a backing (%s)" % (box.bg if box != null else "none"))
	assert_true(drawn.size.y >= shown.size() * font.get_height(fs), "as tall as its lines")


## P39f ("long tracker steps are cut with '...'"): each objective in the tracker may take Quest tracker's
## TEXT_LINES lines and every shipped quest step fits them (one took three, most others two: the side line had
## one); every quest title, with the longest door or lead after it, fits one line. The live tracker shows the
## longest step and a two-line one whole, its panel as tall as its lines and inside its region.
func test_tracker_steps_show_whole() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var tracker := hud.get_node("QuestTracker")
	var labels: Array = tracker.call("text_labels")
	var text_label := labels[0] as Label
	var font := text_label.get_theme_font("font")
	var width: float = tracker.get("TEXT_WIDTH")
	var max_lines: int = tracker.get("TEXT_LINES")
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var longest := ""
	var longest_lines := 0
	var steps := 0
	var over := PackedStringArray()
	for rec: Dictionary in GameData.records_of_type("quest"):
		var title := "%s  -  by the Kings' Door" % str(rec.get("display_name", ""))
		if font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, HudKit.SMALL).x > width:
			over.append("title %s" % title)
		for st: Dictionary in rec.get("stages", []):
			var t := str(st.get("objective", ""))
			var n := roundi(font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, width, HudKit.TEXT, -1, flags).y
				/ font.get_height(HudKit.TEXT))
			steps += 1
			if n > max_lines:
				over.append("%s (%d lines)" % [t, n])
			if n > longest_lines:
				longest_lines = n
				longest = t
	assert_true(steps > 60, "every quest step is measured (%d)" % steps)
	assert_eq(over, PackedStringArray(), "every step and title fits the tracker whole")
	assert_true(longest_lines >= 3, "the longest step takes %d lines: %s" % [longest_lines, longest])
	Fx.install([Fx.quest("quest.test_long", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0, {"objective": longest})]),
		Fx.quest("quest.test_side", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Meet Sedge, the woodfolk's elder, at Hollowmere, and hear what the wood asks of you"})])])
	Fx.activate(["quest.test_long", "quest.test_side"], [], "quest.test_long")
	for i in 3:
		await get_tree().process_frame
	for l: Label in labels:
		assert_true(l.visible and l.get_line_count() >= 2, "a long step shows (%d lines): %s" % [l.get_line_count(), l.text])
		assert_eq(l.get_visible_line_count(), l.get_line_count(), "whole, untrimmed: %s" % l.text)
	var panel: Control = tracker.call("layout_controls").quest_tracker
	var drawn := _rect_in(hud, panel)
	assert_true(hud.layout_regions(hud.size).quest_tracker.grow(0.5).encloses(drawn), "inside its region: %s" % drawn)
	assert_near(drawn.size.y, panel.get_combined_minimum_size().y, 1.0, "as tall as its lines")
