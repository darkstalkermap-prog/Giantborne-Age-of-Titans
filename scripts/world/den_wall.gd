class_name DenWall
extends BreakableProp
## The Troll Den's back wall (P35; plan M6-M9 §5.7, §5.13, decision 26): rocks and timber heaped
## across the cave at the back of the den, the Matriarch's way out when she is driven off. A
## BreakableProp (record prop.den_back_wall: requires_permission heave, open_when_flag and
## on_destroyed_flags both world.troll_den.wall_open) that opens three ways:
##   * a stage-5 giant heaves it aside (its HeavePoint, or any blow: the heave permission rule) - it
##     breaks and its record sets wall_flag;
##   * the woodfolk pull it down woodfolk_delay_s after the den's last brood nest burned (nests_flag,
##     set by BroodNest): this node sets wall_flag then, and the record's open_when_flag opens it
##     (BreakableProp.force_open: the final state, no debris, loot or XP);
##   * at once when Sedge's bargain flag is set (a Stormborn giant's bargain with the woodfolk).
## The countdown runs while the wall is loaded; a wall loaded with the nests already burned (a
## reload, a chunk streamed back in) starts it again. Built by the world builder's den_wall kind
## (tools/world/kinds/den_wall.gd) into its chunk's props part.

const HOOK_ORDER := 135
const OPEN_MESSAGE := "The woodfolk tear down the den's back wall: the Matriarch's way out lies open."
const BARGAIN_MESSAGE := "Hollowmere's woodfolk have opened the den's back wall for you."

## Set when the den's last brood nest has burned (BroodNest).
@export var nests_flag := "world.troll_den.nests_burned"
## Sedge's bargain (a Stormborn giant): the woodfolk open the wall at once.
@export var bargain_flag := "world.troll_den.bargain"
## The open wall (the Matriarch's drive_out flag; the record's open_when_flag).
@export var wall_flag := "world.troll_den.wall_open"
## Seconds after the last nest burns before the woodfolk pull the wall down.
@export var woodfolk_delay_s := 20.0

## The tick the woodfolk open the wall (-1 while they are not coming).
var due_tick := -1
var _hooked := false


func _ready() -> void:
	super()
	if not Events.flag_changed.is_connected(_on_den_flag):
		Events.flag_changed.connect(_on_den_flag)
	_sync()


func _enter_tree() -> void:
	if not _hooked:
		Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_tick, HOOK_ORDER)
		_hooked = true


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	_hooked = false


## True once the wall is open (broken, opened, or its flag set).
func is_open() -> bool:
	return destroyed or BreakableProp.flag_truthy(WorldState.get_flag(wall_flag))


## Opens the wall for the woodfolk now (sets wall_flag; the record's open_when_flag does the rest).
## False when it is open already.
func open_for_woodfolk(message := OPEN_MESSAGE) -> bool:
	due_tick = -1
	if is_open():
		return false
	if WorldState.try_set_flag(wall_flag, true) and message != "":
		Events.hud_message.emit(message, "good")
	return true


func _sync() -> void:
	if is_open():
		due_tick = -1
		return
	if BreakableProp.flag_truthy(WorldState.get_flag(bargain_flag)):
		open_for_woodfolk(BARGAIN_MESSAGE)
		return
	if BreakableProp.flag_truthy(WorldState.get_flag(nests_flag)) and due_tick < 0:
		due_tick = Sim.tick + ActionDef.seconds_to_ticks(woodfolk_delay_s)


func _on_den_flag(_tick: int, flag_id: String, _value: Variant) -> void:
	if flag_id == nests_flag or flag_id == bargain_flag:
		_sync()


func _on_tick(tick: int) -> void:
	if due_tick >= 0 and tick >= due_tick:
		open_for_woodfolk()
