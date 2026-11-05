class_name PlayerAttack
extends PlayerComponent
## The giant's weapon geometry and hit queries. Hits are produced by a shared AttackRunner
## (one handler per hit shape) and built by HitFactory, exactly like every enemy's.
##
## Geometry (player.weapon_pivot, attack_origin, arm_length, weapon_length, weapon_radius) is
## a cache read from the growth profile and the weapon record; it is refreshed when either
## changes, never mid-swing.
##
## Projectiles (P03): the runner asks resolve_launch() where a projectile starts and what it
## flies at. launch_offset_m is authored for the stage-1 giant and scales with k = height /
## 3.6576; "lock_or_camera" aims at the locked target's anchor, otherwise at the point under
## the crosshair (a camera ray up to the range).
##
## Range (P16, M2 review): a projectile slot aimed at a locked target its shot cannot reach (the
## shot would fizzle at its range) is refused with "out_of_range" and spends nothing. The same
## check is the slot's precheck in the HUD (preview_params) and in the request (handle_edge;
## PlayerGrab's slots call range_reason too), so the hotbar's "Out of range" and the controller
## never disagree.
##
## Vertical aim (P17b, the balance pass): a weapon swing tilts up toward the giant's target when the
## stage's default tilt (arc_pitch_offset_deg, which brings the arcs down to the giant's feet:
## decision 5) would pass over it. When a swing starts, its target is the hard lock, else the soft
## target in front (PlayerTargeting.soft_target, the yaw nudge's pick). The default tilt stays when
## its sweep passes through the core of the target's body (within the weapon's radius plus
## AIM_CORE of the target's: hurtboxes are narrower than the capsule); otherwise the swing takes the
## tilt, in AIM_STEP_DEG steps from the default up to AIM_MAX_OFFSET_DEG, whose sweep passes closest
## to the target's axis (AttackGeometry, the target taken straight ahead at its distance and
## height), as long as that one reaches the body at all; else the default. Without a target, or
## when the default already reaches it, the swing is unchanged (a wolf at the feet is hit as before).
## The rig draws the same tilt (rig_state).
## With it a light reaches about the §4.8 table's distances against a soldier: 3.5 m at stage 1,
## about 5 m at stage 2, about 7 m with a reforged weapon at stage 3, where the fixed downward tilt
## stopped short at about 3.3 / 4.0 / 3.5 m (P17a's measurement), so stages 2 and 3 never felt their
## reach and a stage-2 giant could not strike a holding soldier from beyond its spear.

const OUT_OF_RANGE := "out_of_range"
## Vertical aim (P17b): the lift step and the highest tilt an aimed swing may take (degrees; the
## stage's default tilt is the lowest).
const AIM_STEP_DEG := 2.0
const AIM_MAX_OFFSET_DEG := 16.0
## The share of the target's radius an aimed swing wants to pass within (its body's core).
const AIM_CORE := 0.5
## Arc samples of the aim's reach test (as BotCombat.reach_band).
const AIM_SAMPLES := 25

var runner: AttackRunner
## The aimed tilt of the swing running now (instance id, action id, degrees); -1 = none.
var _aim_instance := -1
var _aim_action := ""
var _aim_offset := 0.0


func setup(p: GiantPlayer) -> void:
	super(p)
	runner = AttackRunner.new(player, player.entity, player.controller)
	runner.emit_clank = true
	runner.launch_resolver = resolve_launch
	refresh_geometry()


## Reads the weapon geometry cache from the profile and the weapon. The weapon's length and
## radius follow player.current_weapon_scale() (1.0 until growth profiles carry weapon_scale).
func refresh_geometry() -> void:
	var profile := player.profile
	var w := player.weapon
	var p: Array = profile.get("weapon_pivot_m", [0.82, 2.9, 0.0])
	player.weapon_pivot = Vector3(p[0], p[1], p[2])
	var o: Array = profile.get("attack_origin_m", [0.0, 2.6, 0.0])
	player.attack_origin = Vector3(o[0], o[1], o[2])
	player.arm_length = float(profile.get("arm_length_m", 1.5))
	var weapon_scale := player.current_weapon_scale()
	player.weapon_length = float(w.get("length_m", 1.85)) * weapon_scale
	player.weapon_radius = float(w.get("hit_radius_m", 0.45)) * weapon_scale


