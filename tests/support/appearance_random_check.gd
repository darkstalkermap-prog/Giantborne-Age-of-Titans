extends RefCounted
## The random-record check shared by tests/unit/test_appearance_record.gd (6 seeds a scope, the default
## tier) and tests/slow/test_appearance_random.gd (1,000 seeds a scope; plan M10 §3.2): every scope of
## Appearance.random_record from `base` for a giant of `line` gives a record that sanitize() keeps as it is
## (nothing dropped, nothing noted: no unknown and no locked option), never a tattoo or war paint where
## the outfit hides it, the outfit kept by "all" with keep_outfit, the mark's choice kept; and Sim.rng is
## never touched.

## {"count": records checked, "error": the first problem ("" when none)}.
static func run(seeds: int, base: Dictionary, line: String) -> Dictionary:
	var n := 0
	var sim_before := Sim.rng.state
	var rng := RandomNumberGenerator.new()
	var base_outfit: Variant = base.get("outfit")
	for scope: String in Appearance.RANDOM_SCOPES:
		for seed in seeds:
			rng.seed = seed * 7919 + scope.hash()
			var keep := seed % 2 == 0
			var r := Appearance.random_record(rng, scope, keep, line, base)
			var s := Appearance.sanitize(r, line)
			if not ((s.dropped as PackedStringArray).is_empty() and (s.notes as PackedStringArray).is_empty()):
				return {"count": n, "error": "%s seed %d: not valid (%s / %s)" % [scope, seed, s.dropped, s.notes]}
			if scope in ["tattoos", "paint", "all"]:
				var covered := Appearance.covered_regions(r)
				for region: String in Appearance.DESIGN_REGIONS:
					if covered.has(region) and str(r.tattoos[region]) != "":
						return {"count": n, "error": "%s seed %d: a tattoo where the outfit hides it (%s)" % [scope, seed,
							region]}
				var paint := str(r.paint.design)
				if paint != "" and covered.has(str(Appearance.option(paint).get("region", ""))):
					return {"count": n, "error": "%s seed %d: war paint where the outfit hides it" % [scope, seed]}
			if scope == "all" and keep and base_outfit != null and str(r.outfit) != str(base_outfit):
				return {"count": n, "error": "all seed %d: the outfit changed with keep_outfit" % seed}
			if scope != "presets" and str(r.mark) != str(base.get("mark", Appearance.MARK_AUTO)):
				return {"count": n, "error": "%s seed %d: the mark's choice is the player's" % [scope, seed]}
			n += 1
	if Sim.rng.state != sim_before:
		return {"count": n, "error": "random_record moved Sim.rng"}
	return {"count": n, "error": ""}
