extends Node
## The catalogue II, rendered (P56; plan M11 §2.6, §3.9). Without --review: the check tests/slow/
## test_catalogue_render.gd reads (one line, CATALOGUE_RENDER {...}): every new style drawn, swaying and wearing its
## beads; every face key at -1 and +1 against the same shape drawn without blend shapes (the head's arrays blended on
## the CPU: a dark patch from the renderer's blend of the normals and tangents shows as a difference); every preset
## valid and drawn distinct from every other. With --review, the sheets a reviewer reads (no check):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/catalogue_render_probe.tscn -- --review \
##     --out=/abs/folder [--group=hair|beard|beads|designs|presets] [--only=a,b]
##
## Each look's sheet: the whole giant from the front, his right and behind in the world's light, the same in the
## creator's, then the face close (world, creator turned), and the hair framing from behind (creator, world).
## Groups: "hair" every hair style of the catalogue II (bone beads on), "beard" every beard of it (bronze rings on),
## "beads" the three bead sets on braided hair and a braided beard, "designs" the tattoos, war paints and scars of
## the catalogue II, "presets" every preset (one sheet of their fronts, one of their backs).

const PREFIX := "CATALOGUE_RENDER "
const REVIEW_TILE := Vector2i(300, 420)
const CHECK_TILE := Vector2i(320, 240)
## The face keys' dark-patch measure (plan M11 §3.9): the mean of the luminance difference over a PATCH_PX square.
const PATCH_PX := 9
const WATCHDOG_S := 900.0
const NEW_HAIR := ["top_knot", "side_braids", "twin_braids", "long_loose", "circlet_braid"]
const NEW_BEARD := ["chin_braid", "long_forked", "mutton_chops", "braided_moustache"]
const BEAD_SETS := ["bone_beads", "bronze_rings", "silver_beads"]
const NEW_DESIGNS := ["tat_leg_bands", "tat_leg_serpent", "tat_leg_runes", "tat_leg_claws", "tat_arm_runes",
	"tat_arm_spirals", "tat_chest_raven", "tat_chest_runes", "tat_back_wheel", "tat_back_spine", "tat_face_temples",
	"tat_face_tears", "paint_eye_band", "paint_half_face", "paint_chest_slash", "paint_leg_stripes", "scar_lip",
	"scar_shoulder_bite", "scar_thigh_gash", "scar_ribs"]
## The framing a design is reviewed at, by its region.
const REGION_FRAMING := {"face": "face", "chest": "chest", "back": "back_design", "arms": "arms", "legs": "legs"}

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
	_p.custom_minimum_size = Vector2(REVIEW_TILE)
	_p.size = Vector2(REVIEW_TILE)
	add_child(_p)
	_p.viewport.size = REVIEW_TILE
	_p.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var review := OS.get_cmdline_user_args().has("--review")
	if not review:
		_p.viewport.size = CHECK_TILE
	get_tree().process_frame.connect(_review_run if review else _check_run, CONNECT_ONE_SHOT)


