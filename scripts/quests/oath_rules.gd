class_name OathRules
extends RefCounted
## The data rules of the oaths and the factions' reconciliations (P29; plan M6-M9 decision 26, §2.12,
## §5.7, §5.9), run by GameData's post-pass (anchor P29) over every loaded record. Pure: records in,
## error lines out (no scene, no autoload but DataValidator's constants).
##
## first_oath_errors(): every oath quest present (an id "quest.oath_<x>") has at least one
## resolution that can be won as the first oath by a stage-4 giant. A resolution is a value some
## record writes to oath.<x>.outcome together with (or before) oath.<x>.done - a dialogue choice's
## set_flags, a quest stage's set_flags, a prop's on_destroyed_flags - and it is open to a first oath
## at stage 4 when the conditions guarding that writer (the choice's conditions; the stage's
## complete_when) can hold then: no stage above 4, no other oath's flag or quest done, and every flag
## they read can itself be written under such conditions (a flag no record writes - the engine's: an
## encounter cleared, a beacon lit, a faction's standing - is taken to be reachable). The quest's own
## start conditions and every stage's complete_when must be reachable the same way, so a quest whose
## first stage already needs stage 5 fails too. (What it does not judge: whether an item a condition
## asks for can be had - P36's parley tokens are checked by its own tests.)
##
## reconcile_errors(): a faction record's `reconcile` is offered somewhere - some dialogue has a
## choice whose outcome is "reconcile_<short>" (FactionState reconciles on it) and that takes the
## record's cost.
##
## lead_errors() (M7 polish; the M7 gate review): a quest stage that counts the oaths' done flags
## (oath.<x>.done in its complete_when - the main thread's oaths stage) and points at several
## markers, the oath leads, ends each lead with its own oath: every marker has a markers_done_when
## that is the flag test of one of those oaths, one lead per oath. Quests drops a lead once its
## condition holds, so no lead outlives its oath in any order of the oaths (decision 26).

const OATH_QUEST_PREFIX := "quest.oath_"
const FIRST_OATH_STAGE := 4
const RECONCILE_PREFIX := "reconcile_"


## The oath key of an oath quest id ("quest.oath_march" -> "march"; "" for any other id).
static func oath_key(quest_id: String) -> String:
	return quest_id.trim_prefix(OATH_QUEST_PREFIX) if quest_id.begins_with(OATH_QUEST_PREFIX) else ""


static func outcome_flag(key: String) -> String:
	return "oath.%s.outcome" % key


static func done_flag(key: String) -> String:
	return "oath.%s.done" % key


## Every writer of each flag in the records: flag id -> [{"value", "conditions": Array (all must
## hold), "source": String}]. Dialogue choices (their conditions), quest stages (their complete_when
## and the quest's start conditions), props (destroyed: no condition kept - a prop's own stage rule
## is the size gates').
static func flag_writers(records: Dictionary) -> Dictionary:
	var out := {}
	var ids: Array = records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		match str(rec.get("type", "")):
			"dialogue":
				var ni := 0
				for n: Variant in rec.get("nodes", []):
					if typeof(n) != TYPE_DICTIONARY:
						continue
					var ci := 0
					for c: Variant in n.get("choices", []):
						if typeof(c) == TYPE_DICTIONARY and typeof(c.get("effects")) == TYPE_DICTIONARY:
							var conds: Array = c.get("conditions", []) if typeof(c.get("conditions")) == TYPE_ARRAY else []
							var src := "%s:%s:%d" % [id, n.get("id", ni), ci]
							_add_writes(out, c.effects.get("set_flags"), conds, src)
							var outcome := str(c.effects.get("outcome", ""))
							if outcome != "":
								_add_write(out, "dialogue.%s.outcome.%s" % [str(id).trim_prefix("dialogue."), outcome], true, conds, src)
						ci += 1
					ni += 1
			"quest":
				var starts: Array = rec.get("start_conditions", []) if typeof(rec.get("start_conditions")) == TYPE_ARRAY else []
				var before: Array = starts.duplicate()
				for s: Variant in rec.get("stages", []):
					if typeof(s) != TYPE_DICTIONARY:
						continue
					var conds := before.duplicate()
					if s.has("complete_when"):
						conds.append(s.complete_when)
					_add_writes(out, s.get("set_flags"), conds, "%s:%s" % [id, s.get("id", "")])
					before = conds
			"prop":
				_add_writes(out, rec.get("on_destroyed_flags"), [], str(id))
	return out


static func _add_writes(out: Dictionary, flags: Variant, conds: Array, src: String) -> void:
	if typeof(flags) != TYPE_DICTIONARY:
		return
	for f: Variant in flags:
		_add_write(out, str(f), flags[f], conds, src)


