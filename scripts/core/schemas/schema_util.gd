class_name SchemaUtil
extends RefCounted
## Shared builders and checkers for the per-type schema modules (scripts/core/schemas/).
##
## A field spec is a Dictionary understood by check_value():
##   "t": "number" | "int" | "string" | "bool" | "vec3" | "array" | "dict"
##   "req": bool, "min", "max", "gt" (numbers), "enum" (strings),
##   "ref": record type (+ "ref_allow_empty") for string references,
##   arrays: "items" ("string" | "number" | "int" | "dict"), "items_enum", "items_ref",
##           "items_ref_allow_empty", "item_fields" (strict sub-schema for dict items),
##   dicts:  "fields" (strict sub-schema) or "keys_enum" + "values" (a map).
## Unknown keys are always errors. Every message here is pinned by tests; do not reword them.

# --------------------------------------------------------------------------- builders

static func num(min_v: Variant = null, max_v: Variant = null, req := false) -> Dictionary:
	var s := {"t": "number", "req": req}
	if min_v != null:
		s["min"] = min_v
	if max_v != null:
		s["max"] = max_v
	return s


## A number that must be > 0.
static func pos(req := false) -> Dictionary:
	return {"t": "number", "gt": 0.0, "req": req}


static func int_field(min_v: Variant = null, max_v: Variant = null, req := false) -> Dictionary:
	var s := {"t": "int", "req": req}
	if min_v != null:
		s["min"] = min_v
	if max_v != null:
		s["max"] = max_v
	return s


static func str_field(req := false, enum_values: Array = []) -> Dictionary:
	var s := {"t": "string", "req": req}
	if not enum_values.is_empty():
		s["enum"] = enum_values
	return s


static func bool_field(req := false) -> Dictionary:
	return {"t": "bool", "req": req}


## A reference to another record of exactly `type` (checked across records after loading).
static func ref(type: String, req := false, allow_empty := false) -> Dictionary:
	return {"t": "string", "req": req, "ref": type, "ref_allow_empty": allow_empty}


static func vec3(req := false) -> Dictionary:
	return {"t": "vec3", "req": req}


## An array of strings from a closed list.
static func enum_array(values: Array, req := false) -> Dictionary:
	return {"t": "array", "req": req, "items": "string", "items_enum": values}


## An array of references to records of exactly `type`.
static func ref_array(type: String, req := false, allow_empty := false) -> Dictionary:
	return {"t": "array", "req": req, "items": "string", "items_ref": type,
		"items_ref_allow_empty": allow_empty}


## The shared poise block (player and enemy records).
static func poise_fields() -> Dictionary:
	return {
		"threshold": pos(true),
		"recover_per_s": num(0.0),
		"recover_delay_s": num(0.0),
		"stagger_s": pos(),
		"immunity_s": num(0.0),
		# Poise damage taken during the owner's own attack RECOVERY phase is multiplied by this.
		"recovery_mult": num(1.0),
		# Stagger length when the attacker is at least twice the defender's height.
		"stagger_vs_larger_s": pos(),
	}


# --------------------------------------------------------------------------- checks

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func check_fields(d: Dictionary, schema: Dictionary, ctx: String, out: Dictionary) -> void:
	for key: Variant in d.keys():
		if not schema.has(key):
			out.errors.append("%s: unknown key '%s'" % [ctx, key])
	for key: String in schema.keys():
		var spec: Dictionary = schema[key]
		if not d.has(key):
			if spec.get("req", false):
				out.errors.append("%s: missing required key '%s'" % [ctx, key])
			continue
		check_value(d[key], spec, "%s.%s" % [ctx, key], out)


