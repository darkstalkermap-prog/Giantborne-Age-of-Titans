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
##   b9 (P61) the rival giants' looks on the player's model (the npc presets the creator never offers: Appearance.is_npc):
##      each from the front, behind, his right, the head and the shoulders, and the garments and the beard's rings alone
## Sheet C (P64; plan M11 §3.17 design 5: the people sheet), the brutes, the bosses and the wolves as the game draws
## them skinned (BruteRig, SkinnedWolfRig: the actors themselves, AI off, in a stage of the world's light), a soldier
## of the people's at 1.8 m beside each for scale:
##   c1 the ogre, the troll and the whelp: front, three-quarter, side and the head; idle, a walk and an attack's wind-up
##   c2 the Ogre King and the Troll Matriarch with their gear: front, back, three-quarter, the head and the crown
##   c3 the wolf and the dire wolf: front, side, three-quarter and the head, the fur shell on and off; the bite
##   c4 (P64c) every human role and named character: front, side and three-quarter, and beside the giant at stages 1
##      and 4
##   c5 (P64c) the rival giant and Harrok beside the stage-1 giant and a soldier, facing the camera; a formation of
##      forty from the front at 25 m and at 60 m for three factions
## Sheet D (A1: Stoneback, the quarry titan, before his fight is built): StonebackRig (his model and clips, no actor)
## in the same stage:
##   d1 the turnaround at the neutral light: front, his left side, back, three-quarter (the idle); the walk from his
##      left side at two phases half a stride apart (A1b)
##   d2 the scale line-up (a soldier at 6 ft, the player giant at 26 ft and at 62 ft, Stoneback at 55 ft) and the
##      close-ups: the head, the plates, the shackles, the club
##   d3 the plates hidden: all on, the shoulders' off, the back's off, the brow's off, all off (front and back);
##      the three attacks' wind-ups (overhead, the shoulder charge, the boulder throw) from two sides
## A main scene, not a -s script (Appearance and GiantPreview read the autoloads' data). Run under Xvfb:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1920x1080x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --audio-driver Dummy res://tools/character_sheet.tscn -- \
##     [--out=docs/screenshots/m10/] [--renders=<folder with test_studio_full34.png, test_outdoor_head.png>] \
##     [--pages=1,2,3,4a,4b,5,6] [--sheet=a] [--jpg]
##   ... -- --sheet=b --out=<dir> [--pages=b1,...] [--creator-shots=<dir>,<dir>]
##   ... -- --sheet=c --out=<dir> [--pages=c1,c2,c3,c4,c5]
##   ... -- --sheet=d --out=<dir> [--pages=d1,d2,d3]
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
const WATCHDOG_S := 1800.0
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
	if sheet == "c":
		return pages_c()
	if sheet == "d":
		return pages_d()
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
	# b9 - P61: the rival giants' looks (never in the creator: only this page draws them)
	var npc: Array = []
	var ids := GameData.ids_of_type("appearance_preset")
	ids.sort()
	for pid: String in ids:
		if not Appearance.is_npc(GameData.get_record(pid)):
			continue
		var rec := Appearance.preset_record(pid)
		var words := str(GameData.get_record(pid).get("display_name", pid))
		npc.append(_tile(words, rec, "full"))
		npc.append(_tile(words + " - behind", rec, "back"))
		npc.append(_tile(words + " - his right", rec, "full", "", -70.0))
		npc.append(_tile(words + " - head", rec, "head"))
		npc.append(_tile(words + " - shoulders", rec, "shoulders"))
		npc.append(_tile(words + " - the beard's rings", rec, "neck"))
	var plain := Appearance.default_record()
	var gear: Array = []
	for id: String in ["garment.hide_mantle", "garment.war_harness"]:
		var g := OptionRows.with_value(plain, "outfit.slots.%s.item" % str(Appearance.option(id).get("slot", "")), id)
		gear.append(_tile(str(Appearance.option(id).get("name", id)), g, "full"))
		gear.append(_tile(str(Appearance.option(id).get("name", id)) + " - behind", g, "back"))
	if not npc.is_empty():
		out.append({"id": "b9", "name": "npc_looks", "title": "B9. The rival giants' looks (never offered by the creator)",
			"note": "The npc presets on the player's model at stage 1, in the world's light: P62 puts them on the rival giant (10 m) and Harrok (15 m).",
			"sections": [{"title": "The looks", "columns": 6, "aspect": 1.0, "tiles": npc},
				{"title": "Their garments on the default giant", "columns": 4, "aspect": 1.25, "tiles": gear}]})
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
		elif tile.has("creature"):
			tile["image"] = await _creature_tile(tile, size)
			_tiles += 1
		elif tile.has("titan"):
			tile["image"] = await _titan_tile(tile, size)
			_tiles += 1
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


