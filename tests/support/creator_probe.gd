extends Node
## P55 (plan M11 §3.8): the creator II under a real renderer (a main scene, run in a child Godot under Xvfb by
## tests/slow/test_creator_thumbnails.gd, and by hand for the package's captures):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy res://tests/support/creator_probe.tscn -- [--out=DIR] [--catalogue] [--shots] [--quick]
##
## It opens the creator (a New Game) on a ScreenStack, walks the categories, opens grids (a clothing slot, the
## hair styles, a tattoo region, an accessory slot), waits for each grid's thumbnails, and measures them: how many
## were made, the most in one frame, the frames they were made in, each one's own work in its frame, and the
## frames' wall time while they were made against the frames after. --catalogue puts the test catalogue (about
## 190 options, tests/fixtures/appearance/creator_catalogue.json) over the game's sets first. --shots saves a PNG
## of the window at each step into --out (default user://m11_frames/P55/). It prints one line,
## CREATOR_PROBE {...}, and quits; a watchdog quits it after WATCHDOG_S.

const TAG := "CREATOR_PROBE "
const WATCHDOG_S := 240.0
## Frames a grid is given for its thumbnails (12 a page at one a frame, and the read-back's frame).
const GRID_FRAMES := 40

var out_dir := "user://m11_frames/P55/"
var shots := false
## --quick (the slow suite): no category tour; two grids (a clothing slot, a tattoo region), each saved, then the
## report.
var quick := false
## The frames measured after a grid's thumbnails are done.
var after_frames := 12
var stack: ScreenStack
var c: CreatorScreen
var report := {"grids": {}, "shots": [], "errors": []}
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--shots":
			shots = true
		elif a == "--catalogue":
			report["options"] = CreatorCatalogue.install_for_probe()
		elif a == "--quick":
			quick = true
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("user://") \
		or out_dir.begins_with("res://") else out_dir)
	report["window"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	report["adapter"] = RenderingServer.get_video_adapter_name()
	_run.call_deferred()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _t0 > WATCHDOG_S * 1000.0:
		report.errors.append("watchdog")
		_finish()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + shot_name + ".png"
	img.save_png(path if not path.begins_with("user://") else ProjectSettings.globalize_path(path))
	(report.shots as Array).append(shot_name)


func _run() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	await _frames(2)
	c = stack.open("creator", {"context": "new_game", "start": {"mode": "valley", "options": {"new_game": true}}}) \
		as CreatorScreen
	await _frames(8)
	if quick:
		after_frames = 6
		for case: Array in [["Clothing", "outfit.slots.armour.item", "grid_armour"], ["Tattoos", "tattoos.arms", "grid_tattoo_arms"]]:
			await _grid(case[0], case[1], case[2])
		report["thumbnails"] = {"made": c.thumbnails.made, "rendered": c.thumbnails.rendered, "flat": c.thumbnails.flat,
			"most_in_a_frame": c.thumbnails.most_in_a_frame}
		_finish()
		return
	await _shot("01_presets")
	for cat: String in ["Body", "Face", "Hair", "Beard", "Tattoos", "War paint", "Scars", "Clothing", "Accessories", "Colours"]:
		c.show_category(cat)
		await _frames(4)
		await _shot("%02d_%s" % [3 + OptionRows.CATEGORIES.find(cat), cat.to_lower().replace(" ", "_")])
	# a build slider has the focus: the stage-1 rear Game view
	c.show_category("Body")
	var brawn := c.row("build.brawn") as OptionRows.SliderRow
	if brawn != null:
		brawn.slider.grab_focus()
		await _frames(4)
		report["slider_framing"] = c.preview.framing
		c.pick("build.brawn", 0.4)
		await _frames(3)
		await _shot("20_body_brawn_rear")
		c.undo()
	# grids: a clothing slot, the outfits, the hair styles, a tattoo region, an accessory slot
	for case: Array in [["Clothing", "outfit.slots.chest.item", "21_grid_chest"], ["Clothing", "outfit.slots.armour.item",
			"22_grid_armour"], ["Clothing", "outfit.set", "23_grid_outfits"], ["Hair", "hair.style", "24_grid_hair"],
			["Tattoos", "tattoos.arms", "25_grid_tattoo_arms"], ["Accessories", "outfit.accessories.neck", "26_grid_neck"]]:
		await _grid(case[0], case[1], case[2])
	# the second page of the hair styles (the catalogue has more than a page), the material filter
	c.show_category("Clothing")
	c.open_grid(c.row("outfit.slots.armour.item") as OptionRows.GridRow)
	await _frames(2)
	if c.grid.materials().size() > 1:
		c.grid.set_material_filter("metal")
		await _frames(GRID_FRAMES / 2)
		await _shot("27_grid_armour_metal")
	c.grid.set_query("sc")
	await _frames(GRID_FRAMES / 2)
	await _shot("28_grid_armour_find")
	c.close_grid()
	c.show_category("Hair")
	c.open_grid(c.row("hair.style") as OptionRows.GridRow)
	await _frames(2)
	if c.grid.pages() > 1:
		c.grid.step_page(1)
		await _frames(GRID_FRAMES / 2)
		await _shot("29_grid_hair_page2")
	c.close_grid()
	# the rear view and the discard question
	c.set_view("back")
	await _frames(4)
	await _shot("30_back_view")
	c.set_view("")
	c.cancel()
	await _frames(3)
	await _shot("31_question")
	c.keep_editing()
	report["thumbnails"] = {"made": c.thumbnails.made, "rendered": c.thumbnails.rendered, "flat": c.thumbnails.flat,
		"most_in_a_frame": c.thumbnails.most_in_a_frame}
	_finish()


## Opens the grid of row `key` in `category` and measures its thumbnails: the frames' wall time while they are made
## against the GRID_FRAMES / 2 frames after.
func _grid(category: String, key: String, shot_name: String) -> void:
	c.show_category(category)
	await _frames(2)
	var r := c.row(key) as OptionRows.GridRow
	if r == null:
		report.errors.append("no row " + key)
		return
	var made_before := c.thumbnails.made
	var work_before := c.thumbnails.work_ms.size()
	var frames_ms: Array = []
	c.open_grid(r)
	var t := Time.get_ticks_usec()
	var visible := c.grid.visible_ids().size()
	var n := 0
	while n < GRID_FRAMES and (c.thumbnails.busy() or n < 2):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames_ms.append(float(now - t) / 1000.0)
		t = now
		n += 1
	var after: Array = []
	for i in after_frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		after.append(float(now - t) / 1000.0)
		t = now
	var shown := 0
	for id: String in c.grid.visible_ids():
		if c.grid.shows_thumbnail(id):
			shown += 1
	var work: Array = c.thumbnails.work_ms.slice(work_before)
	after.sort()
	var made_ids: Array = c.thumbnails.made_ids.slice(made_before)
	var off_page := 0
	for id: String in made_ids:
		if not c.grid.visible_ids().has(id):
			off_page += 1
	report.grids[shot_name] = {"key": key, "visible": visible, "made": c.thumbnails.made - made_before,
		"with_thumbnail": shown, "frames": n, "frames_ms": frames_ms, "median_after_ms": after[after.size() / 2],
		"worst_ms": frames_ms.max() if not frames_ms.is_empty() else 0.0, "work_ms": work,
		"most_in_a_frame": c.thumbnails.most_in_a_frame, "off_page": off_page, "pages": c.grid.pages(),
		"cell_px": c.grid.cell_px(), "design": c.thumbnails.design_timings.duplicate(),
		"focus": str(get_viewport().gui_get_focus_owner().name) if get_viewport().gui_get_focus_owner() != null else ""}
	await _shot(shot_name)
	c.close_grid()


func _finish() -> void:
	report["ms"] = Time.get_ticks_msec() - _t0
	print(TAG + JSON.stringify(report))
	get_tree().quit()
