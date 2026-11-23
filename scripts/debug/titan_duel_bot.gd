class_name TitanDuelBot
extends RefCounted
## A2: the balance runs' player against a titan - the bots' own fighting (BotCombat: the lock, the reach, the light
## chain and the heavies, the abilities by rule, the dodges and parries of its skill profile, all through the giant's
## input router) on the open floor of a test arena, with no route planning (the quarry is one bowl), and, with
## `flank` on, one titan rule a skilled player follows: while the titan reels, staggers or recovers from a blow, get
## round to his back (the lock then frames the back plate: TitanEnemy.titan_lock_point) and strike there; A3: and
## another - bait his charge into stone (step so a rock stands behind it on his line early in the windup, then
## sidestep: he runs on into the rock and reels, his back to the giant).
## A4: and two more, the fight a giant smaller than him wins: in his recoveries it strikes the plate the lock frames
## where it stands (his shins, for a giant his shoulders overtop) instead of going round to his back; and while he
## is down on a knee it walks to where its heavy reaches the lowered plate the lock frames (his back, a shoulder,
## his brow) and lands heavies there (a dodge's stamina is not kept: he cannot strike while down), lights when
## a heavy is out of stamina.
## It stands in for the ValleyBot BotCombat reads (metrics, steer_toward, steer_world, stop_moving). Debug only.

const FLANK_M := 9.0
## B2: the titan FLANK_M was set for (Stoneback's height).
const STONEBACK_H := 17.7
## A3: the share of the charge's windup the bait (a stone behind the giant) is sought in; the sidestep after it.
const BAIT_UNTIL := 0.75

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
## A3: whether the bot baits his charge into stone (TitanDuelBot._bait_spot), and the ticks it stood baiting.
var bait := true
var baits := 0
## A4: whether the bot fights his downs and his shins (TitanDuelBot._down_rule, _low_target), the ticks it spent
## on his downs and the heavies it started while he was down (the report).
var titan_rules := true
## B2: whether it goes round to his back in his openings (A2's rule). Off against a titan who turns on it faster than
## it gets round (the Ogre King, half Stoneback's size): it strikes the trophy the lock-switch picks where it stands.
var round_to_back := true
var down_ticks := 0
var down_heavies := 0
var _strike_cache: Dictionary = {}
var _retreat_until := -1
## A4: it starts backing away this long before his rise begins.
const RISE_EARLY_S := 0.4
## A4: how far aside (against straight back) the retreat goes.
const RETREAT_ASIDE := 0.8
## A4: a lock point lower than this share of the giant's height is a low target (a shin) it strikes where it stands.
const LOW_TARGET_SHARE := 0.45
## A4: the heavies' stamina its abilities leave for his next down.
const DOWN_STAMINA_HEAVIES := 2.0
## A4: the giant's stamina regeneration (decision: 15 a second after a second without spending).
const STAMINA_REGEN_PER_S := 15.0
## A4: the walk to a downed titan sprints only beyond this many metres.
const DOWN_SPRINT_M := 16.0


func setup(p: GiantPlayer, t: TitanEnemy, skill: String, seed_value: int, p_flank := true) -> void:
	player = p
	titan = t
	flank = p_flank
	rng.seed = seed_value
	p.router.use_injection = true
	if p_flank:
		_melee_only()
	combat.setup(self, p, skill, rng)
	if p_flank and titan_rules:
		var h := combat._loadout_action(&"heavy")
		combat.ability_stamina_floor = DOWN_STAMINA_HEAVIES * (h.stamina_cost if h != null else 20.0)


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
	if flank and titan_rules:
		# A5: a skilled giant picks his shins with the lock-switch while he stands (the lock's own choice frames a
		# higher plate for a stage-6 giant: TitanEnemy.auto_lock_plate) - the plate A4's rule framed
		titan.lock_choice = "" if titan.is_down() else titan.a4_lock_plate(player.entity.combatant.height_m)
	if flank and _guard(tick):
		return
	var defending := combat.defend(tick)
	if tick < combat.dodge_steer_until():
		return
	if flank and _evade(tick):
		return
	if flank and titan_rules and not defending and _down_rule(tick):
		return
	if flank and round_to_back and not defending and _opening() and not (titan_rules and _low_target()) \
			and _get_round(tick):
		return
	combat.fight(tick, titan)


# --------------------------------------------------------------------------- A4: his downs and his shins

## The point the giant's lock frames on him (TitanEnemy.titan_lock_point through the entity).
func _lock_point() -> Vector3:
	return titan.entity.lock_anchor_position(player.entity.combatant.height_m)


