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
		_fade_with_frame()
	if ItemPickup.is_taken(world_id):
		_empty()


## M8 gate (F27; plan M6-M9 §5.2: at most 40 static draw calls a view at low): the weapon on display -
## built here, after the level or the chunk gave the rack's frame the preset's scenery distance - fades
## with the frame: its parts join group "scenery" (so LevelRoot.apply_graphics keeps them in step) at
## the frame's distance now. Before, the six or seven parts of a world rack's weapon were drawn from
## 500 m away while the rack itself was not.
func _fade_with_frame() -> void:
	var frame_range := 0.0
	var frame := get_node_or_null("Frame")
	if frame != null:
		for n in frame.find_children("*", "GeometryInstance3D", true, false):
			frame_range = maxf(frame_range, (n as GeometryInstance3D).visibility_range_end)
	for n in display_weapon.find_children("*", "GeometryInstance3D", true, false):
		n.add_to_group(LevelRoot.SCENERY_GROUPS[0])
		(n as GeometryInstance3D).visibility_range_end = frame_range


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
