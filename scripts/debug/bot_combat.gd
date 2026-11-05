class_name BotCombat
extends RefCounted
## The Valley bot's fighting (plan §5.1, decision 30): picking a target, closing in, attacking with
## the light chain, heavies, grabs and throws, the abilities by rule, and defending according to
## the skill profile. Everything goes through the giant's input router (edges, holds and the stick)
## and its camera, exactly as a player's input would, never by editing combat state. One instance
## per level (ValleyBot makes it); what must outlive a reload is in RunMetrics.
##
## Skill profiles:
##   novice (balance targets) - perceives only telegraph_started aimed at the giant and the windup
##     start (ability_started) of enemies on screen within NOVICE_SCREEN_M; reacts NOVICE_LATENCY
##     ticks (250 ms) later, timing its answer from what it saw (the telegraph fills over the
##     windup), never from controller phases. A blockable blow: a timed parry attempt half the time
##     (with timing noise, so some become plain blocks or come late), otherwise a late block or
##     nothing. An unblockable or dashing blow (and arrows and bolts): a dodge 70 % of the time, a
##     tenth of those the wrong way. Abilities are decided at most once a second.
##   expert (the skill ceiling) - reads the controller phase and ticks-to-active of every enemy
##     attacking it: parries EXPERT_PARRY_LEAD ticks before a blockable blow lands, always dodges
##     dashes, charges, slams and shots, decides abilities every 6 ticks.
## Random choices use the bot's RNG (Sim.rng_for("bot"), seeded by --bot-seed).

const NOVICE := "novice"
const EXPERT := "expert"
const NOVICE_LATENCY_TICKS := 15
const NOVICE_SCREEN_M := 8.0
const NOVICE_PARRY_P := 0.5
const NOVICE_LATE_BLOCK_P := 0.5
const NOVICE_DODGE_P := 0.7
const NOVICE_WRONG_WAY_P := 0.1
const NOVICE_TIMING_NOISE_TICKS := 9
const NOVICE_ABILITY_EVERY_TICKS := 60
const EXPERT_ABILITY_EVERY_TICKS := 6
const EXPERT_PARRY_LEAD_MIN := 6
const EXPERT_PARRY_LEAD_MAX := 10
const PARRY_LEAD_TICKS := 6
const DODGE_LEAD_TICKS := 10
const BLOCK_HOLD_TICKS := 16
const EXPERT_WATCH_M := 12.0
## Hostile, aware enemies this far (by stage) pull the bot into a fight.
const ENGAGE_RADIUS_M := [16.0, 22.0, 28.0]
## A target this much higher than the giant's feet is out of melee reach (an archer on a wall).
const ELEVATED_M := 2.5
## Targets narrower than this get the reach band (BotCombat.reach_band); larger ones the reach.
const SMALL_TARGET_RADIUS_M := 0.8
const BOSS_ID := "valley.arena.ogre_king"
const RUNIC_BOLT := "ability.runic_bolt"
const BOULDER_HURL := "ability.boulder_hurl"
const MEND := "ability.ancestral_mend"
const STONE_SKIN := "ability.stone_skin"
const FOOTFALL := "ability.heavy_footfall"
const SWEEP := "ability.sweeping_blow"
const ROAR := "ability.thunder_roar"
const GRIP := "ability.crushing_grip"
const SURGE := "ability.titan_surge"

var bot = null                  ## ValleyBot (movement helpers, rng, metrics)
var player: GiantPlayer
var skill := NOVICE
var rng: RandomNumberGenerator
var target: EnemyActor = null
var boss_engaged := false

var _reactions: Array = []      ## {"at", "kind": block|dodge, "dir": Vector3, "actor", "why"}
var _seen: Dictionary = {}      ## actor id -> instance/tick already reacted to
var _block_until := -1
var _dodge_hold_until := -1
var _dodge_dir := Vector3.ZERO
var _next_ability_tick := 0
var _stone_skin_done := false
var _lock_wait_until := -1
var _hold_started := -1
var _last_light_tick := -100
var _connected := false
var _ability_log: Array = []
var _bands: Dictionary = {}     ## reach_band cache


