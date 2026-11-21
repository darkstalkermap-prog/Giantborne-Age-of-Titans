extends RefCounted
## Schema module for "person_role" records (P60; plan M11 §2.9): one role of the people pipeline as the game
## draws it (data/people/role_<role>.json): which of the role's body variants a hash of an entity id picks from,
## and the role's palette - skin tones, hair colours, cloth colours and the faction colours its faction band
## takes. The role's meshes, atlases and clips are P59's (assets/people/<asset_role>.glb, the manifest's index).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "person_role.soldier", "type": "person_role", "asset_role": "soldier",
##    "variants": ["soldier_a", "soldier_b", "soldier_c"],
##    "palette": {"skin": ["#c69a7e", ...], "hair": ["#3b2a1e", ...], "cloth": ["#6f6a5e", ...]},
##    "factions": {"default": "#7a2c24", "brannock": "#3e5a8a", ...}}
##
## Colours are "#rrggbb" (sRGB). `variants` is the pool an entity id's hash picks from (a named variant, the
## iron guard's, is named by the actor's record: its `body.variant`). `factions` maps an actor's faction (its
## short name, as EnemyActor.faction holds it) to the colour of the faction band; "default" is required.
##
## The actor records' `body` key (enemy and npc records; body_field() below): {"role": "person_role.<role>",
## "variant": "" | "<variant>", "palette": {"skin"|"hair"|"cloth"|"faction": "#rrggbb"}, "gear": [...]}
## (plan §2.9; absent: the scene's own default). Presentation only: no gameplay code reads it.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## The pieces of the role's gear a body may carry (P59's gear.glb).
const GEAR := ["sword", "spear", "shield", "banner", "bow", "quiver", "staff", "hammer"]
## The palette's bands a record may set (plan §2.9).
const BANDS := ["skin", "hair", "cloth", "faction"]
const COLOR_REGEX := "^#[0-9a-fA-F]{6}$"


static func fields() -> Dictionary:
	return {
		"asset_role": U.str_field(true),
		"variants": {"t": "array", "items": "string", "req": true},
		"palette": {"t": "dict", "req": true, "fields": {
			"skin": {"t": "array", "items": "string", "req": true},
			"hair": {"t": "array", "items": "string", "req": true},
			"cloth": {"t": "array", "items": "string", "req": true}}},
		"factions": {"t": "dict", "req": true, "values": U.str_field()},
	}


## The actor records' `body` key (enemy_schema and npc_schema merge it).
static func body_field() -> Dictionary:
	return {"t": "dict", "fields": {
		"role": U.ref("person_role", true),
		"variant": U.str_field(),
		"palette": {"t": "dict", "keys_enum": BANDS, "values": U.str_field()},
		"gear": {"t": "array", "items": "string", "items_enum": GEAR}}}


## The checks of a `body` value (colours are colours).
static func check_body(body: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		return
	var pal: Variant = (body as Dictionary).get("palette")
	if typeof(pal) == TYPE_DICTIONARY:
		for k: Variant in pal:
			_check_color(pal[k], "%s.body.palette.%s" % [ctx, k], out)


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("person_role."):
		out.errors.append("%s: person_role ids start with 'person_role.' (got '%s')" % [ctx, id])
	if typeof(d.get("variants")) == TYPE_ARRAY and (d.variants as Array).is_empty():
		out.errors.append("%s: variants must list at least one body variant" % ctx)
	var pal: Variant = d.get("palette")
	if typeof(pal) == TYPE_DICTIONARY:
		for band: String in ["skin", "hair", "cloth"]:
			var list: Variant = pal.get(band)
			if typeof(list) != TYPE_ARRAY:
				continue
			if (list as Array).is_empty():
				out.errors.append("%s.palette.%s: at least one colour" % [ctx, band])
			for i in (list as Array).size():
				_check_color(list[i], "%s.palette.%s[%d]" % [ctx, band, i], out)
	var fac: Variant = d.get("factions")
	if typeof(fac) == TYPE_DICTIONARY:
		if not (fac as Dictionary).has("default"):
			out.errors.append("%s.factions: needs a 'default' colour" % ctx)
		for k: Variant in fac:
			_check_color(fac[k], "%s.factions.%s" % [ctx, k], out)


static func _check_color(v: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(v) != TYPE_STRING or RegEx.create_from_string(COLOR_REGEX).search(str(v)) == null:
		out.errors.append("%s: expected a colour \"#rrggbb\" (got %s)" % [ctx, v])


static func required_ids() -> Dictionary:
	return {}
