extends Node
## The rendered option check's probe (P44; plan M10 §3.4 design 4, §2.13, decision 18): tests/slow/
## test_appearance_render.gd runs this scene (a main scene, so the autoloads exist: Appearance reads GameData) in
## a child Godot under Xvfb with the Compatibility renderer:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x960x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x960 --audio-driver Dummy res://tests/support/appearance_render_probe.tscn -- --giant-tier=web
##
## Sixteen GiantPreview tiles of 320x240 in a 4x4 grid draw sixteen looks a frame: every option of every set in
## the creator's framing of its category (skin, clothing, dyes and presets the whole giant; eyes and beards the
## face; hair and hair colours three-quarter from behind; a design its region), each against the base look in the
## same framing (the Wanderer; an option that is the base's own value against its neighbour in the set), and every
## design (tattoos, war paint, scars, ancestry marks) also in the stage-1 rear Game view and in first person. A
## line's options (ashen skin, the storm and amber eyes, the marks) are drawn for that line. For each tile it
## measures the share of pixels off the tile's backdrop (`lit`, every second pixel each way) and the share of
## its pixels that changed against its base (`changed`, every pixel), runs GiantLook.validate(), saves every grid to
## user://m10_frames/options/ and prints one line
##   APPEARANCE_RENDER {"tiles", "grids", "ms", "grid_ms", "results": {key: {cat, view, changed, lit, vs}},
##                      "validate": [...], "adapter", "tier"}
## then quits (a watchdog quits it on a script error). `-- --only=<prefix>` draws only the options whose key starts
## with the prefix (and the bases they are measured against): `--only=scar` for a look at the scars alone.

const OUT_DIR := "user://m10_frames/options/"
const PREFIX := "APPEARANCE_RENDER "
const TILE := Vector2i(320, 240)
const COLS := 4
const TILES := 16
const WATCHDOG_S := 170.0
## A pixel counts as changed when its channels move this much together (0-3 scale).
const DIFF := 0.08
## Frames drawn before a grid is read: the first grid compiles the giant's shaders, the others only draw.
const FRAMES_FIRST := 2
const FRAMES_EACH := 1
## Each option set's creator framing (a design category's framing comes from the design's region).
const SET_FRAMING := {"skin": "full", "eyes": "face", "hair": "hair", "beard": "face", "haircolor": "hair",
	"ink": "arms", "paintcolor": "face", "outfit": "full", "dye": "full", "preset": "full"}
const DESIGN_SETS := ["tattoo", "paint", "scar", "mark"]

var _tiles: Array[GiantPreview] = []
var _jobs: Array = []
var _results := {}
var _images := {}
var _validate := PackedStringArray()
var _stage1: Dictionary = {}


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the probe timed out"}))
		get_tree().quit(3))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_stage1 = GiantPreview.stage_profile(1)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	add_child(grid)
	for i in TILES:
		var p := GiantPreview.new()
		p.still = true   # one pose in every tile: an option is measured against its base, not against the idle
		p.custom_minimum_size = Vector2(TILE)
		p.viewport.msaa_3d = Viewport.MSAA_DISABLED   # the check measures pixels, not edges
		grid.add_child(p)
		_tiles.append(p)
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


# --------------------------------------------------------------------------- the jobs