func setup(p_bot: Variant, p_player: GiantPlayer, p_skill: String, p_rng: RandomNumberGenerator) -> void:
	bot = p_bot
	player = p_player
	skill = p_skill if p_skill in [NOVICE, EXPERT] else NOVICE
	rng = p_rng
	if not _connected:
		_connected = true
		Events.telegraph_started.connect(_on_telegraph_started)
		Events.ability_started.connect(_on_ability_started)


func teardown() -> void:
	if _connected:
		_connected = false
		if Events.telegraph_started.is_connected(_on_telegraph_started):
			Events.telegraph_started.disconnect(_on_telegraph_started)
		if Events.ability_started.is_connected(_on_ability_started):
			Events.ability_started.disconnect(_on_ability_started)
	player = null
	target = null


func _alive_player() -> bool:
	return player != null and is_instance_valid(player) and player.is_inside_tree() and player.entity.is_alive()


# --------------------------------------------------------------------------- perception

## Novice: a telegraph aimed at the giant (always perceived, however far: the decal shows).
func _on_telegraph_started(tick: int, actor_id: String, action_id: String, target_id: String,
		_shape: String, _origin: Vector3, _yaw: float, _radius: float, _length: float, _duration_s: float) -> void:
	if skill != NOVICE or not _alive_player() or target_id != player.entity.entity_id:
		return
	_perceive(tick, actor_id, action_id, "telegraph")


## Novice: the windup start of an enemy on screen within NOVICE_SCREEN_M (its swing begins).
func _on_ability_started(tick: int, actor_id: String, action_id: String, _instance_id: int) -> void:
	if skill != NOVICE or not _alive_player() or actor_id == player.entity.entity_id:
		return
	var e := Sim.get_entity(actor_id)
	if e == null or e.team != CombatEntity.Team.ENEMY or e.actor == null:
		return
	var a := e.actor as EnemyActor
	if a == null or a.brain == null or a.brain.target_id != player.entity.entity_id:
		return
	if (e.actor as Node3D).global_position.distance_to(player.global_position) > NOVICE_SCREEN_M:
		return
	if bot != null and bot.metrics != null and not bot.metrics.on_camera(e):
		return
	_perceive(tick, actor_id, action_id, "windup")


func _perceive(tick: int, actor_id: String, action_id: String, why: String) -> void:
	if int(_seen.get(actor_id, -1000)) == tick:
		return   # the telegraph and the windup of one swing arrive together
	_seen[actor_id] = tick
	var a := GameData.get_action(action_id)
	if a == null or not a.is_attack():
		return
	var e := Sim.get_entity(actor_id)
	if e == null or e.actor == null:
		return
	var eta := tick + _impact_ticks(a, e.actor as Node3D, 0)
	_plan_reaction(tick + NOVICE_LATENCY_TICKS, eta, a, e.actor as Node3D, why)


## Ticks from the windup's start (elapsed ticks already in it) until the blow lands: the rest of
## the windup, plus the flight of a projectile or the run of a dash or charge.
func _impact_ticks(a: ActionDef, actor: Node3D, elapsed: int) -> int:
	var t := maxi(0, a.windup_ticks - elapsed)
	if not _alive_player():
		return t
	var dist := actor.global_position.distance_to(player.global_position)
	var proj: Variant = a.params.get("projectile")
	if typeof(proj) == TYPE_DICTIONARY:
		t += int(dist / maxf(1.0, float(proj.get("speed_mps", 20.0))) * 60.0)
	var motion: Variant = a.params.get("motion")
	if typeof(motion) == TYPE_DICTIONARY:
		var reach := maxf(0.0, dist - 2.0)
		var cap := float(motion.get("max_distance_m", reach))
		t += int(minf(reach, cap) / maxf(1.0, float(motion.get("speed_mps", 9.0))) * 60.0)
	return t


