extends Node
## The catalogue II, rendered (P56; plan M11 §2.6, §3.9). Review sheets a reviewer reads (no check):
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
const WATCHDOG_S := 900.0
const NEW_HAIR := ["top_knot", "side_braids", "twin_braids", "long_loose", "circlet_braid"]
const NEW_BEARD := ["chin_braid", "long_forked", "mutton_chops", "braided_moustache"]
const BEAD_SETS := ["bone_beads", "bronze_rings", "silver_beads"]
const NEW_DESIGNS := ["tat_leg_bands", "tat_leg_serpent", "tat_leg_runes", "tat_leg_claws", "tat_arm_runes",
	"tat_arm_spirals", "tat_chest_raven", "tat_chest_runes", "tat_back_wheel", "tat_back_spine", "tat_face_temples",
	"tat_face_chin", "paint_eye_band", "paint_half_face", "paint_chest_slash", "paint_leg_stripes", "scar_lip",
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
	get_tree().process_frame.connect(_review_run, CONNECT_ONE_SHOT)


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
		if framing == "legs" and id in ["scar.thigh_gash"]:
			turn = 160.0
		if id in ["scar.shoulder_bite", "tattoo.arm_spirals"]:
			framing = "arms_left"
			turn = 0.0
		tiles.append(await _tile(all[id], true, turn, framing))
		tiles.append(await _tile(all[id], false, turn + (0.0 if framing != "legs" else 180.0), framing))
		by_kind[kind] = tiles
	for kind: String in by_kind:
		_save_sheet(by_kind[kind], 4, "designs_%s.png" % kind)


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
