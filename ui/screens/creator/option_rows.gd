class_name OptionRows
extends RefCounted
## The creator's categories and their rows (P44; plan M10 §2.10): what each category shows, the row widgets
## and the record paths they read and write. CreatorScreen builds a category's rows with build_rows() and
## turns every pick into a new record with with_value() / with_scar(); nothing here touches a node outside
## the rows it makes, the preview or the simulation.
##
## Row kinds (the P16 focus rules: a row is one line of focusable controls, up / down between rows):
##   * swatch  - a row of colour buttons, every one named; moving the focus onto a swatch applies it at once
##               (moving previews and keeps, like the cyclers), A or a click too. The focus that enters the
##               row with the keyboard or the pad lands on the chosen swatch; a mouse press stays on the
##               swatch it pressed and applies it (M10 gate, LA-2). A locked swatch takes the
##               focus but applies nothing: the line under the row says why ("Choose your line at a shrine of
##               the Old Kingdom").
##   * cycler  - one focusable button "<  Long, combed back  >": left / right (D-pad, arrows) step through the
##               choices and apply each at once; A or a click steps forward, a click on its left third back.
##               Its own left and right are consumed, so the focus never leaves it sideways.
##   * slider  - an HSlider (the greys): left / right move it; the changes of one slider in a row are one step
##               of the undo history.
##   * toggle  - a CheckButton (scars): A or a click turns it on or off.
##   * preset  - a button per preset: A or a click puts the whole preset on. The focused preset's description
##               shows in one place under the list (CreatorScreen's), so that no button moves when the focus
##               does: a mouse press moves the focus, and a button that jumps under the pointer between the
##               press and the release loses the click (M10 gate, LA-1).
## Every design row (tattoos, war paint, scars, the ancestry mark) has a note line that says "Hidden by your
## clothing" while the current outfit covers its region (Appearance.covered_regions with the giant's index).
##
## P53 (plan M11 §2.5): the record is version 2 (clothing by slot). The record paths M10's rows used
## ("outfit.primary", "outfit.secondary", "paint.design") still read and write the same values (LEGACY_KEYS,
## PAINT_ROW), for the sheets and the probes that name them.
##
## P55, the creator II (plan M11 §2.7, §3.8): eleven categories (CATEGORIES); every row is built from the sets'
## data, so a set that grows (P54's wardrobe, P56's catalogue) shows its new options without an edit, and an empty
## set shows a grid with "None" alone. New row kinds:
##   * grid    - a row naming its value ("Chest   Tunic"): A, Enter or a click opens the option grid (OptionGrid,
##               CreatorScreen's: pages of thumbnails, "None" first, the material filter, the name filter); left
##               and right step through the choices as a cycler did, applying each. The ten clothing slots, the
##               outfits (starting points: "Custom" once a slot differs), the three accessory slots, the hair
##               and beard styles, beads, the five tattoo regions and the war paint's two places.
##   * slider  - also signed (`signed`: -1 to 1 within `limit`): the build (brawn, girth) and the face sliders
##               (the face set, P56); every slider steps by SLIDER_PAD_STEP with the pad or the arrows and snaps
##               to 0 within SNAP_ZERO (the grey sliders to their 0 end).
## The Colours category has the outfit's three dyes (cloth, leather, metal) and a row of the slot's own dye for
## every worn garment that takes one ("Outfit's dye" first: the outfit's dye of its material).

## The creator's categories, in tab order (P55: plan M11 §2.7).
const CATEGORIES := ["Presets", "Body", "Face", "Hair", "Beard", "Tattoos", "War paint", "Scars", "Clothing",
	"Accessories", "Colours"]
## M10's category names that are now a part of another (the sheets, the probes and older tests name them).
const CATEGORY_ALIASES := {"Skin": "Body", "Eyes": "Face"}
## The scope of a category's Randomize (Y / R): Appearance.random_record's, or this file's ("body", "face",
## "clothing", "accessories", "colours": random_record()).
const RANDOM_SCOPE := {"Presets": "presets", "Body": "body", "Face": "face", "Hair": "hair", "Beard": "beard",
	"Tattoos": "tattoos", "War paint": "paint", "Scars": "scars", "Clothing": "clothing", "Accessories": "accessories",
	"Colours": "colours"}
## The garment slots' names (Appearance.SLOTS order) and the accessory slots'.
const SLOT_NAMES := {"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "armour": "Armour", "arms": "Arms",
	"waist": "Waist", "legs": "Legs", "shins": "Shins", "feet": "Feet", "cape": "Cape"}
const ACCESSORY_NAMES := {"neck": "Neck", "arm_ring": "Arm ring", "belt": "Belt"}
## A slot's thumbnails' framing (GiantPreview.FRAMINGS) and the live preview's while its grid is open.
const SLOT_FRAMINGS := {"head": "head", "shoulders": "shoulders", "chest": "chest", "armour": "chest", "arms": "arms",
	"waist": "waist", "legs": "legs", "shins": "shins", "feet": "feet", "cape": "back", "neck": "chest",
	"arm_ring": "arms", "belt": "waist"}
const SLOT_PREVIEW := {"head": "head", "shoulders": "upper", "chest": "upper", "armour": "upper", "arms": "upper",
	"waist": "lower", "legs": "lower", "shins": "lower", "feet": "lower", "cape": "back", "neck": "upper",
	"arm_ring": "upper", "belt": "lower"}
## The note of a design row whose region the outfit covers (plan M10 §2.10, decision 18).
const HIDDEN_NOTE := "Hidden by your clothing"
## The beard colour that follows the hair's ("" in the record).
const SAME_AS_HAIR := "Same as hair"
## A slot's own dye that follows the outfit's dye of its material ("" in the record).
const OUTFITS_DYE := "Outfit's dye"
const NONE := "None"
## The Outfit row once the slots are no outfit's.
const CUSTOM := "Custom"
const MARK_SHOWN := "Shown"
const MARK_HIDDEN := "Hidden"
## Under the mark row before a line is chosen.
const MARK_NO_LINE := "Your line's mark shows here once you choose your line at a shrine of the Old Kingdom."
const SWATCH_PX := 34
const NOTE_COLOR := Color(1.0, 0.72, 0.35)
## The record paths of the design regions' tattoo rows (P53's fifth region: the legs).
const TATTOO_ROWS := {"tattoos.arms": "arms", "tattoos.chest": "chest", "tattoos.back": "back", "tattoos.face": "face",
	"tattoos.legs": "legs"}