# --------------------------------------------------------------------------- sheet C: the people sheet (P64)

const SOLDIER_SCENE := "res://scenes/enemies/soldier.tscn"
## [scene, record, label, height (m)]
const BRUTES := [["res://scenes/enemies/ogre.tscn", "enemy.ogre", "The ogre", 3.4],
	["res://scenes/enemies/troll.tscn", "enemy.troll", "The troll", 5.5],
	["res://scenes/enemies/troll_whelp.tscn", "enemy.troll_whelp", "The whelp", 3.5]]
const BOSSES := [["res://scenes/enemies/ogre_king.tscn", "enemy.ogre_king", "The Ogre King", 8.5],
	["res://scenes/enemies/troll_matriarch.tscn", "enemy.troll_matriarch", "The Troll Matriarch", 9.0]]
## (a wolf's fifth item: its views stand back this much further - a quadruped is long for its height; P64b)
const WOLVES := [["res://scenes/enemies/wolf.tscn", "enemy.wolf", "The wolf", 0.9, 2.3],
	["res://scenes/enemies/dire_wolf.tscn", "enemy.dire_wolf", "The dire wolf", 1.8, 2.3]]
## The views: the camera's direction from the creature (its front faces +Z here) and the share of its height looked at.
## P64c: page c4's people [scene, record, label, height] and page c5's rival giants and formation factions.
const PEOPLE := [["res://scenes/enemies/soldier.tscn", "enemy.soldier", "The soldier", 1.8],
	["res://scenes/enemies/pikeman.tscn", "enemy.pikeman", "The pikeman", 1.8],
	["res://scenes/enemies/shieldman.tscn", "enemy.shieldman", "The shieldman", 1.8],
	["res://scenes/enemies/archer.tscn", "enemy.archer", "The archer", 1.8],
	["res://scenes/enemies/mage.tscn", "enemy.mage", "The mage", 1.8],
	["res://scenes/enemies/siege_crew.tscn", "enemy.siege_crew", "The siege crew", 1.8],
	["res://scenes/enemies/bannerman.tscn", "enemy.bannerman", "The bannerman", 1.8],
	["res://scenes/enemies/corvane.tscn", "enemy.corvane", "Corvane", 1.8],
	["res://scenes/enemies/cavalry.tscn", "enemy.cavalry", "The cavalry", 2.6],
	["res://scenes/npcs/villager.tscn", "npc.villager", "The villager", 1.8],
	["res://scenes/npcs/elder.tscn", "npc.elder", "The elder", 1.8]]
const RIVALS := [["res://scenes/enemies/rival_giant.tscn", "enemy.rival_giant", "The rival giant", 10.0],
	["res://scenes/enemies/harrok.tscn", "enemy.harrok", "Harrok the Unbowed", 15.0]]
const FORMATION_FACTIONS := ["brannock", "aldmere", "skarn"]
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const VIEWS := {"front": [Vector3(0.0, 0.12, 1.0), 0.55, 1.6], "three_quarter": [Vector3(0.75, 0.2, 0.7), 0.55, 1.6],
	"side": [Vector3(1.0, 0.08, 0.0), 0.5, 1.6], "back": [Vector3(-0.2, 0.15, -1.0), 0.55, 1.6],
	"head": [Vector3(0.35, 0.1, 1.0), 0.86, 0.45]}

