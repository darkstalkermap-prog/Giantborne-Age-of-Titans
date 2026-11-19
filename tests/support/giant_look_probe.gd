extends Node
## The giant's look, measured against frames (P51; plan M11 §2.13, §3.4): tests/gate/test_skin_tone_render.gd and
## tests/gate/test_hair_render.gd run this scene (a main scene, so the autoloads exist: Appearance reads GameData)
## once in a child Godot under Xvfb with the Compatibility renderer (GiantLookProbeRun shares that one run between
## the suites), and the package's before and after captures use it with `--show`:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/giant_look_probe.tscn -- --giant-tier=web \
##     [--show --out=/absolute/folder] [--only=skin,hair,beard,eyes,designs,draws]
##
## Every tile is a GiantPreview (the creator's framings and light; `still`, so every tile has one pose) of 320x240,
## MSAA off. It measures:
##   skin     the default look's lit chest in the creator's light (the chest framing): the mean sRGB of a patch
##            round the right pectoral's projection, against the approved studio render's (198, 170, 157)
##   hair     every hair style at the Face and Hair framings with and without its mesh: the hair's pixels (those
##            that differ; the skin under it untinted), the outline's roughness (the perimeter of the filled hair
##            region over the perimeter of the same region opened and closed by OPEN_PX: higher is a more broken,
##            strand-like edge) and the scalp share (of the skin the style grows on - the pixels its tint changes
##            without the style - the share that still shows through: lower is denser); the same for every
##            beard at the Face framing, and a beard's pixels seen from straight behind the head
##   eyes     at the eye close-up: the brightest pixels (the cornea's highlight), and the pixels the eye's
##            `look` moves when it is set to (0.25, 0) (0 while the shader has no `look`)
##   designs  every scar and ancestry mark in the stage-1 rear Game view and in first person against the base
##            (the option check's views and rule), in pixels of the 320x240 tile
##   draws    the giant's draw calls (visible and shadow passes) in the creator's Full framing for every hair
##            and beard style, against the stage with the model hidden
## Prints one line
##   GIANT_LOOK {"skin": {...}, "hair": {style: {framing: {px, rough, scalp}}}, "beard": {...}, "eyes": {...},
##               "designs": {id: {rear, fp}}, "draws": {...}, "validate": [...], "ms", "adapter", "tier"}
## and quits. With --show it also draws the showcase (SHOW looks x SHOW_FRAMINGS at 720x540) into --out (default
## user://m11_frames/P51/): <look>_<framing>.png and one <look>.png strip each, the frames the system doc names.

const PREFIX := "GIANT_LOOK "
const OUT_DIR := "user://m11_frames/P51/"
const TILE := Vector2i(320, 240)
const SHOW_TILE := Vector2i(720, 540)
const POOL := 8
const WATCHDOG_S := 300.0
## A pixel differs when its channels move this much together (0-3 scale; the option check's rule).
const DIFF := 0.08
## The outline's smoothing radius for the roughness (pixels of the 320x240 tile).
const OPEN_PX := 2
## The approved studio render's lit chest (sRGB 0-255; docs/systems/P46.md, "OR-1").
const APPROVED_CHEST := [198, 170, 157]
## The chest patch: a model-space point on the lit right pectoral at stage 1 (+X his right, -Z his front) and the
## patch's half size in pixels of the tile.
const CHEST_POINT := Vector3(0.2, 2.78, -0.3)
const CHEST_HALF := Vector2i(10, 8)
const EYE_LOOK := Vector2(0.25, 0.0)
## A pixel of the eye close-up counts as highlight when every channel is at least this.
const HIGHLIGHT := 0.8
const SHOW_FRAMINGS := ["face", "full", "back", "hair"]
## The creator's framings a scar or mark can be framed in (the option check's region framings).
const DESIGN_FRAMINGS := ["face", "chest", "arms", "hand", "hand_l", "back_design", "full"]

var _pool: Array[GiantPreview] = []
var _stage1: Dictionary = {}
var _validate := PackedStringArray()
var _images := {}
var _draws := {}
var _out := OUT_DIR
var _only := PackedStringArray()
var _show := false
var _frames := 0


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the probe timed out"}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",", false)
		elif arg == "--show":
			_show = true
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out if _out.is_absolute_path() else ProjectSettings.globalize_path(_out))
	_stage1 = GiantPreview.stage_profile(1)
	var holder := Control.new()
	holder.name = "Tiles"
	add_child(holder)
	for i in POOL:
		var p := GiantPreview.new()
		p.still = true
		p.viewport.msaa_3d = Viewport.MSAA_DISABLED
		holder.add_child(p)
		_pool.append(p)
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wants(part: String) -> bool:
	return _only.is_empty() or part in _only


