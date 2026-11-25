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
## never disagree. P26 (plan M6-M9 §2.9): an action's range_by_stage_m gives its range at the
## giant's stage (Boulder Hurl: 25 m at stages 1-3, 32 / 38 / 44 m at stages 4-6); range_reason
## checks it, and resolve_launch writes it into the spec the runner launches with (stage_spec).
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
##
## P31 (plan M6-M9 §2.11, §5.12): a projectile with launch_from "above_target" (Storm Call) starts
## launch_height_m above its aim point - the locked target's anchor, else the point under the
## crosshair within the lock range - and falls on it; it is never refused as out of range (the lock
## range bounds it). An ability with a telegraph (Earthquake's crack, Storm Call's circle) announces
## it as its windup begins (Events.telegraph_started with the lock target; TelegraphVisuals draws
## the giant's own telegraphs as cracks and keeps a telegraph "at" the target on the target).
## body_sweep (Shoulder Charge's dash, moved by PlayerMotor's motion) sweeps the giant's capsule
## from where it stood the tick before; an action's on_hit_stagger staggers the targets it hits
## (Thunderhead: 1.5 s on humans).

const OUT_OF_RANGE := "out_of_range"
## P31: the body sweep's capsule is this much wider than the giant's (Shoulder Charge).
const BODY_SWEEP_MARGIN_M := 0.4
## Vertical aim (P17b): the lift step and the highest tilt an aimed swing may take (degrees; the
## stage's default tilt is the lowest).
const AIM_STEP_DEG := 2.0
const AIM_MAX_OFFSET_DEG := 16.0
## The share of the target's radius an aimed swing wants to pass within (its body's core).
const AIM_CORE := 0.5
## Arc samples of the aim's reach test (as BotCombat.reach_band).
const AIM_SAMPLES := 25
## A2: an aimed swing at a titan aims at a band this tall about its lock point (a plate).
const A2_PLATE_BAND_M := 3.0
## A2: and may tilt as high as this (a stage-5 giant's swing reaches up to a 55 ft titan's shoulder).
const A2_PLATE_MAX_OFFSET_DEG := 40.0
## A4: and as low as this many degrees below the stage's default (a titan's shins stand at a smaller giant's knee).
const A4_PLATE_MIN_OFFSET_DEG := -30.0


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
	runner.register_shape("body_sweep", _run_body_sweep)   # P31: Shoulder Charge
	if not player.entity.hit_landed.is_connected(_on_hit_landed):
		player.entity.hit_landed.connect(_on_hit_landed)
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
	_announce_telegraph(action)


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
	if best_m > wr + t_radius:
		# C3: a body low before a big giant (a man nearer than the stage's tilt brings the weapon down): the tilts
		# below the default, down to A4_PLATE_MIN_OFFSET_DEG, are tried too (as A4 does for a titan's shins)
		off = r.x - AIM_STEP_DEG
		while off >= r.x + A4_PLATE_MIN_OFFSET_DEG - 1e-4:
			var m := closest_approach(action, off, distance, base_y, t_height)
			if m < best_m - 1e-4:
				best_m = m
				best = off
			off -= AIM_STEP_DEG
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


## A2: the tilt (from the stage's default up to A2_PLATE_MAX_OFFSET_DEG) whose sweep passes closest to a titan's plate
## `distance` m ahead and `height` m up (its lock point): the swing goes for the plate the lock frames. A4: when no
## tilt from the default up reaches it (a shin plate at a smaller giant's knee), the tilts below the default down to
## A4_PLATE_MIN_OFFSET_DEG are tried too (a strictly closer one wins: every tilt that reached before still wins).
func a2_plate_offset(action: ActionDef, distance: float, height: float) -> float:
	var r := aim_offset_range(action)
	r.y = maxf(r.y, A2_PLATE_MAX_OFFSET_DEG)   # (a titan's plates stand higher than any other target)
	var best := r.x
	var best_m := INF
	var off := r.x
	while off <= r.y + 1e-4:
		var m := closest_approach(action, off, distance, height - 0.05 - A2_PLATE_BAND_M * 0.5, A2_PLATE_BAND_M)
		if m < best_m - 1e-4:
			best_m = m
			best = off
		off += AIM_STEP_DEG
	if best_m > float(player.weapon_hit_radius()):
		off = r.x - AIM_STEP_DEG
		while off >= r.x + A4_PLATE_MIN_OFFSET_DEG - 1e-4:
			var m := closest_approach(action, off, distance, height - 0.05 - A2_PLATE_BAND_M * 0.5, A2_PLATE_BAND_M)
			if m < best_m - 1e-4:
				best_m = m
				best = off
			off -= AIM_STEP_DEG
	return best


