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
##
## P22 (decision 9): the rig's parts are merged per pivot into vertex-coloured meshes that share
## one material, which the rig copies once per actor (RigPaint): a hit flash sets that material's
## emission and a status tint multiplies its albedo. render_lod_m swaps the rig for its one-box
## proxy by distance (RigPaint.apply_render_lod; set by the builder for people, by EnemyActor from
## the enemy record).

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
## P22: beyond this distance (m) the renderer draws the one-box proxy instead of the rig (AI LOD
## tiers 0 and 1; RigPaint.apply_render_lod). 0 = never.
@export var render_lod_m := 0.0

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
var _material_copies: Dictionary = {}   ## source material -> this rig's copy (RigPaint)
## The copy of Visual/LodProxy under Body that the renderer shows beyond render_lod_m (P22).
var far_proxy: MeshInstance3D = null
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
	if render_lod_m > 0.0:
		set_render_lod(render_lod_m)


## P22: the distance LOD (see RigPaint): beyond lod_m metres the renderer draws the one-box proxy
## instead of the rig (0 = never). Callable again (EnemyActor applies its record's value).
func set_render_lod(lod_m: float) -> void:
	render_lod_m = maxf(0.0, lod_m)
	far_proxy = RigPaint.apply_render_lod(self, body, render_lod_m)
	_p30_apply_mid()   # P30: the merged rest-pose mesh at mid distance (low preset)


## Places the weapon shoulder exactly where the data says the hit sweep pivots. `pivot_local`
## is in the actor's space; the shoulders live in the (scaled) Body, so it is divided by the
## body scale (P05).
func set_weapon_pivot(pivot_local: Vector3) -> void:
	_pivot_local = pivot_local
	_pivot_set = true
	var p := pivot_local / body_scale
	if weapon_arm != null:
		weapon_arm.position = p
	if off_arm != null:
		off_arm.position = Vector3(-p.x, p.y, p.z)


func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	_flash = maxf(_flash, strength * float(Settings.get_value("hit_flash")))
	_flash_color = color


## Gives the meshes under `node` this rig's copies of their materials: one per source material,
## so a merged rig (one shared material) gets one material per actor (P22, RigPaint).
func _make_materials_unique(node: Node) -> void:
	RigPaint.make_unique(node, _materials, _base_colors, _material_copies)


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
		# P05: the growth stage's downward arc tilt, exact during ACTIVE like the hit sweep.
		arm.y += float(s.get("arc_pitch_offset_deg", 0.0)) * arc_offset_weight(phase, f)
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
		var dodge_arms := dodge_arm_pose(str(s.get("dodge_style", "roll")))
		arm = dodge_arms[0]
		off = dodge_arms[1]
	var moving := speed > 0.3 and state in [CombatController.State.LOCOMOTION, CombatController.State.BLOCKING]
	if moving:
		_walk_phase += delta * speed / (stride_length_m * body_scale) * PI
		_count_footfalls()
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
	_p30_promote(s)   # P30: an acting rig keeps its full detail out to render_lod_m


func _update_body(s: Dictionary, delta: float) -> void:
	if body == null:
		return
	if s.get("dead", false):
		_fall = move_toward(_fall, 1.0, delta * 1.6)
		var e := _fall * _fall * (3.0 - 2.0 * _fall)
		body.rotation = Vector3(-e * PI * 0.48, 0.0, 0.0)
		body.position = Vector3(0.0, -e * 0.15, e * 0.4) * body_scale
		return
	_fall = 0.0
	var target_rot := Vector3.ZERO
	var rate := 18.0
	if s.get("staggered", false):
		_stagger_time += delta
		target_rot = Vector3(0.14 + sin(_stagger_time * 16.0) * 0.06, 0.0, sin(_stagger_time * 9.0) * 0.05)
	else:
		_stagger_time = 0.0
		if s.get("dodging", false):
			var lean := dodge_lean(str(s.get("dodge_style", "roll")), s.get("dodge_local", Vector3.ZERO))
			target_rot = lean[0]
			rate = lean[1]
	body.rotation = body.rotation.lerp(target_rot, 1.0 - exp(-rate * delta))
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
	# P22: the tint multiplies the albedo, the flash is emission (RigPaint).
	RigPaint.paint(_materials, _base_colors, _tint, _flash, _flash_color)
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
# Growth (P05). The giant's Visual/Body is scaled uniformly by k = height / 3.6576, so the
# authored stage-1 rig keeps exactly the profile's proportions: the pivots in data are divided
# by k (set_weapon_pivot), and the club mesh (1.85 m in Body space) scales to the profile's
# weapon_scale. Collision never uses node scale (PlayerGrowth resizes the shapes). Rig-state
# keys read here: "arc_pitch_offset_deg" (the stage's downward arc tilt, added to the weapon
# arm exactly as the hit sweep adds it) and "dodge_style" (roll | sidestep).