# --------------------------------------------------------------------------- the looks

## The base record of the measurements (the default look, no mark, "custom").
static func base_record() -> Dictionary:
	var base := Appearance.default_record()
	base["mark"] = Appearance.MARK_NONE
	base["preset"] = ""
	return base


## The base look with `changes` put over it (look keys: hair_mesh, beard_mesh, ...).
static func look_with(changes: Dictionary) -> Dictionary:
	var l := Appearance.to_look(base_record())
	for k: Variant in changes:
		l[k] = changes[k]
	return l


## The showcase's looks: {name: look}.
static func show_looks() -> Dictionary:
	var out := {}
	out["wanderer"] = Appearance.to_look(Appearance.preset_record("appearance_preset.wanderer"))
	out["chieftain"] = Appearance.to_look(Appearance.preset_record("appearance_preset.northern_chieftain"))
	out["crop"] = look_with({"hair_mesh": "Hair_crop", "beard_mesh": "Beard_short", "beard_tint": 0.85})
	out["braids"] = look_with({"hair_mesh": "Hair_long_braided", "beard_mesh": "Beard_braided"})
	return out


## Every tile to draw: {key, look, framing, turn, size, eye_look (Vector2, optional), hide_model (optional)}.
func jobs() -> Array:
	var out: Array = []
	var model: GiantModel = _pool[0].model
	var index := model.index
	if _wants("skin"):
		out.append({"key": "skin.chest", "look": look_with({}), "framing": "chest"})
	if _wants("hair"):
		for f: String in ["face", "hair"]:
			# the skin under the hair untinted, in both frames: where the head shows through, it is bare skin
			out.append({"key": "hair.none@" + f, "look": look_with({"hair_mesh": "", "scalp_tint": 0.0}), "framing": f})
			out.append({"key": "hair.tinted@" + f, "look": look_with({"hair_mesh": "", "scalp_tint": 1.0}), "framing": f})
			for id in GiantLook.meshes_of(index, "hair"):
				out.append({"key": "hair.%s@%s" % [id, f], "look": look_with({"hair_mesh": id, "scalp_tint": 0.0}), "framing": f})
	if _wants("beard"):
		# the beard's own frames: no hair, so the hair's cards do not hide the jaw seen from behind
		out.append({"key": "beard.none@face", "look": look_with({"hair_mesh": "", "beard_mesh": "", "beard_tint": 0.0, "stubble": 0.0}), "framing": "face"})
		out.append({"key": "beard.tinted@face", "look": look_with({"hair_mesh": "", "beard_mesh": "", "beard_tint": 1.0, "stubble": 1.0}),
			"framing": "face"})
		out.append({"key": "beard.none@behind", "look": look_with({"hair_mesh": "", "beard_mesh": "", "beard_tint": 0.0, "stubble": 0.0}), "framing": "hair",
			"turn": 40.0})
		for id in GiantLook.meshes_of(index, "beard"):
			out.append({"key": "beard.%s@face" % id, "look": look_with({"hair_mesh": "", "beard_mesh": id, "beard_tint": 0.0, "stubble": 0.0}), "framing": "face"})
			out.append({"key": "beard.%s@behind" % id, "look": look_with({"hair_mesh": "", "beard_mesh": id, "beard_tint": 0.0, "stubble": 0.0}),
				"framing": "hair", "turn": 40.0})
	if _wants("eyes"):
		out.append({"key": "eyes.ahead", "look": look_with({}), "framing": "eyes", "eye_look": Vector2.ZERO})
		out.append({"key": "eyes.aside", "look": look_with({}), "framing": "eyes", "eye_look": EYE_LOOK})
	if _wants("designs"):
		var base := base_record()
		out.append({"key": "design.base@rear", "look": Appearance.to_look(base), "framing": "game"})
		for f: String in DESIGN_FRAMINGS:
			out.append({"key": "design.base@" + f, "look": Appearance.to_look(base), "framing": f})
		out.append({"key": "design.base@fp", "look": Appearance.to_look(base), "framing": GiantPreview.FIRST_PERSON})
		for id in Appearance.option_ids("scar"):
			var rec := OptionRows.with_scar(base, id, true)
			out.append({"key": "design.%s@rear" % id, "look": Appearance.to_look(rec), "framing": "game"})
			out.append({"key": "design.%s@fp" % id, "look": Appearance.to_look(rec), "framing": GiantPreview.FIRST_PERSON})
			out.append({"key": "design.%s@%s" % [id, _framing_of(id, "")], "look": Appearance.to_look(rec),
				"framing": _framing_of(id, "")})
		for id in Appearance.option_ids("mark"):
			var o := Appearance.option(id)
			var line := Appearance.required_ancestry(o)
			var rec := OptionRows.with_value(base, "mark", Appearance.MARK_AUTO)
			out.append({"key": "design.%s@rear" % id, "look": Appearance.to_look(rec, line), "framing": "game"})
			out.append({"key": "design.%s@fp" % id, "look": Appearance.to_look(rec, line), "framing": GiantPreview.FIRST_PERSON})
			out.append({"key": "design.%s@%s" % [id, _framing_of(id, line)], "look": Appearance.to_look(rec, line),
				"framing": _framing_of(id, line)})
	if _wants("draws"):
		out.append({"key": "draws.empty", "look": look_with({}), "framing": "full", "hide_model": true})
		out.append({"key": "draws.default", "look": look_with({}), "framing": "full"})
		for id in GiantLook.meshes_of(index, "hair"):
			out.append({"key": "draws." + id, "look": look_with({"hair_mesh": id, "beard_mesh": ""}), "framing": "full"})
		for id in GiantLook.meshes_of(index, "beard"):
			out.append({"key": "draws." + id, "look": look_with({"hair_mesh": "", "beard_mesh": id, "beard_tint": 0.0, "stubble": 0.0}), "framing": "full"})
		out.append({"key": "draws.bare", "look": look_with({"hair_mesh": "", "beard_mesh": "", "beard_tint": 0.0, "stubble": 0.0}), "framing": "full"})
	if _show:
		var looks := show_looks()
		for name: String in looks:
			for f: String in SHOW_FRAMINGS:
				out.append({"key": "show.%s_%s" % [name, f], "look": looks[name], "framing": f, "size": SHOW_TILE})
			out.append({"key": "show.%s_eyes" % name, "look": looks[name], "framing": "eyes", "size": SHOW_TILE})
		out.append({"key": "show.wanderer_game", "look": looks.wanderer, "framing": "game", "size": SHOW_TILE})
		out.append({"key": "show.wanderer_game_back", "look": looks.wanderer, "framing": "game", "turn": 180.0,
			"size": SHOW_TILE})
	return out


