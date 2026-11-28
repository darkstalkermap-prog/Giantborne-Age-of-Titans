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
## B3: and the Rootwarden's: it picks his root-arm's knot first while it can reach it (a "wither" plate: no wound of his
## regrows while it is broken, and it uproots him), and while a wound of his is open and he stands within his fire's
## reach of a standing brazier it lets go of the lock, walks to the brazier and smashes it (he burns: the wound is
## seared); it gets out of his snare's circle and his stomp's ring.
## C2: and the Broken Warden's (a titan with a guard): before his shield (inside his guard's arc) it does not trade blows
## with the wall - with the stamina for two heavies it drives heavies into the shield to break his guard, else it goes
## round to his back, outside the arc (his right side is in his sweep's reach: it keeps going); his guard broken or
## down (his bar's blow's recovery, a reel, the rubble), it fights where it stands; and while a crumbling tower of his
## old walls stands within the rubble's reach of him (his record's rubble.radius_m) and he is not striking, it lets go
## of the lock, walks to the tower and brings it down on him.
## D1: and the Frostbound Titan's (a titan whose blows rime: PlayerRime): frozen fast, it throws a heavy at once (a heavy
## shatters the ice off it); with its rime past RIME_THAW_AT and a lit fire (WarmthSource) within THAW_REACH_M it lets
## go of the lock, walks to the fire and stands in its warmth until the rime is down to RIME_THAWED (unless he is down on
## a knee - then it fights - or he comes within THAW_FIGHT_M: then it fights where it stands).
## D2: and the Stormcaller's (a titan with a `storm`: his lightning runs through the storm's water, StormWater): standing
## in water while a bolt of his is coming down on water within its shock's reach, it wades out to the nearest dry ground
## (away from the bolt) - unless he stands deep in that water within the shock's reach and the giant stands shallow in
## it (its share under STORM_BAIT_WET: a bigger giant can afford it), when it stays and lets his own lightning ground
## him; and while he stands clear of the deep pool and is not striking, it goes round the pool to its far shore from
## him (STORM_BAIT_*), so his way to it runs through the deep water. His gale is braced against (the guard's rule: a
## sector of his within reach).
## E2: and the Cinder Titan's (a CinderEnemy: his fire, PlayerHeat): standing in his burning ground it steps out of it
## (to the nearest ground that does not burn and no ember is coming down on); hot (HEAT_COOL_AT, or ablaze) it lets go of
## the lock and goes to the nearest water deep enough to cool it (the stream) and stands in it until it has cooled to
## HEAT_COOLED - he follows it in, and the water quenches him; and while his crust is molten and he could be quenched, not
## striking and not down, it goes round the deep water to its far shore from him (QUENCH_LURE_*: his way to it runs
## through the water). Quenched, or down, it fights.
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
## B4: a plate on his back it goes for while it stands behind him (the Ogre King's keg: its burst drops him to a knee);
## "" none. Once it is broken the lock's own rules again.
var back_plate := ""
var down_ticks := 0
var down_heavies := 0
## B5: the plate picked with the lock-switch while he stands (_steady_pick) and whether it was broken when picked;
## steady_pick false re-picks every tick (as before B5).
var steady_pick := true
## B5: whether its evasions look for an open way (_way_open; off: straight out, as before B5). On in the Rootwarden's
## duels (his grove's trunks, braziers and resin pots stand in his fight); the other titans' duels keep their A3/B2
## evasions (the Ogre King's keg duel turned on them: with it on, his keg broke in 1 duel of 7 seeds, not 1 of 3).
var see_obstacles := false
var _pick := ""
var _pick_broken := false
## B3: whether it uses fire against regrowing wounds, the fire props it smashed and the ticks it spent at it.
var use_fire := true
var fire_ticks := 0
var _fire_prop: Node3D = null
var _fire_given_up := {}
## B3: his arena hazards in the air (the grove's falling trees): [point, radius, the tick it strikes].
var _hazards: Array = []
var _strike_cache: Dictionary = {}
## C2: the Broken Warden's rules (a titan with a guard): heavies it threw into his guard, the crumbling towers it brought
## down on him (the report).
var guard_rules := true
## D1: the cold's rules (PlayerRime), the ticks it spent going to and standing at a fire, the thaws begun, the freezes
## it shattered with a heavy (the report).
var cold_rules := true
var thaw_ticks := 0
var thaws := 0
var shatter_heavies := 0
var _thawing := false
const RIME_THAW_AT := 0.6
const RIME_THAWED := 0.12
const THAW_REACH_M := 170.0
const THAW_FIGHT_M := 16.0
## D2: the storm's rules (PlayerStorm, StormWater), the times it waded out of the water before a bolt, the times it
## stayed to bait his grounding, the ticks it spent going round to the deep pool's far shore, the gale braced (the report).
var storm_rules := true
var storm_outs := 0
var storm_baits := 0
var storm_lure_ticks := 0
var braces := 0
var _wading_out := false
var _baiting := false
const STORM_BAIT_WET := 0.12
const STORM_LURE_FROM_M := 26.0
const STORM_LURE_MAX_M := 110.0
## The rule it acted on this tick (the probe's trace).
var last_rule := ""
## E2: the fire's rules (a CinderEnemy titan), the times it stepped out of his fire, the coolings it went for and the
## ticks it spent at them, the ticks it spent luring him into the water (the report).
var heat_rules := true
var burn_steps := 0
var cool_runs := 0
var cool_ticks := 0
var quench_lure_ticks := 0
var _cooling := false
const HEAT_COOL_AT := 0.62
const HEAT_COOLED := 0.18
const QUENCH_LURE_MAX_M := 130.0
## E1: the fetters' rules (Orrik's fight only: a HeirEnemy titan): tear a chain on the giant (a heave when a heavy is
## ready, else a pull away from its anchor), out of the Throne-breaker's line once free, a winch's harpoon side-stepped
## after its aim lock, a winch in the fight broken while Orrik is not swinging (a stage-8 giant strides through it).
var fetter_rules := true
var heaves := 0
var pull_ticks := 0
var harpoon_dodges := 0
var breaker_dodges := 0
var winch_runs := 0
var winch_ticks := 0
var _winch: Node3D = null
var _winch_given_up := {}
var _harpoon_seen := {}
## E1: how far a winch may be for the giant to go for it (m), and how near Orrik may stand while it does.
const WINCH_RUN_M := 60.0
const WINCH_SAFE_FROM_HEIR_M := 18.0
var guard_heavies := 0
var towers_felled := 0
var guard_ticks := 0
var tower_ticks := 0
var _tower: Node3D = null
var _pressing := false
var _tower_given_up := {}
## C2: it drives heavies into his guard from this many heavies' stamina down to one (else it waits out of his reach).
const GUARD_PRESS_HEAVIES := 3.0
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
	if player != null and player.attack != null:
		player.attack.bot_controls()   # C3: the bots aim and buffer as they were tuned (no cursor)
	titan = t
	flank = p_flank
	rng.seed = seed_value
	p.router.use_injection = true
	if p_flank:
		_melee_only()
	combat.setup(self, p, skill, rng)
	if not Events.telegraph_started.is_connected(_on_hazard_telegraph):
		Events.telegraph_started.connect(_on_hazard_telegraph)
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
	if Events.telegraph_started.is_connected(_on_hazard_telegraph):
		Events.telegraph_started.disconnect(_on_hazard_telegraph)


