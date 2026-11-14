extends RefCounted
## Schema module for "appearance_preset" records (P42; plan M10 §2.3): a whole look the creator offers
## (data/appearance/preset_<key>.json). Loaded by DataValidator's registry (see data_validator.gd).
##
##   {"schema_version": 1, "id": "appearance_preset.wanderer", "type": "appearance_preset",
##    "display_name": "The Wanderer", "description": "...", "ancestry": "ancestry.stoneblood" (optional,
##    a suggestion only), "appearance": {a full record, Appearance's format, "preset" naming itself}}
##
## Here: the record's shape (Appearance.structure_errors) and its version. Whether its ids exist in the
## sets, and the default preset's choices, are Appearance.data_errors' (GameData, anchor P42).

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"appearance": {"t": "dict", "req": true},
		"ancestry": U.ref("ancestry"),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with(Appearance.PRESET_PREFIX):
		out.errors.append("%s: appearance preset ids start with '%s' (got '%s')" % [ctx, Appearance.PRESET_PREFIX, id])
	var a: Variant = d.get("appearance")
	if typeof(a) != TYPE_DICTIONARY:
		return
	for e in Appearance.structure_errors(a):
		out.errors.append("%s.%s" % [ctx, e])
	var v: Variant = (a as Dictionary).get("v")
	if not U.is_number(v) or int(v) != Appearance.RECORD_VERSION:
		out.errors.append("%s.appearance.v: a preset's record is version %d (got %s)" % [ctx, Appearance.RECORD_VERSION, v])
	for key: String in ["skin", "eyes", "hair", "beard", "tattoos", "paint", "scars", "mark", "outfit"]:
		if not (a as Dictionary).has(key):
			out.errors.append("%s.appearance: a preset's record is a full record (no '%s')" % [ctx, key])


static func required_ids() -> Dictionary:
	return {}
