class_name Waystone
extends CheckpointMarker
## A waystone (plan §2.7.4, §4.3): a checkpoint only - no heal, no growth. It counts as reached
## when the player stands within radius_m of it (horizontally) while every requires_flags flag
## is truthy, and then emits Events.checkpoint_reached(tick, checkpoint_id, "waystone") once per
## level visit (P20, plan M6-M9 §2.6: GameSession.activated_this_visit / mark_activated, so a
## streamed chunk that reloads never gives a second checkpoint; a reload or a travel is a new
## visit). GameSession takes the checkpoint, deferred while an enemy nearby is aware of the
## player ("taken when out of combat"); the player respawns at the marker's transform, so the
## builder puts the stone itself a few metres behind it.
##
## It re-checks whenever one of its flags changes (Events.flag_changed) and twice a second (a
## Sim POST_RESOLVE hook, before GameSession's checkpoint drain). A child named "Glow" is shown
## while the waystone is open (every flag truthy). display_name ("Forest road waystone", from the
## layout) is what the world index, the title's save line and the checkpoint toast show.

const CHECK_INTERVAL_TICKS := 30     ## 2 Hz
const HOOK_ORDER := 190              ## POST_RESOLVE, before GameSession (200)
const GROUP := "waystones"

## Horizontal reach around the marker, in metres.
@export var radius_m := 10.0
## Flags that must all be truthy before the waystone can be reached (e.g. an encounter cleared).
@export var requires_flags := PackedStringArray()
## The player-facing name (P20), e.g. "Forest road waystone".
@export var display_name := ""

var _reached := false


func _ready() -> void:
	add_to_group(GROUP)
	Events.flag_changed.connect(_on_flag_changed)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_tick, HOOK_ORDER)
	attach_look()
	_update_visual()


# --------------------------------------------------------------------------- C3: the monument

const MONUMENT := "res://scenes/world/waystone_monument.tscn"

var look: WaystoneLook = null


## C3 (decision C3-6): puts the monument on (scenes/world/waystone_monument.tscn: WaystoneLook) where the old stone
## stood - at the foot of the Stone body's shape, turned with the marker - and hides the old stone, cap and glow
## (the Stone's solid stays). Once.
func attach_look() -> void:
	if look != null or not ResourceLoader.exists(MONUMENT):
		return
	var stone := get_node_or_null("Stone") as Node3D
	look = (load(MONUMENT) as PackedScene).instantiate() as WaystoneLook
	if look == null:
		return
	look.name = "Monument"
	var foot := Vector3.ZERO
	if stone != null:
		var shape := stone.get_node_or_null("Shape") as CollisionShape3D
		var c := shape.position if shape != null else Vector3.ZERO
		var hy := (shape.shape as BoxShape3D).size.y * 0.5 if shape != null and shape.shape is BoxShape3D else 0.0
		foot = stone.position + stone.basis * c - Vector3(0, hy, 0)
		_hide_old(stone)
	for n: String in ["Cap", "Glow"]:
		var g := get_node_or_null(n) as GeometryInstance3D
		if g != null:
			g.visible = false
			g.set_meta("c3_hidden", true)
	look.position = foot
	add_child(look)


func _hide_old(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false
		_hide_old(c)


## True once the giant has reached this stone (this visit, or ever: GameSession's visited flag).
func is_known() -> bool:
	return _reached or (checkpoint_id != "" and flag_truthy(WorldState.get_flag(GameSession.VISITED_PREFIX + checkpoint_id)))


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
## reached in this level visit.
func check() -> bool:
	if _reached or not is_inside_tree() or not is_open():
		return false
	if checkpoint_id != "" and GameSession.activated_this_visit(checkpoint_id):
		_reached = true
		_update_visual()
		return false
	var player := GameSession.player()
	if player == null or player.controller == null \
			or player.controller.state == CombatController.State.DEAD or not player_inside(player):
		return false
	_reached = true
	_update_visual()
	GameSession.mark_activated(checkpoint_id)
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
	elif checkpoint_id != "" and flag_id == GameSession.VISITED_PREFIX + checkpoint_id:
		_update_visual()


func _update_visual() -> void:
	var glow := get_node_or_null("Glow") as Node3D
	if glow != null:
		glow.visible = is_open() and look == null
	if look != null:
		look.set_state(is_open(), is_known())
