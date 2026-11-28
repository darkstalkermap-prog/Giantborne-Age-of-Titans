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
## E2: the Cinder Titan's molten crust (CinderEnemy): while he is hot every blow's damage, and a plate's stone, take
## this share (1.0 for every other titan and for him quenched: no pinned number moves).
var heat_mult := 1.0
## B2: an "unbalance" plate broken (the Ogre King's crown): every later blow's poise counts this many times
## (TitanEnemy multiplies it in; a new attempt resets it to 1).
var poise_taken_mult := 1.0
## B1/B3: every plate broken in this attempt, once each in the order of its first break - the loot's (a plate that
## regrew still counts: it was broken).
var ever_broken: Array[String] = []
## B3: the wounds of broken plates that regrow ({plate id: {"open_ticks": the ticks its clock ran, "state": open |
## regrowing | seared, "grow": 0..1}}), and the tick until which no wound's clock runs (a "wither" plate broke).
var wounds: Dictionary = {}
var withered_until := -1
## B3: the plates that grew back in this attempt, in order (tests, the report).
var regrown: Array[String] = []
## C2: the guard (a plate with a guard block: the Broken Warden's wall-shield; PlateRules.parse_guard). TitanEnemy sets
## guard_up, guard_origin and guard_forward every tick (the guard is up while the shield is whole and he can raise it);
## prepare() sends a blow it catches onto the shield, absorb() fills the meter and reports its break. The titan's
## height scales a blow's poise as the resolver does (CombatRules.poise_scale).
var guard_plate := ""
var guard: Dictionary = {}
var guard_up := false
var guard_origin := Vector3.ZERO
var guard_forward := Vector3.FORWARD
var guard_meter := 0.0
var guard_last_tick := -1000000
var height_m := 10.0
## C2: the blows the guard caught and the guard's breaks this attempt (tests, the report).
var guarded_hits := 0
var guard_breaks := 0


static func from_record(record: Dictionary) -> PlateSet:
	var s := PlateSet.new()
	s.plates = PlateRules.parse(record)
	s.default_region = str(record.get("plate_default_region", PlateRules.DEFAULT_REGION))
	s.height_m = float(record.get("height_m", 10.0))
	for i in s.plates.size():
		var p: Dictionary = s.plates[i]
		s.by_region[str(p.region)] = i
		s.by_id[str(p.id)] = i
		if s.guard_plate == "" and not (p.get("guard", {}) as Dictionary).is_empty():
			s.guard_plate = str(p.id)
			s.guard = p.guard
	s.reset()
	return s


## Every plate whole again (a new attempt).
func reset() -> void:
	health.clear()
	broken.clear()
	break_order.clear()
	ever_broken.clear()
	wounds.clear()
	regrown.clear()
	withered_until = -1
	poise_taken_mult = 1.0
	guard_meter = 0.0
	guard_last_tick = -1000000
	guarded_hits = 0
	guard_breaks = 0
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
	if catches(hit):
		# C2: the guard caught it - the blow lands on the shield whatever it touched
		hit.guarded = true
		hit.region = str(plate(guard_plate).region)
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
	if heat_mult != 1.0:
		hit.region_damage_mult *= heat_mult


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
	if hit.guarded and result.outcome == HitResult.Outcome.HIT:
		_fill_guard(hit, out)
	if result.outcome != HitResult.Outcome.HIT or hit.plate_state != PlateRules.STATE_ARMOURED or is_broken(id):
		return out
	var p := plate(id)
	var stone := PlateRules.stone_damage(p, result.raw_damage, hit.tags) * heat_mult
	if stone <= 0.0:
		return out
	var left := maxf(0.0, float(health.get(id, 0.0)) - stone)
	health[id] = left
	out.stone = stone
	out.left = left
	if left <= 1e-6:
		_mark_broken(id)
		out.broken = true
	return out


# --------------------------------------------------------------------------- C2: the guard

## C2: whether the guard is up and catches `hit` (PlateRules.guard_catches from the blow's attacker and point; never a
## blow already on the shield's own region, never once the shield is broken).
func catches(hit: HitEvent) -> bool:
	if not guard_up or guard_plate == "" or is_broken(guard_plate) or hit == null:
		return false
	return PlateRules.guard_catches(guard, guard_origin, guard_forward, hit.attacker_position, hit.hit_point)


## C2: a caught blow's poise into the guard's meter (PlateRules.guard_fill; the poise as the resolver scales it, the
## unbalance's multiplier with it); a full meter breaks the guard: {"guarded", "meter" (0..1 after), "guard_broken"}
## into `out`.
func _fill_guard(hit: HitEvent, out: Dictionary) -> void:
	guarded_hits += 1
	var poise := hit.poise_damage * hit.outgoing_poise_mult * CombatRules.poise_scale(hit.attacker_height_m, height_m)
	guard_meter += PlateRules.guard_fill(guard, poise, hit.tags) * poise_taken_mult
	guard_last_tick = hit.tick
	out["guarded"] = true
	if guard_meter >= float(guard.get("meter", 200.0)):
		guard_meter = 0.0
		guard_breaks += 1
		out["guard_broken"] = true
	out["meter"] = clampf(guard_meter / float(guard.get("meter", 200.0)), 0.0, 1.0)


