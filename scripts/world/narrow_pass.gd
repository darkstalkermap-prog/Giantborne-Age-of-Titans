class_name NarrowPass
extends Area3D
## A pass only a small giant fits (P35; plan M6-M9 §5.5): the Needle, a 5 m slot through the Hidden
## Grove's ridge that a giant of stage 3 or 4 walks and a bigger one cannot enter (its walls stop the
## capsule: no physics here). This sensing area along the slot names the reason: while a giant above
## max_stage touches it, the message goes to the HUD as a warning and Events.size_gate_blocked(tick,
## pass_id, 0, message) goes out (the audio router plays `cue` at last_contact: it finds this node
## in group "size_gates" by gate_id), at most once every BLOCKED_GAP_TICKS (4 s), checked in the
## simulation tick. A giant that fits passes in silence. Built by the world builder's narrow_pass kind
## (tools/world/kinds/narrow_pass.gd): a box along the slot, a little longer than it.

const GROUP := "size_gates"
const BLOCKED_GAP_TICKS := 240
const HOOK_ORDER := 61

## Stable id (the event's gate_id).
@export var pass_id := "world.gate.needle"
## The biggest stage that fits.
@export var max_stage := 4
@export var message := "Too narrow. You have outgrown the Needle: it fits a giant of stage 4 or less."
## The contact sound (sfx.gate.stone).
@export var cue := "sfx.gate.stone"

## The point of the slot's mouth nearest the giant when it last pushed in (INF before).
var last_contact := Vector3.INF
## Refusals sent so far (tests, debug).
var blocked_count := 0
## The audio router looks size gates up by gate_id.
var gate_id: String:
	get:
		return pass_id
var _player: Node3D = null
var _last_tick := -1000000


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)
		Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_sim_tick, HOOK_ORDER)


func _ready() -> void:
	collision_layer = 0
	collision_mask = HitQueryAdapter.LAYER_ACTORS
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	_player = null


## True when a giant of `stage` fits through.
func fits(stage: int) -> bool:
	return stage <= max_stage


func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null


## Refuses `body` now if it is too big (tests may call it): true when a refusal went out.
func refuse(body: Node3D, tick: int = Sim.tick) -> bool:
	if body == null or fits(SizeGate.stage_of(body)) or tick - _last_tick < BLOCKED_GAP_TICKS:
		return false
	_last_tick = tick
	last_contact = _mouth_point(body.global_position)
	blocked_count += 1
	Events.size_gate_blocked.emit(tick, pass_id, 0, message)
	Events.hud_message.emit(message, "warn")
	return true


func _on_sim_tick(tick: int) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		return
	refuse(_player, tick)


## The point of the area's box nearest `pos` (its centre without a box).
func _mouth_point(pos: Vector3) -> Vector3:
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var half := (cs.shape as BoxShape3D).size * 0.5
		var local := cs.global_transform.affine_inverse() * pos
		return cs.global_transform * Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y),
			clampf(local.z, -half.z, half.z))
	return global_position
