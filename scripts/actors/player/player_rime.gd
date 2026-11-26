class_name PlayerRime
extends PlayerComponent
## D1 (decision D1-2): the cold on the giant - rime, a frost that builds on his body and slows him until it freezes
## him fast. The `rime` component of GiantPlayer.COMPONENTS.
##
## Rime is 0..RIME_MAX. It builds from the Frostbound Titan's blows and his breath (an action's `rime` parameter: the
## amount each hit adds, half when blocked), from his cold when he wakes it (TitanEnemy's cold aura: add_rime every
## tick within its reach) and from wading in a tarn's open water (IceSheet: WADE_RIME_PER_S). How much of it takes
## hold depends on the giant: a big body keeps its heat (RIME_TAKEN_BY_STAGE: a stage-6 giant takes 1.5 x, stage 7
## the rule, stage 8 0.6 x) and the Frostbound set's ice (the passive `rime_taken_mult`).
##
## What it does: he moves slower as it builds (RIME_SLOW_AT_FULL of his speed lost at full: the motor's "rime"
## multiplier). Full, he is frozen fast for FREEZE_S: barely able to move (FROZEN_SPEED_MULT), no dodge, no jump, no
## sprint - only a heavy blow, begun while frozen, shatters the ice off him at once (it is a giant's way out: brute
## force); then the rime falls back to AFTER_FREEZE.
##
## It goes: by itself after DECAY_DELAY_S without more (DECAY_PER_S), fast beside a fire (a WarmthSource: a balefire on
## the tarn's shore, the Hearth's fires; WARM_DECAY_PER_S), and in chunks off his own heavy blows that land
## (HEAVY_SHED). It is never saved: a reload, a death or a travel thaws him.

const RIME_MAX := 100.0
const RIME_SLOW_AT_FULL := 0.45
const FREEZE_S := 2.2
const AFTER_FREEZE := 55.0
const FROZEN_SPEED_MULT := 0.08
const DECAY_DELAY_S := 2.5
const DECAY_PER_S := 4.0
const WARM_DECAY_PER_S := 30.0
const HEAVY_SHED := 12.0
const WADE_RIME_PER_S := 3.5
const WADE_SPEED_MULT := 0.65
## A blocked blow's rime: this share of the blow's.
const BLOCKED_SHARE := 0.5
## The share of the rime that takes hold on a giant of each growth stage (a bigger body keeps its heat).
const RIME_TAKEN_BY_STAGE := {1: 2.4, 2: 2.4, 3: 2.2, 4: 2.0, 5: 1.8, 6: 1.5, 7: 0.85, 8: 0.55, 9: 0.45, 10: 0.35}
const FROZEN_EDGES := [&"dodge", &"jump", &"sprint_press"]
const FROZEN_TEXT := "Frozen fast! A heavy blow will shatter the ice."

var rime := 0.0
## The tick the freeze ends (-1: not frozen), the tick of the last gain, freezes and shatters this life (tests, HUD).
var frozen_until := -1
var last_gain_tick := -100000
var freezes := 0
var shatters := 0
## Rime gained and shed this life by source (tests, the duel report): {"hit": .., "aura": .., "wade": ..}.
var gained := {}
var shed := {}
## True while he stands in a tarn's open water (IceSheet) / beside a fire (WarmthSource), this tick.
var wading := false
var warm := false
var _emitted := -1.0


func edge_priority() -> int:
	return 8


func setup(p: GiantPlayer) -> void:
	super(p)
	if not Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.connect(_on_hit_resolved)
	p.entity.hit_landed.connect(_on_hit_landed)


func on_exit() -> void:
	if Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.disconnect(_on_hit_resolved)


func is_frozen() -> bool:
	return frozen_until >= 0 and Sim.tick < frozen_until


func fraction() -> float:
	return clampf(rime / RIME_MAX, 0.0, 1.0)


## The share of rime that takes hold on him now: his stage's (RIME_TAKEN_BY_STAGE) times his armour's passive.
func taken_mult() -> float:
	var stage := int(player.growth_stage)
	var m := float(RIME_TAKEN_BY_STAGE.get(clampi(stage, 1, 10), 1.0))
	if player.entity != null and player.entity.combatant != null:
		m *= player.entity.combatant.modifier("rime_taken_mult")
	return m


## Adds `amount` of raw rime (before his stage and armour): returns the rime that took hold. `source` names it in
## the tallies ("hit", "aura", "wade", ...). Frozen, he takes no more (the ice is already on him).
func add_rime(amount: float, source := "hit") -> float:
	if amount <= 0.0 or player.entity == null or not player.entity.is_alive() or is_frozen():
		return 0.0
	var took := amount * taken_mult()
	rime = minf(RIME_MAX, rime + took)
	last_gain_tick = Sim.tick
	gained[source] = float(gained.get(source, 0.0)) + took
	if rime >= RIME_MAX - 1e-3:
		_freeze()
	_announce()
	return took


