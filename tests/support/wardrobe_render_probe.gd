extends Node
## The wardrobe, rendered (P54; plan M11 §2.6, §3.7): tests/slow/test_wardrobe_render.gd runs this scene
## (tests/support/wardrobe_render_probe.tscn) in a child Godot under Xvfb with the Compatibility renderer:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/wardrobe_render_probe.tscn [-- --out=/abs/folder]
##
## The check (default): GiantPreview at 320x240 in the world's light shows the fullest slot look (the huscarl's
## outfit: a garment in every one of the ten slots, the three accessories, long hair and a full beard) from the front
## and from behind. Each garment and accessory mesh is drawn in a flat colour of its own (unshaded, the look's own
## skeleton and pose) and the frame is drawn twice with the camera moved by half a millimetre: where two surfaces
## share a depth (z-fighting) the colour under a pixel flips although its neighbours keep theirs. It reports per view
## the share of the giant's pixels that flip so (`flicker`), which garments show (`seen`), the draw calls and the
## primitives of the view (the renderer's own counters), and GiantLook.validate(). One line:
##   WARDROBE_RENDER {"views": {name: {"flicker", "pixels", "seen": [...], "draws", "primitives"}}, "validate": [...],
##                    "meshes": n, "adapter": ...}
## With --review the probe draws instead the look sheets a reviewer reads (no check): for every outfit (and the
## fullest look with its accessories) front, side and back in the world's light and in the creator's at stage 1, and
## for the fullest look also at stage 6 and at build -1 and +1, each sheet one PNG in --out.

const PREFIX := "WARDROBE_RENDER "
const TILE := Vector2i(320, 240)
const REVIEW_TILE := Vector2i(300, 420)
const WATCHDOG_S := 200.0
const FULLEST := "outfit.huscarl"
const ACCESSORIES := {"neck": "accessory.gilded_torc", "arm_ring": "accessory.iron_arm_ring", "belt": "accessory.drinking_horn"}
## The camera's nudge between the two frames of a view (metres, stage 1).
const NUDGE_M := 0.0005
## Two colours are one garment's when they differ by less than this (sum over the channels, 0-3).
const SAME := 0.02
## A pixel is a garment's flat colour when it lies within this of it (the frame's own rounding).
const MATCH := 0.08
## The flat colours, far apart from one another and from the backdrop's sky and ground.
const PALETTE := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0), Color(1, 0, 1), Color(0, 1, 1),
	Color(1, 0.5, 0), Color(0.5, 0, 1), Color(0, 0.5, 0), Color(0.5, 0, 0), Color(0, 0, 0.5), Color(1, 1, 1),
	Color(0.5, 0.5, 0), Color(0, 0.5, 0.5), Color(0.5, 0, 0.5), Color(1, 0.5, 0.5)]

var _p: GiantPreview
var _out := ""
var _review := false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the probe timed out"}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg == "--review":
			_review = true
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	var size := REVIEW_TILE if _review else TILE
	_p = GiantPreview.new()
	_p.still = true
	_p.stretch = false
	_p.custom_minimum_size = Vector2(size)
	_p.size = Vector2(size)
	add_child(_p)
	_p.viewport.size = size
	_p.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().process_frame.connect(_review_run if _review else _run, CONNECT_ONE_SHOT)


func _draw_frame() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return _p.viewport.get_texture().get_image()


## The fullest slot look's record: the huscarl's outfit, the three accessories, long hair, a full beard.
static func fullest_record() -> Dictionary:
	var r := Appearance.with_outfit(Appearance.preset_record("appearance_preset.wanderer"), FULLEST)
	for slot: String in ACCESSORIES:
		r.outfit.accessories[slot] = ACCESSORIES[slot]
	r.outfit.dyes = {"cloth": "dye.woad_blue", "leather": "dye.walnut", "metal": "metal.steel"}
	return r


