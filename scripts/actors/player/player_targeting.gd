class_name PlayerTargeting
extends PlayerComponent
## Hard lock-on (acquire, switch, release, upkeep) and the soft-target nudge during attack
## windups (moved unchanged from the M1 GiantPlayer). The lock state itself is player.lock
## (a LockOnTracker); camera_rig.lock_target and Events.lock_target_changed are only ever
## updated through sync_lock().
##
## Which entities the player may target at all is decided in one place, may_target(): hostile-
## only targeting (P03, decision 17) - TargetingRules.player_may_target, so team ENEMY and
## faction-less NEUTRAL targets (dummies, props) only; neutral villagers and guards are never
## locked or soft-targeted. P11a adds the boss's extra lock anchors where the candidates are
## gathered.


func setup(p: GiantPlayer) -> void:
	super(p)
	apply_lock_profile(player.profile)


func on_profile_changed(_old_profile: Dictionary, new_profile: Dictionary) -> void:
	apply_lock_profile(new_profile)


func apply_lock_profile(profile: Dictionary) -> void:
	player.lock.range_m = float(profile.get("lock_range_m", 35.0))
	player.lock.half_angle_deg = float(profile.get("lock_half_angle_deg", 60.0))


# --------------------------------------------------------------------------- queries

func locked_entity() -> CombatEntity:
	if not player.lock.is_locked():
		return null
	if _p30_is_group(player.lock.target_id):
		return _p30_locked_member()   # P30: a formation's focus member
	return Sim.get_entity(player.lock.target_id)


## Whether lock-on and soft targeting may consider `e` at all (hostile-only, P03).
func may_target(e: CombatEntity) -> bool:
	return e != null and e != player.entity and TargetingRules.player_may_target(e)


func eye() -> Vector3:
	return player.global_position + Vector3.UP * player.entity.combatant.height_m \
		* float(player.profile.get("eye_height_ratio", 0.92))


## Line of sight from the eye to the target's lock point (P11a: the same anchor the camera frames).
func is_visible(target: CombatEntity) -> bool:
	var space := player.get_world_3d().direct_space_state
	return HitQueryAdapter.line_clear(space, eye(), lock_point(target),
		HitQueryAdapter.LAYER_WORLD, target.occlusion_rids)


## Lock candidate snapshots for LockOnTracker (see its header for the keys). Direction, distance
## and the screen position are taken at each target's lock point (P11a).
func gather_candidates(with_screen: bool) -> Array:
	if _p30_formation_lock():
		return _p30_gather(with_screen)   # P30: formations fold into one candidate each (stages 4-6)
	var out: Array = []
	var from := eye()
	var cam := player.camera_rig.camera
	for e: CombatEntity in Sim.entities():
		if not may_target(e) or not e.combatant.lockable:
			continue
		var anchor := lock_point(e)
		var c := {"id": e.entity_id, "direction": anchor - from, "distance": from.distance_to(anchor),
			"threat": e.combatant.threat, "alive": e.is_alive(), "lockable": e.combatant.lockable,
			"visible": is_visible(e)}
		if with_screen and cam != null and not cam.is_position_behind(anchor):
			c["screen"] = cam.unproject_position(anchor)
		out.append(c)
	return out


## Soft targeting: during a windup, the offset (radians, at most soft_target_max_deg) that
## turns `base_yaw` toward the best enemy in front - never toward one hidden behind a wall.
func soft_target_offset(base_yaw: float) -> float:
	var action := player.controller.action
	if action == null or action.soft_target_max_deg <= 0.0:
		return 0.0
	var best: Array = soft_target(base_yaw)
	if best.is_empty():
		return 0.0
	var max_rad := deg_to_rad(action.soft_target_max_deg)
	return clampf(float(best[1]), -max_rad, max_rad)