func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	refresh_geometry()
	runner.reset()


func on_weapon_changed(_weapon: Dictionary) -> void:
	refresh_geometry()
	runner.reset()


func on_action_started(action: ActionDef, instance_id: int) -> void:
	if action.kind in ["light", "heavy", "ability", "ultimate"]:
		runner.prev_segment = PackedVector3Array()
		player.stats.attacks += 1
	_start_aim(action, instance_id)


## Weapon segment (shoulder-side end, tip) in world space at fraction f of the action's arc.
## The rig poses the arm with the same AttackGeometry, so the visible swing is the tested one.
## The growth profile's arc pitch offset (arc_pitch_offset_for) tilts the arc downward, so a big
## giant still reaches soldiers and wolves at its feet (decision 5); the rig adds the same tilt
## (rig state "arc_pitch_offset_deg").
func weapon_segment_global(action: ActionDef, f: float) -> PackedVector3Array:
	var ang := AttackGeometry.arc_point(action, f)
	var dir := AttackGeometry.local_direction(ang.x, ang.y + arc_pitch_offset_for(action))
	var seg := AttackGeometry.segment_local(player.weapon_pivot, dir, player.arm_length,
		player.arm_length + player.weapon_length)
	return PackedVector3Array([player.to_global(seg[0]), player.to_global(seg[1])])


func run_hit_queries(tick: int) -> void:
	runner.run(tick)


## The current growth stage's downward tilt of the weapon arcs (degrees, <= 0).
func arc_pitch_offset_deg() -> float:
	return float(player.profile.get("arc_pitch_offset_deg", 0.0))


## The tilt of `action`'s arc now: the aimed tilt while that swing runs (vertical aim, P17b), else
## the stage's default - the profile's arc_pitch_offsets_deg entry for the action, else its
## arc_pitch_offset_deg.
func arc_pitch_offset_for(action: ActionDef) -> float:
	if action != null and _aim_instance >= 0 and action.id == _aim_action \
			and player.controller.action == action and player.controller.instance_id == _aim_instance:
		return _aim_offset
	return offset_for(player.profile, action.id if action != null else "")


# --------------------------------------------------------------------------- vertical aim (P17b)

## The range of tilts an aimed swing of `action` may take now: Vector2(default, highest).
func aim_offset_range(action: ActionDef) -> Vector2:
	var default := offset_for(player.profile, action.id if action != null else "")
	return Vector2(default, maxf(default, AIM_MAX_OFFSET_DEG))


## What a swing aims at: the hard lock (alive), else the soft target in front, else null.
func aim_target() -> CombatEntity:
	if player.targeting == null:
		return null
	var locked := player.targeting.locked_entity()
	if locked != null and locked.is_alive() and locked.actor != null and is_instance_valid(locked.actor):
		return locked
	if not player.is_inside_tree():
		return null
	var soft: Array = player.targeting.soft_target(player.facing_yaw)
	return soft[0] as CombatEntity if not soft.is_empty() else null


## The tilt for a swing of `action` at a target `distance` m away (horizontally, centre to centre),
## its feet `base_y` m above the giant's, of radius `t_radius` and height `t_height`: the default
## when its sweep passes through the target's core, else the tilt whose sweep passes closest to the
## target's axis if that one reaches its body, else the default.
func aimed_offset(action: ActionDef, distance: float, base_y: float, t_radius: float, t_height: float) -> float:
	var r := aim_offset_range(action)
	var wr := float(player.weapon_hit_radius())
	if closest_approach(action, r.x, distance, base_y, t_height) <= wr + t_radius * AIM_CORE:
		return r.x
	var best := r.x
	var best_m := INF
	var off := r.x
	while off <= r.y + 1e-4:
		var m := closest_approach(action, off, distance, base_y, t_height)
		if m < best_m - 1e-4:
			best_m = m
			best = off
		off += AIM_STEP_DEG
	return best if best_m <= wr + t_radius else r.x