## C2: the guard's meter drains (regen_per_s) once regen_delay_s passed without a blow filling it (every tick).
func guard_step(tick: int) -> void:
	if guard.is_empty() or guard_meter <= 0.0:
		return
	if tick - guard_last_tick < ActionDef.seconds_to_ticks(float(guard.get("regen_delay_s", 2.0))):
		return
	guard_meter = maxf(0.0, guard_meter - float(guard.get("regen_per_s", 20.0)) / float(Sim.TICK_RATE))


## C2: the guard's meter as a share of its break (0..1; the HUD, tests).
func guard_frac() -> float:
	return clampf(guard_meter / float(guard.get("meter", 1.0)), 0.0, 1.0) if not guard.is_empty() else 0.0


## A plate breaks: the break order, the loot's list, its wound when it regrows.
func _mark_broken(id: String) -> void:
	broken[id] = true
	break_order.append(id)
	if not ever_broken.has(id):
		ever_broken.append(id)
	if not (plate(id).get("regrow", {}) as Dictionary).is_empty():
		wounds[id] = {"open_ticks": 0, "state": PlateRules.WOUND_OPEN, "grow": 0.0}


# --------------------------------------------------------------------------- B3: regrowth

## B3: a "wither" plate broke at `tick`: no wound's clock runs for `seconds` (the longest wither wins).
func wither(tick: int, seconds: float) -> void:
	withered_until = maxi(withered_until, tick + ActionDef.seconds_to_ticks(seconds))


func is_withered(tick: int) -> bool:
	return tick < withered_until


## B3: plate `id`'s wound: "open", "regrowing", "seared" or "" (whole, or a plate that never regrows).
func wound_state(id: String) -> String:
	return str((wounds.get(id, {}) as Dictionary).get("state", ""))


## B3: how far plate `id`'s bark has grown back over its wound (0 open .. 1 whole; 1 for an intact plate).
func grow_of(id: String) -> float:
	if not is_broken(id):
		return 1.0
	return float((wounds.get(id, {}) as Dictionary).get("grow", 0.0))


## B3: one tick of the wounds (TitanEnemy, every tick): `burning` - the titan carries a status tagged Burning (a
## wound open or regrowing then is seared: it never regrows in this attempt, if its regrow block's burn_sears);
## while withered no clock runs. A wound whose regrowth completes is whole again: unbroken, with its regrow
## block's health_frac of its health, out of the break order. Returns {"regrowing": [ids that began to regrow],
## "regrown": [ids whole again], "seared": [ids seared]} in plate order (plain values: a seeded fight repeats).
func regrow_step(tick: int, burning: bool) -> Dictionary:
	var out := {"regrowing": [], "regrown": [], "seared": []}
	if wounds.is_empty():
		return out
	var withered := is_withered(tick)
	for p: Dictionary in plates:
		var id := str(p.id)
		if not wounds.has(id):
			continue
		var w: Dictionary = wounds[id]
		var rg: Dictionary = p.get("regrow", {})
		if str(w.state) == PlateRules.WOUND_SEARED:
			continue
		if burning and bool(rg.get("burn_sears", true)):
			w.state = PlateRules.WOUND_SEARED
			w.grow = 0.0
			out.seared.append(id)
			continue
		if withered:
			continue
		w.open_ticks = int(w.open_ticks) + 1
		var at := PlateRules.regrow_at(rg, float(w.open_ticks) / float(Sim.TICK_RATE))
		var before := str(w.state)
		w.grow = float(at.grow)
		if str(at.state) == "":
			_regrow(id)
			out.regrown.append(id)
		else:
			w.state = str(at.state)
			if before != PlateRules.WOUND_REGROWING and str(at.state) == PlateRules.WOUND_REGROWING:
				out.regrowing.append(id)
	return out


## Plate `id` whole again after its regrowth (its regrow block's share of its health).
func _regrow(id: String) -> void:
	var p := plate(id)
	broken.erase(id)
	break_order.erase(id)
	wounds.erase(id)
	health[id] = float(p.health) * float((p.get("regrow", {}) as Dictionary).get("health_frac", 0.5))
	regrown.append(id)


## B3: sears plate `id`'s open wound now (tests, a scripted burn); false when it has none to sear.
func sear(id: String) -> bool:
	if not wounds.has(id) or wound_state(id) == PlateRules.WOUND_SEARED:
		return false
	wounds[id].state = PlateRules.WOUND_SEARED
	wounds[id].grow = 0.0
	return true


## Breaks plate `id` at once (tests, debug, a scripted break); false when it is not breakable or already broken.
func force_break(id: String) -> bool:
	var p := plate(id)
	if p.is_empty() or not bool(p.breakable) or is_broken(id):
		return false
	health[id] = 0.0
	_mark_broken(id)
	return true


## {plate id: {"health": left, "broken": bool}} (tests, the determinism check, debug).
func snapshot() -> Dictionary:
	var out := {}
	for p: Dictionary in plates:
		var id := str(p.id)
		out[id] = {"health": snappedf(float(health.get(id, -1.0)), 0.001), "broken": is_broken(id)}
		if wounds.has(id):
			out[id]["wound"] = wound_state(id)
			out[id]["grow"] = snappedf(grow_of(id), 0.001)
	if guard_plate != "":
		out["_guard"] = {"meter": snappedf(guard_meter, 0.001), "hits": guarded_hits, "breaks": guard_breaks}
	return out