var _stage: SubViewport = null
var _stage_root: Node3D = null
var _stage_cam: Camera3D = null
var _standing := {}   # the still creature kept for its next view: {key, e, s}


func pages_c() -> Array:
	PersonRig.enable_for_tests()   # the people and the creatures drawn skinned, as with a display in play
	var out: Array = []
	var brutes: Array = []
	for b: Array in BRUTES:
		var tiles: Array = []
		for v: String in ["front", "three_quarter", "side", "head"]:
			tiles.append(_creature(b, v, "%s, %s" % [b[2], v.replace("_", "-")]))
		tiles.append(_with(_creature(b, "three_quarter", "%s walking" % b[2]), {"walk": true}))
		tiles.append(_with(_creature(b, "three_quarter", "%s, an attack's wind-up" % b[2]), {"attack": true}))
		brutes.append({"title": str(b[2]), "columns": 6, "aspect": 1.25, "tiles": tiles})
	out.append({"id": "c1", "name": "brutes", "title": "C1. The brutes in play", "sections": brutes,
		"note": "BruteRig on P63's and P65a's creatures: the clips on the brain's clock, the club in the fist; a soldier at 1.8 m for scale"})
	var bosses: Array = []
	for b: Array in BOSSES:
		var tiles: Array = []
		for v: String in ["front", "back", "three_quarter", "side", "head"]:
			tiles.append(_creature(b, v, "%s, %s" % [b[2], v.replace("_", "-")]))
		tiles.append(_with(_creature(b, "three_quarter", "%s, an attack's wind-up" % b[2]), {"attack": true}))
		bosses.append({"title": str(b[2]), "columns": 6, "aspect": 1.25, "tiles": tiles})
	out.append({"id": "c2", "name": "bosses", "title": "C2. The bosses and their gear", "sections": bosses,
		"note": "The King's mantle, belt and crown; the Matriarch's hide cloak and bone crown; always skinned"})
	var wolves: Array = []
	for w: Array in WOLVES:
		var tiles: Array = []
		for v: String in ["front", "side", "three_quarter", "head"]:
			tiles.append(_creature(w, v, "%s, %s, the fur shell" % [w[2], v.replace("_", "-")]))
			tiles.append(_with(_creature(w, v, "%s, %s, no shell (low)" % [w[2], v.replace("_", "-")]), {"fur": false}))
		wolves.append({"title": str(w[2]), "columns": 4, "aspect": 0.75, "tiles": tiles})
	out.append({"id": "c3", "name": "wolves", "title": "C3. The wolves, the fur shell on and off", "sections": wolves,
		"note": "SkinnedWolfRig: P63's wolf on its 25 bones, the shell's twelve layers in one draw (none at low, the Web)"})
	# P64c (the owner's checkpoint): every human role and named character, and the giants beside them
	var people: Array = []
	for p: Array in PEOPLE:
		var tiles: Array = []
		for v: String in ["front", "side", "three_quarter"]:
			tiles.append(_with(_creature(p, v, "%s, %s" % [p[2], v.replace("_", "-")]), {"alone": true}))
		for st: int in [1, 4]:
			tiles.append(_with(_creature(p, "three_quarter", "%s beside the giant at stage %d" % [p[2], st]), {"giant": st}))
		people.append({"title": str(p[2]), "columns": 5, "aspect": 1.25, "tiles": tiles})
	out.append({"id": "c4", "name": "people", "title": "C4. The people: every role and named character", "sections": people,
		"note": "PersonRig skinned (P59's bodies, the record's variant and palette by the entity id): front, side and three-quarter; beside the giant at stages 1 and 4"})
	var giants: Array = []
	for g: Array in RIVALS:
		var tiles: Array = []
		for v: String in ["front", "three_quarter"]:
			tiles.append(_with(_creature(g, v, "%s, %s, the player and a soldier beside him" % [g[2], v.replace("_", "-")]), {"giant": 1}))
		giants.append({"title": str(g[2]), "columns": 2, "aspect": 0.75, "tiles": tiles})
	var ranks: Array = []
	for fac: String in FORMATION_FACTIONS:
		for d: float in [25.0, 60.0]:
			ranks.append({"label": "forty of the %s from the front at %d m" % [fac, int(d)], "creature": SOLDIER_SCENE,
				"record": "enemy.soldier", "height": 1.8, "view": "front", "formation": fac, "distance": d})
	giants.append({"title": "A formation of forty, three factions", "columns": 2, "aspect": 0.5625, "tiles": ranks})
	out.append({"id": "c5", "name": "giants_and_ranks", "title": "C5. The rival giants beside the player; the ranks",
		"sections": giants, "note": "The rival giant and Harrok (SkinnedRig, their own looks) beside the stage-1 giant and a soldier, facing the camera; forty soldiers as the game levels them (skinned near, the crowd beyond)"})
	return out