## Whether a blow should be dodged rather than blocked: unblockable, a dash or charge, an area
## slam, or a projectile.
static func dodge_worthy(a: ActionDef) -> bool:
	return a.has_tag("Unblockable") or a.has_tag("Charge") or a.has_tag("AoE") \
		or a.hit_shape == "projectile" or typeof(a.params.get("motion")) == TYPE_DICTIONARY


func _plan_reaction(decide_tick: int, eta: int, a: ActionDef, actor: Node3D, why: String) -> void:
	var dodge := dodge_worthy(a)
	if skill == EXPERT:
		if dodge:
			_add_reaction(eta - DODGE_LEAD_TICKS, "dodge", actor, why)
		else:
			_add_reaction(eta - rng.randi_range(EXPERT_PARRY_LEAD_MIN, EXPERT_PARRY_LEAD_MAX), "block", actor, why)
		return
	if dodge:
		if rng.randf() < NOVICE_DODGE_P:
			var wrong := rng.randf() < NOVICE_WRONG_WAY_P
			var at := maxi(decide_tick, eta - DODGE_LEAD_TICKS + rng.randi_range(-NOVICE_TIMING_NOISE_TICKS, NOVICE_TIMING_NOISE_TICKS))
			_add_reaction(at, "dodge_wrong" if wrong else "dodge", actor, why)
		return
	var roll := rng.randf()
	if roll < NOVICE_PARRY_P:
		var at := eta - PARRY_LEAD_TICKS + rng.randi_range(-NOVICE_TIMING_NOISE_TICKS, NOVICE_TIMING_NOISE_TICKS)
		_add_reaction(maxi(decide_tick, at), "block", actor, why)
	elif roll < NOVICE_PARRY_P + (1.0 - NOVICE_PARRY_P) * NOVICE_LATE_BLOCK_P:
		_add_reaction(maxi(decide_tick, eta + rng.randi_range(0, 6)), "block", actor, why + ":late")


func _add_reaction(at: int, kind: String, actor: Node3D, why: String) -> void:
	_reactions.append({"at": at, "kind": kind, "actor": weakref(actor), "why": why})


## Expert perception: every enemy within EXPERT_WATCH_M (or any distance for shots and charges)
## winding up an attack at the giant gets a reaction once per swing, from its controller phase.
func _expert_watch(tick: int) -> void:
	var tree := player.get_tree()
	# The Hollow's sparring post is not an "enemy" (it never dies) but swings at the giant all the same.
	for n in tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group(SparringPost.GROUP):
		var e := n as EnemyActor
		if e == null or not e.is_inside_tree() or e.entity == null or not e.entity.is_alive() or e.controller == null:
			continue
		if (e.entity.team != CombatEntity.Team.ENEMY and not (e is SparringPost)) or e.brain == null \
				or e.brain.target_id != player.entity.entity_id:
			continue
		var c := e.controller
		if c.action == null or c.phase() != ActionDef.Phase.WINDUP or not c.action.is_attack():
			continue
		var far_ok := c.action.hit_shape == "projectile" or typeof(c.action.params.get("motion")) == TYPE_DICTIONARY
		if not far_ok and e.global_position.distance_to(player.global_position) > EXPERT_WATCH_M:
			continue
		if int(_seen.get(e.entity_id, -1)) == c.instance_id:
			continue
		_seen[e.entity_id] = c.instance_id
		_plan_reaction(tick, tick + _impact_ticks(c.action, e, c.elapsed), c.action, e, "phase")


# --------------------------------------------------------------------------- defence (every tick)

