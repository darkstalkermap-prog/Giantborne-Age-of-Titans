class_name Appearance
extends RefCounted
## The giant's look as a saved record (plan M10 §2.2-§2.4, §2.10; decisions 13, 14, 16, 18): the rules
## that turn the optional `character.appearance` into the concrete look every renderer of the giant draws
## (GiantLook.apply), read from the thirteen appearance sets and eight presets of data/appearance/. Pure:
## it reads GameData's records and nothing else (the one exception is `cli_preset`, which GameSession
## sets from --appearance= at start-up), never Sim, never a node. Nothing in the simulation reads it.
##
## The record (schema 2 kept; the record has its own "v"):
##   {"v": 1, "preset": "appearance_preset.wanderer", "skin": "skin.ruddy", "eyes": "eyes.grey_green",
##    "hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12},
##    "beard": {"style": "beard.full", "color": "", "grey": 0.2},
##    "tattoos": {"arms": "", "chest": "", "back": "", "face": "", "ink": "ink.woad"},
##    "paint": {"design": "", "color": "paintcolor.chalk"}, "scars": [], "mark": "auto",
##    "outfit": {"set": "outfit.wanderer", "primary": "dye.undyed", "secondary": "dye.dark_leather"}}
## An option's id is <set category>.<key> (hair.long_back). Absent means the default look: resolve() gives
## the character's record, else the --appearance= preset's, else the default preset's (the Wanderer).
## Only the creator writes a record, always the full record.
##
## sanitize() never fails: a record that is not a dictionary, or whose fields have the wrong types,
## becomes the default with NOTE_BROKEN; a record a later build wrote ("v" above 1) is kept untouched with
## NOTE_FUTURE (the default look is shown, the record is written back as it is); otherwise each id is
## checked against its set - unknown ids fall back to the default record's (listed in `dropped`, which
## SaveSlots.read() reports as "Dropped ids this build does not know"), options locked for the character's
## line and tattoos in the wrong region are reset and named in a note, scars are made unique and capped at
## four, greys clamped, the mark is "auto" or "none", and any key this build does not know is kept, so a
## later build's addition survives an older build.
##
## Covered regions (decision 18, "Hidden by your clothing"): an outfit option's optional `covers` lists
## the design regions (arms, chest, back, face) its garments hide; covered_regions() reads it, so
## random_record() never puts a new design where the clothing hides it. With the giant's index,
## covered_regions(record, index) reads the garments' coverage instead: a body region hides a design when
## a garment covers at least DESIGN_COVER_SHARE of it (its index `coverage`; or it is in the garment's
## `covers`, the regions covered at 97 % or more, which also sink under the clothing). The two agree on the
## real model for every outfit (tests/integration/test_giant_look_real.gd).
##
## Describing a record (summary_lines, covered_regions) applies the line's locks only when given the
## character's line: a stored record was sanitized for its line already, so without one it is described
## as it is (a Stormborn's storm eyes read "storm", not the default).

const RECORD_VERSION := 1
const DEFAULT_PRESET := "appearance_preset.wanderer"
const SET_PREFIX := "appearance_set."
const PRESET_PREFIX := "appearance_preset."
## The thirteen sets (data/appearance/set_<category>.json).
const CATEGORIES := ["skin", "eyes", "hair", "beard", "haircolor", "tattoo", "ink", "paint", "paintcolor",
	"scar", "mark", "outfit", "dye"]