func _start_aim(action: ActionDef, instance_id: int) -> void:
	_aim_instance = -1
	_swing_aim_instance = -1
	if action == null or action.hit_shape != "weapon_arc" or action.arc.is_empty():
		return
	# C3: the swing's tilt, its facing and the point it aims at come from the swing plan - the same one the HUD's
	# aim indicator shows (the lock, else what is under the cursor, else the soft target in front)
	var plan := swing_plan_for(action, instance_id)
	_swing_aim_point = plan.get("aim_point", Vector3.INF)
	_swing_aim_entity = plan.get("entity") as CombatEntity
	_swing_aim_instance = instance_id
	if str(plan.source) == "none":
		return
	_aim_offset = float(plan.offset)
	_aim_action = action.id
	_aim_instance = instance_id


# --------------------------------------------------------------------------- C3: the swing plan and the cursor

## C3 (decision C3-4): what a swing started now would do - the one answer the swing itself and the HUD's aim
## indicator share, so the indicator shows what the swing will strike. The aim, in order:
##   * the hard lock (alive): its lock point (a titan's plate the lock frames), as before;
##   * else what is under the cursor (the screen centre's ray from the camera, cursor_pick): the hurtbox or the
##     breakable it meets first, or the body standing where it meets the ground (within CURSOR_MAGNET_M plus a
##     share of the giant's height); the swing turns to face it (at most CURSOR_MAX_TURN_DEG off the camera's
##     yaw) and tilts toward it - a man at the feet, a titan's plate high up (the plate under the cursor, which
##     HitFactory then strikes as it strikes the plate a lock frames), a wall's face;
##   * else the soft target in front (PlayerTargeting.soft_target), as before;
##   * else nothing: the camera's yaw and the stage's tilt.
## The plan then sweeps the arc as the runner will (predicted_struck: the same weapon segments, tick by tick,
## through HitQueryAdapter.sweep_capsule, a titan's region by HitFactory.predict_titan_region) at that facing
## and tilt: "struck" is every entity the swing meets in order, "primary" the aimed one if it is struck, else the
## first struck, "reaches" whether it strikes anything, "short_m" how much nearer the aimed target must be.
## Keys: source ("lock", "cursor", "soft", "point", "none"), entity, region, aim_point, yaw, offset, struck
## ([{entity, region}]), primary, primary_region, reaches, distance, short_m.
const CURSOR_MAX_TURN_DEG := 40.0
const CURSOR_MAGNET_M := 0.6
const CURSOR_MAGNET_HEIGHT_SHARE := 0.06
const CURSOR_RANGE_REACHES := 4.0
## A bare point under the cursor raises the tilt only when it stands this share of the giant's height above his
## feet (a wall's face, a tower's top): the stage's tilt already reaches the ground in front.
const CURSOR_POINT_RAISE_SHARE := 0.25

var _swing_aim_point := Vector3.INF
var _swing_aim_entity: CombatEntity = null
var _swing_aim_instance := -1
var _plan_cache_key := ""
var _started_plan: Dictionary = {}
var _started_instance := -1
var _started_action := ""
var _plan_cache: Dictionary = {}


## The plan for a swing of `action` starting now (cached per tick and action; instance_id keys the started one).
func swing_plan_for(action: ActionDef, instance_id := -1) -> Dictionary:
	if instance_id >= 0:
		# the plan a started swing was made with stays its plan for as long as it runs
		if instance_id == _started_instance and action != null and action.id == _started_action:
			return _started_plan
		_started_plan = swing_plan(action)
		_started_instance = instance_id
		_started_action = action.id if action != null else ""
		return _started_plan
	var key := "%d|%s|%d|%.4f|%.4f" % [Sim.tick, action.id if action != null else "", instance_id,
		player.camera_rig.yaw if player.camera_rig != null else 0.0, player.camera_rig.pitch if player.camera_rig != null else 0.0]
	if key == _plan_cache_key:
		return _plan_cache
	_plan_cache = swing_plan(action)
	_plan_cache_key = key
	return _plan_cache


