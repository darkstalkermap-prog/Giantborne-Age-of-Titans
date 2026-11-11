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
	# P30 (plan M6-M9 §2.10, decision 19): `formations`, organised groups of the encounter's members
	# (scripts/ai/formation.gd; the director owns one Formation per entry): `id` (unique in the
	# encounter; the formation's id is "<encounter short id>.<id>"), `kind` (line | pike | shield |
	# crew), `display_name` (the lock line's name; by kind when absent), `banner` (the entity id of
	# the spawn carrying its banner, slot -1), `banner_name`, `banner_color` (its flag, RGB 0..1),
	# `min_stage` / `max_stage` (the giant's stages it forms at: its members sit other activations
	# out), `ranks` x `files` slots `rank_spacing_m` / `file_spacing_m` apart around one pivot,
	# `facing` ("threat": it turns toward the giant at turn_deg_s once aware; "fixed"), `yaw_deg` (its
	# facing until then; default its first spawn's yaw), `advance_mps` (how fast it advances on the
	# giant; 0 = it holds its ground) within `advance_m` of its home, `brace_m` (it braces when the
	# giant is this close to its front rank) with `brace_action` (a band_pulse action its focus
	# member runs: one band along the front rank) and `brace_height_m` (the size the brace strikes
	# with: poise and knockback treat it as an attacker this tall; default 5.0), `morale_start` (its
	# members' morale; default 90) and `flee_points` (marker ids its routed members spread over;
	# without them, points 30-60 m away over a 140-degree fan). A spawn's `formation` names its
	# formation and `slot` its place: 0 .. ranks x files - 1, rank-major from the front rank's left
	# file; -1 is the banner.
	f["formations"] = {"t": "array", "items": "dict", "item_fields": {
		"id": U.str_field(true),
		"kind": U.str_field(true, ["line", "pike", "shield", "crew"]),
		"display_name": U.str_field(),
		"banner": U.str_field(),
		"banner_name": U.str_field(),
		"banner_color": U.vec3(),
		"min_stage": U.int_field(0, 10),
		"max_stage": U.int_field(0, 10),
		"ranks": U.int_field(1, 8, true),
		"files": U.int_field(1, 16, true),
		"rank_spacing_m": U.pos(true),
		"file_spacing_m": U.pos(true),
		"facing": U.str_field(false, ["threat", "fixed"]),
		"yaw_deg": U.num(-360.0, 360.0),
		"turn_deg_s": U.pos(),
		"advance_mps": U.num(0.0, 10.0),
		"advance_m": U.num(0.0),
		"brace_m": U.num(0.0, 30.0),
		"brace_action": U.ref("action", false, true),
		"brace_height_m": U.pos(),
		"morale_start": U.num(0.0, 100.0),
		"flee_points": {"t": "array", "items": "string"}}}
	(((f.spawns as Dictionary).item_fields) as Dictionary).merge({
		"formation": U.str_field(),
		"slot": U.int_field(-1, 255),
	})

	## @anchor P32
	# P32 (plan M6-M9 §2.10, §3.16; this anchor is P32's own: the plan's §1.5 table gave the encounter
	# schema none for the `engines` list its §3.16 director edit reads): `engines`, the siege engines the
	# encounter's crews serve - each `engine` names a placed engine by its world id (a SiegeEngine prop of
	# the level's scene or chunk) and `crew` the spawn entity ids of this encounter that serve it (role
	# "crew"; one engine each). The director gives each crew member its engine when both are in the tree.
	f["engines"] = {"t": "array", "items": "dict", "item_fields": {
		"engine": U.str_field(true),
		"crew": {"t": "array", "req": true, "items": "string"}}}

	## @anchor P37
	# P37 (plan M6-M9 §2.13, decision 27): `template` - a wander or world-event template, never active by
	# itself: the WanderDirector has the director make copies of it (EncounterDirector's P37 section) with
	# ids <template id>.<n>, its centre at the anchor chosen and every spawn point moved (and turned)
	# with it. A template's own centre_m is where it is drawn up (the copies keep their offsets from it).
	# A spawn of a template may carry `targets` (P30's target provider for that spawn alone: raiders who
	# burn a settlement's houses and hunt its folk while the giant is not in their way) and `prefer` (a
	# record used instead of `definition` once it exists - a later package's archetype, such as
	# enemy.dire_wolf, without a data change when it lands: a prefer naming no record yet is no error).
	f["template"] = U.bool_field()
	(((f.spawns as Dictionary).item_fields) as Dictionary).merge({
		"targets": {"t": "dict", "fields": {
			"teams": {"t": "array", "items": "string", "items_enum": ["player"]},
			"factions": U.ref_array("faction"),
			"prop_tags": {"t": "array", "items": "string"},
			"priority": U.str_field(false, ["nearest"]),
			"aggro_player_m": U.pos()}},
		"prefer": U.str_field(),
	})

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
	# P30: the formations and their members within the encounter (FormationRules.record_errors: unique
	# plain ids, a stage range that is not empty, every member's formation and slot, one banner; M7
	# gate: in a leashed encounter every formation's reach - slots plus advance_m - inside the leash).
	out.errors.append_array(FormationRules.record_errors(d, ctx))

	## @anchor P32
	# P32: an engine named once, a world id of the dotted form; every crew id is a spawn of this
	# encounter and serves one engine only.
	var p32_engines: Variant = d.get("engines")
	if typeof(p32_engines) == TYPE_ARRAY:
		var p32_spawn_ids := {}
		for sp: Variant in d.get("spawns", []):
			if typeof(sp) == TYPE_DICTIONARY:
				p32_spawn_ids[str(sp.get("entity_id", ""))] = true
		var p32_seen_engines := {}
		var p32_seen_crew := {}
		for i in (p32_engines as Array).size():
			var p32_e: Variant = p32_engines[i]
			var p32_ctx := "%s.engines[%d]" % [ctx, i]
			if typeof(p32_e) != TYPE_DICTIONARY:
				continue
			var p32_id := str(p32_e.get("engine", ""))
			if U.check_id_string(p32_id, p32_ctx + ".engine", out):
				if p32_seen_engines.has(p32_id):
					out.errors.append("%s.engine: engine '%s' is listed twice" % [p32_ctx, p32_id])
				p32_seen_engines[p32_id] = true
			for p32_c: Variant in p32_e.get("crew", []):
				if not p32_spawn_ids.has(str(p32_c)):
					out.errors.append("%s.crew: '%s' is not a spawn of this encounter" % [p32_ctx, p32_c])
				elif p32_seen_crew.has(str(p32_c)):
					out.errors.append("%s.crew: '%s' already serves another engine" % [p32_ctx, p32_c])
				p32_seen_crew[str(p32_c)] = true

	## @anchor P37
	# P37: a spawn's `targets` names at least one team, faction or prop tag (as an enemy record's) and
	# `prefer` is a record id; only a template's spawns use them (a placed encounter's members are their
	# records' own).
	var p37_spawns: Variant = d.get("spawns")
	if typeof(p37_spawns) == TYPE_ARRAY:
		var p37_template := bool(d.get("template", false))
		for i in (p37_spawns as Array).size():
			var p37_sp: Variant = p37_spawns[i]
			if typeof(p37_sp) != TYPE_DICTIONARY:
				continue
			var p37_ctx := "%s.spawns[%d]" % [ctx, i]
			for p37_key: String in ["targets", "prefer"]:
				if p37_sp.has(p37_key) and not p37_template:
					out.errors.append("%s.%s: only a template's spawns take %s (P37)" % [p37_ctx, p37_key, p37_key])
			var p37_targets: Variant = p37_sp.get("targets")
			if typeof(p37_targets) == TYPE_DICTIONARY:
				var p37_kinds := 0
				for p37_key: String in ["teams", "factions", "prop_tags"]:
					if typeof(p37_targets.get(p37_key)) == TYPE_ARRAY:
						p37_kinds += (p37_targets[p37_key] as Array).size()
				if p37_kinds == 0:
					out.errors.append("%s.targets: names no team, faction or prop tag" % p37_ctx)
			if typeof(p37_sp.get("prefer")) == TYPE_STRING and str(p37_sp.prefer) != "":
				U.check_id_string(p37_sp.prefer, p37_ctx + ".prefer", out)


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