## The war paint's two places (P53: a face paint and a body paint at once).
const PAINT_ROWS := {"paint.face": "face", "paint.body": "body"}
## M10's record paths of the dye rows and the record v2's paths they edit now (P53).
const LEGACY_KEYS := {"outfit.primary": "outfit.dyes.cloth", "outfit.secondary": "outfit.dyes.leather"}
## M10's one War paint row's path (its value is the record's first paint: Appearance.first_paint).
const PAINT_ROW := "paint.design"
## Sliders (plan M11 §2.7): a pad or arrow step, and the band around 0 a drag snaps to.
const SLIDER_PAD_STEP := 0.1
const SNAP_ZERO := 0.05
## The build sliders' reach (P53's follow-up: at +1 the thighs nearly double and at -1 the sleeves show steps; the
## record keeps -1 to 1, and a record beyond this reach shows the slider at its end).
const BUILD_LIMIT := 0.6
## Randomize by slot (random_record "clothing"): a worn slot changes to another of its pieces this often, an empty
## one is filled this often, a worn one (not the legs) is emptied this often.
const SWAP_P := 0.35
const ADD_P := 0.2
const DROP_P := 0.1
## An accessory slot is filled this often; a slot's own dye is set this often.
const ACCESSORY_P := 0.4
const SLOT_DYE_P := 0.15


# --------------------------------------------------------------------------- the categories

## The row specs of a category: [{key, kind, label, set?, region?, place?, slot?, id?, description?, framing?}], top
## to bottom. `key` is the record path the row edits ("hair.color", "tattoos.back", "outfit.slots.chest.item",
## "scar.brow", "preset.<id>"). Colours lists a slot's own dye for every garment `record` wears that takes one.
static func row_specs(category: String, record: Dictionary = {}) -> Array:
	category = str(CATEGORY_ALIASES.get(category, category))
	match category:
		"Presets":
			var out: Array = []
			for id: String in Appearance.preset_ids():
				var rec := GameData.get_record(id)
				out.append({"key": "preset." + id, "kind": "preset", "label": str(rec.get("display_name", id)),
					"id": id, "description": str(rec.get("description", ""))})
			return out
		"Body":
			var out: Array = [{"key": "skin", "kind": "swatch", "set": "skin", "label": "Skin tone"}]
			for o: Dictionary in Appearance.options("build", ""):
				out.append({"key": "build." + str(o.key), "kind": "slider", "signed": true, "limit": BUILD_LIMIT,
					"set": "build", "label": str(o.get("name", o.key)), "low": str(o.get("low", "")),
					"high": str(o.get("high", "")), "framing": GiantPreview.GAME_STAGE1})
			return out
		"Face":
			var out: Array = [{"key": "eyes", "kind": "swatch", "set": "eyes", "label": "Eye colour"}]
			for o: Dictionary in Appearance.options("face", ""):
				out.append({"key": "face." + str(o.key), "kind": "slider", "signed": true, "limit": 1.0, "set": "face",
					"label": str(o.get("name", o.key)), "low": str(o.get("low", "")), "high": str(o.get("high", ""))})
			return out
		"Hair", "Beard":
			var part := "hair" if category == "Hair" else "beard"
			var framing := "hair" if part == "hair" else "face"
			var out: Array = [{"key": part + ".style", "kind": "grid", "set": part, "label": "Style", "framing": framing,
				"thumb": "hair_close" if part == "hair" else "face"},
				{"key": part + ".color", "kind": "swatch", "set": "haircolor", "label": "Colour"},
				{"key": part + ".grey", "kind": "slider", "label": "Grey"}]
			if not Appearance.option_ids("bead").is_empty():
				out.append({"key": part + ".beads", "kind": "grid", "set": "bead", "label": "Beads", "framing": framing,
					"thumb": "hair_close" if part == "hair" else "face"})
			return out
		"Tattoos":
			var out: Array = []
			for key: String in TATTOO_ROWS:
				out.append({"key": key, "kind": "grid", "set": "tattoo", "region": TATTOO_ROWS[key],
					"label": str(TATTOO_ROWS[key]).capitalize()})
			out.append({"key": "tattoos.ink", "kind": "swatch", "set": "ink", "label": "Ink"})
			out.append({"key": "mark", "kind": "cycler", "set": "mark", "label": "Ancestry mark"})
			return out
		"War paint":
			return [{"key": "paint.face", "kind": "grid", "set": "paint", "place": "face", "label": "Face"},
				{"key": "paint.body", "kind": "grid", "set": "paint", "place": "body", "label": "Body"},
				{"key": "paint.color", "kind": "swatch", "set": "paintcolor", "label": "Colour"}]
		"Scars":
			var out: Array = []
			for id: String in Appearance.option_ids("scar"):
				out.append({"key": "scar." + id.get_slice(".", 1), "kind": "toggle", "set": "scar", "id": id,
					"label": str(Appearance.option(id).get("name", id))})
			return out
		"Clothing":
			var out: Array = [{"key": "outfit.set", "kind": "grid", "set": "outfit", "label": "Outfit", "framing": "full"}]
			for slot: String in Appearance.SLOTS:
				out.append({"key": "outfit.slots.%s.item" % slot, "kind": "grid", "set": "garment", "slot": slot,
					"label": str(SLOT_NAMES.get(slot, slot.capitalize())), "framing": str(SLOT_PREVIEW.get(slot, "full")),
					"thumb": str(SLOT_FRAMINGS.get(slot, "full"))})
			return out
		"Accessories":
			var out: Array = []
			for slot: String in Appearance.ACCESSORY_SLOTS:
				out.append({"key": "outfit.accessories." + slot, "kind": "grid", "set": "accessory", "slot": slot,
					"label": str(ACCESSORY_NAMES.get(slot, slot.capitalize())), "framing": str(SLOT_PREVIEW.get(slot, "full")),
					"thumb": str(SLOT_FRAMINGS.get(slot, "full"))})
			return out
		"Colours":
			var out: Array = [{"key": "outfit.dyes.cloth", "kind": "swatch", "set": "dye", "label": "Cloth"},
				{"key": "outfit.dyes.leather", "kind": "swatch", "set": "dye", "label": "Leather"},
				{"key": "outfit.dyes.metal", "kind": "swatch", "set": "metal", "label": "Metal"}]
			for slot: String in Appearance.SLOTS:
				var item := str(value_of(record, "outfit.slots.%s.item" % slot)) if not record.is_empty() else ""
				var palette := slot_palette(item)
				if palette == "":
					continue
				out.append({"key": "outfit.slots.%s.dye" % slot, "kind": "swatch", "set": palette, "slot": slot,
					"item": item, "label": "%s: %s" % [SLOT_NAMES.get(slot, slot), str(Appearance.option(item).get("name", item))]})
			return out
	return []


