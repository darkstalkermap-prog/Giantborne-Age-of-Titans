class_name UprootTree
extends Interactable
## An ancient oak a stage-3 giant tears from the ground and wields (plan §2.7.4, §3.8 design 3,
## decision 19). E needs the growth profile's interaction permission (the record's
## requires_permission, `tree_weapon`); without it the prompt stays and E shows the record's
## locked message ("Too small to uproot this oak (stage 3)."). With it: the tree weapon is granted
## and equipped (PlayerEquipment.grant_weapon(weapon_id, true)), WorldState.record_destroyed for
## the oak's world id, the flag world.tree_weapon_taken (first write wins), and the oak is hidden
## with its collision off. A reload of an uprooted oak starts that way.
##
## Children: Trunk (StaticBody3D on WORLD: the obstacle), Visual (meshes).

const TAKEN_FLAG := "world.tree_weapon_taken"

## Placed, persistent id, e.g. "valley.kingsfall.oak".
@export var world_id := ""
@export var prop_id := "prop.ancient_oak"
## "" = the record's uproot_weapon.
@export var weapon_id := "weapon.tree_oak"

var uprooted := false


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id
	if world_id == "":
		push_error("UprootTree %s has no world_id" % get_path())
	if record().is_empty():
		push_error("UprootTree %s: unknown prop record '%s'" % [world_id, prop_id])
	if WorldState.is_destroyed(world_id):
		_remove()


func record() -> Dictionary:
	return GameData.get_record(prop_id)


func tree_weapon_id() -> String:
	return weapon_id if weapon_id != "" else str(record().get("uproot_weapon", ""))


func required_permission() -> String:
	return str(record().get("requires_permission", "tree_weapon"))


func has_permission(player: GiantPlayer) -> bool:
	var perms: Variant = player.profile.get("interaction_permissions", []) if player != null else []
	return typeof(perms) == TYPE_ARRAY and (perms as Array).has(required_permission())


func prompt_text(_player: GiantPlayer) -> String:
	return "Uproot the %s" % str(record().get("display_name", "oak")).to_lower()


func can_interact(player: GiantPlayer) -> bool:
	return not uprooted and player != null and player.equipment != null and has_permission(player) \
		and player.controller.state == CombatController.State.LOCOMOTION


func blocked_reason(player: GiantPlayer) -> String:
	if uprooted or player == null:
		return ""
	if not has_permission(player):
		var msg := str(record().get("locked_message", ""))
		return msg if msg != "" else "Too small to uproot this oak (stage 3)."
	if player.equipment == null:
		return ""
	return "Finish your attack first."


func interact(player: GiantPlayer) -> void:
	if not can_interact(player):
		return
	uprooted = true
	player.equipment.grant_weapon(tree_weapon_id(), true)
	WorldState.record_destroyed(world_id)
	WorldState.try_set_flag(TAKEN_FLAG, true)
	Events.hud_message.emit("You tear the oak from the ground.", "good")
	_remove()


func _remove() -> void:
	uprooted = true
	enabled = false
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = false
	var trunk := get_node_or_null("Trunk") as CollisionObject3D
	if trunk != null:
		trunk.collision_layer = 0
		for c in trunk.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
