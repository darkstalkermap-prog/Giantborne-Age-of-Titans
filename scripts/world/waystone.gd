class_name Waystone
extends CheckpointMarker
## A waystone (plan §2.7.4, §4.3): a checkpoint only - no heal, no growth. It counts as reached
## when the player stands within radius_m of it (horizontally) while every requires_flags flag
## is truthy, and then emits Events.checkpoint_reached(tick, checkpoint_id, "waystone") once per
## load (a reload makes a new waystone). GameSession takes the checkpoint, deferred while an
## enemy nearby is aware of the player ("taken when out of combat"); the player respawns at the
## marker's transform, so the builder puts the stone itself a few metres behind it.
##
## It re-checks whenever one of its flags changes (Events.flag_changed) and twice a second (a
## Sim POST_RESOLVE hook, before GameSession's checkpoint drain). A child named "Glow" is shown
## while the waystone is open (every flag truthy).

const CHECK_INTERVAL_TICKS := 30     ## 2 Hz
const HOOK_ORDER := 190              ## POST_RESOLVE, before GameSession (200)
const GROUP := "waystones"

## Horizontal reach around the marker, in metres.
@export var radius_m := 10.0
## Flags that must all be truthy before the waystone can be reached (e.g. an encounter cleared).
@export var requires_flags := PackedStringArray()

var _reached := false


func _ready() -> void:
	add_to_group(GROUP)
	Events.flag_changed.connect(_on_flag_changed)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_tick, HOOK_ORDER)
	_update_visual()


## True once the player reached it in this load.
func is_reached() -> bool:
	return _reached


## True while every required flag is truthy.
func is_open() -> bool:
	for flag_id in requires_flags:
		if not flag_truthy(WorldState.get_flag(flag_id)):
			return false
	return true


## True when `player` (alive) stands within radius_m of the marker on the ground plane (and
## within radius_m vertically).
func player_inside(player: GiantPlayer) -> bool:
	if player == null or not player.is_inside_tree() or not is_inside_tree():
		return false
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length() <= radius_m and absf(d.y) <= radius_m


## Checks the waystone now; emits checkpoint_reached and returns true the first time it is
## reached in this load.
func check() -> bool:
	if _reached or not is_inside_tree() or not is_open():
		return false
	var player := GameSession.player()
	if player == null or player.controller == null \
			or player.controller.state == CombatController.State.DEAD or not player_inside(player):
		return false
	_reached = true
	_update_visual()
	Events.checkpoint_reached.emit(Sim.tick, checkpoint_id, "waystone")
	return true


## The flag values that count as set: true, a non-zero number, a non-empty string (and any other
## non-null value).
static func flag_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v) != ""
	return true


func _on_tick(tick: int) -> void:
	if tick % CHECK_INTERVAL_TICKS == 0:
		check()


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if requires_flags.has(flag_id):
		_update_visual()
		check()


func _update_visual() -> void:
	var glow := get_node_or_null("Glow") as Node3D
	if glow != null:
		glow.visible = is_open()