## The plan of the light (or the heavy) a press would start now: the HUD's aim indicator.
func next_swing_plan(heavy := false) -> Dictionary:
	var c := player.controller
	var id := str(c.loadout.get("heavy", "")) if heavy else c.next_light_id()
	var def: ActionDef = c.library.get(id) if id != "" else null
	if def == null or def.hit_shape != "weapon_arc" or def.arc.is_empty():
		return {}
	return swing_plan_for(def)


func swing_plan(action: ActionDef) -> Dictionary:
	var out := {"source": "none", "entity": null, "region": "", "aim_point": Vector3.INF, "yaw": _camera_yaw(),
		"offset": offset_for(player.profile, action.id if action != null else ""), "struck": [], "primary": null,
		"primary_region": "", "reaches": false, "distance": 0.0, "short_m": 0.0, "too_close": false}
	if action == null or action.arc.is_empty() or not player.is_inside_tree():
		return out
	var h := float(player.profile.get("height_m", 3.66))
	var locked := player.targeting.locked_entity() if player.targeting != null else null
	var t: CombatEntity = null
	var point := Vector3.INF
	if locked != null and locked.is_alive() and locked.actor != null and is_instance_valid(locked.actor):
		t = locked
		out.source = "lock"
		point = locked.lock_anchor_position(h)
		out.yaw = player.motor.yaw_to(locked.anchor_position()) if player.motor != null else out.yaw
	else:
		var pick := cursor_pick(action)
		if pick.has("entity"):
			t = pick.entity
			out.source = "cursor"
			out.region = str(pick.get("region", ""))
			point = pick.aim
			out.yaw = _turn_toward(point)
		elif pick.has("point"):
			point = pick.point   # (a bare point keeps the camera's yaw: no turn for the shoulder camera's parallax)
			out.source = "point"
		if t == null:
			var soft: Array = player.targeting.soft_target(_camera_yaw()) if player.targeting != null else []
			if not soft.is_empty():
				t = soft[0]
				out.source = "soft"
				point = t.anchor_position()
				out.region = ""
				var max_rad := deg_to_rad(action.soft_target_max_deg)
				out.yaw = wrapf(_camera_yaw() + clampf(float(soft[1]), -max_rad, max_rad), -PI, PI)
	out.entity = t
	out.aim_point = point
	var xf := Transform3D(Basis(Vector3.UP, float(out.yaw)), player.global_position)
	var inv := xf.affine_inverse()
	if t != null:
		var rel := inv * (t.actor as Node3D).global_position
		out.distance = Vector2(rel.x, rel.z).length()
		if t.plates != null and point.is_finite():
			var at := inv * point
			out.offset = a2_plate_offset(action, Vector2(at.x, at.z).length(), at.y)
		else:
			out.offset = aimed_offset(action, out.distance, rel.y, EnemyActor.entity_radius(t), t.combatant.height_m)
	elif str(out.source) == "point":
		var at := inv * point
		out.distance = Vector2(at.x, at.z).length()
		if at.y >= CURSOR_POINT_RAISE_SHARE * h:
			out.offset = _point_offset(action, out.distance, at.y)
	var struck := predicted_struck(action, float(out.yaw), float(out.offset), point if t != null else Vector3.INF, t)
	out.struck = struck
	for s: Dictionary in struck:
		if t != null and s.entity == t:
			out.primary = t
			out.primary_region = s.region
			break
	if out.primary == null and not struck.is_empty():
		out.primary = struck[0].entity
		out.primary_region = struck[0].region
	out.reaches = out.primary != null
	out["too_close"] = false
	if t != null and out.primary != t:
		out.short_m = maxf(0.0, out.distance - reach_estimate(action))
		out.too_close = out.short_m <= 0.0 and out.distance < 0.5 * reach_estimate(action)
	return out


## The swing's horizontal reach: arm and weapon from the pivot, at its widest (a guide for "out of reach").
func reach_estimate(_action: ActionDef) -> float:
	return player.arm_length + player.weapon_length + float(player.weapon_hit_radius())


func _camera_yaw() -> float:
	return player.camera_rig.yaw if player.camera_rig != null else player.facing_yaw