func _creature(spec: Array, view: String, label: String) -> Dictionary:
	return {"label": label, "creature": spec[0], "record": spec[1], "height": spec[3], "view": view,
		"frame": float(spec[4]) if spec.size() > 4 else 1.0}


## One creature tile: the actor in the stage (with a soldier beside it), posed, seen from its view. P64b: a still
## tile (no walk, no attack) keeps the creature and its soldier standing for the next still tile of the same creature
## (one spawn for its views, not one a view: page c3 ran past the watchdog on a loaded machine).
func _creature_tile(tile: Dictionary, size: Vector2i) -> Image:
	if _stage == null:
		_make_stage()
	_stage.size = size
	var h := float(tile.height)
	if tile.has("formation"):
		return await _formation_tile(tile, size)
	var still := not bool(tile.get("walk", false)) and not bool(tile.get("attack", false)) and not tile.has("giant")
	var key := str(tile.creature) + ("#alone" if bool(tile.get("alone", false)) else "")
	if not _standing.is_empty() and (not still or str(_standing.key) != key):
		_free_standing()
	var e: Node3D
	var s: Node3D
	if still and not _standing.is_empty():
		e = _standing.e
		s = _standing.s
		await get_tree().process_frame
	else:
		e = (load(str(tile.creature)) as PackedScene).instantiate() as Node3D
		e.set("entity_id", "sheet." + str(tile.record))
		e.set("ai_enabled", false)
		e.rotation.y = PI   # its front toward +Z
		_stage_root.add_child(e)
		if tile.has("giant") or bool(tile.get("alone", false)):
			s = Node3D.new()   # (P64c: alone, or the giant instead below)
			_stage_root.add_child(s)
		else:
			s = (load(SOLDIER_SCENE) as PackedScene).instantiate() as Node3D
			s.set("entity_id", "sheet.soldier")
			s.set("ai_enabled", false)
			s.position = Vector3(-maxf(1.4, h * 0.55), 0.0, -0.5)
			s.rotation.y = PI * 0.85
			_stage_root.add_child(s)
		if tile.has("giant"):
			_giant_beside(s, int(tile.giant), h)
		for i in 10:
			await get_tree().process_frame
		if still:
			_standing = {"key": key, "e": e, "s": s}
	var vis := e.get_node("Visual")
	if vis.has_method("fur") and vis.call("fur") != null:
		(vis.call("fur") as Node3D).visible = bool(tile.get("fur", true))
	if bool(tile.get("walk", false)):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		vis.process_mode = Node.PROCESS_MODE_ALWAYS
		var speed := float(GameData.get_record(str(tile.record)).get("walk_speed_mps", 2.0))
		for i in 24:
			e.set("velocity", Vector3(0, 0, speed))
			e.position.z += speed / 60.0
			await get_tree().process_frame
		e.position.z = 0.0
		await get_tree().process_frame
	elif bool(tile.get("attack", false)):
		var actions: Array = GameData.get_record(str(tile.record)).get("attacks", [])
		var a := GameData.get_action(str(actions[0])) if not actions.is_empty() else null
		if a != null:
			var c := e.get("controller") as CombatController
			c.request(&"attack", {"action_id": a.id})
			for i in 600:   # (the frames are slower than the ticks here: wait for the wind-up's end itself)
				if c.action == null or c.phase() != ActionDef.Phase.WINDUP or c.phase_fraction() >= 0.85:
					break
				await get_tree().process_frame
	var v: Array = VIEWS[str(tile.view)]
	var look := Vector3(0.0, h * float(v[1]), 0.0)
	var sk := vis.find_child("Skeleton3D", true, false) as Skeleton3D
	if str(tile.view) == "head" and sk != null and sk.find_bone("head") >= 0:
		look = sk.global_transform * (sk.get_bone_global_pose(sk.find_bone("head")) * Vector3(0.0, 0.08 * h / 3.4, 0.0)) \
			if h > 2.0 else sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head")).origin
	if tile.has("giant") and h < 5.0:
		# (framed on the giant beside the person, the two side by side)
		var gh := GiantPreview.STAGE1_HEIGHT_M * GiantPreview.stage_scale(GiantPreview.stage_profile(int(tile.giant)))
		h = maxf(h, gh)
		look = Vector3(-gh * 0.22, h * float(v[1]), 0.0)
	var frame := float(tile.get("frame", 1.0))
	var dist := maxf(h * float(v[2]) * (frame if str(tile.view) != "head" else sqrt(frame)),
		1.2 if str(tile.view) != "head" else 0.7)
	_stage_cam.global_position = look + (v[0] as Vector3).normalized() * dist
	_stage_cam.look_at(look, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _stage.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if _standing.is_empty() or _standing.e != e:
		e.queue_free()
		s.queue_free()
		await get_tree().process_frame
	return img


## P64c: the giant at `stage` (giant_model.tscn in his default look, relaxed) beside the subject under `holder`, to
## the subject's right as the camera sees it; for a giant subject (c5) the stage-1 giant and a soldier beside him.
func _giant_beside(holder: Node3D, stage: int, h: float) -> void:
	var m := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
	holder.add_child(m)
	GiantLook.build_materials(m, m.index, "auto")
	m.apply_defaults()
	m.pose_relaxed()
	var k := GiantPreview.stage_scale(GiantPreview.stage_profile(stage))
	m.scale = Vector3.ONE * k
	m.rotation.y = PI   # facing the camera (+Z)
	var gh := GiantPreview.STAGE1_HEIGHT_M * k
	m.position = Vector3(-(maxf(h, gh) * 0.18 + gh * 0.22 + 0.6), 0.0, -0.3)
	if h > 5.0:
		var s := (load(SOLDIER_SCENE) as PackedScene).instantiate() as Node3D
		s.set("entity_id", "sheet.soldier_beside")
		s.set("ai_enabled", false)
		s.position = m.position + Vector3(-gh * 0.35 - 0.8, 0.0, 0.4)
		holder.add_child(s)
		s.rotation.y = PI


## P64c: forty soldiers of `tile.formation` in five ranks of eight, seen from the front at `tile.distance` metres,
## levelled as the game levels them (the nearest skinned, the rest drawn by the crowd's renderer); a stand-in giant
## at the camera gives the people their distances.
func _formation_tile(tile: Dictionary, size: Vector2i) -> Image:
	if _stage == null:
		_make_stage()
	if not _standing.is_empty():
		_free_standing()
	_stage.size = size
	var d := float(tile.distance)
	var holder := Node3D.new()
	_stage_root.add_child(holder)
	var giant := Node3D.new()
	giant.position = Vector3(0.0, 0.0, d)
	giant.add_to_group("player")
	holder.add_child(giant)
	for i in 40:
		var e := (load(str(tile.creature)) as PackedScene).instantiate() as Node3D
		e.set("entity_id", "sheet.rank_%s_%d" % [tile.formation, i])
		e.set("ai_enabled", false)
		e.set("faction", str(tile.formation))
		e.position = Vector3((float(i % 8) - 3.5) * 1.1, 0.0, -float(i / 8) * 1.3)
		e.rotation.y = PI
		holder.add_child(e)
	for i in 12:
		await get_tree().process_frame
		var lr := PersonRig.loner_renderer()
		if lr != null and lr.is_inside_tree() and lr.get_parent() != _stage_root:
			lr.get_parent().remove_child(lr)   # (into the stage's own world)
			_stage_root.add_child(lr)
	_stage_cam.global_position = Vector3(0.0, 2.4, d)
	_stage_cam.look_at(Vector3(0.0, 0.9, -2.6), Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _stage.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_stage_root.remove_child(holder)
	holder.queue_free()
	await get_tree().process_frame
	return img


func _free_standing() -> void:
	for n: Node in [_standing.e, _standing.s]:
		n.get_parent().remove_child(n)   # (out of the tree now: the next spawn takes the same entity ids)
		n.queue_free()
	_standing = {}


## The stage: its own world in the world's light (a sun with shadows, the sky's ambient, a grass ground).
func _make_stage() -> void:
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_stage)
	_stage_root = Node3D.new()
	_stage.add_child(_stage_root)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.55, 0.65, 0.78)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	we.environment.ambient_light_energy = 0.55
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_stage_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	_stage_root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.46, 0.32)
	gm.roughness = 0.95
	ground.material_override = gm
	_stage_root.add_child(ground)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	_stage_root.add_child(floor_body)
	_stage_cam = Camera3D.new()
	_stage_cam.fov = 40.0
	_stage_cam.near = 0.05
	_stage_root.add_child(_stage_cam)
	_stage_cam.current = true


