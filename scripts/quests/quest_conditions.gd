class_name QuestConditions
extends RefCounted
## The condition dictionaries of quests, dialogue and tutorial prompts (plan §2.8.3, §3.15
## design 2), evaluated against a context dictionary. Pure: no scene, autoload or record access,
## so tests build contexts by hand; Quests.condition_context() builds the live one.
##
## Context keys (empty_context() has them all):
##   flags      {flag id: value}                     WorldState.flags
##   deltas     {world/entity id: delta}             WorldState.deltas ("killed", "destroyed")
##   inventory  {item id: count}                     WorldState.inventory
##   stage      int                                  the player's growth stage
##   level      int                                  the character level (progression)
##   weapon     String                               the equipped weapon id
##   inside     {area id: true}                      areas the player is inside now
##   entered    {area id: true}                      areas entered since the level loaded
##   died       {entity id: true}                    deaths seen since the level loaded
##   destroyed  {world id: true}                     destructions seen since the level loaded
##   hits       {target id: {action id: count}}      the player's blows that connected
##   hit_kinds  {action id: kind}                    the kind of every action in `hits`
##   level_id   String                               the campaign level played ("" outside it; P20)
##   position   Vector3                              the player's position (INF without one; P20)
##   ancestry   String                               the character's ancestry id (P20)
##   ancestry_chosen  bool                           the ancestry was chosen (P20; P33 offers it)
##
## Shapes ({"type": ...}):
##   flag {flag, equals?, at_least?}   truthy without a test; equals compares numbers as numbers
##   entered {area}                    inside now, or entered since the level loaded
##   killed {targets}                  every target is dead (saved kill or a death seen)
##   encounter_cleared {encounter}     the flag encounter.<short id>.cleared is truthy
##   destroyed {world_id}              the object is destroyed (saved or seen)
##   has_item {item, count}            at least count held
##   hits_on {targets, count, action_kind?, action_id?}   the player's connected blows on the
##                                     targets, counting only actions that match the filters
##   stage_at_least {stage}, level_at_least {level}, weapon_equipped {weapon}
##   dialogue_outcome {dialogue, outcome}   the flag dialogue.<short id>.outcome.<outcome>
##   all / any {of: [conditions]}, not {of: condition}
## M6-M9 (plan §2.12; P20 evaluates the pure ones):
##   count {n, of: [conditions]}       at least n of the conditions hold
##   quest_done {quest}                the quest is complete (the flag quest.<short id>.done is true)
##   level_is {level}                  the campaign level being played is that level record
##   ancestry_is {ancestry}            the character's ancestry is that record
##   ancestry_chosen {}                the character has chosen its ancestry
##   discovered {poi} (P27), region_entered {region} (P27), event_done {event, outcome?} (P37),
##   near {target, radius_m} (P29)     evaluated below those packages' anchors in holds()
## An empty list of conditions holds; an unknown or malformed condition does not (nor does a
## declared type whose package has not landed yet).

const KEYS := ["flags", "deltas", "inventory", "stage", "level", "weapon", "inside", "entered",
	"died", "destroyed", "hits", "hit_kinds", "level_id", "position", "ancestry", "ancestry_chosen"]


## A context with every key and nothing in it (stage 1, level 1, no weapon).
static func empty_context() -> Dictionary:
	return {"flags": {}, "deltas": {}, "inventory": {}, "stage": 1, "level": 1, "weapon": "",
		"inside": {}, "entered": {}, "died": {}, "destroyed": {}, "hits": {}, "hit_kinds": {},
		"level_id": "", "position": Vector3.INF, "ancestry": "", "ancestry_chosen": false}


## True when every condition of `conds` holds (an empty list, or null, holds).
static func all_hold(conds: Variant, ctx: Dictionary) -> bool:
	if conds == null:
		return true
	if typeof(conds) != TYPE_ARRAY:
		return false
	for c: Variant in conds:
		if not holds(c, ctx):
			return false
	return true


