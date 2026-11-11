class_name BossRules
extends RefCounted
## P34's data rules (plan M6-M9 §2.10, §5.13): pure, so GameData's post-pass (anchor P34) can run
## them at start-up without loading the actors (as P30's FormationRules and P32's SiegeRules).
##
##   * a yield's dialogue offers both decisions - a choice with outcome "spare" and one with outcome
##     "strike" (the yield prompt needs them; nothing else can decide the outcome);
##   * a brood's definition can be carried (its grab_attach is not "none") and its throw action is a
##     projectile that flies the body (visual thrown_body);
##   * a boss phase's hazard is an action with an arena_hazard block;
##   * a regeneration's status carries the tag Regeneration (the router's regrowth cue and the tint
##     follow it).

const YIELD_OUTCOMES := ["spare", "strike"]


## Every error of the P34 rules over `records` (id -> record); paths give the file of each id.
static func data_errors(records: Dictionary, paths: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in records:
		var rec: Dictionary = records[id]
		if str(rec.get("type", "")) != "enemy":
			continue
		var where := "%s (%s)" % [id, str(paths.get(id, "?"))]
		var y: Variant = rec.get("yield_at")
		if typeof(y) == TYPE_DICTIONARY:
			var d: Dictionary = records.get(str(y.get("dialogue", "")), {})
			var found := dialogue_outcomes(d)
			for o: String in YIELD_OUTCOMES:
				if not found.has(o):
					out.append("%s: yield_at.dialogue %s offers no choice with outcome '%s'" % [where,
						str(y.get("dialogue", "")), o])
		var brood: Variant = rec.get("brood")
		if typeof(brood) == TYPE_DICTIONARY:
			var child: Dictionary = records.get(str(brood.get("definition", "")), {})
			if str(child.get("grab_attach", "none")) == "none":
				out.append("%s: brood.definition %s cannot be carried (grab_attach none)" % [where,
					str(brood.get("definition", ""))])
			var throw: Dictionary = records.get(str(brood.get("throw_action", "")), {})
			var proj: Variant = throw.get("projectile")
			if str(throw.get("hit_shape", "")) != "projectile" or typeof(proj) != TYPE_DICTIONARY \
					or str((proj as Dictionary).get("visual", "")) != "thrown_body":
				out.append("%s: brood.throw_action %s must be a projectile of visual thrown_body" % [where,
					str(brood.get("throw_action", ""))])
		var boss: Variant = rec.get("boss")
		if typeof(boss) == TYPE_DICTIONARY:
			for ph: Variant in boss.get("phases", []):
				if typeof(ph) != TYPE_DICTIONARY or str(ph.get("hazard", "")) == "":
					continue
				var h: Dictionary = records.get(str(ph.hazard), {})
				if typeof(h.get("arena_hazard")) != TYPE_DICTIONARY:
					out.append("%s: phase %s's hazard %s has no arena_hazard block" % [where,
						str(ph.get("id", "")), str(ph.hazard)])
		var regen: Variant = rec.get("regeneration")
		if typeof(regen) == TYPE_DICTIONARY:
			var st: Dictionary = records.get(str(regen.get("status", "")), {})
			if not (st.get("tags", []) as Array).has("Regeneration"):
				out.append("%s: regeneration.status %s lacks the tag Regeneration" % [where, str(regen.get("status", ""))])
	return out


## The outcomes a dialogue record's choices can give (any node).
static func dialogue_outcomes(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for n: Variant in d.get("nodes", []):
		if typeof(n) != TYPE_DICTIONARY:
			continue
		for c: Variant in n.get("choices", []):
			if typeof(c) != TYPE_DICTIONARY or typeof(c.get("effects")) != TYPE_DICTIONARY:
				continue
			var o := str((c.effects as Dictionary).get("outcome", ""))
			if o != "" and not out.has(o):
				out.append(o)
	return out
