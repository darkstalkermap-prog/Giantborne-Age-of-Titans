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
	runner.register_shape(FOOT_STAMP, _run_foot_stamp)   # C3b: the low strike (a stamp, a stomp)
	for id: String in [LOW_LIGHT, LOW_HEAVY]:
		player.ensure_action(id)
	player.controller.variant_resolver = low_variant
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
func aimed_offset(action: ActionDef, distance: float, base_y: float, t_radius: float, t_height: float,
		low := true) -> float:
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
	if low and best_m > wr + t_radius:
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
	_stamp_instance = -1
	if action != null and action.hit_shape == FOOT_STAMP:
		_start_stamp(action, instance_id)
		return
	if action == null or action.hit_shape != "weapon_arc" or action.arc.is_empty():
		return
	if not cursor_aim:
		_start_aim_classic(action, instance_id)
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


## The vertical aim as P17b and A2 made it (the bots': cursor_aim off): the lock, else the soft target.
func _start_aim_classic(action: ActionDef, instance_id: int) -> void:
	var t := aim_target()
	if t == null:
		return
	var rel := player.global_transform.affine_inverse() * (t.actor as Node3D).global_position
	var radius := EnemyActor.entity_radius(t)
	if t.plates != null:
		var at := player.global_transform.affine_inverse() * t.lock_anchor_position(float(player.profile.get("height_m", 3.66)))
		_aim_offset = a2_plate_offset(action, Vector2(at.x, at.z).length(), at.y)
	else:
		_aim_offset = aimed_offset(action, Vector2(rel.x, rel.z).length(), rel.y, radius, t.combatant.height_m, false)
	_aim_action = action.id
	_aim_instance = instance_id


## C3: a bot's controls (BotCombat, TitanDuelBot): the aim as the duels were tuned (no cursor, no low tilts, the swing
## facing its aim at once), the constant-rate turns and the 0.15 s buffer for every request.
func bot_controls() -> void:
	cursor_aim = false
	player.controller.variant_resolver = Callable()   # C3b: no low strike in place of their swings
	player.controller.attack_buffer_ticks = InputBuffer.DEFAULT_WINDOW_TICKS


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

## C3: the cursor's aim (decision C3-4) is a player's: the bots (BotCombat, TitanDuelBot) aim by the lock and the soft
## target as they were tuned to, and switch it off (bot_controls), with the 0.25 s attack buffer and the swing's turn
## into its blow.
var cursor_aim := true
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
	if action != null and action.hit_shape == FOOT_STAMP:
		return _stamp_plan(action)
	var out := _weapon_plan(action)
	# C3b (decision C3b-1): what the swing aims at stands at the giant's feet, below its arc - the press stamps (a
	# light) or stomps (a heavy) on it instead, when that strikes it
	var low := low_variant_def(action)
	if low != null and _wants_low(out):
		var alt := _stamp_plan(low)
		if alt.get("entity") == out.get("entity") and alt.get("primary") == out.get("entity"):
			alt["variant"] = low.id
			alt["base"] = action.id
			return alt
	return out


func _empty_plan(action: ActionDef) -> Dictionary:
	return {"source": "none", "entity": null, "region": "", "aim_point": Vector3.INF, "yaw": _camera_yaw(),
		"offset": offset_for(player.profile, action.id if action != null else ""), "struck": [], "primary": null,
		"primary_region": "", "reaches": false, "distance": 0.0, "short_m": 0.0, "too_close": false, "variant": "",
		"base": "", "strike": "swing"}


func _weapon_plan(action: ActionDef) -> Dictionary:
	var out := _empty_plan(action)
	if action == null or action.arc.is_empty() or not player.is_inside_tree():
		return out
	var point := _pick_target(action, out)
	var t: CombatEntity = out.entity
	var h := float(player.profile.get("height_m", 3.66))
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
	# (nothing strikable within reach of the arc: nothing to sweep - the HUD asks every few frames, most of them with
	# nothing near)
	var struck: Array = predicted_struck(action, float(out.yaw), float(out.offset), point if t != null else Vector3.INF, t) \
		if anything_near(action) else []
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


