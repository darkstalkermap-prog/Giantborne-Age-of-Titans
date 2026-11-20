extends Node
## The character sheets (P44; plan M10 §3.4 design 5, §4.2): labelled pages, 1920 px wide, of the giant as the
## game draws him - GiantPreview tiles (the creator's framings, the stage-1 Game view, first person) in the
## world's light (its sun, sky, ambient, fog and ground: tools/builders/world.gd's values, held by GiantPreview),
## every tile in the same still pose. Sheet A (the W26 merge, the floor catalogue):
##   1  the giant in the engine: the Wanderer at the third-person camera with the game's soldier and villager,
##      and beside the approved Blender renders at their angles (--renders=)
##   2  hair and beards: every style in three colours from the front and from behind, grey 0 / 0.5 / 1, the presets
##   3  skin and eyes: the ten tones, the eye colours close up (a line's options drawn for that line)
##   4a tattoos by region in two inks, each also in the stage-1 Game view and in first person
##   4b war paint in two colours, the scars and the ancestry marks, each also in Game view and first person
##   5  clothing: the four outfits in two dye pairs, front and back, and their cloth close up
##   6  web and desktop: the creator's face framing at the web (512 px) and hi (1024 px) texture tiers
## Sheet B (P57; plan M11 §4.2, the owner's checkpoint B: the wardrobe sheet), every page built from the sets, so a
## set that grows shows its new options:
##   b1 the garments by slot, each on the default giant in its slot's framing and whole (a cape from behind and his right)
##   b2 the outfits front and back; the fullest look from four sides; its armour in every metal
##   b3 the accessories (each aimed at, as the creator's pictures are) and the bead sets on a hair style and a beard
##   b4 the hair styles from the front and from behind, the beards from the front and the side
##   b5 the designs by region: every tattoo, war paint and scar framed and in the stage-1 Game view
##   b6 the build sliders at the creator's ends, from behind in Game view and whole; the face sliders at -1 and +1
##   b7 the presets, front and back
##   b8a, b8b the creator at 1280x720 and at 1920x1080 (--creator-shots=<dir at 1280x720>,<dir at 1920x1080>: the PNGs
##      tests/support/creator_probe.tscn --shots wrote at those sizes)
## A main scene, not a -s script (Appearance and GiantPreview read the autoloads' data). Run under Xvfb:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1920x1080x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --audio-driver Dummy res://tools/character_sheet.tscn -- \
##     [--out=docs/screenshots/m10/] [--renders=<folder with test_studio_full34.png, test_outdoor_head.png>] \
##     [--pages=1,2,3,4a,4b,5,6] [--sheet=a] [--jpg]
##   ... -- --sheet=b --out=<dir> [--pages=b1,...] [--creator-shots=<dir>,<dir>]
##
## It writes sheet_<sheet>_<page>_<name>.png (or .jpg with --jpg) into --out (a path relative to the project or
## absolute; default docs/screenshots/m10/), prints CHARACTER_SHEET {"pages", "tiles", "ms", "tier", "adapter"}
## and quits (a watchdog quits it after WATCHDOG_S).

const PAGE_W := 1920
const MARGIN := 24
const GAP := 16
const CAPTION_H := 28
const POOL := 8
const FRAMES_FIRST := 3
const FRAMES_EACH := 2
const WATCHDOG_S := 900.0
const DEFAULT_OUT := "docs/screenshots/m10/"
const PREFIX := "CHARACTER_SHEET "
const VILLAGER_SCENE := "res://scenes/npcs/villager.tscn"
const RENDERS := {"studio": "test_studio_full34.png", "head": "test_outdoor_head.png"}
const BG := Color(0.105, 0.11, 0.125)
const INK := Color(0.93, 0.91, 0.87)
const DIM := Color(0.66, 0.67, 0.70)
## Colours shown for the hair styles and beards (dark, red, fair), the grey steps, the inks, paints and dyes.
const HAIR_COLOURS := ["haircolor.black", "haircolor.copper", "haircolor.blond"]
const GREYS := [0.0, 0.5, 1.0]
const INKS := ["ink.woad", "ink.ochre"]
const PAINT_COLOURS := ["paintcolor.chalk", "paintcolor.blood"]
const DYE_PAIRS := [["dye.undyed", "dye.dark_leather"], ["dye.madder", "dye.woad_blue"]]
## A design region in a caption.
const REGION_WORDS := {"hand_l": "left hand", "hand": "right hand", "arms": "arms", "face": "face", "chest": "chest",
	"back": "back"}
## The lines a mark is drawn for.
const MARK_LINES := {"mark.granite_veins": "ancestry.stoneblood", "mark.lightning_tree": "ancestry.stormborn",
	"mark.claw_stripes": "ancestry.wildheart"}

