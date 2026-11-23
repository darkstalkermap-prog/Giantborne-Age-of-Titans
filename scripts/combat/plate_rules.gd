class_name PlateRules
extends RefCounted
## Breakable armour plates over weak points (A2): the pure rules of a titan's `plates` record block. No engine
## state: plain values in, plain values out, so the rules are unit-tested alone and a seeded fight repeats.
##
## A titan's enemy record lists its plates (`plates`, an array; the first titan, enemy.stoneback, has eight):
##   id               the plate's id ("shoulder_l"), unique in the record
##   region           the Hurtbox.region it covers ("shoulder_l"); one plate a region
##   piece            the rig's mesh shown while it holds ("plate_shoulder_l": StonebackRig.set_plate_visible)
##   anchor           the lock anchor under the actor's Anchors ("PlateShoulderL"; "" = none)
##   breakable        false: armour only (the forearms, the shins), never breaks
##   health           the stone's own health (a breakable plate), in raw damage (before the body's armour)
##   reduction        the share of a blow the intact plate keeps from the body (0.85: 15 % reaches it)
##   poise_reduction  the same for poise (default: reduction)
##   weak_multiplier  once broken, the region is a weak point: blows there deal this many times as much (and full
##                    poise); 1.0 = only the plate's protection is gone
##   heavy_multiplier blows tagged Heavy crack the stone this many times as fast (default 1.5)
##   break            what its breaking does: {"stagger_s", "debris" (pieces), "cue" (a cue event id)}
##   lock_bias_m      A4: added to the plate's lock score (TitanEnemy.titan_lock_point): below 0 the lock frames it
##                    sooner than a nearer plate (his shins: the legs first, whatever the giant's size)
##   on_break         A4: the break's effect beyond the stagger, {"effect", "down_s", "again_damage"}: "stagger" (the
##                    default: only the break's stagger) or "topple" - the plate holds a leg up (Stoneback's shins):
##                    broken, he goes down on a knee for down_s (his upper body, its hurtboxes and lock anchors lowered
##                    into a smaller giant's reach: TitanEnemy), and once broken every again_damage more health damage
##                    to its region (or the record's topple.again_regions) drops him again (0: never again); B2:
##                    "unbalance" - the plate held his balance (the Ogre King's crown): broken, every later blow's
##                    poise counts poise_mult times (PlateSet.poise_taken_mult) for the rest of the attempt; B3:
##                    "wither" - the plate held the titan's growth (the Rootwarden's root-arm knot): broken, no
##                    plate of his regrows for block_s (their wounds stay open; PlateSet.wither)
##   regrow           B3: the plate grows back (the Rootwarden's living bark): {"after_s", "over_s", "health_frac",
##                    "burn_sears"} - broken, its wound stays open (a weak point) for after_s, then the bark creeps
##                    back over it for over_s (still a weak point) and it is whole again with health_frac of its
##                    health; a wound the titan's fire reaches while it is open (he carries a status tagged
##                    Burning: a smashed brazier beside him, a lightning strike) is seared and never regrows in the
##                    attempt (burn_sears, default true); a withered titan's wounds wait (their clocks stop).
##                    {} or absent: the plate stays broken (Stoneback's stone, the Ogre King's trophies).
## A hit's region is the struck hurtbox's (HitFactory picks one per titan per pulse, see pick_order()); a hit with
## no hurtbox (a lob's landing, a scripted hit) strikes `default_region` ("torso": no plate there).
##
## Every hit on a titan (CombatEntity.plates set): PlateSet.prepare() reads the plate of its region and sets the
## hit's region multipliers (DamageResolver applies them after armour, exactly 1.0 for every other entity, so no
## pinned number moves); the resolver resolves it as ever; PlateSet.absorb() takes the stone's share off an intact
## breakable plate (the hit's raw damage x heavy_multiplier for a Heavy) and breaks it at 0.