## True when `action`'s weapon arc, tilted by `offset_deg`, passes within the weapon's radius plus
## `t_radius` of a target's axis straight ahead (from its feet to its height, `distance` m in front).
func sweep_reaches(action: ActionDef, offset_deg: float, distance: float, base_y: float, t_radius: float,
		t_height: float) -> bool:
	return closest_approach(action, offset_deg, distance, base_y, t_height) \
		<= float(player.weapon_hit_radius()) + t_radius


## How close (m) the weapon segment of `action`'s arc, tilted by `offset_deg`, passes to the axis of a
## target straight ahead `distance` m away (from base_y + 0.05 to base_y + t_height), sampled at
## AIM_SAMPLES points of the arc; INF without an arc.
func closest_approach(action: ActionDef, offset_deg: float, distance: float, base_y: float, t_height: float) -> float:
	if action == null or action.arc.is_empty():
		return INF
	var a := Vector3(0.0, base_y + 0.05, -distance)
	var b := Vector3(0.0, base_y + maxf(0.2, t_height), -distance)
	var best := INF
	for i in AIM_SAMPLES:
		var ang := AttackGeometry.arc_point(action, float(i) / float(AIM_SAMPLES - 1))
		var dir := AttackGeometry.local_direction(ang.x, ang.y + offset_deg)
		var seg := AttackGeometry.segment_local(player.weapon_pivot, dir, player.arm_length,
			player.arm_length + player.weapon_length)
		var pts := Geometry3D.get_closest_points_between_segments(seg[0], seg[1], a, b)
		best = minf(best, pts[0].distance_to(pts[1]))
	return best


func _start_aim(action: ActionDef, instance_id: int) -> void:
	_aim_instance = -1
	if action == null or action.hit_shape != "weapon_arc" or action.arc.is_empty():
		return
	var t := aim_target()
	if t == null:
		return
	var rel := player.global_transform.affine_inverse() * (t.actor as Node3D).global_position
	var radius := EnemyActor.entity_radius(t)
	_aim_offset = aimed_offset(action, Vector2(rel.x, rel.z).length(), rel.y, radius, t.combatant.height_m)
	_aim_action = action.id
	_aim_instance = instance_id


## arc_pitch_offsets_deg[action_id] of `profile` when present, else arc_pitch_offset_deg (0).
static func offset_for(profile: Dictionary, action_id: String) -> float:
	var per_action: Variant = profile.get("arc_pitch_offsets_deg")
	if typeof(per_action) == TYPE_DICTIONARY and (per_action as Dictionary).has(action_id):
		return float(per_action[action_id])
	return float(profile.get("arc_pitch_offset_deg", 0.0))


func rig_state(out: Dictionary) -> void:
	out["arc_pitch_offset_deg"] = arc_pitch_offset_for(player.controller.action)


# --------------------------------------------------------------------------- projectiles (P03)

## Projectile slots go through here (after PlayerGrab, which takes Boulder Hurl and everything
## while holding): the request carries range_reason as its precheck.
func handle_edge(edge: StringName) -> bool:
	var s := String(edge)
	if edge != &"ultimate" and not s.begins_with("slot_"):
		return false
	var key := "ultimate" if edge == &"ultimate" else s
	var def := _slot_action(key)
	if def == null or def.hit_shape != "projectile":
		return false
	var params := {"precheck": range_reason.bind(def)}
	if key == "ultimate":
		player.controller.request(&"ultimate", params)
	else:
		params["slot"] = int(key.substr(5))
		player.controller.request(&"slot", params)
	return true


## HUD hotbar (P03's hook): projectile slots get range_reason as their precheck, run after any
## precheck another component added first.
func preview_params(_slot_key: String, def: ActionDef, params: Dictionary) -> void:
	if def == null or def.hit_shape != "projectile":
		return
	var mine := range_reason.bind(def)
	var other: Variant = params.get("precheck")
	if typeof(other) == TYPE_CALLABLE and (other as Callable).is_valid():
		params["precheck"] = func() -> String:
			var why := str((other as Callable).call())
			return why if why != "" else str(mine.call())
	else:
		params["precheck"] = mine