## The soft target in front of `base_yaw`: [CombatEntity, yaw delta (radians)] of the best-scoring
## targetable, lockable, visible enemy within the stage's melee reach + 1.5 m and
## SOFT_TARGET_CONE_DEG, or [] (soft_target_offset's pick; PlayerAttack's vertical aim, P17b).
func soft_target(base_yaw: float) -> Array:
	var reach := float(player.profile.get("melee_reach_m", 3.5)) + 1.5
	var base_dir := Vector3(-sin(base_yaw), 0.0, -cos(base_yaw))
	var best_score := -1.0
	var best: Array = []
	var space := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3.UP * player.attack_origin.y
	for e: CombatEntity in Sim.entities():
		if not e.is_alive() or not may_target(e):
			continue
		if not e.combatant.lockable:
			continue
		var to := e.actor.global_position - player.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > reach or dist < 0.01:
			continue
		var delta := TargetingRules.yaw_delta(base_yaw, TargetingRules.yaw_of(to))
		if absf(rad_to_deg(delta)) > GiantPlayer.SOFT_TARGET_CONE_DEG:
			continue
		if not HitQueryAdapter.line_clear(space, from, e.anchor_position(), HitQueryAdapter.OCCLUDER_MASK, e.occlusion_rids):
			continue
		var q := TargetingRules.score(base_dir, to, dist, reach, e.combatant.threat)
		if q > best_score:
			best_score = q
			best = [e, delta]
	return best


# --------------------------------------------------------------------------- input

## Default mapping of the lock edges (lock_press/_release, target_left/_right, stick flicks
## and taps). Returns false for any other edge.
func handle_lock_edge(edge: StringName) -> bool:
	var hold_lock: bool = Settings.get_value("lock_mode") == "hold"
	var lock := player.lock
	var camera := player.camera_rig
	match edge:
		&"lock_press":
			if lock.is_locked() and not hold_lock:
				release_lock("manual")
			else:
				try_lock()
		&"lock_release":
			if hold_lock and lock.is_locked():
				release_lock("manual")
		&"target_left":
			if lock.is_locked():
				switch_target(-1)
			else:
				camera.zoom(-1)
		&"target_right":
			if lock.is_locked():
				switch_target(1)
			else:
				camera.zoom(1)
		# Right stick: in third-person lock the stick does not look, so a fast flick switches
		# at once; in first-person lock it also looks, so only a flick-and-release ("tap") does.
		&"stick_flick_left", &"stick_flick_right":
			if lock.is_locked() and not camera.is_first_person():
				switch_target(-1 if edge == &"stick_flick_left" else 1)
		&"stick_tap_left", &"stick_tap_right":
			if lock.is_locked() and camera.is_first_person():
				switch_target(-1 if edge == &"stick_tap_left" else 1)
		_:
			return false
	return true


## Hold mode follows the polled key state, not only release edges: a release that happened
## while paused or unfocused (no edge delivered) still ends the lock. Runs after the tick's
## meta edges.
func apply_hold_release(intents: Dictionary) -> void:
	var hold_lock: bool = Settings.get_value("lock_mode") == "hold"
	if hold_lock and player.lock.is_locked() and not intents.lock_held:
		release_lock("manual")


# --------------------------------------------------------------------------- lock state

func try_lock() -> void:
	var id := player.lock.acquire(gather_candidates(false), player.camera_rig.aim_forward())
	if id == "":
		Events.hud_message.emit("No target in range", "info")
	sync_lock(id, "acquired")


func switch_target(direction: int) -> void:
	var current := locked_entity()
	if current == null:
		return
	var cam := player.camera_rig.camera
	# If the current target is behind the camera (first-person free look), switch relative to
	# the screen centre instead of doing nothing.
	var screen := cam.get_viewport().get_visible_rect().size * 0.5
	var current_point := lock_point(current)
	if _p30_is_group(player.lock.target_id) and _p30_group(player.lock.target_id) != null:
		current_point = _p30_group(player.lock.target_id).anchor()   # P30: the group's own lock point
	if not cam.is_position_behind(current_point):
		screen = cam.unproject_position(current_point)
	if player.lock.switch_target(direction, gather_candidates(true), screen,
			player.camera_rig.aim_forward(), Sim.tick / 60.0):
		sync_lock(player.lock.target_id, "switched")


func release_lock(reason: String) -> void:
	player.lock.release()
	sync_lock("", reason)


func sync_lock(id: String, reason: String) -> void:
	player.camera_rig.lock_target = Sim.get_entity(id) if id != "" else null
	_p30_sync_camera(id)   # P30: a group lock frames its formation's anchor on its focus member
	Events.lock_target_changed.emit(player.entity.entity_id, id, reason)