# --------------------------------------------------------------------------- sheet D: Stoneback (A1)

const TITAN_H := 16.8
## The line-up's heights (m): 6 ft, 26 ft, 62 ft.
const SOLDIER_H := 1.8288
const GIANT_26_H := 7.9248
const GIANT_62_H := 18.8976
## [label, focus (a bone, a piece, or "club_head"), the camera's direction from it, its distance (m), lift (m)]
const TITAN_CLOSE := [["The head (the brow plate on)", "head", Vector3(0.45, 0.12, 1.0), 4.4, 0.45],
	["The left shoulder's plate", "upperarm_l", Vector3(0.85, 0.45, 0.55), 6.5, 0.3],
	["The back's plate", "spine_03", Vector3(-0.35, 0.3, -1.0), 11.0, 0.5],
	["The right forearm's plate and wrist shackle", "lowerarm_r", Vector3(-0.85, 0.2, 0.6), 5.0, -1.0],
	["The left wrist's shackle and broken chain", "hand_l", Vector3(0.8, 0.05, 0.7), 4.6, -0.3],
	["The ankles' shackles and the shins' plates", "calf_l", Vector3(0.3, 0.15, 1.0), 6.5, -1.6],
	["The club's grip in the right fist", "hand_r", Vector3(-0.7, 0.25, 1.0), 4.6, 0.0],
	["The club's head: the root ball", "club_head", Vector3(-0.4, 0.45, 1.0), 7.5, 0.0]]