## Runs every tick (fighting or not): perception for the expert, then the reactions that are due,
## then the block release. Returns true while a defensive move is under way (no attack then).
func defend(tick: int) -> bool:
	if not _alive_player():
		_reactions.clear()
		return false
	if skill == EXPERT:
		_expert_watch(tick)
	var r := player.router
	var busy := false
	var keep: Array = []
	for re: Dictionary in _reactions:
		var at := int(re.at)
		if at > tick:
			keep.append(re)
			if at - tick <= 20:
				busy = true
			continue
		if tick - at > 6:
			continue   # too stale to act on
		var actor: Node3D = (re.actor as WeakRef).get_ref() as Node3D
		match str(re.kind):
			"block":
				_press_block(tick, actor)
			"dodge", "dodge_wrong":
				_press_dodge(tick, actor, str(re.kind) == "dodge_wrong")
		busy = true
	_reactions = keep
	if _block_until >= 0 and tick >= _block_until:
		_block_until = -1
		r.set_injected_hold(&"block", false)
		r.inject_edge(&"block_release")
	if _block_until >= 0 or tick < _dodge_hold_until:
		busy = true
	return busy


func _press_block(tick: int, actor: Node3D) -> void:
	var r := player.router
	if player.controller.state == CombatController.State.BLOCKING:
		_block_until = maxi(_block_until, tick + BLOCK_HOLD_TICKS)
		return
	# Raise the guard toward the attacker when nothing is locked (the guard faces the aim).
	if actor != null and is_instance_valid(actor) and player.targeting.locked_entity() == null:
		player.camera_rig.yaw = TargetingRules.yaw_of(_flat(actor.global_position - player.global_position))
	r.set_injected_hold(&"block", true)
	r.inject_edge(&"block_press")
	_block_until = tick + BLOCK_HOLD_TICKS


func _press_dodge(tick: int, actor: Node3D, wrong: bool) -> void:
	var away := Vector3.BACK
	if actor != null and is_instance_valid(actor):
		var to := _flat(player.global_position - actor.global_position)
		if to.length_squared() > 1e-4:
			away = to.normalized()
	var side := away.cross(Vector3.UP).normalized()
	if rng.randf() < 0.5:
		side = -side
	var dir := (side * 0.8 + away * 0.6).normalized()
	if wrong:
		dir = -away
	if _block_until >= 0:
		_block_until = -1
		player.router.set_injected_hold(&"block", false)
		player.router.inject_edge(&"block_release")
	_dodge_dir = dir
	_dodge_hold_until = tick + 3
	if bot != null:
		bot.steer_world(dir, false)
	player.router.inject_edge(&"dodge")


## The tick until which a dodge holds its stick (ValleyBot leaves movement alone until then).
func dodge_steer_until() -> int:
	return _dodge_hold_until


## Forgets every planned reaction (the tutorial's dodge lesson wants a roll, not a block).
func clear_reactions() -> void:
	_reactions.clear()


# --------------------------------------------------------------------------- targets

## Hostile enemies (team ENEMY, alive) within `radius` that are aware of the giant, not fleeing or
## routed, nearest first. Elevated ones (archers on walls) are included only with include_elevated.
func threats(radius: float, include_elevated := true) -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	if not _alive_player():
		return out
	var pos := player.global_position
	for n in player.get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyActor
		if not is_threat(e):
			continue
		if _flat(e.global_position - pos).length() > radius:
			continue
		if not include_elevated and is_elevated(e):
			continue
		out.append(e)
	out.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	return out


## A hostile enemy (team ENEMY, alive, targetable) engaged with the giant (aware of it or after it)
## and not fleeing, routed or walking home.
func is_threat(e: EnemyActor) -> bool:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or e.entity == null or not e.entity.is_alive():
		return false
	if e.entity.team != CombatEntity.Team.ENEMY or e.brain == null or not TargetingRules.player_may_target(e.entity):
		return false
	if e.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED, EnemyBrain.AIState.RETURN]:
		return false
	return e.brain.aware or e.brain.target_id == player.entity.entity_id


