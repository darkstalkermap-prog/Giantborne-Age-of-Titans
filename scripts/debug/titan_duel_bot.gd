class_name TitanDuelBot
extends RefCounted
## A2: the balance runs' player against a titan - the bots' own fighting (BotCombat: the lock, the reach, the light
## chain and the heavies, the abilities by rule, the dodges and parries of its skill profile, all through the giant's
## input router) on the open floor of a test arena, with no route planning (the quarry is one bowl), and, with
## `flank` on, one titan rule a skilled player follows: while the titan reels, staggers or recovers from a blow, get
## round to his back (the lock then frames the back plate: TitanEnemy.titan_lock_point) and strike there.
## It stands in for the ValleyBot BotCombat reads (metrics, steer_toward, steer_world, stop_moving). Debug only.

const FLANK_M := 9.0

var player: GiantPlayer
var titan: TitanEnemy
var combat := BotCombat.new()
var metrics := RunMetrics.new()
var flank := true
var rng := RandomNumberGenerator.new()
## Ticks the giant spent getting round to his back (the report).
var flank_ticks := 0
var _guarding := false
## The ranged abilities the skilled duel took out of the loadout (the report).
var emptied: Array[String] = []
## Ticks spent getting out of a telegraph's way (the report).
var evade_ticks := 0


func setup(p: GiantPlayer, t: TitanEnemy, skill: String, seed_value: int, p_flank := true) -> void:
	player = p
	titan = t
	flank = p_flank
	rng.seed = seed_value
	p.router.use_injection = true
	if p_flank:
		_melee_only()
	combat.setup(self, p, skill, rng)


## The skilled titan fighter fights in close: the plates break under the weapon and its heavy blows, and an ability
## that flies (a hurled crag, a bolt) strikes his hide. Its projectile and magic slots are emptied for the duel.
func _melee_only() -> void:
	for key: String in player.controller.loadout:
		var a := GameData.get_action(str(player.controller.loadout[key]))
		if a != null and (a.hit_shape == "projectile" or a.category == "magic"):
			player.set_loadout_slot(key, "")
			emptied.append(a.id)


func teardown() -> void:
	combat.teardown()


## True: the bot's world rules (the reach of each blow from stage 4, the rotation of the abilities).
func _in_world() -> bool:
	return true


## One tick: the defence first (a dodge or a block due), then the flank rule, then BotCombat's fight.
func step(tick: int) -> void:
	if player == null or not player.entity.is_alive() or titan == null or not titan.entity.is_alive():
		stop_moving()
		return
	if flank and _guard(tick):
		return
	var defending := combat.defend(tick)
	if tick < combat.dodge_steer_until():
		return
	if flank and _evade(tick):
		return
	if flank and not defending and _opening() and _get_round(tick):
		return
	combat.fight(tick, titan)


## The sweep caught inside its reach (too close to walk out of it): the block held, facing him, from the late
## windup through the blow (the sweep can be blocked; nothing else of his can). True while it holds.
func _guard(_tick: int) -> bool:
	var c := titan.controller
	var a := c.action
	var r := player.router
	var want := false
	if a != null and a.hit_shape == "sector_pulse":
		var rel := player.global_position - titan.global_position
		rel.y = 0.0
		var reach := float(a.param("radius_m", 15.0)) + player.entity.combatant.height_m * 0.2
		var late := (c.phase() == ActionDef.Phase.WINDUP and c.phase_fraction() > 0.45) or c.phase() == ActionDef.Phase.ACTIVE
		want = late and rel.length() < reach - 2.0
	if want:
		stop_moving()
		r.set_injected_hold(&"block", true)
		_guarding = true
		return true
	if _guarding:
		_guarding = false
		r.set_injected_hold(&"block", false)
		r.inject_edge(&"block_release")
	return false