## Every tile to draw: {key, cat, view ("framed" | "rear" | "fp"), framing, record, ancestry, vs (the key it is
## compared with; "" for a base)}.
static func jobs() -> Array:
	var out: Array = []
	var base := Appearance.default_record()
	base["mark"] = Appearance.MARK_NONE
	base["preset"] = ""   # an edited record is "custom": the base differs from an option only by that option
	var bases := {}
	var add_base := func(framing: String, record: Dictionary, key: String) -> void:
		out.append({"key": key, "cat": "base", "view": "framed", "framing": framing, "record": record, "ancestry": "", "vs": ""})
		bases[key] = true
	for f: String in ["full", "face", "hair", "arms", "chest", "back_design", "hand_l"]:
		add_base.call(f, base, "base." + f)
	out.append({"key": "base.rear", "cat": "base", "view": "rear", "framing": "game", "record": base, "ancestry": "", "vs": ""})
	out.append({"key": "base.fp", "cat": "base", "view": "fp", "framing": GiantPreview.FIRST_PERSON, "record": base,
		"ancestry": "", "vs": ""})
	var inked := OptionRows.with_value(base, "tattoos.arms", "tattoo.arm_bands")
	add_base.call("arms", inked, "base.ink")
	var painted := OptionRows.with_value(base, "paint.design", "paint.face_stripes")
	add_base.call("face", painted, "base.paintcolor")
	# Every option of every set in its framing.
	for cat: String in Appearance.CATEGORIES:
		var ids := Appearance.option_ids(cat)
		for i in ids.size():
			var id := ids[i]
			var o := Appearance.option(id)
			var line := Appearance.required_ancestry(o)
			var rec := _with_option(cat, id, base, inked, painted)
			var framing := str(SET_FRAMING.get(cat, "full"))
			var vs := "base." + framing
			if cat == "ink":
				vs = "base.ink"
			elif cat == "paintcolor":
				vs = "base.paintcolor"
			elif cat in DESIGN_SETS:
				framing = GiantPreview.region_framing(_design_region(cat, o))
				vs = "base." + framing
			if OptionRows.same(rec, (base if cat not in ["ink", "paintcolor"] else (inked if cat == "ink" else painted))):
				vs = cat + "." + ids[(i + 1) % ids.size()].get_slice(".", 1)   # the base's own value: against its neighbour
			out.append({"key": id, "cat": cat, "view": "framed", "framing": framing, "record": rec, "ancestry": line, "vs": vs})
			if cat in DESIGN_SETS:
				out.append({"key": id + "@rear", "cat": cat, "view": "rear", "framing": "game", "record": rec, "ancestry": line,
					"vs": "base.rear"})
				out.append({"key": id + "@fp", "cat": cat, "view": "fp", "framing": GiantPreview.FIRST_PERSON, "record": rec,
					"ancestry": line, "vs": "base.fp"})
	for pid: String in Appearance.preset_ids():
		var rec := Appearance.preset_record(pid)
		rec["mark"] = Appearance.MARK_NONE
		var plain := rec.duplicate(true)
		plain["preset"] = ""
		var vs := "base.full" if not OptionRows.same(plain, base) else str(Appearance.preset_ids()[1])
		out.append({"key": pid, "cat": "preset", "view": "framed", "framing": "full", "record": rec, "ancestry": "", "vs": vs})
	return out


## The base record with option `id` of set `cat` put on (an ink on the inked base, a paint colour on the painted
## one; a mark shows through mark "auto" and the line it is drawn for).
static func _with_option(cat: String, id: String, base: Dictionary, inked: Dictionary, painted: Dictionary) -> Dictionary:
	match cat:
		"skin":
			return OptionRows.with_value(base, "skin", id)
		"eyes":
			return OptionRows.with_value(base, "eyes", id)
		"hair":
			return OptionRows.with_value(base, "hair.style", id)
		"haircolor":
			return OptionRows.with_value(base, "hair.color", id)
		"beard":
			return OptionRows.with_value(base, "beard.style", id)
		"tattoo":
			return OptionRows.with_value(base, "tattoos." + str(Appearance.option(id).get("region", "arms")), id)
		"ink":
			return OptionRows.with_value(inked, "tattoos.ink", id)
		"paint":
			return OptionRows.with_value(base, "paint.design", id)
		"paintcolor":
			return OptionRows.with_value(painted, "paint.color", id)
		"scar":
			return OptionRows.with_scar(base, id, true)
		"mark":
			return OptionRows.with_value(base, "mark", Appearance.MARK_AUTO)
		"outfit":
			return OptionRows.with_value(base, "outfit.set", id)
		"dye":
			return OptionRows.with_value(base, "outfit.primary", id)
	return base.duplicate(true)


## The design region of a design option (tattoo, paint: its region; scar, mark: its design's first body region).
static func _design_region(cat: String, o: Dictionary) -> String:
	if cat in ["tattoo", "paint"]:
		return str(o.get("region", "arms"))
	var spec := {"key": "scar.x" if cat == "scar" else "mark", "id": "%s.%s" % [cat, str(o.get("key", ""))]}
	return OptionRows.row_region(spec, {}, _index, str(Appearance.required_ancestry(o)))


## The giant's index (from the first tile's model): scars and marks are framed by their design's region.
static var _index := {}


