extends RefCounted
## Schema module for "titan_roster" records (A4): the signature titans in the story's order - the save's titan
## records (schema 3: ExpansionState) and the Character menu's Titans tab read it
## (data/titans/titan_roster.json, the only record of the type).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "titan_roster.signature", "type": "titan_roster",
##    "titans": [{"id": "titan.stoneback", "display_name": "Stoneback", "epithet", "act": 1, "where", "height_m",
##                "enemy": "enemy.stoneback", "boss_ids": [...], "outcome_flag", "defeated_flag", "sighted_poi",
##                "loot_table": "loot.stoneback"}, {"id": "titan.ogre_king", "display_name": ..., "act": 1}, ...]}
##
## A slot a later milestone fills leaves its enemy, boss ids and flags out (the menu shows it as unknown).

const U := preload("res://scripts/core/schemas/schema_util.gd")
const MAX_TITANS := 16


static func fields() -> Dictionary:
	return {
		"titans": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"display_name": U.str_field(),
			"epithet": U.str_field(),
			"act": U.int_field(1, 3, true),
			"where": U.str_field(),
			"height_m": U.pos(),
			"enemy": U.ref("enemy", false, true),
			"boss_ids": {"t": "array", "items": "string"},
			"outcome_flag": U.str_field(),
			"defeated_flag": U.str_field(),
			"sighted_poi": U.ref("poi", false, true),
			"loot_table": U.ref("loot_table", false, true)}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var list: Array = d.titans if typeof(d.get("titans")) == TYPE_ARRAY else []
	if list.size() > MAX_TITANS:
		out.errors.append("%s.titans: at most %d titans" % [ctx, MAX_TITANS])
	var ids := {}
	for i in list.size():
		var t: Variant = list[i]
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var id := str(t.get("id", ""))
		if not id.begins_with("titan."):
			out.errors.append("%s.titans[%d]: id '%s' must begin with 'titan.'" % [ctx, i, id])
		if ids.has(id):
			out.errors.append("%s.titans[%d]: duplicate titan id '%s'" % [ctx, i, id])
		ids[id] = true


static func required_ids() -> Dictionary:
	return {"titan_roster.signature": "titan_roster"}
