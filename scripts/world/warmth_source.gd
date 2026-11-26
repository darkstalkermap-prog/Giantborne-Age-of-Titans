class_name WarmthSource
extends Node3D
## D1: a fire that warms a giant (PlayerRime sheds his rime fast within radius_m): the balefires the Hearth's
## watchers keep on the Rimeglass's shore, Last Hearth's hall fire. Lit (warming) only while its flag says so: a
## `requires_flag` that is not set leaves it cold and unseen (its flames are its own FlagVisibility node beside it).
## A pure lookup: the rime asks warm_at() every tick; nothing here steps.

const GROUP := "warmth_sources"

@export var radius_m := 22.0
## A world flag the fire needs (the watchers came: "" = always lit).
@export var requires_flag := ""
## A world flag that puts it out ("" = never).
@export var hidden_when_flag := ""


func _ready() -> void:
	add_to_group(GROUP)


func is_lit() -> bool:
	if requires_flag != "" and not bool(WorldState.get_flag(requires_flag, false)):
		return false
	if hidden_when_flag != "" and bool(WorldState.get_flag(hidden_when_flag, false)):
		return false
	return true


## True when `pos` lies within the radius of a lit fire (on the ground: horizontally, a giant's height above).
static func warm_at(tree: SceneTree, pos: Vector3) -> bool:
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP):
		var w := n as WarmthSource
		if w == null or not w.is_inside_tree() or not w.is_lit():
			continue
		var d := Vector2(w.global_position.x - pos.x, w.global_position.z - pos.z).length()
		if d <= w.radius_m and absf(w.global_position.y - pos.y) < 40.0:
			return true
	return false


## The nearest lit fire to `pos` (null when none): the duel bot walks there to thaw.
static func nearest(tree: SceneTree, pos: Vector3) -> WarmthSource:
	if tree == null:
		return null
	var best: WarmthSource = null
	var best_d := INF
	for n in tree.get_nodes_in_group(GROUP):
		var w := n as WarmthSource
		if w == null or not w.is_inside_tree() or not w.is_lit():
			continue
		var d := w.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = w
	return best