## What a strike started now aims at and where it faces (the lock, else the cursor, else the soft target in front):
## fills `out`'s source, entity, region, aim_point and yaw; returns the aim point (INF for none).
func _pick_target(action: ActionDef, out: Dictionary) -> Vector3:
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
		var pick := cursor_pick(action) if cursor_aim else {}
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
	return point


# --------------------------------------------------------------------------- C3b: the hit-stop (decision C3b-4)

## A light, a heavy, a stamp or a stomp of the player's that lands holds where it struck for a few ticks - more the
## bigger he is (HITSTOP_TICKS from stage 1 to stage 8; a heavy's HITSTOP_HEAVY x that) - so a blow reads as meeting
## something, and the camera kicks with it (CameraRig.add_kick, by size; HitFeedback). Once per swing; the bots keep
## their swings unheld (cursor_aim off).
const HITSTOP_TICKS := Vector2(2.0, 5.0)
const HITSTOP_HEAVY := 1.5
const HITSTOP_MAX := 8

var _stopped_instance := -1


## The giant's size between stage 1 (0) and stage 8 (1).
func size_share() -> float:
	var h := float(player.profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M))
	return clampf((h - CombatRules.REFERENCE_HEIGHT_M) / (29.2608 - CombatRules.REFERENCE_HEIGHT_M), 0.0, 1.0)


## The hit-stop of a blow of `action` now (ticks).
func hitstop_ticks(action: ActionDef) -> int:
	var n := lerpf(HITSTOP_TICKS.x, HITSTOP_TICKS.y, size_share())
	if action != null and action.kind == "heavy":
		n *= HITSTOP_HEAVY
	return clampi(roundi(n), 1, HITSTOP_MAX)


func _hit_stop(result: HitResult) -> void:
	if not cursor_aim or result == null or result.event == null:
		return
	var c := player.controller
	if c.action == null or result.event.instance_id != c.instance_id or _stopped_instance == c.instance_id:
		return
	if not (c.action.kind in ["light", "heavy"]) or c.phase() != ActionDef.Phase.ACTIVE:
		return
	if not (result.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.GUARD_BROKEN, HitResult.Outcome.BLOCKED]):
		return
	_stopped_instance = c.instance_id
	c.hold_ticks = hitstop_ticks(c.action)
	if player.camera_rig != null and player.camera_rig.has_method("add_kick"):
		player.camera_rig.add_kick((0.35 + 0.65 * size_share()) * (1.4 if c.action.kind == "heavy" else 1.0))


# --------------------------------------------------------------------------- C3b: the low strike (decision C3b-1)

## A light or a heavy whose arc passes over what it aims at - a man, a wolf, a fence at the giant's feet, below the
## swing (at stages 7 and 8 every swing does: the weapon is carried past its fit and the shoulder stands 19-23 m up) -
## becomes a stamp (a light: LOW_LIGHT) or a stomp (a heavy: LOW_HEAVY): the near foot lifted and driven down where
## the target stands (hit shape foot_stamp). PlayerAttack.swing_plan chooses it (so the aim indicator shows it, its
## struck the stamp's), CombatController.variant_resolver starts it in the swing's place (low_variant: the same plan
## this tick), the light chain goes on from the light it stood in for. Only a player's (cursor_aim): the bots keep the
## swings their duels were tuned with (bot_controls).
const FOOT_STAMP := "foot_stamp"
const LOW_LIGHT := "ability.low_stamp"
const LOW_HEAVY := "ability.low_stomp"
## What a low strike is for: a body whose top stands at most this share of the giant's height (not a titan, not a
## house).
const LOW_TARGET_SHARE := 0.5
## From stage 5 (this tall), a body this small beside the giant (its top at most this share of his height: a man, a
## wolf, a fence) within this share of his height of his middle is stamped on even when the swing would reach it: at
## his feet a swing is the weapon chopping at the ground beside his toes. (Below, a swing that reaches it swings.)
const LOW_TINY_MIN_HEIGHT_M := 14.0
const LOW_TINY_SHARE := 0.14
const LOW_TINY_REACH_SHARE := 0.45
## The stamp's foot side: the left when the target stands more than this share of the height left of the facing.
const STAMP_SIDE_SHARE := 0.03

var _stamp_instance := -1
var _stamp_point := Vector3.INF
var _stamp_foot := "r"
var _stamp_action := ""