const STATE_ARMOURED := "armoured"
const STATE_WEAK := "weak"
const STATE_BODY := ""
const DEFAULT_REGION := "torso"
const DEFAULT_HEAVY_MULT := 1.5
const DEFAULT_STAGGER_S := 2.0
const DEFAULT_DEBRIS := 8
## A4: the effects a plate's break may have (on_break.effect), and a topple's defaults.
const EFFECT_STAGGER := "stagger"
const EFFECT_TOPPLE := "topple"
const EFFECT_UNBALANCE := "unbalance"
const EFFECT_WITHER := "wither"
const ON_BREAK_EFFECTS := [EFFECT_STAGGER, EFFECT_TOPPLE, EFFECT_UNBALANCE, EFFECT_WITHER]
const DEFAULT_WITHER_S := 40.0
## B3: a plate's regrowth's defaults (regrow present).
const REGROW_DEFAULTS := {"after_s": 12.0, "over_s": 6.0, "health_frac": 0.5, "burn_sears": true}
## B3: where a broken plate's wound is (PlateSet.wound_state): open (a weak point, its clock running), regrowing
## (the bark creeping back), seared (burned: it never regrows), "" (whole, or a plate that never regrows).
const WOUND_OPEN := "open"
const WOUND_REGROWING := "regrowing"
const WOUND_SEARED := "seared"
const DEFAULT_DOWN_S := 5.0
const TOPPLE_DEFAULTS := {"kneel_s": 0.8, "rise_s": 1.2, "damage_mult": 1.0, "heavy_mult": 1.0,
	"again_regions": [], "again_immune_s": 10.0, "recover_s": 0.0}


## The record's plates, normalised: every field present (the defaults above), in the record's order.
static func parse(record: Dictionary) -> Array:
	var out: Array = []
	var list: Variant = record.get("plates")
	if typeof(list) != TYPE_ARRAY:
		return out
	for p: Variant in list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = p
		var red := clampf(float(d.get("reduction", 0.0)), 0.0, 1.0)
		var brk: Dictionary = d.get("break", {}) if typeof(d.get("break")) == TYPE_DICTIONARY else {}
		var ob: Dictionary = d.get("on_break", {}) if typeof(d.get("on_break")) == TYPE_DICTIONARY else {}
		out.append({
			"id": str(d.get("id", "")),
			"region": str(d.get("region", d.get("id", ""))),
			"piece": str(d.get("piece", "")),
			"anchor": str(d.get("anchor", "")),
			"breakable": bool(d.get("breakable", true)),
			"health": maxf(0.0, float(d.get("health", 0.0))),
			"reduction": red,
			"poise_reduction": clampf(float(d.get("poise_reduction", red)), 0.0, 1.0),
			"weak_multiplier": maxf(0.0, float(d.get("weak_multiplier", 1.0))),
			"heavy_multiplier": maxf(0.0, float(d.get("heavy_multiplier", DEFAULT_HEAVY_MULT))),
			"stagger_s": maxf(0.0, float(brk.get("stagger_s", DEFAULT_STAGGER_S))),
			"debris": maxi(0, int(brk.get("debris", DEFAULT_DEBRIS))),
			"cue": str(brk.get("cue", "")),
			"lock_bias_m": float(d.get("lock_bias_m", 0.0)),
			"effect": str(ob.get("effect", EFFECT_STAGGER)),
			"down_s": maxf(0.0, float(ob.get("down_s", DEFAULT_DOWN_S))),
			"again_damage": maxf(0.0, float(ob.get("again_damage", 0.0))),
			"poise_mult": maxf(1.0, float(ob.get("poise_mult", 1.0))),
			"block_s": maxf(0.0, float(ob.get("block_s", DEFAULT_WITHER_S))),
			"regrow": parse_regrow(d.get("regrow")),
		})
	return out


