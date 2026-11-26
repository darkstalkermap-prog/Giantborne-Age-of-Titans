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
## Cgate: shown by a flag changing in play (a settlement's work raised, a load set down), it rises this far out of the
## ground and settles, under a burst of dust, instead of appearing at once (0 = at once; at a load it is simply there).
## Presentation only: its collision follows the flag at once, as before.
@export var rise_m := 0.0
const RISE_S := 1.3
## Tests: the rise runs headless too (it is presentation; headless runs skip it).
static var animate_headless := false
var _rise_t := -1.0
var _rest := Vector3.ZERO


func _ready() -> void:
	set_process(false)
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


## Applies the flags now: visibility and the collision below. `in_play`: the flag changed now (not a load).
func refresh(in_play := false) -> void:
	var on := should_show()
	if in_play and on and not visible and rise_m > 0.0 and is_inside_tree() \
			and (DisplayServer.get_name() != "headless" or animate_headless):
		_begin_rise()
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
		refresh(true)


## Cgate: the rise - from rise_m below its place, eased out with a small overshoot and settle, a dust burst at its foot.
func _begin_rise() -> void:
	if _rise_t < 0.0:
		_rest = position
	_rise_t = 0.0
	position = _rest - Vector3.UP * rise_m
	set_process(true)
	var aabb := _local_aabb()
	var width := clampf(maxf(aabb.size.x, aabb.size.z) * 0.6, 4.0, 22.0)
	var parent := get_parent()
	if parent != null:
		var at := global_transform * (aabb.get_center() * Vector3(1, 0, 1))
		DustBurst.puff(parent, at, width, 22, 5.0, Color(0.78, 0.76, 0.74))
		DustBurst.puff(parent, at + Vector3(width * 0.3, 0, 0), width * 0.6, 12, 3.5, Color(0.72, 0.7, 0.68))


func _process(delta: float) -> void:
	if _rise_t < 0.0:
		set_process(false)
		return
	_rise_t += delta / RISE_S
	var t := clampf(_rise_t, 0.0, 1.0)
	# ease out (back): up fast, a touch past its bed, then down into it - a weight settling
	var c := 1.4
	var e := 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)
	position = _rest - Vector3.UP * rise_m * (1.0 - e)
	if t >= 1.0:
		position = _rest
		_rise_t = -1.0
		set_process(false)


func _local_aabb() -> AABB:
	var box := AABB()
	var first := true
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := (global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if is_inside_tree() else mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