func _arg(name: String, fallback := "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback


func _draw_frame() -> Image:
	for i in 2:
		await RenderingServer.frame_post_draw
	return _p.viewport.get_texture().get_image()


## The review's looks of `group`: name -> record.
static func looks(group: String) -> Dictionary:
	var base := Appearance.preset_record("appearance_preset.wanderer")
	var out := {}
	match group:
		"hair":
			for k: String in NEW_HAIR:
				var r := base.duplicate(true)
				r.hair.style = "hair." + k
				r.hair.beads = "bead.bone_beads"
				r.beard.style = "beard.short"
				out["hair_" + k] = r
		"beard":
			for k: String in NEW_BEARD:
				var r := base.duplicate(true)
				r.hair.style = "hair.crop"
				r.beard.style = "beard." + k
				r.beard.beads = "bead.bronze_rings"
				out["beard_" + k] = r
		"beads":
			for k: String in BEAD_SETS:
				var r := base.duplicate(true)
				r.hair.style = "hair.twin_braids"
				r.hair.beads = "bead." + k
				r.beard.style = "beard.chin_braid"
				r.beard.beads = "bead." + k
				out["beads_" + k] = r
		"designs":
			for kind: String in ["tattoo", "paint", "scar"]:
				for id: String in Appearance.option_ids(kind):
					if not str(Appearance.option(id).get("design", "")) in NEW_DESIGNS:
						continue
					var r := _bare(base)
					match kind:
						"tattoo":
							r.tattoos[str(Appearance.option(id).region)] = id
						"paint":
							r = Appearance.with_paint(r, id)
						"scar":
							r.scars = [id]
					out[id] = r
		"face":
			for k: String in Appearance.FACE_KEYS:
				for v: float in [-1.0, 1.0]:
					var r := base.duplicate(true)
					r.face[k] = v
					out["face_%s_%s" % [k, "minus" if v < 0.0 else "plus"]] = r
		"presets":
			for id: String in Appearance.preset_ids():
				out[id] = Appearance.preset_record(id)
	return out


## A record that shows the skin: short hair, no beard, a loincloth only.
static func _bare(base: Dictionary) -> Dictionary:
	var r := base.duplicate(true)
	r.hair.style = "hair.crop"
	r.beard.style = "beard.stubble"
	for slot: String in r.outfit.slots:
		r.outfit.slots[slot] = {"item": "", "dye": ""}
	r.outfit.slots.legs = {"item": "garment.loincloth", "dye": ""}
	r.outfit.set = ""
	return r


## The design option's framing: its region's, the scars' by their design's body regions.
static func design_framing(id: String) -> String:
	var region := str(Appearance.option(id).get("region", ""))
	if region == "":
		var d := str(Appearance.option(id).get("design", ""))
		region = {"scar_lip": "face", "scar_shoulder_bite": "arms", "scar_thigh_gash": "legs", "scar_ribs": "chest"}.get(d, "chest")
	return str(REGION_FRAMING.get(region, "full"))


func _review_run() -> void:
	var group := _arg("group", "hair")
	var only := _arg("only")
	if group == "presets":
		await _presets_sheet(only)
	elif group == "designs":
		await _designs_sheet(only)
	elif group == "face":
		await _face_sheet()

	else:
		var all := looks(group)
		for name: String in all:
			if only != "" and not name in only.split(","):
				continue
			await _look_sheet(name, all[name])
	print(PREFIX + JSON.stringify({"review": _out, "group": group}))
	get_tree().quit(0)


func _look_sheet(name: String, record: Dictionary) -> void:
	var tiles: Array = []
	for world: bool in [true, false]:
		for yaw: float in [0.0, 70.0, 160.0]:
			tiles.append(await _tile(record, world, yaw, "full"))
	tiles.append(await _tile(record, true, 0.0, "face"))
	tiles.append(await _tile(record, false, 55.0, "face"))
	tiles.append(await _tile(record, false, 0.0, "hair"))
	tiles.append(await _tile(record, true, 40.0, "hair"))
	tiles.append(await _tile(record, false, 100.0, "face"))
	tiles.append(await _tile(record, false, -60.0, "hair"))
	_save_sheet(tiles, 3, "sheet_%s.png" % name)


func _designs_sheet(only: String) -> void:
	var all := looks("designs")
	var by_kind := {}
	for id: String in all:
		if only != "" and not id in only.split(","):
			continue
		var kind := id.get_slice(".", 0)
		var framing := design_framing(id)
		var tiles: Array = by_kind.get(kind, [])
		var turn := 0.0
		if id == "scar.shoulder_bite":
			turn = 20.0
		if id == "tattoo.arm_spirals":
			framing = "arms_left"
		tiles.append(await _tile(all[id], true, turn, framing))
		tiles.append(await _tile(all[id], false, turn + (0.0 if framing != "legs" else 180.0), framing))
		by_kind[kind] = tiles
	for kind: String in by_kind:
		_save_sheet(by_kind[kind], 4, "designs_%s.png" % kind)


## The face keys: each at -1, 0 and +1 at the Face framing, in the world's light and the creator's turned.
func _face_sheet() -> void:
	var base := Appearance.preset_record("appearance_preset.wanderer")
	var all := looks("face")
	var tiles: Array = []
	for k: String in Appearance.FACE_KEYS:
		for world: bool in [false, true]:
			for name: String in ["face_%s_minus" % k, "", "face_%s_plus" % k]:
				tiles.append(await _tile(all.get(name, base), world, 0.0 if world else 50.0, "face"))
	_save_sheet(tiles, 6, "face_keys.png")


func _presets_sheet(only: String) -> void:
	var ids := Appearance.preset_ids()
	var fronts: Array = []
	var backs: Array = []
	for id: String in ids:
		if only != "" and not id in only.split(","):
			continue
		var r := Appearance.preset_record(id)
		fronts.append(await _tile(r, false, 0.0, "full"))
		backs.append(await _tile(r, true, 160.0, "full"))
	_save_sheet(fronts, 5, "presets_front.png")
	_save_sheet(backs, 5, "presets_back.png")


func _tile(record: Dictionary, world: bool, yaw: float, framing: String) -> Image:
	_p.world_light = world
	_p.set_game_profile(GiantPreview.stage_profile(1))
	_p.apply_look(Appearance.to_look(record))
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



# ------------------------------------------------------------------------------------------------ the check
func _check_run() -> void:
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "styles": {}, "face": {}, "presets": {}}
	_p.world_light = false
	_p.set_game_profile(GiantPreview.stage_profile(1))
	var base := Appearance.preset_record("appearance_preset.wanderer")
	# 1. the styles: drawn (against none), swaying (the hair shader's head_motion moves the cards' tips), beaded
	var bare := base.duplicate(true)
	bare.hair.style = "hair.shaved"
	bare.beard.style = "beard.none"
	var none_hair: Image = await _tile(bare, false, 0.0, "hair_close")
	var none_face: Image = await _tile(bare, false, 50.0, "face")
	for k: String in NEW_HAIR + NEW_BEARD:
		var hair := k in NEW_HAIR
		var r := bare.duplicate(true)
		if hair:
			r.hair.style = "hair." + k
		else:
			r.beard.style = "beard." + k
		var framing := "hair_close" if hair else "face"
		var turn := 0.0 if hair else 50.0
		var plain: Image = await _tile(r, false, turn, framing)
		var mesh := str(Appearance.option(("hair." if hair else "beard.") + k).get("mesh", ""))
		var mi := GiantLook.mesh_node(_p.model, _p.model.index, mesh)
		var mat := mi.material_override as ShaderMaterial if mi != null else null
		if mat != null:
			mat.set_shader_parameter("head_motion", Vector3(0.06, 0.0, 0.06))
		var swayed: Image = await _draw_frame()
		if mat != null:
			mat.set_shader_parameter("head_motion", Vector3.ZERO)
		var beaded := r.duplicate(true)
		if hair:
			beaded.hair.beads = "bead.bone_beads"
		else:
			beaded.beard.beads = "bead.bone_beads"
		var with_beads: Image = await _tile(beaded, false, turn, framing)
		var beads := _changed(plain, with_beads)
		if hair:
			# a braid that falls in front (the twin braids, the temples' braids) wears its beads on the chest
			var front: Image = await _tile(r, false, 50.0, "face")
			beads = maxf(beads, _changed(front, await _tile(beaded, false, 50.0, "face")))
		report.styles[k] = {"drawn": _changed(plain, none_hair if hair else none_face), "sway": _changed(plain, swayed),
			"beads": beads, "validate": Array(GiantLook.validate(_p.model, _p.model.index,
			Appearance.to_look(beaded)))}
	# 2. the face keys against the CPU's blend of the same arrays (the skin alone: no hair, no beard)
	var head := GiantLook.mesh_node(_p.model, _p.model.index, "Body_Head")
	var shapes := {}
	if head != null and head.mesh is ArrayMesh:
		for i in (head.mesh as ArrayMesh).get_blend_shape_count():
			shapes[str((head.mesh as ArrayMesh).get_blend_shape_name(i))] = i
	report["head_keys"] = shapes.keys()
	for k: String in Appearance.FACE_KEYS:
		if not shapes.has(k):
			continue
		for w: float in [-1.0, 1.0]:
			var r := bare.duplicate(true)
			r.face[k] = w
			var gpu: Image = await _tile(r, false, 30.0, "face")
			var keyed: Mesh = head.mesh
			head.mesh = _cpu_blend(keyed as ArrayMesh, int(shapes[k]), w)
			var cpu: Image = await _draw_frame()
			head.mesh = keyed
			head.set_blend_shape_value(int(shapes[k]), w)
			report.face["%s%+d" % [k, int(w)]] = _darkest_patch(gpu, cpu)
			if _out != "":
				gpu.save_png(_out.path_join("face_%s%+d_gpu.png" % [k, int(w)]))
				cpu.save_png(_out.path_join("face_%s%+d_cpu.png" % [k, int(w)]))
	# 3. the presets: valid, and each drawn distinct from every other
	var tiles := {}
	for id: String in Appearance.preset_ids():
		var r := Appearance.preset_record(id)
		tiles[id] = await _tile(r, false, 0.0, "full")
		report.presets[id] = {"validate": Array(GiantLook.validate(_p.model, _p.model.index, Appearance.to_look(r))),
			"valid": Appearance.is_valid(r, "")}
	var ids: Array = tiles.keys()
	var least := 1.0
	var pair := ""
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d := _changed(tiles[ids[i]], tiles[ids[j]])
			if d < least:
				least = d
				pair = "%s|%s" % [ids[i], ids[j]]
	report["preset_least"] = {"share": least, "pair": pair}
	print(PREFIX + JSON.stringify(report))
	get_tree().quit(0)


