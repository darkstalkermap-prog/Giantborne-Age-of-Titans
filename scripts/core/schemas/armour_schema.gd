extends RefCounted
## Schema module for "armour" records (B1): one functional armour piece - the numbers it adds while worn and the look
## it shows on the giant (data/armour/armour_*.json). Worn pieces count through the passives (Armour.modifiers ->
## Combatant.set_passives), never statuses; the look's cosmetic slots are not touched (Armour.dress shows the piece over
## the giant's own look while its slot is shown).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "armour.quarry_pauldrons", "type": "armour", "display_name": "Quarry Pauldrons",
##    "description": "...", "slot": "shoulders", "set": "armour_set.quarry",
##    "defence": {"physical": 10, "fire": 0.04},     physical: armour points (100 / (100 + A) of a blow is kept, at
##                                                    any size); the elemental types: a resistance added (0.04 = 4 %)
##    "poise": 10,                                    added to the poise threshold
##    "weight": 3,                                    0-6: what the set's frame carries (Armour.weight_mult)
##    "modifiers": {"stamina_cost_mult": 0.97},       optional, STATUS_MODIFIERS keys (a light piece's own)
##    "perks": ["armour_perk.steady", ...],           the authored perks a forge's Reforge tab may set on it (1-4)
##    "look": {"garments": ["garment.mail_hauberk"], "dye": "metal.iron"},   the wardrobe's garments it shows (its
##            cosmetic slots), or {"meshes": ["Armour_quarry_pauldrons"], "clears": ["shoulders"],
##            "clears_accessories": ["neck"]}: the giant index's modelled pieces (the Quarry set's stone) and the
##            cosmetic slots they empty while shown
##    "min_stage": 1}
##
## Semantic rules: the slot is one of the seven (ExpansionState.ARMOUR_SLOTS); a look's garments are options of the
## appearance sets (Armour.data_errors checks them and the meshes against the giant's index).

const U := preload("res://scripts/core/schemas/schema_util.gd")
const SLOTS := ["head", "shoulders", "chest", "arms", "waist", "legs", "trinket"]


static func fields() -> Dictionary:
	return {
		"slot": U.str_field(true, SLOTS),
		"set": U.ref("armour_set", true),
		"defence": {"t": "dict", "req": true, "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(0.0, 60.0)},
		"poise": U.num(0.0, 100.0),
		"weight": U.num(0.0, 6.0, true),
		"modifiers": {"t": "dict", "keys_enum": DataValidator.STATUS_MODIFIERS, "values": U.num(0.0)},
		"perks": U.ref_array("armour_perk", true),
		"look": {"t": "dict", "req": true, "fields": {
			"garments": {"t": "array", "items": "string"},
			"meshes": {"t": "array", "items": "string"},
			"clears": U.enum_array(Appearance.SLOTS),
			"clears_accessories": U.enum_array(Appearance.ACCESSORY_SLOTS),
			"dye": U.str_field()}},
		"min_stage": U.int_field(1, 10),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var defence: Variant = d.get("defence")
	if typeof(defence) == TYPE_DICTIONARY:
		for t: Variant in defence:
			if str(t) != "physical" and U.is_number(defence[t]) and float(defence[t]) > 0.5:
				out.errors.append("%s.defence.%s: an elemental resistance is a share (at most 0.5)" % [ctx, t])
	var perks: Variant = d.get("perks")
	if typeof(perks) == TYPE_ARRAY and ((perks as Array).is_empty() or (perks as Array).size() > 4):
		out.errors.append("%s.perks: one to four perks" % ctx)


static func required_ids() -> Dictionary:
	return {}
