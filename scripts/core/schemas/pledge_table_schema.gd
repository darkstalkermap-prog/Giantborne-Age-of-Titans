extends RefCounted
## Schema module for "pledge_table" records (C1, decision C1-12): act two's pledges - what each act-one settlement
## answers when the rim breaks, by how act one ended (its oath, its standing, Skarn's fate, the champion's) -
## data/world/act_two_pledges.json, the only record of the type. ActTwo (scripts/quests/act_two.gd) reads it as act
## two begins: each pledge's `sends_when` holding sets its flag to "sends" (and <flag>.sends), else "refuses" (and
## <flag>.refuses), once; the rim council's dialogue speaks each line; milestone D's events consume the flags.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "pledge_table.act_two", "type": "pledge_table",
##    "pledges": [{"id": "brannock", "settlement": "poi.brannock", "speaker": "Marchwarden Edda",
##                 "flag": "pledge.brannock", "sends_when": {quest condition}, "sends_line": "...",
##                 "refuses_line": "..."}, ...]}

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"consumed_by": U.str_field(),
		"pledges": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"settlement": U.ref("poi", true),
			"speaker": U.str_field(true),
			"flag": U.str_field(true),
			"sends_when": {"t": "dict", "req": true},
			"sends_line": U.str_field(true),
			"refuses_line": U.str_field(true)}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var seen := {}
	var flags := {}
	var list: Array = d.pledges if typeof(d.get("pledges")) == TYPE_ARRAY else []
	for i in list.size():
		var p: Variant = list[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var id := str(p.get("id", ""))
		if seen.has(id):
			out.errors.append("%s.pledges[%d]: a second pledge '%s'" % [ctx, i, id])
		seen[id] = true
		var flag := str(p.get("flag", ""))
		if not flag.begins_with("pledge."):
			out.errors.append("%s.pledges[%d].flag: '%s' must begin with 'pledge.'" % [ctx, i, flag])
		if flags.has(flag):
			out.errors.append("%s.pledges[%d].flag: '%s' is another pledge's" % [ctx, i, flag])
		flags[flag] = true


static func required_ids() -> Dictionary:
	return {"pledge_table.act_two": "pledge_table"}