## True when the condition `c` holds in `ctx`.
static func holds(c: Variant, ctx: Dictionary) -> bool:
	if typeof(c) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = c
	match str(d.get("type", "")):
		"flag":
			return flag_matches((ctx.get("flags", {}) as Dictionary).get(str(d.get("flag", ""))), d)
		"entered":
			return is_entered(ctx, str(d.get("area", "")))
		"killed":
			var targets: Variant = d.get("targets")
			if typeof(targets) != TYPE_ARRAY or (targets as Array).is_empty():
				return false
			for t: Variant in targets:
				if not is_killed(ctx, str(t)):
					return false
			return true
		"encounter_cleared":
			return truthy((ctx.get("flags", {}) as Dictionary).get(encounter_flag(str(d.get("encounter", "")))))
		"destroyed":
			return is_destroyed(ctx, str(d.get("world_id", "")))
		"has_item":
			return int((ctx.get("inventory", {}) as Dictionary).get(str(d.get("item", "")), 0)) \
				>= maxi(1, int(d.get("count", 1)))
		"hits_on":
			var targets: Variant = d.get("targets")
			if typeof(targets) != TYPE_ARRAY:
				return false
			return hit_count(ctx, targets, str(d.get("action_kind", "")), str(d.get("action_id", ""))) \
				>= maxi(1, int(d.get("count", 1)))
		"stage_at_least":
			return int(ctx.get("stage", 1)) >= int(d.get("stage", 1))
		"level_at_least":
			return int(ctx.get("level", 1)) >= int(d.get("level", 1))
		"weapon_equipped":
			var w := str(d.get("weapon", ""))
			return w != "" and str(ctx.get("weapon", "")) == w
		"dialogue_outcome":
			return truthy((ctx.get("flags", {}) as Dictionary).get(
				outcome_flag(str(d.get("dialogue", "")), str(d.get("outcome", "")))))
		"all":
			var of: Variant = d.get("of")
			return typeof(of) == TYPE_ARRAY and all_hold(of, ctx)
		"any":
			var of: Variant = d.get("of")
			if typeof(of) != TYPE_ARRAY:
				return false
			for sub: Variant in of:
				if holds(sub, ctx):
					return true
			return false
		"not":
			return typeof(d.get("of")) == TYPE_DICTIONARY and not holds(d.of, ctx)
		# M6-M9 (P20): the pure condition types of plan §2.12.
		"count":
			var of: Variant = d.get("of")
			if typeof(of) != TYPE_ARRAY:
				return false
			var need := int(d.get("n", 1))
			var n := 0
			for sub: Variant in of:
				if holds(sub, ctx):
					n += 1
					if n >= need:
						return true
			return false
		"quest_done":
			var quest := str(d.get("quest", ""))
			return quest != "" and same_value((ctx.get("flags", {}) as Dictionary).get(quest + ".done"), true)
		"level_is":
			var lv := str(d.get("level", ""))
			return lv != "" and str(ctx.get("level_id", "")) == lv
		"ancestry_is":
			var anc := str(d.get("ancestry", ""))
			return anc != "" and str(ctx.get("ancestry", "")) == anc
		"ancestry_chosen":
			return bool(ctx.get("ancestry_chosen", false))
		# A later package adds the branch of its own condition type directly below its anchor:
		# discovered and region_entered (P27), near (P29), event_done (P37).
		## @anchor P27
		## @anchor P29
		## @anchor P37
	return false


## Flag truthiness: true, a non-zero number or a non-empty string (null and missing are false).
static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v) != ""
	return true


## A flag value against a flag condition: "equals" (numbers compare as numbers), "at_least"
## (a number at least that), or truthy when neither is given.
static func flag_matches(value: Variant, c: Dictionary) -> bool:
	if c.has("equals"):
		return same_value(value, c.equals)
	if c.has("at_least"):
		return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) >= float(c.at_least)
	return truthy(value)