## B3: his arena hazards announced (keys "<his id>#..."): the circles a skilled giant steps out of.
func _on_hazard_telegraph(tick: int, entity_id: String, _action_id: String, _target: String, _shape: String,
		origin: Vector3, _yaw: float, radius: float, _length: float, duration: float) -> void:
	if titan == null or not entity_id.begins_with(titan.entity_id + "#"):
		return
	_hazards.append([origin, radius, tick + int(duration * Sim.TICK_RATE)])


## True: the bot's world rules (the reach of each blow from stage 4, the rotation of the abilities).
func _in_world() -> bool:
	return true


## One tick: the defence first (a dodge or a block due), then the flank rule, then BotCombat's fight.
func step(tick: int) -> void:
	last_rule = ""
	if player == null or not player.entity.is_alive() or titan == null or not titan.entity.is_alive():
		stop_moving()
		return
	if flank and titan_rules:
		# A5: a skilled giant picks his shins with the lock-switch while he stands (the lock's own choice frames a
		# higher plate for a stage-6 giant: TitanEnemy.auto_lock_plate) - the plate A4's rule framed; B3: his knot first
		var pick := _wither_pick()
		titan.lock_choice = pick if pick != "" else ("" if titan.is_down()
			else _steady_pick(_shin_pick()))
		if back_plate != "" and not titan.is_down() and _behind() and titan.entity.plates != null \
				and not titan.entity.plates.is_broken(back_plate):
			titan.lock_choice = back_plate
		if guard_rules and _pressing and _before_guard():
			titan.lock_choice = titan.entity.plates.guard_plate   # (C2: battering the shield: its face framed)
	if flank and _guard(tick):
		last_rule = "block"
		return
	var defending := combat.defend(tick)
	if tick < combat.dodge_steer_until():
		return
	if flank and titan_rules and storm_rules and not defending and _storm_water_rule(tick):
		return
	if flank and titan_rules and fetter_rules and not defending and _heir_rule(tick):
		return
	if flank and _evade(tick):
		last_rule = "evade"
		return
	if flank and titan_rules and heat_rules and not defending and _heat_rule(tick):
		return
	if flank and titan_rules and use_fire and not defending and _fire_rule(tick):
		return
	if flank and titan_rules and cold_rules and not defending and _cold_rule(tick):
		return
	if flank and titan_rules and storm_rules and not defending and _lure_rule(tick):
		return
	if flank and titan_rules and heat_rules and not defending and _quench_lure(tick):
		return
	if flank and titan_rules and guard_rules and not defending and _tower_rule(tick):
		last_rule = "tower"
		return
	if flank and titan_rules and guard_rules and not defending and _guard_rule(tick):
		if last_rule == "":
			last_rule = "wait_guard"
		return
	if flank and titan_rules and not defending and _down_rule(tick):
		last_rule = "down"
		return
	if flank and round_to_back and not defending and _opening() and not (titan_rules and _low_target()
			and not _before_guard()) and _get_round(tick):
		return
	combat.fight(tick, titan)


# --------------------------------------------------------------------------- A4: his downs and his shins

## B5: A4's pick (TitanEnemy.a4_lock_plate: the nearest plate in reach, a broken one first, his shins first by their
## bias) without a broken "wither" plate: the knot's work is done once it breaks (his wounds withered, his second phase
## begun), and a skilled giant goes back to his shins - A4's fight, the topple. Kept on it (a broken plate the lock
## prefers, and it never grows back), a stage-6 giant, whose chest is level with his knot, never broke a shin again and
## never brought him down (BALANCE_LOG "B5").
func _shin_pick() -> String:
	var h := player.entity.combatant.height_m
	var ps := titan.plates()
	var best := ""
	var best_score := INF
	for c: Dictionary in titan.lock_candidates(h):
		if ps != null and bool(c.broken) and str(ps.plate(str(c.id)).get("effect", "")) == PlateRules.EFFECT_WITHER:
			continue
		if float(c.score) < best_score - 1e-4:
			best_score = float(c.score)
			best = str(c.id)
	return best if best != "" else titan.a4_lock_plate(h)


## B5: the plate the lock-switch picked is kept, as a player's pick is (decision A5-1: kept until a new lock or a new
## attempt), until it breaks or grows back or the giant can no longer reach it; then the best again. Re-picked every
## tick, the bot's lock went from one shin to the other and to the broken knot as he turned (the Rootwarden's grove
## duels at stage 5: 113 damage on his shins in 168 s, neither broken; BALANCE_LOG "B5"), so its blows were spread over
## plates a player would not have switched between.
func _steady_pick(best: String) -> String:
	var ps := titan.plates()
	if best == "" or ps == null or not steady_pick:
		_pick = ""
		return best
	if _pick != "" and ps.is_broken(_pick) == _pick_broken:
		for c: Dictionary in titan.lock_candidates(player.entity.combatant.height_m):
			if str(c.id) == _pick:
				return _pick
	_pick = best
	_pick_broken = ps.is_broken(best)
	return best


