extends RefCounted
## Schema module for "encounter" records (P10a; plan §2.8.3): a group of actors the
## EncounterDirector spawns from data near its centre, with stable entity ids.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "encounter.forest_wolves_a", "type": "encounter", "level": "level.valley",
##    "district": "forest", "center_m": [-142, 0, 55], "activate_radius_m": 55, "deactivate_radius_m": 110,
##    "leash_radius_m": 50, "alert_group": true, "requires_flags": [], "forbids_flags": [],
##    "counts_toward_budget": true,
##    "spawns": [{"entity_id": "valley.forest.wolf_a1", "definition": "enemy.wolf", "position_m": [-150, 0, 50],
##                "yaw_deg": 90, "patrol": "valley.patrol.wolves_a", "faction": "", "commander": false,
##                "ai_enabled": true, "persist_death": true, "loot_table": ""}]}
##
## Defaults (the EncounterDirector applies them when a key is absent): district "",
## leash_radius_m 0 (no leash: the boss, held by its arena gate), alert_group true,
## requires_flags / forbids_flags [], counts_toward_budget true; per spawn: yaw_deg 0, patrol "",
## faction "", commander false, ai_enabled true, persist_death true, loot_table "" (the
## record's own table).
##
## `definition` must name an enemy or npc record. References are exact-type, so that check,
## the uniqueness of spawn entity ids across encounters and the district (one of the level's
## districts) are cross-record checks: cross_record_errors(), run by the GameData post-pass.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const LEVEL := preload("res://scripts/core/schemas/level_schema.gd")

## Record types a spawn's definition may name (npc arrives with P11b).
const DEFINITION_TYPES := ["enemy", "npc"]


static func fields() -> Dictionary:
	var f := {
		"level": U.ref("level", true),
		"district": U.str_field(),
		"center_m": U.vec3(true),
		# The encounter activates when the player comes this close to its centre (horizontal)...
		"activate_radius_m": U.pos(true),
		# ... and its living members are despawned once the player is farther than this and no
		# member has been aware of the player for 10 s.
		"deactivate_radius_m": U.pos(true),
		# A member farther than this from the centre walks home (0 = no leash).
		"leash_radius_m": U.num(0.0),
		# Members share awareness: when one notices the player, the others do too.
		"alert_group": U.bool_field(),
		"requires_flags": {"t": "array", "items": "string"},
		"forbids_flags": {"t": "array", "items": "string"},
		# Members whose definition is an enemy count toward the level's max_active_enemies.
		"counts_toward_budget": U.bool_field(),
		"spawns": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"entity_id": U.str_field(true),
			"definition": U.str_field(true),
			"position_m": U.vec3(true),
			"yaw_deg": U.num(-360.0, 360.0),
			# A patrol route id: the level's Markers/Patrol/<route> node ("" = none).
			"patrol": U.str_field(),
			"faction": U.str_field(),
			"commander": U.bool_field(),
			"ai_enabled": U.bool_field(),
			"persist_death": U.bool_field(),
			"loot_table": U.ref("loot_table", false, true)}},
	}
	# M6-M9 (P20, plan M6-M9 §2.10, §2.12): `stand_down_when` is a quest condition; while it holds
	# the encounter's members stand down (P29 implements it at its director anchor).
	# `web_formation_scale` (0..1) scales each formation's files on the web (P30 applies it).
	f.merge({
		"stand_down_when": {"t": "any"},
		"web_formation_scale": U.num(0.0, 1.0),
	})
	# Later packages add their fields (a spawn's fields: f.spawns.item_fields) below their anchor.
	## @anchor P24b
	# P24b (plan M6-M9 §2.8, decision 15): `arena` (an arena boss's encounter: held by its arena and
	# its disengage rule, the one kind of world encounter that needs no leash - GameData's leash rule)
	# and a spawn entry's `min_stage` / `max_stage` (the giant's growth stages it spawns at; checked at
	# each activation; absent = any).
	f["arena"] = U.bool_field()
	(((f.spawns as Dictionary).item_fields) as Dictionary).merge({
		"min_stage": U.int_field(0, 10),
		"max_stage": U.int_field(0, 10),
	})

	## @anchor P29

	## @anchor P30

	## @anchor P37

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if U.is_number(d.get("activate_radius_m")) and U.is_number(d.get("deactivate_radius_m")) \
			and float(d.deactivate_radius_m) <= float(d.activate_radius_m):
		out.errors.append("%s: deactivate_radius_m must be greater than activate_radius_m" % ctx)
	for key: String in ["requires_flags", "forbids_flags"]:
		var flags: Variant = d.get(key)
		if typeof(flags) == TYPE_ARRAY:
			var i := 0
			for f: Variant in flags:
				U.check_flag_id(f, "%s.%s[%d]" % [ctx, key, i], out)
				i += 1
	var district: Variant = d.get("district")
	if typeof(district) == TYPE_STRING and district != "" \
			and RegEx.create_from_string(LEVEL.DISTRICT_ID_REGEX).search(district) == null:
		out.errors.append("%s.district: '%s' must be a plain lowercase district id like 'forest'" % [ctx, district])
	check_spawns(d.get("spawns"), ctx, out)
	# M6-M9 (P20): stand_down_when is one condition (plan §2.12 shapes).
	if d.has("stand_down_when") and d.stand_down_when != null:
		U.check_condition(d.stand_down_when, ctx + ".stand_down_when", out)
	## @anchor P24b
	# P24b: a spawn's stage range is not empty.
	var p24b_spawns: Variant = d.get("spawns")
	if typeof(p24b_spawns) == TYPE_ARRAY:
		for i in (p24b_spawns as Array).size():
			var sp: Variant = p24b_spawns[i]
			if typeof(sp) == TYPE_DICTIONARY and U.is_number(sp.get("min_stage")) and U.is_number(sp.get("max_stage")) \
					and int(sp.min_stage) > int(sp.max_stage):
				out.errors.append("%s.spawns[%d]: min_stage (%s) is above max_stage (%s)" % [ctx, i, sp.min_stage, sp.max_stage])

	## @anchor P29

	## @anchor P30

	## @anchor P37


