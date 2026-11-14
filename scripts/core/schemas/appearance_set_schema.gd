extends RefCounted
## Schema module for "appearance_set" records (P42; plan M10 §2.3): one category of the giant's look
## (data/appearance/set_<category>.json), its options in the order the creator shows them. Loaded by
## DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "appearance_set.hair", "type": "appearance_set", "category": "hair",
##    "display_name": "Hair", "options": [{"key": "long_back", "name": "Long, combed back",
##    "mesh": "Hair_long_back", "scalp_tint": 1.0, "default": true}, ...]}
##
## An option's id in a record is <category>.<key>. Every option has a key (unique in the set), a name,
## optionally "default": true and "requires": {"ancestry": <ancestry id>} (locked until that line is
## chosen); then the category's fields:
##   skin, ink, paintcolor, dye   color ("#rrggbb", sRGB)
##   eyes                         color, glow (0-1; the Stormborn eyes glow a little)
##   haircolor                    color, tip (the sun-bleached ends), natural (default true: Randomize
##                                picks a natural colour nine times in ten)
##   hair                         mesh (a giant index mesh id, "" for none), scalp_tint (0-1)
##   beard                        mesh, stubble (0-1, the stubble mask), beard_tint (0-1, the skin under
##                                the cards takes the beard's colour)
##   tattoo, paint                design (a giant index design id), region (arms | chest | back | face)
##   scar                         design
##   mark                         design, color, glow (and requires: the line whose mark it is)
##   outfit                       garments (giant index garment ids), covers (the design regions its
##                                garments hide: "Hidden by your clothing", Randomize avoids them)
## Exactly one option is the default in every set except tattoo, paint, scar and mark (none there).
## Cross-record rules (the presets against the sets, the default preset's choices) are
## Appearance.data_errors' (GameData, anchor P42); the index ids are checked by test_giant_look_real.

const U := preload("res://scripts/core/schemas/schema_util.gd")

const KEY_REGEX := "^[a-z][a-z0-9_]*$"
const PALETTES := ["skin", "eyes", "haircolor", "ink", "paintcolor", "dye", "mark"]


static func fields() -> Dictionary:
	return {
		"category": U.str_field(true, Appearance.CATEGORIES),
		"options": {"t": "array", "req": true, "items": "dict"},
	}


## The field specs of one option of `category`.
static func option_fields(category: String) -> Dictionary:
	var f := {
		"key": U.str_field(true),
		"name": U.str_field(true),
		"default": U.bool_field(),
		"requires": {"t": "dict", "fields": {"ancestry": U.ref("ancestry", true)}},
	}
	match category:
		"skin", "ink", "paintcolor", "dye":
			f["color"] = U.str_field(true)
		"eyes":
			f["color"] = U.str_field(true)
			f["glow"] = U.num(0.0, 1.0)
		"haircolor":
			f["color"] = U.str_field(true)
			f["tip"] = U.str_field(true)
			f["natural"] = U.bool_field()
		"hair":
			f["mesh"] = U.str_field(true)
			f["scalp_tint"] = U.num(0.0, 1.0, true)
		"beard":
			f["mesh"] = U.str_field(true)
			f["stubble"] = U.num(0.0, 1.0, true)
			f["beard_tint"] = U.num(0.0, 1.0, true)
		"tattoo", "paint":
			f["design"] = U.str_field(true)
			f["region"] = U.str_field(true, Appearance.DESIGN_REGIONS)
		"scar":
			f["design"] = U.str_field(true)
		"mark":
			f["design"] = U.str_field(true)
			f["color"] = U.str_field(true)
			f["glow"] = U.num(0.0, 1.0)
		"outfit":
			f["garments"] = {"t": "array", "req": true, "items": "string"}
			f["covers"] = U.enum_array(Appearance.DESIGN_REGIONS)
	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var category := str(d.get("category", ""))
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and category in Appearance.CATEGORIES and str(id) != Appearance.SET_PREFIX + category:
		out.errors.append("%s: the id of the %s set is '%s%s' (got '%s')" % [ctx, category, Appearance.SET_PREFIX,
			category, id])
	if not category in Appearance.CATEGORIES:
		return   # fields() reports the unknown category
	var opts: Variant = d.get("options")
	if typeof(opts) != TYPE_ARRAY:
		return
	if (opts as Array).is_empty():
		out.errors.append("%s.options: a set needs at least one option" % ctx)
		return
	var spec := option_fields(category)
	var re := RegEx.create_from_string(KEY_REGEX)
	var keys := {}
	var defaults := 0
	var i := 0
	for o: Variant in opts:
		var octx := "%s.options[%d]" % [ctx, i]
		i += 1
		if typeof(o) != TYPE_DICTIONARY:
			continue   # check_value reports it
		var opt: Dictionary = o
		U.check_fields(opt, spec, octx, out)
		var key := str(opt.get("key", ""))
		if typeof(opt.get("key")) == TYPE_STRING:
			if re.search(key) == null:
				out.errors.append("%s.key: '%s' must be lowercase letters, digits and underscores" % [octx, key])
			if keys.has(key):
				out.errors.append("%s.key: duplicate key '%s' in the %s set" % [octx, key, category])
			keys[key] = true
		if bool(opt.get("default", false)):
			defaults += 1
		for ckey: String in ["color", "tip"]:
			if typeof(opt.get(ckey)) == TYPE_STRING:
				_check_color(str(opt[ckey]), "%s.%s" % [octx, ckey], out)
		if category in ["tattoo", "paint", "scar", "mark"] and typeof(opt.get("design")) == TYPE_STRING and str(opt.design) == "":
			out.errors.append("%s.design: a design option names its giant index design" % octx)
		if category == "outfit" and typeof(opt.get("garments")) == TYPE_ARRAY and (opt.garments as Array).is_empty():
			out.errors.append("%s.garments: an outfit shows at least one garment" % octx)
		if category == "mark" and Appearance.required_ancestry(opt) == "":
			out.errors.append("%s.requires: a mark belongs to a line (requires.ancestry)" % octx)
	if category in Appearance.NO_DEFAULT:
		if defaults > 0:
			out.errors.append("%s.options: the %s set has no default (an empty choice is its default)" % [ctx, category])
	elif defaults != 1:
		out.errors.append("%s.options: exactly one option of the %s set is the default (found %d)" % [ctx, category, defaults])


## "#rrggbb" only (sRGB, as every colour of the data).
static func _check_color(s: String, ctx: String, out: Dictionary) -> void:
	if s.length() != 7 or not s.begins_with("#") or not Color.html_is_valid(s):
		out.errors.append("%s: '%s' is not a colour (#rrggbb)" % [ctx, s])


static func required_ids() -> Dictionary:
	return {}