## Sheds `amount` of rime (a fire, a heavy blow): returns what went.
func shed_rime(amount: float, source := "warm") -> float:
	if amount <= 0.0 or rime <= 0.0:
		return 0.0
	var went := minf(rime, amount)
	rime -= went
	shed[source] = float(shed.get(source, 0.0)) + went
	_announce()
	return went


func _freeze() -> void:
	freezes += 1
	frozen_until = Sim.tick + ActionDef.seconds_to_ticks(FREEZE_S)
	if player.controller != null and player.controller.action != null and player.controller.action.has_tag("Dodge"):
		player.controller.call("_finish_action", true)
	player.motor.set_speed_mult(&"rime_frozen", FROZEN_SPEED_MULT)
	player.entity.apply_status("status.frozen_fast", NAN, FREEZE_S, "rime")
	Events.rime_frozen.emit(Sim.tick, player.entity.entity_id, FREEZE_S)
	Events.hud_message.emit(FROZEN_TEXT, "warn")


func _thaw(shattered: bool) -> void:
	if frozen_until < 0:
		return
	frozen_until = -1
	rime = minf(rime, AFTER_FREEZE)
	player.motor.set_speed_mult(&"rime_frozen", 1.0)
	if player.entity != null:
		player.entity.combatant.statuses.remove("status.frozen_fast")
	if shattered:
		shatters += 1
	Events.rime_thawed.emit(Sim.tick, player.entity.entity_id, shattered)
	_announce()


func handle_edge(edge: StringName) -> bool:
	if is_frozen() and edge in FROZEN_EDGES:
		return true
	return false


func on_action_started(action: ActionDef, _instance_id: int) -> void:
	# a heavy blow begun while frozen fast shatters the ice off him
	if is_frozen() and action != null and action.has_tag("Heavy"):
		_thaw(true)


## A heavy blow of his that lands sheds rime (the ice cracks off him with the effort).
func _on_hit_landed(result: HitResult) -> void:
	if result == null or result.event == null or rime <= 0.0:
		return
	var a := GameData.get_action(result.event.action_id)
	if a != null and a.has_tag("Heavy"):
		shed_rime(HEAVY_SHED, "heavy")


## A blow with a `rime` parameter that struck him adds its rime (half when he blocked it).
func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or player == null or player.entity == null:
		return
	if r.event.target_id != player.entity.entity_id:
		return
	var a := GameData.get_action(r.event.action_id)
	if a == null:
		return
	var amount := float(a.param("rime", 0.0))
	if amount <= 0.0:
		return
	var blocked := r.outcome == HitResult.Outcome.BLOCKED
	add_rime(amount * (BLOCKED_SHARE if blocked else 1.0), "hit")


func post_movement(_tick: int, dt: float) -> void:
	if player.entity == null or not player.entity.is_alive():
		if rime > 0.0 or frozen_until >= 0:
			_thaw(false)
			rime = 0.0
			player.motor.set_speed_mult(&"rime", 1.0)
			player.motor.set_speed_mult(&"wading", 1.0)
			_announce()
		return
	if frozen_until >= 0 and Sim.tick >= frozen_until:
		_thaw(false)
	var pos := player.global_position
	var tree := player.get_tree() if player.is_inside_tree() else null
	warm = tree != null and WarmthSource.warm_at(tree, pos)
	var sheet := IceSheet.sheet_at(tree, pos) if tree != null else null
	wading = sheet != null and sheet.state_at(pos) == IceSheet.OPEN
	player.motor.set_speed_mult(&"wading", WADE_SPEED_MULT if wading else 1.0)
	if wading:
		add_rime(WADE_RIME_PER_S * dt, "wade")
	if warm:
		shed_rime(WARM_DECAY_PER_S * dt, "warm")
	elif Sim.tick - last_gain_tick >= ActionDef.seconds_to_ticks(DECAY_DELAY_S):
		shed_rime(DECAY_PER_S * dt, "time")
	player.motor.set_speed_mult(&"rime", 1.0 - RIME_SLOW_AT_FULL * fraction())


func _announce() -> void:
	if absf(rime - _emitted) < 0.5 and not (rime == 0.0 and _emitted != 0.0):
		return
	_emitted = rime
	Events.rime_changed.emit(Sim.tick, player.entity.entity_id, rime)


func rig_state(out: Dictionary) -> void:
	if rime > 0.0 or is_frozen():
		out["rime"] = fraction()
		out["frozen"] = is_frozen()


func debug_info(out: Dictionary) -> void:
	if rime > 0.0 or is_frozen():
		out["rime"] = "%.0f%s%s" % [rime, " FROZEN" if is_frozen() else "", " (wading)" if wading else ""]