## The creator's framing of a scar or mark option (its design's first region; the option check's rule).
func _framing_of(option_id: String, line: String) -> String:
	var o := Appearance.option(option_id)
	var cat := option_id.get_slice(".", 0)
	var spec := {"key": "scar.x" if cat == "scar" else "mark", "id": "%s.%s" % [cat, str(o.get("key", ""))]}
	var f := GiantPreview.region_framing(OptionRows.row_region(spec, {}, _pool[0].model.index, line))
	return f if f in DESIGN_FRAMINGS else "full"


# --------------------------------------------------------------------------- drawing

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var all := jobs()
	var i := 0
	while i < all.size():
		var batch: Array = all.slice(i, i + POOL)
		for k in POOL:
			var p := _pool[k]
			p.visible = k < batch.size()
			if k < batch.size():
				_set_up(p, batch[k])
		for f in (3 if _frames == 0 else 2):
			await RenderingServer.frame_post_draw
		_frames += 1
		for k in batch.size():
			var job: Dictionary = batch[k]
			var img := _pool[k].viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			_images[job.key] = img
			var rid := _pool[k].viewport.get_viewport_rid()
			_draws[job.key] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME) + RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			if str(job.key).begins_with("show.") or not _show:
				img.save_png(_abs(_out + str(job.key).trim_prefix("show.") + ".png"))
			if job.has("chest_px"):
				_images[str(job.key) + "#chest_px"] = job.chest_px
		i += POOL
	var out := {"ms": Time.get_ticks_msec() - t0, "validate": Array(_validate),
		"adapter": RenderingServer.get_video_adapter_name(), "tier": GiantLook.built_tier(_pool[0].model)}
	out.merge(_measure(all), true)
	if _show:
		_strips()
	print(PREFIX + JSON.stringify(out))
	get_tree().quit(0)


func _abs(path: String) -> String:
	return path if path.is_absolute_path() else ProjectSettings.globalize_path(path)