## B3: a plate's regrow block with every field present (REGROW_DEFAULTS), {} when the plate never regrows.
static func parse_regrow(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY or (src as Dictionary).is_empty():
		return {}
	var out := REGROW_DEFAULTS.duplicate()
	for k: String in REGROW_DEFAULTS:
		if (src as Dictionary).has(k):
			out[k] = bool(src[k]) if k == "burn_sears" else maxf(0.0, float(src[k]))
	out.health_frac = clampf(float(out.health_frac), 0.05, 1.0)
	out.over_s = maxf(float(out.over_s), 0.1)
	return out


## B3: where a wound stands `open_s` seconds (its clock: the time it was open and not withered) after its plate
## broke, the plate's regrow block `regrow` ({} never): {"state": open | regrowing | "" (grown back), "grow": 0..1
## (how far the bark has come back: 0 open, 1 whole)}. Pure: the clock is the caller's.
static func regrow_at(regrow: Dictionary, open_s: float) -> Dictionary:
	if regrow.is_empty():
		return {"state": WOUND_OPEN, "grow": 0.0}
	var after := float(regrow.get("after_s", 0.0))
	var over := float(regrow.get("over_s", 0.1))
	if open_s < after:
		return {"state": WOUND_OPEN, "grow": 0.0}
	if open_s < after + over:
		var u := (open_s - after) / over
		return {"state": WOUND_REGROWING, "grow": u * u * (3.0 - 2.0 * u)}
	return {"state": "", "grow": 1.0}


## B2: the cues a plate's break plays (CueRouter): its record's break.cue (Stoneback's plates name none: the large
## stone break), and the wood splintering besides for a piece of wood and iron (a "trophy_" piece other than the
## bell's bronze).
static func trophy_cues(plate: Dictionary) -> Array:
	var cue := str(plate.get("cue", ""))
	if cue == "":
		return ["sfx.break.stone.large"]
	var out: Array = [cue]
	var piece := str(plate.get("piece", ""))
	if piece.begins_with("trophy_") and piece != "trophy_bell" and cue != "sfx.break.wood.large":
		out.append("sfx.break.wood.large")
	return out


## B1: what a titan's broken plates give when he dies: each plate of `broken_ids` with a record "loot" list adds its
## items ([{"item", "count"}], the counts of one item summed, in the record's plate order). [] for none.
static func break_loot(record: Dictionary, broken_ids: Array) -> Array:
	var counts := {}
	var order: Array = []
	var list: Variant = record.get("plates")
	for p: Variant in list if typeof(list) == TYPE_ARRAY else []:
		if typeof(p) != TYPE_DICTIONARY or not broken_ids.has(str(p.get("id", ""))):
			continue
		for l: Variant in p.get("loot", []):
			if typeof(l) != TYPE_DICTIONARY:
				continue
			var item := str(l.get("item", ""))
			if item == "":
				continue
			if not counts.has(item):
				order.append(item)
				counts[item] = 0
			counts[item] = int(counts[item]) + maxi(1, int(l.get("count", 1)))
	var out: Array = []
	for item: Variant in order:
		out.append({"item": str(item), "count": int(counts[item])})
	return out


## A4: the record's topple block with every field present (TOPPLE_DEFAULTS), {} when no plate topples him.
static func parse_topple(record: Dictionary) -> Dictionary:
	var any := false
	for p: Dictionary in parse(record):
		any = any or str(p.effect) == EFFECT_TOPPLE
	if not any:
		return {}
	var src: Dictionary = record.get("topple", {}) if typeof(record.get("topple")) == TYPE_DICTIONARY else {}
	var out := TOPPLE_DEFAULTS.duplicate(true)
	for k: String in TOPPLE_DEFAULTS:
		if src.has(k):
			out[k] = src[k] if k == "again_regions" else maxf(0.0, float(src[k]))
	var regions: Array[String] = []
	for r: Variant in out.again_regions:
		regions.append(str(r))
	out.again_regions = regions
	return out


## A4: the down's whole length for a topple plate `plate` and the record's `topple` (parse_topple): the kneel, the
## time on the knee (down_s) and the rise, in seconds.
static func down_total_s(plate: Dictionary, topple: Dictionary) -> float:
	return float(topple.get("kneel_s", 0.0)) + float(plate.get("down_s", DEFAULT_DOWN_S)) + float(topple.get("rise_s", 0.0))


## A4: how far down he is (0 standing .. 1 on the knee) `t` seconds into a down of `total` seconds (the kneel eased
## in over kneel_s, held, the rise eased out over rise_s): his hurtboxes and lock anchors follow it.
static func down_weight(t: float, total: float, topple: Dictionary) -> float:
	if t < 0.0 or t >= total:
		return 0.0
	var k := float(topple.get("kneel_s", 0.0))
	var r := float(topple.get("rise_s", 0.0))
	if t < k:
		var u := t / maxf(k, 1e-6)
		return u * u * (3.0 - 2.0 * u)
	if t > total - r:
		var v := (total - t) / maxf(r, 1e-6)
		return v * v * (3.0 - 2.0 * v)
	return 1.0


## The region a hit strikes: its own, else the record's default (no hurtbox: a landing, a scripted blow).
static func region_of(hit_region: String, default_region: String = DEFAULT_REGION) -> String:
	return hit_region if hit_region != "" else default_region


## What a blow on `plate` ({} for a region without one) does, the plate `broken` or not:
## {"state": armoured | weak | "", "damage_mult", "poise_mult"}. An intact plate keeps its reduction from the body;
## a broken breakable plate exposes the weak point (weak_multiplier, full poise); armour-only plates never break.
static func effect(plate: Dictionary, broken: bool) -> Dictionary:
	if plate.is_empty():
		return {"state": STATE_BODY, "damage_mult": 1.0, "poise_mult": 1.0}
	if broken:
		return {"state": STATE_WEAK, "damage_mult": float(plate.get("weak_multiplier", 1.0)), "poise_mult": 1.0}
	return {"state": STATE_ARMOURED, "damage_mult": 1.0 - float(plate.get("reduction", 0.0)),
		"poise_mult": 1.0 - float(plate.get("poise_reduction", plate.get("reduction", 0.0)))}


## The stone a blow of `raw` raw damage takes off an intact breakable plate (0 for armour only): raw, times
## heavy_multiplier for a blow tagged Heavy.
static func stone_damage(plate: Dictionary, raw: float, tags: PackedStringArray) -> float:
	if plate.is_empty() or not bool(plate.get("breakable", false)) or raw <= 0.0:
		return 0.0
	return raw * (float(plate.get("heavy_multiplier", DEFAULT_HEAVY_MULT)) if tags.has("Heavy") else 1.0)


## The order HitFactory picks a titan's struck hurtbox in, among one pulse's candidates of it: the earliest
## sub-step (the first thing the weapon touches), then the contact (the candidate's point to the hurtbox's
## centre: the hurtbox the weapon passes through most deeply), then the candidate's distance, then the region's
## name. Plain values only: the same candidates always give the same region (no physics order is read).
static func pick_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.substep) != int(b.substep):
		return int(a.substep) < int(b.substep)
	if not is_equal_approx(float(a.contact), float(b.contact)):
		return float(a.contact) < float(b.contact)
	if not is_equal_approx(float(a.distance), float(b.distance)):
		return float(a.distance) < float(b.distance)
	return str(a.region) < str(b.region)