func is_elevated(e: Node3D) -> bool:
	return e.global_position.y - player.global_position.y > ELEVATED_M


func engage_radius() -> float:
	var stage := clampi(player.current_growth_stage(), 1, 3)
	return float(ENGAGE_RADIUS_M[stage - 1])


## The target to fight: `preferred` (an objective's kill target) when it is alive and near, else
## the boss when engaged, else the nearest reachable threat; an elevated one only when a ranged
## ability can reach it now.
func pick_target(preferred: Node3D = null) -> EnemyActor:
	if preferred is EnemyActor and _fightable(preferred as EnemyActor):
		return preferred as EnemyActor
	var near := threats(engage_radius())
	for e in near:
		if e.is_in_group(OgreBoss.GROUP):
			return e
	for e in near:
		if not is_elevated(e):
			return e
	for e in near:
		if is_elevated(e) and (ready_slot(RUNIC_BOLT) != "" or ready_slot(BOULDER_HURL) != ""):
			return e
	return null


func _fightable(e: EnemyActor) -> bool:
	return e != null and is_instance_valid(e) and e.is_inside_tree() and e.entity != null and e.entity.is_alive() \
		and TargetingRules.player_may_target(e.entity)


# --------------------------------------------------------------------------- slots

## The slot key ("slot_1".."slot_8", "ultimate") holding `action_id`, or "".
func slot_of(action_id: String) -> String:
	for key: String in GiantPlayer.SLOT_KEYS:
		if str(player.controller.loadout.get(key, "")) == action_id:
			return key
	return ""


## The slot holding `action_id` when it could be used now (nothing refuses it), else "".
func ready_slot(action_id: String) -> String:
	var key := slot_of(action_id)
	if key == "":
		return ""
	return key if slot_reason(key) == "" else ""


## Why the slot's request would be refused now ("" = it would be accepted), with the components'
## own prechecks (range, grab), as the HUD asks.
func slot_reason(key: String) -> String:
	var c := player.controller
	var why := ""
	if key == "ultimate":
		why = c.preview_reason(&"ultimate")
	else:
		why = c.preview_reason(&"slot", {"slot": int(key.substr(5))})
	if why != "":
		return why
	var def: ActionDef = c.library.get(str(c.loadout.get(key, "")))
	if def == null:
		return "empty_slot"
	if player.attack != null and player.attack.has_method("range_reason"):
		why = str(player.attack.range_reason(def))
		if why != "":
			return why
	if player.grab != null and (PlayerGrab.is_crush(def) or def.id == PlayerGrab.HURL_ID or player.grab.is_holding()):
		why = str(player.grab.ability_reason(def, true))
	return why


## Readiness of every slotted ability (RunMetrics' "used when ready" ratio).
func readiness() -> Dictionary:
	var out := {}
	for key: String in GiantPlayer.SLOT_KEYS:
		var id := str(player.controller.loadout.get(key, ""))
		if id == "":
			continue
		out[id] = slot_reason(key) == ""
	return out


func use_slot(key: String, why: String) -> void:
	player.router.inject_edge(StringName(key))
	_ability_log.append([Sim.tick, key, why])


# --------------------------------------------------------------------------- fighting

