extends RefCounted
## Schema module for "poi" records (P20 pre-declares it for M7; plan M6-M9 §2.7, §5.4): a point
## of interest - a settlement, shrine, waystone, ruin, landmark, camp, lair, boss arena, forge,
## gate, vista, exit or sealed place. P25 ships the first records; Discovery (P27) and the world
## index read them.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "poi.hollowmere", "type": "poi", "display_name": "Hollowmere",
##    "level": "level.world", "region": "region.greywood", "kind": "settlement",
##    "position_m": [-640, 22, -40], "radius_m": 70, "xp": 40, "map_icon": "settlement",
##    "compass": true, "landmark": "world.greywood.hollowmere_hall", "skyline": true, "min_stage": 0,
##    "reveals_m": 0, "max_inner_stage": 4, "green_m": [-610, 20, 20],
##    "note": "The woodfolk's stilt village on the black pond."}
##
## `landmark` names a layout element that stands within the radius (the world builder checks it);
## `skyline` puts that landmark's silhouette in the skyline (and lets the compass show the POI as
## "?" from 1,000 m); a `vista` reveals every POI within `reveals_m` (default 400) on the map; a
## `secret` (a sealed place) needs `min_stage` and its `seal` (the prop or gate that opens it); a
## settlement's `max_inner_stage` and `green_m` tell its talkers where to meet a bigger giant.
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		"level": U.ref("level", true),
		"region": U.ref("region", false, true),
		"kind": U.str_field(true, DataValidator.POI_KINDS),
		"position_m": U.vec3(true),
		"radius_m": U.pos(true),
		# Discovery XP (every POI gives some, decision 33).
		"xp": U.int_field(0, 10000),
		"map_icon": U.str_field(),
		"compass": U.bool_field(),
		"landmark": U.str_field(),
		"skyline": U.bool_field(),
		# A sealed place opens to this stage (0 = any).
		"min_stage": U.int_field(0, 10),
		"reveals_m": U.num(0.0),
		"max_inner_stage": U.int_field(0, 10),
		"green_m": U.vec3(),
		# A sealed place's key: the world id of the prop or gate that opens it.
		"seal": U.str_field(),
		"note": U.str_field(),
	}
	## @anchor P25

	## @anchor P27

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("poi."):
		out.errors.append("%s: poi ids start with 'poi.' (got '%s')" % [ctx, id])
	for key: String in ["landmark", "seal"]:
		var v: Variant = d.get(key, "")
		if typeof(v) == TYPE_STRING and v != "":
			U.check_id_string(v, "%s.%s" % [ctx, key], out)
	var kind := str(d.get("kind", ""))
	if kind == "secret":
		if int(d.get("min_stage", 0)) < 1:
			out.errors.append("%s: a secret (sealed place) needs min_stage >= 1" % ctx)
		if str(d.get("seal", "")) == "":
			out.errors.append("%s: a secret (sealed place) needs its seal (the world id that opens it)" % ctx)
	if bool(d.get("skyline", false)) and str(d.get("landmark", "")) == "":
		out.errors.append("%s: skyline needs a landmark (its silhouette is the landmark's)" % ctx)
	if d.has("green_m") != d.has("max_inner_stage"):
		out.errors.append("%s: green_m and max_inner_stage go together (where talkers meet a bigger giant)" % ctx)
	## @anchor P25

	## @anchor P27


static func required_ids() -> Dictionary:
	return {}