func _run() -> void:
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "views": {}, "validate": []}
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var look := Appearance.to_look(fullest_record())
	_p.apply_look(look)
	report.validate = Array(GiantLook.validate(_p.model, _p.model.index, look))
	var shown: Array = []
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		if mi.visible and mi.is_visible_in_tree():
			shown.append(mi)
	report["meshes"] = shown.filter(func(mi: MeshInstance3D) -> bool: return mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY).size()
	for view: String in ["front", "back"]:
		_p.frame("full")
		_p.turn(0.0 if view == "front" else 180.0)
		var counters: Dictionary = (await _counters()) if view == "front" else report.views.front.duplicate()
		counters = {"draws": counters.draws, "primitives": counters.primitives}
		var colours := _flat(shown)
		var a: Image = await _draw_frame()
		_p.camera.position += _p.camera.transform.basis.x * NUDGE_M
		var b: Image = await _draw_frame()
		_unflat(shown)
		var m := flicker(a, b)
		m["seen"] = _seen(a, colours)
		m.merge(counters)
		report.views[view] = m
		if _out != "":
			a.save_png(_out.path_join("wardrobe_ids_%s.png" % view))
	print(PREFIX + JSON.stringify(report))
	get_tree().quit(0)


## The giant's own draw calls and primitives in the view's main pass, as the renderer counts them: the frame with the
## model less the frame without it (the look as drawn, its own materials; shadows are counted apart, the proxy's).
func _counters() -> Dictionary:
	var rid := _p.viewport.get_viewport_rid()
	var info := func() -> Vector2i:
		return Vector2i(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	await _draw_frame()
	var with_model: Vector2i = info.call()
	_p.model.visible = false
	await _draw_frame()
	var without: Vector2i = info.call()
	_p.model.visible = true
	return {"draws": with_model.x - without.x, "primitives": with_model.y - without.y}


## Every garment and accessory mesh in a flat colour of its own (the body, hair and eyes black): {mesh name: colour}.
func _flat(shown: Array) -> Dictionary:
	var out := {}
	var i := 0
	# the flat colours come out as they are: no fog, no tonemapping
	_p.environment.fog_enabled = false
	_p.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_p.environment.tonemap_exposure = 1.0
	for mi: MeshInstance3D in shown:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cat := str((_p.model.index.meshes.get(str(mi.name), {}) as Dictionary).get("category", ""))
		m.disable_fog = true
		var c := Color.BLACK
		if cat in ["garment", "accessory"]:
			c = PALETTE[i % PALETTE.size()]
			i += 1
			out[str(mi.name)] = c
		m.albedo_color = c
		mi.set_meta("wardrobe_probe_material", mi.material_override)
		mi.material_override = m
	return out


func _unflat(shown: Array) -> void:
	_p.environment.fog_enabled = _p.world_light
	for mi: MeshInstance3D in shown:
		mi.material_override = mi.get_meta("wardrobe_probe_material")
		mi.remove_meta("wardrobe_probe_material")


## The garments whose colour covers at least a few pixels of the frame.
static func _seen(img: Image, colours: Dictionary) -> Array:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			for k: String in colours:
				var c: Color = colours[k]
				if absf(p.r - c.r) + absf(p.g - c.g) + absf(p.b - c.b) < MATCH:
					counts[k] = int(counts.get(k, 0)) + 1
					break
	var out: Array = []
	for k: String in counts:
		if int(counts[k]) >= 4:
			out.append(k)
	out.sort()
	return out


## The z-fighting measure of two frames a nudge apart: the share of the giant's pixels (not the backdrop) whose colour
## changes although the colour of each of their four neighbours in the first frame is their own (an interior pixel of
## a surface: a moved silhouette changes edge pixels only).
static func flicker(a: Image, b: Image) -> Dictionary:
	var w := a.get_width()
	var h := a.get_height()
	var bg := a.get_pixel(0, 0)
	var pixels := 0
	var flips := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var p := a.get_pixel(x, y)
			if _d(p, bg) < SAME:
				continue
			pixels += 1
			if _d(p, b.get_pixel(x, y)) < SAME:
				continue
			if _d(p, a.get_pixel(x - 1, y)) < SAME and _d(p, a.get_pixel(x + 1, y)) < SAME \
					and _d(p, a.get_pixel(x, y - 1)) < SAME and _d(p, a.get_pixel(x, y + 1)) < SAME:
				flips += 1
	return {"pixels": pixels, "flicker": float(flips) / maxf(1.0, float(pixels)), "flips": flips}


static func _d(p: Color, q: Color) -> float:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)


