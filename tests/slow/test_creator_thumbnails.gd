extends TestSuite
## The creator II's thumbnails (P55; plan M11 §2.7, §3.8 item 3; the Web's rule): made one a frame, only for the
## page a grid shows, cached by the option, the skin and the dyes for the screen's life.
##   * Headless (the scheduling): a grid of three pages - a page turned past is never drawn, what was made comes back
##     at once, a closed grid makes nothing, nothing is made while the screen opens.
##   * Rendered: tests/support/creator_probe.tscn (--quick, the test catalogue) in a child Godot under Xvfb at
##     640x360 (the Compatibility renderer, two llvmpipe threads): a clothing slot's grid, the outfits, a tattoo region
##     (flat pictures of the designs) - every visible option gets its picture, none off the page, never two in a
##     frame, no engine or shader error; the frames while they are made against the frames after are reported (the
##     thumbnails' cost; the creator's first frame is creator_check.mjs's). Frames: user://m11_frames/P55/grid_*.png.
## Without xvfb-run the rendered part is skipped with a note.

const PROBE := "res://tests/support/creator_probe.tscn"
const CHILD_TIMEOUT_S := 150
const PREFIX := "CREATOR_PROBE "
## The frames while a page's thumbnails are made may cost at most this much more than the frames after (median
## against median): one 96 x 96 draw and its read-back a frame.
const MAX_FRAME_COST := 1.5

var layer: CanvasLayer
var stack: ScreenStack


func before_each() -> void:
	InputBindings.reset_device()
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(layer):
		layer.queue_free()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await get_tree().process_frame


func _open() -> CreatorScreen:
	var c := stack.open("creator", {"context": "new_game", "start": {"mode": "valley", "options": {"new_game": true}}}) 		as CreatorScreen
	assert_true(c != null, "the creator opens")
	return c



func test_thumbnails_come_one_a_frame_for_the_page_shown_only() -> void:
	CreatorCatalogue.install()
	var hair: Array = []
	for i in 30:
		hair.append({"key": "style_%d" % i, "name": "Style %d" % i, "mesh": "Hair_long_back" if i % 2 == 0 else "",
			"scalp_tint": 0.0})
	TestFixtures.record_override(Appearance.SET_PREFIX + "hair", {"options": hair})
	var c := _open()
	await get_tree().process_frame
	assert_true(c.thumbnails.preview == null, "nothing is made while the screen opens")
	c.show_category("Hair")
	c.open_grid(c.row("hair.style") as OptionRows.GridRow)
	var g := c.grid
	assert_eq(g.pages(), 3, "three pages")
	var page1: Array = g.visible_ids()
	assert_eq(page1.size(), OptionGrid.PER_PAGE, "twelve on the first")
	for i in 4:
		await get_tree().process_frame
	var made_first := c.thumbnails.made
	var started: Array = c.thumbnails.made_ids.duplicate()   # with the one drawn in the frame before the turn
	assert_true(made_first >= 2 and made_first <= 4, "a few made in four frames (%d)" % made_first)
	g.step_page(1)
	var page2: Array = g.visible_ids()
	for i in 20:
		await get_tree().process_frame
	assert_false(c.thumbnails.busy(), "the page's thumbnails are done")
	assert_true(c.thumbnails.most_in_a_frame <= ThumbnailCache.THUMBS_PER_FRAME, "never more than one a frame (%d)" %
		c.thumbnails.most_in_a_frame)
	var frames: Array = c.thumbnails.made_frames
	var unique := {}
	for f: int in frames:
		unique[f] = true
	assert_eq(unique.size(), frames.size(), "each made in a frame of its own")
	var off := PackedStringArray()
	for id: String in c.thumbnails.made_ids:
		if not (started.has(id) or page2.has(id)):
			off.append(id)
	assert_eq(off, PackedStringArray(), "only the pages shown were made (the first page's rest was never drawn)")
	for id: String in page2:
		assert_true(g.shows_thumbnail(id), "%s shows its thumbnail" % id)
	# back to the first page: what was made comes from the cache at once; the rest is made
	var made := c.thumbnails.made
	g.step_page(-1)
	for id: String in page1.slice(0, made_first):
		assert_true(g.shows_thumbnail(id), "%s is shown again at once" % id)
	assert_eq(c.thumbnails.made, made, "without making it again")
	# closing the grid stops the queue
	c.close_grid()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(c.thumbnails.busy(), "a closed grid makes nothing")
	# a thumbnail's key: the option, the skin and the dyes
	var item := c.thumb_item((c.row("hair.style") as OptionRows.GridRow).spec, "hair.style_0")
	assert_true(str(item.key).begins_with("hair.style_0|skin."), "the key starts with the option and the skin: %s" % item.key)
	c.show_category("Clothing")
	var g_item := c.thumb_item((c.row("outfit.slots.chest.item") as OptionRows.GridRow).spec, "garment.tunic")
	assert_true(str(g_item.key).contains("dye.undyed") and str(g_item.framing) == "chest", "a garment's key carries the dyes: %s" %
		g_item.key)
	assert_eq(c.thumb_item({"set": "garment", "slot": "chest"}, ""), {}, "None has no thumbnail")


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return float(v[v.size() / 2])


func test_rendered_thumbnails_for_the_visible_page_one_a_frame() -> void:
	if not _have("xvfb-run"):
		print("    test_creator_thumbnails: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var out := "user://m11_frames/P55/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 640x360x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "640x360", "--audio-driver", "Dummy", PROBE, "--",
		"--quick", "--catalogue", "--shots", "--out=" + ProjectSettings.globalize_path(out)])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "
".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("
"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or l.contains("SCRIPT ERROR") or (l.begins_with("ERROR") and not l.contains("pulse")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "no engine, script or shader error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and (r.errors as Array).is_empty(), "it reported: %s" % (line if line != ""
		else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY:
		return
	var lines := PackedStringArray()
	for key: String in r.grids:
		var g: Dictionary = r.grids[key]
		assert_true(int(g.visible) > 0 and int(g.with_thumbnail) == int(g.visible), "%s: every option on the page has its picture (%d of %d)" %
			[key, int(g.with_thumbnail), int(g.visible)])
		assert_eq(int(g.made), int(g.visible), "%s: one made per option shown" % key)
		assert_eq(int(g.off_page), 0, "%s: none off the page" % key)
		assert_true(int(g.most_in_a_frame) <= ThumbnailCache.THUMBS_PER_FRAME, "%s: never two in a frame" % key)
		var during := _median(g.frames_ms)
		var after := float(g.median_after_ms)
		assert_true(during <= after * MAX_FRAME_COST, "%s: the frames while they are made %.1f ms against %.1f ms after" %
			[key, during, after])
		lines.append("%s %d in %d frames, %.1f ms a frame against %.1f after (worst %.1f), own work at most %.1f ms" % [key,
			int(g.made), int(g.frames), during, after, float(g.worst_ms), (g.work_ms as Array).max()])
	assert_true(int(r.thumbnails.flat) > 0, "the tattoos are flat pictures of their designs (%d)" % int(r.thumbnails.flat))
	print("    test_creator_thumbnails: %s; on %s" % ["; ".join(lines), str(r.adapter)])
