class_name PlateSet
extends RefCounted
## A titan's plates in a fight (A2): the record's plates (PlateRules.parse) and their state - each breakable
## plate's stone health and whether it is broken. CombatEntity.plates holds it (TitanEnemy sets it); CombatEntity
## calls prepare() before a hit resolves and absorb() after, in the Sim's hit order, so a seeded fight breaks the
## same plates on the same ticks. No engine state, no RNG.

## The record's plates in its order (PlateRules.parse).
var plates: Array = []
## Region -> index into plates.
var by_region: Dictionary = {}
## Plate id -> index into plates.
var by_id: Dictionary = {}
## Plate id -> the stone health left (breakable plates).
var health: Dictionary = {}
## Plate id -> true once broken.
var broken: Dictionary = {}
## The plates broken, in order (tests, debug, the phases).
var break_order: Array[String] = []
var default_region := PlateRules.DEFAULT_REGION
## A4: while the titan is down on a knee (TitanEnemy sets them, 1 standing): every blow's region multipliers are
## multiplied by down_mult, a Heavy's by down_heavy_mult besides (a blow on a kneeling titan is decisive).
var down_mult := 1.0
var down_heavy_mult := 1.0
## B2: an "unbalance" plate broken (the Ogre King's crown): every later blow's poise counts this many times
## (TitanEnemy multiplies it in; a new attempt resets it to 1).
var poise_taken_mult := 1.0


static func from_record(record: Dictionary) -> PlateSet:
	var s := PlateSet.new()
	s.plates = PlateRules.parse(record)
	s.default_region = str(record.get("plate_default_region", PlateRules.DEFAULT_REGION))
	for i in s.plates.size():
		var p: Dictionary = s.plates[i]
		s.by_region[str(p.region)] = i
		s.by_id[str(p.id)] = i
	s.reset()
	return s


## Every plate whole again (a new attempt).
func reset() -> void:
	health.clear()
	broken.clear()
	break_order.clear()
	poise_taken_mult = 1.0
	for p: Dictionary in plates:
		if bool(p.breakable):
			health[str(p.id)] = float(p.health)


func is_empty() -> bool:
	return plates.is_empty()


func plate(id: String) -> Dictionary:
	return plates[by_id[id]] if by_id.has(id) else {}


func plate_for_region(region: String) -> Dictionary:
	var r := PlateRules.region_of(region, default_region)
	return plates[by_region[r]] if by_region.has(r) else {}


func is_broken(id: String) -> bool:
	return bool(broken.get(id, false))


func broken_count() -> int:
	return break_order.size()


## The stone health left of plate `id` as a share of its own (1 for armour only, 0 once broken).
func health_frac(id: String) -> float:
	var p := plate(id)
	if p.is_empty() or not bool(p.breakable):
		return 1.0
	return clampf(float(health.get(id, 0.0)) / maxf(float(p.health), 1e-6), 0.0, 1.0)


## The breakable plates still intact, in record order.
func intact_breakable() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in plates:
		if bool(p.breakable) and not is_broken(str(p.id)):
			out.append(str(p.id))
	return out


## Sets the hit's plate fields before it resolves: plate_id, plate_state and the region multipliers
## (PlateRules.effect). A titan's hurtboxes carry no weak_point flag: its weak points are its broken plates.
func prepare(hit: HitEvent) -> void:
	var p := plate_for_region(hit.region)
	var fx := PlateRules.effect(p, is_broken(str(p.get("id", ""))))
	hit.plate_id = str(p.get("id", ""))
	hit.plate_state = str(fx.state)
	hit.region_damage_mult = float(fx.damage_mult)
	hit.region_poise_mult = float(fx.poise_mult)
	hit.weak_point = false
	if down_mult != 1.0 or down_heavy_mult != 1.0:
		var k := down_mult * (down_heavy_mult if hit.tags.has("Heavy") else 1.0)
		hit.region_damage_mult *= k
		hit.region_poise_mult *= k
	if poise_taken_mult != 1.0:
		hit.region_poise_mult *= poise_taken_mult


## After resolution: an intact breakable plate struck by a landed blow (HIT) loses its share of stone
## (PlateRules.stone_damage) and breaks at 0. Returns {} when no plate was struck, else {"plate": id,
## "state": the hit's plate_state, "stone": the stone taken, "left": the stone left, "broken": true on the
## blow that broke it}.
func absorb(result: HitResult) -> Dictionary:
	var hit := result.event
	if hit == null or hit.plate_id == "":
		return {}
	var id := hit.plate_id
	var out := {"plate": id, "state": hit.plate_state, "stone": 0.0, "left": float(health.get(id, 0.0)),
		"broken": false}
	if result.outcome != HitResult.Outcome.HIT or hit.plate_state != PlateRules.STATE_ARMOURED or is_broken(id):
		return out
	var p := plate(id)
	var stone := PlateRules.stone_damage(p, result.raw_damage, hit.tags)
	if stone <= 0.0:
		return out
	var left := maxf(0.0, float(health.get(id, 0.0)) - stone)
	health[id] = left
	out.stone = stone
	out.left = left
	if left <= 1e-6:
		broken[id] = true
		break_order.append(id)
		out.broken = true
	return out


## Breaks plate `id` at once (tests, debug, a scripted break); false when it is not breakable or already broken.
func force_break(id: String) -> bool:
	var p := plate(id)
	if p.is_empty() or not bool(p.breakable) or is_broken(id):
		return false
	health[id] = 0.0
	broken[id] = true
	break_order.append(id)
	return true


## {plate id: {"health": left, "broken": bool}} (tests, the determinism check, debug).
func snapshot() -> Dictionary:
	var out := {}
	for p: Dictionary in plates:
		var id := str(p.id)
		out[id] = {"health": snappedf(float(health.get(id, -1.0)), 0.001), "broken": is_broken(id)}
	return out
