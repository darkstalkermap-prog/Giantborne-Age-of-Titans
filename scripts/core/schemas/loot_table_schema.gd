extends RefCounted
## Schema module for "loot_table" records (P12, plan §2.8.3): what an enemy or a breakable prop
## drops, once per world or entity id (Loot.roll, WorldState.try_award_loot).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "loot.ogre_king", "type": "loot_table", "rolls": 0, "entries": [],
##    "guaranteed": [{"item": "item.ogre_tusk", "count": 1}, {"item": "item.iron_ingot", "count": 1}]}
##
## `guaranteed` items always drop. Then `rolls` times one weighted entry {item, count, weight} is
## picked with Sim.rng_for("loot") (each pick independently, weights relative to their sum).

const U := preload("res://scripts/core/schemas/schema_util.gd")

## Upper bounds that keep a typo from flooding the inventory.
const MAX_ROLLS := 10
const MAX_COUNT := 99


static func fields() -> Dictionary:
	return {
		"rolls": U.int_field(0, MAX_ROLLS, true),
		"entries": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"item": U.ref("item", true),
			"count": U.int_field(1, MAX_COUNT, true),
			"weight": U.pos(true)}},
		"guaranteed": {"t": "array", "items": "dict", "item_fields": {
			"item": U.ref("item", true),
			"count": U.int_field(1, MAX_COUNT, true)}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var rolls := int(d.get("rolls", 0)) if U.is_number(d.get("rolls")) else 0
	var entries: Array = d.entries if typeof(d.get("entries")) == TYPE_ARRAY else []
	var guaranteed: Array = d.guaranteed if typeof(d.get("guaranteed")) == TYPE_ARRAY else []
	if rolls > 0 and entries.is_empty():
		out.errors.append("%s: rolls %d needs at least one weighted entry to roll" % [ctx, rolls])
	if rolls == 0 and not entries.is_empty():
		out.warnings.append("%s: entries are never rolled (rolls is 0)" % ctx)
	if guaranteed.is_empty() and (rolls == 0 or entries.is_empty()):
		out.warnings.append("%s: this table can never drop anything" % ctx)


static func required_ids() -> Dictionary:
	return {}
