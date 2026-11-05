extends RefCounted
## Schema module for "ancestry" records (one neutral ancestry in the prototype).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).


static func fields() -> Dictionary:
	return {}


static func semantic(_d: Dictionary, _ctx: String, _out: Dictionary) -> void:
	pass


static func required_ids() -> Dictionary:
	return {}
