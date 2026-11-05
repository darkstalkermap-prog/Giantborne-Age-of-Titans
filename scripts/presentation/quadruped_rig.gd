class_name QuadrupedRig
extends Node3D
## Procedural low-poly animation for four-legged actors (wolves): a trot with diagonal leg
## pairs, the head raised in a windup and snapped down when the jaws close, the body stretched
## low during a lunge, a wobble while staggered, a roll onto the side when dead, a swaying tail
## and hit flashes. Reads actor.get_rig_state() (the ActorRig keys, plus "lunging"). Purely
## presentational: never changes gameplay state.

@export var body_path: NodePath
@export var head_path: NodePath
@export var tail_path: NodePath
@export var leg_fl_path: NodePath
@export var leg_fr_path: NodePath
@export var leg_bl_path: NodePath
@export var leg_br_path: NodePath
@export var stride_length_m := 1.1
@export var leg_swing_rad := 0.7

var actor: Node3D
var body: Node3D
var head: Node3D
var tail: Node3D
var legs: Array[Node3D] = []   # FL, FR, BL, BR
var _gait := 0.0
var _time := 0.0
var _fall := 0.0
var _flash := 0.0
var _flash_applied := 0.0
var _flash_color := Color(1.0, 0.95, 0.85)
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _head_rest := Basis()


func _ready() -> void:
	actor = get_parent() as Node3D
	body = get_node_or_null(body_path) as Node3D
	head = get_node_or_null(head_path) as Node3D
	tail = get_node_or_null(tail_path) as Node3D
	for p in [leg_fl_path, leg_fr_path, leg_bl_path, leg_br_path]:
		legs.append(get_node_or_null(p) as Node3D)
	if head != null:
		_head_rest = head.basis
	_make_materials_unique(self)


func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	_flash = maxf(_flash, strength * float(Settings.get_value("hit_flash")))
	_flash_color = color


func _make_materials_unique(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mat := mi.material_override as StandardMaterial3D
			if mat != null:
				var copy := mat.duplicate() as StandardMaterial3D
				mi.material_override = copy
				_materials.append(copy)
				_base_colors.append(copy.albedo_color)
		_make_materials_unique(child)


func _process(delta: float) -> void:
	if actor == null or not actor.has_method("get_rig_state"):
		return
	_time += delta
	var s: Dictionary = actor.get_rig_state()
	var state: int = s.get("state", 0)
	var action: ActionDef = s.get("action")
	var phase: int = s.get("phase", ActionDef.Phase.NONE)
	var f: float = s.get("phase_fraction", 0.0)
	var speed: float = s.get("speed", 0.0)
	var k := 1.0 - exp(-18.0 * delta)
	# Legs: diagonal pairs swing together (FL + BR, FR + BL).
	var moving := speed > 0.3 and state == CombatController.State.LOCOMOTION
	if moving:
		_gait += delta * speed / stride_length_m * PI
	var swing := sin(_gait) * clampf(speed / 6.0, 0.25, 1.0) * leg_swing_rad if moving else 0.0
	if bool(s.get("lunging", false)):
		swing = 0.0
	for i in legs.size():
		var leg := legs[i]
		if leg == null:
			continue
		var sign_i := 1.0 if i == 0 or i == 3 else -1.0
		var target := swing * sign_i
		if bool(s.get("lunging", false)):
			target = -0.9 if i < 2 else 0.9   # front legs reach forward, hind legs push back
		leg.rotation.x = lerpf(leg.rotation.x, target, k)
	# Head: raised in the windup, snapped down on the bite, back in the recovery.
	if head != null:
		var pitch := 0.0
		if action != null:
			match phase:
				ActionDef.Phase.WINDUP:
					pitch = lerpf(0.0, 0.45, f)
				ActionDef.Phase.ACTIVE:
					pitch = -0.5
				ActionDef.Phase.RECOVERY:
					pitch = lerpf(-0.5, 0.0, f)
		head.basis = head.basis.slerp(_head_rest * Basis(Vector3.RIGHT, pitch), k)
	if tail != null:
		var wag := sin(_time * (9.0 if moving else 3.0)) * (0.35 if moving else 0.15)
		tail.rotation.y = lerpf(tail.rotation.y, wag, k)
	_update_body(s, state, phase, delta)
	_update_flash(delta)


func _update_body(s: Dictionary, state: int, phase: int, delta: float) -> void:
	if body == null:
		return
	if s.get("dead", false):
		_fall = move_toward(_fall, 1.0, delta * 1.8)
		var e := _fall * _fall * (3.0 - 2.0 * _fall)
		body.rotation = Vector3(0.0, 0.0, e * PI * 0.5)
		body.position = Vector3(e * 0.2, -e * 0.15, 0.0)
		return
	_fall = 0.0
	var target_rot := Vector3.ZERO
	var target_pos := Vector3.ZERO
	if s.get("staggered", false):
		target_rot = Vector3(0.0, 0.0, sin(_time * 14.0) * 0.12)
	elif bool(s.get("lunging", false)):
		target_rot = Vector3(-0.12, 0.0, 0.0)
		target_pos = Vector3(0.0, -0.06, 0.0)
	elif phase == ActionDef.Phase.WINDUP and state == CombatController.State.ATTACKING:
		target_rot = Vector3(0.1, 0.0, 0.0)   # crouch back before the strike
		target_pos = Vector3(0.0, -0.05, 0.05)
	var k := 1.0 - exp(-14.0 * delta)
	body.rotation = body.rotation.lerp(target_rot, k)
	body.position = body.position.lerp(target_pos, k)


func _update_flash(delta: float) -> void:
	if _flash <= 0.0 and _flash_applied <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 6.0)
	for i in _materials.size():
		_materials[i].albedo_color = _base_colors[i].lerp(_flash_color, _flash * 0.85)
	_flash_applied = _flash