var out_dir := ""
var renders_dir := ""
## Sheet b's page 8: the creator_probe shots at 1280x720 and at 1920x1080.
var creator_shots := PackedStringArray()
var sheet := "a"
var only_pages := PackedStringArray()
var jpg := false
var _pool: Array[GiantPreview] = []
var _villagers := {}
var _stage1: Dictionary = {}
var _frames := 0
var _tiles := 0
var _written := PackedStringArray()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "the sheet tool timed out", "pages": Array(_written)}))
		get_tree().quit(3))
	out_dir = DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--renders="):
			renders_dir = arg.substr(10)
		elif arg.begins_with("--pages="):
			only_pages = arg.substr(8).split(",", false)
		elif arg.begins_with("--sheet="):
			sheet = arg.substr(8).to_lower()
		elif arg == "--jpg":
			jpg = true
		elif arg.begins_with("--creator-shots="):
			creator_shots = arg.substr(16).split(",", false)
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_stage1 = GiantPreview.stage_profile(1)
	var holder := Control.new()
	holder.name = "Tiles"
	add_child(holder)
	for i in POOL:
		var p := GiantPreview.new()
		p.still = true
		p.stretch = false   # P57: the tile sets its viewport's size itself
		p.world_light = true
		holder.add_child(p)
		_pool.append(p)
	await get_tree().process_frame
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for page: Dictionary in pages():
		if not only_pages.is_empty() and not str(page.id) in only_pages:
			continue
		for section: Dictionary in page.sections:
			await _render_section(section)
		var img := await _compose(page)
		var path := out_dir.path_join("sheet_%s_%s_%s.%s" % [sheet, page.id, page.name, "jpg" if jpg else "png"])
		var err := img.save_jpg(path, 0.9) if jpg else img.save_png(path)
		if err == OK:
			_written.append(path)
		else:
			push_error("character_sheet: could not write %s (%d)" % [path, err])
	print(PREFIX + JSON.stringify({"pages": Array(_written), "tiles": _tiles, "ms": Time.get_ticks_msec() - t0,
		"tier": GiantLook.built_tier(_pool[0].model), "adapter": RenderingServer.get_video_adapter_name()}))
	get_tree().quit(0)


# --------------------------------------------------------------------------- the pages