func maintain_lock(dt: float) -> void:
	var lock := player.lock
	if not lock.is_locked():
		return
	if _p30_is_group(lock.target_id):
		_p30_maintain(dt)   # P30: a formation's lock holds while one of its members stands
		return
	var t := Sim.get_entity(lock.target_id)
	var info := {"exists": t != null}
	if t != null:
		info["alive"] = t.is_alive()
		info["lockable"] = t.combatant.lockable
		info["distance"] = eye().distance_to(lock_point(t))
		info["visible"] = is_visible(t)
	var reason := lock.update(dt, info)
	if reason != "":
		sync_lock("", reason)


func on_any_entity_died(id: String) -> void:
	if id == player.lock.target_id:
		release_lock("target_died")
	_p30_on_any_entity_died(id)   # P30: a locked formation's last standing member died


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5).

## @anchor P03
## @anchor P11a
# --- lock anchors (P11a) -------------------------------------------------------------------------
# Plan §3.12 design 3: lock framing (CameraRig.lock_focus_point), the lock's line of sight, the
# candidates' direction, distance and screen position, and the HUD's lock marker all use one
# point - a knee of a target at least 1.3 x as tall as the giant (the Ogre King), else its torso.

## The giant's height for the lock anchor rule (its current profile).
func viewer_height() -> float:
	return float(player.profile.get("height_m", player.entity.combatant.height_m))


## The point lock-on aims at on `e`: CombatEntity.lock_anchor_position(viewer_height()).
func lock_point(e: CombatEntity) -> Vector3:
	return e.lock_anchor_position(viewer_height())


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P30
# --- formations as lock groups (P30, plan M6-M9 §2.10, decision 19) ---------------------------------
# Hook lines: locked_entity, gather_candidates, switch_target, sync_lock, maintain_lock and
# on_any_entity_died. While the profile's target_rules.formation_lock holds (stages 4-6):
#   * gather_candidates folds each formation's rank-and-file into one candidate "formation:<id>" -
#     its anchor (Formation.anchor(): the front rank's centre at chest height) for direction,
#     distance and screen, the highest member threat, visible when any of its nearest members is,
#     alive while a member stands (living and not routed) - and keeps its banner as a candidate of
#     its own (flagged "banner": the lock line's flag icon);
#   * locked_entity() resolves the group to its focus member (Formation.focus_member of the giant's
#     attack origin; a fleeing one when none stands), so the camera, the vertical aim and grabs keep
#     receiving a CombatEntity; the camera frames the formation's anchor (CameraRig.p30_lock_group);
#   * the group lock releases with "target_died" once no member is alive and not routed;
#   * switching moves between formations, banners and single targets (one candidate list).
# lock_label() is the HUD's lock line (P27 shows it): "Pike Regiment (8)", "⚑ Banner of the
# Toll-Riders", or the target's name.

const P30_GROUP_PREFIX := "formation:"
## A group is visible when any of this many of its members nearest the giant is.
const P30_VISIBLE_PROBES := 3


## True for a group lock id ("formation:<formation id>").
static func _p30_is_group(id: String) -> bool:
	return id.begins_with(P30_GROUP_PREFIX)


## The live formation a group id names (null when it is gone).
func _p30_group(id: String) -> Formation:
	if not _p30_is_group(id):
		return null
	var fid := id.trim_prefix(P30_GROUP_PREFIX)
	for f in Formation.live():
		if f.id == fid:
			return f
	return null


## True while the giant's profile folds formations into lock groups (target_rules.formation_lock).
func _p30_formation_lock() -> bool:
	var rules: Variant = player.profile.get("target_rules", {})
	return typeof(rules) == TYPE_DICTIONARY and bool((rules as Dictionary).get("formation_lock", false))


## The giant's attack origin (the group's focus member is the one nearest it).
func _p30_attack_origin() -> Vector3:
	return player.global_position + Vector3.UP * player.attack_origin.y


## The focus member of the locked group (null when none is left).
func _p30_locked_member() -> CombatEntity:
	var f := _p30_group(player.lock.target_id)
	if f == null:
		return null
	var m := f.focus_member(_p30_attack_origin())
	if m == null:
		m = f.nearest_living(_p30_attack_origin())
	return m.entity if m != null else null


