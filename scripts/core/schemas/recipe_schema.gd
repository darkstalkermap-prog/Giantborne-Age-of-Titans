extends RefCounted
## Schema module for "recipe" records (B1): what a forge can make from materials - an armour piece or a weapon -
## and where (data/recipes/recipe_*.json). The forge screen's Armour and Weapons tabs list them; Forge.craft makes one.
##
##   {"schema_version": 1, "id": "recipe.quarry_pauldrons", "type": "recipe", "makes": "armour.quarry_pauldrons",
##    "cost": [{"item": "item.stoneback_slab", "count": 3}, ...], "forge_tier": "iron", "works": "titan_stone",
##    "requires_flag": "world.quarry.reopened", "order": 10}
##
## "makes" is an armour or a weapon record. "forge_tier" is P31's (iron or titan: a titan forge does every step);
## "works" a material trait the forge must have (Forge.works: Millford's forge works titan stone once its quarry is
## reopened); "requires_flag" a world flag that must be truthy (the settlement's aftermath; "" = none). A later
## titan's settlement unlocks its recipes the same way: its forge's works and its flag.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"makes": U.str_field(true),
		"cost": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"item": U.ref("item", true), "count": U.int_field(1, 99, true)}},
		"forge_tier": U.str_field(false, ["iron", "titan"]),
		"works": U.str_field(),
		"requires_flag": U.str_field(),
		"order": U.int_field(0, 1000),
		"where": U.str_field(),   # where a forge that cannot make it sends the giant ("Millford's quarry forge, ...")
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var makes := str(d.get("makes", ""))
	if makes != "" and not (makes.begins_with("armour.") or makes.begins_with("weapon.")):
		out.errors.append("%s.makes: an armour or a weapon record (got '%s')" % [ctx, makes])
	if typeof(d.get("cost")) == TYPE_ARRAY and (d.cost as Array).is_empty():
		out.errors.append("%s.cost: a recipe costs something" % ctx)


static func required_ids() -> Dictionary:
	return {}
