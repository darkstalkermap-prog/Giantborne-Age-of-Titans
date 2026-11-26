class_name SettlementRules
extends RefCounted
## C4 (decisions C4-1..C4-4): a settlement's development, pure. A settlement record (data/settlements/, schema
## "settlement") names its tiers; each tier above 0 is earned by its projects, and a project by its needs - loads the
## giant hauls to its site ("haul": a king-stone, a great timber), materials he gives ("give": a titan's slabs, iron),
## deeds done in the world ("deed": a quest condition - a rockfall heaved aside, a pack driven off, a raid beaten
## back) - and then by the giant raising the work at its site himself (raise). The last project of a tier raised, the
## settlement stands at that tier: its tier flags go into the world (what the world's FlagVisibility elements, forges,
## waystones, encounters and dialogue read) and its unlocks are open.
##
## The state of one settlement (ExpansionState.settlements[<its POI>], save schema 3's reserved block):
##   {"level": tier, "flags": {mirrored world flags}, "projects": {project id: {"hauled": {load: n},
##    "given": {item id: n}, "raised": bool}}}
## Every function here reads and writes plain dictionaries; SettlementWork (scripts/world/settlement_work.gd) is the
## live side (the session's state, the world's flags, the inventory, the events, the checkpoint).

const TYPE := "settlement"
const REASONS := ["unknown", "max_tier", "later_tier", "raised", "stage", "needs", "not_needed", "missing_items",
	"tier", "auto"]


# --------------------------------------------------------------------------- records

## Every settlement record, by `order` then id.
static func records() -> Array:
	var out: Array = GameData.records_of_type(TYPE).duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 50))
		var ob := int(b.get("order", 50))
		return oa < ob if oa != ob else str(a.id) < str(b.id))
	return out


static func record(id: String) -> Dictionary:
	var r := GameData.get_record(id)
	return r if str(r.get("type", "")) == TYPE else {}


## The settlement record of POI `poi` ({} when none).
static func for_poi(poi: String) -> Dictionary:
	for r: Dictionary in records():
		if str(r.get("poi", "")) == poi:
			return r
	return {}


## The settlement record whose board, site or flag prefix is `world_id` (a site of one of its projects) ({}).
static func for_site(world_id: String) -> Dictionary:
	for r: Dictionary in records():
		if str(r.get("board", "")) == world_id:
			return r
		for t: Dictionary in tiers(r):
			for p: Dictionary in t.get("projects", []):
				if str(p.get("site", "")) == world_id:
					return r
	return {}


static func tiers(rec: Dictionary) -> Array:
	return rec.get("tiers", []) if typeof(rec.get("tiers")) == TYPE_ARRAY else []


## The highest tier the record has (0 for none).
static func max_tier(rec: Dictionary) -> int:
	return maxi(0, tiers(rec).size() - 1)


static func tier_rec(rec: Dictionary, n: int) -> Dictionary:
	var t := tiers(rec)
	return t[n] if n >= 0 and n < t.size() else {}


static func tier_name(rec: Dictionary, n: int) -> String:
	return str(tier_rec(rec, n).get("name", "Tier %d" % n))


## The project `pid` of the record ({}), and the tier it belongs to (project_tier; -1 when unknown).
static func project(rec: Dictionary, pid: String) -> Dictionary:
	for t: Dictionary in tiers(rec):
		for p: Dictionary in t.get("projects", []):
			if str(p.get("id", "")) == pid:
				return p
	return {}


static func project_tier(rec: Dictionary, pid: String) -> int:
	var all := tiers(rec)
	for i in all.size():
		for p: Dictionary in (all[i] as Dictionary).get("projects", []):
			if str(p.get("id", "")) == pid:
				return i
	return -1


## The project whose site is `site` ({}).
static func project_at(rec: Dictionary, site: String) -> Dictionary:
	for t: Dictionary in tiers(rec):
		for p: Dictionary in t.get("projects", []):
			if str(p.get("site", "")) == site:
				return p
	return {}