## The facing toward `point`, if within CURSOR_MAX_TURN_DEG of the camera's yaw (else the camera's yaw).
func _turn_toward(point: Vector3) -> float:
	var cam := _camera_yaw()
	if not point.is_finite():
		return cam
	var to := point - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return cam
	var want := TargetingRules.yaw_of(to)
	return want if absf(rad_to_deg(TargetingRules.yaw_delta(cam, want))) <= CURSOR_MAX_TURN_DEG else cam


## The tilt whose sweep passes closest to a point `distance` m ahead and `height` m up (a bare point under the
## cursor, aimed high), from the stage's default up to A2_PLATE_MAX_OFFSET_DEG; the default when none reaches it.
func _point_offset(action: ActionDef, distance: float, height: float) -> float:
	var r := aim_offset_range(action)
	r.y = maxf(r.y, A2_PLATE_MAX_OFFSET_DEG)
	var best := r.x
	var best_m := INF
	var off := r.x
	while off <= r.y + 1e-4:
		var m := closest_approach(action, off, distance, height - 0.3, 0.6)
		if m < best_m - 1e-4:
			best_m = m
			best = off
		off += AIM_STEP_DEG
	return best if best_m <= float(player.weapon_hit_radius()) * 2.0 else r.x


## What the screen centre's ray from the camera meets: {"entity", "hurtbox", "region", "aim" (the point to strike:
## the hurtbox's centre, else the body's anchor), "point" (where the ray met it)}, or {"point"} (the world, nothing
## to strike there), or {} (nothing within CURSOR_RANGE_REACHES reaches). Only bodies the giant's blows damage.
func cursor_pick(action: ActionDef) -> Dictionary:
	var rig := player.camera_rig
	if rig == null or not rig.is_inside_tree():
		return {}
	var dir := Basis.from_euler(Vector3(rig.pitch, rig.yaw, 0.0)) * Vector3.FORWARD
	var from := rig.global_position
	var reach := reach_estimate(action)
	var length := from.distance_to(player.global_position) + reach * CURSOR_RANGE_REACHES + 2.0
	var to := from + dir * length
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, to,
			HitQueryAdapter.LAYER_HURTBOX | HitQueryAdapter.OCCLUDER_MASK, exclude)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var col: Object = hit.collider
		if col is Hurtbox:
			var hb := col as Hurtbox
			if _strikable(hb.entity):
				return {"entity": hb.entity, "hurtbox": hb, "region": hb.region, "aim": _aim_of(hb.entity, hb),
					"point": hit.position}
			exclude.append(hb.get_rid())
			continue
		var owner := _entity_of(col as Node)
		if _strikable(owner):
			var hb2 := _nearest_hurtbox(owner, hit.position)
			return {"entity": owner, "hurtbox": hb2, "region": hb2.region if hb2 != null else "",
				"aim": _aim_of(owner, hb2), "point": hit.position}
		var near := _magnet(hit.position)
		if not near.is_empty():
			return near
		return {"point": hit.position}
	return {}


func _strikable(e: CombatEntity) -> bool:
	return e != null and is_instance_valid(e) and e != player.entity and e.is_alive() and e.actor != null \
		and is_instance_valid(e.actor) and CombatEntity.can_damage(player.entity.team, e.team)


static func _aim_of(e: CombatEntity, hb: Hurtbox) -> Vector3:
	if e.plates != null and hb != null:
		return hb.global_position
	return hb.global_position if hb != null else e.anchor_position()


## The CombatEntity a body (a breakable's block, a siege engine) belongs to: its own or an ancestor's.
static func _entity_of(n: Node) -> CombatEntity:
	while n != null:
		var e: Variant = n.get("entity")
		if e is CombatEntity:
			return e
		n = n.get_parent()
	return null