## The candidates with formations folded (see the section notes).
func _p30_gather(with_screen: bool) -> Array:
	var out: Array = []
	var from := eye()
	var cam := player.camera_rig.camera
	var groups := {}   # formation id -> Formation
	for e: CombatEntity in Sim.entities():
		if not may_target(e) or not e.combatant.lockable:
			continue
		var actor := e.actor as EnemyActor
		if actor != null and actor.formation != null and actor.formation_slot >= 0 and not actor.formation.dissolved:
			groups[actor.formation.id] = actor.formation
			continue
		var anchor := lock_point(e)
		var c := {"id": e.entity_id, "direction": anchor - from, "distance": from.distance_to(anchor),
			"threat": e.combatant.threat, "alive": e.is_alive(), "lockable": e.combatant.lockable,
			"visible": is_visible(e)}
		if actor != null and actor.formation != null and actor.formation_slot == Formation.BANNER_SLOT:
			c["banner"] = true
		if with_screen and cam != null and not cam.is_position_behind(anchor):
			c["screen"] = cam.unproject_position(anchor)
		out.append(c)
	var ids := groups.keys()
	ids.sort()
	for fid: String in ids:
		var f: Formation = groups[fid]
		var anchor := f.anchor()
		var threat := 0.0
		for m in f.members:
			if is_instance_valid(m) and m.entity != null and m.entity.combatant != null:
				threat = maxf(threat, m.entity.combatant.threat)
		var c := {"id": P30_GROUP_PREFIX + fid, "direction": anchor - from, "distance": from.distance_to(anchor),
			"threat": threat, "alive": f.living_count() > 0, "lockable": true, "visible": _p30_group_visible(f),
			"group": true}
		if with_screen and cam != null and not cam.is_position_behind(anchor):
			c["screen"] = cam.unproject_position(anchor)
		out.append(c)
	return out


## A group is visible when its anchor or one of its P30_VISIBLE_PROBES members nearest the giant is.
func _p30_group_visible(f: Formation) -> bool:
	var space := player.get_world_3d().direct_space_state
	var from := eye()
	if HitQueryAdapter.line_clear(space, from, f.anchor(), HitQueryAdapter.LAYER_WORLD, []):
		return true
	var near: Array = []
	for m in f.members:
		if is_instance_valid(m) and m.entity != null and m.entity.is_alive():
			near.append(m)
	near.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	for i in mini(P30_VISIBLE_PROBES, near.size()):
		if is_visible((near[i] as EnemyActor).entity):
			return true
	return false


## sync_lock: a group lock points the camera at its focus member and frames its formation's anchor.
func _p30_sync_camera(id: String) -> void:
	var f := _p30_group(id)
	player.camera_rig.call("p30_set_lock_group", f)
	if f != null:
		player.camera_rig.lock_target = _p30_locked_member()


## maintain_lock for a group: the tracker's rules on the group (alive while a member stands, the
## distance and line of sight to its anchor), the camera kept on the current focus member.
func _p30_maintain(dt: float) -> void:
	var lock := player.lock
	var f := _p30_group(lock.target_id)
	var info := {"exists": f != null}
	if f != null:
		info["alive"] = f.living_count() > 0
		info["lockable"] = true
		info["distance"] = eye().distance_to(f.anchor())
		info["visible"] = _p30_group_visible(f)
	var reason := lock.update(dt, info)
	if reason != "":
		sync_lock("", reason)
		return
	var member := _p30_locked_member()
	if member != player.camera_rig.lock_target:
		player.camera_rig.lock_target = member


## on_any_entity_died: the locked group's last standing member died.
func _p30_on_any_entity_died(_id: String) -> void:
	if not player.lock.is_locked() or not _p30_is_group(player.lock.target_id):
		return
	var f := _p30_group(player.lock.target_id)
	if f == null or f.living_count() == 0:
		release_lock("target_died")


## The lock line's text: a formation's "Pike Regiment (8)", a banner's "⚑ Banner of ...", else the
## locked target's name ("" without a lock).
func lock_label() -> String:
	if not player.lock.is_locked():
		return ""
	var id := player.lock.target_id
	if _p30_is_group(id):
		var f := _p30_group(id)
		return f.lock_label() if f != null else ""
	var e := Sim.get_entity(id)
	if e == null:
		return ""
	var actor := e.actor as EnemyActor
	if actor != null and actor.formation != null and actor.formation_slot == Formation.BANNER_SLOT:
		return actor.formation.banner_label()
	return e.display_name()


## True when the lock holds a formation group.
func is_group_locked() -> bool:
	return player.lock.is_locked() and _p30_is_group(player.lock.target_id)
