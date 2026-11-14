class_name FlagVisibility
extends Node3D
## A layout element that appears or vanishes by a world flag (P25; plan M6-M9 §2.7): the
## `visible_when_flag` / `hidden_when_flag` of the world's layout tables - the rubble that seals the
## Broken Stair until the Citadel is breached, and later the region packages' banners on allied
## gates, tribute piles, burned houses and struck flags. Evaluated when it enters the tree (its
## chunk loads) and on Events.flag_changed while it is loaded. Hidden, it also switches off the
## collision of every StaticBody3D below it (layer and mask kept in metadata), so hidden rubble no
## longer blocks the way. Group "flag_visibility".

const GROUP := "flag_visibility"

## Shown only while this flag is truthy ("" = no such condition).
@export var visible_when_flag := ""
## Hidden while this flag is truthy ("" = no such condition).
@export var hidden_when_flag := ""


func _ready() -> void:
	add_to_group(GROUP)
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	refresh()


## True while the flags say the element shows.
func should_show() -> bool:
	if visible_when_flag != "" and not QuestConditions.truthy(WorldState.get_flag(visible_when_flag)):
		return false
	if hidden_when_flag != "" and QuestConditions.truthy(WorldState.get_flag(hidden_when_flag)):
		return false
	return true


## Applies the flags now: visibility and the collision below.
func refresh() -> void:
	var on := should_show()
	visible = on
	for n in find_children("*", "CollisionObject3D", true, false):
		var body := n as CollisionObject3D
		if not body.has_meta("flag_layer"):
			body.set_meta("flag_layer", body.collision_layer)
			body.set_meta("flag_mask", body.collision_mask)
		body.collision_layer = int(body.get_meta("flag_layer")) if on else 0
		body.collision_mask = int(body.get_meta("flag_mask")) if on else 0


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if flag_id == visible_when_flag or flag_id == hidden_when_flag:
		refresh()