# ------------------------------------------------------------------------------------------------ the review sheets
func _review_run() -> void:
	var looks := {}
	for id: String in Appearance.option_ids("outfit"):
		var r := Appearance.with_outfit(Appearance.preset_record("appearance_preset.wanderer"), id)
		r.outfit.dyes = {"cloth": "dye.madder", "leather": "dye.walnut", "metal": "metal.iron"}
		looks[id.trim_prefix("outfit.")] = r
	looks["fullest"] = fullest_record()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			only = arg.substr(8)
	for name: String in looks:
		if only != "" and not name in only.split(","):
			continue
		var tiles: Array = []
		for world: bool in [true, false]:
			for yaw: float in [20.0, 90.0, 180.0]:
				tiles.append(await _tile(looks[name], world, yaw, 1, Vector2.ZERO))
		_save_sheet(tiles, 3, "sheet_%s.png" % name)
		if OS.get_cmdline_user_args().has("--closeups"):
			var close: Array = []
			for f: String in ["chest", "face", "back_design"]:
				close.append(await _tile(looks[name], true, 0.0, 1, Vector2.ZERO, f))
			for f: String in ["arms", "chest", "hair"]:
				close.append(await _tile(looks[name], false, 0.0 if f != "chest" else 150.0, 1, Vector2.ZERO, f))
			_save_sheet(close, 3, "sheet_%s_close.png" % name)
		if OS.get_cmdline_user_args().has("--build-close"):
			var bc: Array = []
			for b: Vector2 in [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]:
				bc.append(await _tile(looks[name], false, 0.0, 1, b, "back_design"))
			for b: Vector2 in [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]:
				bc.append(await _tile(looks[name], false, 0.0, 1, b, "arms"))
			_save_sheet(bc, 3, "sheet_%s_build_close.png" % name)
		if name == "fullest" or only != "":
			var extra: Array = []
			for b: Vector2 in [Vector2(-1, -1), Vector2(1, 1)]:
				for yaw: float in [20.0, 180.0]:
					extra.append(await _tile(looks[name], true, yaw, 1, b))
			for yaw: float in [0.0, 180.0]:
				extra.append(await _tile(looks[name], true, yaw, 6, Vector2.ZERO, "game"))
			_save_sheet(extra, 3, "sheet_%s_build_stage.png" % name)
	print(PREFIX + JSON.stringify({"review": _out}))
	get_tree().quit(0)


func _tile(record: Dictionary, world: bool, yaw: float, stage: int, build: Vector2, framing := "full") -> Image:
	var r := record.duplicate(true)
	r.build = {"brawn": build.x, "girth": build.y}
	_p.world_light = world
	_p.set_game_profile(GiantPreview.stage_profile(stage))
	_p.apply_look(Appearance.to_look(r))
	_p.frame(framing)
	_p.turn(yaw)
	return await _draw_frame()


func _save_sheet(tiles: Array, cols: int, file: String) -> void:
	if _out == "" or tiles.is_empty():
		return
	var tw := (tiles[0] as Image).get_width()
	var th := (tiles[0] as Image).get_height()
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(tw * cols, th * rows, false, (tiles[0] as Image).get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	sheet.save_png(_out.path_join(file))
