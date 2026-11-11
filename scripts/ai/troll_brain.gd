class_name TrollBrain
extends OgreBrain
## Trolls and troll whelps (plan M6-M9 §2.10, §4.6; P34): the ogre's tactics (OgreBrain) - close to
## the legs, strike by range band and weight while facing the target, the all-round smash at a giant
## beside or behind it, a long recovery to punish - plus one thing a troll knows about fire: while it
## burns (it cannot regenerate) and is badly hurt it does not wait out its strike pause, it presses the
## attack (BURNING_PRESS_FRAC), since time no longer heals it. Ignores morale and Fear (its record).

## Below this health fraction a burning troll strikes again without its pause.
const BURNING_PRESS_FRAC := 0.5

## Set by the actor: () -> bool, true while a status tagged Burning is on it.
var burning_probe := Callable()


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if state == AIState.RECOVER and burning_probe.is_valid() and bool(burning_probe.call()) \
			and float(perception.get("self_health_frac", 1.0)) < BURNING_PRESS_FRAC:
		strike_ready_tick = mini(strike_ready_tick, now)
	super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)
