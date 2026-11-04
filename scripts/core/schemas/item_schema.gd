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

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	## @anchor P12

	pass


static func required_ids() -> Dictionary:
	return {}