static func _hurtboxes_of(e: CombatEntity) -> Array:
	var out: Array = []
	var stack: Array = [e.actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Hurtbox and (c as Hurtbox).entity == e:
				out.append(c)
			stack.append(c)
	return out


static func _nearest_hurtbox(e: CombatEntity, at: Vector3) -> Hurtbox:
	var best: Hurtbox = null
	var best_d := INF
	for hb: Hurtbox in _hurtboxes_of(e):
		var d := hb.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = hb
	return best


## The body standing where the cursor's ray meets the ground: the strikable entity nearest `ground` within its
## radius plus CURSOR_MAGNET_M plus CURSOR_MAGNET_HEIGHT_SHARE of the giant's height (a man at a big giant's feet).
func _magnet(ground: Vector3) -> Dictionary:
	var h := float(player.profile.get("height_m", 3.66))
	var best: CombatEntity = null
	var best_d := INF
	for e: CombatEntity in Sim.entities():
		if not _strikable(e) or not TargetingRules.player_may_target(e):
			continue   # (only what the giant may target is pulled in: never a villager beside the cursor)
		var p := (e.actor as Node3D).global_position
		if ground.y > p.y + e.combatant.height_m + 0.5 or ground.y < p.y - 1.0:
			continue
		var d := Vector2(p.x - ground.x, p.z - ground.z).length()
		var lim := EnemyActor.entity_radius(e) + CURSOR_MAGNET_M + CURSOR_MAGNET_HEIGHT_SHARE * h
		if d <= lim and d < best_d:
			best_d = d
			best = e
	if best == null:
		return {}
	var hb := _nearest_hurtbox(best, ground)
	return {"entity": best, "hurtbox": hb, "region": hb.region if hb != null else "", "aim": _aim_of(best, hb),
		"point": ground}


## The entities a swing of `action` facing `yaw` with tilt `offset_deg` meets, in order, as the runner will meet them:
## the arc's weapon segments tick by tick through its active phase (HitQueryAdapter.sweep_capsule, the same origin,
## radius and occlusion), each tick's candidates in HitFactory's order, every entity once. A titan's region is the
## one HitFactory lands on (HitFactory.predict_titan_region, with `aim` the point the swing aims at on `aimed`).
## [{entity, region, tick}].
func predicted_struck(action: ActionDef, yaw: float, offset_deg: float, aim := Vector3.INF,
		aimed: CombatEntity = null) -> Array:
	var out: Array = []
	if action == null or action.arc.is_empty():
		return out
	var xf := Transform3D(Basis(Vector3.UP, yaw), player.global_position)
	var space := player.get_world_3d().direct_space_state
	var origin := xf * player.attack_origin
	var n := maxi(action.active_ticks, 1)
	var seen := {}
	var titan_ticks := {}   # entity id -> [[tick, [cands]]]
	var order: Array = []
	var prev := _segment_at(action, 0.0, offset_deg, xf)
	for k in range(1, n + 1):
		var cur := _segment_at(action, float(k) / float(n), offset_deg, xf)
		var cands := HitQueryAdapter.sweep_capsule(space, player.entity, origin, prev[0], prev[1], cur[0], cur[1],
			float(player.weapon_hit_radius()))
		HitFactory.sort_candidates(cands)
		var per_titan := {}
		for c: Dictionary in cands:
			var e: CombatEntity = c.entity
			if e.plates != null:
				if not per_titan.has(e.entity_id):
					per_titan[e.entity_id] = []
				per_titan[e.entity_id].append(c)
				continue
			if seen.has(e.entity_id):
				continue
			seen[e.entity_id] = true
			var hb: Variant = c.get("hurtbox")
			order.append({"entity": e, "region": (hb as Hurtbox).region if hb is Hurtbox else "", "tick": k})
		for id: String in per_titan:
			if not titan_ticks.has(id):
				titan_ticks[id] = []
				order.append({"entity": (per_titan[id][0] as Dictionary).entity, "region": "", "tick": k, "titan": id})
			titan_ticks[id].append([k, per_titan[id]])
		prev = cur
	for o: Dictionary in order:
		if not o.has("titan"):
			out.append(o)
			continue
		var e: CombatEntity = o.entity
		var a := aim if aimed == e else Vector3.INF
		var cand := HitFactory.predict_titan_region(titan_ticks[o.titan], a, HitFactory.aim_snap_m(e),
			a.is_finite() and HitFactory.aim_beyond_from(player.global_position, a, e))
		if cand.is_empty():
			continue
		var hb: Variant = cand.get("hurtbox")
		out.append({"entity": e, "region": (hb as Hurtbox).region if hb is Hurtbox else "", "tick": int(cand.get("tick", o.tick))})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.tick) < int(y.tick))
	return out


func _segment_at(action: ActionDef, f: float, offset_deg: float, xf: Transform3D) -> PackedVector3Array:
	var ang := AttackGeometry.arc_point(action, f)
	var dir := AttackGeometry.local_direction(ang.x, ang.y + offset_deg)
	var seg := AttackGeometry.segment_local(player.weapon_pivot, dir, player.arm_length,
		player.arm_length + player.weapon_length)
	return PackedVector3Array([xf * seg[0], xf * seg[1]])


