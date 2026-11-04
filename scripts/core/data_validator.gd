class_name DataValidator
extends RefCounted
## Startup validation for every JSON content record.
##
## Reports every problem it finds (unknown keys, wrong types, negative costs, nonpositive
## heights, invalid timing, unknown enum values, missing references, duplicate ids) and
## never silently "fixes" data. GameData refuses to start the sandbox if any error remains.

const SUPPORTED_SCHEMA_VERSION := 1
const TICK_RATE := 60

const RECORD_TYPES := ["action", "growth_profile", "player", "enemy", "prop", "weapon", "item",
	"ancestry", "input_bindings"]
const DAMAGE_TYPES := ["physical", "fire", "frost", "lightning", "arcane", "poison"]
const TAGS := ["Melee", "Ranged", "Magic", "Parryable", "Unparryable", "Unblockable", "Unavoidable",
	"BasicAttack", "Light", "Heavy", "Ability", "AoE", "Projectile", "Grab", "Siege"]
const ACTION_KINDS := ["light", "heavy", "ability", "enemy_attack", "ultimate", "dodge", "block",
	"jump", "sprint"]
const ATTACK_KINDS := ["light", "heavy", "ability", "enemy_attack", "ultimate"]
const HIT_SHAPES := ["weapon_arc", "cylinder_pulse", "none"]
const ATTACK_CATEGORIES := ["melee", "ability", "projectile", "magic", "siege"]
const PROP_CATEGORIES := ["cosmetic", "breakable", "structural", "training_target"]
const ARCHETYPES := ["soldier", "archer", "mage", "wolf", "ogre", "boss"]
const WEAPON_FAMILIES := ["club", "sword", "hammer", "axe", "fists"]
const ATTRIBUTES := ["strength", "endurance", "dexterity", "intellect", "willpower", "constitution"]
const CANCEL_INTO := ["light", "heavy", "dodge", "block", "ability", "jump"]
const PHASES := ["windup", "active", "recovery"]
const SIZE_POLICIES := ["attacker_growth", "none"]
const INTERRUPT_POLICIES := ["hard_stagger", "super_armor"]
const INTERACTION_PERMISSIONS := ["grab_small", "throw_boulder", "tree_weapon", "gate_breach",
	"formation_sweep", "siege_disruption", "monster_grapple", "titan_execution"]
const ID_REGEX := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"


## Validates one parsed JSON document.
## Returns {"errors": PackedStringArray, "warnings": PackedStringArray, "refs": Array}.
## refs holds {"ctx", "id", "type"} entries that validate_references() checks later.
static func validate_record(rec: Variant, path: String) -> Dictionary:
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "refs": []}
	if typeof(rec) != TYPE_DICTIONARY:
		out.errors.append("%s: top-level JSON value must be an object" % path)
		return out
	var d: Dictionary = rec
	var ctx := path
	var id_value: Variant = d.get("id")
	if typeof(id_value) == TYPE_STRING:
		ctx = "%s (%s)" % [path, id_value]
		var re := RegEx.create_from_string(ID_REGEX)
		if re.search(id_value) == null:
			out.errors.append("%s: id '%s' must be lowercase dotted form like 'ability.light_1'" % [ctx, id_value])
	var version: Variant = d.get("schema_version")
	if _is_number(version) and int(version) > SUPPORTED_SCHEMA_VERSION:
		out.errors.append("%s: schema_version %d is newer than supported version %d" % [
			ctx, int(version), SUPPORTED_SCHEMA_VERSION])
		return out
	var type_value: Variant = d.get("type")
	if typeof(type_value) != TYPE_STRING or not RECORD_TYPES.has(type_value):
		out.errors.append("%s: 'type' must be one of %s (got %s)" % [ctx, RECORD_TYPES, type_value])
		return out
	_check_fields(d, schema_for(type_value), ctx, out)
	match type_value:
		"action":
			_semantic_action(d, ctx, out)
		"growth_profile":
			_semantic_growth(d, ctx, out)
		"player":
			_semantic_player(d, ctx, out)
		"enemy":
			_semantic_enemy(d, ctx, out)
		"input_bindings":
			_semantic_input(d, ctx, out)
	return out


