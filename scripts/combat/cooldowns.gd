class_name Cooldowns
extends RefCounted
## Per-action cooldowns measured in simulation ticks. Started once, on acceptance.

const TICK_RATE := 60

var _ready_tick: Dictionary = {}   ## action id -> first tick at which it is usable again
var _length_ticks: Dictionary = {} ## action id -> full cooldown length (for HUD fill)


func start(action_id: String, cooldown_s: float, now: int) -> void:
	var length := int(roundf(cooldown_s * TICK_RATE))
	if length <= 0:
		return
	_ready_tick[action_id] = now + length
	_length_ticks[action_id] = length


func is_ready(action_id: String, now: int) -> bool:
	return now >= int(_ready_tick.get(action_id, 0))


func remaining_s(action_id: String, now: int) -> float:
	return maxf(0.0, float(int(_ready_tick.get(action_id, 0)) - now) / TICK_RATE)


## 1.0 right after starting, 0.0 when ready.
func remaining_fraction(action_id: String, now: int) -> float:
	var length := int(_length_ticks.get(action_id, 0))
	if length <= 0:
		return 0.0
	return clampf(float(int(_ready_tick.get(action_id, 0)) - now) / length, 0.0, 1.0)


func clear() -> void:
	_ready_tick.clear()
	_length_ticks.clear()