## HitFactory: the point the running swing aims at on `e` when the giant holds no lock - the plan's aim point while
## the swing it was made for runs and `e` is its target; INF otherwise.
func swing_aim_point(e: CombatEntity) -> Vector3:
	if _swing_aim_instance < 0 or _swing_aim_entity != e or player.controller.instance_id != _swing_aim_instance \
			or player.controller.action == null:
		return Vector3.INF
	return _swing_aim_point


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
	var spec := stage_spec(a)
	if not (str(spec.aim) in ["lock_or_camera", "target"]):
		return ""
	var target := player.targeting.locked_entity() if player.targeting != null else null
	if target == null or not target.is_alive() or launches_above_target(a):
		return ""   # P31: a strike from above (Storm Call) reaches whatever the lock holds
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


## P26: the range of projectile action `a` at the giant's stage: range_by_stage_m[stage - 1] (the
## last entry beyond the list), else `fallback` (the projectile's range_m).
func stage_range(a: ActionDef, fallback: float) -> float:
	var by_stage: Variant = a.param("range_by_stage_m") if a != null else null
	if typeof(by_stage) != TYPE_ARRAY or (by_stage as Array).is_empty():
		return fallback
	var list: Array = by_stage
	return float(list[clampi(player.growth_stage - 1, 0, list.size() - 1)])


## P26: the projectile spec of `a` (Projectile.spec_for) with the stage's range.
func stage_spec(a: ActionDef) -> Dictionary:
	var spec := Projectile.spec_for(a)
	spec["range_m"] = stage_range(a, float(spec.range_m))
	return spec


## k: the giant's size relative to the stage-1 giant (launch offsets are authored for stage 1).
func body_scale() -> float:
	return float(player.profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M)) \
		/ CombatRules.REFERENCE_HEIGHT_M


## AttackRunner.launch_resolver: {"origin": launch_offset_m x k in the giant's space (or the
## attack origin), "aim": aim_point_for(spec, origin)}. P26: the stage's range (range_by_stage_m)
## goes into `spec` itself - the runner's own copy, which it launches with right after (the arc's
## range clamp) and PlayerGrab's landing preview reads - so the shot flies as far as the check says.
func resolve_launch(a: ActionDef, spec: Dictionary) -> Dictionary:
	spec["range_m"] = stage_range(a, float(spec.get("range_m", 25.0)))
	if launches_above_target(a):
		return above_target_launch(a, spec)
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


# --------------------------------------------------------------------------- P31: strikes from above, telegraphs, body sweep

## True when projectile action `a` falls on its aim point from above (projectile.launch_from
## "above_target": Storm Call).
static func launches_above_target(a: ActionDef) -> bool:
	if a == null or a.hit_shape != "projectile":
		return false
	var p: Variant = a.param("projectile")
	return typeof(p) == TYPE_DICTIONARY and str((p as Dictionary).get("launch_from", "actor")) == "above_target"


## The launch of a strike from above: the aim point is the locked target's anchor, else the point
## under the crosshair within the lock range (aimed from the attack origin); the projectile starts
## launch_height_m above it and falls straight onto it.
func above_target_launch(a: ActionDef, spec: Dictionary) -> Dictionary:
	var p: Dictionary = a.param("projectile", {})
	var height := float(p.get("launch_height_m", 20.0))
	var aim := strike_point(a)
	return {"origin": aim + Vector3.UP * height, "aim": aim}


## Where a strike from above lands now: the locked target's anchor, else the point under the
## crosshair within the lock range.
func strike_point(_a: ActionDef) -> Vector3:
	var target := player.targeting.locked_entity() if player.targeting != null else null
	if target != null and target.is_alive():
		return target.anchor_position()
	var origin := player.attack_origin_global()
	return camera_aim_point(origin, float(player.profile.get("lock_range_m", 55.0)))