## "out_of_range" when projectile action `a` would fly at the locked target (aim lock_or_camera
## or target) and could not reach it from its launch point: a straight shot farther than its
## range plus its radius, an arc (aimed horizontally, clamped to its range) farther than its range
## plus its splash or radius. "" otherwise (no lock, a dead target, camera or forward aim, or not
## a projectile): an unlocked shot flies at the crosshair and is never refused.
func range_reason(a: ActionDef) -> String:
	if a == null or a.hit_shape != "projectile":
		return ""
	var spec := Projectile.spec_for(a)
	if not (str(spec.aim) in ["lock_or_camera", "target"]):
		return ""
	var target := player.targeting.locked_entity() if player.targeting != null else null
	if target == null or not target.is_alive():
		return ""
	return OUT_OF_RANGE if target_distance(a, target) > reach_of(spec) + 1e-4 else ""


## The distance range_reason compares: the launch point to the target's anchor, horizontal for
## an arc (arc_to_target with gravity), straight-line otherwise.
func target_distance(a: ActionDef, target: CombatEntity) -> float:
	var spec := Projectile.spec_for(a)
	var offset: Vector3 = spec.launch_offset
	var origin := player.to_global(offset * body_scale()) if offset != Vector3.INF \
		else player.attack_origin_global()
	var to := target.anchor_position() - origin
	if _is_arc(spec):
		to.y = 0.0
	return to.length()


## How far a shot of `spec` reaches toward a target: its range plus its radius (an arc: plus the
## larger of its splash and its radius).
static func reach_of(spec: Dictionary) -> float:
	var extra := float(spec.radius_m)
	if _is_arc(spec):
		extra = maxf(extra, float(spec.impact_radius_m))
	return float(spec.range_m) + extra


static func _is_arc(spec: Dictionary) -> bool:
	return bool(spec.arc_to_target) and float(spec.gravity_mps2) > 0.0


func _slot_action(slot_key: String) -> ActionDef:
	var id := str(player.controller.loadout.get(slot_key, ""))
	return player.controller.library.get(id) if id != "" else null


## k: the giant's size relative to the stage-1 giant (launch offsets are authored for stage 1).
func body_scale() -> float:
	return float(player.profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M)) \
		/ CombatRules.REFERENCE_HEIGHT_M


## AttackRunner.launch_resolver: {"origin": launch_offset_m x k in the giant's space (or the
## attack origin), "aim": aim_point_for(spec, origin)}.
func resolve_launch(_a: ActionDef, spec: Dictionary) -> Dictionary:
	var offset: Vector3 = spec.get("launch_offset", Vector3.INF)
	var origin := player.to_global(offset * body_scale()) if offset != Vector3.INF \
		else player.attack_origin_global()
	return {"origin": origin, "aim": aim_point_for(spec, origin)}


## Aim modes: "lock_or_camera" - the locked target's anchor, otherwise the camera aim;
## "camera" - always the camera aim; "forward" - straight ahead at range; "target" - the
## runner's stored aim_point, otherwise as lock_or_camera.
func aim_point_for(spec: Dictionary, origin: Vector3) -> Vector3:
	var range_m := float(spec.get("range_m", 25.0))
	match str(spec.get("aim", "lock_or_camera")):
		"forward":
			return origin + -player.global_transform.basis.z * range_m
		"camera":
			return camera_aim_point(origin, range_m)
		"target":
			if runner.aim_point != Vector3.INF:
				return runner.aim_point
	var target := player.targeting.locked_entity()
	if target != null and target.is_alive():
		return target.anchor_position()
	return camera_aim_point(origin, range_m)


## The point under the crosshair: a ray along the camera's view (its yaw and pitch, without
## shake) from the camera, long enough to reach range_m beyond `origin`. It stops at the world,
## props and other actors' bodies, never at the giant itself; with nothing in the way it is the
## far end of the ray.
func camera_aim_point(origin: Vector3, range_m: float) -> Vector3:
	var rig := player.camera_rig
	if rig == null:
		return origin + -player.global_transform.basis.z * range_m
	var dir := Basis.from_euler(Vector3(rig.pitch, rig.yaw, 0.0)) * Vector3.FORWARD
	var from := rig.global_position
	var to := from + dir * (range_m + from.distance_to(origin))
	var q := PhysicsRayQueryParameters3D.create(from, to,
		HitQueryAdapter.OCCLUDER_MASK | HitQueryAdapter.LAYER_ACTORS, [player.get_rid()])
	q.collide_with_areas = false
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else to