## The skilled player's answer to each telegraph (what the ground marker shows): out of the smash's line sideways,
## out of the sweep's reach (or round behind him when already at his flank), out of the boulder's circle, aside
## from the charge's line; BotCombat's dodge still fires at the blow. True while it moves to safety.
func _evade(_tick: int) -> bool:
	var c := titan.controller
	var a := c.action
	if a == null or c.phase() != ActionDef.Phase.WINDUP or not a.is_attack() or a.hit_shape == "none":
		return false
	var r := player.entity.combatant.height_m * 0.2 + 1.0
	var p := player.global_position
	var fwd := -titan.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var rel := p - titan.global_position
	rel.y = 0.0
	var goal := Vector3.INF
	match a.hit_shape:
		TitanEnemy.SHOCK_SHAPE, "body_sweep":
			var half := float((a.param("telegraph", {}) as Dictionary).get("width_m", 7.0)) * 0.5 + r + 1.5
			var lateral := rel.dot(right)
			if absf(lateral) < half and rel.dot(fwd) > -4.0:
				goal = p + right * (signf(lateral) if absf(lateral) > 0.5 else 1.0) * (half - absf(lateral) + 2.0)
		"sector_pulse":
			var reach := float(a.param("radius_m", 15.0)) + r + 2.0
			var off := rad_to_deg(absf(fwd.signed_angle_to(rel.normalized(), Vector3.UP))) if rel.length() > 0.1 else 0.0
			var half_arc := float(a.param("sector_deg", 220.0)) * 0.5
			if rel.length() < reach and off < half_arc + 12.0:
				goal = titan.global_position + rel.normalized() * (reach + 2.0)
		"projectile":
			var at := titan.runner.aim_point
			if at.is_finite():
				var radius := float((a.param("telegraph", {}) as Dictionary).get("radius_m", 7.0)) + r + 1.5
				var away := p - at
				away.y = 0.0
				if away.length() < radius:
					goal = at + (away.normalized() if away.length() > 0.3 else right) * (radius + 2.0)
	if not goal.is_finite():
		return false
	evade_ticks += 1
	steer_world(goal - p, true)
	return true


## His opening: reeling (a charge into stone), staggered (a plate, a poise break) or in a strike's recovery.
func _opening() -> bool:
	var c := titan.controller
	if c.state == CombatController.State.STAGGERED:
		return true
	return c.action != null and (c.phase() == ActionDef.Phase.RECOVERY or c.action.hit_shape == "none") \
		and c.action.id != "ability.stoneback_roar"


## Steers round to the point FLANK_M behind him; true while on the way (false once there: fight).
func _get_round(_tick: int) -> bool:
	var back := titan.global_position + titan.global_transform.basis.z.normalized() * (FLANK_M + 3.4)
	var to := back - player.global_position
	to.y = 0.0
	if to.length() < 3.0:
		return false
	# round him, not through him: aim beside him while his body is in the way
	var from_t := player.global_position - titan.global_position
	from_t.y = 0.0
	var side := titan.global_transform.basis.x * (1.0 if from_t.dot(titan.global_transform.basis.x) >= 0.0 else -1.0)
	var behind := from_t.dot(titan.global_transform.basis.z) > 0.0
	var goal := back if behind else titan.global_position + side * (FLANK_M + 4.0) + titan.global_transform.basis.z * 4.0
	flank_ticks += 1
	steer_world((goal - player.global_position).normalized(), true)
	return true


func steer_toward(point: Vector3, sprint: bool) -> void:
	steer_world((point - player.global_position).normalized(), sprint)


func steer_world(dir: Vector3, sprint: bool) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1e-6:
		stop_moving()
		return
	var basis_yaw := player.camera_rig.yaw
	var locked := player.targeting.locked_entity()
	if locked != null and locked.is_alive() and not player.camera_rig.is_first_person():
		basis_yaw = player.motor.yaw_to(locked.anchor_position())
	else:
		player.camera_rig.yaw = lerp_angle(player.camera_rig.yaw, TargetingRules.yaw_of(flat), 0.25)
		basis_yaw = player.camera_rig.yaw
	var local := flat.normalized().rotated(Vector3.UP, -basis_yaw)
	player.router.set_injected_move(Vector2(local.x, -local.z).limit_length(1.0))
	player.router.set_injected_hold(&"sprint", sprint)


func stop_moving() -> void:
	if player == null:
		return
	player.router.set_injected_move(Vector2.ZERO)
	player.router.set_injected_hold(&"sprint", false)
