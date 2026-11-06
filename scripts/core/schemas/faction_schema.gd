extends RefCounted
## Schema module for "faction" records (P20 pre-declares it; plan M6-M9 §2.12, decision 31): a
## people with its texts, its offence thresholds and its manners toward a giant. P22 generalises
## FactionState and ships faction.village (Thornwick, today's texts); P29, P35 and P36 ship the
## world's factions.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "faction.brannock", "type": "faction", "display_name": "Brannock",
##    "flag_prefix": "faction.brannock", "initial": "neutral", "offences_to_hostile": 2, "offence_window_s": 30,
##    "civilians_give_way": true, "give_way_m": 3.0,
##    "reconcile": {"talker": "world.crownmarch.edda", "cost": [{"item": "item.iron_ingot", "count": 2}],
##                  "text": "Pay for the gate you broke (2 iron)"},
##    "warn_text": "Brannock's folk scatter from your feet. Strike again and the town will fight you.",
##    "hostile_text": "Brannock's bells ring: the town takes up arms.",
##    "stood_down_text": "Brannock's guards lower their pikes.",
##    "reconciled_text": "Brannock forgives the gate, if not the fright."}
##
## The faction's state lives in the flags <flag_prefix>.{warned, hostile, stood_down, reconciled,
## allied, tribute} (reconciled wins over hostile, which wins over stood_down). `initial`:
## neutral (members spawn in HOLD) or hostile. `reconcile` adds a dialogue choice at its talker
## that sets <flag_prefix>.reconciled.
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const DIALOGUE := preload("res://scripts/core/schemas/dialogue_schema.gd")

## The state flags under a faction's flag_prefix (plan §2.3).
const STATES := ["warned", "hostile", "stood_down", "reconciled", "allied", "tribute"]


static func fields() -> Dictionary:
	var f := {
		# The flags' prefix (default: the record id, e.g. faction.village.hostile).
		"flag_prefix": U.str_field(),
		"initial": U.str_field(false, DataValidator.FACTION_INITIAL),
		# Direct offences within offence_window_s that turn a warned faction hostile.
		"offences_to_hostile": U.int_field(1, 100),
		"offence_window_s": U.num(0.0),
		# Its civilians step aside and watch a giant at peace with them instead of fleeing.
		"civilians_give_way": U.bool_field(),
		"give_way_m": U.num(0.0),
		"reconcile": {"t": "dict", "fields": {
			"talker": U.str_field(true),
			"cost": DIALOGUE.item_list(),
			"text": U.str_field(true)}},
		"warn_text": U.str_field(),
		"hostile_text": U.str_field(),
		"stood_down_text": U.str_field(),
		"reconciled_text": U.str_field(),
	}
	## @anchor P22

	## @anchor P29

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("faction."):
		out.errors.append("%s: faction ids start with 'faction.' (got '%s')" % [ctx, id])
	var prefix: Variant = d.get("flag_prefix")
	if typeof(prefix) == TYPE_STRING:
		U.check_flag_id(prefix, ctx + ".flag_prefix", out)
	var rec: Variant = d.get("reconcile")
	if typeof(rec) == TYPE_DICTIONARY and typeof(rec.get("talker")) == TYPE_STRING:
		U.check_id_string(rec.talker, ctx + ".reconcile.talker", out)
	## @anchor P22

	## @anchor P29


static func required_ids() -> Dictionary:
	return {}


## The flag of one of a faction's states: <flag_prefix>.<state> (faction.brannock.hostile).
static func state_flag(record: Dictionary, state: String) -> String:
	return "%s.%s" % [str(record.get("flag_prefix", record.get("id", ""))), state]
