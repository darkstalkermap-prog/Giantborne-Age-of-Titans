class_name Appearance
extends RefCounted
## The giant's look as a saved record (plan M10 §2.2-§2.4, §2.10; decisions 13, 14, 16, 18; plan M11 §2.5,
## §2.6, decisions 10, 11): the rules that turn the optional `character.appearance` into the concrete look every
## renderer of the giant draws (GiantLook.apply), read from the appearance sets and presets of data/appearance/.
## Pure: it reads GameData's records and nothing else (the one exception is `cli_preset`, which GameSession sets
## from --appearance= at start-up), never Sim, never a node. Nothing in the simulation reads it.
##
## The record, version 2 (P53; schema 2 kept, the record has its own "v"):
##   {"v": 2, "preset": "appearance_preset.wanderer", "skin": "skin.ruddy", "eyes": "eyes.grey_green",
##    "build": {"brawn": 0.0, "girth": 0.0},
##    "face": {"jaw": 0.0, "chin": 0.0, "nose": 0.0, "brow": 0.0, "cheeks": 0.0, "age": 0.0},
##    "hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12, "beads": "bead.none"},
##    "beard": {"style": "beard.full", "color": "", "grey": 0.2, "beads": "bead.none"},
##    "tattoos": {"arms": "", "chest": "", "back": "", "face": "", "legs": "", "ink": "ink.woad"},
##    "paint": {"face": "", "body": "", "color": "paintcolor.chalk"}, "scars": [], "mark": "auto",
##    "outfit": {"set": "outfit.wanderer",
##               "slots": {"<slot>": {"item": "garment.<key>" or "", "dye": "dye.<key>", "metal.<key>" or ""}, ...},
##               "accessories": {"neck": "", "arm_ring": "", "belt": ""},
##               "dyes": {"cloth": "dye.undyed", "leather": "dye.dark_leather", "metal": "metal.iron"}}}
## An option's id is <set category>.<key> (hair.long_back). Absent means the default look: resolve() gives the
## character's record, else the --appearance= preset's, else the default preset's (the Wanderer). Only the
## creator writes a record, always the full record.
##
## Version 1 (M10) had one outfit with two dyes ("outfit": {"set", "primary", "secondary"}) and one war paint
## ("paint": {"design", "color"}). migrate() is the one pure step from 1 to 2 (plan M11 §2.5): the outfit's
## garments go to the slots set_garment.json gives them, primary and secondary become the cloth and leather
## dyes, the paint goes to its region's place, and the new keys take their defaults. A migrated record draws
## exactly what it drew (tests/unit/test_appearance_migration.gd, against M10's code kept as the oracle).
##
## sanitize() never fails: a record that is not a dictionary, or whose fields have the wrong types, becomes the
## default with NOTE_BROKEN; a record a later build wrote ("v" above 2) is kept untouched with NOTE_FUTURE (the
## default look is shown, the record is written back as it is); a version-1 record is migrated first (the
## result's "migrated" is true; CharacterState turns it into the load's NOTE_MIGRATED); a broken `slots` block
## alone becomes the default outfit with NOTE_SLOTS and leaves the rest of the look; otherwise each id is
## checked against its set - unknown ids fall back to the default record's (listed in `dropped`, which
## SaveSlots.read() reports as "Dropped ids this build does not know"), options locked for the character's line
## and designs in the wrong region are reset and named in a note, scars are made unique and capped at six,
## greys, build and face values clamped, the mark is "auto" or "none", and any key this build does not know is
## kept, so a later build's addition survives an older build.
##
## Covered regions (decision 18, "Hidden by your clothing"): a garment option's optional `covers` lists the
## design regions it hides; covered_regions() reads them, so random_record() never puts a new design where the
## clothing hides it. With the giant's index, covered_regions(record, index) reads the garments' coverage
## instead: a body region hides a design when a garment covers at least DESIGN_COVER_SHARE of it (its index
## `coverage`; or it is in the garment's `covers`, the regions covered at 97 % or more, which also sink under the
## clothing). The two agree on the real model for every garment (tests/integration/test_giant_look_real.gd).
##
## Describing a record (summary_lines, covered_regions) applies the line's locks only when given the character's
## line: a stored record was sanitized for its line already, so without one it is described as it is (a
## Stormborn's storm eyes read "storm", not the default).

const RECORD_VERSION := 2
const DEFAULT_PRESET := "appearance_preset.wanderer"
const SET_PREFIX := "appearance_set."
const PRESET_PREFIX := "appearance_preset."
## M10's thirteen sets (data/appearance/set_<category>.json): the creator's categories of today.
const CATEGORIES := ["skin", "eyes", "hair", "beard", "haircolor", "tattoo", "ink", "paint", "paintcolor",
	"scar", "mark", "outfit", "dye"]
## The record v2's own sets (P53), required like M10's: the garments by slot, the metals, the build sliders.
const SLOT_CATEGORIES := ["garment", "metal", "build"]
## Part B's later sets, declared here (plan M11 §1.5: P53 lands Part B's pre-declarations): the accessories
## (P54), the beads and the face sliders (P56). Optional: a build without them shows none and keeps the record's
## values; the schema accepts them before their files exist.
const LATER_CATEGORIES := ["accessory", "bead", "face"]
const ALL_CATEGORIES := CATEGORIES + SLOT_CATEGORIES + LATER_CATEGORIES
## Sets whose options carry no default: a design or a garment is "" (none) by default; a slider set is a list of
## sliders.
const NO_DEFAULT := ["tattoo", "paint", "scar", "mark", "garment", "accessory", "build", "face"]
## The slider sets (their options are sliders from -1 to 1, 0 the giant as built).
const SLIDER_CATEGORIES := ["build", "face"]
## The record's design regions (its tattoos' keys; a tattoo's or a war paint's `region`). "legs" is v2's.
const DESIGN_REGIONS := ["arms", "chest", "back", "face", "legs"]
## M10's four (a version-1 record's tattoo keys).
const V1_DESIGN_REGIONS := ["arms", "chest", "back", "face"]
## The body regions (plan M10 §2.6: the per-vertex ids in COLOR_0.r) each design region covers.
const DESIGN_REGION_BODY := {"arms": [8, 9], "chest": [3, 4], "back": [5, 6], "face": [1], "legs": [11, 12, 13]}
## War paint's two places (v2): one design on the face and one on the body at once.
const PAINT_PLACES := ["face", "body"]
## The share of a body region one garment must cover to hide a design there (covered_regions with an index).
## On the floor's garments the shares fall either at 0.81 and above (the jerkin over the chest and the upper
## back, the tunic) or at 0.67 and below (the furs, the tunic's sleeves, the boots' shins).
const DESIGN_COVER_SHARE := 0.75
const MAX_SCARS := 6
## A version-1 record wore at most four.
const V1_MAX_SCARS := 4
const MARK_AUTO := "auto"
const MARK_NONE := "none"
## The ten garment slots (plan M11 §2.6, decision 10), in the record's order.
const SLOTS := ["head", "shoulders", "chest", "armour", "arms", "waist", "legs", "shins", "feet", "cape"]
## The three accessory slots.
const ACCESSORY_SLOTS := ["neck", "arm_ring", "belt"]
## A garment's material (set_garment.json) and the outfit dye each takes when its slot names none: cloth the
## cloth dye, leather the leather dye, metal the metal; fur keeps its own colour.
const MATERIALS := ["cloth", "leather", "fur", "metal"]
const DYE_OF_MATERIAL := {"cloth": "cloth", "leather": "leather", "metal": "metal"}
## The palette a dye of each outfit dye comes from.
const DYE_SET := {"cloth": "dye", "leather": "dye", "metal": "metal"}
## A fur's own colour (GiantLook.NATURAL_DYE: the furs had no dye in M10 either).
const FUR_COLOR := Color(0.36, 0.30, 0.24)
const BUILD_KEYS := ["brawn", "girth"]
const FACE_KEYS := ["jaw", "chin", "nose", "brow", "cheeks", "age"]
const BEAD_NONE := "bead.none"
## The M10 garments' slots (plan M11 §2.5's fixed mapping; set_garment.json says the same, and data_errors
## checks it): the migration is defined by it.
const M10_SLOTS := {"braies": "legs", "belt": "waist", "tunic": "chest", "jerkin": "armour", "bracers": "arms",
	"boots": "feet", "furs": "shoulders", "pauldron": "shoulders", "cape": "cape", "leg_wraps": "shins"}