## The pages of the sheet: {id, name, title, note, sections: [{title, columns, aspect, tiles: [tile]}]}. A tile is
## {label, record, ancestry, framing, turn, zoom, villager, tier} or {label, image_path} (an approved render).
func pages() -> Array:
	if sheet == "b":
		return pages_b()
	var base := Appearance.default_record()
	base["mark"] = Appearance.MARK_NONE
	var out: Array = []
	# 1 - the giant in the engine
	var studio := _tile("Our giant, the same angle (the world's light)", base, "full", "", -50.0)
	var head := _tile("Our giant, the same angle (the world's light)", base, "face", "", -44.0)
	out.append({"id": "1", "name": "giant", "title": "1. Our giant in the engine",
		"note": "The Wanderer (the default look) at stage 1, drawn by the game: the Compatibility renderer, the world's sun, sky, ambient and fog.",
		"sections": [
			{"title": "At the third-person camera, beside the game's soldier and villager", "columns": 2, "aspect": 0.5625,
				"tiles": [_with(_tile("Game view: the default camera, from behind", base, "game"), {"villager": true}),
					_with(_tile("The same distance, from the front", base, "game", "", 180.0), {"villager": true})]},
			{"title": "Beside the approved Blender renders, at their angles", "columns": 4, "aspect": 1.0,
				"tiles": [_image("Approved render: studio, three-quarter", RENDERS.studio), studio,
					_image("Approved render: outdoor head close-up", RENDERS.head), head]}]})
	# 2 - hair and beards
	var styles: Array = []
	for style in Appearance.option_ids("hair"):
		for colour: String in HAIR_COLOURS:
			var rec := OptionRows.with_value(OptionRows.with_value(base, "hair.style", style), "hair.color", colour)
			var words := "%s, %s" % [_name(style), _name(colour).to_lower()]
			styles.append(_tile(words + " - front", rec, "face", "", 0.0, -2.0))
			styles.append(_tile(words + " - behind", rec, "hair"))
	var beards: Array = []
	for style in Appearance.option_ids("beard"):
		for colour: String in HAIR_COLOURS:
			var rec := OptionRows.with_value(OptionRows.with_value(base, "beard.style", style), "hair.color", colour)
			beards.append(_tile("Beard: %s, %s" % [_name(style).to_lower(), _name(colour).to_lower()], rec, "face"))
	var greys: Array = []
	for g: float in GREYS:
		var rec := OptionRows.with_value(OptionRows.with_value(base, "hair.grey", g), "beard.grey", g)
		var words := Appearance.grey_words(g)
		greys.append(_tile("Grey %.1f%s - front" % [g, (" (%s)" % words) if words != "" else ""], rec, "face", "", 0.0, -2.0))
		greys.append(_tile("Grey %.1f - behind" % g, rec, "hair"))
	var presets: Array = []
	for pid in Appearance.preset_ids():
		var rec := Appearance.preset_record(pid)
		rec["mark"] = Appearance.MARK_NONE
		presets.append(_tile(str(GameData.get_record(pid).get("display_name", pid)), rec, "full"))
	out.append({"id": "2", "name": "hair", "title": "2. Hair and beards",
		"note": "Hair and beards are game cards (not strands). The beard takes the hair's colour; grey is 0 to 1 for each.",
		"sections": [
			{"title": "The hair styles in three colours, from the front and from behind", "columns": 6, "aspect": 1.0, "tiles": styles},
			{"title": "The beards in three colours", "columns": 6, "aspect": 1.0, "tiles": beards},
			{"title": "Grey at 0, 0.5 and 1 (hair and beard)", "columns": 6, "aspect": 1.0, "tiles": greys},
			{"title": "The eight presets", "columns": 4, "aspect": 1.25, "tiles": presets}]})
	# 3 - skin and eyes
	var skins: Array = []
	for id in Appearance.option_ids("skin"):
		var line := Appearance.required_ancestry(Appearance.option(id))
		skins.append(_tile(_name(id) + _line_words(line), OptionRows.with_value(base, "skin", id), "full", line))
	var eyes: Array = []
	for id in Appearance.option_ids("eyes"):
		var line := Appearance.required_ancestry(Appearance.option(id))
		eyes.append(_tile(_name(id) + _line_words(line), OptionRows.with_value(base, "eyes", id), "eyes", line))
	out.append({"id": "3", "name": "skin_eyes", "title": "3. Skin and eyes",
		"note": "A line's options (ashen skin; the storm-lit and amber eyes) are drawn for that line, which unlocks them.",
		"sections": [
			{"title": "The ten skin tones", "columns": 5, "aspect": 1.25, "tiles": skins},
			{"title": "The eye colours, close up", "columns": 5, "aspect": 0.5, "tiles": eyes}]})
	# 4a - tattoos
	var tattoos: Array = []
	for id in Appearance.option_ids("tattoo"):
		var o := Appearance.option(id)
		var region := str(o.get("region", "arms"))
		var framing := GiantPreview.region_framing(region)
		var rec := OptionRows.with_value(base, "tattoos." + region, id)
		for ink: String in INKS:
			tattoos.append(_tile("%s (%s) - %s ink" % [_name(id), region, _name(ink).to_lower()],
				OptionRows.with_value(rec, "tattoos.ink", ink), framing))
		tattoos.append(_tile("%s - Game view, stage 1" % _name(id), rec, "game"))
		tattoos.append(_tile("%s - first person" % _name(id), rec, GiantPreview.FIRST_PERSON))
	out.append({"id": "4a", "name": "tattoos", "title": "4a. Tattoos",
		"note": "Each tattoo framed on its region in two inks, then in the stage-1 Game view and in first person: what reads in play.",
		"sections": [{"title": "The tattoos by region", "columns": 4, "aspect": 0.6, "tiles": tattoos}]})
	# 4b - war paint, scars, marks
	var paints: Array = []
	for id in Appearance.option_ids("paint"):
		var region := str(Appearance.option(id).get("region", "face"))
		var rec := OptionRows.with_value(base, "paint.design", id)
		for colour: String in PAINT_COLOURS:
			paints.append(_tile("%s - %s" % [_name(id), _name(colour).to_lower()], OptionRows.with_value(rec, "paint.color", colour),
				GiantPreview.region_framing(region)))
		paints.append(_tile("%s - Game view, stage 1" % _name(id), rec, "game"))
		paints.append(_tile("%s - first person" % _name(id), rec, GiantPreview.FIRST_PERSON))
	var scars: Array = []
	var index := _pool[0].index()
	for id in Appearance.option_ids("scar"):
		var rec := OptionRows.with_scar(base, id, true)
		var region := OptionRows.row_region({"key": "scar.x", "id": id}, {}, index, "")
		scars.append(_tile("%s (%s)" % [_name(id), str(REGION_WORDS.get(region, region))], rec, GiantPreview.region_framing(region)))
		scars.append(_tile("%s - Game view, stage 1" % _name(id), rec, "game"))
		scars.append(_tile("%s - first person" % _name(id), rec, GiantPreview.FIRST_PERSON))
	var marks: Array = []
	for id: String in MARK_LINES:
		if not id in Appearance.option_ids("mark"):
			continue
		var line: String = MARK_LINES[id]
		var rec := OptionRows.with_value(base, "mark", Appearance.MARK_AUTO)
		var region := OptionRows.row_region({"key": "mark", "id": id}, {}, index, line)
		marks.append(_tile("%s%s" % [_name(id), _line_words(line)], rec, GiantPreview.region_framing(region), line))
		marks.append(_tile("%s - Game view, stage 1" % _name(id), rec, "game", line))
		marks.append(_tile("%s - first person" % _name(id), rec, GiantPreview.FIRST_PERSON, line))
	out.append({"id": "4b", "name": "paint_scars_marks", "title": "4b. War paint, scars and ancestry marks",
		"note": "Each design framed, then in the stage-1 Game view and in first person. Of the scars, the back lashes are the ones that read from behind.",
		"sections": [
			{"title": "War paint in two colours", "columns": 4, "aspect": 0.6, "tiles": paints},
			{"title": "Scars", "columns": 3, "aspect": 0.6, "tiles": scars},
			{"title": "Ancestry marks (each drawn for its line)", "columns": 3, "aspect": 0.6, "tiles": marks}]})
	# 5 - clothing
	var outfits: Array = []
	var cloth: Array = []
	for pair: Array in DYE_PAIRS:
		for id in Appearance.option_ids("outfit"):
			var rec := OptionRows.with_value(base, "outfit.set", id)
			rec = OptionRows.with_value(OptionRows.with_value(rec, "outfit.primary", pair[0]), "outfit.secondary", pair[1])
			var words := "%s - %s and %s" % [_name(id), _name(pair[0]).to_lower(), _name(pair[1]).to_lower()]
			outfits.append(_tile(words, rec, "full"))
			outfits.append(_tile(words + ", behind", rec, "back"))
			if pair == DYE_PAIRS[0]:
				cloth.append(_tile(_name(id) + " - the cloth close up", rec, "chest", "", 0.0, -1.0))
	out.append({"id": "5", "name": "clothing", "title": "5. Clothing",
		"note": "The outfits in two dye pairs (primary and secondary), front and back; the cloth's detail maps close up.",
		"sections": [
			{"title": "The outfits in two dye pairs", "columns": 4, "aspect": 1.25, "tiles": outfits},
			{"title": "The cloth close up (weave, leather, fur)", "columns": 4, "aspect": 0.75, "tiles": cloth}]})
	# 6 - web and desktop
	var tiers: Array = []
	var chieftain := Appearance.preset_record("appearance_preset.northern_chieftain")
	chieftain["mark"] = Appearance.MARK_NONE
	for rec: Dictionary in [base, chieftain]:
		for tier: String in ["web", "hi"]:
			tiers.append(_with(_tile("%s - %s tier (%s)" % ["The Wanderer" if rec == base else "The Northern Chieftain", tier,
				"512 px maps" if tier == "web" else "1024 px normal and ORM maps"], rec, "face"), {"tier": tier}))
	out.append({"id": "6", "name": "tiers", "title": "6. Web and desktop",
		"note": "The creator's face framing at the two texture tiers: the Web build draws the 512 px tier, desktop the 1024 px one.",
		"sections": [{"title": "The face framing at the web and hi tiers", "columns": 2, "aspect": 0.75, "tiles": tiers}]})
	return out