static func check_value(v: Variant, spec: Dictionary, ctx: String, out: Dictionary) -> void:
	match spec.t:
		"number", "int":
			if not is_number(v):
				out.errors.append("%s: expected a number, got %s" % [ctx, type_string(typeof(v))])
				return
			var f := float(v)
			if spec.t == "int" and f != floorf(f):
				out.errors.append("%s: expected an integer, got %s" % [ctx, v])
			if spec.has("min") and f < float(spec.min):
				out.errors.append("%s: must be >= %s (got %s)" % [ctx, spec.min, v])
			if spec.has("gt") and f <= float(spec.gt):
				out.errors.append("%s: must be > %s (got %s)" % [ctx, spec.gt, v])
			if spec.has("max") and f > float(spec.max):
				out.errors.append("%s: must be <= %s (got %s)" % [ctx, spec.max, v])
		"string":
			if typeof(v) != TYPE_STRING:
				out.errors.append("%s: expected a string, got %s" % [ctx, type_string(typeof(v))])
				return
			if spec.has("enum") and not (spec.enum as Array).has(v):
				out.errors.append("%s: unknown value '%s' (allowed: %s)" % [ctx, v, spec.enum])
			if spec.has("ref"):
				if v == "":
					if not spec.get("ref_allow_empty", false):
						out.errors.append("%s: reference must not be empty" % ctx)
				else:
					out.refs.append({"ctx": ctx, "id": v, "type": spec.ref})
		"bool":
			if typeof(v) != TYPE_BOOL:
				out.errors.append("%s: expected true/false, got %s" % [ctx, type_string(typeof(v))])
		"vec3":
			if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
				out.errors.append("%s: expected [x, y, z]" % ctx)
				return
			for c: Variant in v:
				if not is_number(c):
					out.errors.append("%s: vector components must be numbers" % ctx)
					return
		"array":
			if typeof(v) != TYPE_ARRAY:
				out.errors.append("%s: expected an array, got %s" % [ctx, type_string(typeof(v))])
				return
			var i := 0
			for item: Variant in v:
				var ictx := "%s[%d]" % [ctx, i]
				match spec.get("items", ""):
					"string":
						if typeof(item) != TYPE_STRING:
							out.errors.append("%s: expected a string" % ictx)
						else:
							if spec.has("items_enum") and not (spec.items_enum as Array).has(item):
								out.errors.append("%s: unknown value '%s' (allowed: %s)" % [ictx, item, spec.items_enum])
							if spec.has("items_ref"):
								if item == "":
									if not spec.get("items_ref_allow_empty", false):
										out.errors.append("%s: reference must not be empty" % ictx)
								else:
									out.refs.append({"ctx": ictx, "id": item, "type": spec.items_ref})
					"number":
						if not is_number(item):
							out.errors.append("%s: expected a number" % ictx)
						elif float(item) < 0.0:
							out.errors.append("%s: must be >= 0" % ictx)
					"int":
						if not is_number(item):
							out.errors.append("%s: expected a number" % ictx)
						elif float(item) != floorf(float(item)):
							out.errors.append("%s: expected an integer, got %s" % [ictx, item])
						elif float(item) < 0.0:
							out.errors.append("%s: must be >= 0" % ictx)
					"dict":
						if typeof(item) != TYPE_DICTIONARY:
							out.errors.append("%s: expected an object" % ictx)
						elif spec.has("item_fields"):
							check_fields(item, spec.item_fields, ictx, out)
				i += 1
		"dict":
			if typeof(v) != TYPE_DICTIONARY:
				out.errors.append("%s: expected an object, got %s" % [ctx, type_string(typeof(v))])
				return
			var dv: Dictionary = v
			if spec.has("fields"):
				check_fields(dv, spec.fields, ctx, out)
				return
			for k: Variant in dv.keys():
				if spec.has("keys_enum") and not (spec.keys_enum as Array).has(k):
					out.errors.append("%s: unknown key '%s' (allowed: %s)" % [ctx, k, spec.keys_enum])
				if spec.has("values"):
					check_value(dv[k], spec.values, "%s.%s" % [ctx, k], out)


static func require(d: Dictionary, keys: Array, ctx: String, out: Dictionary, why: String) -> void:
	for k: String in keys:
		if not d.has(k):
			out.errors.append("%s: '%s' is required for %s" % [ctx, k, why])


## Timings that are not whole 1/60 s ticks are rounded by ActionDef; warn so tuning never drifts.
static func check_tick_multiple(d: Dictionary, keys: Array, ctx: String, out: Dictionary) -> void:
	for k: String in keys:
		if d.has(k) and is_number(d[k]):
			var ticks := float(d[k]) * DataValidator.TICK_RATE
			if absf(ticks - roundf(ticks)) > 0.01:
				out.warnings.append("%s.%s: %s s is not a whole number of 1/60 s ticks; rounded to %d ticks" % [
					ctx, k, d[k], int(roundf(ticks))])


## Flag ids (WorldState.flags) use the dotted id form, e.g. "quest.main.stage". Returns true if valid.
static func check_flag_id(v: Variant, ctx: String, out: Dictionary) -> bool:
	if typeof(v) != TYPE_STRING:
		out.errors.append("%s: expected a flag id string, got %s" % [ctx, type_string(typeof(v))])
		return false
	var re := RegEx.create_from_string(DataValidator.ID_REGEX)
	if re.search(v) == null:
		out.errors.append("%s: flag id '%s' must be lowercase dotted form like 'quest.main.stage'" % [ctx, v])
		return false
	return true


