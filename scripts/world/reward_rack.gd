class_name RewardRack
extends WeaponRack
## A weapon rack that holds a quest's reward (P35; plan M6-M9 §5.7): the Stoneknuckles at the
## ferrywoman's landing, kept for the giant who rings the Mere's five sunken bells. A WeaponRack
## (the weapon on display, taken once per world id, granted and equipped) whose E waits for every
## requires_flags flag (quest.drowned_bells.done); before that it shows locked_message. Built by the
## world builder's rack kind (tools/world/kinds/rack.gd).

## M8 gate fix-up 1 (N2.2): the priority of a rack whose reward is ready (its flags hold, the weapon not
## taken): below a talker's (NpcTalker: 40), so where both are in reach E takes the reward. Wenna's talker
## (F42 gave her one) stands 8.9 m from the Stoneknuckles' rack at her landing; with the rack's own 45 she
## won wherever both were in reach and E talked to her instead of taking the gauntlets.
const READY_PRIORITY := 35

## Flags that must all be truthy before the weapon can be taken.
@export var requires_flags := PackedStringArray()
## Shown when E is pressed before requires_flags hold.
@export var locked_message := "It is not yours to take yet."


## True when every requires_flags flag is truthy.
func flags_allow() -> bool:
	for f in requires_flags:
		if not BreakableProp.flag_truthy(WorldState.get_flag(f)):
			return false
	return true


func can_interact(player: GiantPlayer) -> bool:
	return flags_allow() and super(player)


## READY_PRIORITY while the reward waits for its bell-ringer; the rack's own priority otherwise (locked:
## its locked_message does not push a talker aside).
func priority_for(player: GiantPlayer) -> int:
	if not taken and flags_allow():
		return mini(priority, READY_PRIORITY)
	return super(player)


func blocked_reason(player: GiantPlayer) -> String:
	if not taken and not flags_allow():
		return locked_message
	return super(player)
