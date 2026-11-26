extends RefCounted
## Schema module for "settlement" records (C4, decisions C4-1..C4-3): a settlement's development - its tiers, the
## projects each tier is earned by (giant-shaped work: loads hauled to a site, materials given, deeds done in the world,
## then the work raised at its site), what each tier unlocks, its trades and what its folk mend behind the giant's back
## (data/settlements/settlement_*.json). SettlementRules (scripts/progression/settlement_rules.gd) reads them; the
## state lives in the save's ExpansionState.settlements under the record's POI.
##
##   {"schema_version": 1, "id": "settlement.last_hearth", "type": "settlement", "display_name": "Last Hearth",
##    "poi": "poi.last_hearth", "level": "level.world", "flag_prefix": "settlement.last_hearth", "settle_m": 150,
##    "steward": "Maera", "board": "world.hoarfell.hearth_board",
##    "loads": {"timber": {"name": "great timber", "plural": "great timbers", "from": "the Windfall ..."}},
##    "tiers": [{"tier": 0, "name": "The Camp", "text": "..."},
##              {"tier": 1, "name": "The Roofed Hall", "text": "...", "unlocks": [{"kind": "rest", "text": "..."}],
##               "projects": [{"id": "hall_roof", "name": "Roof the hall", "text": "...", "site": "<world id>",
##                             "min_stage": 6, "raise": "Raise the roof-tree",
##                             "needs": [{"kind": "haul", "load": "timber", "count": 2},
##                                       {"kind": "give", "item": "item.hide", "count": 4},
##                                       {"kind": "deed", "text": "Clear the rockfall", "when": {condition},
##                                        "where": "world.marker.x"}]}]}],
##    "trades": [{"id": "hides_for_iron", "requires_tier": 1, "give": [{"item", "count"}], "get": [...], "text": ""}],
##    "mends": [{"after_event": "event.hearth_raid", "killed": ["<entity id>"], "destroyed": ["<world id>"]}]}
##
## A tier is numbered from 0 (the settlement as the giant first finds it: no projects) up, each the next; a project's
## id is unique in the record; a haul names one of the record's loads; a give an item; a deed its condition (a quest
## condition) and the words the panel shows.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const NEED_KINDS := ["haul", "give", "deed"]
const UNLOCK_KINDS := ["rest", "forge", "waystone", "trade", "garrison", "people", "quest", "event", "lead", "look"]
const MAX_TIERS := 6


static func item_list() -> Dictionary:
	return {"t": "array", "items": "dict", "item_fields": {
		"item": U.ref("item", true),
		"count": U.int_field(1, 99, true)}}


