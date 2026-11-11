class_name SiegeRules
extends RefCounted
## The data rules of siege engines and their crews (P32, plan M6-M9 §2.10, §3.16), kept apart from
## SiegeEngine so that GameData's post-pass - run at start-up - does not pull the actors in (as P30's
## FormationRules). Pure: records in, error lines out.

## The engine's projectile visual that a giant's throw must fly (the engine itself rides it).
const THROW_VISUAL := "engine"


## Cross-record checks (the GameData post-pass, anchor P32):
##   * an engine prop's `action` is a projectile enemy attack, and its `throw_action` flies the engine
##     (projectile visual "engine");
##   * every crew member an encounter's `engines` list names is a spawn whose definition has role
##     "crew", and every spawn of a crew definition serves an engine of its encounter.
static func data_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, id), id]
		match str(rec.get("type", "")):
			"prop":
				out.append_array(_engine_errors(rec, records, ctx))
			"encounter":
				out.append_array(_crew_errors(rec, records, ctx))
	return out


static func _engine_errors(rec: Dictionary, records: Dictionary, ctx: String) -> PackedStringArray:
	var out := PackedStringArray()
	var eng: Variant = rec.get("engine")
	if typeof(eng) != TYPE_DICTIONARY:
		return out
	var shot: Variant = records.get(str(eng.get("action", "")))
	if typeof(shot) == TYPE_DICTIONARY and (str(shot.get("hit_shape", "")) != "projectile"
			or str(shot.get("kind", "")) != "enemy_attack"):
		out.append("%s: its engine.action %s is not a projectile enemy attack" % [ctx, eng.get("action")])
	var throw_id := str(eng.get("throw_action", ""))
	var throw: Variant = records.get(throw_id)
	if throw_id != "" and typeof(throw) == TYPE_DICTIONARY:
		var proj: Variant = throw.get("projectile", {})
		var visual := str((proj as Dictionary).get("visual", "")) if typeof(proj) == TYPE_DICTIONARY else ""
		if str(throw.get("hit_shape", "")) != "projectile" or visual != THROW_VISUAL:
			out.append("%s: its engine.throw_action %s does not fly the engine (a projectile of visual '%s')" % [
				ctx, throw_id, THROW_VISUAL])
	return out


static func _crew_errors(rec: Dictionary, records: Dictionary, ctx: String) -> PackedStringArray:
	var out := PackedStringArray()
	var served := {}
	for entry: Variant in rec.get("engines", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for c: Variant in entry.get("crew", []):
			served[str(c)] = str(entry.get("engine", ""))
	for sp: Variant in rec.get("spawns", []):
		if typeof(sp) != TYPE_DICTIONARY:
			continue
		var def: Variant = records.get(str(sp.get("definition", "")))
		var is_crew := typeof(def) == TYPE_DICTIONARY and str(def.get("role", "")) == "crew"
		var eid := str(sp.get("entity_id", ""))
		if is_crew and not served.has(eid):
			out.append("%s: the siege crew %s serves no engine of the encounter (engines)" % [ctx, eid])
		elif served.has(eid) and not is_crew:
			out.append("%s: %s serves engine %s but its definition %s is not a crew (role 'crew')" % [ctx,
				eid, served[eid], sp.get("definition")])
	return out