## The palette a garment's own dye comes from ("dye" for cloth and leather, "metal" for metal; "" for a fur or no
## garment: it takes none).
static func slot_palette(item: String) -> String:
	if item == "" or Appearance.option(item).is_empty():
		return ""
	return str(Appearance.DYE_SET.get(str(Appearance.option(item).get("material", "cloth")), ""))


## The worn garments whose own dye the Colours category lists ("<slot>=<item>" joined; its rows change with it).
static func dye_signature(record: Dictionary) -> String:
	var parts := PackedStringArray()
	for slot: String in Appearance.SLOTS:
		var item := str(value_of(record, "outfit.slots.%s.item" % slot))
		if slot_palette(item) != "":
			parts.append("%s=%s" % [slot, item])
	return ",".join(parts)


## The category that has a row of record path `key` ("" when none does; Colours for a slot's dye and M10's dye
## paths, War paint for M10's paint path).
static func category_of_key(key: String) -> String:
	if key.begins_with("outfit.slots.") and key.ends_with(".dye"):
		return "Colours"
	if LEGACY_KEYS.has(key):
		return "Colours"
	if key == PAINT_ROW:
		return "War paint"
	if key.begins_with("preset."):
		return "Presets"
	if key.begins_with("scar."):
		return "Scars"
	for category: String in CATEGORIES:
		for spec: Dictionary in row_specs(category):
			if str(spec.key) == key:
				return category
	return ""


## The choices of a swatch, cycler or grid row for a giant of `ancestry_id`: [{id, name, color?, material?,
## design?, locked, reason}] in data order. Optional rows start with "None" ("" - "bead.none" for beads): the
## design regions, the paint places, the garment and accessory slots; the beard's colour with "Same as hair" (""),
## a slot's own dye with "Outfit's dye" (""); the mark row is Shown ("auto") / Hidden ("none"). A grid's choices
## are the set's options of its region, place or slot.
static func choices(spec: Dictionary, ancestry_id: String) -> Array:
	var out: Array = []
	var key := str(spec.get("key", ""))
	var set_name := str(spec.get("set", ""))
	match key:
		"mark":
			return [{"id": Appearance.MARK_AUTO, "name": MARK_SHOWN, "locked": false, "reason": ""},
				{"id": Appearance.MARK_NONE, "name": MARK_HIDDEN, "locked": false, "reason": ""}]
		"beard.color":
			out.append({"id": "", "name": SAME_AS_HAIR, "locked": false, "reason": "", "same": true})
	if key.begins_with("outfit.slots.") and key.ends_with(".dye"):
		out.append({"id": "", "name": OUTFITS_DYE, "locked": false, "reason": "", "same": true})
	if set_name in ["tattoo", "paint", "garment", "accessory"]:
		out.append({"id": "", "name": NONE, "locked": false, "reason": ""})
	elif set_name == "bead":
		out.append({"id": Appearance.BEAD_NONE, "name": NONE, "locked": false, "reason": ""})
	var region := str(spec.get("region", ""))
	var place := str(spec.get("place", ""))
	var slot := str(spec.get("slot", "")) if set_name in ["garment", "accessory"] else ""
	for o: Dictionary in Appearance.options(set_name, ancestry_id):
		if region != "" and str(o.get("region", "")) != region:
			continue
		if place != "" and Appearance.paint_place(str(o.id)) != place:
			continue
		if slot != "" and str(o.get("slot", "")) != slot:
			continue
		if str(o.id) == Appearance.BEAD_NONE:
			continue
		var c := {"id": str(o.id), "name": str(o.get("name", o.id)), "locked": bool(o.locked), "reason": str(o.reason)}
		if str(o.get("color", "")) != "" and Color.html_is_valid(str(o.color)):
			c["color"] = Color.html(str(o.color))
			if set_name == "skin":
				c["color"] = GiantLook.drawn_tone(o)   # P51: the colour the skin draws at, not the record's
		if o.has("material"):
			c["material"] = str(o.material)
		if o.has("design"):
			c["design"] = str(o.design)
		out.append(c)
	return out


# --------------------------------------------------------------------------- the record paths

## The value a row shows from `record` (an option id, a grey, "auto"/"none", or a bool for a scar toggle).
static func value_of(record: Dictionary, key: String) -> Variant:
	if key.begins_with("scar."):
		var scars: Variant = record.get("scars", [])
		return typeof(scars) == TYPE_ARRAY and (scars as Array).has("scar." + key.get_slice(".", 1))
	if key.begins_with("preset."):
		return str(record.get("preset", "")) == key.substr(7)
	if key == PAINT_ROW:
		return Appearance.first_paint(record)
	var parts := str(LEGACY_KEYS.get(key, key)).split(".")
	var v: Variant = record
	for p: String in parts:
		if typeof(v) != TYPE_DICTIONARY:
			return ""
		v = (v as Dictionary).get(p, "")
	return v


## A copy of `record` with the row `key` set to `value`; any manual edit makes the look "custom" (its preset
## is cleared: the summary and SKIN_STATS read it). A preset row puts that preset's whole record on.
static func with_value(record: Dictionary, key: String, value: Variant) -> Dictionary:
	if key.begins_with("preset."):
		var rec := Appearance.preset_record(key.substr(7))
		return rec if not rec.is_empty() else record.duplicate(true)
	var out: Dictionary
	if key == "outfit.set":
		out = Appearance.with_outfit(record, str(value))
	elif key == PAINT_ROW:
		out = Appearance.with_paint(record, str(value))
	else:
		out = record.duplicate(true)
		_set_path(out, str(LEGACY_KEYS.get(key, key)).split("."), value)
	out["preset"] = ""
	return out


