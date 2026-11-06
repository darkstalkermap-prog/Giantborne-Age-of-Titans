extends RefCounted
## Schema module for "item" records (inventory items and loot).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {"stack_max": U.int_field(1)}
	## @anchor P12
	# Items (P12, plan §2.8.2): the inventory groups them by category (material: iron, wood;
	# quest: the supply cache, the crown; trophy: the ogre tusk; key), and tags quest items.
	f.merge({
		"category": U.str_field(false, DataValidator.ITEM_CATEGORIES),
		"quest_item": U.bool_field(),
	})

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P31

	## @anchor P33

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	## @anchor P12
	if typeof(d.get("quest_item")) == TYPE_BOOL and d.quest_item and not str(d.get("category", "material")) in ["quest", "key"]:
		out.warnings.append("%s: a quest_item is usually of category quest or key (got %s)" % [
			ctx, str(d.get("category", "material"))])

	pass

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P31

	## @anchor P33


static func required_ids() -> Dictionary:
	return {}
