class_name PlayerHeat
extends PlayerComponent
## E2 (decision E2-2): the Cinder Titan's heat on the giant. The `heat` component of GiantPlayer.COMPONENTS.
##
## Heat is 0..HEAT_MAX. It builds from the Cinder Titan's fire (CinderEnemy adds it: his blows' `heat`, standing in his
## burning ground, his furnace's breath near him in his later phases, striking his molten crust bare-handed). How much
## of it takes hold depends on the giant: the flames stand a few metres off the ground, so a bigger body has more of
## itself above them (HEAT_TAKEN_BY_STAGE: a stage-8 giant takes the rule, stage 9 0.7 x) and the Cinder set's slag
## (the passive `heat_taken_mult`).
##
## What it does: full, he is ABLAZE - the fire has caught him and he burns (CinderEnemy strikes him with its scorch
## every second, the titan's hit) until his heat is back down to ABLAZE_UNTIL. Nothing else: no slow, no lock - the
## meter is the whole warning.
##
## It goes: by itself a while after the last gain (DECAY_DELAY_S, DECAY_PER_S), and fast in water (any StormWater:
## WATER_SHED_PER_S at WATER_FULL_M deep or more, less in the shallows) - wade the stream, or the dammed water. It is
## never saved: a reload, a death or a travel cools him.

const HEAT_MAX := 100.0
## Ablaze at HEAT_MAX, until the heat is back down to this.
const ABLAZE_UNTIL := 45.0
const DECAY_DELAY_S := 1.5
const DECAY_PER_S := 6.0
## In water: this much a second at WATER_FULL_M deep or more (a share of it in the shallows, from WATER_FROM_M).
const WATER_SHED_PER_S := 42.0
const WATER_FULL_M := 2.0
const WATER_FROM_M := 0.4
## The share of the heat that takes hold on a giant of each growth stage (the flames stand a few metres high).
const HEAT_TAKEN_BY_STAGE := {1: 2.4, 2: 2.3, 3: 2.2, 4: 2.0, 5: 1.85, 6: 1.65, 7: 1.3, 8: 1.0, 9: 0.7, 10: 0.55}
const ABLAZE_TEXT := "Ablaze! Get into the water, or out of his fire."

var heat := 0.0
## Ablaze (the tick it caught, -1 not), the tick of the last gain, the times he caught fire this life (tests, HUD).
var ablaze_since := -1
var last_gain_tick := -100000
var ignitions := 0
## Heat gained and shed this life by source (tests, the duel report): {"hit": .., "burn": .., "aura": .., ...}.
var gained := {}
var shed := {}
## True while he stands in water deep enough to cool him (this tick), and how deep.
var wading := false
var water_m := 0.0
var _emitted := -1.0


func edge_priority() -> int:
	return 6


func is_ablaze() -> bool:
	return ablaze_since >= 0


func fraction() -> float:
	return clampf(heat / HEAT_MAX, 0.0, 1.0)


## The share of heat that takes hold on him now: his stage's (HEAT_TAKEN_BY_STAGE) times his armour's passive.
func taken_mult() -> float:
	var stage := int(player.growth_stage)
	var m := float(HEAT_TAKEN_BY_STAGE.get(clampi(stage, 1, 10), 1.0))
	if player.entity != null and player.entity.combatant != null:
		m *= player.entity.combatant.modifier("heat_taken_mult")
	return m


## Adds `amount` of raw heat (before his stage and armour): returns the heat that took hold. `source` names it in the
## tallies ("hit", "burn", "aura", "crust").
func add_heat(amount: float, source := "hit") -> float:
	if amount <= 0.0 or player.entity == null or not player.entity.is_alive():
		return 0.0
	var took := amount * taken_mult()
	heat = minf(HEAT_MAX, heat + took)
	last_gain_tick = Sim.tick
	gained[source] = float(gained.get(source, 0.0)) + took
	if heat >= HEAT_MAX - 1e-3 and not is_ablaze():
		ablaze_since = Sim.tick
		ignitions += 1
		Events.heat_ablaze.emit(Sim.tick, player.entity.entity_id, true)
		Events.hud_message.emit(ABLAZE_TEXT, "warn")
	_announce()
	return took


## Sheds `amount` of heat: returns what went.
func shed_heat(amount: float, source := "time") -> float:
	if amount <= 0.0 or heat <= 0.0:
		return 0.0
	var went := minf(heat, amount)
	heat -= went
	shed[source] = float(shed.get(source, 0.0)) + went
	if is_ablaze() and heat <= ABLAZE_UNTIL:
		ablaze_since = -1
		Events.heat_ablaze.emit(Sim.tick, player.entity.entity_id, false)
	_announce()
	return went


## The cooling a body gets from water `depth` m deep (a share of WATER_SHED_PER_S a second; 0 on dry ground).
static func water_shed(depth: float) -> float:
	if depth < WATER_FROM_M:
		return 0.0
	return WATER_SHED_PER_S * clampf(depth / WATER_FULL_M, 0.25, 1.0)


func post_movement(_tick: int, dt: float) -> void:
	if player.entity == null or not player.entity.is_alive():
		if heat > 0.0 or is_ablaze():
			heat = 0.0
			if is_ablaze():
				ablaze_since = -1
				Events.heat_ablaze.emit(Sim.tick, player.entity.entity_id if player.entity != null else "", false)
			_announce()
		return
	var tree := player.get_tree() if player.is_inside_tree() else null
	water_m = StormWater.depth_at(tree, player.global_position) if tree != null else 0.0
	wading = water_m >= WATER_FROM_M
	if heat <= 0.0:
		return
	if wading:
		shed_heat(water_shed(water_m) * dt, "water")
	elif Sim.tick - last_gain_tick >= ActionDef.seconds_to_ticks(DECAY_DELAY_S):
		shed_heat(DECAY_PER_S * dt, "time")


func _announce() -> void:
	if absf(heat - _emitted) < 0.5 and not (heat == 0.0 and _emitted != 0.0):
		return
	_emitted = heat
	if player.entity != null:
		Events.heat_changed.emit(Sim.tick, player.entity.entity_id, heat)


func rig_state(out: Dictionary) -> void:
	if heat > 0.0:
		out["heat"] = fraction()
		out["ablaze"] = is_ablaze()


func debug_info(out: Dictionary) -> void:
	if heat > 0.0:
		out["heat"] = "%.0f%s%s" % [heat, " ABLAZE" if is_ablaze() else "", " (wading)" if wading else ""]