## The prologue's ancestry: no line chosen yet (CharacterState.DEFAULT_ANCESTRY).
const NEUTRAL_ANCESTRY := "ancestry.neutral"
## The scopes of random_record(): one creator category, or "all" (the Randomize all button). "build" is v2's
## (the creator II's sliders; "all" leaves the build as it is).
const RANDOM_SCOPES := ["presets", "skin", "eyes", "hair", "beard", "tattoos", "paint", "scars", "outfit", "build", "all"]
## Randomize's weights (plan M10 §2.10): natural hair colours 90 % of the time, at most two tattoo regions,
## war paint 30 %, the beard in the hair's colour 70 %.
const NATURAL_HAIR_P := 0.9
const MAX_RANDOM_TATTOOS := 2
const PAINT_P := 0.3
const BEARD_SAME_COLOR_P := 0.7
## A random build stays within this of the giant as built.
const RANDOM_BUILD := 0.6
## The summary names a beard's colour when it has cards or a stubble at least this dark ("none" keeps a
## faint shadow of 0.15 and reads "Beard: none").
const STUBBLE_NAMED := 0.5

## The Wanderer, as data/appearance/preset_wanderer.json holds it: the default look when the data is
## missing (a test's temporary data), so a look always resolves.
const FALLBACK_RECORD := {
	"v": 2,
	"preset": "appearance_preset.wanderer",
	"skin": "skin.ruddy",
	"eyes": "eyes.grey_green",
	"build": {"brawn": 0.0, "girth": 0.0},
	"face": {"jaw": 0.0, "chin": 0.0, "nose": 0.0, "brow": 0.0, "cheeks": 0.0, "age": 0.0},
	"hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12, "beads": "bead.none"},
	"beard": {"style": "beard.full", "color": "", "grey": 0.2, "beads": "bead.none"},
	"tattoos": {"arms": "", "chest": "", "back": "", "face": "", "legs": "", "ink": "ink.woad"},
	"paint": {"face": "", "body": "", "color": "paintcolor.chalk"},
	"scars": [],
	"mark": "auto",
	"outfit": {
		"set": "outfit.wanderer",
		"slots": {"head": {"item": "", "dye": ""}, "shoulders": {"item": "", "dye": ""},
			"chest": {"item": "", "dye": ""}, "armour": {"item": "", "dye": ""},
			"arms": {"item": "", "dye": ""}, "waist": {"item": "garment.belt", "dye": ""},
			"legs": {"item": "garment.braies", "dye": ""}, "shins": {"item": "", "dye": ""},
			"feet": {"item": "", "dye": ""}, "cape": {"item": "", "dye": ""}},
		"accessories": {"neck": "", "arm_ring": "", "belt": ""},
		"dyes": {"cloth": "dye.undyed", "leather": "dye.dark_leather", "metal": "metal.iron"},
	},
}

const NOTE_FUTURE := "This giant's look was made by a newer version of the game; the default look is shown until you change it."
const NOTE_BROKEN := "Your giant's look could not be read; the default look is used."
const NOTE_LOCKED := "Your giant's look used %s, which your line has not unlocked; the default is shown instead."
const NOTE_MISPLACED := "A design of your giant's look was in the wrong place (%s) and was removed."
## P53 (plan M11 §2.5): a broken `outfit.slots` block alone.
const NOTE_SLOTS := "Your giant's clothing could not be read; the default clothing is worn."
## A garment or an accessory in a slot it does not fit.
const NOTE_WRONG_SLOT := "A piece of your giant's clothing was in the wrong place (%s) and was taken off."
## The load's one-time message for a look made before clothing by slot (CharacterState adds it when sanitize
## migrated the record; SaveSlots shows it once: the flag appearance.slots_seen).
const NOTE_MIGRATED := "Your giant's clothing is now worn piece by piece; nothing was changed."
## Why a locked option cannot be chosen yet (the creator shows it; plan M10 §2.10).
const LOCKED_HINT := "Choose your line at a shrine of the Old Kingdom"
const LOCKED_OTHER := "Only for the %s line"

## The --appearance=<preset id> of the command line (GameSession.apply_args; "" = none): the look of a
## character without one in every mode (the sandbox, the soak, the bots, a command-line New Game).
## Never written into a save. GameSession.reset_for_tests clears it.
static var cli_preset := ""


# --------------------------------------------------------------------------- the data

## The set record of `category` ({} when it is not loaded).
static func set_record(category: String) -> Dictionary:
	var rec := GameData.get_record(SET_PREFIX + category)
	return rec if str(rec.get("type", "")) == "appearance_set" else {}


## The option an id names (the set's own dictionary: do not edit it), {} when unknown. The id's first
## part is the set's category: "hair.long_back" is the hair set's option "long_back".
static func option(option_id: String) -> Dictionary:
	var dot := option_id.find(".")
	if dot <= 0 or dot >= option_id.length() - 1:
		return {}
	var category := option_id.substr(0, dot)
	var key := option_id.substr(dot + 1)
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) == TYPE_DICTIONARY and str(o.get("key", "")) == key:
			return o
	return {}


## The category of an option id ("" when it names no set's option).
static func category_of(option_id: String) -> String:
	return option_id.get_slice(".", 0) if not option(option_id).is_empty() else ""


## The ids of a set's options, in data order (the creator's: the rival giants' own pieces, `npc`, left out).
static func option_ids(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) == TYPE_DICTIONARY and not is_npc(o):
			out.append("%s.%s" % [category, str(o.get("key", ""))])
	return out


## The id of a set's default option ("" for the sets without one).
static func set_default(category: String) -> String:
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) == TYPE_DICTIONARY and bool(o.get("default", false)):
			return "%s.%s" % [category, str(o.get("key", ""))]
	return ""


## The options of `category` for a giant of `ancestry_id`, for the creator: copies of the options with
## "id", "locked" (its `requires` does not hold) and "reason" (locked_reason) added.
static func options(category: String, ancestry_id: String) -> Array:
	var out: Array = []
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) != TYPE_DICTIONARY or is_npc(o):
			continue
		var c: Dictionary = (o as Dictionary).duplicate(true)
		var id := "%s.%s" % [category, str(c.get("key", ""))]
		c["id"] = id
		c["reason"] = locked_reason(id, ancestry_id)
		c["locked"] = c.reason != ""
		out.append(c)
	return out


## P61 (plan M11 §2.10, §3.14): true for an option or a preset only the rival giants and Harrok wear (`"npc": true`):
## never offered by the creator, Randomize or the preset list; option() and preset_record() still find it.
static func is_npc(rec: Variant) -> bool:
	return typeof(rec) == TYPE_DICTIONARY and bool((rec as Dictionary).get("npc", false))


## The ancestry an option requires ("" = none).
static func required_ancestry(opt: Dictionary) -> String:
	var req: Variant = opt.get("requires")
	return str((req as Dictionary).get("ancestry", "")) if typeof(req) == TYPE_DICTIONARY else ""


## True when a line has been chosen (not "" and not the prologue's neutral ancestry).
static func line_chosen(ancestry_id: String) -> bool:
	return ancestry_id != "" and ancestry_id != NEUTRAL_ANCESTRY


## Why the option cannot be chosen by a giant of `ancestry_id` ("" when it can, or is unknown): before a
## line is chosen, LOCKED_HINT; with another line, "Only for the <line> line".
static func locked_reason(option_id: String, ancestry_id: String) -> String:
	var req := required_ancestry(option(option_id))
	if req == "" or req == ancestry_id:
		return ""
	if not line_chosen(ancestry_id):
		return LOCKED_HINT
	var name := str(GameData.get_record(req).get("display_name", req.trim_prefix("ancestry.").capitalize()))
	return LOCKED_OTHER % name


static func is_locked(option_id: String, ancestry_id: String) -> bool:
	return locked_reason(option_id, ancestry_id) != ""


## An outfit option's slots (P53: set_outfit.json's `slots`, slot -> garment id): every slot of SLOTS, "" where
## the outfit wears nothing. {} for an unknown outfit.
static func outfit_slots(outfit_id: String) -> Dictionary:
	var o := option(outfit_id) if outfit_id.begins_with("outfit.") else {}
	if o.is_empty():
		return {}
	var given: Dictionary = o.get("slots", {}) if typeof(o.get("slots")) == TYPE_DICTIONARY else {}
	var out := {}
	for slot: String in SLOTS:
		out[slot] = str(given.get(slot, ""))
	return out


