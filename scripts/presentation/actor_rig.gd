class_name ActorRig
extends Node3D
## Procedural low-poly animation for humanoid actors (the giant and soldiers).
##
## Reads the actor's combat state through get_rig_state() and poses limb pivots. During an
## attack's active window the weapon arm uses AttackGeometry exactly, so the swing on screen
## is the swing the hit sweep tests. Purely presentational: never changes gameplay state.
##
## Poses by hit shape: weapon_arc (exact arc), cylinder_pulse (stomp; a roar - a pulse with
## morale damage - flings both arms wide), sector_pulse (a wide horizontal sweep), projectile
## (a one-hand cast, or a two-hand overhead throw for boulders and bodies) and none (a two-arm
## flex for self buffs). A rig state may carry "pose_override": {"arm": Vector2, "off":
## Vector2, "exact": bool} (yaw, pitch in degrees) from a player component's rig_state(), which
## wins over every pose (P07 holding). set_status_tint() keeps a status colour on the materials
## (HitFeedback); hit flashes still play on top of it.

@export var weapon_arm_path: NodePath
@export var off_arm_path: NodePath
@export var leg_left_path: NodePath
@export var leg_right_path: NodePath
@export var torso_path: NodePath
@export var body_path: NodePath
@export var idle_arm_pose := Vector2(12.0, -78.0)    ## (yaw, pitch) of the weapon arm at rest
@export var off_idle_pose := Vector2(-10.0, -80.0)
@export var block_pose := Vector2(-45.0, 12.0)
@export var off_block_pose := Vector2(30.0, 8.0)
@export var stride_length_m := 1.6
@export var leg_swing_rad := 0.55

var actor: Node3D
var weapon_arm: Node3D
var off_arm: Node3D
var leg_left: Node3D
var leg_right: Node3D
var torso: Node3D
var body: Node3D
var _walk_phase := 0.0
var _flash := 0.0
var _flash_color := Color(1.0, 0.95, 0.85)
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _fall := 0.0
var _stagger_time := 0.0
var _arm := Vector2.ZERO
var _off := Vector2.ZERO


func _ready() -> void:
	actor = get_parent() as Node3D
	weapon_arm = get_node_or_null(weapon_arm_path) as Node3D
	off_arm = get_node_or_null(off_arm_path) as Node3D
	leg_left = get_node_or_null(leg_left_path) as Node3D
	leg_right = get_node_or_null(leg_right_path) as Node3D
	torso = get_node_or_null(torso_path) as Node3D
	body = get_node_or_null(body_path) as Node3D
	_arm = idle_arm_pose
	_off = off_idle_pose
	_make_materials_unique(self)


## Places the weapon shoulder exactly where the data says the hit sweep pivots.
func set_weapon_pivot(pivot_local: Vector3) -> void:
	if weapon_arm != null:
		weapon_arm.position = pivot_local
	if off_arm != null:
		off_arm.position = Vector3(-pivot_local.x, pivot_local.y, pivot_local.z)


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


static func _aim(node: Node3D, pose: Vector2) -> void:
	if node == null:
		return
	var dir := AttackGeometry.local_direction(pose.x, clampf(pose.y, -AttackGeometry.MAX_PITCH_DEG, AttackGeometry.MAX_PITCH_DEG))
	node.basis = Basis.looking_at(dir, Vector3.UP)


