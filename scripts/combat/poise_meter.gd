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


func configure(cfg: Dictionary, constitution := 10.0) -> void:
	threshold = float(cfg.get("threshold", threshold)) + 3.0 * maxf(0.0, constitution - 10.0)
	recover_per_s = float(cfg.get("recover_per_s", recover_per_s))
	recover_delay_s = float(cfg.get("recover_delay_s", recover_delay_s))
	stagger_s = float(cfg.get("stagger_s", stagger_s))
	immunity_s = float(cfg.get("immunity_s", immunity_s))
	value = 0.0


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