## CombatController.variant_resolver: the low strike to start in place of `def` (a light or a heavy) now, else `def`.
func low_variant(def: ActionDef, _kind: StringName) -> ActionDef:
	if def == null or def.hit_shape != "weapon_arc" or def.arc.is_empty() or not cursor_aim:
		return def
	var plan := swing_plan_for(def)
	var v := str(plan.get("variant", ""))
	if v == "" or not player.controller.library.has(v):
		return def
	return player.controller.library[v]


## The low strike that may stand in for `action` (a light: the stamp; a heavy: the stomp), else null.
func low_variant_def(action: ActionDef) -> ActionDef:
	if action == null or not cursor_aim or action.hit_shape != "weapon_arc" or player.controller == null:
		return null
	var id := LOW_LIGHT if action.kind == "light" else (LOW_HEAVY if action.kind == "heavy" else "")
	return player.controller.library.get(id) if id != "" else null


## True when the swing's plan aims at a low body it does not strike (the low strike may then).
func _wants_low(plan: Dictionary) -> bool:
	var t: Variant = plan.get("entity")
	if not (t is CombatEntity) or not _strikable(t as CombatEntity) or (t as CombatEntity).plates != null:
		return false
	var h := float(player.profile.get("height_m", 3.66))
	var e := t as CombatEntity
	var top := (e.actor as Node3D).global_position.y - player.global_position.y + e.combatant.height_m
	if h >= LOW_TINY_MIN_HEIGHT_M and top <= LOW_TINY_SHARE * h and float(plan.get("distance", INF)) <= LOW_TINY_REACH_SHARE * h:
		return true   # (a man at a colossus's toes is stamped on, even where the swing would reach down to him)
	return plan.get("primary") != t and top <= LOW_TARGET_SHARE * h


## The stamp's numbers for `action` at the giant's height: {reach, min, radius, height} (metres).
func stamp_numbers(action: ActionDef) -> Dictionary:
	var h := float(player.profile.get("height_m", 3.66))
	var st: Dictionary = action.param("stamp", {}) if action != null else {}
	return {"reach": float(st.get("reach_share", 0.42)) * h, "min": float(st.get("min_share", 0.12)) * h,
		"radius": maxf(float(st.get("radius_min_m", 0.45)), float(st.get("radius_share", 0.1)) * h),
		"height": maxf(float(st.get("height_min_m", 1.2)), float(st.get("height_share", 0.12)) * h)}


## Where a stamp of `action` at `t` comes down: the ground under the target, brought within the foot's reach (between
## its min and reach from the giant's middle, along the bearing to it); with no target, the reach's middle ahead of
## `yaw`.
func stamp_point(action: ActionDef, t: CombatEntity, yaw: float) -> Vector3:
	var n := stamp_numbers(action)
	var at := player.global_position
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var d := (float(n.reach) + float(n.min)) * 0.5
	var y := at.y
	if t != null and t.actor != null and is_instance_valid(t.actor):
		var base := (t.actor as Node3D).global_position
		var to := Vector3(base.x - at.x, 0.0, base.z - at.z)
		if to.length() > 1e-3:
			dir = to.normalized()
		d = clampf(to.length(), float(n.min), float(n.reach))
		y = base.y
	return Vector3(at.x + dir.x * d, y, at.z + dir.z * d)


## The plan of a stamp or a stomp started now (as swing_plan's for a swing): its target as a swing's (the lock, the
## cursor, the soft target), facing it, the foot's point (stamp_point) and side, and what its pulse strikes there.
func _stamp_plan(action: ActionDef) -> Dictionary:
	var out := _empty_plan(action)
	out.strike = "stamp" if action.kind == "light" else "stomp"
	if action == null or not player.is_inside_tree():
		return out
	_pick_target(action, out)
	var t: CombatEntity = out.entity
	if t != null and str(out.source) == "soft":
		out.yaw = _turn_toward(t.anchor_position())   # (the stamp faces its target as a cursor's swing does)
	var point := stamp_point(action, t, float(out.yaw))
	out["stamp_point"] = point
	var local := Transform3D(Basis(Vector3.UP, player.facing_yaw), player.global_position).affine_inverse() * point
	out["foot"] = "l" if local.x < -STAMP_SIDE_SHARE * float(player.profile.get("height_m", 3.66)) else "r"
	var n := stamp_numbers(action)
	var struck: Array = predicted_stamp(action, point) if t != null or anything_near(action) else []
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
	if t != null:
		var base := (t.actor as Node3D).global_position
		out.distance = Vector2(base.x - player.global_position.x, base.z - player.global_position.z).length()
		if out.primary != t:
			out.short_m = maxf(0.0, out.distance - float(n.reach) - float(n.radius) - EnemyActor.entity_radius(t))
			out.too_close = out.short_m <= 0.0 and out.distance < float(n.min)
	return out