## Sets `value` at the record path `parts` inside `d` (the blocks on the way copied or made).
static func _set_path(d: Dictionary, parts: PackedStringArray, value: Variant) -> void:
	if parts.size() == 1:
		d[parts[0]] = value
		return
	var block: Dictionary = (d.get(parts[0]) as Dictionary).duplicate(true) if typeof(d.get(parts[0])) == TYPE_DICTIONARY else {}
	_set_path(block, parts.slice(1), value)
	d[parts[0]] = block


## A copy of `record` with the scar `scar_id` on or off (at most Appearance.MAX_SCARS: a fifth is refused and
## the record comes back as it was).
static func with_scar(record: Dictionary, scar_id: String, on: bool) -> Dictionary:
	var out := record.duplicate(true)
	var scars: Array = (out.get("scars") as Array).duplicate() if typeof(out.get("scars")) == TYPE_ARRAY else []
	if on and not scars.has(scar_id):
		if scars.size() >= Appearance.MAX_SCARS:
			return record.duplicate(true)
		scars.append(scar_id)
	elif not on:
		scars.erase(scar_id)
	out["scars"] = scars
	out["preset"] = ""
	return out


## True when two records describe the same look (numbers compared as numbers, so a grey read back from JSON
## as a float equals the slider's).
static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k: Variant in da:
			if not db.has(k) or not same(da[k], db[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same(a[i], b[i]):
				return false
		return true
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if na and nb:
		return absf(float(a) - float(b)) < 1e-6
	return typeof(a) == typeof(b) and a == b


# --------------------------------------------------------------------------- what a row shows and covers

## The design region a design row shows ("face", "chest", "back", "arms", "hand_l", or "" for a row that is not
## about a place on the body): a tattoo row's region, the war paint's and a scar's by their design, the
## mark's by the line's mark. The preview frames it while the row has the focus.
static func row_region(spec: Dictionary, record: Dictionary, index: Dictionary, ancestry_id: String) -> String:
	var key := str(spec.get("key", ""))
	if TATTOO_ROWS.has(key):
		return str(TATTOO_ROWS[key])
	match key:
		"paint.design", "paint.color":
			var o := Appearance.option(str(value_of(record, "paint.design")))
			return str(o.get("region", "face")) if not o.is_empty() else "face"
		"paint.face":
			return "face"
		"paint.body":
			var o := Appearance.option(str(value_of(record, key)))
			return str(o.get("region", "arms")) if not o.is_empty() else "arms"
		"mark":
			var m := Appearance.ancestry_mark(ancestry_id)
			return _design_region(str(m.get("design", "")), index) if not m.is_empty() else "arms"
		"tattoos.ink":
			for k: String in TATTOO_ROWS:
				if str(value_of(record, k)) != "":
					return str(TATTOO_ROWS[k])
			return "arms"
	if key.begins_with("scar."):
		return _design_region(str(Appearance.option(str(spec.get("id", ""))).get("design", "")), index)
	return ""


## The design region of a design id by its first body region in the index (the hand for region 10).
static func _design_region(design_id: String, index: Dictionary) -> String:
	var d: Variant = (index.get("designs", {}) as Dictionary).get(design_id) if typeof(index.get("designs")) == TYPE_DICTIONARY else null
	var regions: Array = (d as Dictionary).get("regions", []) if typeof(d) == TYPE_DICTIONARY else []
	if regions.is_empty():
		return "face"
	var first := int(regions[0])
	if first == 10:
		return "hand_l"   # the floor's one hand design, the knuckles scar, is on the left hand (tools/giant/kit)
	for region: String in Appearance.DESIGN_REGION_BODY:
		if (Appearance.DESIGN_REGION_BODY[region] as Array).has(first):
			return region
	return "face"


## The side of the giant a design row shows ("left", "right" or "centre": the index's design `side`), for the
## preview's framing (a design on his left is framed from his left: M10's follow-up).
static func row_side(spec: Dictionary, record: Dictionary, index: Dictionary, ancestry_id: String) -> String:
	var key := str(spec.get("key", ""))
	var design := ""
	if TATTOO_ROWS.has(key) or PAINT_ROWS.has(key) or key == PAINT_ROW:
		design = str(Appearance.option(str(value_of(record, key))).get("design", ""))
	elif key.begins_with("scar."):
		design = str(Appearance.option(str(spec.get("id", ""))).get("design", ""))
	elif key == "mark":
		design = str(Appearance.ancestry_mark(ancestry_id).get("design", ""))
	return design_side(design, index)


## A design's side in the index ("centre" when it has none).
static func design_side(design_id: String, index: Dictionary) -> String:
	var table: Dictionary = index.get("designs", {}) if typeof(index.get("designs")) == TYPE_DICTIONARY else {}
	var d: Variant = table.get(design_id)
	return str((d as Dictionary).get("side", "centre")) if typeof(d) == TYPE_DICTIONARY else "centre"


## What the outfit of `record` covers, for row_hidden(): {"regions": the design regions
## (Appearance.covered_regions), "body": the body region ids where a design is hidden
## (Appearance.design_hidden_body_regions)}. Computed once per record.
static func coverage(record: Dictionary, index: Dictionary, ancestry_id: String) -> Dictionary:
	var garments: Array = Appearance.record_garments(Appearance.sanitize(record, ancestry_id, false).record)
	return {"regions": Appearance.covered_regions(record, index, ancestry_id),
		"body": Appearance.design_hidden_body_regions(garments, index)}


## True when the outfit of `record` hides the design a row shows (its note reads HIDDEN_NOTE). A tattoo or
## war paint row by its design region (Appearance.covered_regions); a scar or the mark by every body region of
## its design (Appearance.design_hidden_body_regions); with no design chosen, by the row's own region.
## `cover` is coverage() of the record (computed here when empty).
static func row_hidden(spec: Dictionary, record: Dictionary, index: Dictionary, ancestry_id: String,
		cover: Dictionary = {}) -> bool:
	var key := str(spec.get("key", ""))
	if cover.is_empty():
		cover = coverage(record, index, ancestry_id)
	var covered: PackedStringArray = cover.regions
	if TATTOO_ROWS.has(key):
		return covered.has(str(TATTOO_ROWS[key]))
	if key == PAINT_ROW or PAINT_ROWS.has(key):
		var o := Appearance.option(str(value_of(record, key)))
		return not o.is_empty() and covered.has(str(o.get("region", "")))
	var design := ""
	if key.begins_with("scar."):
		design = str(Appearance.option(str(spec.get("id", ""))).get("design", ""))
	elif key == "mark":
		design = str(Appearance.ancestry_mark(ancestry_id).get("design", ""))
	if design == "" or typeof(index.get("designs")) != TYPE_DICTIONARY:
		return false
	var d: Variant = (index.designs as Dictionary).get(design)
	var regions: Array = (d as Dictionary).get("regions", []) if typeof(d) == TYPE_DICTIONARY else []
	if regions.is_empty():
		return false
	var hidden: PackedInt32Array = cover.body
	for r: Variant in regions:
		if not hidden.has(int(r)):
			return false
	return true


# --------------------------------------------------------------------------- Randomize over every row

## A random record for the creator's Randomize (plan M11 §2.7, §3.8 item 7), from `rng` only (the creator's own
## generator: never Sim.rng). `scope` is a category's RANDOM_SCOPE or "all"; the rest of `base` is kept.
##   * "body": the skin and the build (within Appearance.RANDOM_BUILD); "face": the eyes and the face sliders;
##   * "clothing": random_clothing() - dressed by slot from a random outfit;
##   * "accessories": each accessory slot filled ACCESSORY_P of the time with one of its pieces;
##   * "colours": the outfit's three dyes, and now and then a slot's own;
##   * "all": everything but the clothing when `keep_outfit` (another category open), the build and the face too;
##   * any other scope: Appearance.random_record's.
## Clothing comes first, so that the designs drawn after it never go where it covers.
static func random_record(rng: RandomNumberGenerator, scope: String, keep_outfit: bool, ancestry_id: String,
		base: Dictionary) -> Dictionary:
	var r: Dictionary = Appearance.sanitize(base, ancestry_id).record
	match scope:
		"body":
			r = Appearance.random_record(rng, "skin", true, ancestry_id, r)
			return _random_build(rng, r)
		"face":
			r = Appearance.random_record(rng, "eyes", true, ancestry_id, r)
			return _random_face(rng, r)
		"clothing":
			return random_clothing(rng, r, ancestry_id)
		"accessories":
			return _random_accessories(rng, r, ancestry_id)
		"colours":
			return _random_colours(rng, r, ancestry_id)
		"all":
			if not keep_outfit:
				r = random_clothing(rng, r, ancestry_id)
				r = _random_accessories(rng, r, ancestry_id)
			r = Appearance.random_record(rng, "all", true, ancestry_id, r)
			return _random_face(rng, _random_build(rng, r))
	return Appearance.random_record(rng, scope, keep_outfit, ancestry_id, r)


## Dressed by slot (plan M11 §3.8 item 7): a random outfit (a starting point), then each slot now and then changed
## to another of its pieces (SWAP_P), filled (ADD_P) or emptied (DROP_P; never the legs), with a cloth, a leather
## and a metal dye; an armour is never left over a bare chest unless the outfit it started from wore one so.
static func random_clothing(rng: RandomNumberGenerator, base: Dictionary, ancestry_id: String) -> Dictionary:
	var outfits := _unlocked_ids("outfit", ancestry_id)
	if outfits.is_empty():
		return base.duplicate(true)
	var start: String = outfits[rng.randi_range(0, outfits.size() - 1)]
	var r := Appearance.with_outfit(base, start)
	var started := Appearance.outfit_slots(start)
	var slots: Dictionary = r.outfit.slots
	var pools := {}
	for id: String in _unlocked_ids("garment", ancestry_id):
		var s := str(Appearance.option(id).get("slot", ""))
		if not pools.has(s):
			pools[s] = []
		(pools[s] as Array).append(id)
	for slot: String in Appearance.SLOTS:
		var pool: Array = pools.get(slot, [])
		var item := str(slots[slot].item)
		var roll := rng.randf()
		if pool.is_empty():
			continue
		if item != "" and roll < SWAP_P:
			item = pool[rng.randi_range(0, pool.size() - 1)]
		elif item == "" and roll < ADD_P:
			item = pool[rng.randi_range(0, pool.size() - 1)]
		elif item != "" and slot != "legs" and roll > 1.0 - DROP_P:
			item = ""
		slots[slot] = {"item": item, "dye": ""}
	var bare_armour := str(started.get("armour", "")) != "" and str(started.get("chest", "")) == ""
	if str(slots.armour.item) != "" and str(slots.chest.item) == "" and not bare_armour:
		slots["armour"] = {"item": "", "dye": ""}
	for material: String in Appearance.DYE_SET:
		var ids := _unlocked_ids(str(Appearance.DYE_SET[material]), ancestry_id)
		if not ids.is_empty():
			r.outfit.dyes[material] = ids[rng.randi_range(0, ids.size() - 1)]
	r["preset"] = ""
	return Appearance.sanitize(r, ancestry_id).record


static func _random_accessories(rng: RandomNumberGenerator, base: Dictionary, ancestry_id: String) -> Dictionary:
	var r := base.duplicate(true)
	for slot: String in Appearance.ACCESSORY_SLOTS:
		var pool := _unlocked_ids("accessory", ancestry_id, slot)
		r.outfit.accessories[slot] = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() \
			and rng.randf() < ACCESSORY_P else ""
	r["preset"] = ""
	return r


static func _random_colours(rng: RandomNumberGenerator, base: Dictionary, ancestry_id: String) -> Dictionary:
	var r := base.duplicate(true)
	for material: String in Appearance.DYE_SET:
		var ids := _unlocked_ids(str(Appearance.DYE_SET[material]), ancestry_id)
		if not ids.is_empty():
			r.outfit.dyes[material] = ids[rng.randi_range(0, ids.size() - 1)]
	for slot: String in Appearance.SLOTS:
		var palette := slot_palette(str(r.outfit.slots[slot].item))
		var ids := _unlocked_ids(palette, ancestry_id) if palette != "" else []
		r.outfit.slots[slot]["dye"] = ids[rng.randi_range(0, ids.size() - 1)] if not ids.is_empty() \
			and rng.randf() < SLOT_DYE_P else ""
	r["preset"] = ""
	return r


static func _random_build(rng: RandomNumberGenerator, base: Dictionary) -> Dictionary:
	var r := base.duplicate(true)
	for k: String in Appearance.BUILD_KEYS:
		r.build[k] = snappedf(rng.randf_range(-Appearance.RANDOM_BUILD, Appearance.RANDOM_BUILD), SLIDER_PAD_STEP)
	r["preset"] = ""
	return r


## The face sliders of the face set (none until P56's): small, in steps of SLIDER_PAD_STEP.
static func _random_face(rng: RandomNumberGenerator, base: Dictionary) -> Dictionary:
	var r := base.duplicate(true)
	for o: Dictionary in Appearance.options("face", ""):
		r.face[str(o.key)] = snappedf(rng.randf_range(-0.5, 0.5), SLIDER_PAD_STEP)
	return r


## The option ids of `category` a giant of `ancestry_id` may use (data order), of `slot` when given.
static func _unlocked_ids(category: String, ancestry_id: String, slot := "") -> Array:
	var out: Array = []
	for o: Dictionary in Appearance.options(category, ancestry_id):
		if bool(o.locked) or (slot != "" and str(o.get("slot", "")) != slot):
			continue
		out.append(str(o.id))
	return out


# --------------------------------------------------------------------------- building

## The rows of `category`, built (not yet in the tree): Array of OptionRows.Row.
static func build_rows(category: String, ancestry_id: String, record: Dictionary = {}) -> Array:
	var out: Array = []
	for spec: Dictionary in row_specs(category, record):
		match str(spec.kind):
			"swatch":
				out.append(SwatchRow.new(spec, choices(spec, ancestry_id)))
			"cycler":
				out.append(CyclerRow.new(spec, choices(spec, ancestry_id)))
			"grid":
				out.append(GridRow.new(spec, choices(spec, ancestry_id)))
			"slider":
				out.append(SliderRow.new(spec))
			"toggle":
				out.append(ToggleRow.new(spec))
			"preset":
				out.append(PresetRow.new(spec))
	return out


## A row's frame: a label (its name) above its controls and a note line under them.
class Row extends VBoxContainer:
	## The user picked a value (an option id, a grey, a bool): CreatorScreen makes the new record.
	signal picked(row: Row, value: Variant)
	## A control of the row took the focus (the preview frames the row's region).
	signal focused(row: Row)

	var spec: Dictionary = {}
	var key := ""
	var title: Label
	var note: Label
	var _note_base := ""

	func _init(p_spec: Dictionary) -> void:
		spec = p_spec
		key = str(p_spec.get("key", ""))
		name = key.replace(".", "_")
		add_theme_constant_override("separation", 3)
		title = UiKit.label(str(p_spec.get("label", key)), 15, UiKit.MUTED)
		add_child(title)

	## The row's focusable controls, left to right (one focus row).
	func focus_controls() -> Array:
		return []

	## The control the focus lands on when the row is entered (the current value's).
	func main_control() -> Control:
		var c := focus_controls()
		return c[0] if not c.is_empty() else null

	## Shows `value` (from the record) without emitting anything.
	func show_value(_value: Variant) -> void:
		pass

	## The note line under the row ("" hides it): "Hidden by your clothing", a locked option's reason.
	func set_note(text: String) -> void:
		_note_base = text
		_show_note(text)

	func note_text() -> String:
		return note.text if note != null and note.visible else ""

	func _show_note(text: String) -> void:
		if note == null:
			note = UiKit.label("", 13, OptionRows.NOTE_COLOR)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(note)
		note.text = text
		note.visible = text != ""

	func _wire_focus(c: Control) -> void:
		c.focus_entered.connect(func() -> void: focused.emit(self))


## A row of named colour swatches (skin, eyes, hair and beard colours, inks, paint colours, dyes).
class SwatchRow extends Row:
	var buttons: Dictionary = {}     ## option id ("" for "Same as hair") -> Button
	var choices: Array = []
	var name_label: Label
	var selected := ""
	var _box: HFlowContainer
	var _inside := false     ## the focus is on one of this row's swatches

	func _init(p_spec: Dictionary, p_choices: Array) -> void:
		super(p_spec)
		choices = p_choices
		_box = HFlowContainer.new()
		_box.add_theme_constant_override("h_separation", 6)
		_box.add_theme_constant_override("v_separation", 6)
		add_child(_box)
		for c: Dictionary in choices:
			var b := Button.new()
			b.name = "Swatch_" + (str(c.id).get_slice(".", 1) if str(c.id) != "" else "same")
			b.custom_minimum_size = Vector2(OptionRows.SWATCH_PX, OptionRows.SWATCH_PX)
			b.focus_mode = Control.FOCUS_ALL
			b.tooltip_text = str(c.name) + (" (%s)" % c.reason if bool(c.locked) else "")
			var col: Color = c.get("color", Color(0.5, 0.5, 0.5))
			if bool(c.get("same", false)):
				b.text = "="
				b.add_theme_font_size_override("font_size", 16)
			if bool(c.locked):
				b.text = "x"
				b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
			b.set_meta("swatch_color", col)
			_box.add_child(b)
			buttons[str(c.id)] = b
			var id := str(c.id)
			b.focus_entered.connect(_on_swatch_focus.bind(id))
			b.focus_exited.connect(_on_swatch_unfocus)
			b.pressed.connect(_on_swatch_pressed.bind(id))
			_wire_focus(b)
		name_label = UiKit.label("", 14, UiKit.TEXT)
		add_child(name_label)
		_style_all()

	func focus_controls() -> Array:
		var out: Array = []
		for c: Dictionary in choices:
			out.append(buttons[str(c.id)])
		return out

	func main_control() -> Control:
		return buttons.get(selected, focus_controls()[0] if not choices.is_empty() else null)

	func show_value(value: Variant) -> void:
		selected = str(value)
		_style_all()
		_name_of(selected)

	## The choice of an id ({} when unknown).
	func choice(id: String) -> Dictionary:
		for c: Dictionary in choices:
			if str(c.id) == id:
				return c
		return {}

	## Moving along the row applies each swatch; entering the row from another (up, down, Tab) lands on the
	## selected swatch and changes nothing. A mouse press gives the swatch under the pointer the focus before
	## its own press: it keeps the focus and is applied at once (sending the focus to the selected swatch
	## while the button is held would make the pressed swatch drop its click).
	func _on_swatch_focus(id: String) -> void:
		if not _inside:
			_inside = true
			if id != selected and buttons.has(selected) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_redirect.call_deferred()
				return
		_pick(id)

	func _redirect() -> void:
		var b: Button = buttons.get(selected)
		if b != null and is_instance_valid(b) and UiNav.focusable(b):
			b.grab_focus()

	func _on_swatch_unfocus() -> void:
		_check_inside.call_deferred()

	func _check_inside() -> void:
		if not is_inside_tree():
			_inside = false
			return
		var owner := get_viewport().gui_get_focus_owner()
		_inside = owner != null and owner.get_parent() == _box

	func _on_swatch_pressed(id: String) -> void:
		_pick(id)

	func _pick(id: String) -> void:
		var c := choice(id)
		if c.is_empty():
			return
		if bool(c.locked):
			name_label.text = "%s: %s" % [c.name, c.reason]
			name_label.add_theme_color_override("font_color", OptionRows.NOTE_COLOR)
			return
		if id != selected:
			picked.emit(self, id)
		else:
			_name_of(id)

	func _name_of(id: String) -> void:
		var c := choice(id)
		name_label.text = str(c.get("name", ""))
		name_label.add_theme_color_override("font_color", UiKit.TEXT)

	func _style_all() -> void:
		for id: Variant in buttons:
			var b: Button = buttons[id]
			var on := str(id) == selected
			if b.has_meta("selected") and bool(b.get_meta("selected")) == on:
				continue
			var col: Color = b.get_meta("swatch_color", Color(0.5, 0.5, 0.5))
			for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.add_theme_stylebox_override(st, OptionRows.swatch_box(col, on, st == "hover"))
			b.add_theme_stylebox_override("focus", OptionRows.focus_box())
			b.set_meta("selected", on)


## One control stepping through choices: "<  Long, combed back  >".
class CyclerRow extends Row:
	var button: Button
	var choices: Array = []
	var index := 0

	func _init(p_spec: Dictionary, p_choices: Array) -> void:
		super(p_spec)
		choices = p_choices
		button = Button.new()
		button.name = "Cycler"
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(300, 34)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override("font_size", 16)
		button.gui_input.connect(_on_gui_input)
		button.pressed.connect(_on_pressed)
		add_child(button)
		_wire_focus(button)
		_show()

	func focus_controls() -> Array:
		return [button]

	func show_value(value: Variant) -> void:
		for i in choices.size():
			if str(choices[i].id) == str(value):
				index = i
		_show()

	func value() -> String:
		return str(choices[index].id) if index < choices.size() else ""

	## Steps `dir` (+1 or -1) to the next choice that is not locked, applies it and returns its id.
	func step(dir: int) -> String:
		if choices.is_empty():
			return ""
		var i := index
		for n in choices.size():
			i = (i + dir + choices.size()) % choices.size()
			if not bool(choices[i].locked):
				break
		if i != index:
			index = i
			_show()
			picked.emit(self, value())
		return value()

	func _show() -> void:
		var label := str(choices[index].name) if index < choices.size() else ""
		button.text = "<   %s   >" % label

	func _on_gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true):
			step(-1)
			button.accept_event()
		elif event.is_action_pressed("ui_right", true):
			step(1)
			button.accept_event()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			# a click on the left third steps back (the right two thirds: the button's own pressed, forward)
			if (event as InputEventMouseButton).position.x < button.size.x / 3.0:
				step(-1)
				button.accept_event()

	func _on_pressed() -> void:
		step(1)


## A slider: the greys (0 to 1), and the signed sliders (`signed`: the build and the face, -limit to limit). A drag
## moves in hundredths and snaps to 0 within SNAP_ZERO; the pad and the arrows step by SLIDER_PAD_STEP (plan M11
## §2.7). The changes of one slider in a row are one step of the undo history (CreatorScreen's merge key).
class SliderRow extends Row:
	var slider: HSlider
	var value_label: Label
	var signed := false
	var _quiet := false

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		signed = bool(p_spec.get("signed", false))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		add_child(h)
		slider = HSlider.new()
		slider.name = "Slider"
		var limit := float(p_spec.get("limit", 1.0))
		slider.min_value = -limit if signed else 0.0
		slider.max_value = limit if signed else 1.0
		slider.step = 0.01
		slider.gui_input.connect(_on_slider_input)
		slider.custom_minimum_size = Vector2(300, 28)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_on_changed)
		h.add_child(slider)
		value_label = UiKit.label("", 14)
		value_label.custom_minimum_size = Vector2(120, 0)
		h.add_child(value_label)
		_wire_focus(slider)

	func focus_controls() -> Array:
		return [slider]

	func show_value(value: Variant) -> void:
		_quiet = true
		slider.value = float(value)
		_quiet = false
		_label(float(value))

	## The pad and the arrows step by SLIDER_PAD_STEP (the drag keeps its hundredths), from the step's grid.
	func _on_slider_input(event: InputEvent) -> void:
		var dir := 0
		if event.is_action_pressed("ui_left", true):
			dir = -1
		elif event.is_action_pressed("ui_right", true):
			dir = 1
		if dir == 0:
			return
		var step := OptionRows.SLIDER_PAD_STEP
		var v := snappedf(slider.value / step, 1e-6)
		var next := (floorf(v) + 1.0 if dir > 0 else ceilf(v) - 1.0) * step
		slider.value = clampf(next, slider.min_value, slider.max_value)
		slider.accept_event()

	func _on_changed(v: float) -> void:
		var snapped := OptionRows.snap_slider(v)
		if not is_equal_approx(snapped, v):
			_quiet = true
			slider.set_value_no_signal(snapped)
			_quiet = false
		_label(snapped)
		if not _quiet:
			picked.emit(self, snapped)

	func _label(v: float) -> void:
		if signed:
			var low := str(spec.get("low", ""))
			var high := str(spec.get("high", ""))
			if absf(v) < 0.005:
				value_label.text = "As built"
			else:
				value_label.text = "%s %+.1f" % [high if v > 0.0 else low, v] if (low != "" and high != "") else "%+.1f" % v
			return
		var words := Appearance.grey_words(v)
		value_label.text = words.capitalize() if words != "" else "None"