## Sheet B, the wardrobe sheet (see the header). Its framed tiles are drawn in the creator's studio light, its Game view
## and first-person tiles in the world's.
func pages_b() -> Array:
	var base := Appearance.default_record()
	base["mark"] = Appearance.MARK_NONE
	base["preset"] = ""
	var out: Array = []
	var dye_words := "the default dyes (cloth: %s; leather: %s; metal: %s)" % [_name(str(base.outfit.dyes.cloth)).to_lower(),
		_name(str(base.outfit.dyes.leather)).to_lower(), _name(str(base.outfit.dyes.metal)).to_lower()]
	# b1 - the garments by slot
	var slots: Array = []
	for slot: String in Appearance.SLOTS:
		var tiles: Array = []
		for id in Appearance.option_ids("garment"):
			var o := Appearance.option(id)
			if str(o.get("slot", "")) != slot:
				continue
			var rec := OptionRows.with_value(base, "outfit.slots.%s.item" % slot, id)
			var words := "%s (%s)" % [_name(id), str(o.get("material", ""))]
			tiles.append(_tile(words, rec, str(OptionRows.SLOT_FRAMINGS.get(slot, "full"))))
			if slot == "cape":
				tiles.append(_tile(words + " - his right", rec, "full", "", -70.0))   # the slot's own framing is from behind
			else:
				tiles.append(_tile(words + " - whole", rec, "full"))
		slots.append({"title": "%s: %d garments (each in the slot's framing, then the whole giant)" % [str(OptionRows.SLOT_NAMES.get(slot, slot)),
			tiles.size() / 2], "columns": 6, "aspect": 1.15, "tiles": tiles})
	out.append({"id": "b1", "name": "garments", "title": "B1. The garments, slot by slot",
		"note": "Each garment alone on the default giant (the Wanderer: his braies and belt stay unless the slot replaces them), in %s, in the creator's light." % dye_words,
		"sections": slots})
	# b2 - outfits, the fullest look, the metals
	var outfits: Array = []
	for id in Appearance.option_ids("outfit"):
		var rec := OptionRows.with_value(base, "outfit.set", id)
		outfits.append(_tile(_name(id), rec, "full"))
		outfits.append(_tile(_name(id) + " - behind", rec, "back"))
	var fullest := fullest_record(base)
	var sides: Array = []
	for turn: Array in [[0.0, "front"], [-90.0, "his right"], [180.0, "behind"], [90.0, "his left"]]:
		sides.append(_tile("The fullest look - %s" % turn[1], fullest, "full", "", float(turn[0]) - 20.0))
	var metals: Array = []
	for id in Appearance.option_ids("metal"):
		var rec := OptionRows.with_value(fullest, "outfit.dyes.metal", id)
		metals.append(_tile("Armour in %s" % _name(id).to_lower(), rec, "chest", "", 0.0, -2.0))
	out.append({"id": "b2", "name": "outfits", "title": "B2. Outfits, the fullest look, the metals",
		"note": "Every outfit fills its slots at once (front and behind). The fullest look: %s." % _fullest_words(fullest),
		"sections": [
			{"title": "The %d outfits, front and behind" % (outfits.size() / 2), "columns": 6, "aspect": 1.25, "tiles": outfits},
			{"title": "The fullest look from four sides", "columns": 4, "aspect": 1.25, "tiles": sides},
			{"title": "Its armour in every metal", "columns": mini(6, maxi(1, metals.size())), "aspect": 0.8, "tiles": metals}]})
	# b3 - accessories and beads
	var acc: Array = []
	for id in Appearance.option_ids("accessory"):
		var o := Appearance.option(id)
		var slot := str(o.get("slot", ""))
		var rec := OptionRows.with_value(base, "outfit.accessories." + slot, id)
		var framing := str(OptionRows.SLOT_FRAMINGS.get(slot, "full"))
		var t := _tile("%s (%s)" % [_name(id), str(OptionRows.ACCESSORY_NAMES.get(slot, slot)).to_lower()], rec, framing)
		t["aim"] = [str(o.get("mesh", ""))]
		acc.append(t)
	var beads: Array = []
	var index := _pool[0].index()
	for id in Appearance.option_ids("bead"):
		var mesh := str(Appearance.option(id).get("mesh", ""))
		if mesh == "":
			continue
		var styles: Dictionary = ((index.get("meshes", {}) as Dictionary).get(mesh, {}) as Dictionary).get("styles", {})
		for part: String in ["hair", "beard"]:
			var style := _style_with_anchors(part, styles)
			if style == "":
				continue
			var rec := OptionRows.with_value(OptionRows.with_value(base, part + ".style", style), part + ".beads", id)
			beads.append(_tile("%s on %s" % [_name(id), _name(style).to_lower()], rec, "face", "", 60.0 if part == "hair" else 30.0))
	out.append({"id": "b3", "name": "accessories_beads", "title": "B3. Accessories and beads",
		"note": "Each accessory on the default giant, framed as its picture in the creator (a belt piece aimed at itself); each bead set on a hair style and a beard that carry its anchors.",
		"sections": [
			{"title": "The %d accessories" % acc.size(), "columns": 4, "aspect": 1.0, "tiles": acc},
			{"title": "The bead sets", "columns": 6, "aspect": 1.0, "tiles": beads}]})
	# b4 - hair and beards
	var hair: Array = []
	for id in Appearance.option_ids("hair"):
		var rec := OptionRows.with_value(base, "hair.style", id)
		hair.append(_tile(_name(id) + " - front", rec, "face", "", 0.0, -2.0))
		hair.append(_tile(_name(id) + " - behind", rec, "hair"))
	var beards: Array = []
	for id in Appearance.option_ids("beard"):
		var rec := OptionRows.with_value(base, "beard.style", id)
		beards.append(_tile(_name(id) + " - front", rec, "face"))
		beards.append(_tile(_name(id) + " - side", rec, "face", "", 70.0))
	out.append({"id": "b4", "name": "hair_beards", "title": "B4. Hair and beards",
		"note": "Every style in the default colours (%s), the hair from the front and from behind, the beards from the front and his right." %
			_name(str(base.hair.color)).to_lower(),
		"sections": [
			{"title": "The %d hair styles" % (hair.size() / 2), "columns": 6, "aspect": 1.0, "tiles": hair},
			{"title": "The %d beards" % (beards.size() / 2), "columns": 6, "aspect": 1.0, "tiles": beards}]})
	# b5 - designs by region
	var sections: Array = []
	for kind: Array in [["tattoo", "Tattoos"], ["paint", "War paint"], ["scar", "Scars"]]:
		var tiles: Array = []
		for id in Appearance.option_ids(str(kind[0])):
			var o := Appearance.option(id)
			var rec: Dictionary
			var region: String
			match str(kind[0]):
				"tattoo":
					region = str(o.get("region", "arms"))
					rec = OptionRows.with_value(base, "tattoos." + region, id)
				"paint":
					region = str(o.get("region", "face"))
					rec = OptionRows.with_value(base, "paint.design", id)
				_:
					rec = OptionRows.with_scar(base, id, true)
					region = OptionRows.row_region({"key": "scar.x", "id": id}, {}, index, "")
			if region == "face":
				rec = OptionRows.with_value(rec, "beard.style", "beard.none")
			elif region == "legs":
				rec = OptionRows.with_value(rec, "outfit.slots.legs.item", "")   # the braies cover the thighs
			var side := OptionRows.design_side(str(o.get("design", "")), index)
			tiles.append(_tile("%s (%s%s)" % [_name(id), str(REGION_WORDS.get(region, region)), "" if side == "centre" else ", " + side], rec,
				GiantPreview.region_framing(region, side)))
			tiles.append(_tile(_name(id) + " - Game view", rec, "game"))
		sections.append({"title": "%s: %d, each framed and in the stage-1 Game view" % [kind[1], tiles.size() / 2], "columns": 6,
			"aspect": 0.75, "tiles": tiles})
	out.append({"id": "b5", "name": "designs", "title": "B5. Designs by region",
		"note": "Every tattoo, war paint and scar alone on the default giant (no beard over a face design, no braies over a leg design), framed from its side, then at the stage-1 game camera.",
		"sections": sections})
	# b6 - sliders
	var build: Array = []
	for o: Dictionary in Appearance.options("build", ""):
		for v: float in [-OptionRows.BUILD_LIMIT, OptionRows.BUILD_LIMIT]:
			var rec := OptionRows.with_value(base, "build." + str(o.key), v)
			var words := "%s %+.1f (%s)" % [str(o.get("name", o.key)), v, str(o.get("low" if v < 0.0 else "high", ""))]
			build.append(_tile(words + " - Game view, behind", rec, "game"))
			build.append(_tile(words + " - whole", rec, "full"))
	var shaven := OptionRows.with_value(base, "beard.style", "beard.none")   # the jaw and the chin under no beard
	var face: Array = [_tile("Every face slider at 0 (no beard)", shaven, "face", "", 20.0)]
	for o: Dictionary in Appearance.options("face", ""):
		for v: float in [-1.0, 1.0]:
			face.append(_tile("%s %+d (%s)" % [str(o.get("name", o.key)), int(v), str(o.get("low" if v < 0.0 else "high", ""))],
				OptionRows.with_value(shaven, "face." + str(o.key), v), "face", "", 20.0))
	out.append({"id": "b6", "name": "sliders", "title": "B6. The build and face sliders at their ends",
		"note": "The build sliders at the creator's ends (%.1f each way), from behind at the stage-1 game camera and whole; the face sliders at -1 and +1 without a beard." %
			OptionRows.BUILD_LIMIT,
		"sections": [
			{"title": "Build", "columns": 4, "aspect": 0.75, "tiles": build},
			{"title": "Face", "columns": 5, "aspect": 1.0, "tiles": face}]})
	# b7 - presets
	var presets: Array = []
	for pid in Appearance.preset_ids():
		var rec := Appearance.preset_record(pid)
		rec["mark"] = Appearance.MARK_NONE
		var words := str(GameData.get_record(pid).get("display_name", pid))
		presets.append(_tile(words, rec, "full"))
		presets.append(_tile(words + " - behind", rec, "back"))
	out.append({"id": "b7", "name": "presets", "title": "B7. The %d presets" % (presets.size() / 2),
		"note": "Every preset as the creator puts it on (its ancestry mark left off), front and behind.",
		"sections": [{"title": "Front and behind", "columns": 6, "aspect": 1.25, "tiles": presets}]})
	# b8 - the creator, one page a window size, one screen a line (legible at the page's width)
	for i in creator_shots.size():
		var dir := creator_shots[i]
		var size_words := "1280x720" if i == 0 else "1920x1080"
		var screens: Array = []
		for f: Array in [["01_presets.png", "Presets"], ["11_clothing.png", "Clothing: the slot rows"],
				["23_grid_outfits.png", "The outfits' grid"], ["22_grid_armour.png", "The armour's grid"],
				["32_grid_belt.png", "The belt's grid"], ["25_grid_tattoo_arms.png", "The arm tattoos' grid"],
				["33_grid_paint_face.png", "The face paints' grid"]]:
			screens.append({"label": "%s - %s" % [str(f[1]), size_words], "image_path": dir.path_join(str(f[0]))})
		out.append({"id": "b8%s" % ("a" if i == 0 else "b"), "name": "creator_%s" % size_words, "title": "B8%s. The creator at %s" %
			["a" if i == 0 else "b", size_words],
			"note": "The creator as a player meets it after New Game (the game's own sets), from tests/support/creator_probe.tscn: the slot rows and option grids with their pictures (the desktop's; the browser shows the names).",
			"sections": [{"title": "The creator's screens", "columns": 1, "aspect": 0.5625, "tiles": screens}]})
	return out


