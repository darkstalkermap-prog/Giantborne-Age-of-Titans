class_name RewardRack
extends WeaponRack
## A weapon rack that holds a quest's reward (P35; plan M6-M9 §5.7): the Stoneknuckles at the
## ferrywoman's landing, kept for the giant who rings the Mere's five sunken bells. A WeaponRack
## (the weapon on display, taken once per world id, granted and equipped) whose E waits for every
## requires_flags flag (quest.drowned_bells.done); before that it shows locked_message. Built by the
## world builder's rack kind (tools/world/kinds/rack.gd).

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


func blocked_reason(player: GiantPlayer) -> String:
	if not taken and not flags_allow():
		return locked_message
	return super(player)
