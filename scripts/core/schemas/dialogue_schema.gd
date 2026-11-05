extends RefCounted
## Schema module for "dialogue" records (P13; plan §2.8.3): one NPC conversation of nodes and
## choices, run by DialogueSession (scripts/quests/dialogue_session.gd).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "dialogue.elder", "type": "dialogue", "speaker": "Elder Maren",
##    "entries": [{"node": "hostile", "conditions": [{"type": "flag", "flag": "faction.village.hostile"}]},
##                {"node": "greet", "conditions": []}],
##    "nodes": [{"id": "greet", "text": "A giant... we want no trouble.",
##      "choices": [
##       {"text": "[Loom over them] Open the bridge. Now.", "next": "cowed",
##        "conditions": [{"type": "stage_at_least", "stage": 2}],
##        "effects": {"set_flags": {"quest.village.outcome": "intimidate"}, "outcome": "intimidate", "xp": 40,
##                    "learn_abilities": ["ability.thunder_roar"], "once_flag": "reward.village.intimidate"}},
##       {"text": "Not now.", "next": ""}]}, ...]}
##
## The first entry whose conditions all hold is the start node. A choice is shown only while its
## conditions hold (and its take_items are held); "next" is a node id, or "" to end the
## conversation. Effects: set_flags (first write wins), outcome (dialogue_outcome and the flag
## dialogue.<short id>.outcome.<outcome>), give_items / take_items ([{item, count}]), xp,
## learn_abilities, once_flag, close (end after this choice). xp, give_items and learn_abilities
## are rewards: they need a once_flag and are granted only when try_set_flag(once_flag) is true,
## so repeating a conversation never grants anything twice (spec §14).
##
## Semantic rules: the id starts with "dialogue."; node ids are unique plain words; every entry
## and every non-empty "next" names an existing node; conditions are valid (§2.8.3 shapes); flag
## ids pass the id regex; outcomes are plain words; rewards have a once_flag. Warnings: no entry
## without conditions (there may be no start node) and nodes no entry or choice leads to.

const U := preload("res://scripts/core/schemas/schema_util.gd")

## Node ids and outcomes are plain lowercase words (they become parts of flag ids).
const WORD_REGEX := "^[a-z][a-z0-9_]*$"
## Effects that are rewards: granted only through the once_flag.
const ONCE_GATED := ["xp", "give_items", "learn_abilities"]


## [{item, count}] lists (give_items, take_items; quest stage items).
static func item_list() -> Dictionary:
	return {"t": "array", "items": "dict", "item_fields": {
		"item": U.ref("item", true),
		"count": U.int_field(1, 999, true)}}


