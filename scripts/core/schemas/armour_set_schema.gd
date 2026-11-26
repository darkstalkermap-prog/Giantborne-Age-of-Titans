extends RefCounted
## Schema module for "armour_set" records (B1): a set of armour pieces, the bonus a giant earns by wearing enough of
## them, and the forge's refit steps of its pieces (P31's forge tiers: an iron forge's or a titan forge's work, and
## the material a forge must work - titan stone only where a titan's settlement has learned it).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "armour_set.quarry", "type": "armour_set", "display_name": "Quarry set",
##    "description": "...", "pieces": ["armour.quarry_pauldrons", ...], "weight_class": "heavy",
##    "bonuses": [{"pieces": 2, "name": "...", "text": "...", "modifiers": {...}}, {"pieces": 4, ...}],
##    "refit": [{"tier": 2, "cost": [{"item", "count"}], "forge_tier": "iron", "works": "titan_stone"}, {"tier": 3, ...}],
##    "perk_cost": [{"item", "count"}], "works": "titan_stone"}
##
## A piece's tier is 1 when made; refit[i] takes it to its "tier" (2, then 3; Armour.TIER_MULT scales its defence and
## poise). "works" (a set's, or a step's) names the material trait a forge must have (Forge.works; "" = any forge).

const U := preload("res://scripts/core/schemas/schema_util.gd")
const WEIGHT_CLASSES := ["light", "medium", "heavy"]


static func cost() -> Dictionary:
	return {"t": "array", "items": "dict", "item_fields": {"item": U.ref("item", true), "count": U.int_field(1, 99, true)}}


static func fields() -> Dictionary:
	return {
		"pieces": U.ref_array("armour", true),
		"weight_class": U.str_field(true, WEIGHT_CLASSES),
		"bonuses": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"pieces": U.int_field(2, 7, true),
			"name": U.str_field(true),
			"text": U.str_field(true),
			"modifiers": {"t": "dict", "req": true, "keys_enum": DataValidator.STATUS_MODIFIERS, "values": U.num(0.0)}}},
		"refit": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"tier": U.int_field(2, 3, true),
			"cost": cost(),
			"forge_tier": U.str_field(false, ["iron", "titan", "colossus"]),
			"works": U.str_field()}},
		"perk_cost": cost(),
		"works": U.str_field(),
		"color": U.str_field(),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var refit: Array = d.refit if typeof(d.get("refit")) == TYPE_ARRAY else []
	for i in refit.size():
		if typeof(refit[i]) == TYPE_DICTIONARY and int(refit[i].get("tier", 0)) != i + 2:
			out.errors.append("%s.refit[%d]: the steps go to tiers 2 and 3 in order" % [ctx, i])
	var pieces: Array = d.pieces if typeof(d.get("pieces")) == TYPE_ARRAY else []
	for b: Variant in d.get("bonuses", []):
		if typeof(b) == TYPE_DICTIONARY and int(b.get("pieces", 0)) > pieces.size():
			out.errors.append("%s.bonuses: a bonus for %d pieces, but the set has %d" % [ctx, int(b.pieces), pieces.size()])


static func required_ids() -> Dictionary:
	return {}
