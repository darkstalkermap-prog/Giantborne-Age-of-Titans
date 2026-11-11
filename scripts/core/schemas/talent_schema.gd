extends RefCounted
## Schema module for "talent" records (P20 pre-declares it; plan M6-M9 §2.11, §5.12, decision 22):
## one talent of the three trees (Destroyer, Guardian, Primordial; nine each, tiers 1-5, the
## capstone costs 2). Talents are passives on the Combatant (never statuses) or grant an ability.
## P33 ships the records and applies them; the character keeps the learned ids in its "talents".
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "talent.destroyer_shoulder_charge", "type": "talent", "display_name": "Shoulder Charge",
##    "tree": "destroyer", "tier": 2, "cost": 1, "requires": ["talent.destroyer_heavy_hands"], "requires_level": 8,
##    "effects": {"modifiers": {}, "grants": ["ability.shoulder_charge"], "replaces": {}}}
##
## effects.modifiers uses DataValidator.STATUS_MODIFIERS keys only (the passives the Combatant
## folds into its accessors); grants are abilities learned with the talent; replaces maps an
## ability id to the one that takes its slot.
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")

const TREES := ["destroyer", "guardian", "primordial"]


static func fields() -> Dictionary:
	var f := {
		"tree": U.str_field(true, TREES),
		"tier": U.int_field(1, 5, true),
		"cost": U.int_field(1, 5),
		"requires": U.ref_array("talent"),
		"requires_level": U.int_field(1, 20),
		"effects": {"t": "dict", "req": true, "fields": {
			"modifiers": {"t": "dict", "keys_enum": DataValidator.STATUS_MODIFIERS, "values": U.num()},
			"grants": U.ref_array("action"),
			"replaces": {"t": "dict", "values": U.str_field()}}},
	}
	## @anchor P33
	# P33 (plan M6-M9 §5.12): where the talent stands on the Talents tab - column 1 or 2 of tiers 1-4
	# (each talent needs the one above it in its column, `requires`), 0 for the tier-5 capstone.
	f.merge({"column": U.int_field(0, 2)})

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("talent."):
		out.errors.append("%s: talent ids start with 'talent.' (got '%s')" % [ctx, id])
	var requires: Variant = d.get("requires")
	if typeof(requires) == TYPE_ARRAY and typeof(id) == TYPE_STRING and (requires as Array).has(id):
		out.errors.append("%s.requires: a talent cannot require itself" % ctx)
	var effects: Variant = d.get("effects")
	if typeof(effects) == TYPE_DICTIONARY and typeof(effects.get("replaces")) == TYPE_DICTIONARY:
		for k: Variant in effects.replaces:
			# Both sides are action ids (checked like any reference).
			out.refs.append({"ctx": "%s.effects.replaces" % ctx, "id": str(k), "type": "action"})
			if typeof(effects.replaces[k]) == TYPE_STRING:
				out.refs.append({"ctx": "%s.effects.replaces.%s" % [ctx, k], "id": str(effects.replaces[k]),
					"type": "action"})
	## @anchor P33
	# P33: passives last (no periodic heal, no slow: those are statuses'), a multiplier is above 0, and the
	# capstone (tier 5) stands in column 0, the others in column 1 or 2. Cross-record rules (tiers and
	# levels, requirements within the tree, grants) are Talents.data_errors' (GameData, anchor P33).
	if typeof(effects) == TYPE_DICTIONARY:
		Talents.check_passive_modifiers(effects.get("modifiers"), ctx + ".effects.modifiers", out)
	var p33_tier: Variant = d.get("tier")
	var p33_column: Variant = d.get("column")
	if U.is_number(p33_tier) and U.is_number(p33_column):
		if int(p33_tier) == 5 and int(p33_column) != 0:
			out.errors.append("%s.column: a tier-5 capstone stands in column 0 (got %d)" % [ctx, int(p33_column)])
		elif int(p33_tier) < 5 and int(p33_column) == 0:
			out.errors.append("%s.column: a tier-%d talent stands in column 1 or 2" % [ctx, int(p33_tier)])


static func required_ids() -> Dictionary:
	return {}