## True when the lock frames a low plate (his shin): the giant strikes it where it stands.
func _low_target() -> bool:
	var at := _lock_point()
	return at.is_finite() and at.y - titan.global_position.y < player.entity.combatant.height_m * LOW_TARGET_SHARE


## While he is down on a knee: to the heavy's striking distance from the lowered plate the lock frames, then heavies
## (lights when the stamina is short). True while it acts.
func _down_rule(tick: int) -> bool:
	if not titan.is_down():
		return tick < _retreat_until and _retreat()
	if titan.down_elapsed_s() < 0.1:
		return false
	down_ticks += 1
	var rise_at := titan.down_total_s() - float(titan.topple.get("rise_s", 0.0))
	if titan.down_elapsed_s() >= rise_at - RISE_EARLY_S:
		# he is getting up: out of his sweep's reach before he can swing (his daze: topple.recover_s)
		_retreat_until = tick + int((titan.down_total_s() - titan.down_elapsed_s()
			+ float(titan.topple.get("recover_s", 0.0))) * Sim.TICK_RATE)
		return _retreat()
	var c := player.controller
	var at := _lock_point()
	if not at.is_finite():
		return false
	if player.targeting.locked_entity() != titan.entity:
		return false   # (BotCombat's fight takes the lock first)
	var heavy := combat._loadout_action(&"heavy")
	var want := _strike_distance(heavy, at.y - player.global_position.y)
	var to := at - player.global_position
	to.y = 0.0
	var d := to.length()
	if d > want.y:
		steer_world(to.normalized(), d > DOWN_SPRINT_M)
		return true
	if d < want.x:
		steer_world(-to.normalized(), false)
		return true
	stop_moving()
	if c.state != CombatController.State.LOCOMOTION and not BotCombat._chain_window(c):
		return true
	var pools := player.entity.combatant.pools
	if heavy != null and pools.stamina >= heavy.stamina_cost and c.preview_reason(&"heavy") == "":
		player.router.inject_edge(&"heavy")
		down_heavies += 1
		return true
	# short of a heavy's stamina: wait for it while he stays down long enough for it to come back and land, else a light
	var left := titan.down_total_s() - float(titan.topple.get("rise_s", 0.0)) - titan.down_elapsed_s()
	var regen_s := 1.0 + maxf(0.0, (heavy.stamina_cost if heavy != null else 0.0) - pools.stamina) / STAMINA_REGEN_PER_S
	if heavy != null and left > regen_s + heavy.windup_ticks / 60.0 + 0.3:
		return true
	var light := combat._loadout_action(&"light")
	if light != null and pools.stamina >= light.stamina_cost and c.preview_reason(&"light") in ["", "busy"]:
		player.router.inject_edge(&"light")
	return true


## Backing away from him to beyond his sweep's reach (and the giant's own size); false once there.
func _retreat() -> bool:
	var away := player.global_position - titan.global_position
	away.y = 0.0
	var sweep := GameData.get_action("ability.stoneback_sweep")
	var reach := (float(sweep.param("radius_m", 13.5)) if sweep != null else 13.5) \
		+ player.entity.combatant.height_m * 0.2 + 3.0
	if away.length() >= reach:
		return false
	# (aside as well as back: straight back from his front is his smash's line)
	var right := titan.global_transform.basis.x
	right.y = 0.0
	var side := right.normalized() * (1.0 if away.dot(right) >= 0.0 else -1.0)
	var dir := away.normalized() if away.length() > 0.1 else player.global_transform.basis.z
	steer_world((dir + side * RETREAT_ASIDE).normalized(), false)
	return true