## The empty slots block ({"<slot>": {"item": "", "dye": ""}} for every slot).
static func empty_slots() -> Dictionary:
	var out := {}
	for slot: String in SLOTS:
		out[slot] = {"item": "", "dye": ""}
	return out


## The slots block an outfit puts on (every dye "": the outfit's dyes).
static func slots_of_outfit(outfit_id: String) -> Dictionary:
	var out := empty_slots()
	var s := outfit_slots(outfit_id)
	for slot: String in s:
		out[slot]["item"] = s[slot]
	return out


## A copy of `record` wearing the outfit `outfit_id` (the creator's Outfit row: every slot filled at once, the
## per-slot dyes back to the outfit's; its dyes and accessories kept). Unknown outfits change nothing.
static func with_outfit(record: Dictionary, outfit_id: String) -> Dictionary:
	var out := record.duplicate(true)
	if outfit_slots(outfit_id).is_empty():
		return out
	var o: Dictionary = (out.get("outfit") as Dictionary).duplicate(true) if typeof(out.get("outfit")) == TYPE_DICTIONARY else {}
	o["set"] = outfit_id
	o["slots"] = slots_of_outfit(outfit_id)
	out["outfit"] = o
	return out


## A copy of `record` with one war paint `paint_id` and none in the other place (the creator's one War paint row
## of today: "" takes both off). The place is the design's region: face, else body.
static func with_paint(record: Dictionary, paint_id: String) -> Dictionary:
	var out := record.duplicate(true)
	var p: Dictionary = (out.get("paint") as Dictionary).duplicate(true) if typeof(out.get("paint")) == TYPE_DICTIONARY else {}
	p.erase("design")
	p["face"] = ""
	p["body"] = ""
	if paint_id != "":
		p[paint_place(paint_id)] = paint_id
	out["paint"] = p
	return out


## The place ("face" or "body") of a war paint option: its region "face" is the face, any other the body.
static func paint_place(paint_id: String) -> String:
	return "face" if str(option(paint_id).get("region", "")) == "face" else "body"


## The war paint a record shows first (the face's, else the body's; "" for none): the creator's one paint row.
static func first_paint(record: Dictionary) -> String:
	var p: Variant = record.get("paint")
	if typeof(p) != TYPE_DICTIONARY:
		return ""
	if (p as Dictionary).has("design"):   # a version-1 block
		return str(p.design)
	for place: String in PAINT_PLACES:
		if str((p as Dictionary).get(place, "")) != "":
			return str(p[place])
	return ""


## The giant index garments (set_garment.json's `mesh`) a record's slots wear, in slot order (unknown items left
## out). A version-1 record's outfit option's garments.
static func record_garments(record: Variant) -> Array:
	var out: Array = []
	if typeof(record) != TYPE_DICTIONARY or typeof((record as Dictionary).get("outfit")) != TYPE_DICTIONARY:
		return out
	var o: Dictionary = record.outfit
	if typeof(o.get("slots")) != TYPE_DICTIONARY:
		for g: Variant in option(str(o.get("set", ""))).get("garments", []):
			out.append(str(g))
		return out
	for slot: String in SLOTS:
		var s: Variant = (o.slots as Dictionary).get(slot)
		var item := str((s as Dictionary).get("item", "")) if typeof(s) == TYPE_DICTIONARY else ""
		var m := str(option(item).get("mesh", "")) if item.begins_with("garment.") else ""
		if m != "":
			out.append(m)
	return out


## The index id of a look's garment entry: a {"mesh", "dye", "kind"} entry's mesh, or an M10 id as it is.
static func garment_id(g: Variant) -> String:
	return str((g as Dictionary).get("mesh", "")) if typeof(g) == TYPE_DICTIONARY else str(g)


## The index ids of a look's garments (either shape).
static func garment_ids(garments: Variant) -> Array:
	var out: Array = []
	for g: Variant in (garments if typeof(garments) == TYPE_ARRAY else []):
		out.append(garment_id(g))
	return out


# --------------------------------------------------------------------------- the record

## The default record: the default preset's (the Wanderer's), else FALLBACK_RECORD. A copy.
static func default_record() -> Dictionary:
	var rec: Dictionary = preset_record(DEFAULT_PRESET)
	return rec if not rec.is_empty() else FALLBACK_RECORD.duplicate(true)


## A preset's record (a copy; {} for an unknown preset). "storm_herald" works as well as the full id.
static func preset_record(preset_id: String) -> Dictionary:
	var id := preset_id if preset_id.begins_with(PRESET_PREFIX) else PRESET_PREFIX + preset_id
	var rec := GameData.get_record(id)
	if str(rec.get("type", "")) != "appearance_preset" or typeof(rec.get("appearance")) != TYPE_DICTIONARY:
		return {}
	return (rec.appearance as Dictionary).duplicate(true)


## The preset ids, in id order.
static func preset_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in GameData.ids_of_type("appearance_preset"):
		if not is_npc(GameData.get_record(id)):
			out.append(id)
	out.sort()
	return out


## The record the giant of `character` wears: its `appearance` (sanitized for its ancestry), else the
## --appearance= preset's (cli_preset), else the default record.
static func resolve(character: Dictionary) -> Dictionary:
	var ancestry := str(character.get("ancestry", "")) if typeof(character.get("ancestry")) == TYPE_STRING else ""
	if character.has("appearance"):
		return sanitize(character.appearance, ancestry).record
	if cli_preset != "":
		var rec := preset_record(cli_preset)
		if not rec.is_empty():
			return sanitize(rec, ancestry).record
	return default_record()


## The record's version: its "v" (1 when missing: M10 wrote 1 always, and a record without one is M10's shape).
static func version_of(record: Variant) -> int:
	if typeof(record) != TYPE_DICTIONARY:
		return 0
	var v: Variant = (record as Dictionary).get("v", 1)
	return int(v) if SchemaUtil.is_number(v) and float(v) == floorf(float(v)) else 0


## One pure step per record version (plan M11 §2.5): a version-1 record (or one without "v") becomes version 2;
## any other is returned as it is. A copy. Only the keys a v1 record has are moved; what it lacks is filled by
## sanitize from the default record, as M10 filled it. Unknown ids are carried over for sanitize to report.
static func migrate(record: Dictionary) -> Dictionary:
	var r := record.duplicate(true)
	if version_of(r) != 1:
		return r
	r["v"] = 2
	if typeof(r.get("outfit")) == TYPE_DICTIONARY:
		var o: Dictionary = r.outfit
		var set_id := str(o.get("set", ""))
		if o.has("set"):
			# an outfit this build does not know wears the default record's (M10 drew the default outfit); the
			# unknown id stays for sanitize to report
			var known := not outfit_slots(set_id).is_empty()
			o["slots"] = slots_of_outfit(set_id if known else str(_default_outfit()))
		var dyes := {}
		if o.has("primary"):
			dyes["cloth"] = o.primary
		if o.has("secondary"):
			dyes["leather"] = o.secondary
		o.erase("primary")
		o.erase("secondary")
		if not dyes.is_empty():
			o["dyes"] = dyes
	if typeof(r.get("paint")) == TYPE_DICTIONARY:
		var p: Dictionary = r.paint
		if p.has("design"):
			var design := str(p.design) if p.design != null else ""
			p["face"] = design if design != "" and paint_place(design) == "face" else ""
			p["body"] = design if design != "" and paint_place(design) != "face" else ""
			p.erase("design")
	if typeof(r.get("tattoos")) == TYPE_DICTIONARY and not (r.tattoos as Dictionary).has("legs"):
		r.tattoos["legs"] = ""
	for block: String in ["hair", "beard"]:
		if typeof(r.get(block)) == TYPE_DICTIONARY and not (r[block] as Dictionary).has("beads"):
			r[block]["beads"] = BEAD_NONE
	if typeof(r.get("scars")) == TYPE_ARRAY:
		# M10 wore the first four known scars: a fifth known one (only a hand-made record has it) stays off
		var kept: Array = []
		var known := 0
		for s: Variant in r.scars:
			var known_scar := typeof(s) == TYPE_STRING and str(s).begins_with("scar.") and not option(str(s)).is_empty()
			if known_scar and kept.has(s):
				continue
			if known_scar:
				if known >= V1_MAX_SCARS:
					continue
				known += 1
			kept.append(s)
		r["scars"] = kept
	return r


