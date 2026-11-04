extends RefCounted
## Schema module for "input_bindings" records (data/input/default_bindings.json).
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
## Every InputBindings.ACTIONS entry needs a default binding entry here.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"actions": {"t": "dict", "req": true},
		"deadzones": {"t": "dict", "values": U.num(0.0, 1.0)},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var actions: Variant = d.get("actions")
	if typeof(actions) != TYPE_DICTIONARY:
		return
	for action_name: Variant in actions:
		var actx := "%s.actions.%s" % [ctx, action_name]
		if not InputBindings.ACTIONS.has(action_name):
			out.errors.append("%s: unknown input action (allowed: %s)" % [actx, InputBindings.ACTIONS])
			continue
		if typeof(actions[action_name]) != TYPE_ARRAY:
			out.errors.append("%s: expected an array of input events" % actx)
			continue
		var i := 0
		for ev: Variant in actions[action_name]:
			var problem := InputBindings.validate_event_dict(ev)
			if problem != "":
				out.errors.append("%s[%d]: %s" % [actx, i, problem])
			i += 1
	for action_name: Variant in InputBindings.ACTIONS:
		if not actions.has(action_name):
			out.errors.append("%s: no default binding entry for input action '%s'" % [ctx, action_name])
	var dz: Variant = d.get("deadzones")
	if typeof(dz) == TYPE_DICTIONARY:
		for k: Variant in dz:
			if k != "default" and not InputBindings.ACTIONS.has(k):
				out.errors.append("%s.deadzones: unknown action '%s'" % [ctx, k])


static func required_ids() -> Dictionary:
	return {"input.default": "input_bindings"}