func _process(delta: float) -> void:
	if actor == null or not actor.has_method("get_rig_state"):
		return
	var s: Dictionary = actor.get_rig_state()
	var state: int = s.get("state", 0)
	var action: ActionDef = s.get("action")
	var phase: int = s.get("phase", ActionDef.Phase.NONE)
	var f: float = s.get("phase_fraction", 0.0)
	var speed: float = s.get("speed", 0.0)
	var arm := idle_arm_pose
	var off := off_idle_pose
	var exact := false
	var twist := 0.0
	var override: Variant = s.get("pose_override")
	if typeof(override) == TYPE_DICTIONARY:
		arm = override.get("arm", arm)
		off = override.get("off", off)
		exact = bool(override.get("exact", false))
	elif action != null and action.hit_shape in ["sector_pulse", "projectile", "none"] \
			and action.is_attack():
		var pose := ability_pose(action, phase, f)
		arm = pose[0]
		off = pose[1]
		twist = deg_to_rad(pose[2])
	elif action != null and action.hit_shape == "weapon_arc":
		arm = AttackGeometry.pose_for(action, phase, f, idle_arm_pose)
		exact = phase == ActionDef.Phase.ACTIVE
		off = off_idle_pose + Vector2(0.0, 30.0)
		twist = -deg_to_rad(arm.x) * 0.3
	elif action != null and action.hit_shape == "cylinder_pulse" \
			and float(action.param("morale_damage", 0.0)) > 0.0:
		var pose := ability_pose(action, phase, f)
		arm = pose[0]
		off = pose[1]
	elif action != null and action.hit_shape == "cylinder_pulse":
		var raised := Vector2(20.0, 70.0)
		var slammed := Vector2(10.0, -70.0)
		match phase:
			ActionDef.Phase.WINDUP:
				arm = idle_arm_pose.lerp(raised, f)
				off = off_idle_pose.lerp(Vector2(-raised.x, raised.y), f)
			ActionDef.Phase.ACTIVE:
				arm = slammed
				off = Vector2(-slammed.x, slammed.y)
			_:
				arm = slammed.lerp(idle_arm_pose, f)
				off = Vector2(-slammed.x, slammed.y).lerp(off_idle_pose, f)
	elif state == CombatController.State.BLOCKING or s.get("guarding", false):
		arm = block_pose
		off = off_block_pose
	elif state == CombatController.State.DODGING:
		arm = Vector2(25.0, -50.0)
		off = Vector2(-25.0, -50.0)
	var moving := speed > 0.3 and state in [CombatController.State.LOCOMOTION, CombatController.State.BLOCKING]
	if moving:
		_walk_phase += delta * speed / stride_length_m * PI
	var swing := sin(_walk_phase) * clampf(speed / 5.0, 0.0, 1.2) if moving else 0.0
	if state == CombatController.State.LOCOMOTION and action == null:
		arm.y += swing * 16.0
		off.y -= swing * 16.0
	if exact:
		_arm = arm
	else:
		_arm = _arm.lerp(arm, 1.0 - exp(-25.0 * delta))
	_off = _off.lerp(off, 1.0 - exp(-15.0 * delta))
	_aim(weapon_arm, _arm)
	_aim(off_arm, _off)
	var leg_target := swing * leg_swing_rad
	if leg_left != null:
		leg_left.rotation.x = lerpf(leg_left.rotation.x, leg_target, 1.0 - exp(-20.0 * delta))
	if leg_right != null:
		leg_right.rotation.x = lerpf(leg_right.rotation.x, -leg_target, 1.0 - exp(-20.0 * delta))
	if torso != null:
		torso.rotation.y = lerpf(torso.rotation.y, twist, 1.0 - exp(-12.0 * delta))
	_update_body(s, delta)
	_update_flash(delta)


func _update_body(s: Dictionary, delta: float) -> void:
	if body == null:
		return
	if s.get("dead", false):
		_fall = move_toward(_fall, 1.0, delta * 1.6)
		var e := _fall * _fall * (3.0 - 2.0 * _fall)
		body.rotation = Vector3(-e * PI * 0.48, 0.0, 0.0)
		body.position = Vector3(0.0, -e * 0.15, e * 0.4)
		return
	_fall = 0.0
	var target_rot := Vector3.ZERO
	if s.get("staggered", false):
		_stagger_time += delta
		target_rot = Vector3(0.14 + sin(_stagger_time * 16.0) * 0.06, 0.0, sin(_stagger_time * 9.0) * 0.05)
	else:
		_stagger_time = 0.0
		if s.get("dodging", false):
			var d: Vector3 = s.get("dodge_local", Vector3.ZERO)
			target_rot = Vector3(-d.z * 0.25, 0.0, -d.x * 0.25)
	body.rotation = body.rotation.lerp(target_rot, 1.0 - exp(-18.0 * delta))
	body.position = body.position.lerp(Vector3.ZERO, 1.0 - exp(-18.0 * delta))


var _flash_applied := 0.0
var _tint := Color(0.0, 0.0, 0.0, 0.0)   ## rgb = status colour, a = strength (0 = none)
var _tint_dirty := false


## A lasting status colour (alpha = strength, 0 removes it), e.g. stone grey under Stone Skin.
func set_status_tint(color: Color) -> void:
	if color.is_equal_approx(_tint):
		return
	_tint = color
	_tint_dirty = true


