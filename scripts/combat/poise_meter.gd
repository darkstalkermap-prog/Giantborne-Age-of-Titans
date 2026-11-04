class_name PoiseMeter
extends RefCounted
## Poise accumulation (spec section 7): damage fills the meter; at the threshold the owner
## staggers and the meter resets. Recovers after a delay. While staggered and for a short
## immunity period afterwards, further poise damage is ignored, preventing stun-locks.

## Timers accumulate 1/60 s steps; compare with a tolerance so 90 ticks == 1.5 s exactly.
const TIME_EPSILON := 1e-6

var threshold := 100.0
var value := 0.0
var recover_per_s := 20.0
var recover_delay_s := 3.0
var stagger_s := 1.0
var immunity_s := 1.5
var locked := false            ## true while the owner is staggered
var immunity_left := 0.0
var since_damage := 999.0
## Poise damage taken during the owner's own attack RECOVERY phase is multiplied by this
## (ogre and boss 3.5: the "recovery punish"). Applied by CombatEntity.
var recovery_mult := 1.0
## Stagger length when the attacker is at least twice the owner's height (< 0 = stagger_s), so
## a grab after a heavy lands reliably. Chosen by CombatEntity via stagger_duration().
var stagger_vs_larger_s := -1.0


func configure(cfg: Dictionary, constitution := 10.0) -> void:
	threshold = float(cfg.get("threshold", threshold)) + 3.0 * maxf(0.0, constitution - 10.0)
	recover_per_s = float(cfg.get("recover_per_s", recover_per_s))
	recover_delay_s = float(cfg.get("recover_delay_s", recover_delay_s))
	stagger_s = float(cfg.get("stagger_s", stagger_s))
	immunity_s = float(cfg.get("immunity_s", immunity_s))
	recovery_mult = float(cfg.get("recovery_mult", recovery_mult))
	stagger_vs_larger_s = float(cfg.get("stagger_vs_larger_s", stagger_vs_larger_s))
	value = 0.0


## Like configure() for a live meter (attribute changes): the accumulated value, the stagger
## lock and the immunity timer are kept unless keep_value is false.
func reconfigure(cfg: Dictionary, constitution: float, keep_value: bool = true) -> void:
	var kept := value
	configure(cfg, constitution)
	if keep_value:
		value = kept


## The stagger a poise break causes: stagger_vs_larger_s when the attacker is at least twice
## the owner's height and that value is set, otherwise stagger_s.
func stagger_duration(attacker_is_twice_as_tall: bool) -> float:
	if attacker_is_twice_as_tall and stagger_vs_larger_s >= 0.0:
		return stagger_vs_larger_s
	return stagger_s


func is_immune() -> bool:
	return locked or immunity_left > TIME_EPSILON


## Adds poise damage. Returns true when this addition broke poise (caller staggers).
func add(amount: float) -> bool:
	if amount <= 0.0 or is_immune():
		return false
	value += amount
	since_damage = 0.0
	if value >= threshold - 1e-6:
		value = 0.0
		return true
	return false


func begin_stagger() -> void:
	locked = true
	value = 0.0


func end_stagger() -> void:
	locked = false
	immunity_left = immunity_s


func tick(dt: float) -> void:
	since_damage += dt
	if since_damage >= recover_delay_s - TIME_EPSILON:
		value = maxf(0.0, value - recover_per_s * dt)
	if immunity_left > 0.0:
		immunity_left = maxf(0.0, immunity_left - dt)
		if immunity_left <= TIME_EPSILON:
			immunity_left = 0.0
