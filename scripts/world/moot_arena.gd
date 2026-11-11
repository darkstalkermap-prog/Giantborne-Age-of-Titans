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
## reconciled.
func _on_moot_flag(_tick: int, flag_id: String, value: Variant) -> void:
	if flag_id != settled_flag or not QuestConditions.truthy(value):
		return
	if str(value) == "yielded_talk":
		if state != State.ENGAGED:
			state = State.DEFEATED
		if faction != "":
			FactionState.reconcile(faction)


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