## Announces the telegraph of the giant's own ability as its windup begins (Earthquake's crack along
## its facing, Storm Call's circle where it will strike), as enemies announce theirs: radius / length
## by shape (circle: radius_m; line: width_m / 2 and length_m; cone: radius_m), duration the windup,
## the lock target as the target. A telegraph "at" "target" starts at the strike point.
func _announce_telegraph(action: ActionDef) -> void:
	var t: Variant = action.param("telegraph") if action != null else null
	if typeof(t) != TYPE_DICTIONARY or not (action.kind in ["ability", "ultimate"]):
		return
	var shape := str(t.get("shape", "line"))
	var radius := float(t.get("radius_m", 0.0))
	var length := 0.0
	match shape:
		"line":
			radius = float(t.get("width_m", 1.0)) * 0.5
			length = float(t.get("length_m", 0.0))
		"cone":
			length = radius
	var target := player.targeting.locked_entity() if player.targeting != null else null
	var target_id := target.entity_id if target != null and target.is_alive() else ""
	var origin := player.global_position
	if str(t.get("at", "actor")) == "target":
		origin = strike_point(action)
		if target_id != "":
			origin = (target.actor as Node3D).global_position
	Events.telegraph_started.emit(Sim.tick, player.entity.entity_id, action.id, target_id, shape, origin,
		player.facing_yaw, radius, length, float(action.windup_ticks) / Sim.TICK_RATE)


var _sweep_instance := -1
var _sweep_prev := Vector3.ZERO


## Shoulder Charge's hit (hit_shape body_sweep, while PlayerMotor dashes the giant along its
## motion): the giant's capsule (radius + BODY_SWEEP_MARGIN_M, its height) swept from where it stood
## the tick before to where it stands now; one hit per target and instance (HitFactory), each coming
## from behind the target on the charge line's side (charge_shove_origin), so the knockback throws
## it forward and out of the charge's way.
func _run_body_sweep(a: ActionDef, tick: int) -> void:
	var cur := player.global_position
	if _sweep_instance != player.controller.instance_id:
		_sweep_instance = player.controller.instance_id
		_sweep_prev = cur
	var prev := _sweep_prev
	_sweep_prev = cur
	var cap := player.body_shape.shape as CapsuleShape3D
	var r := (cap.radius if cap != null else 1.0) + BODY_SWEEP_MARGIN_M
	var h := maxf(cap.height if cap != null else 3.66, 2.0 * r)
	var lo := Vector3.UP * r
	var hi := Vector3.UP * (h - r)
	var cands := HitQueryAdapter.sweep_capsule(player.get_world_3d().direct_space_state, player.entity,
		player.attack_origin_global(), prev + lo, prev + hi, cur + lo, cur + hi, r)
	for c: Dictionary in cands:
		var t: CombatEntity = c.entity
		var ctx := runner.context()
		ctx.attacker_position = charge_shove_origin(t.actor.global_position)
		HitFactory.queue(ctx, a, [c], 0, tick)


## The point a charge hit on a target at `target_pos` comes "from": a metre behind it, diagonally
## from the charge line (to the giant's right when it stands dead ahead), so the knockback bowls it
## forward and aside.
func charge_shove_origin(target_pos: Vector3) -> Vector3:
	var dir := Vector3(-sin(player.facing_yaw), 0.0, -cos(player.facing_yaw))
	var to := target_pos - player.global_position
	to.y = 0.0
	var side := to - dir * to.dot(dir)
	if side.length() < 0.3:
		side = Vector3(-dir.z, 0.0, dir.x)
	var from := target_pos - (side.normalized() + dir).normalized()
	from.y = target_pos.y
	return from


## on_hit_stagger (Thunderhead): every target of the listed archetypes (any, when the list is
## empty) a hit of the action struck - and did not kill - staggers for the given seconds (the
## existing fixed-length stagger).
func _on_hit_landed(result: HitResult) -> void:
	if result == null or result.killed or result.event == null:
		return
	if not (result.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARD_BROKEN]):
		return
	var a := GameData.get_action(result.event.action_id)
	var st: Variant = a.param("on_hit_stagger") if a != null else null
	if typeof(st) != TYPE_DICTIONARY:
		return
	var target := Sim.get_entity(result.event.target_id)
	if target == null or not target.is_alive():
		return
	var kinds: Array = (st as Dictionary).get("archetypes", [])
	var archetype := str(target.combatant.base_record.get("archetype", "")) if target.combatant != null else ""
	if kinds.is_empty() or kinds.has(archetype):
		target.stagger(float(st.get("seconds", 1.0)), "stunned")