## Emitted on every footfall of the walk cycle (each half stride); the giant shakes its camera
## on it at stage 2 and above (presentation only).
signal footfall

var body_scale := 1.0
var footfalls := 0                 ## footfalls counted so far (tests, debug)
var _pivot_local := Vector3.ZERO   ## the last set_weapon_pivot argument (actor space)
var _pivot_set := false
var _last_step := 0


## Scales Visual/Body uniformly by k and re-places the shoulders (pivots stay in actor space).
func set_body_scale(k: float) -> void:
	body_scale = maxf(k, 0.01)
	if body != null:
		body.scale = Vector3.ONE * body_scale
	if _pivot_set:
		set_weapon_pivot(_pivot_local)


## How much of the arc pitch offset the weapon arm shows at `phase` / fraction `f`: all of it
## during ACTIVE (the swept arc), easing in over the windup and out over the recovery, so the
## arm never jumps at the start or the end of a swing.
static func arc_offset_weight(phase: int, f: float) -> float:
	match phase:
		ActionDef.Phase.WINDUP:
			return clampf(f, 0.0, 1.0)
		ActionDef.Phase.ACTIVE:
			return 1.0
		ActionDef.Phase.RECOVERY:
			return 1.0 - smoothstep(0.0, 1.0, clampf(f, 0.0, 1.0))
	return 0.0


## Arm poses (weapon arm, off arm) while dodging: arms tucked for the stage-1 roll, held lower
## and wider for the heavier sidestep of stages 2-3.
static func dodge_arm_pose(style: String) -> Array:
	if style == "sidestep":
		return [Vector2(35.0, -62.0), Vector2(-35.0, -62.0)]
	return [Vector2(25.0, -50.0), Vector2(-25.0, -50.0)]


## Body lean while dodging toward `dodge_local` (actor space) and how fast it is reached:
## [rotation: Vector3, rate: float]. The roll pitches into the direction of travel; the
## sidestep mostly leans sideways, less and more slowly (the same i-frames and distance).
static func dodge_lean(style: String, dodge_local: Vector3) -> Array:
	if style == "sidestep":
		return [Vector3(-dodge_local.z * 0.08, 0.0, -dodge_local.x * 0.14), 8.0]
	return [Vector3(-dodge_local.z * 0.25, 0.0, -dodge_local.x * 0.25), 18.0]


## Emits `footfall` once for every half stride (pi of walk phase) since the last call.
func _count_footfalls() -> void:
	var step := int(floor(_walk_phase / PI))
	if step == _last_step:
		return
	_last_step = step
	footfalls += 1
	footfall.emit()

## @anchor P07
# Grabbing, holding and throwing a body (P07). PlayerGrab.rig_state() writes "holding" (the held
# body's attachment profile, "" when the hand is empty) and "grab_phase" ("reach", "hold",
# "crush", "throw" or ""), and puts grab_pose() into "pose_override". The hand that holds - the
# off hand, the club stays in the right; both hands for a two_hand hold in third person - points
# at the socket where PlayerGrab places the held body, so the visible grip is the simulated one.
# In first person the socket is low and to the left, so neither the arm nor the body covers the
# crosshair.

const GRAB_REACH_POSE := Vector2(-8.0, -20.0)        ## off arm at the end of a grab windup
const THROW_RELEASE_POSE := Vector2(-6.0, 12.0)      ## off arm as a throw lets go
const CRUSH_SHAKE_DEG := 2.5


