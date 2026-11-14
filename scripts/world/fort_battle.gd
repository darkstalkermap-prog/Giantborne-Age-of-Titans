class_name FortBattle
extends BattleBoss
## Fort Aldmere's battle (P36; plan M6-M9 §5.7 the crown's breach, §5.9, §5.13 boss 1): P34's
## BattleBoss for the Iron Regiment in the inner bailey, with the fort's own rules around it:
##   * Peace keeps the bailey open: while `peace_condition` holds (the crown's oath sworn by parley:
##     Aldmere is the giant's ally) entering the bailey engages nothing - the regiment never musters.
##   * A settled battle stays settled: once `settled_flag` is set (boss.corvane.outcome: spared or
##     slain) the battle loads defeated and never engages again.
##   * Corvane's yield decides the garrison: Spare reconciles `faction` (Aldmere; its soldiers and
##     engines stand down, the fort forge opens through its own condition) and opens the fort
##     (`open_flag`); Strike - the warlord dies on the giant's blow - routs what is left of the battle
##     (the garrison flees). The oath itself is quest.iron_regiment's (its last stage completes on the
##     warlord's outcome and writes oath.crown.outcome = breach).
## Placed by the world builder's arena kind (style "battle") with its engage trigger and the inner
## portcullis that closes behind the giant (BossArena's gate).

## While this condition holds the bailey is at peace ({} = never).
@export var peace_condition: Dictionary = {}
## Set once the battle is over for good (the warlord spared or slain).
@export var settled_flag := "boss.corvane.outcome"
## The faction a spared warlord reconciles ("" = none).
@export var faction := "aldmere"
## Set when the warlord is spared (the fort's gate opens to the giant: its open_when_flag).
@export var open_flag := ""

## True once Strike routed the survivors (tests).
var routed_survivors := false


func _ready() -> void:
	super()
	if settled():
		state = State.DEFEATED


## True once the battle's outcome is decided (spared or slain).
func settled() -> bool:
	return settled_flag != "" and QuestConditions.truthy(WorldState.get_flag(settled_flag))


## M8 release (R1): a settled battle is over too - a load keeps its phases as they are (BattleBoss repairs
## only a battle not over).
func battle_over() -> bool:
	return super() or settled()


## True while the bailey is at peace (the parley).
func at_peace() -> bool:
	return not peace_condition.is_empty() and QuestConditions.holds(peace_condition, Quests.condition_context())


func engage(tick: int = -1) -> void:
	if at_peace():
		return
	if settled():
		state = State.DEFEATED
		return
	super(tick)


## The trigger's engagement waits while the bailey is at peace (the giant walks in as a friend).
func _on_post_resolve(tick: int) -> void:
	if state == State.ENGAGING and at_peace():
		state = State.WAITING
		return
	super(tick)


## The yield's decision (EnemyActor.p34_decide): Spare reconciles the faction and opens the fort.
func p34_on_yield_decided(entity_id: String, outcome: String) -> void:
	super(entity_id, outcome)
	if entity_id != commander_id or outcome != "spare":
		return
	if faction != "":
		FactionState.reconcile(faction)
	if open_flag != "":
		WorldState.try_set_flag(open_flag, true)


## Strike: the warlord is dead - what is left of the battle routs (the garrison flees).
func _on_entity_died(tick: int, id: String, killer: String) -> void:
	var was_defeated := state == State.DEFEATED
	super(tick, id, killer)
	if id == commander_id and commander_id != "" and not was_defeated:
		rout_survivors()


## Every living unit of the battle's composition routs (tests may call it).
func rout_survivors() -> int:
	var n := 0
	for uid: String in _planned:
		if uid == commander_id:
			continue
		var e := Sim.get_entity(uid)
		if e != null and e.is_alive() and is_instance_valid(e.actor) and e.actor.has_method("p30_force_rout"):
			e.actor.call("p30_force_rout")
			n += 1
	routed_survivors = true
	return n
