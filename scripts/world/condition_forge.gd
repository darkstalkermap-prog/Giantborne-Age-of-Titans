class_name ConditionForge
extends Forge
## A forge that opens on a quest condition (P36; plan M6-M9 §5.7, §5.9, §5.12): the titan-tier forges
## a deed opens - Fort Aldmere's (the crown's parley, or a spared Corvane) and Skarn's hearth-forge
## (Skarn saved from the siege, or rebuilt after it burned). `open_when` is one condition of the quests'
## shapes (QuestConditions, evaluated on Quests.condition_context()); while it fails the forge is shut
## with `closed_message`. Otherwise a Forge like any other (its flags, its tier, its reforge). Placed
## by the world builder's condition_forge kind (tools/world/kinds/condition_forge.gd).

## The condition that opens the forge ({} = always open).
@export var open_when: Dictionary = {}


## Open when open_when holds and the Forge's own flags allow it.
func is_open() -> bool:
	if not open_when.is_empty() and not QuestConditions.holds(open_when, Quests.condition_context()):
		return false
	return super.is_open()