static func fields() -> Dictionary:
	return {
		"display_name": U.str_field(true),
		"description": U.str_field(),
		"poi": U.str_field(true),   # the state's key (ExpansionState.settlements): a world POI, or the Valley's own name
		"level": U.ref("level", true),
		"flag_prefix": U.str_field(true),
		"settle_m": U.pos(),
		"centre_m": U.vec3(),   # where the settlement stands ([x, y, z]; default its POI's)
		"steward": U.str_field(),
		"board": U.str_field(),
		"order": U.int_field(0, 100),
		"loads": {"t": "dict"},
		"tiers": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"tier": U.int_field(0, MAX_TIERS, true),
			"name": U.str_field(true),
			"text": U.str_field(true),
			"settled_text": U.str_field(),
			"unlocks": {"t": "array", "items": "dict", "item_fields": {
				"kind": U.str_field(true, UNLOCK_KINDS),
				"text": U.str_field(true)}},
			"projects": {"t": "array", "items": "dict", "item_fields": {
				"id": U.str_field(true),
				"name": U.str_field(true),
				"text": U.str_field(true),
				"site": U.str_field(),
				# an `auto` project raises itself once its needs are met and the giant is away (SettlementWatch): an older
				# settlement's aftermath (Millford's quarry reopened after Stoneback) as its first tier
				"auto": U.bool_field(),
				"raise": U.str_field(),
				"raised_text": U.str_field(),
				"min_stage": U.int_field(0, 10),
				"needs": {"t": "array", "req": true, "items": "dict", "item_fields": {
					"kind": U.str_field(true, NEED_KINDS),
					"load": U.str_field(),
					"item": U.ref("item", false, true),
					"count": U.int_field(1, 99),
					"text": U.str_field(),
					"where": U.str_field(),
					"when": {"t": "dict"}}}}}}},
		"trades": {"t": "array", "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"requires_tier": U.int_field(0, MAX_TIERS),
			"give": item_list(),
			"get": item_list(),
			"text": U.str_field()}},
		"mends": {"t": "array", "items": "dict", "item_fields": {
			"after_event": U.ref("world_event", true),
			"killed": {"t": "array", "items": "string"},
			"destroyed": {"t": "array", "items": "string"}}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var prefix := str(d.get("flag_prefix", ""))
	if prefix != "" and not prefix.begins_with("settlement."):
		out.errors.append("%s.flag_prefix: '%s' must begin with 'settlement.'" % [ctx, prefix])
	var loads: Dictionary = d.loads if typeof(d.get("loads")) == TYPE_DICTIONARY else {}
	for k: Variant in loads:
		var l: Variant = loads[k]
		if typeof(l) != TYPE_DICTIONARY or typeof((l as Dictionary).get("name")) != TYPE_STRING \
				or typeof((l as Dictionary).get("plural")) != TYPE_STRING:
			out.errors.append("%s.loads.%s: {name, plural, from} (strings)" % [ctx, str(k)])
	var tiers: Array = d.tiers if typeof(d.get("tiers")) == TYPE_ARRAY else []
	if tiers.size() < 2:
		out.errors.append("%s.tiers: a settlement has its tier 0 and at least one tier to earn" % ctx)
	var ids := {}
	for i in tiers.size():
		var t: Variant = tiers[i]
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if int(t.get("tier", -1)) != i:
			out.errors.append("%s.tiers[%d].tier: tiers are numbered 0, 1, 2 ... in order (got %s)" % [ctx, i, str(t.get("tier"))])
		var projects: Array = t.projects if typeof(t.get("projects")) == TYPE_ARRAY else []
		if i == 0 and not projects.is_empty():
			out.errors.append("%s.tiers[0]: tier 0 is the settlement as found (no projects)" % ctx)
		if i > 0 and projects.is_empty():
			out.errors.append("%s.tiers[%d]: a tier is earned by at least one project" % [ctx, i])
		for j in projects.size():
			var p: Variant = projects[j]
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var pctx := "%s.tiers[%d].projects[%d]" % [ctx, i, j]
			var pid := str(p.get("id", ""))
			if ids.has(pid):
				out.errors.append("%s.id: a second project '%s'" % [pctx, pid])
			ids[pid] = true
			if not bool(p.get("auto", false)) and str(p.get("site", "")) == "":
				out.errors.append("%s.site: a project the giant raises names its site" % pctx)
			var needs: Array = p.needs if typeof(p.get("needs")) == TYPE_ARRAY else []
			if needs.is_empty():
				out.errors.append("%s.needs: a project needs something done" % pctx)
			for k in needs.size():
				var n: Variant = needs[k]
				if typeof(n) != TYPE_DICTIONARY:
					continue
				var nctx := "%s.needs[%d]" % [pctx, k]
				match str(n.get("kind", "")):
					"haul":
						if not loads.has(str(n.get("load", ""))):
							out.errors.append("%s.load: '%s' is not one of the record's loads" % [nctx, str(n.get("load", ""))])
						if int(n.get("count", 0)) < 1:
							out.errors.append("%s.count: a haul carries at least one load" % nctx)
					"give":
						if str(n.get("item", "")) == "" or int(n.get("count", 0)) < 1:
							out.errors.append("%s: a give names its item and count" % nctx)
					"deed":
						if typeof(n.get("when")) != TYPE_DICTIONARY or str(n.get("text", "")) == "":
							out.errors.append("%s: a deed has its condition (when) and its words (text)" % nctx)
	var trade_ids := {}
	var trades: Array = d.trades if typeof(d.get("trades")) == TYPE_ARRAY else []
	for i in trades.size():
		var tr: Variant = trades[i]
		if typeof(tr) != TYPE_DICTIONARY:
			continue
		var tid := str(tr.get("id", ""))
		if trade_ids.has(tid):
			out.errors.append("%s.trades[%d].id: a second trade '%s'" % [ctx, i, tid])
		trade_ids[tid] = true
		if (tr.get("give", []) as Array).is_empty() or (tr.get("get", []) as Array).is_empty():
			out.errors.append("%s.trades[%d]: a trade gives something and gets something" % [ctx, i])
		if int(tr.get("requires_tier", 0)) >= tiers.size():
			out.errors.append("%s.trades[%d].requires_tier: past the last tier" % [ctx, i])


static func required_ids() -> Dictionary:
	return {}