## B4: true while the giant stands behind him (more than a third of the way round from his flank).
func _behind() -> bool:
	var rel := player.global_position - titan.global_position
	rel.y = 0.0
	return rel.length() > 0.1 and rel.normalized().dot(titan.global_transform.basis.z.normalized()) > 0.3


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
	last_rule = "press %.1f [%.1f-%.1f] h%.1f" % [d, want.x, want.y, at.y - player.global_position.y]
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
	if titan.brain is TitanBrain and (titan.brain as TitanBrain).phase_sweep() != "":
		sweep = GameData.get_action((titan.brain as TitanBrain).phase_sweep())   # B3: his own
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
		if not _guarding and a != null and float(a.param("gale", 0.0)) > 0.0:
			braces += 1   # (D2: braced against his gale)
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
func _evade(tick: int) -> bool:
	if _dodge_hazard(tick):
		return true
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
				var side := signf(lateral) if absf(lateral) > 0.5 else 1.0
				var need := half - absf(lateral) + 2.0
				# B5: a skilled player steps off the line on the side that is open - not into a tree or the grove's edge
				# (not off a charge's line: A3's bait wants the stone there)
				if a.hit_shape == TitanEnemy.SHOCK_SHAPE and not _way_open(p, right * side, need) \
						and _way_open(p, -right * side, half + absf(lateral) + 2.0):
					side = -side
					need = half + absf(lateral) + 2.0
				goal = p + right * side * need
		"sector_pulse":
			var reach := float(a.param("radius_m", 15.0)) + r + 2.0
			var off := rad_to_deg(absf(fwd.signed_angle_to(rel.normalized(), Vector3.UP))) if rel.length() > 0.1 else 0.0
			var half_arc := float(a.param("sector_deg", 220.0)) * 0.5
			if rel.length() < reach and off < half_arc + 12.0:
				goal = titan.global_position + rel.normalized() * (reach + 2.0)
				goal = p + _open_way(p, goal - p)
		"cylinder_pulse":
			# B3: the stomp's ring about him - his answer to a giant at his feet (record.hug); not the Ogre King's slam,
			# which B2's band met with BotCombat's dodge at the blow
			var ring := titan.runner.pulse_radius(a) + r + 2.0
			if typeof(titan.record.get("hug")) == TYPE_DICTIONARY and rel.length() < ring:
				goal = titan.global_position + (rel.normalized() if rel.length() > 0.3 else -fwd) * (ring + 2.0)
				goal = p + _open_way(p, goal - p)
		"projectile", TitanEnemy.SNARE_SHAPE:
			var at := titan.runner.aim_point
			if at.is_finite():
				var radius := float((a.param("telegraph", {}) as Dictionary).get("radius_m", 7.0)) + r + 1.5
				var away := p - at
				away.y = 0.0
				if away.length() < radius:
					goal = at + (away.normalized() if away.length() > 0.3 else right) * (radius + 2.0)
					goal = p + _open_way(p, goal - p)
	if not goal.is_finite():
		return false
	evade_ticks += 1
	steer_world(goal - p, true)
	return true


## B5: whether the giant's body can move `dist` m along `dir` from `p` without meeting the world (a trunk, a rock, the
## grove's edge): a sphere of its capsule's radius cast at its middle. A skilled player sees the tree it would dodge
## into; the bot's evasions used to run into them (the Rootwarden's grove, BALANCE_LOG "B5").
func _way_open(p: Vector3, dir: Vector3, dist: float) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1e-6 or dist <= 0.0 or not see_obstacles:
		return true
	var radius := float(player.profile.get("capsule_radius_m", 0.85)) * 0.9
	var space := player.get_world_3d().direct_space_state
	# (at its shins - a brazier, a stump - and at its middle - a trunk, a rock face)
	for h: float in [radius + 0.35, maxf(radius + 0.4, player.entity.combatant.height_m * 0.35)]:
		var from := p + Vector3.UP * h
		if not HitQueryAdapter.sphere_contact(space, from, from + flat.normalized() * dist, radius,
				[player.get_rid()]).is_empty():
			return false
	return true


## B5: `way` (an evasion's move from `p`) when its path is open; else the nearest open turn of it (30 to 90 degrees
## either side, the same length), else `way` itself.
func _open_way(p: Vector3, way: Vector3) -> Vector3:
	var flat := Vector3(way.x, 0.0, way.z)
	if _way_open(p, flat, flat.length()):
		return way
	for deg: float in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var turned := flat.rotated(Vector3.UP, deg_to_rad(deg))
		if _way_open(p, turned, turned.length()):
			return turned
	return way


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


# --------------------------------------------------------------------------- D1: the cold

## D1: frozen fast, a heavy at once (it shatters the ice); rimed past RIME_THAW_AT, to the nearest lit fire and into its
## warmth until the rime is down to RIME_THAWED - not while he is down (it fights), and it turns to fight once he comes
## within THAW_FIGHT_M. True while it acts.
func _cold_rule(_tick: int) -> bool:
	var r = player.rime
	if r == null:
		return false
	var pc := player.controller
	if r.is_frozen():
		last_rule = "shatter"
		if pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"heavy") == "":
			player.router.inject_edge(&"heavy")
			shatter_heavies += 1
		return true
	if titan.is_down():
		_thawing = false
		return false
	if bool(r.wading) and _wade_out():
		last_rule = "wade_out"
		return true
	var frac: float = r.fraction()
	if not _thawing and frac < RIME_THAW_AT:
		return false
	if _thawing and frac <= RIME_THAWED:
		_thawing = false
		return false
	var fire := WarmthSource.nearest(player.get_tree(), player.global_position)
	if fire == null or fire.global_position.distance_to(player.global_position) > THAW_REACH_M:
		_thawing = false
		return false
	var rel := titan.global_position - player.global_position
	rel.y = 0.0
	if rel.length() < THAW_FIGHT_M + float(titan.record.get("capsule_radius_m", 4.0)) and bool(r.warm):
		return false   # (he followed it to the fire: it fights there, in the warmth)
	if not _thawing:
		thaws += 1
	_thawing = true
	thaw_ticks += 1
	last_rule = "thaw %.0f" % (frac * 100.0)
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_thaw")
	var to := fire.global_position - player.global_position
	to.y = 0.0
	if to.length() > fire.radius_m * 0.55:
		steer_world(to.normalized(), true)
		return true
	stop_moving()
	return true