static func load_name(rec: Dictionary, load_id: String, count := 1) -> String:
	var l: Variant = (rec.get("loads", {}) as Dictionary).get(load_id)
	if typeof(l) != TYPE_DICTIONARY:
		return load_id
	return str(l.get("name", load_id)) if count == 1 else str(l.get("plural", load_id))


static func load_from(rec: Dictionary, load_id: String) -> String:
	var l: Variant = (rec.get("loads", {}) as Dictionary).get(load_id)
	return str((l as Dictionary).get("from", "")) if typeof(l) == TYPE_DICTIONARY else ""


# --------------------------------------------------------------------------- state

static func blank() -> Dictionary:
	return {"level": 0, "flags": {}, "projects": {}}


## The state of settlement `rec` in the expansion state `exp` (made, and kept there, when missing; every key whole).
static func state_of(exp: Dictionary, rec: Dictionary) -> Dictionary:
	if typeof(exp.get("settlements")) != TYPE_DICTIONARY:
		exp["settlements"] = {}
	var key := str(rec.get("poi", ""))
	var st: Variant = exp.settlements.get(key)
	if typeof(st) != TYPE_DICTIONARY:
		st = blank()
		exp.settlements[key] = st
	normalize(st)
	return st


## Fills the missing keys of a settlement's state in place.
static func normalize(st: Dictionary) -> void:
	if not SchemaUtil.is_number(st.get("level")):
		st["level"] = 0
	if typeof(st.get("flags")) != TYPE_DICTIONARY:
		st["flags"] = {}
	if typeof(st.get("projects")) != TYPE_DICTIONARY:
		st["projects"] = {}


static func tier_of(st: Dictionary) -> int:
	return maxi(0, int(st.get("level", 0))) if SchemaUtil.is_number(st.get("level")) else 0


## A project's own state (made when missing).
static func project_state(st: Dictionary, pid: String) -> Dictionary:
	normalize(st)
	var p: Variant = st.projects.get(pid)
	if typeof(p) != TYPE_DICTIONARY:
		p = {}
		st.projects[pid] = p
	if typeof(p.get("hauled")) != TYPE_DICTIONARY:
		p["hauled"] = {}
	if typeof(p.get("given")) != TYPE_DICTIONARY:
		p["given"] = {}
	if typeof(p.get("raised")) != TYPE_BOOL:
		p["raised"] = false
	return p


## The projects of the tier being earned now (the tier after the settlement's): [] at its last tier.
static func current_projects(rec: Dictionary, st: Dictionary) -> Array:
	var n := tier_of(st) + 1
	return tier_rec(rec, n).get("projects", []) if n <= max_tier(rec) else []


# --------------------------------------------------------------------------- the needs

