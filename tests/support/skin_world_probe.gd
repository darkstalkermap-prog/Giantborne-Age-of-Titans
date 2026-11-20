extends Node
## The skin in the world's light (Gate A; docs/systems/P51.md "Gate A"): GiantPreview in the world's sun, sky and
## ambient (world_light) draws the skin alone (garments, hair, beard and eyes hidden; the body's sunk regions stay)
## for a few looks at the face and full framings, and the frame without the giant; the pixels that differ are skin.
## Per look and framing it reports:
##   * white: the share of the skin's lit pixels (the brightest 30 %) that are near white (the channels' spread under
##     WHITE_SPREAD of the brightest): W30's sunlit skin read like snow;
##   * step: the share of skin pixels whose luminance jumps by more than STEP_JUMP to a skin neighbour (a hard,
##     ragged terminator; a shadow's edge counts too, but the hair and beard that cast most are hidden);
##   * shade_warm: the mean red minus blue (0-255) of the darkest 15 % of the skin: the shaded side's warmth.
## It also draws first person (GiantPreview's FIRST_PERSON framing: the torso and head layers culled) with and without
## the giant and reports `fp_shadow`, the share of the frame's ground the giant darkens (W29 put the shadow proxy on
## the head's layer, and the camera's cull mask culled its shadow).
## Gate A2: the shell hair in the world's light. For five looks (dark, greying, red, fair and grey hair) it draws a
## shell style (the crop, the short beard) and the same look with a card style in its place (the long back hair, the
## full beard), each with and without the style; the pixels that differ are hair. `shells` reports per case the
## shell's mean colour (sRGB), the card's (W33frame: in the shell's own pixels; card_all: the whole card style's), and
## the shell's luminance spread (the 90th less the 10th percentile): at
## m11-gate-a the black short beard drew one flat black and the greying crop near black with sparse white specks.
## Prints one line "SKIN_WORLD <json>" and quits. tests/slow/test_skin_world_render.gd runs it in a child:
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/skin_world_probe.tscn [-- --out=/abs/folder]

const PREFIX := "SKIN_WORLD "
const TILE := Vector2i(320, 240)
const LOOKS := ["wanderer", "storm_herald", "iron_veteran"]
const FRAMINGS := ["face", "full"]
const WATCHDOG_S := 120.0
## A pixel is skin when its channels differ from the frame without the giant by this much (sum, 0-765).
const SKIN_DIFF := 30
const WHITE_SPREAD := 0.2
const STEP_JUMP := 40.0
const LIT_SHARE := 0.3
const SHADE_SHARE := 0.15
## The shell cases (Gate A2): the look, the slot, the shell style, the card style it is compared with, the framing.
const SHELL_CASES := [
	{"name": "storm_herald_beard", "preset": "storm_herald", "slot": "beard_mesh", "shell": "Beard_short", "card": "Beard_full", "framing": "face"},
	{"name": "iron_veteran_crop", "preset": "iron_veteran", "slot": "hair_mesh", "shell": "Hair_crop", "card": "Hair_long_back", "framing": "hair"},
	{"name": "chieftain_beard", "preset": "northern_chieftain", "slot": "beard_mesh", "shell": "Beard_short", "card": "Beard_full", "framing": "face"},
	{"name": "young_giant_crop", "preset": "young_giant", "slot": "hair_mesh", "shell": "Hair_crop", "card": "Hair_long_back", "framing": "hair"},
	{"name": "stone_elder_beard", "preset": "stone_elder", "slot": "beard_mesh", "shell": "Beard_short", "card": "Beard_full", "framing": "face"},
]
## A ground pixel is in the giant's shadow when it is darker than without him by this much (sum, 0-765).
const SHADOW_DIFF := 30

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
	_p = GiantPreview.new()
	_p.still = true
	_p.stretch = false
	_p.custom_minimum_size = Vector2(TILE)
	_p.size = Vector2(TILE)
	add_child(_p)
	_p.viewport.size = TILE
	_p.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _draw_frame() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	return _p.viewport.get_texture().get_image()


func _meshes() -> Array:
	return _p.model.find_children("*", "MeshInstance3D", true, false) if _p.model != null else []


## Shows only the body's skin meshes (true) or the look as applied (false).
func _skin_only(on: bool, shown: Dictionary) -> void:
	for mi: MeshInstance3D in _meshes():
		if on:
			shown[mi] = mi.visible
			if not str(mi.name).begins_with("Body_") and mi.name != RigPaint.SHADOW_PROXY:
				mi.visible = false
		elif shown.has(mi):
			mi.visible = shown[mi]


func _save(img: Image, name: String) -> void:
	if _out != "":
		img.save_png(_out.path_join(name + ".png"))


func _run() -> void:
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "looks": {}}
	_p.world_light = true
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var empty := {}
	for look_id: String in LOOKS:
		_p.apply_look(Appearance.to_look(Appearance.preset_record("appearance_preset." + look_id)))
		var per := {}
		for f: String in FRAMINGS:
			_p.frame(f)
			if not empty.has(f):
				_p.model.visible = false
				empty[f] = await _draw_frame()
				_p.model.visible = true
			var shown := {}
			_skin_only(true, shown)
			var img: Image = await _draw_frame()
			_skin_only(false, shown)
			_save(img, "%s_%s" % [look_id, f])
			per[f] = measure(img, empty[f])
		report.looks[look_id] = per
	report["shells"] = await _shells()
	_p.apply_look(Appearance.to_look(Appearance.preset_record("appearance_preset.wanderer")))
	_p.frame(GiantPreview.FIRST_PERSON)
	var with_giant: Image = await _draw_frame()
	_p.model.visible = false
	var without: Image = await _draw_frame()
	_p.model.visible = true
	_save(with_giant, "first_person")
	report["fp_shadow"] = shadow_share(with_giant, without)
	print(PREFIX + JSON.stringify(report))
	get_tree().quit(0)


