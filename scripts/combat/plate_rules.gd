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
		})
	return out


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
	return out