static func _add_write(out: Dictionary, flag: String, value: Variant, conds: Array, src: String) -> void:
	if not out.has(flag):
		out[flag] = []
	(out[flag] as Array).append({"value": value, "conditions": conds, "source": src})


## True when the condition `c` can hold for a first oath `key` at stage 4 (see the class notes).
## `writers` from flag_writers(); `visiting` guards against loops.
static func reachable(c: Variant, key: String, writers: Dictionary, visiting := {}) -> bool:
	if typeof(c) != TYPE_DICTIONARY:
		return true
	var d: Dictionary = c
	match str(d.get("type", "")):
		"stage_at_least":
			return int(d.get("stage", 1)) <= FIRST_OATH_STAGE
		"flag":
			return flag_reachable(str(d.get("flag", "")), d, key, writers, visiting)
		"dialogue_outcome":
			var f := "dialogue.%s.outcome.%s" % [str(d.get("dialogue", "")).trim_prefix("dialogue."), str(d.get("outcome", ""))]
			return flag_reachable(f, {}, key, writers, visiting)
		"quest_done":
			var other := oath_key(str(d.get("quest", "")))
			return other == "" or other == key
		"all":
			for sub: Variant in d.get("of", []):
				if not reachable(sub, key, writers, visiting):
					return false
			return true
		"any":
			for sub: Variant in d.get("of", []):
				if reachable(sub, key, writers, visiting):
					return true
			return false
		"count":
			var n := 0
			for sub: Variant in d.get("of", []):
				if reachable(sub, key, writers, visiting):
					n += 1
			return n >= int(d.get("n", 1))
	return true


## True when the flag test `cond` ({flag, equals?}) can hold for a first oath `key`: never another
## oath's flag; a flag nothing writes is the engine's (reachable); else some writer of a matching
## value whose conditions are reachable.
static func flag_reachable(flag: String, cond: Dictionary, key: String, writers: Dictionary, visiting: Dictionary) -> bool:
	if flag.begins_with("oath.") and flag.get_slice(".", 1) != key:
		return false
	if not writers.has(flag):
		return true
	if visiting.has(flag):
		return false
	visiting[flag] = true
	var ok := false
	for w: Dictionary in writers[flag]:
		if cond.has("equals") and not QuestConditions.same_value(w.value, cond.equals):
			continue
		var all := true
		for sub: Variant in w.conditions:
			if not reachable(sub, key, writers, visiting):
				all = false
				break
		if all:
			ok = true
			break
	visiting.erase(flag)
	return ok


## The resolutions (outcome values) of the oath quest `quest_id` that a stage-4 giant can win as its
## first oath, sorted.
static func first_oath_resolutions(quest_id: String, records: Dictionary, writers: Dictionary = {}) -> PackedStringArray:
	var key := oath_key(quest_id)
	if writers.is_empty():
		writers = flag_writers(records)
	var out := PackedStringArray()
	for w: Dictionary in writers.get(outcome_flag(key), []):
		var value := str(w.value)
		if out.has(value):
			continue
		var ok := true
		for sub: Variant in w.conditions:
			if not reachable(sub, key, writers):
				ok = false
				break
		if ok:
			out.append(value)
	out.sort()
	return out


## The oath quests' errors (see the class notes).
static func first_oath_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var writers := {}
	var ids: Array = records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		var key := oath_key(str(id))
		if key == "" or typeof(rec) != TYPE_DICTIONARY or str(rec.get("type", "")) != "quest":
			continue
		if writers.is_empty():
			writers = flag_writers(records)
		var ctx := "%s (%s)" % [record_paths.get(id, id), id]
		for c: Variant in rec.get("start_conditions", []):
			if not reachable(c, key, writers):
				errors.append("%s: its start conditions need more than a first oath at stage %d (%s)" % [
					ctx, FIRST_OATH_STAGE, JSON.stringify(c)])
		for s: Variant in rec.get("stages", []):
			if typeof(s) == TYPE_DICTIONARY and not reachable(s.get("complete_when"), key, writers):
				errors.append("%s: stage '%s' cannot be completed as a first oath at stage %d" % [
					ctx, s.get("id", ""), FIRST_OATH_STAGE])
		if first_oath_resolutions(str(id), records, writers).is_empty():
			errors.append("%s: no resolution of oath.%s.outcome can be won as the first oath at stage %d (decision 26)" % [
				ctx, key, FIRST_OATH_STAGE])
	return errors