## The spawn list: at least one member, ids unique within the encounter and in the id form, a
## definition and a patrol id in the id form.
static func check_spawns(spawns: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(spawns) != TYPE_ARRAY:
		return
	if (spawns as Array).is_empty():
		out.errors.append("%s: spawns must list at least one member" % ctx)
	var seen := {}
	var i := 0
	for s: Variant in spawns:
		var sctx := "%s.spawns[%d]" % [ctx, i]
		i += 1
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var entity_id: Variant = s.get("entity_id")
		if typeof(entity_id) == TYPE_STRING and U.check_id_string(entity_id, sctx + ".entity_id", out):
			if seen.has(entity_id):
				out.errors.append("%s.entity_id: duplicate spawn entity_id '%s' in this encounter" % [sctx, entity_id])
			seen[entity_id] = true
		var definition: Variant = s.get("definition")
		if typeof(definition) == TYPE_STRING:
			U.check_id_string(definition, sctx + ".definition", out)
		var patrol: Variant = s.get("patrol")
		if typeof(patrol) == TYPE_STRING and patrol != "":
			U.check_id_string(patrol, sctx + ".patrol", out)


static func required_ids() -> Dictionary:
	return {}


## Cross-record checks (the GameData post-pass, plan §2.8.1 / §3.10), over every loaded record:
##   * a spawn entity_id is used by one encounter only ("Duplicate spawn entity_id '…'");
##   * a spawn's definition is an enemy or npc record;
##   * a non-empty district is one of the level's districts.
## Returns the error lines (empty when everything holds).
static func cross_record_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var first_use := {}   # entity_id -> encounter id
	var ids: Array = []
	for id: Variant in records:
		var rec: Variant = records[id]
		if typeof(rec) == TYPE_DICTIONARY and rec.get("type") == "encounter":
			ids.append(str(id))
	ids.sort()
	for enc_id: String in ids:
		var rec: Dictionary = records[enc_id]
		var ctx := "%s (%s)" % [record_paths.get(enc_id, enc_id), enc_id]
		var level: Variant = records.get(str(rec.get("level", "")))
		var district: Variant = rec.get("district", "")
		if typeof(district) == TYPE_STRING and district != "" and typeof(level) == TYPE_DICTIONARY \
				and level.get("type") == "level":
			var known := LEVEL.district_ids(level)
			if not known.has(district):
				errors.append("%s: district '%s' is not a district of %s (known: %s)" % [ctx, district,
					rec.get("level"), ", ".join(known)])
		var spawns: Variant = rec.get("spawns")
		if typeof(spawns) != TYPE_ARRAY:
			continue
		var i := 0
		for s: Variant in spawns:
			var sctx := "%s.spawns[%d]" % [ctx, i]
			i += 1
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var entity_id: Variant = s.get("entity_id")
			if typeof(entity_id) == TYPE_STRING and entity_id != "":
				if first_use.has(entity_id) and first_use[entity_id] != enc_id:
					errors.append("%s: Duplicate spawn entity_id '%s' (also spawned by %s)" % [sctx,
						entity_id, first_use[entity_id]])
				elif not first_use.has(entity_id):
					first_use[entity_id] = enc_id
			var definition: Variant = s.get("definition")
			if typeof(definition) != TYPE_STRING:
				continue
			var def_rec: Variant = records.get(definition)
			if typeof(def_rec) != TYPE_DICTIONARY:
				errors.append("%s.definition: missing reference '%s' (expected an enemy or npc record)" % [sctx, definition])
			elif not DEFINITION_TYPES.has(def_rec.get("type")):
				errors.append("%s.definition: '%s' is a %s, expected an enemy or npc record" % [sctx,
					definition, def_rec.get("type")])
	return errors
