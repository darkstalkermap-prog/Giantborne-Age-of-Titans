class_name AreaTrigger
extends Area3D
## A named volume of a level (plan §2.7.4): quests ("entered" conditions), tutorial prompts and
## the boss arena react when the player walks in or out. Shapes are ordinary CollisionShape3D
## children. It sits on no physics layer and watches the actors layer; only the player counts.
## Group "area_triggers" (joined in _notification, so subclasses need no super() calls).
##
## player_inside follows the player's body all the time (the tutorial's "entered" trigger is a
## state). Events.area_entered / area_exited(tick, area_id, entity_id) are emitted for the
## player only, deferred to the end of the physics frame: the overlap callbacks run while the
## physics server flushes its queries, when listeners must not change physics state yet (the
## arena gate closing on arena_engage, for example). A `once` trigger reports only the first
## visit (its entry and its exit); player_inside keeps following the player afterwards.

const GROUP := "area_triggers"
## The actors physics layer (the player's body is on it).
const ACTORS_MASK := 2

## Stable id, e.g. "valley.area.arena_engage".
@export var area_id := ""
## Report only the first visit per load.
@export var once := false

## True while the player's body overlaps the trigger.
var player_inside := false
## How many times area_entered was emitted in this load.
var entered_count := 0
## How many times area_exited was emitted in this load.
var exited_count := 0

var _first_visit_done := false


func _init() -> void:
	collision_layer = 0
	collision_mask = ACTORS_MASK
	monitoring = true
	monitorable = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## True when `body` is the player (group "player").
static func is_player_body(body: Node) -> bool:
	return body != null and body.is_in_group("player")


func _on_body_entered(body: Node3D) -> void:
	if not is_player_body(body):
		return
	player_inside = true
	if once and _first_visit_done:
		return
	_emit_deferred.call_deferred(true, _entity_id_of(body))


func _on_body_exited(body: Node3D) -> void:
	if not is_player_body(body):
		return
	player_inside = false
	if once and _first_visit_done:
		return
	if once:
		_first_visit_done = true
	_emit_deferred.call_deferred(false, _entity_id_of(body))


func _emit_deferred(entered: bool, entity_id: String) -> void:
	if not is_inside_tree():
		return
	if entered:
		entered_count += 1
		Events.area_entered.emit(Sim.tick, area_id, entity_id)
	else:
		exited_count += 1
		Events.area_exited.emit(Sim.tick, area_id, entity_id)


static func _entity_id_of(body: Node) -> String:
	var e: Variant = body.get("entity")
	if e is CombatEntity and (e as CombatEntity).entity_id != "":
		return (e as CombatEntity).entity_id
	var id: Variant = body.get("entity_id")
	return str(id) if typeof(id) == TYPE_STRING and id != "" else "player"