## D1: standing in a tarn's open water (it rimes): to the nearest cell of ice that holds (or off the ice), the way
## away from him first. False when there is none near.
func _wade_out() -> bool:
	var sheet := IceSheet.sheet_at(player.get_tree(), player.global_position)
	if sheet == null:
		return false
	var best := Vector3.INF
	var best_d := INF
	var away := player.global_position - titan.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	for k in sheet.cells.size():
		var st := sheet.state(k)
		if st != IceSheet.WHOLE and st != IceSheet.CRACKED:
			continue
		var c := sheet.cell_centre(k)
		var to := c - player.global_position
		to.y = 0.0
		var d := to.length() - 0.5 * to.normalized().dot(away) * sheet.cell_m
		if d < best_d:
			best_d = d
			best = c
	if best == Vector3.INF or best_d > 60.0:
		return false
	steer_world((best - player.global_position).normalized(), false)
	return true


# --------------------------------------------------------------------------- D2: the storm's water

## D2: a bolt coming down on water near it while it stands in water: out to dry ground (or, he deep in that water and
## it shallow, it stays: his own lightning will ground him); he clear of the deep pool and not striking: round to the
## pool's far shore from him. True while it acts.
func _storm_water_rule(tick: int) -> bool:
	var st: PlayerStorm = player.storm
	if st == null or titan.storm.is_empty():
		return false
	var spread := float(titan.storm.get("spread_m", 30.0))
	var min_water := float(titan.storm.get("min_water_m", 0.6))
	var tree := player.get_tree()
	if st.in_water():
		var threat := Vector3.INF
		for h: Array in _hazards:
			if int(h[2]) <= tick:
				continue
			var at: Vector3 = h[0]
			if StormWater.depth_at(tree, at) < min_water:
				continue
			if Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length() <= spread + 2.0:
				threat = at
				break
		if threat != Vector3.INF:
			var his := Vector2(titan.global_position.x - threat.x, titan.global_position.z - threat.z).length()
			if titan.storm_depth() >= float(titan.storm.get("ground_depth_m", 3.0)) and his <= spread \
					and st.wet <= STORM_BAIT_WET and not titan.is_down():
				if not _baiting:
					storm_baits += 1
				_baiting = true
				return false   # (it fights on where it stands: the strike grounds him)
			_baiting = false
			var dry := _dry_point(threat)
			if dry != Vector3.INF:
				if not _wading_out:
					storm_outs += 1
				_wading_out = true
				last_rule = "wade_out"
				if player.targeting.locked_entity() != null:
					player.targeting.release_lock("bot_storm")
				steer_world((dry - player.global_position).normalized(), false)
				return true
	_wading_out = false
	_baiting = false
	return false


func _lure_rule(tick: int) -> bool:
	if player.storm == null or titan.storm.is_empty():
		return false
	return _lure(tick)


