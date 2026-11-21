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
## "variant": "" | "<variant>", "palette": {"skin"|"hair"|"cloth"|"faction": "#rrggbb"}, "gear": [...],
## "rig": "skinned" | "box"} (plan §2.9; absent: the scene's own default). P62: `rig` picks an animal's rig - the
## cavalry's skinned horse (SkinnedQuadrupedRig) or the old box rig it can fall back to (plan §3.18's beasts' gate);
## the rider is the `role`. Presentation only: no gameplay code reads it.
## P64: a creature's body (the brutes and the wolves: BruteRig, SkinnedWolfRig) names `creature` (a kind of the
## creatures' manifest: ogre, troll, wolf) instead of a role, its `variant` (ogre, troll, whelp; wolf, dire_wolf), an
## `outfit` (the bosses' gear: ogre_king, troll_matriarch) and the palette's bands; every body names a role or a
## creature.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## The pieces of the role's gear a body may carry (P59's gear.glb).
const GEAR := ["sword", "spear", "shield", "banner", "bow", "quiver", "staff", "hammer"]
## The palette's bands a record may set (plan §2.9).
const BANDS := ["skin", "hair", "cloth", "faction"]
const COLOR_REGEX := "^#[0-9a-fA-F]{6}$"
## P62: an animal's rig (`body.rig`).
const RIGS := ["skinned", "box"]
## P64: the creatures a body may name (assets/creatures/manifest.json's kinds) and the bosses' outfits.
const CREATURES := ["ogre", "troll", "wolf"]
const OUTFITS := ["ogre_king", "troll_matriarch"]


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
		"role": U.ref("person_role", false),
		"creature": U.str_field(false, CREATURES),
		"outfit": U.str_field(false, OUTFITS),
		"variant": U.str_field(),
		"palette": {"t": "dict", "keys_enum": BANDS, "values": U.str_field()},
		"gear": {"t": "array", "items": "string", "items_enum": GEAR},
		"rig": U.str_field(false, RIGS)}}


## The checks of a `body` value (colours are colours).
static func check_body(body: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		return
	var pal: Variant = (body as Dictionary).get("palette")
	if typeof(pal) == TYPE_DICTIONARY:
		for k: Variant in pal:
			_check_color(pal[k], "%s.body.palette.%s" % [ctx, k], out)
	var named := int((body as Dictionary).has("role")) + int((body as Dictionary).has("creature"))
	if named != 1:
		out.errors.append("%s.body: names a role or a creature (one of them)" % ctx)


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