## The stamp's pulse at `point`: a vertical cylinder from the ground, its line of sight from the giant's hips.
func _stamp_query(action: ActionDef, point: Vector3) -> Array:
	var n := stamp_numbers(action)
	var h := float(player.profile.get("height_m", 3.66))
	var center := point + Vector3.UP * (float(n.height) * 0.5)
	return HitQueryAdapter.cylinder_pulse(player.get_world_3d().direct_space_state, player.entity, center,
		float(n.radius), float(n.height), player.global_position + Vector3.UP * (0.45 * h))


## What a stamp of `action` at `point` strikes, in HitFactory's order and with its filters: [{entity, region, tick}].
func predicted_stamp(action: ActionDef, point: Vector3) -> Array:
	var cands := _stamp_query(action, point)
	HitFactory.sort_candidates(cands)
	HitFactory.pick_titan_regions(cands, player.entity, -1, Sim.tick)
	var out: Array = []
	var seen := {}
	for c: Dictionary in cands:
		var e: CombatEntity = c.entity
		if seen.has(e.entity_id) or HitFactory.skip_candidate(player.entity, e, true):
			continue
		seen[e.entity_id] = true
		var hb: Variant = c.get("hurtbox")
		out.append({"entity": e, "region": (hb as Hurtbox).region if hb is Hurtbox else "", "tick": 1})
	return out


func _start_stamp(action: ActionDef, instance_id: int) -> void:
	var plan := swing_plan_for(action, instance_id)
	_stamp_point = plan.get("stamp_point", stamp_point(action, null, player.facing_yaw))
	_stamp_foot = str(plan.get("foot", "r"))
	_stamp_action = action.id
	_stamp_instance = instance_id
	_swing_aim_entity = plan.get("entity") as CombatEntity
	_swing_aim_point = _stamp_point
	_swing_aim_instance = instance_id


## The running stamp (the rig's foot): {"point" (world), "foot" ("r" / "l"), "radius"}; {} when none runs.
func stamp_state() -> Dictionary:
	var c := player.controller
	if _stamp_instance < 0 or c.action == null or c.instance_id != _stamp_instance or c.action.id != _stamp_action:
		return {}
	return {"point": _stamp_point, "foot": _stamp_foot, "radius": float(stamp_numbers(c.action).radius)}


## The stamp's hit (hit shape foot_stamp): on the first active tick, the pulse where the foot comes down (the plan's
## point); an area effect (neutral bystanders are spared), one hit per target; then the ground's shock (area_pulse:
## the impact's sound and ring, the camera's kick).
func _run_foot_stamp(a: ActionDef, tick: int) -> void:
	if not player.controller.is_first_active_tick():
		return
	var st := stamp_state()
	var point: Vector3 = st.get("point", stamp_point(a, null, player.facing_yaw))
	var cands := _stamp_query(a, point)
	var ctx := runner.context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.area_pulse.emit(tick, player.entity.entity_id, a.id, point, float(stamp_numbers(a).radius))


## True when a body the giant's blows damage stands within `reaches` x the swing's reach (horizontally, plus its
## radius; a titan 8 m more).
func anything_near(action: ActionDef, reaches := 1.5) -> bool:
	var r := reach_estimate(action) * reaches
	var at := player.global_position
	for e: CombatEntity in Sim.entities():
		if not _strikable(e):
			continue
		var p := (e.actor as Node3D).global_position
		var lim := r + EnemyActor.entity_radius(e) + (8.0 if e.plates != null else 0.0)
		if Vector2(p.x - at.x, p.z - at.z).length_squared() <= lim * lim:
			return true
	return false


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
	_hit_stop(result)
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