## One tick of fighting `t`: keep the lock, close in, then attack or use an ability. The bot moves
## the giant through ValleyBot.steer_toward (paths when far).
func fight(tick: int, t: EnemyActor) -> void:
	target = t
	if not _alive_player() or t == null:
		return
	var r := player.router
	var c := player.controller
	var holding: bool = player.grab != null and player.grab.is_holding()
	if holding:
		_throw(tick)
		return
	# The giant's blows go where the lock points: a different threat already locked and close is
	# the one fought (a throw locks the next enemy, for one).
	t = _ensure_lock(tick, t)
	target = t
	var to := _flat(t.global_position - player.global_position)
	var dist := to.length()
	if bot != null and bot.metrics != null:
		bot.metrics.note_engagement(dist)
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	var t_radius := EnemyActor.entity_radius(t.entity) if t.entity != null else 0.5
	var t_height := t.entity.combatant.height_m if t.entity != null and t.entity.combatant != null else 1.8
	# A man-sized target (soldiers, archers, mages, wolves): stand where the swings land (the
	# weapon's arc at this stage, with this weapon, on this target's size), a little short of the
	# middle of the light's band (its far edge is optimistic), and back off when near its inner edge.
	# A large one (ogres, the King: hurtboxes high on a broad body): by the reach, as before.
	var small := t_radius < SMALL_TARGET_RADIUS_M
	var light_band := reach_band(_loadout_action(&"light"), t_radius, t_height) if small else Vector2.ZERO
	var heavy_band := reach_band(_loadout_action(&"heavy"), t_radius, t_height) if small else Vector2.ZERO
	var want := maxf(1.0, reach * 0.8 + t_radius * 0.5)
	if t.is_in_group(OgreBoss.GROUP):
		want = reach * 0.9 + t_radius * 0.5
	var too_close := 0.0
	if light_band != Vector2.ZERO:
		want = lerpf(light_band.x, light_band.y, 0.45)
		too_close = light_band.x + 0.25
	var busy := defend_busy(tick)
	if not busy and _abilities(tick, t, dist):
		return
	if is_elevated(t):
		# Out of melee reach: ranged abilities only (above); otherwise stand off.
		if bot != null:
			bot.stop_moving()
		return
	if _boss_positioning(tick, t):
		return
	if dist > want:
		if bot != null:
			bot.steer_toward(t.global_position, dist > 10.0)
		return
	if too_close > 1.0 and dist < too_close and not busy and c.state == CombatController.State.LOCOMOTION:
		if bot != null:
			bot.steer_world(-to.normalized(), false)   # step back into the swing's reach
		return
	if bot != null:
		bot.stop_moving()
	if busy:
		return
	if c.state == CombatController.State.BLOCKING:
		return
	if c.state != CombatController.State.LOCOMOTION and not _chain_window(c):
		return
	# Grab a staggered target that can be grabbed (a throw follows); Crushing Grip on a small one.
	if player.grab != null and t.entity != null and t.controller != null \
			and t.controller.state == CombatController.State.STAGGERED:
		var grip := ready_slot(GRIP)
		if grip != "" and player.grab.check_target(t.entity, "crush", "small") == "":
			use_slot(grip, "grip a staggered target")
			return
		if player.grab.check_target(t.entity, "hold") == "" and threats(25.0).size() >= 2:
			r.inject_edge(&"interact")
			_hold_started = tick
			return
	var heavy := t.is_guarding() or (t.controller != null and t.controller.state == CombatController.State.STAGGERED) \
		or (t.controller != null and t.controller.phase() == ActionDef.Phase.RECOVERY and t.is_in_group(OgreBoss.GROUP))
	var light_lands := _in_band(light_band, dist)
	var heavy_lands := _in_band(heavy_band, dist)
	if heavy_lands and (heavy or not light_lands) and c.preview_reason(&"heavy") == "":
		r.inject_edge(&"heavy")
		return
	if light_lands and c.preview_reason(&"light") in ["", "busy"]:
		r.inject_edge(&"light")
		_last_light_tick = tick


## The loadout's action for `kind` (light: the chain's first; heavy).
func _loadout_action(kind: StringName) -> ActionDef:
	var c := player.controller
	return c.library.get(str(c.loadout.get(String(kind), ""))) as ActionDef


## True when `dist` is within `band` (with 0.3 m of slack), or when the band is unknown.
static func _in_band(band: Vector2, dist: float) -> bool:
	return band == Vector2.ZERO or (dist >= band.x - 0.3 and dist <= band.y + 0.3)


