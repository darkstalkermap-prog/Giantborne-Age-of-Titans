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
	# P33 (plan M6-M9 §2.11, §5.12, decision 22): attribute points the ancestry adds once, when it is
	# chosen; its lasting passives (resistances by damage type, and STATUS_MODIFIERS keys folded into
	# the Combatant like the talents'); its signature ability (learned on choosing it); the dialogue
	# tags peoples answer to, and the player-facing line that names them.
	f.merge({
		"attribute_bonus": {"t": "dict", "keys_enum": DataValidator.ATTRIBUTES, "values": SchemaUtil.int_field(0, 10)},
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": SchemaUtil.num(-0.5, 0.75)},
		"modifiers": {"t": "dict", "keys_enum": DataValidator.STATUS_MODIFIERS, "values": SchemaUtil.num()},
		"signature": SchemaUtil.ref("action", false, true),
		"dialogue_tags": {"t": "array", "items": "string"},
		"dialogue_note": SchemaUtil.str_field(),
	})

	return f


static func semantic(_d: Dictionary, _ctx: String, _out: Dictionary) -> void:
	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P31

	## @anchor P33
	# P33: ids start with "ancestry."; the passives last (Talents.check_passive_modifiers); dialogue
	# tags are plain lowercase words. The signature's kind and grant are checked across records
	# (Talents.data_errors, GameData anchor P33).
	var p33_id: Variant = _d.get("id")
	if typeof(p33_id) == TYPE_STRING and not str(p33_id).begins_with("ancestry."):
		_out.errors.append("%s: ancestry ids start with 'ancestry.' (got '%s')" % [_ctx, p33_id])
	Talents.check_passive_modifiers(_d.get("modifiers"), _ctx + ".modifiers", _out)
	var p33_tags: Variant = _d.get("dialogue_tags")
	if typeof(p33_tags) == TYPE_ARRAY:
		var p33_word := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
		for p33_tag: Variant in p33_tags:
			if typeof(p33_tag) != TYPE_STRING or p33_word.search(str(p33_tag)) == null:
				_out.errors.append("%s.dialogue_tags: '%s' is not a plain lowercase word" % [_ctx, p33_tag])

	pass


static func required_ids() -> Dictionary:
	return {}