## The default record's outfit (the Wanderer's).
static func _default_outfit() -> String:
	var d: Dictionary = default_record()
	var o: Variant = d.get("outfit")
	var id := str((o as Dictionary).get("set", "")) if typeof(o) == TYPE_DICTIONARY else ""
	return id if not outfit_slots(id).is_empty() else str(FALLBACK_RECORD.outfit.set)


## True for a record written by a later build ("v" above RECORD_VERSION): kept untouched, never drawn.
static func is_future(record: Variant) -> bool:
	if typeof(record) != TYPE_DICTIONARY:
		return false
	var v: Variant = (record as Dictionary).get("v", RECORD_VERSION)
	return SchemaUtil.is_number(v) and float(v) == floorf(float(v)) and int(v) > RECORD_VERSION


## Structural problems of a record (wrong types, not unknown ids): [] when it can be sanitized key by
## key. A record with any is replaced whole by the default (NOTE_BROKEN). Missing keys are not problems; the
## shape checked is the record's own version's (a v1 record's outfit and paint, a v2 record's). A broken
## `outfit.slots` or `outfit.accessories` is not one: sanitize puts the default clothing on (NOTE_SLOTS).
static func structure_errors(record: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(record) != TYPE_DICTIONARY:
		errors.append("appearance: not an object")
		return errors
	var r: Dictionary = record
	var v: Variant = r.get("v", 1)
	if not SchemaUtil.is_number(v) or float(v) != floorf(float(v)) or int(v) < 1:
		errors.append("appearance.v: must be a whole number of at least 1")
	var v1 := version_of(r) == 1
	for key: String in ["preset", "skin", "eyes", "mark"]:
		if r.has(key) and typeof(r[key]) != TYPE_STRING:
			errors.append("appearance.%s: must be a string" % key)
	var blocks := {"hair": ["style", "color", "beads"], "beard": ["style", "color", "beads"],
		"tattoos": DESIGN_REGIONS + ["ink"],
		"paint": ["design", "color"] if v1 else ["face", "body", "color"],
		"outfit": ["set", "primary", "secondary"] if v1 else ["set"],
		"build": [], "face": []}
	for key: String in blocks:
		if not r.has(key):
			continue
		if typeof(r[key]) != TYPE_DICTIONARY:
			errors.append("appearance.%s: must be an object" % key)
			continue
		for sub: String in blocks[key]:
			if (r[key] as Dictionary).has(sub) and typeof(r[key][sub]) != TYPE_STRING:
				errors.append("appearance.%s.%s: must be a string" % [key, sub])
	if not v1 and typeof(r.get("outfit")) == TYPE_DICTIONARY and (r.outfit as Dictionary).has("dyes"):
		var dyes: Variant = r.outfit.dyes
		if typeof(dyes) != TYPE_DICTIONARY:
			errors.append("appearance.outfit.dyes: must be an object")
		else:
			for k: Variant in dyes:
				if typeof(dyes[k]) != TYPE_STRING:
					errors.append("appearance.outfit.dyes.%s: must be a string" % k)
	if r.has("scars") and typeof(r.scars) != TYPE_ARRAY:
		errors.append("appearance.scars: must be an array")
	return errors


## {"record": the record to keep, "dropped": unknown ids (each once), "notes": what the player is told,
## "migrated": a version-1 record was brought to version 2}. See the class notes; `ancestry_id` is the
## character's line (its locked options are reset). With `check_locks` false no option counts as locked
## (describing a stored record, which was sanitized for its line when it was stored).
static func sanitize(record: Variant, ancestry_id := "", check_locks := true) -> Dictionary:
	var dropped := PackedStringArray()
	var notes := PackedStringArray()
	if is_future(record):
		notes.append(NOTE_FUTURE)
		return {"record": (record as Dictionary).duplicate(true), "dropped": dropped, "notes": notes, "migrated": false}
	if not structure_errors(record).is_empty():
		notes.append(NOTE_BROKEN)
		return {"record": default_record(), "dropped": dropped, "notes": notes, "migrated": false}
	var migrated := version_of(record) == 1
	var r: Dictionary = migrate(record)
	var base := default_record()
	if not structure_errors(base).is_empty() or version_of(base) != RECORD_VERSION:
		base = FALLBACK_RECORD.duplicate(true)
	var locked := PackedStringArray()
	var misplaced := PackedStringArray()
	var ctx := {"ancestry": ancestry_id, "dropped": dropped, "locked": locked, "check_locks": check_locks}
	var out := r.duplicate(true)   # keys this build does not know stay as they are
	out["v"] = RECORD_VERSION
	var preset := str(r.get("preset", ""))
	out["preset"] = preset if preset == "" or not preset_record(preset).is_empty() else ""
	out["skin"] = _check(ctx, r.get("skin", base.skin), "skin", false, str(base.skin))
	out["eyes"] = _check(ctx, r.get("eyes", base.eyes), "eyes", false, str(base.eyes))
	out["build"] = _sliders(r.get("build"), BUILD_KEYS)
	out["face"] = _sliders(r.get("face"), FACE_KEYS)
	var hair := _block(r, "hair", base)
	hair["style"] = _check(ctx, hair.get("style"), "hair", false, str(base.hair.style))
	hair["color"] = _check(ctx, hair.get("color"), "haircolor", false, str(base.hair.color))
	hair["grey"] = _grey(hair.get("grey", base.hair.grey))
	hair["beads"] = _bead(ctx, hair.get("beads", BEAD_NONE))
	out["hair"] = hair
	var beard := _block(r, "beard", base)
	beard["style"] = _check(ctx, beard.get("style"), "beard", false, str(base.beard.style))
	beard["color"] = _check(ctx, beard.get("color"), "haircolor", true, "")
	beard["grey"] = _grey(beard.get("grey", base.beard.grey))
	beard["beads"] = _bead(ctx, beard.get("beads", BEAD_NONE))
	out["beard"] = beard
	var tattoos := _block(r, "tattoos", base)
	for region: String in DESIGN_REGIONS:
		var t := _check(ctx, tattoos.get(region, ""), "tattoo", true, "")
		if t != "" and str(option(t).get("region", "")) != region:
			misplaced.append(t)
			t = ""
		tattoos[region] = t
	tattoos["ink"] = _check(ctx, tattoos.get("ink"), "ink", false, str(base.tattoos.ink), false)
	out["tattoos"] = tattoos
	var paint := _block(r, "paint", base)
	for place: String in PAINT_PLACES:
		var p := _check(ctx, paint.get(place, ""), "paint", true, "")
		if p != "" and paint_place(p) != place:
			misplaced.append(p)
			p = ""
		paint[place] = p
	paint["color"] = _check(ctx, paint.get("color"), "paintcolor", false, str(base.paint.color), false)
	out["paint"] = paint
	var scars: Array = []
	for s: Variant in r.get("scars", []):
		var id := _check(ctx, s, "scar", true, "")
		if id != "" and not scars.has(id):
			scars.append(id)
	out["scars"] = scars.slice(0, MAX_SCARS)
	var mark := str(r.get("mark", MARK_AUTO))
	out["mark"] = mark if mark in [MARK_AUTO, MARK_NONE] else MARK_AUTO
	out["outfit"] = _sanitize_outfit(ctx, r, base, notes)
	if not locked.is_empty():
		notes.append(NOTE_LOCKED % ", ".join(locked))
	if not misplaced.is_empty():
		notes.append(NOTE_MISPLACED % ", ".join(misplaced))
	return {"record": out, "dropped": dropped, "notes": notes, "migrated": migrated}


## The outfit block of a (migrated) record, sanitized: see the table of plan M11 §2.5.
static func _sanitize_outfit(ctx: Dictionary, r: Dictionary, base: Dictionary, notes: PackedStringArray) -> Dictionary:
	var src: Dictionary = r.get("outfit", {}) if typeof(r.get("outfit")) == TYPE_DICTIONARY else {}
	var outfit := _block(r, "outfit", base)
	var base_o: Dictionary = base.outfit
	var set_id := _check(ctx, outfit.get("set", ""), "outfit", true, "")
	# the slots: the record's own; a block without them (a hand-made record naming only its outfit) wears its
	# outfit's; a broken one the default clothing, with a note
	var slots: Dictionary
	var broken := false
	if src.has("slots"):
		broken = not _slots_readable(src.slots)
		slots = (src.slots as Dictionary).duplicate(true) if not broken else {}
	elif set_id != "" and src.has("set"):
		slots = slots_of_outfit(set_id)
	else:
		slots = (base_o.get("slots", {}) as Dictionary).duplicate(true)
	if src.has("accessories") and typeof(src.accessories) != TYPE_DICTIONARY:
		broken = true
	if broken:
		notes.append(NOTE_SLOTS)
		slots = (base_o.slots as Dictionary).duplicate(true)
		set_id = str(base_o.set)
		outfit["accessories"] = (base_o.accessories as Dictionary).duplicate(true)
	var dyes: Dictionary = (base_o.dyes as Dictionary).duplicate(true)
	if typeof(src.get("dyes")) == TYPE_DICTIONARY:
		for k: Variant in src.dyes:
			dyes[k] = src.dyes[k]
	for material: String in DYE_SET:
		var palette := str(DYE_SET[material])
		dyes[material] = _check(ctx, dyes.get(material), palette, false, str(base_o.dyes.get(material, "")))
	outfit["dyes"] = dyes
	var wrong := PackedStringArray()
	var clean := {}
	for slot: String in SLOTS:
		var s: Dictionary = slots.get(slot, {}) if typeof(slots.get(slot)) == TYPE_DICTIONARY else {}
		var item := _check(ctx, s.get("item", ""), "garment", true, "")
		if item != "" and str(option(item).get("slot", "")) != slot:
			wrong.append(item)
			item = ""
		var dye := str(s.get("dye", "")) if typeof(s.get("dye")) == TYPE_STRING else ""
		dye = _slot_dye(item, dye)
		var entry := s.duplicate(true)   # keys this build does not know stay
		entry["item"] = item
		entry["dye"] = dye
		clean[slot] = entry
	for k: Variant in slots:
		if not clean.has(k):
			clean[k] = slots[k]   # a later build's slot: kept as it is
	outfit["slots"] = clean
	var acc: Dictionary = (outfit.get("accessories", {}) as Dictionary).duplicate(true) \
		if typeof(outfit.get("accessories")) == TYPE_DICTIONARY else {}
	for slot: String in ACCESSORY_SLOTS:
		var a := _check(ctx, acc.get(slot, ""), "accessory", true, "")
		if a != "" and str(option(a).get("slot", "")) != slot:
			wrong.append(a)
			a = ""
		acc[slot] = a
	outfit["accessories"] = acc
	if not wrong.is_empty():
		notes.append(NOTE_WRONG_SLOT % ", ".join(wrong))
	# the outfit's name is a summary only: "" once the slots wear anything else
	if set_id != "":
		var want := outfit_slots(set_id)
		for slot: String in SLOTS:
			if str(clean[slot].item) != str(want.get(slot, "")):
				set_id = ""
				break
	outfit["set"] = set_id
	outfit.erase("primary")
	outfit.erase("secondary")
	return outfit


## True when a `slots` block can be read slot by slot: an object whose known slots are objects with string
## items and dyes (or absent).
static func _slots_readable(slots: Variant) -> bool:
	if typeof(slots) != TYPE_DICTIONARY:
		return false
	for slot: String in SLOTS:
		if not (slots as Dictionary).has(slot):
			continue
		var s: Variant = slots[slot]
		if typeof(s) != TYPE_DICTIONARY:
			return false
		for k: String in ["item", "dye"]:
			if (s as Dictionary).has(k) and typeof(s[k]) != TYPE_STRING:
				return false
	return true


## A slot's dye: a dye (or a metal for a metal garment) that fits the garment's material, else "" (the outfit's
## dye of that material). A fur takes none; an empty slot keeps none.
## The dye id a worn slot `s` ({item, dye}) is drawn in with the outfit's `dyes`: the slot's own dye (the player's
## per-piece colour), else the garment's own (the W33 look lane: the bronze breastplate is bronze whatever the outfit's
## metal), else the outfit's dye of its material. "" for none (a fur, no garment). to_look draws it; the shrine's
## summary and the creator's Colours rows name it (Gate B).
static func slot_dye_id(s: Dictionary, dyes: Dictionary) -> String:
	var g := option(str(s.get("item", "")))
	if g.is_empty():
		return ""
	if str(s.get("dye", "")) != "":
		return str(s.dye)
	var own := garment_dye(str(s.item))
	if own != "":
		return own
	return str(dyes.get(DYE_OF_MATERIAL.get(str(g.get("material", "cloth")), ""), ""))


## The garment `item`'s own dye of its material's palette ("" when it names none: it takes the outfit's).
static func garment_dye(item: String) -> String:
	return _slot_dye(item, str(option(item).get("dye", ""))) if item != "" else ""


static func _slot_dye(item: String, dye: String) -> String:
	if item == "" or dye == "":
		return ""
	var material := str(option(item).get("material", "cloth"))
	if not DYE_SET.has(material):
		return ""
	var palette := str(DYE_SET[material])
	return dye if dye.begins_with(palette + ".") and not option(dye).is_empty() else ""


## A copy of the record's block `key` ({} when missing), its missing keys taken from `base`.
static func _block(r: Dictionary, key: String, base: Dictionary) -> Dictionary:
	var out: Dictionary = (base.get(key, {}) as Dictionary).duplicate(true)
	if typeof(r.get(key)) == TYPE_DICTIONARY:
		for k: Variant in r[key]:
			out[k] = r[key][k]
	return out


## `value` when it names an option of `category` this line may use; "" when empty and allowed; else
## `fallback`, the id listed in ctx.dropped (unknown, when `report`) or its name in ctx.locked.
static func _check(ctx: Dictionary, value: Variant, category: String, allow_empty: bool, fallback: String,
		report := true) -> String:
	var id := str(value) if value != null else ""
	if id == "" and allow_empty:
		return ""
	var opt := option(id) if id.begins_with(category + ".") else {}
	if opt.is_empty():
		var dropped: PackedStringArray = ctx.dropped
		if report and id != "" and not dropped.has(id):
			dropped.append(id)
		return fallback
	if bool(ctx.check_locks) and is_locked(id, str(ctx.ancestry)):
		var locked: PackedStringArray = ctx.locked
		var name := str(opt.get("name", id))
		if not locked.has(name):
			locked.append(name)
		return fallback
	return id


## A hair's or a beard's beads: a bead option, else BEAD_NONE (an unknown id reported). Before the bead set
## exists (P56) only BEAD_NONE is known.
static func _bead(ctx: Dictionary, value: Variant) -> String:
	var id := str(value) if typeof(value) == TYPE_STRING else ""
	if id == BEAD_NONE or id == "":
		return BEAD_NONE
	return _check(ctx, id, "bead", false, BEAD_NONE)


## A slider block (build, face): every key of `keys` a number from -1 to 1 (not a number: 0); other keys kept.
static func _sliders(value: Variant, keys: Array) -> Dictionary:
	var out: Dictionary = (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
	for k: String in keys:
		var v: Variant = out.get(k, 0.0)
		out[k] = clampf(float(v), -1.0, 1.0) if SchemaUtil.is_number(v) else 0.0
	return out


static func _grey(v: Variant) -> float:
	return clampf(float(v), 0.0, 1.0) if SchemaUtil.is_number(v) else 0.0


## True when `record` passes sanitize unchanged in its ids: nothing dropped, nothing noted.
static func is_valid(record: Variant, ancestry_id := "") -> bool:
	var s := sanitize(record, ancestry_id)
	return (s.dropped as PackedStringArray).is_empty() and (s.notes as PackedStringArray).is_empty()


# --------------------------------------------------------------------------- the look

## The concrete look of `record` for a giant of `ancestry_id` (plan M10 §2.4, M11 §2.5; GiantLook.apply draws
## it): the palettes resolved, locked options replaced, `mark: "auto"` resolved with the ancestry, the garments
## as {"mesh": index garment, "dye": Color, "kind": material} in slot order. A record from a later build gives
## the default record's look.
static func to_look(record: Variant, ancestry_id := "") -> Dictionary:
	var r: Dictionary = sanitize(record, ancestry_id).record
	if is_future(r):
		r = default_record()
	var hair_style := option(str(r.hair.style))
	var hair_color := option(str(r.hair.color))
	var beard_style := option(str(r.beard.style))
	var beard_color := option(str(r.beard.color)) if str(r.beard.color) != "" else hair_color
	var look := {
		"skin_tone": _color(option(str(r.skin)), "color", Color(0.69, 0.53, 0.44)),
		"eye_color": _color(option(str(r.eyes)), "color", Color(0.3, 0.45, 0.38)),
		"eye_glow": float(option(str(r.eyes)).get("glow", 0.0)),
		"hair_mesh": str(hair_style.get("mesh", "")),
		"beard_mesh": str(beard_style.get("mesh", "")),
		"hair_color": _color(hair_color, "color", Color(0.29, 0.17, 0.1)),
		"hair_tip": _color(hair_color, "tip", _color(hair_color, "color", Color(0.43, 0.29, 0.19))),
		"hair_grey": float(r.hair.grey),
		"beard_color": _color(beard_color, "color", Color(0.29, 0.17, 0.1)),
		"beard_tip": _color(beard_color, "tip", _color(beard_color, "color", Color(0.43, 0.29, 0.19))),
		"beard_grey": float(r.beard.grey),
		"scalp_tint": float(hair_style.get("scalp_tint", 0.0)),
		"stubble": float(beard_style.get("stubble", 0.0)),
		"beard_tint": float(beard_style.get("beard_tint", 0.0)),
		"hair_length": float(hair_style.get("length", 1.0)),     # P46: a shorter cut of the style's mesh
		"beard_length": float(beard_style.get("length", 1.0)),
		"build": Vector2(float(r.build.brawn), float(r.build.girth)),
		"face": {},
		"hair_beads": str(option(str(r.hair.beads)).get("mesh", "")),
		"beard_beads": str(option(str(r.beard.beads)).get("mesh", "")),
		"tattoos": [],
		"paint": [],
		"mark": {},
		"scars": [],
		"garments": [],
		"accessories": [],
	}
	for k: String in FACE_KEYS:
		look.face[k] = float(r.face.get(k, 0.0))
	var ink := _color(option(str(r.tattoos.ink)), "color", Color(0.1, 0.18, 0.4))
	for region: String in DESIGN_REGIONS:
		var t := option(str(r.tattoos.get(region, "")))
		if not t.is_empty():
			(look.tattoos as Array).append({"design": str(t.get("design", "")), "ink": ink})
	var paint_color := _color(option(str(r.paint.color)), "color", Color(0.86, 0.84, 0.78))
	for place: String in PAINT_PLACES:
		var paint := option(str(r.paint.get(place, "")))
		if not paint.is_empty():
			(look.paint as Array).append({"design": str(paint.get("design", "")), "color": paint_color})
	var mark := ancestry_mark(ancestry_id) if str(r.mark) == MARK_AUTO else {}
	if not mark.is_empty():
		look["mark"] = {"design": str(mark.get("design", "")), "color": _color(mark, "color", Color(0.5, 0.5, 0.55)),
			"glow": float(mark.get("glow", 0.0))}
	for s: Variant in r.scars:
		var o := option(str(s))
		if not o.is_empty():
			(look.scars as Array).append(str(o.get("design", "")))
	var dyes: Dictionary = r.outfit.dyes
	for slot: String in SLOTS:
		var s: Dictionary = r.outfit.slots[slot]
		var g := option(str(s.item))
		if g.is_empty():
			continue
		var material := str(g.get("material", "cloth"))
		var dye_id := slot_dye_id(s, dyes)
		var dye := FUR_COLOR if not DYE_SET.has(material) else _color(option(dye_id), "color", FUR_COLOR)
		(look.garments as Array).append({"mesh": str(g.get("mesh", "")), "dye": dye, "kind": material})
	for slot: String in ACCESSORY_SLOTS:
		var a := option(str(r.outfit.accessories.get(slot, "")))
		if not a.is_empty() and str(a.get("mesh", "")) != "":
			(look.accessories as Array).append(str(a.mesh))
	return look


## The mark option of an ancestry's line ({} for none: the prologue, or a line without a mark).
static func ancestry_mark(ancestry_id: String) -> Dictionary:
	if not line_chosen(ancestry_id):
		return {}
	for o: Variant in set_record("mark").get("options", []):
		if typeof(o) == TYPE_DICTIONARY and required_ancestry(o) == ancestry_id:
			return o
	return {}


static func _color(opt: Dictionary, key: String, fallback: Color) -> Color:
	var s := str(opt.get(key, ""))
	return Color.html(s) if s != "" and Color.html_is_valid(s) else fallback


## The design regions (arms, chest, back, face, legs) the record's clothing hides. Without an index: the
## garments' `covers`. With the giant's index (plan M10 §2.5): a design region is covered when every one of its
## body regions hides a design under the garments (design_hidden_body_regions). With `ancestry_id` the line's
## locks apply (see the class notes).
static func covered_regions(record: Variant, index: Dictionary = {}, ancestry_id := "") -> PackedStringArray:
	var r := _described(record, ancestry_id)
	if index.is_empty() or typeof(index.get("garments")) != TYPE_DICTIONARY:
		return _garment_covers(r)
	var out := PackedStringArray()
	var body := design_hidden_body_regions(record_garments(r), index)
	for region: String in DESIGN_REGIONS:
		var all := true
		for b: int in DESIGN_REGION_BODY[region]:
			if not body.has(b):
				all = false
				break
		if all:
			out.append(region)
	return out


## The design regions a (sanitized) record's garments' `covers` list (the data, no index).
static func _garment_covers(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var slots: Dictionary = (r.get("outfit", {}) as Dictionary).get("slots", {})
	for slot: String in SLOTS:
		var s: Variant = slots.get(slot)
		var item := str((s as Dictionary).get("item", "")) if typeof(s) == TYPE_DICTIONARY else ""
		var covers: Array = option(item).get("covers", []) if item.begins_with("garment.") else []
		for c: Variant in covers:
			if str(c) in DESIGN_REGIONS and not out.has(str(c)):
				out.append(str(c))
	return out


## The record as it is described (summary_lines, covered_regions): sanitized, the locks of `ancestry_id`
## applied only when a line is given; the default record for a record that is not a dictionary or comes
## from a later build.
static func _described(record: Variant, ancestry_id: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return default_record()
	var r: Dictionary = sanitize(record, ancestry_id, ancestry_id != "").record
	return default_record() if is_future(r) else r


## The body region ids under the given garments where a design is hidden: those their meshes' `covers`
## list, and those one of their meshes' `coverage` shares (region id -> 0-1) puts at DESIGN_COVER_SHARE or
## more (sorted, unique). `garments` are index garment ids or a look's garment entries.
static func design_hidden_body_regions(garments: Variant, index: Dictionary) -> PackedInt32Array:
	var seen := {}
	for b in covered_body_regions(garments, index):
		seen[b] = true
	var m_table: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	for mesh_id: Variant in _garment_meshes(garments, index):
		var entry: Variant = m_table.get(str(mesh_id), {})
		var cov: Variant = (entry as Dictionary).get("coverage", {}) if typeof(entry) == TYPE_DICTIONARY else {}
		if typeof(cov) != TYPE_DICTIONARY:
			continue
		for k: Variant in cov:
			if str(k).is_valid_int() and SchemaUtil.is_number(cov[k]) and float(cov[k]) >= DESIGN_COVER_SHARE:
				seen[int(str(k))] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## The body region ids the given garments' meshes cover, from the giant's index (sorted, unique).
static func covered_body_regions(garments: Variant, index: Dictionary) -> PackedInt32Array:
	var seen := {}
	var m_table: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	for mesh_id: Variant in _garment_meshes(garments, index):
		var entry: Variant = m_table.get(str(mesh_id), {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for c: Variant in (entry as Dictionary).get("covers", []):
			if SchemaUtil.is_number(c):
				seen[int(c)] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## The index meshes of the given garments: an index garment's meshes (index.garments), or a garment mesh named
## directly (P54's single-part garments may be).
static func _garment_meshes(garments: Variant, index: Dictionary) -> Array:
	var g_table: Dictionary = index.get("garments", {}) if typeof(index.get("garments")) == TYPE_DICTIONARY else {}
	var m_table: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	var out: Array = []
	for id: String in garment_ids(garments):
		if typeof(g_table.get(id)) == TYPE_ARRAY:
			out.append_array(g_table[id])
		elif m_table.has(id):
			out.append(id)
	return out


# --------------------------------------------------------------------------- randomize

## A random record (plan M10 §2.10, the creator's Randomize), from `rng` only (the creator's own
## generator seeded from the clock: never Sim.rng or a Sim stream). `scope` is one category of
## RANDOM_SCOPES or "all"; the rest of `base` (the creator's current record; the default when empty) is
## kept. "all" keeps the outfit when `keep_outfit` (the Clothing category is not open), and the build. Natural
## hair colours NATURAL_HAIR_P of the time, at most MAX_RANDOM_TATTOOS tattoo regions and never one the
## clothing covers, war paint PAINT_P of the time and never where the clothing covers; options locked for
## `ancestry_id` are never picked; the mark's choice is the player's and is kept. The outfit scope puts on a
## whole outfit (its slots) with a cloth and a leather dye, as M10's outfit and its two dyes.
static func random_record(rng: RandomNumberGenerator, scope: String, keep_outfit: bool, ancestry_id: String,
		base: Dictionary = {}) -> Dictionary:
	var r: Dictionary = sanitize(base if not base.is_empty() else default_record(), ancestry_id).record
	if is_future(r):
		r = default_record()
	var s := scope.to_lower()
	match s:
		"clothing":
			s = "outfit"
		"war_paint", "war paint", "warpaint":
			s = "paint"
		"tattoo":
			s = "tattoos"
		"scar":
			s = "scars"
		"preset":
			s = "presets"
		"body":
			s = "build"
	if s == "presets":
		var ids := preset_ids()
		if not ids.is_empty():
			var picked := preset_record(ids[rng.randi_range(0, ids.size() - 1)])
			return sanitize(picked, ancestry_id).record
		return r
	r["preset"] = ""
	if s == "outfit" or (s == "all" and not keep_outfit):
		r = with_outfit(r, _pick(rng, "outfit", ancestry_id, str(r.outfit.set)))
		r.outfit.dyes["cloth"] = _pick(rng, "dye", ancestry_id, str(r.outfit.dyes.cloth))
		r.outfit.dyes["leather"] = _pick(rng, "dye", ancestry_id, str(r.outfit.dyes.leather))
	if s in ["skin", "all"]:
		r["skin"] = _pick(rng, "skin", ancestry_id, str(r.skin))
	if s in ["eyes", "all"]:
		r["eyes"] = _pick(rng, "eyes", ancestry_id, str(r.eyes))
	if s in ["hair", "all"]:
		r.hair["style"] = _pick(rng, "hair", ancestry_id, str(r.hair.style))
		r.hair["color"] = _pick_hair_color(rng, ancestry_id, str(r.hair.color))
		r.hair["grey"] = _random_grey(rng)
	if s in ["beard", "all"]:
		r.beard["style"] = _pick(rng, "beard", ancestry_id, str(r.beard.style))
		r.beard["color"] = "" if rng.randf() < BEARD_SAME_COLOR_P else _pick_hair_color(rng, ancestry_id, "")
		r.beard["grey"] = clampf(float(r.hair.grey) + rng.randf_range(-0.1, 0.2), 0.0, 1.0)
	if s == "build":
		for k: String in BUILD_KEYS:
			r.build[k] = snappedf(rng.randf_range(-RANDOM_BUILD, RANDOM_BUILD), 0.1)
	var covered := _garment_covers(r)
	if s in ["tattoos", "all"]:
		var open: Array = []
		for region: String in DESIGN_REGIONS:
			r.tattoos[region] = ""
			if not covered.has(region) and not _region_options("tattoo", region, ancestry_id).is_empty():
				open.append(region)
		var count := mini(rng.randi_range(0, MAX_RANDOM_TATTOOS), open.size())
		for i in count:
			var region: String = open.pop_at(rng.randi_range(0, open.size() - 1))
			var choices := _region_options("tattoo", region, ancestry_id)
			r.tattoos[region] = choices[rng.randi_range(0, choices.size() - 1)]
		r.tattoos["ink"] = _pick(rng, "ink", ancestry_id, str(r.tattoos.ink))
	if s in ["paint", "all"]:
		for place: String in PAINT_PLACES:
			r.paint[place] = ""
		if rng.randf() < PAINT_P:
			var choices: Array = []
			for region: String in DESIGN_REGIONS:
				if not covered.has(region):
					choices.append_array(_region_options("paint", region, ancestry_id))
			if not choices.is_empty():
				var p: String = choices[rng.randi_range(0, choices.size() - 1)]
				r.paint[paint_place(p)] = p
		r.paint["color"] = _pick(rng, "paintcolor", ancestry_id, str(r.paint.color))
	if s in ["scars", "all"]:
		var pool := _unlocked("scar", ancestry_id)
		var scars: Array = []
		var n := mini(rng.randi_range(0, 2), pool.size())
		for i in n:
			scars.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		r["scars"] = scars
	return r


## A random unlocked option id of `category` (`current` when the set has none).
static func _pick(rng: RandomNumberGenerator, category: String, ancestry_id: String, current: String) -> String:
	var ids := _unlocked(category, ancestry_id)
	return ids[rng.randi_range(0, ids.size() - 1)] if not ids.is_empty() else current


## The ids of the options of `category` a giant of `ancestry_id` may use, in data order (`region`: only
## the design options of that region; `natural_only`: only natural hair colours).
static func _unlocked(category: String, ancestry_id: String, region := "", natural_only := false) -> Array:
	var out: Array = []
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) != TYPE_DICTIONARY or is_npc(o):
			continue
		var req := required_ancestry(o)
		if req != "" and req != ancestry_id:
			continue
		if region != "" and str(o.get("region", "")) != region:
			continue
		if natural_only and not bool(o.get("natural", true)):
			continue
		out.append("%s.%s" % [category, str(o.get("key", ""))])
	return out


## A hair colour: a natural one NATURAL_HAIR_P of the time (an option's optional `natural`, default true).
static func _pick_hair_color(rng: RandomNumberGenerator, ancestry_id: String, current: String) -> String:
	var natural := _unlocked("haircolor", ancestry_id, "", true)
	var all := _unlocked("haircolor", ancestry_id)
	var pool := natural if (rng.randf() < NATURAL_HAIR_P and not natural.is_empty()) else all
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else current


## Mostly little grey; now and then a greying or grey giant.
static func _random_grey(rng: RandomNumberGenerator) -> float:
	return snappedf(rng.randf_range(0.0, 0.25) if rng.randf() < 0.75 else rng.randf_range(0.25, 1.0), 0.01)


## The unlocked option ids of a design set (tattoo, paint) in `region`.
static func _region_options(category: String, region: String, ancestry_id: String) -> Array:
	return _unlocked(category, ancestry_id, region)


# --------------------------------------------------------------------------- the summary

## The look in words, one line per part (the shrine's Appearance tab; plan M10 §2.10):
## "Hair: long, combed back, chestnut, a little grey", "Beard: full, chestnut, a little grey", ...
## Without `ancestry_id` the record is described as it is (no option counts as locked: a stored record was
## sanitized for its line); with it, the line's locks apply, as to_look draws it. A build away from the giant as
## built adds a "Build:" line; clothing that is no outfit reads "Clothing: custom (the garments), dyes".
static func summary_lines(record: Variant, ancestry_id := "") -> PackedStringArray:
	var r := _described(record, ancestry_id)
	var out := PackedStringArray()
	var hair_color := _name(str(r.hair.color))
	var hair := [_name(str(r.hair.style)), hair_color]
	if grey_words(float(r.hair.grey)) != "":
		hair.append(grey_words(float(r.hair.grey)))
	out.append("Hair: " + ", ".join(_non_empty(hair)))
	var beard_style := str(r.beard.style)
	var beard := [_name(beard_style)]
	if str(option(beard_style).get("mesh", "")) != "" or float(option(beard_style).get("stubble", 0.0)) >= STUBBLE_NAMED:
		beard.append(_name(str(r.beard.color)) if str(r.beard.color) != "" else hair_color)
		if grey_words(float(r.beard.grey)) != "":
			beard.append(grey_words(float(r.beard.grey)))
	out.append("Beard: " + ", ".join(_non_empty(beard)))
	out.append("Skin: " + _name(str(r.skin)))
	var build := PackedStringArray()
	for k: String in BUILD_KEYS:
		if absf(float(r.build[k])) >= 0.05:
			build.append("%s %+.1f" % [k, float(r.build[k])])
	if not build.is_empty():
		out.append("Build: " + ", ".join(build))
	out.append("Eyes: " + _name(str(r.eyes)))
	var ink := _name(str(r.tattoos.ink))
	var tattoos := PackedStringArray()
	for region: String in DESIGN_REGIONS:
		var t := str(r.tattoos.get(region, ""))
		if t != "":
			tattoos.append("%s %s" % [ink, _name(t)])
	out.append("Tattoos: " + (", ".join(tattoos) if not tattoos.is_empty() else "none"))
	var paints := PackedStringArray()
	for place: String in PAINT_PLACES:
		if str(r.paint[place]) != "":
			paints.append(_name(str(r.paint[place])))
	out.append("War paint: " + ("%s %s" % [_name(str(r.paint.color)), " and ".join(paints)] if not paints.is_empty() else "none"))
	var scars := PackedStringArray()
	for s: Variant in r.scars:
		scars.append(_name(str(s)))
	out.append("Scars: " + (", ".join(scars) if not scars.is_empty() else "none"))
	out.append("Ancestry mark: " + ("shown" if str(r.mark) == MARK_AUTO else "hidden"))
	var dyes := _name(str(r.outfit.dyes.cloth))
	if str(r.outfit.dyes.leather) != str(r.outfit.dyes.cloth):
		dyes += " and " + _name(str(r.outfit.dyes.leather))
	var clothing := _name(str(r.outfit.set))
	if str(r.outfit.set) == "":
		var worn := PackedStringArray()
		for slot: String in SLOTS:
			if str(r.outfit.slots[slot].item) != "":
				worn.append(_name(str(r.outfit.slots[slot].item)))
		clothing = "custom (%s)" % (", ".join(worn) if not worn.is_empty() else "nothing")
	out.append("Clothing: %s, %s" % [clothing, dyes])
	return out


## "a little grey", "greying", "mostly grey", "grey", or "" for no grey to speak of.
static func grey_words(grey: float) -> String:
	if grey < 0.03:
		return ""
	if grey < 0.25:
		return "a little grey"
	if grey < 0.5:
		return "greying"
	if grey < 0.85:
		return "mostly grey"
	return "grey"


## An option's name in lower case, mid-sentence ("Long, combed back" -> "long, combed back").
static func _name(option_id: String) -> String:
	var o := option(option_id)
	return str(o.get("name", option_id.get_slice(".", 1).replace("_", " "))).to_lower() if option_id != "" else ""


static func _non_empty(parts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p: Variant in parts:
		if str(p) != "":
			out.append(str(p))
	return out


# --------------------------------------------------------------------------- the data's own rules

## GameData's post-pass at anchor P42 (plan M10 §2.3, M11 §2.5): every required category's set once (M10's
## thirteen and the record v2's three; the later sets of Part B at most once); the default preset exists and uses
## each set's default; every preset's record is version 2, names itself and passes sanitize() with nothing
## dropped or noted (presets are offered at New Game, before any line is chosen, so they use no locked option);
## every outfit's slots name garments of those slots, and its M10 `garments` list (kept for the migration) puts
## the same garments on; every garment names an index garment and its M10 slot.
static func data_errors(records: Dictionary, record_paths: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var by_category := {}
	var any := false
	for id: Variant in records:
		var rec: Dictionary = records[id]
		var t := str(rec.get("type", ""))
		if t == "appearance_preset":
			any = true
		if t != "appearance_set":
			continue
		any = true
		var c := str(rec.get("category", ""))
		if by_category.has(c):
			errors.append("%s (%s): a second set of category '%s' (the first is %s)" % [record_paths.get(id, "?"), id, c,
				by_category[c]])
		else:
			by_category[c] = id
	if not any:
		return errors
	for c: String in CATEGORIES + SLOT_CATEGORIES:
		if not by_category.has(c):
			errors.append("data/appearance: no appearance set of category '%s' (%s%s)" % [c, SET_PREFIX, c])
	var garments := _set_options(records, "garment")
	for key: Variant in garments:
		var g: Dictionary = garments[key]
		var ctx := "%s (garment.%s)" % [record_paths.get(SET_PREFIX + "garment", "?"), key]
		if str(g.get("dye", "")) != "" and _slot_dye("garment." + str(key), str(g.dye)) == "":
			errors.append("%s: its own dye '%s' is no %s of its material's palette" % [ctx, g.dye, g.get("material", "cloth")])
		if M10_SLOTS.has(str(g.get("mesh", ""))) and str(g.get("slot", "")) != str(M10_SLOTS[str(g.mesh)]):
			errors.append("%s: M10's %s is worn in the %s slot (plan M11 §2.5), not '%s'" % [ctx, g.mesh, M10_SLOTS[str(g.mesh)],
				g.get("slot", "")])
	for key: Variant in _set_options(records, "outfit"):
		var o: Dictionary = _set_options(records, "outfit")[key]
		var ctx := "%s (outfit.%s)" % [record_paths.get(SET_PREFIX + "outfit", "?"), key]
		var slots: Dictionary = o.get("slots", {}) if typeof(o.get("slots")) == TYPE_DICTIONARY else {}
		var worn: Array = []
		for slot: Variant in slots:
			var item := str(slots[slot])
			if item == "":
				continue
			var g: Dictionary = garments.get(item.trim_prefix("garment."), {}) if item.begins_with("garment.") else {}
			if g.is_empty():
				errors.append("%s: slots.%s names '%s', which the garment set does not have" % [ctx, slot, item])
			elif str(g.get("slot", "")) != str(slot):
				errors.append("%s: slots.%s names %s, a garment of the %s slot" % [ctx, slot, item, g.get("slot", "")])
			else:
				worn.append(str(g.get("mesh", "")))
		if typeof(o.get("garments")) == TYPE_ARRAY:
			var want: Array = []
			for m: Variant in o.garments:
				want.append(str(m))
			want.sort()
			worn.sort()
			if want != worn:
				errors.append("%s: its slots wear %s, its M10 garments are %s" % [ctx, worn, want])
	var default_preset: Dictionary = records.get(DEFAULT_PRESET, {})
	if default_preset.is_empty():
		errors.append("data/appearance: the default preset %s is missing" % DEFAULT_PRESET)
	else:
		var d: Dictionary = default_preset.get("appearance", {}) if typeof(default_preset.get("appearance")) == TYPE_DICTIONARY else {}
		var outfit: Dictionary = d.get("outfit", {}) if typeof(d.get("outfit")) == TYPE_DICTIONARY else {}
		var chosen := {"skin": d.get("skin"), "eyes": d.get("eyes"), "hair": _get2(d, "hair", "style"),
			"haircolor": _get2(d, "hair", "color"), "beard": _get2(d, "beard", "style"), "ink": _get2(d, "tattoos", "ink"),
			"paintcolor": _get2(d, "paint", "color"), "outfit": outfit.get("set"), "dye": _get2(outfit, "dyes", "cloth"),
			"metal": _get2(outfit, "dyes", "metal")}
		for c: String in chosen:
			var want := set_default(c)
			if want != "" and str(chosen[c]) != want:
				errors.append("%s (%s): the default preset should use the %s set's default %s (it uses %s)" % [
					record_paths.get(DEFAULT_PRESET, "?"), DEFAULT_PRESET, c, want, chosen[c]])
	for id: Variant in records:
		var rec: Dictionary = records[id]
		if str(rec.get("type", "")) != "appearance_preset":
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		var a: Variant = rec.get("appearance")
		if typeof(a) != TYPE_DICTIONARY:
			continue   # the schema reports it
		if str((a as Dictionary).get("preset", "")) != str(id):
			errors.append("%s: its record's preset is '%s', not the preset itself" % [ctx, (a as Dictionary).get("preset", "")])
		if is_future(a):
			errors.append("%s: its record's v is newer than %d" % [ctx, RECORD_VERSION])
			continue
		var s := sanitize(a, "")
		if not (s.dropped as PackedStringArray).is_empty():
			errors.append("%s: its record names ids no set has: %s" % [ctx, ", ".join(s.dropped)])
		for n: String in s.notes:
			errors.append("%s: %s" % [ctx, n])
		var given: Variant = (a as Dictionary).get("outfit")
		var given_set := str((given as Dictionary).get("set", "")) if typeof(given) == TYPE_DICTIONARY else ""
		if given_set != str((s.record as Dictionary).outfit.set):
			errors.append("%s: its outfit.set '%s' does not match its slots" % [ctx, given_set])
	return errors


## The options of the set `category` in `records`, key -> option ({} when the set is missing).
static func _set_options(records: Dictionary, category: String) -> Dictionary:
	var out := {}
	var rec: Variant = records.get(SET_PREFIX + category)
	if typeof(rec) != TYPE_DICTIONARY:
		return out
	for o: Variant in (rec as Dictionary).get("options", []):
		if typeof(o) == TYPE_DICTIONARY:
			out[str(o.get("key", ""))] = o
	return out


static func _get2(d: Dictionary, a: String, b: String) -> Variant:
	return (d.get(a) as Dictionary).get(b) if typeof(d.get(a)) == TYPE_DICTIONARY else null