## The shell cases: each style's hair pixels (the frame against the same frame with the style hidden).
func _shells() -> Dictionary:
	var out := {}
	for c: Dictionary in SHELL_CASES:
		var per := {}
		var shell_px := PackedByteArray()
		for kind: String in ["shell", "card"]:
			var look := Appearance.to_look(Appearance.preset_record("appearance_preset." + str(c.preset)))
			look[str(c.slot)] = str(c[kind])
			_p.apply_look(look)
			_p.frame(str(c.framing))
			var mi := GiantLook.mesh_node(_p.model, _p.model.index, str(c[kind]))
			if mi == null:
				per[kind] = {"pixels": 0}
				continue
			var img: Image = await _draw_frame()
			mi.visible = false
			var without: Image = await _draw_frame()
			mi.visible = true
			if kind == "shell":
				_save(img, "shell_" + str(c.name))
				per[kind] = hair_measure(img, without)
				shell_px = hair_mask(img, without)
			else:
				# W33frame: the card style's colour where the shell draws too (like with like): the card beards grew with
				# the reproportioned head (W33body), and their longer tips over the lit chest lightened the card's mean
				# (the Northern Chieftain's blue 34.8 to 37.1) while in the shell's own area it held (31.4 to 31.1);
				# the whole style's reading stays in card_all
				per["card_all"] = hair_measure(img, without)
				per[kind] = hair_measure(img, without, shell_px)
		out[str(c.name)] = per
	return out


## The mask (1 a pixel) of the pixels of `img` that differ from `without` (a style's hair pixels).
static func hair_mask(img: Image, without: Image) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(img.get_width() * img.get_height())
	for y in img.get_height():
		for x in img.get_width():
			var a := _px(img, x, y)
			var b := _px(without, x, y)
			if absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) > SKIN_DIFF:
				m[y * img.get_width() + x] = 1
	return m


## The hair's pixels of `img` against `without`: their count, mean colour (sRGB 0-255) and luminance's 10th and 90th
## percentiles; with `within` (a hair_mask) only the pixels in it.
static func hair_measure(img: Image, without: Image, within := PackedByteArray()) -> Dictionary:
	var sum := Vector3.ZERO
	var lums := PackedFloat32Array()
	for y in img.get_height():
		for x in img.get_width():
			if not within.is_empty() and within[y * img.get_width() + x] == 0:
				continue
			var a := _px(img, x, y)
			var b := _px(without, x, y)
			if absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) > SKIN_DIFF:
				sum += a
				lums.append(a.dot(Vector3(0.2126, 0.7152, 0.0722)))
	var n := lums.size()
	if n < 50:
		return {"pixels": n}
	lums.sort()
	var mean := sum / n
	return {"pixels": n, "rgb": [mean.x, mean.y, mean.z], "lum": mean.dot(Vector3(0.2126, 0.7152, 0.0722)),
		"p10": lums[int(n * 0.1)], "p90": lums[int(n * 0.9)]}


static func _px(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(c.r, c.g, c.b) * 255.0


## The measures of one frame of the skin against the frame without the giant.
static func measure(img: Image, empty: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var skin := PackedByteArray()
	skin.resize(w * h)
	var cols: Array[Vector3] = []
	var lums: Array[float] = []
	for y in h:
		for x in w:
			var a := _px(img, x, y)
			var b := _px(empty, x, y)
			var i := y * w + x
			lum[i] = a.dot(Vector3(0.2126, 0.7152, 0.0722))
			if absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) > SKIN_DIFF:
				skin[i] = 1
				cols.append(a)
				lums.append(lum[i])
	var n := cols.size()
	if n < 50:
		return {"pixels": n}
	var sorted := lums.duplicate()
	sorted.sort()
	var lit_floor: float = sorted[int(n * (1.0 - LIT_SHARE))]
	var shade_ceil: float = sorted[int(n * SHADE_SHARE)]
	var lit := 0
	var white := 0
	var shade := 0
	var warm := 0.0
	for k in n:
		var c := cols[k]
		if lums[k] >= lit_floor:
			lit += 1
			var hi := maxf(c.x, maxf(c.y, c.z))
			if hi > 0.0 and (hi - minf(c.x, minf(c.y, c.z))) / hi < WHITE_SPREAD:
				white += 1
		if lums[k] <= shade_ceil:
			shade += 1
			warm += c.x - c.z
	var steps := 0
	for y in h - 1:
		for x in w - 1:
			var i := y * w + x
			if skin[i] == 0:
				continue
			var j := 0.0
			if skin[i + 1] == 1:
				j = maxf(j, absf(lum[i + 1] - lum[i]))
			if skin[i + w] == 1:
				j = maxf(j, absf(lum[i + w] - lum[i]))
			if j > STEP_JUMP:
				steps += 1
	return {"pixels": n, "white": float(white) / maxf(lit, 1), "step": float(steps) / n,
		"shade_warm": warm / maxf(shade, 1)}


## The share of the frame's pixels the giant darkens (his shadow on the ground; his own drawn pixels are lighter or
## differently coloured, not darker green).
static func shadow_share(with_giant: Image, without: Image) -> float:
	var dark := 0
	var total := with_giant.get_width() * with_giant.get_height()
	for y in with_giant.get_height():
		for x in with_giant.get_width():
			var a := _px(with_giant, x, y)
			var b := _px(without, x, y)
			var green := a.y >= a.x and a.y >= a.z
			if green and (b.x + b.y + b.z) - (a.x + a.y + a.z) > SHADOW_DIFF:
				dark += 1
	return float(dark) / total