# --------------------------------------------------------------------------- drawing

func _run() -> void:
	_index = _tiles[0].index()
	_jobs = jobs()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	if only != "":
		var keep := {}
		for job: Dictionary in _jobs:
			if str(job.key).begins_with(only) or str(job.key).begins_with("base."):
				keep[job.key] = true
		for job: Dictionary in _jobs:
			if keep.has(job.key) and str(job.vs) != "":
				keep[job.vs] = true
		_jobs = _jobs.filter(func(j: Dictionary) -> bool: return keep.has(j.key))
	var t0 := Time.get_ticks_msec()
	var grids := 0
	var grid_ms := 0.0
	var i := 0
	while i < _jobs.size():
		var batch: Array = _jobs.slice(i, i + TILES)
		for t in TILES:
			var tile := _tiles[t]
			if t >= batch.size():
				tile.visible = false
				continue
			tile.visible = true
			var job: Dictionary = batch[t]
			tile.set_game_profile(_stage1)
			var look := Appearance.to_look(job.record, str(job.ancestry))
			tile.apply_look(look)
			tile.frame(str(job.framing))
			for problem in GiantLook.validate(tile.model, tile.index(), look):
				if not _validate.has(problem):
					_validate.append(problem)
		var g0 := Time.get_ticks_msec()
		for f in (FRAMES_FIRST if grids == 0 else FRAMES_EACH):
			await RenderingServer.frame_post_draw
		grid_ms += float(Time.get_ticks_msec() - g0)
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT_DIR + "grid_%02d.png" % grids)
		for t in batch.size():
			var job: Dictionary = batch[t]
			var rect := Rect2i(Vector2i(t % COLS, t / COLS) * TILE, TILE)
			var tile_img := img.get_region(rect)
			tile_img.convert(Image.FORMAT_RGB8)
			_images[job.key] = tile_img
		grids += 1
		i += TILES
	for job: Dictionary in _jobs:
		var img: Image = _images[job.key]
		var r := {"cat": job.cat, "view": job.view, "lit": lit_share(img), "vs": job.vs, "changed": 0.0}
		if str(job.vs) != "" and _images.has(job.vs):
			r["changed"] = changed_share(img, _images[job.vs])
		_results[job.key] = r
	var out := {"tiles": _jobs.size(), "grids": grids, "ms": Time.get_ticks_msec() - t0,
		"grid_ms": grid_ms / maxf(1.0, float(grids)), "results": _results, "validate": Array(_validate),
		"adapter": RenderingServer.get_video_adapter_name(), "tier": GiantLook.built_tier(_tiles[0].model)}
	_write_index()
	print(PREFIX + JSON.stringify(out))
	get_tree().quit(0)


## The grids' tile keys, for the frames' readers (P46, the sheets).
func _write_index() -> void:
	var keys: Array = []
	for job: Dictionary in _jobs:
		keys.append(job.key)
	var f := FileAccess.open(OUT_DIR + "index.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"tile": [TILE.x, TILE.y], "per_grid": TILES, "columns": COLS, "keys": keys}, "  "))


## The share of pixels (every second one each way) off the tile's backdrop (its top-left pixel).
static func lit_share(img: Image) -> float:
	var bg := img.get_pixel(0, 0)
	var lit := 0
	var total := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			total += 1
			var p := img.get_pixel(x, y)
			if absf(p.r - bg.r) + absf(p.g - bg.g) + absf(p.b - bg.b) > DIFF:
				lit += 1
	return float(lit) / maxf(1.0, float(total))


## The share of a tile's pixels (every one: a design seen from behind covers a few) that differ between two
## tiles of the same size in RGB8; rows equal byte for byte are skipped whole.
static func changed_share(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size() or da.is_empty():
		return 1.0
	var limit := int(DIFF * 255.0)
	var row := a.get_width() * 3
	var changed := 0
	for y in a.get_height():
		var ra := da.slice(y * row, (y + 1) * row)
		var rb := db.slice(y * row, (y + 1) * row)
		if ra == rb:
			continue
		for i in range(0, row, 3):
			if absi(ra[i] - rb[i]) + absi(ra[i + 1] - rb[i + 1]) + absi(ra[i + 2] - rb[i + 2]) > limit:
				changed += 1
	return float(changed) / float(a.get_width() * a.get_height())