## The horizontal distances from a point `height` m above the giant's feet at which `action`'s swing (its best tilt:
## PlayerAttack.a2_plate_offset) reaches it: Vector2(nearest, farthest), or the stage's reach band when none does.
func _strike_distance(action: ActionDef, height: float) -> Vector2:
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	if action == null or player.attack == null:
		return Vector2(reach * 0.5, reach * 0.8)
	var key := "%d|%s|%d" % [player.current_growth_stage(), action.id, int(round(height * 2.0))]
	if _strike_cache.has(key):
		return _strike_cache[key]
	var hit := float(player.weapon_hit_radius()) + 0.3
	var lo := INF
	var hi := -INF
	var d := 2.0
	while d <= 16.0:
		var off := player.attack.a2_plate_offset(action, d, height)
		var m := player.attack.closest_approach(action, off, d, height - 0.05 - PlayerAttack.A2_PLATE_BAND_M * 0.5,
			PlayerAttack.A2_PLATE_BAND_M)
		if m <= hit:
			lo = minf(lo, d)
			hi = maxf(hi, d)
		d += 0.5
	var band := Vector2(lo, hi) if lo <= hi else Vector2(reach * 0.5, reach * 0.8)
	if band.y - band.x > 2.0:
		band = Vector2(band.x + 0.5, band.y - 1.0)   # (well inside it: the body moves as it swings)
	_strike_cache[key] = band
	return band


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
	if a.hit_shape == "body_sweep" and bait:
		var run := float((a.param("motion", {}) as Dictionary).get("max_distance_m", 75.0))
		if _stone_on_line(titan.global_position + Vector3.UP * 4.0, p, run):
			# the stone stands behind the giant on his line: hold there (he turns on it to the end of his windup);
			# the dodge at his rush (BotCombat) takes it out of his way and he runs on into the stone
			baits += 1
			stop_moving()
			return true
		var lure := _bait_spot(a, c.phase_fraction(), r)
		if lure.is_finite():
			evade_ticks += 1
			steer_world(lure - p, true)
			return true
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


## A3, baiting the charge: early in its windup, when no stone stands on his line through the giant, the point a few
## metres aside whose line from him meets stone (a rock, the quarry's wall: WORLD) within the charge's run - the giant
## steps there so the stone stands behind it and holds (he turns on the giant to the end of his windup); its dodge at
## his rush takes it out of his way and he runs on into the stone. Past BAIT_UNTIL of the windup with no stone behind
## it, the ordinary sidestep. INF when the windup is late or no stone is near.
func _bait_spot(a: ActionDef, f: float, r: float) -> Vector3:
	if f >= BAIT_UNTIL:
		return Vector3.INF
	var p := player.global_position
	var from := titan.global_position + Vector3.UP * 4.0
	var run := float((a.param("motion", {}) as Dictionary).get("max_distance_m", 75.0))
	var rel := p - titan.global_position
	rel.y = 0.0
	var side := rel.normalized().cross(Vector3.UP)
	for k: float in [4.0, -4.0, 8.0, -8.0, 12.0, -12.0]:
		var spot := p + side * k
		if _stone_on_line(from, spot, run):
			# (no closer than the sidestep needs to the stone: the giant must still get out of his way)
			return spot
	return Vector3.INF


## Whether WORLD geometry stands on the line from `from` through `to` within `run` metres, beyond `to` by at least
## a few metres (the stone behind the giant, not between them).
func _stone_on_line(from: Vector3, to: Vector3, run: float) -> bool:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 1.0:
		return false
	var end := from + dir.normalized() * run
	var q := PhysicsRayQueryParameters3D.create(from, end, HitQueryAdapter.LAYER_WORLD)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var at := hit.position as Vector3
	return Vector2(at.x - from.x, at.z - from.z).length() > Vector2(dir.x, dir.z).length() + 6.0


## His opening: reeling (a charge into stone), staggered (a plate, a poise break) or in a strike's recovery.
func _opening() -> bool:
	var c := titan.controller
	if c.state == CombatController.State.STAGGERED:
		return true
	return c.action != null and (c.phase() == ActionDef.Phase.RECOVERY or c.action.hit_shape == "none") \
		and c.action.id != "ability.stoneback_roar"


## Steers round to the point FLANK_M behind him; true while on the way (false once there: fight). B2: the distances
## are Stoneback's (17.7 m) and shrink with a smaller titan's height (the Ogre King's 8.5 m: about half).
func _get_round(_tick: int) -> bool:
	var k := flank_scale()
	var back := titan.global_position + titan.global_transform.basis.z.normalized() * (FLANK_M + 3.4) * k
	var to := back - player.global_position
	to.y = 0.0
	if to.length() < 3.0:
		return false
	# round him, not through him: aim beside him while his body is in the way
	var from_t := player.global_position - titan.global_position
	from_t.y = 0.0
	var side := titan.global_transform.basis.x * (1.0 if from_t.dot(titan.global_transform.basis.x) >= 0.0 else -1.0)
	var behind := from_t.dot(titan.global_transform.basis.z) > 0.0
	var goal := back if behind else titan.global_position + side * (FLANK_M + 4.0) * k + titan.global_transform.basis.z * 4.0 * k
	flank_ticks += 1
	steer_world((goal - player.global_position).normalized(), true)
	return true


## B2: the flank's scale - the titan's height against Stoneback's (1 for him).
func flank_scale() -> float:
	return clampf(float(titan.record.get("height_m", STONEBACK_H)) / STONEBACK_H, 0.4, 1.0)


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
