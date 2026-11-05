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

const OUT_OF_RANGE := "out_of_range"

var runner: AttackRunner


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


func on_action_started(action: ActionDef, _instance_id: int) -> void:
	if action.kind in ["light", "heavy", "ability", "ultimate"]:
		runner.prev_segment = PackedVector3Array()
		player.stats.attacks += 1


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


## The tilt of `action`'s arc at the current stage: the profile's arc_pitch_offsets_deg entry
## for the action, else its arc_pitch_offset_deg.
func arc_pitch_offset_for(action: ActionDef) -> float:
	return offset_for(player.profile, action.id if action != null else "")


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