func status_tint() -> Color:
	return _tint


func _update_flash(delta: float) -> void:
	if _flash <= 0.0 and _flash_applied <= 0.0 and not _tint_dirty:
		return  # nothing to fade: do not touch the materials every frame
	_tint_dirty = false
	_flash = maxf(0.0, _flash - delta * 6.0)
	var tint_rgb := Color(_tint.r, _tint.g, _tint.b)
	for i in _materials.size():
		var base := _base_colors[i].lerp(tint_rgb, clampf(_tint.a, 0.0, 1.0))
		_materials[i].albedo_color = base.lerp(_flash_color, _flash * 0.85)
	_flash_applied = _flash


## Arm poses (yaw, pitch in degrees) and the torso twist (degrees) of the ability shapes:
## [weapon arm, off arm, twist] at `phase` and phase fraction `f`.
func ability_pose(action: ActionDef, phase: int, f: float) -> Array:
	var idle := idle_arm_pose
	var off_idle := off_idle_pose
	var t := clampf(f, 0.0, 1.0)
	var e := 1.0 - (1.0 - t) * (1.0 - t)
	var settle := smoothstep(0.0, 1.0, t)
	match action.hit_shape:
		"sector_pulse":
			var wound := Vector2(110.0, 5.0)
			var swept := Vector2(-110.0, 0.0)
			var guard := Vector2(-30.0, 20.0)
			match phase:
				ActionDef.Phase.WINDUP:
					return [idle.lerp(wound, e), off_idle.lerp(guard, e), 25.0 * e]
				ActionDef.Phase.ACTIVE:
					return [wound.lerp(swept, t), guard, lerpf(25.0, -25.0, t)]
			return [swept.lerp(idle, settle), guard.lerp(off_idle, settle), lerpf(-25.0, 0.0, t)]
		"projectile":
			var spec: Variant = action.param("projectile", {})
			var visual := str((spec as Dictionary).get("visual", "bolt")) if typeof(spec) == TYPE_DICTIONARY else "bolt"
			if visual in ["boulder", "thrown_body"]:
				var up := Vector2(15.0, 85.0)
				var down := Vector2(10.0, 5.0)
				match phase:
					ActionDef.Phase.WINDUP:
						return [idle.lerp(up, e), off_idle.lerp(Vector2(-up.x, up.y), e), 0.0]
					ActionDef.Phase.ACTIVE:
						return [down, Vector2(-down.x, down.y), 0.0]
				return [down.lerp(idle, settle), Vector2(-down.x, down.y).lerp(off_idle, settle), 0.0]
			var raised := Vector2(-25.0, 55.0)
			var thrust := Vector2(-5.0, 5.0)
			match phase:
				ActionDef.Phase.WINDUP:
					return [idle, off_idle.lerp(raised, e), -10.0 * e]
				ActionDef.Phase.ACTIVE:
					return [idle, thrust, -10.0]
			return [idle, thrust.lerp(off_idle, settle), lerpf(-10.0, 0.0, t)]
		"cylinder_pulse":
			var pulled := Vector2(30.0, -40.0)
			var wide := Vector2(85.0, 20.0)
			match phase:
				ActionDef.Phase.WINDUP:
					return [idle.lerp(pulled, e), off_idle.lerp(Vector2(-pulled.x, pulled.y), e), 0.0]
				ActionDef.Phase.ACTIVE:
					return [wide, Vector2(-wide.x, wide.y), 0.0]
			return [wide.lerp(idle, settle), Vector2(-wide.x, wide.y).lerp(off_idle, settle), 0.0]
	var flex := Vector2(45.0, 35.0)
	match phase:
		ActionDef.Phase.WINDUP:
			return [idle.lerp(flex, e), off_idle.lerp(Vector2(-flex.x, flex.y), e), 0.0]
		ActionDef.Phase.ACTIVE:
			return [flex, Vector2(-flex.x, flex.y), 0.0]
	return [flex.lerp(idle, settle), Vector2(-flex.x, flex.y).lerp(off_idle, settle), 0.0]


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5): P05 the body
# scale k of a growth stage (pivots in Body space are pivot / k), P07 holding and throwing a
# body (a component's rig_state() can also set "pose_override"), P08 the weapon visual per
# weapon record.

## @anchor P05

## @anchor P07

## @anchor P08