func _set_up(p: GiantPreview, job: Dictionary) -> void:
	var size: Vector2i = job.get("size", TILE)
	p.custom_minimum_size = Vector2(size)
	p.size = Vector2(size)
	p.set_game_profile(_stage1)
	p.apply_look(job.look)
	p.frame(str(job.framing))
	if float(job.get("turn", 0.0)) != 0.0:
		p.turn(float(job.turn))
	p.model.visible = not bool(job.get("hide_model", false))
	var eyes := p.model.mesh("Eyes")
	if eyes != null and eyes.material_override is ShaderMaterial:
		var mat := eyes.material_override as ShaderMaterial
		if GiantLook.undeclared_uniforms(mat.shader, ["look"]).is_empty():
			mat.set_shader_parameter("look", job.get("eye_look", Vector2.ZERO))
	for problem in GiantLook.validate(p.model, p.index(), job.look):
		if not _validate.has(problem):
			_validate.append(problem)
	if str(job.key) == "skin.chest":
		var world := p.model.global_transform * CHEST_POINT
		job["chest_px"] = p.camera.unproject_position(world) * Vector2(size) / p.viewport.get_visible_rect().size
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


# --------------------------------------------------------------------------- the measures

func _measure(all: Array) -> Dictionary:
	var out := {}
	if _images.has("skin.chest"):
		var c: Vector2 = _images.get("skin.chest#chest_px", Vector2(TILE) * 0.5)
		var mean := patch_mean(_images["skin.chest"], Vector2i(c), CHEST_HALF)
		var d := 0
		for ch in 3:
			d = maxi(d, absi(int(mean[ch]) - int(APPROVED_CHEST[ch])))
		out["skin"] = {"chest": mean, "approved": APPROVED_CHEST, "max_channel_diff": d, "at": [int(c.x), int(c.y)]}
	var hair := {}
	var beard := {}
	for job: Dictionary in all:
		var key := str(job.key)
		if key.begins_with("hair.") and not key.begins_with("hair.none") and not key.begins_with("hair.tinted"):
			var id := key.get_slice("@", 0).substr(5)
			var f := key.get_slice("@", 1)
			var m := hair_measures(_images[key], _images["hair.none@" + f], _images["hair.tinted@" + f])
			var row: Dictionary = hair.get(id, {})
			row[f] = m
			hair[id] = row
		elif key.begins_with("beard.") and not key.begins_with("beard.none") and not key.begins_with("beard.tinted"):
			var id := key.get_slice("@", 0).substr(6)
			var f := key.get_slice("@", 1)
			var row: Dictionary = beard.get(id, {})
			if f == "behind":
				row[f] = {"px": changed_px(_images[key], _images["beard.none@behind"])}
			else:
				row[f] = hair_measures(_images[key], _images["beard.none@" + f], _images["beard.tinted@" + f])
			beard[id] = row
	if not hair.is_empty():
		out["hair"] = hair
	if not beard.is_empty():
		out["beard"] = beard
	if _images.has("eyes.ahead"):
		out["eyes"] = {"highlight_px": bright_px(_images["eyes.ahead"], HIGHLIGHT),
			"look_px": changed_px(_images["eyes.aside"], _images["eyes.ahead"])}
	var designs := {}
	for job: Dictionary in all:
		var key := str(job.key)
		if key.begins_with("design.") and not key.begins_with("design.base"):
			var id := key.get_slice("@", 0).substr(7)
			var v := key.get_slice("@", 1)
			var row: Dictionary = designs.get(id, {})
			var px := changed_px(_images[key], _images["design.base@" + v])
			if v in ["rear", "fp"]:
				row[v] = px
			else:
				row["framed"] = px
				row["framing"] = v
			designs[id] = row
	if not designs.is_empty():
		out["designs"] = designs
	if _draws.has("draws.empty"):
		var empty := int(_draws["draws.empty"])
		var d := {}
		for key: Variant in _draws:
			if str(key).begins_with("draws.") and key != "draws.empty":
				d[str(key).substr(6)] = int(_draws[key]) - empty
		out["draws"] = d
	return out


## The mean sRGB (0-255) of the patch of half size `half` round `c`.
static func patch_mean(img: Image, c: Vector2i, half: Vector2i) -> Array:
	var s := [0.0, 0.0, 0.0]
	var n := 0
	for y in range(maxi(0, c.y - half.y), mini(img.get_height(), c.y + half.y)):
		for x in range(maxi(0, c.x - half.x), mini(img.get_width(), c.x + half.x)):
			var p := img.get_pixel(x, y)
			s[0] += p.r
			s[1] += p.g
			s[2] += p.b
			n += 1
	return [int(round(255.0 * s[0] / maxf(1, n))), int(round(255.0 * s[1] / maxf(1, n))), int(round(255.0 * s[2] / maxf(1, n)))]


