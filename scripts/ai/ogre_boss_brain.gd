class_name OgreBossBrain
extends EnemyBrain
## The Ogre King (spec 10 "Valley boss", decision 27, plan §3.12 design 2).
##
## Fights by the phases of its record's `boss` block (EnemyBrain's P11a section): phase 1 (above
## 50 % health) strictly alternates the two-hit combo and the slam; phase 2 (at or below 50 %)
## begins with the forced phase roar and cycles combo, slam, charge - a charge at least every
## third decision. Each sequence entry is struck when the target is inside that action's ai band
## and the entry's facing rule allows it (the slam hits all round; the charge turns during its
## windup); otherwise the king closes in or backs off for up to 2 s, then skips the entry. A
## phase is entered once (update_boss_phase): healed above 50 % the king never returns to phase-1
## behaviour, and the roar never repeats. Ignores morale (no flight); immune to Grab and Fear.


## True once phase 2 (or any later phase) has begun; never false again.
var phase2_entered := false


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	init_boss_phases(record)


func update_boss_phase(health_frac: float, tick: int = -1) -> int:
	var entered := super(health_frac, tick)
	if boss_phase() >= 2:
		phase2_entered = true
	return entered


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	_decide_sequence(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token,
		release_token)


## A path failure while chasing an entry's band skips the entry; otherwise the base rule.
func on_path_failed(my_position: Vector3) -> void:
	if not sequence_path_failed():
		super(my_position)


## The current phase's pick (its sequence entry); the base pick without phases.
func _choose_attack() -> String:
	var id := choose_phase_attack()
	return id if id != "" else super()
