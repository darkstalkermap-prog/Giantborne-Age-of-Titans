extends Node
## The giant beyond 120 m, rendered (the second W33 look lane; plan M11 §2.12: "at most 4,000 primitives beyond 120 m"):
## tests/gate/test_giant_far_render.gd runs this scene (tests/support/giant_far_probe.tscn) in a child Godot under Xvfb
## at 1920x1080 (the Compatibility renderer, two llvmpipe threads):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --audio-driver Dummy res://tests/support/giant_far_probe.tscn [-- --out=/abs/folder]
##
## GiantPreview at the window's size (the levels follow the pixels) in the world's light at stage 1 shows the Wanderer
## and the fullest look of the data (the outfit that fills the most slots, an accessory in every accessory slot: the
## wardrobe budget probe's) from three-quarters in front, at DISTANCES from the giant's middle. Per look and distance
## the giant's own primitives in the main pass (the frame with the model less the frame without it), and at 121 m and
## 151 m the giant's silhouette at its levels against the same frame at full detail (every mesh's lod_bias raised so
## the renderer keeps level 0): the pixels either covers ("pixels", "full_pixels") and the share both cover ("overlap").
## One line:
##   GIANT_FAR {"looks": {name: {"primitives": {m: n}, "silhouette": {m: {"pixels", "full_pixels", "overlap"}}}},
##              "size", "adapter"}

const PREFIX := "GIANT_FAR "
const DISTANCES := [60.0, 121.0, 130.0, 151.0, 200.0]
const COMPARED := [121.0, 151.0]
const WATCHDOG_S := 200.0
## A pixel is the giant's when it differs from the frame without him by more than this (sum over the channels).
const SEEN := 0.12

var _p: GiantPreview
var _out := ""


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the probe timed out"}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	var size := DisplayServer.window_get_size()
	_p = GiantPreview.new()
	_p.still = true
	_p.stretch = false
	_p.custom_minimum_size = Vector2(size)
	_p.size = Vector2(size)
	add_child(_p)
	_p.viewport.size = size
	_p.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _draw_frame() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return _p.viewport.get_texture().get_image()


## The fullest look of the data: the outfit that fills the most slots, the first accessory of every accessory slot.
static func fullest(base: Dictionary) -> Dictionary:
	var best := ""
	var most := -1
	for id in Appearance.option_ids("outfit"):
		var n := Appearance.record_garments(Appearance.with_outfit(base, id)).size()
		if n > most:
			most = n
			best = id
	var rec := Appearance.with_outfit(base, best)
	for slot: String in Appearance.ACCESSORY_SLOTS:
		for id in Appearance.option_ids("accessory"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				rec = OptionRows.with_value(rec, "outfit.accessories." + slot, id)
				break
	return rec


## The camera `d` metres from the giant's middle, three-quarter from the front, looking at him.
func _at_distance(d: float) -> void:
	_p.frame("full")
	_p.camera.far = 4000.0
	var target := Vector3(0.0, 1.85, 0.0)
	var dir := (_p.camera.position - target).normalized()
	_p.camera.position = target + dir * d
	_p.camera.look_at(target, Vector3.UP)


func _primitives() -> int:
	var rid := _p.viewport.get_viewport_rid()
	await _draw_frame()
	var with_model := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	_p.model.visible = false
	await _draw_frame()
	var without := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	_p.model.visible = true
	return with_model - without


func _lod_bias(bias: float) -> void:
	for mi: MeshInstance3D in _p.model.find_children("*", "MeshInstance3D", true, false):
		mi.lod_bias = bias


func _silhouette(name: String, d: float) -> Dictionary:
	_p.model.visible = false
	var bg: Image = await _draw_frame()
	_p.model.visible = true
	var far: Image = await _draw_frame()
	_lod_bias(100000.0)
	var full: Image = await _draw_frame()
	_lod_bias(1.0)
	var cx := bg.get_width() / 2
	var cy := bg.get_height() / 2
	var r := Rect2i(cx - 96, cy - 96, 192, 192)
	var a := 0
	var b := 0
	var both := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var k := bg.get_pixel(x, y)
			var in_far := _d(far.get_pixel(x, y), k) > SEEN
			var in_full := _d(full.get_pixel(x, y), k) > SEEN
			a += int(in_far)
			b += int(in_full)
			both += int(in_far and in_full)
	if _out != "":
		far.get_region(r).save_png(_out.path_join("far_%s_%d.png" % [name, int(d)]))
		full.get_region(r).save_png(_out.path_join("far_%s_%d_full.png" % [name, int(d)]))
	return {"pixels": a, "full_pixels": b, "overlap": float(both) / maxf(1.0, float(maxi(a, b)))}


static func _d(p: Color, q: Color) -> float:
	return absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)


func _run() -> void:
	var report := {"looks": {}, "size": [_p.viewport.size.x, _p.viewport.size.y],
		"adapter": RenderingServer.get_video_adapter_name()}
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var wanderer := Appearance.preset_record("appearance_preset.wanderer")
	for look: Array in [["wanderer", wanderer], ["fullest", fullest(wanderer)]]:
		_p.apply_look(Appearance.to_look(look[1]))
		var prims := {}
		var sil := {}
		for d: float in DISTANCES:
			_at_distance(d)
			prims[str(int(d))] = await _primitives()
			if d in COMPARED:
				sil[str(int(d))] = await _silhouette(look[0], d)
		report.looks[look[0]] = {"primitives": prims, "silhouette": sil}
	print(PREFIX + JSON.stringify(report))
	get_tree().quit(0)