## D2: the nearest dry ground from the giant (rings 6-48 m out, eight ways), away from `from` first; INF when none.
func _dry_point(from: Vector3) -> Vector3:
	var tree := player.get_tree()
	var p := player.global_position
	var away := p - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else Vector3.BACK
	var best := Vector3.INF
	var best_d := INF
	for r: float in [6.0, 10.0, 15.0, 21.0, 28.0, 36.0, 48.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var q := p + Vector3(sin(a), 0.0, cos(a)) * r
			if StormWater.depth_at(tree, q) > 0.05 or _in_hazard(q):
				continue
			var d := r - 6.0 * Vector3(sin(a), 0.0, cos(a)).dot(away)
			if d < best_d:
				best_d = d
				best = q
		if best != Vector3.INF:
			return best
	return best


## D2: true when `q` lies inside a circle of his that has not struck yet (a bolt's), the giant's own size round it.
func _in_hazard(q: Vector3) -> bool:
	var pad := player.entity.combatant.height_m * 0.2 + 1.0
	for h: Array in _hazards:
		var at: Vector3 = h[0]
		if Vector2(at.x - q.x, at.z - q.z).length() < float(h[1]) + pad:
			return true
	return false


## D2: he stands clear of the deep pool, not striking and not down: the giant goes round it to its far shore from him
## (his way to it runs through the water). True while it moves.
func _lure(_tick: int) -> bool:
	if titan.is_down() or titan.controller.action != null:
		return false
	var deep := float(titan.storm.get("ground_depth_m", 3.0))
	if titan.storm_depth() >= deep:
		return false
	var pool := _deep_pool(deep)
	if pool.is_empty():
		return false
	var c: Vector3 = pool.centre
	var r := float(pool.radius)
	var from_him := c - titan.global_position
	from_him.y = 0.0
	if from_him.length() > STORM_LURE_MAX_M or from_him.length() < 1.0:
		return false
	var shore := c + from_him.normalized() * (r + player.entity.combatant.height_m * 0.25 + 4.0)
	var to := shore - player.global_position
	to.y = 0.0
	if to.length() < STORM_LURE_FROM_M * 0.25:
		return false   # (there: it waits for him on the shore - BotCombat fights when he comes)
	var rel := player.global_position - titan.global_position
	rel.y = 0.0
	if rel.length() < 18.0 + player.entity.combatant.height_m * 0.3:
		return false   # (he is on it: it fights)
	storm_lure_ticks += 1
	last_rule = "lure"
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_storm")
	steer_world(to.normalized(), to.length() > 70.0)
	return true


## D2: the deepest of the storm's pools (at least `deep` m deep at its middle): {"centre", "radius"}; {} when none.
func _deep_pool(deep: float) -> Dictionary:
	var best := {}
	var best_d := deep - 0.01
	for n in player.get_tree().get_nodes_in_group(StormWater.GROUP):
		var w := n as StormWater
		if w == null or w.calm():
			continue
		for pool: Variant in w.pools:
			var a := pool as Array
			var c := w.to_global(Vector3(float(a[0]), 0.0, float(a[1])))
			var d := w.depth_here(Vector3(c.x, titan.global_position.y, c.z))
			if d > best_d:
				best_d = d
				best = {"centre": Vector3(c.x, titan.global_position.y, c.z),
					"radius": minf(float(a[2]), float(a[3]))}
	return best


# --------------------------------------------------------------------------- E2: the Cinder Titan's fire

## E2: out of his fire; hot, to the water until cooled (not while he is down: it fights). True while it acts.
func _heat_rule(_tick: int) -> bool:
	var c := titan as CinderEnemy
	if c == null or player.heat == null:
		return false
	var h: PlayerHeat = player.heat
	var p := player.global_position
	var pad := player.entity.combatant.height_m * 0.05 + 1.0
	# (his crust brittle and he within its reach, it fights on in the fire until the heat is high)
	var near := c.global_position - p
	near.y = 0.0
	var close := near.length() < float(c.record.get("height_m", 40.0)) * 0.7
	var stay := (c.is_quenched() or c.is_down()) and close and h.fraction() < 0.5
	var hot := h.is_ablaze() or h.fraction() >= HEAT_COOL_AT or (_cooling and h.fraction() > HEAT_COOLED)
	# (hot, it does not step aside out of the fire: it makes for the water, through the fire if it must)
	if not stay and not hot and c.burning_at(p, pad) and (h.fraction() >= 0.1 or not close):
		var out := _unburnt_point(c, p, pad, h.fraction() >= HEAT_COOL_AT * 0.7)
		if out != Vector3.INF:
			burn_steps += 1
			last_rule = "out_of_fire"
			steer_world((out - p).normalized(), false)
			return true
	if not hot or c.is_down():
		_cooling = false
		return false
	if not _cooling:
		cool_runs += 1
	_cooling = true
	cool_ticks += 1
	last_rule = "cool"
	if h.water_m >= PlayerHeat.WATER_FULL_M * 0.8:
		# in deep enough water: stand and cool, fighting him if he comes within reach
		var rel := c.global_position - p
		rel.y = 0.0
		if rel.length() < float(c.record.get("height_m", 40.0)) * 0.6:
			return false
		stop_moving()
		return true
	var w := _water_point(c, p, PlayerHeat.WATER_FULL_M)
	if w == Vector3.INF:
		_cooling = false
		return false
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_heat")
	steer_world((w - p).normalized(), (w - p).length() > 12.0 or h.is_ablaze())
	return true


## E2: the nearest ground round `p` that is not burning and no ember is coming down on (water first when `wet`).
func _unburnt_point(c: CinderEnemy, p: Vector3, pad: float, wet: bool) -> Vector3:
	var tree := player.get_tree()
	var best := Vector3.INF
	var best_d := INF
	for r: float in [6.0, 10.0, 15.0, 21.0, 28.0, 36.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var q := p + Vector3(sin(a), 0.0, cos(a)) * r
			if c.burning_at(q, pad) or _in_hazard(q):
				continue
			var d := r - (12.0 if wet and StormWater.depth_at(tree, q) >= 1.0 else 0.0)
			if d < best_d:
				best_d = d
				best = q
		if best != Vector3.INF:
			return best
	return best


## E2: the nearest water at least `deep` m deep that does not burn (a pool's middle or a point of it toward `p`).
func _water_point(c: CinderEnemy, p: Vector3, deep: float) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group(StormWater.GROUP):
		var w := n as StormWater
		if w == null or w.calm() or not w.present():
			continue
		for pool: Variant in w.pools:
			var a := pool as Array
			var ctr := w.to_global(Vector3(float(a[0]), 0.0, float(a[1])))
			ctr.y = _ground_at(ctr, p.y)
			if w.depth_here(ctr) < deep:
				continue
			# the point of the pool's ellipse halfway from its middle toward the giant
			var to := p - ctr
			to.y = 0.0
			var q := ctr
			if to.length() > 0.5:
				var dir := to.normalized()
				var rr := Vector2(float(a[2]) * dir.x, float(a[3]) * dir.z).length()
				q = ctr + dir * minf(rr * 0.45, to.length())
			if c.burning_at(q, 2.0) or _in_hazard(q):
				continue
			var d := q.distance_to(p)
			if d < best_d:
				best_d = d
				best = q
	return best


## E2: the ground's height under `p` (the world's, else the arena floor's: `fallback`).
func _ground_at(p: Vector3, fallback: float) -> float:
	var w := player.get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot
	if w == null:
		return fallback
	var h := w.height_at(p)
	return h if not is_nan(h) else fallback


## E2: his crust molten and quenchable, he not striking, not down and dry: round the deep water to its far shore from him
## (his way to the giant runs through it). True while it moves.
func _quench_lure(_tick: int) -> bool:
	var c := titan as CinderEnemy
	if c == null or c.is_quenched() or c.is_down() or c.controller.action != null:
		return false
	var deep := float(c.cinder.get("quench_depth_m", 2.0))
	if StormWater.depth_at(player.get_tree(), c.global_position) >= deep:
		return false
	var best := {}
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group(StormWater.GROUP):
		var w := n as StormWater
		if w == null or w.calm() or not w.present():
			continue
		for pool: Variant in w.pools:
			var a := pool as Array
			var ctr := w.to_global(Vector3(float(a[0]), 0.0, float(a[1])))
			ctr.y = _ground_at(ctr, c.global_position.y)
			if w.depth_here(ctr) < deep:
				continue
			var d := Vector2(ctr.x - c.global_position.x, ctr.z - c.global_position.z).length()
			# (the deepest water counts nearer: the dammed water puts him on a knee)
			d -= w.depth_here(ctr) * 6.0
			if d < best_d:
				best_d = d
				best = {"centre": ctr, "radius": minf(float(a[2]), float(a[3]))}
	if best.is_empty():
		return false
	var ctr: Vector3 = best.centre
	var from_him := ctr - c.global_position
	from_him.y = 0.0
	if from_him.length() > QUENCH_LURE_MAX_M or from_him.length() < 1.0:
		return false
	var shore := ctr + from_him.normalized() * (float(best.radius) + player.entity.combatant.height_m * 0.25 + 3.0)
	if c.burning_at(shore, 3.0):
		return false
	var to := shore - player.global_position
	to.y = 0.0
	if to.length() < 6.0:
		return false   # (there: it waits for him across the water - BotCombat fights when he comes)
	var rel := player.global_position - c.global_position
	rel.y = 0.0
	if rel.length() < 20.0 + player.entity.combatant.height_m * 0.3:
		return false   # (he is on it: it fights)
	quench_lure_ticks += 1
	last_rule = "quench_lure"
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_heat")
	steer_world(to.normalized(), to.length() > 60.0)
	return true


# --------------------------------------------------------------------------- B3: the knot, fire

## B3: the titan's "wither" plate (the Rootwarden's knot) while it stands and the giant can reach it; else "".
func _wither_pick() -> String:
	var ps := titan.plates()
	if ps == null or titan.is_down():
		return ""
	for c: Dictionary in titan.lock_candidates(player.entity.combatant.height_m):
		var p := ps.plate(str(c.id))
		if str(p.get("effect", "")) == PlateRules.EFFECT_WITHER and not bool(c.broken):
			return str(c.id)
	return ""


## B3: while a wound of his is open (its clock running, not seared) and a standing fire prop stands within his
## record's fire.brazier_radius_m, the giant lets go of the lock, walks to the prop and smashes it: he burns and the
## open wounds are seared. Not while he strikes at the giant. True while it acts.
func _fire_rule(_tick: int) -> bool:
	var spec: Dictionary = titan.record.get("fire", {}) if typeof(titan.record.get("fire")) == TYPE_DICTIONARY else {}
	var ps := titan.plates()
	if spec.is_empty() or ps == null or titan.p34_has_status_tag("Burning"):
		_fire_prop = null
		return false
	var open := false
	for id: String in ps.wounds:
		if ps.wound_state(id) in [PlateRules.WOUND_OPEN, PlateRules.WOUND_REGROWING]:
			open = true
	if not open:
		_fire_prop = null
		return false
	if _fire_prop == null or not is_instance_valid(_fire_prop) or bool(_fire_prop.get("destroyed")):
		_fire_prop = _nearest_fire(float(spec.get("brazier_radius_m", 0.0)))
	if _fire_prop == null:
		return false
	var c := titan.controller
	if c.action != null and c.phase() in [ActionDef.Phase.WINDUP, ActionDef.Phase.ACTIVE]:
		return false   # (his blow first: the evasion and the defence have it)
	fire_ticks += 1
	var wid := str(_fire_prop.get("world_id"))
	_fire_given_up[wid] = int(_fire_given_up.get(wid, 0)) + 1
	if int(_fire_given_up[wid]) > 60 * 12:
		_fire_prop = null   # (twelve seconds and it still stands: something is in the way)
		return false
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_fire")
	var to := _fire_prop.global_position - player.global_position
	to.y = 0.0
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	if to.length() > reach * 0.5:
		steer_world(to.normalized(), to.length() > 12.0)
		return true
	stop_moving()
	player.camera_rig.yaw = TargetingRules.yaw_of(to)
	# (a heavy: its overhead blow comes down to the ground ahead, where a brazier stands; a light passes over it)
	var pc := player.controller
	if pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"heavy") == "":
		player.router.inject_edge(&"heavy")
	return true


## The nearest standing fire prop (a BreakableProp whose record is tagged fire) within `radius` of him.
func _nearest_fire(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group("breakables"):
		var b := n as Node3D
		if b == null or bool(b.get("destroyed")):
			continue
		var rec: Variant = b.get("record")
		if typeof(rec) != TYPE_DICTIONARY or not ((rec as Dictionary).get("prop_tags", []) as Array).has("fire"):
			continue
		var from_t := Vector2(b.global_position.x - titan.global_position.x, b.global_position.z - titan.global_position.z)
		if from_t.length() > radius - 0.5:
			continue
		var d := b.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


## B3: out of a hazard circle (a falling tree) that strikes soon; true while it moves.
func _dodge_hazard(tick: int) -> bool:
	var p := player.global_position
	var r := player.entity.combatant.height_m * 0.2 + 1.0
	for h: Array in _hazards.duplicate():
		if tick > int(h[2]) + 2:
			_hazards.erase(h)
			continue
		var away := p - (h[0] as Vector3)
		away.y = 0.0
		var reach := float(h[1]) + r + 1.0
		if away.length() < reach:
			evade_ticks += 1
			var dir := away.normalized() if away.length() > 0.3 else player.global_transform.basis.x
			steer_world(dir, true)
			return true
	return false


# --------------------------------------------------------------------------- C2: the guard, the rubble

## C2: true while the titan's guard is up and the giant stands inside its arc (the shield between them).
func _before_guard() -> bool:
	if titan == null or not titan.has_guard() or not titan.guard_raised():
		return false
	var ps := titan.plates()
	return PlateRules.guard_catches(ps.guard, titan.global_position, -titan.global_transform.basis.z,
		player.global_position, Vector3.ZERO)


## C2: before his raised shield: heavies into it while the stamina holds two (its meter fills: the guard breaks),
## else round to his back, outside the guard's arc. Not while he winds up or strikes (the evasion and the defence
## have those). True while it acts.
func _guard_rule(_tick: int) -> bool:
	combat.prefer_heavy = false
	if not _before_guard():
		return false
	var c := titan.controller
	if c.action != null and c.phase() in [ActionDef.Phase.WINDUP, ActionDef.Phase.ACTIVE] and c.action.is_attack() \
			and c.action.hit_shape != "none":
		return false
	guard_ticks += 1
	var heavy := combat._loadout_action(&"heavy")
	var pools := player.entity.combatant.pools
	# (pressing from GUARD_PRESS_HEAVIES heavies' stamina down to one: a start at one would sprint it away again)
	var cost := heavy.stamina_cost if heavy != null else 20.0
	if _pressing and pools.stamina < cost:
		_pressing = false
	elif not _pressing and pools.stamina >= cost * GUARD_PRESS_HEAVIES:
		_pressing = true
	if _pressing:
		last_rule = "press"
		return _press_guard(heavy)
	return _wait_guard()


## C2: heavies into the shield: to the heavy's striking distance from the point the lock frames (the shield takes
## whatever it touches), then a heavy each time the giant is free to swing. True while it acts (false: the fight's own).
func _press_guard(heavy: ActionDef) -> bool:
	if heavy == null or player.targeting.locked_entity() != titan.entity:
		combat.prefer_heavy = true
		return false   # (BotCombat's fight takes the lock first)
	var at := _lock_point()
	if not at.is_finite():
		at = titan.global_position + Vector3.UP * player.entity.combatant.height_m * 0.4
	var want := _strike_distance(heavy, at.y - player.global_position.y)
	var to := at - player.global_position
	to.y = 0.0
	var d := to.length()
	last_rule = "press %.1f [%.1f-%.1f] h%.1f" % [d, want.x, want.y, at.y - player.global_position.y]
	if d > want.y:
		steer_world(to.normalized(), d > DOWN_SPRINT_M)
		return true
	if d < want.x:
		steer_world(-to.normalized(), false)
		return true
	stop_moving()
	var c := player.controller
	if c.state != CombatController.State.LOCOMOTION and not BotCombat._chain_window(c):
		return true
	if c.preview_reason(&"heavy") == "":
		player.router.inject_edge(&"heavy")
	return true


## C2: short of a heavy's stamina before his shield: back off out of his bash's reach and edge round to his right at
## a walk while it comes back (no sprint: the sprint is what it waits for).
func _wait_guard() -> bool:
	var fwd := -titan.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var from_t := player.global_position - titan.global_position
	from_t.y = 0.0
	var bash := GameData.get_action("ability.bastion_bash")
	var keep := (float(bash.param("radius_m", 13.0)) if bash != null else 13.0) \
		+ player.entity.combatant.height_m * 0.2 + 2.5
	var away := from_t.normalized() if from_t.length() > 0.1 else -fwd
	var dir := right * 0.6
	if from_t.length() < keep:
		dir += away
	elif from_t.length() > keep + 6.0:
		dir -= away * 0.5
	flank_ticks += 1
	steer_world(dir.normalized(), false)
	return true


## C2: round him to the side his shield does not cover, then to his back (aside of his body, never through it).
func _round_guard() -> bool:
	var k := flank_scale()
	var fwd := -titan.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var from_t := player.global_position - titan.global_position
	from_t.y = 0.0
	var back := titan.global_position - fwd * (FLANK_M + 3.4) * k
	var goal := back
	if from_t.dot(fwd) > -2.0:
		# (still before him: out past his right side, wide of his body and his sweep's edge)
		goal = titan.global_position + right * (FLANK_M + 6.0) * k - fwd * 4.0 * k
	var to := goal - player.global_position
	to.y = 0.0
	if to.length() < 3.0:
		return false
	flank_ticks += 1
	steer_world(to.normalized(), to.length() > 16.0)
	return true


## C2: a crumbling tower of his old walls (a standing BreakableProp tagged rubble) within his record's rubble.radius_m
## of him: unless he is striking, the giant lets go of the lock, walks to it and brings it down (heavies) - it falls on
## him. Gives a tower up after twelve seconds. True while it acts.
func _tower_rule(_tick: int) -> bool:
	var spec: Dictionary = titan.record.get("rubble", {}) if typeof(titan.record.get("rubble")) == TYPE_DICTIONARY else {}
	if spec.is_empty() or titan.is_down() or titan.controller.state == CombatController.State.STAGGERED:
		_tower = null
		return false
	var c := titan.controller
	if c.action != null and c.phase() in [ActionDef.Phase.WINDUP, ActionDef.Phase.ACTIVE] and c.action.is_attack() \
			and c.action.hit_shape != "none":
		return false
	if _tower == null or not is_instance_valid(_tower) or bool(_tower.get("destroyed")):
		if _tower != null and is_instance_valid(_tower) and bool(_tower.get("destroyed")):
			towers_felled += 1
		_tower = _nearest_tagged("rubble", float(spec.get("radius_m", 0.0)) - 2.0)
	if _tower == null:
		return false
	var wid := str(_tower.get("world_id"))
	_tower_given_up[wid] = int(_tower_given_up.get(wid, 0)) + 1
	if int(_tower_given_up[wid]) > 60 * 12:
		_tower = null
		return false
	tower_ticks += 1
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_tower")
	var to := _tower.global_position - player.global_position
	to.y = 0.0
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	if to.length() > reach * 0.55 + 3.5:
		steer_world(to.normalized(), to.length() > 12.0)
		return true
	stop_moving()
	player.camera_rig.yaw = TargetingRules.yaw_of(to)
	var pc := player.controller
	if pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"heavy") == "":
		player.router.inject_edge(&"heavy")
	elif pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"light") == "":
		player.router.inject_edge(&"light")
	return true


