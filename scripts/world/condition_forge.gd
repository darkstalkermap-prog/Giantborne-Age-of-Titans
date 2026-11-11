class_name ConditionForge
extends Forge
## A forge that opens on a quest condition (P36; plan M6-M9 §5.7, §5.9, §5.12): the titan-tier forges
## a deed opens - Fort Aldmere's (the crown's parley, or a spared Corvane) and Skarn's hearth-forge
## (Skarn saved from the siege, or rebuilt after it burned). `open_when` is one condition of the quests'
## shapes (QuestConditions, evaluated on Quests.condition_context()); while it fails the forge is shut
## with `closed_message`. Otherwise a Forge like any other (its flags, its tier, its reforge). Placed
## by the world builder's condition_forge kind (tools/world/kinds/condition_forge.gd).
##
## M8 gate (F16; plan §5.9 "Settlements anywhere": a faction turned hostile "shuts its forge" until it is
## reconciled): an optional `faction` - the settlement whose smiths work the forge (Fort Aldmere's
## "aldmere", Skarn's "skarn") - shuts it while FactionState.is_hostile(faction), with `hostile_message`,
## whatever open_when says, as TownForge shuts Brannock's; it opens again once the faction is
## reconciled ("reconciled" wins over "hostile").

## The condition that opens the forge ({} = always open).
@export var open_when: Dictionary = {}
## The faction whose forge this is (its short name); "" = no faction rule.
@export var faction := ""
## Shown while the faction is hostile.
@export var hostile_message := "The smiths bar the forge against you."


## Open when its faction is not hostile, open_when holds and the Forge's own flags allow it.
func is_open() -> bool:
	if faction != "" and FactionState.is_hostile(faction):
		return false
	if not open_when.is_empty() and not QuestConditions.holds(open_when, Quests.condition_context()):
		return false
	return super.is_open()


func blocked_reason(player: GiantPlayer) -> String:
	if faction != "" and FactionState.is_hostile(faction):
		return hostile_message
	return super.blocked_reason(player)