var _titan: StonebackRig = null
var _lineup_nodes: Array = []


func _titan_tile_def(label: String, view: String, extra := {}) -> Dictionary:
	var t := {"label": label, "titan": true, "view": view}
	t.merge(extra, true)
	return t


func pages_d() -> Array:
	PersonRig.enable_for_tests()   # the soldier of the line-up skinned
	var out: Array = []
	var turn: Array = []
	for v: Array in [["front", "front"], ["side", "his left side"], ["back", "back"], ["three_quarter", "three-quarter"]]:
		turn.append(_titan_tile_def("Stoneback, %s (idle)" % v[1], str(v[0])))
	var walk: Array = []
	for w: Array in [[0.0, "the right foot forward"], [0.5, "the left foot forward"]]:
		walk.append(_titan_tile_def("The walk, his left side: %s" % w[1], "side", {"clip": "walk", "phase": w[0]}))
	out.append({"id": "d1", "name": "stoneback_turnaround", "title": "D1. Stoneback, the quarry titan: the turnaround",
		"note": "55 ft (16.8 m): StonebackRig on tools/giant/kit/stoneback.py's asset (A1; no fight yet), the stone plates on, the idle's first key; the walk's two phases",
		"sections": [{"title": "Front, his left side, back, three-quarter", "columns": 4, "aspect": 1.5, "tiles": turn},
			{"title": "The walk from his left side: two phases half a stride apart", "columns": 4, "aspect": 1.5, "tiles": walk}]})
	var close: Array = []
	for c: Array in TITAN_CLOSE:
		close.append(_titan_tile_def(str(c[0]), "close", {"focus": c[1], "dir": c[2], "dist": c[3], "lift": c[4]}))
	out.append({"id": "d2", "name": "stoneback_scale_closeups", "title": "D2. Stoneback's scale and close-ups",
		"note": "Left to right: a soldier at 6 ft (1.83 m), the player giant at 26 ft (7.92 m), Stoneback at 55 ft (16.8 m), the player giant at 62 ft (18.9 m)",
		"sections": [{"title": "The line-up, facing the camera", "columns": 1, "aspect": 0.42,
				"tiles": [_titan_tile_def("A soldier 6 ft, the giant 26 ft, Stoneback 55 ft, the giant 62 ft", "lineup", {"lineup": true})]},
			{"title": "Close up: the head, the plates, the shackles, the club", "columns": 4, "aspect": 0.8, "tiles": close}]})
	var states := [["All plates on", []], ["The shoulders' plates off", ["plate_shoulder_l", "plate_shoulder_r"]],
		["The back's plate off", ["plate_back"]], ["The brow's plate off", ["plate_brow"]],
		["All plates off", Array(StonebackRig.WEAK_PLATES) + Array(StonebackRig.LIMB_PLATES)]]
	var hidden_tiles: Array = []
	for st: Array in states:
		hidden_tiles.append(_titan_tile_def("%s - three-quarter" % st[0], "three_quarter", {"hidden": st[1]}))
	for st: Array in states:
		hidden_tiles.append(_titan_tile_def("%s - from behind" % st[0], "back_quarter", {"hidden": st[1]}))
	var heads: Array = []
	for st: Array in [states[0], states[3]]:
		heads.append(_titan_tile_def("%s - the head" % st[0], "close", {"hidden": st[1], "focus": "head",
			"dir": Vector3(0.45, 0.12, 1.0), "dist": 4.4, "lift": 0.45}))
	var attacks: Array = []
	for a: Array in [["overhead", "The trunk-club's overhead wind-up"], ["charge", "The shoulder charge's lean"],
			["throw", "The boulder throw's wind-up"]]:
		attacks.append(_titan_tile_def("%s - three-quarter" % a[1], "three_quarter", {"clip": a[0], "windup": true}))
		attacks.append(_titan_tile_def("%s - his right side" % a[1], "right", {"clip": a[0], "windup": true}))
	out.append({"id": "d3", "name": "stoneback_plates_attacks", "title": "D3. The plates hidden; the attacks' wind-ups",
		"note": "Each plate is its own mesh (StonebackRig.set_plate_visible): under the shoulders', the back's and the brow's (the weak points a later package exposes) the skin is paler and scarred",
		"sections": [{"title": "The plates: all on, the shoulders' off, the back's off, the brow's off, all off", "columns": 5,
				"aspect": 1.35, "tiles": hidden_tiles},
			{"title": "The brow plate on and off, close", "columns": 5, "aspect": 0.8, "tiles": heads},
			{"title": "The wind-ups (each clip's last key)", "columns": 6, "aspect": 1.2, "tiles": attacks}]})
	return out