## The distances (centre to centre, straight ahead) at which `action`'s weapon arc lands on a target
## of radius `t_radius` and height `t_height`, from the swing's geometry at the giant's stage and
## weapon now (AttackGeometry, as PlayerAttack sweeps it): Vector2(nearest, farthest), or
## Vector2.ZERO when it is not a weapon arc or lands nowhere within 14 m. Cached.
func reach_band(action: ActionDef, t_radius: float, t_height: float) -> Vector2:
	if action == null or action.hit_shape != "weapon_arc" or action.arc.is_empty() or player.attack == null:
		return Vector2.ZERO
	var key := "%d|%s|%.2f|%.2f|%.2f|%.1f|%.1f" % [player.current_growth_stage(), action.id, player.arm_length,
		player.weapon_length, float(player.weapon_hit_radius()), t_radius, t_height]
	if _bands.has(key):
		return _bands[key]
	var pitch := float(player.attack.arc_pitch_offset_for(action))
	var segs: Array = []
	for i in 25:
		var ang := AttackGeometry.arc_point(action, float(i) / 24.0)
		var dir := AttackGeometry.local_direction(ang.x, ang.y + pitch)
		segs.append(AttackGeometry.segment_local(player.weapon_pivot, dir, player.arm_length,
			player.arm_length + player.weapon_length))
	var hit := float(player.weapon_hit_radius()) + t_radius
	var lo := INF
	var hi := -INF
	var d := 0.5
	while d <= 14.0:
		var a := Vector3(0, 0.05, -d)
		var b := Vector3(0, maxf(0.2, t_height), -d)
		for seg: PackedVector3Array in segs:
			var pts := Geometry3D.get_closest_points_between_segments(seg[0], seg[1], a, b)
			if pts[0].distance_to(pts[1]) <= hit:
				lo = minf(lo, d)
				hi = maxf(hi, d)
				break
		d += 0.25
	var band := Vector2(lo, hi) if lo <= hi else Vector2.ZERO
	_bands[key] = band
	return band


func defend_busy(tick: int) -> bool:
	for re: Dictionary in _reactions:
		if int(re.at) - tick <= 20:
			return true
	return _block_until >= 0 or tick < _dodge_hold_until


## True during a light's recovery, when the next light of the chain may be pressed.
static func _chain_window(c: CombatController) -> bool:
	return c.state == CombatController.State.ATTACKING and c.action != null and c.action.kind == "light" \
		and c.phase() == ActionDef.Phase.RECOVERY and c.action.chain_next != ""


## Locks `t` when nothing (or a dead target) is locked: the camera turns to it, then the lock key.
## Returns the enemy to fight: the one locked when that is another threat close by on the giant's
## level (kept rather than toggling the lock each time the nearest enemy changes; the blows go
## where the lock points), else `t`.
func _ensure_lock(tick: int, t: EnemyActor) -> EnemyActor:
	var locked := player.targeting.locked_entity()
	if locked != null and locked.is_alive():
		if locked == t.entity:
			return t
		var other := locked.actor as EnemyActor
		if other != null and is_threat(other) and other.global_position.distance_to(player.global_position) < 10.0 \
				and not t.is_in_group(OgreBoss.GROUP) and not is_elevated(other):
			return other
		if tick >= _lock_wait_until:
			player.router.inject_edge(&"lock_press")   # toggle off, then lock `t`
			_lock_wait_until = tick + 2
		return t
	if tick >= _lock_wait_until:
		player.camera_rig.yaw = TargetingRules.yaw_of(_flat(t.global_position - player.global_position))
		player.router.inject_edge(&"lock_press")
		_lock_wait_until = tick + 8
	return t