## The share of the frame's pixels that differ between two frames by more than 6/255 in some channel.
static func _changed(a: Image, b: Image) -> float:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) > 6.0 / 255.0:
				n += 1
	return float(n) / float(a.get_width() * a.get_height())


## The darkest PATCH_PX square mean of the luminance difference gpu - cpu (in 1/255; negative: the renderer's
## blend draws darker than the same shape blended on the CPU), over the pixels the head covers in both.
static func _darkest_patch(gpu: Image, cpu: Image) -> float:
	var w := gpu.get_width()
	var h := gpu.get_height()
	var bg := cpu.get_pixel(0, 0)
	var worst := 0.0
	for y0 in range(0, h - PATCH_PX, 3):
		for x0 in range(0, w - PATCH_PX, 3):
			var sum := 0.0
			var ok := true
			for y in range(y0, y0 + PATCH_PX):
				for x in range(x0, x0 + PATCH_PX):
					var c := cpu.get_pixel(x, y)
					if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) < 0.02:
						ok = false
						break
					sum += gpu.get_pixel(x, y).get_luminance() - c.get_luminance()
				if not ok:
					break
			if ok:
				worst = minf(worst, sum / float(PATCH_PX * PATCH_PX) * 255.0)
	return worst


## The head's arrays with blend shape `index` at weight `w` blended on the CPU (positions; normals and tangents
## blended and normalized, the tangent keeping the base's sign): the reference the renderer's blend is checked against.
static func _cpu_blend(src: ArrayMesh, index: int, w: float) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var shape: Array = src.surface_get_blend_shape_arrays(0)[index]
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sv: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
	var nb: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var sn: PackedVector3Array = shape[Mesh.ARRAY_NORMAL] if shape[Mesh.ARRAY_NORMAL] != null else nb
	var tb: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var st: PackedFloat32Array = shape[Mesh.ARRAY_TANGENT] if shape[Mesh.ARRAY_TANGENT] != null else tb
	var relative := src.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for i in v.size():
		var dv: Vector3 = sv[i] if relative else sv[i] - v[i]
		var dn: Vector3 = sn[i] if relative else sn[i] - nb[i]
		v[i] += dv * w
		nb[i] = (nb[i] + dn * w).normalized()
		if tb.size() == v.size() * 4:
			var t := Vector3(tb[i * 4], tb[i * 4 + 1], tb[i * 4 + 2])
			var s := Vector3(st[i * 4], st[i * 4 + 1], st[i * 4 + 2])
			t = (t + (s if relative else s - t) * w).normalized()
			tb[i * 4] = t.x
			tb[i * 4 + 1] = t.y
			tb[i * 4 + 2] = t.z
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nb
	if tb.size() == v.size() * 4:
		arr[Mesh.ARRAY_TANGENT] = tb
	var flags := src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return out
