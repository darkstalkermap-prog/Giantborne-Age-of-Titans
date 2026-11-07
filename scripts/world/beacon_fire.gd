class_name BeaconFire
extends Interactable
## A beacon's fire (P29; plan M6-M9 §5.4, §5.7): the interaction at the foot of a beacon tower that
## relights it - the Kingsgate beacon (quest.world_main's `beacon` stage) and Shepherd's Watch
## (quest.watch_beacon). Built by the world builder's beacon_fire kind (tools/world/kinds/), saved in
## its chunk's props part.
##
## - It can be lit once every requires_flags flag is truthy (the beacon hill's toll-riders or
##   squatters cleared: encounter.<short>.cleared); before that E shows locked_message.
## - light(): sets lit_flag (world.kingsgate.lit - the Kingsgate shrine's growth condition and the
##   skyline's light column), awards its cache once (loot_table through Loot.award_once on its world
##   id: the beacon cache's titan iron and iron), reveals the places within reveal_m on the map
##   (Discovery.reveal_around), says lit_message, and plays its short scene: scene_dialogue through
##   Events.dialogue_requested (the Kingsgate beacon's names the three powers of the Old Kingdom).
## - The Fire child (the flames on the tower's top) shows while lit_flag is set, from any writer and
##   after a reload. Group "beacons".

const GROUP := "beacons"

## The beacon's persistent world id (its cache pays once per id).
@export var world_id := ""
@export var display_name := "beacon"
## The world flag a lit beacon sets (and that shows its fire).
@export var lit_flag := ""
## Flags that must all be truthy before it can be lit.
@export var requires_flags := PackedStringArray()
## Shown when E is pressed before requires_flags hold.
@export var locked_message := "The beacon's hill is not yet yours."
## Its cache (a loot_table record), awarded once when it is lit ("" = none).
@export var loot_table := ""
## A lit beacon reveals the POIs within this many metres on the map (0 = none).
@export var reveal_m := 0.0
## The HUD line when it catches.
@export var lit_message := ""
## The short scene played after lighting (a dialogue record; "" = none).
@export var scene_dialogue := ""

## How many times light() lit it in this process (tests).
var lights := 0


func _init() -> void:
	prompt = "Relight the beacon"
	priority = 35
	radius_m = 9.0


func _ready() -> void:
	add_to_group(GROUP)
	if interact_id == "":
		interact_id = world_id
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	_sync_fire()


## True once the beacon burns (its lit_flag is truthy).
func is_lit() -> bool:
	return lit_flag != "" and BreakableProp.flag_truthy(WorldState.get_flag(lit_flag))


## True when every requires_flags flag is truthy.
func flags_allow() -> bool:
	for f in requires_flags:
		if not BreakableProp.flag_truthy(WorldState.get_flag(f)):
			return false
	return true


func can_interact(_player: GiantPlayer) -> bool:
	return not is_lit() and flags_allow()


func blocked_reason(_player: GiantPlayer) -> String:
	return "The %s already burns." % display_name if is_lit() else locked_message


func prompt_text(_player: GiantPlayer) -> String:
	return "Relight the %s" % display_name


func interact(_player: GiantPlayer) -> void:
	light()


## Lights the beacon (see the class notes). False when it burns already or may not be lit yet.
func light() -> bool:
	if is_lit() or not flags_allow() or lit_flag == "":
		return false
	lights += 1
	WorldState.set_flag(lit_flag, true)
	if loot_table != "" and world_id != "":
		Loot.award_once(world_id, loot_table, "player")
	if reveal_m > 0.0 and is_inside_tree():
		var d := Discovery.of_tree(get_tree())
		if d != null:
			d.reveal_around(global_position, reveal_m)
	if lit_message != "":
		Events.hud_message.emit(lit_message, "good")
	if scene_dialogue != "":
		Events.dialogue_requested.emit(world_id, scene_dialogue)
	_sync_fire()
	return true


func _on_flag_changed(_tick: int, id: String, _value: Variant) -> void:
	if id == lit_flag:
		_sync_fire()


func _sync_fire() -> void:
	var fire := get_node_or_null("Fire") as Node3D
	if fire != null:
		fire.visible = is_lit()