## Holding a body: lock another enemy if there is one, then throw it (light).
func _throw(tick: int) -> void:
	var held: CombatEntity = player.grab.held_entity()
	var others: Array[EnemyActor] = []
	for e in threats(25.0):
		if held == null or e.entity != held:
			others.append(e)
	if not others.is_empty() and tick - _hold_started < 40:
		var locked := player.targeting.locked_entity()
		if locked == null or locked != others[0].entity:
			_ensure_lock(tick, others[0])
			return
	player.router.inject_edge(&"light")


## Abilities by rule (plan §5.1). True when one was used this tick.
func _abilities(tick: int, t: EnemyActor, dist: float) -> bool:
	if tick < _next_ability_tick:
		return false
	_next_ability_tick = tick + (NOVICE_ABILITY_EVERY_TICKS if skill == NOVICE else EXPERT_ABILITY_EVERY_TICKS)
	var c := player.controller
	if c.state != CombatController.State.LOCOMOTION:
		return false
	var pools := player.entity.combatant.pools
	var is_boss := t.is_in_group(OgreBoss.GROUP)
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	var near := threats(reach + 2.0, false).size()
	var crowd := threats(8.0, false).size()
	var key := ""
	if pools.health < pools.health_max * 0.5:
		key = ready_slot(MEND)
		if key != "":
			use_slot(key, "mend below 50% health")
			return true
	if is_boss and not _stone_skin_done and dist < 20.0:
		key = ready_slot(STONE_SKIN)
		if key != "":
			_stone_skin_done = true
			use_slot(key, "stone skin at the boss")
			return true
	if pools.fury >= pools.fury_max - 0.01 and (is_boss or crowd >= 3):
		key = ready_slot(SURGE)
		if key != "":
			use_slot(key, "titan surge")
			return true
	if crowd >= 3:
		key = ready_slot(ROAR)
		if key != "":
			use_slot(key, "roar at %d enemies" % crowd)
			return true
	if near >= 2:
		for id: String in [FOOTFALL, SWEEP]:
			key = ready_slot(id)
			if key != "":
				use_slot(key, "%s at %d enemies" % [id, near])
				return true
	var locked := player.targeting.locked_entity()
	if locked != null and locked == t.entity:
		var arch := RunMetrics.archetype_of(t.entity)
		var casting := t.controller != null and t.controller.state == CombatController.State.CASTING
		if (arch == "mage" and casting) or (arch == "archer" and dist > 10.0) or (is_elevated(t) and dist > 4.0):
			key = ready_slot(RUNIC_BOLT)
			if key != "":
				use_slot(key, "runic bolt at a %s" % arch)
				return true
		if (arch == "archer" and dist > 10.0) or is_elevated(t):
			key = ready_slot(BOULDER_HURL)
			if key != "":
				use_slot(key, "boulder hurl at a %s" % arch)
				return true
	return false


## Phase 2 of the Ogre King: stand with a pillar behind the giant (the charge ends on it), unless
## the boss is close or recovering (then fight). True while repositioning.
func _boss_positioning(_tick: int, t: EnemyActor) -> bool:
	if not t.is_in_group(OgreBoss.GROUP) or not t.has_method("boss_phase") or int(t.call("boss_phase")) < 2:
		return false
	var c := t.controller
	if c != null and (c.state == CombatController.State.STAGGERED or c.phase() == ActionDef.Phase.RECOVERY):
		return false
	var d := _flat(t.global_position - player.global_position).length()
	if d < 9.0:
		return false
	var arena := player.get_tree().get_first_node_in_group(BossArena.GROUP) as BossArena
	if arena == null:
		return false
	var best := Vector3.INF
	var best_d := INF
	for p: Vector3 in arena.pillar_positions():
		var dd := p.distance_to(player.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	if not best.is_finite():
		return false
	var away := _flat(best - t.global_position)
	if away.length_squared() < 1e-3:
		return false
	var spot := best - away.normalized() * 6.0
	if _flat(spot - player.global_position).length() > 2.0 and bot != null:
		bot.steer_toward(spot, true)
		return true
	if bot != null:
		bot.stop_moving()
	return true


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