## C2: the nearest standing breakable tagged `tag` within `radius` of him (flat), else null.
func _nearest_tagged(tag: String, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group("breakables"):
		var b := n as Node3D
		if b == null or bool(b.get("destroyed")):
			continue
		var rec: Variant = b.get("record")
		if typeof(rec) != TYPE_DICTIONARY or not ((rec as Dictionary).get("prop_tags", []) as Array).has(tag):
			continue
		var from_t := Vector2(b.global_position.x - titan.global_position.x, b.global_position.z - titan.global_position.z)
		if from_t.length() > radius:
			continue
		var d := b.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


# --------------------------------------------------------------------------- E1: the fetters

## E1: Orrik's fight. True while a fetter rule acts (see fetter_rules).
func _heir_rule(tick: int) -> bool:
	var heir := titan as HeirEnemy
	if heir == null or player.fetter == null:
		return false
	var f: PlayerFetter = player.fetter
	var c := heir.controller
	var hb := heir.heir_brain()
	var breaker := c.action != null and c.action.id == hb.breaker_id() and c.phase() == ActionDef.Phase.WINDUP
	var pc := player.controller
	if f.count() > 0:
		if breaker and not f.is_bound() and pc.state == CombatController.State.LOCOMOTION:
			_dodge_out(tick, heir)
			breaker_dodges += 1
			last_rule = "breaker_out"
			return true
		var h := combat._loadout_action(&"heavy")
		var cost := h.stamina_cost if h != null else 20.0
		if pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"heavy") == "" \
				and player.entity.combatant.pools.stamina >= cost:
			stop_moving()
			player.camera_rig.yaw = TargetingRules.yaw_of(_flat_to(heir.global_position))
			player.router.inject_edge(&"heavy")
			heaves += 1
			last_rule = "heave"
			return true
		if pc.state != CombatController.State.LOCOMOTION:
			last_rule = "heaving"
			return true
		# pull against the tautest chain: straight away from its anchor
		var best: Dictionary = {}
		for fd: Dictionary in f.fetters:
			if best.is_empty() or float(fd.strain) > float(best.strain) or str(fd.kind) == "hook":
				best = fd
		var away := _flat_to(player.global_position * 2.0 - (best.point as Vector3))
		steer_world(away, false)
		pull_ticks += 1
		last_rule = "pull"
		return true
	if breaker and pc.state == CombatController.State.LOCOMOTION and _flat_to(heir.global_position).length() < 30.0:
		_dodge_out(tick, heir)
		breaker_dodges += 1
		last_rule = "breaker_out"
		return true
	if _harpoon_rule(tick):
		return true
	return _winch_rule(tick, heir)