## Cross-record checks: every reference must exist and point to a record of the right type.
static func validate_references(records: Dictionary, refs: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for ref: Dictionary in refs:
		var target: String = ref.id
		if not records.has(target):
			errors.append("%s: missing reference '%s' (expected a %s record)" % [ref.ctx, target, ref.type])
		elif records[target].get("type") != ref.type:
			errors.append("%s: reference '%s' is a %s, expected %s" % [
				ref.ctx, target, records[target].get("type"), ref.type])
	return errors


# --------------------------------------------------------------------------- schemas

static func _num(min_v: Variant = null, max_v: Variant = null, req := false) -> Dictionary:
	var s := {"t": "number", "req": req}
	if min_v != null:
		s["min"] = min_v
	if max_v != null:
		s["max"] = max_v
	return s


static func _pos(req := false) -> Dictionary:
	return {"t": "number", "gt": 0.0, "req": req}


static func _int(min_v: Variant = null, max_v: Variant = null, req := false) -> Dictionary:
	var s := {"t": "int", "req": req}
	if min_v != null:
		s["min"] = min_v
	if max_v != null:
		s["max"] = max_v
	return s


static func _str(req := false, enum_values: Array = []) -> Dictionary:
	var s := {"t": "string", "req": req}
	if not enum_values.is_empty():
		s["enum"] = enum_values
	return s


static func _ref(type: String, req := false, allow_empty := false) -> Dictionary:
	return {"t": "string", "req": req, "ref": type, "ref_allow_empty": allow_empty}


static func _poise_fields() -> Dictionary:
	return {
		"threshold": _pos(true),
		"recover_per_s": _num(0.0),
		"recover_delay_s": _num(0.0),
		"stagger_s": _pos(),
		"immunity_s": _num(0.0),
	}


static func schema_for(type: String) -> Dictionary:
	var s := {
		"schema_version": _int(1, null, true),
		"id": _str(true),
		"type": _str(true, RECORD_TYPES),
		"display_name": _str(),
		"description": _str(),
	}
	match type:
		"action":
			s.merge({
				"kind": _str(true, ACTION_KINDS),
				"hotbar_label": _str(),
				"power": _num(0.0),
				"damage_type": _str(false, DAMAGE_TYPES),
				"damage_split": {"t": "dict", "keys_enum": DAMAGE_TYPES, "values": _num(0.0, 1.0)},
				"ability_multiplier": _num(0.0),
				"stamina_cost": _num(0.0),
				"essence_cost": _num(0.0),
				"fury_cost": _num(0.0),
				"cooldown_s": _num(0.0),
				"windup_s": _num(0.0),
				"active_s": _num(0.0),
				"recovery_s": _num(0.0),
				"poise_damage": _num(0.0),
				"max_hits_per_target": _int(1),
				"tags": {"t": "array", "items": "string", "items_enum": TAGS},
				"category": _str(false, ATTACK_CATEGORIES),
				"uses_weapon": {"t": "bool"},
				"crit_eligible": {"t": "bool"},
				"size_policy": _str(false, SIZE_POLICIES),
				"flat_penetration": _num(0.0),
				"chain_next": _ref("action", false, true),
				"chain_window_s": _num(0.0),
				"hit_shape": _str(false, HIT_SHAPES),
				"radius_m": _pos(),
				"height_m": _pos(),
				"arc": {"t": "dict", "fields": {
					"windup_yaw_deg": _num(-180.0, 180.0, true),
					"windup_pitch_deg": _num(-89.0, 89.0, true),
					"yaw_start_deg": _num(-180.0, 180.0, true),
					"yaw_end_deg": _num(-180.0, 180.0, true),
					"pitch_start_deg": _num(-89.0, 89.0, true),
					"pitch_end_deg": _num(-89.0, 89.0, true),
				}},
				"cancels": {"t": "array", "items": "dict", "item_fields": {
					"into": {"t": "array", "req": true, "items": "string", "items_enum": CANCEL_INTO},
					"phase": _str(true, PHASES),
					"after_s": _num(0.0),
				}},
				"movement": {"t": "dict", "fields": {
					"windup_speed_mult": _num(0.0),
					"active_speed_mult": _num(0.0),
					"recovery_speed_mult": _num(0.0),
				}},
				"knockback_impulse": _num(0.0),
				"knockback_max_speed": _num(0.0),
				"tracking_fraction": _num(0.0, 1.0),
				"soft_target_max_deg": _num(0.0, 45.0),
				"unlock_stage": _int(1, 10),
				"interrupt_policy": _str(false, INTERRUPT_POLICIES),
				"duration_s": _pos(),
				"move_s": _pos(),
				"iframe_start_s": _num(0.0),
				"iframe_end_s": _num(0.0),
				"distance_m": _num(0.0),
				"parry_window_s": _pos(),
				"parry_extra_stamina": _num(0.0),
				"parry_poise_damage": _num(0.0),
				"coverage_deg": _num(0.0, 360.0),
				"physical_reduction": _num(0.0, 1.0),
				"elemental_reduction": _num(0.0, 1.0),
				"impact_stamina_factor": _num(0.0),
				"guard_break_damage_fraction": _num(0.0, 1.0),
				"guard_break_stagger_s": _num(0.0),
				"move_speed_mult": _num(0.0),
				"velocity_mps": _num(0.0),
				"drain_per_s": _num(0.0),
				"speed_mult": _pos(),
				"resume_threshold": _num(0.0),
			})
		"growth_profile":
			s.merge({
				"stage": _int(1, 10, true),
				"required_level": _int(1, 20, true),
				"height_m": _pos(true),
				"capsule_radius_m": _pos(true),
				"capsule_total_height_m": _pos(true),
				"walk_speed_mps": _pos(true),
				"melee_reach_m": _pos(true),
				"camera_distance_m": _pos(true),
				"camera_zoom_min_m": _pos(true),
				"camera_zoom_max_m": _pos(true),
				"camera_pivot_height_m": _pos(true),
				"camera_shoulder_offset_m": _num(null, null, true),
				"eye_height_ratio": {"t": "number", "gt": 0.0, "max": 1.0, "req": true},
				"acceleration_mps2": _pos(true),
				"turn_rate_deg_s": _pos(true),
				"step_height_m": _num(0.0, null, true),
				"jump_velocity_mps": _num(0.0, null, true),
				"dodge_distance_m": _pos(true),
				"lock_range_m": _pos(true),
				"lock_half_angle_deg": {"t": "number", "gt": 0.0, "max": 180.0, "req": true},
				"weapon_pivot_m": {"t": "vec3", "req": true},
				"attack_origin_m": {"t": "vec3", "req": true},
				"arm_length_m": _pos(true),
				"interaction_permissions": {"t": "array", "items": "string", "items_enum": INTERACTION_PERMISSIONS},
				"unlocks": {"t": "array", "items": "string", "items_ref": "action"},
			})
		"player":
			s.merge({
				"ancestry": _ref("ancestry"),
				"growth_profile": _ref("growth_profile", true),
				"weapon": _ref("weapon", true),
				"attributes": {"t": "dict", "req": true, "keys_enum": ATTRIBUTES, "values": _num(0.0)},
				"resources": {"t": "dict", "req": true, "fields": {
					"health": _pos(true), "stamina": _pos(true), "essence": _num(0.0, null, true),
					"fury_max": _pos(true)}},
				"regen": {"t": "dict", "req": true, "fields": {
					"stamina_per_s": _num(0.0, null, true), "stamina_delay_s": _num(0.0, null, true),
					"essence_per_s": _num(0.0, null, true), "essence_delay_s": _num(0.0, null, true),
					"fury_decay_per_s": _num(0.0, null, true), "fury_decay_delay_s": _num(0.0, null, true)}},
				"fury_gain": {"t": "dict", "req": true, "fields": {
					"basic_attack": _num(0.0, null, true), "parry": _num(0.0, null, true),
					"kill": _num(0.0, null, true)}},
				"poise": {"t": "dict", "req": true, "fields": _poise_fields()},
				"armor": _num(0.0),
				"resistances": {"t": "dict", "keys_enum": DAMAGE_TYPES, "values": _num(-0.5, 0.75)},
				"immunities": {"t": "array", "items": "string", "items_enum": DAMAGE_TYPES + TAGS},
				"crit_chance": _num(0.0, 1.0),
				"crit_multiplier": _num(1.0),
				"stability": _pos(),
				"loadout": {"t": "dict", "req": true, "fields": {
					"light_chain": _ref("action", true),
					"heavy": _ref("action", true),
					"dodge": _ref("action", true),
					"block": _ref("action", true),
					"jump": _ref("action", true),
					"sprint": _ref("action", true),
					"slots": {"t": "array", "req": true, "items": "string", "items_ref": "action",
						"items_ref_allow_empty": true},
					"ultimate": _ref("action", false, true)}},
			})
		"enemy":
			s.merge({
				"archetype": _str(true, ARCHETYPES),
				"height_m": _pos(true),
				"capsule_radius_m": _pos(true),
				"health": _pos(true),
				"stamina": _pos(),
				"guard": {"t": "dict", "fields": {
					"coverage_deg": _num(0.0, 360.0, true),
					"min_stamina": _num(0.0, null, true),
					"turn_rate_deg_s": _pos(true),
					"physical_reduction": _num(0.0, 1.0, true),
					"elemental_reduction": _num(0.0, 1.0, true),
					"impact_stamina_factor": _num(0.0, null, true),
					"guard_break_damage_fraction": _num(0.0, 1.0, true),
					"guard_break_stagger_s": _num(0.0, null, true)}},
				"armor": _num(0.0),
				"resistances": {"t": "dict", "keys_enum": DAMAGE_TYPES, "values": _num(-0.5, 0.75)},
				"immunities": {"t": "array", "items": "string", "items_enum": DAMAGE_TYPES + TAGS},
				"attributes": {"t": "dict", "keys_enum": ATTRIBUTES, "values": _num(0.0)},
				"poise": {"t": "dict", "req": true, "fields": _poise_fields()},
				"stability": _pos(),
				"walk_speed_mps": _pos(true),
				"run_speed_mps": _pos(true),
				"turn_rate_deg_s": _pos(true),
				"weapon": _ref("weapon", true),
				"weapon_pivot_m": {"t": "vec3", "req": true},
				"attack_origin_m": {"t": "vec3", "req": true},
				"arm_length_m": _pos(true),
				"attacks": {"t": "array", "req": true, "items": "string", "items_ref": "action"},
				"attack_weights": {"t": "array", "items": "number"},
				"ai": {"t": "dict", "req": true, "fields": {
					"sight_range_m": _pos(true),
					"sight_half_angle_deg": {"t": "number", "gt": 0.0, "max": 180.0, "req": true},
					"hearing_radius_m": _num(0.0, null, true),
					"memory_s": _num(0.0, null, true),
					"perception_hz": _pos(true),
					"decision_hz": _pos(true),
					"notice_s": _num(0.0, null, true),
					"attack_range_m": _pos(true),
					"engage_distance_m": _pos(true),
					"reposition_radius_m": _pos(true),
					"strike_pause_min_s": _num(0.0, null, true),
					"strike_pause_max_s": _num(0.0, null, true),
					"path_fail_s": _pos(true),
					"patrol_wait_s": _num(0.0, null, true),
					"max_attackers": _int(1, null, true),
					"flee_morale": _num(0.0, 100.0, true),
					"regroup_morale": _num(0.0, 100.0, true)}},
				"morale": _num(0.0, 100.0),
				"threat": _num(0.0, 1.0),
				"lockable": {"t": "bool"},
				"grants_fury": {"t": "bool"},
				"crit_chance": _num(0.0, 1.0),
			})
		"prop":
			s.merge({
				"category": _str(true, PROP_CATEGORIES),
				"height_m": _pos(true),
				"health": _pos(true),
				"armor": _num(0.0),
				"resistances": {"t": "dict", "keys_enum": DAMAGE_TYPES, "values": _num(-0.5, 0.75)},
				"immunities": {"t": "array", "items": "string", "items_enum": DAMAGE_TYPES + TAGS},
				"accepted_attack_categories": {"t": "array", "req": true, "items": "string",
					"items_enum": ATTACK_CATEGORIES},
				"min_growth_stage": _int(1, 10),
				"loot": {"t": "array", "items": "dict", "item_fields": {
					"item": _ref("item", true), "count": _int(1, null, true)}},
				"debris_count": _int(0, 40),
				"unkillable": {"t": "bool"},
				"reset_after_s": _num(0.0),
				"lockable": {"t": "bool"},
				"grants_fury": {"t": "bool"},
				"threat": _num(0.0, 1.0),
				"stability": _pos(),
			})
		"weapon":
			s.merge({
				"family": _str(true, WEAPON_FAMILIES),
				"damage_multiplier": _pos(true),
				"length_m": _pos(true),
				"hit_radius_m": _pos(true),
			})
		"item":
			s.merge({"stack_max": _int(1)})
		"input_bindings":
			s.merge({
				"actions": {"t": "dict", "req": true},
				"deadzones": {"t": "dict", "values": _num(0.0, 1.0)},
			})
	return s


# --------------------------------------------------------------------------- generic checks

static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _check_fields(d: Dictionary, schema: Dictionary, ctx: String, out: Dictionary) -> void:
	for key: String in d.keys():
		if not schema.has(key):
			out.errors.append("%s: unknown key '%s'" % [ctx, key])
	for key: String in schema.keys():
		var spec: Dictionary = schema[key]
		if not d.has(key):
			if spec.get("req", false):
				out.errors.append("%s: missing required key '%s'" % [ctx, key])
			continue
		_check_value(d[key], spec, "%s.%s" % [ctx, key], out)


static func _check_value(v: Variant, spec: Dictionary, ctx: String, out: Dictionary) -> void:
	match spec.t:
		"number", "int":
			if not _is_number(v):
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
				if not _is_number(c):
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
						if not _is_number(item):
							out.errors.append("%s: expected a number" % ictx)
						elif float(item) < 0.0:
							out.errors.append("%s: must be >= 0" % ictx)
					"dict":
						if typeof(item) != TYPE_DICTIONARY:
							out.errors.append("%s: expected an object" % ictx)
						elif spec.has("item_fields"):
							_check_fields(item, spec.item_fields, ictx, out)
				i += 1
		"dict":
			if typeof(v) != TYPE_DICTIONARY:
				out.errors.append("%s: expected an object, got %s" % [ctx, type_string(typeof(v))])
				return
			var dv: Dictionary = v
			if spec.has("fields"):
				_check_fields(dv, spec.fields, ctx, out)
				return
			for k: Variant in dv.keys():
				if spec.has("keys_enum") and not (spec.keys_enum as Array).has(k):
					out.errors.append("%s: unknown key '%s' (allowed: %s)" % [ctx, k, spec.keys_enum])
				if spec.has("values"):
					_check_value(dv[k], spec.values, "%s.%s" % [ctx, k], out)


static func _require(d: Dictionary, keys: Array, ctx: String, out: Dictionary, why: String) -> void:
	for k: String in keys:
		if not d.has(k):
			out.errors.append("%s: '%s' is required for %s" % [ctx, k, why])


static func _check_tick_multiple(d: Dictionary, keys: Array, ctx: String, out: Dictionary) -> void:
	for k: String in keys:
		if d.has(k) and _is_number(d[k]):
			var ticks := float(d[k]) * TICK_RATE
			if absf(ticks - roundf(ticks)) > 0.01:
				out.warnings.append("%s.%s: %s s is not a whole number of 1/60 s ticks; rounded to %d ticks" % [
					ctx, k, d[k], int(roundf(ticks))])


# --------------------------------------------------------------------------- semantic checks

static func _semantic_action(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var kind: String = str(d.get("kind", ""))
	_check_tick_multiple(d, ["windup_s", "active_s", "recovery_s", "duration_s", "move_s",
		"iframe_start_s", "iframe_end_s", "parry_window_s", "chain_window_s"], ctx, out)
	if ATTACK_KINDS.has(kind):
		_require(d, ["power", "damage_type", "ability_multiplier", "stamina_cost", "cooldown_s",
			"windup_s", "active_s", "recovery_s", "poise_damage", "max_hits_per_target", "tags",
			"hit_shape"], ctx, out, "attack kind '%s'" % kind)
		if _is_number(d.get("active_s")) and float(d.active_s) <= 0.0:
			out.errors.append("%s: invalid timing: active_s must be > 0 for attacks" % ctx)
		var shape: String = str(d.get("hit_shape", ""))
		if shape == "weapon_arc" and not d.has("arc"):
			out.errors.append("%s: hit_shape 'weapon_arc' requires an 'arc'" % ctx)
		if shape == "cylinder_pulse":
			_require(d, ["radius_m", "height_m"], ctx, out, "hit_shape 'cylinder_pulse'")
		if kind == "heavy" and typeof(d.get("cancels")) == TYPE_ARRAY:
			for rule: Variant in d.cancels:
				if typeof(rule) == TYPE_DICTIONARY and rule.get("phase") == "active":
					out.errors.append("%s: heavy attacks cannot be cancelled during their active strike" % ctx)
		if d.has("damage_split") and typeof(d.damage_split) == TYPE_DICTIONARY:
			var total := 0.0
			for k: Variant in d.damage_split:
				if _is_number(d.damage_split[k]):
					total += float(d.damage_split[k])
			if absf(total - 1.0) > 0.001:
				out.errors.append("%s: damage_split portions must sum to 1.0 (got %s)" % [ctx, total])
	match kind:
		"dodge":
			_require(d, ["stamina_cost", "duration_s", "move_s", "iframe_start_s", "iframe_end_s",
				"distance_m"], ctx, out, "dodge")
			if _is_number(d.get("iframe_start_s")) and _is_number(d.get("iframe_end_s")):
				if float(d.iframe_start_s) >= float(d.iframe_end_s):
					out.errors.append("%s: invalid timing: iframe_start_s must be < iframe_end_s" % ctx)
				if _is_number(d.get("duration_s")) and float(d.iframe_end_s) > float(d.duration_s):
					out.errors.append("%s: invalid timing: iframe_end_s exceeds duration_s" % ctx)
			if _is_number(d.get("move_s")) and _is_number(d.get("duration_s")) \
					and float(d.move_s) > float(d.duration_s):
				out.errors.append("%s: invalid timing: move_s exceeds duration_s" % ctx)
		"block":
			_require(d, ["stamina_cost", "parry_window_s", "parry_extra_stamina", "parry_poise_damage",
				"coverage_deg", "physical_reduction", "elemental_reduction", "impact_stamina_factor",
				"guard_break_damage_fraction", "guard_break_stagger_s", "move_speed_mult"], ctx, out, "block")
		"jump":
			_require(d, ["velocity_mps"], ctx, out, "jump")
		"sprint":
			_require(d, ["drain_per_s", "speed_mult", "resume_threshold"], ctx, out, "sprint")


static func _semantic_growth(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if _is_number(d.get("capsule_total_height_m")) and _is_number(d.get("capsule_radius_m")):
		if float(d.capsule_total_height_m) < 2.0 * float(d.capsule_radius_m):
			out.errors.append("%s: capsule_total_height_m must be at least twice capsule_radius_m" % ctx)
	if _is_number(d.get("camera_zoom_min_m")) and _is_number(d.get("camera_zoom_max_m")) \
			and _is_number(d.get("camera_distance_m")):
		if not (float(d.camera_zoom_min_m) <= float(d.camera_distance_m)
				and float(d.camera_distance_m) <= float(d.camera_zoom_max_m)):
			out.errors.append("%s: camera_distance_m must lie between camera_zoom_min_m and camera_zoom_max_m" % ctx)


static func _semantic_player(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var loadout: Variant = d.get("loadout")
	if typeof(loadout) == TYPE_DICTIONARY and typeof(loadout.get("slots")) == TYPE_ARRAY:
		if (loadout.slots as Array).size() != 8:
			out.errors.append("%s: loadout.slots must have exactly 8 entries (empty string = empty slot)" % ctx)


static func _semantic_enemy(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if typeof(d.get("attacks")) == TYPE_ARRAY and (d.attacks as Array).is_empty():
		out.errors.append("%s: attacks must list at least one action" % ctx)
	if typeof(d.get("attack_weights")) == TYPE_ARRAY and typeof(d.get("attacks")) == TYPE_ARRAY:
		if (d.attack_weights as Array).size() != (d.attacks as Array).size():
			out.errors.append("%s: attack_weights must have one entry per attack" % ctx)
	var ai: Variant = d.get("ai")
	if typeof(ai) == TYPE_DICTIONARY and _is_number(ai.get("strike_pause_min_s")) \
			and _is_number(ai.get("strike_pause_max_s")):
		if float(ai.strike_pause_min_s) > float(ai.strike_pause_max_s):
			out.errors.append("%s: ai.strike_pause_min_s must be <= ai.strike_pause_max_s" % ctx)


static func _semantic_input(d: Dictionary, ctx: String, out: Dictionary) -> void:
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
