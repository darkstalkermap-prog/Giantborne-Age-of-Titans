class_name FormationRules
extends RefCounted
## The data checks of encounter formations (plan M6-M9 §2.10, decision 19; P30): kept apart from
## Formation (scripts/ai/formation.gd), which needs the actors, so that the encounter schema - loaded
## with GameData at start-up - depends on nothing but SchemaUtil.

const BANNER_SLOT := -1
## Encounters of one level whose centres lie this close count as one cluster for the caps.
const CLUSTER_M := 150.0
## The caps when a level record names none (plan §2.10: desktop 40, web 20; EncounterDirector's).
const DESKTOP_CAP := 40
const WEB_CAP := 20
## The giant's stages the caps are checked at.
const STAGES := 6


## The errors of an encounter record's formations (encounter_schema.gd calls it): ids unique plain
## words, a stage range that is not empty, a flee point list of ids; every spawn's formation is one
## of them, its slot inside the grid and not shared, the banner's slot -1 and named by its
## formation's `banner`, at most one banner each; a formation needs at least one member.
static func record_errors(enc: Dictionary, ctx: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var forms: Variant = enc.get("formations")
	var by_id := {}
	if typeof(forms) == TYPE_ARRAY:
		var i := 0
		for f: Variant in forms:
			var fctx := "%s.formations[%d]" % [ctx, i]
			i += 1
			if typeof(f) != TYPE_DICTIONARY:
				continue
			var fid := str(f.get("id", ""))
			if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(fid) == null:
				errors.append("%s.id: '%s' must be a plain lowercase word like 'pikes'" % [fctx, fid])
			elif by_id.has(fid):
				errors.append("%s.id: duplicate formation id '%s'" % [fctx, fid])
			by_id[fid] = f
			if SchemaUtil.is_number(f.get("min_stage")) and SchemaUtil.is_number(f.get("max_stage")) \
					and int(f.min_stage) > int(f.max_stage):
				errors.append("%s: min_stage (%s) is above max_stage (%s)" % [fctx, f.min_stage, f.max_stage])
			if typeof(f.get("flee_points")) == TYPE_ARRAY:
				var ids_out := {"errors": PackedStringArray()}
				for p: Variant in f.flee_points:
					SchemaUtil.check_id_string(p, fctx + ".flee_points", ids_out)
				errors.append_array(ids_out.errors)
			if str(f.get("brace_action", "")) != "" and not (SchemaUtil.is_number(f.get("brace_m")) and float(f.brace_m) > 0.0):
				errors.append("%s: a brace_action needs brace_m > 0" % fctx)
	var spawns: Variant = enc.get("spawns")
	var members := {}       # formation id -> member count
	var used := {}          # "<formation>/<slot>" -> entity id
	var banners := {}       # formation id -> entity id of its slot -1 spawn
	if typeof(spawns) == TYPE_ARRAY:
		var i := 0
		for s: Variant in spawns:
			var sctx := "%s.spawns[%d]" % [ctx, i]
			i += 1
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var fid := str(s.get("formation", ""))
			if fid == "":
				if s.has("slot"):
					errors.append("%s: a slot needs a formation" % sctx)
				continue
			if not by_id.has(fid):
				errors.append("%s.formation: '%s' is not a formation of this encounter" % [sctx, fid])
				continue
			if not SchemaUtil.is_number(s.get("slot")):
				errors.append("%s: a member of formation '%s' needs its slot" % [sctx, fid])
				continue
			var f: Dictionary = by_id[fid]
			var slot := int(s.slot)
			var count := int(f.get("ranks", 1)) * int(f.get("files", 1))
			if slot == BANNER_SLOT:
				if banners.has(fid):
					errors.append("%s: formation '%s' has a second banner" % [sctx, fid])
				banners[fid] = str(s.get("entity_id", ""))
			elif slot < 0 or slot >= count:
				errors.append("%s.slot: %d is outside formation '%s' (%d slots)" % [sctx, slot, fid, count])
			else:
				var key := "%s/%d" % [fid, slot]
				if used.has(key):
					errors.append("%s.slot: slot %d of formation '%s' is also %s's" % [sctx, slot, fid, used[key]])
				used[key] = str(s.get("entity_id", ""))
				members[fid] = int(members.get(fid, 0)) + 1
	for fid: String in by_id:
		var f: Dictionary = by_id[fid]
		var named := str(f.get("banner", ""))
		if int(members.get(fid, 0)) == 0:
			errors.append("%s: formation '%s' has no member (spawns with formation '%s' and a slot)" % [ctx, fid, fid])
		if named != "" and str(banners.get(fid, "")) != named:
			errors.append("%s: formation '%s' names banner '%s', which is not its spawn with slot -1" % [ctx, fid, named])
		if named == "" and banners.has(fid):
			errors.append("%s: formation '%s' has a slot -1 spawn but names no banner" % [ctx, fid])
	return errors


## The cross-record errors of formations (GameData's post-pass, its anchor P30): a formation's
## banner spawn is a record of role `banner` and its rank and file are not; and around every
## encounter with formations, the formation members of its level's encounters within CLUSTER_M of
## it - those that form at the giant's stage, for every stage 1..STAGES - fit the level's
## max_formation_members on the desktop and its web_overrides' value on the web (each formation's
## web composition: web_kept_slots at its encounter's web_formation_scale).
static func cross_record_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var by_level := {}   # level id -> Array of encounter records with formations
	for id: String in records:
		var enc: Dictionary = records[id]
		if str(enc.get("type", "")) != "encounter" or typeof(enc.get("formations")) != TYPE_ARRAY \
				or (enc.formations as Array).is_empty():
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		errors.append_array(_role_errors(enc, records, ctx))
		var lv := str(enc.get("level", ""))
		if not by_level.has(lv):
			by_level[lv] = []
		(by_level[lv] as Array).append(enc)
	for lv: String in by_level:
		var level: Dictionary = records.get(lv, {})
		var desktop := int(level.get("max_formation_members", DESKTOP_CAP))
		var web_over: Variant = level.get("web_overrides")
		var web := int((web_over as Dictionary).get("max_formation_members", WEB_CAP)) \
			if typeof(web_over) == TYPE_DICTIONARY else WEB_CAP
		var encs: Array = by_level[lv]
		encs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
		for enc: Dictionary in encs:
			var center := _center(enc)
			for stage in range(1, STAGES + 1):
				var on_desktop := 0
				var on_web := 0
				var near := PackedStringArray()
				for other: Dictionary in encs:
					if _center(other).distance_to(center) > CLUSTER_M:
						continue
					var counts := member_counts(other, stage)
					if counts[0] > 0:
						near.append(str(other.id))
					on_desktop += counts[0]
					on_web += counts[1]
				if on_desktop > desktop:
					errors.append("%s (%s): at stage %d its cluster (%s, within %d m) has %d formation members, over the level's max_formation_members %d" % [
						record_paths.get(enc.id, "?"), enc.id, stage, ", ".join(near), int(CLUSTER_M), on_desktop, desktop])
				if on_web > web:
					errors.append("%s (%s): at stage %d its cluster (%s, within %d m) keeps %d formation members on the web, over the web's max_formation_members %d (lower web_formation_scale)" % [
						record_paths.get(enc.id, "?"), enc.id, stage, ", ".join(near), int(CLUSTER_M), on_web, web])
	return errors


## [desktop, web] formation members of `enc` at the giant's `stage`: the spawns of its formations
## that form at that stage (the formation's and the spawn's own stage ranges), and of those the
## web composition at its web_formation_scale.
static func member_counts(enc: Dictionary, stage: int) -> Array:
	var scale := clampf(float(enc.get("web_formation_scale", 1.0)), 0.0, 1.0) \
		if SchemaUtil.is_number(enc.get("web_formation_scale")) else 1.0
	var desktop := 0
	var web := 0
	for f: Variant in enc.get("formations", []):
		if typeof(f) != TYPE_DICTIONARY or not stage_allows(f, stage):
			continue
		var slots: Array = []
		for s: Variant in enc.get("spawns", []):
			if typeof(s) == TYPE_DICTIONARY and str(s.get("formation", "")) == str(f.get("id", "")) \
					and SchemaUtil.is_number(s.get("slot")) and stage_allows(s, stage):
				slots.append(int(s.slot))
		desktop += slots.size()
		web += web_kept_slots(slots, scale).size() if scale < 1.0 else slots.size()
	return [desktop, web]


## True when a formation entry or a spawn admits `stage` (min_stage / max_stage; absent = any).
## The same rule as EncounterDirector.stage_allows.
static func stage_allows(entry: Dictionary, stage: int) -> bool:
	if stage <= 0:
		return true
	if SchemaUtil.is_number(entry.get("min_stage")) and stage < int(entry.min_stage):
		return false
	if SchemaUtil.is_number(entry.get("max_stage")) and stage > int(entry.max_stage):
		return false
	return true


## The spawns of one formation that a web build keeps at `scale` (plan §2.10: front rank and banner
## first): the banner, then the slots in order (the front rank first) up to round(members x scale),
## at least one. `slots` lists the members' slots (BANNER_SLOT for the banner). Returns the kept
## slots, in order. Pure.
static func web_kept_slots(slots: Array, scale: float) -> Array:
	var rank_and_file: Array = []
	var has_banner := false
	for s: Variant in slots:
		if int(s) == BANNER_SLOT:
			has_banner = true
		else:
			rank_and_file.append(int(s))
	rank_and_file.sort()
	var keep := clampi(int(roundf(float(rank_and_file.size()) * clampf(scale, 0.0, 1.0))), mini(1, rank_and_file.size()),
		rank_and_file.size())
	var out: Array = []
	if has_banner:
		out.append(BANNER_SLOT)
	out.append_array(rank_and_file.slice(0, keep))
	return out


## A banner spawn's record is of role banner; a rank-and-file member's is not.
static func _role_errors(enc: Dictionary, records: Dictionary, ctx: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var i := 0
	for s: Variant in enc.get("spawns", []):
		i += 1
		if typeof(s) != TYPE_DICTIONARY or str(s.get("formation", "")) == "" or not SchemaUtil.is_number(s.get("slot")):
			continue
		var def: Dictionary = records.get(str(s.get("definition", "")), {})
		if def.is_empty():
			continue   # the encounter's own cross-record check reports an unknown definition
		var role := str(def.get("role", ""))
		if int(s.slot) == BANNER_SLOT and role != "banner":
			errors.append("%s.spawns[%d]: the banner of formation '%s' is %s, whose role is '%s', not 'banner'" % [
				ctx, i - 1, s.formation, s.definition, role])
		elif int(s.slot) != BANNER_SLOT and role == "banner":
			errors.append("%s.spawns[%d]: %s (role banner) stands in slot %d of formation '%s': a banner takes slot -1" % [
				ctx, i - 1, s.definition, int(s.slot), s.formation])
	return errors


static func _center(enc: Dictionary) -> Vector3:
	var c: Variant = enc.get("center_m")
	if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3:
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	return Vector3.ZERO