static func fields() -> Dictionary:
	return {
		# The name shown above every line of this conversation.
		"speaker": U.str_field(true),
		# Where a conversation starts: the first entry whose conditions all hold.
		"entries": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"node": U.str_field(true),
			"conditions": {"t": "array"}}},
		"nodes": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"text": U.str_field(true),
			"choices": {"t": "array", "items": "dict", "item_fields": {
				"text": U.str_field(true),
				# The node this choice leads to; "" (or absent) ends the conversation.
				"next": U.str_field(),
				# The choice is listed only while these hold.
				"conditions": {"t": "array"},
				"effects": {"t": "dict", "fields": {
					"set_flags": {"t": "dict"},
					"outcome": U.str_field(),
					"give_items": item_list(),
					"take_items": item_list(),
					"xp": U.int_field(0, 100000),
					"learn_abilities": U.ref_array("action"),
					"once_flag": U.str_field(),
					"close": U.bool_field()}}}}}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("dialogue."):
		out.errors.append("%s: dialogue ids start with 'dialogue.' (got '%s')" % [ctx, id])
	var word := RegEx.create_from_string(WORD_REGEX)
	var node_ids := {}
	var nodes: Variant = d.get("nodes")
	if typeof(nodes) == TYPE_ARRAY:
		if (nodes as Array).is_empty():
			out.errors.append("%s: nodes must list at least one node" % ctx)
		var i := 0
		for n: Variant in nodes:
			var nctx := "%s.nodes[%d]" % [ctx, i]
			i += 1
			if typeof(n) != TYPE_DICTIONARY or typeof(n.get("id")) != TYPE_STRING:
				continue
			var nid: String = n.id
			if word.search(nid) == null:
				out.errors.append("%s.id: node id '%s' must be a plain lowercase word like 'greet'" % [nctx, nid])
			if node_ids.has(nid):
				out.errors.append("%s.id: duplicate node id '%s'" % [nctx, nid])
			node_ids[nid] = true
	var reached := {}
	var entries: Variant = d.get("entries")
	if typeof(entries) == TYPE_ARRAY:
		if (entries as Array).is_empty():
			out.errors.append("%s: entries must list at least one entry" % ctx)
		var unconditional := false
		var i := 0
		for e: Variant in entries:
			var ectx := "%s.entries[%d]" % [ctx, i]
			i += 1
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var node: Variant = e.get("node")
			if typeof(node) == TYPE_STRING:
				reached[node] = true
				if not node_ids.has(node):
					out.errors.append("%s.node: unknown node '%s'" % [ectx, node])
			var conds: Variant = e.get("conditions", [])
			if typeof(conds) == TYPE_ARRAY:
				U.check_conditions(conds, ectx + ".conditions", out)
				if (conds as Array).is_empty():
					unconditional = true
		if not unconditional and not (entries as Array).is_empty():
			out.warnings.append("%s: no entry without conditions: the conversation may have no start node" % ctx)
	if typeof(nodes) != TYPE_ARRAY:
		return
	var i := 0
	for n: Variant in nodes:
		var nctx := "%s.nodes[%d]" % [ctx, i]
		i += 1
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var choices: Variant = n.get("choices", [])
		if typeof(choices) != TYPE_ARRAY:
			continue
		var j := 0
		for c: Variant in choices:
			var cctx := "%s.choices[%d]" % [nctx, j]
			j += 1
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var next: Variant = c.get("next", "")
			if typeof(next) == TYPE_STRING and next != "":
				reached[next] = true
				if not node_ids.has(next):
					out.errors.append("%s.next: unknown node '%s'" % [cctx, next])
			var conds: Variant = c.get("conditions", [])
			if typeof(conds) == TYPE_ARRAY:
				U.check_conditions(conds, cctx + ".conditions", out)
			var effects: Variant = c.get("effects")
			if typeof(effects) == TYPE_DICTIONARY:
				check_effects(effects, cctx + ".effects", out)
	for nid: String in node_ids:
		if not reached.has(nid):
			out.warnings.append("%s: node '%s' is never reached (no entry or choice leads to it)" % [ctx, nid])


## The checks of one choice's effects (types are checked by fields()).
static func check_effects(e: Dictionary, ctx: String, out: Dictionary) -> void:
	check_flag_map(e.get("set_flags"), ctx + ".set_flags", out)
	var outcome: Variant = e.get("outcome")
	if typeof(outcome) == TYPE_STRING and outcome != "" \
			and RegEx.create_from_string(WORD_REGEX).search(outcome) == null:
		out.errors.append("%s.outcome: '%s' must be a plain lowercase word like 'intimidate'" % [ctx, outcome])
	var once: Variant = e.get("once_flag", "")
	if typeof(once) == TYPE_STRING and once != "":
		U.check_flag_id(once, ctx + ".once_flag", out)
	var has_once: bool = typeof(once) == TYPE_STRING and once != ""
	for key: String in ONCE_GATED:
		if e.has(key) and not has_once and _is_reward(e[key]):
			out.errors.append("%s.%s: a reward needs a once_flag (rewards are granted once, spec §14)" % [ctx, key])


## A {flag id: value} map (set_flags, on_complete_flags): flag ids pass the id regex and values
## are JSON scalars (bool, number or string).
static func check_flag_map(v: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		return
	for k: Variant in v:
		U.check_flag_id(k, "%s.%s" % [ctx, k], out)
		var t := typeof(v[k])
		if t != TYPE_BOOL and t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_STRING:
			out.errors.append("%s.%s: a flag value must be true/false, a number or a string" % [ctx, k])


static func _is_reward(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v) > 0.0
		TYPE_ARRAY:
			return not (v as Array).is_empty()
	return false


static func required_ids() -> Dictionary:
	return {}