## Validates an id that is not a record reference (spawned entity ids, world ids, area ids).
static func check_id_string(v: Variant, ctx: String, out: Dictionary) -> bool:
	if typeof(v) != TYPE_STRING:
		out.errors.append("%s: expected an id string, got %s" % [ctx, type_string(typeof(v))])
		return false
	var re := RegEx.create_from_string(DataValidator.ID_REGEX)
	if re.search(v) == null:
		out.errors.append("%s: id '%s' must be lowercase dotted form like 'valley.forest.wolf_a1'" % [ctx, v])
		return false
	return true


## Validates a list of condition dicts (quests, dialogue, tutorials). See check_condition.
static func check_conditions(v: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(v) != TYPE_ARRAY:
		out.errors.append("%s: expected an array of conditions, got %s" % [ctx, type_string(typeof(v))])
		return
	var i := 0
	for c: Variant in v:
		check_condition(c, "%s[%d]" % [ctx, i], out)
		i += 1


## One condition dict (plan section 2.8.3). Shapes, by "type":
##   flag {flag, equals?, at_least?} | entered {area} | killed {targets} |
##   encounter_cleared {encounter} | destroyed {world_id} | has_item {item, count} |
##   hits_on {targets, count, action_kind?, action_id?} | stage_at_least {stage} |
##   level_at_least {level} | weapon_equipped {weapon} | dialogue_outcome {dialogue, outcome} |
##   all / any {of: [conditions]} | not {of: condition}
## Flag ids, area ids, world ids and target entity ids are checked against the id regex;
## items, weapons, actions, encounters and dialogues are record references.
static func check_condition(c: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		out.errors.append("%s: expected a condition object, got %s" % [ctx, type_string(typeof(c))])
		return
	var d: Dictionary = c
	var type_value: Variant = d.get("type")
	if typeof(type_value) != TYPE_STRING or not DataValidator.CONDITION_TYPES.has(type_value):
		out.errors.append("%s.type: unknown value '%s' (allowed: %s)" % [ctx, type_value, DataValidator.CONDITION_TYPES])
		return
	# Keys checked with check_value; "special" keys get their own checks below.
	var schema := {}
	var special: Array = []
	match type_value:
		"flag":
			schema = {"at_least": num()}
			special = ["flag", "equals"]
		"entered":
			special = ["area"]
		"killed":
			special = ["targets"]
		"encounter_cleared":
			schema = {"encounter": ref("encounter", true)}
		"destroyed":
			special = ["world_id"]
		"has_item":
			schema = {"item": ref("item", true), "count": int_field(1, null, true)}
		"hits_on":
			schema = {"count": int_field(1, null, true),
				"action_kind": str_field(false, DataValidator.ACTION_KINDS), "action_id": ref("action")}
			special = ["targets"]
		"stage_at_least":
			schema = {"stage": int_field(1, 10, true)}
		"level_at_least":
			schema = {"level": int_field(1, 20, true)}
		"weapon_equipped":
			schema = {"weapon": ref("weapon", true)}
		"dialogue_outcome":
			schema = {"dialogue": ref("dialogue", true), "outcome": str_field(true)}
		"all", "any", "not":
			special = ["of"]
	for k: Variant in d.keys():
		if k != "type" and not schema.has(k) and not special.has(k):
			out.errors.append("%s: unknown key '%s'" % [ctx, k])
	for k: String in schema:
		var spec: Dictionary = schema[k]
		if not d.has(k):
			if spec.get("req", false):
				out.errors.append("%s: missing required key '%s'" % [ctx, k])
			continue
		check_value(d[k], spec, "%s.%s" % [ctx, k], out)
	for k: String in special:
		if k == "equals":
			continue  # any JSON value
		if not d.has(k):
			out.errors.append("%s: missing required key '%s'" % [ctx, k])
			continue
		var kctx := "%s.%s" % [ctx, k]
		match k:
			"flag":
				check_flag_id(d[k], kctx, out)
			"area", "world_id":
				check_id_string(d[k], kctx, out)
			"targets":
				if typeof(d[k]) != TYPE_ARRAY:
					out.errors.append("%s: expected an array, got %s" % [kctx, type_string(typeof(d[k]))])
				elif (d[k] as Array).is_empty():
					out.errors.append("%s: must list at least one id" % kctx)
				else:
					var j := 0
					for t: Variant in d[k]:
						check_id_string(t, "%s[%d]" % [kctx, j], out)
						j += 1
			"of":
				if type_value == "not":
					check_condition(d[k], kctx, out)
				else:
					check_conditions(d[k], kctx, out)
