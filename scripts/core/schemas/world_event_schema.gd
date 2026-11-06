extends RefCounted
## Schema module for "world_event" records (P20 pre-declares it; plan M6-M9 §2.13, §5.10,
## decision 27): a world event - a raid on a settlement, an army column, a siege line - with its
## trigger, its centre, the encounters it starts, its objective, its fail rule and its outcomes.
## P37 ships the framework (WorldEvent) and the Crownmarch's two events; P35 and P36 their
## regions'. Only an event's centre chunk being loaded and ready with the player within
## start_radius_m (200) lets it start; its fail rule pauses while that chunk is unloaded.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "event.millford_raid", "type": "world_event", "display_name": "Raid on Millford",
##    "level": "level.world", "region": "region.crownmarch", "centre_m": [-320, 6, 540],
##    "start_radius_m": 200,
##    "trigger": {"min_stage": 4, "max_stage": 10, "requires_flags": [], "forbids_flags": ["event.millford_raid.done"],
##                "conditions": [], "cooldown_s": 600},
##    "encounters": ["encounter.tpl_crownmarch_raiders"],
##    "objective": {"kind": "protect", "targets": ["world.crownmarch.millford_house_1"], "lost_to_fail": 3},
##    "fail": {"timer_s": 0},
##    "outcomes": {"defended": {"set_flags": {"world.millford.defended": true}, "xp": 150},
##                 "burned": {"set_flags": {"world.millford.burned": true}}}}
##
## A moving event (the army column) also names its `path` (a patrol route) and `speed_mps`; it
## advances as a path parameter while its point is unloaded. Outcome names are plain words (they
## become event.<id>.outcome values).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const DIALOGUE := preload("res://scripts/core/schemas/dialogue_schema.gd")

const OBJECTIVE_KINDS := ["protect", "destroy", "defeat", "survive", "escort"]
const WORD_REGEX := "^[a-z][a-z0-9_]*$"


static func fields() -> Dictionary:
	var f := {
		"level": U.ref("level", true),
		"region": U.ref("region", false, true),
		"centre_m": U.vec3(true),
		"start_radius_m": U.pos(),
		"trigger": {"t": "dict", "fields": {
			"min_stage": U.int_field(1, 10),
			"max_stage": U.int_field(1, 10),
			"requires_flags": {"t": "array", "items": "string"},
			"forbids_flags": {"t": "array", "items": "string"},
			"conditions": {"t": "array"},
			"cooldown_s": U.num(0.0)}},
		"encounters": U.ref_array("encounter"),
		"objective": {"t": "dict", "fields": {
			"kind": U.str_field(true, OBJECTIVE_KINDS),
			"targets": {"t": "array", "items": "string"},
			"lost_to_fail": U.int_field(0, 100)}},
		"fail": {"t": "dict", "fields": {
			"timer_s": U.num(0.0),
			"conditions": {"t": "array"}}},
		"path": U.str_field(),
		"speed_mps": U.num(0.0),
		"outcomes": {"t": "dict", "values": {"t": "dict", "fields": {
			"set_flags": {"t": "dict"},
			"xp": U.int_field(0, 100000),
			"items": DIALOGUE.item_list()}}},
	}
	## @anchor P37

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("event."):
		out.errors.append("%s: world event ids start with 'event.' (got '%s')" % [ctx, id])
	var trig: Variant = d.get("trigger")
	if typeof(trig) == TYPE_DICTIONARY:
		if U.is_number(trig.get("min_stage")) and U.is_number(trig.get("max_stage")) \
				and int(trig.min_stage) > int(trig.max_stage):
			out.errors.append("%s.trigger: min_stage must be <= max_stage" % ctx)
		for key: String in ["requires_flags", "forbids_flags"]:
			if typeof(trig.get(key)) == TYPE_ARRAY:
				var j := 0
				for fl: Variant in trig[key]:
					U.check_flag_id(fl, "%s.trigger.%s[%d]" % [ctx, key, j], out)
					j += 1
		if typeof(trig.get("conditions")) == TYPE_ARRAY:
			U.check_conditions(trig.conditions, ctx + ".trigger.conditions", out)
	var fail: Variant = d.get("fail")
	if typeof(fail) == TYPE_DICTIONARY and typeof(fail.get("conditions")) == TYPE_ARRAY:
		U.check_conditions(fail.conditions, ctx + ".fail.conditions", out)
	var objective: Variant = d.get("objective")
	if typeof(objective) == TYPE_DICTIONARY and typeof(objective.get("targets")) == TYPE_ARRAY:
		var j := 0
		for t: Variant in objective.targets:
			U.check_id_string(t, "%s.objective.targets[%d]" % [ctx, j], out)
			j += 1
	var path: Variant = d.get("path", "")
	if typeof(path) == TYPE_STRING and path != "":
		U.check_id_string(path, ctx + ".path", out)
	var outcomes: Variant = d.get("outcomes")
	if typeof(outcomes) == TYPE_DICTIONARY:
		var word := RegEx.create_from_string(WORD_REGEX)
		for name: Variant in outcomes:
			if word.search(str(name)) == null:
				out.errors.append("%s.outcomes: outcome '%s' must be a plain lowercase word" % [ctx, name])
			var o: Variant = outcomes[name]
			if typeof(o) == TYPE_DICTIONARY:
				DIALOGUE.check_flag_map(o.get("set_flags"), "%s.outcomes.%s.set_flags" % [ctx, name], out)
	## @anchor P37


static func required_ids() -> Dictionary:
	return {}