## The factions' reconciliations: each record's `reconcile` is offered by some dialogue choice whose
## outcome is reconcile_<short> and whose take_items are the record's cost.
static func reconcile_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var offers := {}   # outcome -> [take_items lists]
	for id: Variant in records:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY or str(rec.get("type", "")) != "dialogue":
			continue
		for n: Variant in rec.get("nodes", []):
			if typeof(n) != TYPE_DICTIONARY:
				continue
			for c: Variant in n.get("choices", []):
				if typeof(c) != TYPE_DICTIONARY or typeof(c.get("effects")) != TYPE_DICTIONARY:
					continue
				var outcome := str(c.effects.get("outcome", ""))
				if outcome.begins_with(RECONCILE_PREFIX):
					if not offers.has(outcome):
						offers[outcome] = []
					(offers[outcome] as Array).append(c.effects.get("take_items", []))
	var ids: Array = records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY or str(rec.get("type", "")) != "faction" or typeof(rec.get("reconcile")) != TYPE_DICTIONARY:
			continue
		var outcome := RECONCILE_PREFIX + str(id).trim_prefix("faction.")
		var ctx := "%s (%s)" % [record_paths.get(id, id), id]
		if not offers.has(outcome):
			errors.append("%s: no dialogue offers its reconciliation (a choice with outcome '%s')" % [ctx, outcome])
			continue
		var cost: Variant = rec.reconcile.get("cost", [])
		var matched := false
		for taken: Variant in offers[outcome]:
			if _same_items(taken, cost):
				matched = true
		if not matched:
			errors.append("%s: the '%s' choice does not take the reconciliation's cost %s" % [ctx, outcome, JSON.stringify(cost)])
	return errors


## The oath leads' errors (see the class notes): one line per stage whose leads do not each end with
## their own oath.
static func lead_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Array = records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY or str(rec.get("type", "")) != "quest":
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, id), id]
		for s: Variant in rec.get("stages", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var oaths := oath_done_flags_read(s.get("complete_when"))
			var markers := PackedStringArray()
			var named: Array = [s.get("marker", "")]
			if typeof(s.get("markers")) == TYPE_ARRAY:
				named.append_array(s.markers)
			for m: Variant in named:
				if typeof(m) == TYPE_STRING and str(m) != "" and not markers.has(str(m)):
					markers.append(str(m))
			if oaths.is_empty() or markers.size() < 2:
				continue
			var done_when: Dictionary = s.markers_done_when if typeof(s.get("markers_done_when")) == TYPE_DICTIONARY else {}
			var claimed := {}
			var lacking := PackedStringArray()
			for m in markers:
				var c: Variant = done_when.get(m)
				var flag := str(c.get("flag", "")) if typeof(c) == TYPE_DICTIONARY and str(c.get("type", "")) == "flag" \
					and not (c as Dictionary).has("equals") else ""
				if not oaths.has(flag):
					lacking.append(m)
				elif claimed.has(flag):
					errors.append("%s: stage '%s': the leads '%s' and '%s' both end with %s (one lead per oath)" % [
						ctx, s.get("id", ""), claimed[flag], m, flag])
				else:
					claimed[flag] = m
			var unclaimed := PackedStringArray()
			for f in oaths:
				if not claimed.has(f):
					unclaimed.append(f)
			if not lacking.is_empty() or not unclaimed.is_empty():
				errors.append("%s: stage '%s': the oath leads %s need a markers_done_when on their own oath (%s): a lead must not outlive its oath" % [
					ctx, s.get("id", ""), ", ".join(lacking), ", ".join(unclaimed)])
	return errors


## The oaths' done flags (oath.<x>.done) a condition reads, through all / any / count, in order.
static func oath_done_flags_read(c: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(c) != TYPE_DICTIONARY:
		return out
	match str(c.get("type", "")):
		"flag":
			var f := str(c.get("flag", ""))
			if f.begins_with("oath.") and f.ends_with(".done") and f.get_slice_count(".") == 3:
				out.append(f)
		"all", "any", "count":
			for sub: Variant in c.get("of", []):
				for f in oath_done_flags_read(sub):
					if not out.has(f):
						out.append(f)
	return out


static func _same_items(a: Variant, b: Variant) -> bool:
	var ca := {}
	var cb := {}
	for pair: Array in [[a, ca], [b, cb]]:
		if typeof(pair[0]) != TYPE_ARRAY:
			continue
		for it: Variant in pair[0]:
			if typeof(it) == TYPE_DICTIONARY:
				var k := str(it.get("item", ""))
				(pair[1] as Dictionary)[k] = int((pair[1] as Dictionary).get(k, 0)) + int(it.get("count", 1))
	return ca == cb
