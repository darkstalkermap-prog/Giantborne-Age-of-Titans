class_name MootArena
extends BossArena
## The Moot's ring (P36; plan M6-M9 §5.7 the champion stage, §5.9, §5.13 boss 3): P34's BossArena for
## Harrok the Unbowed's honour duel, with the Moot's own rules around it:
##   * A settled champion stays settled: once `settled_flag` is set (boss.harrok.outcome: spared, slain
##     or yielded_talk) the ring loads defeated and the duel never engages again - so the talk ending
##     (Harrok kneels to a giant whom the three powers and Skarn have sworn to: his dialogue sets
##     yielded_talk) lets the giant walk into the ring to the Stone Throne without a fight, and a reload
##     after the duel finds the ring at peace.
##   * The duel's endings reach the clans: Spare (or the talk) reconciles `faction` (Harrok's clan: its
##     giants at Harrok's Hall stand down); Strike - Harrok dead - sets `empty_flag` (world.moot.empty:
##     the watching clans leave the Moot, and Harrok's clan stays hostile).
## Placed by the world builder's arena kind (style "moot"); Harrok's encounter holds him neutral at his
## post until the giant enters the ring (its stand_down_when).

## The talk ending's outcome (Harrok's dialogue sets settled_flag to it) and, M8 release (R1), the
## boss_disengaged reason it ends an engaged duel with.
const TALK_OUTCOME := "yielded_talk"

## Set once the champion's outcome is decided.
@export var settled_flag := "boss.harrok.outcome"
## The faction a spared (or talked-down) champion reconciles ("" = none).
@export var faction := "harrok_clan"
## Set when the champion dies (the Moot empties).
@export var empty_flag := "world.moot.empty"


func _ready() -> void:
	super()
	if settled():
		state = State.DEFEATED
	if not Events.flag_changed.is_connected(_on_moot_flag):
		Events.flag_changed.connect(_on_moot_flag)


func _exit_tree() -> void:
	super()
	if Events.flag_changed.is_connected(_on_moot_flag):
		Events.flag_changed.disconnect(_on_moot_flag)


func settled() -> bool:
	return settled_flag != "" and QuestConditions.truthy(WorldState.get_flag(settled_flag))


## A settled champion engages nothing (the talk ending, a reload after the duel).
func engage(tick: int = -1) -> void:
	if settled() and state != State.ENGAGED:
		state = State.DEFEATED
		return
	super(tick)


## The talk ending during play: the ring goes quiet at once (no duel, no boss music), the clan
## reconciled. M8 release (R1): also when the duel is engaged (_end_by_talk).
func _on_moot_flag(tick: int, flag_id: String, value: Variant) -> void:
	if flag_id != settled_flag or not QuestConditions.truthy(value):
		return
	if str(value) == TALK_OUTCOME:
		if state == State.ENGAGED:
			_end_by_talk(tick)
		else:
			state = State.DEFEATED
		if faction != "":
			FactionState.reconcile(faction)


## M8 release (R1): the talk ending chosen while the duel is engaged - the giant stepped into the ring, then
## walked out to the challenge stone (the fight's ground, N4.6) and bid Harrok kneel - ends the duel without a
## victory: the ring at peace (DEFEATED, its gate open) and Events.boss_disengaged(boss, "yielded_talk"), which
## ends the bar, takes the boss music back to the zone with the yield stinger (CueRouter) and takes the fight's
## end checkpoint (GameSession: boss_yielded_talk). No defeated flag and no boss_defeated (no victory stinger):
## the talk ending chosen before the duel sets neither, and the outcome flag is its record (settled() on a
## load). The duel stayed engaged before, with Harrok stood down, until the giant walked away; and since no
## checkpoint is committed while a fight is engaged, the throne inside the ring would have been claimed with
## nothing saved.
func _end_by_talk(tick: int) -> void:
	state = State.DEFEATED
	defeated_tick = tick
	_outside_since = -1
	_set_gate_closed(false)
	Events.boss_disengaged.emit(tick, boss_id, TALK_OUTCOME)


## The yield's decision: Spare reconciles the clan (the duel is won).
func p34_on_yield_decided(entity_id: String, outcome: String) -> void:
	super(entity_id, outcome)
	if entity_id == boss_id and outcome == "spare" and faction != "":
		FactionState.reconcile(faction)


## Harrok's death (Strike): the Moot empties.
func _on_entity_died(tick: int, id: String, killer: String) -> void:
	super(tick, id, killer)
	if id == boss_id and empty_flag != "":
		WorldState.try_set_flag(empty_flag, true)