## A slider's value as it is kept: in hundredths, 0 within SNAP_ZERO (a drag's detent at the middle, or at a grey
## slider's 0 end).
static func snap_slider(v: float) -> float:
	if absf(v) < SNAP_ZERO:
		return 0.0
	return snappedf(v, 0.01)


## A row naming its value that opens its option grid (plan M11 §2.7): "Chest   Tunic". A, Enter or a click asks
## CreatorScreen to open the grid (`open_requested`); left and right step through the choices and apply each, as
## M10's cyclers did. The label stands at the row's left, the value fills the rest of the line.
class GridRow extends Row:
	## A, Enter or a click: open this row's grid.
	signal open_requested(row: GridRow)
	var button: Button
	var choices: Array = []
	var value := ""
	var name_width := 110.0
	var count_label: Label

	func _init(p_spec: Dictionary, p_choices: Array) -> void:
		super(p_spec)
		choices = p_choices
		title.visible = false
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		add_child(h)
		var label := UiKit.label(str(p_spec.get("label", key)), 15, UiKit.MUTED)
		label.name = "Name"
		label.custom_minimum_size = Vector2(name_width, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(label)
		button = Button.new()
		button.name = "Open"
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size = Vector2(200, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		button.gui_input.connect(_on_gui_input)
		button.pressed.connect(func() -> void: open_requested.emit(self))
		h.add_child(button)
		count_label = UiKit.label("", 13, UiKit.MUTED)
		count_label.name = "Count"
		count_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		count_label.offset_left = -70
		count_label.offset_right = -10
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count_label)
		_wire_focus(button)
		_show()

	func focus_controls() -> Array:
		return [button]

	func show_value(v: Variant) -> void:
		value = str(v)
		_show()

	## How many options the row has (not counting "None").
	func option_count() -> int:
		var n := 0
		for c: Dictionary in choices:
			if not ((str(c.id) == "" and str(c.name) == OptionRows.NONE) or str(c.id) == Appearance.BEAD_NONE):
				n += 1
		return n

	## The choice of an id ({} when unknown).
	func choice(id: String) -> Dictionary:
		for c: Dictionary in choices:
			if str(c.id) == id:
				return c
		return {}

	## The name the row shows for its value ("Custom" for clothing that is no outfit's).
	func value_name() -> String:
		var c := choice(value)
		if not c.is_empty():
			return str(c.name)
		if key == "outfit.set" and value == "":
			return OptionRows.CUSTOM
		return OptionRows.NONE if value == "" or value == Appearance.BEAD_NONE \
			else str(Appearance.option(value).get("name", value))

	## Steps `dir` (+1 or -1) to the next choice that is not locked, applies it and returns its id.
	func step(dir: int) -> String:
		if choices.is_empty():
			return value
		var i := -1
		for n in choices.size():
			if str(choices[n].id) == value:
				i = n
		var start := i
		for n in choices.size():
			i = (i + dir + choices.size()) % choices.size()
			if not bool(choices[i].locked):
				break
		if i != start and i >= 0:
			value = str(choices[i].id)
			_show()
			picked.emit(self, value)
		return value

	func _show() -> void:
		var n := option_count()
		button.text = value_name()
		count_label.text = "%d  >" % n if n > 0 else "none yet"
		button.tooltip_text = "%s: %d to choose from" % [str(spec.get("label", key)), n]

	func _on_gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true):
			step(-1)
			button.accept_event()
		elif event.is_action_pressed("ui_right", true):
			step(1)
			button.accept_event()