## The record's plate problems (the enemy schema's semantic check): unique ids and regions, a breakable plate
## with health above 0, a weak multiplier on a breakable plate only.
static func errors(record: Dictionary, ctx: String) -> PackedStringArray:
	var out := PackedStringArray()
	var list: Variant = record.get("plates")
	if typeof(list) != TYPE_ARRAY:
		return out
	var ids := {}
	var regions := {}
	for i in (list as Array).size():
		var p: Variant = list[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pctx := "%s.plates[%d]" % [ctx, i]
		var id := str(p.get("id", ""))
		var region := str(p.get("region", id))
		if ids.has(id):
			out.append("%s: duplicate plate id '%s'" % [pctx, id])
		ids[id] = true
		if regions.has(region):
			out.append("%s: region '%s' already has a plate" % [pctx, region])
		regions[region] = true
		var breakable := bool(p.get("breakable", true))
		if breakable and float(p.get("health", 0.0)) <= 0.0:
			out.append("%s: a breakable plate needs health above 0" % pctx)
		if not breakable and float(p.get("weak_multiplier", 1.0)) != 1.0:
			out.append("%s: weak_multiplier only on a breakable plate (armour only never breaks)" % pctx)
		var ob: Variant = p.get("on_break")
		if typeof(ob) == TYPE_DICTIONARY and str(ob.get("effect", EFFECT_STAGGER)) == EFFECT_TOPPLE:
			if not breakable:
				out.append("%s: a topple plate must be breakable" % pctx)
			if float(ob.get("down_s", DEFAULT_DOWN_S)) <= 0.0:
				out.append("%s: a topple needs down_s above 0" % pctx)
		if typeof(ob) == TYPE_DICTIONARY and str(ob.get("effect", EFFECT_STAGGER)) == EFFECT_WITHER:
			if not breakable:
				out.append("%s: a wither plate must be breakable" % pctx)
			if float(ob.get("block_s", DEFAULT_WITHER_S)) <= 0.0:
				out.append("%s: wither needs block_s above 0" % pctx)
		var rg: Variant = p.get("regrow")
		if rg != null and typeof(rg) != TYPE_DICTIONARY:
			out.append("%s: regrow must be a dictionary" % pctx)
		elif typeof(rg) == TYPE_DICTIONARY and not (rg as Dictionary).is_empty():
			if not breakable:
				out.append("%s: only a breakable plate regrows" % pctx)
			for k: String in (rg as Dictionary):
				if not REGROW_DEFAULTS.has(k):
					out.append("%s.regrow: unknown key '%s'" % [pctx, k])
			if float(rg.get("over_s", 1.0)) <= 0.0:
				out.append("%s.regrow: over_s must be above 0" % pctx)
			var hf := float(rg.get("health_frac", 0.5))
			if hf <= 0.0 or hf > 1.0:
				out.append("%s.regrow: health_frac must be in (0, 1]" % pctx)
		if typeof(ob) == TYPE_DICTIONARY and str(ob.get("effect", EFFECT_STAGGER)) == EFFECT_UNBALANCE:
			if not breakable:
				out.append("%s: an unbalance plate must be breakable" % pctx)
			if float(ob.get("poise_mult", 1.0)) <= 1.0:
				out.append("%s: unbalance needs poise_mult above 1" % pctx)
	var top: Variant = record.get("topple")
	if typeof(top) == TYPE_DICTIONARY:
		for r: Variant in top.get("again_regions", []):
			if not regions.has(str(r)):
				out.append("%s.topple.again_regions: '%s' is no plate's region" % [ctx, str(r)])
	return out