## Equality as WorldState stores values: 1 == 1.0, otherwise the same type and value.
static func same_value(a: Variant, b: Variant) -> bool:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


static func is_entered(ctx: Dictionary, area: String) -> bool:
	if area == "":
		return false
	return (ctx.get("inside", {}) as Dictionary).has(area) or (ctx.get("entered", {}) as Dictionary).has(area)


static func is_killed(ctx: Dictionary, entity_id: String) -> bool:
	if entity_id == "":
		return false
	if (ctx.get("died", {}) as Dictionary).has(entity_id):
		return true
	var delta: Variant = (ctx.get("deltas", {}) as Dictionary).get(entity_id)
	return typeof(delta) == TYPE_DICTIONARY and bool(delta.get("killed", false))


static func is_destroyed(ctx: Dictionary, world_id: String) -> bool:
	if world_id == "":
		return false
	if (ctx.get("destroyed", {}) as Dictionary).has(world_id):
		return true
	var delta: Variant = (ctx.get("deltas", {}) as Dictionary).get(world_id)
	return typeof(delta) == TYPE_DICTIONARY and bool(delta.get("destroyed", false))


## The player's connected blows on `targets` whose action matches the filters (action_kind ""
## and action_id "" = any).
static func hit_count(ctx: Dictionary, targets: Array, action_kind: String, action_id: String) -> int:
	var hits: Dictionary = ctx.get("hits", {})
	var kinds: Dictionary = ctx.get("hit_kinds", {})
	var n := 0
	for t: Variant in targets:
		var per: Variant = hits.get(str(t))
		if typeof(per) != TYPE_DICTIONARY:
			continue
		for a: Variant in per:
			if action_id != "" and str(a) != action_id:
				continue
			if action_kind != "" and str(kinds.get(a, "")) != action_kind:
				continue
			n += int(per[a])
	return n


## The ids a condition names, in order and without repeats: kill and hit targets, areas, world
## ids, encounters, items, weapons (all / any / not included). The objective's "targets".
static func targets_of(c: Variant) -> PackedStringArray:
	var out: Array = []
	_collect_targets(c, out)
	return PackedStringArray(out)


static func _collect_targets(c: Variant, out: Array) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		return
	var d: Dictionary = c
	match str(d.get("type", "")):
		"killed", "hits_on":
			if typeof(d.get("targets")) == TYPE_ARRAY:
				for t: Variant in d.targets:
					_add_target(out, t)
		"entered":
			_add_target(out, d.get("area", ""))
		"destroyed":
			_add_target(out, d.get("world_id", ""))
		"encounter_cleared":
			_add_target(out, d.get("encounter", ""))
		"has_item":
			_add_target(out, d.get("item", ""))
		"weapon_equipped":
			_add_target(out, d.get("weapon", ""))
		"discovered":
			_add_target(out, d.get("poi", ""))
		"near":
			_add_target(out, d.get("target", ""))
		"all", "any", "count":
			if typeof(d.get("of")) == TYPE_ARRAY:
				for sub: Variant in d.of:
					_collect_targets(sub, out)
		"not":
			_collect_targets(d.get("of"), out)


static func _add_target(out: Array, v: Variant) -> void:
	var s := str(v)
	if s != "" and not out.has(s):
		out.append(s)


## The flag a director sets when an encounter is cleared: encounter.<short id>.cleared.
static func encounter_flag(encounter_id: String) -> String:
	return "encounter.%s.cleared" % encounter_id.trim_prefix("encounter.")


## The flag a dialogue outcome sets: dialogue.<short id>.outcome.<outcome>
## (dialogue.elder + intimidate -> dialogue.elder.outcome.intimidate).
static func outcome_flag(dialogue_id: String, outcome: String) -> String:
	return "dialogue.%s.outcome.%s" % [dialogue_id.trim_prefix("dialogue."), outcome]


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Helpers of the condition types above go directly below their package's anchor (plan §1.5).

## @anchor P27

## @anchor P29

## @anchor P37