## The mask (1 a pixel) of the pixels where two images differ.
static func diff_mask(a: Image, b: Image) -> PackedByteArray:
	var w := a.get_width()
	var h := a.get_height()
	var m := PackedByteArray()
	m.resize(w * h)
	var da := a.get_data()
	var db := b.get_data()
	var t := int(DIFF * 255.0)
	for i in w * h:
		var o := i * 3
		if absi(da[o] - db[o]) + absi(da[o + 1] - db[o + 1]) + absi(da[o + 2] - db[o + 2]) > t:
			m[i] = 1
	return m


static func changed_px(a: Image, b: Image) -> int:
	var m := diff_mask(a, b)
	var n := 0
	for v in m:
		n += v
	return n


## Pixels whose every channel is at least `level` (0-1).
static func bright_px(img: Image, level: float) -> int:
	var d := img.get_data()
	var t := int(level * 255.0)
	var n := 0
	for i in range(0, d.size(), 3):
		if d[i] >= t and d[i + 1] >= t and d[i + 2] >= t:
			n += 1
	return n


## {px, rough, scalp} of a style drawn (`with`, the skin under it untinted) against the same frame without it
## (`without`) and without it with the skin's hair tint (`tinted`: the tint marks the skin the style grows on).
## px: the style's pixels; rough: its filled outline's perimeter over the same outline opened and closed by
## OPEN_PX; scalp: the share of the growing skin in view that still shows through the style (unchanged pixels).
static func hair_measures(with: Image, without: Image, tinted: Image) -> Dictionary:
	var w := with.get_width()
	var h := with.get_height()
	var m := diff_mask(with, without)
	var grow := diff_mask(tinted, without)
	var px := 0
	var area := 0
	var bare := 0
	for i in m.size():
		px += m[i]
		if grow[i] == 1:
			area += 1
			if m[i] == 0:
				bare += 1
	if px == 0:
		return {"px": 0, "rough": 0.0, "scalp": 1.0}
	var filled := fill_holes(m, w, h)
	var smooth := dilate(erode(erode(dilate(filled, w, h, OPEN_PX), w, h, OPEN_PX), w, h, OPEN_PX), w, h, OPEN_PX)
	var rough := float(perimeter(filled, w, h)) / maxf(1.0, float(perimeter(smooth, w, h)))
	return {"px": px, "rough": snappedf(rough, 0.0001), "scalp": snappedf(float(bare) / maxf(1.0, float(area)), 0.0001),
		"skin_px": area}


## The mask with every hole (a 0 region that does not reach the border) filled.
static func fill_holes(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if outside[i] == 1 or m[i] == 1:
			continue
		outside[i] = 1
		var x := i % w
		var y := i / w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 - outside[i]
	return out


## The pixels of the mask with a 4-neighbour outside it.
static func perimeter(m: PackedByteArray, w: int, h: int) -> int:
	var n := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if m[i] == 0:
				continue
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 or m[i - 1] == 0 or m[i + 1] == 0 or m[i - w] == 0 or m[i + w] == 0:
				n += 1
	return n


## A square erosion or dilation by `r` pixels (separable: rows, then columns).
static func _morph(m: PackedByteArray, w: int, h: int, r: int, grow: bool) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	for y in h:
		for x in w:
			var v := 0 if grow else 1
			for k in range(-r, r + 1):
				var xx := clampi(x + k, 0, w - 1)
				if grow and m[y * w + xx] == 1:
					v = 1
					break
				if not grow and m[y * w + xx] == 0:
					v = 0
					break
			tmp[y * w + x] = v
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var v := 0 if grow else 1
			for k in range(-r, r + 1):
				var yy := clampi(y + k, 0, h - 1)
				if grow and tmp[yy * w + x] == 1:
					v = 1
					break
				if not grow and tmp[yy * w + x] == 0:
					v = 0
					break
			out[y * w + x] = v
	return out


static func erode(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _morph(m, w, h, r, false)


static func dilate(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _morph(m, w, h, r, true)


# --------------------------------------------------------------------------- the showcase strips

## One strip a showcase look: its framings side by side (720x540 each).
func _strips() -> void:
	for name: String in show_looks():
		var strip := Image.create(SHOW_TILE.x * SHOW_FRAMINGS.size(), SHOW_TILE.y, false, Image.FORMAT_RGB8)
		for k in SHOW_FRAMINGS.size():
			var img: Image = _images.get("show.%s_%s" % [name, SHOW_FRAMINGS[k]])
			if img != null:
				strip.blit_rect(img, Rect2i(Vector2i.ZERO, SHOW_TILE), Vector2i(k * SHOW_TILE.x, 0))
		strip.save_png(_abs(_out + name + ".png"))
