class_name WeaponRack
extends Interactable
## A rack holding one weapon (plan §2.7.4, §3.8 design 3): the quarry's maul, the armory's sword.
## E grants the weapon and equips it (PlayerEquipment.grant_weapon(weapon_id, true)), once per
## world id: the delta `taken` keeps the rack empty after a reload. The weapon on display is built
## from the record (WeaponVisuals) under Display at _ready, upright.
##
## Equipping needs LOCOMOTION, so E mid-swing shows "Finish your attack first." and keeps the
## weapon on the rack.
##
## Children: Frame (the rack, static), Display (where the weapon mesh goes).

## Placed, persistent id, e.g. "valley.ruins.sword_rack".
@export var world_id := ""
@export var weapon_id := "weapon.sword"

var taken := false
var display_weapon: Node3D = null


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id
	if world_id == "":
		push_error("WeaponRack %s has no world_id" % get_path())
	var rec := GameData.get_record(weapon_id)
	if str(rec.get("type", "")) != "weapon":
		push_error("WeaponRack %s: unknown weapon '%s'" % [world_id, weapon_id])
	var display := get_node_or_null("Display") as Node3D
	if display != null and not rec.is_empty():
		display_weapon = WeaponVisuals.build(rec)
		display_weapon.rotation_degrees = Vector3(90, 0, 0)   # the tip up
		display.add_child(display_weapon)
	if ItemPickup.is_taken(world_id):
		_empty()


func weapon_name() -> String:
	return str(GameData.get_record(weapon_id).get("display_name", weapon_id))


func prompt_text(_player: GiantPlayer) -> String:
	return "Take the %s" % weapon_name()


func can_interact(player: GiantPlayer) -> bool:
	return not taken and player != null and player.equipment != null \
		and player.controller.state == CombatController.State.LOCOMOTION


func blocked_reason(player: GiantPlayer) -> String:
	if taken or player == null or player.equipment == null:
		return ""
	return "Finish your attack first."


func interact(player: GiantPlayer) -> void:
	if not can_interact(player):
		return
	taken = true
	ItemPickup.record_taken(world_id)
	player.equipment.grant_weapon(weapon_id, true)
	_empty()


func _empty() -> void:
	taken = true
	enabled = false
	if display_weapon != null:
		display_weapon.visible = false
