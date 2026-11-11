class_name GreatPineTree
extends UprootTree
## A great pine of the Greywood that a giant tears from the ground and wields (P35; plan M6-M9 §5.4,
## §5.12, quest.great_pine): P26's great_pine.tscn (Trunk, Visual: UprootTree's children) given this
## script by the world builder (a `pines` entry with `uproot_prop`). An UprootTree that also asks the
## record's min_growth_stage (prop.great_pine: stage 4 - the oak's tree_weapon permission already
## comes at stage 3), grants the record's uproot weapon or `weapon_id` (weapon.tree_pine, with its
## stage movesets), records the pine's world id as destroyed (quest.great_pine counts it) and says so.
## It never sets the Valley oak's world.tree_weapon_taken.

const UPROOTED_MESSAGE := "You tear the great pine from the earth: a weapon fit for a giant of the old height."


## The stage the record asks for (1 when it names none).
func min_stage() -> int:
	return int(record().get("min_growth_stage", 1))


func has_permission(player: GiantPlayer) -> bool:
	return super(player) and player != null and int(player.get("growth_stage")) >= min_stage()


func interact(player: GiantPlayer) -> void:
	if not can_interact(player):
		return
	uprooted = true
	player.equipment.grant_weapon(tree_weapon_id(), true)
	WorldState.record_destroyed(world_id)
	Events.hud_message.emit(UPROOTED_MESSAGE, "good")
	_remove()