## Sets whose options carry no default: a design is "" (none) by default.
const NO_DEFAULT := ["tattoo", "paint", "scar", "mark"]
## The record's design regions (its tattoos' keys; a tattoo's or a war paint's `region`).
const DESIGN_REGIONS := ["arms", "chest", "back", "face"]
## The body regions (plan M10 §2.6: the per-vertex ids in COLOR_0.r) each design region covers.
const DESIGN_REGION_BODY := {"arms": [8, 9], "chest": [3, 4], "back": [5, 6], "face": [1]}
## The share of a body region one garment must cover to hide a design there (covered_regions with an index).
## On the floor's garments the shares fall either at 0.81 and above (the jerkin over the chest and the upper
## back, the tunic) or at 0.67 and below (the furs, the tunic's sleeves, the boots' shins).
const DESIGN_COVER_SHARE := 0.75
const MAX_SCARS := 4
const MARK_AUTO := "auto"
const MARK_NONE := "none"
## The prologue's ancestry: no line chosen yet (CharacterState.DEFAULT_ANCESTRY).
const NEUTRAL_ANCESTRY := "ancestry.neutral"
## The scopes of random_record(): one creator category, or "all" (the Randomize all button).
const RANDOM_SCOPES := ["presets", "skin", "eyes", "hair", "beard", "tattoos", "paint", "scars", "outfit", "all"]
## Randomize's weights (plan M10 §2.10): natural hair colours 90 % of the time, at most two tattoo regions,
## war paint 30 %, the beard in the hair's colour 70 %.
const NATURAL_HAIR_P := 0.9
const MAX_RANDOM_TATTOOS := 2
const PAINT_P := 0.3
const BEARD_SAME_COLOR_P := 0.7
## The summary names a beard's colour when it has cards or a stubble at least this dark ("none" keeps a
## faint shadow of 0.15 and reads "Beard: none").
const STUBBLE_NAMED := 0.5

## The Wanderer, as data/appearance/preset_wanderer.json holds it: the default look when the data is
## missing (a test's temporary data), so a look always resolves.
const FALLBACK_RECORD := {
	"v": 1,
	"preset": "appearance_preset.wanderer",
	"skin": "skin.ruddy",
	"eyes": "eyes.grey_green",
	"hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12},
	"beard": {"style": "beard.full", "color": "", "grey": 0.2},
	"tattoos": {"arms": "", "chest": "", "back": "", "face": "", "ink": "ink.woad"},
	"paint": {"design": "", "color": "paintcolor.chalk"},
	"scars": [],
	"mark": "auto",
	"outfit": {"set": "outfit.wanderer", "primary": "dye.undyed", "secondary": "dye.dark_leather"},
}

const NOTE_FUTURE := "This giant's look was made by a newer version of the game; the default look is shown until you change it."
const NOTE_BROKEN := "Your giant's look could not be read; the default look is used."
const NOTE_LOCKED := "Your giant's look used %s, which your line has not unlocked; the default is shown instead."
const NOTE_MISPLACED := "A design of your giant's look was in the wrong place (%s) and was removed."
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