## One tile of sheet D: Stoneback posed and plated as the tile says, seen from its view (a close-up on its focus);
## the line-up with the soldier and the two player giants beside him.
func _titan_tile(tile: Dictionary, size: Vector2i) -> Image:
	if _stage == null:
		_make_stage()
	if not _standing.is_empty():
		_free_standing()
	_stage.size = size
	if _titan == null:
		_titan = StonebackRig.new()
		_titan.name = "Stoneback"
		_stage_root.add_child(_titan)
	var clip := str(tile.get("clip", "idle"))
	if bool(tile.get("windup", false)):
		_titan.pose_windup(clip)
	elif tile.has("phase"):
		_titan.pose(clip, float(tile.phase) * _titan.clip_length(clip))
	else:
		_titan.pose(clip, float(tile.get("t", 0.0)))
	_titan.set_plates(true)
	for n: Variant in tile.get("hidden", []):
		_titan.set_plate_visible(str(n), false)
	var lineup := bool(tile.get("lineup", false))
	if lineup and _lineup_nodes.is_empty():
		_make_lineup()
	for n: Node3D in _lineup_nodes:
		n.visible = lineup
	_titan.position = Vector3(2.0, 0.0, 0.0) if lineup else Vector3.ZERO
	for i in (14 if lineup else 2):
		await get_tree().process_frame
	var h := TITAN_H
	var view := str(tile.view)
	var look := Vector3(0.0, h * 0.52, 0.0)
	var dir := Vector3(0.0, 0.1, 1.0)
	var dist := h * 1.6
	match view:
		"front":
			dir = Vector3(0.0, 0.1, 1.0)
		"side":
			dir = Vector3(1.0, 0.08, 0.0)
		"right":
			dir = Vector3(-1.0, 0.1, 0.15)
		"back":
			dir = Vector3(0.0, 0.12, -1.0)
		"three_quarter":
			dir = Vector3(0.75, 0.16, 0.7)
		"back_quarter":
			dir = Vector3(-0.7, 0.2, -0.75)
		"lineup":
			look = Vector3(-1.0, 9.6, 0.0)
			dir = Vector3(0.0, 0.08, 1.0)
			dist = 31.0
		"close":
			var focus := str(tile.focus)
			look = _titan.club_head() if focus == "club_head" else _titan.bone_position(focus)
			look += Vector3(0.0, float(tile.get("lift", 0.0)), 0.0)
			dir = tile.dir
			dist = float(tile.dist)
	if view != "close" and view != "lineup" and clip != "idle":
		look.y = h * 0.5
	if tile.has("phase"):
		# (the walk: framed on his pelvis, a little farther, the whole stride in the tile)
		var pel := _titan.bone_position("pelvis")
		look = Vector3(pel.x, h * 0.48, pel.z)
		dist = h * 1.9
	_stage_cam.global_position = look + dir.normalized() * dist
	_stage_cam.look_at(look, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _stage.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


## The line-up (left of Stoneback, then right of him, facing the camera): a soldier (6 ft), the player giant at 26 ft,
## and the player giant at 62 ft.
func _make_lineup() -> void:
	var s := (load(SOLDIER_SCENE) as PackedScene).instantiate() as Node3D
	s.set("entity_id", "sheet.lineup_soldier")
	s.set("ai_enabled", false)
	s.position = Vector3(-15.5, 0.0, 1.0)
	s.rotation.y = PI
	_stage_root.add_child(s)
	_lineup_nodes.append(s)
	for g: Array in [[GIANT_26_H, Vector3(-11.0, 0.0, 0.5)], [GIANT_62_H, Vector3(12.5, 0.0, 0.0)]]:
		var m := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
		_stage_root.add_child(m)
		GiantLook.build_materials(m, m.index, "auto")
		m.apply_defaults()
		m.pose_relaxed()
		m.scale = Vector3.ONE * (float(g[0]) / GiantPreview.STAGE1_HEIGHT_M)
		m.rotation.y = PI
		m.position = g[1]
		_lineup_nodes.append(m)


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
