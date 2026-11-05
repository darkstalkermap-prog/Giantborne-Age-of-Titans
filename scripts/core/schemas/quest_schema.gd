extends RefCounted
## Schema module for "quest" records (P13; plan §2.8.3, §4.5, §4.6): ordered stages with a
## completion condition each, run by the Quests autoload (scripts/quests/quests.gd).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "quest.main", "type": "quest", "display_name": "The Valley of Broken Kings",
##    "prototype_pacing": true, "auto_start": true, "start_conditions": [], "abandon_when": null,
##    "stages": [{"id": "ogre", "objective": "Defeat the ogre blocking the forest trail",
##                "complete_when": {"type": "killed", "targets": ["valley.forest.ogre"]},
##                "marker": "valley.marker.ogre_clearing", "xp": 110, "items": [], "set_flags": {},
##                "bot": {"action": "kill", "target": "valley.forest.ogre"}}],
##    "on_complete_flags": {"slice.completed": true}}
##
## An auto_start quest starts at once (New Game); otherwise it starts the first time every
## start_conditions entry holds. abandon_when (a condition, or null) ends an active quest without
## rewards. Stages run in order; when one's complete_when holds, its rewards (xp, items,
## set_flags) are granted once (the once-flag reward.<quest short id>.<stage>) and the next stage
## starts; after the last one the quest is complete and on_complete_flags are set (first write
## wins). The quest's state lives in the flags quest.<short id>.stage and quest.<short id>.done.
## `marker` is an objective marker id ("" = none); `bot` is the Valley bot's hint for the stage:
## {"action": one of BOT_ACTIONS (required), "target": an id (optional), any other keys the bot
## reads}. tracker_priority (optional, default 0) orders side quests in the HUD tracker (higher
## first).
##
## Semantic rules: the id starts with "quest."; at least one stage; stage ids are unique plain
## words; conditions are valid (§2.8.3 shapes); marker and bot target ids and flag ids pass the
## id regex; flag values are scalars; a bot hint names a known action. Warning: an auto_start
## quest's start_conditions are ignored.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const DIALOGUE := preload("res://scripts/core/schemas/dialogue_schema.gd")

## Stage ids are plain lowercase words (they become parts of flag ids: reward.main.<stage>).
const WORD_REGEX := "^[a-z][a-z0-9_]*$"


static func fields() -> Dictionary:
	return {
		# XP of this quest is accelerated for the prototype (decision 7): the HUD labels it.
		"prototype_pacing": U.bool_field(),
		# Start at once (New Game) instead of waiting for start_conditions.
		"auto_start": U.bool_field(),
		"start_conditions": {"t": "array"},
		# A condition (or null): the active quest ends without rewards when it holds.
		"abandon_when": {"t": "any"},
		# Side quests with a higher value are shown first by the HUD tracker (default 0).
		"tracker_priority": U.int_field(-100, 100),
		"on_complete_flags": {"t": "dict"},
		"stages": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"objective": U.str_field(true),
			"complete_when": {"t": "any", "req": true},
			"marker": U.str_field(),
			"xp": U.int_field(0, 100000),
			"items": DIALOGUE.item_list(),
			"set_flags": {"t": "dict"},
			"bot": {"t": "dict"}}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("quest."):
		out.errors.append("%s: quest ids start with 'quest.' (got '%s')" % [ctx, id])
	var starts: Variant = d.get("start_conditions", [])
	if typeof(starts) == TYPE_ARRAY:
		U.check_conditions(starts, ctx + ".start_conditions", out)
		if bool(d.get("auto_start", false)) and not (starts as Array).is_empty():
			out.warnings.append("%s: start_conditions are ignored while auto_start is true" % ctx)
	if d.has("abandon_when") and d.abandon_when != null:
		U.check_condition(d.abandon_when, ctx + ".abandon_when", out)
	DIALOGUE.check_flag_map(d.get("on_complete_flags"), ctx + ".on_complete_flags", out)
	var stages: Variant = d.get("stages")
	if typeof(stages) != TYPE_ARRAY:
		return
	if (stages as Array).is_empty():
		out.errors.append("%s: stages must list at least one stage" % ctx)
	var word := RegEx.create_from_string(WORD_REGEX)
	var seen := {}
	var i := 0
	for s: Variant in stages:
		var sctx := "%s.stages[%d]" % [ctx, i]
		i += 1
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sid: Variant = s.get("id")
		if typeof(sid) == TYPE_STRING:
			if word.search(sid) == null:
				out.errors.append("%s.id: stage id '%s' must be a plain lowercase word like 'grove'" % [sctx, sid])
			if seen.has(sid):
				out.errors.append("%s.id: duplicate stage id '%s'" % [sctx, sid])
			seen[sid] = true
		if s.has("complete_when"):
			U.check_condition(s.complete_when, sctx + ".complete_when", out)
		var marker: Variant = s.get("marker", "")
		if typeof(marker) == TYPE_STRING and marker != "":
			U.check_id_string(marker, sctx + ".marker", out)
		DIALOGUE.check_flag_map(s.get("set_flags"), sctx + ".set_flags", out)
		var bot: Variant = s.get("bot")
		if typeof(bot) == TYPE_DICTIONARY:
			check_bot_hint(bot, sctx + ".bot", out)


## A stage's bot hint: "action" (required, one of BOT_ACTIONS) and an optional "target" id; any
## other keys are left to the bot.
static func check_bot_hint(b: Dictionary, ctx: String, out: Dictionary) -> void:
	var action: Variant = b.get("action")
	if action == null:
		out.errors.append("%s: missing required key 'action'" % ctx)
	elif typeof(action) != TYPE_STRING or not DataValidator.BOT_ACTIONS.has(action):
		out.errors.append("%s.action: unknown value '%s' (allowed: %s)" % [ctx, action, DataValidator.BOT_ACTIONS])
	var target: Variant = b.get("target")
	if target != null and not (typeof(target) == TYPE_STRING and target == ""):
		U.check_id_string(target, ctx + ".target", out)


static func required_ids() -> Dictionary:
	return {}
