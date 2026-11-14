class_name QuadrupedRig
extends Node3D
## Procedural low-poly animation for four-legged actors (wolves): a trot with diagonal leg
## pairs, the head raised in a windup and snapped down when the jaws close, the body stretched
## low during a lunge, a wobble while staggered, a roll onto the side when dead, a swaying tail
## and hit flashes. Reads actor.get_rig_state() (the ActorRig keys, plus "lunging"). Purely
## presentational: never changes gameplay state. set_status_tint() keeps a status colour on the
## materials like ActorRig's (HitFeedback, P09: a slowed wolf shows it); flashes play on top.
##
## P22: the parts are merged per animated part into vertex-coloured meshes with one material per
## actor (a flash sets its emission, a tint multiplies its albedo: RigPaint), render_lod_m swaps the
## rig for its one-box proxy by distance, and `footfall` fires when a diagonal paw pair lands (each
## half gait cycle; the audio router's paw steps, P21).

## Emitted when a diagonal pair of paws lands (each half gait cycle, like ActorRig.footfall).
signal footfall

@export var body_path: NodePath
@export var head_path: NodePath
@export var tail_path: NodePath
@export var leg_fl_path: NodePath
@export var leg_fr_path: NodePath
@export var leg_bl_path: NodePath
@export var leg_br_path: NodePath
@export var stride_length_m := 1.1
@export var leg_swing_rad := 0.7
## P22: beyond this distance (m) the renderer draws the one-box proxy instead of the rig (AI LOD
## tiers 0 and 1; RigPaint.apply_render_lod). 0 = never. WolfEnemy sets it from its record.
@export var render_lod_m := 0.0

## Footfalls emitted so far (tests, debug).
var footfalls := 0
## The copy of Visual/LodProxy under Body that the renderer shows beyond render_lod_m (P22).
var far_proxy: MeshInstance3D = null
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
var _material_copies: Dictionary = {}   ## source material -> this rig's copy (RigPaint)
var _head_rest := Basis()
var _last_step := 0


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
	if render_lod_m > 0.0:
		set_render_lod(render_lod_m)


func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	_flash = maxf(_flash, strength * float(Settings.get_value("hit_flash")))
	_flash_color = color


## P22: the distance LOD (see RigPaint): beyond lod_m metres the renderer draws the one-box proxy
## instead of the rig (0 = never).
func set_render_lod(lod_m: float) -> void:
	render_lod_m = maxf(0.0, lod_m)
	far_proxy = RigPaint.apply_render_lod(self, body, render_lod_m)
	_p30_apply_mid()   # P30: the merged rest-pose mesh at mid distance (low preset)


## Gives the meshes under `node` this rig's copies of their materials (one per source: P22).
func _make_materials_unique(node: Node) -> void:
	RigPaint.make_unique(node, _materials, _base_colors, _material_copies)


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
		_count_footfalls()
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
	_p30_promote(s)   # P30: an acting rig keeps its full detail out to render_lod_m


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


var _tint := Color(0.0, 0.0, 0.0, 0.0)   ## rgb = status colour, a = strength (0 = none)
var _tint_dirty := false


## A lasting status colour (alpha = strength, 0 removes it), e.g. blue while slowed (P09).
func set_status_tint(color: Color) -> void:
	if color.is_equal_approx(_tint):
		return
	_tint = color
	_tint_dirty = true


func status_tint() -> Color:
	return _tint


func _update_flash(delta: float) -> void:
	if _flash <= 0.0 and _flash_applied <= 0.0 and not _tint_dirty:
		return
	_tint_dirty = false
	_flash = maxf(0.0, _flash - delta * 6.0)
	# P22: the tint multiplies the albedo, the flash is emission (RigPaint).
	RigPaint.paint(_materials, _base_colors, _tint, _flash, _flash_color)
	_flash_applied = _flash


## Emits `footfall` once for every half gait cycle (pi of gait phase) since the last call: the
## diagonal pairs (front left + back right, front right + back left) land in turn (P22).
func _count_footfalls() -> void:
	var step := int(floor(_gait / PI))
	if step == _last_step:
		return
	_last_step = step
	footfalls += 1
	footfall.emit()


# --- the mid distance (P30, FOLLOWUPS: Valley views at low under 250 draw calls) -------------------
# Hook lines: set_render_lod (_p30_apply_mid) and _process (_p30_promote); as ActorRig's P30 section:
# at `low` one merged rest-pose mesh between 0.45 x render_lod_m and render_lod_m, the full rig
# while it acts.

## The rig's mid-distance mesh (null when none: not at `low`, or no render_lod_m).
var mid_proxy: MeshInstance3D = null
var _p30_promoted := false


func _p30_apply_mid() -> void:
	if render_lod_m > 0.0 and RigPaint.mid_lod_wanted(self):
		var key := actor.scene_file_path if actor != null else ""
		mid_proxy = RigPaint.apply_mid_lod(body, render_lod_m, _materials[0] if not _materials.is_empty() else null, key)
		_p30_promoted = false
	elif mid_proxy != null:
		RigPaint.remove_mid_lod(body, render_lod_m)
		mid_proxy = null


func _p30_promote(s: Dictionary) -> void:
	if mid_proxy == null:
		return
	var acting := s.get("action") != null or bool(s.get("staggered", false)) or bool(s.get("dead", false)) \
		or (actor != null and actor.has_method("is_held") and bool(actor.call("is_held")))
	if acting != _p30_promoted:
		_p30_promoted = acting
		RigPaint.set_mid_active(body, not acting, render_lod_m)