func _flat_to(p: Vector3) -> Vector3:
	var d := p - player.global_position
	d.y = 0.0
	return d


## Out of his overhead's line: sideways from where he faces.
func _dodge_out(_tick: int, heir: Node3D) -> void:
	var fwd := -heir.global_transform.basis.z
	fwd.y = 0.0
	var side := fwd.cross(Vector3.UP).normalized()
	var rel := player.global_position - heir.global_position
	if side.dot(rel) < 0.0:
		side = -side
	steer_world(side, false)
	player.router.inject_edge(&"dodge")


## A winch drawing at the giant, its aim locked and the harpoon about to fly: a step aside (a dodge when free).
func _harpoon_rule(_tick: int) -> bool:
	if player.fetter.is_bound() or player.controller.state != CombatController.State.LOCOMOTION:
		return false
	for n in player.get_tree().get_nodes_in_group("fetter_winches"):
		var w := n as FetterWinch
		if w == null or w.destroyed or w.controller == null or w.controller.action == null:
			continue
		var c := w.controller
		if c.phase() != ActionDef.Phase.WINDUP or not w.aim_locked():
			continue
		var left := c.action.windup_ticks - c.elapsed
		if left > 14 or left < 2:
			continue
		if int(_harpoon_seen.get(w.world_id, -1)) == c.instance_id:
			continue
		_harpoon_seen[w.world_id] = c.instance_id
		var line := _flat_to(w.global_position)
		var side := line.cross(Vector3.UP).normalized()
		if rng.randf() < 0.5:
			side = -side
		steer_world(side, false)
		player.router.inject_edge(&"dodge")
		harpoon_dodges += 1
		last_rule = "harpoon"
		return true
	return false


