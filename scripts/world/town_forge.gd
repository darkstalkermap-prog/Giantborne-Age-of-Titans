class_name TownForge
extends Forge
## A settlement's forge (P29; plan M6-M9 §5.4, §5.7, §5.9): Brannock's smithy (iron tier). It works for
## any giant its town is not hostile to - shut while the faction is hostile (closed_message names it),
## open again once reconciled (FactionState.is_hostile: "reconciled" wins over "hostile") - and
## otherwise is a Forge like any other (its flags, its reforge). Placed by the world builder's
## forge_site kind with style "town" (tools/world/kinds/forge_site.gd).

## The faction whose forge this is (its short name: "brannock"); "" = no faction rule.
@export var faction := ""
## Shown while the faction is hostile.
@export var hostile_message := "The smith bars the forge against you."


## Open when the faction is not hostile and the Forge's own flags allow it.
func is_open() -> bool:
	if faction != "" and FactionState.is_hostile(faction):
		return false
	return super.is_open()


func blocked_reason(player: GiantPlayer) -> String:
	if faction != "" and FactionState.is_hostile(faction):
		return hostile_message
	return super.blocked_reason(player)
