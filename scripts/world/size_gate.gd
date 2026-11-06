class_name SizeGate
extends StaticBody3D
## An invisible wall that only a giant of `min_stage` or more passes (plan M6-M9 §2.2, §2.9, §5.5,
## decision 18): the Wend's deep reach (stage 4), the Mere's deep channel (5), the Giant's Stair and
## the Moot's gate stones (6). Group "size_gates".
##
## Its physics layer is its stage's size-gate layer (7, 8, 9: 64, 128, 256). Only the giant's body
## collides with those layers, and only below their stage (PlayerGrowth sets the giant's mask to
## ACTOR_MASK | size_gate_mask); enemies, NPCs, the camera's sweep, attack occluders and sight never
## see them (enemies are kept out of gated water by their navmeshes instead). The wall is its
## CollisionShape3D children (boxes and cylinders), placed by a builder.
##
## A sensing Area3D, made at _ready from the same shapes grown by SENSE_MARGIN_M (0.5 m on every
## side: "1 m larger"), notices the giant touching the wall: while a giant below min_stage is inside
## it, Events.size_gate_blocked(tick, gate_id, min_stage, message) and the message as a HUD warning
## go out at most once every BLOCKED_GAP_TICKS (4 s), checked in the simulation tick. The gate's
## sound is `cue` (sfx.gate.water | .stone | .timber; `material` names its kind for the audio router)
## at last_contact, the point of the wall nearest the giant.

const GROUP := "size_gates"
const SENSE_MARGIN_M := 0.5
const BLOCKED_GAP_TICKS := 240
const HOOK_ORDER := 60   ## POST_RESOLVE, after the shrines (50)
## The size-gate physics layer of each gate stage (layers 7-9).
const LAYERS := {4: 64, 5: 128, 6: 256}
const DEFAULT_MESSAGES := {
	4: "Too deep to wade. Grow to stage 4.",
	5: "The channel is too deep. Grow to stage 5.",
	6: "Only a giant of the old height can pass here. Grow to stage 6.",
}

## Stable id, e.g. "world.gate.wend_deep" (the event's gate_id).
@export var gate_id := ""
## The growth stage that passes (4, 5 or 6).
@export var min_stage := 4
## The player-facing refusal ("" = DEFAULT_MESSAGES of the stage).
@export var message := ""
## The contact sound: sfx.gate.water | sfx.gate.stone | sfx.gate.timber.
@export var cue := "sfx.gate.water"

## The point of the wall nearest the giant when it last touched it (INF before).
var last_contact := Vector3.INF
## Events sent so far (tests, debug).
var blocked_count := 0
## The world id the audio router looks gates up by (= gate_id).
var world_id: String:
	get:
		return gate_id
## The kind of the wall's sound ("water", "stone", "timber"): the cue's last part.
var material: String:
	get:
		var parts := cue.split(".")
		return parts[parts.size() - 1] if parts.size() > 0 else "stone"
var _sense: Area3D = null
var _player: Node3D = null
var _last_tick := -1000000


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	collision_layer = layer_for_stage(min_stage)
	collision_mask = 0
	_build_sense()
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_sim_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


## The size-gate physics layer of a gate for `stage` (stages below 4 use layer 7, above 6 layer 9).
static func layer_for_stage(stage: int) -> int:
	return int(LAYERS[clampi(stage, 4, 6)])


## The refusal text (the default of the stage when `message` is empty).
func message_text() -> String:
	return message if message != "" else str(DEFAULT_MESSAGES.get(clampi(min_stage, 4, 6), DEFAULT_MESSAGES[4]))


## True when a giant of `stage` passes this gate.
func passes(stage: int) -> bool:
	return stage >= min_stage


## The sensing area (made at _ready).
func sense_area() -> Area3D:
	return _sense


func _build_sense() -> void:
	_sense = Area3D.new()
	_sense.name = "Sense"
	_sense.collision_layer = 0
	_sense.collision_mask = HitQueryAdapter.LAYER_ACTORS
	_sense.monitoring = true
	_sense.monitorable = false
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var grown := CollisionShape3D.new()
		grown.name = "Sense" + str(cs.name)
		grown.transform = cs.transform
		grown.shape = grown_shape(cs.shape, SENSE_MARGIN_M)
		_sense.add_child(grown)
	add_child(_sense)
	_sense.body_entered.connect(_on_body_entered)
	_sense.body_exited.connect(_on_body_exited)


## A copy of `shape` grown by `margin` on every side (boxes and cylinders; other shapes as they are).
static func grown_shape(shape: Shape3D, margin: float) -> Shape3D:
	var s := shape.duplicate() as Shape3D
	if s is BoxShape3D:
		(s as BoxShape3D).size = (shape as BoxShape3D).size + Vector3.ONE * (2.0 * margin)
	elif s is CylinderShape3D:
		(s as CylinderShape3D).radius = (shape as CylinderShape3D).radius + margin
		(s as CylinderShape3D).height = (shape as CylinderShape3D).height + 2.0 * margin
	return s


func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null


## The giant's growth stage (1 when it has none).
static func stage_of(body: Node) -> int:
	if body != null and "growth_stage" in body:
		return int(body.get("growth_stage"))
	return 1


func _on_sim_tick(tick: int) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		return
	if passes(stage_of(_player)) or tick - _last_tick < BLOCKED_GAP_TICKS:
		return
	_last_tick = tick
	last_contact = contact_point(_player.global_position)
	blocked_count += 1
	var text := message_text()
	Events.size_gate_blocked.emit(tick, gate_id, min_stage, text)
	Events.hud_message.emit(text, "warn")


## The point of the wall nearest `pos` (its shapes' boxes; the gate's origin without any).
func contact_point(pos: Vector3) -> Vector3:
	var best := global_position
	var best_d := INF
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var half := Vector3.ZERO
		if cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size * 0.5
		elif cs.shape is CylinderShape3D:
			var cyl := cs.shape as CylinderShape3D
			half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
		var xf := cs.global_transform
		var local := xf.affine_inverse() * pos
		var clamped := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y),
			clampf(local.z, -half.z, half.z))
		var p := xf * clamped
		var d := p.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best