## An on / off option (a scar).
class ToggleRow extends Row:
	var check: CheckButton
	var _quiet := false

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		title.visible = false
		check = CheckButton.new()
		check.name = "Toggle"
		check.text = str(p_spec.get("label", ""))
		check.focus_mode = Control.FOCUS_ALL
		check.add_theme_font_size_override("font_size", 16)
		check.toggled.connect(_on_toggled)
		add_child(check)
		_wire_focus(check)

	func focus_controls() -> Array:
		return [check]

	func show_value(value: Variant) -> void:
		_quiet = true
		check.button_pressed = bool(value)
		_quiet = false

	func _on_toggled(on: bool) -> void:
		if not _quiet:
			picked.emit(self, on)


## A preset: its name as a button. Its description is shown by the screen, in one place under the list, while
## the preset has the focus (a description that opened under the focused button moved every button below it).
class PresetRow extends Row:
	var button: Button
	var description := ""

	func _init(p_spec: Dictionary) -> void:
		super(p_spec)
		title.visible = false
		description = str(p_spec.get("description", ""))
		button = Button.new()
		button.name = "Preset"
		button.text = str(p_spec.get("label", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func() -> void: picked.emit(self, true))
		add_child(button)
		_wire_focus(button)

	func focus_controls() -> Array:
		return [button]

	func show_value(value: Variant) -> void:
		button.add_theme_color_override("font_color", UiKit.GOOD if bool(value) else UiKit.TEXT)


# --------------------------------------------------------------------------- styles

static var _boxes := {}


## A swatch's box: its colour, a light border when selected (shared: one per colour and state).
static func swatch_box(col: Color, selected: bool, hover: bool) -> StyleBoxFlat:
	var key := [col.to_rgba32(), selected, hover]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	_boxes[key] = sb
	sb.bg_color = col.lightened(0.08) if hover else col
	sb.set_corner_radius_all(4)
	sb.border_color = Color(1.0, 0.86, 0.5) if selected else Color(0, 0, 0, 0.6)
	sb.set_border_width_all(3 if selected else 1)
	return sb


## The focus outline drawn over a swatch (the theme's is thin on a coloured box; shared).
static func focus_box() -> StyleBoxFlat:
	if _boxes.has("focus"):
		return _boxes.focus
	var sb := StyleBoxFlat.new()
	_boxes["focus"] = sb
	sb.draw_center = false
	sb.border_color = Color(1, 1, 1, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.expand_margin_left = 3
	sb.expand_margin_right = 3
	sb.expand_margin_top = 3
	sb.expand_margin_bottom = 3
	return sb
