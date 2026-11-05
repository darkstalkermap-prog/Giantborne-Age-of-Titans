extends RefCounted
## Schema module for "tutorial_prompt" records (P13; plan §2.8.3, §4.5): one hint the tutorial
## director (scripts/quests/tutorial_director.gd) shows when its trigger holds, until its dismiss
## condition holds. Loaded by DataValidator's registry (see data_validator.gd for the contract).
##
##   {"schema_version": 1, "id": "tutorial.block", "type": "tutorial_prompt",
##    "text": "Raise your guard with {block}. Block just as the blow lands to parry it.",
##    "trigger": {"type": "event", "event": "telegraph_started", "target": "player", "action_tags_any": ["Parryable"]},
##    "dismiss": {"type": "event", "event": "hit_resolved", "defender": "player", "outcome_in": ["blocked", "parried"]},
##    "requires_flags": [], "min_stage": 1, "priority": 20, "once": true, "defer_in_combat": false,
##    "sets_flag": "tutorial.block.done"}
##
## trigger (TUTORIAL_TRIGGERS):
##   {"type": "entered", "area": <area id>}            the player is inside the area now (a state)
##   {"type": "flag", "flag": <id>, "equals"?, "at_least"?}   the flag holds (truthy without a test)
##   {"type": "level", "level": n}                       the character level is at least n
##   {"type": "stage", "stage": n}                       the growth stage is at least n
##   {"type": "event", "event": <TUTORIAL_EVENTS>, <filters>}   the event happened (an edge)
## dismiss (TUTORIAL_DISMISS), each with an optional "timeout_s" fallback (the prompt then goes
## away without its lesson being marked done) except the timeout type itself:
##   {"type": "action_kind", "action_kind": <ACTION_KINDS>, "count"?}   the player started that many
##   {"type": "action_id", "action_id": <action>, "count"?}              ... of that action
##   {"type": "event", "event": <TUTORIAL_EVENTS>, <filters>, "count"?}   the event happened count times
##   {"type": "flag", "flag": <id>, "equals"?, "at_least"?}
##   {"type": "timeout", "timeout_s": s}                                  shown for s seconds
## Event filters (the only keys an event takes besides type, event, count and timeout_s):
##   telegraph_started {target, action_tags_any, actor_archetype}; hit_resolved {defender,
##   attacker, outcome_in}; staggered {near_player_m, grabbable}; ability_started {actor,
##   action_kind, action_id}; lock_target_changed {actor, non_empty}; boss_phase_changed {phase};
##   interacted {interact_prefix}; the others none. Entity filters compare entity ids ("player"
##   is the giant's).
## Other fields: requires_flags (all truthy), min_stage (default 1), priority (higher shows
## first, default 0), once (default true: never again once seen), defer_in_combat (wait until
## the player is out of combat), sets_flag (set when the lesson is done; "" = none).
## Semantic rules: the id starts with "tutorial."; trigger and dismiss shapes; flag and area ids
## pass the id regex. Warning: a {placeholder} that names no input action.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"text": U.str_field(true),
		"trigger": {"t": "any", "req": true},
		"dismiss": {"t": "any", "req": true},
		"requires_flags": {"t": "array", "items": "string"},
		"min_stage": U.int_field(1, 10),
		"priority": U.int_field(-1000, 1000),
		"once": U.bool_field(),
		"defer_in_combat": U.bool_field(),
		"sets_flag": U.str_field(),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var id: Variant = d.get("id")
	if typeof(id) == TYPE_STRING and not str(id).begins_with("tutorial."):
		out.errors.append("%s: tutorial prompt ids start with 'tutorial.' (got '%s')" % [ctx, id])
	if d.has("trigger"):
		check_trigger(d.trigger, ctx + ".trigger", out)
	if d.has("dismiss"):
		check_dismiss(d.dismiss, ctx + ".dismiss", out)
	var flags: Variant = d.get("requires_flags")
	if typeof(flags) == TYPE_ARRAY:
		var i := 0
		for f: Variant in flags:
			U.check_flag_id(f, "%s.requires_flags[%d]" % [ctx, i], out)
			i += 1
	var sets: Variant = d.get("sets_flag", "")
	if typeof(sets) == TYPE_STRING and sets != "":
		U.check_flag_id(sets, ctx + ".sets_flag", out)
	var text: Variant = d.get("text")
	if typeof(text) == TYPE_STRING:
		for w in TutorialText.placeholders_in(text):
			if not TutorialText.is_known(w):
				out.warnings.append("%s.text: {%s} names no input action (it is shown as written)" % [ctx, w])