## The fullest look of the data: the outfit that fills the most slots, an accessory in every accessory slot (the first
## of each), the default hair and beard.
static func fullest_record(base: Dictionary) -> Dictionary:
	var best := ""
	var most := -1
	for id in Appearance.option_ids("outfit"):
		var n := Appearance.record_garments(Appearance.with_outfit(base, id)).size()
		if n > most:
			most = n
			best = id
	var rec := Appearance.with_outfit(base, best) if best != "" else base.duplicate(true)
	for slot: String in Appearance.ACCESSORY_SLOTS:
		for id in Appearance.option_ids("accessory"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				rec = OptionRows.with_value(rec, "outfit.accessories." + slot, id)
				break
	return rec


static func _fullest_words(rec: Dictionary) -> String:
	var acc: Array = []
	for slot: String in Appearance.ACCESSORY_SLOTS:
		var id := str(OptionRows.value_of(rec, "outfit.accessories." + slot))
		if id != "":
			acc.append(_name(id).to_lower())
	return "%s (%d garments) with %s" % [_name(str(rec.outfit.set)), Appearance.record_garments(rec).size(), ", ".join(acc)]


## The first style of `part` whose mesh has bead anchors in `styles` (a bead set's index "styles").
static func _style_with_anchors(part: String, styles: Dictionary) -> String:
	for id in Appearance.option_ids(part):
		if styles.has(str(Appearance.option(id).get("mesh", ""))):
			return id
	return ""


func _tile(label: String, record: Dictionary, framing: String, ancestry := "", turn := 0.0, zoom := 0.0) -> Dictionary:
	return {"label": label, "record": record, "framing": framing, "ancestry": ancestry, "turn": turn, "zoom": zoom}


func _with(tile: Dictionary, extra: Dictionary) -> Dictionary:
	tile.merge(extra, true)
	return tile


func _image(label: String, file_name: String) -> Dictionary:
	return {"label": label, "image_path": renders_dir.path_join(file_name) if renders_dir != "" else ""}


static func _name(option_id: String) -> String:
	return str(Appearance.option(option_id).get("name", option_id.get_slice(".", 1).replace("_", " ").capitalize()))


static func _line_words(line: String) -> String:
	if line == "":
		return ""
	return " (%s line)" % str(GameData.get_record(line).get("display_name", line.get_slice(".", 1).capitalize()))


# --------------------------------------------------------------------------- drawing the tiles

## The section's tile size: `columns` across the page's width between the margins, `aspect` high.
static func tile_size(section: Dictionary) -> Vector2i:
	var cols := maxi(1, int(section.columns))
	var w := int(floor(float(PAGE_W - 2 * MARGIN - (cols - 1) * GAP) / float(cols)))
	return Vector2i(w, int(round(float(w) * float(section.aspect))))


## Draws every tile of `section` (POOL at a time) and keeps its image in tile.image.
func _render_section(section: Dictionary) -> void:
	var size := tile_size(section)
	var todo: Array = []
	for tile: Dictionary in section.tiles:
		if tile.has("image_path"):
			tile["image"] = _approved(str(tile.image_path), size)
		else:
			todo.append(tile)
	var i := 0
	while i < todo.size():
		var batch: Array = todo.slice(i, i + POOL)
		for k in POOL:
			var p := _pool[k]
			p.visible = k < batch.size()
			if k < batch.size():
				_set_up(p, batch[k], size)
		for f in (FRAMES_FIRST if _frames == 0 else FRAMES_EACH):
			await RenderingServer.frame_post_draw
		_frames += 1
		for k in batch.size():
			(batch[k] as Dictionary)["image"] = _pool[k].viewport.get_texture().get_image()
			_tiles += 1
		i += POOL


func _set_up(p: GiantPreview, tile: Dictionary, size: Vector2i) -> void:
	p.custom_minimum_size = Vector2(size)
	p.size = Vector2(size)
	p.viewport.size = size
	var tier := str(tile.get("tier", ""))
	if tier != "" and GiantLook.built_tier(p.model) != tier or tier == "" and p.get_meta("sheet_tier", "") != "":
		var forced := GiantLook.forced_tier
		GiantLook.forced_tier = ""
		GiantLook.build_materials(p.model, p.index(), tier if tier != "" else "auto")
		GiantLook.forced_tier = forced
		p.set_meta("sheet_tier", tier)
	p.set_game_profile(_stage1)
	# P57: sheet B draws its framed tiles in the creator's studio light (a face against the world's sun was in shadow);
	# Game view and first person keep the world's light (GiantPreview.frame)
	p.world_light = sheet != "b"
	p.apply_look(Appearance.to_look(tile.record, str(tile.ancestry)))
	if str(tile.framing) == GiantPreview.AIM:
		p.frame_on(p.aim_box(tile.get("aim", []) as Array))   # P57: a belt piece, as the creator's picture aims at it
	else:
		p.frame(str(tile.framing))
	if float(tile.get("turn", 0.0)) != 0.0:
		p.turn(float(tile.turn))
	if float(tile.get("zoom", 0.0)) != 0.0:
		p.zoom(float(tile.zoom))
	_villager(p, bool(tile.get("villager", false)))
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## The game's villager beside the giant (page 1), the soldier's mirror across him.
func _villager(p: GiantPreview, show: bool) -> void:
	var v: Node3D = _villagers.get(p)
	if v == null and show:
		v = GiantPreview.figure_of(VILLAGER_SCENE)
		v.name = "Villager"
		p.world_root.add_child(v)
		_villagers[p] = v
	if v != null:
		var k := GiantPreview.stage_scale(_stage1)
		v.position = Vector3(-2.3 * k, 0.0, -1.7 * k)
		v.rotation_degrees = Vector3(0, 160, 0)
		v.visible = show


## An approved render, scaled to fit the tile (a dark tile when it was not given).
func _approved(path: String, size: Vector2i) -> Image:
	var img := Image.new()
	if path == "" or img.load(path) != OK:
		img = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
		img.fill(Color(0.18, 0.18, 0.2))
		return img
	img.convert(Image.FORMAT_RGB8)
	var s := minf(float(size.x) / img.get_width(), float(size.y) / img.get_height())
	img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	out.fill(Color(0.18, 0.18, 0.2))
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (size - img.get_size()) / 2)
	return out