## A winch in the fight (crewed, shooting) near the giant while Orrik is not swinging at him: go and break it - a stage-8
## giant strides through it (its trample stage), a smaller one strikes it.
func _winch_rule(_tick: int, heir: HeirEnemy) -> bool:
	var c := heir.controller
	var near_heir := _flat_to(heir.global_position).length() < WINCH_SAFE_FROM_HEIR_M + float(heir.record.get("capsule_radius_m", 5.0))
	if c.action != null and c.phase() in [ActionDef.Phase.WINDUP, ActionDef.Phase.ACTIVE] and c.action.is_attack() and near_heir:
		_winch = null
		return false
	if heir.controller.state == CombatController.State.STAGGERED:
		_winch = null
		return false   # (his stagger is the time to strike him)
	if _winch == null or not is_instance_valid(_winch) or bool(_winch.get("destroyed")):
		_winch = null
		var best_d := WINCH_RUN_M
		for n in player.get_tree().get_nodes_in_group("fetter_winches"):
			var w := n as FetterWinch
			if w == null or w.destroyed or not w.in_action():
				continue
			if int(_winch_given_up.get(w.world_id, 0)) > 60 * 10:
				continue
			var d := _flat_to(w.global_position).length()
			if d < best_d:
				best_d = d
				_winch = w
		if _winch != null:
			winch_runs += 1
	if _winch == null:
		return false
	var wid := str(_winch.get("world_id"))
	_winch_given_up[wid] = int(_winch_given_up.get(wid, 0)) + 1
	winch_ticks += 1
	last_rule = "winch"
	if player.targeting.locked_entity() != null:
		player.targeting.release_lock("bot_winch")
	var to := _flat_to(_winch.global_position)
	var stage := player.current_growth_stage()
	var trample := stage >= int((_winch as FetterWinch).record.get("trample_stage", 99))
	if trample:
		steer_world(to.normalized(), true)   # (he strides through it)
		return true
	var reach := float(player.profile.get("melee_reach_m", 3.5))
	if to.length() > reach * 0.55 + 4.0:
		steer_world(to.normalized(), to.length() > 12.0)
		return true
	stop_moving()
	player.camera_rig.yaw = TargetingRules.yaw_of(to)
	var pc := player.controller
	if pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"heavy") == "":
		player.router.inject_edge(&"heavy")
	elif pc.state == CombatController.State.LOCOMOTION and pc.preview_reason(&"light") == "":
		player.router.inject_edge(&"light")
	return true