## One need's state: {"kind", "text", "have", "want", "met", "where", "item", "load"} (`ctx` a quest condition
## context: Quests.condition_context()).
static func need_status(rec: Dictionary, need: Dictionary, pst: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind := str(need.get("kind", ""))
	var want := maxi(1, int(need.get("count", 1)))
	var out := {"kind": kind, "text": str(need.get("text", "")), "have": 0, "want": want, "met": false,
		"where": str(need.get("where", "")), "item": str(need.get("item", "")), "load": str(need.get("load", ""))}
	match kind:
		"haul":
			var ld := str(need.get("load", ""))
			out.have = mini(want, int((pst.get("hauled", {}) as Dictionary).get(ld, 0)))
			if out.text == "":
				out.text = "Haul %s" % (("%d %s" % [want, load_name(rec, ld, want)]) if want > 1 else "a " + load_name(rec, ld))
			if out.where == "":
				out.where = load_from(rec, ld)
		"give":
			var item := str(need.get("item", ""))
			out.have = mini(want, int((pst.get("given", {}) as Dictionary).get(item, 0)))
			if out.text == "":
				var nm := str(GameData.get_record(item).get("display_name", item))
				out.text = "Bring %s" % (("%d %s" % [want, nm]) if want > 1 else nm)
		"deed":
			want = 1
			out.want = 1
			out.have = 1 if QuestConditions.holds(need.get("when"), ctx) else 0
	out.met = int(out.have) >= int(out.want)
	return out


## Every need of project `pid` with the project's state: {"id", "name", "text", "tier", "site", "raise", "needs":
## [need_status...], "met", "total", "ready" (every need met), "raised", "current" (its tier is the one being earned),
## "min_stage", "stage_ok"}.
static func project_status(rec: Dictionary, pid: String, st: Dictionary, ctx: Dictionary) -> Dictionary:
	var p := project(rec, pid)
	if p.is_empty():
		return {}
	var pst := project_state(st, pid)
	var tier := project_tier(rec, pid)
	var needs: Array = []
	var met := 0
	for n: Dictionary in p.get("needs", []):
		var s := need_status(rec, n, pst, ctx)
		needs.append(s)
		if bool(s.met):
			met += 1
	var min_stage := int(p.get("min_stage", 0))
	return {"id": pid, "name": str(p.get("name", pid)), "text": str(p.get("text", "")), "tier": tier,
		"site": str(p.get("site", "")), "raise": str(p.get("raise", "Raise it")), "needs": needs, "met": met,
		"total": needs.size(), "ready": met == needs.size(), "raised": bool(pst.raised) or tier <= tier_of(st),
		"auto": bool(p.get("auto", false)),
		"current": tier == tier_of(st) + 1, "min_stage": min_stage, "stage_ok": int(ctx.get("stage", 1)) >= min_stage}


## How many more of `load` project `pid` still wants (0: none, or not a project being earned).
static func wants_load(rec: Dictionary, st: Dictionary, pid: String, load_id: String) -> int:
	var p := project(rec, pid)
	if p.is_empty() or project_tier(rec, pid) != tier_of(st) + 1 or bool(project_state(st, pid).raised):
		return 0
	var pst := project_state(st, pid)
	for n: Dictionary in p.get("needs", []):
		if str(n.get("kind", "")) == "haul" and str(n.get("load", "")) == load_id:
			return maxi(0, int(n.get("count", 1)) - int((pst.hauled as Dictionary).get(load_id, 0)))
	return 0


## One `load` set down at project `pid`'s site: the count it now holds, or -1 when the project did not want it.
static func deliver(rec: Dictionary, st: Dictionary, pid: String, load_id: String) -> int:
	if wants_load(rec, st, pid, load_id) <= 0:
		return -1
	var pst := project_state(st, pid)
	var n := int((pst.hauled as Dictionary).get(load_id, 0)) + 1
	pst.hauled[load_id] = n
	return n


## Whether the give need of project `pid` for `item` can be met now from `inventory` ({item: count}):
## {"ok", "reason", "message", "item", "count" (what would be given: what is still wanted, at most what is held)}.
static func can_give(rec: Dictionary, st: Dictionary, pid: String, item: String, inventory: Dictionary) -> Dictionary:
	var o := {"ok": false, "reason": "", "message": "", "item": item, "count": 0}
	var p := project(rec, pid)
	if p.is_empty():
		return _fail(o, "unknown", "No such work.")
	if project_tier(rec, pid) != tier_of(st) + 1:
		return _fail(o, "later_tier", "That work waits for the tier before it.")
	var pst := project_state(st, pid)
	if bool(pst.raised):
		return _fail(o, "raised", "That work is done.")
	for n: Dictionary in p.get("needs", []):
		if str(n.get("kind", "")) != "give" or str(n.get("item", "")) != item:
			continue
		var left := int(n.get("count", 1)) - int((pst.given as Dictionary).get(item, 0))
		if left <= 0:
			return _fail(o, "not_needed", "They have all of that they need.")
		var held := int(inventory.get(item, 0))
		if held <= 0:
			var nm := str(GameData.get_record(item).get("display_name", item))
			return _fail(o, "missing_items", "You carry no %s." % nm)
		o.ok = true
		o.count = mini(left, held)
		return o
	return _fail(o, "not_needed", "That work does not need it.")


## Records `count` of `item` given to project `pid` (the caller takes them from the inventory).
static func give(st: Dictionary, pid: String, item: String, count: int) -> void:
	var pst := project_state(st, pid)
	pst.given[item] = int((pst.given as Dictionary).get(item, 0)) + maxi(0, count)


## Whether the giant may raise project `pid` now: {"ok", "reason", "message"} (`ctx` with the giant's stage).
static func can_raise(rec: Dictionary, st: Dictionary, pid: String, ctx: Dictionary) -> Dictionary:
	var o := {"ok": false, "reason": "", "message": ""}
	var s := project_status(rec, pid, st, ctx)
	if s.is_empty():
		return _fail(o, "unknown", "No such work.")
	if bool(s.raised):
		return _fail(o, "raised", "%s is done." % str(s.name))
	if not bool(s.current):
		return _fail(o, "later_tier", "%s waits until %s stands at %s." % [str(s.name), str(rec.get("display_name", "")),
			tier_name(rec, int(s.tier) - 1)])
	if bool(s.auto):
		return _fail(o, "auto", "%s comes of itself once its deed is done." % str(s.name)) if not bool(s.ready) else o.merged({"ok": true}, true)
	if not bool(s.stage_ok):
		return _fail(o, "stage", "This work needs a bigger giant: grow to stage %d." % int(s.min_stage))
	if not bool(s.ready):
		var missing := PackedStringArray()
		for n: Dictionary in s.needs:
			if not bool(n.met):
				missing.append("%s (%d/%d)" % [str(n.text), int(n.have), int(n.want)] if int(n.want) > 1 else str(n.text))
		return _fail(o, "needs", "Not yet: " + "; ".join(missing) + ".")
	o.ok = true
	return o


## Raises project `pid` (can_raise passed): its state, and the tier when it was the tier's last. Returns {"tier_up":
## the new tier or -1, "flags": {world flag: value} to set (the project's raised flag; the tier's flags on a tier up)}.
static func raise(rec: Dictionary, st: Dictionary, pid: String) -> Dictionary:
	var pst := project_state(st, pid)
	pst.raised = true
	var flags := {project_flag(rec, pid): true}
	var tier := project_tier(rec, pid)
	var all_raised := true
	for p: Dictionary in tier_rec(rec, tier).get("projects", []):
		if not bool(project_state(st, str(p.id)).raised):
			all_raised = false
	var up := -1
	if all_raised and tier == tier_of(st) + 1:
		st.level = tier
		up = tier
		flags.merge(tier_flags(rec, tier), true)
	return {"tier_up": up, "flags": flags}


# --------------------------------------------------------------------------- the flags the world reads

static func prefix(rec: Dictionary) -> String:
	return str(rec.get("flag_prefix", "settlement.unknown"))


## The flags a settlement at tier `n` holds: "<prefix>.tier" = n and "<prefix>.tier_<k>" for every k from 1 to n.
static func tier_flags(rec: Dictionary, n: int) -> Dictionary:
	var out := {prefix(rec) + ".tier": n}
	for k in range(1, n + 1):
		out["%s.tier_%d" % [prefix(rec), k]] = true
	return out


## Set once project `pid` is raised (its work shows at once: the giant raised it).
static func project_flag(rec: Dictionary, pid: String) -> String:
	return "%s.%s.raised" % [prefix(rec), pid]


## Set for the n-th `load` set down at project `pid`'s site (the stack there grows: FlagVisibility).
static func haul_flag(rec: Dictionary, pid: String, load_id: String, n: int) -> String:
	return "%s.%s.%s_%d" % [prefix(rec), pid, load_id, n]


## Set once tier `n`'s life has come - its folk, fires and banners - out of the giant's sight (A3-4's rule:
## SettlementWatch, when he is beyond settle_m or on a later load).
static func settled_flag(rec: Dictionary, n: int) -> String:
	return "%s.tier_%d.settled" % [prefix(rec), n]


## Every flag the settlements write (SettlementWork, SettlementWatch): {flag: true} - each tier's and its number, each
## tier's settled flag, each project's raised flag and each hauled load's stack flag (the content checks' writers).
static func written_flags() -> Dictionary:
	var out := {}
	for rec: Dictionary in records():
		out[prefix(rec) + ".tier"] = true
		for k in range(1, max_tier(rec) + 1):
			out["%s.tier_%d" % [prefix(rec), k]] = true
			out[settled_flag(rec, k)] = true
			for p: Dictionary in tier_rec(rec, k).get("projects", []):
				out[project_flag(rec, str(p.id))] = true
				for n: Dictionary in p.get("needs", []):
					if str(n.get("kind", "")) == "haul":
						for c in range(1, int(n.get("count", 1)) + 1):
							out[haul_flag(rec, str(p.id), str(n.load), c)] = true
	return out


## The tier the world's flags say (0 without them): the save's truth for an older state.
static func tier_from_flags(rec: Dictionary, flags: Dictionary) -> int:
	var v: Variant = flags.get(prefix(rec) + ".tier")
	var n := int(v) if SchemaUtil.is_number(v) else 0
	for k in range(max_tier(rec), 0, -1):
		if QuestConditions.truthy(flags.get("%s.tier_%d" % [prefix(rec), k])):
			n = maxi(n, k)
			break
	return clampi(n, 0, max_tier(rec))


## The flags the state says that the world lacks (a save whose state ran ahead of its flags; SettlementWork mends
## them as a level loads): the tier's flags and every raised project's and haul's.
static func flags_owed(rec: Dictionary, st: Dictionary, flags: Dictionary) -> Dictionary:
	var want := tier_flags(rec, tier_of(st)) if tier_of(st) > 0 else {}
	for pid: Variant in (st.get("projects", {}) as Dictionary):
		var pst: Variant = st.projects[pid]
		if typeof(pst) != TYPE_DICTIONARY:
			continue
		if bool(pst.get("raised", false)):
			want[project_flag(rec, str(pid))] = true
		var hauled: Variant = pst.get("hauled")
		if typeof(hauled) == TYPE_DICTIONARY:
			for ld: Variant in hauled:
				for k in range(1, int(hauled[ld]) + 1):
					want[haul_flag(rec, str(pid), str(ld), k)] = true
	var out := {}
	for f: String in want:
		if not QuestConditions.same_value(flags.get(f), want[f]):
			var have: Variant = flags.get(f)
			# a number flag (the tier) is never lowered
			if SchemaUtil.is_number(have) and SchemaUtil.is_number(want[f]) and float(have) >= float(want[f]):
				continue
			out[f] = want[f]
	return out


# --------------------------------------------------------------------------- what a tier gives

## The unlock lines of tier `n` (["<kind>: text"...] as {"kind", "text"}).
static func unlocks(rec: Dictionary, n: int) -> Array:
	return tier_rec(rec, n).get("unlocks", [])


## The trades open at the settlement's tier.
static func trades_open(rec: Dictionary, st: Dictionary) -> Array:
	var out: Array = []
	for t: Dictionary in rec.get("trades", []):
		if int(t.get("requires_tier", 0)) <= tier_of(st):
			out.append(t)
	return out


static func trade(rec: Dictionary, tid: String) -> Dictionary:
	for t: Dictionary in rec.get("trades", []):
		if str(t.get("id", "")) == tid:
			return t
	return {}


## Whether trade `tid` can be made now from `inventory`: {"ok", "reason", "message"}.
static func can_trade(rec: Dictionary, st: Dictionary, tid: String, inventory: Dictionary) -> Dictionary:
	var o := {"ok": false, "reason": "", "message": ""}
	var t := trade(rec, tid)
	if t.is_empty():
		return _fail(o, "unknown", "No such trade.")
	if int(t.get("requires_tier", 0)) > tier_of(st):
		return _fail(o, "tier", "%s trades this from %s." % [str(rec.get("display_name", "")),
			tier_name(rec, int(t.get("requires_tier", 0)))])
	for g: Dictionary in t.get("give", []):
		if int(inventory.get(str(g.item), 0)) < int(g.count):
			var nm := str(GameData.get_record(str(g.item)).get("display_name", g.item))
			return _fail(o, "missing_items", "You need %d %s." % [int(g.count), nm])
	o.ok = true
	return o


## "2 Hide -> 1 Iron Ingot"
static func trade_text(t: Dictionary) -> String:
	if str(t.get("text", "")) != "":
		return str(t.text)
	return "%s for %s" % [_items_text(t.get("give", [])), _items_text(t.get("get", []))]


static func _items_text(list: Array) -> String:
	var parts := PackedStringArray()
	for g: Dictionary in list:
		parts.append("%d %s" % [int(g.count), str(GameData.get_record(str(g.item)).get("display_name", g.item))])
	return ", ".join(parts)


static func _fail(o: Dictionary, reason: String, message: String) -> Dictionary:
	o.ok = false
	o.reason = reason
	o.message = message
	return o


# --------------------------------------------------------------------------- cross-record checks (GameData)

## Every settlement's POI is a settlement (or camp) POI of its level (the Valley's have no POI records), each POI and flag prefix is one settlement's, every
## deed's condition is a condition, and the mends name their event's protect targets.
static func data_errors(records: Dictionary, paths: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var pois := {}
	var prefixes := {}
	var ids: Array = []
	for id: String in records:
		if str((records[id] as Dictionary).get("type", "")) == TYPE:
			ids.append(id)
	ids.sort()
	for id: String in ids:
		var rec: Dictionary = records[id]
		var ctx := "%s (%s)" % [paths.get(id, "?"), id]
		var poi := str(rec.get("poi", ""))
		var p: Dictionary = records.get(poi, {})
		if not p.is_empty() and not (str(p.get("kind", "")) in ["settlement", "camp"]):
			errors.append("%s.poi: '%s' is not a settlement or a camp (kind %s)" % [ctx, poi, str(p.get("kind", ""))])
		if p.is_empty() and str(rec.get("level", "")) == "level.world":
			errors.append("%s.poi: '%s' is not a POI of the world" % [ctx, poi])
		if not p.is_empty() and str(p.get("level", "")) != str(rec.get("level", "")):
			errors.append("%s.level: its POI '%s' is on %s" % [ctx, poi, str(p.get("level", ""))])
		if pois.has(poi):
			errors.append("%s.poi: '%s' is %s's too" % [ctx, poi, pois[poi]])
		pois[poi] = id
		var pre := str(rec.get("flag_prefix", ""))
		if prefixes.has(pre):
			errors.append("%s.flag_prefix: '%s' is %s's too" % [ctx, pre, prefixes[pre]])
		prefixes[pre] = id
		for m: Variant in rec.get("mends", []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var ev: Dictionary = records.get(str(m.get("after_event", "")), {})
			var targets: Array = (ev.get("objective", {}) as Dictionary).get("targets", []) if typeof(ev.get("objective")) == TYPE_DICTIONARY else []
			for k: Variant in (m.get("killed", []) as Array) + (m.get("destroyed", []) as Array):
				if not targets.has(k):
					errors.append("%s.mends: '%s' is not a protect target of %s" % [ctx, str(k), str(m.get("after_event", ""))])
	return errors