# --------------------------------------------------------------------------- the page

## The page drawn into its own viewport: the title, the note, each section's title and its tiles with captions.
func _compose(page: Dictionary) -> Image:
	var root := Control.new()
	var y := MARGIN
	_label(root, str(page.title), Vector2(MARGIN, y), 38, INK)
	y += 54
	var tiered := false
	for section: Dictionary in page.sections:
		for t: Dictionary in section.tiles:
			tiered = tiered or t.has("tier")
	var renderer := "Godot %s, the Compatibility renderer (%s), %s" % [Engine.get_version_info().string,
		RenderingServer.get_video_adapter_name(), "the tiers as captioned" if tiered else
		"the %s texture tier" % GiantLook.built_tier(_pool[0].model)]
	_label(root, "%s  -  %s" % [str(page.note), renderer], Vector2(MARGIN, y), 17, DIM)
	y += 40
	for section: Dictionary in page.sections:
		_label(root, str(section.title), Vector2(MARGIN, y), 24, INK)
		y += 38
		var size := tile_size(section)
		var cols := int(section.columns)
		var tiles: Array = section.tiles
		for i in tiles.size():
			var t: Dictionary = tiles[i]
			var pos := Vector2(MARGIN + (i % cols) * (size.x + GAP), y + (i / cols) * (size.y + CAPTION_H + GAP))
			var rect := TextureRect.new()
			rect.position = pos
			rect.size = Vector2(size)
			if t.has("image"):
				rect.texture = ImageTexture.create_from_image(t.image)
			root.add_child(rect)
			var caption := _label(root, str(t.label) + ("" if not t.has("image_path") or str(t.image_path) != "" else
				" - not given (--renders=)"), pos + Vector2(0, size.y + 3), 16, INK)
			caption.size = Vector2(size.x, CAPTION_H - 4)
			caption.clip_text = true
			caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var rows := int(ceil(float(tiles.size()) / float(cols)))
		y += rows * (size.y + CAPTION_H + GAP) + 14
	var height := y + MARGIN
	var vp := SubViewport.new()
	vp.size = Vector2i(PAGE_W, height)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(PAGE_W, height)
	vp.add_child(bg)
	vp.add_child(root)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return img


func _label(parent: Control, text: String, pos: Vector2, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l