## The filter keys an event trigger or dismissal of `event` may use (field specs).
static func event_filter_fields(event: String) -> Dictionary:
	match event:
		"telegraph_started":
			return {"target": U.str_field(), "action_tags_any": U.enum_array(DataValidator.TAGS),
				"actor_archetype": U.str_field(false, DataValidator.ARCHETYPES)}
		"hit_resolved":
			return {"defender": U.str_field(), "attacker": U.str_field(),
				"outcome_in": U.enum_array(HitResult.OUTCOME_NAMES)}
		"staggered":
			return {"near_player_m": U.pos(), "grabbable": U.bool_field()}
		"ability_started":
			return {"actor": U.str_field(), "action_kind": U.str_field(false, DataValidator.ACTION_KINDS),
				"action_id": U.ref("action")}
		"lock_target_changed":
			return {"actor": U.str_field(), "non_empty": U.bool_field()}
		"boss_phase_changed":
			return {"phase": U.int_field(1, 10)}
		"interacted":
			return {"interact_prefix": U.str_field()}
	return {}


static func check_trigger(t: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(t) != TYPE_DICTIONARY:
		out.errors.append("%s: expected an object, got %s" % [ctx, type_string(typeof(t))])
		return
	var type_value: Variant = t.get("type")
	if typeof(type_value) != TYPE_STRING or not DataValidator.TUTORIAL_TRIGGERS.has(type_value):
		out.errors.append("%s.type: unknown value '%s' (allowed: %s)" % [ctx, type_value, DataValidator.TUTORIAL_TRIGGERS])
		return
	var schema := {"type": U.str_field(true)}
	match type_value:
		"entered":
			schema["area"] = U.str_field(true)
		"flag":
			schema.merge({"flag": U.str_field(true), "equals": {"t": "any"}, "at_least": U.num()})
		"level":
			schema["level"] = U.int_field(1, 20, true)
		"stage":
			schema["stage"] = U.int_field(1, 10, true)
		"event":
			if not _check_event_name(t, ctx, out):
				return
			schema["event"] = U.str_field(true)
			schema.merge(event_filter_fields(str(t.event)))
	U.check_fields(t, schema, ctx, out)
	if type_value == "entered" and typeof(t.get("area")) == TYPE_STRING:
		U.check_id_string(t.area, ctx + ".area", out)
	if type_value == "flag" and typeof(t.get("flag")) == TYPE_STRING:
		U.check_flag_id(t.flag, ctx + ".flag", out)


static func check_dismiss(t: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(t) != TYPE_DICTIONARY:
		out.errors.append("%s: expected an object, got %s" % [ctx, type_string(typeof(t))])
		return
	var type_value: Variant = t.get("type")
	if typeof(type_value) != TYPE_STRING or not DataValidator.TUTORIAL_DISMISS.has(type_value):
		out.errors.append("%s.type: unknown value '%s' (allowed: %s)" % [ctx, type_value, DataValidator.TUTORIAL_DISMISS])
		return
	var schema := {"type": U.str_field(true), "timeout_s": U.pos(type_value == "timeout")}
	match type_value:
		"action_kind":
			schema.merge({"action_kind": U.str_field(true, DataValidator.ACTION_KINDS), "count": U.int_field(1, 100)})
		"action_id":
			schema.merge({"action_id": U.ref("action", true), "count": U.int_field(1, 100)})
		"event":
			if not _check_event_name(t, ctx, out):
				return
			schema.merge({"event": U.str_field(true), "count": U.int_field(1, 100)})
			schema.merge(event_filter_fields(str(t.event)))
		"flag":
			schema.merge({"flag": U.str_field(true), "equals": {"t": "any"}, "at_least": U.num()})
	U.check_fields(t, schema, ctx, out)
	if type_value == "flag" and typeof(t.get("flag")) == TYPE_STRING:
		U.check_flag_id(t.flag, ctx + ".flag", out)


static func _check_event_name(t: Dictionary, ctx: String, out: Dictionary) -> bool:
	var ev: Variant = t.get("event")
	if typeof(ev) != TYPE_STRING or not DataValidator.TUTORIAL_EVENTS.has(ev):
		out.errors.append("%s.event: unknown value '%s' (allowed: %s)" % [ctx, ev, DataValidator.TUTORIAL_EVENTS])
		return false
	return true


static func required_ids() -> Dictionary:
	return {}