## The ids of a set's options, in data order.
static func option_ids(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for o: Variant in set_record(category).get("options", []):
		if typeof(o) == TYPE_DICTIONARY:
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
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = (o as Dictionary).duplicate(true)
		var id := "%s.%s" % [category, str(c.get("key", ""))]
		c["id"] = id
		c["reason"] = locked_reason(id, ancestry_id)
		c["locked"] = c.reason != ""
		out.append(c)
	return out


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


## One pure step per record version (none needed in M10: version 1 is the first). A copy.
static func migrate(record: Dictionary) -> Dictionary:
	return record.duplicate(true)


## True for a record written by a later build ("v" above RECORD_VERSION): kept untouched, never drawn.
static func is_future(record: Variant) -> bool:
	if typeof(record) != TYPE_DICTIONARY:
		return false
	var v: Variant = (record as Dictionary).get("v", RECORD_VERSION)
	return SchemaUtil.is_number(v) and float(v) == floorf(float(v)) and int(v) > RECORD_VERSION


## Structural problems of a record (wrong types, not unknown ids): [] when it can be sanitized key by
## key. A record with any is replaced whole by the default (NOTE_BROKEN). Missing keys are not problems.
static func structure_errors(record: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(record) != TYPE_DICTIONARY:
		errors.append("appearance: not an object")
		return errors
	var r: Dictionary = record
	var v: Variant = r.get("v", RECORD_VERSION)
	if not SchemaUtil.is_number(v) or float(v) != floorf(float(v)) or int(v) < 1:
		errors.append("appearance.v: must be a whole number of at least 1")
	for key: String in ["preset", "skin", "eyes", "mark"]:
		if r.has(key) and typeof(r[key]) != TYPE_STRING:
			errors.append("appearance.%s: must be a string" % key)
	var blocks := {"hair": ["style", "color"], "beard": ["style", "color"], "tattoos": DESIGN_REGIONS + ["ink"],
		"paint": ["design", "color"], "outfit": ["set", "primary", "secondary"]}
	for key: String in blocks:
		if not r.has(key):
			continue
		if typeof(r[key]) != TYPE_DICTIONARY:
			errors.append("appearance.%s: must be an object" % key)
			continue
		for sub: String in blocks[key]:
			if (r[key] as Dictionary).has(sub) and typeof(r[key][sub]) != TYPE_STRING:
				errors.append("appearance.%s.%s: must be a string" % [key, sub])
	if r.has("scars") and typeof(r.scars) != TYPE_ARRAY:
		errors.append("appearance.scars: must be an array")
	return errors


## {"record": the record to keep, "dropped": unknown ids (each once), "notes": what the player is told}.
## See the class notes; `ancestry_id` is the character's line (its locked options are reset). With
## `check_locks` false no option counts as locked (describing a stored record, which was sanitized for its
## line when it was stored).
static func sanitize(record: Variant, ancestry_id := "", check_locks := true) -> Dictionary:
	var dropped := PackedStringArray()
	var notes := PackedStringArray()
	if is_future(record):
		notes.append(NOTE_FUTURE)
		return {"record": (record as Dictionary).duplicate(true), "dropped": dropped, "notes": notes}
	if not structure_errors(record).is_empty():
		notes.append(NOTE_BROKEN)
		return {"record": default_record(), "dropped": dropped, "notes": notes}
	var r: Dictionary = migrate(record)
	var base := default_record()
	if not structure_errors(base).is_empty() or is_future(base):
		base = FALLBACK_RECORD.duplicate(true)
	var locked := PackedStringArray()
	var misplaced := PackedStringArray()
	var out := r.duplicate(true)   # keys this build does not know stay as they are
	out["v"] = RECORD_VERSION
	var preset := str(r.get("preset", ""))
	out["preset"] = preset if preset == "" or not preset_record(preset).is_empty() else ""
	out["skin"] = _checked(r.get("skin", base.skin), "skin", false, str(base.skin), ancestry_id, dropped, locked, true, check_locks)
	out["eyes"] = _checked(r.get("eyes", base.eyes), "eyes", false, str(base.eyes), ancestry_id, dropped, locked, true, check_locks)
	var hair := _block(r, "hair", base)
	hair["style"] = _checked(hair.get("style"), "hair", false, str(base.hair.style), ancestry_id, dropped, locked, true, check_locks)
	hair["color"] = _checked(hair.get("color"), "haircolor", false, str(base.hair.color), ancestry_id, dropped, locked, true, check_locks)
	hair["grey"] = _grey(hair.get("grey", base.hair.grey))
	out["hair"] = hair
	var beard := _block(r, "beard", base)
	beard["style"] = _checked(beard.get("style"), "beard", false, str(base.beard.style), ancestry_id, dropped, locked, true, check_locks)
	beard["color"] = _checked(beard.get("color"), "haircolor", true, "", ancestry_id, dropped, locked, true, check_locks)
	beard["grey"] = _grey(beard.get("grey", base.beard.grey))
	out["beard"] = beard
	var tattoos := _block(r, "tattoos", base)
	for region: String in DESIGN_REGIONS:
		var t := _checked(tattoos.get(region, ""), "tattoo", true, "", ancestry_id, dropped, locked, true, check_locks)
		if t != "" and str(option(t).get("region", "")) != region:
			misplaced.append(t)
			t = ""
		tattoos[region] = t
	tattoos["ink"] = _checked(tattoos.get("ink"), "ink", false, str(base.tattoos.ink), ancestry_id, dropped, locked, false, check_locks)
	out["tattoos"] = tattoos
	var paint := _block(r, "paint", base)
	paint["design"] = _checked(paint.get("design", ""), "paint", true, "", ancestry_id, dropped, locked, true, check_locks)
	paint["color"] = _checked(paint.get("color"), "paintcolor", false, str(base.paint.color), ancestry_id, dropped, locked, false, check_locks)
	out["paint"] = paint
	var scars: Array = []
	for s: Variant in r.get("scars", []):
		var id := _checked(s, "scar", true, "", ancestry_id, dropped, locked, true, check_locks)
		if id != "" and not scars.has(id):
			scars.append(id)
	out["scars"] = scars.slice(0, MAX_SCARS)
	var mark := str(r.get("mark", MARK_AUTO))
	out["mark"] = mark if mark in [MARK_AUTO, MARK_NONE] else MARK_AUTO
	var outfit := _block(r, "outfit", base)
	outfit["set"] = _checked(outfit.get("set"), "outfit", false, str(base.outfit.set), ancestry_id, dropped, locked, true, check_locks)
	outfit["primary"] = _checked(outfit.get("primary"), "dye", false, str(base.outfit.primary), ancestry_id, dropped, locked, true, check_locks)
	outfit["secondary"] = _checked(outfit.get("secondary"), "dye", false, str(base.outfit.secondary), ancestry_id, dropped,
		locked, true, check_locks)
	out["outfit"] = outfit
	if not locked.is_empty():
		notes.append(NOTE_LOCKED % ", ".join(locked))
	if not misplaced.is_empty():
		notes.append(NOTE_MISPLACED % ", ".join(misplaced))
	return {"record": out, "dropped": dropped, "notes": notes}


## A copy of the record's block `key` ({} when missing), its missing keys taken from `base`.
static func _block(r: Dictionary, key: String, base: Dictionary) -> Dictionary:
	var out: Dictionary = (base.get(key, {}) as Dictionary).duplicate(true)
	if typeof(r.get(key)) == TYPE_DICTIONARY:
		for k: Variant in r[key]:
			out[k] = r[key][k]
	return out


## `value` when it names an option of `category` this line may use; "" when empty and allowed; else
## `fallback`, the id listed in `dropped` (unknown, when `report`) or its name in `locked`.
static func _checked(value: Variant, category: String, allow_empty: bool, fallback: String, ancestry_id: String,
		dropped: PackedStringArray, locked: PackedStringArray, report: bool, check_locks := true) -> String:
	var id := str(value) if value != null else ""
	if id == "" and allow_empty:
		return ""
	var opt := option(id) if id.begins_with(category + ".") else {}
	if opt.is_empty():
		if report and id != "" and not dropped.has(id):
			dropped.append(id)
		return fallback
	if check_locks and is_locked(id, ancestry_id):
		var name := str(opt.get("name", id))
		if not locked.has(name):
			locked.append(name)
		return fallback
	return id


static func _grey(v: Variant) -> float:
	return clampf(float(v), 0.0, 1.0) if SchemaUtil.is_number(v) else 0.0


## True when `record` passes sanitize unchanged in its ids: nothing dropped, nothing noted.
static func is_valid(record: Variant, ancestry_id := "") -> bool:
	var s := sanitize(record, ancestry_id)
	return (s.dropped as PackedStringArray).is_empty() and (s.notes as PackedStringArray).is_empty()


# --------------------------------------------------------------------------- the look

## The concrete look of `record` for a giant of `ancestry_id` (plan M10 §2.4; GiantLook.apply draws it):
## the palettes resolved, locked options replaced, `mark: "auto"` resolved with the ancestry. A record
## from a later build gives the default record's look.
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
		"tattoos": [],
		"paint": {},
		"mark": {},
		"scars": [],
		"garments": [],
		"dye_primary": _color(option(str(r.outfit.primary)), "color", Color(0.45, 0.38, 0.29)),
		"dye_secondary": _color(option(str(r.outfit.secondary)), "color", Color(0.16, 0.15, 0.13)),
	}
	var ink := _color(option(str(r.tattoos.ink)), "color", Color(0.1, 0.18, 0.4))
	for region: String in DESIGN_REGIONS:
		var t := option(str(r.tattoos.get(region, "")))
		if not t.is_empty():
			(look.tattoos as Array).append({"design": str(t.get("design", "")), "ink": ink})
	var paint := option(str(r.paint.design))
	if not paint.is_empty():
		look["paint"] = {"design": str(paint.get("design", "")),
			"color": _color(option(str(r.paint.color)), "color", Color(0.86, 0.84, 0.78))}
	var mark := ancestry_mark(ancestry_id) if str(r.mark) == MARK_AUTO else {}
	if not mark.is_empty():
		look["mark"] = {"design": str(mark.get("design", "")), "color": _color(mark, "color", Color(0.5, 0.5, 0.55)),
			"glow": float(mark.get("glow", 0.0))}
	for s: Variant in r.scars:
		var o := option(str(s))
		if not o.is_empty():
			(look.scars as Array).append(str(o.get("design", "")))
	for g: Variant in option(str(r.outfit.set)).get("garments", []):
		(look.garments as Array).append(str(g))
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


## The design regions (arms, chest, back, face) the record's outfit hides. Without an index: the outfit
## option's `covers`. With the giant's index (plan M10 §2.5): a design region is covered when every one
## of its body regions hides a design under the outfit's garments (design_hidden_body_regions). With
## `ancestry_id` the line's locks apply (see the class notes).
static func covered_regions(record: Variant, index: Dictionary = {}, ancestry_id := "") -> PackedStringArray:
	var r := _described(record, ancestry_id)
	var outfit_id := str((r.get("outfit", {}) as Dictionary).get("set", ""))
	if index.is_empty() or typeof(index.get("garments")) != TYPE_DICTIONARY:
		return _outfit_covers(outfit_id)
	var out := PackedStringArray()
	var body := design_hidden_body_regions(option(outfit_id).get("garments", []), index)
	for region: String in DESIGN_REGIONS:
		var all := true
		for b: int in DESIGN_REGION_BODY[region]:
			if not body.has(b):
				all = false
				break
		if all:
			out.append(region)
	return out


## The design regions an outfit option's `covers` lists (its data, no index).
static func _outfit_covers(outfit_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Variant in option(outfit_id).get("covers", []):
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
## more (sorted, unique).
static func design_hidden_body_regions(garments: Variant, index: Dictionary) -> PackedInt32Array:
	var seen := {}
	for b in covered_body_regions(garments, index):
		seen[b] = true
	var g_table: Dictionary = index.get("garments", {}) if typeof(index.get("garments")) == TYPE_DICTIONARY else {}
	var m_table: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	for g: Variant in (garments if typeof(garments) == TYPE_ARRAY else []):
		for mesh_id: Variant in g_table.get(str(g), []):
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
	var g_table: Dictionary = index.get("garments", {}) if typeof(index.get("garments")) == TYPE_DICTIONARY else {}
	var m_table: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	for g: Variant in (garments if typeof(garments) == TYPE_ARRAY else []):
		for mesh_id: Variant in g_table.get(str(g), []):
			var entry: Variant = m_table.get(str(mesh_id), {})
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			for c: Variant in (entry as Dictionary).get("covers", []):
				if SchemaUtil.is_number(c):
					seen[int(c)] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


# --------------------------------------------------------------------------- randomize

## A random record (plan M10 §2.10, the creator's Randomize), from `rng` only (the creator's own
## generator seeded from the clock: never Sim.rng or a Sim stream). `scope` is one category of
## RANDOM_SCOPES or "all"; the rest of `base` (the creator's current record; the default when empty) is
## kept. "all" keeps the outfit when `keep_outfit` (the Clothing category is not open). Natural hair
## colours NATURAL_HAIR_P of the time, at most MAX_RANDOM_TATTOOS tattoo regions and never one the
## outfit covers, war paint PAINT_P of the time and never where the outfit covers; options locked for
## `ancestry_id` are never picked; the mark's choice is the player's and is kept.
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
	if s == "presets":
		var ids := preset_ids()
		if not ids.is_empty():
			var picked := preset_record(ids[rng.randi_range(0, ids.size() - 1)])
			return sanitize(picked, ancestry_id).record
		return r
	r["preset"] = ""
	if s == "outfit" or (s == "all" and not keep_outfit):
		r["outfit"] = {"set": _pick(rng, "outfit", ancestry_id, str(r.outfit.set)),
			"primary": _pick(rng, "dye", ancestry_id, str(r.outfit.primary)),
			"secondary": _pick(rng, "dye", ancestry_id, str(r.outfit.secondary))}
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
	var covered := _outfit_covers(str(r.outfit.set))
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
		r.paint["design"] = ""
		if rng.randf() < PAINT_P:
			var choices: Array = []
			for region: String in DESIGN_REGIONS:
				if not covered.has(region):
					choices.append_array(_region_options("paint", region, ancestry_id))
			if not choices.is_empty():
				r.paint["design"] = choices[rng.randi_range(0, choices.size() - 1)]
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
		if typeof(o) != TYPE_DICTIONARY:
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
## sanitized for its line); with it, the line's locks apply, as to_look draws it.
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
	out.append("Eyes: " + _name(str(r.eyes)))
	var ink := _name(str(r.tattoos.ink))
	var tattoos := PackedStringArray()
	for region: String in DESIGN_REGIONS:
		var t := str(r.tattoos.get(region, ""))
		if t != "":
			tattoos.append("%s %s" % [ink, _name(t)])
	out.append("Tattoos: " + (", ".join(tattoos) if not tattoos.is_empty() else "none"))
	var paint := str(r.paint.design)
	out.append("War paint: " + ("%s %s" % [_name(str(r.paint.color)), _name(paint)] if paint != "" else "none"))
	var scars := PackedStringArray()
	for s: Variant in r.scars:
		scars.append(_name(str(s)))
	out.append("Scars: " + (", ".join(scars) if not scars.is_empty() else "none"))
	out.append("Ancestry mark: " + ("shown" if str(r.mark) == MARK_AUTO else "hidden"))
	var dyes := _name(str(r.outfit.primary))
	if str(r.outfit.secondary) != str(r.outfit.primary):
		dyes += " and " + _name(str(r.outfit.secondary))
	out.append("Clothing: %s, %s" % [_name(str(r.outfit.set)), dyes])
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

## GameData's post-pass at anchor P42 (plan M10 §2.3): every category's set once, all of them when any
## appearance record exists; the default preset exists and uses each set's default; every preset's
## record names itself and passes sanitize() with nothing dropped or noted (presets are offered at New
## Game, before any line is chosen, so they use no locked option).
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
	for c: String in CATEGORIES:
		if not by_category.has(c):
			errors.append("data/appearance: no appearance set of category '%s' (%s%s)" % [c, SET_PREFIX, c])
	var default_preset: Dictionary = records.get(DEFAULT_PRESET, {})
	if default_preset.is_empty():
		errors.append("data/appearance: the default preset %s is missing" % DEFAULT_PRESET)
	else:
		var d: Dictionary = default_preset.get("appearance", {}) if typeof(default_preset.get("appearance")) == TYPE_DICTIONARY else {}
		var chosen := {"skin": d.get("skin"), "eyes": d.get("eyes"), "hair": _get2(d, "hair", "style"),
			"haircolor": _get2(d, "hair", "color"), "beard": _get2(d, "beard", "style"), "ink": _get2(d, "tattoos", "ink"),
			"paintcolor": _get2(d, "paint", "color"), "outfit": _get2(d, "outfit", "set"), "dye": _get2(d, "outfit", "primary")}
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
	return errors


static func _get2(d: Dictionary, a: String, b: String) -> Variant:
	return (d.get(a) as Dictionary).get(b) if typeof(d.get(a)) == TYPE_DICTIONARY else null
