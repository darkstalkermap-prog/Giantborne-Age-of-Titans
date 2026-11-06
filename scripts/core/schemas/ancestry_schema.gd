extends RefCounted
## Schema module for "ancestry" records (one neutral ancestry in the prototype; P33 adds the three
## ancestries of plan M6-M9 §2.11 and §5.12 - attribute bonuses, passives, a signature ability and
## dialogue tags - below its anchor).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.


static func fields() -> Dictionary:
	var f := {}
	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P31

	## @anchor P33

	return f


static func semantic(_d: Dictionary, _ctx: String, _out: Dictionary) -> void:
	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P31

	## @anchor P33

	pass


static func required_ids() -> Dictionary:
	return {}
