class_name PlayerTargeting
extends PlayerComponent
## Hard lock-on (acquire, switch, release, upkeep) and the soft-target nudge during attack
## windups (moved unchanged from the M1 GiantPlayer). The lock state itself is player.lock
## (a LockOnTracker); camera_rig.lock_target and Events.lock_target_changed are only ever
## updated through sync_lock().
##
## Which entities the player may target at all is decided in one place, may_target(): P03
## switches it to TargetingRules.player_may_target (hostile-only targeting), P11a adds the
## boss's extra lock anchors where the candidates are gathered.


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
	return Sim.get_entity(player.lock.target_id)


## Whether lock-on and soft targeting may consider `e` at all.
func may_target(e: CombatEntity) -> bool:
	return e != null and e != player.entity and CombatEntity.can_damage(player.entity.team, e.team)


func eye() -> Vector3:
	return player.global_position + Vector3.UP * player.entity.combatant.height_m \
		* float(player.profile.get("eye_height_ratio", 0.92))


func is_visible(target: CombatEntity) -> bool:
	var space := player.get_world_3d().direct_space_state
	return HitQueryAdapter.line_clear(space, eye(), target.anchor_position(),
		HitQueryAdapter.LAYER_WORLD, target.occlusion_rids)


## Lock candidate snapshots for LockOnTracker (see its header for the keys).
func gather_candidates(with_screen: bool) -> Array:
	var out: Array = []
	var from := eye()
	var cam := player.camera_rig.camera
	for e: CombatEntity in Sim.entities():
		if not may_target(e) or not e.combatant.lockable:
			continue
		var anchor := e.anchor_position()
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
	var max_rad := deg_to_rad(action.soft_target_max_deg)
	var reach := float(player.profile.get("melee_reach_m", 3.5)) + 1.5
	var base_dir := Vector3(-sin(base_yaw), 0.0, -cos(base_yaw))
	var best_score := -1.0
	var best_offset := 0.0
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
			best_offset = clampf(delta, -max_rad, max_rad)
	return best_offset


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
	if not cam.is_position_behind(current.anchor_position()):
		screen = cam.unproject_position(current.anchor_position())
	if player.lock.switch_target(direction, gather_candidates(true), screen,
			player.camera_rig.aim_forward(), Sim.tick / 60.0):
		sync_lock(player.lock.target_id, "switched")


func release_lock(reason: String) -> void:
	player.lock.release()
	sync_lock("", reason)


func sync_lock(id: String, reason: String) -> void:
	player.camera_rig.lock_target = Sim.get_entity(id) if id != "" else null
	Events.lock_target_changed.emit(player.entity.entity_id, id, reason)


func maintain_lock(dt: float) -> void:
	var lock := player.lock
	if not lock.is_locked():
		return
	var t := Sim.get_entity(lock.target_id)
	var info := {"exists": t != null}
	if t != null:
		info["alive"] = t.is_alive()
		info["lockable"] = t.combatant.lockable
		info["distance"] = eye().distance_to(t.anchor_position())
		info["visible"] = is_visible(t)
	var reason := lock.update(dt, info)
	if reason != "":
		sync_lock("", reason)


func on_any_entity_died(id: String) -> void:
	if id == player.lock.target_id:
		release_lock("target_died")


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5).

## @anchor P03
## @anchor P11a