## (yaw, pitch) in degrees that point an arm from `shoulder` at `point` (both in actor space;
## the inverse of AttackGeometry.local_direction).
static func aim_pose(shoulder: Vector3, point: Vector3) -> Vector2:
	var d := point - shoulder
	if d.length_squared() < 1e-10:
		return Vector2.ZERO
	d = d.normalized()
	return Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))


## The arm poses of a grab phase, as a "pose_override": {"arm": weapon arm, "off": off arm,
## "exact": false}. `socket` is the hand socket and `pivot` the weapon shoulder (the off shoulder
## mirrors it), both in actor space; `two_hands` puts the weapon hand on the socket too (a two_hand
## hold in third person; in first person every hold is the off hand's, low and to the left);
## `phase` / `f` are the running action's phase and fraction; `time_s` drives the squeeze.
##   reach  the off hand reaches forward over the windup
##   hold   the off hand (two hands: both) on the socket
##   crush  the hold, squeezing
##   throw  the hold while it winds back (the socket moves), then the arm follows through
static func grab_pose(grab_phase: String, two_hands: bool, socket: Vector3, pivot: Vector3,
		idle_arm: Vector2, idle_off: Vector2, phase: int, f: float, time_s: float) -> Dictionary:
	var off_shoulder := Vector3(-pivot.x, pivot.y, pivot.z)
	var hold_off := aim_pose(off_shoulder, socket)
	var hold_arm := aim_pose(pivot, socket) if two_hands else idle_arm
	var t := clampf(f, 0.0, 1.0)
	match grab_phase:
		"reach":
			return {"arm": idle_arm, "off": idle_off.lerp(GRAB_REACH_POSE, 1.0 - (1.0 - t) * (1.0 - t)),
				"exact": false}
		"crush":
			var shake := Vector2(sin(time_s * 55.0), cos(time_s * 47.0)) * CRUSH_SHAKE_DEG
			return {"arm": hold_arm + shake * 0.5, "off": hold_off + shake, "exact": false}
		"throw":
			if phase == ActionDef.Phase.ACTIVE or phase == ActionDef.Phase.RECOVERY:
				var settle := smoothstep(0.0, 1.0, t) if phase == ActionDef.Phase.RECOVERY else 0.0
				return {"arm": idle_arm, "off": THROW_RELEASE_POSE.lerp(idle_off, settle), "exact": false}
	return {"arm": hold_arm, "off": hold_off, "exact": false}

## @anchor P08
# Weapon visuals (P08). PlayerEquipment builds the mesh of the equipped weapon (WeaponVisuals) and
# hands it to set_weapon_visual(): it goes under the weapon arm at the hand, replaces (hides) the
# generated Club mesh, and its materials join the rig's flash and status-tint list (the previous
# weapon's leave it). The caller sets the node's scale (effective_weapon_scale / body_scale) and,
# for the tree, idle_arm_pose.

var weapon_visual: Node3D = null


## Puts `node` ("Weapon") in the weapon hand at `hand_offset` (weapon-arm space) instead of the
## current weapon mesh; null puts the generated Club back.
func set_weapon_visual(node: Node3D, hand_offset := Vector3(0.0, 0.0, -1.5)) -> void:
	if weapon_visual != null and is_instance_valid(weapon_visual):
		_forget_materials(weapon_visual)
		if weapon_visual.get_parent() != null:
			weapon_visual.get_parent().remove_child(weapon_visual)
		weapon_visual.queue_free()
	weapon_visual = node
	var club := weapon_arm.get_node_or_null("Club") as Node3D if weapon_arm != null else null
	if club != null:
		club.visible = node == null
	if node == null or weapon_arm == null:
		return
	node.position = hand_offset
	weapon_arm.add_child(node)
	_make_materials_unique(node)
	_tint_dirty = true


func _forget_materials(node: Node) -> void:
	RigPaint.forget(node, _materials, _base_colors, _material_copies)


# --- the mid distance (P30, FOLLOWUPS: Valley views at low under 250 draw calls) -------------------
# Hook lines: set_render_lod (_p30_apply_mid) and _process (_p30_promote). At the `low` preset the
# rig draws as one merged mesh of its rest pose between 0.45 x render_lod_m and render_lod_m
# (RigPaint's mid distance); while it acts (an action, staggered, dead, held) it is promoted to its
# full rig out to render_lod_m.

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
