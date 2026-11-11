class_name MatriarchBrain
extends OgreBossBrain
## The Troll Matriarch (plan M6-M9 §5.13 boss 2; P34): fights by the phases of her record's boss block
## (EnemyBrain's P11a sequences, as the Ogre King): phase 1 (above 50 %) cycles the club sweep (cone
## 140 degrees, blockable), the whelp throw and the stomp (circle r 7, unblockable); phase 2 (at or
## below 50 %) begins with the forced 1.5 s roar that calls three whelps (TrollEnemy.p34_summon) and
## cycles the frenzy (two sweeps), the stomp, the throw and the sweep. Each phase is entered once per
## attempt (EnemyActor.p34_reset_attempt starts the next attempt at phase 1).
##
## The whelp throw needs a whelp: while none is within brood.reach_m (whelp_ready, set by the actor)
## the throw's sequence entry is skipped at once. Ignores morale (no flight in fights); the drive-out
## ending is the actor's (TrollEnemy) - her AI is off while she runs for the exit.

## Set by the actor: () -> bool, true while a free whelp is within reach.
var whelp_ready := Callable()
var _throw_id := ""


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	var brood: Variant = record.get("brood")
	_throw_id = str((brood as Dictionary).get("throw_action", "")) if typeof(brood) == TYPE_DICTIONARY else ""


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if state != AIState.ATTACK and _throw_id != "" and current_sequence_entry() == _throw_id \
			and whelp_ready.is_valid() and not bool(whelp_ready.call()):
		advance_sequence(false)   # no whelp to throw: the next entry
	super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)
